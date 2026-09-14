package com.capacitorcommunity.videorecorder;

import android.Manifest;
import android.content.ContentResolver;
import android.content.Context;
import android.graphics.Color;
import android.graphics.drawable.ColorDrawable;
import android.net.Uri;
import android.os.Build;
import android.text.TextUtils;
import android.util.DisplayMetrics;
import android.view.ViewGroup;
import android.view.ViewParent;
import android.webkit.MimeTypeMap;
import android.widget.FrameLayout;

import com.getcapacitor.JSArray;
import com.getcapacitor.FileUtils;
import com.getcapacitor.JSObject;
import com.getcapacitor.Logger;
import com.getcapacitor.PermissionState;
import com.getcapacitor.annotation.CapacitorPlugin;
import com.getcapacitor.annotation.Permission;
import com.getcapacitor.annotation.PermissionCallback;

import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;

import com.capacitorcommunity.videorecorder.editor.TranscodeSettings;
import com.capacitorcommunity.videorecorder.editor.TrimSettings;
import com.capacitorcommunity.videorecorder.editor.VideoEditorLitr;
import com.linkedin.android.litr.TransformationListener;
import com.linkedin.android.litr.analytics.TrackTransformationInfo;

import org.json.JSONException;
import org.json.JSONObject;

import java.io.File;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Timer;
import java.util.TimerTask;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.coordinatorlayout.widget.CoordinatorLayout;
import co.fitcom.fancycamera.CameraEventListenerUI;
import co.fitcom.fancycamera.EventType;
import co.fitcom.fancycamera.FancyCamera;
import co.fitcom.fancycamera.PhotoEvent;
import co.fitcom.fancycamera.VideoEvent;

@CapacitorPlugin(
        name = "VideoRecorder",
        requestCodes = {
            868
        },
        permissions = {
            @Permission(strings = { Manifest.permission.READ_EXTERNAL_STORAGE }, alias = VideoRecorderPlugin.STORAGE)
        }
)
public class VideoRecorderPlugin extends Plugin {

    /** Permission alias used when reading a source video the app does not own. */
    static final String STORAGE = "storage";

    private static final String PERMISSION_DENIED_ERROR_STORAGE = "User denied access to storage";

    /** Error code the editVideo() promise is rejected with after cancelEdit(). */
    private static final String EDIT_CANCELED_CODE = "CANCELED";

    /** Error code for an editVideo() call made while another one is still running. */
    private static final String EDIT_IN_PROGRESS_CODE = "EDIT_IN_PROGRESS";

    private final Object editLock = new Object();
    private boolean editInProgress = false;

    @Nullable
    private VideoEditorLitr activeEditor = null;
    private FancyCamera fancyCamera;
    private PluginCall call;
    private HashMap<String, FrameConfig> previewFrameConfigs;
    private FrameConfig currentFrameConfig;
    private FancyCamera.CameraPosition cameraPosition = FancyCamera.CameraPosition.FRONT;
    private int currentCameraPositionInt = 1; // Track camera position ourselves: 0 = back, 1 = front
    private Timer audioFeedbackTimer;
    private boolean timerStarted;
    private Integer videoBitrate = 3000000;
    private boolean _isFlashEnabled = false;
    private boolean isRecording = false;
    private Integer previousBackgroundColor = null;

    PluginCall getCall() {
        return call;
    }

    @Override
    protected void handleRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
        super.handleRequestPermissionsResult(requestCode, permissions, grantResults);

        if (fancyCamera.hasPermission()) {
            if (getCall() != null) {
                getCall().resolve();
            } else if (savedLastCall != null) {
                savedLastCall.resolve();
            }
            startCamera();
        } else {
            if (getCall() != null) {
                getCall().reject("");
            } else if (savedLastCall != null) {
                savedLastCall.reject("");
            }
        }
    }

    private void startCamera() {
        if (fancyCamera == null || fancyCamera.cameraStarted()) return;
        fancyCamera.start();
    }

    private void startTimer() {
        if (timerStarted) {
            return;
        }

        if (audioFeedbackTimer != null) {
            audioFeedbackTimer.cancel();
            audioFeedbackTimer = null;
        }

        audioFeedbackTimer = new Timer();
        audioFeedbackTimer.scheduleAtFixedRate(new TimerTask() {
            @Override
            public void run() {
                timerStarted = true;
                getActivity().runOnUiThread(new Runnable() {
                    @Override
                    public void run() {
                        JSObject object = new JSObject();
                        double db = fancyCamera != null ? fancyCamera.getDB() : 0;
                        object.put("value", db);
                        //notifyListeners("onVolumeInput", object);
                    }
                });
            }
        }, 0, 100);
    }

    private void stopTimer() {
        if (audioFeedbackTimer != null) {
            audioFeedbackTimer.cancel();
            audioFeedbackTimer = null;
        }
        timerStarted = false;
    }

    @Override
    public void load() {
        super.load();
    }

    @PluginMethod()
    public void initialize(final PluginCall call) {
        JSObject defaultFrame = new JSObject();
        defaultFrame.put("id", "default");
        currentFrameConfig = new FrameConfig(defaultFrame);
        previewFrameConfigs = new HashMap<>();

        this.videoBitrate = call.getInt("videoBitrate", 3000000);

        // flash is turned off by default when initializing camera
        this._isFlashEnabled = false;

        fancyCamera = new FancyCamera(this.getContext());
        fancyCamera.setMaxVideoBitrate(this.videoBitrate);
        fancyCamera.setDisableHEVC(true);
        fancyCamera.setListener(new CameraEventListenerUI() {
            public void onCameraOpenUI() {
                if (getCall() != null) {
                    getCall().resolve();
                }
                startTimer();
                updateCameraView(currentFrameConfig);
                for (FrameConfig f : previewFrameConfigs.values()) {
                    updateCameraView(f);
                }
            }

            public void onCameraCloseUI() {
                if (getCall() != null) {
                    getCall().resolve();
                }
                stopTimer();
            }

            @Override
            public void onPhotoEventUI(PhotoEvent event) {

            }

            @Override
            public void onVideoEventUI(VideoEvent event) {
                if (event.getType() == EventType.INFO &&
                        event
                                .getMessage().contains(VideoEvent.EventInfo.RECORDING_FINISHED.toString())) {
                    if (getCall() != null) {
                        JSObject object = new JSObject();
                        String path = FileUtils.getPortablePath(getContext(), bridge.getLocalUrl(), Uri.fromFile(event.getFile()));
                        object.put("videoUrl", path);
                        getCall().resolve(object);
                    } else {
                        if (event.getType() == co.fitcom.fancycamera.EventType.ERROR) {
                            getCall().reject(event.getMessage());
                        }
                    }

                } else if (event.getType() == EventType.INFO &&
                        event
                                .getMessage().contains(VideoEvent.EventInfo.RECORDING_STARTED.toString())) {
                    if (getCall() != null) {
                        getCall().resolve();
                    }

                }
            }
        });
        final FrameLayout.LayoutParams cameraPreviewParams = new FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT);
        fancyCamera.setLayoutParams(cameraPreviewParams);
        getActivity().runOnUiThread(new Runnable() {
            @Override
            public void run() {
                ((CoordinatorLayout) bridge.getWebView().getParent()).addView(fancyCamera, cameraPreviewParams);
                bridge.getWebView().bringToFront();
                bridge.getWebView().getParent().requestLayout();
                ((CoordinatorLayout) bridge.getWebView().getParent()).invalidate();
            }
        });


        defaultFrame = new JSObject();
        defaultFrame.put("id", "default");
        JSArray defaultArray = new JSArray();
        defaultArray.put(defaultFrame);
        JSArray array = call.getArray("previewFrames", defaultArray);
        int size = array.length();
        for (int i = 0; i < size; i++) {
            try {
                JSONObject obj = (JSONObject) array.get(i);
                FrameConfig config = new FrameConfig(JSObject.fromJSONObject(obj));
                previewFrameConfigs.put(config.id, config);

                // Set the first preview frame as the current frame config
                if (i == 0) {
                    currentFrameConfig = config;
                }
            } catch (JSONException ignored) {

            }
        }

        fancyCamera.setCameraPosition(1);
        currentCameraPositionInt = 1; // Set our tracked position to front camera
        if (fancyCamera.hasPermission()) {
            // Swapping these around since it is the other way for iOS and the plugin interface needs to stay consistent
            if (call.getInt("camera") == 1) {
                fancyCamera.setCameraPosition(0);
                currentCameraPositionInt = 0; // Back camera
            } else if (call.getInt("camera") == 0) {
                fancyCamera.setCameraPosition(1);
                currentCameraPositionInt = 1; // Front camera
            } else {
                fancyCamera.setCameraPosition(1);
                currentCameraPositionInt = 1; // Front camera
            }
        }

        if (!fancyCamera.cameraStarted()) {
            startCamera();
        }

        this.call = call;
    }

    @PluginMethod()
    public void destroy(PluginCall call) {
        makeOpaque();

        getActivity().runOnUiThread(() -> {
            ViewParent parent = fancyCamera.getParent();
            if (parent instanceof ViewGroup) {
                ViewGroup parentGroup = (ViewGroup) parent;
                if (previousBackgroundColor != null) {
                    parentGroup.setBackgroundColor(previousBackgroundColor);
                    previousBackgroundColor = null;
                }
                ((ViewGroup) parent).removeView(fancyCamera);
            }
        });

        fancyCamera.release();
        call.resolve();
    }

    private void makeOpaque() {
        this.bridge.getWebView().setBackgroundColor(Color.WHITE);
    }

    @PluginMethod()
    public void showPreviewFrame(PluginCall call) {
        int position = call.getInt("position");
        int quality = call.getInt("quality");
        fancyCamera.setCameraPosition(position);
        currentCameraPositionInt = position; // Update our tracked position
        fancyCamera.setQuality(quality);
        bridge.getWebView().setBackgroundColor(Color.argb(0, 0, 0, 0));
        if (fancyCamera != null && !fancyCamera.cameraStarted()) {
            startCamera();
            this.call = call;
        } else {
            // Update camera view to apply mirroring settings after camera position change
            getActivity().runOnUiThread(new Runnable() {
                @Override
                public void run() {
                    updateCameraView(currentFrameConfig);
                }
            });
            call.resolve();
        }
    }

    @PluginMethod()
    public void hidePreviewFrame(PluginCall call) {
        makeOpaque();
        fancyCamera.stop();
        this.call = call;
    }

    @PluginMethod()
    public void togglePip(PluginCall call) {

    }

    @PluginMethod()
    public void startRecording(PluginCall call) {
        fancyCamera.setAutoFocus(true);

        // turn on flash if flash is enabled and camera is back camera
        if (this._isFlashEnabled && fancyCamera.getCameraPosition() == 0) {
            fancyCamera.enableFlash();
        }

        isRecording = true;
        fancyCamera.startRecording();
        call.resolve();
    }

    @PluginMethod()
    public void stopRecording(PluginCall call) {
        this.call = call;
        isRecording = false;

        // turn off flash if flash is enabled and camera is back camera
        if (this._isFlashEnabled && fancyCamera.getCameraPosition() == 0) {
            fancyCamera.disableFlash();
        }

        fancyCamera.stopRecording();
    }

    @PluginMethod()
    public void flipCamera(PluginCall call) {
        if (isRecording) {
            call.reject("Cannot switch camera while recording");
            return;
        }
        fancyCamera.toggleCamera();

        // Update our tracked camera position
        currentCameraPositionInt = (currentCameraPositionInt == 0) ? 1 : 0;
        android.util.Log.d("VideoRecorder", "Camera flipped to position: " + currentCameraPositionInt);

        // Update camera view to apply correct mirroring for the new camera position
        // Add a small delay to ensure the camera position has been updated
        getActivity().runOnUiThread(new Runnable() {
            @Override
            public void run() {
                new android.os.Handler().postDelayed(new Runnable() {
                    @Override
                    public void run() {
                        updateCameraView(currentFrameConfig);
                    }
                }, 100); // 100ms delay
            }
        });

        call.resolve();
    }

    @PluginMethod()
    public void enableFlash(PluginCall call) {
        this._isFlashEnabled = true;
        call.resolve();
    }

    @PluginMethod()
    public void disableFlash(PluginCall call) {
        this._isFlashEnabled = false;
        call.resolve();
    }

    @PluginMethod()
    public void toggleFlash(PluginCall call) {
        this._isFlashEnabled = !this._isFlashEnabled;
        call.resolve();
    }

    @PluginMethod()
    public void isFlashEnabled(PluginCall call) {
        JSObject object = new JSObject();
        object.put("isEnabled", this._isFlashEnabled);
        call.resolve(object);
    }

    @PluginMethod()
    public void isFlashAvailable(PluginCall call) {
        JSObject object = new JSObject();
        object.put("isAvailable", fancyCamera.hasFlash());
        call.resolve(object);
    }

    @PluginMethod()
    public void getDuration(PluginCall call) {
        JSObject object = new JSObject();
        object.put("value", fancyCamera.getDuration());
        call.resolve(object);
    }

    @PluginMethod()
    public void editVideo(PluginCall call) {
        String path = call.getString("path");
        JSObject trim = call.getObject("trim", new JSObject());
        JSObject transcode = call.getObject("transcode", new JSObject());

        if (TextUtils.isEmpty(path)) {
            call.reject("Input file path is required");
            return;
        }

        Uri inputUri = resolveSourceUri(path);

        // Checked before the slot below is reserved: this method runs again after the permission
        // request resolves, and must not then collide with its own reservation.
        if (!ensureSourceIsReadable(call, inputUri)) {
            return;
        }

        // Transcoding is heavy enough that running two at once helps nobody, and a single
        // in-flight edit is what makes cancelEdit() unambiguous.
        synchronized (editLock) {
            if (editInProgress) {
                call.reject("An edit is already in progress", EDIT_IN_PROGRESS_CODE);
                return;
            }

            editInProgress = true;
            activeEditor = new VideoEditorLitr();
        }

        String fileName = "VID_" + timeStamp() + "_";
        File storageDir = getContext().getCacheDir();

        execute(() -> {
            File outputFile = null;

            try {
                outputFile = File.createTempFile(fileName, ".mp4", storageDir);
                final File resultFile = outputFile;

                TrimSettings trimSettings = new TrimSettings(trim.getInteger("startsAt", 0), trim.getInteger("endsAt", 0));

                TranscodeSettings transcodeSettings = new TranscodeSettings(
                    transcode.getInteger("height", 0),
                    transcode.getInteger("width", 0),
                    transcode.getBoolean("keepAspectRatio", true),
                    transcode.getInteger("fps", 30),
                    transcode.getInteger("videoBitrate", 0)
                );

                TransformationListener videoTransformationListener = new TransformationListener() {
                    @Override
                    public void onStarted(@NonNull String id) {
                        Logger.debug("Transcode started");
                    }

                    @Override
                    public void onProgress(@NonNull String id, float progress) {
                        JSObject ret = new JSObject();
                        ret.put("progress", progress);

                        notifyListeners("transcodeProgress", ret);
                    }

                    @Override
                    public void onCompleted(@NonNull String id, @Nullable List<TrackTransformationInfo> infos) {
                        Logger.debug("Transcode completed");

                        finishEdit();

                        JSObject ret = new JSObject();
                        ret.put("file", createMediaFile(resultFile));
                        call.resolve(ret);
                    }

                    @Override
                    public void onCancelled(@NonNull String id, @Nullable List<TrackTransformationInfo> infos) {
                        Logger.debug("Transcode cancelled");

                        finishEdit();
                        deleteQuietly(resultFile);
                        call.reject("Transcode canceled", EDIT_CANCELED_CODE);
                    }

                    @Override
                    public void onError(@NonNull String id, @Nullable Throwable cause, @Nullable List<TrackTransformationInfo> infos) {
                        String message = describe(cause);
                        Logger.error("Transcode error: " + message, cause);

                        finishEdit();
                        deleteQuietly(resultFile);

                        // PluginCall only carries an Exception, and LiTr reports a Throwable.
                        if (cause instanceof Exception) {
                            call.reject("Transcode failed: " + message, (Exception) cause);
                        } else {
                            call.reject("Transcode failed: " + message);
                        }
                    }
                };

                VideoEditorLitr editor;

                synchronized (editLock) {
                    editor = activeEditor;
                }

                if (editor == null) {
                    // cancelEdit() ran before the file was even created, so no listener will fire
                    // and the slot has to be released here.
                    finishEdit();
                    deleteQuietly(resultFile);
                    call.reject("Transcode canceled", EDIT_CANCELED_CODE);
                    return;
                }

                editor.edit(getContext(), inputUri, resultFile, trimSettings, transcodeSettings, videoTransformationListener);
            } catch (Exception e) {
                finishEdit();
                deleteQuietly(outputFile);
                call.reject(describe(e), e);
            }
        });
    }

    @PluginMethod()
    public void cancelEdit(PluginCall call) {
        VideoEditorLitr editor;

        synchronized (editLock) {
            editor = activeEditor;
            activeEditor = null;
        }

        if (editor != null) {
            // The pending editVideo() call is rejected from the listener's onCancelled.
            editor.cancel();
        }

        call.resolve();
    }

    /**
     * Releases the single edit slot. Safe to call more than once for the same edit.
     */
    private void finishEdit() {
        synchronized (editLock) {
            editInProgress = false;
            activeEditor = null;
        }
    }

    @PluginMethod()
    public void generateThumbnail(PluginCall call) {
        String path = call.getString("path");
        int atMs = call.getInt("at", 0);
        int width = call.getInt("width", 0);
        int height = call.getInt("height", 0);

        if (TextUtils.isEmpty(path)) {
            call.reject("Input file path is required");
            return;
        }

        Uri inputUri = resolveSourceUri(path);

        if (!ensureSourceIsReadable(call, inputUri)) {
            return;
        }

        String fileName = "TH_" + timeStamp() + "_";
        File storageDir = getContext().getCacheDir();

        execute(() -> {
            File outputFile = null;

            try {
                outputFile = File.createTempFile(fileName, ".jpg", storageDir);

                new VideoEditorLitr().thumbnail(getContext(), inputUri, outputFile, atMs, width, height);

                JSObject ret = new JSObject();
                ret.put("file", createMediaFile(outputFile));
                call.resolve(ret);
            } catch (Exception e) {
                deleteQuietly(outputFile);
                call.reject(describe(e), e);
            }
        });
    }

    private static String describe(@Nullable Throwable throwable) {
        if (throwable == null) {
            return "unknown error";
        }

        String message = throwable.getMessage();

        return message != null && !message.isEmpty() ? message : throwable.getClass().getSimpleName();
    }

    private static String timeStamp() {
        return new SimpleDateFormat("yyyyMMdd_HHmmss", Locale.ENGLISH).format(new Date());
    }

    /**
     * Accepts a {@code file://} url, a {@code content://} uri or a bare filesystem path.
     */
    private static Uri resolveSourceUri(@NonNull String path) {
        Uri uri = Uri.parse(path);

        if (uri.getScheme() == null) {
            return Uri.fromFile(new File(path));
        }

        return uri;
    }

    private static void deleteQuietly(@Nullable File file) {
        if (file != null && file.exists() && !file.delete()) {
            Logger.debug("Could not delete " + file.getAbsolutePath());
        }
    }

    /**
     * Checks that the source can be read, requesting the legacy storage permission only when the
     * file really is out of reach. Files the app owns (its own recordings included) never trigger a
     * permission prompt, and {@code content://} uris are covered by the grant that produced them.
     *
     * @return true when the caller can proceed, false when the call was rejected or is waiting on a
     *         permission request
     */
    private boolean ensureSourceIsReadable(PluginCall call, Uri uri) {
        if (!ContentResolver.SCHEME_FILE.equals(uri.getScheme())) {
            return true;
        }

        String filePath = uri.getPath();
        File file = filePath != null ? new File(filePath) : null;

        if (file != null && file.canRead()) {
            return true;
        }

        // READ_EXTERNAL_STORAGE no longer grants anything from Android 13 on.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU && getPermissionState(STORAGE) != PermissionState.GRANTED) {
            requestPermissionForAlias(STORAGE, call, "storagePermissionsCallback");
            return false;
        }

        call.reject("Cannot read input file: " + (file != null ? file.getAbsolutePath() : uri.toString()));
        return false;
    }

    @PermissionCallback
    private void storagePermissionsCallback(PluginCall call) {
        if (getPermissionState(STORAGE) != PermissionState.GRANTED) {
            Logger.debug(getLogTag(), "User denied storage permission: " + getPermissionState(STORAGE).toString());
            call.reject(PERMISSION_DENIED_ERROR_STORAGE);
            return;
        }

        switch (call.getMethodName()) {
            case "editVideo":
                editVideo(call);
                break;
            case "generateThumbnail":
                generateThumbnail(call);
                break;
            default:
                call.reject(PERMISSION_DENIED_ERROR_STORAGE);
                break;
        }
    }

    /**
     * Builds the JS representation of a file produced by the editor.
     */
    private JSObject createMediaFile(File file) {
        Context context = getContext();
        Uri uri = Uri.fromFile(file);
        String mimeType;

        if (ContentResolver.SCHEME_CONTENT.equals(uri.getScheme())) {
            mimeType = context.getContentResolver().getType(uri);
        } else {
            mimeType = MimeTypeMap.getSingleton().getMimeTypeFromExtension(MimeTypeMap.getFileExtensionFromUrl(uri.toString()));
        }

        JSObject ret = new JSObject();

        ret.put("name", file.getName());
        ret.put("path", uri.toString());
        ret.put("type", mimeType);
        ret.put("size", file.length());

        return ret;
    }

    @PluginMethod()
    public void setPosition(PluginCall call) {
        int position = call.getInt("position");
        fancyCamera.setCameraPosition(position);
        currentCameraPositionInt = position; // Update our tracked position
    }

    @PluginMethod()
    public void setQuality(PluginCall call) {
        int quality = call.getInt("quality");
        fancyCamera.setQuality(quality);
    }

    @PluginMethod()
    public void addPreviewFrameConfig(PluginCall call) {
        if (fancyCamera != null && fancyCamera.cameraStarted()) {
            String layerId = call.getString("id");
            if (layerId.isEmpty()) {
                call.reject("Must provide layer id");
                return;
            }

            FrameConfig config = new FrameConfig(call.getData());

            if (previewFrameConfigs.containsKey(layerId)) {
                editPreviewFrameConfig(call);
                return;
            } else {
                previewFrameConfigs.put(layerId, config);
            }
            call.resolve();
        }
    }

    @PluginMethod()
    public void editPreviewFrameConfig(PluginCall call) {
        if (fancyCamera != null && fancyCamera.cameraStarted()) {
            String layerId = call.getString("id");
            if (layerId.isEmpty()) {
                call.reject("Must provide layer id");
                return;
            }

            FrameConfig updatedConfig = new FrameConfig(call.getData());
            previewFrameConfigs.put(layerId, updatedConfig);

            if (currentFrameConfig.id.equals(layerId)) {
                currentFrameConfig = updatedConfig;
                updateCameraView(currentFrameConfig);
            }

            call.resolve();
        }
    }


    @PluginMethod()
    public void switchToPreviewFrame(PluginCall call) {
        if (fancyCamera != null && fancyCamera.cameraStarted()) {
            String layerId = call.getString("id");
            if (layerId.isEmpty()) {
                call.reject("Must provide layer id");
                return;
            }
            FrameConfig existingConfig = previewFrameConfigs.get(layerId);
            if (existingConfig != null) {
                if (!existingConfig.id.equals(currentFrameConfig.id)) {
                    currentFrameConfig = existingConfig;
                    updateCameraView(currentFrameConfig);
                }

            } else {
                call.reject("Frame config does not exist");
                return;
            }
            call.resolve();
        }
    }

    private int getPixels(int value) {
        return (int) (value * getContext().getResources().getDisplayMetrics().density + 0.5f);
    }

    private void updateCameraView(final FrameConfig frameConfig) {

        DisplayMetrics displayMetrics = new DisplayMetrics();
        getActivity().getWindowManager().getDefaultDisplay().getMetrics(displayMetrics);
        int deviceHeight = displayMetrics.heightPixels;
        int deviceWidth = displayMetrics.widthPixels;
        boolean isLandscape = deviceWidth > deviceHeight;

        if (fancyCamera.getLayoutParams() == null) {
            fancyCamera.setLayoutParams(new ViewGroup.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        }

        // Calculate the aspect ratio dimensions
        int width, height;
        if (isLandscape) {
            width = deviceWidth;
            height = (int) (deviceWidth * 9.0 / 16.0);
        } else {
            width = deviceWidth;
            height = (int) (deviceWidth * 4.0 / 3.0);
        }

        // If the calculated height is greater than the device height, adjust the width and height
        if (height > deviceHeight) {
            height = deviceHeight;
            width = isLandscape ? (int) (deviceHeight * 16.0 / 9.0) : (int) (deviceHeight * 3.0 / 4.0);
        }

        ViewGroup.LayoutParams oldParams = fancyCamera.getLayoutParams();

        if (frameConfig.width != -1) {
            width = getPixels(frameConfig.width);
        }

        if (frameConfig.height != -1) {
            height = getPixels(frameConfig.height);
        }

        oldParams.width = width;
        oldParams.height = height;
        fancyCamera.setLayoutParams(oldParams);

        // Center the preview frame vertically if y is 0 and height and width are -1
        if (frameConfig.y == 0 && frameConfig.height == -1 && frameConfig.width == -1) {
            fancyCamera.setY((deviceHeight - height) / 2);
        } else {
            fancyCamera.setY(getPixels((int) frameConfig.y));
        }

        // Center the preview frame horizontally if x is 0 and height and width are -1
        if (isLandscape && frameConfig.x == 0 && frameConfig.height == -1 && frameConfig.width == -1) {
            fancyCamera.setX((float) (deviceWidth - width) / 2);
        } else {
            fancyCamera.setX(getPixels((int) frameConfig.x));
        }

        // Set the background color to black
        ViewParent parent = fancyCamera.getParent();
        if (parent instanceof ViewGroup) {
            ViewGroup parentGroup = (ViewGroup) parent;
            if (parentGroup.getBackground() instanceof ColorDrawable colorDrawable) {
                previousBackgroundColor = colorDrawable.getColor();
            }
            parentGroup.setBackgroundColor(Color.BLACK);
        }

        fancyCamera.setElevation(9);
        bridge.getWebView().setElevation(9);
        bridge.getWebView().setBackgroundColor(Color.argb(0, 0, 0, 0));
        if (frameConfig.stackPosition.equals("front")) {
            getActivity().runOnUiThread(new Runnable() {
                @Override
                public void run() {
                    fancyCamera.bringToFront();
                    bridge.getWebView().getParent().requestLayout();
                    ((CoordinatorLayout) bridge.getWebView().getParent()).invalidate();
                }
            });

        } else if (frameConfig.stackPosition.equals("back")) {
            getActivity().runOnUiThread(new Runnable() {
                @Override
                public void run() {
                    if (frameConfig.stackPosition.equals("back")) {
                        getBridge().getWebView().bringToFront();
                    }
                    bridge.getWebView().getParent().requestLayout();
                    ((CoordinatorLayout) bridge.getWebView().getParent()).invalidate();
                }
            });
        }

        // Apply mirroring if needed (front camera and mirrorFrontCam true)
        getActivity().runOnUiThread(new Runnable() {
            @Override
            public void run() {
                // Add a small delay to ensure camera position is stable
                new android.os.Handler().postDelayed(new Runnable() {
                    @Override
                    public void run() {
                        // Use our tracked camera position instead of fancyCamera.getCameraPosition()
                        int trackedCameraPosition = currentCameraPositionInt;
                        int fancyCameraPosition = fancyCamera.getCameraPosition();

                        android.util.Log.d("VideoRecorder", "Applying mirroring - Tracked: " + trackedCameraPosition + ", FancyCamera: " + fancyCameraPosition + ", Mirror: " + frameConfig.mirrorFrontCam);

                        // Apply mirroring logic using our tracked position:
                        // - If front camera (1) AND mirrorFrontCam is true: apply mirroring (-1f)
                        // - If front camera (1) AND mirrorFrontCam is false: no mirroring (1f)
                        // - If back camera (0): no mirroring regardless of mirrorFrontCam (1f)
                        if (trackedCameraPosition == 1) { // Front camera
                            if (frameConfig.mirrorFrontCam) {
                                android.util.Log.d("VideoRecorder", "Front camera: Applying mirror effect");
                                fancyCamera.setScaleX(1f);
                            } else {
                                android.util.Log.d("VideoRecorder", "Front camera: No mirror (mirrorFrontCam=false)");
                                fancyCamera.setScaleX(-1f);
                            }
                        } else { // Back camera
                            android.util.Log.d("VideoRecorder", "Back camera: No mirror effect");
                            fancyCamera.setScaleX(1f);
                        }

                        // Force a layout update to ensure the changes are applied
                        fancyCamera.requestLayout();
                        fancyCamera.invalidate();
                    }
                }, 50); // 50ms delay to ensure camera position is stable
            }
        });
    }


    class FrameConfig {
        String id;
        String stackPosition;
        float x;
        float y;
        int width;
        int height;
        float borderRadius;
        DropShadow dropShadow;
        boolean mirrorFrontCam;

        FrameConfig(JSObject object) {
            id = object.getString("id");
            stackPosition = object.getString("stackPosition", "back");
            x = object.getInteger("x", 0).floatValue();
            y = object.getInteger("y", 0).floatValue();
            width = object.getInteger("width", -1);
            height = object.getInteger("height", -1);
            borderRadius = object.getInteger("borderRadius", 0);
            JSObject ds = object.getJSObject("dropShadow");
            dropShadow = new DropShadow(ds != null ? ds : new JSObject());
            if (object.has("mirrorFrontCam")) {
                mirrorFrontCam = object.getBool("mirrorFrontCam");
            } else {
                mirrorFrontCam = true;
            }
        }

        class DropShadow {
            float opacity;
            float radius;
            Color color;

            DropShadow(JSObject object) {
                opacity = object.getInteger("opacity", 0).floatValue();
                radius = object.getInteger("radius", 0).floatValue();
            }
        }
    }
}