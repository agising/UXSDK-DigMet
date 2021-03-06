//
//  AircraftHelper.swift
//  UXSDK-DigMet
//
//  Created by Andreas Gising on 2020-09-11.
//  Copyright © 2020 DJI. All rights reserved.
//

import Foundation
import DJIUXSDK
import SwiftyJSON

class CopterController: NSObject, DJIFlightControllerDelegate {
    var flightController: DJIFlightController?
    var gimbal = GimbalController()
    //var djiState: DJIFlightControllerState?       // Use to enable the dji state delegate func
    
    // Geofencing defaults set in initLoc init code.

    
    // Mission stuff
    var pendingMission = JSON()
    var mission = JSON()
    var missionNextWp = -1
    var missionNextWpId = "id-1"
    var missionType = ""
    var activeWP: MyLocation = MyLocation()
    var pattern: PatternHolder = PatternHolder()
    var missionIsActive = false
    var wpActionExecuting = false
    var hoverTime: Int = 0                          // Hovertime to wait prior to landing in dssSRTL. TODO, make parameter in mission.
    var followStream: Bool = false

   // var localYaw: Double = -1                       // localYaw used for storing the localYaw arg aka mission. -1 means course, 0-360 means heading relative to x axis.
    
    var refVelBodyX: Float = 0.0
    var refVelBodyY: Float = 0.0
    var refVelBodyZ: Float = 0.0
    var refYawRate: Float = 0.0
    
    var refYawLLA: Double = 0
    
    var xyVelLimit: Float = 900 // 300              // cm/s horizontal speed
    var zVelLimit: Float = 150                      // cm/s vertical speed
    var yawRateLimit:Float = 150 //50               // deg/s, defensive.
    
    var defaultXYVel: Float = 1.5                   // m/s default horizontal speed (fallback) TODO remove.
    var defaultHVel: Float = 1.5                    // m/s default horizontal speed (fallback)
    var toHeight: Double = -1                       // Take-Off height. Set to -1 when not in use.

    var homeHeading: Double?                        // Heading of last updated homewaypoint
    var homeLocation: CLLocation?                   // Location of last updated homewaypoint (autopilot home)
    var dssSmartRtlMission: JSON = JSON()           // JSON LLA wayopints to follow in smart rtl
    var dssSrtlActive: Bool = false

    // keep or use in smartRTL
    // var dssHomeHeading: Double?                   // Home heading of DSS

    var flightMode: String?                         // the flight mode as a string
    var loc: MyLocation = MyLocation()
    var initLoc: MyLocation = MyLocation()          // The init location as a MyLocation. Used for origin of geofence.

    // Tracking wp properties
    var trackingRecord: Int = 0                     // Consequtive loops on correct position
    let trackingRecordTarget: Int = 8               // Consequtive loops tracking target
    let trackingPosLimit: Double = 0.3              // Pos error requirement for tracking wp
    let trackingYawLimit: Double = 4                // Yaw error requireemnt for tracking wp
    let trackingVelLimit: Double = 0.1              // Vel error requirement for tracking wp NOT USED

    // Timer settings
    let sampleTime: Double = 120                    // Sample time in ms
    let controlPeriod: Double = 2000                // Number of millliseconds to send dutt command (stated in API)

    // Timers for position control
    var duttTimer: Timer?
    var duttLoopCnt: Int = 0
    var duttLoopTarget: Int = 0                     // Set in init
    var posCtrlTimer: Timer?                        // Position control Timer
    var posCtrlLoopCnt: Int = 0                     // Position control loop counter
    var posCtrlLoopTarget: Int = 250                // Position control loop counter max
    // Velocity Ctrl Timers (stream and patterns) are stored within Pattern object
    
    
    // Control paramters, acting on errors in meters, meters per second and degrees
    var hPosKP: Float = 0.75
    var hPosKD: Float = 0.6
    var etaLimit: Float = 2.0
    private let vPosKP: Float = 1
    private let vVelKD: Float = 0
    private let yawKP: Float = 1.3
    private let yawFFKP: Float = 0.05
    private let radKP: Double = 1                    // KP for radius tracking
    
    
    override init(){
    // Calc number of loops for dutt cycle
        duttLoopTarget = Int(controlPeriod / sampleTime)
    }

    // ***********************************
    // Flight controller delegate function. Might consume battery, don't implement without using it
    //func flightController(_ fc: DJIFlightController, didUpdate state: DJIFlightControllerState) {
    //    self.djiState = state
    //    print("Delegate function printing flight mode: ", state.flightModeString)
    // }
    
        //*************************************
    // Start listening for position updates
    func startListenToVel(){
        guard let key = DJIFlightControllerKey(param: DJIFlightControllerParamVelocity) else {
            NSLog("Couldn't create the key")
            return
        }

        guard let keyManager = DJISDKManager.keyManager() else {
            print("Couldn't get the keyManager, are you registered")
            return
        }

        keyManager.startListeningForChanges(on: key, withListener: self, andUpdate: { (oldValue: DJIKeyedValue?, newValue: DJIKeyedValue?) in
            if let checkedNewValue = newValue{
                let vel = checkedNewValue.value as! DJISDKVector3D
                // Velocities are in NED coordinate system !
                
                let heading = self.loc.heading
                
                // Velocities on the BODY coordinate system (dependent on heading)
                let beta = heading/180*Double.pi
                self.loc.vel.bodyX = Float(vel.x * cos(beta) + vel.y * sin(beta))
                self.loc.vel.bodyY = Float(-vel.x * sin(beta) + vel.y * cos(beta))
                self.loc.vel.bodyZ = Float(vel.z)
                                
                NotificationCenter.default.post(name: .didVelUpdate, object: nil)
            }
        })
    }

    
    //*************************************
    // Start listening for position updates
    func startListenToPos(){
        guard let locationKey = DJIFlightControllerKey(param: DJIFlightControllerParamAircraftLocation) else {
            NSLog("Couldn't create the key")
            return
        }

        guard let keyManager = DJISDKManager.keyManager() else {
            print("Couldn't get the keyManager, are you registered")
            return
        }
        
        keyManager.startListeningForChanges(on: locationKey, withListener: self, andUpdate: { (oldValue: DJIKeyedValue?, newValue: DJIKeyedValue?) in
            if let checkedNewValue = newValue{
                let pos = (checkedNewValue.value as! CLLocation)
                guard let heading = self.getHeading() else {
                   print("PosListener: Error updating heading")
                   return}
                
                // Update the XYZ coordinates relative to the XYZ frame. XYZ if XYZ is not set prior to takeoff, the homelocation updated at takeoff will be set as XYZ origin.
                
                if !self.initLoc.isInitLocation {
                    print("startListenToPos: No start location saved, local XYZ cannot be calculated")
                    return
                }
                
                self.loc.setPosition(pos: pos, heading: heading, gimbalYawRelativeToHeading: self.gimbal.yawRelativeToHeading, initLoc: self.initLoc) {
                        // The completionBock called upon succsessful update of pos.
                        NotificationCenter.default.post(name: .didPosUpdate, object: nil)
                    }
                
                // Run pos updated notification as a completion block. In the notification, look for subscriptions XYZ, NED and LLA
            }
        })
    }
    
    // ***************************
    // Monitor flight mode changes
    func startListenToFlightMode(){
        guard let flightModeKey = DJIFlightControllerKey(param: DJIFlightControllerParamFlightModeString) else {
            NSLog("Couldn't create the key")
           return
        }

        guard let keyManager = DJISDKManager.keyManager() else {
            print("Couldn't get the keyManager, are you registered")
            return
        }
        
        keyManager.startListeningForChanges(on: flightModeKey, withListener: self, andUpdate: { (oldValue: DJIKeyedValue?, newValue: DJIKeyedValue?) in
                if let checkedNewValue = newValue{
                    let flightMode = checkedNewValue.value as! String
                    let printStr = "New Flight mode: " + flightMode
                    NotificationCenter.default.post(name: .didPrintThis, object: self, userInfo: ["printThis": printStr])
                    // If pilot takes off manually, set init point at take-off location.
                    if flightMode == "TakeOff" && !self.initLoc.isInitLocation{
                        self.setInitLocation(headingRef: "drone")
                    }
                    // Trigger completed take-off to climb to correct take-off altitude
                    if self.flightMode == "TakeOff" && flightMode == "GPS"{
                        let height = self.toHeight
                        if height != -1{
                            Dispatch.main{
                                self.setAlt(targetAlt: self.initLoc.altitude + height)
                            }
                            // Reset take off height
                            self.toHeight = -1
                        }
                    }
                    self.flightMode = flightMode
                }
        })
    }
    
    //**************************************
    // Start listen to home position updates
    func startListenToHomePosUpdated(){
        guard let homeKey = DJIFlightControllerKey(param: DJIFlightControllerParamHomeLocation) else {
            NSLog("Couldn't create the key")
            return
        }

        guard let keyManager = DJISDKManager.keyManager() else {
            print("Couldn't get the keyManager, are you registered")
            return
        }
        
        keyManager.startListeningForChanges(on: homeKey, withListener: self, andUpdate: { (oldValue: DJIKeyedValue?, newValue: DJIKeyedValue?) in
            if let checkedNewValue = newValue{
                self.homeHeading = self.getHeading()
                self.homeLocation = (checkedNewValue.value as! CLLocation)
                print("HomePosListener: Home pos was updated.")
               
                // If initLoc is not yet set and we are flying, set initLoc to here.  // TODO Should use armed state instead for force setting init.
                if !self.initLoc.isInitLocation && self.getIsFlying() == true {
                    print("Error: we should not end up here anymore. DEBUG")
                    // Save current postion as the start position. Geofence (radius and height) will be evaluated relative to this pos. getHeading()! TODO guard and handle this.
                    //self.initLoc.setPosition(pos: checkedNewValue.value as! CLLocation, heading: self.getHeading()!, gimbalYawRelativeToHeading: 0, isInitLocation: true, initLoc: self.initLoc){} //Empty completionBlock}
                    //self.initLoc.printLocation(sentFrom: "startListenToHomePosUpated")
                }
            }
        })
    }
    
    //****************************
    // Start listen to armed state
    func startListenToMotorsOn(){
        guard let areMotorsOnKey = DJIFlightControllerKey(param: DJIFlightControllerParamAreMotorsOn) else {
            NSLog("Couldn't create the key")
            return
        }

        guard let keyManager = DJISDKManager.keyManager() else {
            print("Couldn't get the keyManager, are you registered")
            return
        }
        
        keyManager.startListeningForChanges(on: areMotorsOnKey, withListener: self, andUpdate: {(oldState: DJIKeyedValue?, newState: DJIKeyedValue?) in
            if let checkedValue = newState {
                let motorsOn = checkedValue.value as! Bool
                // If motors are armed without Init point has been initiated, initiate it
                if motorsOn && !self.initLoc.isInitLocation {
                    // TODO test robustness.
                    if !self.setInitLocation(headingRef: "drone"){
                        print("Debug start listen to motors on")
                        usleep(200000)
                        if !self.setInitLocation(headingRef: "drone"){
                            print("Debug start listen to motors on2")
                            usleep(200000)
                            _ = self.setInitLocation(headingRef: "drone")
                        }
                    }
                    
                }
            }
        })
    }
    
    
    //*************************************************************************************
    // Generic func to stop listening for updates. Stop all listeners at exit (func xClose)
    func stopListenToParam(DJIFlightControllerKeyString: String){
        guard let key = DJIFlightControllerKey(param: DJIFlightControllerKeyString) else {
            NSLog("Couldn't create the key")
            return
        }

        guard let keyManager = DJISDKManager.keyManager() else {
            print("Couldn't get the keyManager, are you registered")
            return
        }
        keyManager.stopListening(on: key, ofListener: self)
    }
    
    // ****************************************************************************************************
    // Set the initLocation and orientation as a reference of the system. Can only be set once for safety!
    // old: setOriginXYZ
    func setInitLocation(headingRef: String)->Bool{
        if self.initLoc.isInitLocation{
            print("setInitLocation Caution: Start location already set!")
            return false
        }
        guard let pos = getCurrentLocation() else {
            print("setInitLocation: Can't get current location")
            return false}
        guard let heading = getHeading() else {
            print("setInitLocation: Can't get current heading")
            return false}
        
        var startHeading = 0.0
        if headingRef == "camera"{
            // Include camera yaw in heading
            startHeading = heading + self.gimbal.yawRelativeToHeading
        }
        else if headingRef == "drone"{
            // Ignore camera yaw
            startHeading = heading
        }
        else{
            print("argument faulty")
            return false
        }
        
        //To test later..
        //stopListenToParam(DJIFlightControllerKeyString: "DJIFlightControllerParamAreMotorsOn")
        
        // GimbalYawRelativeToHeading is forced to 0. If gimbal yaw shoulb be in cluded it is alreade added to heading.
        self.initLoc.setPosition(pos: pos, heading: startHeading, gimbalYawRelativeToHeading: 0, isInitLocation: true, initLoc: self.initLoc){}
        self.initLoc.printLocation(sentFrom: "setInitLocation")
        // Not sure if sleep is needed, but loc.setPosition uses initLoc. Completion handler could be used.
        usleep(200000)
        
        Dispatch.main {
            // Update the loc, this is first chance for it to calc XYZ and NED
            self.loc.setPosition(pos: pos, heading: heading, gimbalYawRelativeToHeading: self.gimbal.yawRelativeToHeading, initLoc: self.initLoc){
                NotificationCenter.default.post(name: .didPosUpdate, object: nil)
            }
                    
            NotificationCenter.default.post(name: .didPrintThis, object: self, userInfo: ["printThis": "InitLocation set to here including gimbalYaw."])
        }
        
        return true
    }
    
    //**************************************************************************************************
    // Clears the DSS smart rtl list and adds current location as DSS home location, also saves heading.
    func resetDSSSRTLMission()->Bool{
        guard let heading = getHeading() else {
            return false
        }
        guard let pos = self.getCurrentLocation() else {
            return false}
        
        // Reset dssSmartRtlMission
        self.dssSmartRtlMission = JSON()
        let id = "id0"
        self.dssSmartRtlMission[id] = JSON()
        self.dssSmartRtlMission[id]["lat"] = JSON(pos.coordinate.latitude)
        self.dssSmartRtlMission[id]["lon"] = JSON(pos.coordinate.longitude)
        self.dssSmartRtlMission[id]["alt"] = JSON(pos.altitude)
        self.dssSmartRtlMission[id]["heading"] = JSON(heading)
        self.dssSmartRtlMission[id]["action"] = JSON("land")
        
        if pos.altitude - self.initLoc.altitude < 2 {
            print("reserDSSSRTLMission: Forcing land altitude to 2m min")
            self.dssSmartRtlMission[id]["alt"].doubleValue = self.initLoc.altitude + 2
        }
        
        print("resetDSSSRTLMission: DSS SRTL reset: ", self.dssSmartRtlMission)
        return true
    }
    
    //******************************************************
    // Appends current location to the DSS smart rtl mission
    func appendLocToDssSmartRtlMission()->Bool{
        // TODO, should copy loc instead, but it is not supported yet..
        guard let pos = self.getCurrentLocation() else {
            return false}
        
        var wpCnt = 0
        // Find what wp id to add next. If mission is empty result will be id0
        for (_,_):(String, JSON) in self.dssSmartRtlMission {
            // Check wp-numbering
            if self.dssSmartRtlMission["id" + String(wpCnt)].exists() {
                wpCnt += 1
            }
        }
     
        print("appendLocToDssSmartRtlMission: id to add: ", wpCnt)
        let id = "id" + String(wpCnt)
        self.dssSmartRtlMission[id] = JSON()
        self.dssSmartRtlMission[id]["lat"] = JSON(pos.coordinate.latitude)
        self.dssSmartRtlMission[id]["lon"] = JSON(pos.coordinate.longitude)
        self.dssSmartRtlMission[id]["alt"] = JSON(pos.altitude)
        self.dssSmartRtlMission[id]["heading"] = JSON("course")
        self.dssSmartRtlMission[id]["speed"] = JSON(self.activeWP.speed)
        return true
    }

    
    //*************************************
    // Get current location as location object
    func getCurrentLocation()->CLLocation?{
        guard let locationKey = DJIFlightControllerKey(param: DJIFlightControllerParamAircraftLocation) else {
            NSLog("Couldn't create the key")
            return nil
        }

        guard let keyManager = DJISDKManager.keyManager() else {
            print("Couldn't get the keyManager, are you registered")
            return nil
        }
                
        if let locationValue = keyManager.getValueFor(locationKey) {
            let location = locationValue.value as! CLLocation
            return location
        }
     return nil
    }
    
    // ********************************
    // Get current heading as a Double?
    func getHeading()->Double?{
        guard let headingKey = DJIFlightControllerKey(param: DJIFlightControllerParamCompassHeading) else {
            NSLog("Couldn't create the key")
            return nil
        }

        guard let keyManager = DJISDKManager.keyManager() else {
            print("Couldn't get the keyManager, are you registered")
            return nil
        }
                
        if let headingValue = keyManager.getValueFor(headingKey) {
            let heading = headingValue.value as! Double
            return heading
        }
        return nil
    }
    

    //****************************************
    // Get the isFlying parameter from the DJI
    func getIsFlying()->Bool?{
        guard let flyingKey = DJIFlightControllerKey(param: DJIFlightControllerParamIsFlying) else {
            NSLog("Couldn't create the key")
            return nil
        }

        guard let keyManager = DJISDKManager.keyManager() else {
            print("Couldn't get the keyManager, are you registered")
            return nil
        }
                
        if let flyingValue = keyManager.getValueFor(flyingKey) {
            let flying = flyingValue.value as! Bool
            return flying
        }
        return nil
    }

    //***************************************************************************
    // Get the areMotorsOn parameter from the DJI. Default to true, safest option
    func getAreMotorsOn()->Bool{
        guard let areMotorsOnKey = DJIFlightControllerKey(param: DJIFlightControllerParamAreMotorsOn) else {
            NSLog("Couldn't create the key")
            return true
        }

        guard let keyManager = DJISDKManager.keyManager() else {
            print("Couldn't get the keyManager, are you registered")
            return true
        }
                
        if let areMotorsOnValue = keyManager.getValueFor(areMotorsOnKey) {
            let areMotorsOn = areMotorsOnValue.value as! Bool
            return areMotorsOn
        }
        return true
    }
    
    //************************
    // Set up reference frames
    func initFlightController(){
        // Set properties of VirtualSticks
        self.flightController?.rollPitchCoordinateSystem = DJIVirtualStickFlightCoordinateSystem.body
        self.flightController?.yawControlMode = DJIVirtualStickYawControlMode.angularVelocity // Auto reset to angle if controller reconnects
        self.flightController?.rollPitchControlMode = DJIVirtualStickRollPitchControlMode.velocity
   //     self.djiState = DJIFlightControllerState()
        //self.flightController?.delegate?.flightController?(self.flightController!, didUpdate: self.djiState!)
        
        // Activate listeners
        self.startListenToHomePosUpdated()
        self.startListenToPos()
        self.startListenToFlightMode()
        self.startListenToMotorsOn()
        // No reason to track velocities as for now. Uncomment to enable
        self.startListenToVel()
        
        
        // If flight controller delegate is needed. Also activate delegate function flightcontroller row ~95
        // flightController!.delegate = self
    }
        
    //*************************************************************************************
    // Makes sure that value is within -lim < value < lim, if not value is limited to limit
    func limitToMax(value: Float, limit: Float)-> Float{
        if value > limit {
            return limit
        }
        else if value < -limit {
            return -limit
        }
        else {
            return value
        }
    }
    
    //***************************************
    // Limit a value to lower and upper limit
    func withinLimit(value: Double, lowerLimit: Double, upperLimit: Double)->Bool{
        if value > upperLimit {
            //print(value, upperLimit, lowerLimit)
            return false
        }
        else if value < lowerLimit {
            //print(value, lowerLimit, upperLimit)
            return false
        }
        else {
            //print(value, lowerLimit, upperLimit)
            return true
        }
    }


    //**************************************************************************************************
    // Stop ongoing stick command, invalidate all related timers. TODO: handle all modes, stop is stop..
    func stop(){
        invalidateTimers()
        // This following causes an error if called during landing or takeoff for example. The copter is not in stick mode then.
        //sendControlData(velX: 0, velY: 0, velZ: 0, yawRate: 0, speed: 0)
    }
    
    // *****************************************************
    // Invalidates the control timers, resets their counters
    func invalidateTimers(){
        duttTimer?.invalidate()
        posCtrlTimer?.invalidate()
        pattern.velCtrlTimer?.invalidate()
        duttLoopCnt = 0
        posCtrlLoopCnt = 0
        pattern.velCtrlLoopCnt = 0
    }
    
    //********************************
    // Disable the virtual sticks mode
    func stickDisable(){
        self.stop()
        self.flightController?.setVirtualStickModeEnabled(false, withCompletion: { (error: Error?) in
            if error == nil{
                print("stickDisable: Sticks disabled")
            }
            else{
                print("stickDisable: Virtual stick mode change did not go through" + error.debugDescription)
            }
        })
    }

    //**************************************************************
    // Enable the virtual sticks mode and reset reference velocities
    func stickEnable(){
        // Reset any speed set, think about YAW -> Todo!
        self.refVelBodyX = 0
        self.refVelBodyY = 0
        self.refVelBodyZ = 0
        self.refYawRate = 0

        // Set flight controller mode
        self.flightController?.setVirtualStickModeEnabled(true, withCompletion: { (error: Error?) in
            if error == nil{
                print("stickEnable: Sticks enabled")
            }
            else{
                print("stickEnable: Virtual stick mode change did not go through" + error.debugDescription)
            }
        })
    }
    
    //******************************************************************************
    // Sned a velocity command for a 2 second period, dutts the aircraft in x, y, z, yaw.
    func dutt(x: Float, y: Float, z: Float, yawRate: Float){
        // Stop any ongoing mission
        self.missionIsActive = false
        // limit to max
        self.refVelBodyX = limitToMax(value: x, limit: xyVelLimit/100)
        self.refVelBodyY = limitToMax(value: y, limit: xyVelLimit/100)
        self.refVelBodyZ = limitToMax(value: z, limit: zVelLimit/100)
        self.refYawRate = limitToMax(value: yawRate, limit: yawRateLimit)
        
        // Schedule the timer at 20Hz while the default specified for DJI is between 5 and 25Hz. DuttTimer will execute control commands for a period of time
//        posCtrlTimer?.invalidate() // Cancel any posControl
//        duttTimer?.invalidate()
//        duttLoopCnt = 0
        invalidateTimers()
        duttTimer = Timer.scheduledTimer(timeInterval: sampleTime/1000, target: self, selector: #selector(fireDuttTimer), userInfo: nil, repeats: true)
       }
    
    //******************************************************************************************************************
    // Send controller data. Called from Timer that send commands every x ms. Stop timer to stop commands.
    func sendControlData(velX: Float, velY: Float, velZ: Float, yawRate: Float, speed: Float) {

        // The coordinate mapping:
        // controlData.verticalThrottle = velZ // in m/s
        // controlData.roll = velX
        // controlData.pitch = velY
        // controlData.yaw = yawRate
      
        // Check desired horizontal speed towards limitations
        let horizontalVel = sqrt(velX*velX + velY*velY)
        // Finds the most limiting speed constriant. Missions are checked for negative speed.
        let limitedVelRef = min(horizontalVel, speed, xyVelLimit/100)
        // Calculate same reduction factor to x and y to maintain direction
        var factor: Float = 1
        if limitedVelRef < horizontalVel{
            factor = limitedVelRef/horizontalVel
        }
        
        // Make sure velocity limits are respected.
        let limitedVelRefX = factor * velX
        let limitedVelRefY = factor * velY
        let limitedVelRefZ = limitToMax(value: velZ, limit: zVelLimit/100)
        let limitedYawRateRef: Float = limitToMax(value: yawRate, limit: yawRateLimit)
        
        // Construct the flight control data object. Roll axis is pointing forwards but we use velocities..
        var controlData = DJIVirtualStickFlightControlData()
        controlData.verticalThrottle = -limitedVelRefZ
        controlData.roll = limitedVelRefX
        controlData.pitch = limitedVelRefY
        controlData.yaw = limitedYawRateRef
        
        // Check that the heading mode is correct, it seems it has changed without explanation a few times.
        if (self.flightController?.yawControlMode.self == DJIVirtualStickYawControlMode.angularVelocity){
            self.flightController?.send(controlData, withCompletion: { (error: Error?) in
                if error != nil {
                    NotificationCenter.default.post(name: .didPrintThis, object: self, userInfo: ["printThis": "sendControlData: Error:" + error.debugDescription])
                    // Disable the timer(s)
                    self.invalidateTimers()
                }
                else{
                    //_ = "flightContoller data sent ok"
                }
            })
        }
        else{
            NotificationCenter.default.post(name: .didPrintThis, object: self, userInfo: ["printThis": "Error: YawControllerMode is not correct"])
            print("DJIVirtualStickYawControlMode is not longer angularVelocity!")
            self.flightController?.yawControlMode = DJIVirtualStickYawControlMode.angularVelocity
        }
    }
    
    //****************************************************************************************
    // Set altitude function. Climbs/descends to the desired altitude at the current position.
    func setAlt(targetAlt: Double){
            print("setAlt: Target alt:", targetAlt, "current alt: ", self.loc.altitude)
            self.activeWP.altitude = targetAlt
            self.activeWP.heading = self.loc.heading
            self.activeWP.coordinate.latitude = self.loc.coordinate.latitude
            self.activeWP.coordinate.longitude = self.loc.coordinate.longitude
            self.activeWP.speed = 0
            goto()
    }

    
    func setHeading(targetHeading: Double){
        print("setHeading: Target heading:", targetHeading, "current heading: ", self.loc.heading)
        self.activeWP.altitude = self.loc.altitude
        self.activeWP.heading = targetHeading
        self.activeWP.coordinate.latitude = self.loc.coordinate.latitude
        self.activeWP.coordinate.longitude = self.loc.coordinate.longitude
        self.activeWP.speed = 0
        goto()
    }
    
    // ***************************************************
    // Take off function, does not have reference altitude
    func takeOff(){
        print("TakeOff function")
        self.stickEnable()
        self.flightController?.startTakeoff(completion: {(error: Error?) in
            if error != nil{
                print("takeOff: Error, " + String(error.debugDescription))
            }
            else{
                //print("TakeOff else clause")
            }
        })
    }
    
    // *****************************
    // Land at the current location
    func land(){
        self.flightController?.startLanding(completion: {(error: Error?) in
            if error != nil{
                print("Landing error: " + String(error.debugDescription))
            }
            else{
                // _ = "Landing command accepted"
            }
            
        })
    }
    
    // **************************************************************************************************************
    // Activates the autopilot rtl, if it fails the completion handler is called with false, otherwise true
    func rtl(){
        // Stop any ongoing action
        self.stickDisable()
            
        // Check if we are flying first, getIsFlying() can return nil if not successful.
        if self.getIsFlying() == true {
            // Activate the autopilot rtl function
            self.flightController?.startGoHome(completion: {(error: Error?) in
                // Completion code runs when the method is invoked (right away)
                if error != nil {
                    print("rtl: error: ", String(describing: error))
                }
                else {
                    // It takes ~1s to get here, although the reaction is immidiate.
                    _ = "Command accepted by autopilot"
                }
            })
        }
        
    }
    
    // ******************************************************************************************************************
    // dssSrtl activates the DSS smart rtl function that backtracks the flow mission. It includes landing after hovertime
    func dssSrtl(hoverTime: Int){
        // Store hovertime globally. Should implement hovertime as parameter in action: "landing" and just update the smartRTL mission.
        self.hoverTime = hoverTime
        // Reverse the dssSmartRtlMission and activate it
        // Find the last element
        let last_wp = dssSmartRtlMission.count - 1
                
        // Build up a tempMission with reversed correct order
        var tempMission: JSON = JSON()
        let wps = Countdown(count: last_wp) // could use counter in for loop, but found this way of creating a sequence
        var dss_cnt = 0
        for wp in wps {
            let temp_id = "id" + String(wp)
            let dss_id = "id" + String(dss_cnt)
            tempMission[temp_id] = dssSmartRtlMission[dss_id]
            dss_cnt += 1
        }
        self.pendingMission = tempMission
        
        print("The inverted (corrected) DSSrtl mission: ", pendingMission)
        
        _ = self.gogo(startWp: 0, useCurrentMission: false, isDssSrtl: true)
        NotificationCenter.default.post(name: .didPrintThis, object: self, userInfo: ["printThis": "DSS Smart RTL activated"])
    }

    
    //*************************************************************************************************
    // Checks an uploaded mission. If ok it is stored as pending mission. Activate it by sending to wp.
    func uploadMission(mission: JSON)->(fenceOK: Bool, fenceDescr: String, numberingOK: Bool, numberingDescr: String, speedOK: Bool, speedDescr: String, actionOK: Bool, actionDescr: String, headingOK: Bool, headingDescr: String){
        // Init return values
        var fenceOK = true
        var fenceDescr = ""
        var numberingOK = true
        var numberingDescr = ""
        var speedOK = true
        var speedDescr = ""
        var actionOK = true
        var actionDescr = ""
        var headingOK = true
        var headingDescr = ""
        
        var wpCnt = 0
        let tempWP = MyLocation()

        // Check wp-numbering, and for each wp in mission check its properties, note the wpCnt and wpID are not in the same order!
        for (wpID,subJson):(String, JSON) in mission {
            // Temporarily parse from mission to MyLocation. StartWP is used to calc NED and XYZ to LLA, geofence etc
            tempWP.setUpFromJsonWp(jsonWP: subJson, defaultSpeed: self.defaultHVel, initLoc: self.initLoc)
            // Check wp numbering
            if mission["id" + String(wpCnt)].exists()
            {
                // Check for geofence violation
                if !self.initLoc.geofenceOK(wp: tempWP){
                    fenceOK = false
                    fenceDescr = "Geofence violation, " + wpID
                }
                
                // Check action ok, if there is an action
                if tempWP.action != ""{
                    if tempWP.action == "take_photo"{
                        _ = "ok"
                    }
                    else {
                        actionOK = false
                        actionDescr = "WP action not supported, " + wpID
                    }
                }
                
                // Check speed setting not too low
                if tempWP.speed < 0.1 {
                    speedOK = false
                    speedDescr = "Speed below 0.1, " + wpID
                }
                
                // Check for heading error
                if tempWP.heading == -99{
                    headingOK = false
                    headingDescr = "Heading faulty, " + wpID
                }
                
                // Continue the for loop
                wpCnt += 1
                continue
            }
            else{
                // Oops, wp numbering was faulty
                numberingOK = false
                numberingDescr = "Wp numbering faulty, missing id" + String(wpCnt)
            }
        }
        // Accept mission as pending mission if everything is ok
        if fenceOK && numberingOK && speedOK && actionOK && headingOK{
            self.pendingMission = mission
        }
        // Return results
        return (fenceOK, fenceDescr, numberingOK, numberingDescr, speedOK, speedDescr, actionOK, actionDescr, headingOK, headingDescr)
    }

    
    //**********************************
    // Returns the wp action of wp idNum
    func getAction(idNum: Int)->String{
        let id = "id" + String(idNum)
        if self.mission[id]["action"].exists(){
            return self.mission[id]["action"].stringValue
        }
        else{
            return ""
        }
    }
    
    // ******************************************************************************************************************************
    // Tests if some parameters are not nil. These parameters are used in the mission control and will not be checked each time there
    func isReadyForMission()->(Bool){
        // TODO - why not using isInitLocation?
        if self.initLoc.coordinate.latitude == 0 {
            print("readyForMission Error: No start location")
            return false
        }
        else if self.getHeading() == nil {
           print("readyForMission Error: Error updating heading")
           return false
        }
        else{
            return true
        }
    }
    
    
//    // ***********************************************************
//    // Calculate the NED coordinates of target relative to origin
//    func getNEDFromLocation(start: CLLocation, target: MyLocation)->(Double, Double, Double){
//        // Coordinates delta
//        let dLat = target.coordinate.latitude - start.coordinate.latitude
//        let dLon = target.coordinate.longitude - start.coordinate.longitude
//        let dAlt = target.altitude - start.altitude
//
//        // Convert to meters NED
//        let posN = dLat * 1852 * 60
//        let posE = dLon * 1852 * 60 * cos(start.coordinate.latitude/180*Double.pi)
//        let posD = -dAlt
//
//        // Return NED
//        return (posN, posE, posD)
//    }
    
    
    //******************************************************************************************
    // Step up mission next wp if it exists, otherwise report -1 to indicate mission is complete
    func setMissionNextWp(num: Int){
        if mission["id" + String(num)].exists(){
            self.missionNextWp = num
            self.missionNextWpId = "id" + String(num)
        }
        else{
            self.missionNextWp = -1
            self.missionNextWpId = "id-1"
        }
        self.missionType = self.getMissionType()
    }
    
    
    // ****************************************************
    // Return the missionType string of the current mission
    func getMissionType()->String{
    if self.mission["id0"]["x"].exists() {return "XYZ"}
    if self.mission["id0"]["north"].exists() {return "NED"}
    if self.mission["id0"]["lat"].exists() {return "LLA"}
    return ""
    }

    // *************************************************************************************************
    // Prepare a MyLocation for mission execution, then call goto. New implementeation of gogo
    func gogo(startWp: Int, useCurrentMission: Bool, isDssSrtl: Bool = false)->Bool{
        // Set dssSrtlActive flag here since it is only missions that adds wp to dssSrtl. Check flag when reaching a wp.
        if isDssSrtl {
            dssSrtlActive = true
        }
        else{
            dssSrtlActive = false
        }
        
        // useCurrentMission?
        if useCurrentMission {
            self.setMissionNextWp(num: self.missionNextWp + 1)
            if self.missionNextWp == -1{
              NotificationCenter.default.post(name: .didNextWp, object: self, userInfo: ["next_wp": String(self.missionNextWp), "final_wp": String(mission.count-1), "cmd": "gogo" + self.missionType])
                return true
            }
            else{
                self.missionIsActive = true
            }
        }
        // Check if there is a pending mission
        else{
            if self.pendingMission["id" + String(startWp)].exists(){
                self.mission = self.pendingMission
                self.missionNextWp = startWp
                self.missionType = self.getMissionType()
                self.missionIsActive = true
                print("gogo: missionIsActive is set to true")
            }
            else{
                print("gogo - Error: No such wp id in pending mission: id" + String(startWp))
                return false
            }

        }
        // Check if ready for mission, then setup the wp and gogo. Convert any coordinate system to LLA.
        if isReadyForMission(){
            // Reset the activeWP TODO - does this cause a memory leak? If so create a reset function. Test in playground.
            let id = "id" + String(self.missionNextWp)
            self.activeWP.setUpFromJsonWp(jsonWP: self.mission[id], defaultSpeed: self.defaultHVel, initLoc: self.initLoc)

            self.activeWP.printLocation(sentFrom: "gogo")

            self.goto()
            //self.gotoXYZ(refPosX: x, refPosY: y, refPosZ: z, localYaw: yaw, speed: speed)

            // Notify about going to startWP
            NotificationCenter.default.post(name: .didNextWp, object: self, userInfo: ["next_wp": String(self.missionNextWp), "final_wp": String(mission.count-1), "cmd": "gogo" + self.missionType])
            return true
        }
        else{
            print("gogo - Error: Aircraft or mission not ready for mission flight")
            return false
        }
    }
    
    // *********************************************************************************
    // Activate posCtrl towards a self.activeWP, independent of ref (LLA, NED, XYZ).
    func goto(){
        // Check some Geo fence stuff. Ask initLoc if the wp is within the geofence.
        if !initLoc.geofenceOK(wp: self.activeWP){
            print("The WP violates the geofence!")
            return
        }
        
        // Fire posCtrl
        invalidateTimers()
        
//        duttTimer?.invalidate()
//        posCtrlTimer?.invalidate()
//        posCtrlLoopCnt = 0
        self.posCtrlTimer = Timer.scheduledTimer(timeInterval: sampleTime/1000, target: self, selector: #selector(self.firePosCtrlTimer), userInfo: nil, repeats: true)
    }

    
    //
    // Algorithm for detemining if at WP is tracked. When tracked mission can continue.
    // Algorithm requires both position and yaw to be tracked according to globally defined tracking limits.
    func trackingWP(posLimit: Double, yawLimit: Double, velLimit: Double)->Bool{
        // Distance in meters
        let (_, _, _, _, distance3D, _) = self.activeWP.distanceTo(wpLocation: self.loc)
        let yawError = abs(getDoubleWithinAngleRange(angle: self.loc.heading - self.refYawLLA))

        // TODO? Put tracking record on MyLocation?
        if distance3D < posLimit && yawError < yawLimit {
            trackingRecord += 1
        }
        else {
            trackingRecord = 0
        }
        if trackingRecord >= trackingRecordTarget{
            trackingRecord = 0
            return true
        }
        else{
            return false
        }
    }
    
    func startFollowStream(){
        self.followStream = true

        // Fire velCtrl towards stream and pattern
        invalidateTimers()
        self.pattern.velCtrlTimer = Timer.scheduledTimer(timeInterval: sampleTime/1000, target: self, selector: #selector(self.fireVelCtrlTimer), userInfo: nil, repeats: true)

    }
    


    //************************************************************************************************************
    // Timer function that loops every sampleTime ms until timer is invalidated. Each loop control data (joystick) is sent.
    @objc func fireDuttTimer() {
        duttLoopCnt += 1
        if duttLoopCnt >= duttLoopTarget {
            sendControlData(velX: 0, velY: 0, velZ: 0, yawRate: 0, speed: 0)
            invalidateTimers()
            //duttTimer?.invalidate()
        }
        else {
            // Speed argument acts as an upper limit not intended for this way to call the function. Set it high. Vel limits will apply.
            sendControlData(velX: self.refVelBodyX, velY: self.refVelBodyY, velZ: self.refVelBodyZ, yawRate: self.refYawRate, speed: 999)
        }
    }
    
    // *****************************************************************************************
    // Timer function that executes the position controller. It flies towards the self.activeWP.
    @objc func firePosCtrlTimer(_ timer: Timer) {
        posCtrlLoopCnt += 1
        
        // Abort due to Maxtime for flying to wp
        if posCtrlLoopCnt >= posCtrlLoopTarget{
            sendControlData(velX: 0, velY: 0, velZ: 0, yawRate: 0, speed: 0)

            NotificationCenter.default.post(name: .didPrintThis, object: self, userInfo: ["printThis": "myLocationController max time exeeded"])
            //posCtrlTimer?.invalidate()
            invalidateTimers()
        }
        
        // Test if activeWP is tracked or not
        else if trackingWP(posLimit: trackingPosLimit, yawLimit: trackingYawLimit, velLimit: trackingVelLimit){
                print("firePosCtrlTimer: Wp", self.missionNextWp, " is tracked")
                sendControlData(velX: 0, velY: 0, velZ: 0, yawRate: 0, speed: 0)
                
                // Add tracked wp to smartRTL if not on smartRTL mission.
                if self.missionNextWp != -1 && !dssSrtlActive{
                    if self.appendLocToDssSmartRtlMission(){
                        NotificationCenter.default.post(name: .didPrintThis, object: self, userInfo: ["printThis": "Location was added to DSS smart RTL mission"])
                    }
                    else {
                        NotificationCenter.default.post(name: .didPrintThis, object: self, userInfo: ["printThis": "Caution: Current location was NOT added to DSS smart rtl"])
                    }
                }
                
                // activeWP is tracked. Now, if we are on a mission:
                if self.missionIsActive{
                    // check for wp action
                    let action = self.activeWP.action
                    if action == "take_photo"{
                        // Notify action to be executed
                        NotificationCenter.default.post(name: .didWPAction, object: self, userInfo: ["wpAction": action])
                        // Stop mission, Notifier function will re-activate the mission and send gogo with next wp as reference
                        self.missionIsActive = false
                        //self.posCtrlTimer?.invalidate()
                        invalidateTimers()
                        return
                    }
                    if action == "land"{
                        let secondsSleep: UInt32 = UInt32(self.hoverTime*1000000)
                        usleep(secondsSleep)
                        NotificationCenter.default.post(name: .didWPAction, object: self, userInfo: ["wpAction": action])
                        self.missionIsActive = false
                        //self.posCtrlTimer?.invalidate()
                        invalidateTimers()
                        return
                    }
                    // Note that the current mission is stoppped (paused) if there is a wp action.
                    self.setMissionNextWp(num: self.missionNextWp + 1)
                    if self.missionNextWp != -1{
                        let id = "id" + String(self.missionNextWp)
                        self.activeWP.setUpFromJsonWp(jsonWP: self.mission[id], defaultSpeed: self.defaultHVel, initLoc: self.initLoc)
                        
                        self.activeWP.printLocation(sentFrom: "firePosCtrlTimer")
                        goto()
                        // self.posCtrlTimer?.invalidate() this code is run in goto() fcn.
                    }
                    else{
                        print("id is -1")
                        self.missionIsActive = false
                        // posCtrlTimer?.invalidate()
                        invalidateTimers()
                    }
                    NotificationCenter.default.post(name: .didNextWp, object: self, userInfo: ["next_wp": String(self.missionNextWp), "final_wp": String(mission.count-1), "cmd": "gogo_???"])
                }
                else {
                    print("No mission is active")
                    // posCtrlTimer?.invalidate()
                    invalidateTimers()
                }
            } // end if trackingWP

        // The controller: Calculate BODY control commands from lat long reference frame:
        // Get distance and bearing from here to wp
        let (northing, easting, dAlt, distance2D, _, bearing) = self.loc.distanceTo(wpLocation: self.activeWP)
        
        // Set reference Yaw. Heading equals bearing or manually set? Only check once per wp. If bearing becomes exactly -1 it will be evaluated agian, that is ok.
        if self.activeWP.heading == -1{
            self.activeWP.heading = bearing
        }
        self.refYawLLA = self.activeWP.heading
        
        // Calculate yaw-error, use shortest way (right or left?)
        let yawError = getFloatWithinAngleRange(angle: (Float(self.loc.heading - self.refYawLLA)))
        // P-controller for Yaw
        self.refYawRate = -yawError*yawKP
        // Feedforward TBD
        //let yawFF = self.refYawRate*yawFFKP*0
        
        //print("bearing: ", bearing, "reYawLLa: ", self.refYawLLA, "refYawRate: ", self.refYawRate)
        
        // Punish horizontal velocity on yaw error. Otherwise drone will not fly in straight line
        var turnFactor: Float = 1                    //let turnFactor2 = pow(180/(abs(yawError)+180),2) - did not work without feed forward
        if abs(yawError) > 10 {
            turnFactor = 0
        }
        else{
            turnFactor = 1
        }
        
        guard let checkedHeading = self.getHeading() else {return}
        //let alphaRad = (checkedHeading + Double(yawFF))/180*Double.pi
        
        // Rotate from NED to Body
        let alphaRad = checkedHeading/180*Double.pi
        // xDiffBody is in body coordinates
        let xDiffBody = Float(northing * cos(alphaRad) + easting * sin(alphaRad))
        let yDiffBody = Float(-northing * sin(alphaRad) + easting * cos(alphaRad))

        // If ETA is low, reduce speed (brake in time)
        var speed = self.activeWP.speed
        let vel = sqrt(pow(self.loc.vel.bodyX,2)+pow(self.loc.vel.bodyY ,2))
        
        //hdrpano:
        //decellerate at 2m/s/s
        // at distance_to_wp = Speed/2 -> brake
        if Float(distance2D) < etaLimit * vel {
            // Slow down to half speed (dont limit more than to 1.5 though) or use wp speed if it is lower.
            speed = min(max(vel/2,1.5), speed)
            //print("Braking!")
        }
        // Calculate a divider for derivative part used close to target, avoid zero..
        var xDivider = abs(xDiffBody) + 1
        if xDiffBody < 0 {
            xDivider = -xDivider
        }
        var yDivider = abs(yDiffBody) + 1
        if yDiffBody < 0 {
            yDivider = -yDivider
        }

        // Calculate the horizontal reference speed. (Proportional - Derivative)*turnFactor
        self.refVelBodyX = (xDiffBody*hPosKP - hPosKD*self.loc.vel.bodyX/xDivider)*turnFactor
        self.refVelBodyY = (yDiffBody*hPosKP - hPosKD*self.loc.vel.bodyY/yDivider)*turnFactor
        
        // Calc refVelZ
        self.refVelBodyZ = Float(-dAlt) * vPosKP
    
        // TODO, do not store reference values globally?
        self.sendControlData(velX: self.refVelBodyX, velY: self.refVelBodyY, velZ: self.refVelBodyZ, yawRate: self.refYawRate, speed: speed)
    

    }
    
    
    
    // **************************************************************************************************************************************************************************
    // Timer function that executes the velocity controller in pattern mode. It flies towards the stream plus the self.pattern. (Stream is updating the pattern property .stream)
    @objc func fireVelCtrlTimer(_ timer: Timer) {
        let pattern = self.pattern.pattern.name
        let desAltDiff = self.pattern.pattern.relAlt
        let headingMode = self.pattern.pattern.headingMode
        let desHeading = self.pattern.pattern.heading
        let desYawRate = self.pattern.pattern.yawRate
        let radius = self.pattern.pattern.radius
        var refYaw: Double = 0
        var _refYawRate: Double = 0
        var refXVel: Double = 0
        var refYVel: Double = 0
        var refZVel: Double = 0
        let headingRangeLimit: Double = 3
        var yawRateFF: Double = 0
        
        self.pattern.velCtrlLoopCnt += 1
    
        // TODO, integrate gimbal control in patterns
        
        // Abort follow stream?
        if self.followStream == false{
            invalidateTimers()
        }
        else if self.pattern.velCtrlLoopCnt >= self.pattern.velCtrlLoopTarget{
            sendControlData(velX: 0, velY: 0, velZ: 0, yawRate: 0, speed: 0)
            NotificationCenter.default.post(name: .didPrintThis, object: self, userInfo: ["printThis": "VelocityController max time exeeded"])
            invalidateTimers()
        }
        
        // Get distance and bearing from here to stream
        let (_, _, dAlt, distance2D, _, bearing) = self.loc.distanceTo(wpLocation: self.pattern.stream)
        
        switch pattern{
        case "circle":
            // Desired yaw rate and radius gives the speed.
            let radiusError = distance2D - radius
            let speed = 0.01745 * radius * desYawRate// 2*math.pi*radius*desYawRate/360 ~ 0.01745* r* desYawRate
            var CCW = false     // CounterClockWise rotation true or false?
            if desYawRate < 0{
                CCW = true
            }
            
            // For each headingMode, calculate the refYaw, refXVel and refYVel
            switch headingMode{
            case "poi":
                refYaw = bearing
                if CCW {
                    refYVel = -speed
                }
                // Radius tracking
                refXVel = radKP*radiusError
                
                // YawRate feed forward when closing in to radius
                if abs(radiusError) < 4{
                    yawRateFF = desYawRate
                }
                
            case "absolute":
                // Ref yaw defined in pattern
                refYaw = desHeading
                
                // Calc direction of travel as perpedicular to bearing towards poi.
                var direction: Double = 0
                if CCW {
                    direction = bearing + 90.0
                }
                else {
                    direction = bearing - 90.0
                }
                
                // Calc body velocitites based on speed direction and refYaw
                let alphaRad = (direction-refYaw)/180*Double.pi
                refXVel = speed*cos(alphaRad)
                refYVel = speed*sin(alphaRad)
                
                // Radius tracking, add components to x and y
                let betaRad = (bearing-refYaw)/180*Double.pi
                refXVel += radKP*radiusError*cos(betaRad)
                refYVel += radKP*radiusError*sin(betaRad)
                
            case "course":
                // Special case of absolute where heading is same as direction of travel.
                // Calc direction of travel as perpedicular to bearing towards poi.
                var direction: Double = 0
                if CCW {
                    direction = bearing + 90.0
                }
                else {
                    direction = bearing - 90.0
                }
                
                // Ref yaw is same as direction of travel
                refYaw = direction
                
                
                // Calc body velocitites based on speed direction and refYaw
                let alphaRad = (direction-refYaw)/180*Double.pi
                refXVel = speed*cos(alphaRad)
                refYVel = speed*sin(alphaRad)
                
                // Radius tracking, add components to x and y
                let betaRad = (bearing-refYaw)/180*Double.pi
                refXVel += radKP*radiusError*cos(betaRad)
                refYVel += radKP*radiusError*sin(betaRad)
                
            default:
                print("Circle heading mode not supported. Stop follower TODO")
                refYaw = 180
            }
        case "above":
            // For each headingMode, calculate the refYaw, refXVel and refYVel
            switch headingMode{
            case "poi":
                // If 'far' away, set heading to bearing
                if distance2D > headingRangeLimit{
                    refYaw = bearing
                }
                // Else, maintain heading
                else{
                    refYaw = self.loc.heading
                }
                
                // Set speed to half the distance to target
                let speed = distance2D/2
                
                // Direction of travel is bearing
                let direction = bearing
                
                // Calc body velocities based on speed, direction of travel and refYaw
                let alphaRad = (direction-refYaw)/180*Double.pi
                refXVel = speed*cos(alphaRad)
                refYVel = speed*sin(alphaRad)
            case "absolute":
                // Heading is defined in pattern
                refYaw = desHeading
                
                // Set speed to half the distance to target
                let speed = distance2D/2
                
                // Direction of travel is bearing
                let direction = bearing
                
                // Calc body velocities based on speed, direction of travel and refYaw
                let alphaRad = (direction-refYaw)/180*Double.pi
                refXVel = speed*cos(alphaRad)
                refYVel = speed*sin(alphaRad)

            case "course":
                // The heading will appear erratic if following a point standing still. Consider using "poi" code instead.
                refYaw = bearing
                // Set speed to half the distance to target
                let speed = distance2D/2
                refXVel = speed
                
            default:
                print("Above heading mode not supported. Stop follower TODO")
                
            }
        default:
            print("Pattern not supported Stop follower TODO")
        }
        
        // Calculate yaw-error, use shortest way (right or left?)
        let yawError = getDoubleWithinAngleRange(angle: (self.loc.heading - refYaw))
        // P-controller for Yaw
        _refYawRate = yawRateFF - yawError*Double(yawKP)
        

        print("Yawrate: ", _refYawRate, " Yawerror: ", yawError, " yawrateFF: ", yawRateFF)

        // Punish horizontal velocity on yaw error. Otherwise drone will not fly in straight line
        var turnFactor: Double = 1
        if abs(yawError) > 20 {
            turnFactor = 0
            print("turnfactor 0!")
        }
        else{
            turnFactor = 1
        }
        
        // Limit speeds while turning
        refXVel *= turnFactor
        refYVel *= turnFactor
        
        // Altitude trackign
        let altDiff = -dAlt - desAltDiff
        refZVel = altDiff*Double(vPosKP)

        // Set up a speed limit. Use global limit for now, it is given in cm/s..
        let speed = xyVelLimit/100
        
        self.sendControlData(velX: Float(refXVel), velY: Float(refYVel), velZ: Float(refZVel), yawRate: Float(_refYawRate), speed: speed)
    
       
    }
}

//          hdrpano explaining when to brake and how to react to any joystick input from pilot.
//          https://www.youtube.com/watch?fbclid=IwAR0w0VGptmEtxpYLqo1vrizU0K_M-veU_rMU8FN45yy-upvS_4noByA5qrs&v=fRPYyuK_eLA&feature=youtu.be
