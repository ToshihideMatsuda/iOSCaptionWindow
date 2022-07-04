//
//  ViewController.swift
//  iOSCaptionWindow
//
//  Created by tmatsuda on 2022/07/04.
//

import Cocoa
import AVFoundation
import CoreMediaIO

class ViewController: NSViewController {

    @IBOutlet private weak var imageView: NSImageView!

    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let audiooutput = AVCaptureAudioDataOutput()
    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let mixer = AVAudioMixerNode()
    private let context = CIContext()
    private var audioInitialized = false

    private var observer: NSObjectProtocol?
    private var targetRect: CGRect?

    deinit {
        stopRunning()

        if let o = observer {
            NotificationCenter.default.removeObserver(o)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // opt-in settings to find iOS physical devices
        var prop = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMaster))
        var allow: UInt32 = 1;
        CMIOObjectSetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &prop, 0, nil, UInt32(MemoryLayout.size(ofValue: allow)), &allow)

        // discover target iOS device
        let devices = AVCaptureDevice.DiscoverySession(deviceTypes: [.externalUnknown], mediaType: nil, position: .unspecified).devices

        // configure device if found, or wait notification
        if let device = devices.filter({ $0.modelID == "iOS Device" && $0.manufacturer == "Apple Inc." }).last {
            print(device)
            self.configureDevice(device: device)
        } else {
            observer = NotificationCenter.default.addObserver(forName: .AVCaptureDeviceWasConnected, object: nil, queue: .main) { (notification) in
                print(notification)
                guard let device = notification.object as? AVCaptureDevice else { return }
                self.configureDevice(device: device)
            }
        }
    }

    private func configureDevice(device: AVCaptureDevice) {
        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) {
                session.addInput(input)
                if session.canAddOutput(output) {
                    output.setSampleBufferDelegate(self, queue: .main)
                    output.alwaysDiscardsLateVideoFrames = true
                    session.addOutput(output)
                    if session.canAddOutput(audiooutput) {
                        audiooutput.setSampleBufferDelegate(self, queue: .main)
                        session.addOutput(audiooutput)
                        
                    }
                }
            }
            startRunning()
        } catch {
            print(error)
        }
    }

    private func startRunning() {
        guard !session.isRunning else { return }
        session.startRunning()
    }

    private func stopRunning() {
        guard session.isRunning else { return }
        session.stopRunning()
        audioEngine.stop()
        playerNode.stop()
    }

    private func resizeIfNeeded(w: CGFloat, h: CGFloat) {
        guard targetRect == nil else { return }
        let rect = CGRect(x: 0, y: 0, width: w/2, height: h/2)
        self.imageView.frame = rect
        targetRect = rect
    }
}

extension ViewController : AVCaptureVideoDataOutputSampleBufferDelegate,AVCaptureAudioDataOutputSampleBufferDelegate {

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        if(output == self.output)
        {
            connection.videoOrientation = .portrait

            DispatchQueue.main.async(execute: {
                let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)!
                let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
                let w = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
                let h = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
                self.resizeIfNeeded(w: w, h: h)

                guard let targetRect = self.targetRect else { return }
                let m = CGAffineTransform(scaleX: targetRect.width / w, y: targetRect.height / h)
                let resizedImage = ciImage.transformed(by: m)
                let cgimage = self.context.createCGImage(resizedImage, from: targetRect)!
                let image = NSImage(cgImage: cgimage, size: targetRect.size)
                self.imageView.image = image
            })
        }
        else {
            
            guard let description: CMFormatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
                  let sampleRate: Float64 = description.audioStreamBasicDescription?.mSampleRate,
                  let channelsPerFrame: UInt32 = description.audioStreamBasicDescription?.mChannelsPerFrame
            else { return }
            audioInit(sampleRate: sampleRate, channelCount: channelsPerFrame)
            
            guard let pcmBuffer = AVAudioPCMBuffer.create(from:sampleBuffer) else { return }
            self.playerNode.scheduleBuffer(pcmBuffer, completionHandler: nil)
            
            
        }
    }
    private func audioInit(sampleRate:Double = 48000.0, channelCount:UInt32=2) {
        if audioInitialized { return }
        
        self.audioEngine.attach(self.playerNode)
        self.audioEngine.attach(self.mixer)
        
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: AVAudioFrameCount(channelCount), interleaved: false)
        self.audioEngine.connect(self.playerNode,   to: self.mixer, format: format)
        self.audioEngine.connect(self.mixer,        to: self.audioEngine.mainMixerNode, format: format)
        
        print(self.audioEngine.mainMixerNode.outputFormat(forBus: .zero))
        do {
            try self.audioEngine.start()
        } catch {
            print (error)
            return
        }
        self.playerNode.play()
        audioInitialized = true
    }

}

extension AVAudioPCMBuffer {
    static func create(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let description: CMFormatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let sampleRate: Float64 = description.audioStreamBasicDescription?.mSampleRate,
              let channelsPerFrame: UInt32 = description.audioStreamBasicDescription?.mChannelsPerFrame
        else { return nil }
        
        let samplesCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard let blockBuffer: CMBlockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer),
              let audioFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: AVAudioChannelCount(channelsPerFrame), interleaved: false) else {
            return nil
        }
        
        let buffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: AVAudioFrameCount(samplesCount))!
        buffer.frameLength = buffer.frameCapacity
        
        // GET BYTES
        var dataPointer: UnsafeMutablePointer<Int8>?
        CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: nil, dataPointerOut: &dataPointer)
        
        guard var channel: UnsafeMutablePointer<Float> = buffer.floatChannelData?[0],
              let data = dataPointer else { return nil }
        
        var data16 = UnsafeRawPointer(data).assumingMemoryBound(to: Int16.self)
        
        for _ in 0...samplesCount - 1 {
            channel.pointee = Float32(data16.pointee) / Float32(Int16.max)
            channel += 1
            for _ in 0...channelsPerFrame - 1 {
                data16 += 1
            }
        }
        return buffer
    }
    
}
