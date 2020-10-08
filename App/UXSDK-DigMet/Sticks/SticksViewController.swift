//
//  stickViewController.swift
//  UXSDKSwiftSample
//
//  Created by Andreas Gising on 2020-08-20.
//  Copyright © 2020 DJI. All rights reserved.
//

import UIKit
import DJIUXSDK
import DJIWidget
import NMSSH
import SwiftyZeroMQ // https://github.com/azawawi/SwiftyZeroMQ  good examples in readme
import SwiftyJSON // https://github.com/SwiftyJSON/SwiftyJSON good examples in readme

// ZeroMQ https://stackoverflow.com/questions/49204713/zeromq-swift-code-with-swiftyzeromq-recv-still-blocks-gui-text-update-even-a
// Build ZeroMQ https://www.ics.com/blog/lets-build-zeromq-library

// Background process https://stackoverflow.com/questions/24056205/how-to-use-background-thread-in-swift
// Related issue https://stackoverflow.com/questions/49204713/zeromq-swift-code-with-swiftyzeromq-recv-still-blocks-gui-text-update-even-a

public class SticksViewController: DUXDefaultLayoutViewController {
    //**********************
    // Variable declarations
    var aircraft: DJIAircraft?
    var camera: DJICamera?
    var DJIgimbal: DJIGimbal?
    
    
    var acks = 0
    
    
    var server = serverClass() // For test. Could get a JSON from http server.
    let hostIp = "192.168.1.245" //"192.168.43.14"//"10.114.17.0" //192.168.1.245"//25.22.96.189" // Use dict or something to store several ip adresses
    let hostUsername = "gising"
    let hostPath = "/Users/gising/temp/"
    var context: SwiftyZeroMQ.Context = try! SwiftyZeroMQ.Context()
    var infoPublisher: SwiftyZeroMQ.Socket?
    var dataPublisher: SwiftyZeroMQ.Socket?
    var replyEnable = false
    let replyEndpoint = "tcp://*:1234"
    let infoPublishEndPoint = "tcp://*:5558"
    let dataPublishEndPoint = "tcp://*:5559"
    var sshAllocator = Allocator(name: "ssh")
    var subscriptions = Subscriptions()
    
    var pitchRangeExtension_set: Bool = false
    var nextGimbalPitch: Int = 0
    
    var gimbalcapability: [AnyHashable: Any]? = [:]
    //var cameraModeReference: DJICameraMode = DJICameraMode.playback
    var cameraModeAcitve: DJICameraMode = DJICameraMode.playback //shootPhoto
    var cameraAllocator = Allocator(name: "camera")
    
    var copter = Copter()
    var gimbalController = GimbalController()
   
    var photo: UIImage = UIImage.init() // Is this used?
    var sessionIndex: Int = 0 // Picture index of this session
    var sdFirstIndex: Int = -1 // Start index of SDCard, updates at first download
    var jsonMetaData: JSON = JSON()
    
    var lastImage: UIImage = UIImage.init()
    var lastImagePreview: UIImage = UIImage.init()
    var lastImageFilename = ""
    var lastImageURL = ""
    var lastPhotoData: Data = Data.init()
    var lastPhotoDataURL: URL?
    var lastPhotoDataFilename = ""
    var metaDataURL: URL?
    var metaDataFilename = ""
    
    //var helperView = myView(coder: NSObject)

    //*********************
    // IBOutlet declaration: Labels
    @IBOutlet weak var controlPeriodLabel: UILabel!
    @IBOutlet weak var horizontalSpeedLabel: UILabel!
    
    @IBOutlet weak var posXLabel: UILabel!
    @IBOutlet weak var posYLabel: UILabel!
    @IBOutlet weak var posZLabel: UILabel!
    
    // IBOutlet declaration: ImageView
    @IBOutlet weak var previewImageView: UIImageView!
    
    // Steppers
    @IBOutlet weak var controlPeriodStepperButton: UIStepper!
    @IBOutlet weak var horizontalSpeedStepperButton: UIStepper!
    @IBOutlet weak var horizontalSpeedStackView: UIStackView!
    @IBOutlet weak var controlPeriodStackView: UIStackView!
    
    // Buttons
    @IBOutlet weak var DeactivateSticksButton: UIButton!
    @IBOutlet weak var ActivateSticksButton: UIButton!
    @IBOutlet weak var statusLabel: UILabel!
    @IBOutlet weak var DuttLeftButton: UIButton!
    @IBOutlet weak var DuttRightButton: UIButton!
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
        button.backgroundColor = UIColor.systemBlue
    }

    //***********************************************
    // Deactivate the sticks and disable dutt buttons
    func deactivateSticks(){
        //GUI handling
        DeactivateSticksButton.backgroundColor = UIColor.lightGray
        ActivateSticksButton.backgroundColor = UIColor.systemBlue
        disableButton(DuttLeftButton)
        disableButton(DuttRightButton)
        
        // Disable copter stick mode
        copter.stickDisable()
    }
    
    //****************************************************************
    // Activate sticks and dutt buttons, reset any velocity references
    func activateSticks(){
        //GUI handling
        ActivateSticksButton.backgroundColor = UIColor.lightGray
        DeactivateSticksButton.backgroundColor = UIColor.systemRed
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
    
    //**********************************************************************************************
    // Writes metadata to json. OriginXYZ is required to be set, if it is not, set ut to current pos
    func writeMetaDataXYZ()->Bool{
        guard let gimbalYaw = self.gimbalController.getYawRelativeToAircaftHeading() else {
            print("Error: writeMetaData gimbal yaw")
            return false}
        guard let heading = self.copter.getHeading() else {
            print("Error: writeMetaData copter heading")
            return false}
        guard let startHeadingXYZ = self.copter.startHeadingXYZ else {
            // OriginXYZ is not yet set. Try to set it!
            if copter.setOriginXYZ(gimbalYaw: gimbalYaw){
                print("OriginXYZ set from writeMetadata")
                // Go again!
                _ = writeMetaDataXYZ()
                // Return true because to problem is fixed and the func is called again.
                return true
            }
            else{
                self.printSL("Write metadata could not set OriginXYZ, aircraft ready?")
                return false
            }
        }


        var jsonMeta = JSON()
        let localYaw: Double = heading + gimbalYaw - startHeadingXYZ
        print("heading: ", heading, "gimbalYaw: ", gimbalYaw, "startHeadingXYZ: ", startHeadingXYZ)
        jsonMeta["filename"] = JSON("")
        jsonMeta["x"] = JSON(self.copter.posX)
        jsonMeta["y"] = JSON(self.copter.posY)
        jsonMeta["z"] = JSON(self.copter.posZ)
        jsonMeta["agl"] = JSON(-1)
        jsonMeta["local_yaw"] = JSON(localYaw)
        jsonMeta["index"] = JSON(self.sessionIndex)

        self.jsonMetaData[String(self.sessionIndex)] = jsonMeta
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
                    self.sessionIndex += 1
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
     
         // Don't loop for ever
         if attempts <= 0{
             NotificationCenter.default.post(name: .didPrintThis, object: self, userInfo: ["printThis": "Error: Camera set mode - too many"])
             completionHandler(false)
             return
         }
                     
         // Cameramode seems to automatically be reset to single photo. We cannot use local variable to store the mode. Hence getting and setting the current mode should intefere equally, it is better to set directly than first getting, checking and then setting.
         // Set mode to newCameraMode. If there is a fault call the function again.
         self.camera?.setMode(newCameraMode, withCompletion: {(error: Error?) in
             if error != nil {
                 self.cameraSetMode(newCameraMode, attempts - 1 , completionHandler: {(success: Bool) in
                 if success{
                     completionHandler(true)
                     }
                 })
             }
             else{
                 // Camera mode must be successfully set
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
    

    
    // Can be moved to separate file
    //*********************************************************
    // NOT USED Load an UIImage from memory using a path string
    func loadUIImageFromMemory(path: String){
        let photo = UIImage(contentsOfFile: path)
        self.previewImageView.image = photo
        print("Previewing photo from path")
    }
    
    //
    // Function executed when incoming command is download_picture
    func downloadPictureCMD(){
        // First download from sdCard
        self.savePhoto(completionHandler: {(saveSuccess) in
            self.cameraAllocator.deallocate()
            if saveSuccess {
                self.printSL("Image downloaded to App")
                print("Publish photo on PUB-socket")
                let photoData = self.lastPhotoData
                var json_photo = JSON()
                json_photo["photo"].stringValue = getBase64utf8(data: photoData)
                json_photo["metadata"] = self.jsonMetaData[String(self.sessionIndex)]
                print(self.jsonMetaData)
                _ = self.publish(socket: self.dataPublisher, topic: "photo", json: json_photo)
            }
            else{
                self.printSL("Download from sdCard Failed")
            }
        })
    }

    
    //**********************************************************************
     // Save photo from sdCardto app memory. Setup camera then call getImage
     func savePhoto(completionHandler: @escaping (Bool) -> Void){
         cameraSetMode(DJICameraMode.mediaDownload, 2, completionHandler: {(success: Bool) in
             if success {
                 self.getImage(completionHandler: {(new_success: Bool) in
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
    func getImage(completionHandler: @escaping (Bool) -> Void){
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
            self.printSL("Files on sdCard: " + String(describing: files.count))
            if self.sdFirstIndex == -1 {
                self.sdFirstIndex = files.count - self.sessionIndex
                // The files[self.sdFirstIndex] is the first photo of this photosession, it maps to self.jsonMetaData[self.sessionIndex = 1]
            }
            
            // Update Metadata with filename for the n last pictures without a filename added already
            for i in stride(from: self.sessionIndex, to: 0, by: -1){
                if files.count < self.sdFirstIndex + i{
                    self.sessionIndex =  files.count - self.sdFirstIndex // In early bug photo was not always saved on SDcard, but session index is increased. This 'fixes' this issue..
                    print("Session index faulty. Some images were not saved on sdCard..")
                }
                if self.jsonMetaData[String(i)]["filename"] == ""{
                    self.jsonMetaData[String(i)]["filename"].stringValue = files[self.sdFirstIndex + i - 1].fileName
                    print("Added filename: " + files[self.sdFirstIndex + i - 1].fileName + "To session index: " + String(i))
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
            
            let index = files.count - 1
            
            // Create a photo container for this scope
            var photoData: Data?
            var i: Int?
            
            // Download bachthwise, append data. Closure is called each time data is updated.
            files[index].fetchData(withOffset: 0, update: DispatchQueue.main, update: {(_ data: Data?, _ isComplete: Bool, error: Error?) -> Void in
                if error != nil{
                    // THis happens if download is triggered to close to taking a picture. Is the allocator used?
                    self.printSL("Error, set camera mode first: " + String(error!.localizedDescription))
                    completionHandler(false)
                }
                else if isComplete {
                    if let photoData = photoData{
                        self.lastPhotoData = photoData
                        self.savePhotoDataToApp(photoData: photoData, filename: files[index].fileName)
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
    // Save PhotoData to app, set URL to the objet
    func savePhotoDataToApp(photoData: Data, filename: String){
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        if let documentsURL = documentsURL {
            let fileURL = documentsURL.appendingPathComponent(filename)
            self.lastPhotoDataURL = fileURL
            self.lastPhotoDataFilename = filename
            do {
                try photoData.write(to: fileURL, options: .atomicWrite)
            } catch {
                self.printSL("Could not write photoData to App: " + String(describing: error))
            }
        }
    }
    
    //********************************************
    // Save PhotoData to app, set URL to the objet
    func saveDataToApp(data: Data, filename: String){
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        if let documentsURL = documentsURL {
            let fileURL = documentsURL.appendingPathComponent(filename)
            self.metaDataURL = fileURL
            self.metaDataFilename = filename
            do {
                try data.write(to: fileURL, options: .atomicWrite)
            } catch {
                self.printSL("Could not write Data to App: " + String(describing: error))
            }
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
                let index = files.count - 1
                files[index].fetchThumbnail(completion: {(error) in
                    if error != nil{
                        self.printSL("Error downloading thumbnail")
                        completionHandler(false)
                    }
                    else{
                        self.previewImageView.image = files[index].thumbnail
                        print("Thumbnail for preview")
                        completionHandler(true)
                    }
                })
            }
        })
    }
    
    
    
//    // Find the MetaData to attach when file is uploaded (if subscribed)
//                  var metaData = JSON()
//                  for i in stride(from: self.sessionIndex, to: 0, by: -1){
//                      if self.jsonMetaData[String(i)]["fileName"].stringValue == fileNameUploading{
//                          metaData = self.jsonMetaData[String(i)]
//                      }
//                  }
    
       
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
                print("Published photo with metadata: ")
                print(json["metadata"])
            }
            return true
        }
        catch{
            if topic == "photo"{
                print("Tried to publish photo, but failed.")
            }
            else{
            print("Tried to publish, but failed: " + publishStr)
            }
            return false
        }
    }
    

    // ******************************
    // Initiate the zmq reply thread.
    // MARK: ZMQ
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
                    self.printSL("Received cmd arm_take_off")
                    if copter.getIsFlying() ?? false{ // Default to false to handle nil
                        json_r = createJsonNack("arm_take_off")
                    }
                    else{
                        json_r = createJsonAck("arm_take_off")
                        copter.takeOff()
                    }
                case "data_stream":
                    self.printSL("Received cmd data_stream: " + json_m["arg"]["attribute"].stringValue + " - " + json_m["arg"]["enable"].stringValue)
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
                    self.printSL("Received cmd disconnect")
                    // Disconnect code
                    return
                case "gimbal_set":
                    self.printSL("Received cmd gimbal_set")
                    json_r = createJsonAck("gimbal_set")
                    self.gimbalController.setPitch(pitch: json_m["arg"]["pitch"].doubleValue)
                    // No feedback, can't read the gimbal pitch value.
                    
                case "gogo_XYZ":
                    self.printSL("Received cmd gogo_XYZ")
                    if copter.getIsFlying() ?? false{ // Default to false to handle nil
                        let next_wp = json_m["arg"]["next_wp"].intValue
                        if copter.pendingMission["id" + String(next_wp)].exists(){
                                Dispatch.main{
                                    _ = self.copter.gogoXYZ(startWp: next_wp, useCurrentMission: false)
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
                    self.printSL("Received cmd info_request")
                    // Info request code
                    switch json_m["arg"]{
                        case "operator":
                            json_r["arg2"].stringValue = "operator"
                            json_r["arg3"].stringValue = copter._operator
                    case "posD":
                        json_r["arg2"].stringValue = "posD"
                        json_r["arg3"] = JSON(copter.posZ)
                        
                        default:
                        _ = 1
                    }
                case "land":
                    self.printSL("Received cmd land")
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
                        self.printSL("Received cmd photo with arg take_photo")
                        
                        if self.cameraAllocator.allocate("take_photo", maxTime: 3) {
                            json_r = createJsonAck("photo")
                            json_r["arg2"].stringValue = "take_photo"
                            takePhotoCMD()
                        }
                        else{ // camera resource busy
                            json_r = createJsonNack("photo")
                        }
                    case "download":
                        self.printSL("Received cmd photo with arg download")
                        if self.cameraAllocator.allocate("download", maxTime: 14) {
                            json_r = createJsonAck("photo")
                            json_r["arg2"].stringValue = "download"
                            let index = json_m["arg"]["index"]
                            print("The download index argument: " + String(describing: index))
                            downloadPictureCMD()
                        }
                        else { // Camera resource busy
                            json_r = createJsonNack("photo")
                        }
                    default:
                        self.printSL("Received cmd photo with unknow arg: " + json_m["arg"]["cmd"].stringValue)
                        json_r = createJsonNack("photo")
                    }
                case "save_home_position":
                    self.printSL("Received cmd save_home_position")
                    json_r = createJsonAck("save_home_position")
                    copter.saveCurrentPosAsDSSHome()
                case "set_vel_body":
                    self.printSL("Received cmd set_vel_body")
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
                    self.printSL("Received cmd set_yaw")
                    json_r = createJsonAck("set_yaw")
                    // Set yaw code TODO
                case "upload_mission_XYZ":
                    self.printSL("Received cmd upload_mission_XYZ")
                    
                    let (success, arg) = copter.uploadMissionXYZ(mission: json_m["arg"])
                    if success{
                        json_r = createJsonAck("upload_mission_XYZ")
                    }
                    else{
                        json_r = createJsonNack("upload_mission_XYZ")
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
                if json_r["arg"].stringValue != "heart_beat"{
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
    
    
    // ****************************************************************************
    // Control period stepper. Experiments with execution time for joystick command
    @IBAction func controlPeriodStepper(_ sender: UIStepper) {
        controlPeriodLabel.text = String(sender.value/1000)
        // Uses stepper input and sampleTime to calculate how many loops fireDuttTimer should loop
        copter.loopTarget = Int(sender.value / copter.sampleTime)
    }
       
    //***********************************************************************************
    // Horizontal speed stepper. Experiments with velocity reference for joystick command
    @IBAction func horizontalSpeedStepper(_ sender: UIStepper) {
        horizontalSpeedLabel.text = String(sender.value/100)
        copter.xyVelLimit = Float(sender.value)
    }
       
    //*******************************************************************************************************
    // Exit view, but first deactivate Sticks (which invalidates fireTimer-timer to stop any joystick command
    @IBAction func xclose(_ sender: UIButton) {
        deactivateSticks()
        self.replyEnable = false
        
        _ = try? self.infoPublisher?.close()
        _ = try? self.dataPublisher?.close()
        _ = try? self.context.close()
        _ = try? self.context.terminate()
        copter.stopListenToPos()
        self.dismiss(animated: true, completion: nil)
    }
    
    //**************************************************************************************************
    // DeactivateSticks: Touch down action, deactivate immidiately and reset ActivateSticks button color
    @IBAction func DeactivateSticksPressed(_ sender: UIButton) {
        copter.stop()
        deactivateSticks()
        copter._operator = "USER" // Reject application control
    }

    //************************************************************************************
    // ActivateSticks: Touch down up inside action, ativate when ready (release of button)
    @IBAction func ActivateSticksPressed(_ sender: UIButton) {
        activateSticks()
        copter._operator = "CLIENT" // Allow application control
    }

    //***************************************************************************************************************
    // Sends a command to go body right for some time at some speed per settings. Cancel any current joystick command
    @IBAction func DuttRightPressed(_ sender: UIButton) {
        // Clear screen, lets fly!
        previewImageView.image = nil
        // Set the control command
        //copter.dutt(x: 0, y: 1, z: 0, yawRate: 0)
//        var json = JSON()
//        json["id0"] = JSON()
//        json["id0"]["x"] = JSON(1)
//        json["id0"]["y"] = JSON(2)
//        json["id0"]["z"] = JSON(-13)
//        json["id0"]["local_yaw"] = JSON(0)
//
//        json["id1"] = JSON()
//        json["id1"]["x"] = JSON(0)
//        json["id1"]["y"] = JSON(0)
//        json["id1"]["z"] = JSON(-16)
//        json["id1"]["local_yaw"] = JSON(0)
//
//        json["id2"] = JSON()
//        json["id2"]["x"] = JSON(1)
//        json["id2"]["y"] = JSON(2)
//        json["id2"]["z"] = JSON(-13)
//        json["id2"]["local_yaw"] = JSON(0)
//
//        let (success, arg) = copter.uploadMissionXYZ(mission: json)
//        if success{
//            _ = copter.gogoXYZ(startWp: 0)
//        }
//        else{
//            print("Mission failed to upload: " + arg!)
//        }
//        printJson(jsonObject: json)
    
        
        
//        if self.subscriptions.photoXYZ{
//            self.subscriptions.photo_XYZ = false
//            print("Subscription false")
//            self.gimbalController.setPitch(pitch: -90)
//        }
//        else{
//            self.subscriptions.photoXYZ = true
//            print("Subscription true")
//            self.gimbalController.setPitch(pitch: 12.2)
//        }
        self.downloadPictureCMD()
    }

    //***************************************************************************************************************
    // Sends a command to go body left for some time at some speed per settings. Cancel any current joystick command
    @IBAction func DuttLeftPressed(_ sender: UIButton) {
        // Load photo from library to be able to test scp without drone conencted. Could add dummy pic to App assets instead.
        //self.lastImage = loadUIImageFromPhotoLibrary()! // TODO, unsafe code
        //self.previewImageView.photo = loadUIImageFromPhotoLibrary()
        //savePhotoDataToApp(photoData: self.lastImage.jpegData(compressionQuality: 1)!, filename: "From_album.jpg")
        
        previewImageView.image = nil
        // Set the control command
        //copter.dutt(x: 0, y: -1, z: 0, yawRate: 0)
        //copter.stopListenToPos() test functionality of stop listen

//        var json = JSON()
//        json["id0"] = JSON()
//        json["id0"]["x"] = JSON(0)
//        json["id0"]["y"] = JSON(-2)
//        json["id0"]["z"] = JSON(-15)
//        json["id0"]["local_yaw"] = JSON(0)
//
//        json["id1"] = JSON()
//        json["id1"]["x"] = JSON(0)
//        json["id1"]["y"] = JSON(4)
//        json["id1"]["z"] = JSON(-18)
//        json["id1"]["local_yaw"] = JSON(0)
//
//        json["id2"] = JSON()
//        json["id2"]["x"] = JSON(0)
//        json["id2"]["y"] = JSON(-2)
//        json["id2"]["z"] = JSON(-15)
//        json["id2"]["local_yaw"] = JSON(0)
//
//        let (success, arg) = copter.uploadMissionXYZ(mission: json)
//         if success{
//            //copter.gogoXYZ(startWp: 0)
//         }
//         else{
//             print("Mission failed to upload: " + arg!)
//         }
        
       // _ = self.publish(topic: "no_topic", json: json)
        
       // printJson(jsonObject: json)
       
//        if let gimbalRelativeHeading = getYawRelativeToAircaftHeading(){
//            self.printSL("Yaw relative to ac :" + String(gimbalRelativeHeading))
//        }
//        else{
//            print("gimbal heading not available")
//        }
//        if copter.setOriginXYZ(){
//            print("originXYZ set")
//        }
//        else{
//            if copter.startHeadingXYZ != nil{
//                self.printSL("OriginXYZ cannot be updated")
//            }
//            else
//            {
//                print("Aircraft not ready to set OriginXYZ")
//            }
//        }
        NotificationCenter.default.post(name: .didNextWp, object: self, userInfo: ["next_wp": String(1), "final_wp": String(2), "cmd": "gogo_XYZ"])
        //copter.gogoXYZ(startWp: 0)
//        self.subscriptions.photoXYZ = true
//        takePhotoCMD()
    }
    
    //********************************************************
    // Set gimbal pitch according to scheeme and take a photo.
    @IBAction func takePhotoButton(_ sender: Any) {
         //copter.gotoXYZ(refPosX: 0, refPosY: 0, refPosZ: -15)

//        previewImageView.photo = nil
//        statusLabel.text = "Capture photo button pressed, preview cleared"

//        setGimbalPitch(pitch: self.nextGimbalPitch)
//        updateGnextGimbalPitch()
//
        copter.posCtrlTimer?.invalidate()
        // Dispatch to wait in the pitch movement, then capture an photo. TODO - use closure instead of stupid timer.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: {
            self.capturePhoto(completion: {(success) in
                if success {
                    self.printSL("Photo successfully taken")
                }
                else{
                    self.printSL("Photo from button press failed to complete")
                }
            })
        })
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
        savePhoto(){(success) in
            if success{
                self.printSL("Photo saved to app memory")
            }
        }
    }
    
    //***************************************************************************
    // Test button. Uses ssh to 'pwd' on the host and prints the answer to screen
    @IBAction func getDataButton(_ sender: UIButton) {
        Dispatch.background{
//            self.pwdAtServer(completion: {(success, info) in
//                Dispatch.main{
//                    if success{
//                        self.printSL("PWD result: " + info)
//                    }
//                    else{
//                        // Do something more..?
//                        self.printSL("PWD fail: " + info)
//                    }
//                }
//            })
        }
    }
    
    
    //*************************************************
    // Update gui when nofication didposupdata happened
    @objc func onDidPosUpdate(_ notification: Notification){
        self.posXLabel.text = String(format: "%.1f", copter.posX)
        self.posYLabel.text = String(format: "%.1f", copter.posY)
        self.posZLabel.text = String(format: "%.1f", copter.posZ)
        
        if subscriptions.XYZ{
            guard let gimbalYaw = self.gimbalController.getYawRelativeToAircaftHeading() else {
                print("Error: Update XYZ gimbal yaw")
                return}
            guard let heading = self.copter.getHeading() else {
                print("Error: Update XYZ copter heading")
                return}
            guard let startHeadingXYZ = self.copter.startHeadingXYZ else {
                print("Start pos is not set")
                // OriginXYZ is not yet set. Try to set it!
                return
                }
            
            let localYaw: Double = heading + gimbalYaw - startHeadingXYZ
            print("heading: ", heading, "gimbalYaw: ", gimbalYaw, "startHeadingXYZ: ", startHeadingXYZ)
            var json = JSON()
            json["x"].doubleValue = copter.posX
            json["y"].doubleValue = copter.posX
            json["z"].doubleValue = copter.posX
            json["local_yaw"].doubleValue = localYaw

            _ = self.publish(socket: self.infoPublisher, topic: "XYZ", json: json)
        }
    }

    //*************************************************
    // Update gui when nofication didvelupdata happened  TEST only
    @objc func onDidVelUpdate(_ notification: Notification){
        //self.posXLabel.text = String(format: "%.1f", copter.velX)
        //self.posYLabel.text = String(format: "%.1f", copter.velY)
        //self.posZLabel.text = String(format: "%.1f", copter.velZ)
    }
    
    //******************************************************************************
    // Prints notification to statuslabel. Notifications can be sent from everywhere
    @objc func onDidPrintThis(_ notification: Notification){
        self.printSL(String(describing: notification.userInfo!["printThis"]!))
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
                print("wp action take photo - Do it!")
                // Wait for allocator, allocate
                // must be in background to not halt everything. will that work?
                Dispatch.background {
                    while !self.cameraAllocator.allocate("take_photo", maxTime: 3){
                        usleep(300000)
                        //print("WP action trying to allocate camera")
                    }
                    print("Camera allocator allocated by wpAction")
                    self.takePhotoCMD()
                    // takePhotoCMD will execute and deallocate
                    while self.cameraAllocator.allocated{
                        usleep(200000)
                        //print("WP action waiting for takePhoto to complete")
                    }
                    Dispatch.main {
                        _ = self.copter.gogoXYZ(startWp: 99, useCurrentMission: true) // startWP not used
                    }
                }
            }
        }
    }
    
    //*************************************************************************
    //*************************************************************************
    
    // ************
    // viewDidLoad
    override public func viewDidLoad() {
        super.viewDidLoad()
        // Init steppers
        controlPeriodStepperButton.value = copter.controlPeriod
        controlPeriodLabel.text = String(copter.controlPeriod/1000)
        horizontalSpeedStepperButton.value = Double(copter.xyVelLimit)
        horizontalSpeedLabel.text = String(copter.xyVelLimit/100)
        horizontalSpeedStackView.isHidden = true
        controlPeriodStackView.isHidden = true
        
        // Set up layout
        let radius: CGFloat = 5
        // Set corner radiuses to buttons
        DeactivateSticksButton.layer.cornerRadius = radius
        ActivateSticksButton.layer.cornerRadius = radius
        DuttLeftButton.layer.cornerRadius = radius
        DuttRightButton.layer.cornerRadius = radius
        
        // Disable some buttons
        DeactivateSticksButton.backgroundColor = UIColor.lightGray
        disableButton(DuttLeftButton)
        disableButton(DuttRightButton)

        printSL("Setting up aircraft")
        //DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: {
        
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
                self.gimbalController.gimbal = gimbalReference
                self.gimbalController.initGimbal()
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
        

        // Test notification center,https://learnappmaking.com/notification-center-how-to-swift/
        //let posUpdateLabels = Notification.Name("posUpdateLabels")
        NotificationCenter.default.addObserver(self, selector: #selector(onDidPosUpdate(_:)), name: .didPosUpdate, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onDidVelUpdate(_:)), name: .didVelUpdate, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onDidPrintThis(_:)), name: .didPrintThis, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onDidNextWp(_:)), name: .didNextWp, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onDidWPAction(_:)), name: .didWPAction, object: nil)
        

        

        // Start subscriptions
        //copter.startListenToPos() // startListen to position requres home location for calculation of XYZ. Function is called when home pos is updated.

        
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
