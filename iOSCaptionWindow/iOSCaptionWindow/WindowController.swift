//
//  WindowController.swift
//  iOSCaptionWindow
//
//  Created by tmatsuda on 2022/07/04.
//


import Foundation
import Cocoa

class WindowController: NSWindowController {

}

extension WindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        NSApplication.shared.terminate(self)
    }
}
