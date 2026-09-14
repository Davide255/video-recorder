package com.capacitorcommunity.videorecorder.editor.dto;

import androidx.annotation.NonNull;

/**
 * Relevant properties of the video track of a source media file.
 */
public class VideoTrackFormat {

    public final int index;
    public final String mimeType;

    public int width;
    public int height;
    public int bitrate;
    public int frameRate;
    public int rotation;
    public long durationUs;

    public VideoTrackFormat(int index, @NonNull String mimeType) {
        this.index = index;
        this.mimeType = mimeType;
    }
}
