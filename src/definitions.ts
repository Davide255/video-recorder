import type { PluginListenerHandle } from '@capacitor/core';

export interface VideoRecorderPlugin {
  initialize(options?: VideoRecorderOptions): Promise<void>;
  destroy(): Promise<void>;
  flipCamera(): Promise<void>;
  toggleFlash(): Promise<void>;
  enableFlash(): Promise<void>;
  disableFlash(): Promise<void>;
  isFlashAvailable(): Promise<{ isAvailable: boolean }>;
  isFlashEnabled(): Promise<{ isEnabled: boolean }>;
  addPreviewFrameConfig(config: VideoRecorderPreviewFrame): Promise<void>;
  editPreviewFrameConfig(config: VideoRecorderPreviewFrame): Promise<void>;
  switchToPreviewFrame(options: { id: string }): Promise<void>;
  showPreviewFrame(config: { position: number; quality: number }): Promise<void>;
  hidePreviewFrame(): Promise<void>;
  startRecording(): Promise<void>;
  stopRecording(): Promise<{
    videoUrl: string;
  }>;
  getDuration(): Promise<{
    value: number;
  }>;
  /**
   * Enables the microphone audio track. Takes effect immediately if recording is in progress.
   * iOS only.
   */
  enableMicrophone(): Promise<void>;
  /**
   * Disables the microphone audio track. Takes effect immediately if recording is in progress.
   * iOS only.
   */
  disableMicrophone(): Promise<void>;
  /**
   * Returns all available physical cameras on the device.
   * iOS only.
   */
  getAvailableCameras(): Promise<{ cameras: VideoRecorderCameraInfo[] }>;
  /**
   * Switches to a specific camera by its id (from getAvailableCameras).
   * iOS only.
   */
  switchCamera(options: { cameraId: string }): Promise<void>;
  /**
   * Trims and/or transcodes a video file and returns the resulting file.
   * Progress is reported through the `transcodeProgress` event, and `cancelEdit()` stops it.
   *
   * Only one edit runs at a time: calling this while another edit is in progress rejects with
   * the error code `EDIT_IN_PROGRESS`.
   *
   * Not implemented on web.
   */
  editVideo(options: VideoEditOptions): Promise<MediaFileResult>;
  /**
   * Extracts a frame of a video file as a JPEG image.
   * Not implemented on web.
   */
  generateThumbnail(options: VideoThumbnailOptions): Promise<MediaFileResult>;
  /**
   * Cancels the `editVideo()` call in progress, if any. The pending `editVideo()` promise
   * rejects with the error code `CANCELED` and its partial output is deleted.
   *
   * Resolves either way: cancelling when nothing is running is not an error.
   */
  cancelEdit(): Promise<void>;
  addListener(
    eventName: 'onVolumeInput',
    listenerFunc: (event: { value: number }) => void,
  ): Promise<PluginListenerHandle>;
  /**
   * Fired while `editVideo()` is transcoding.
   */
  addListener(
    eventName: 'transcodeProgress',
    listenerFunc: (info: TranscodeProgressInfo) => void,
  ): Promise<PluginListenerHandle>;
}

export interface VideoRecorderCameraInfo {
  /** Unique device identifier to pass to switchCamera */
  id: string;
  position: 'front' | 'back';
  type: 'wide' | 'ultrawide' | 'telephoto';
}
export interface VideoRecorderPreviewFrame {
  id: string;
  stackPosition?: 'front' | 'back';
  x?: number;
  y?: number;
  width?: number | 'fill';
  height?: number | 'fill';
  borderRadius?: number;
  dropShadow?: {
    opacity?: number;
    radius?: number;
    color?: string;
  };
  /**
   * Whether to mirror the front camera preview horizontally. Only applies to front camera.
   * @default true
   */
  mirrorFrontCam?: boolean;
}

export interface VideoRecorderErrors {
  CAMERA_RESTRICTED: string;
  CAMERA_DENIED: string;
  MICROPHONE_RESTRICTED: string;
  MICROPHONE_DENIED: string;
}
export interface VideoRecorderOptions {
  camera?: VideoRecorderCamera;
  quality?: VideoRecorderQuality;
  autoShow?: boolean;
  previewFrames?: VideoRecorderPreviewFrame[];
  /**
   * The default bitrate is 4.5Mbps
   * @default 4500000
   * @type {number}
   * @memberof VideoRecorderOptions
   */
  videoBitrate?: number;
}

export enum VideoRecorderCamera {
  FRONT = 0,
  BACK = 1,
}

export enum VideoRecorderQuality {
  MAX_480P = 0,
  MAX_720P = 1,
  MAX_1080P = 2,
  MAX_2160P = 3,
  HIGHEST = 4,
  LOWEST = 5,
  QVGA = 6,
}

export interface VideoEditTrimOptions {
  /**
   * Start of the output video, in milliseconds from the start of the source.
   * @default 0
   */
  startsAt?: number;
  /**
   * End of the output video, in milliseconds from the start of the source.
   * `0` (the default) means "until the end of the source".
   * @default 0
   */
  endsAt?: number;
}

export interface VideoEditTranscodeOptions {
  /**
   * Target height in pixels. `0` lets the plugin pick it.
   * @default 0
   */
  height?: number;
  /**
   * Target width in pixels. `0` lets the plugin pick it.
   * @default 0
   */
  width?: number;
  /**
   * Keep the aspect ratio of the source video. When `true`, `width`/`height`
   * are treated as a maximum bound instead of an exact size.
   * @default true
   */
  keepAspectRatio?: boolean;
  /**
   * Frames per second of the output video.
   * @default 30
   */
  fps?: number;
  /**
   * Target bitrate of the output video, in bits per second. When omitted (or `0`) the
   * plugin estimates one from the output resolution and frame rate
   * (`0.07 * 2 * width * height * fps`), capped at the bitrate of the source video.
   * @default 0
   */
  videoBitrate?: number;
}

export interface VideoEditOptions {
  /**
   * Path of the source video. Accepts a `file://` url (such as the `videoUrl`
   * returned by `stopRecording()`), a plain filesystem path or, on Android, a
   * `content://` uri.
   */
  path: string;
  trim?: VideoEditTrimOptions;
  transcode?: VideoEditTranscodeOptions;
}

export interface VideoThumbnailOptions {
  /**
   * Path of the source video. Same formats as `editVideo()`.
   */
  path: string;
  /**
   * Position of the extracted frame, in milliseconds from the start of the video.
   * @default 0
   */
  at?: number;
  /**
   * Target width in pixels. `0` keeps the source width.
   * @default 0
   */
  width?: number;
  /**
   * Target height in pixels. `0` keeps the source height.
   * @default 0
   */
  height?: number;
}

export interface MediaFileResult {
  file: MediaFile;
}

export interface MediaFile {
  /**
   * The name of the file, without path information.
   */
  name: string;
  /**
   * The full path of the file, including the name.
   */
  path: string;
  /**
   * The file's mime type.
   */
  type: string;
  /**
   * The size of the file, in bytes.
   */
  size: number;
}

export interface TranscodeProgressInfo {
  /**
   * Transcoding progress, between `0` and `1`.
   */
  progress: number;
}
