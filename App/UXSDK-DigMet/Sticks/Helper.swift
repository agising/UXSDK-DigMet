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
    var allocated = false
    var owner = ""
    var name = ""
    var dateAllocated = Date()
    var maxTime = Double(0)
    var auxOccupier = false // Monitor reading to sdCard, update auxOccupier. Allocator will not deallocate until auxOccupier is true.
    
    init(name: String){
        self.name = name
    }
    
    // ******************************************************************************************************************************************
    // Set additional lock prevent the lock from beeing released prior to all clients are using the resource. Specifically made for sdCard access
    func setAuxOccopier(boolValue: Bool){
        self.auxOccupier = boolValue
        print("sdCard occupied: " + String(describing: boolValue))
    }
    
    // *****************************************************************
    // Allocate a resource, if it is available or if max-time has passed
    func allocate(_ owner: String, maxTime: Double)->Bool{
        // Check if it is rightfully allocated
        if self.allocated{
            if self.maxTime > self.timeAllocated(){
                // Resource is rightfully allocated
                let tempStr = self.name + "Allocator : Resource occupied by " + self.owner + ", " + owner + "tried to occupy"
                print(tempStr)
                return false
            }
            print(self.name + "Allocator : Forcing allocation from " + self.owner)
        }
        // Resource is not rightfully allocated -> Allocate it!
        self.allocated = true
        self.owner = owner
        self.dateAllocated = Date()
        self.maxTime = maxTime
        self.auxOccupier = false
        return true
    }
    
    
    func deallocate(){
        if self.auxOccupier {
            Dispatch.background{
                do{
                    //print("Sleeping for 0.1s")
                    usleep(100000)
                }
                _ = self.deallocate() // How to break endless loop? Include attemts: int?
            }
        }
        else{
            print("Resource was busy for " + String(self.timeAllocated()) + "by: " + self.owner)
            self.allocated = false
            self.owner = ""
            
        }
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
    var photoXYZ = false
    var WpId = false
    
    func setXYZ(bool: Bool){
        XYZ = bool
        print("Subscription XYZ set to: " + String(describing: bool))
    }

    func setPhotoXYZ(bool: Bool){
        photoXYZ = bool
        print("Subscription photoXYZ set to: " + String(describing: bool))
    }
    
    func setWpId(bool: Bool){
        WpId = bool
        print("Subscription WP_ID set to: " + String(describing: bool))
    }

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


// *************************************
// Returns Int angle in range [-180 180]
func getIntWithinAngleRange(angle: Int)->Int{
    var angle2 = angle % 360
    if angle2 > 180 {
        angle2 -= 360
    }
    if angle2 < -180 {
        angle2 += 360
    }
    return angle2
}

// *************************************
// Returns Int angle in range [-180 180]
func getDoubleWithinAngleRange(angle: Double)->Double{
    var angle2 = angle.truncatingRemainder(dividingBy: 360)
    if angle2 > 180 {
        angle2 -= 360
    }
    if angle2 < -180 {
        angle2 += 360
    }
    return angle2
}

// ***************************************
// Returns Float angle in range [-180 180]
func getFloatWithinAngleRange(angle: Float)->Float{
    var angle2 = angle.truncatingRemainder(dividingBy: 360)
    if angle2 > 180 {
        angle2 -= 360
    }
    if angle2 < -180 {
        angle2 += 360
    }
    return angle2
}


// To be a camera class


