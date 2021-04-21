//
//  CameraHelper.swift
//  DSS-APP
//
//  Created by Andreas Gising on 2021-04-21.
//  Copyright © 2021 DJI. All rights reserved.
//

import Foundation
import DJISDK

class CameraController: NSObject, DJICameraDelegate {
    var camera: DJICamera?
    var modeStr = ""
    
    func initCamera(){
        camera!.delegate = self
    }
    
    func parseMode(mode:UInt)->String{
        switch mode {
        case 0:
            return "Shoot photo"
        case 1:
            return  "Record video"
        case 2:
            return "Playback"
        case 3:
            return "Media download"
        case 4:
            return "Broadcast"
        case 255:
            return "Unknown"
        default:
            return "Error"
        }
    }
    func camera(_ camera: DJICamera, didUpdate systemState: DJICameraSystemState) {
        // Monitor camera mode
        let modeStr = parseMode(mode: systemState.mode.rawValue)
        if modeStr != self.modeStr{
           // Mode changed
            print("Camera mode changed to: ", modeStr)
            self.modeStr = modeStr
        }
    }
}
