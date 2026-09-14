package com.capacitorcommunity.videorecorder.editor;

/**
 * Output video settings of an edit operation.
 */
public class TranscodeSettings {

    private int height = 0;
    private int width = 0;
    private boolean keepAspectRatio = true;
    private int fps = 30;

    public TranscodeSettings() {}

    public TranscodeSettings(int height, int width, boolean keepAspectRatio, int fps) {
        setHeight(height);
        setWidth(width);
        setKeepAspectRatio(keepAspectRatio);
        setFps(fps);
    }

    public int getHeight() {
        return height;
    }

    public void setHeight(int height) {
        if (height < 0) {
            throw new IllegalArgumentException("Parameter height cannot be negative");
        }

        this.height = height;
    }

    public int getWidth() {
        return width;
    }

    public void setWidth(int width) {
        if (width < 0) {
            throw new IllegalArgumentException("Parameter width cannot be negative");
        }

        this.width = width;
    }

    public boolean isKeepAspectRatio() {
        return keepAspectRatio;
    }

    public void setKeepAspectRatio(boolean keepAspectRatio) {
        this.keepAspectRatio = keepAspectRatio;
    }

    public int getFps() {
        return fps;
    }

    public void setFps(int fps) {
        if (fps < 1) {
            throw new IllegalArgumentException("Parameter fps cannot be lower than 1");
        }

        this.fps = fps;
    }
}
