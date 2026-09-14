package com.capacitorcommunity.videorecorder.editor;

import android.content.Context;
import android.graphics.Bitmap;
import android.media.MediaCodecInfo;
import android.media.MediaFormat;
import android.media.MediaMetadataRetriever;
import android.net.Uri;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import com.capacitorcommunity.videorecorder.editor.dto.SourceMedia;
import com.capacitorcommunity.videorecorder.editor.dto.VideoSize;
import com.capacitorcommunity.videorecorder.editor.dto.VideoTrackFormat;
import com.getcapacitor.Logger;
import com.linkedin.android.litr.MediaTransformer;
import com.linkedin.android.litr.TransformationListener;
import com.linkedin.android.litr.TransformationOptions;
import com.linkedin.android.litr.analytics.TrackTransformationInfo;
import com.linkedin.android.litr.io.MediaRange;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.OutputStream;
import java.util.List;
import java.util.UUID;

/**
 * Video trimming / transcoding backed by LiTr (MediaCodec based, hardware accelerated).
 */
public class VideoEditorLitr {

    static final int DEFAULT_VIDEO_KEY_FRAME_INTERVAL = 5;
    static final int DEFAULT_AUDIO_BITRATE = 128000;
    static final int DEFAULT_AUDIO_CHANNEL_COUNT = 2;
    static final int DEFAULT_AUDIO_SAMPLE_RATE = 44100;
    static final String DEFAULT_AUDIO_MIME = "audio/mp4a-latm";
    static final String DEFAULT_VIDEO_MIME = "video/avc";
    static final int THUMBNAIL_QUALITY = 80;

    private final Object lock = new Object();

    @Nullable
    private MediaTransformer mediaTransformer;

    @Nullable
    private String requestId;

    private boolean cancelled = false;

    /**
     * Estimates a sane AVC bitrate for the given output size.
     *
     * @see <a href="https://stackoverflow.com/a/5220554/4288782">the rule of thumb this uses</a>
     */
    public static long estimateVideoBitRate(int width, int height, int frameRate) {
        return (long) (0.07F * 2 * width * height * frameRate);
    }

    public void edit(
        Context context,
        Uri sourceVideoUri,
        File outFile,
        TrimSettings trimSettings,
        TranscodeSettings transcodeSettings,
        TransformationListener videoTransformationListener
    ) throws IOException {
        SourceMedia sourceMedia = new SourceMedia(context, sourceVideoUri);
        VideoTrackFormat sourceVideoTrack = sourceMedia.getVideoTrack();

        // Resolution
        VideoSize targetVideoSize = calculateTargetVideoSize(sourceVideoTrack, transcodeSettings);
        Logger.debug("Source video size: " + new VideoSize(sourceVideoTrack.width, sourceVideoTrack.height));
        Logger.debug("Target video size: " + targetVideoSize);

        int targetVideoBitrate = calculateTargetVideoBitrate(sourceVideoTrack, targetVideoSize, transcodeSettings);
        int targetAudioBitrate = sourceMedia.getAudioBitrate() > 0
            ? Math.min(DEFAULT_AUDIO_BITRATE, sourceMedia.getAudioBitrate())
            : DEFAULT_AUDIO_BITRATE;

        // Trim
        long startsAtUs = trimSettings.getStartsAt() * 1000;
        long endsAtUs = trimSettings.getEndsAt() == 0 ? Long.MAX_VALUE : trimSettings.getEndsAt() * 1000;

        TransformationOptions transformationOptions = new TransformationOptions.Builder()
            .setGranularity(MediaTransformer.GRANULARITY_DEFAULT)
            .setSourceMediaRange(new MediaRange(startsAtUs, endsAtUs))
            .setRemoveMetadata(true)
            .build();

        // Video codec config
        MediaFormat targetVideoFormat = new MediaFormat();
        targetVideoFormat.setString(MediaFormat.KEY_MIME, DEFAULT_VIDEO_MIME);
        targetVideoFormat.setInteger(MediaFormat.KEY_WIDTH, targetVideoSize.width);
        targetVideoFormat.setInteger(MediaFormat.KEY_HEIGHT, targetVideoSize.height);
        targetVideoFormat.setInteger(MediaFormat.KEY_FRAME_RATE, transcodeSettings.getFps());
        targetVideoFormat.setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, DEFAULT_VIDEO_KEY_FRAME_INTERVAL);
        targetVideoFormat.setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface);
        targetVideoFormat.setInteger(MediaFormat.KEY_BIT_RATE, targetVideoBitrate);

        // Audio codec config
        MediaFormat targetAudioFormat = new MediaFormat();
        targetAudioFormat.setString(MediaFormat.KEY_MIME, DEFAULT_AUDIO_MIME);
        targetAudioFormat.setInteger(MediaFormat.KEY_CHANNEL_COUNT, DEFAULT_AUDIO_CHANNEL_COUNT);
        targetAudioFormat.setInteger(MediaFormat.KEY_SAMPLE_RATE, DEFAULT_AUDIO_SAMPLE_RATE);
        targetAudioFormat.setInteger(MediaFormat.KEY_BIT_RATE, targetAudioBitrate);

        MediaTransformer mediaTransformer = new MediaTransformer(context);
        String requestId = UUID.randomUUID().toString();

        TransformationListener listener = new TransformationListener() {
            @Override
            public void onStarted(@NonNull String id) {
                videoTransformationListener.onStarted(id);
            }

            @Override
            public void onProgress(@NonNull String id, float progress) {
                videoTransformationListener.onProgress(id, progress);
            }

            @Override
            public void onCompleted(@NonNull String id, @Nullable List<TrackTransformationInfo> trackTransformationInfos) {
                try {
                    videoTransformationListener.onCompleted(id, trackTransformationInfos);
                } finally {
                    releaseTransformer();
                }
            }

            @Override
            public void onCancelled(@NonNull String id, @Nullable List<TrackTransformationInfo> trackTransformationInfos) {
                try {
                    videoTransformationListener.onCancelled(id, trackTransformationInfos);
                } finally {
                    releaseTransformer();
                }
            }

            @Override
            public void onError(
                @NonNull String id,
                @Nullable Throwable cause,
                @Nullable List<TrackTransformationInfo> trackTransformationInfos
            ) {
                try {
                    videoTransformationListener.onError(id, cause, trackTransformationInfos);
                } finally {
                    releaseTransformer();
                }
            }
        };

        // Held across transform() so that cancel() either runs before the request exists, and is
        // caught by the flag below, or after LiTr has registered it and can act on it. transform()
        // only queues the work, so nothing is blocked for long.
        synchronized (lock) {
            if (this.cancelled) {
                // cancel() landed while the source was still being read.
                mediaTransformer.release();
                videoTransformationListener.onCancelled(requestId, null);
                return;
            }

            this.mediaTransformer = mediaTransformer;
            this.requestId = requestId;

            try {
                mediaTransformer.transform(
                    requestId,
                    sourceVideoUri,
                    outFile.getPath(),
                    targetVideoFormat,
                    targetAudioFormat,
                    listener,
                    transformationOptions
                );
            } catch (RuntimeException ex) {
                this.mediaTransformer = null;
                this.requestId = null;
                mediaTransformer.release();
                throw ex;
            }
        }
    }

    /**
     * Stops the transformation in progress. The listener passed to {@link #edit} receives
     * {@code onCancelled}. Calling this before or after a transformation does nothing beyond
     * marking this instance as cancelled, so it is safe to call at any point.
     */
    public void cancel() {
        MediaTransformer transformer;
        String id;

        synchronized (lock) {
            this.cancelled = true;
            transformer = this.mediaTransformer;
            id = this.requestId;
        }

        if (transformer != null && id != null) {
            // LiTr reports this through onCancelled, which is where the transformer is released.
            transformer.cancel(id);
        }
    }

    private void releaseTransformer() {
        MediaTransformer transformer;

        synchronized (lock) {
            transformer = this.mediaTransformer;
            this.mediaTransformer = null;
            this.requestId = null;
        }

        if (transformer != null) {
            transformer.release();
        }
    }

    public void thumbnail(Context context, Uri srcUri, File outFile, int atMs, int width, int height) throws IOException {
        MediaMetadataRetriever retriever = new MediaMetadataRetriever();
        Bitmap bitmap = null;

        try {
            retriever.setDataSource(context, srcUri);

            bitmap = retriever.getFrameAtTime((long) atMs * 1000);

            if (bitmap == null) {
                throw new IOException("Could not extract a frame at " + atMs + "ms");
            }

            Bitmap scaledBitmap = scaleThumbnail(bitmap, width, height);

            try (OutputStream outStream = new FileOutputStream(outFile)) {
                if (!scaledBitmap.compress(Bitmap.CompressFormat.JPEG, THUMBNAIL_QUALITY, outStream)) {
                    throw new IOException("Could not encode the thumbnail as JPEG");
                }
            } finally {
                if (scaledBitmap != bitmap) {
                    scaledBitmap.recycle();
                }
            }
        } catch (RuntimeException ex) {
            throw new IOException("Could not read the source video: " + ex.getMessage(), ex);
        } finally {
            if (bitmap != null) {
                bitmap.recycle();
            }
            try {
                retriever.release();
            } catch (Exception ignored) {
                // Nothing useful to do here.
            }
        }
    }

    /**
     * Scales the frame to fit inside the requested box, preserving the aspect ratio. Either bound
     * may be 0, in which case only the other one constrains the result; when both are 0 the frame
     * is returned untouched.
     */
    private Bitmap scaleThumbnail(@NonNull Bitmap bitmap, int width, int height) {
        if (width <= 0 && height <= 0) {
            return bitmap;
        }

        int sourceWidth = bitmap.getWidth();
        int sourceHeight = bitmap.getHeight();

        if (sourceWidth <= 0 || sourceHeight <= 0) {
            return bitmap;
        }

        double aspectRatio = (double) sourceWidth / (double) sourceHeight;

        int scaleWidth;
        int scaleHeight;

        if (width > 0 && height > 0) {
            // Fit inside the box: whichever bound is reached first wins.
            if ((double) width / (double) height > aspectRatio) {
                scaleHeight = height;
                scaleWidth = (int) Math.round(height * aspectRatio);
            } else {
                scaleWidth = width;
                scaleHeight = (int) Math.round(width / aspectRatio);
            }
        } else if (width > 0) {
            scaleWidth = width;
            scaleHeight = (int) Math.round(width / aspectRatio);
        } else {
            scaleHeight = height;
            scaleWidth = (int) Math.round(height * aspectRatio);
        }

        scaleWidth = Math.max(1, scaleWidth);
        scaleHeight = Math.max(1, scaleHeight);

        if (scaleWidth == sourceWidth && scaleHeight == sourceHeight) {
            return bitmap;
        }

        return Bitmap.createScaledBitmap(bitmap, scaleWidth, scaleHeight, true);
    }

    /**
     * Honours an explicit bitrate when the caller provided one, otherwise estimates one from the
     * output size and caps it at the source bitrate so re-encoding never inflates the file.
     */
    private int calculateTargetVideoBitrate(
        @NonNull VideoTrackFormat sourceVideoTrack,
        @NonNull VideoSize targetVideoSize,
        @NonNull TranscodeSettings transcodeSettings
    ) {
        if (transcodeSettings.getVideoBitrate() > 0) {
            return transcodeSettings.getVideoBitrate();
        }

        int estimatedVideoBitrate = (int) estimateVideoBitRate(targetVideoSize.width, targetVideoSize.height, transcodeSettings.getFps());

        // A source bitrate of 0 means "unknown": capping against it would produce an invalid format.
        if (sourceVideoTrack.bitrate > 0) {
            return Math.min(estimatedVideoBitrate, sourceVideoTrack.bitrate);
        }

        return estimatedVideoBitrate;
    }

    private VideoSize calculateTargetVideoSize(VideoTrackFormat videoTrackFormat, TranscodeSettings transcodeSettings) {
        if (transcodeSettings.isKeepAspectRatio()) {
            int mostSize = transcodeSettings.getWidth() == 0 && transcodeSettings.getHeight() == 0
                ? 1280
                : Math.max(transcodeSettings.getWidth(), transcodeSettings.getHeight());

            return calculateVideoSizeAtMost(videoTrackFormat, mostSize);
        } else {
            if (transcodeSettings.getWidth() > 0 && transcodeSettings.getHeight() > 0) {
                return new VideoSize(transcodeSettings.getWidth(), transcodeSettings.getHeight());
            } else {
                return calculateVideoSizeAtMost(videoTrackFormat, 720);
            }
        }
    }

    private VideoSize calculateVideoSizeAtMost(VideoTrackFormat videoTrackFormat, int mostSize) {
        int sourceMajor = Math.max(videoTrackFormat.width, videoTrackFormat.height);

        if (sourceMajor <= mostSize) {
            // No resize needed
            return new VideoSize(videoTrackFormat.width, videoTrackFormat.height);
        }

        int outWidth;
        int outHeight;

        if (videoTrackFormat.width >= videoTrackFormat.height) {
            // Landscape
            float inputRatio = (float) videoTrackFormat.height / videoTrackFormat.width;

            outWidth = mostSize;
            outHeight = (int) ((float) mostSize * inputRatio);
        } else {
            // Portrait
            float inputRatio = (float) videoTrackFormat.width / videoTrackFormat.height;

            outHeight = mostSize;
            outWidth = (int) ((float) mostSize * inputRatio);
        }

        // Most hardware encoders reject odd dimensions.
        if (outWidth % 2 != 0) {
            outWidth--;
        }
        if (outHeight % 2 != 0) {
            outHeight--;
        }

        return new VideoSize(outWidth, outHeight);
    }
}
