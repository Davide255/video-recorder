import Foundation
import AVFoundation
import UIKit

/// Trimming, transcoding and thumbnail extraction, ported from
/// https://github.com/dragermrb/capacitor-plugin-video-editor
@objc public class VideoEditor: NSObject {

    static let defaultAudioBitrate = 128000
    static let thumbnailQuality: CGFloat = 0.8

    private let transcoder = VideoTranscoder()

    /// For AVC this is a reasonable default.
    /// See https://stackoverflow.com/a/5220554/4288782
    static func estimateVideoBitRate(width: Int, height: Int, frameRate: Int) -> Int {
        return Int(0.07 * 2 * Float(width) * Float(height) * Float(frameRate))
    }

    @objc public func edit(
        srcFile: URL,
        outFile: URL,
        trimSettings: TrimSettings,
        transcodeSettings: TranscodeSettings,
        completionHandler: @escaping (URL) -> Void,
        progressHandler: @escaping (Float) -> Void,
        errorHandler: @escaping (String) -> Void
    ) {
        let avAsset = AVURLAsset(url: srcFile, options: nil)

        guard let videoTrack = avAsset.tracks(withMediaType: AVMediaType.video).first else {
            errorHandler(VideoTranscoderError.noVideoTrack.localizedDescription)
            return
        }

        let transformedVideoSize = videoTrack.naturalSize.applying(videoTrack.preferredTransform)
        let mediaSize = CGSize(width: abs(transformedVideoSize.width), height: abs(transformedVideoSize.height))

        // Resolution
        let targetVideoSize = calculateTargetVideoSize(sourceVideoSize: mediaSize, transcodeSettings: transcodeSettings)

        guard targetVideoSize.width >= 2, targetVideoSize.height >= 2 else {
            errorHandler("Target video size is too small: \(Int(targetVideoSize.width))x\(Int(targetVideoSize.height))")
            return
        }

        // Trim
        let timeRange = calculateTimeRange(asset: avAsset, trimSettings: trimSettings)

        guard timeRange.duration.seconds > 0 else {
            errorHandler("Trim range is empty: nothing to export")
            return
        }

        let configuration = VideoTranscoder.Configuration(
            outputURL: outFile,
            timeRange: timeRange,
            targetSize: targetVideoSize,
            fps: transcodeSettings.getFps(),
            videoBitrate: calculateTargetVideoBitrate(
                videoTrack: videoTrack,
                targetVideoSize: targetVideoSize,
                transcodeSettings: transcodeSettings
            ),
            audioBitrate: calculateTargetAudioBitrate(asset: avAsset)
        )

        transcoder.export(
            asset: avAsset,
            configuration: configuration,
            progressHandler: progressHandler,
            completion: { result in
                switch result {
                case .success(let outputURL):
                    completionHandler(outputURL)
                case .failure(let error):
                    errorHandler(error.localizedDescription)
                }
            }
        )
    }

    @objc public func thumbnail(
        srcFile: URL,
        outFile: URL,
        atMs: Int,
        width: Int,
        height: Int
    ) async throws {
        let asset = AVURLAsset(url: srcFile, options: nil)
        let imgGenerator = AVAssetImageGenerator(asset: asset)
        imgGenerator.appliesPreferredTrackTransform = true
        // Without this the generator is free to return a key frame seconds away from the request.
        imgGenerator.requestedTimeToleranceBefore = .zero
        imgGenerator.requestedTimeToleranceAfter = .zero

        let at = min(asset.duration, CMTimeMake(value: Int64(atMs), timescale: 1000))
        let cgImage: CGImage

        if #available(iOS 16, *) {
            cgImage = try await imgGenerator.image(at: at).image
        } else {
            cgImage = try imgGenerator.copyCGImage(at: at, actualTime: nil)
        }

        let thumbnail = scaleToFit(image: UIImage(cgImage: cgImage), width: width, height: height)

        guard let data = thumbnail.jpegData(compressionQuality: VideoEditor.thumbnailQuality) else {
            throw VideoTranscoderError.cannotWriteOutput("could not encode the thumbnail as JPEG")
        }

        try data.write(to: outFile)
    }

    /// Scales the frame to fit inside the requested box, preserving the aspect ratio. Either bound
    /// may be 0, in which case only the other one constrains the result; when both are 0 the frame
    /// is returned untouched.
    func scaleToFit(image: UIImage, width: Int, height: Int) -> UIImage {
        guard width > 0 || height > 0 else {
            return image
        }

        let sourceSize = image.size

        guard sourceSize.width > 0, sourceSize.height > 0 else {
            return image
        }

        let aspectRatio = sourceSize.width / sourceSize.height
        var targetWidth: CGFloat
        var targetHeight: CGFloat

        if width > 0 && height > 0 {
            // Fit inside the box: whichever bound is reached first wins.
            if CGFloat(width) / CGFloat(height) > aspectRatio {
                targetHeight = CGFloat(height)
                targetWidth = (CGFloat(height) * aspectRatio).rounded()
            } else {
                targetWidth = CGFloat(width)
                targetHeight = (CGFloat(width) / aspectRatio).rounded()
            }
        } else if width > 0 {
            targetWidth = CGFloat(width)
            targetHeight = (CGFloat(width) / aspectRatio).rounded()
        } else {
            targetHeight = CGFloat(height)
            targetWidth = (CGFloat(height) * aspectRatio).rounded()
        }

        targetWidth = max(1, targetWidth)
        targetHeight = max(1, targetHeight)

        if targetWidth == sourceSize.width && targetHeight == sourceSize.height {
            return image
        }

        let targetSize = CGSize(width: targetWidth, height: targetHeight)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1

        return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    /// Clamps the requested trim window to what the source actually contains.
    func calculateTimeRange(asset: AVAsset, trimSettings: TrimSettings) -> CMTimeRange {
        let start = min(
            CMTimeMake(value: Int64(trimSettings.getStartsAt()), timescale: 1000),
            asset.duration
        )
        let end = trimSettings.getEndsAt() > 0
            ? min(CMTimeMake(value: Int64(trimSettings.getEndsAt()), timescale: 1000), asset.duration)
            : asset.duration
        let duration = max(.zero, end - start)

        return CMTimeRangeMake(start: start, duration: duration)
    }

    /// Honours an explicit bitrate when the caller provided one, otherwise estimates one from the
    /// output size and caps it at the source bitrate so re-encoding never inflates the file.
    func calculateTargetVideoBitrate(
        videoTrack: AVAssetTrack,
        targetVideoSize: CGSize,
        transcodeSettings: TranscodeSettings
    ) -> Int {
        if transcodeSettings.getVideoBitrate() > 0 {
            return transcodeSettings.getVideoBitrate()
        }

        let estimated = VideoEditor.estimateVideoBitRate(
            width: Int(targetVideoSize.width),
            height: Int(targetVideoSize.height),
            frameRate: transcodeSettings.getFps()
        )
        let sourceBitrate = Int(videoTrack.estimatedDataRate)

        return sourceBitrate > 0 ? min(estimated, sourceBitrate) : estimated
    }

    func calculateTargetAudioBitrate(asset: AVAsset) -> Int {
        guard let audioTrack = asset.tracks(withMediaType: .audio).first else {
            return VideoEditor.defaultAudioBitrate
        }

        let sourceBitrate = Int(audioTrack.estimatedDataRate)

        return sourceBitrate > 0 ? min(VideoEditor.defaultAudioBitrate, sourceBitrate) : VideoEditor.defaultAudioBitrate
    }

    func calculateTargetVideoSize(sourceVideoSize: CGSize, transcodeSettings: TranscodeSettings) -> CGSize {
        if transcodeSettings.isKeepAspectRatio() {
            let mostSize = transcodeSettings.getWidth() == 0 && transcodeSettings.getHeight() == 0
                ? 1280
                : max(transcodeSettings.getWidth(), transcodeSettings.getHeight())

            return calculateVideoSizeAtMost(sourceVideoSize: sourceVideoSize, mostSize: mostSize)
        } else {
            if transcodeSettings.getWidth() > 0 && transcodeSettings.getHeight() > 0 {
                return CGSize(
                    width: transcodeSettings.getWidth(),
                    height: transcodeSettings.getHeight()
                )
            } else {
                return calculateVideoSizeAtMost(sourceVideoSize: sourceVideoSize, mostSize: 720)
            }
        }
    }

    func calculateVideoSizeAtMost(sourceVideoSize: CGSize, mostSize: Int) -> CGSize {
        let sourceMajor = Int(max(sourceVideoSize.width, sourceVideoSize.height))

        var outWidth: Int
        var outHeight: Int

        if sourceMajor <= mostSize {
            // No resize needed
            outWidth = Int(sourceVideoSize.width)
            outHeight = Int(sourceVideoSize.height)
        } else if sourceVideoSize.width >= sourceVideoSize.height {
            // Landscape
            let inputRatio = Float(sourceVideoSize.height) / Float(sourceVideoSize.width)

            outWidth = mostSize
            outHeight = Int(Float(mostSize) * inputRatio)
        } else {
            // Portrait
            let inputRatio = Float(sourceVideoSize.width) / Float(sourceVideoSize.height)

            outHeight = mostSize
            outWidth = Int(Float(mostSize) * inputRatio)
        }

        // Most hardware encoders reject odd dimensions.
        if outWidth % 2 != 0 {
            outWidth -= 1
        }
        if outHeight % 2 != 0 {
            outHeight -= 1
        }

        return CGSize(width: outWidth, height: outHeight)
    }
}
