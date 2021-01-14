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
    var gimbal: GimbalController?
    
    var state: DJIFlightControllerState?
    
    // Geofencing. TODO. Use one geofence only. Radius and height for example
    var missionGeoFenceX: [Double] = [-50, 50]
    var missionGeoFenceY: [Double] = [-50, 50]
    var missionGeoFenceZ: [Double] = [-20, -2]
    //
    
    var missionGeoFenceNorth: [Double] = [-50, 50]
    var missionGeoFenceEast: [Double] = [-50, 50]
    var missionGeoFenceDown: [Double] = [-20, -2]
    
    var missionGeoFenceLat: [Double] = [58.1, 58.3]
    var missionGeoFenceLon: [Double] = [16.7, 16.9]
    var missionGeoFenceAlt: [Double] = [2, 20]
    
    var geoFenceRadius: Double = 50                 // Geofence radius relative start location (startMyLocation)
    var geoFenceHeight: [Double] = [2, 20]          // Geofence height relative start location
    
    var pendingMission = JSON()
    var mission = JSON()
    var missionNextWp = -1
    var missionNextWpId = "id-1"
    var missionType = ""
    var activeWP: MyLocation = MyLocation()
    var missionIsActive = false
    var wpActionExecuting = false

    var posX: Double = 0
    var posY: Double = 0
    var posZ: Double = 0
    var gimbalYawXYZ: Double = 0
    var yawXYZ: Double = 0
    
    var currentMyLocation: MyLocation = MyLocation()
    
    var velX: Float = 0
    var velY: Float = 0
    var velZ: Float = 0
    var yawRate: Double = 0
    
    var refPosX: Double = 0                     // Refpos x relative XYZ origin
    var refPosY: Double = 0                     // Refpos y relative XYZ origin
    var refPosZ: Double = 0                     // Refpos z relative XYZ origin
    var refYawXYZ = 0.0                         // Patameter used for refYawXYZ, -1 means one degree left of X axis.
    var localYaw: Double = -1                   // Parameter used for storing the localYaw arg aka mission. -1 means course, 0-360 means heading relative to x axis.
    
    var refVelX: Float = 0.0
    var refVelY: Float = 0.0
    var refVelZ: Float = 0.0
    var refYawRate: Float = 0.0
    
    var refLat: Double = 0
    var refLon: Double = 0
    var refAltLLA: Double = 0
    var refYawLLA: Double = 0
    
    var xyVelLimit: Float = 900 // 300                 // cm/s horizontal speed
    var zVelLimit: Float = 150                  // cm/s vertical speed
    var yawRateLimit:Float = 150 //50                 // deg/s, defensive.
    
    var defaultXYVel: Float = 1.5               // m/s default horizontal speed (fallback) TODO remove.
    var defaultHVel: Float = 1.5               // m/s default horizontal speed (fallback)
    var toAlt: Double = -1
    var toReference = ""
    var pos: CLLocation?
    var heading: Double = 0                     // Curent heading relative to north
    var homeHeading: Double?                    // Heading of last updated homewaypoint
    var homeLocation: CLLocation?               // Location of last updated homewaypoint
    var dssSmartRtlMission: JSON = JSON()       // JSON LLA wayopints to follow in smart rtl

    // keep or use in smartRTL
  //  var dssHomeHeading: Double?               // Home heading of DSS

    var flightMode: String?                     // the flight mode as a string
    var startHeadingXYZ: Double?                // The start heading that defines the XYZ coordinate system
    var startLocationXYZ: CLLocation?           // The start location that defines the XYZ coordinate system
    var startMyLocation: MyLocation = MyLocation()// The start location as a MyLocation. Used for origin of geofence.
    
 //   var _operator: String = "USER"

    // Tracking wp properties
    var trackingRecord: Int = 0                 // Consequtive loops on correct position
    let trackingRecordTarget: Int = 8           // Consequtive loops tracking target
    let trackingPosLimit: Double = 0.3          // Pos error requirement for tracking wp
    let trackingYawLimit: Double = 4            // Yaw error requireemnt for tracking wp
    let trackingVelLimit: Double = 0.1          // Vel error requirement for tracking wp NOT USED

    // Timer settings
    let sampleTime: Double = 120                // Sample time in ms
    let controlPeriod: Double = 750 // 1500     // Number of millliseconds to send dutt command

    // Timers
    var duttTimer: Timer?
    var duttLoopCnt: Int = 0
    var duttLoopTarget: Int = 0
    
    // XYZ reference
    var posCtrlTimer: Timer?
    var posCtrlLoopCnt: Int = 0
    var posCtrlLoopTarget: Int = 250

    // MyLocation reference (LLA)
    var myLocationCtrlTimer: Timer?
    var myLocationCtrlLoopCnt: Int = 0
    var myLocationCtrlLoopTarget: Int = 250
    
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
    //    self.state = state
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
                guard let checkedHeading = self.getHeading() else {return}
                guard let checkedStartHeading = self.startHeadingXYZ else {return}
                let alpha = (checkedHeading - checkedStartHeading)/180*Double.pi
                
                self.velX = Float(vel.x * cos(alpha) + vel.y * sin(alpha))
                self.velY = Float(-vel.x * sin(alpha) + vel.y * cos(alpha))
                self.velZ = Float(vel.z)
                
                //NotificationCenter.default.post(name: .didVelUpdate, object: nil)
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
                let temp = (checkedNewValue.value as! CLLocation)
                self.pos = temp
                guard let heading = self.getHeading() else {
                   print("PosListener: Error updating heading")
                   return}
                self.heading = heading
                
                // Todo: Uppdate different frames depending on subscription. Only implementet XYZ-frame.
                // Update the XYZ coordinates relative to the XYZ frame. XYZ if XYZ is not set prior to takeoff, the homelocation updated at takeoff will be set as XYZ origin.
                guard let start = self.startLocationXYZ else {
                    print("PosListener: No start location XYZ")
                    return}
                guard let checkedStartHeading = self.startHeadingXYZ else {
                    print("PosListener: No start headingXYZ")
                    return}
                
                let lat_diff = self.pos!.coordinate.latitude - start.coordinate.latitude
                let lon_diff = self.pos!.coordinate.longitude - start.coordinate.longitude
                let alt_diff = self.pos!.altitude - start.altitude

                let posN = lat_diff * 1852 * 60
                let posE = lon_diff * 1852 * 60 * cos(start.coordinate.latitude/180*Double.pi)
                
                let alpha = checkedStartHeading/180*Double.pi

                // Coordinate transformation, from (E,N) to (y,x)
                self.posX =  posN * cos(alpha) + posE * sin(alpha)
                self.posY = -posN * sin(alpha) + posE * cos(alpha)
                self.posZ = -alt_diff
                
                guard let yawRelativeToAircraftHeading = self.gimbal!.yawRelativeToAircraftHeading else {
                               print("PosListener: Error: no gimbal relative to aircraft heading")
                               return}
                self.gimbalYawXYZ = heading - checkedStartHeading + yawRelativeToAircraftHeading
                self.yawXYZ = heading - checkedStartHeading
                
                NotificationCenter.default.post(name: .didXYZUpdate, object: nil)
                
                
                // A semaphore could be needed, controller reads often. TODO
                self.currentMyLocation.setPosition(pos: temp, heading: heading, gimbalYaw: yawRelativeToAircraftHeading)
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

                // Cath the event of setting home wp in take-off (in flight..) TODO - catch takeoff as flight mode?
                if self.startHeadingXYZ == nil && self.getIsFlying() == true {
                    print("HomePosListener: The local XYZ is not set, setting local XYZ to home position and start heading")
                    self.startLocationXYZ = (checkedNewValue.value as! CLLocation)
                    self.startHeadingXYZ = self.homeHeading
                    print("HomePosListener: StartHeadingXYZ: " + String(describing: self.startHeadingXYZ!))
                    //NotificationCenter.default.post(name: .didPrintThis, object: self, userInfo: ["printThis": "XYZ origin set to here"])
                    print("HomePosListener: Home pos was updated. XYZ origin was automatically set")
                    
                    // The new implementation. Clean up a lot above... TODO
                    // Save current postion as the start position. Geofence (radius and height) will be evaluated relative to this pos
                    self.startMyLocation.setPosition(pos: checkedNewValue.value as! CLLocation, heading: self.getHeading()!, gimbalYaw: 0, isStartWP: true)
                    self.startMyLocation.setGeoFence(radius: self.geoFenceRadius, height: self.geoFenceHeight)
                    self.startMyLocation.printLocation(sentFrom: "setOrigin")
                    
                }
                else{
                    print("HomePosListener: Home pos was updated.")
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
    
    // ******************************************************************************************
    // Set the origin and orientation for XYZ coordinate system. Can only be set once for safety!
    func setOriginXYZ()->Bool{
        if let _ = self.startHeadingXYZ {
            print("Caution: XYZ coordinate system already set!")
            return false
        }
        guard let pos = getCurrentLocation() else {
            print("setOriginXYZ: Can't get current location")
            return false}
        guard let heading = getHeading() else {
            print("setOriginXYZ: Can't get current heading")
            return false}
        guard let gimbalYaw = self.gimbal?.yawRelativeToAircraftHeading else {
            print("setOriginXYZ: Cant get gimbalYaw")
            return false}
        
        if heading == 0 {
            print("setOriginXYZ: Start heading is exactly 0, CAUTION!")
        }
        // The old implementation TODO
        self.startHeadingXYZ = heading + gimbalYaw
        self.startLocationXYZ = pos
        // The new implementation
        self.startMyLocation.setPosition(pos: pos, heading: heading, gimbalYaw: gimbalYaw)
        self.startMyLocation.setGeoFence(radius: self.geoFenceRadius, height: self.geoFenceHeight)
        self.startMyLocation.printLocation(sentFrom: "setOriginXYZ")
        
        print("setOriginXYZ: StartHeadingXYZ: " + String(describing: self.startHeadingXYZ!) + ", of which gimbalYaw is: " + String(describing: gimbalYaw))
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
        self.dssSmartRtlMission[id]["action"] = JSON("land")
        
        if pos.altitude - self.startLocationXYZ!.altitude < 2 {
            print("saveCurrentPosAsDSSHome: Forcing land altitude to 2m")
            self.dssSmartRtlMission[id]["alt"].doubleValue = self.startLocationXYZ!.altitude + 2
        }
        
        print("saveCurrentPosAsDSSHome: DSS home saved: ",self.dssSmartRtlMission)
        return true
    }
    
    //******************************************************
    // Appends current location to the DSS smart rtl mission
    func appendLocToDssSmartRtlMission()->Bool{
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
        print("xyz home alt:", self.startLocationXYZ!.altitude)


        //print("appendLocToDssSmartRtlMission: the updated smart rtl mission: ", self.dssSmartRtlMission)
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
   //     self.state = DJIFlightControllerState()
        //self.flightController?.delegate?.flightController?(self.flightController!, didUpdate: self.state!)
        
        // Activate listeners
        self.startListenToHomePosUpdated()
        self.startListenToPos()
        self.startListenToFlightMode()
        // No reason to track velocities as for now. Uncomment to enable
        self.startListenToVel()
        
        // If flight controller delegate is needed. Also activate delegate function flightcontroller row ~95
        // flightController!.delegate = self
    }
        
    //***************************************************
    // Limit any stick control command copters limitation
    func limitToMax(value: Float, limit: Float)-> Float{
        // Limit desired velocities to limit
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
        self.refVelX = 0
        self.refVelY = 0
        self.refVelZ = 0
        //let temp: Double = self.flightController?.compass?.heading   returns optionalDouble, i want Float..
        self.refYawRate = 0

        
        // TODO, set heading mode again?
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
        self.refVelX = limitToMax(value: x, limit: xyVelLimit/100)
        self.refVelY = limitToMax(value: y, limit: xyVelLimit/100)
        self.refVelZ = limitToMax(value: z, limit: zVelLimit/100)
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
        //print("Sending x: \(velX), y: \(velY), z: \(velZ), yaw: \(yawRate)")
       
//        controlData.verticalThrottle = velZ // in m/s
//        controlData.roll = velX
//        controlData.pitch = velY
//        controlData.yaw = yawRate
      
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
        
        
        //print("limitedvelX: ", limitedVelRefX, " limitedVelRefY: ", limitedVelRefY)
        
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
            //gotoXYZ(refPosX: self.posX, refPosY: self.posY, refPosZ: -targetAlt, localYaw: self.yawXYZ, speed: 0.5)  //self.yawXYZ can be -1, forcing course.. TODO
            print("Target alt:", targetAlt, "current alt: ", self.currentMyLocation.altitude)
            self.activeWP.altitude = targetAlt
            self.activeWP.heading = self.currentMyLocation.heading
            self.activeWP.coordinate.latitude = self.currentMyLocation.coordinate.latitude
            self.activeWP.coordinate.longitude = self.currentMyLocation.coordinate.longitude
            self.activeWP.speed = 0
            gotoMyLocation(wp: self.activeWP)
        default:
            print("altitude reference not known")
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
    
    //**************************************************************************************************************
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
    
    
    func dssSrtl(hoverTime: Int){
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
        
        
        print("dssRTL: Old controller is used!       WARNING")
        
        _ = self.xgogo(startWp: 0, useCurrentMission: false)  // Handle response?
        NotificationCenter.default.post(name: .didPrintThis, object: self, userInfo: ["printThis": "DSS Smart RTL activated"])
    }
    //*************************************************************************************
    // Check if a wp is within the geofence. TODO? - handeled in uploadMissionXYZ already..
    func wpFence(wp: JSON)->Bool{
        return true
    }
    
    //*************************************************************************************************
    // Checks an uploaded mission. If ok it is stored as pending mission. Activate it by sending to wp.
    func uploadMissionXYZ(mission: JSON)->(success: Bool, arg: String){
        // For the number of wp-keys, check that there is a matching wp id and that the geoFence is not violated
        var wpCnt = 0
        for (_,subJson):(String, JSON) in mission {
            // Check wp-numbering
            if mission["id" + String(wpCnt)].exists()
            {
                // Check for geofence violation
                guard withinLimit(value: subJson["x"].doubleValue, lowerLimit: missionGeoFenceX[0], upperLimit: missionGeoFenceX[1])
                    else {return (false, "GeofenceX or x missing")}
                guard withinLimit(value: subJson["y"].doubleValue, lowerLimit: missionGeoFenceY[0], upperLimit: missionGeoFenceY[1])
                    else {return (false, "GeofenceY or y missing")}
                guard withinLimit(value: subJson["z"].doubleValue, lowerLimit: missionGeoFenceZ[0], upperLimit: missionGeoFenceZ[1])
                    else {return (false, "GeofenceZ or z missing")}
                guard withinLimit(value: subJson["local_yaw"].doubleValue, lowerLimit: 0.0, upperLimit: 360.0) || subJson["local_yaw"].doubleValue == -1
                    else {return (false, "local_yaw out of bounds or missing")}
                // Check if any wp-action is supported, otherwise reject.
                if subJson["action"].exists() {
                    if subJson["action"].stringValue != "take_photo"{
                        return(false, "Faulty wp action")
                    }
                }
                // Check that any speed setting is positive
                if subJson["speed"].exists() {
                    if subJson["speed"].doubleValue < 0.1 {
                        return(false, "Too low speed")
                    }
                }
                wpCnt += 1
                continue
            }
            else{
                return (false, "Wp numbering faulty")
            }
        }
        self.pendingMission = mission
        return (true, "")
    }
    // Checks an uploaded mission. If ok it is stored as pending mission. Activate it by sending to wp.
    func uploadMissionNED(mission: JSON)->(success: Bool, arg: String){
        // For the number of wp-keys, check that there is a matching wp id and that the geoFence is not violated
        var wpCnt = 0
        print("uploadMissionNED: Evaluate to use Radius for geofence - TODO")
        print("uploadMissionNED TODO: Test geofence NED")

        for (_,subJson):(String, JSON) in mission {
            // Check wp-numbering
            if mission["id" + String(wpCnt)].exists()
            {
                // Check for geofence violation
                guard withinLimit(value: subJson["north"].doubleValue, lowerLimit: missionGeoFenceNorth[0], upperLimit: missionGeoFenceNorth[1])
                    else {return (false, "GeofenceNorth or North missing")}
                guard withinLimit(value: subJson["east"].doubleValue, lowerLimit: missionGeoFenceEast[0], upperLimit: missionGeoFenceEast[1])
                    else {return (false, "GeofenceEast or East missing")}
                guard withinLimit(value: subJson["down"].doubleValue, lowerLimit: missionGeoFenceDown[0], upperLimit: missionGeoFenceDown[1])
                    else {return (false, "GeofenceDown or Down missing")}
                guard withinLimit(value: subJson["heading"].doubleValue, lowerLimit: 0.0, upperLimit: 360.0) || subJson["heading"].doubleValue == -1
                    else {return (false, "heading out of bounds or missing")}
                // Check if any wp-action is supported, otherwise reject.
                if subJson["action"].exists() {
                    if subJson["action"].stringValue != "take_photo"{
                        return(false, "Faulty wp action")
                    }
                }
                // Check that any speed setting is positive
                if subJson["speed"].exists() {
                    if subJson["speed"].doubleValue < 0.1 {
                        return(false, "Too low speed")
                    }
                }
                wpCnt += 1
                continue
            }
            else{
                return (false, "Wp numbering faulty")
            }
        }
        self.pendingMission = mission
        return (true, "")
    }
    
    // Checks an uploaded mission. If ok it is stored as pending mission. Activate it by sending to wp.
    func uploadMissionLLA(mission: JSON)->(success: Bool, arg: String){
        // For the number of wp-keys, check that there is a matching wp id and that the geoFence is not violated
        var wpCnt = 0
        print("uploadMissionLLA: Evaluate to use Radius for geofence - TODO")
        print("uploadMissionLLA TODO: Test geofence LLA")
        for (_,subJson):(String, JSON) in mission {
            // Check wp-numbering
            if mission["id" + String(wpCnt)].exists()
            {
                // Check for geofence violation
                guard withinLimit(value: subJson["lat"].doubleValue, lowerLimit: missionGeoFenceLat[0], upperLimit: missionGeoFenceLat[1])
                    else {return (false, "GeofenceLat or Lat missing")}
                guard withinLimit(value: subJson["lon"].doubleValue, lowerLimit: missionGeoFenceLon[0], upperLimit: missionGeoFenceLon[1])
                    else {return (false, "GeofenceLon or Lon missing")}
                guard withinLimit(value: subJson["alt"].doubleValue, lowerLimit: missionGeoFenceAlt[0], upperLimit: missionGeoFenceAlt[1])
                    else {return (false, "GeofenceAlt or Alt missing")}
                guard withinLimit(value: subJson["heading"].doubleValue, lowerLimit: 0.0, upperLimit: 360.0) || subJson["heading"].doubleValue == -1
                    else {return (false, "heading out of bounds or missing")}
                // Check if any wp-action is supported, otherwise reject.
                if subJson["action"].exists() {
                    if subJson["action"].stringValue != "take_photo"{
                        return(false, "Faulty wp action")
                    }
                }
                // Check that any speed setting is positive
                if subJson["speed"].exists() {
                    if subJson["speed"].doubleValue < 0.1 {
                        return(false, "Too low speed")
                    }
                }
                wpCnt += 1
                continue
            }
            else{
                return (false, "Wp numbering faulty")
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
        if self.startLocationXYZ == nil {
            print("readyForMission Error: No start location XYZ")
            return false
        }
        else if self.startHeadingXYZ == nil {
            print("readyForMission Error: No start headingXYZ")
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
    
    // *****************************************************************************************
    // Converts heading from a mission to local yaw in range 0-360 or -1. -1 means follow course
    func getLocalYawFromHeading(heading: Double)->Double{
        var local_yaw: Double = -1
        if heading == -1 {
            // Use course for heading
            local_yaw = -1
        }
        else {
            // Convert to local yaw
            local_yaw = heading - self.startHeadingXYZ!
            // local_yaw must be in range 0-360, or -1
            if local_yaw < 0 {
                local_yaw += 360
            }
            if local_yaw > 360 {
                local_yaw -= 360
            }
        }
        return local_yaw
    }
    
    
    
    
    
    
    
    
    
    
    
    
    
    
//    //
//    //
//    func setUpActiveWP(idNum: Int){
//        let id: String = "id" + String(idNum)
//        self.activeWP
//    }
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    //************************************************************************************************************************
    // Extract the wp x, y, z, yaw from wp with id idNum. isReadyForMission() must return true before this method can be used.
    func getWpXYZYaw(idNum: Int)->(Double, Double, Double, Double, Float){
        let id: String = "id" + String(idNum)
        var speed: Float = self.defaultXYVel
        var x: Double = 0
        var y: Double = 0
        var z: Double = 0
        var local_yaw: Double = -1
        
        // If mission is XYZ
        if self.mission[id]["x"].exists() {
            x = self.mission[id]["x"].doubleValue
            y = self.mission[id]["y"].doubleValue
            z = self.mission[id]["z"].doubleValue
            local_yaw = self.mission[id]["local_yaw"].doubleValue
            // Check optional speed.
            if self.mission[id]["speed"].exists() {
                speed = self.mission[id]["speed"].floatValue
            }
        }
        
        // If mission is NED - TODO Test
        if self.mission[id]["north"].exists(){
            let posN = self.mission[id]["north"].doubleValue
            let posE = self.mission[id]["east"].doubleValue
            let posD = self.mission[id]["down"].doubleValue
            (x, y, z) = self.getXYZYawFromNED(posN: posN, posE: posE, posD: posD)
            local_yaw = getLocalYawFromHeading(heading: self.mission[id]["heading"].doubleValue)
            if self.mission[id]["speed"].exists() {
                speed = self.mission[id]["speed"].floatValue
            }
        }
        
        // If mission is LLA - TODO Test
        if self.mission[id]["lat"].exists(){
            let wp = MyLocation()
            wp.coordinate.latitude = self.mission[id]["lat"].doubleValue
            wp.coordinate.longitude = self.mission[id]["lon"].doubleValue
            wp.altitude = self.mission[id]["alt"].doubleValue
            
            let (posN, posE, posD) = self.getNEDFromLocation(start: self.startLocationXYZ!, target: wp)
            (x, y, z) = self.getXYZYawFromNED(posN: posN, posE: posE, posD: posD)
            local_yaw = getLocalYawFromHeading(heading: self.mission[id]["heading"].doubleValue)
            if self.mission[id]["speed"].exists() {
                speed = self.mission[id]["speed"].floatValue
            }
        }
        return (x, y, z, local_yaw, speed)
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
    
    func getXYZYawFromNED(posN: Double, posE: Double, posD: Double)->(Double, Double, Double){
        // Start heading and heading shall be available since isReadyForMission() shall have returned true prior to executing
        let startHeadingXYZ = self.startHeadingXYZ!
        let alpha = startHeadingXYZ/180*Double.pi

        // Coordinate transformation, from (E,N) to (y,x)
        let x =  posN * cos(alpha) + posE * sin(alpha)
        let y = -posN * sin(alpha) + posE * cos(alpha)
        let z = posD

        // Need direction from HERE to THERE in order to calc course..
//        var yawXYZ: Double = 0
//        if heading == -1 {
//            // Guard division by 0 and calculate: Heading = course
//            // Case localYaw = 0 or -180
//            if y == 0 {
//                if x > 0 {
//                    yawXYZ = 0
//                }
//                else {
//                    yawXYZ = 180
//                }
//            }
//            else if y > 0 {
//                yawXYZ = (Double.pi/2 - atan(x/y))/Double.pi*180
//            }
//            else if y < 0 {
//                yawXYZ = -(Double.pi/2 + atan(x/y))/Double.pi*180
//            }
//        }
//        else {
//            yawXYZ = self.heading - startHeadingXYZ
//        }
        
        // Returns heading as local heading.
        // Have to handle -1 here.
 //       let yawXYZ = getDoubleWithinAngleRange(angle: self.heading - startHeadingXYZ)
        
        
        return(x, y, z)
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
    
    //**********************************************************************************************
    // Starts the pending mission on startWp. returns false if startWp is not in the pending mission
    // useCurrentMission is needed for continuing current mission after wp action. If set to false,
    // the pending mission will be loaded.
    func xgogo(startWp: Int, useCurrentMission: Bool)->Bool{
        // useCurrentMission?
        if useCurrentMission{
            self.setMissionNextWp(num: self.missionNextWp + 1)
            if self.missionNextWp == -1{
                NotificationCenter.default.post(name: .didNextWp, object: self, userInfo: ["next_wp": String(self.missionNextWp), "final_wp": String(mission.count-1), "cmd": "gogo_XYZ"])
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
                self.missionIsActive = true
                print("gogo: missionIsActive is set to true")
            }
            else{
                print("gogo - Error: No such wp id in pending mission: id" + String(startWp))
                return false
            }
        }
        // Check if ready for mission
        if isReadyForMission(){
            
            
            let (x, y, z, yaw, speed) = getWpXYZYaw(idNum: self.missionNextWp)
            print("gogo: Extracted x, y, z, yaw :", x, y, z, yaw)
            self.xgotoXYZ(refPosX: x, refPosY: y, refPosZ: z, localYaw: yaw, speed: speed)
            
            
            // Notify about going to startWP
            NotificationCenter.default.post(name: .didNextWp, object: self, userInfo: ["next_wp": String(self.missionNextWp), "final_wp": String(mission.count-1), "cmd": "gogo_XYZ"])
            return true
        }
        else{
            print("gogo - Error: Aircraft or mission not ready for mission flight")
            return false
        }
    }
    
    //**************************************************************************************
    // Function that sets reference position and executes the XYZ position controller timer.
    private func xgotoXYZ(refPosX: Double, refPosY: Double, refPosZ: Double, localYaw: Double, speed: Float){
        // Check if horixzontal positions are within geofence  (should X be max 1m?)
        // Function is private, only approved missions will be passed in here.
        if refPosY > missionGeoFenceY[0] && refPosY < missionGeoFenceY[1] && refPosX > missionGeoFenceX[0] && refPosX < missionGeoFenceX[1]{
            self.refPosY = refPosY
            self.refPosX = refPosX
        }
        else{
            print("GotoXYZ Error: XY position is out of allowed area!")
            return
        }
        
        // TODO, check first, then store value
        self.refPosZ = refPosZ
        if self.refPosZ < missionGeoFenceZ[0] && self.refPosZ > missionGeoFenceZ[1] {
            print("GotoXYZ Error: Z Position out of allowed area for postion control, refPosZ: " + String(self.refPosZ))
            return
        }
        
        //self.refYawXYZ = refYawXYZ
        self.localYaw = localYaw
        
        
        print("gotoXYZ: New ref pos, x:", self.refPosX, ", y: ", self.refPosY, ", z: ", self.refPosZ, ", localYaw: ", self.localYaw, ", speed: ", speed)
        // Schedule the timer at 20Hz while the default specified for DJI is between 5 and 25Hz. Timer will execute control commands for a period of time
        duttTimer?.invalidate()
        
        posCtrlTimer?.invalidate()
        posCtrlLoopCnt = 0
        // Make sure noone else is updating the self.refPosXYZ ! TODO
        self.posCtrlTimer = Timer.scheduledTimer(timeInterval: sampleTime/1000, target: self, selector: #selector(self.xfirePosCtrlTimer), userInfo: speed, repeats: true)
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
    // Prepare a MyLocation for mission execution, then call gotoMyLocation. New implementeation of gogo
    func gogoMyLocation(startWp: Int, useCurrentMission: Bool)->Bool{
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
                print("gogoMyLocation: missionIsActive is set to true")
            }
            else{
                print("gogoMyLocation - Error: No such wp id in pending mission: id" + String(startWp))
                return false
            }
            
        }
        // Check if ready for mission, then setup the wp and gogo. Convert any coordinate system to LLA.
        if isReadyForMission(){
            // Reset the activeWP TODO - does this cause a memory leak? If so create a reset function. Test in playground.
            let id = "id" + String(self.missionNextWp)
            self.activeWP.setUpFromJsonWp(jsonWP: self.mission[id], defaultSpeed: self.defaultHVel, start: self.startMyLocation)
            
            self.activeWP.printLocation(sentFrom: "gogoMyLocation")
            
            self.gotoMyLocation(wp: self.activeWP)
            //self.gotoXYZ(refPosX: x, refPosY: y, refPosZ: z, localYaw: yaw, speed: speed)
            
            // Notify about going to startWP
            NotificationCenter.default.post(name: .didNextWp, object: self, userInfo: ["next_wp": String(self.missionNextWp), "final_wp": String(mission.count-1), "cmd": "gogo" + self.missionType])
            return true
        }
        else{
            print("gogoMyLocation - Error: Aircraft or mission not ready for mission flight")
            return false
        }
    }
    
    //
    // Corresponding function to gotoXYZ but for MyLocation and lat long.  What ever type of WP we are going to, create a MyLocation object, then activate gotoMyLocation
    private func gotoMyLocation(wp: MyLocation){
        // Check some Geo fence stuff. Ask start location if the wp is within the geofence.
        if !startMyLocation.geofenceOK(wp: wp){
            print("The WP violates the geofence!")
            return
        }
        // Print some status?
        print("gotoMyLocation is setting up controller timer.")
        
        // Fire LLAPosCtrl
        duttTimer?.invalidate()
        posCtrlTimer?.invalidate()
        myLocationCtrlTimer?.invalidate()
        myLocationCtrlLoopCnt = 0
        self.myLocationCtrlTimer = Timer.scheduledTimer(timeInterval: sampleTime/1000, target: self, selector: #selector(self.fireMyLocationCtrlTimer), userInfo: nil, repeats: true)
    }
    
    //********************************************************************************************
    // Algorithm for determining of a wp is tracked or not. When tracked the mission can continue.
    // Algorithm requires position and yaw to be tracked trackingRecordTarget times
    func trackingWP(posLimit: Double, yawLimit: Double, velLimit: Double)->Bool{
        
        let x2 = pow(self.refPosX - self.posX, 2)
        let y2 = pow(self.refPosY - self.posY, 2)
        let z2 = pow(self.refPosZ - self.posZ, 2)
        let posError = sqrt(x2 + y2 + z2)
        // tacking the gimbal yaw is not resonable, it cant be controlled.
        let YawError = abs(getDoubleWithinAngleRange(angle: self.yawXYZ - self.refYawXYZ))
        //print("Tracking errors: ", posError, YawError)
        if posError < posLimit && YawError < yawLimit {
            trackingRecord += 1
        }
        else{
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
    
    //
    // Algorithm for detemining if at WP is tracked. When tracked mission can continue.
    // Algorithm requires both position and yaw to be tracked according to globally defined tracking limits.
    func trackingMyLocation(posLimit: Double, yawLimit: Double, velLimit: Double)->Bool{
        // Distance in meters
        let (_, _, _, _, distance3D, _) = self.activeWP.distanceTo(wpLocation: self.currentMyLocation)
        let yawError = abs(getDoubleWithinAngleRange(angle: self.currentMyLocation.heading - self.refYawLLA))

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
    
    // ********************************************************************
    // Takes velocity arguments and returns course in XYZ coordinate system
    func getCourse(dX: Double, dY: Double)->(Double){
        // Guard division by 0 and calculate: Course given x and y-velocities
        // Case velY == 0, i.e. courseXYZ == 0 or -180
        var course: Double = 0
        if dY == 0 {
            if dX > 0 {
                course = 0
            }
            else {
                course = 180
            }
        }
        else if dY > 0 {
            course = (Double.pi/2 - atan(dX/dY))/Double.pi*180
        }
        else if dY < 0 {
            course = -(Double.pi/2 + atan(dX/dY))/Double.pi*180
        }
        return course
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
            sendControlData(velX: self.refVelX, velY: self.refVelY, velZ: self.refVelZ, yawRate: self.refYawRate, speed: self.defaultXYVel)
        }
    }
    
    
    // ************************************************************************************************************************************************
    // Position controller from XYZ coordinates.
    // Takes speed argument in userInfo. If omitted default speed is used.
    // Evaluates if a wp is tracked, compares tracking limits and during a number of loops
    // Looks for wp action. If action it stops mission and notifies action, after action is performed mission is restarted by action function.
    // If no action the wp number is increased, new XYZ reference positions are extracted from any mission (XYZ, LLA, NED) and gotoXYZ is called. gotoXYZ invalidates the timer and starts a new timer.
    // Position controller that files towards self.refPosX/Y/Z/ refYawXYZ. Reference positions are given in XYZ coordinate system, drone is controlled in BODY XYZ. Yaw is handeled too, if yaw arg i -1 heading is set to course towards next wp.
    // Safety function for maxtime
    
    @objc func xfirePosCtrlTimer(_ timer: Timer) {
        // Test if speed argument is passed. If not use default speed.
        var speed = self.defaultXYVel
        if timer.isValid{
            if let temp = timer.userInfo as? Float {
                speed = temp
            }
        }
        
        posCtrlLoopCnt += 1
        // If we arrived. Compares rePosX with posX etc
        if trackingWP(posLimit: trackingPosLimit, yawLimit: trackingYawLimit, velLimit: trackingVelLimit){
            print("firePosCtrolTimer: Wp", self.missionNextWp, " is tracked")
            sendControlData(velX: 0, velY: 0, velZ: 0, yawRate: 0, speed: 0)
            // Add location to DSS RTL List. TODO what if we are on the dss srtl?
            // Do not add climb to alt after take-off. It is executed as a mission.
            if  self.missionNextWp != -1{
                if self.appendLocToDssSmartRtlMission(){
                    NotificationCenter.default.post(name: .didPrintThis, object: self, userInfo: ["printThis": "Location was added to DSS smart RTL mission"])
                }
                else {
                    NotificationCenter.default.post(name: .didPrintThis, object: self, userInfo: ["printThis": "Caution: Current location was NOT added to DSS smart rtl"])
                }
            }
            // WP tracked, If we are on a mission
            if self.missionIsActive{
                // Check for wp action
                let action = getAction(idNum: self.missionNextWp)
                if action == "take_photo"{
                    // Notify action to be executed
                    NotificationCenter.default.post(name: .didWPAction, object: self, userInfo: ["wpAction": action])
                    // Stop mission, Notifier function will re-activate the mission and send gogo with next wp as reference
                    self.missionIsActive = false
                    self.posCtrlTimer?.invalidate()
                    return
                }
                if action == "land"{
                    let secondsSleep: UInt32 = 5*1000000
                    usleep(secondsSleep)
                    NotificationCenter.default.post(name: .didWPAction, object: self, userInfo: ["wpAction": action])
                    self.missionIsActive = false
                    self.posCtrlTimer?.invalidate()
                    return
                }
                // Note that the current mission is stoppped (paused) if there is a wp action.

                self.setMissionNextWp(num: self.missionNextWp + 1)
                if self.missionNextWp != -1{
                    let (x, y, z, yaw, speed_) = self.getWpXYZYaw(idNum: self.missionNextWp)
                    self.xgotoXYZ(refPosX: x, refPosY: y, refPosZ: z, localYaw: yaw, speed: speed_)
                }
                else{
                    print("id is -1")
                    self.missionIsActive = false
                    self.posCtrlTimer?.invalidate() // dont fire timer again
                }
                NotificationCenter.default.post(name: .didNextWp, object: self, userInfo: ["next_wp": String(self.missionNextWp), "final_wp": String(mission.count-1), "cmd": "gogo_XYZ"])
            }
            else{
                print("No mission is active")
                posCtrlTimer?.invalidate()
            }
        }
        // WP is not tracked
        // The controller
        else{
            // Implement P-controller, position error to ref vel: Get error in XYZ, handle yaw, rotate to BODY XYZ. Then send control data.
            let xDiff: Float = Float(self.refPosX - self.posX)
            let yDiff: Float = Float(self.refPosY - self.posY)
            let zDiff: Float = Float(self.refPosZ - self.posZ)

            //Do not concider gimbalYaw in yawControl
            // Check if following course or heading:
            if self.localYaw == -1 {
                // heading equals course
                self.refYawXYZ = getCourse(dX: Double(xDiff), dY: Double(yDiff))
                //( To only check course once)
                self.localYaw = self.refYawXYZ
            }
            else {
                self.refYawXYZ = self.localYaw
            }
            
            
            // Calculate yaw error, use shortest way (right or left?)
            let yawError = getFloatWithinAngleRange(angle: Float(self.yawXYZ - self.refYawXYZ))
            self.refYawRate = -yawError*yawKP
            
            // Feedfoward to fly in straight line
            let yawFF = self.refYawRate*yawFFKP
            
            guard let checkedHeading = self.getHeading() else {return}
            guard let checkedStartHeading = self.startHeadingXYZ else {return}
            let alphaRad = (checkedHeading - checkedStartHeading + Double(yawFF))/180*Double.pi

            // Rotate coordinates, calc refvelx, refvely
//            let oldRefVelX = self.refVelX
//            let oldRefVelY = self.refVelY
            
            // xDiff is in XYZ coordinates.
            let xDiffBody = xDiff * Float(cos(alphaRad)) + yDiff * Float(sin(alphaRad))
            let yDiffBody = -xDiff * Float(sin(alphaRad)) + yDiff * Float(cos(alphaRad))
//            self.refVelX =  (xDiff * Float(cos(alphaRad)) + yDiff * Float(sin(alphaRad)))*hPosKP
//            self.refVelY = (-xDiff * Float(sin(alphaRad)) + yDiff * Float(cos(alphaRad)))*hPosKP

            self.refVelX = xDiffBody*hPosKP - hPosKD*self.velX/(abs(xDiffBody)+1)
            self.refVelY = yDiffBody*hPosKP - hPosKD*self.velY/(abs(yDiffBody)+1)
           
            print("refVelX: ", self.refVelX, "velX: ", self.velX, " brake: ", hPosKD*self.velX/abs(xDiffBody)+1)
//            print("oldRefVelX: ", oldRefVelX, " newRefVelX: ", self.refVelX, "velx: ", self.velX)
//            print("oldRefVelY: ", oldRefVelY, " newRefVelY: ", self.refVelY, "vely: ", self.velY)

            // Calc refvelz
            self.refVelZ = (zDiff) * vPosKP
            // If velocity get limited the copter will not fly in straight line! Handled in sendControlData

            //print("local_yaw: ", self.localYaw, " xDiff: ", xDiff, " yDiff: ", yDiff, "refYawXYZ: ", self.refYawXYZ, " yawFF: ", yawFF)
            
            
            // Send control data, limits in velocity are handeled in sendControlData
            sendControlData(velX: self.refVelX, velY: self.refVelY, velZ: self.refVelZ, yawRate: self.refYawRate, speed: speed)
        }
        
        // For safety during testing.. Maxtime for flying to wp
        if posCtrlLoopCnt >= posCtrlLoopTarget{
            sendControlData(velX: 0, velY: 0, velZ: 0, yawRate: 0, speed: 0)

            NotificationCenter.default.post(name: .didPrintThis, object: self, userInfo: ["printThis": "Position controller max time exeeded"])
            
            posCtrlTimer?.invalidate()
        }
    }
    
    @objc func fireMyLocationCtrlTimer(_ timer: Timer) {
        
        
        myLocationCtrlLoopCnt += 1
        // always false.. TODO
        if trackingMyLocation(posLimit: trackingPosLimit, yawLimit: trackingYawLimit, velLimit: trackingVelLimit){
            print("fireMyLocationCtrlTimer: Wp", self.missionNextWp, " is tracked")
            print(self.activeWP.altitude, self.currentMyLocation.altitude)
            
            sendControlData(velX: 0, velY: 0, velZ: 0, yawRate: 0, speed: 0)
            
            if self.missionNextWp != -1{
                // Add to DSS SRTL list.
                // TODO
                // Extend a list of MyLocations
                // Save
                // - coordinates
                // - alt
                // - speed?
                // - heading
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
                    self.myLocationCtrlTimer?.invalidate()
                    return
                }
                if action == "land"{
                    let secondsSleep: UInt32 = 5*1000000
                    usleep(secondsSleep)
                    NotificationCenter.default.post(name: .didWPAction, object: self, userInfo: ["wpAction": action])
                    self.missionIsActive = false
                    self.myLocationCtrlTimer?.invalidate()
                    return
                }
                // Note that the current mission is stoppped (paused) if there is a wp action.
                self.setMissionNextWp(num: self.missionNextWp + 1)
                if self.missionNextWp != -1{
                    let id = "id" + String(self.missionNextWp)
                    self.activeWP.setUpFromJsonWp(jsonWP: self.mission[id], defaultSpeed: self.defaultHVel, start: self.startMyLocation)
                    
                    self.activeWP.printLocation(sentFrom: "gogoMyLocation")
                    
                    gotoMyLocation(wp: self.activeWP)
                }
                else{
                    print("id is -1")
                    self.missionIsActive = false
                    myLocationCtrlTimer?.invalidate() // dont fire timer again
                }
                NotificationCenter.default.post(name: .didNextWp, object: self, userInfo: ["next_wp": String(self.missionNextWp), "final_wp": String(mission.count-1), "cmd": "gogo_???"])
            }
            else {
                print("No mission is active")
                myLocationCtrlTimer?.invalidate()
            }
        }
        // WP is not tracked
        // The controller
        else {
            // Calculate BODY control commands from lat long reference frame
            
            // Get distance and bearing from here to wp
            let (northing, easting, dAlt, distance2D, _, bearing) = self.currentMyLocation.distanceTo(wpLocation: self.activeWP)
            
            // Set reference Yaw. Heading equals bearing or manually set? Only check once per wp. If bearing becomes exactly -1 it will be evaluated agian, that is ok.
            if self.activeWP.heading == -1{
                self.activeWP.heading = bearing
            }
            self.refYawLLA = self.activeWP.heading
            
            
            // Calculate yaw-error, use shortest way (right or left?)
            let yawError = getFloatWithinAngleRange(angle: (Float(self.currentMyLocation.heading - self.refYawLLA)))
            // P-controller for Yaw
            self.refYawRate = -yawError*yawKP
            // Feedforward TBD
            //let yawFF = self.refYawRate*yawFFKP*0
            
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
            let vel = sqrt(pow(self.velX,2)+pow(self.velY,2))
            
            //hdrano:
            //decellerate at 2m/s/s
            // at distance_to_wp = Speed/2 -> brake
            if Float(distance2D) < etaLimit * vel {
                // Slow down to half speed (dont limit more than to 1.5 though) or use wp speed if it is lower.
                speed = min(max(vel/2,1.5), speed)
                print("Braking!")
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
            self.refVelX = (xDiffBody*hPosKP - hPosKD*self.velX/xDivider)*turnFactor
            self.refVelY = (yDiffBody*hPosKP - hPosKD*self.velY/yDivider)*turnFactor
            
            // Calc refVelZ
            self.refVelZ = Float(-dAlt) * vPosKP
        
            // TODO, do not store reference values globally?
            self.sendControlData(velX: self.refVelX, velY: self.refVelY, velZ: self.refVelZ, yawRate: self.refYawRate, speed: speed)
        }
        // Maxtime for flying to wp
        if myLocationCtrlLoopCnt >= myLocationCtrlLoopTarget{
            sendControlData(velX: 0, velY: 0, velZ: 0, yawRate: 0, speed: 0)

            NotificationCenter.default.post(name: .didPrintThis, object: self, userInfo: ["printThis": "myLocationController max time exeeded"])
            myLocationCtrlTimer?.invalidate()
        }
    }
}

//          hdrpano explaining when to brake
//          https://www.youtube.com/watch?fbclid=IwAR0w0VGptmEtxpYLqo1vrizU0K_M-veU_rMU8FN45yy-upvS_4noByA5qrs&v=fRPYyuK_eLA&feature=youtu.be

//            var xDivider: Float = 1
//            var yDivider: Float = 1
//            if xDiffBody < 0{
//                xDivider = xDiffBody - 1
//            }
//            else{
//                xDivider = xDiffBody + 1
//            }
//            if yDiffBody < 0{
//                yDivider = yDiffBody - 1
//            }
//            else{
//                yDivider = yDiffBody + 1
//            }
