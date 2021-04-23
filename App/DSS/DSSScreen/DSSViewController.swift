//
//  stickViewController.swift
//  UXSDKSwiftSample
//
//  Created by Andreas Gising on 2020-08-20.
//  Copyright © 2020 DJI. All rights reserved.
//

// header serach path "$(SRCROOT)/Frameworks/VideoPreviewer/VideoPreviewer/ffmpeg/include"/**
// $(inherited) $(PROJECT_DIR)/Frameworks/VideoPreviewer/VideoPreviewer/ffmpeg/lib


// framework search paht debug : $(inherited) $(PROJECT_DIR)/Frameworks $(PROJECT_DIR)/../DJIWidget/**
// feamework search path release : $(inherited) $(PROJECT_DIR)/Frameworks $(PROJECT_DIR)/../DJIWidget/**
import UIKit
import DJIUXSDK
import DJIWidget
import SwiftyZeroMQ5 // https://github.com/azawawi/SwiftyZeroMQ  good examples in readme
import SwiftyJSON // https://github.com/SwiftyJSON/SwiftyJSON good examples in readme

// ZeroMQ https://stackoverflow.com/questions/49204713/zeromq-swift-code-with-swiftyzeromq-recv-still-blocks-gui-text-update-even-a
// Build ZeroMQ https://www.ics.com/blog/lets-build-zeromq-library

// Background process https://stackoverflow.com/questions/24056205/how-to-use-background-thread-in-swift
// Related issue https://stackoverflow.com/questions/49204713/zeromq-swift-code-with-swiftyzeromq-recv-still-blocks-gui-text-update-even-a

// Generate App icons: https://appicon.co/

// Look into media download scheduler: fetchFileDataWithOffset:updateQueue:updateBlock

public class DSSViewController: DUXDefaultLayoutViewController { //DUXFPVViewController {
    //**********************
    // Variable declarations
    
    var debug: Int = 0                  // 0 - off, 1 debug to screen, 2 debug to StatusLabel (user)
        
    var aircraft: DJIAircraft?
    var camera: DJICamera?
    //var DJIgimbal: DJIGimbal?
    
    var leftTicker = 0
    var rightTicker = 0
    
    //var acks = 0
    var context: SwiftyZeroMQ.Context = try! SwiftyZeroMQ.Context()
    var poller = SwiftyZeroMQ.Poller()
    var infoPublisher: SwiftyZeroMQ.Socket?
    var dataPublisher: SwiftyZeroMQ.Socket?
    var endPointDict:[String : SwiftyZeroMQ.Socket] = [ : ]                     // For subscribing to gps-strams or other streams, key = enPoint, value = socket
    var replyEnable = false
    let replyEndpoint = "tcp://*:5557"
    let infoPublishEndPoint = "tcp://*:5558"
    let dataPublishEndPoint = "tcp://*:5559"
    var dscIP = ""
    let dscPort = ""
    var dscInUse = false
    var subscriptions = Subscriptions()
    var heartBeat = HeartBeat()
    var inControls = "PILOT"
    var disconnected = true
    
    
    var pitchRangeExtension_set: Bool = false
    var nextGimbalPitch: Int = 0
    
    //var gimbalcapability: [AnyHashable: Any]? = [:]
    var cameraModeAcitve: DJICameraMode = DJICameraMode.playback //shootPhoto
    var cameraAllocator = Allocator(name: "camera")
    var transferAllAllocator = Allocator(name: "transferAll")
    
    var copter = CopterController()
    var cameraTODO = CameraController()
   
    var sessionLastIndex: Int = 0 // Picture index of this session
    var sdFirstIndex: Int = -1 // Start index of SDCard, updates at first download
    var transferring: Bool = false
    var jsonMetaDataXYZ: JSON = JSON()                 // All the photo metadata XYZ
    var jsonMetaDataNED: JSON = JSON()                 // All th photo metadata NED
    var jsonMetaDataLLA: JSON = JSON()                 // All the photo metadata LLA
    var jsonPhotos: JSON = JSON()                   // Photos filename and downloaded status
        
    
    var idle: Bool = true                   // For future implementation of task que
    
    var ownerID: String = ""
    
    
    // Steppers
    @IBOutlet weak var leftStepperStackView: UIStackView!
    @IBOutlet weak var leftStepperLabel: UILabel!
    @IBOutlet weak var leftStepperName: UILabel!
    @IBOutlet weak var leftStepperButton: UIStepper!
    @IBOutlet weak var rightStepperStackView: UIStackView!
    @IBOutlet weak var rightStepperLabel: UILabel!
    @IBOutlet weak var rightStepperName: UILabel!
    @IBOutlet weak var rightStepperButton: UIStepper!
    
    
    
    @IBOutlet weak var posXLabel: UILabel!
    @IBOutlet weak var posYLabel: UILabel!
    @IBOutlet weak var posZLabel: UILabel!
    
    // IBOutlet declaration: ImageView
    @IBOutlet weak var previewImageView: UIImageView!
    
    @IBOutlet weak var controlsButton: UIButton!
    @IBOutlet weak var DuttLeftButton: UIButton!
    @IBOutlet weak var DuttRightButton: UIButton!
    @IBOutlet weak var getDataButton: UIButton!
    @IBOutlet weak var putDataButton: UIButton!
    
    @IBOutlet weak var takePhotoButton: UIButton!
    @IBOutlet weak var previewButton: UIButton!
    @IBOutlet weak var savePhotoButton: UIButton!

    // TableView (failed to set corner radius, not used now.
    @IBOutlet weak var logTableView: UIView!
    
    
    // Just to test an init function
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    
    //**********************
    // Fucntion declarations
    //**********************
    
    
    //************************************
    // Disable button and change colormode
    func disableButton(_ button: UIButton!){
        button.isEnabled = false
        button.backgroundColor = UIColor.lightGray
    }
    
    //***********************************
    // Enable button and change colormode
    func enableButton(_ button: UIButton!){
        button.isEnabled = true
        button.backgroundColor = UIColor.systemOrange
    }

    //***********************************************
    // Deactivate the sticks and disable dutt buttons
    func deactivateSticks(){
        //GUI handling
        
        //DeactivateSticksButton.backgroundColor = UIColor.lightGray
        //ActivateSticksButton.backgroundColor = UIColor.systemBlue
        controlsButton.backgroundColor = UIColor.systemOrange
        disableButton(DuttLeftButton)
        disableButton(DuttRightButton)
        
        // Disable copter stick mode
        copter.stickDisable()
        self.inControls = "PILOT"
    }
    
    //****************************************************************
    // Activate sticks and dutt buttons, reset any velocity references
    func activateSticks(){
        //GUI handling
        //ActivateSticksButton.backgroundColor = UIColor.lightGray
        //DeactivateSticksButton.backgroundColor = UIColor.systemRed
        controlsButton.backgroundColor = UIColor.systemGreen
        enableButton(DuttLeftButton)
        enableButton(DuttRightButton)
        
        // Enable stick mode
        copter.stickEnable()
        self.inControls = "APPLICATION"
    }
    
    //*****************************************************
    // Support function to step through gimbal pitch values
    func updateGnextGimbalPitch(){
        self.nextGimbalPitch -= 20
        if self.nextGimbalPitch < -40 {
            self.nextGimbalPitch = 20
        }
    }
    
    //********************************************************************************
    // Writes metadata to json. If init point is not set, XYZ and NED are set to 999.0
    func writeMetaData()->Bool{

        var jsonPhoto = JSON()
        jsonPhoto["filename"] = JSON("")
        jsonPhoto["stored"].boolValue = false
        self.jsonPhotos[String(self.sessionLastIndex)] = jsonPhoto
        
        // LLA metadata
        var metaLLA = JSON()
        metaLLA["filename"] = JSON("")
        metaLLA["index"] = JSON(self.sessionLastIndex)
        metaLLA["lat"] = JSON(self.copter.loc.coordinate.latitude)
        metaLLA["lon"] = JSON(self.copter.loc.coordinate.longitude)
        metaLLA["alt"] = JSON(self.copter.loc.altitude)
        metaLLA["agl"] = JSON(-1)
        metaLLA["heading"] = JSON(self.copter.loc.gimbalYaw)
        metaLLA["pitch"] = JSON(self.copter.gimbal.gimbalPitch)
        
        // Append metaLLA
        self.jsonMetaDataLLA[String(self.sessionLastIndex)] = metaLLA
        
        // Check for subscriptions
        if self.subscriptions.photoLLA{
            _ = self.publish(socket: self.infoPublisher, topic: "photo_LLA", json: metaLLA)
        }
        else{
            print(metaLLA)
        }
        
        
        // Local coordinates requires init point.
        // If init point is set calc XYZ and NED, otherwise set to default
        if self.copter.initLoc.isInitLocation {

            // XYZ metadata
            var metaXYZ = JSON()
            metaXYZ["filename"] = JSON("")
            metaXYZ["x"] = JSON(self.copter.loc.pos.x)
            metaXYZ["y"] = JSON(self.copter.loc.pos.y)
            metaXYZ["z"] = JSON(self.copter.loc.pos.z)
            metaXYZ["agl"] = JSON(-1)
            // In sim loc.gimbalYaw does not update while on ground exept for first photo.
            metaXYZ["heading"] = JSON(self.copter.loc.gimbalYaw - self.copter.initLoc.gimbalYaw)
            metaXYZ["pitch"] = JSON(self.copter.gimbal.gimbalPitch)
            metaXYZ["index"] = JSON(self.sessionLastIndex)
            
            // Append metaXYZ
            self.jsonMetaDataXYZ[String(self.sessionLastIndex)] = metaXYZ
        
            // Check for subscriptions
            if self.subscriptions.photoXYZ{
                _ = self.publish(socket: self.infoPublisher, topic: "photo_XYZ", json: metaXYZ)
            }
            
            // NED metadata
            var metaNED = JSON()
            metaNED["filename"] = JSON("")
            metaNED["north"] = JSON(self.copter.loc.pos.north)
            metaNED["east"] = JSON(self.copter.loc.pos.east)
            metaNED["down"] = JSON(self.copter.loc.pos.down)
            metaNED["agl"] = JSON(-1)
            // In sim loc.gimbalYaw does not update while on ground exept for first photo.
            metaNED["heading"] = JSON(self.copter.loc.gimbalYaw)
            metaNED["pitch"] = JSON(self.copter.gimbal.gimbalPitch)
            metaNED["index"] = JSON(self.sessionLastIndex)
            
            // Append metaNED
            self.jsonMetaDataNED[String(self.sessionLastIndex)] = metaNED
            
            // Dont check for subscriptiopns, NED is not subscirbeable.
        }
        // No init point, fill empty meta data to not have faulte sizes etc.
        else{
            // XYZ metadata
            var metaXYZ = JSON()
            metaXYZ["filename"] = JSON("")
            metaXYZ["x"] = JSON(999.0)
            metaXYZ["y"] = JSON(999.0)
            metaXYZ["z"] = JSON(999.0)
            metaXYZ["agl"] = JSON(-1)
            // In sim loc.gimbalYaw does not update while on ground exept for first photo.
            metaXYZ["heading"] = JSON(self.copter.loc.gimbalYaw)
            metaXYZ["pitch"] = JSON(self.copter.gimbal.gimbalPitch)
            metaXYZ["index"] = JSON(self.sessionLastIndex)
            
            // Append metaXYZ
            self.jsonMetaDataXYZ[String(self.sessionLastIndex)] = metaXYZ
        
            // Check for subscriptions
            if self.subscriptions.photoXYZ{
                _ = self.publish(socket: self.infoPublisher, topic: "photo_XYZ", json: metaXYZ)
            }
            
            // NED metadata
            var metaNED = JSON()
            metaNED["filename"] = JSON("")
            metaNED["north"] = JSON(999.0)
            metaNED["east"] = JSON(999.0)
            metaNED["down"] = JSON(999.0)
            metaNED["agl"] = JSON(-1)
            // In sim loc.gimbalYaw does not update while on ground exept for first photo.
            metaNED["heading"] = JSON(self.copter.loc.gimbalYaw)
            metaNED["pitch"] = JSON(self.copter.gimbal.gimbalPitch)
            metaNED["index"] = JSON(self.sessionLastIndex)
            
            // Append metaNED
            self.jsonMetaDataNED[String(self.sessionLastIndex)] = metaNED
            
            
            if false{
                print(metaXYZ)
                print(metaNED)
            }
        }
        
        return true
    }
    

    
    // Implement the camera delegate in cameraHelper. TODO
    //***************************************
    // Monitor when data is written to sdCard
    func startListenToCamera(){
        guard let locationKey = DJICameraKey(param: DJICameraParamIsStoringPhoto) else {
            NSLog("Couldn't create the key")
            return
        }

        guard let keyManager = DJISDKManager.keyManager() else {
            print("Couldn't get the keyManager, are you registered")
            return
        }
        
        keyManager.startListeningForChanges(on: locationKey, withListener: self, andUpdate: { (oldValue: DJIKeyedValue?, newValue: DJIKeyedValue?) in
            if let checkedNewValue = newValue{
                self.cameraAllocator.setAuxOccopier(boolValue: checkedNewValue.boolValue)
            }
        })
    }
    
    
    //*************************************************************
    // capturePhoto sets up the camera if needed and takes a photo.
    func capturePhoto(completion: @escaping (Bool)-> Void ) {
        // Make sure camera is in the correct mode
            self.cameraSetMode(DJICameraMode.shootPhoto, 2, completionHandler: {(succsess: Bool) in
                if succsess{
                // Make sure shootPhotoMode is single, if so, go ahead startShootPhoto
                self.camera?.setShootPhotoMode(DJICameraShootPhotoMode.single, withCompletion: {(error: Error?) in
                    if error != nil{
                        print("Error setting ShootPhotoMode to single")
                        completion(false)
                    }
                    else{
                        // Take photo and save to sdCard
                        self.camera?.startShootPhoto(completion: { (error) in
                            // Camera is wrinting to sdCard AFTER photo is completed!
                            if error != nil {
                                print("Shoot Photo Error: " + String(describing: error))
                                completion(false)
                            }
                            else{
                                completion(true)
                            }
                        })
                    }
                })
            }
            else{
                print("cameraSetMode failed")
                completion(false)
            }
       })
    }
    
    //*********************************************************
    //Function executed when a take_picture command is received
    func takePhotoCMD(){
        self.capturePhoto(completion: {(success) in
                if success{
                    self.sessionLastIndex += 1
                    // Write JSON meta data
                    if self.writeMetaData(){
                            // Metadata was successfully written
                            print("Metadata written")
                        }
                        else{
                            print("MetaData failed to write, initiating ")
                        }
                        NotificationCenter.default.post(name: .didPrintThis, object: self, userInfo: ["printThis": "Take Photo sucessfully completed"])
                    }
                else{
                    NotificationCenter.default.post(name: .didPrintThis, object: self, userInfo: ["printThis": "Take Photo failed to complete"])
                }
            // The camera has not started writing to sdCard yet, but lock the resource for now to prevent allocator from releasing.
            self.cameraAllocator.setAuxOccopier(boolValue: true)
            self.cameraAllocator.deallocate()
        })
    }
    
    // ***********************************************************************************************************************************************
    // cameraSetMode checks if the newCamera mode is the active mode, and if not it tries to set the mode 'attempts' times. TODO - is attemtps needed?
    func cameraSetMode(_ newCameraMode: DJICameraMode,_ attempts: Int, completionHandler: @escaping (Bool) -> Void) {
     
         // Don't exxed maximum number of tries
         if attempts <= 0{
             NotificationCenter.default.post(name: .didPrintThis, object: self, userInfo: ["printThis": "Error: Camera set mode - too many"])
             completionHandler(false)
             return
         }
                     
         // Cameramode seems to automatically be reset to single photo. We cannot use local variable to store the mode. Hence getting and setting the current mode should intefere equally, it is better to set directly than first getting, checking and then setting.
         // Set mode to newCameraMode.
         self.camera?.setMode(newCameraMode, withCompletion: {(error: Error?) in
             if error != nil {
                 self.cameraSetMode(newCameraMode, attempts - 1 , completionHandler: {(success: Bool) in
                 if success{
                     completionHandler(true)
                     }
                 })
             }
             else{
                 // Camera mode is successfully set
                 completionHandler(true)
             }
         })
     }
    
    
    // Function could be redefined to send a notification that updates the GUI
    //****************************************************
    // Print to terminal and display
    func log(_ str: String){
       // Dispatch.main{
       //     self.statusLabel.text = str
       // }
        print(str)
        NotificationCenter.default.post(name: .didNewLogItem, object: self, userInfo: ["logItem": str])
    }
    
    func printDB(_ str: String){
        if debug == 1 {
            print(str)
        }
        if debug == 2 {
            self.log(str)
        }
    }
    
    // Can be moved to separate file
    //*********************************************************
    // NOT USED Load an UIImage from memory using a path string
    func loadUIImageFromMemory(path: String){
        let photo = UIImage(contentsOfFile: path)
        self.previewImageView.image = photo
        print("Previewing photo from path")
    }
    

    //**********************************************************************
     // Save photo from sdCardto app memory. Setup camera then call getImage
    func savePhoto(sessionIndex: Int, completionHandler: @escaping (Bool) -> Void){
         cameraSetMode(DJICameraMode.mediaDownload, 2, completionHandler: {(success: Bool) in
             if success {
                self.getImage(sessionIndex: sessionIndex, completionHandler: {(new_success: Bool) in
                     if new_success{
                         completionHandler(true)
                     }
                     else{
                        completionHandler(false)
                     }
                 })
             }
             else{
                 completionHandler(false)
             }
         })
     }
    
    
    //*****************************************************************************************
    // Downloads an photoData from sdCard. Saves photoData to app. Can preview photo on screen
    func getImage(sessionIndex: Int, completionHandler: @escaping (Bool) -> Void){
        let manager = self.camera?.mediaManager
        manager?.refreshFileList(of: DJICameraStorageLocation.sdCard, withCompletion: {(error: Error?) in
            print("Refreshing file list...")
            if error != nil {
                completionHandler(false)
                self.log("Refresh file list Failed")
                return
            }
            
            // Get file references
            guard let files = manager?.sdCardFileListSnapshot() else {
                self.log("No photos on sdCard")
                completionHandler(false)
                return
            }
            
            // Print number of files on sdCard and note the first photo of the session if not already done
            print("Files on sdCard: ", String(describing: files.count))
            if self.sdFirstIndex == -1 {
                self.sdFirstIndex = files.count - self.sessionLastIndex
                print("sessionIndex 1 mapped to cameraIndex: ", self.sdFirstIndex)
                // The files[self.sdFirstIndex] is the first photo of this photosession, it maps to self.jsonMetaData[self.sessionLastIndex = 1]
            }
            
            // Update Metadata with filename for the n last pictures without a filename added already
            for i in stride(from: self.sessionLastIndex, to: 0, by: -1){
                if files.count < self.sdFirstIndex + i{
                    self.sessionLastIndex =  files.count - self.sdFirstIndex // In early bug photo was not always saved on SDcard, but sessionLastIndex is increased. This quickfix should not be needed now thanks to allocator.
                    print("SessionIndex faulty. Some images were not saved on sdCard.. DEBUG if printed!")
                }
                let indx = String(i)
                if self.jsonMetaDataXYZ[indx]["filename"] == ""{
                    let filename = files[self.sdFirstIndex + i - 1].fileName
                    
                    self.jsonMetaDataXYZ[indx]["filename"].stringValue = filename
                    self.jsonMetaDataLLA[indx]["filename"].stringValue = filename
                    
                    self.jsonPhotos[indx]["filename"].stringValue = filename
                    print("Added filename: " + filename + " to sessionIndex: " + indx)
                }
                else{
                    // Picture n has a filename -> so does n-1, -2, -3 etc -> break!
                    break
                }
            }
            
            // Save metadata to app memory // TODO is this used?
//            do {
//                let rawMetaData = try self.jsonMetaData.rawData()
//                self.saveDataToApp(data: rawMetaData, filename: "metaData.json")
//            }
//            catch {
//                print("Error \(error)")
//            }
            
            // Init cameraIndex
            // TODO move sessionIndex logic up the chain
            var cameraIndex = 0
            var theSessionIndex = 0
            // Take last photo or specific sessionIndex
            if sessionIndex == -1 {
                print("All photos not supported yet! You get the last instead..")
                theSessionIndex = self.sessionLastIndex
               // cameraIndex = files.count - 1
            }
            // Last image
            else if sessionIndex == 0 {
                cameraIndex = files.count - 1
                theSessionIndex = self.sessionLastIndex
            }
            else{
                cameraIndex = sessionIndex + self.sdFirstIndex - 1
                theSessionIndex = sessionIndex
            }

            // Create a photo container for this scope
            var photoData: Data?
            var i: Int?
            
            // Download batchhwise, append data. Closure is called each time data is updated.
            files[cameraIndex].fetchData(withOffset: 0, update: DispatchQueue.main, update: {(_ data: Data?, _ isComplete: Bool, error: Error?) -> Void in
                if error != nil{
                    // This happens if download is triggered to close to taking a picture. Is the allocator used?
                    self.log("Error, set camera mode first: " + String(error!.localizedDescription))
                    completionHandler(false)
                }
                else if isComplete {
                    if let photoData = photoData{
                        //self.lastPhotoData = photoData
                        self.savePhotoDataToApp(photoData: photoData, filename: files[cameraIndex].fileName, sessionIndex: theSessionIndex)
                        completionHandler(true)
                        }
                    else{
                        self.log("Fetch photo from sdCard Failed")
                        completionHandler(false)
                    }
                }
                else {
                    // If photo has been initialized, append the updated data to it
                    if let _ = photoData, let data = data {
                        photoData?.append(data)
                        i! += 1
                        // TODO - progress bar
                    }
                    else {// initialize the photo data
                        photoData = data
                        i = 1
                    }
                }
            })
        })
    }
    
    //********************************************
    // Save PhotoData to app, set URL to the object
    func savePhotoDataToApp(photoData: Data, filename: String, sessionIndex: Int){
        // Translate the sdCardIndex index to theSessionIndex numbering starting at 1.
        //let theSessionIndex = index - self.sdFirstIndex + 1
        let theSessionIndex = sessionIndex
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        if let documentsURL = documentsURL {
            let fileURL = documentsURL.appendingPathComponent(filename)
            do {
                try photoData.write(to: fileURL, options: .atomicWrite)
                self.jsonPhotos[String(theSessionIndex)]["stored"].boolValue = true
                self.printDB("savePhotoDataToApp: The write fileURL points at: " + fileURL.description)
            } catch {
                self.log("savePhotoDataToApp: Could not write photoData to App: " + String(describing: error))
            }
        }
    }
    
    // ***************************************************************************************************************
    // Transfers (publishes) all photos, downloads from sdCard if needed. transferAll allocates the rescource it self.
    func transferAll(){
        // Check if there are any photos to transfer
        if self.sessionLastIndex == 0 {
            print("transferAll: No photos to transfer")
            self.transferAllAllocator.deallocate()
            return
        }
        self.transferAllHelper(sessionIndex: self.sessionLastIndex, attempt: 1, skipped: 0)
    }

    // *****************************************************************
    // Iterative nested calls, allows three download attempts per index.
    func transferAllHelper(sessionIndex: Int, attempt: Int, skipped: Int){
        // If too many attempts, skip this photo
        if attempt > 3{
            print("transferAllHelper: Difficulties downloading index: ", sessionIndex, " Skipping.")
            // If there are more photos in que, try with next one, add one to skipped.
            if sessionIndex > 1 {
                self.transferAllHelper(sessionIndex: sessionIndex - 1, attempt: 1, skipped: skipped + 1)
            }
            // If no more photos in que, report result to user, deallocate transferAll and return.
            else {
                self.log("downloadAllHelper: Caution: " + String(skipped + 1) + " photos not transferred")
                self.transferAllAllocator.deallocate()
                return
            }
        }
        else {
            self.transferIndex(sessionIndex: sessionIndex, completionHandler: {(success) in
                if success{
                    // If no more photos in que, report result to user, deallocate transferAll and return
                    if sessionIndex == 1{
                        if skipped == 0 {
                            self.log("downloadAllHelper: All photos transferred")
                        }
                        else {
                            self.log("downloadAllHelper: Caution: " + String(skipped) + " photos not transferred")
                        }
                        self.transferAllAllocator.deallocate()
                        return
                    }
                    else {
                        self.transferAllHelper(sessionIndex: sessionIndex - 1, attempt: 1, skipped: skipped)
                    }
                }
                else{
                    // Sleep to give system a chance to recover..
                    usleep(200000)
                    self.transferAllHelper(sessionIndex: sessionIndex, attempt: attempt + 1, skipped: skipped)
                }
            })
        }
    }
    
    //
    // Uses transferIndex to download and transfer photo with index sessionIndex. I tries max three times.
    func transferSingle(sessionIndex: Int, attempt: Int){
        if attempt > 3{
            print("transferSingle: Difficulties downloading index: ", sessionIndex, " Skipping.")
            return
        }
        self.transferIndex(sessionIndex: sessionIndex, completionHandler: {(success) in
            if success{
                self.log("downloadSingle: Photo index: " + String(sessionIndex) + ", transferred")
            }
            else{
                self.log("downloadSingle: Filed to transfer index: " + String(sessionIndex))
                // Sleep to give user a chance to read the message..
                usleep(500000)
                self.transferSingle(sessionIndex: sessionIndex, attempt: attempt + 1)
            }
        })
    }
    
    //*************************************************
    // Transfer a photo with sessionIndex [1,2...n].
    func transferIndex(sessionIndex: Int, completionHandler: @escaping (Bool) -> Void){
        //print("transferIndex: jsonPhotos: ", self.jsonPhotos)
        log("Transfer index: " + String(sessionIndex))
        if self.jsonPhotos[String(sessionIndex)].exists(){
            if jsonPhotos[String(sessionIndex)]["stored"] == false{
                log("transferIndex: Download photo: " + String(sessionIndex))
                // Allocate resource
                var maxTime = 41
                while !self.cameraAllocator.allocate("download", maxTime: 40){
                    // Sleep 0.1s
                    usleep(100000)
                    maxTime -= 1
                    if maxTime < 0 {
                        // Give up attempt to download index
                        self.log("transferIndex: Error, could not allocate cameraAllocator")
                        completionHandler(false)
                    }
                }
                // Allocator allocated
                self.savePhoto(sessionIndex: sessionIndex, completionHandler: {(saveSuccess) in
                    self.cameraAllocator.deallocate()
                    if saveSuccess {
                        self.log("transferIndex: Photo " + String(sessionIndex) + " downloaded to App")
                        self.transferIndex(sessionIndex: sessionIndex, completionHandler: {(success: Bool) in
                            // Completion handler on first call depends on the second call, child process.
                            if success{
                                completionHandler(true)
                            }
                            else{
                                completionHandler(false)
                            }
                        })
                    }
                    else{
                        self.log("transferIndex: Error, failed to download index " + String(sessionIndex))
                        completionHandler(false)
                    }
                })
            }
            // Photo is locally stored, load and transfer it!
            else{
                // Build up the full URLpath, then load photo and transfer
                if let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    let filename = self.jsonPhotos[String(sessionIndex)]["filename"].stringValue
                    let fileURL = documentsURL.appendingPathComponent(filename)
                    self.printDB("The file url we try to publish: " + fileURL.description)
                    do{
                        //print("The read fileURL points at: ", fileURL)
                        let photoData = try Data(contentsOf: fileURL)
                        self.log("transferIndex: Publish photo " + String(sessionIndex) + " on PUB-socket")
                        var json_photo = JSON()
                        json_photo["photo"].stringValue = getBase64utf8(data: photoData)
                        // What metadata to add, XYZ or LLA? TODO
                        json_photo["metadata"] = self.jsonMetaDataXYZ[String(sessionIndex)]
                        _ = self.publish(socket: self.dataPublisher, topic: "photo", json: json_photo)
                        completionHandler(true)
                    }
                    catch{
                        print("transferIndex: Could not load data: ", filename)
                        completionHandler(false)
                    }
                }
            }
        }
        else{
            self.log("transferIndex: Index has not been produced yet: " + String(sessionIndex))
            completionHandler(false)
        }
    }
        

    // Can be moved to separate file
    // ******************************************************************
    // Download the preview of the last photo taken. Preview it on screen
    func getPreview(completionHandler: @escaping (Bool) -> Void){
        let manager = self.camera?.mediaManager
        manager?.refreshFileList(of: DJICameraStorageLocation.sdCard, withCompletion: {(error: Error?) in
            print("Refreshing file list...")
            if error != nil {
                completionHandler(false)
                self.log("Refreshing file list failed.")
            }
            else{
                guard let files = manager?.sdCardFileListSnapshot() else {
                    self.log("No photos on sdCard")
                    completionHandler(true)
                    return
                }
                let cameraIndex = files.count - 1
                files[cameraIndex].fetchThumbnail(completion: {(error) in
                    if error != nil{
                        self.log("Error downloading thumbnail")
                        completionHandler(false)
                    }
                    else{
                        self.previewImageView.image = files[cameraIndex].thumbnail
                        print("Thumbnail for preview")
                        completionHandler(true)
                    }
                })
            }
        })
    }
        
       
    //**************************
    // Init the publisher socket
    func initPublisher()->Bool{
        do{
            self.infoPublisher = try context.socket(.publish)
            try self.infoPublisher?.bind(self.infoPublishEndPoint)
            self.dataPublisher = try context.socket(.publish)
            try self.dataPublisher?.bind(self.dataPublishEndPoint)
            return true
            }
        catch{
            return false
        }
    }
    
    //****************************************************************
    // ZMQ publish socket. Publishes string and serialized json-object
    func publish(socket: SwiftyZeroMQ.Socket?, topic: String, json: JSON)->Bool{
        // Create string with topic and json representation
        let publishStr = getJsonStringAndTopic(topic: topic, json: json)
        do{
            try socket?.send(string: publishStr)
            if topic != "photo"{
                print("Published: " + publishStr)
            }
            else{
                print("Published photo with topic: " + topic + " and metadata: ")
                print(json["metadata"])
            }
            return true
        }
        catch{
            if topic == "photo"{
                print("publish: Error, tried to publish photo, but failed.")
            }
            else{
                print("publish: Error, tried to publish, but failed: " + publishStr)
            }
            return false
        }
    }
    
    
    //**************************************************
    // Initiate socket and start the subscription thread
    func startGpsSubThread(endPoint: String, topic: String)->Bool{
        // Only one socket per unique ip and port.
        //Create a list of endpoints and sockets. [String : swiftZeroMQ.Socket]
        if let socket = endPointDict[endPoint]{
            print("Reconnecting to " + endPoint)
            do{
                try socket.setSubscribe(topic)
                try poller.register(socket: socket, flags: .pollIn)
            }
            catch{
                print("Cannot connect to socket")
                return false
            }
            // Start the thread
            Dispatch.background{
                self.gpsSubThread(endPoint: endPoint)
            }
        }
        else{
            print("Connecting to " + endPoint)
            do{
                let subscribe = try context.socket(.subscribe)
                try subscribe.connect(endPoint)
                // Add socket to dictionary with key endPoint
                endPointDict[endPoint] = subscribe
                try subscribe.setSubscribe(topic)
                try poller.register(socket: subscribe, flags: .pollIn)
            }
            catch{
                print("startGpsSubThread: Could not connect to socket.")
                return false
            }
            print("startGpsSubThread")
            Dispatch.background{
                self.gpsSubThread(endPoint: endPoint)
            }
        }
        return true
    }
        
    func gpsSubThread(endPoint: String){
        if let socket = endPointDict[endPoint]{
            while true {//copter.followStream {             // TODO, shold be other criter
                let (success,jsonString) = pollAndRecv(socket: socket)
                if success{
                    print("Received message: " + jsonString)
                    let (topic,json_m) = getJsonObject(uglyString: jsonString, stringIncludesTopic: true)
                    if topic == nil{
                        print("Found no topic, the parsed json_m: ", json_m)
                    }
                    print("The topic: ", topic!, " The parsed json_m: ", json_m)
                    
                    // Decode the stream message and apply pattern
                    let lat = json_m["lat"].doubleValue
                    let lon = json_m["lon"].doubleValue
                    let alt = json_m["alt"].doubleValue
                    let yaw = json_m["yaw"].doubleValue
                    
                    self.copter.pattern.streamUpdate(lat: lat, lon: lon, alt: alt, yaw: yaw, currentPos: self.copter.loc)
                    
                    // Update the activeWP
//                    self.copter.activeWP.coordinate.latitude = self.copter.pattern.reference.coordinate.latitude
//                    self.copter.activeWP.coordinate.longitude = self.copter.pattern.reference.coordinate.longitude
//                    self.copter.activeWP.altitude = self.copter.pattern.reference.altitude
//
//                    // Speed TODO
//                    self.copter.activeWP.speed = 3
//
//                    self.copter.activeWP.printLocation(sentFrom: "gpsSubThread")
//                    Dispatch.main{
//                        self.copter.goto()
//                    }
                }
                print("Subscribe: Nothing to receive")
            }
            print("Exiting subscribe thread")
        }
    }
    
    func pollAndRecv(socket: SwiftyZeroMQ.Socket)->(Bool, String) {
        do{
            let regSockets = try poller.poll(timeout: 500)
            print(regSockets)
            if regSockets[socket] == SwiftyZeroMQ.PollFlags.pollIn {
                
                
                //TODO, changed buffer size. Have not tested
                let message: String? = try socket.recv(bufferLength: 4096, options: .dontWait) //recv(options: .dontWait)
                return (true, String(message!))
            }
        }
        catch{
            // We'll return (false, "") below
        }
        return (false, "")
    }
    
    //*************
    
    
    
    
    
    
    
    
    
    
    
//    func startGpsSubThread(endPoint: String, topic: String)->Bool{
//        do{
//            let subscribe = try context.socket(.subscribe)
//            try subscribe.connect("tcp://192.168.1.249:5560")
//            try subscribe.setSubscribe(nil)
//            Dispatch.background{
//                self.gpsSubThread(socket: subscribe)
//            }
//            return true
//        }
//        catch{
//            self.log("startGpsSubThread: Could not connect to socket.")
//            return false
//        }
//    }
//
//    func gpsSubThread(socket: SwiftyZeroMQ.Socket){
//        while copter.followStream{
//            do{
////                let jsonString: String? = try socket.recv()!
////                print(jsonString!)
//                print("Getting stuck waiting for message..")
//                let jsonString: String = try socket.recv()!
//                print("Received message")
//                print(jsonString)
//
//                if let dataFromString = jsonString.data(using: .utf8, allowLossyConversion: false) {
//                    let jsonObj: JSON = try JSON(data: dataFromString)
//                    print(jsonObj)
//                }
//
//            }
//            catch{
//                print("catching subThread error..")
//            }
//        }
//        print("gpsSubThread exited, copter.followStream == false")
//    }
    
    // *****************
    // Heart beat thread
    func startHeartBeatThread(){
        Dispatch.background{
            self.heartBeats()
        }
    }
    
    func heartBeats() {
        // Wait for first heartbeat
        while !self.heartBeat.beatDetected {
            usleep(1000000)
        }
        print("heartBeats: Starting to monitor heartBests")

        // Monitor heartbeats
        while self.heartBeat.alive() {
            usleep(150000)  
            // User disconnect will call DSC immidiatly on receive of comma
        }
        
        // Lost 1 time
        if self.dscInUse{
            // If the link is lost for the first time
            if !self.heartBeat.lostOnce {
                // TODO: call DSC
                // Reset the timer by sending a new beat.
                self.heartBeat.newBeat()
                // Set lostOnce flag
                self.heartBeat.lostOnce = true
                Dispatch.background{
                    self.heartBeats()
                }
                return
            }
        }
        
        // Lost 2 times
        self.log("Link lost. Autopilot Rtl")
        Dispatch.main{
            self.deactivateSticks()
            usleep(100)    // TODO, deactivate sticks sets inControls to PILOT..
            self.inControls = "DSS"
            self.controlsButton.backgroundColor = UIColor.systemGreen
            self.controlsButton.setTitle("TAKE Controls from DSS", for: .normal)

        }
        // Activate RTL
        Dispatch.main{
            self.copter.rtl()
        }
        // Reset the heartbeat state diagram. Wait for new heartbeats
        self.heartBeat.beatDetected = false
        Dispatch.background{
            self.heartBeats()
        }
        return
    }
    
    // ******************************
    // Initiate the zmq reply thread.
    func startReplyThread()->Bool{
        do{
            // Reply socket
            let replier = try context.socket(.reply)
            try replier.bind(self.replyEndpoint)
            print("Did bind to reply socket")
            self.replyEnable = true
            
            Dispatch.background{
                self.readSocket(replier)
            }
            return true
        }
        catch{
            self.log("Could not bind to socket")
            return false
        }
    }
    
    // If function is not used in more than parser, put it in parser.
    // Function checks if the ownerID and the id from a request matches or not.
    func isOwner(id: String)->Bool{
        if id == self.ownerID{
            // Owner match
            return true
        }
        else{
            // Owner mismatch
            print("Requestor owner: ", id, " registered owner: ", self.ownerID)
            return false
        }
    }

    // ****************************************************
    // zmq reply thread that reads command from applictaion
    func readSocket(_ socket: SwiftyZeroMQ.Socket){
        var fromOwner = false
        var requesterID = ""
        var nackOwnerStr = ""
        var messageQualifiesForHeartBeat = false

        while self.replyEnable{
            do {
                let _message: String? = try socket.recv(bufferLength: 4096, options: .none)
                if self.replyEnable == false{ // Since code can halt on socket.recv(), check if input is still desired
                    return
                }
                // A message is received.
                
                // Parse and create an ack/nack
                let (_, json_m) = getJsonObject(uglyString: _message!)
                
                if json_m["fcn"] != "heart_beat"{
                    print("Received message: ", json_m)
                }
                var json_r = JSON()

                // Update message owner status
                requesterID = json_m["id"].stringValue
                if isOwner(id: requesterID){
                    fromOwner = true
                }
                else {
                    fromOwner = false
                    nackOwnerStr = "Requester (" + requesterID + ") is not the DSS owner"

                }
                
                // Message valid for heartbeat?
                messageQualifiesForHeartBeat = false
                if fromOwner{
                    messageQualifiesForHeartBeat = true
                }
                
                switch json_m["fcn"]{
                case "heart_beat":
                    self.printDB("Received cmd: heart_beat")
                    // Nack not fromOwner
                    if !fromOwner{
                        json_r = createJsonNack(fcn: "arm_take_off", description: nackOwnerStr)
                    }
                    // Accept command
                    else{
                        json_r = createJsonAck("heart_beat")
                    }
                case "who_controls":
                    self.log("Received cmd: who_controls")
                    // No nack reasons
                    // Accept command
                    json_r = createJsonAck("who_controls")
                    json_r["in_controls"].stringValue = self.inControls
                
                case "set_geofence":
                    self.log("Received cmd: set_geofence")
                    // Nack not fromOwner
                    if !fromOwner{
                        json_r = createJsonNack(fcn: "set_geofence", description: nackOwnerStr)
                    }
                    // Accept command
                    else{
                        json_r = createJsonAck("set_geofence")
                        // Parse
                        let radius = json_m["radius"].doubleValue
                        var height: [Double] = []
                        height[0] = json_m["low_height_low"].doubleValue
                        height[1] = json_m["height_high"].doubleValue
                        // Set Geo fence
                        self.copter.initLoc.setGeoFence(radius: radius, height: height)
                    }
                    
                case "get_idle":
                    self.log("Received cmd: get_idle")
                    // No nack reasons
                    // Accept command
                    json_r = createJsonAck("get_idle")
                    json_r["idle"].boolValue = self.idle // TODO hardcoded to true..
                                    
                                

                    
                case "set_init_point":
                    self.log("Received cmd: set_init_point")
                    var navReady = false
                    if let currLoc = self.copter.getCurrentLocation(){
                        if currLoc.coordinate.latitude != 0{
                            navReady = true
                        }
                    }
                    // Nack not fromOwner
                    if !fromOwner{
                        json_r = createJsonNack(fcn: "set_init_point", description: nackOwnerStr)
                    }
                    // Nack nav not ready
                    else if !navReady { //self.copter.loc.coordinate.latitude == 0{
                        json_r = createJsonNack(fcn: "set_init_point", description: "Navigation not ready")
                    }
                    // Nack init point already set
                    else if self.copter.initLoc.isInitLocation{
                        json_r = createJsonNack(fcn: "set_init_point", description: "Init point already set")
                    }
                    // Accept command
                    else{
                        json_r = createJsonAck("set_init_point")
                        let headingRef = json_m["heading_ref"].stringValue

                        // Test robustness
                        if !copter.setInitLocation(headingRef: headingRef){
                            print("Error: Debug. Something is wrong, should not have passed to here.")
                            json_r = createJsonNack(fcn: "set_init_point", description: "Navigation not ready")
                        }
                    }
                    
                case "reset_dss_srtl":
                    self.log("Received cmd: reset_dss_srtl")
                    var navReady = false
                    if let currLoc = self.copter.getCurrentLocation(){
                        if currLoc.coordinate.latitude != 0{
                            navReady = true
                        }
                    }
                    // Nack not fromOwner
                    if !fromOwner{
                        json_r = createJsonNack(fcn: "reset_dss_srtl", description: nackOwnerStr)
                    }
                    // Nack nav not ready
                    else if !navReady{
                        json_r = createJsonNack(fcn: "reset_dss_srtl", description: "Navigation not ready")
                    }
                    // Accept command
                    else{
                        if copter.resetDSSSRTLMission(){
                            json_r = createJsonAck("reset_dss_srtl")
                        }
                        else {
                            json_r = createJsonNack(fcn: "reset_dss_srtl", description: "Position not available")
                        }
                    }
                    
                case "arm_take_off":
                    self.log("Received cmd: arm_take_off")
                    let toHeight = json_m["height"].doubleValue
                    // Nack not fromOwner
                    if !fromOwner{
                        json_r = createJsonNack(fcn: "arm_take_off", description: nackOwnerStr)
                    }
                    // TODO nsat check
                    else if false {
                        json_r = createJsonNack(fcn: "arm_take_off", description: "Less than 8 satellites")
                    }
                    // Nack is flying
                    else if copter.getIsFlying() ?? false{ // Default to false to handle nil
                        json_r = createJsonNack(fcn: "arm_take_off", description: "State is flying")
                    }
                    // Nack height limits
                    else if toHeight < 2 || toHeight > 40 {
                        json_r = createJsonNack(fcn: "arm_take_off", description: "Height is out of limits")
                    }
                    // Nack nit point not set
                    else if !self.copter.initLoc.isInitLocation {
                        json_r = createJsonNack(fcn: "arm_take_off", description: "Init point not set")
                    }
                    // Accept command
                    else{
                        json_r = createJsonAck("arm_take_off")
                        copter.toHeight = toHeight
                        copter.takeOff()
                    }
                    
//                case "save_dss_home_position":
//                    self.log("Received cmd: save_dss_home_position")
//                    if self.copter.resetDSSSRTLMission(){
//                        json_r = createJsonAck("save_dss_home_position")
//                    }
//                    else{
//                        json_r = createJsonNack(fcn: "save_dss_home_position", description: "Nav not ready. TODO proper nacks")
//                    }
                
                case "land":
                    self.log("Received cmd: land")
                    // Nack not owner
                    if !fromOwner{
                        json_r = createJsonNack(fcn: "land", description: nackOwnerStr)
                    }
                    // Nack not flying
                    else if !(copter.getIsFlying() ?? false){ // Default to false to handle nil
                        json_r = createJsonNack(fcn: "land", description: "Not flying")
                    }
                    // Accept command
                    else{
                        json_r = createJsonAck("land")
                        copter.land()
                    }

                  case "rtl":
                    self.log("Received cmd: rtl")
                    // We want to know if the command is accepted or not. Problem is that it takes ~1s to know for sure that the RTL is accepted (completion code of rtl) and we can't wait 1s with the reponse.
                    // Instead we look at flight mode which changes much faster, although we do not know for sure that the rtl is accepted. For example, the flight mode is already GPS after take-off..
                    
                    // Nack not owner
                    if !fromOwner{
                        json_r = createJsonNack(fcn: "rtl", description: nackOwnerStr)
                    }
                    // Nack not flying
                    else if !(copter.getIsFlying() ?? false){ // Default to false to handle nil
                        json_r = createJsonNack(fcn: "rtl", description: "Not flying")
                    }
                    // Accept command
                    else{
                        // Activate the rtl, then figure if the command whent through or not
                        copter.rtl()
                        // Sleep for max 8*50ms = 0.4s to allow for mode change to go through.
                        var max_attempts = 8
                        // while flightMode is neither GPS nor Landing -  wait. If flightMode is GPS or Landing - continue
                        while copter.flightMode != "GPS" && copter.flightMode != "Landing" {
                            if max_attempts > 0{
                                max_attempts -= 1
                                // Sleep 0.1s
                                print("ReadSocket: Waiting for rtl to go through before replying.")
                                usleep(50000)
                            }
                            else {
                                // We tried many times, it must have failed somehow -> nack
                                print("ReadSocket: RTL did not go through. Debug.")
                                json_r = createJsonNack(fcn: "rtl", description: "RTL failed to engage, try again")
                                break
                            }
                        }
                        // If RTL is engaged send ack.
                        if copter.flightMode == "GPS" || copter.flightMode == "Landing" {
                            json_r = createJsonAck("rtl")
                        }
                    }
                   
                case "dss_srtl":
                    self.log("Received comd: dss srtl")
                    let hoverT = json_m["arg"]["hover_time"].intValue
                    // Nack not owner
                    if !fromOwner{
                        json_r = createJsonNack(fcn: "rtl", description: nackOwnerStr)
                    }
                    // Nack not flying
                    else if !(copter.getIsFlying() ?? false){ // Default to false to handle nil
                        json_r = createJsonNack(fcn: "rtl", description: "Not flying")
                    }
                    // Nack hover time out of limits
                    else if !(0 <= hoverT && hoverT <= 300){
                        json_r = createJsonNack(fcn: "dss_srtl", description: "Hover_time is out of limits")
                    }
                    // Accept command
                    else {
                        json_r = createJsonAck("dss_srtl")
                        Dispatch.main{
                            self.copter.dssSrtl(hoverTime: hoverT)
                        }
                    }
                    
                case "set_vel_BODY":
                    self.log("Received cmd: set_vel_BODY")
                    // Nack not owner
                    if !fromOwner{
                        json_r = createJsonNack(fcn: "set_vel_BODY", description: nackOwnerStr)
                    }
                    // Nack not flying
                    else if !(copter.getIsFlying() ?? false){ // Default to false to handle nil
                        json_r = createJsonNack(fcn: "set_vel_BODY", description: "Not flying")
                    }
                    // Accept command
                    else{
                        json_r = createJsonAck("set_vel_BODY")
                        let velX = Float(json_m["x"].doubleValue)
                        let velY = Float(json_m["y"].doubleValue)
                        let velZ = Float(json_m["z"].doubleValue)
                        let yawRate = Float(json_m["yaw_rate"].doubleValue)
                        print("VelX: " + String(velX) + ", velY: " + String(velY) + ", velZ: " + String(velZ) + ", yawRate: "  + String(yawRate))
                        Dispatch.main{
                            self.copter.dutt(x: velX, y: velY, z: velZ, yawRate: yawRate)
                            print("Dutt command sent from readSocket")
                        }
                    }
                    
                case "set_heading":
                    self.log("Received cmd: set_heading")
                    let heading = json_m["heading"].doubleValue
                    // Nack not owner
                    if !fromOwner{
                        json_r = createJsonNack(fcn: "set_heading", description: nackOwnerStr)
                    }
                    // Nack not flying
                    else if !(copter.getIsFlying() ?? false){ // Default to false to handle nil
                        json_r = createJsonNack(fcn: "set_heading", description: "Not flying")
                    }
                    // Nack yaw out of limits
                    else if heading < 0 || 360 < heading {
                        json_r = createJsonNack(fcn: "set_heading", description: "Yaw is out of limits")
                    }
                    // Nack mission active
                    else if copter.missionIsActive{
                        json_r = createJsonNack(fcn: "set_heading", description: "Mission is active")
                    }
                    // Accept command
                    else{
                        json_r = createJsonAck("set_heading")
                        Dispatch.main{
                            self.copter.setHeading(targetHeading: heading)
                        }
                    }

                case "upload_mission_LLA":
                    self.log("Received cmd: upload_mission_LLA")
                    let fcnStr = "upload_mission_LLA"
                    let (fenceOK, fenceDescr, numberingOK, numberingDescr, speedOK, speedDescr, actionOK, actionDescr, headingOK, headingDescr) = copter.uploadMission(mission: json_m["mission"])
                    // Nack not owner
                    if !fromOwner{
                        json_r = createJsonNack(fcn: fcnStr, description: nackOwnerStr)
                    }
                    // Nack init point not set
                    else if !copter.initLoc.isInitLocation{
                        json_r = createJsonNack(fcn: fcnStr, description: "Init point is not set")
                    }
                    // Nack wp violate geofence
                    else if !fenceOK {
                        json_r = createJsonNack(fcn: fcnStr, description: fenceDescr)
                    }
                    // Nack wp numbering
                    else if !numberingOK{
                        json_r = createJsonNack(fcn: fcnStr, description: numberingDescr)
                    }
                    // Nack action not supported
                    else if !actionOK{
                        json_r = createJsonNack(fcn: fcnStr, description: actionDescr)
                    }
                    // Nack speed too low
                    else if !speedOK{
                        json_r = createJsonNack(fcn: fcnStr, description: speedDescr)
                    }
                    // Nack heading error
                    else if !headingOK{
                        json_r = createJsonNack(fcn: fcnStr, description: headingDescr)
                    }
                    // Accept command
                    else{
                        copter.pendingMission = json_m["mission"]
                        json_r = createJsonAck(fcnStr)
                    }
                    
                case "upload_mission_NED":
                    self.log("Received cmd: upload_mission_NED")
                    let fcnStr = "upload_mission_NED"
                    let (fenceOK, fenceDescr, numberingOK, numberingDescr, speedOK, speedDescr, actionOK, actionDescr, headingOK, headingDescr) = copter.uploadMission(mission: json_m["mission"])
                    // Nack not owner
                    if !fromOwner{
                        json_r = createJsonNack(fcn: fcnStr, description: nackOwnerStr)
                    }
                    // Nack init point not set
                    else if !copter.initLoc.isInitLocation{
                        json_r = createJsonNack(fcn: fcnStr, description: "Init point is not set")
                    }
                    // Nack wp violate geofence
                    else if !fenceOK {
                        json_r = createJsonNack(fcn: fcnStr, description: fenceDescr)
                    }
                    // Nack wp numbering
                    else if !numberingOK{
                        json_r = createJsonNack(fcn: fcnStr, description: numberingDescr)
                    }
                    // Nack action not supported
                    else if !actionOK{
                        json_r = createJsonNack(fcn: fcnStr, description: actionDescr)
                    }
                    // Nack speed too low
                    else if !speedOK{
                        json_r = createJsonNack(fcn: fcnStr, description: speedDescr)
                    }
                    // Nack heading error
                    else if !headingOK{
                        json_r = createJsonNack(fcn: fcnStr, description: headingDescr)
                    }
                    // Accept command
                    else{
                        copter.pendingMission = json_m["mission"]
                        json_r = createJsonAck(fcnStr)
                    }

                case "upload_mission_XYZ":
                    self.log("Received cmd: upload_mission_XYZ")
                    let fcnStr = "upload_mission_XYZ"
                    let (fenceOK, fenceDescr, numberingOK, numberingDescr, speedOK, speedDescr, actionOK, actionDescr, headingOK, headingDescr) = copter.uploadMission(mission: json_m["mission"])
                    // Nack not owner
                    if !fromOwner{
                        json_r = createJsonNack(fcn: fcnStr, description: nackOwnerStr)
                    }
                    // Nack init point not set
                    else if !copter.initLoc.isInitLocation{
                        json_r = createJsonNack(fcn: fcnStr, description: "Init point is not set")
                    }
                    // Nack wp violate geofence
                    else if !fenceOK {
                        json_r = createJsonNack(fcn: fcnStr, description: fenceDescr)
                    }
                    // Nack wp numbering
                    else if !numberingOK{
                        json_r = createJsonNack(fcn: fcnStr, description: numberingDescr)
                    }
                    // Nack action not supported
                    else if !actionOK{
                        json_r = createJsonNack(fcn: fcnStr, description: actionDescr)
                    }
                    // Nack speed too low
                    else if !speedOK{
                        json_r = createJsonNack(fcn: fcnStr, description: speedDescr)
                    }
                    // Nack heading error
                    else if !headingOK{
                        json_r = createJsonNack(fcn: fcnStr, description: headingDescr)
                    }
                    // Accept command
                    else{
                        copter.pendingMission = json_m["mission"]
                        json_r = createJsonAck(fcnStr)
                    }
                    
                case "gogo":
                    self.log("Received cmd: gogo")
                    let next_wp = json_m["next_wp"].intValue
                    // Nack not fromOwner
                    if !fromOwner{
                        json_r = createJsonNack(fcn: "gogo", description: nackOwnerStr)
                    }
                    // Nack not flying
                    else if !(copter.getIsFlying() ?? false){ // Default to false to handle nil
                        json_r = createJsonNack(fcn: "land", description: "Not flying")
                    }
                    // Nack Wp number is not available in pending mission
                    else if !copter.pendingMission["id" + String(next_wp)].exists(){
                        json_r = createJsonNack(fcn: "gogo", description: "Wp number is not available in pending mission")
                    }
                    // Accept command
                    else{
                        json_r = createJsonAck("gogo")
                        Dispatch.main{
                            _ = self.copter.gogo(startWp: next_wp, useCurrentMission: false)
                        }
                    }
                            
                case "set_pattern":
                    self.log("Received cmd: set_pattern")
                    let heading = parseHeading(json: json_m)
                    // Nack not fromOwner
                    if !fromOwner{
                        json_r = createJsonNack(fcn: "set_pattern", description: nackOwnerStr)
                    }
                    // Nack faulty heading
                    else if heading == -99{
                        // heading faulty
                        json_r = createJsonNack(fcn: "set_pattern", description: "Heading faulty")
                    }
                    // Accept command
                    else {
                        // Parse and set pattern
                        let pattern = json_m["pattern"].stringValue
                        let relAlt = json_m["rel_alt"].doubleValue
                        if pattern == "above"{
                            copter.pattern.setPattern(pattern: pattern, relAlt: relAlt, heading: heading)
                            json_r = createJsonAck("set_pattern")
                        }
                        else if pattern == "circle"{
                            let radius = json_m["radius"].doubleValue
                            let yawRate = json_m["yaw_rate"].doubleValue
                            copter.pattern.setPattern(pattern: pattern, relAlt: relAlt, heading: heading, radius: radius, yawRate: yawRate)
                        }
                    }
                    
                    
                case "follow_stream":
                    self.log("Received cmd: follow_stream")
                    // Nack not fromOwner
                    if !fromOwner{
                        json_r = createJsonNack(fcn: "gogo", description: nackOwnerStr)
                    }
                    // Nack not flying
                    else if !(copter.getIsFlying() ?? false){ // Default to false to handle nil
                        json_r = createJsonNack(fcn: "land", description: "Not flying")
                    }
                    // Nack pattern not set
                    else if copter.pattern.pattern.name == "" {
                        json_r = createJsonNack(fcn: "follow_stream", description: "Pattern not set")
                    }
                    // Acccept command
                    else {
                        let enable = json_m["enable"].boolValue
                        let endPoint = json_m["endpoint"].stringValue
                        if enable {
                            let topic = "LLA"
                            if startGpsSubThread(endPoint: endPoint, topic: topic) {
                                self.log("startGpsSubThread listening to :" + endPoint + " topic: " + topic)
                                copter.followStream = enable
                                copter.startFollowStream()
                                
                            }
                            else{
                                self.log("Cannot subscribe to stream: " + endPoint)
                                json_r = createJsonNack(fcn: "follow_stream", description: "Cannot connect to stream")
                                copter.followStream = false
                            }
                        }
                        else {
                            // If enable is false, the subscription thread is exited.
                            copter.followStream = false
                        }
                        
                        json_r = createJsonAck("follow_stream")
                    }
               
                case "set_gimbal":
                    self.log("Received cmd: set_gimbal")
                    _ = json_m["roll"].doubleValue
                    let pitch = json_m["pitch"].doubleValue
                    _ = json_m["yaw"].doubleValue
                    // Nack not fromOwner
                    if !fromOwner{
                        json_r = createJsonNack(fcn: "gogo", description: nackOwnerStr)
                    }
                    // Nack out of range
                    else if pitch < self.copter.gimbal.pitchRange[0] || self.copter.gimbal.pitchRange[1] < pitch {
                        json_r = createJsonNack(fcn: "set_gimbal", description: "Pitch, roll or yaw is out of range for the gimbal")
                    }
                    // Acccept command
                    else{
                        json_r = createJsonAck("set_gimbal")
                        self.copter.gimbal.setPitch(pitch: pitch)
                    }
                    
                case "set_gripper":
                    self.log("Received cmd: set_gripper")
                    json_r = createJsonNack(fcn: "set_gripper", description: "Not applicable to DJI")
                
                case "photo":
                    self.log("Received cmd: photo")
                    let parsedIndex = parseIndex(json: json_m, sessionLastIndex: self.sessionLastIndex)
                    // Nack not fromOwner
                    if !fromOwner{
                        json_r = createJsonNack(fcn: "gogo", description: nackOwnerStr)
                    }
                    // Nack camera busy
                    else if self.cameraAllocator.allocated {
                        json_r = createJsonNack(fcn: "photo", description: "Camera resource is busy")
                    }
                    // Nack index out of range (coded from parseIndex)
                    else if parsedIndex == -11{
                        json_r = createJsonNack(fcn: "photo", description: "Index out of range, " + String(json_m["index"].intValue))
                    }
                    // Nack index faulty (coded from parseIndex)
                    else if parsedIndex == -12{
                        json_r = createJsonNack(fcn: "photo", description: "Index string faulty, " + json_m["index"].stringValue)
                    }
                    // Accept command:
                    else {
                        json_r = createJsonAck("photo")
                        // Switch cmd
                        switch json_m["cmd"]{
                            case "take_photo":
                                self.log("Received cmd: photo, with arg take_photo")
                                if self.cameraAllocator.allocate("take_photo", maxTime: 3) {
                                    // Complete ack message
                                    json_r["description"] = "take_photo"
                                    takePhotoCMD()
                                }
                                else{
                                    json_r = createJsonNack(fcn: "photo", description: "Allocator1 denied, report")
                                    print("DEBUG: Allocator1 denied")
                                    self.log("Allocator1 denied, report")
                                }
                            case "download":
                                self.log("Received cmd: photo, with arg download")
                                // Default resolution
                                var resolution  = "high"
                                // Check resolution argument
                                if json_m["resulution"].exists(){
                                    resolution = json_m["resolution"].stringValue
                                }
                                if resolution == "low"{
                                    print("TODO Low resolution not supported yet, getting high res")
                                }
                                // Download all or single index
                                if parsedIndex == -1 {
                                    if transferAllAllocator.allocate("transferAll", maxTime: 300) {
                                        // Complete ack message
                                        json_r["description"].stringValue = "download all"
                                        // Transfer all in background, transferAll handles the allcoator
                                        Dispatch.background {
                                            // Transfer function handles the allocator
                                            self.log("Downloading all photos...")
                                            self.transferAll()
                                        }
                                    }
                                    else {
                                        json_r = createJsonNack(fcn: "photo", description: "Allocator2 denied, report")
                                        print("DEBUG: Allocator2 denied")
                                        self.log("Allocator2 denied, report")
                                    }
                                }
                                // Index must be ok, download the index
                                else{
                                    // Complete ack message
                                    json_r["description"].stringValue = "download " + String(parsedIndex)
                                    Dispatch.background{
                                        // Download function handles the allocator
                                        self.log("Download photo index " + String(parsedIndex))
                                        self.transferSingle(sessionIndex: parsedIndex, attempt: 1)
                                    }
                                }
                            default:
                            self.log("Photo cmd faulty: " + json_m["cmd"].stringValue)
                                json_r = createJsonNack(fcn: "photo", description: "Cmd faulty")
                        }
                    }
                    
                case "get_armed":
                    self.log("Received cmd: get_armed")
                    // No nack reasons
                    // Accept command
                    json_r = createJsonAck("get_armed")
                    if self.copter.getAreMotorsOn(){
                        json_r["armed"].boolValue = true
                    }
                    else{
                        json_r["armed"].boolValue = false
                    }
                    
                case "get_currentWP":
                    self.log("received cmd: get_currentWP")
                    // No nack reasons
                    // Accept command
                    json_r = createJsonAck("get_currentWP")
                    json_r["currentWP"].intValue = copter.missionNextWp
                    
                case "get_flightmode":
                    // No nack reasons
                    // Accept command
                    json_r = createJsonAck("get_flightmode")
                    if copter.flightMode != nil {
                        json_r["flightmode"].stringValue = copter.flightMode!
                    }
                    else{
                        json_r["flightmode"].stringValue = "No flight mode"
                    }
                case "get_metadata":
                    self.log("Received cmd: get_metadata")
                    let parsedIndex = parseIndex(json: json_m, sessionLastIndex: self.sessionLastIndex)
                    // Nack reference faulty
                    if parsedIndex == -10{
                        json_r = createJsonNack(fcn: "get_metadata", description: "Reference faulty, " + json_m["ref"].stringValue)
                    }
                    // Nack index out of range (coded from parseIndex)
                    else if parsedIndex == -11{
                        json_r = createJsonNack(fcn: "get_metadata", description: "Index out of range, " + String(json_m["index"].intValue))
                    }
                    // Nack index faulty (coded from parseIndex)
                    else if parsedIndex == -12{
                        json_r = createJsonNack(fcn: "get_metadata", description: "Index string faulty, " + json_m["index"].stringValue)
                    }
                    // Accept command
                    else{
                        json_r = createJsonAck("get_metadata")
                        let frame = json_m["ref"].stringValue
                        // All indexes
                        if  parsedIndex == -1{
                            if frame == "XYZ"{
                                json_r["metadata"] = self.jsonMetaDataXYZ
                            }
                            else if frame == "NED"{
                                json_r["metadata"] = self.jsonMetaDataNED
                            }
                            else if frame == "LLA"{
                                json_r["metadata"] = self.jsonMetaDataLLA
                            }
                        }
                        // Specific index
                        else{
                            if frame == "XYZ"{
                                json_r["metadata"] = self.jsonMetaDataXYZ[String(describing: parsedIndex)]
                            }
                            else if frame == "NED"{
                                json_r["metadata"] = self.jsonMetaDataNED[String(describing: parsedIndex)]
                        }
                            else if frame == "LLA"{
                                    json_r["metadata"] = self.jsonMetaDataLLA[String(describing: parsedIndex)]
                            }
                        }
                    }
                    
                case "get_posD":
                    self.log("Received cmd: get_posD")
                    // No nack reasons
                    // Accept command
                    json_r = createJsonAck("get_posD")
                    json_r["posD"].doubleValue = self.copter.loc.pos.down
                
                case "get_PWM":
                    self.log("Received cmd: get_PWM")
                    json_r = createJsonNack(fcn: "get_PWM", description: "Not applicable to DJI")
                    
                case "disconnect":
                    self.log("Received cmd: disconnect")
                    // Nack not fromOwner
                    if !fromOwner{
                        json_r = createJsonNack(fcn: "disconnect", description: nackOwnerStr)
                    }
                    // Accept command
                    else{
                        json_r = createJsonAck("disconnect")
                        // Stop any rtl or other flight mode, then stop
                        Dispatch.main{
                            self.deactivateSticks()
                            usleep(100)                 // TODO, ugly hack
                            self.controlsButton.setTitle("TAKE Controls from DSS", for: .normal)
                            self.controlsButton.backgroundColor = UIColor.systemGreen
                            self.inControls = "DSS"
                        }
                        copter.dutt(x: 0, y: 0, z: 0, yawRate: 0)
                        // Prevent wp action to resume mission
                        self.heartBeat.disconnected = true
                        // TODO: call DSC, dsc
                    }
                    
                case "data_stream":
                    self.log("Received cmd: data_stream with attrubute: " + json_m["stream"].stringValue + " and enable: " + String(json_m["enable"].boolValue))
                    let enable = json_m["enable"].boolValue
                    // Nack faulty stream handeled in switch case
                    // Accept command (and nack later if neccessary)
                    json_r = createJsonAck("data_stream")
                    switch json_m["stream"]{
                        case "ATT":
                            json_r["stream"].stringValue = "ATT"
                            self.subscriptions.setATT(bool: enable)
                            print("TODO: support ATT")
                        case "LLA":
                            json_r["stream"].stringValue = "LLA"
                            self.subscriptions.setLLA(bool: enable)
                        case "NED":
                            json_r["stream"].stringValue = "NED"
                            self.subscriptions.setNED(bool: enable)
                        case "XYZ":
                            json_r["stream"].stringValue = "XYZ"
                            self.subscriptions.setXYZ(bool: enable)
                        case "photo_LLA":
                            json_r["stream"].stringValue = "photo_LLA"
                            self.subscriptions.setPhotoLLA(bool: enable)
                        case "photo_XYZ":
                            json_r["stream"].stringValue = "photo_XYZ"
                            self.subscriptions.setPhotoXYZ(bool: enable)
                        case "currentWP":
                            json_r["stream"].stringValue = "currentWP"
                            self.subscriptions.setWpId(bool: enable)
                        default:
                            json_r = createJsonNack(fcn: "data_stream", description: "Stream faulty, " + json_m["stream"].stringValue)
                    }
                    
                default:
                    json_r = createJsonNack(fcn: json_m["fcn"].stringValue, description: "API call not recognized")
                    self.log("API call not recognized: " + json_m["fcn"].stringValue)
                    messageQualifiesForHeartBeat = false
                }
                if messageQualifiesForHeartBeat{
                    self.heartBeat.newBeat()
                }
                
                // Create string from json and send reply
                let reply_str = getJsonString(json: json_r)
                //print(reply_str)
                try socket.send(string: reply_str)
                                
                if json_r["fcn"].stringValue == "nack"{
                    print(json_r)
                }
                else if json_r["arg"].stringValue != "heart_beat" && json_r["arg"].stringValue != "info_request"{
                    //print("Reply:")
                    print(json_r)
                    //print(reply_str)
                }
                
               }
            catch {
                self.log(String(describing: error))
            }
        }
        return
    }
    
    
    //***************
    // Button actions
    //***************
    @IBAction func leftStepperAction(_ sender: UIStepper) {
        leftStepperLabel.text = String(sender.value/100)
        leftStepperName.text = "hPosKP"
        copter.hPosKP = Float(sender.value/100)
        print("hPosKP updated: ", Float(sender.value/100))
    }
    
    @IBAction func rightStepperAction(_ sender: UIStepper) {
        rightStepperLabel.text = String(sender.value/100)
        rightStepperName.text = "hPosKD"
        copter.hPosKD = Float(sender.value/100)
        print("hPosKD updated: ", Float(sender.value/100))
    }
    
    
    //*******************************************************************************************************
    // Exit view, but first deactivate Sticks (which invalidates fireTimer-timer to stop any joystick command)
 
    @IBAction func xClose(_ sender: UIButton) {
        print("xclose: Closing view and related tasks")
        
        // Allow display do be dimmed
        UIApplication.shared.isIdleTimerDisabled = false
        
        deactivateSticks()
        print("xClose: Sticks deactivated")
        
        // Stop the receiving thread
        self.replyEnable = false
        print("xClose: Rep-Req thread stopped")

        // Stop the publisher threads
        _ = ((try? self.infoPublisher?.close()) as ()??)
        _ = ((try? self.dataPublisher?.close()) as ()??)
        _ = try? self.context.close()
        _ = try? self.context.terminate()
        print("xClose: Info-link and data-link closed. Context terminated")

        
        // Stop listener prenumerations
        copter.stopListenToParam(DJIFlightControllerKeyString: DJIFlightControllerParamVelocity)
        copter.stopListenToParam(DJIFlightControllerKeyString: DJIFlightControllerParamFlightModeString)
        copter.stopListenToParam(DJIFlightControllerKeyString: DJIFlightControllerParamAircraftLocation)
        copter.stopListenToParam(DJIFlightControllerKeyString: DJIFlightControllerParamHomeLocation)
        print("xClose: Sopped listening to velocity-, flight mode-, position- and home location updates")

        self.dismiss(animated: true, completion: nil)
    }
    

    //************************************************************************************
    // ActivateSticks: Touch down up inside action, ativate when ready (release of button)
    @IBAction func ActivateSticksPressed(_ sender: UIButton) {
        if inControls == "PILOT"{
            // GIVE the controls to client
            inControls = "APPLICATION"
            // Prepare button text for next toggle
            controlsButton.setTitle("TAKE Controls", for: .normal)
            activateSticks()
            self.log("APPLICATION has the Controls")
        }
        else{
            // TAKE back the controls from CLIENT
            deactivateSticks()
            inControls = "PILOT"
            // Prepare button text for next toggle
            controlsButton.setTitle("GIVE Controls", for: .normal)
            self.log("PILOT has the Controls")
        }
    }

    //***************************************************************************************************************
    // Sends a command to go body right for some time at some speed per settings. Cancel any current joystick command
    @IBAction func DuttRightPressed(_ sender: UIButton) {

//        // Set a flight pattern
        switch rightTicker{
            case 0:
                copter.pattern.setPattern(pattern: "circle", relAlt: 15, heading: -2, radius: 10, yawRate: 20)
                self.log("Cricle +15 poi r10")
            case 1:
                copter.pattern.setPattern(pattern: "circle", relAlt: 20, heading: -1, radius: 15, yawRate: -20)
                self.log("Cricle +20 course r15")
            case 2:
                copter.pattern.setPattern(pattern: "circle", relAlt: 25, heading: 0, radius: 20, yawRate: 20)
                self.log("Cricle +25 north r20")
                // Reset ticker
                rightTicker = -1
            default:
                rightTicker = -1
        }
        rightTicker += 1
        print(rightTicker)
        
        // Set follow stream flag to true
        copter.followStream = true
     
        // Execute follow stream controller
        self.copter.startFollowStream()

    }

    //***************************************************************************************************************
    // Sends a command to go body left for some time at some speed per settings. Cancel any current joystick command
    @IBAction func DuttLeftPressed(_ sender: UIButton) {
        // Set the control command
        //copter.dutt(x: 0, y: -1, z: 0, yawRate: 0)
       
        switch leftTicker{
            case 0:
                copter.pattern.setPattern(pattern: "above", relAlt: 10, heading: 0)
                self.log("Above +10 north")
            case 1:
                copter.pattern.setPattern(pattern: "above", relAlt: 15, heading: -1)
                self.log("Above +15 course")
            case 2:
                copter.pattern.setPattern(pattern: "above", relAlt: 20, heading: -180)
                self.log("Above +20 south")
                // Reset ticker
                leftTicker = -1
            default:
                leftTicker = -1
        }
        leftTicker += 1
        print(leftTicker)
        
        // Set follow stream flag to true
        copter.followStream = true

        // Execute the follow stream controller
        self.copter.startFollowStream()
    }
    
    //**********************************************
    // Download and preview the last photo on sdCard
    @IBAction func previewPhotoButton(_ sender: Any) {
        // download a preview of last photo, dipsply preview
        cameraSetMode(DJICameraMode.mediaDownload, 2, completionHandler: {(succsess: Bool) in
            if succsess {
                self.getPreview(completionHandler: {(success: Bool) in
                    if success{
                        print("Preview downloaded and displayed.")
                    }
                    else{
                        self.log("Download preview Failed")
                        }
                    })
            }
            else{
                self.log("Set camera mode failed")
            }
        })
    }

    //*************************************************************************
    // Download last photoData from sdCard and save to app memory. Save URL to self.
    @IBAction func savePhotoButton(_ sender: Any) {
        savePhoto(sessionIndex: -1){(success) in
            if success{
                self.log("Photo saved to app memory")
            }
        }
    }
    
    
    //*************************************************
    // Update gui when nofication didposupdate happened
    @objc func onDidPosUpdate(_ notification: Notification){
        // These fields should perhaps be configurable to use.
        self.posXLabel.text = String(format: "%.1f", copter.loc.pos.x)
        self.posYLabel.text = String(format: "%.1f", copter.loc.pos.y)
        self.posZLabel.text = String(format: "%.1f", copter.loc.pos.z)
        
        // Check subscriptions and publish if enabled
        // LLA
        if subscriptions.LLA{
            var json = JSON()
            json["lat"].doubleValue = copter.loc.coordinate.latitude
            json["lon"].doubleValue = copter.loc.coordinate.longitude
            json["alt"].doubleValue = round(100 * copter.loc.altitude) / 100
            json["yaw"].doubleValue = copter.loc.heading
            json["agl"].doubleValue = -1
            _ = self.publish(socket: self.infoPublisher, topic: "LLA", json: json)
        }
        // NED
        if subscriptions.NED {
            var json = JSON()
            json["north"].doubleValue = round(100 * copter.loc.pos.north) / 100
            json["east"].doubleValue = round(100 * copter.loc.pos.east) / 100
            json["down"].doubleValue = round(100 * copter.loc.pos.down) / 100
            json["yaw"].doubleValue = copter.loc.heading
            json["agl"].doubleValue = -1
            _ = self.publish(socket: self.infoPublisher, topic: "NED", json: json)
        }
        // XYZ
        if subscriptions.XYZ{
            var json = JSON()
            json["x"].doubleValue = round(100 * copter.loc.pos.x) / 100
            json["y"].doubleValue = round(100 * copter.loc.pos.y) / 100
            json["z"].doubleValue = round(100 * copter.loc.pos.z) / 100
            json["agl"].doubleValue = -1
            json["heading"].doubleValue =
                round(100 * (copter.loc.gimbalYaw - self.copter.initLoc.gimbalYaw)) / 100
            _ = self.publish(socket: self.infoPublisher, topic: "XYZ", json: json)
        }
    }

    //************************************************************
    // Update gui when nofication didvelupdata happened  TEST only
    @objc func onDidVelUpdate(_ notification: Notification){
        //self.posXLabel.text = String(format: "%.1f", copter.velX)
        //self.posYLabel.text = String(format: "%.1f", copter.velY)
        //self.posZLabel.text = String(format: "%.1f", copter.velZ)
    }
    
    //******************************************************************************
    // Prints notification to log. Notifications can be sent from everywhere
    @objc func onDidPrintThis(_ notification: Notification){
        let strToPrint = String(describing: notification.userInfo!["printThis"]!)
        self.log(strToPrint)
    }
    
    //*************************************************
    // Update gui and publish when nofication didnextwp happened
    @objc func onDidNextWp(_ notification: Notification){
        if let data = notification.userInfo as? [String: String]{
            var json_o = JSON()
            for (key, value) in data{
                json_o[key] = JSON(value)
            }
            
            // print to screen
            log("Going to WP " + json_o["next_wp"].stringValue)

            // Publish if subscribed
            if self.subscriptions.WpId {
                _ = self.publish(socket: self.infoPublisher, topic: "currentWP", json:  json_o)
            }
        }
    }
    
    // ***************************************************************
    // Execute a wp action. Signal wpActionExecuting = false when done
    @objc func onDidWPAction(_ notification: Notification){
        if let data = notification.userInfo as? [String: String]{
            if data["wpAction"] == "take_photo"{
                self.log("wpAction: take photo")
                // Wait for allocator, allocate
                // must be in background to not halt everything.
                Dispatch.background {
                    while !self.cameraAllocator.allocate("take_photo", maxTime: 3){
                        usleep(300000)
                        //print("WP action trying to allocate camera")
                    }
                    self.printDB("Camera allocator allocated by wpAction")
                    self.takePhotoCMD()
                    // takePhotoCMD will execute and deallocate
                    while self.cameraAllocator.allocated{
                        usleep(200000)
                        //print("WP action waiting for takePhoto to complete")
                    }
                    // Stop contination of link is lost or application disconnected.
                    if self.heartBeat.alive() && !self.heartBeat.disconnected{
                        Dispatch.main {
                            _ = self.copter.gogo(startWp: 99, useCurrentMission: true) // startWP not used
                        }
                    }
                }
            }
            if data["wpAction"] == "land"{
                print("wpAction: land")
                // dispatch to background, delay and land?
                Dispatch.background {
                    var hover = 5
                    while hover > 0 {
                        self.log("Hover at home, landing in: " + String(describing: hover))
                        hover -= 1
                        usleep(1000000)
                    }
                    self.copter.land()
                    }
                }
        }
    }
    
    
    // ************
    // viewDidLoad
    override public func viewDidLoad() {
        super.viewDidLoad()  // run the viDidoad of the superclass

        // Trying to get rid of the mavic mini camera - label. The property is withon the DUXFPVViewController - fpvView.showCameraDisplayName
        // DUXFPVViewController is a SUBclass of DUXContentViewController. DUXContentViewContrller is a container for Vider and stuff and is a subclass of UIViweController.
        // https://forum.dji.com/thread-224097-1-1.html
        // https://github.com/dji-sdk/Mobile-UXSDK-iOS/blob/master/Sample%20Code/SwiftSampleCode/UXSDKSwiftSample/DefaultLayout/DefaultLayoutCustomizationViewController.swift
        // https://developer.dji.com/api-reference/ios-uilib-api/Widgets/DUXFPVView.html#duxfpvview_showcameradisplayname_inline
        //
        //        var modViewController: DUXFPVViewController = DUXFPVViewController()
        //        print("Flag is now: ", modViewController.fpvView?.showCameraDisplayName.description)
        //        modViewController.fpvView?.showCameraDisplayName.toggle()
        //        print("Flag is now: ", modViewController.fpvView?.showCameraDisplayName.description)
        //        self.contentViewController = modViewController
        
        // Prevent display from dimming. Will cause battery drain, but flight control is lost if display is dimmed..
        UIApplication.shared.isIdleTimerDisabled = true
        
        // Init steppers
        leftStepperStackView.isHidden = true
        leftStepperButton.value = Double(copter.hPosKP*100)
        leftStepperLabel.text = String(copter.hPosKP)
        rightStepperStackView.isHidden = true
        rightStepperButton.value = Double(copter.hPosKD*100)
        rightStepperLabel.text = String(copter.hPosKD)

        // Set up layout
        let radius: CGFloat = 5
        // Set corner radiuses to buttons
        controlsButton.layer.cornerRadius = radius
        DuttLeftButton.layer.cornerRadius = radius
        DuttRightButton.layer.cornerRadius = radius
        
        // Disable some buttons
        disableButton(DuttLeftButton)
        disableButton(DuttRightButton)
        
        // Hide some buttons. TODO remove of not used..
        takePhotoButton.isHidden = true
        previewButton.isHidden = true
        savePhotoButton.isHidden = true
        getDataButton.isHidden = true
        putDataButton.isHidden = true
        
        log("Setting up aircraft")
    
        // Setup aircraft
        var setupOk = true
        if let product = DJISDKManager.product() as? DJIAircraft {
            self.aircraft = product
            
            // Store flight controller reference in the Copter class
            if let fc = self.aircraft?.flightController {
                // Store the flightController reference
                self.copter.flightController = fc
                self.copter.initFlightController()
            }
            else{
                setupOk = false
                self.log("Flight controller not loaded")
            }
            
            // Store the camera refence
            if let cam = product.camera {
                // Implement the camera functions, including delegate in class CameraController.
                self.cameraTODO.camera = cam
                self.cameraTODO.initCamera()
                self.camera = cam
                self.camera?.setPhotoAspectRatio(DJICameraPhotoAspectRatio.ratio4_3, withCompletion: {(error) in
                    if error != nil{
                        self.log("Aspect ratio 4:3 could not be set")
                    }
                })
                self.startListenToCamera()
            }
            else{
                setupOk = false
                self.log("Camera not loaded")
            }
            // Store the gimbal reference
            if let gimbalReference = self.aircraft?.gimbal {
                self.copter.gimbal.gimbal = gimbalReference
                self.copter.gimbal.initGimbal()
            }
            else{
                setupOk = false
                self.log("Gimbal not loaded")
            }
        }
        else{
            setupOk = false
            self.log("Aircraft not loaded")
        }
        
        
        print("dscIP: ", dscIP)
        
//        // Hardcode Subscribe to stream
        let ipPort = "25.29.189.135:5560"
//        let port = "5560"
//        let ipPort = dscIP + ":" + port
        let endPointStr = "tcp://" + ipPort
        let topic = "LLA"
        if startGpsSubThread(endPoint: endPointStr, topic: topic){
            self.log("startGpsSubThread listening to :" + endPointStr + " topic: " + topic)
        }

        
        
        

        // Notification center,https://learnappmaking.com/notification-center-how-to-swift/
        NotificationCenter.default.addObserver(self, selector: #selector(onDidPosUpdate(_:)), name: .didPosUpdate, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onDidVelUpdate(_:)), name: .didVelUpdate, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onDidPrintThis(_:)), name: .didPrintThis, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onDidNextWp(_:)), name: .didNextWp, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onDidWPAction(_:)), name: .didWPAction, object: nil)
        
        _ = initPublisher()
        
        self.ownerID = "da000"
        if startReplyThread(){
            print("Reply thread successfully started")
            self.startHeartBeatThread()
        }
        else{
            setupOk = false
            self.log("Reply thread could not be started")
        }
        
        if setupOk == true{
            log("Aircraft componentes set up OK")
        }
        else{
            log("Setup failed. Close and reload this view")
        }
        
        


    }
    
    override public func viewWillAppear(_ animated: Bool) {
        //print("will appear")
        super.viewWillAppear(animated)
    }

    override public func viewDidAppear(_ animated: Bool) {
        //print("did appear")
        super.viewDidAppear(animated)
    }
    
    override public func viewWillLayoutSubviews() {
        //print("Will layout subviews")
        super.viewWillLayoutSubviews()
    }
    
    override public func viewDidLayoutSubviews() {
        //print("Did layout subviews")
        super.viewDidLayoutSubviews()
    }
}
