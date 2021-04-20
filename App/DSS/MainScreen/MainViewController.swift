//
//  MainViewController.swift
//  UXSDK Sample
//
//  MIT License
//
//  Copyright © 2018-2020 DJI
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:

//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.

//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//


import UIKit
import DJISDK
import SwiftyJSON

func simulatorLocationNumberFormatter() -> NumberFormatter {
    let nf = NumberFormatter()
    
    nf.usesSignificantDigits = true
    nf.minimumSignificantDigits = 8
    nf.alwaysShowsDecimalSeparator = true
    
    return nf
}




class MainViewController: UITableViewController, UITextFieldDelegate {

    var appDelegate = UIApplication.shared.delegate as! AppDelegate
    
    @IBOutlet weak var version: UILabel!
    @IBOutlet weak var registered: UILabel!
    @IBOutlet weak var register: UIButton!
    @IBOutlet weak var connected: UILabel!
    @IBOutlet weak var connect: UIButton!
    
    // DSS layout
    @IBOutlet weak var startDSSButton: UIButton!
    @IBOutlet weak var dscIpTextField: UITextField!
    @IBOutlet weak var DSSIpButton: UIButton!
    
    @IBAction func dscIpTextFieldOK(_ sender: UITextField) {
        print("Editing did end, the entered IP is: ", dscIpTextField.text!)
    }
    
    //@IBAction func myUnwindAction(unwindSegue: UIStoryboardSegue) {}
    
    // Buttons for layout
    @IBOutlet weak var greenSafeButton: UIButton!
    @IBOutlet weak var orangeThinkButton: UIButton!
    @IBOutlet weak var greyDisabledButton: UIButton!
    
    // Bridge Mode Controls
    @IBOutlet weak var bridgeModeSwitch: UISwitch!
    @IBOutlet weak var bridgeModeIPField: UITextField!
    
    // Simulator Controls
    @IBOutlet weak var simulatorOnOrOff: UILabel!
    @IBOutlet weak var startOrStopSimulator: UIButton!
    
    static let numberFormatter:NumberFormatter = simulatorLocationNumberFormatter()
    
    @IBOutlet weak var userAccountStatusHeader: UILabel!
    @IBOutlet weak var currentUserAccountStatus: UILabel!
    @IBOutlet weak var loginOrLogout: UIButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Set up layout of the DSS Button
        let radius: CGFloat = 5
        // Set corner radiuses to buttons
        startDSSButton.layer.cornerRadius = radius
        startDSSButton.backgroundColor = UIColor.lightGray
        startDSSButton.isEnabled = false
        
        DSSIpButton.layer.cornerRadius = radius
        DSSIpButton.backgroundColor = UIColor.systemGreen
        greenSafeButton.layer.cornerRadius = radius
        orangeThinkButton.layer.cornerRadius = radius
        greyDisabledButton.layer.cornerRadius = radius
        
        greenSafeButton.isEnabled = false
        orangeThinkButton.isEnabled = false
        greyDisabledButton.isEnabled = false
        
        // dsc input field
        dscIpTextField.layer.cornerRadius = radius
        dscIpTextField.returnKeyType = .done
        dscIpTextField.keyboardType = .numbersAndPunctuation
        dscIpTextField.autocorrectionType = .no
        dscIpTextField.clearButtonMode = .whileEditing
        dscIpTextField.clearsOnBeginEditing = true
        dscIpTextField.delegate = self
        
        NotificationCenter.default.addObserver(self, selector: #selector(productCommunicationDidChange), name: Notification.Name(rawValue: ProductCommunicationServiceStateDidChange), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleFlightControllerSimulatorDidStart), name: Notification.Name(rawValue: FligntControllerSimulatorDidStart), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleFlightControllerSimulatorDidStop), name: Notification.Name(rawValue: FligntControllerSimulatorDidStop), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(productRegisterDidError), name: Notification.Name(rawValue: ProductRegisterDidError), object: nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        var version = DJISDKManager.sdkVersion()
        if version == "" {
            version = "N/A"
        }
        
       // let strIPAddress : String = getIPAddress()
       //print("IPAddress :: \(strIPAddress)")
        
        self.version.text = "Version \(version)"
        
        self.bridgeModeSwitch.setOn(ProductCommunicationService.shared.useBridge, animated: true)
        self.bridgeModeIPField.text = ProductCommunicationService.shared.bridgeAppIP
        
        self.updateSimulatorControls(isSimulatorActive: ProductCommunicationService.shared.isSimulatorActive)
    }

    @IBAction func registerAction() {
        ProductCommunicationService.shared.registerWithProduct()
    }
    
    @objc func productRegisterDidError() {
        // Look for errors at shared string
        let regError = ProductCommunicationService.shared.regError
        if regError != ""{
            if let firstRange = regError.range(of: "(code:"){
                if let secondRange = regError.range(of: "))") {
                    let substring = regError[firstRange.lowerBound...secondRange.lowerBound]
                    self.registered.text = String(substring)
                    self.registered.textColor = UIColor.systemRed
                }
            }
        }
    }
    
    @IBAction func connectAction() {
        ProductCommunicationService.shared.connectToProduct()
    }
    
    @IBAction func userAccountAction() {
        if (DJISDKManager.userAccountManager().userAccountState == .notLoggedIn ||
            DJISDKManager.userAccountManager().userAccountState == .tokenOutOfDate ||
            DJISDKManager.userAccountManager().userAccountState == .unknown) {
            DJISDKManager.userAccountManager().logIntoDJIUserAccount(withAuthorizationRequired: false) { (state, error) in
                if(error != nil){
                    NSLog("Login failed: %@" + String(describing: error))
                }
                self.updateUserAccountStatus()
            }
        } else {
            DJISDKManager.userAccountManager().logOutOfDJIUserAccount { (error:Error?) in
                if(error != nil){
                    NSLog("Logout failed: %@" + String(describing: error))
                }
                self.updateUserAccountStatus()
            }
        }
    }
    
    
    
    func updateUserAccountStatus() {
        if DJISDKManager.userAccountManager().userAccountState == .notLoggedIn {
            self.currentUserAccountStatus?.text = "Not Logged In"
        } else if DJISDKManager.userAccountManager().userAccountState == .tokenOutOfDate {
            self.currentUserAccountStatus?.text = "Token Out of Date"
        } else if DJISDKManager.userAccountManager().userAccountState == .notAuthorized {
            self.currentUserAccountStatus?.text = "Not Authorized"
        } else if DJISDKManager.userAccountManager().userAccountState == .authorized {
            self.currentUserAccountStatus?.text = "Authorized"
        } else if DJISDKManager.userAccountManager().userAccountState == .unknown {
            self.currentUserAccountStatus?.text = "Unknown"
        }
    }
    
    @objc func productCommunicationDidChange() {
        // If this demo is used in China, it's required to login to your DJI account to activate the application.
        // Also you need to use DJI Go app to bind the aircraft to your DJI account. For more details, please check this demo's tutorial.
        self.updateUserAccountStatus()
        
        if ProductCommunicationService.shared.registered {
            self.registered.text = "YES"
            self.register.isHidden = true
        } else {
            self.registered.text = "NO"
            self.register.isHidden = false
        }
        
        if ProductCommunicationService.shared.connected {
            self.connected.text = "YES"
            self.connect.isHidden = true
            startDSSButton.backgroundColor = UIColor.systemOrange
            startDSSButton.setTitleColor(UIColor.white, for: .normal)
            startDSSButton.isEnabled = true
        } else {
            self.connected.text = "NO"
            self.connect.isHidden = false
            startDSSButton.backgroundColor = UIColor.lightGray
            startDSSButton.isEnabled = false

            // FOR TESTING ONLY, set to true to get through without drone..
            //startDSSButton.isEnabled = true
        }
    }
    
    // MARK: - Bridge Mode Controls
    
    @objc func handleBridgeModeSwitchValueChanged(_ sender:Any) {
        ProductCommunicationService.shared.useBridge = self.bridgeModeSwitch.isOn
    }
    
    // MARK: - UITextFieldDelegate
    
    func textFieldDidEndEditing(_ textField: UITextField) {
        if textField == self.bridgeModeIPField {
            ProductCommunicationService.shared.bridgeAppIP = textField.text!
        }
        
        if textField == self.dscIpTextField {
            // Did end
        }
    }
    
    func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool {
        return true
    }
    
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        return true
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField.canResignFirstResponder {
            textField.resignFirstResponder()
        }
        return true
    }
    
    func textFieldShouldEndEditing(_ textField: UITextField) -> Bool {
        if textField == self.dscIpTextField{
            if let text = textField.text{
                // Leave blank if not using dsc
                if text == ""{
                    return true
                }
                let dots = text.filter { $0 == "." }.count
                let colons = text.filter { $0 == ":"}.count
                
                print("number of dots: ", dots, "number of colons: ", colons)
                if dots == 3 && colons == 0{
                    return true
                }
            }
            textField.text = "bad IP format"
            //ipInputField.backgroundColor = UIColor.systemRed
            return false
        }
        // Dont change behaviour of Bridgemode text field
        else{
            return true
        }
    }
    
    // MARK: - Simulator Controls

    @objc func handleFlightControllerSimulatorDidStart() {
        self.updateSimulatorControls(isSimulatorActive: true)
        startDSSButton.backgroundColor = UIColor.systemGreen
        startDSSButton.setTitleColor(UIColor.white, for: .normal)
        startDSSButton.setTitle("SIMULATE", for: .normal)
        startDSSButton.isEnabled = true
    }
    
    @objc func handleFlightControllerSimulatorDidStop() {
        self.updateSimulatorControls(isSimulatorActive: false)
        startDSSButton.backgroundColor = UIColor.systemOrange
        startDSSButton.setTitleColor(UIColor.white, for: .normal)
        startDSSButton.setTitle("Start DSS", for: .normal)
        startDSSButton.isEnabled = true
    }
    
    @objc func updateSimulatorControls(isSimulatorActive:Bool) {
        self.simulatorOnOrOff.text = isSimulatorActive ? "ON" : "OFF"
        let simulatorControlTitle = isSimulatorActive ? "Stop" : "Start"
        self.startOrStopSimulator.setTitle(simulatorControlTitle, for: .normal)
        self.startOrStopSimulator.setTitle(simulatorControlTitle, for: .highlighted)
        self.startOrStopSimulator.setTitle(simulatorControlTitle, for: .disabled)
        self.startOrStopSimulator.setTitle(simulatorControlTitle, for: .selected)
    }
    
    @IBAction func handleStartOrStopSimulator() {
        if ProductCommunicationService.shared.isSimulatorActive == true {
            let didStartStoppingSimulator = ProductCommunicationService.shared.stopSimulator()
            self.dismiss(self)
            if !didStartStoppingSimulator {
                self.presentError("Could Not Begin Stopping Simulator")
            }
        } else {
            let viewController = SimulatorControlsViewController()
            
            let navigationController = UINavigationController(rootViewController: viewController)
        
            let dismissItem = UIBarButtonItem(barButtonSystemItem: .done,
                                              target: self,
                                              action: #selector(MainViewController.dismiss(_:)))
            viewController.navigationItem.rightBarButtonItem = dismissItem
            
            navigationController.modalPresentationStyle = .formSheet
            viewController.modalPresentationStyle = .formSheet
            
            self.present(navigationController,
                         animated: true,
                         completion: nil)
        }
    }
    
    @IBAction func useBridgeAction(_ sender: UISwitch) {
        ProductCommunicationService.shared.useBridge = self.bridgeModeSwitch.isOn
        ProductCommunicationService.shared.disconnectProduct()
    }
    
    
    @IBAction func DSSIpButtonAction(_ sender: Any) {
        let strIPAddress : String = getIPAddress()
        print("IPAddress :: \(strIPAddress)")
        DSSIpButton.setTitle(strIPAddress, for: .normal)
    }
    
    
    @objc public func dismiss(_ sender: Any) {
        self.presentedViewController?.dismiss(animated: true,
                                            completion: nil)
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if let vc = segue.destination as? DSSViewController{
            vc.dscIP = ""
        }
    }
}

extension UIViewController {
    func presentError(_ errorDescription:String) {
        let alertController = UIAlertController(title: "Error",
                                              message: errorDescription,
                                              preferredStyle: .alert)
        let action = UIAlertAction(title: "Ok",
                                   style: .cancel,
                                 handler: nil)
        
        alertController.addAction(action)
        
        self.present(alertController,
                     animated: true,
                     completion: nil)
    }
}


// Return IP address of WiFi interface (en0) as a String, or `nil` https://stackoverflow.com/questions/30748480/swift-get-devices-wifi-ip-address
func getIPAddress() -> String {
    var address = ""
    var ifaddr: UnsafeMutablePointer<ifaddrs>? = nil
    var interfaces = JSON()
    if getifaddrs(&ifaddr) == 0 {
        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }

            guard let interface = ptr?.pointee else { return "" }
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) || addrFamily == UInt8(AF_INET6) { //|| addrFamily == UInt8(AF_LINK){

                // wifi = ["en0"]
                // wired = ["en1", "en2", "en3", "en4"]
                // cellular = ["pdp_ip0","pdp_ip1","pdp_ip2","pdp_ip3","pdp_ip4"]
                // VPN1? = ["ipsec0", "ipsec1","ipsec3","ipsec4","ipsec5","ipsec7"]
                // VPN2 = ["utun0", "utun1", "utun2", "utun3"]

                let name: String = String(cString: (interface.ifa_name))
                //print("name: ",name)
                if  name == "en0" || name == "pdp_ip0" || name == "utun0" || name == "utun1" || name == "utun2" || name == "utun3" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t((interface.ifa_addr.pointee.sa_len)), &hostname, socklen_t(hostname.count), nil, socklen_t(0), NI_NUMERICHOST)
                    let hostnameStr = String(cString: hostname)
                    // If the identified interface is not a mac address (conatins :), suggest it as an ip
                    if !hostnameStr.contains(":"){
                        // Inferface is VPN
                        if name.contains("utun"){
                            interfaces["utun"] = JSON(hostnameStr)
                        }
                        // Interface is local network
                        else if name.contains("en"){
                            interfaces["en"] = JSON(hostnameStr)
                        }
                        // Interface is mobile network
                        else if name.contains("pdp") {
                            interfaces["pdp"] = JSON(hostnameStr)
                        }
                        // For debug, set if statement to true
                        else{
                            address = hostnameStr
                            print("Name: ", name, " Address: :", address)
                        }
                    }
                }
            }
        }
        freeifaddrs(ifaddr)
    }
    
    // prioritize return string as: 1. VPN 2. Local network 3. mobile connection
    if interfaces["utun"].exists(){
        print("VPN connection")
        return interfaces["utun"].stringValue
    }
    else if interfaces["en"].exists(){
        print("Wifi connection")
        return interfaces["en"].stringValue
    }
    else if interfaces["pdp"].exists(){
        print("Cellular connection")
        return interfaces["pdp"].stringValue
    }
    else{
        print("Connection not identified")
        return "??: " + address
    }
}


