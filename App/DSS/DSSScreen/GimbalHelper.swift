//
//  GimbalHelper.swift
//  UXSDK-DigMet
//
//  Created by Andreas Gising on 2020-09-29.
//  Copyright © 2020 DJI. All rights reserved.
//

import Foundation
import DJIUXSDK

class GimbalController: NSObject, DJIGimbalDelegate{
    var gimbal: DJIGimbal?
    var pitchRangeExtensionSet = false
    
    var gimbalPitch: Float? = nil
    var yawRelativeToAircraftHeading: Double? = nil

    // *******************************************
    // Init the gimbal, set pitch range extension.
    func initGimbal(){
        self.gimbal?.setPitchRangeExtensionEnabled(true, withCompletion: {(error: Error?) in
            if error != nil {
                NotificationCenter.default.post(name: .didPrintThis, object: self, userInfo: ["printThis": "Error: Gimbal range extension :" + String(describing: error)])
            }
        })

        // Have to dispatch in order for change to fall through before checking it
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: {
            self.gimbal?.getPitchRangeExtensionEnabled(completion: {(success: Bool, error: Error?) in
                self.pitchRangeExtensionSet = success
            })
        })
        
        
        gimbal!.delegate = self
                
        // Should check of gimbal can be controlled aka selftest. getYawRelativeToAircaftHeading() returns nil of the init of gimbal fails (motor blocked?)
    }
    
    
    //**************************************************
    // The gimbal delegate function
    func gimbal(_ gimbal: DJIGimbal, didUpdate state: DJIGimbalState) {
        gimbalPitch = state.attitudeInDegrees.pitch
        yawRelativeToAircraftHeading = state.yawRelativeToAircraftHeading
    }

    
    //***************************
    // Set the gimbal pitch value
    func setPitch(pitch: Double){
        // Check if rangeExtension for gimbal has been set sucessfully
        if self.pitchRangeExtensionSet != true{
            initGimbal()
            NotificationCenter.default.post(name: .didPrintThis, object: self, userInfo: ["printThis": "Gimbal range extension not set, trying to set again"])
        }
        
        // Create a DJIGimbalRotaion object
        let gimbal_rotation = DJIGimbalRotation(pitchValue: pitch as NSNumber, rollValue: 0, yawValue: 0, time: 1, mode: DJIGimbalRotationMode.absoluteAngle, ignore: true)
        // Feed rotate object to Gimbal method rotate
        self.gimbal?.rotate(with: gimbal_rotation, completion: { (error: Error?) in
            if error != nil {
                NotificationCenter.default.post(name: .didPrintThis, object: self, userInfo: ["printThis": "Error: Gimbal rotation :" + String(describing: error)])
            }
        })
    }
    
    
    // **************************************************************************************************
    // Get the gimbal yaw relative to aircraft heading. Tested ok. Handeled by the delegate funciton now.
    func getYawRelativeToAircraftHeading()->Double?{
        guard let gimbalStateKey = DJIGimbalKey(param: DJIGimbalParamAttitudeYawRelativeToAircraft) else {
            NSLog("Couldn't create the key")
            return nil
        }

        guard let keyManager = DJISDKManager.keyManager() else {
            print("Couldn't get the keyManager, are you registered")
            return nil
        }
                
        if let gimbalStateValue = keyManager.getValueFor(gimbalStateKey) {
            let yawRelativeToAircraftHeading = gimbalStateValue.value as? Double
            return yawRelativeToAircraftHeading
        }
     return nil
    }


    // ************************************************************************************
    // Get gimbal pitch Attitude always returns nil. Handeled by the delegate function now.
    func getGimbalPitch()->DJIGimbalAttitude?{
        guard let gimbalAttitudeKey = DJIGimbalKey(param: DJIGimbalParamAttitudeInDegrees) else {
            NSLog("Couldn't create the key")
            return nil
        }

        guard let keyManager = DJISDKManager.keyManager() else {
            print("Couldn't get the keyManager, are you registered")
            return nil
        }
                
        if let gimbalAttitudeValue: DJIKeyedValue = keyManager.getValueFor(gimbalAttitudeKey){
            if let gimbalAttitude = gimbalAttitudeValue.value as? DJIGimbalAttitude{
                print("Attitude.pitch is: " + String(gimbalAttitude.pitch))
                return gimbalAttitude
            }
            else{
                print("Error: getGimbalPitchCode ends up here")
            }
        }
        else{
            print("Code does not end up here")
        }
        return nil
    }

    
    // ****************************
    // Print the gimbal capabilites
    func printGimbalCapabilities(){
        let capabilities = self.gimbal?.capabilities
        for (key, value) in capabilities!{
            //print(key,value)
            let theType = type(of: value)
            if theType == DJIParamCapabilityMinMax.self{
                let minMax = value as! DJIParamCapabilityMinMax
                if minMax.max == nil{
                    print("Gimbal feature is not available: ", key)
                }
                else{
                    print("Gimbal feature is available: ", key, ", min: ", minMax.min.description, ", max: ", minMax.max.description)
                }
            }
            if theType == DJIParamCapability.self{
                let capability = value as! DJIParamCapability
                print("Status of gimbal feature ", key, "is :", capability.isSupported)
            }
        }
    }
}
