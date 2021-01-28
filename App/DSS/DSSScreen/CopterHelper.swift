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
    
    // Geofencing
    var geoFenceRadius: Double = 50                 // Geofence radius relative start location (startLoc)
    var geoFenceHeight: [Double] = [2, 20]          // Geofence height relative start location
    
    var pendingMission = JSON()
    var mission = JSON()
    var missionNextWp = -1
    var missionNextWpId = "id-1"
    var missionType = ""
    var activeWP: MyLocation = MyLocation()
    var missionIsActive = false
    var wpActionExecuting = false
    var hoverTime: Int = 0                          // Hovertime to wait prior to landing in dssSRTL. TODO, make parameter in mission.

    var localYaw: Double = -1                   // localYaw used for storing the localYaw arg aka mission. -1 means course, 0-360 means heading relative to x axis.
    
    var refVelBodyX: Float = 0.0
    var refVelBodyY: Float = 0.0
    var refVelBodyZ: Float = 0.0
    var refYawRate: Float = 0.0
    
    var refYawLLA: Double = 0
    
    var xyVelLimit: Float = 900 // 300                 // cm/s horizontal speed
    var zVelLimit: Float = 150                  // cm/s vertical speed
    var yawRateLimit:Float = 150 //50                 // deg/s, defensive.
    
    var defaultXYVel: Float = 1.5               // m/s default horizontal speed (fallback) TODO remove.
    var defaultHVel: Float = 1.5               // m/s default horizontal speed (fallback)
    var toAlt: Double = -1
    var toReference = ""

    var homeHeading: Double?                    // Heading of last updated homewaypoint
    var homeLocation: CLLocation?               // Location of last updated homewaypoint (autopilot home)
    var dssSmartRtlMission: JSON = JSON()       // JSON LLA wayopints to follow in smart rtl

    // keep or use in smartRTL
  //  var dssHomeHeading: Double?               // Home heading of DSS

    var flightMode: String?                     // the flight mode as a string
    //var startHeadingXYZ: Double?                // The start heading that defines the XYZ coordinate system
    //var startLocationXYZ: CLLocation?           // The start location that defines the XYZ coordinate system
    var loc: MyLocation = MyLocation()
    var startLoc: MyLocation = MyLocation()      // The start location as a MyLocation. Used for origin of geofence.

    // Tracking wp properties
    var trackingRecord: Int = 0                 // Consequtive loops on correct position
    let trackingRecordTarget: Int = 8           // Consequtive loops tracking target
    let trackingPosLimit: Double = 0.3          // Pos error requirement for tracking wp
    let trackingYawLimit: Double = 4            // Yaw error requireemnt for tracking wp
    let trackingVelLimit: Double = 0.1          // Vel error requirement for tracking wp NOT USED

    // Timer settings
    let sampleTime: Double = 120                // Sample time in ms
    let controlPeriod: Double = 750 // 1500     // Number of millliseconds to send dutt command

    // Timers for position control
    var duttTimer: Timer?
    var duttLoopCnt: Int = 0
    var duttLoopTarget: Int = 0                 // Set in init
    var posCtrlTimer: Timer?
    var posCtrlLoopCnt: Int = 0
    var posCtrlLoopTarget: Int = 250
    
    // Control paramters, acting on errors in meters, meters per second and degrees
    var hPosKP: Float = 0.75
    var hPosKD: Float = 0.6
    var etaLimit: Float = 2.0
    private let vPosKP: Float = 1
    private let vVelKD: Float = 0
    private let yawKP: Float = 1
    private let yawFFKP: Float = 0.05
    
    
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
                
                if !self.startLoc.isStartLocation {
                    print("startListenToPos: No start location saved, local XYZ cannot be calculated")
                    return
                }
                
                self.loc.setPosition(pos: pos, heading: heading, gimbalYawRelativeToHeading: self.gimbal.yawRelativeToHeading, startWP: self.startLoc) {
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
                    // Trigger completed take-off to climb to correct take-off altitude
                    if self.flightMode == "TakeOff" && flightMode == "GPS"{
                        let toAlt = self.toAlt
                        let toReference = self.toReference
                        if toAlt != -1{
                            Dispatch.main{
                                self.setAlt(targetAlt: toAlt, reference: toReference)
                            }
                            self.toAlt = -1  // Reset to default value
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
               
                // If start location is not yet set and we are flying, set start location to here.
                if !self.startLoc.isStartLocation && self.getIsFlying() == true {
                    // Save current postion as the start position. Geofence (radius and height) will be evaluated relative to this pos. getHeading()! TODO guard and handle this.
                    self.startLoc.setPosition(pos: checkedNewValue.value as! CLLocation, heading: self.getHeading()!, gimbalYawRelativeToHeading: 0, isStartWP: true, startWP: self.startLoc){} //Empty completionBlock}
                    self.startLoc.setGeoFence(radius: self.geoFenceRadius, height: self.geoFenceHeight)
                    self.startLoc.printLocation(sentFrom: "startListenToHomePosUpated")
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
    // Set the startLocation and orientation as a reference of the system. Can only be set once for safety!
    // old: setOriginXYZ
    func setStartLocation()->Bool{
        if self.startLoc.isStartLocation{
            print("setStartLocation Caution: Start location already set!")
            return false
        }
        guard let pos = getCurrentLocation() else {
            print("setStartLocation: Can't get current location")
            return false}
        guard let heading = getHeading() else {
            print("setStartLocation: Can't get current heading")
            return false}
                
        // Gimbal yaw is included in heading for the startpoint since the cameras sets the reference if startpoint is not automatically set. GimbalYawRelativeToHeading is forced to 0
        let startHeading = heading + self.gimbal.yawRelativeToHeading
        self.startLoc.setPosition(pos: pos, heading: startHeading, gimbalYawRelativeToHeading: 0, isStartWP: true, startWP: self.startLoc){}
        self.startLoc.setGeoFence(radius: self.geoFenceRadius, height: self.geoFenceHeight)
        self.startLoc.printLocation(sentFrom: "setStartLocation")
        // Not sure if sleep is needed, but loc.setPosition uses startLoc. Completion handler could be used.
        usleep(200000)
        
        self.loc.setPosition(pos: pos, heading: heading, gimbalYawRelativeToHeading: self.gimbal.yawRelativeToHeading, startWP: self.startLoc){
            NotificationCenter.default.post(name: .didPosUpdate, object: nil)
        }
                
        NotificationCenter.default.post(name: .didPrintThis, object: self, userInfo: ["printThis": "StartLocation set to here including gimbalYaw."])
        
        return true
    }
    
    //**************************************************************************************************
    // Clears the DSS smart rtl list and adds current location as DSS home location, also saves heading.
    func saveCurrentPosAsDSSHome()->Bool{
        guard let heading = getHeading() else {
            return false
        }
        guard let pos = self.getCurrentLocation() else {
            return false}
        
        // Reset dssSmartERtlMission
        self.dssSmartRtlMission = JSON()
        let id = "id0"
        dssSmartRtlMission[id] = JSON()
        dssSmartRtlMission[id]["lat"] = JSON(pos.coordinate.latitude)
        dssSmartRtlMission[id]["lon"] = JSON(pos.coordinate.longitude)
        dssSmartRtlMission[id]["alt"] = JSON(pos.altitude)
        dssSmartRtlMission[id]["heading"] = JSON(heading)
        dssSmartRtlMission[id]["action"] = JSON("land")
        
        if pos.altitude - self.startLoc.altitude < 2 {
            print("saveCurrentPosAsDSSHome: Forcing land altitude to 2m")
            self.dssSmartRtlMission[id]["alt"].doubleValue = self.startLoc.altitude + 2
        }
        
        print("saveCurrentPosAsDSSHome: DSS home saved: ",self.dssSmartRtlMission)
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
        self.dssSmartRtlMission[id]["heading"] = JSON(-1)
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
        duttTimer?.invalidate()
        posCtrlTimer?.invalidate()
        sendControlData(velX: 0, velY: 0, velZ: 0, yawRate: 0, speed: 0)
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
    // Sned a velocity command for a short time, dutts the aircraft in x, y, z, yaw.
    func dutt(x: Float, y: Float, z: Float, yawRate: Float){
        // limit to max
        self.refVelBodyX = limitToMax(value: x, limit: xyVelLimit/100)
        self.refVelBodyY = limitToMax(value: y, limit: xyVelLimit/100)
        self.refVelBodyZ = limitToMax(value: z, limit: zVelLimit/100)
        self.refYawRate = limitToMax(value: yawRate, limit: yawRateLimit)
        
        // Schedule the timer at 20Hz while the default specified for DJI is between 5 and 25Hz. DuttTimer will execute control commands for a period of time
        posCtrlTimer?.invalidate() // Cancel any posControl
        duttTimer?.invalidate()
        duttLoopCnt = 0
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
                    NotificationCenter.default.post(name: .didPrintThis, object: self, userInfo: ["printThis": "sendControlData: Error:" + String(describing: error.debugDescription)])
                    // Disable the timer(s)
                    self.duttTimer?.invalidate()
                    self.posCtrlTimer?.invalidate()
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
    func setAlt(targetAlt: Double, reference: String){
        switch reference{
        case "HOME":
            print("setAlt: Target alt:", targetAlt, "current alt: ", self.loc.altitude)
            self.activeWP.altitude = targetAlt
            self.activeWP.heading = self.loc.heading
            self.activeWP.coordinate.latitude = self.loc.coordinate.latitude
            self.activeWP.coordinate.longitude = self.loc.coordinate.longitude
            self.activeWP.speed = 0
            goto(wp: self.activeWP)
        default:
            print("setAlt: Altitude reference not known")
        }
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
        
        _ = self.gogo(startWp: 0, useCurrentMission: false)
        NotificationCenter.default.post(name: .didPrintThis, object: self, userInfo: ["printThis": "DSS Smart RTL activated"])
    }

    
    //*************************************************************************************************
    // Checks an uploaded mission. If ok it is stored as pending mission. Activate it by sending to wp.
    func uploadMission(mission: JSON)->(success: Bool, arg: String){


        // Create a temo WP to verify any geofence violation against
        var tempStartLocation = MyLocation()
        if self.startLoc.isStartLocation {
            // There is a startLocation set, use it
            tempStartLocation = self.startLoc
        }
        else if let pos = self.getCurrentLocation(){
            // If current position is available, create a temporary startLocation at the current position
            tempStartLocation.setPosition(pos: pos, heading: 0, gimbalYawRelativeToHeading: 0, isStartWP: true, startWP: tempStartLocation){}
            tempStartLocation.setGeoFence(radius: self.geoFenceRadius, height: self.geoFenceHeight)
        }
        else {
            // Position cannot be obtained, geofence cannot be checked. Return false
            return(false, "No startPosition nor Position available. GEO fence fail.")
        }

        // Loop through the wp in the mission
        // For the number of wp-keys, check that there is a matching wp id and that the geoFence is not violated
        var wpCnt = 0
        let tempWP = MyLocation()
        
        for (wpID,subJson):(String, JSON) in mission {
            // Temporarily translate from Json to MyLocation
            tempWP.setUpFromJsonWp(jsonWP: subJson, defaultSpeed: self.defaultHVel, startWP: tempStartLocation)
            
            // Check wp-numbering, and for each wp check its properties, note the wpCnt and wpID are not in the same order!
            if mission["id" + String(wpCnt)].exists()
            {
                // Check for geofence violation
                if !tempStartLocation.geofenceOK(wp: tempWP){
                    return(false, "Geofence violation " + wpID)
                }
                
                // If there is a wp.action, check that it is one of the approved.
                if tempWP.action != ""{
                    if tempWP.action == "take_photo"{
                        _ = "ok"
                    }
                    else {
                        return(false, "WP action not supported " + wpID)
                    }
                }
                
                // Check that any speed setting is positive
                if subJson["speed"].exists() {
                    if subJson["speed"].doubleValue < 0.1 {
                        return(false, "Too low speed " + wpID)
                    }
                }
                
                // Check if given heading is in range [-1-359]
                var tempHeading:Double = 0
                if subJson["local_yaw"].exists() {
                    tempHeading = subJson["local_yaw"].doubleValue
                }
                else if subJson["heading"].exists() {
                    tempHeading = subJson["heading"].doubleValue
                }
                if tempHeading < -1 || tempHeading > 360 {
                    return(false, "Heading violation " + wpID)
                }
                
                // Continue the for loop
                wpCnt += 1
                continue
            }
            else{
                return (false, "Wp numbering faulty, missing id" + String(wpCnt))
            }
        }
        self.pendingMission = mission
        return (true, "")
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
        if self.startLoc.coordinate.latitude == 0 {
            print("readyForMission Error: No start location")
            return false
        }
//        else if self.startHeadingXYZ == nil {
//            print("readyForMission Error: No start headingXYZ")
//            return false
//        }
        else if self.getHeading() == nil {
           print("readyForMission Error: Error updating heading")
           return false
        }
        else{
            return true
        }
    }
    
    
    // ***********************************************************
    // Calculate the NED coordinates of target relative to origin
    func getNEDFromLocation(start: CLLocation, target: MyLocation)->(Double, Double, Double){
        // Coordinates delta
        let dLat = target.coordinate.latitude - start.coordinate.latitude
        let dLon = target.coordinate.longitude - start.coordinate.longitude
        let dAlt = target.altitude - start.altitude
            
        // Convert to meters NED
        let posN = dLat * 1852 * 60
        let posE = dLon * 1852 * 60 * cos(start.coordinate.latitude/180*Double.pi)
        let posD = -dAlt
        
        // Return NED
        return (posN, posE, posD)
    }
    
    
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
    func gogo(startWp: Int, useCurrentMission: Bool)->Bool{
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
            self.activeWP.setUpFromJsonWp(jsonWP: self.mission[id], defaultSpeed: self.defaultHVel, startWP: self.startLoc)

            self.activeWP.printLocation(sentFrom: "gogo")

            self.goto(wp: self.activeWP)
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
    // Activate posCtrl towards a MyLocation object, independent of ref (LLA, NED, XYZ).
    private func goto(wp: MyLocation){
        // Check some Geo fence stuff. Ask start location if the wp is within the geofence.
        if !startLoc.geofenceOK(wp: wp){
            print("The WP violates the geofence!")
            return
        }
        
        // Fire posCtrl
        duttTimer?.invalidate()
        posCtrlTimer?.invalidate()
        posCtrlLoopCnt = 0
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
    


    //************************************************************************************************************
    // Timer function that loops every x ms until timer is invalidated. Each loop control data (joystick) is sent.
    @objc func fireDuttTimer() {
        duttLoopCnt += 1
        if duttLoopCnt >= duttLoopTarget {
            sendControlData(velX: 0, velY: 0, velZ: 0, yawRate: 0, speed: 0)
            duttTimer?.invalidate()
        }
        else {
            sendControlData(velX: self.refVelBodyX, velY: self.refVelBodyY, velZ: self.refVelBodyZ, yawRate: self.refYawRate, speed: self.defaultXYVel)
        }
    }
    
    
    @objc func firePosCtrlTimer(_ timer: Timer) {
        posCtrlLoopCnt += 1
        // Test if WP is tracked or not
        if trackingWP(posLimit: trackingPosLimit, yawLimit: trackingYawLimit, velLimit: trackingVelLimit){
            print("firePosCtrlTimer: Wp", self.missionNextWp, " is tracked")
            sendControlData(velX: 0, velY: 0, velZ: 0, yawRate: 0, speed: 0)
            
            if self.missionNextWp != -1{
                if  self.missionNextWp != -1{
                    if self.appendLocToDssSmartRtlMission(){
                        NotificationCenter.default.post(name: .didPrintThis, object: self, userInfo: ["printThis": "Location was added to DSS smart RTL mission"])
                    }
                    else {
                        NotificationCenter.default.post(name: .didPrintThis, object: self, userInfo: ["printThis": "Caution: Current location was NOT added to DSS smart rtl"])
                    }
                }
            }
            
            // WP is tracked. If we are on a mission
            if self.missionIsActive{
                // check for wp action
                let action = self.activeWP.action
                if action == "take_photo"{
                    // Notify action to be executed
                    NotificationCenter.default.post(name: .didWPAction, object: self, userInfo: ["wpAction": action])
                    // Stop mission, Notifier function will re-activate the mission and send gogo with next wp as reference
                    self.missionIsActive = false
                    self.posCtrlTimer?.invalidate()
                    return
                }
                if action == "land"{
                    let secondsSleep: UInt32 = UInt32(self.hoverTime*1000000)
                    usleep(secondsSleep)
                    NotificationCenter.default.post(name: .didWPAction, object: self, userInfo: ["wpAction": action])
                    self.missionIsActive = false
                    self.posCtrlTimer?.invalidate()
                    return
                }
                // Note that the current mission is stoppped (paused) if there is a wp action.
                self.setMissionNextWp(num: self.missionNextWp + 1)
                if self.missionNextWp != -1{
                    let id = "id" + String(self.missionNextWp)
                    self.activeWP.setUpFromJsonWp(jsonWP: self.mission[id], defaultSpeed: self.defaultHVel, startWP: self.startLoc)
                    
                    self.activeWP.printLocation(sentFrom: "gogo")
                    
                    goto(wp: self.activeWP)
                }
                else{
                    print("id is -1")
                    self.missionIsActive = false
                    posCtrlTimer?.invalidate() // dont fire timer again
                }
                NotificationCenter.default.post(name: .didNextWp, object: self, userInfo: ["next_wp": String(self.missionNextWp), "final_wp": String(mission.count-1), "cmd": "gogo_???"])
            }
            else {
                print("No mission is active")
                posCtrlTimer?.invalidate()
            }
        }
        // WP is not tracked
        // The controller
        else {
            // Calculate BODY control commands from lat long reference frame
            
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
        // Maxtime for flying to wp
        if posCtrlLoopCnt >= posCtrlLoopTarget{
            sendControlData(velX: 0, velY: 0, velZ: 0, yawRate: 0, speed: 0)

            NotificationCenter.default.post(name: .didPrintThis, object: self, userInfo: ["printThis": "myLocationController max time exeeded"])
            posCtrlTimer?.invalidate()
        }
    }
}

//          hdrpano explaining when to brake and how to react to any joystick input from pilot.
//          https://www.youtube.com/watch?fbclid=IwAR0w0VGptmEtxpYLqo1vrizU0K_M-veU_rMU8FN45yy-upvS_4noByA5qrs&v=fRPYyuK_eLA&feature=youtu.be


// XYZ stuff, delete when more tested

//    // *****************************************************************************************
//    // Converts heading from a mission to local yaw in range 0-360 or -1. -1 means follow course
//    func getLocalYawFromHeading(heading: Double)->Double{
//        var local_yaw: Double = -1
//        if heading == -1 {
//            // Use course for heading
//            local_yaw = -1
//        }
//        else {
//            // Convert to local yaw
////            local_yaw = heading - self.startHeadingXYZ!
//            local_yaw = heading - (self.startLoc.heading + self.startLoc.gimbalYaw)
//            // local_yaw must be in range 0-360, or -1
//            if local_yaw < 0 {
//                local_yaw += 360
//            }
//            if local_yaw > 360 {
//                local_yaw -= 360
//            }
//        }
//        return local_yaw
//    }
    
    
    
    
    
    
    //************************************************************************************************************************
    // Extract the wp x, y, z, yaw from wp with id idNum. isReadyForMission() must return true before this method can be used.
//    func getWpXYZYaw(idNum: Int)->(Double, Double, Double, Double, Float){
//        let id: String = "id" + String(idNum)
//        var speed: Float = self.defaultXYVel
//        var x: Double = 0
//        var y: Double = 0
//        var z: Double = 0
//        var local_yaw: Double = -1
//
//        // If mission is XYZ
//        if self.mission[id]["x"].exists() {
//            x = self.mission[id]["x"].doubleValue
//            y = self.mission[id]["y"].doubleValue
//            z = self.mission[id]["z"].doubleValue
//            local_yaw = self.mission[id]["local_yaw"].doubleValue
//            // Check optional speed.
//            if self.mission[id]["speed"].exists() {
//                speed = self.mission[id]["speed"].floatValue
//            }
//        }
//
//        // If mission is NED - TODO Test
//        if self.mission[id]["north"].exists(){
//            let posN = self.mission[id]["north"].doubleValue
//            let posE = self.mission[id]["east"].doubleValue
//            let posD = self.mission[id]["down"].doubleValue
//            (x, y, z) = self.getXYZYawFromNED(posN: posN, posE: posE, posD: posD)
//            local_yaw = getLocalYawFromHeading(heading: self.mission[id]["heading"].doubleValue)
//            if self.mission[id]["speed"].exists() {
//                speed = self.mission[id]["speed"].floatValue
//            }
//        }
//
//        // If mission is LLA - TODO Test
//        if self.mission[id]["lat"].exists(){
//            let wp = MyLocation()
//            wp.coordinate.latitude = self.mission[id]["lat"].doubleValue
//            wp.coordinate.longitude = self.mission[id]["lon"].doubleValue
//            wp.altitude = self.mission[id]["alt"].doubleValue
//
//            let (posN, posE, posD) = self.getNEDFromLocation(start: self.startLocationXYZ!, target: wp)
//            (x, y, z) = self.getXYZYawFromNED(posN: posN, posE: posE, posD: posD)
//            local_yaw = getLocalYawFromHeading(heading: self.mission[id]["heading"].doubleValue)
//            if self.mission[id]["speed"].exists() {
//                speed = self.mission[id]["speed"].floatValue
//            }
//        }
//        return (x, y, z, local_yaw, speed)
//    }
//


// ************************************************************************************************************************************************
// Position controller from XYZ coordinates.
// Takes speed argument in userInfo. If omitted default speed is used.
// Evaluates if a wp is tracked, compares tracking limits and during a number of loops
// Looks for wp action. If action it stops mission and notifies action, after action is performed mission is restarted by action function.
// If no action the wp number is increased, new XYZ reference positions are extracted from any mission (XYZ, LLA, NED) and gotoXYZ is called. gotoXYZ invalidates the timer and starts a new timer.
// Position controller that files towards self.refPosX/Y/Z/ refYawXYZ. Reference positions are given in XYZ coordinate system, drone is controlled in BODY XYZ. Yaw is handeled too, if yaw arg i -1 heading is set to course towards next wp.
// Safety function for maxtime

//    @objc func xfirePosCtrlTimer(_ timer: Timer) {
//        // Test if speed argument is passed. If not use default speed.
//        var speed = self.defaultXYVel
//        if timer.isValid{
//            if let temp = timer.userInfo as? Float {
//                speed = temp
//            }
//        }
//
//        posCtrlLoopCnt += 1
//        // If we arrived. Compares rePosX with posX etc
//        if trackingWP(posLimit: trackingPosLimit, yawLimit: trackingYawLimit, velLimit: trackingVelLimit){
//            print("firePosCtrolTimer: Wp", self.missionNextWp, " is tracked")
//            sendControlData(velX: 0, velY: 0, velZ: 0, yawRate: 0, speed: 0)
//            // Add location to DSS RTL List. TODO what if we are on the dss srtl?
//            // Do not add climb to alt after take-off. It is executed as a mission.
//            if  self.missionNextWp != -1{
//                if self.appendLocToDssSmartRtlMission(){
//                    NotificationCenter.default.post(name: .didPrintThis, object: self, userInfo: ["printThis": "Location was added to DSS smart RTL mission"])
//                }
//                else {
//                    NotificationCenter.default.post(name: .didPrintThis, object: self, userInfo: ["printThis": "Caution: Current location was NOT added to DSS smart rtl"])
//                }
//            }
//            // WP tracked, If we are on a mission
//            if self.missionIsActive{
//                // Check for wp action
//                let action = getAction(idNum: self.missionNextWp)
//                if action == "take_photo"{
//                    // Notify action to be executed
//                    NotificationCenter.default.post(name: .didWPAction, object: self, userInfo: ["wpAction": action])
//                    // Stop mission, Notifier function will re-activate the mission and send gogo with next wp as reference
//                    self.missionIsActive = false
//                    self.posCtrlTimer?.invalidate()
//                    return
//                }
//                if action == "land"{
//                    let secondsSleep: UInt32 = 5*1000000
//                    usleep(secondsSleep)
//                    NotificationCenter.default.post(name: .didWPAction, object: self, userInfo: ["wpAction": action])
//                    self.missionIsActive = false
//                    self.posCtrlTimer?.invalidate()
//                    return
//                }
//                // Note that the current mission is stoppped (paused) if there is a wp action.
//
//                self.setMissionNextWp(num: self.missionNextWp + 1)
//                if self.missionNextWp != -1{
//                    let (x, y, z, yaw, speed_) = self.getWpXYZYaw(idNum: self.missionNextWp)
//                    self.xgotoXYZ(refPosX: x, refPosY: y, refPosZ: z, localYaw: yaw, speed: speed_)
//                }
//                else{
//                    print("id is -1")
//                    self.missionIsActive = false
//                    self.posCtrlTimer?.invalidate() // dont fire timer again
//                }
//                NotificationCenter.default.post(name: .didNextWp, object: self, userInfo: ["next_wp": String(self.missionNextWp), "final_wp": String(mission.count-1), "cmd": "gogo_XYZ"])
//            }
//            else{
//                print("No mission is active")
//                posCtrlTimer?.invalidate()
//            }
//        }
//        // WP is not tracked
//        // The controller
//        else{
//            // Implement P-controller, position error to ref vel: Get error in XYZ, handle yaw, rotate to BODY XYZ. Then send control data.
//            let xDiff: Float = Float(self.refPosX - self.posX)
//            let yDiff: Float = Float(self.refPosY - self.posY)
//            let zDiff: Float = Float(self.refPosZ - self.posZ)
//
//            //Do not concider gimbalYaw in yawControl
//            // Check if following course or heading:
//            if self.localYaw == -1 {
//                // heading equals course
//                self.refYawXYZ = getCourse(dX: Double(xDiff), dY: Double(yDiff))
//                //( To only check course once)
//                self.localYaw = self.refYawXYZ
//            }
//            else {
//                self.refYawXYZ = self.localYaw
//            }
//
//
//            // Calculate yaw error, use shortest way (right or left?)
//            let yawError = getFloatWithinAngleRange(angle: Float(self.yawXYZ - self.refYawXYZ))
//            self.refYawRate = -yawError*yawKP
//
//            // Feedfoward to fly in straight line
//            let yawFF = self.refYawRate*yawFFKP
//
//            guard let checkedHeading = self.getHeading() else {return}
//            guard let checkedStartHeading = self.startHeadingXYZ else {return}
//            let alphaRad = (checkedHeading - checkedStartHeading + Double(yawFF))/180*Double.pi
//
//            // Rotate coordinates, calc refvelx, refvely
////            let oldRefVelX = self.refVelX
////            let oldRefVelY = self.refVelY
//
//            // xDiff is in XYZ coordinates.
//            let xDiffBody = xDiff * Float(cos(alphaRad)) + yDiff * Float(sin(alphaRad))
//            let yDiffBody = -xDiff * Float(sin(alphaRad)) + yDiff * Float(cos(alphaRad))
////            self.refVelX =  (xDiff * Float(cos(alphaRad)) + yDiff * Float(sin(alphaRad)))*hPosKP
////            self.refVelY = (-xDiff * Float(sin(alphaRad)) + yDiff * Float(cos(alphaRad)))*hPosKP
//
//            self.refVelX = xDiffBody*hPosKP - hPosKD*self.velX/(abs(xDiffBody)+1)
//            self.refVelY = yDiffBody*hPosKP - hPosKD*self.velY/(abs(yDiffBody)+1)
//
//            print("refVelX: ", self.refVelX, "velX: ", self.velX, " brake: ", hPosKD*self.velX/abs(xDiffBody)+1)
////            print("oldRefVelX: ", oldRefVelX, " newRefVelX: ", self.refVelX, "velx: ", self.velX)
////            print("oldRefVelY: ", oldRefVelY, " newRefVelY: ", self.refVelY, "vely: ", self.velY)
//
//            // Calc refvelz
//            self.refVelZ = (zDiff) * vPosKP
//            // If velocity get limited the copter will not fly in straight line! Handled in sendControlData
//
//            //print("local_yaw: ", self.localYaw, " xDiff: ", xDiff, " yDiff: ", yDiff, "refYawXYZ: ", self.refYawXYZ, " yawFF: ", yawFF)
//
//
//            // Send control data, limits in velocity are handeled in sendControlData
//            sendControlData(velX: self.refVelX, velY: self.refVelY, velZ: self.refVelZ, yawRate: self.refYawRate, speed: speed)
//        }
//
//        // For safety during testing.. Maxtime for flying to wp
//        if posCtrlLoopCnt >= posCtrlLoopTarget{
//            sendControlData(velX: 0, velY: 0, velZ: 0, yawRate: 0, speed: 0)
//
//            NotificationCenter.default.post(name: .didPrintThis, object: self, userInfo: ["printThis": "Position controller max time exeeded"])
//
//            posCtrlTimer?.invalidate()
//        }
//    }


//**********************************************************************************************
// Starts the pending mission on startWp. returns false if startWp is not in the pending mission
// useCurrentMission is needed for continuing current mission after wp action. If set to false,
// the pending mission will be loaded.
//    func xgogo(startWp: Int, useCurrentMission: Bool)->Bool{
//        // useCurrentMission?
//        if useCurrentMission{
//            self.setMissionNextWp(num: self.missionNextWp + 1)
//            if self.missionNextWp == -1{
//                NotificationCenter.default.post(name: .didNextWp, object: self, userInfo: ["next_wp": String(self.missionNextWp), "final_wp": String(mission.count-1), "cmd": "gogo_XYZ"])
//                return true
//            }
//            else{
//                self.missionIsActive = true
//            }
//        }
//        // Check if there is a pending mission
//        else{
//            if self.pendingMission["id" + String(startWp)].exists(){
//                self.mission = self.pendingMission
//                self.missionNextWp = startWp
//                self.missionIsActive = true
//                print("gogo: missionIsActive is set to true")
//            }
//            else{
//                print("gogo - Error: No such wp id in pending mission: id" + String(startWp))
//                return false
//            }
//        }
//        // Check if ready for mission
//        if isReadyForMission(){
//
//
//            let (x, y, z, yaw, speed) = getWpXYZYaw(idNum: self.missionNextWp)
//            print("gogo: Extracted x, y, z, yaw :", x, y, z, yaw)
//            self.xgotoXYZ(refPosX: x, refPosY: y, refPosZ: z, localYaw: yaw, speed: speed)
//
//
//            // Notify about going to startWP
//            NotificationCenter.default.post(name: .didNextWp, object: self, userInfo: ["next_wp": String(self.missionNextWp), "final_wp": String(mission.count-1), "cmd": "gogo_XYZ"])
//            return true
//        }
//        else{
//            print("gogo - Error: Aircraft or mission not ready for mission flight")
//            return false
//        }
//    }
//
//    //**************************************************************************************
//    // Function that sets reference position and executes the XYZ position controller timer.
//    private func xgotoXYZ(refPosX: Double, refPosY: Double, refPosZ: Double, localYaw: Double, speed: Float){
//        // Check if horixzontal positions are within geofence  (should X be max 1m?)
//        // Function is private, only approved missions will be passed in here.
//        if refPosY > missionGeoFenceY[0] && refPosY < missionGeoFenceY[1] && refPosX > missionGeoFenceX[0] && refPosX < missionGeoFenceX[1]{
//            self.refPosY = refPosY
//            self.refPosX = refPosX
//        }
//        else{
//            print("GotoXYZ Error: XY position is out of allowed area!")
//            return
//        }
//
//        // TODO, check first, then store value
//        self.refPosZ = refPosZ
//        if self.refPosZ < missionGeoFenceZ[0] && self.refPosZ > missionGeoFenceZ[1] {
//            print("GotoXYZ Error: Z Position out of allowed area for postion control, refPosZ: " + String(self.refPosZ))
//            return
//        }
//
//        //self.refYawXYZ = refYawXYZ
//        self.localYaw = localYaw
//
//
//        print("gotoXYZ: New ref pos, x:", self.refPosX, ", y: ", self.refPosY, ", z: ", self.refPosZ, ", localYaw: ", self.localYaw, ", speed: ", speed)
//        // Schedule the timer at 20Hz while the default specified for DJI is between 5 and 25Hz. Timer will execute control commands for a period of time
//        duttTimer?.invalidate()
//
//        posCtrlTimer?.invalidate()
//        posCtrlLoopCnt = 0
//        // Make sure noone else is updating the self.refPosXYZ ! TODO
//        self.posCtrlTimer = Timer.scheduledTimer(timeInterval: sampleTime/1000, target: self, selector: #selector(self.xfirePosCtrlTimer), userInfo: speed, repeats: true)
//    }

//********************************************************************************************
// Algorithm for determining of a wp is tracked or not. When tracked the mission can continue.
// Algorithm requires position and yaw to be tracked trackingRecordTarget times
//    func trackingWP(posLimit: Double, yawLimit: Double, velLimit: Double)->Bool{
//
//        let x2 = pow(self.refPosX - self.posX, 2)
//        let y2 = pow(self.refPosY - self.posY, 2)
//        let z2 = pow(self.refPosZ - self.posZ, 2)
//        let posError = sqrt(x2 + y2 + z2)
//        // tacking the gimbal yaw is not resonable, it cant be controlled.
//        let YawError = abs(getDoubleWithinAngleRange(angle: self.yawXYZ - self.refYawXYZ))
//        //print("Tracking errors: ", posError, YawError)
//        if posError < posLimit && YawError < yawLimit {
//            trackingRecord += 1
//        }
//        else{
//            trackingRecord = 0
//        }
//        if trackingRecord >= trackingRecordTarget{
//            trackingRecord = 0
//            return true
//        }
//        else{
//            return false
//        }
//    }

//    // ********************************************************************
//    // Takes velocity arguments and returns course in XYZ coordinate system
//    func getCourse(dX: Double, dY: Double)->(Double){
//        // Guard division by 0 and calculate: Course given x and y-velocities
//        // Case velY == 0, i.e. courseXYZ == 0 or -180
//        var course: Double = 0
//        if dY == 0 {
//            if dX > 0 {
//                course = 0
//            }
//            else {
//                course = 180
//            }
//        }
//        else if dY > 0 {
//            course = (Double.pi/2 - atan(dX/dY))/Double.pi*180
//        }
//        else if dY < 0 {
//            course = -(Double.pi/2 + atan(dX/dY))/Double.pi*180
//        }
//        return course
//    }
