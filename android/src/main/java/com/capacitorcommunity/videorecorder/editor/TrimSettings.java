package com.capacitorcommunity.videorecorder.editor;

/**
 * Trim boundaries of an edit operation, expressed in milliseconds.
 */
public class TrimSettings {

    private long startsAt = 0;
    private long endsAt = 0;

    public TrimSettings() {}

    public TrimSettings(long startsAt, long endsAt) {
        setStartsAt(startsAt);
        setEndsAt(endsAt);
    }

    /**
     * Get startsAt in milliseconds
     *
     * @return startsAt in milliseconds
     */
    public long getStartsAt() {
        return startsAt;
    }

    public void setStartsAt(long startsAt) {
        if (startsAt < 0) {
            throw new IllegalArgumentException("Parameter startsAt cannot be negative");
        }

        this.startsAt = startsAt;
    }

    /**
     * Get endsAt in milliseconds. A value of 0 means "until the end of the source".
     *
     * @return endsAt in milliseconds
     */
    public long getEndsAt() {
        return endsAt;
    }

    public void setEndsAt(long endsAt) {
        if (endsAt < 0) {
            throw new IllegalArgumentException("Parameter endsAt cannot be negative");
        }

        this.endsAt = endsAt;
    }
}
