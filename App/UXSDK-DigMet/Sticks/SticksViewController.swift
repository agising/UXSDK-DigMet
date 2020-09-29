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
    
    var server = serverClass() // For test. Could get a JSON from http server.
    let hostIp = "25.22.96.189" // Use dict or something to store several ip adresses
    let hostUsername = "gising"
    let hostPath = "/Users/gising/temp/"
    var context: SwiftyZeroMQ.Context = try! SwiftyZeroMQ.Context()
    var publisher: SwiftyZeroMQ.Socket?
    var replyEnable = false
    let replyEndpoint = "tcp://*:1234"
    let publishEndPoint = "tcp://*:5558"
    var sshAllocator = Allocator(name: "ssh")
    var subscriptions = Subscriptions()
    
    var pitchRangeExtension_set: Bool = false
    var nextGimbalPitch: Int = 0
    
    var gimbalcapability: [AnyHashable: Any]? = [:]
    var cameraModeReference: DJICameraMode = DJICameraMode.playback
    var cameraModeAcitve: DJICameraMode = DJICameraMode.shootPhoto
    var cameraAllocator = Allocator(name: "camera")
    
    var copter = Copter()
    var gimbal = Gimbal()
   
    var image: UIImage = UIImage.init() // Is this used?
    var image_index: UInt?
    var sessionIndex: Int = 0 // Picture index of this session
    var sdFirstIndex: Int = -1 // Start index of SDCard, updates at first download
    var jsonMetaData: JSON = JSON()
    
    var lastImage: UIImage = UIImage.init()
    var lastImagePreview: UIImage = UIImage.init()
    var lastImageFilename = ""
    var lastImageURL = ""
    var lastImageData: Data = Data.init()
    var lastImageDataURL: URL?
    var lastImageDataFilename = ""
    
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
        self.image_index = 0
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
    
    func writeMetaDataXYZ()->Bool{
        guard let gimbalYaw = self.gimbal.getYawRelativeToAircaftHeading() else {
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
        jsonMeta["fileName"] = JSON("")
        jsonMeta["x"] = JSON(self.copter.posX)
        jsonMeta["y"] = JSON(self.copter.posY)
        jsonMeta["z"] = JSON(self.copter.posZ)
        jsonMeta["agl"] = JSON(-1)
        jsonMeta["local_yaw"] = JSON(localYaw)

        self.sessionIndex += 1
        self.jsonMetaData[String(self.sessionIndex)] = jsonMeta
        print(jsonMeta)
        return true
    }
    
    
    //*************************************************************
    // captureImage sets up the camera if needed and takes a photo.
    func captureImage(completion: @escaping (Bool)-> Void ) {
        // Make sure camera is in the correct mode
        self.cameraSetMode(DJICameraMode.shootPhoto, 1, completionHandler: {(succsess: Bool) in
            if succsess{
                // Make sure shootPhotoMode is single, if so, go ahead startShootPhoto
                self.camera?.setShootPhotoMode(DJICameraShootPhotoMode.single, withCompletion: {(error: Error?) in
                    // Take photo and save to sdCard
                    self.camera?.startShootPhoto(completion: { (error) in
                        // startShootPhoto returns before resource is available for next action, wait to be sure resource is available when code returns.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: {
                            if error != nil {
                                NSLog("Shoot Photo Error: " + String(describing: error))
                                completion(false)
                            }
                            else{ // Write metadata
                                if self.subscriptions.image_XYZ{
                                    if self.writeMetaDataXYZ(){
                                        // Metadata was successfully written
                                        _ = 1
                                    }
                                    else{
                                        print("MetaData failed to write, initiating ")
                                    }
                                }
                                completion(true)
                            }
                        })
                    })
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
    func takePictureCMD(){
        Dispatch.background{
            self.captureImage(completion: {(success) in
                self.cameraAllocator.deallocate()
                Dispatch.main{
                    if success{
                        self.printSL("Take Photo sucessfully completed")
                        //self.cameraAllocator.deallocate()
                    }
                    else{
                        self.printSL("Take Photo failed to complete")
                        //lself.cameraAllocator.deallocate()
                    }
                }
            })
            
        }

    }
    // ***********************************************************************************************************************************************
    // cameraSetMode checks if the newCamera mode is the active mode, and if not it tries to set the mode 'attempts' times. TODO - is attemtps needed?
    func cameraSetMode(_ newCameraMode: DJICameraMode,_ attempts: Int, completionHandler: @escaping (Bool) -> Void) {
        if attempts <= 0{
            self.printSL("CameraSetMode error: too many")
            completionHandler(false)
        }
        self.cameraModeReference = newCameraMode
        // Check if the wanted camera mode is already set
        self.camera?.getModeWithCompletion( {(mode: DJICameraMode, error: Error?) in
            if error != nil{
                self.printSL("CameraGetMode Error: " + error.debugDescription)
                completionHandler(false)
            }
            else{
                self.cameraModeAcitve = mode
                if self.cameraModeAcitve == self.cameraModeReference{
                    print("Camera Mode is set")
                    completionHandler(true)
                }
                else{
                    self.camera?.setMode(newCameraMode, withCompletion: {(error) in
                        self.cameraSetMode(newCameraMode, attempts - 1, completionHandler: {(succsess: Bool) in
                            if succsess{
                                completionHandler(true) // refers to inital completionHandler
                            }
                        })
                    })
                }
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
    
    //********************************************
    // Save ImageData to app, set URL to the objet
    func saveImageDataToApp(imageData: Data, filename: String){
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        if let documentsURL = documentsURL {
            let fileURL = documentsURL.appendingPathComponent(filename)
            self.lastImageDataURL = fileURL
            self.lastImageDataFilename = filename
            do {
                try imageData.write(to: fileURL, options: .atomicWrite)
            } catch {
                self.printSL("Could not write imageData to App: " + String(describing: error))
            }
        }
    }
    
    
    // Can be moved to separate file
    //*********************************************************
    // NOT USED Load an UIImage from memory using a path string
    func loadUIImageFromMemory(path: String){
        let image = UIImage(contentsOfFile: path)
        self.previewImageView.image = image
        print("Previewing image from path")
    }
    
    //
    // Function executed when incoming command is download_picture
    func downloadPictureCMD(){
    // Download picture code
        Dispatch.background{
            // First download from sdCard
            self.savePhoto(completionHandler: {(saveSuccess) in
                print("Deallocating cameraAllocator")
                self.cameraAllocator.deallocate()
                if saveSuccess {
                    self.printSL("Image downloaded to App")
                    
                    Dispatch.superBackground{
                        // Scp to server. Use ssh allocator
                        if self.sshAllocator.allocate("download_picture", maxTime: 50){
                            self.scpToServer(completion: {(scpSuccess, pending, info) in
                                Dispatch.main{
                                    if pending{
                                        self.printSL(info)
                                    }
                                    else{
                                        if scpSuccess{
                                            self.printSL("Uploaded: " + info)
                                            print("Scp to server ok")
                                        }
                                        else{
                                            self.printSL("Scp failed: " + info)
                                        }
                                        self.sshAllocator.deallocate()
                                    }
                                }
                            })
                        }
                        else{
                            self.printSL("Ssh allocator busy")
                        }
                    }
                }
                else{
                    self.printSL("Download from sdCard Failed")
                }
            })
        }
    }

    
    //**********************************************************************
     // Save photo from sdCardto app memory. Setup camera then call getImage
     func savePhoto(completionHandler: @escaping (Bool) -> Void){
         cameraSetMode(DJICameraMode.mediaDownload, 1, completionHandler: {(success: Bool) in
             if success {

                 self.getImage(completionHandler: {(new_success: Bool) in
                     if new_success{
                         //self.printSL("Photo downloaded and saved to App memory")
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
    // Downloads an imageData from sdCard. Saves imageData to app. Can previews image on screen
    func getImage(completionHandler: @escaping (Bool) -> Void){
        let manager = self.camera?.mediaManager
        manager?.refreshFileList(of: DJICameraStorageLocation.sdCard, withCompletion: {(error: Error?) in
            print("Refreshing file list...")
            if error != nil {
                completionHandler(false)
                self.printSL("Refresh file list Failed")
            }
            else{ // Get file references
                guard let files = manager?.sdCardFileListSnapshot() else {
                    self.printSL("No images on sdCard")
                    completionHandler(false)
                    return
                }
                self.printSL("Files on sdCard: " + String(describing: files.count))
                if self.sdFirstIndex == -1 {
                    self.sdFirstIndex = files.count - self.sessionIndex
                    // The files[self.sdFirstIndex] is the first photo of this photosession, it maps to self.jsonMetaData[self.sessionIndex = 1]
                }
                // Update Metadata with filename for the n last pictures without a filename added already
                for i in stride(from: self.sessionIndex, to: 0, by: -1){
                    if self.jsonMetaData[String(i)]["fileName"] == ""{
                        self.jsonMetaData[String(i)]["fileName"].stringValue = files[self.sdFirstIndex + i - 1].fileName
                        print("Added filename: " + files[self.sdFirstIndex + i - 1].fileName + "To session index: " + String(i))
                    }
                    else{
                        break
                    }
                }

                let index = files.count - 1
                // Create a image container for this scope
                var imageData: Data?
                var i: Int?
                // Download bachthwise, append data. Closure is called each time data is updated.
                files[index].fetchData(withOffset: 0, update: DispatchQueue.main, update: {(_ data: Data?, _ isComplete: Bool, error: Error?) -> Void in
                    if error != nil{
                        // THis happens if download is triggered to close to taking a picture. Is the allocator used?
                        self.printSL("Error, set camera mode first: " + String(error!.localizedDescription))
                        completionHandler(false)
                    }
                    else if isComplete { // No more data blocks to collect
                        if let imageData = imageData{
                            // let encodedImageData = imageData.base64EncodedData() https://github.com/DavidBolis261/Previous_Work/blob/master/Base64Encoding&Decoding.swift
                            self.saveImageDataToApp(imageData: imageData, filename: files[index].fileName)
                            //let image = UIImage(data: imageData)
                            //self.lastImage = image!
                            //self.lastImageFilename = files[index].fileName
                            //self.printSL("UIImage saved to self, showing image preview. Filename:" + self.lastImageFilename)
                            completionHandler(true)
                            }
                        else{
                            self.printSL("Fetch image from sdCard Failed")
                            completionHandler(false)
                        }
                    }
                    else {
                        // If image has been initialized, append the updated data to it
                        if let _ = imageData, let data = data {
                            imageData?.append(data)
                            i! += 1
                            // TODO - progress bar
                            //self.printSL("Appending data to image" + String(describing: i))
                        }
                        // initialize the image data
                        else {
                            imageData = data
                            i = 1
                        }
                    }
                })
            }
        })
    }
    
    // Can be moved to separate file
    // ******************************************************************
    // Download the preview of the last image taken. Preview it on screen
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
                    self.printSL("No images on sdCard")
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

    // Scp image saved to app memory to host. Connect using RSA-keys. SFTP could be faster. Also increse buffer size could have impact. Approx 45s from photo to file on server over vpn, 12s over local network..
    // generate rsa key using ssh-keygen -m PEM to get it the requred format! https://github.com/NMSSH/NMSSH/issues/265
    func scpToServer(completion: @escaping (Bool, Bool, String) -> Void){
        // OSX acitvate sftp server by enablign file sharing in system prefs
        // sftp session muyst be silent.. add this to bashrc on server [[ $- == *i* ]] || return, found at https://unix.stackexchange.com/questions/61580/sftp-gives-an-error-received-message-too-long-and-what-is-the-reason
        var success = false
        var info = ""
        var pending = true
        // Pick up private key from file.
        let urlPath = Bundle.main.url(forResource: "digmet_id_rsa", withExtension: "")

        // Try privatekeysting
        do{
         let privatekeystring = try String(contentsOf: urlPath!, encoding: .utf8)
         let ip = self.hostIp
         let username = self.hostUsername
         let session = NMSSHSession(host: ip, andUsername: username)
        
         completion(success, pending, "Connecting to server..")
         session.connect()
         if session.isConnected == true{
             session.authenticateBy(inMemoryPublicKey: "", privateKey: privatekeystring, andPassword: nil)
             if session.isAuthorized == true {
                // Upload Data object
                completion(success, pending, "Uploading " + self.lastImageDataFilename + "...")
                let fileNameUploading = self.lastImageDataFilename // This can change during upload process..
                
                // Find the MetaData to attach when file is uploaded (if subscribed)
                var metaData = JSON()
                for i in stride(from: self.sessionIndex, to: 0, by: -1){
                    if self.jsonMetaData[String(i)]["fileName"].stringValue == fileNameUploading{
                        metaData = self.jsonMetaData[String(i)]
                    }
                }
                
                // Upload the file
                session.channel.uploadFile(self.lastImageDataURL!.path, to: self.hostPath)
                info = fileNameUploading
                if self.subscriptions.image_XYZ{
                    _ = self.publish(topic: "image_XYZ", json: metaData)
                }
                success = true
             }
             else{
                info = "Not authorized"
                success = false
             }
             session.disconnect()
         }
         else{
             info = "Could not connect to: " + String(describing: ip) + " Check ip refernce."
             success = false
         }
        }
       catch {
        info = "Private keystring could not be loaded from file"
        success = false
        }
    pending = false
    completion(success, pending, info)
    }

       //**********************************************
       // SSH into host, pwd and print result to screen
    func pwdAtServer(completion: @escaping (Bool, String) -> Void ){
        let urlPath = Bundle.main.url(forResource: "digmet_id_rsa", withExtension: "")
        var success = false
        var returnStr = ""
            
        // Try privatekeysting
        do{
            let privatekeystring = try String(contentsOf: urlPath!, encoding: .utf8)
            let ip = self.hostIp
            let username = self.hostUsername
            let session = NMSSHSession(host: ip, andUsername: username)
    
            
            session.connect()
            if session.isConnected == true{
                session.authenticateBy(inMemoryPublicKey: "", privateKey: privatekeystring, andPassword: nil)
                if session.isAuthorized == true {
                    var error: NSError?
                    let response: String = session.channel.execute("pwd", error: &error)
                    let lines = response.components(separatedBy: "\n")
                    returnStr = lines[0]
                    success = true
                }
                else{
                    success = false
                    returnStr = "Authentication failed"
                }
                session.disconnect()
            }
            else{
                success = false
                returnStr = "Could not connect to: " + String(describing: ip) + " Check ip refernce."
            }
           }
           catch{
            success = false
               returnStr = "Could not read rsa keyfile"
           }
        completion(success, returnStr)
   }

       
    //**************************
    // Init the publisher socket
    func initPublisher()->Bool{
        do{
            self.publisher = try context.socket(.publish)
            try self.publisher?.bind(self.publishEndPoint)
            return true
            }
        catch{
            return false
        }
    }
    
    func publish(topic: String, json: JSON)->Bool{
        let json_s = getJsonString(json: json)
        do{
            let publishStr = topic + " " + json_s
            try self.publisher?.send(string: publishStr)
            print("Published: " + publishStr)
            return true
        }
        catch{
            print("Tried to publish, but failed: " + json_s)
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
                    self.printSL("Received cmd data_stream: " + json_m["arg"]["attribute"].stringValue)
                    // Data stream code
                    switch json_m["arg"]["attribute"]{
                        case "XYZ":
                            self.subscriptions.XYZ = json_m["arg"]["enable"].boolValue
                            json_r = createJsonAck("data_stream")
                        case "image_XYZ":
                            self.subscriptions.image_XYZ = json_m["arg"]["enable"].boolValue
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
                    self.gimbal.setPitch(pitch: json_m["arg"]["pitch"].doubleValue)
                    // No feedback, can't read the gimbal pitch value.
                    
                case "gogo_XYZ":
                    self.printSL("Received cmd gogo_XYZ")
                    if copter.getIsFlying() ?? false{ // Default to false to handle nil
                        let next_wp = json_m["arg"]["next_wp"].intValue
                        if copter.pendingMission["id" + String(next_wp)].exists(){
                                Dispatch.main{
                                    _ = self.copter.gogoXYZ(startWp: next_wp)
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
                    if copter.getIsFlying() ?? false{ // Default to flase to handle nil
                        json_r = createJsonAck("land")
                        copter.land()
                    }
                    else{
                        json_r = createJsonNack("land")
                    }
                case "photo":
                switch json_m["arg"]["cmd"]{
                    case "take_picture":
                        self.printSL("Received cmd photo with arg take_picture")
                        if self.cameraAllocator.allocate("take_picture", maxTime: 3) {
                            json_r = createJsonAck("photo")
                            takePictureCMD()
                        }
                        else{ // camera resource busy
                            json_r = createJsonNack("photo")
                        }
                    case "download_picture":
                        self.printSL("Received cmd photo with arg download_picture")
                        if self.cameraAllocator.allocate("download_picture", maxTime: 12) {
                            json_r = createJsonAck("photo")
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
                    // Must dispatch to main for command to go through.
                    print("Testing if copter is available from here in code TODO: " + String(describing: copter.ref_velX))
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
                        print("Mission upload failed: " + arg!)
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
                    print(json_r)
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
        
        _ = try? self.publisher?.close()
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
        var json = JSON()
        json["id0"] = JSON()
        json["id0"]["x"] = JSON(1)
        json["id0"]["y"] = JSON(2)
        json["id0"]["z"] = JSON(-13)
        json["id0"]["local_yaw"] = JSON(0)

        json["id1"] = JSON()
        json["id1"]["x"] = JSON(0)
        json["id1"]["y"] = JSON(0)
        json["id1"]["z"] = JSON(-16)
        json["id1"]["local_yaw"] = JSON(0)

        json["id2"] = JSON()
        json["id2"]["x"] = JSON(1)
        json["id2"]["y"] = JSON(2)
        json["id2"]["z"] = JSON(-13)
        json["id2"]["local_yaw"] = JSON(0)

        let (success, arg) = copter.uploadMissionXYZ(mission: json)
        if success{
            _ = copter.gogoXYZ(startWp: 0)
        }
        else{
            print("Mission failed to upload: " + arg!)
        }
        printJson(jsonObject: json)
    
        
//        if self.subscriptions.image_XYZ{
//            self.subscriptions.image_XYZ = false
//            print("Subscription false")
//            self.gimbal.setPitch(pitch: -90)
//        }
//        else{
//            self.subscriptions.image_XYZ = true
//            print("Subscription true")
//            self.gimbal.setPitch(pitch: 12.2)
//        }
    }

    //***************************************************************************************************************
    // Sends a command to go body left for some time at some speed per settings. Cancel any current joystick command
    @IBAction func DuttLeftPressed(_ sender: UIButton) {
        // Load image from library to be able to test scp without drone conencted. Could add dummy pic to App assets instead.
        //self.lastImage = loadUIImageFromPhotoLibrary()! // TODO, unsafe code
        //self.previewImageView.image = loadUIImageFromPhotoLibrary()
        //saveImageDataToApp(imageData: self.lastImage.jpegData(compressionQuality: 1)!, filename: "From_album.jpg")
        
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
        
        copter.gogoXYZ(startWp: 0)
        takePictureCMD()
        

    }
    
    //********************************************************
    // Set gimbal pitch according to scheeme and take a photo.
    @IBAction func takePhotoButton(_ sender: Any) {
         //copter.gotoXYZ(refPosX: 0, refPosY: 0, refPosZ: -15)

//        previewImageView.image = nil
//        statusLabel.text = "Capture image button pressed, preview cleared"

//        setGimbalPitch(pitch: self.nextGimbalPitch)
//        updateGnextGimbalPitch()
//
        copter.posCtrlTimer?.invalidate()
        // Dispatch to wait in the pitch movement, then capture an image. TODO - use closure instead of stupid timer.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: {
            self.captureImage(completion: {(success) in
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
    // Download and preview the last image on sdCard
    @IBAction func previewPhotoButton(_ sender: Any) {
        // download a preview of last photo, dipsply preview
        cameraSetMode(DJICameraMode.mediaDownload, 3, completionHandler: {(succsess: Bool) in
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
    // Download last imageData from sdCard and save to app memory. Save URL to self.
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
            self.pwdAtServer(completion: {(success, info) in
                Dispatch.main{
                    if success{
                        self.printSL("PWD result: " + info)
                    }
                    else{
                        // Do something more..?
                        self.printSL("PWD fail: " + info)
                    }
                }
            })
        }
    }
    
    //***********************************************
    // Button to scp the last saved imageData to host
    @IBAction func putDatabutton(_ sender: UIButton) {
        if self.lastImageDataURL == nil{
            self.printSL("No image to upload")
            return
        }
        if self.cameraAllocator.allocate("download_picture", maxTime: 12) {
            downloadPictureCMD()
        }
        else{
            self.printSL("Resource busy")
        }
        // If testing without drone, use this code instead of cameraAllocator.
//        else{
//            Dispatch.background{
//                self.scpToServer(completion: {(success, pending, info) in
//                    Dispatch.main{
//                        if pending{
//                            self.printSL(info)
//                        }
//                        else{
//                            if success{
//                                self.printSL("SCP ok: " + info)
//                            }
//                            else{
//                                // Do something more..?
//                                self.printSL("SCP fail: " + info)
//                            }
//                        }
//                    }
//                })
//            }
//        }
    }
    
    @objc func onDidPosUpdate(_ notification: Notification){
        self.posXLabel.text = String(format: "%.1f", copter.posX)
        self.posYLabel.text = String(format: "%.1f", copter.posY)
        self.posZLabel.text = String(format: "%.1f", copter.posZ)
    }
    
    @objc func onDidVelUpdate(_ notification: Notification){
        //self.posXLabel.text = String(format: "%.1f", copter.velX)
        //self.posYLabel.text = String(format: "%.1f", copter.velY)
        //self.posZLabel.text = String(format: "%.1f", copter.velZ)
    }
    
    @objc func onDidPrintThis(_ notification: Notification){
        self.printSL(String(describing: notification.userInfo!["printThis"]!))
    }
    
    @objc func onDidNextWp(_ notification: Notification){
        if let data = notification.userInfo as? [String: String]{
            var json_o = JSON()
            for (key, value) in data{
                json_o[key] = JSON(value)
            }
            _ = self.publish(topic: "WP_ID", json:  json_o)
            printSL("Going to WP " + json_o["next_wp"].stringValue)
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
                self.image_index = self.camera?.index // Not used
                // Should try to implement callback listener to progress image index.
            }
            else{
                setupOk = false
                self.printSL("Camera not loaded")
            }
            // Store the gimbal reference
            if let gimbalReference = self.aircraft?.gimbal {
                self.gimbal.gimbal = gimbalReference
                self.gimbal.initGimbal()
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
