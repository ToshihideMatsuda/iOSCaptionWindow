//
//  AppDelegate.swift
//  iOSCaptionWindow
//
//  Created by tmatsuda on 2022/07/04.
//

import Cocoa

let commonDelegate:AppDelegate = NSApplication.shared.delegate as! AppDelegate

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    var vc:ViewController? = nil
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Insert code here to initialize your application
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }
}
