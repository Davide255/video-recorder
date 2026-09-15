import Foundation
import AVFoundation
import Capacitor
import UniformTypeIdentifiers

extension UIColor {
    convenience init(fromHex hex: String) {
        var cString:String = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if (cString.hasPrefix("#")) {
            cString.remove(at: cString.startIndex)
        }
        var rgbValue:UInt64 = 0
        Scanner(string: cString).scanHexInt64(&rgbValue)
        self.init(
            red: CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0,
            green: CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0,
            blue: CGFloat(rgbValue & 0x0000FF) / 255.0,
            alpha: CGFloat(1.0)
        )
    }
}

public class FrameConfig {
    var id: String
    var stackPosition: String
    var x: CGFloat
    var y: CGFloat
    var width: Any
    var height: Any
    var borderRadius: CGFloat
    var dropShadow: DropShadow
    var mirrorFrontCam: Bool

    init(_ options: [AnyHashable: Any] = [:]) {
        self.id = options["id"] as! String
        self.stackPosition = options["stackPosition"] as? String ?? "back"
        self.x = options["x"] as? CGFloat ?? 0
        self.y = options["y"] as? CGFloat ?? 0
        self.width = options["width"] ?? "fill"
        self.height = options["height"] ?? "fill"
        self.borderRadius = options["borderRadius"] as? CGFloat ?? 0
        self.dropShadow = DropShadow(options["dropShadow"] as? [AnyHashable: Any] ?? [:])
        self.mirrorFrontCam = options["mirrorFrontCam"] as? Bool ?? true
    }

    class DropShadow {
        var opacity: Float
        var radius: CGFloat
        var color: CGColor
        init(_ options: [AnyHashable: Any]) {
            self.opacity = (options["opacity"] as? NSNumber ?? 0).floatValue
            self.radius = options["radius"] as? CGFloat ?? 0
            self.color = UIColor(fromHex: options["color"] as? String ?? "#000000").cgColor
        }
    }
}

class CameraView: UIView {
    var videoPreviewLayer: AVCaptureVideoPreviewLayer?

    func interfaceOrientationToVideoOrientation(_ orientation : UIInterfaceOrientation) -> AVCaptureVideoOrientation {
        switch (orientation) {
        case UIInterfaceOrientation.portrait:
            return AVCaptureVideoOrientation.portrait;
        case UIInterfaceOrientation.portraitUpsideDown:
            return AVCaptureVideoOrientation.portraitUpsideDown;
        case UIInterfaceOrientation.landscapeLeft:
            return AVCaptureVideoOrientation.landscapeLeft;
        case UIInterfaceOrientation.landscapeRight:
            return AVCaptureVideoOrientation.landscapeRight;
        default:
            return AVCaptureVideoOrientation.portraitUpsideDown;
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews();
        if let sublayers = self.layer.sublayers {
            for layer in sublayers {
                layer.frame = self.bounds
            }
        }
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            self.videoPreviewLayer?.connection?.videoOrientation = interfaceOrientationToVideoOrientation(windowScene.interfaceOrientation)
        }
    }

    func addPreviewLayer(_ previewLayer:AVCaptureVideoPreviewLayer?) {
        previewLayer!.videoGravity = AVLayerVideoGravity.resizeAspectFill
        previewLayer!.frame = self.bounds
        self.layer.addSublayer(previewLayer!)
        self.videoPreviewLayer = previewLayer;
    }

    func removePreviewLayer() {
        self.videoPreviewLayer?.removeFromSuperlayer()
        self.videoPreviewLayer = nil
    }
}

public func checkAuthorizationStatus(_ call: CAPPluginCall) -> Bool {
    let videoStatus = AVCaptureDevice.authorizationStatus(for: AVMediaType.video)
    if (videoStatus == AVAuthorizationStatus.restricted) {
        call.reject("Camera access restricted")
        return false
    } else if videoStatus == AVAuthorizationStatus.denied {
        call.reject("Camera access denied")
        return false
    }
    let audioStatus = AVCaptureDevice.authorizationStatus(for: AVMediaType.audio)
    if (audioStatus == AVAuthorizationStatus.restricted) {
        call.reject("Microphone access restricted")
        return false
    } else if audioStatus == AVAuthorizationStatus.denied {
        call.reject("Microphone access denied")
        return false
    }
    return true
}

enum CaptureError: Error {
    case backCameraUnavailable
    case frontCameraUnavailable
    case couldNotCaptureInput(error: NSError)
}

/**
	* Create capture input
	*/
public func createCaptureDeviceInput(currentCamera: Int, frontCamera: AVCaptureDevice?, backCamera: AVCaptureDevice?) throws -> AVCaptureDeviceInput {
	var captureDevice: AVCaptureDevice
	if (currentCamera == 0) {
		if (frontCamera != nil){
			captureDevice = frontCamera!
		} else {
			throw CaptureError.frontCameraUnavailable
		}
	} else {
		if (backCamera != nil){
			captureDevice = backCamera!
		} else {
			throw CaptureError.backCameraUnavailable
		}
	}
	let captureDeviceInput: AVCaptureDeviceInput
	do {
		captureDeviceInput = try AVCaptureDeviceInput(device: captureDevice)
	} catch let error as NSError {
		throw CaptureError.couldNotCaptureInput(error: error)
	}
	return captureDeviceInput
}

public func joinPath(left: String, right: String) -> String {
    let nsString: NSString = NSString.init(string:left);
    return nsString.appendingPathComponent(right);
}

public func randomFileName() -> String {
    return UUID().uuidString
}

@objc(VideoRecorder)
public class VideoRecorder: CAPPlugin, AVCaptureFileOutputRecordingDelegate, AVCaptureAudioDataOutputSampleBufferDelegate, CAPBridgedPlugin {
    public let identifier = "VideoRecorder"
    public let jsName = "VideoRecorder"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "initialize", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "destroy", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "flipCamera", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "toggleFlash", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "enableFlash", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "disableFlash", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "isFlashAvailable", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "isFlashEnabled", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "addPreviewFrameConfig", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "editPreviewFrameConfig", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "switchToPreviewFrame", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "showPreviewFrame", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "hidePreviewFrame", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "startRecording", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "stopRecording", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getDuration", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "enableMicrophone", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "disableMicrophone", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getAvailableCameras", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "switchCamera", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getAvailableQualities", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "editVideo", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "generateThumbnail", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "cancelEdit", returnType: CAPPluginReturnPromise),
    ]

    var capWebView: WKWebView!

    var cameraView: CameraView!
    var captureSession: AVCaptureSession?
    var captureVideoPreviewLayer: AVCaptureVideoPreviewLayer?
    var videoOutput: AVCaptureMovieFileOutput?
    var durationTimer: Timer?

    // Audio metering is derived from the capture session itself (see audioDataOutput)
    // instead of a separate AVAudioRecorder, so a second audio client never re-activates
    // the audio session and interrupts other apps' audio (e.g. background music).
    var audioDataOutput: AVCaptureAudioDataOutput?
    let audioMeterQueue = DispatchQueue(label: "video-recorder.audio-meter")
    private var lastMeterEmit: CFAbsoluteTime = 0

    var cameraInput: AVCaptureDeviceInput?

    var currentCamera: Int = 0
    var frontCamera: AVCaptureDevice?
    var backCamera: AVCaptureDevice?
    var allCameras: [AVCaptureDevice] = []
    var quality: Int = 0
    var videoBitrate: Int = 3000000
    var _isFlashEnabled: Bool = false
    var isMicrophoneEnabled: Bool = true

    var stopRecordingCall: CAPPluginCall?
    var recordingSegments: [URL] = []
    var pendingCameraSwitch: (() -> Void)?
    var shouldStopAfterSwitch: Bool = false

    var previewFrameConfigs: [FrameConfig] = []
    var currentFrameConfig: FrameConfig = FrameConfig(["id": "default"])

    let videoEditor = VideoEditor()

    /// Error code the editVideo() promise is rejected with after cancelEdit().
    static let editCanceledCode = "CANCELED"

    /// Error code for an editVideo() call made while another one is still running.
    static let editInProgressCode = "EDIT_IN_PROGRESS"

    /// Guards editInProgress: plugin calls arrive on the plugin's queue, the edit handlers on main.
    let editStateLock = NSLock()
    private var editInProgressFlag = false

    /// Reserves the single edit slot, returning false when one is already taken.
    func beginEdit() -> Bool {
        editStateLock.lock()
        defer { editStateLock.unlock() }

        if editInProgressFlag {
            return false
        }

        editInProgressFlag = true
        return true
    }

    func finishEdit() {
        editStateLock.lock()
        editInProgressFlag = false
        editStateLock.unlock()
    }

    /**
     * Capacitor Plugin load
     */
    override public func load() {
        self.capWebView = self.bridge?.webView
    }

    /**
     * AVCaptureFileOutputRecordingDelegate
     */
    public func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        recordingSegments.append(outputFileURL)

        if let switchAction = pendingCameraSwitch {
            pendingCameraSwitch = nil
            switchAction()
            if shouldStopAfterSwitch {
                shouldStopAfterSwitch = false
                DispatchQueue.main.async { self.videoOutput?.stopRecording() }
            }
            return
        }

        self.durationTimer?.invalidate()
        finalizeRecording()
    }

    private func finalizeRecording() {
        guard !recordingSegments.isEmpty else {
            self.stopRecordingCall?.reject("No recorded segments")
            return
        }
        if recordingSegments.count == 1 {
            let url = recordingSegments[0]
            recordingSegments = []
            self.stopRecordingCall?.resolve([
                "videoUrl": self.bridge?.portablePath(fromLocalURL: url)?.absoluteString as Any
            ])
        } else {
            let segments = recordingSegments
            recordingSegments = []
            mergeRecordingSegments(segments) { mergedURL in
                if let url = mergedURL {
                    self.stopRecordingCall?.resolve([
                        "videoUrl": self.bridge?.portablePath(fromLocalURL: url)?.absoluteString as Any
                    ])
                } else {
                    self.stopRecordingCall?.reject("Failed to merge video segments")
                }
            }
        }
    }

    private func beginRecordingSegment() {
        let tempDir = NSURL.fileURL(withPath: NSTemporaryDirectory(), isDirectory: true)
        var fileName = randomFileName()
        fileName.append(".mp4")
        let fileUrl = NSURL.fileURL(withPath: joinPath(left: tempDir.path, right: fileName))

        DispatchQueue.main.async {
            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: self.videoBitrate]
            ]
            if let connection = self.videoOutput?.connection(with: .video) {
                self.videoOutput?.setOutputSettings(videoSettings, for: connection)
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                    connection.videoOrientation = self.cameraView.interfaceOrientationToVideoOrientation(windowScene.interfaceOrientation)
                }
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = false
            }
            if let audioConnection = self.videoOutput?.connection(with: .audio) {
                audioConnection.isEnabled = self.isMicrophoneEnabled
            }
            self.videoOutput?.startRecording(to: fileUrl, recordingDelegate: self)
        }
    }

    private func performCameraSwitch(to newInput: AVCaptureDeviceInput, newCameraPosition: Int) {
        self.captureSession?.beginConfiguration()
        if let current = self.cameraInput {
            self.captureSession?.removeInput(current)
        }
        self.captureSession?.addInput(newInput)
        self.cameraInput = newInput
        self.currentCamera = newCameraPosition
        self.captureSession?.commitConfiguration()
        DispatchQueue.main.async {
            self.updateCameraView(self.currentFrameConfig)
        }
    }

    private func mergeRecordingSegments(_ segments: [URL], completion: @escaping (URL?) -> Void) {
        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            completion(nil)
            return
        }

        var insertTime = CMTime.zero
        var preferredTransform: CGAffineTransform?

        for url in segments {
            let asset = AVAsset(url: url)
            let timeRange = CMTimeRange(start: .zero, duration: asset.duration)
            do {
                if let vTrack = asset.tracks(withMediaType: .video).first {
                    try videoTrack.insertTimeRange(timeRange, of: vTrack, at: insertTime)
                    if preferredTransform == nil { preferredTransform = vTrack.preferredTransform }
                }
                if let aTrack = asset.tracks(withMediaType: .audio).first {
                    try audioTrack.insertTimeRange(timeRange, of: aTrack, at: insertTime)
                }
            } catch {
                completion(nil)
                return
            }
            insertTime = CMTimeAdd(insertTime, asset.duration)
        }

        if let transform = preferredTransform { videoTrack.preferredTransform = transform }

        let tempDir = NSURL.fileURL(withPath: NSTemporaryDirectory(), isDirectory: true)
        var fileName = randomFileName()
        fileName.append(".mp4")
        let outputURL = NSURL.fileURL(withPath: joinPath(left: tempDir.path, right: fileName))

        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            completion(nil)
            return
        }
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.exportAsynchronously {
            if exportSession.status == .completed {
                for url in segments { try? FileManager.default.removeItem(at: url) }
                completion(outputURL)
            } else {
                completion(nil)
            }
        }
    }

    /**
     * Configures the shared audio session so the camera/mic never interrupt other
     * apps' audio. `.mixWithOthers` is the key option: with it set, activating our
     * (play-and-record) session does not stop background music. `.videoRecording`
     * mode is the camera-appropriate mode and plays nicely with mixing.
     *
     * Note: with mixing enabled the microphone will also pick up any audio coming
     * out of the speaker — that is the inherent trade-off of keeping other audio
     * playing while recording.
     */
    private func configureAudioSessionForMixing() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .videoRecording, options: [
                .mixWithOthers,
                .defaultToSpeaker,
                .allowBluetoothA2DP,
                .allowAirPlay
            ])
            try session.setActive(true)
        } catch {
            print("Failed to configure audio session for mixing: \(error)")
        }
    }

    /**
     * AVCaptureAudioDataOutputSampleBufferDelegate
     * Reads the mic level straight from the capture session's audio connection so we
     * don't need a second audio client just for metering.
     */
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Throttle to ~10 Hz to match the previous timer-based cadence.
        let now = CFAbsoluteTimeGetCurrent()
        if now - self.lastMeterEmit < 0.1 { return }
        self.lastMeterEmit = now

        var averagePower: Float = -160
        for channel in connection.audioChannels {
            averagePower = max(averagePower, channel.averagePowerLevel)
        }
        self.notifyListeners("onVolumeInput", data: ["value": averagePower])
    }


	/**
	* Initializes the camera.
	* { camera: Int, quality: Int }
	*/
    @objc func initialize(_ call: CAPPluginCall) {
        // log to console for initializing
        print("Initializing camera")

        if (self.captureSession?.isRunning != true) {
            self.currentCamera = call.getInt("camera", 0)
            self.quality = call.getInt("quality", 0)
            self.videoBitrate = call.getInt("videoBitrate", 3000000)
            let autoShow = call.getBool("autoShow", true)

            for frameConfig in call.getArray("previewFrames", [ ["id": "default"] ]) {
                self.previewFrameConfigs.append(FrameConfig(frameConfig as! [AnyHashable : Any]))
            }
            self.currentFrameConfig = self.previewFrameConfigs.first!

            if checkAuthorizationStatus(call) {
                DispatchQueue.main.async {
                    do {
                        // Set webview to transparent and set the app window background to white
                        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                            windowScene.windows.first?.backgroundColor = UIColor.white
                        }
                        self.capWebView?.isOpaque = false
                        self.capWebView?.backgroundColor = UIColor.clear

                        let deviceDescoverySession = AVCaptureDevice.DiscoverySession.init(
                            deviceTypes: [AVCaptureDevice.DeviceType.builtInWideAngleCamera],
                            mediaType: AVMediaType.video,
                            position: AVCaptureDevice.Position.unspecified)

                        for device in deviceDescoverySession.devices {
                            if device.position == AVCaptureDevice.Position.back {
                                self.backCamera = device
                            } else if device.position == AVCaptureDevice.Position.front {
                                self.frontCamera = device
                            }
                        }

                        if (self.backCamera == nil) {
                            self.currentCamera = 1
                        }

                        // Create capture session
                        self.captureSession = AVCaptureSession()
                        // Begin configuration
                        self.captureSession?.beginConfiguration()

                        self.captureSession?.automaticallyConfiguresApplicationAudioSession = false

                        /**
                         * Video file recording capture session
                         */
                        self.captureSession?.usesApplicationAudioSession = true
                        // Add Camera Input
                        self.cameraInput = try createCaptureDeviceInput(currentCamera: self.currentCamera, frontCamera: self.frontCamera, backCamera: self.backCamera)
                        self.captureSession!.addInput(self.cameraInput!)
                        // Add Microphone Input
                        let microphone = AVCaptureDevice.default(for: .audio)
                        if let audioInput = try? AVCaptureDeviceInput(device: microphone!), (self.captureSession?.canAddInput(audioInput))! {
                            self.captureSession!.addInput(audioInput)
                        }
                        // Add Video File Output
                        self.videoOutput = AVCaptureMovieFileOutput()
                        self.videoOutput?.movieFragmentInterval = CMTime.invalid
                        self.captureSession!.addOutput(self.videoOutput!)

                        // Add Audio Data Output purely for level metering (onVolumeInput),
                        // sharing the capture session's single audio client.
                        self.audioDataOutput = AVCaptureAudioDataOutput()
                        if self.captureSession!.canAddOutput(self.audioDataOutput!) {
                            self.captureSession!.addOutput(self.audioDataOutput!)
                        }

                        // Set Video quality
                        switch(self.quality){
                        case 1:
                            self.captureSession?.sessionPreset = AVCaptureSession.Preset.hd1280x720
                            break;
                        case 2:
                            self.captureSession?.sessionPreset = AVCaptureSession.Preset.hd1920x1080
                            break;
                        case 3:
                            self.captureSession?.sessionPreset = AVCaptureSession.Preset.hd4K3840x2160
                            break;
                        case 4:
                            self.captureSession?.sessionPreset = AVCaptureSession.Preset.high
                            break;
                        case 5:
                            self.captureSession?.sessionPreset = AVCaptureSession.Preset.low
                            break;
                        case 6:
                            self.captureSession?.sessionPreset = AVCaptureSession.Preset.cif352x288
                            break;
                        default:
                            self.captureSession?.sessionPreset = AVCaptureSession.Preset.vga640x480
                            break;
                        }

                        let connection: AVCaptureConnection? = self.videoOutput?.connection(with: .video)
                        self.videoOutput?.setOutputSettings([AVVideoCodecKey : AVVideoCodecType.h264], for: connection!)

                        // Commit configurations
                        self.captureSession?.commitConfiguration()

                        // Configure the audio session AFTER the capture session is fully
                        // committed. Because `automaticallyConfiguresApplicationAudioSession`
                        // is false, nothing overwrites these options, so `.mixWithOthers`
                        // actually sticks and other apps' audio (e.g. background music)
                        // keeps playing while the camera previews and records.
                        self.configureAudioSessionForMixing()

                        // Route metering samples to our delegate on a dedicated queue.
                        self.audioDataOutput?.setSampleBufferDelegate(self, queue: self.audioMeterQueue)

                        // Start running sessions
                        self.captureSession!.startRunning()

                        // Initialize camera view
                        self.initializeCameraView()

                        if autoShow {
                            self.cameraView.isHidden = false
                        }

                    } catch CaptureError.backCameraUnavailable {
                        call.reject("Back camera unavailable")
                    } catch CaptureError.frontCameraUnavailable {
                        call.reject("Front camera unavailable")
                    } catch CaptureError.couldNotCaptureInput( _){
                        call.reject("Camera unavailable")
                    } catch {
                        call.reject("Unexpected error")
                    }
                    call.resolve()
                }
            }
        }
    }

	/**
	* Destroys the camera.
	*/
    @objc func destroy(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            let appDelegate = UIApplication.shared.delegate
            appDelegate?.window?!.backgroundColor = UIColor.black

            self.capWebView?.isOpaque = true
            self.capWebView?.backgroundColor = UIColor.white
            if (self.captureSession != nil) {
				// Need to destroy all preview layers
                self.previewFrameConfigs = []
                self.currentFrameConfig = FrameConfig(["id": "default"])
                if (self.captureSession!.isRunning) {
                    self.captureSession!.stopRunning()
                }
                self.audioDataOutput?.setSampleBufferDelegate(nil, queue: nil)
                self.cameraView?.removePreviewLayer()
                self.captureVideoPreviewLayer = nil
                self.cameraView?.removeFromSuperview()
                self.videoOutput = nil
                self.audioDataOutput = nil
                self.cameraView = nil
                self.captureSession = nil
                self.currentCamera = 0
                self.frontCamera = nil
                self.backCamera = nil
                self.allCameras = []
                self.isMicrophoneEnabled = true
                self.recordingSegments = []
                self.pendingCameraSwitch = nil
                self.shouldStopAfterSwitch = false
                self.notifyListeners("onVolumeInput", data: ["value":0])
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            }
            call.resolve()
        }
    }

	/**
	* Toggle between the front facing and rear facing camera.
	*/
    @objc func flipCamera(_ call: CAPPluginCall) {
        guard self.captureSession != nil else { return }

        let newCameraPosition = self.currentCamera == 0 ? 1 : 0
        let newInput: AVCaptureDeviceInput
        do {
            newInput = try createCaptureDeviceInput(currentCamera: newCameraPosition, frontCamera: self.frontCamera, backCamera: self.backCamera)
        } catch CaptureError.backCameraUnavailable {
            call.reject("Back camera unavailable")
            return
        } catch CaptureError.frontCameraUnavailable {
            call.reject("Front camera unavailable")
            return
        } catch CaptureError.couldNotCaptureInput(_) {
            call.reject("Camera unavailable")
            return
        } catch {
            call.reject("Unexpected error")
            return
        }

        if videoOutput?.isRecording == true {
            pendingCameraSwitch = { [weak self] in
                guard let self = self else { return }
                self.performCameraSwitch(to: newInput, newCameraPosition: newCameraPosition)
                self.beginRecordingSegment()
            }
            self.videoOutput?.stopRecording()
        } else {
            performCameraSwitch(to: newInput, newCameraPosition: newCameraPosition)
        }

        call.resolve()
    }

	/**
	* Add a camera preview frame config.
	*/
    @objc func addPreviewFrameConfig(_ call: CAPPluginCall) {
        if (self.captureSession != nil) {
            guard let layerId = call.getString("id") else {
                call.reject("Must provide layer id")
                return
            }
			let newFrame = FrameConfig(call.options)

            // Check to make sure config doesn't already exist, if it does, edit it instead
            if (self.previewFrameConfigs.firstIndex(where: {$0.id == layerId }) == nil) {
                self.previewFrameConfigs.append(newFrame)
            }
            else {
                self.editPreviewFrameConfig(call)
                return
            }
			call.resolve()
        }
    }

	/**
	* Edit an existing camera frame config.
	*/
    @objc func editPreviewFrameConfig(_ call: CAPPluginCall) {
        if (self.captureSession != nil) {
            guard let layerId = call.getString("id") else {
                call.reject("Must provide layer id")
                return
            }

            let updatedConfig = FrameConfig(call.options)

            // Get existing frame config
            let existingConfig = self.previewFrameConfigs.filter( {$0.id == layerId }).first
            if (existingConfig != nil) {
                let index = self.previewFrameConfigs.firstIndex(where: {$0.id == layerId })
                self.previewFrameConfigs[index!] = updatedConfig
            }
            else {
                self.addPreviewFrameConfig(call)
                return
            }

            if (self.currentFrameConfig.id == layerId) {
                // Is set to the current frame, need to update
                DispatchQueue.main.async {
                    self.currentFrameConfig = updatedConfig
                    self.updateCameraView(self.currentFrameConfig)
                }
            }
            call.resolve()
        }
    }

    /**
     * Switch frame configs.
     */
    @objc func switchToPreviewFrame(_ call: CAPPluginCall) {
        if (self.captureSession != nil) {
            guard let layerId = call.getString("id") else {
                call.reject("Must provide layer id")
                return
            }
            DispatchQueue.main.async {
                let existingConfig = self.previewFrameConfigs.filter( {$0.id == layerId }).first
                if (existingConfig != nil) {
                    if (existingConfig!.id != self.currentFrameConfig.id) {
                        self.currentFrameConfig = existingConfig!
                        self.updateCameraView(self.currentFrameConfig)
                    }
                }
                else {
                    call.reject("Frame config does not exist")
                    return
                }
                call.resolve()
            }
        }
    }

	/**
	* Show the camera preview frame.
	*/
    @objc func showPreviewFrame(_ call: CAPPluginCall) {
        if (self.captureSession != nil) {
            DispatchQueue.main.async {
                self.cameraView.isHidden = true
                call.resolve()
            }
        }
    }

	/**
	* Hide the camera preview frame.
	*/
    @objc func hidePreviewFrame(_ call: CAPPluginCall) {
        if (self.captureSession != nil) {
            DispatchQueue.main.async {
                self.cameraView.isHidden = false
                call.resolve()
            }
        }
    }

    func initializeCameraView() {
        self.cameraView = CameraView(frame: CGRect(x: 0, y: 0, width: 0, height: 0))
        self.cameraView.isHidden = true
        self.cameraView.autoresizingMask = [.flexibleWidth, .flexibleHeight];
        self.captureVideoPreviewLayer = AVCaptureVideoPreviewLayer(session: self.captureSession!)
        self.captureVideoPreviewLayer?.frame = self.cameraView.bounds
        self.cameraView.addPreviewLayer(self.captureVideoPreviewLayer)

        self.cameraView.backgroundColor = UIColor.black
        self.cameraView.videoPreviewLayer?.masksToBounds = true
        self.cameraView.clipsToBounds = false
        self.cameraView.layer.backgroundColor = UIColor.clear.cgColor

        self.capWebView!.superview!.insertSubview(self.cameraView, belowSubview: self.capWebView!)

        self.updateCameraView(self.currentFrameConfig)
    }

    func updateCameraView(_ config: FrameConfig) {
        // Set position and dimensions
        let width = config.width as? String == "fill" ? UIScreen.main.bounds.width : config.width as! CGFloat
        let height = config.height as? String == "fill" ? UIScreen.main.bounds.height : config.height as! CGFloat
        self.cameraView.frame = CGRect(x: config.x, y: config.y, width: width, height: height)

        // Set stackPosition
        if config.stackPosition == "front" {
            self.capWebView!.superview!.bringSubviewToFront(self.cameraView)
        }
        else if config.stackPosition == "back" {
            self.capWebView!.superview!.sendSubviewToBack(self.cameraView)
        }

        // Set decorations
        self.cameraView.videoPreviewLayer?.cornerRadius = config.borderRadius
        self.cameraView.layer.shadowOffset = CGSize.zero
        self.cameraView.layer.shadowColor = config.dropShadow.color
        self.cameraView.layer.shadowOpacity = config.dropShadow.opacity
        self.cameraView.layer.shadowRadius = config.dropShadow.radius
        self.cameraView.layer.shadowPath = UIBezierPath(roundedRect: self.cameraView.bounds, cornerRadius: config.borderRadius).cgPath

        // Set mirroring based on config.mirrorFrontCam property (only for front camera, mirrored by default)
        if let connection = self.cameraView.videoPreviewLayer?.connection {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = self.currentCamera == 0 ? config.mirrorFrontCam : false
        }
    }

	/**
	* Start recording.
	*/
    @objc func startRecording(_ call: CAPPluginCall) {
        if (self.captureSession != nil) {
            if (!(videoOutput?.isRecording)!) {
                recordingSegments = []
                pendingCameraSwitch = nil
                shouldStopAfterSwitch = false

                let tempDir = NSURL.fileURL(withPath:NSTemporaryDirectory(), isDirectory: true)
                var fileName = randomFileName()
                fileName.append(".mp4")
                let fileUrl = NSURL.fileURL(withPath: joinPath(left: tempDir.path, right: fileName))

                // Configure video output settings
                let videoSettings: [String: Any] = [
                    AVVideoCodecKey: AVVideoCodecType.h264,
                    AVVideoCompressionPropertiesKey: [
                        AVVideoAverageBitRateKey: self.videoBitrate
                    ]
                ]

                if let connection = self.videoOutput?.connection(with: .video) {
                    self.videoOutput?.setOutputSettings(videoSettings, for: connection)
                }

                DispatchQueue.main.async {
                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                        self.videoOutput?.connection(with: .video)?.videoOrientation = self.cameraView.interfaceOrientationToVideoOrientation(windowScene.interfaceOrientation)
                    }

                    // Apply mirroring setting to video output connection (saved video should never be mirrored to match Android behavior)
                    if let connection = self.videoOutput?.connection(with: .video) {
                        connection.automaticallyAdjustsVideoMirroring = false
                        connection.isVideoMirrored = false
                    }
                    self.applyTorchState()
                    if let audioConnection = self.videoOutput?.connection(with: .audio) {
                        audioConnection.isEnabled = self.isMicrophoneEnabled
                    }
                    // Re-assert mixing in case starting the recording nudged the audio session,
                    // so background music keeps playing throughout the recording.
                    self.configureAudioSessionForMixing()
                    self.videoOutput?.startRecording(to: fileUrl, recordingDelegate: self)
                    call.resolve()
                }
            }
        }
    }

	/**
	* Stop recording.
	*/
    @objc func stopRecording(_ call: CAPPluginCall) {
        if (self.captureSession != nil) {
            self.stopRecordingCall = call

            if pendingCameraSwitch != nil {
                // A segment transition is in progress; mark to stop once the next segment starts
                shouldStopAfterSwitch = true
                return
            }

            if (videoOutput?.isRecording)! {
                self.videoOutput!.stopRecording()

                if self.currentCamera == 1 {
                    guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
                    do {
                        try device.lockForConfiguration()
                        device.torchMode = .off
                        device.unlockForConfiguration()
                    } catch {}
                }
            }
        }
    }

	/**
	* Get current recording duration.
	*/
    @objc func getDuration(_ call: CAPPluginCall) {
        if (self.videoOutput!.isRecording == true) {
            let duration = self.videoOutput?.recordedDuration;
            if (duration != nil) {
                call.resolve(["value":round(CMTimeGetSeconds(duration!))])
            } else {
                call.resolve(["value":0])
            }
        } else {
            call.resolve(["value":0])
        }
    }

    @objc func enableMicrophone(_ call: CAPPluginCall) {
        self.isMicrophoneEnabled = true
        if videoOutput?.isRecording != true {
            if let audioConnection = self.videoOutput?.connection(with: .audio) {
                audioConnection.isEnabled = true
            }
        }
        call.resolve()
    }

    @objc func disableMicrophone(_ call: CAPPluginCall) {
        self.isMicrophoneEnabled = false
        if videoOutput?.isRecording != true {
            if let audioConnection = self.videoOutput?.connection(with: .audio) {
                audioConnection.isEnabled = false
            }
        }
        call.resolve()
    }

    @objc func getAvailableCameras(_ call: CAPPluginCall) {
        DispatchQueue.global(qos: .userInitiated).async {
            if self.allCameras.isEmpty {
                let discovery = AVCaptureDevice.DiscoverySession(
                    deviceTypes: [
                        .builtInWideAngleCamera,
                        .builtInUltraWideCamera,
                        .builtInTelephotoCamera
                    ],
                    mediaType: .video,
                    position: .unspecified
                )
                self.allCameras = discovery.devices
            }
            let cameras: [[String: Any]] = self.allCameras.map { device in
                let position = device.position == .front ? "front" : "back"
                var type = "wide"
                if #available(iOS 13.0, *) {
                    switch device.deviceType {
                    case .builtInUltraWideCamera: type = "ultrawide"
                    case .builtInTelephotoCamera: type = "telephoto"
                    default: type = "wide"
                    }
                }
                return ["id": device.uniqueID, "position": position, "type": type]
            }
            call.resolve(["cameras": cameras])
        }
    }

    @objc func switchCamera(_ call: CAPPluginCall) {
        guard self.captureSession != nil else {
            call.reject("Camera not initialized")
            return
        }
        guard let cameraId = call.getString("cameraId") else {
            call.reject("Must provide cameraId")
            return
        }
        guard let device = self.allCameras.first(where: { $0.uniqueID == cameraId }) else {
            call.reject("Camera not found")
            return
        }
        do {
            let newInput = try AVCaptureDeviceInput(device: device)
            let newCameraPosition = device.position == .front ? 0 : 1

            if videoOutput?.isRecording == true {
                pendingCameraSwitch = { [weak self] in
                    guard let self = self else { return }
                    self.performCameraSwitch(to: newInput, newCameraPosition: newCameraPosition)
                    self.beginRecordingSegment()
                }
                self.videoOutput?.stopRecording()
                call.resolve()
            } else {
                self.captureSession?.beginConfiguration()
                if let currentInput = self.cameraInput {
                    self.captureSession?.removeInput(currentInput)
                }
                guard self.captureSession?.canAddInput(newInput) == true else {
                    if let currentInput = self.cameraInput {
                        self.captureSession?.addInput(currentInput)
                    }
                    self.captureSession?.commitConfiguration()
                    call.reject("Cannot use selected camera in current session")
                    return
                }
                self.captureSession?.addInput(newInput)
                self.cameraInput = newInput
                self.currentCamera = newCameraPosition
                self.captureSession?.commitConfiguration()
                DispatchQueue.main.async {
                    self.updateCameraView(self.currentFrameConfig)
                }
                call.resolve()
            }
        } catch {
            call.reject("Could not switch camera: \(error.localizedDescription)")
        }
    }

    /// Which of a device's `AVCaptureDevice.Format`s to consult for the max frame rate of a
    /// quality: an exact resolution match for the fixed presets, or the largest/smallest
    /// available format for `.high`/`.low` (which pick a resolution dynamically per device).
    private enum FrameRateFormatSelection {
        case exactSize(width: Int32, height: Int32)
        case largest
        case smallest
    }

    /// Maps each `VideoRecorderQuality` raw value (see definitions.ts) to the session preset
    /// `initialize()` applies for it, so support can be checked without an active session.
    private static let qualityPresets: [(Int, AVCaptureSession.Preset, FrameRateFormatSelection)] = [
        (0, .vga640x480, .exactSize(width: 640, height: 480)),
        (1, .hd1280x720, .exactSize(width: 1280, height: 720)),
        (2, .hd1920x1080, .exactSize(width: 1920, height: 1080)),
        (3, .hd4K3840x2160, .exactSize(width: 3840, height: 2160)),
        (4, .high, .largest),
        (5, .low, .smallest),
        (6, .cif352x288, .exactSize(width: 352, height: 288)),
    ]

    private static func pixelCount(of format: AVCaptureDevice.Format) -> Int32 {
        let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        return dimensions.width * dimensions.height
    }

    /// The highest frame rate the device can record at for a given quality, found by matching
    /// its resolution (or, for `.high`/`.low`, the largest/smallest available) against the
    /// device's supported formats and reading their frame rate ranges.
    private static func maxFrameRate(for device: AVCaptureDevice, selection: FrameRateFormatSelection) -> Double {
        let formats = device.formats
        let candidates: [AVCaptureDevice.Format]

        switch selection {
        case .exactSize(let width, let height):
            let matches = formats.filter {
                let dimensions = CMVideoFormatDescriptionGetDimensions($0.formatDescription)
                return dimensions.width == width && dimensions.height == height
            }
            candidates = matches.isEmpty ? formats : matches
        case .largest:
            candidates = formats.max(by: { pixelCount(of: $0) < pixelCount(of: $1) }).map { [$0] } ?? formats
        case .smallest:
            candidates = formats.min(by: { pixelCount(of: $0) < pixelCount(of: $1) }).map { [$0] } ?? formats
        }

        let maxRate = candidates
            .flatMap { $0.videoSupportedFrameRateRanges }
            .map { $0.maxFrameRate }
            .max()

        return maxRate ?? 30
    }

    @objc func getAvailableQualities(_ call: CAPPluginCall) {
        let devicePosition: AVCaptureDevice.Position
        if let cameraOption = call.getInt("camera") {
            devicePosition = cameraOption == 1 ? .back : .front
        } else if self.captureSession != nil {
            devicePosition = self.currentCamera == 1 ? .back : .front
        } else {
            devicePosition = .back
        }

        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: devicePosition
        )

        guard let device = discoverySession.devices.first else {
            call.reject(devicePosition == .back ? "Back camera unavailable" : "Front camera unavailable")
            return
        }

        let qualities: [[String: Any]] = VideoRecorder.qualityPresets.compactMap { (raw, preset, selection) in
            guard device.supportsSessionPreset(preset) else { return nil }
            return [
                "quality": raw,
                "maxFps": VideoRecorder.maxFrameRate(for: device, selection: selection)
            ]
        }

        call.resolve(["qualities": qualities])
    }

    @objc func isFlashAvailable(_ call: CAPPluginCall) {
        if (self.captureSession != nil) {
            let device = AVCaptureDevice.default(for: .video)
            if let device = device {
                call.resolve(["isAvailable": device.hasTorch])
            } else {
                call.resolve(["isAvailable": false])
            }
        }
    }

    @objc func isFlashEnabled(_ call: CAPPluginCall) {
        call.resolve(["isEnabled": self._isFlashEnabled])
    }

    @objc func enableFlash(_ call: CAPPluginCall) {
        self._isFlashEnabled = true
        self.applyTorchState()
        call.resolve()
    }

    @objc func disableFlash(_ call: CAPPluginCall) {
        self._isFlashEnabled = false
        self.applyTorchState()
        call.resolve()
    }

    @objc func toggleFlash(_ call: CAPPluginCall) {
        self._isFlashEnabled = !self._isFlashEnabled
        self.applyTorchState()
        call.resolve()
    }

    private func applyTorchState() {
        guard self.currentCamera == 1 else { return }
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            if self._isFlashEnabled {
                try device.setTorchModeOn(level: 1.0)
            } else {
                device.torchMode = .off
            }
            device.unlockForConfiguration()
        } catch {}
    }

    /**
     * Video editing, ported from https://github.com/dragermrb/capacitor-plugin-video-editor
     */
    @objc func editVideo(_ call: CAPPluginCall) {
        guard let path = call.getString("path"), !path.isEmpty else {
            call.reject("Input file path is required")
            return
        }

        let trim = call.getObject("trim") ?? JSObject()
        let transcode = call.getObject("transcode") ?? JSObject()

        do {
            let trimSettings = try TrimSettings(
                startsAt: self.intValue(trim, "startsAt", 0),
                endsAt: self.intValue(trim, "endsAt", 0)
            )

            let transcodeSettings = try TranscodeSettings(
                height: self.intValue(transcode, "height", 0),
                width: self.intValue(transcode, "width", 0),
                keepAspectRatio: transcode["keepAspectRatio"] as? Bool ?? true,
                fps: self.intValue(transcode, "fps", 30),
                videoBitrate: self.intValue(transcode, "videoBitrate", 0)
            )

            let srcFile = self.sourceUrl(from: path)
            let outFile = self.getDestVideoUrl()

            guard FileManager.default.isReadableFile(atPath: srcFile.path) else {
                call.reject("Cannot read input file: \(srcFile.path)")
                return
            }

            // Transcoding is heavy enough that running two at once helps nobody, and a single
            // in-flight edit is what makes cancelEdit() unambiguous.
            guard self.beginEdit() else {
                call.reject("An edit is already in progress", VideoRecorder.editInProgressCode)
                return
            }

            self.videoEditor.edit(
                srcFile: srcFile,
                outFile: outFile,
                trimSettings: trimSettings,
                transcodeSettings: transcodeSettings,
                completionHandler: { [weak self] url in
                    guard let self = self else { return }
                    self.finishEdit()
                    call.resolve(["file": self.createMediaFile(url: url)])
                },
                progressHandler: { [weak self] progress in
                    self?.notifyListeners("transcodeProgress", data: ["progress": progress])
                },
                errorHandler: { [weak self] error in
                    self?.finishEdit()
                    try? FileManager.default.removeItem(at: outFile)

                    if error == VideoTranscoderError.cancelled.localizedDescription {
                        call.reject(error, VideoRecorder.editCanceledCode)
                    } else {
                        call.reject(error)
                    }
                }
            )
        } catch TrimSettingsError.invalidArgument(let message) {
            call.reject(message)
        } catch TranscodeSettingsError.invalidArgument(let message) {
            call.reject(message)
        } catch {
            call.reject("Invalid parameters: \(error.localizedDescription)")
        }
    }

    @objc func generateThumbnail(_ call: CAPPluginCall) {
        guard let path = call.getString("path"), !path.isEmpty else {
            call.reject("Input file path is required")
            return
        }

        let atMs = call.getInt("at") ?? 0
        let width = call.getInt("width") ?? 0
        let height = call.getInt("height") ?? 0

        let srcFile = self.sourceUrl(from: path)
        let outFile = self.getDestImageUrl()

        guard FileManager.default.isReadableFile(atPath: srcFile.path) else {
            call.reject("Cannot read input file: \(srcFile.path)")
            return
        }

        Task {
            do {
                try await self.videoEditor.thumbnail(
                    srcFile: srcFile,
                    outFile: outFile,
                    atMs: atMs,
                    width: width,
                    height: height
                )

                call.resolve(["file": self.createMediaFile(url: outFile)])
            } catch {
                try? FileManager.default.removeItem(at: outFile)
                call.reject(error.localizedDescription)
            }
        }
    }

    @objc func cancelEdit(_ call: CAPPluginCall) {
        // The pending editVideo() call is rejected from its error handler.
        self.videoEditor.cancel()
        call.resolve()
    }

    /**
     * Reads a numeric option. JS numbers reach the bridge as NSNumber, so a value written as
     * 1000.0 still has to be accepted where an Int is expected.
     */
    func intValue(_ object: JSObject, _ key: String, _ defaultValue: Int) -> Int {
        guard let number = object[key] as? NSNumber else {
            return defaultValue
        }

        return number.intValue
    }

    /**
     * Accepts a file:// url as well as a bare filesystem path.
     */
    func sourceUrl(from path: String) -> URL {
        if let url = URL(string: path), url.isFileURL {
            return url
        }

        // URL(string:) returns nil for an unencoded url, which a path holding a space produces.
        if path.hasPrefix("file://") {
            return URL(fileURLWithPath: String(path.dropFirst("file://".count)))
        }

        return URL(fileURLWithPath: path)
    }

    func getDestVideoUrl() -> URL {
        return URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(NSUUID().uuidString)
            .appendingPathExtension("mp4")
    }

    func getDestImageUrl() -> URL {
        return URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(NSUUID().uuidString)
            .appendingPathExtension("jpg")
    }

    func createMediaFile(url: URL) -> JSObject {
        var fileSize = 0

        if let resources = try? url.resourceValues(forKeys: [.fileSizeKey]) {
            fileSize = resources.fileSize ?? 0
        }

        var file = JSObject()

        file["name"] = url.lastPathComponent
        file["path"] = url.absoluteString
        file["type"] = self.getMimeType(url: url)
        file["size"] = fileSize

        return file
    }

    func getMimeType(url: URL) -> String {
        if let type = UTType(filenameExtension: url.pathExtension), let mimeType = type.preferredMIMEType {
            return mimeType
        }

        return "application/octet-stream"
    }
}
