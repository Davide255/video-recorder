package com.capacitorcommunity.videorecorder.editor.dto;

import androidx.annotation.NonNull;

public class VideoSize {

    public final int width;
    public final int height;

    public VideoSize(int width, int height) {
        this.width = width;
        this.height = height;
    }

    @NonNull
    @Override
    public String toString() {
        return "VideoSize{" + "width=" + width + ", height=" + height + '}';
    }
}
