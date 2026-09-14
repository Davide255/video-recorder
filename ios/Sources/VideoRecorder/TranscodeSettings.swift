import Foundation

enum TranscodeSettingsError: Error {
    case invalidArgument(message: String)
}

/// Output video settings of an edit operation.
public class TranscodeSettings: NSObject {
    private var height: Int = 0
    private var width: Int = 0
    private var keepAspectRatio: Bool = true
    private var fps: Int = 30
    private var videoBitrate: Int = 0

    init(height: Int, width: Int, keepAspectRatio: Bool, fps: Int, videoBitrate: Int = 0) throws {
        super.init()

        try self.setHeight(height)
        try self.setWidth(width)
        self.setKeepAspectRatio(keepAspectRatio)
        try self.setFps(fps)
        try self.setVideoBitrate(videoBitrate)
    }

    func getHeight() -> Int {
        return self.height
    }

    func setHeight(_ height: Int) throws {
        if height < 0 {
            throw TranscodeSettingsError.invalidArgument(message: "Parameter height cannot be negative")
        }
        self.height = height
    }

    func getWidth() -> Int {
        return self.width
    }

    func setWidth(_ width: Int) throws {
        if width < 0 {
            throw TranscodeSettingsError.invalidArgument(message: "Parameter width cannot be negative")
        }
        self.width = width
    }

    func isKeepAspectRatio() -> Bool {
        return self.keepAspectRatio
    }

    func setKeepAspectRatio(_ keepAspectRatio: Bool) {
        self.keepAspectRatio = keepAspectRatio
    }

    func getFps() -> Int {
        return self.fps
    }

    func setFps(_ fps: Int) throws {
        if fps < 1 {
            throw TranscodeSettingsError.invalidArgument(message: "Parameter fps cannot be lower than 1")
        }
        self.fps = fps
    }

    /// Requested output bitrate in bits/sec, or 0 to let the plugin estimate one.
    func getVideoBitrate() -> Int {
        return self.videoBitrate
    }

    func setVideoBitrate(_ videoBitrate: Int) throws {
        if videoBitrate < 0 {
            throw TranscodeSettingsError.invalidArgument(message: "Parameter videoBitrate cannot be negative")
        }
        self.videoBitrate = videoBitrate
    }
}
