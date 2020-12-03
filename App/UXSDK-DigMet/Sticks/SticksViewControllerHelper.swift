//
//  SticksViewControllerHelper.swift
//  UXSDK-DigMet
//
//  Created by Andreas Gising on 2020-08-31.
//  Copyright © 2020 DJI. All rights reserved.
//

import UIKit

// Store ugly notes somewhere else..


//
//                           self.saveImageDataToApp(imageData: imageData, filename: files[index].fileName)
//                           //let image = UIImage(data: imageData)
//                           //self.lastImage = image!
//                           //self.lastImageFilename = files[index].fileName
//                           //self.printSL("UIImage saved to self, showing image preview. Filename:" + self.lastImageFilename)
//                           completionHandler(true)
//                           }

// If json is .Dictionary
//for (wp,subJson):(String, JSON) in mission {
//    print(wp)
//    for(property,arg):(String, JSON) in subJson{
//        print(property + ": " + arg.stringValue)
//    }
//}

    
//    //************************************
//    // Tested ok, but not in use anymore..
//    // ***********************************
//
//    // Store an UIImage to filename (.png will be added). Full path is returned (and written to self.lastImageURL
//    func saveUIImageToAppPNG(image: UIImage, filename: String) -> String {
//        //// Code gives an ur to the unsaved image.
//        // https://stackoverflow.com/questions/29009621/url-of-image-after-uiimagewritetosavedphotosalbum-in-swift
//        let png = NSData(data: image.pngData()!)
//        let paths = NSSearchPathForDirectoriesInDomains(FileManager.SearchPathDirectory.documentDirectory, FileManager.SearchPathDomainMask.userDomainMask, true)
//        let docs: String = paths[0]
//        let fullPath = docs + filename + ".png"
//        self.lastImageURL = fullPath
//        self.printSL(fullPath)
//        png.write(toFile: fullPath, atomically: true)
//        return fullPath
//    }
//
//    // Store an UIImage to filename (.png will be added). Full path is returned (and written to self.lastImageURL
//    func saveUIImageToAppJPG(image: UIImage, filename: String) -> String {
//        //// Code gives an ur to the unsaved image.
//        // https://stackoverflow.com/questions/29009621/url-of-image-after-uiimagewritetosavedphotosalbum-in-swift
//        let png = NSData(data: image.jpegData(compressionQuality: 0.3)!)
//
//        let paths = NSSearchPathForDirectoriesInDomains(FileManager.SearchPathDirectory.documentDirectory, FileManager.SearchPathDomainMask.userDomainMask, true)
//        let docs: String = paths[0]
//        let fullPath = docs + filename + ".JPG"
//        self.lastImageURL = fullPath
//        self.printSL(fullPath)
//        png.write(toFile: fullPath, atomically: true)
//        return fullPath
//    }
//
//  //Called in savePhotoButton
//    self.lastImageURL = self.saveUIImageToAppPNG(image: self.lastImage, filename: "/1")
//    self.lastImageURL = self.saveUIImageToAppJPG(image: self.lastImage, filename: "/3")
//    //**************************************
    
    
    
    
    
    
/*
    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }
    */




//
//import UIKit
//import DJIUXSDK
//
//public class SticksViewController: UIViewController {
//
//    weak var mapWidget: DUXMapWidget?
//    var mapWidgetController: DUXMapViewController?
//
//
//    override public func viewDidLoad() {
//        super.viewDidLoad()
//        self.setupMapWidget()
//    }
//
//    // MARK: - Setup
//    func setupMapWidget() {
//        self.mapWidgetController = DUXMapViewController()
//        self.mapWidget = self.mapWidgetController?.mapWidget!
//        self.mapWidget?.translatesAutoresizingMaskIntoConstraints = false
//        self.mapWidgetController?.willMove(toParent: self)
//        self.addChild(self.mapWidgetController!)
//        self.view.addSubview(self.mapWidgetController!.mapWidget)
//        self.mapWidgetController?.didMove(toParent: self)
//
//        if let image = UIImage(named: "Lock") {
//            self.mapWidget?.changeAnnotation(of: .eligibleFlyZones, toCustomImage: image, withCenterOffset: CGPoint(x: -8, y: -15));
//        }
//
//        self.mapWidget?.topAnchor.constraint(equalTo: self.view.topAnchor).isActive = true
//        self.mapWidget?.bottomAnchor.constraint(equalTo: self.view.bottomAnchor).isActive = true
//        self.mapWidget?.leadingAnchor.constraint(equalTo: self.view.leadingAnchor).isActive = true
//        self.mapWidget?.trailingAnchor.constraint(equalTo: self.view.trailingAnchor).isActive = true
//
//        self.mapWidget?.setNeedsDisplay()
//        self.view.sendSubviewToBack(self.mapWidget!)
//    }
//
//

// Capabilities..
//            if let gimbalcapability = self.gimbal?.capabilities {
//                statusLabel.text = String(describing: gimbalcapability[DJIGimbalParamPitchUpEndpoint])
//                for (keys, values) in gimbalcapability {
//                    statusLabel.text = String(describing: keys) + String(describing: values)
//                    print(keys, values)
//                }
//    // Get gimbal capabilities via keyManager
//    func getGimbalCapabilites() -> Int {
//        guard let gimbalCapabilitiesKey = DJIGimbalKey(param: DJIGimbalParamCapabilities) else {
//            print("Cold not creat DJIGimbalParamCapabilities key")
//            return 0
//        }
//        guard let keyManager = DJISDKManager.keyManager() else {
//            print("Could not get the keyManager, make sure you are registered")
//            return 0
//        }
//        if let capabilityValue = keyManager.getValueFor(gimbalCapabilitiesKey) {
//            //let capability = capabilityValue.value as! DJIParamCapabilityMinMax
//            let capability = capabilityValue.value as! NSDictionary
//            let check_first = capability.object(forKey: DJIGimbalParamPitchUpEndpoint) as! DJIParamCapability
//            statusLabel.text = String(check_first.isSupported)
//            // Unfortunately, DJIGimbalParamPitchUpEndpoint is not supported..
//            // If it was we should be able to get the min max like this:
//            if check_first.isSupported{
//                let minmaxCapability = capability.object(forKey: DJIGimbalParamPitchUpEndpoint) as! DJIParamCapabilityMinMax
//                let my_value = minmaxCapability.min
//                statusLabel.text = my_value?.stringValue
//                return my_value as! Int
//            }
//            //statusLabel.text = String(describing: keys) + String(describing: values)
//        }
//        return 0
//    }

//
//  /// Sets up a Telemetry Listener
//  fileprivate func setupTelemetryListeners() {
//
//      let manager = DJISDKManager.keyManager()
//
//      // Position & Altitude
//      if let positionKey = DJIFlightControllerKey(param: DJIFlightControllerParamAircraftLocation) {
//
//          manager?.startListeningForChanges(on: positionKey, withListener: self, andUpdate: { oldKeyedValue, newKeyedValue in
//
//              guard let location = newKeyedValue?.value as? CLLocation, let flightId = self.airmapFlight?.id else {
//                  return
//              }
//
//              guard let altitudeKey = DJIFlightControllerKey(param: DJIFlightControllerParamAltitudeInMeters), let altitude = manager?.getValueFor(altitudeKey)?.floatValue  else {
//                  return
//              }
//
//              do { try AirMap.sendTelemetryData(flightId, coordinate: location.coordinate, altitudeAgl: altitude, altitudeMsl: nil) }
//              catch let error { AirMap.logger.error(error) }
//
//              // update flight
//              self.airmapFlight?.coordinate = location.coordinate
//          })
//      }
//
//      // Velocity
//      if let velocityKey = DJIFlightControllerKey(param: DJIFlightControllerParamVelocity) {
//
//          manager?.startListeningForChanges(on: velocityKey, withListener: self, andUpdate: { oldKeyedValue, newKeyedValue in
//
//              guard let velocity = newKeyedValue?.value as? DJISDKVector3D, let flightId = self.airmapFlight?.id else {
//                  return
//              }
//
//              do { try AirMap.sendTelemetryData(flightId, velocity: (x: Float(velocity.x), y: Float(velocity.y), z: Float(velocity.z))) }
//              catch let error { AirMap.logger.error(error) }
//          })
//      }
//
//      // Attitude
//      if let attitudeKey = DJIFlightControllerKey(param: DJIFlightControllerParamAttitude) {
//
//          manager?.startListeningForChanges(on: attitudeKey, withListener: self, andUpdate: { oldKeyedValue, newKeyedValue in
//              guard let attitude = newKeyedValue?.value as? DJISDKVector3D, let flightId = self.airmapFlight?.id else {
//                  return
//              }
//              do { try AirMap.sendTelemetryData(flightId, yaw: Float(attitude.z), pitch: Float(attitude.y), roll: Float(attitude.x)) }
//              catch let error { AirMap.logger.error(error) }
//          })
//      }
//  }




// Livestream via rmtp server https://www.youtube.com/watch?v=Llv18AdtTho


// Closures
// A function can be defined to receive a code block as an argument, a completion handler. The compltion handler code block
// will be executed with the passed arguments as the function has finished executing. A competion handler with an escaping argument is an argument that escapes from the scope of the function, it is outside.
// It is in the function definition that the completion block input arguments and return value types are defined, as so:
// completion: @escaping (String) -> Void, means: pass on a code block that takes a String and returns Void
// When the function is called we pass on the codeblock, as so:
// completion: {(str: String) in
//  print("In the end, it shows the that the number must have been :", str)
// })

// In the function definition we define the input and output of the completion handler.
// In the function call we define what to do with the input and output of the completion handler.

//    func my_function(number: Int, completion: @escaping (String) -> Void) {
//        print("the number is: ", number.description)
//        print("lets do a lot of calculations and then return if it was odd or even")
//        print("...")
//        usleep(1000000)
//        print("ok, we are done thinking. Exit scope")
//        if number.isMultiple(of: 2){
//            // the number is even
//            completion("even")
//        }
//        else{
//            completion("odd")
//        }
//    }
//
//    my_function(number: 78, completion: {(str: String) in
//      print("In the end, it shows the that the number must have been :", str)
//    })
