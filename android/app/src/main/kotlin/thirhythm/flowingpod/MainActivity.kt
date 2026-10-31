package thirhythm.flowingpod

import android.content.Intent
import android.os.Build
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Shares audio_service's FlutterEngine so playback keeps running while the
 * activity is in the background, and hosts the native audio effects the Dart
 * side drives.
 */
class MainActivity : AudioServiceActivity() {
    private lateinit var storageChannel: StorageChannel
    private lateinit var downloadChannel: DownloadChannel

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        storageChannel = StorageChannel(this)
        MethodChannel(messenger, STORAGE_CHANNEL)
            .setMethodCallHandler(storageChannel::handle)

        downloadChannel = DownloadChannel(this)
        MethodChannel(messenger, DOWNLOAD_CHANNEL)
            .setMethodCallHandler(downloadChannel::handle)

        MethodChannel(messenger, VOLUME_LEVELING_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "setEnabled" -> {
                    NativeAudioEffects.configureLeveling(
                        call.argument<Boolean>("enabled") == true,
                        call.argument<Int>("sessionId"),
                    )
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(messenger, EQUALIZER_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isSupported" -> result.success(
                    Build.VERSION.SDK_INT >= Build.VERSION_CODES.P,
                )
                "probe" -> result.success(
                    NativeAudioEffects.probe(call.argument<Int>("sessionId")),
                )
                "configure" -> {
                    NativeAudioEffects.configureEqualizer(
                        call.argument<Boolean>("enabled") == true,
                        call.gains(),
                        call.argument<Int>("sessionId"),
                    )
                    result.success(null)
                }
                "release" -> {
                    NativeAudioEffects.release()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    /** Decodes the band gains, accepting a standard list or a typed array. */
    private fun MethodCall.gains(): FloatArray? = when (val raw = argument<Any>("gains")) {
        is DoubleArray -> FloatArray(raw.size) { raw[it].toFloat() }
        is List<*> -> raw.mapNotNull { (it as? Number)?.toFloat() }.toFloatArray()
        else -> null
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        storageChannel.onActivityResult(requestCode, resultCode, data)
    }

    override fun onResume() {
        super.onResume()
        storageChannel.onResume()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        storageChannel.onRequestPermissionsResult(requestCode, grantResults)
        downloadChannel.onRequestPermissionsResult(requestCode, grantResults)
    }

    private companion object {
        const val VOLUME_LEVELING_CHANNEL = "thirhythm.flowingpod/volume_leveling"
        const val EQUALIZER_CHANNEL = "thirhythm.flowingpod/equalizer"
        const val STORAGE_CHANNEL = "thirhythm.flowingpod/storage"
        const val DOWNLOAD_CHANNEL = "thirhythm.flowingpod/download"
    }
}
