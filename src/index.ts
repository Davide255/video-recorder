import { registerPlugin } from '@capacitor/core';

import type { VideoRecorderPlugin } from './definitions';

const VideoRecorder = registerPlugin<VideoRecorderPlugin>('VideoRecorder', {
  web: () => import('./web').then(m => new m.VideoRecorderWeb()),
});

export { VideoRecorderQuality, VideoRecorderCamera, VideoRecorderOptions, VideoRecorderErrors, VideoRecorderPlugin, VideoRecorderPreviewFrame, VideoRecorderCameraInfo, VideoEditOptions, VideoEditTrimOptions, VideoEditTranscodeOptions, VideoThumbnailOptions, MediaFile, MediaFileResult, TranscodeProgressInfo } from './definitions';
export { VideoRecorder };