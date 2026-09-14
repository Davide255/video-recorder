package com.capacitorcommunity.videorecorder.editor.dto;

import static com.capacitorcommunity.videorecorder.editor.MediaFormatUtils.getInt;
import static com.capacitorcommunity.videorecorder.editor.MediaFormatUtils.getLong;

import android.content.Context;
import android.media.MediaExtractor;
import android.media.MediaFormat;
import android.media.MediaMetadataRetriever;
import android.net.Uri;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import java.io.IOException;

/**
 * Reads the track information the editor needs out of a source media file.
 *
 * <p>Unlike the upstream plugin this does not depend on LiTr internal utility classes, so it
 * keeps working across LiTr upgrades.
 */
public class SourceMedia {

    public final Uri uri;

    @Nullable
    private VideoTrackFormat videoTrack;

    private int audioBitrate = 0;
    private long durationUs = 0;

    public SourceMedia(Context context, @NonNull Uri uri) throws IOException {
        this.uri = uri;
        this.load(context, uri);
    }

    private void load(Context context, @NonNull Uri uri) throws IOException {
        MediaExtractor mediaExtractor = new MediaExtractor();

        try {
            mediaExtractor.setDataSource(context, uri, null);

            for (int track = 0; track < mediaExtractor.getTrackCount(); track++) {
                MediaFormat mediaFormat = mediaExtractor.getTrackFormat(track);
                String mimeType = mediaFormat.getString(MediaFormat.KEY_MIME);

                if (mimeType == null) {
                    continue;
                }

                if (mimeType.startsWith("video/") && this.videoTrack == null) {
                    VideoTrackFormat videoTrackFormat = new VideoTrackFormat(track, mimeType);
                    videoTrackFormat.width = getInt(mediaFormat, MediaFormat.KEY_WIDTH, 0);
                    videoTrackFormat.height = getInt(mediaFormat, MediaFormat.KEY_HEIGHT, 0);
                    videoTrackFormat.bitrate = getInt(mediaFormat, MediaFormat.KEY_BIT_RATE, 0);
                    videoTrackFormat.frameRate = getInt(mediaFormat, MediaFormat.KEY_FRAME_RATE, 0);
                    videoTrackFormat.rotation = getInt(mediaFormat, MediaFormat.KEY_ROTATION, 0);
                    videoTrackFormat.durationUs = getLong(mediaFormat, MediaFormat.KEY_DURATION);
                    this.videoTrack = videoTrackFormat;
                } else if (mimeType.startsWith("audio/") && this.audioBitrate == 0) {
                    this.audioBitrate = getInt(mediaFormat, MediaFormat.KEY_BIT_RATE, 0);
                }
            }
        } catch (IOException ex) {
            throw new IOException("Failed to read source media: " + ex.getMessage(), ex);
        } finally {
            mediaExtractor.release();
        }

        if (this.videoTrack == null) {
            throw new IOException("Video track not found");
        }

        // MediaExtractor frequently omits KEY_BIT_RATE and KEY_DURATION on the video track.
        // Fall back to the container level metadata so callers never see a bogus value.
        if (this.videoTrack.bitrate <= 0 || this.videoTrack.durationUs <= 0) {
            readContainerMetadata(context, uri);
        }
    }

    private void readContainerMetadata(Context context, @NonNull Uri uri) {
        MediaMetadataRetriever retriever = new MediaMetadataRetriever();

        try {
            retriever.setDataSource(context, uri);

            if (this.videoTrack != null && this.videoTrack.bitrate <= 0) {
                this.videoTrack.bitrate = parseInt(retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_BITRATE));
            }

            long durationMs = parseInt(retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION));
            if (durationMs > 0) {
                this.durationUs = durationMs * 1000;

                if (this.videoTrack != null && this.videoTrack.durationUs <= 0) {
                    this.videoTrack.durationUs = this.durationUs;
                }
            }
        } catch (RuntimeException ignored) {
            // Metadata is best effort, the defaults above are good enough to transcode.
        } finally {
            releaseQuietly(retriever);
        }
    }

    private static void releaseQuietly(MediaMetadataRetriever retriever) {
        try {
            retriever.release();
        } catch (Exception ignored) {
            // Nothing useful to do here.
        }
    }

    private static int parseInt(@Nullable String value) {
        if (value == null) {
            return 0;
        }

        try {
            return Integer.parseInt(value);
        } catch (NumberFormatException ex) {
            return 0;
        }
    }

    /**
     * @return the first video track of the source, never null
     */
    @NonNull
    public VideoTrackFormat getVideoTrack() {
        if (this.videoTrack == null) {
            throw new IllegalStateException("Video track not found");
        }

        return this.videoTrack;
    }

    /**
     * @return the bitrate of the first audio track in bits/sec, or 0 when unknown / no audio track
     */
    public int getAudioBitrate() {
        return this.audioBitrate;
    }

    /**
     * @return the source duration in microseconds, or 0 when unknown
     */
    public long getDurationUs() {
        return this.durationUs > 0 ? this.durationUs : (this.videoTrack != null ? this.videoTrack.durationUs : 0);
    }
}
