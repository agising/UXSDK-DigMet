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

class Copter {
    var flightController: DJIFlightController?
    var state: DJIFlightControllerState?
    
    var missionGeoFenceX: [Double] = [-5, 5]
    var missionGeoFenceY: [Double] = [-5, 5]
    var missionGeoFenceZ: [Double] = [-20, -2]
    
    var pendingMission = JSON()
    var mission = JSON()
    var missionNextWp = -1
    var missionNextWpId = "id-1"
    var missionIsActive = false

    var posX: Double = 0
    var posY: Double = 0
    var posZ: Double = 0
    
    var velX: Double = 0
    var velY: Double = 0
    var velZ: Double = 0
    
    var ref_posX: Double = 0
    var ref_posY: Double = 0
    var ref_posZ: Double = 0
    var ref_yaw: Float = 0.0
    
    var ref_velX: Float = 0.0
    var ref_velY: Float = 0.0
    var ref_velZ: Float = 0.0
    var ref_yawRate: Float = 0.0
    
    var xyVelLimit: Float = 350 // cm/s horizontal speed
    var zVelLimit: Float = 150 // cm/s vertical speed
    var yawRateLimit:Float = 10 // deg/s, defensive.

    var pos: CLLocation?
    var startHeading: Double?
    var homeLocation: CLLocation?
    var dssHome: CLLocation?
    var dssHomeHeading: Double?

    
    var _operator: String = "USER"

    var duttTimer: Timer?
    var posCtrlTimer: Timer?
    var trackingRecord: Int = 0         // Consequtive loops on correct position
    let trackingRecordTarget: Int = 8  // Consequtive loops tracking target
    let trackingPosLimit = 0.3          // Pos error requirement for tracking wp
    let trackingVelLimit = 0.1          // Vel error requirement for tracking wp NOT USED
    let sampleTime: Double = 50         // Sample time in ms
    let controlPeriod: Double = 1500    // Number of millliseconds to send command
    var loopCnt: Int = 0
    var loopTarget: Int = 0
    var posCtrlLoopCnt: Int = 0
    var posCtrlLoopTarget: Int = 200
    private let hPosKP: Float = 0.9     // Test KP 2!
    private let vPosKP: Float = 1
    private let vVelKD: Float = 0
    
    
    // Init
    //init(controlPeriod: Double, sampleTime: Double){
    init(){
    // Calc number of loops for dutt cycle
        loopTarget = Int(controlPeriod / sampleTime)
        self.state = DJIFlightControllerState()
    }

        //*************************************
    // Start listening for position updates
    func startListenToVel(){
        guard let locationKey = DJIFlightControllerKey(param: DJIFlightControllerParamVelocity) else {
            NSLog("Couldn't create the key")
            return
        }

        guard let keyManager = DJISDKManager.keyManager() else {
            print("Couldn't get the keyManager, are you registered")
            return
        }

        keyManager.startListeningForChanges(on: locationKey, withListener: self, andUpdate: { (oldValue: DJIKeyedValue?, newValue: DJIKeyedValue?) in
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
                guard let home = self.getHomeLocation() else {return}
                guard let checkedStartHeading = self.startHeading else {return}
                
                let lat_diff = self.pos!.coordinate.latitude - home.coordinate.latitude
                let lon_diff = self.pos!.coordinate.longitude - home.coordinate.longitude

                let posN = lat_diff * 1854 * 60
                let posE = lon_diff * 1854 * 60 * cos(home.coordinate.latitude/180*Double.pi)
                let alt = self.pos!.altitude
                
                let alpha = checkedStartHeading/180*Double.pi

                // Coordinate transformation, from (E,N) to (y,x)
                self.posX =  posN * cos(alpha) + posE * sin(alpha)
                self.posY = -posN * sin(alpha) + posE * cos(alpha)
                self.posZ = -alt
                
                NotificationCenter.default.post(name: .didPosUpdate, object: nil)
            }
        })
    }

    //************************************
    // Stop listening for position updates
    func stopListenToPos(){
        guard let locationKey = DJIFlightControllerKey(param: DJIFlightControllerParamAircraftLocation) else {
            NSLog("Couldn't create the key")
            return
        }

        guard let keyManager = DJISDKManager.keyManager() else {
            print("Couldn't get the keyManager, are you registered")
            return
        }
        
        keyManager.stopListening(on: locationKey, ofListener: self)
    
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
                self.startHeading = self.getHeading()
                self.homeLocation = (checkedNewValue.value as! CLLocation)
                self.startListenToPos()
                self.startListenToVel()
                print("Home location has been updated, caught by listener")
            }
        })
    }
    
    func saveCurrentPosAsDSSHome(){
        self.dssHomeHeading = getHeading()
        self.dssHome = getCurrentLocation()
    }
    
    //*************************************
    // Get home location as location object
    func getHomeLocation()->CLLocation?{
        // Start listen to home location instead
        guard let locationKey = DJIFlightControllerKey(param: DJIFlightControllerParamHomeLocation) else {
            NSLog("Couldn't create the key")
            return nil
        }

        guard let keyManager = DJISDKManager.keyManager() else {
            print("Couldn't get the keyManager, are you registered")
            return nil
        }
                
        if let locationValue = keyManager.getValueFor(locationKey) {
            let homeLocation = locationValue.value as! CLLocation
            self.homeLocation = homeLocation
            return homeLocation
        }
     return nil
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
    
    //
    // Get gimbal pitch Attitude DOES NOT WORK
    func getGimbalPitchAtt()->DJIGimbalAttitude?{
        guard let gimbalAttitudeKey = DJIGimbalKey(param: DJIGimbalParamAttitudeInDegrees) else {
            NSLog("Couldn't create the key")
            return nil
        }

        guard let keyManager = DJISDKManager.keyManager() else {
            print("Couldn't get the keyManager, are you registered")
            return nil
        }
                
        if let attitudeValue = keyManager.getValueFor(gimbalAttitudeKey) {
            let attitude = attitudeValue.value as! DJIGimbalAttitude
            return attitude
        }
     return nil
    }
    
    //
    // Get gimbal pitch Rotate DOES NOT WORK
    func getGimbalPitchRot()->DJIGimbalRotation?{
        guard let gimbalRotateKey = DJIGimbalKey(param: DJIGimbalParamRotate) else {
            NSLog("Couldn't create the key")
            return nil
        }

        guard let keyManager = DJISDKManager.keyManager() else {
            print("Couldn't get the keyManager, are you registered")
            return nil
        }
                
        if let rotationValue = keyManager.getValueFor(gimbalRotateKey) {
            let rotation = rotationValue.value as! DJIGimbalRotation
            return rotation
        }
     return nil
    }
    
    
    //****************
    // Tester function
    func stateTest(){
        if let gimbalAttitude = self.getGimbalPitchAtt(){
            print("Gimbal pitch: (ATT)" + String(describing: gimbalAttitude.pitch))
        }
        
        if let gimbalRotation = self.getGimbalPitchRot(){
            print("Gimbal pitch (ROT): " + String(describing: gimbalRotation.pitch))
        }
        
        if let home = self.getHomeLocation(){
            print("Home location lat: " + String(describing: home.coordinate.latitude))
        }

        if let currLocation = self.getCurrentLocation(){
            print("Current location lat: " + String(describing: currLocation.coordinate.latitude))
        }

    }
    
    // TODO, is this used and/or still ok?
    func getPos(){
        guard let home = getHomeLocation() else {return}
        guard let curr = getCurrentLocation() else {return}
        guard let startHeading = self.startHeading else {return}
        _ = startHeading

        let lat_diff = curr.coordinate.latitude - home.coordinate.latitude
        let lon_diff = curr.coordinate.longitude - home.coordinate.longitude

        let posN = lat_diff * 1854 * 60
        let posE = lon_diff * 1854 * 60 * cos(home.coordinate.latitude)
        let posD = curr.altitude
        
        let distance = curr.distance(from: home).magnitude
        print("posN: " + String(posN) + ", posE: " + String(posE), ", posD: " + String(posD) + ", Distance: " + String(describing: distance))
    }
    
    

    
    //************************
    // Set up reference frames
    func initFlightController(){
        // Default the coordinate system to body and reference yaw to heading
        self.flightController?.setFlightOrientationMode(DJIFlightOrientationMode.aircraftHeading, withCompletion: { (error: Error?) in
            if error == nil{
                print("Orientation mode set")
            }
            else{
                print("Orientation mode not set: " + error.debugDescription)
            }
        })

        // Set properties of VirtualSticks
        self.flightController?.rollPitchCoordinateSystem = DJIVirtualStickFlightCoordinateSystem.body
        self.flightController?.yawControlMode = DJIVirtualStickYawControlMode.angularVelocity
        self.flightController?.rollPitchControlMode = DJIVirtualStickRollPitchControlMode.velocity
        self.state = DJIFlightControllerState()
        //self.flightController?.delegate?.flightController?(self.flightController!, didUpdate: self.state!)
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
        sendControlData(velX: 0, velY: 0, velZ: 0, yawRate: 0)
    }
    
    //********************************
    // Disable the virtual sticks mode
    func stickDisable(){
        stop()
        self.flightController?.setVirtualStickModeEnabled(false, withCompletion: { (error: Error?) in
            if error == nil{
                print("Sticks disabled")
            }
            else{
                print("StickDisable: Virtual stick mode change did not go through" + error.debugDescription)
            }
        })
    }

    //**************************************************************
    // Enable the virtual sticks mode and reset reference velocities
    func stickEnable(){
        // Reset any speed set, think about YAW -> Todo!
        ref_velX = 0
        ref_velY = 0
        ref_velZ = 0
        //let temp: Double = self.flightController?.compass?.heading   returns optionalDouble, i want Float..
        ref_yaw = 0

        // Set flight controller mode
        self.flightController?.setVirtualStickModeEnabled(true, withCompletion: { (error: Error?) in
            if error == nil{
                print("Sticks enabled")
            }
            else{
                print("StickEnable: Virtual stick mode change did not go through" + error.debugDescription)
            }
        })
    }
    
    func dutt(x: Float, y: Float, z: Float, yawRate: Float){
        // limit to max
        self.ref_velX = limitToMax(value: x, limit: xyVelLimit/100)
        self.ref_velY = limitToMax(value: y, limit: xyVelLimit/100)
        self.ref_velZ = limitToMax(value: z, limit: zVelLimit/100)
        self.ref_yawRate = limitToMax(value: yawRate, limit: yawRateLimit)
        
        // Schedule the timer at 20Hz while the default specified for DJI is between 5 and 25Hz. DuttTimer will execute control commands for a period of time
        posCtrlTimer?.invalidate() // Cancel any posControl
        duttTimer?.invalidate()
        loopCnt = 0
        duttTimer = Timer.scheduledTimer(timeInterval: sampleTime/1000, target: self, selector: #selector(fireDuttTimer), userInfo: nil, repeats: true)
       }
    
    //***************************************************************************************************************
    // Send controller data (joystick). Called from fireTimer that send commands every x ms. Stop timer to stop commands.
    func sendControlData(velX: Float, velY: Float, velZ: Float, yawRate: Float) {
        //print("Sending x: \(velX), y: \(velY), z: \(velZ), yaw: \(yawRate)")
       
//        controlData.verticalThrottle = velZ // in m/s
//        controlData.roll = velX
//        controlData.pitch = velY
//        controlData.yaw = yawRate
      
        // Check horizontal spped and reduce both proportionally
        let horizontalVel = sqrt(velX*velX + velY*velY)
        let limitedHorizontalVel = limitToMax(value: horizontalVel, limit: xyVelLimit/100)
        var factor: Float = 1
        if limitedHorizontalVel < horizontalVel{
            factor = limitedHorizontalVel/horizontalVel
        }
        
        // Make sure velocity limits are not exceeded.
        let limitedVelX = factor * velX
        let limitedVelY = factor * velY
        let limitedVelZ = limitToMax(value: velZ, limit: zVelLimit/100)
        let limitedYawRate = limitToMax(value: velX, limit: xyVelLimit/100)
                
        // Construct the flight control data object. Roll axis is pointing forwards but we use velocities..
        var controlData = DJIVirtualStickFlightControlData()
        controlData.verticalThrottle = -limitedVelZ
        controlData.roll = limitedVelX
        controlData.pitch = limitedVelY
        controlData.yaw = limitedYawRate
        
        
        // Send the control data to the FC
        self.flightController?.send(controlData, withCompletion: { (error: Error?) in
           // There's an error so let's stop (What happens with last sent command..?
            if error != nil {
                print("Error sending control data from position controller")
                // Disable the timer
                self.duttTimer?.invalidate()
                //self.loopCnt = 0
                self.posCtrlTimer?.invalidate()
                //self.posCtrlLoopCnt = 0
            }
           
        })
    }
    
    func takeOff(){
        self.flightController?.startTakeoff(completion: {(error: Error?) in
            if error != nil{
                print("Takeoff error: " + String(error.debugDescription))
            }
            else{
                _ = 1
            }
            
        })
    }
    
    func land(){
        self.flightController?.startLanding(completion: {(error: Error?) in
            if error != nil{
                print("Takeoff error: " + String(error.debugDescription))
            }
            else{
                _ = 1
            }
            
        })
    }
    
    func wpFence(wp: JSON)->Bool{
        return true
    }
    
    func uploadMissionXYZ(mission: JSON)->(success: Bool, arg: String?){
        // For the number of wp-keys, check that there is a matching wp id and that the geoFence is not violated
        var wpCnt = 0
        for (_,subJson):(String, JSON) in mission {
            // Check wp-numbering
            if mission["id" + String(wpCnt)].exists()
            {
                // Check for geofence violation
                guard withinLimit(value: subJson["x"].doubleValue, lowerLimit: missionGeoFenceX[0], upperLimit: missionGeoFenceX[1]) else {return (false, "GeofenceX")}
                guard withinLimit(value: subJson["y"].doubleValue, lowerLimit: missionGeoFenceY[0], upperLimit: missionGeoFenceY[1]) else {return (false, "GeofenceY")}
                guard withinLimit(value: subJson["z"].doubleValue, lowerLimit: missionGeoFenceZ[0], upperLimit: missionGeoFenceZ[1]) else {return (false, "GeofenceZ")}
                // Check speed in mission thread
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
    
    func getWPXYZ(num: Int)->(Double, Double, Double){
        let id = "id" + String(num)
        let x = self.mission[id]["x"].doubleValue
        let y = self.mission[id]["y"].doubleValue
        let z = self.mission[id]["z"].doubleValue
        return(x, y, z)
    }

    
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
    
    func gogoXYZ(startWp: Int){
        if self.pendingMission["id" + String(startWp)].exists(){
            
            // invalidate and such..
            
            self.mission = self.pendingMission
            self.missionNextWp = startWp
            self.missionIsActive = true
            
            let (x, y, z) = getWPXYZ(num: startWp)
            gotoXYZ(refPosX: x, refPosY: y, refPosZ: z)
        }
    }
    
    //**********************************************************************************
    // Function that sets reference position and executes the position controller timer.
    private func gotoXYZ(refPosX: Double, refPosY: Double, refPosZ: Double){
        // start in Y only
        // Check if horixzontal positions are within geofence  (should X be max 1m?)
        // Function is private, only approved missions will be passed in here.
        print("gotoXYZ: " + String(refPosX) + String(refPosY) + String(refPosZ))
        if refPosY > -10 && refPosY < 10{
            self.ref_posY = refPosY
        }
        else if refPosX > -10 && refPosX < 10{
            self.ref_posX = refPosX
        }
        else{
            print("XYZ position is out of allowed area!")
            return
        }
        
        self.ref_posZ = refPosZ
        if self.ref_posZ > -10{
            print("Too low altitude for postion control: " + String(self.ref_posX) + String(self.ref_posY) + String(self.ref_posZ))
            return
        }
        
        // Schedule the timer at 20Hz while the default specified for DJI is between 5 and 25Hz. Timer will execute control commands for a period of time
        duttTimer?.invalidate()
        //loopCnt = 0
        
        posCtrlTimer?.invalidate()
        posCtrlLoopCnt = 0
        // Make sure noone else is updating the self.refPosXYZ ! TODO
        // Set fix timeinterval
//        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: {
            self.posCtrlTimer = Timer.scheduledTimer(timeInterval: 0.05, target: self, selector: #selector(self.firePosCtrlTimer), userInfo: nil, repeats: true)
  //      })
    }
    
    //********************************************************************************************
    // Algorithm for determining of a wp is tracked or not. When tracked the mission can continue.
    func trackingWP(posLimit: Double, velLimit: Double)->Bool{
        
        let x2 = pow(self.ref_posX - self.posX, 2)
        let y2 = pow(self.ref_posY - self.posY, 2)
        let z2 = pow(self.ref_posZ - self.posZ, 2)
        let posError = sqrt(x2 + y2 + z2)
        if posError < posLimit{
            trackingRecord += 1
            print("tracking")
        }
        else{
            trackingRecord = 0
        }
        if trackingRecord >= trackingRecordTarget{
            return true
        }
        else{
            return false
        }
    }
}

extension Copter{
    //************************************************************************************************************
    // Timer function that loops every x ms until timer is invalidated. Each loop control data (joystick) is sent.
   
    @objc func fireDuttTimer() {
        loopCnt += 1
        if loopCnt >= loopTarget {
            sendControlData(velX: 0, velY: 0, velZ: 0, yawRate: 0)
            duttTimer?.invalidate()
        }
        else {
            sendControlData(velX: self.ref_velX, velY: self.ref_velY, velZ: self.ref_velZ, yawRate: self.ref_yawRate)
        }
    }
    
    @objc func firePosCtrlTimer() {
        posCtrlLoopCnt += 1
        // If we arrived

        if trackingWP(posLimit: trackingPosLimit, velLimit: trackingVelLimit){
            sendControlData(velX: 0, velY: 0, velZ: 0, yawRate: 0)
            
            // if we are on a mission
            if self.missionIsActive{
                print("Mission is active")
                self.setMissionNextWp(num: self.missionNextWp + 1)
                if self.missionNextWp != -1{
                    let (x, y, z) = self.getWPXYZ(num: self.missionNextWp)
                    self.gotoXYZ(refPosX: x, refPosY: y, refPosZ: z)
                }
                else{
                    print("id is -1")
                    self.missionIsActive = false
                    self.posCtrlTimer?.invalidate() // dont fire timer again
                }
                print("if stream: Publish next wp id :" + String(self.missionNextWpId))
            }
        }
            
        // The controller
        else{
            // Implement P-controller, position error to ref vel. Rotate aka SimpleMode
            let x_diff: Float = Float(self.ref_posX - self.posX)
            let y_diff: Float = Float(self.ref_posY - self.posY)
            let z_diff: Float = Float(self.ref_posZ - self.posZ)
 
            guard let checkedHeading = self.getHeading() else {return}
            guard let checkedStartHeading = self.startHeading else {return}
            let alpha = Float((checkedHeading - checkedStartHeading)/180*Double.pi)
            
        
            self.ref_velX =  (x_diff * cos(alpha) + y_diff * sin(alpha))*hPosKP
            self.ref_velY = (-x_diff * sin(alpha) + y_diff * cos(alpha))*hPosKP
            
            self.ref_velZ = (z_diff) * vPosKP
            // If velocity get limited the copter will not fly in straight line! Handled in sendControlData
            

            sendControlData(velX: self.ref_velX, velY: self.ref_velY, velZ: self.ref_velZ, yawRate: 0)
        }
        
        // For safety during testing..
        if posCtrlLoopCnt >= posCtrlLoopTarget{
            sendControlData(velX: 0, velY: 0, velZ: 0, yawRate: 0)

            NotificationCenter.default.post(name: .didPrintThis, object: self, userInfo: ["printThis": "Position controller max time exeeded"])
            
            posCtrlTimer?.invalidate()
        }
    }
}



