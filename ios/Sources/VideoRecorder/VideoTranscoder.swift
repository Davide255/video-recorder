import Foundation
import AVFoundation

enum VideoTranscoderError: LocalizedError {
    case noVideoTrack
    case cannotReadSource(String)
    case cannotWriteOutput(String)
    case exportFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .noVideoTrack:
            return "Source file has no video track or could not be decoded"
        case .cannotReadSource(let reason):
            return "Cannot read the source video: \(reason)"
        case .cannotWriteOutput(let reason):
            return "Cannot write the output video: \(reason)"
        case .exportFailed(let reason):
            return "Failed to transcode: \(reason)"
        case .cancelled:
            return "Transcode canceled"
        }
    }
}

/// Trims and transcodes a video with AVAssetReader / AVAssetWriter.
///
/// An `AVAssetExportSession` preset would be shorter, but presets ignore the requested bitrate
/// and resolution, which is what made the upstream plugin produce a different quality on iOS than
/// on Android for the same options. Driving the writer directly keeps both platforms in step and
/// gives an accurate progress signal.
final class VideoTranscoder {

    struct Configuration {
        /// Where to write the result. Any existing file is replaced.
        var outputURL: URL
        /// Portion of the source to keep, in the source timeline.
        var timeRange: CMTimeRange
        /// Size of the output, in pixels. Both dimensions must be even.
        var targetSize: CGSize
        var fps: Int
        /// Output video bitrate, in bits per second.
        var videoBitrate: Int
        /// Output audio bitrate, in bits per second.
        var audioBitrate: Int
        /// Distance between key frames, in seconds.
        var keyFrameIntervalSeconds: Int = 5
        /// Moves the moov atom to the front so the result can be streamed while downloading.
        var optimizeForNetworkUse: Bool = true
    }

    private let videoQueue = DispatchQueue(label: "com.capacitorcommunity.videorecorder.transcoder.video")
    private let audioQueue = DispatchQueue(label: "com.capacitorcommunity.videorecorder.transcoder.audio")

    private let stateLock = NSLock()
    private var reader: AVAssetReader?
    private var writer: AVAssetWriter?
    private var isCancelled = false

    /// Stops the export in progress; its completion handler then reports
    /// `VideoTranscoderError.cancelled`. Safe to call before, during or after an export, and from
    /// any thread.
    func cancel() {
        stateLock.lock()
        isCancelled = true
        let reader = self.reader
        let writer = self.writer
        stateLock.unlock()

        // Both are safe to call on an already finished session.
        reader?.cancelReading()
        writer?.cancelWriting()
    }

    private var cancelled: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }

        return isCancelled
    }

    /// Transcodes `asset` and reports progress between 0 and 1 while it runs.
    ///
    /// Both handlers are called on the main queue; `completion` is called exactly once.
    func export(
        asset: AVAsset,
        configuration: Configuration,
        progressHandler: @escaping (Float) -> Void,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            DispatchQueue.main.async { completion(.failure(VideoTranscoderError.noVideoTrack)) }
            return
        }

        let reader: AVAssetReader
        let writer: AVAssetWriter

        do {
            try? FileManager.default.removeItem(at: configuration.outputURL)

            reader = try AVAssetReader(asset: asset)
            writer = try AVAssetWriter(outputURL: configuration.outputURL, fileType: .mp4)
        } catch {
            DispatchQueue.main.async { completion(.failure(VideoTranscoderError.cannotWriteOutput(error.localizedDescription))) }
            return
        }

        reader.timeRange = configuration.timeRange
        writer.shouldOptimizeForNetworkUse = configuration.optimizeForNetworkUse

        stateLock.lock()
        let cancelledBeforeStart = isCancelled
        if !cancelledBeforeStart {
            self.reader = reader
            self.writer = writer
        }
        stateLock.unlock()

        if cancelledBeforeStart {
            DispatchQueue.main.async { completion(.failure(VideoTranscoderError.cancelled)) }
            return
        }

        // Reader: the video composition applies the source orientation and scales to the target size.
        let videoOutput = AVAssetReaderVideoCompositionOutput(
            videoTracks: [videoTrack],
            videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        videoOutput.videoComposition = self.makeVideoComposition(
            asset: asset,
            videoTrack: videoTrack,
            targetSize: configuration.targetSize,
            fps: configuration.fps
        )
        videoOutput.alwaysCopiesSampleData = false

        guard reader.canAdd(videoOutput) else {
            DispatchQueue.main.async { completion(.failure(VideoTranscoderError.cannotReadSource("video track cannot be decoded"))) }
            return
        }
        reader.add(videoOutput)

        var audioOutput: AVAssetReaderAudioMixOutput?
        if let audioTrack = asset.tracks(withMediaType: .audio).first {
            let output = AVAssetReaderAudioMixOutput(
                audioTracks: [audioTrack],
                audioSettings: [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsBigEndianKey: false,
                    AVLinearPCMIsNonInterleaved: false
                ]
            )
            output.alwaysCopiesSampleData = false

            if reader.canAdd(output) {
                reader.add(output)
                audioOutput = output
            }
        }

        // Writer
        let videoInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: Int(configuration.targetSize.width),
                AVVideoHeightKey: Int(configuration.targetSize.height),
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: configuration.videoBitrate,
                    AVVideoMaxKeyFrameIntervalKey: max(1, configuration.fps * configuration.keyFrameIntervalSeconds),
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                    AVVideoAllowFrameReorderingKey: true
                ]
            ]
        )
        videoInput.expectsMediaDataInRealTime = false

        guard writer.canAdd(videoInput) else {
            DispatchQueue.main.async { completion(.failure(VideoTranscoderError.cannotWriteOutput("video input rejected"))) }
            return
        }
        writer.add(videoInput)

        var audioInput: AVAssetWriterInput?
        if audioOutput != nil {
            let input = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVNumberOfChannelsKey: 2,
                    AVSampleRateKey: 44100,
                    AVEncoderBitRateKey: configuration.audioBitrate
                ]
            )
            input.expectsMediaDataInRealTime = false

            if writer.canAdd(input) {
                writer.add(input)
                audioInput = input
            } else {
                audioOutput = nil
            }
        }

        guard writer.startWriting() else {
            let reason = writer.error?.localizedDescription ?? "unknown error"
            DispatchQueue.main.async { completion(.failure(VideoTranscoderError.cannotWriteOutput(reason))) }
            return
        }

        guard reader.startReading() else {
            let reason = reader.error?.localizedDescription ?? "unknown error"
            writer.cancelWriting()
            DispatchQueue.main.async { completion(.failure(VideoTranscoderError.cannotReadSource(reason))) }
            return
        }

        writer.startSession(atSourceTime: configuration.timeRange.start)

        let group = DispatchGroup()
        let durationSeconds = configuration.timeRange.duration.seconds
        var lastReportedProgress: Float = 0

        group.enter()
        self.pump(input: videoInput, output: videoOutput, on: self.videoQueue, group: group) { presentationTime in
            guard durationSeconds > 0 else { return }

            let elapsed = (presentationTime - configuration.timeRange.start).seconds
            let progress = Float(min(max(elapsed / durationSeconds, 0), 1))

            // The bridge does not need a message per frame, only meaningful movement.
            guard progress - lastReportedProgress >= 0.01 else { return }
            lastReportedProgress = progress

            DispatchQueue.main.async { progressHandler(progress) }
        }

        if let audioInput = audioInput, let audioOutput = audioOutput {
            group.enter()
            self.pump(input: audioInput, output: audioOutput, on: self.audioQueue, group: group, onSample: nil)
        }

        group.notify(queue: self.videoQueue) {
            self.clearSession()

            if self.cancelled {
                // cancelReading()/cancelWriting() also mark the sessions failed, so this has to be
                // checked before their status.
                reader.cancelReading()
                writer.cancelWriting()
                try? FileManager.default.removeItem(at: configuration.outputURL)
                DispatchQueue.main.async { completion(.failure(VideoTranscoderError.cancelled)) }
                return
            }

            if reader.status == .failed {
                let reason = reader.error?.localizedDescription ?? "unknown error"
                writer.cancelWriting()
                DispatchQueue.main.async { completion(.failure(VideoTranscoderError.cannotReadSource(reason))) }
                return
            }

            if writer.status == .failed {
                let reason = writer.error?.localizedDescription ?? "unknown error"
                reader.cancelReading()
                DispatchQueue.main.async { completion(.failure(VideoTranscoderError.exportFailed(reason))) }
                return
            }

            writer.finishWriting {
                DispatchQueue.main.async {
                    switch writer.status {
                    case .completed:
                        progressHandler(1)
                        completion(.success(configuration.outputURL))
                    default:
                        let reason = writer.error?.localizedDescription ?? "unknown error"
                        completion(.failure(VideoTranscoderError.exportFailed(reason)))
                    }
                }
            }
        }
    }

    private func clearSession() {
        stateLock.lock()
        reader = nil
        writer = nil
        stateLock.unlock()
    }

    /// Feeds every sample of `output` into `input`, then leaves `group` exactly once.
    private func pump(
        input: AVAssetWriterInput,
        output: AVAssetReaderOutput,
        on queue: DispatchQueue,
        group: DispatchGroup,
        onSample: ((CMTime) -> Void)?
    ) {
        var finished = false

        input.requestMediaDataWhenReady(on: queue) { [weak self] in
            guard !finished else { return }

            while input.isReadyForMoreMediaData {
                if self?.cancelled == true {
                    finished = true
                    input.markAsFinished()
                    group.leave()
                    return
                }

                guard let sampleBuffer = output.copyNextSampleBuffer() else {
                    // Either the track is drained or the reader failed; the caller checks which.
                    finished = true
                    input.markAsFinished()
                    group.leave()
                    return
                }

                let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                let appended = input.append(sampleBuffer)

                if !appended {
                    finished = true
                    input.markAsFinished()
                    group.leave()
                    return
                }

                onSample?(presentationTime)
            }
        }
    }

    /// Rotates the source upright and scales it to `targetSize`.
    private func makeVideoComposition(
        asset: AVAsset,
        videoTrack: AVAssetTrack,
        targetSize: CGSize,
        fps: Int
    ) -> AVMutableVideoComposition {
        let displaySize = videoTrack.naturalSize.applying(videoTrack.preferredTransform)
        let mediaSize = CGSize(width: abs(displaySize.width), height: abs(displaySize.height))

        // preferredTransform already places the rotated frame in positive coordinates, so scaling
        // it afterwards is all that is needed to land on the requested render size.
        let scaleX = mediaSize.width > 0 ? targetSize.width / mediaSize.width : 1
        let scaleY = mediaSize.height > 0 ? targetSize.height / mediaSize.height : 1
        let transform = videoTrack.preferredTransform.concatenating(CGAffineTransform(scaleX: scaleX, y: scaleY))

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        layerInstruction.setTransform(transform, at: .zero)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: asset.duration)
        instruction.layerInstructions = [layerInstruction]

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = targetSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(max(1, fps)))
        videoComposition.instructions = [instruction]

        return videoComposition
    }
}
