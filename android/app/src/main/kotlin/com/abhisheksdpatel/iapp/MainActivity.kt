package com.abhisheksdpatel.iapp

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/// Smooth, CONTINUOUS haptics (explicit request, 2026-10-03: "the
/// vibrations shall be soothing, smooth and continuous, not sudden").
///
/// Flutter's HapticFeedback only fires single discrete taps. VibrationEffect
/// .createWaveform with an AMPLITUDE array (API 26+) lets the strength rise
/// and fall across many short steps, which reads as one smooth swell rather
/// than a row of separate buzzes. Pre-26, or on a device without amplitude
/// control, it degrades to a plain short vibration.
class MainActivity : FlutterActivity() {

    private val channelName = "i/haptics"

    /** One step of the waveform, in ms. Short enough that stepped
     *  amplitudes are felt as a continuous curve. */
    private val step = 16L

    private val vibrator: Vibrator? by lazy {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val manager =
                getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
            manager?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "ramp" -> {
                        val ms = (call.argument<Int>("ms") ?: 1000).toLong()
                        result.success(ramp(ms))
                    }
                    "reward" -> result.success(reward())
                    "thud" -> result.success(thud())
                    "warm" -> result.success(vibrator?.hasVibrator() == true)
                    "stop" -> {
                        vibrator?.cancel()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun canAmplitude(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            vibrator?.hasAmplitudeControl() == true

    /** Plays [amplitudes] (0-255) as one smooth waveform. */
    private fun play(amplitudes: IntArray): Boolean {
        val v = vibrator ?: return false
        if (!v.hasVibrator()) return false
        if (!canAmplitude()) {
            @Suppress("DEPRECATION")
            v.vibrate(60)
            return false
        }
        val timings = LongArray(amplitudes.size) { step }
        v.cancel()
        v.vibrate(VibrationEffect.createWaveform(timings, amplitudes, -1))
        return true
    }

    /** Hold-to-unblur: a swell that grows over the hold. */
    private fun ramp(ms: Long): Boolean {
        val steps = (ms / step).toInt().coerceIn(8, 120)
        val amps = IntArray(steps) { i ->
            val t = i.toFloat() / (steps - 1)
            // Ease-in, soft top end — a purr that grows rather than a
            // buzz that arrives (same shape as the iOS curve).
            (20 + (160 * t * t)).toInt().coerceIn(1, 255)
        }
        return play(amps)
    }

    /** Replied / pinged back: rise, body, gentle fade. */
    private fun reward(): Boolean {
        val steps = 52
        val amps = IntArray(steps) { i ->
            val t = i.toFloat() / (steps - 1)
            val a = when {
                t < 0.2f -> 60 + (195 * (t / 0.2f))
                t < 0.5f -> 255f
                else -> 255 * (1f - ((t - 0.5f) / 0.5f))
            }
            a.toInt().coerceIn(1, 255)
        }
        return play(amps)
    }

    /** Sent a ping, or pinged back: ONE thud (explicit request,
     *  2026-10-03: "single thud feeling, not vibrations"). */
    private fun thud(): Boolean {
        val amps = mutableListOf<Int>()
        for (i in 0 until 3) amps.add((120 + 135 * (i / 2f)).toInt())
        for (i in 0 until 6) amps.add((255 * (1f - i / 5f)).toInt().coerceAtLeast(1))
        return play(amps.map { it.coerceIn(1, 255) }.toIntArray())
    }
}
