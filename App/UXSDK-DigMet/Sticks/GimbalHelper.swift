//
//  GimbalHelper.swift
//  UXSDK-DigMet
//
//  Created by Andreas Gising on 2020-09-29.
//  Copyright © 2020 DJI. All rights reserved.
//

import Foundation
import DJIUXSDK 

class Gimbal{
    var gimbal: DJIGimbal?
    var pitchRangeExtensionSet = false
    

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
        
        // Should check of gimbal can be controlled aka selftest. getYawRelativeToAircaftHeading() returns nil of the init of gimbal fails (motor blocked?)
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
    
    // **********************************************************
    // Get the gimbal yaw relative to aircraft heading. Tested ok
    func getYawRelativeToAircaftHeading()->Double?{
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
            print("gimbal relative yaw returning: " + String(describing: yawRelativeToAircraftHeading))
            return yawRelativeToAircraftHeading
        }
     return nil
    }


    // ********************************************
    // Get gimbal pitch Attitude always returns nil
    func getGimbalPitchAtt()->DJIGimbalAttitude?{
        guard let gimbalStateKey = DJIGimbalKey(param: DJIGimbalParamAttitudeInDegrees) else {
            NSLog("Couldn't create the key")
            return nil
        }

        guard let keyManager = DJISDKManager.keyManager() else {
            print("Couldn't get the keyManager, are you registered")
            return nil
        }
                
        if let gimbalStateValue = keyManager.getValueFor(gimbalStateKey){
            if let attitude = gimbalStateValue.value as? DJIGimbalAttitude{
                print("Attitude.pitch is: " + String(attitude.pitch))
                return attitude
            }
            else{
                print("Error: getGimbalPitchCode ends up here")
            }
        }
        else{
            _ = "Does not end up here"
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
                    print("Gimbal feature is available: ", key, ", min: ", minMax.min, ", max: ", minMax.max)
                }
            }
            if theType == DJIParamCapability.self{
                let capability = value as! DJIParamCapability
                print("Status of gimbal feature ", key, "is :", capability.isSupported)
            }
        }
    }
    
    
}
