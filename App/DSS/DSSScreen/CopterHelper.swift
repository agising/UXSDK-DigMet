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
    
    var missionGeoFenceX: [Double] = [-5, 5]
    var missionGeoFenceY: [Double] = [-10, 10]
    var missionGeoFenceZ: [Double] = [-20, -2]
    
    var pendingMission = JSON()
    var mission = JSON()
    var missionNextWp = -1
    var missionNextWpId = "id-1"
    var missionIsActive = false
    var wpActionExecuting = false

    var posX: Double = 0
    var posY: Double = 0
    var posZ: Double = 0
    var gimbalYawXYZ: Double = 0
    var yawXYZ: Double = 0
    
    var velX: Double = 0
    var velY: Double = 0
    var velZ: Double = 0
    var yawRate: Double = 0
    
    var refPosX: Double = 0
    var refPosY: Double = 0
    var refPosZ: Double = 0
    var refYawXYZ = 0.0
    
    var refVelX: Float = 0.0
    var refVelY: Float = 0.0
    var refVelZ: Float = 0.0
    var refYawRate: Float = 0.0
    
    var refLat: Double = 0
    var refLon: Double = 0
    var refAltLLA: Double = 0
    var refYawLLA: Double = 0
    
    var xyVelLimit: Float = 300                 // cm/s horizontal speed
    var zVelLimit: Float = 150                  // cm/s vertical speed
    var yawRateLimit:Float = 50                 // deg/s, defensive.
    
    var defaultXYVel: Float = 1.5               // m/s default horizontal speed (fallback)

    var toAlt: Double = -1
    var toReference = ""
    var pos: CLLocation?
    var heading: Double = 0
    var homeHeading: Double?                    // Heading of last updated homewaypoint
    var homeLocation: CLLocation?               // Location of last updated homewaypoint
    var dssSmartRtlMission: JSON = JSON()       // JSON LLA wayopints to follow in smart rtl

    // keep or use in smartRTL
  //  var dssHomeHeading: Double?                 // Home heading of DSS

    var flightMode: String?                     // the flight mode as a string
    var startHeadingXYZ: Double?                // The start heading that defines the XYZ coordinate system
    var startLocationXYZ: CLLocation?           // The statt location that defines the XYZ coordinate system
    
 //   var _operator: String = "USER"

    var duttTimer: Timer?
    var posCtrlTimer: Timer?
    var trackingRecord: Int = 0         // Consequtive loops on correct position
    let trackingRecordTarget: Int = 8  // Consequtive loops tracking target
    let trackingPosLimit: Double = 0.3          // Pos error requirement for tracking wp
    let trackingYawLimit: Double = 4            // Yaw error requireemnt for tracking wp
    let trackingVelLimit: Double = 0.1          // Vel error requirement for tracking wp NOT USED
    let sampleTime: Double = 50         // Sample time in ms
    let controlPeriod: Double = 750 // 1500    // Number of millliseconds to send command
    var loopCnt: Int = 0
    var loopTarget: Int = 0
    var posCtrlLoopCnt: Int = 0
    var posCtrlLoopTarget: Int = 250
    private let hPosKP: Float = 0.9     // Test KP 2!
    private let vPosKP: Float = 1
    private let vVelKD: Float = 0
    private let yawKP: Float = 3
    
    
    override init(){
    // Calc number of loops for dutt cycle
        loopTarget = Int(controlPeriod / sampleTime)
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
                let alpha = checkedHeading/180*Double.pi
                
                self.velX = vel.x * cos(alpha) + vel.y * sin(alpha)
                self.velY = -vel.x * sin(alpha) + vel.y * cos(alpha)
                self.velZ = vel.z
                
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
                self.pos = (checkedNewValue.value as! CLLocation)
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

                let posN = lat_diff * 1854 * 60
                let posE = lon_diff * 1854 * 60 * cos(start.coordinate.latitude/180*Double.pi)
                
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
        self.startHeadingXYZ = heading + gimbalYaw
        self.startLocationXYZ = pos
        print("setOriginXYZ: StartHeadingXYZ: " + String(describing: self.startHeadingXYZ!) + ", of which gimbalYaw is: " + String(describing: gimbalYaw))
        NotificationCenter.default.post(name: .didPrintThis, object: self, userInfo: ["printThis": "XYZ origin set to here + gimbal yaw"])
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
        //self.startListenToVel()
        
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
        loopCnt = 0
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
    
    //
    // Set altitude function. Climbs/descends to the desired altitude at the current position.
    func setAlt(targetAlt: Double, reference: String){
        switch reference{
        case "HOME":
            gotoXYZ(refPosX: self.posX, refPosY: self.posY, refPosZ: -targetAlt, refYawXYZ: self.yawXYZ, speed: 0.5)
        
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
        
        _ = self.gogo(startWp: 0, useCurrentMission: false)  // Handle response?
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
    
    func uploadMissionLLA(mission:JSON)->(succsess: Bool, arg: String){
        print("uploadMissionLLA: Not implemented yet")
        return(false, "Not implemented")
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
    
    //************************************************************************************************************************
    // Extract the wp x, y, z, yaw from wp with id idNum. isReadyForMission() must return true before this method can be used.
    func getWpXYZYaw(idNum: Int)->(Double, Double, Double, Double, Float){
        let id: String = "id" + String(idNum)
        var heading: Double = 0
        var speed: Float = self.defaultXYVel
        // If mission is XYZ
        if self.mission[id]["x"].exists() {
            let x = self.mission[id]["x"].doubleValue
            let y = self.mission[id]["y"].doubleValue
            let z = self.mission[id]["z"].doubleValue
            
            let local_yaw = getDoubleWithinAngleRange(angle: self.mission[id]["local_yaw"].doubleValue)
            print("                               The local yaw was limited to: ", local_yaw)
            // TODO: heading == -1
            if self.mission[id]["speed"].exists() {
                speed = self.mission[id]["speed"].floatValue
            }
            return (x, y, z, local_yaw, speed)
        }
        
        // If mission is NED - TODO Test
        if self.mission[id]["north"].exists(){
            let posN = self.mission[id]["north"].doubleValue
            let posE = self.mission[id]["east"].doubleValue
            let posD = self.mission[id]["down"].doubleValue
            if self.mission[id]["heading"].exists(){
                if self.mission[id]["heading"].doubleValue != -1{
                    heading = getDoubleWithinAngleRange(angle: self.mission[id]["heading"].doubleValue)
                }
                // Calc course to destination. Use course for heading
                else{
                    // Defult to start heading.. TODO
                    print("getWpXYZYaw - Defaut vaule used! Have to correct code.")
                    heading = self.startHeadingXYZ!
                }
            }
            if self.mission[id]["speed"].exists() {
                speed = self.mission[id]["speed"].floatValue
            }

            // TODO where to extract yaw? here or there?
            let (x, y, z, yaw) = self.getXYZYawFromNED(posN: posN, posE: posE, posD: posD, heading: heading)
            return(x, y, z, yaw, speed)
        }
        
        // If mission is LLA - TODO Test
        if self.mission[id]["lat"].exists(){
            let wp = MyLocation()
            wp.coordinate.latitude = self.mission[id]["lat"].doubleValue
            wp.coordinate.longitude = self.mission[id]["lon"].doubleValue
            wp.altitude = self.mission[id]["alt"].doubleValue
            if self.mission[id]["heading"].exists(){
                if self.mission[id]["heading"].doubleValue != -1{
                    heading = getDoubleWithinAngleRange(angle: self.mission[id]["heading"].doubleValue)
                }
                // Calc course to destination. Use course for heading
                else{
                    // Defult to start heading.. TODO
                    print("getWpXYZYaw - Defaut vaule used for heading! Have to correct code.")
                    heading = self.startHeadingXYZ!
                }
            }
            wp.heading = heading
            if self.mission[id]["speed"].exists() {
                speed = self.mission[id]["speed"].floatValue
            }

            
            let (posN, posE, posD) = self.getNEDFromLocation(start: self.startLocationXYZ!, target: wp)
            let (x, y, z, yaw) = self.getXYZYawFromNED(posN: posN, posE: posE, posD: posD, heading: wp.heading)
           
            return(x, y, z, yaw, speed)
        }
        
        print("TODO  BAD, DONT END UP HERE. ERROR")
        return (0.0,0.0,0.0,0.0, 0.0)
    }
    
    
    
    // ***********************************************************
    // Calculate the NED coordinates of target relative to origin
    func getNEDFromLocation(start: CLLocation, target: MyLocation)->(Double, Double, Double){
        // Coordinates delta
        let dLat = target.coordinate.latitude - start.coordinate.latitude
        let dLon = target.coordinate.longitude - start.coordinate.longitude
        let dAlt = target.altitude - start.altitude
            
        // Convert to meters NED
        let posN = dLat * 1854 * 60
        let posE = dLon * 1854 * 60 * cos(start.coordinate.latitude/180*Double.pi)
        let posD = -dAlt
        
        // Return NED
        return (posN, posE, posD)
    }
    
    func getXYZYawFromNED(posN: Double, posE: Double, posD: Double, heading: Double = -1)->(Double, Double, Double, Double){
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
        let yawXYZ = getDoubleWithinAngleRange(angle: self.heading - startHeadingXYZ)
        
        
        return(x, y, z, yawXYZ)
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
    }
    
    //**********************************************************************************************
    // Starts the pending mission on startWp. returns false if startWp is not in the pending mission
    // useCurrentMission is needed for continuing current mission after wp action. If set to false,
    // the pending mission will be loaded.
    func gogo(startWp: Int, useCurrentMission: Bool)->Bool{
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
            self.gotoXYZ(refPosX: x, refPosY: y, refPosZ: z, refYawXYZ: yaw, speed: speed)
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
    private func gotoXYZ(refPosX: Double, refPosY: Double, refPosZ: Double, refYawXYZ: Double, speed: Float){
        // Check if horixzontal positions are within geofence  (should X be max 1m?)
        // Function is private, only approved missions will be passed in here.
        //TODO hardconded geofence
        if refPosY > -10 && refPosY < 10 && refPosX > -10 && refPosX < 10{
            self.refPosY = refPosY
            self.refPosX = refPosX
        }
        else{
            print("XYZ position is out of allowed area!")
            return
        }
        
        // TODO, check first, then store value
        self.refPosZ = refPosZ
        if self.refPosZ > -2{
            print("Too low altitude for postion control, refPosZ: " + String(self.refPosZ))
            return
        }
        
        self.refYawXYZ = refYawXYZ
        
        print("gotoXYZ: New ref pos, x:", self.refPosX, ", y: ", self.refPosY, ", z: ", self.refPosZ, ", yawXYZ: ", self.refYawXYZ, ", speed: ", speed)
        // Schedule the timer at 20Hz while the default specified for DJI is between 5 and 25Hz. Timer will execute control commands for a period of time
        duttTimer?.invalidate()
        
        posCtrlTimer?.invalidate()
        posCtrlLoopCnt = 0
        // Make sure noone else is updating the self.refPosXYZ ! TODO
        self.posCtrlTimer = Timer.scheduledTimer(timeInterval: 0.05, target: self, selector: #selector(self.firePosCtrlTimer), userInfo: speed, repeats: true)
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

    //************************************************************************************************************
    // Timer function that loops every x ms until timer is invalidated. Each loop control data (joystick) is sent.
    @objc func fireDuttTimer() {
        loopCnt += 1
        if loopCnt >= loopTarget {
            sendControlData(velX: 0, velY: 0, velZ: 0, yawRate: 0, speed: 0)
            duttTimer?.invalidate()
        }
        else {
            sendControlData(velX: self.refVelX, velY: self.refVelY, velZ: self.refVelZ, yawRate: self.refYawRate, speed: self.defaultXYVel)
        }
    }
    
    @objc func firePosCtrlTimer(_ timer: Timer) {
        
        // TODO, test if speed argument is passed. If not use default speed.
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
                }
                // Note that the current mission is stoppped (paused) if there is a wp action.

                self.setMissionNextWp(num: self.missionNextWp + 1)
                if self.missionNextWp != -1{
                    let (x, y, z, yaw, speed_) = self.getWpXYZYaw(idNum: self.missionNextWp)
                    self.gotoXYZ(refPosX: x, refPosY: y, refPosZ: z, refYawXYZ: yaw, speed: speed_)
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
            // Implement P-controller, position error to ref vel. Rotate aka SimpleMode
            let xDiff: Float = Float(self.refPosX - self.posX)
            let yDiff: Float = Float(self.refPosY - self.posY)
            let zDiff: Float = Float(self.refPosZ - self.posZ)
            guard let checkedHeading = self.getHeading() else {return}
            guard let checkedStartHeading = self.startHeadingXYZ else {return}
            let alphaRad = (checkedHeading - checkedStartHeading)/180*Double.pi

            // Rotate coordinates, calc refvelx, refvely
            self.refVelX =  (xDiff * Float(cos(alphaRad)) + yDiff * Float(sin(alphaRad)))*hPosKP
            self.refVelY = (-xDiff * Float(sin(alphaRad)) + yDiff * Float(cos(alphaRad)))*hPosKP
            
            // Calc refvelz
            self.refVelZ = (zDiff) * vPosKP
            // If velocity get limited the copter will not fly in straight line! Handled in sendControlData

            //Do not concider gimbalYaw in yawControl
            let yawError = getFloatWithinAngleRange(angle: Float(self.yawXYZ - self.refYawXYZ))
            self.refYawRate = -yawError*yawKP
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
}




