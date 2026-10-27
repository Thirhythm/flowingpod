package thirhythm.flowingpod

import com.ryanheise.audioservice.AudioServiceActivity

/**
 * Shares audio_service's FlutterEngine so playback keeps running while the
 * activity is in the background.
 */
class MainActivity : AudioServiceActivity()
