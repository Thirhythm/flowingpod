package thirhythm.flowingpod

import android.media.audiofx.DynamicsProcessing
import android.os.Build
import androidx.annotation.RequiresApi

/**
 * Native audio processing on the player's audio session.
 *
 * Loudness leveling (input gain + limiter) and the ten-band equalizer share a
 * single [DynamicsProcessing] instance, so the two features cannot attach
 * competing effects to the same session. The instance is created lazily once
 * the engine reports a session id and released once neither feature is active.
 */
internal object NativeAudioEffects {
    /** Lift applied before the limiter, in decibels. */
    private const val INPUT_GAIN_DB = 6f

    /** Peaks are held below this level, in decibels, leaving headroom. */
    private const val LIMITER_THRESHOLD_DB = -2f

    /** Ten equalizer bands, low to high, in hertz. */
    private val EQ_FREQUENCIES = floatArrayOf(
        31f,
        62f,
        125f,
        250f,
        500f,
        1_000f,
        2_000f,
        4_000f,
        8_000f,
        16_000f,
    )

    private var effect: DynamicsProcessing? = null
    private var sessionId: Int? = null

    private var levelingEnabled = false
    private var equalizerEnabled = false

    /** Latest band gains in decibels, matching [EQ_FREQUENCIES]. */
    private var gains = FloatArray(EQ_FREQUENCIES.size)

    /**
     * Applies the requested leveling state to [session], creating the effect
     * when the session becomes known or changes. Calling this repeatedly with
     * the same values is cheap.
     */
    @Synchronized
    fun configureLeveling(enabled: Boolean, session: Int?) {
        updateSession(session)
        levelingEnabled = enabled
        apply()
    }

    /**
     * Applies the requested equalizer state. [gainsDecibels] is expected to
     * have one gain per band; other lengths are ignored.
     */
    @Synchronized
    fun configureEqualizer(enabled: Boolean, gainsDecibels: FloatArray?, session: Int?) {
        updateSession(session)
        equalizerEnabled = enabled
        if (gainsDecibels != null && gainsDecibels.size == EQ_FREQUENCIES.size) {
            gains = gainsDecibels
        }
        apply()
    }

    /**
     * Whether a ten-band dynamics effect can be created on [session]. An
     * already created effect proves that the platform supports it; otherwise a
     * throwaway instance is created and released.
     */
    @Synchronized
    fun probe(session: Int?): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return false
        if (effect != null) return true
        val id = session ?: return false
        val candidate = create(id) ?: return false
        try {
            candidate.release()
        } catch (_: Exception) {
            // Nothing was attached to the session yet.
        }
        return true
    }

    @Synchronized
    fun release() {
        releaseEffect()
        sessionId = null
    }

    private fun updateSession(session: Int?) {
        if (session != null && session != sessionId) {
            releaseEffect()
            sessionId = session
        }
    }

    private fun apply() {
        val id = sessionId
        if (id == null || (!levelingEnabled && !equalizerEnabled)) {
            releaseEffect()
            return
        }
        val processor = effect ?: create(id) ?: return
        effect = processor
        try {
            if (levelingEnabled) {
                processor.setInputGainAllChannelsTo(INPUT_GAIN_DB)
                processor.setLimiterAllChannelsTo(limiter(true))
            } else {
                processor.setInputGainAllChannelsTo(0f)
                processor.setLimiterAllChannelsTo(limiter(false))
            }
            val equalizer = DynamicsProcessing.Eq(
                true,
                equalizerEnabled,
                EQ_FREQUENCIES.size,
            )
            for (index in EQ_FREQUENCIES.indices) {
                equalizer.setBand(
                    index,
                    DynamicsProcessing.EqBand(
                        true,
                        EQ_FREQUENCIES[index],
                        gains[index],
                    ),
                )
            }
            processor.setPreEqAllChannelsTo(equalizer)
            processor.setEnabled(true)
        } catch (_: Exception) {
            releaseEffect()
        }
    }

    private fun releaseEffect() {
        effect?.let { processor ->
            try {
                processor.setEnabled(false)
            } catch (_: Exception) {
                // The session already tore the effect down.
            }
            try {
                processor.release()
            } catch (_: Exception) {
                // Already released.
            }
        }
        effect = null
    }

    @RequiresApi(Build.VERSION_CODES.P)
    private fun create(session: Int): DynamicsProcessing? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return null
        return try {
            val config = DynamicsProcessing.Config.Builder(
                // A ten-band equalizer resolving down to 31 Hz needs the larger
                // analysis window; the limiter tolerates the added latency.
                DynamicsProcessing.VARIANT_FAVOR_FREQUENCY_RESOLUTION,
                2, // Stereo; effect attachment fails gracefully on mono sessions.
                true,
                EQ_FREQUENCIES.size,
                false,
                0,
                false,
                0,
                true,
            )
                .setInputGainAllChannelsTo(0f)
                .setLimiterAllChannelsTo(limiter(false))
                .build()
            DynamicsProcessing(0, session, config)
        } catch (_: Exception) {
            // Devices without a working dynamics stage keep the plain output.
            null
        }
    }

    private fun limiter(enabled: Boolean) = DynamicsProcessing.Limiter(
        true,
        enabled,
        0,
        4f, // attack, ms
        250f, // release, ms
        4f, // ratio
        LIMITER_THRESHOLD_DB,
        0f, // post gain, dB
    )
}
