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
import SwiftyJSON


class MyLocation: NSObject{
    var speed: Float = 0
    var altitude: Double = 0
    var heading: Double = 0
    var gimbalYaw: Double = 0
    var gimbalYawRelativeToHeading: Double = 0
    var action: String = ""
    var isStartLocation: Bool = false
    var coordinate = MyCoordinate()
    var geoFence = GeoFence()
    var vel = Vel()
    var pos = POS()

    // Reset all values.
    func reset(){
        self.speed = 0
        self.altitude = 0
        self.heading = 0
        self.gimbalYaw = 0
        self.gimbalYawRelativeToHeading = 0
        self.action = ""
        self.isStartLocation = false
        self.coordinate.latitude = 0
        self.coordinate.longitude = 0
        self.geoFence.radius = 0
        self.geoFence.height = [0, 0]
        self.vel.bodyX = 0
        self.vel.bodyY = 0
        self.vel.bodyZ = 0
        self.vel.yawRate = 0
        self.pos.x = 0
        self.pos.y = 0
        self.pos.z = 0
        self.pos.north = 0
        self.pos.east = 0
        self.pos.down = 0
    }
    
    
    /**
     Calculates distance to the wpLocation from the MyLocation it is called from.
     - Parameter wpLocation: A MyLocation object to calc distance to
     - Returns: northing, easting, dAlt, distance2D, distance3D, bearing (degrees)
     */
    func distanceTo(wpLocation: MyLocation)->(Double, Double, Double, Double, Double, Double){
        
        // Lat lon alt deltas
        let dLat = wpLocation.coordinate.latitude - self.coordinate.latitude
        let dLon = wpLocation.coordinate.longitude - self.coordinate.longitude
        let dAlt = wpLocation.altitude - self.altitude
            
        // Convert to meters
        let northing = dLat * 1852 * 60
        let easting =  dLon * 1852 * 60 * cos(wpLocation.coordinate.latitude/180*Double.pi)
        
        // Square
        let northing2 = pow(northing, 2)
        let easting2 = pow(easting, 2)
        let dAlt2 = pow(dAlt, 2)
        
        // Calc distances
        let distance2D = sqrt(northing2 + easting2)
        let distance3D = sqrt(northing2 + easting2 + dAlt2)
        
        // Calc bearing (ref to CopterHelper -> getCourse)
        // Guard division by 0 and calculate: Bearing given northing and easting
        // Case easting == 0, i.e. bearing == 0 or -180
        var bearing: Double = 0
        if easting == 0 {
            if northing > 0 {
                bearing = 0
            }
            else {
                bearing = 180
            }
        }
        else if easting > 0 {
            bearing = (Double.pi/2 - atan(northing/easting))/Double.pi*180
        }
        else if easting < 0 {
            bearing = -(Double.pi/2 + atan(northing/easting))/Double.pi*180
        }
        
        return (northing, easting, dAlt, distance2D, distance3D, bearing)
    }
    
   
   
    // This function should be used from the startMyLocation
    func geofenceOK(wp: MyLocation)->Bool{
        // To make sure function is only used from startlocation.
        if !isStartLocation {
            print("geofence: WP used for reference is not a start location.")
            return false
        }
        let (_, _, dAlt, dist2D, _, _) = self.distanceTo(wpLocation: wp)
        print("geofence: OK, dAlt:", dAlt," dist2D: ", dist2D)

        if dist2D > self.geoFence.radius {
            printToScreen("geofence: Radius violation")
            return false
        }
        if dAlt < self.geoFence.height[0] || self.geoFence.height[1] < dAlt {
            printToScreen("geofence: Height violation")
            return false
        }
        return true
    }
    
    // Set up wp properties
    func setPosition(pos: CLLocation, heading: Double, gimbalYawRelativeToHeading: Double, isStartWP: Bool=false, startWP: MyLocation, completionBlock: ()->Void){
        self.altitude = pos.altitude
        self.heading = heading
        self.gimbalYawRelativeToHeading = gimbalYawRelativeToHeading
        self.gimbalYaw = heading + gimbalYawRelativeToHeading
        self.coordinate.latitude = pos.coordinate.latitude
        self.coordinate.longitude = pos.coordinate.longitude
        self.isStartLocation = isStartWP
        
        // Dont set up XYZ for the startMyLocation it self.
        if self.isStartLocation{
            return
        }
        // If startWP is not setup, return
        if !startWP.isStartLocation {
            print("setPosition: Error, cannot update XYZ without a set start position")
            return
        }
        // Lat-, lon-, alt-diff
        let latDiff = pos.coordinate.latitude - startWP.coordinate.latitude
        let lonDiff = pos.coordinate.longitude - startWP.coordinate.longitude
        let altDiff = pos.altitude - startWP.altitude

        // posN, posE
        let posN = latDiff * 1852 * 60
        let posE = lonDiff * 1852 * 60 * cos(startWP.coordinate.latitude/180*Double.pi)
        self.pos.north = posN
        self.pos.east = posE
        self.pos.down = -altDiff
        
        // X direction definition
        let alpha = (startWP.gimbalYaw)/180*Double.pi

        // Coordinate transformation, from (N, E) to (X,Y)
        self.pos.x =  posN * cos(alpha) + posE * sin(alpha)
        self.pos.y = -posN * sin(alpha) + posE * cos(alpha)
        self.pos.z = -altDiff  // Same as pos.down..
             
        completionBlock()
        // Suitable completionblock:
        // {NotificationCenter.default.post(name: .didPosUpdate, object: nil)}
    }
    
    func setGeoFence(radius: Double, height: [Double]){
        self.geoFence.radius = radius
        self.geoFence.height = height
    }
    
    func setUpFromJsonWp(jsonWP: JSON, defaultSpeed: Float, startWP: MyLocation){
        // Reset all properties
        self.reset()
                
        // Test if mission is LLA
        if jsonWP["lat"].exists(){
            // Mission is LLA
            self.altitude = jsonWP["alt"].doubleValue
            self.heading = jsonWP["heading"].doubleValue
            self.coordinate.latitude = jsonWP["lat"].doubleValue
            self.coordinate.longitude = jsonWP["lon"].doubleValue
        }
        
        // Test if mission NED
        else if jsonWP["north"].exists(){
            // Mission is NED
            let north = jsonWP["north"].doubleValue
            let east = jsonWP["east"].doubleValue
            let down = jsonWP["down"].doubleValue
            // Calc dLat, dLon from north east. Add to start location.
            let dLat = startWP.coordinate.latitude + north/(1852 * 60)
            let dLon = startWP.coordinate.longitude + east/(1852 * 60 * cos(startWP.coordinate.latitude/180*Double.pi))
            self.coordinate.latitude = dLat
            self.coordinate.longitude = dLon
            self.altitude = startWP.altitude - down
            self.heading = jsonWP["heading"].doubleValue
            
        }
        else if jsonWP["x"].exists(){
            // Mission is XYZ
            let x = jsonWP["x"].doubleValue
            let y = jsonWP["y"].doubleValue
            let z = jsonWP["z"].doubleValue
            // First calculate northing and easting.
            let XYZstartHeading = startWP.gimbalYaw
            let beta = -XYZstartHeading/180*Double.pi
            let north = x * cos(beta) + y * sin(beta)
            let east = -x * sin(beta) + y * cos(beta)
            // Calc dLat, dLon from north east. Add to start location
            let dLat = startWP.coordinate.latitude + north/(1852 * 60)
            let dLon = startWP.coordinate.longitude + east/(1852 * 60 * cos(startWP.coordinate.latitude/180*Double.pi))
            self.coordinate.latitude = dLat
            self.coordinate.longitude = dLon
            self.altitude = startWP.altitude - z
            if jsonWP["local_yaw"].doubleValue != -1 {
                self.heading = startWP.gimbalYaw + jsonWP["local_yaw"].doubleValue
                // Make sure heading is within 0-360 range (mainly to avoid -1 which has other meaning)
                if self.heading < 0 {
                    self.heading += 360
                }
                if self.heading > 360 {
                    self.heading -= 360
                }
            }
            else {
                self.heading = -1
            }
        }
        
        // Extract speed
        if jsonWP["speed"].exists(){
            self.speed = jsonWP["speed"].floatValue
        }
        else {
            self.speed = defaultSpeed
        }
        
        // Extract action
        if jsonWP["action"].exists() {
            self.action = jsonWP["action"].stringValue
        }
    }
    
    // Prints text to both statusLabel and error output
    func printToScreen(_ string: String){
        NotificationCenter.default.post(name: .didPrintThis, object: self, userInfo: ["printThis": string])
    }

    func printLocation(sentFrom: String){
        print(sentFrom + ": ",
              "lat: ", self.coordinate.latitude,
              " lon: ", self.coordinate.longitude,
              " alt: ", self.altitude,
              " heading: ", self.heading,
              " gimbalYaw: ", self.gimbalYaw,
              " gimbalYawRelativeToHeading: ", self.gimbalYawRelativeToHeading)
    }
}

// Subclass to MyLocation. Coordinates influenced by CLLocation
class MyCoordinate:NSObject{
    var latitude: Double = 0
    var longitude: Double = 0
}
// SubClass to MyLocation. Geofence properties that are stored in the startMyLocation. Geofence is checked relative to startMyLocation
class GeoFence: NSObject{
    var radius: Double = 0
    var height: [Double] = [0, 0]
}
// SubClass to MyLocation. Body class for body velocities
class Vel: NSObject{
    var bodyX: Float = 0
    var bodyY: Float = 0
    var bodyZ: Float = 0
    var yawRate: Float = 0
}

// SubClass to MyLocation.
class POS: NSObject{
    var x: Double = 0
    var y: Double = 0
    var z: Double = 0
    var north: Double = 0
    var east: Double = 0
    var down: Double = 0
}

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
    
    // **********************************************************************************************************************************************************
    // Set additional lock prevent the lock from beeing released prior to all clients that are using the resource has let go. Specifically made for sdCard access
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
                self.deallocate() // How to break endless loop? Include attemts: int?
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
    var ATT = false
    var XYZ = false
    var photoXYZ = false
    var LLA = false
    var photoLLA = false
    var NED = false
    var WpId = false

    func setATT(bool: Bool){
        ATT = bool
        print("Subscription ATT set to: " + String(describing: bool))
    }

    func setXYZ(bool: Bool){
        XYZ = bool
        print("Subscription XYZ set to: " + String(describing: bool))
    }

    func setPhotoXYZ(bool: Bool){
        photoXYZ = bool
        print("Subscription photoXYZ set to: " + String(describing: bool))
    }

    func setLLA(bool: Bool){
        LLA = bool
        print("Subscription LLA set to: " + String(describing: bool))
    }

    func setPhotoLLA(bool: Bool){
        photoLLA = bool
        print("Subscription photoLLA set to: " + String(describing: bool))
    }

    func setNED(bool: Bool){
        NED = bool
        print("Subscription NED set to: " + String(describing: bool))
    }

    func setWpId(bool: Bool){
        WpId = bool
        print("Subscription WP_ID set to: " + String(describing: bool))
    }
}

class HeartBeat: NSObject{
    var lastBeat = CACurrentMediaTime()
    var degradedLimit: Double = 2               // Time limit for link to be considered degraded
    var lostLimit: Double = 10                  // Time limit for link to be considered lost
    var beatDetected = false                    // Flag for first received heartBeat
    
    func newBeat(){
        if !beatDetected{
            beatDetected = true
        }
        self.lastBeat = CACurrentMediaTime()
    }
    
    func elapsed()->Double{
        return CACurrentMediaTime() - self.lastBeat
    }
    
    func alive()->Bool{
        let elapsedTime = self.elapsed()
        if elapsedTime < degradedLimit{
            return true
        }
        else if elapsedTime < lostLimit{
            print("Link degraded, elapsed time since last heartBeat: ", elapsedTime)
            return true
        }
        else{
            print("Link lost, elapsed time since last heartBeat: ", elapsedTime)
            return false
        }
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


// Struct for declared conformance for squence and following iterator protocol. Returns sequence n, n-1, ... 0
struct Countdown: Sequence, IteratorProtocol {
    var count: Int

    mutating func next() -> Int? {
        if count == -1 {
            return nil
        } else {
            defer { count -= 1 }  // defer: Fancy way of reducing counter after count has been returned, can be used to guarantee things are not forgotten. Google it :)
            return count
        }
    }
}


