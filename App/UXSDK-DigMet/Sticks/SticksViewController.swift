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
    var gimbal: DJIGimbal?
    
    var server = serverClass() // For test. Could get a JSON from http server.
    let hostIp = "25.22.96.189" // Use dict or something to store several ip adresses
    let hostUsername = "gising"
    let hostPath = "/Users/gising/temp/"
    var context: SwiftyZeroMQ.Context = try! SwiftyZeroMQ.Context()
    var replyEnable = false
    let replyEndpoint = "tcp://*:1234"
    
    var pitchRangeExtension_set: Bool = false
    var nextGimbalPitch: Int = 0
    
    var gimbalcapability: [AnyHashable: Any]? = [:]
    var cameraModeReference: DJICameraMode = DJICameraMode.playback
    var cameraModeAcitve: DJICameraMode = DJICameraMode.shootPhoto
    
    var copter = Copter()
   
    var image: UIImage = UIImage.init() // Is this used?
    var image_index: UInt?
    
    var lastImage: UIImage = UIImage.init()
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
    
    // IBOutlet declaration: ImageView
    @IBOutlet weak var previewImageView: UIImageView!
    
    // Steppers
    @IBOutlet weak var controlPeriodStepperButton: UIStepper!
    @IBOutlet weak var horizontalSpeedStepperButton: UIStepper!
    
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
    
    //***************************
    // Set the gimbal pitch value
    func setGimbalPitch(pitch: Int){
        // Check if rangeExtension for gimbal has been set sucessfully
        if self.pitchRangeExtension_set != true{
            statusLabel.text = "Gimbal pitch does not seem to have been updated"
        }
        // Create a DJIGimbalRotaion object
        let gimbal_rotation = DJIGimbalRotation(pitchValue: pitch as NSNumber, rollValue: 0, yawValue: 0, time: 1, mode: DJIGimbalRotationMode.absoluteAngle, ignore: true)
        // Feed rotate object to Gimbal method rotate
        self.gimbal?.rotate(with: gimbal_rotation, completion: { (error: Error?) in
            if error != nil {
                self.printSL("Gimbal rotation" + String(describing: error))
            }
        })
    }
        
    
    //*************************************************************
    // captureImage sets up the camera if needed and takes a photo.
    func captureImage() {
        // Make sure camer is in the correct mode
        self.cameraSetMode(DJICameraMode.shootPhoto, 3, completionHandler: {(succsess: Bool) in
            if succsess{
                // Make sure shootPhotoMode is single
                self.camera?.setShootPhotoMode(DJICameraShootPhotoMode.single, withCompletion: {(error: Error?) in
                    // Take photo and save to sdCard
                    self.camera?.startShootPhoto(completion: { (error) in
                        if error != nil {
                            NSLog("Shoot Photo Error: " + String(describing: error))
                        }
                        else{
                            self.printSL("Photo taken")
                        }
                    })
                })
            }
            else{
                self.printSL("Error taking a photo..")
            }
        })
    }
    
    // ***********************************************************************************************************************************************
    // cameraSetMode checks if the newCamera mode is the active mode, and if not it tries to set the mode 'attempts' times. TODO - is attemtps needed?
    func cameraSetMode(_ newCameraMode: DJICameraMode,_ attempts: Int, completionHandler: @escaping (Bool) -> Void) {
        if attempts <= 0{
            self.printSL("Too many attempts changing camera mode.")
            completionHandler(false)
        }
        self.cameraModeReference = newCameraMode
        // Check if the wanted camera mode is already set
        self.camera?.getModeWithCompletion( {(mode: DJICameraMode, error: Error?) in
            if error != nil{
                self.statusLabel.text = "Error getting Cameramode"
                completionHandler(false)
            }
            else{
                self.cameraModeAcitve = mode
                if self.cameraModeAcitve == self.cameraModeReference{
                    self.printSL("Camera Mode is set")
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
    
    
    //****************************************************
    // Print to terminal and update status label on screen
    func printSL(_ str: String){
        Dispatch.main{
            self.statusLabel.text = str
        }
        print(str)
    }
    
    //********************************
    // Save an UIImage to Photos album
    func saveUIImageToPhotosAlbum(image: UIImage){
        let imageSaverHelper = imageSaver()
        imageSaverHelper.writeToPhotoAlbum(image: image)
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
    
    //*****************************************************************************
    // Load an image from the photo library. Seem to be loaded with poor resolution
    func loadUIImageFromPhotoLibrary() -> UIImage? {
        // https://stackoverflow.com/questions/29009621/url-of-image-after-uiimagewritetosavedphotosalbum-in-swift
        // https://www.hackingwithswift.com/forums/swiftui/accessing-image-exif-data-creation-date-location-of-an-image/1429
        let fetchOptions: PHFetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let fetchResult = PHAsset.fetchAssets(with: PHAssetMediaType.image, options: fetchOptions)
        if (fetchResult.firstObject != nil) {
            let lastAsset: PHAsset = fetchResult.lastObject!
            self.previewImageView.image = lastAsset.image
            self.printSL("Previewing image from path")
            return lastAsset.image
        }
        else{
            return nil
        }
    }
    
    //*********************************************************
    // NOT USED Load an UIImage from memory using a path string
    func loadUIImageFromMemory(path: String){
        let image = UIImage(contentsOfFile: path)
        self.previewImageView.image = image
        self.printSL("Previewing image from path")
    }
    
    //*************************
     // Save photo to app memory
     func savePhoto(completionHandler: @escaping (Bool) -> Void){
         // Download last image taken by drone. From on board sdCard to app memory to
         cameraSetMode(DJICameraMode.mediaDownload, 3, completionHandler: {(success: Bool) in
             if success {
                 self.getImage(completionHandler: {(new_success: Bool) in
                     if new_success{
                         self.printSL("Photo downloaded and saved to App memory")
                         completionHandler(true)
                     }
                     else{
                         completionHandler(false)
                         self.printSL("Failed downloading imageData")
                     }
                 })
             }
             else{
                 self.printSL("Set camera mode failed. Interrupting camera too early?")
                 completionHandler(false)
             }
         })
     }
     
     
    //*************************************************************************************
    // Downloads an imageData from sdCard. Saves imageData to app. Previews image on screen
    func getImage(completionHandler: @escaping (Bool) -> Void){
        let manager = self.camera?.mediaManager
        manager?.refreshFileList(of: DJICameraStorageLocation.sdCard, withCompletion: {(error: Error?) in
            self.printSL("Refreshing file list...")
            if error != nil {
                completionHandler(false)
                self.printSL("Refreshing file list failed.")
            }
            else{ // Get file references
                guard let files = manager?.sdCardFileListSnapshot() else {
                    self.printSL("No images on sdCard")
                    completionHandler(false)
                    return
                }
                self.printSL("Files on sdCard: " + String(describing: files.count))
                let index = files.count - 1
                // Create a image container for this scope
                var imageData: Data?
                var i: Int?
                // Download bachthwise, append data. Closure is called each time data is updated.
                files[index].fetchData(withOffset: 0, update: DispatchQueue.main, update: {(_ data: Data?, _ isComplete: Bool, error: Error?) -> Void in
                    if error != nil{
                        // THis happens if download is triggered to close to taking a picture.
                        self.printSL("Error, not ready for download: " + String(error!.localizedDescription))
                        completionHandler(false)
                    }
                    else if isComplete { // No more data blocks to collect
                        self.printSL("it isComplete")
                        if let imageData = imageData{
                            self.saveImageDataToApp(imageData: imageData, filename: files[index].fileName)
                            let image = UIImage(data: imageData)
                            self.lastImage = image!
                            self.lastImageFilename = files[index].fileName
                            self.printSL("Image saved to self, showing image preview. Filename:" + self.lastImageFilename)
                            self.previewImageView.image = files[index].preview //image TODO, does this work?
                            // Modifying EXIF, a clue: https://stackoverflow.com/questions/43920643/modifying-image-metadata
                            completionHandler(true)
                            }
                        else{
                            self.printSL("Could not fetch image from sdCard properly")
                            completionHandler(false)
                        }
                    }
                    else {
                        // If image has been initialized, append the updated data to it
                        if let _ = imageData, let data = data {
                            imageData?.append(data)
                            i! += 1
                            self.printSL("Appending data to image" + String(describing: i))
                        }
                        // initialize the image data
                        else {
                            imageData = data
                            i = 1
                            self.printSL("Initiating a new image")
                        }
                    }
                })
            }
        })
    }
    
    // ******************************************************************
    // Download the preview of the last image taken. Preview it on screen
    func getPreview(completionHandler: @escaping (Bool) -> Void){
        let manager = self.camera?.mediaManager
        manager?.refreshFileList(of: DJICameraStorageLocation.sdCard, withCompletion: {(error: Error?) in
            self.printSL("Refreshing file list...")
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
                        self.printSL("Thumbnail for preview")
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
        
         session.connect()
         if session.isConnected == true{
             session.authenticateBy(inMemoryPublicKey: "", privateKey: privatekeystring, andPassword: nil)
             if session.isAuthorized == true {
                // Upload Data object
                completion(success, pending, "Uploading " + self.lastImageDataFilename)
                session.channel.uploadFile(self.lastImageDataURL!.path, to: self.hostPath)
                info = "Filename: " + self.lastImageDataFilename
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

       

    
    //*****************************************************
    // retreive the gimbal pitch. DOES CRASH THE APP! TODO
    func getGimbalAttitude(){
        // Get the key
        guard let gimbalAttitudeInDegreesKey = DJIGimbalKey(param: DJIGimbalParamAttitudeInDegrees) else {
            print("Could not create DJIGimbalParamAttitudeInDegrees key")
            return
        }
        // Get the keyManager
        guard let keyManager = DJISDKManager.keyManager() else {
            print("Could not get the key manager, manke sure you are registered")
            return
        }
        // Use key to retreive info
        let gimbalAttitudeInDegreesValue = keyManager.getValueFor(gimbalAttitudeInDegreesKey)
        let gimbalAttitudeInDegrees = gimbalAttitudeInDegreesValue?.value as! DJIGimbalState
        _ = gimbalAttitudeInDegrees.attitudeInDegrees.pitch

        // I want to use gimbalAttitude.attitudeInDegrees.pitch.description
        var temp_str:String = ""
        temp_str += "Roll" + gimbalAttitudeInDegrees.attitudeInDegrees.roll.description
        temp_str += "Pitch" + gimbalAttitudeInDegrees.attitudeInDegrees.pitch.description
        temp_str += "Yaw" + gimbalAttitudeInDegrees.attitudeInDegrees.yaw.description
        self.statusLabel.text = temp_str
    }
    

    
 
    // ******************************
    // Initiate the zmq reply thread.
    // MARK: ZMQ
    func startReplyThread()->Bool{
        do{
            // Reply socket
            let replier = try context.socket(.reply)
            try replier.bind(self.replyEndpoint)
            self.printSL("Did bind to socket")
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
                    json_r = createJsonAck("arm_take_off")
                    self.printSL("Received cmd arm_take_off")
                    // Arm take off code
                case "land":
                    json_r = createJsonAck("land")
                    self.printSL("Received cmd land")
                    // Land code
                case "set_vel_body":
                    json_r = createJsonAck("set_vel_body")
                    self.printSL("Received cmd set_vel_body")
                    // Set velocity code
                case "set_yaw":
                    json_r = createJsonAck("set_yaw")
                    self.printSL("Received cmd set_yaw")
                    // Set yaw code
                case "upload_mission_xyz":
                    json_r = createJsonAck("upload_mission_xyz")
                    self.printSL("Received cmd upload_mission_xyz")
                    // Upload mission xyz code
                case "gogo_xyz":
                    json_r = createJsonAck("gogo_xyz")
                    self.printSL("Received cmd gogo_xyz")
                    // Gogo xyz code
                case "take_picture":
                    json_r = createJsonAck("take_picture")
                    self.printSL("Received cmd take_picture")
                    // Take picture cmd
                    Dispatch.main{
                        self.captureImage()
                        // Background process continues without delay (hopp-hej)
                    }
                case "download_picture":
                    json_r = createJsonAck("download_picture")
                    self.printSL("Received cmd download_picture")
                    // Download picture code
                    Dispatch.background{
                        // First download from sdCard
                        self.savePhoto(completionHandler: {(saveSuccess) in
                            if saveSuccess {
                                // Then scp to server, put code in completion block
                                self.scpToServer(completion: {(scpSuccess, pending, info) in
                                    Dispatch.main{
                                        if pending{
                                            self.printSL(info)
                                        }
                                        else{
                                            if scpSuccess{
                                                self.printSL(info)
                                                self.printSL("Send image info on PUB socket")
                                            }
                                            else{
                                                self.printSL("Scp to server failed. Send on PUB?" + info)
                                            }
                                        }
                                    }
                                    })
                            }
                            else{
                                self.printSL("Failed to scp file to server")
                            }
                        })
                    }
                case "gimbal_set":
                    json_r = createJsonAck("gimbal_set")
                    self.printSL("Received cmd gimbal_set")
                    // Gimbal set code
                case "info_request":
                    json_r = createJsonAck("info_request")
                    self.printSL("Received cmd info_request")
                    // Infor request code
                case "data_stream":
                    json_r = createJsonAck("data_stream")
                    self.printSL("Received cmd data_stream")
                    // Data stream code
                case "disconnect":
                    json_r = createJsonAck("disconnect")
                    self.printSL("Received cmd disconnect")
                    // Disconnect code
                    return
                default:
                    json_r = createJsonNack("API call not recognized")
                    self.printSL("API call not recognized: " + json_m["fcn"].stringValue)
                    // Code to handle faulty message
                }
                // Create string from json and send reply
                let reply_str = getJsonString(json: json_r)
                try socket.send(string: reply_str)
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
        // Uses stepper input and sampleTime to calculate how many loops fireTimer should loop
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
//        _ = try? self.context.terminate()
        _ = try? self.context.close()
        self.dismiss(animated: true, completion: nil)
    }
    
    //**************************************************************************************************
    // DeactivateSticks: Touch down action, deactivate immidiately and reset ActivateSticks button color
    @IBAction func DeactivateSticksPressed(_ sender: UIButton) {
        deactivateSticks()
        copter.stop()
    }

    //************************************************************************************
    // ActivateSticks: Touch down up inside action, ativate when ready (release of button)
    @IBAction func ActivateSticksPressed(_ sender: UIButton) {
        activateSticks()
    }

    //***************************************************************************************************************
    // Sends a command to go body right for some time at some speed per settings. Cancel any current joystick command
    @IBAction func DuttRightPressed(_ sender: UIButton) {
        // Clear screen, lets fly!
        previewImageView.image = nil
        // Set the control command
        copter.dutt(x: 0, y: 2, z: 0, yaw: 0)
    }


    //***************************************************************************************************************
    // Sends a command to go body left for some time at some speed per settings. Cancel any current joystick command
    @IBAction func DuttLeftPressed(_ sender: UIButton) {
        // Load image from library to be able to test scp without drone conencted. Could add dummy pic to App assets instead.
        self.lastImage = loadUIImageFromPhotoLibrary()! // TODO, unsafe code
        saveImageDataToApp(imageData: self.lastImage.jpegData(compressionQuality: 1)!, filename: "From_album.jpg")
        
        // Set the control command
        copter.dutt(x: 0, y: -2, z: 0, yaw: 0)
    }
    
    //********************************************************
    // Set gimbal pitch according to scheeme and take a photo.
    @IBAction func takePhotoButton(_ sender: Any) {
        // Command the drone to take a picture and save it to the onboard sdCard. Change gimbal pitch accorsding to pattern.
        previewImageView.image = nil
        statusLabel.text = "Capture image button pressed, preview cleared"

        setGimbalPitch(pitch: self.nextGimbalPitch)
        updateGnextGimbalPitch()
       
        // Dispatch to wait in the pitch movement, then capture an image. TODO - use closure instead of stupid timer.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: {
            self.captureImage()
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
                        self.printSL("Preview downloaded and displayed.")
                    }
                    else{
                        self.printSL("Preview not downloaded")
                        }
                    })
            }
            else{
                self.printSL("Set camera mode failed. Interrupting camera too early?")
            }
        })
    }
    

    //*************************************************************************
    // Download last imageData from sdCard and save to app memory. Save URL to self.
    @IBAction func savePhotoButton(_ sender: Any) {
        savePhoto(){(success) in
            if success{
                self.printSL("Phot successfullt saved to app memory")
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
        }
        else{
            Dispatch.background{
                self.scpToServer(completion: {(success, pending, info) in
                    Dispatch.main{
                        if pending{
                            self.printSL(info)
                        }
                        else{
                            if success{
                                self.printSL("SCP ok: " + info)
                            }
                            else{
                                // Do something more..?
                                self.printSL("SCP fail: " + info)
                            }
                        }
                    }
                })
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
        
        // Setup aircraft
        if let product = DJISDKManager.product() as? DJIAircraft {
            self.aircraft = product
            
            // Store flight controller reference in the Copter class
            if let fc = product.flightController {
                // Store the flightController reference
                copter.flightController = fc
                copter.initFlightController()
            }
            
            // Store the camera refence
            if let cam = product.camera {
                self.camera = cam
                image_index = self.camera?.index // Not used
                // Should try to implement callback listener to progress image index.
                
            }
            else{
                self.printSL("Camera not loaded")
            }
            // Store the gimbal reference
            if let gimb = product.gimbal{
                self.gimbal = gimb
                self.gimbal?.setPitchRangeExtensionEnabled(true, withCompletion: {(error: Error?) in
                    if error != nil {
                        self.printSL("RangeExtension is not set in viewDidLoad")
                    }
                })
                self.gimbal?.getPitchRangeExtensionEnabled(completion: {(sucsess: Bool, error_msg: Error?) in
                    self.pitchRangeExtension_set = sucsess})
                // Have to dispatch in order for change to fall through before checking it
                DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: {
                    if self.pitchRangeExtension_set {
                        self.statusLabel.text = "Range extension set"}
                    else {
                        self.statusLabel.text = "Range extension not set"}
                })
            }
            else{
                self.printSL("Gimbal not loaded")
            }
            
        }
        else{
            self.printSL("Aircraft not loaded")
        }
        
        // Start reply socket thread
//        if self.replyEnable  {
//            self.replyEnable = false
//            self.printSL("Reply thread stopped")
//        }
//        else{
        if startReplyThread(){
            self.printSL("Reply thread successfully started")
        }
        else{
            self.printSL("Reply thread could not be started, check VPN connection")
        }
    }
}
