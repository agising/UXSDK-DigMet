//
//  zmqHelper.swift
//  UXSDK-DigMet
//
//  Created by Andreas Gising on 2020-09-11.
//  Copyright © 2020 DJI. All rights reserved.
//

import Foundation
import SwiftyJSON


//***************************************************************************
// Clean string from leading and trailing quotationmarks and also backslashes
func cleanUpString(str: String)->String{
    let str2 = str.dropLast()
    let str3 = str2.dropFirst()
    let str4 = str3.replacingOccurrences(of: "\\", with: "")
    return str4
 }

//**************************************
// Add quotation marks around the string
func addQuotations(string: String)->String{
    return "\"" + string + "\""
}

//*******************
// Insert backslashes
func uglyfyString(string: String)->String{
   let str1 = string.replacingOccurrences(of: "\"", with: "\\\"")
   return str1
}

////*************************************
//// Get the json-object from json-string
//func getJsonObject(uglyString: String) -> JSON {
//   let str = cleanUpString(str: uglyString)
//   guard let data = str.data(using: .utf8) else {return JSON()}
//   guard let json = try? JSON(data: data) else {return JSON()}
//   return json
//}

//*************************************
// Get the json-object from json-string
func getJsonObject(uglyString: String, stringIncludesTopic: Bool = false) -> (String?, JSON) {
    var topic: String? = nil
    var message = uglyString
    if stringIncludesTopic{
        // Incoming messages from iOS and python are a bit different. From python there are whitespaces between key: and value. For iOS no such whitespaces occur.
        // Start by getting topic, slice string on every whitespace. First occurance is topic:
        let strArray = message.components(separatedBy: " ")
        topic = strArray[0]
        
        // Start over, drop the first topic characters including the whitespace after topic
        message = String(message.dropFirst(topic!.count))
        // Remove all whitespaces
        message = message.replacingOccurrences(of: " ", with: "")
    }
    else{
        // Messages received on REQ socket needs to be modified before parsing.
        //Clean up leading, trailing and replace som backslashes
        message = cleanUpString(str: message)
    }
    // Parse string into JSON
    guard let data = message.data(using: .utf8) else {return (topic, JSON())}
    guard let json = try? JSON(data: data) else {return (topic,JSON())}
    return (topic, json)
}

////*************************************
//// Get the json-object from json-string
//func getJsonObject(uglyString: String, stringIncludesTopic: Bool = false) -> (String?, JSON) {
//    var topic: String? = nil
//    var message = uglyString
//    if stringIncludesTopic{
//        // Split at the whitespace, the cherry pick the message. Topic is avalable at strArray[0]
//        let strArray = message.components(separatedBy: " ")
//        // If parsing does not work for some reason the Array gets the wrong size, if so return JSON().
//        if strArray.endIndex != 2{
//            return (topic, JSON())
//        }
//        topic = strArray[0]
//        message = strArray[1]
//    }
//    else{
//        // Clean up leading, trailing and replace som backslashes
//        message = cleanUpString(str: message)
//    }
//    // Parse string into JSON
//    guard let data = message.data(using: .utf8) else {return (topic, JSON())}
//    guard let json = try? JSON(data: data) else {return (topic,JSON())}
//    return (topic, json)
//}


//**********************************************************************
// Get ZMQ string consisting of the topic and the serialized json-object
func getJsonStringAndTopic(topic: String, json: JSON) -> String{
    let str1 = json.rawString(.utf8, options: .withoutEscapingSlashes)!
    let str2 = topic + " " + str1
    return str2
}


//*************************************************
// Get the ZMQ string of the serialized json-object
// Sending replies in the same format as publish messages does not work..
// reply and publish uses different format from iOS in order for python to recieive it
func getJsonStringLENNART_DETTA_FUNKAR_INTE(json: JSON) -> String{
    let str1 = json.rawString(.utf8, options: .sortedKeys)!
    return str1
}

//*************************************************
// Get the ZMQ string of the serialized json-object
func getJsonString(json: JSON) -> String{
    let str1 = json.rawString(.utf8, options: .withoutEscapingSlashes)!
    let str2 = uglyfyString(string: str1)
    let str3 = addQuotations(string: str2)
    return str3
}

//**************************
// Create a json ack message
func createJsonAck(_ str: String) -> JSON {
    var json = JSON()
    json["fcn"] = JSON("ack")
    json["arg"] = JSON(str)
    return json
 }

//***************************
// Create a json nack message
func createJsonNack(fcn: String, description: String) -> JSON {
    var json = JSON()
    json["fcn"] = JSON("nack")
    json["arg"] = JSON(fcn)
    json["description"] = JSON(description)
    return json
}

//********************
// Print a json-object
func printJson(jsonObject: JSON){
    print(jsonObject)
}

//******************************
// Encode data object to base 64
func getBase64utf8(data: Data)->String{
    let base64Data = data.base64EncodedString()
    return base64Data
}


