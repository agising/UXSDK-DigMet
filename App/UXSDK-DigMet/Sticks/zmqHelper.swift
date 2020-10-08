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

//*************************************
// Get the json-object from json-string
func getJsonObject(uglyString: String) -> JSON {
   let str = cleanUpString(str: uglyString)
   guard let data = str.data(using: .utf8) else {return JSON()}
   guard let json = try? JSON(data: data) else {return JSON()}
   return json
}

//**********************************************************************
// Get ZMQ string consisting of the topic and the serialized json-object
func getJsonStringAndTopic(topic: String, json: JSON) -> String{
    var str1 = json.rawString(.utf8, options: .withoutEscapingSlashes)!
    //str1 = uglyfyString(string: str1)
    let str3 = topic + " " + str1
    return str3
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
 func createJsonNack(_ str: String) -> JSON {
    var json = JSON()
    json["fcn"] = JSON("nack")
    json["arg"] = JSON(str)
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


