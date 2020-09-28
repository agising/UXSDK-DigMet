//
//  Helpers.swift
//  UXSDK-DigMet
//
//  Created by Andreas Gising on 2020-09-21.
//  Copyright © 2020 DJI. All rights reserved.
//

import Foundation
import UIKit
import Photos
import DJIUXSDK

//
// Class to use for allocation of resources, like camera, gimbal, etc.
class Allocator: NSObject{
    private var allocated = false
    private var owner = ""
    private var name = ""
    private var dateAllocated = Date()
    private var maxTime = Double(0)
    
    init(name: String){
        self.name = name
    }
    
    func allocate(_ owner: String, maxTime: Double)->Bool{
        // Check if it is rightfully allocated
        if self.allocated{
            if self.maxTime > self.timeAllocated(){
                // Resource is rightfully allocated
                let tempStr = self.name + "-Allocator : Resource occupied by " + self.owner + ", " + owner + "tried to occupy"
                print(tempStr)
                return false
            }
            print(self.name + "-Allocator : Forcing allocation from " + self.owner)
        }
        // Resource is not rightfully allocated -> Allocate it!
        self.allocated = true
        self.owner = owner
        self.dateAllocated = Date()
        self.maxTime = maxTime
        return true
    }
    
    
    func deallocate(){
        print("Resource was busy for " + String(self.timeAllocated()) + "by: " + self.owner)
        self.allocated = false
        self.owner = ""
    }

    func timeAllocated()->Double{
        if self.allocated{
            // timeIntervalSinceNow returns a negative time in seconds. This function returns positive value.
            return -dateAllocated.timeIntervalSinceNow
        }
        else{
            return Double(0)
        }
    }
}

class Subscriptions: NSObject{
    var XYZ = false
    var image_XYZ = false
}


// https://www.hackingwithswift.com/books/ios-swiftui/how-to-save-images-to-the-users-photo-library
class imageSaver: NSObject {
    func writeToPhotoAlbum(image: UIImage) {
        UIImageWriteToSavedPhotosAlbum(image, self, #selector(saveError), nil)
    }
    @objc func saveError(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer) {
        print("Save Finished")
    }
}


//*****************************************************************************
// Load an image from the photo library. Seems to be loaded with poor resolution
func loadUIImageFromPhotoLibrary() -> UIImage? {
    // https://stackoverflow.com/questions/29009621/url-of-image-after-uiimagewritetosavedphotosalbum-in-swift
    // https://www.hackingwithswift.com/forums/swiftui/accessing-image-exif-data-creation-date-location-of-an-image/1429
    let fetchOptions: PHFetchOptions = PHFetchOptions()
    fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
    let fetchResult = PHAsset.fetchAssets(with: PHAssetMediaType.image, options: fetchOptions)
    if (fetchResult.firstObject != nil) {
        let lastAsset: PHAsset = fetchResult.lastObject!
        print("Previewing image from path")
        return lastAsset.image // use result: self.previewImageView.image = loadUIImageFromPhotoLibrary()
    }
    else{
        return nil
    }
}

//********************************
// Save an UIImage to Photos album
func saveUIImageToPhotosAlbum(image: UIImage){
    let imageSaverHelper = imageSaver()
    imageSaverHelper.writeToPhotoAlbum(image: image)
}


// Gimbal stuff
// Print the gimbal capabilites. Call like so: printGimbalCapabilities(theGimbal: self.gimbal)
func printGimbalCapabilities(theGimbal: DJIGimbal?){
    let capabilities = theGimbal?.capabilities
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
            let cap = value as! DJIParamCapability
            print("Status of gimbal feature ", key, "is :", cap.isSupported)
        }
    }
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
        return yawRelativeToAircraftHeading
    }
 return nil
}


//
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
            return attitude
        }
    }
 return nil
}
// Call safely like this
//let gState:DJIGimbalAttitude? = getGimbalPitchAtt()
//
//       self.printSL("gimbal pithc: " + String(describing: gState.debugDescription))
//       if let gPitch = gState?.pitch{
//           print("Pitch is: ", gPitch)
//       }
//       else{
//           print("Pitch is nil")
//       }




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
