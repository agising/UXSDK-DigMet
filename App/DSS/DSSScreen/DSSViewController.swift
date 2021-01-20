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
import SwiftyZeroMQ // https://github.com/azawawi/SwiftyZeroMQ  good examples in readme
import SwiftyJSON // https://github.com/SwiftyJSON/SwiftyJSON good examples in readme

// ZeroMQ https://stackoverflow.com/questions/49204713/zeromq-swift-code-with-swiftyzeromq-recv-still-blocks-gui-text-update-even-a
// Build ZeroMQ https://www.ics.com/blog/lets-build-zeromq-library

// Background process https://stackoverflow.com/questions/24056205/how-to-use-background-thread-in-swift
// Related issue https://stackoverflow.com/questions/49204713/zeromq-swift-code-with-swiftyzeromq-recv-still-blocks-gui-text-update-even-a

// Generate App icons: https://appicon.co/


public class DSSViewController:  DUXDefaultLayoutViewController { //DUXFPVViewController {
    //**********************
    // Variable declarations
    
    var debug: Int = 0                  // 0 - off, 1 debug to screen, 2 debug to StatusLabel (user)
        
    var aircraft: DJIAircraft?
    var camera: DJICamera?
    var DJIgimbal: DJIGimbal?
    
    
    //var acks = 0
    var context: SwiftyZeroMQ.Context = try! SwiftyZeroMQ.Context()
    var infoPublisher: SwiftyZeroMQ.Socket?
    var dataPublisher: SwiftyZeroMQ.Socket?
    var replyEnable = false
    let replyEndpoint = "tcp://*:5557"
    let infoPublishEndPoint = "tcp://*:5558"
    let dataPublishEndPoint = "tcp://*:5559"
    //var sshAllocator = Allocator(name: "ssh")
    var subscriptions = Subscriptions()
    var inControls = "USER"
    
    var pitchRangeExtension_set: Bool = false
    var nextGimbalPitch: Int = 0
    
    //var gimbalcapability: [AnyHashable: Any]? = [:]
    var cameraModeAcitve: DJICameraMode = DJICameraMode.playback //shootPhoto
    var cameraAllocator = Allocator(name: "camera")
    var transferAllAllocator = Allocator(name: "transferAll")
    
    var copter = CopterController()
   
    var sessionLastIndex: Int = 0 // Picture index of this session
    var sdFirstIndex: Int = -1 // Start index of SDCard, updates at first download
    var transferring: Bool = false
    var jsonMetaData: JSON = JSON()                 // All the photo metadata
    var jsonPhotos: JSON = JSON()                   // Photos filename and downloaded status
        
    
    var idle: Bool = true                   // For future implementation of task que
    
    
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
    @IBOutlet weak var statusLabel: UILabel!
    @IBOutlet weak var DuttLeftButton: UIButton!
    @IBOutlet weak var DuttRightButton: UIButton!
    @IBOutlet weak var getDataButton: UIButton!
    @IBOutlet weak var putDataButton: UIButton!
    
    @IBOutlet weak var takePhotoButton: UIButton!
    @IBOutlet weak var previewButton: UIButton!
    @IBOutlet weak var savePhotoButton: UIButton!

    
    
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
    }
    
    //*****************************************************
    // Support function to step through gimbal pitch values
    func updateGnextGimbalPitch(){
        self.nextGimbalPitch -= 20
        if self.nextGimbalPitch < -40 {
            self.nextGimbalPitch = 20
        }
    }
    
    //**************************************************************************************************
    // Writes metadata to json. startLoc for the calulations, if it is not, set ut to current pos
    func writeMetaDataXYZ()->Bool{
        // Make sure startWP is set in order to be able to calc the local XYZ
        if !self.copter.startLoc.isStartLocation {
            // StartLocation is not set. Try to set it!
            if copter.setStartLocation(){
                print("writeMetaData: setStartLocation set from here")
                // In simulation the position is not updated until take-off. So we need to update the loc with the current gimbal data to the it right in simulation too.
                guard let heading = self.copter.getHeading() else {
                   print("writeMetaDataXYZ: Error updating heading")
                   return false}
                self.copter.loc.gimbalYaw = heading + self.copter.gimbal.yawRelativeToHeading
                
                // Start location is set, call the function again, return true because problem is fixed.
                _ = writeMetaDataXYZ()
                return true
            }
            else{
                self.printSL("writeMetaData: Could not setStartLocation, Aircraft ready?")
                return false
            }
        }

        var jsonMeta = JSON()
        jsonMeta["filename"] = JSON("")
        jsonMeta["x"] = JSON(self.copter.loc.pos.x)
        jsonMeta["y"] = JSON(self.copter.loc.pos.y)
        jsonMeta["z"] = JSON(self.copter.loc.pos.z)
        jsonMeta["agl"] = JSON(-1)
        // In sim loc.gimbalYaw does not update while on ground exept for first photo.
        jsonMeta["local_yaw"] = JSON(self.copter.loc.gimbalYaw - self.copter.startLoc.gimbalYaw)
        jsonMeta["index"] = JSON(self.sessionLastIndex)

        var jsonPhoto = JSON()
        jsonPhoto["filename"] = JSON("")
        jsonPhoto["stored"].boolValue = false
        
        self.jsonMetaData[String(self.sessionLastIndex)] = jsonMeta
        self.jsonPhotos[String(self.sessionLastIndex)] = jsonPhoto
        
        if self.subscriptions.photoXYZ{
            _ = self.publish(socket: self.infoPublisher, topic: "photo_XYZ", json: jsonMeta)
        }
        else{
            print(jsonMeta)
        }
        return true
    }
    

    
    // Move this somewhere.. Also start monitoring mode camera mode changes
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
                    if self.writeMetaDataXYZ(){
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
    // Print to terminal and update status label on screen
    func printSL(_ str: String){
        Dispatch.main{
            self.statusLabel.text = str
        }
        print(str)
    }
    
    func printDB(_ str: String){
        if debug == 1 {
            print(str)
        }
        if debug == 2 {
            self.printSL(str)
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
                self.printSL("Refresh file list Failed")
                return
            }
            
            // Get file references
            guard let files = manager?.sdCardFileListSnapshot() else {
                self.printSL("No photos on sdCard")
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
                    self.sessionLastIndex =  files.count - self.sdFirstIndex // In early bug photo was not always saved on SDcard, but sessionLastIndex is increased. This 'fixes' this issue..
                    print("SessionIndex faulty. Some images were not saved on sdCard..")
                }
                if self.jsonMetaData[String(i)]["filename"] == ""{
                    self.jsonMetaData[String(i)]["filename"].stringValue = files[self.sdFirstIndex + i - 1].fileName
                    self.jsonPhotos[String(i)]["filename"].stringValue = files[self.sdFirstIndex + i - 1].fileName
                    print("Added filename: " + files[self.sdFirstIndex + i - 1].fileName + " to sessionIndex: " + String(i))
                }
                else{
                    // Picture n has a filename -> so does n+1, +2, +3 etc break!
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
                    self.printSL("Error, set camera mode first: " + String(error!.localizedDescription))
                    completionHandler(false)
                }
                else if isComplete {
                    if let photoData = photoData{
                        //self.lastPhotoData = photoData
                        self.savePhotoDataToApp(photoData: photoData, filename: files[cameraIndex].fileName, sessionIndex: theSessionIndex)
                        completionHandler(true)
                        }
                    else{
                        self.printSL("Fetch photo from sdCard Failed")
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
                self.printSL("savePhotoDataToApp: Could not write photoData to App: " + String(describing: error))
            }
        }
    }
    
    // ***************************************************************************************************************
    // Transfers (publishes) all photos, downloads from sdCard if needed. transferAll allocates the rescource it self.
    func transferAll(){
        // Check if there are any photos to transfer
        if self.sessionLastIndex == 0 {
            print("transferAll: No photos to transfer")
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
                self.printSL("downloadAllHelper: Caution: " + String(skipped + 1) + " photos not transferred")
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
                            self.printSL("downloadAllHelper: All photos transferred")
                        }
                        else {
                            self.printSL("downloadAllHelper: Caution: " + String(skipped) + " photos not transferred")
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
                self.printSL("downloadSingle: Photo index: " + String(sessionIndex) + ", transferred")
            }
            else{
                self.printSL("downloadSingle: Filed to transfer index: " + String(sessionIndex))
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
        printSL("Transfer index: " + String(sessionIndex))
        if self.jsonPhotos[String(sessionIndex)].exists(){
            if jsonPhotos[String(sessionIndex)]["stored"] == false{
                printSL("transferIndex: Download photo: " + String(sessionIndex))
                // Allocate resource
                var maxTime = 41
                while !self.cameraAllocator.allocate("download", maxTime: 40){
                    // Sleep 0.1s
                    usleep(100000)
                    maxTime -= 1
                    if maxTime < 0 {
                        // Give up attempt to download index
                        self.printSL("transferIndex: Error, could not allocate cameraAllocator")
                        completionHandler(false)
                    }
                }
                // Allocator allocated
                self.savePhoto(sessionIndex: sessionIndex, completionHandler: {(saveSuccess) in
                    self.cameraAllocator.deallocate()
                    if saveSuccess {
                        self.printSL("transferIndex: Photo " + String(sessionIndex) + " downloaded to App")
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
                        self.printSL("transferIndex: Error, failed to download index " + String(sessionIndex))
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
                        self.printSL("transferIndex: Publish photo " + String(sessionIndex) + " on PUB-socket")
                        var json_photo = JSON()
                        json_photo["photo"].stringValue = getBase64utf8(data: photoData)
                        json_photo["metadata"] = self.jsonMetaData[String(sessionIndex)]
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
            self.printSL("transferIndex: Index has not been produced yet: " + String(sessionIndex))
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
                self.printSL("Refreshing file list failed.")
            }
            else{
                guard let files = manager?.sdCardFileListSnapshot() else {
                    self.printSL("No photos on sdCard")
                    completionHandler(true)
                    return
                }
                let cameraIndex = files.count - 1
                files[cameraIndex].fetchThumbnail(completion: {(error) in
                    if error != nil{
                        self.printSL("Error downloading thumbnail")
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
            self.printSL("Could not bind to socket")
            return false
        }
    }
    

    // ****************************************************
    // zmq reply thread that reads command from applictaion
    func readSocket(_ socket: SwiftyZeroMQ.Socket){
        while self.replyEnable{
            do {
                let _message: String? = try socket.recv()!
                if self.replyEnable == false{ // Since code can halt on socket.recv(), check if input is still desired
                    return
                }   

                // Parse and create an ack/nack
                let json_m = getJsonObject(uglyString: _message!)
                var json_r = JSON()
            
                switch json_m["fcn"]{
                case "arm_take_off":
                    self.printSL("Received cmd: arm_take_off")
                    if copter.getIsFlying() ?? false{ // Default to false to handle nil
                        json_r = createJsonNack("arm_take_off")
                    }
                    else{
                        let toAlt = json_m["arg"]["height"].doubleValue
                        if toAlt >= 2 && toAlt <= 40{
                            json_r = createJsonAck("arm_take_off")
                            copter.toAlt = toAlt
                            copter.toReference = "HOME"
                            copter.takeOff()
                        }
                        else{
                            json_r = createJsonNack("arm_take_off")
                        }
                    }
                case "data_stream":
                    self.printSL("Received cmd: data_stream, with attrubute: " + json_m["arg"]["attribute"].stringValue + " and enable: " + json_m["arg"]["enable"].stringValue)
                    // Data stream code
                    switch json_m["arg"]["attribute"]{
                        case "XYZ":
                            self.subscriptions.setXYZ(bool: json_m["arg"]["enable"].boolValue)
                            json_r = createJsonAck("data_stream")
                        case "photo_XYZ":
                            self.subscriptions.setPhotoXYZ(bool: json_m["arg"]["enable"].boolValue)
                            json_r = createJsonAck("data_stream")
                        case "WP_ID":
                            self.subscriptions.setWpId(bool: json_m["arg"]["enable"].boolValue)
                            json_r = createJsonAck("data_stream")
                        default:
                            json_r = createJsonNack("data_stream")
                    }
                case "disconnect":
                    json_r = createJsonAck("disconnect")
                    self.printSL("Received cmd: disconnect")
                    // Disconnect code
                    return
                case "gimbal_set":
                    self.printSL("Received cmd: gimbal_set")
                    json_r = createJsonAck("gimbal_set")
                    self.copter.gimbal.setPitch(pitch: json_m["arg"]["pitch"].doubleValue)
                    // No feedback, can't read the gimbal pitch value.
                    
                case "gogo_LLA":
                    self.printSL("Received cpmd: gogo_LLA")
                    if copter.getIsFlying() ?? false{ // Default to false to handle nil
                        let next_wp = json_m["arg"]["next_wp"].intValue
                        if copter.pendingMission["id" + String(next_wp)].exists(){
                                Dispatch.main{
                                    _ = self.copter.gogo(startWp: next_wp, useCurrentMission: false)
                                }
                                json_r = createJsonAck("gogo_LLA")
                            }
                            else{
                                json_r = createJsonNack("gogo_LLA")
                            }
                        }
                    else{
                         json_r = createJsonNack("gogo_LLA")
                    }

                case "gogo_NED":
                    self.printSL("Received cpmd: gogo_NED")
                    if copter.getIsFlying() ?? false{ // Default to false to handle nil
                        let next_wp = json_m["arg"]["next_wp"].intValue
                        if copter.pendingMission["id" + String(next_wp)].exists(){
                                Dispatch.main{
                                    _ = self.copter.gogo(startWp: next_wp, useCurrentMission: false)
                                }
                                json_r = createJsonAck("gogo_NED")
                            }
                            else{
                                json_r = createJsonNack("gogo_NED")
                            }
                        }
                    else{
                         json_r = createJsonNack("gogo_NED")
                    }

                case "gogo_XYZ":
                    self.printSL("Received cpmd: gogo_XYZ")
                    if copter.getIsFlying() ?? false{ // Default to false to handle nil
                        let next_wp = json_m["arg"]["next_wp"].intValue
                        if copter.pendingMission["id" + String(next_wp)].exists(){
                                Dispatch.main{
                                    _ = self.copter.gogo(startWp: next_wp, useCurrentMission: false)
                                }
                                json_r = createJsonAck("gogo_XYZ")
                            }
                            else{
                                json_r = createJsonNack("gogo_XYZ")
                            }
                        }
                    else{
                         json_r = createJsonNack("gogo_XYZ")
                    }

                case "heart_beat": // DONE
                    json_r = createJsonAck("heart_beat")
                    //print("Received heart_beat")
                    // Any heart beat code here
                    
                case "info_request":
                    json_r = createJsonAck("info_request")
                    // print("Received cmd: info_request", json_m["arg"])
                    // Info request code
                    switch json_m["arg"]{
                    case "operator":
                        json_r["arg2"].stringValue = "operator"
                        json_r["arg3"].stringValue = self.inControls
                    case "posD":
                        json_r["arg2"].stringValue = "posD"
                        json_r["arg3"] = JSON(self.copter.loc.pos.z)
                    case "armed":
                        json_r["arg2"].stringValue = "armed"
                        json_r["arg3"].boolValue = self.copter.getAreMotorsOn()
                    case "idle":
                        json_r["arg2"].stringValue = "idle"
                        json_r["arg3"].boolValue = self.idle
                    case "current_wp":
                        json_r["arg2"].stringValue = "current_wp"
                        json_r["arg3"].stringValue = copter.missionNextWp.description
                    case "metadata":
                        json_r["arg2"].stringValue = "metadata"
                        let sessionIndex = json_m["arg2"].intValue
                        if  sessionIndex == -1{
                            json_r["arg3"] = self.jsonMetaData
                        }
                        else{
                            if self.jsonMetaData[String(describing: sessionIndex)].exists(){
                                json_r["arg3"] = self.jsonMetaData[String(describing: sessionIndex)]
                            }
                            else{
                                json_r = createJsonNack("No such index for metadata")
                            }
                        }
                    default:
                        json_r = createJsonNack("info_request")
                        json_r["arg2"].stringValue = "Attribute not supported: " + json_m["arg"].stringValue
                    }
                case "land":
                    self.printSL("Received cmd: land")
                    json_r = createJsonAck("land")
                    if copter.getIsFlying() ?? false{ // Default to false to handle nil
                        json_r = createJsonAck("land")
                        copter.land()
                    }
                    else{
                        json_r = createJsonNack("land")
                    }
                case "photo":
                    switch json_m["arg"]["cmd"]{
                        case "take_photo":
                            self.printSL("Received cmd: photo, with arg take_photo")
                            
                            if self.cameraAllocator.allocate("take_photo", maxTime: 3) {
                                json_r = createJsonAck("photo")
                                json_r["arg2"].stringValue = "take_photo"
                                takePhotoCMD()
                            }
                            else{ // camera resource busy
                                json_r = createJsonNack("photo")
                            }
                        case "download":
                            self.printSL("Received cmd: photo, with arg download")
                            // Check if argument is ok, send reply and do actions in the background
                            let sessionIndex = json_m["arg"]["index"].intValue
                            // Index does not exist
                            if sessionIndex > self.sessionLastIndex {
                                self.printSL("Requested photo index does not exist " + String(sessionIndex) + " the last index available is: " + String(self.sessionLastIndex))
                                json_r = createJsonNack("photo")
                                json_r["arg2"] = JSON("index does not exist")
                                // Done
                            }
                            else if sessionIndex == -1 {
                                if transferAllAllocator.allocate("transferAll", maxTime: 300) {
                                    json_r = createJsonAck("photo")
                                    json_r["arg2"].stringValue = "download"
                                    // Transfer all in background, transferAll handles the allcoator
                                    Dispatch.background {
                                        // Transfer function handles the allocator
                                        self.printSL("Downloading all photos...")
                                        self.transferAll()
                                    }
                                }
                                else {
                                    json_r = createJsonNack("photo")
                                    json_r["arg2"] = JSON("download all already running")
                                    self.printSL("Dowload all nacked, already running")
                                }
                            }
                            // Index is 0 or less (but not -1 since it is already tested)
                            else if sessionIndex < 1 {
                                self.printSL("Requested photo index cannot not exist " + String(sessionIndex) + " index starts at 1")
                                json_r = createJsonNack("photo")
                                json_r["arg2"] = JSON("bad index")
                                // Done
                            }
                            // Index must be ok, download the index
                            else{
                                json_r = createJsonAck("photo")
                                json_r["arg2"].stringValue = "download"
                                Dispatch.background{
                                    // Download function handles the allocator
                                    self.printSL("Download photo index " + String(sessionIndex))
                                    self.transferSingle(sessionIndex: sessionIndex, attempt: 1)
                                }
                            }
                        default:
                            self.printSL("Received cmd: photo, with unknow arg: " + json_m["arg"]["cmd"].stringValue)
                            json_r = createJsonNack("photo")
                        }
                case "rtl":
                    self.printSL("Received cmd: rtl")
                    // We want to know if the command is accepted or not. Problem is that it takes ~1s to know for sure that the RTL is accepted (completion code of rtl) and we can't wait 1s with the reponse.
                    // Instead we look at flight mode which changes much faster, although we do not know for sure that the rtl is accepted. For example, the flight mode is already GPS after take-off..
                  
                    if copter.getIsFlying() == false {
                        json_r = createJsonNack("rtl")
                    }
                    else {
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
                                json_r = createJsonNack("rtl")
                                break
                            }
                        }
                        if copter.flightMode == "GPS" || copter.flightMode == "Landing" {
                            json_r = createJsonAck("rtl")
                        }
                    }
                case "dss_srtl":
                    // Once activated it should be possible to interfere TODO
                    self.printSL("Received comd: dss srtl")
                    json_r = createJsonAck("dss_srtl")
                    Dispatch.main{
                        self.copter.dssSrtl(hoverTime: json_m["arg"]["hover_time"].intValue)
                    }
                case "save_dss_home_position":
                    // Function saves dss smart rtl home position
                    self.printSL("Received cmd: save_dss_home_position")
                    if copter.saveCurrentPosAsDSSHome(){
                        json_r = createJsonAck("save_dss_home_position")
                    }
                    else {
                        json_r = createJsonNack("save_dss_home_position")
                        json_r["arg2"].stringValue = "Position not available"
                    }
                case "set_vel_body":
                    self.printSL("Received cmd: set_vel_body")
                    json_r = createJsonAck("set_vel_body")

                    // Set velocity code
                    // parse
                    let velX = Float(json_m["arg"]["vel_X"].stringValue) ?? 0
                    let velY = Float(json_m["arg"]["vel_Y"].stringValue) ?? 0
                    let velZ = Float(json_m["arg"]["vel_Z"].stringValue) ?? 0
                    let yawRate = Float(json_m["arg"]["yaw_rate"].stringValue) ?? 0
                    print("VelX: " + String(velX) + ", velY: " + String(velY) + ", velZ: " + String(velZ) + ", yawRate: "  + String(yawRate))
                    Dispatch.main{
                        self.copter.dutt(x: velX, y: velY, z: velZ, yawRate: yawRate)
                        self.printSL("Dutt command sent from readSocket")
                    }
                case "set_yaw":
                    self.printSL("Received cmd: set_yaw")
                    json_r = createJsonAck("set_yaw")
                    // Set yaw code TODO
                case "upload_mission_XYZ":
                    self.printSL("Received cmd: upload_mission_XYZ")
                    
                    let (success, arg) = copter.uploadMissionXYZ(mission: json_m["arg"])
                    if success{
                        json_r = createJsonAck("upload_mission_XYZ")
                    }
                    else{
                        json_r = createJsonNack("upload_mission_XYZ")
                        print("Mission upload failed: " + arg)
                    }
                case "upload_mission_NED":
                    self.printSL("Received cmd: upload_mission_NED")
                    
                    let (success, arg) = copter.uploadMissionNED(mission: json_m["arg"])
                    if success{
                        json_r = createJsonAck("upload_mission_NED")
                    }
                    else{
                        json_r = createJsonNack("upload_mission_NED")
                        print("Mission upload failed: " + arg)
                    }
                case "upload_mission_LLA":
                    self.printSL("Received cmd: upload_mission_LLA")
                    
                    let (success, arg) = copter.uploadMissionLLA(mission: json_m["arg"])
                    if success{
                        json_r = createJsonAck("upload_mission_LLA")
                    }
                    else{
                        json_r = createJsonNack("upload_mission_LLA")
                        print("Mission upload failed: " + arg)
                    }
                    
                default:
                    json_r = createJsonNack("API call not recognized")
                    self.printSL("API call not recognized: " + json_m["fcn"].stringValue)
                    // Code to handle faulty message
                }
                // Create string from json and send reply
                let reply_str = getJsonString(json: json_r)
                try socket.send(string: reply_str)
                                
                if json_r["fcn"].stringValue == "nack"{
                    print(json_r)
                }
                if json_r["arg"].stringValue != "heart_beat" && json_r["arg"].stringValue != "info_request"{
                    print("Reply:")
                   // print(json_r)
                    print(reply_str)
                }
                
               }
            catch {
                self.printSL(String(describing: error))
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
        print("xclose: Closing view an related tasks")
        
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
        if inControls == "USER"{
            // GIVE the controls to client
            inControls = "CLIENT"
            // Prepare button text for next toggle
            controlsButton.setTitle("TAKE Controls", for: .normal)
            activateSticks()
            self.printSL("CLIENT has the Controls")
        }
        else{
            // TAKE back the controls from CLIENT
            deactivateSticks()
            inControls = "USER"
            // Prepare button text for next toggle
            controlsButton.setTitle("GIVE Controls", for: .normal)
            self.printSL("USER has the Controls")
        }
    }

    //***************************************************************************************************************
    // Sends a command to go body right for some time at some speed per settings. Cancel any current joystick command
    @IBAction func DuttRightPressed(_ sender: UIButton) {
        // Set the control command
        copter.dutt(x: 0, y: 1, z: 0, yawRate: 0)
        
        
    }

    //***************************************************************************************************************
    // Sends a command to go body left for some time at some speed per settings. Cancel any current joystick command
    @IBAction func DuttLeftPressed(_ sender: UIButton) {
        // Set the control command
        copter.dutt(x: 0, y: -1, z: 0, yawRate: 0)
        
        
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
                        self.printSL("Download preview Failed")
                        }
                    })
            }
            else{
                self.printSL("Set camera mode failed")
            }
        })
    }

    //*************************************************************************
    // Download last photoData from sdCard and save to app memory. Save URL to self.
    @IBAction func savePhotoButton(_ sender: Any) {
        savePhoto(sessionIndex: -1){(success) in
            if success{
                self.printSL("Photo saved to app memory")
            }
        }
    }
    
    
    //*************************************************
    // Update gui when nofication didposupdate happened
    @objc func onDidXYZUpdate(_ notification: Notification){
        self.posXLabel.text = String(format: "%.1f", copter.loc.pos.x)
        self.posYLabel.text = String(format: "%.1f", copter.loc.pos.y)
        self.posZLabel.text = String(format: "%.1f", copter.loc.pos.z)
        
        // If subscribed to XYZ updates, also get local_yaw and publish
        if subscriptions.XYZ{
            var json = JSON()
            json["x"].doubleValue = round(100 * copter.loc.pos.x) / 100
            json["y"].doubleValue = round(100 * copter.loc.pos.y) / 100
            json["z"].doubleValue = round(100 * copter.loc.pos.z) / 100
            json["local_yaw"].doubleValue =
                round(100 * (copter.loc.gimbalYaw - self.copter.startLoc.gimbalYaw)) / 100
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
    // Prints notification to statuslabel. Notifications can be sent from everywhere
    @objc func onDidPrintThis(_ notification: Notification){
        let strToPrint = String(describing: notification.userInfo!["printThis"]!)
        self.printSL(strToPrint)
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
            printSL("Going to WP " + json_o["next_wp"].stringValue)

            // Publish if subscribed
            if self.subscriptions.WpId {
                _ = self.publish(socket: self.infoPublisher, topic: "WP_ID", json:  json_o)
            }
        }
    }
    
    // ***************************************************************
    // Execute a wp action. Signal wpActionExecuting = false when done
    @objc func onDidWPAction(_ notification: Notification){
        if let data = notification.userInfo as? [String: String]{
            if data["wpAction"] == "take_photo"{
                self.printSL("wpAction: take photo")
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
                    Dispatch.main {
                        _ = self.copter.gogo(startWp: 99, useCurrentMission: true) // startWP not used
                    }
                }
            }
            if data["wpAction"] == "land"{
                print("wpAction: land")
                // dispatch to background, delay and land?
                Dispatch.background {
                    var hover = 5
                    while hover > 0 {
                        self.printSL("Hover at home, landing in: " + String(describing: hover))
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
        
        
        printSL("Setting up aircraft")
    
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
                self.printSL("Flight controller not loaded")
            }
            
            // Store the camera refence
            if let cam = product.camera {
                self.camera = cam
                self.camera?.setPhotoAspectRatio(DJICameraPhotoAspectRatio.ratio4_3, withCompletion: {(error) in
                    if error != nil{
                        self.printSL("Aspect ratio 4:3 could not be set")
                    }
                })
                self.startListenToCamera()
            }
            else{
                setupOk = false
                self.printSL("Camera not loaded")
            }
            // Store the gimbal reference
            if let gimbalReference = self.aircraft?.gimbal {
                self.copter.gimbal.gimbal = gimbalReference
                self.copter.gimbal.initGimbal()
            }
            else{
                setupOk = false
                self.printSL("Gimbal not loaded")
            }
        }
        else{
            setupOk = false
            self.printSL("Aircraft not loaded")
        }
        

        // Notification center,https://learnappmaking.com/notification-center-how-to-swift/
        NotificationCenter.default.addObserver(self, selector: #selector(onDidXYZUpdate(_:)), name: .didXYZUpdate, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onDidVelUpdate(_:)), name: .didVelUpdate, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onDidPrintThis(_:)), name: .didPrintThis, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onDidNextWp(_:)), name: .didNextWp, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onDidWPAction(_:)), name: .didWPAction, object: nil)
        
        _ = initPublisher()
        if startReplyThread(){
            print("Reply thread successfully started")
        }
        else{
            setupOk = false
            self.printSL("Reply thread could not be started")
        }
        
        if setupOk == true{
            printSL("Aircraft componentes set up OK")
        }
        else{
            printSL("Setup failed. Close and reload this view")
        }

    }
}
