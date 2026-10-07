package com.abhisheksdpatel.iapp

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/// The "feel" of pinging, on Android — matched to the iPhone's
/// (ios/Runner/AppDelegate.swift), which is the reference.
///
/// WHY THIS WAS REWRITTEN (explicit report, 2026-10-07: "the haptics how I'm
/// feeling in iPhone isn't the same in Android phone"). Every pattern used
/// to be a hand-drawn amplitude waveform in 16 ms steps. An iPhone's Taptic
/// Engine can follow a curve like that; an Android phone's motor mostly
/// cannot — it needs tens of milliseconds just to spin up — so the same
/// curve came out as one muddy buzz. And on a phone with no amplitude
/// control at all it played a flat 60 ms buzz AND reported failure, so the
/// Dart side then fired its fallback taps on top of it.
///
/// Now each feel uses the best thing the phone actually has, in this order:
///
///  1. HAPTIC PRIMITIVES (Android 11+, where the phone supports them):
///     effects the phone's maker tuned for its own motor — a real THUD, a
///     real rise and fall. This is Android's equivalent of Core Haptics and
///     the closest match to the iPhone.
///  2. PREDEFINED EFFECTS (Android 10+): the system's own heavy click.
///  3. A WAVEFORM, with an amplitude curve where the motor has amplitude
///     control (in 20 ms+ steps it can follow), or an on/off rhythm where
///     it hasn't.
///
/// Every path that makes the phone vibrate returns true, so the Dart side
/// never adds a second, fallback vibration.
class MainActivity : FlutterActivity() {

    private val channelName = "i/haptics"

    /** One step of an amplitude waveform, in ms. Long enough for a motor to
     *  follow, short enough that the steps still read as one curve. */
    private val step = 20L

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

    /** True when this phone has every one of [ids] as a tuned primitive. */
    private fun hasPrimitives(vararg ids: Int): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.R &&
            vibrator?.areAllPrimitivesSupported(*ids) == true

    /** The motor, ready to play — or null when the phone has none. */
    private fun ready(): Vibrator? {
        val v = vibrator ?: return null
        if (!v.hasVibrator()) return null
        v.cancel()
        return v
    }

    /** Plays [amplitudes] (0-255), one per [step], as a single waveform. */
    @androidx.annotation.RequiresApi(Build.VERSION_CODES.O)
    private fun playCurve(v: Vibrator, amplitudes: IntArray) {
        val timings = LongArray(amplitudes.size) { step }
        v.vibrate(
            VibrationEffect.createWaveform(
                timings,
                amplitudes.map { it.coerceIn(1, 255) }.toIntArray(),
                -1,
            ),
        )
    }

    /** Plays an off/on/off/on... rhythm, for motors with no amplitude
     *  control. [timings] starts with an OFF duration. */
    private fun playRhythm(v: Vibrator, timings: LongArray) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            v.vibrate(VibrationEffect.createWaveform(timings, -1))
        } else {
            @Suppress("DEPRECATION")
            v.vibrate(timings, -1)
        }
    }

    /** Sent a ping, or pinged back: ONE thud (explicit request,
     *  2026-10-03: "single thud feeling, not vibrations"). iPhone: a 0.14 s
     *  soft swell with body and no click. */
    private fun thud(): Boolean {
        val v = ready() ?: return false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            hasPrimitives(VibrationEffect.Composition.PRIMITIVE_THUD)
        ) {
            v.vibrate(
                VibrationEffect.startComposition()
                    .addPrimitive(VibrationEffect.Composition.PRIMITIVE_THUD, 1f)
                    .compose(),
            )
            return true
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R &&
            hasPrimitives(VibrationEffect.Composition.PRIMITIVE_CLICK)
        ) {
            v.vibrate(
                VibrationEffect.startComposition()
                    .addPrimitive(VibrationEffect.Composition.PRIMITIVE_CLICK, 1f)
                    .compose(),
            )
            return true
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            v.vibrate(
                VibrationEffect.createPredefined(VibrationEffect.EFFECT_HEAVY_CLICK),
            )
            return true
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            v.vibrate(
                VibrationEffect.createOneShot(
                    30,
                    if (canAmplitude()) 230 else VibrationEffect.DEFAULT_AMPLITUDE,
                ),
            )
        } else {
            @Suppress("DEPRECATION")
            v.vibrate(30)
        }
        return true
    }

    /** Replied / pinged back: rise, body, gentle fade — a finished gesture.
     *  iPhone: one 0.85 s swell (0.25 -> 1.0 by 0.18 s, easing to 0). */
    private fun reward(): Boolean {
        val v = ready() ?: return false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R &&
            hasPrimitives(
                VibrationEffect.Composition.PRIMITIVE_SLOW_RISE,
                VibrationEffect.Composition.PRIMITIVE_QUICK_FALL,
            )
        ) {
            v.vibrate(
                VibrationEffect.startComposition()
                    .addPrimitive(VibrationEffect.Composition.PRIMITIVE_SLOW_RISE, 0.8f)
                    .addPrimitive(VibrationEffect.Composition.PRIMITIVE_QUICK_FALL, 0.9f)
                    .compose(),
            )
            return true
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && canAmplitude()) {
            // The iPhone's own control points, sampled every [step]. Peaks
            // at 200, not 255: full power on a phone motor is a rattle, not
            // the soft top the Taptic Engine gives.
            val points = listOf(
                0f to 0.25f, 0.18f to 1f, 0.42f to 0.9f, 0.62f to 0.55f, 0.85f to 0f,
            )
            val total = 0.85f
            val steps = (total * 1000 / step).toInt()
            val amps = IntArray(steps) { i ->
                val t = i * step / 1000f
                val hi = points.indexOfFirst { it.first >= t }.coerceAtLeast(1)
                val (t0, a0) = points[hi - 1]
                val (t1, a1) = points[hi]
                val k = ((t - t0) / (t1 - t0)).coerceIn(0f, 1f)
                ((a0 + (a1 - a0) * k) * 200).toInt()
            }
            playCurve(v, amps)
            return true
        }
        // No amplitude control: three pulses that grow, then one long one —
        // strength can't change, so length does the rising.
        playRhythm(v, longArrayOf(0, 16, 46, 22, 40, 30, 34, 70))
        return true
    }

    /** Hold-to-unblur: a swell that grows over the hold (iPhone: 0.08 ->
     *  0.7 across the hold, cancelled when the finger lifts). */
    private fun ramp(ms: Long): Boolean {
        val v = ready() ?: return false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && canAmplitude()) {
            val steps = (ms / step).toInt().coerceIn(8, 100)
            val amps = IntArray(steps) { i ->
                val t = i.toFloat() / (steps - 1)
                // Ease-in, soft top end — a purr that grows rather than a
                // buzz that arrives (same shape as the iOS curve).
                (18 + (150 * t * t)).toInt()
            }
            playCurve(v, amps)
            return true
        }
        // No amplitude control: short pulses that get longer and closer
        // together across the hold.
        val timings = ArrayList<Long>()
        var elapsed = 0L
        while (elapsed < ms) {
            val t = elapsed.toFloat() / ms
            val off = (90 - 65 * t).toLong()
            val on = (12 + 22 * t).toLong()
            timings.add(off)
            timings.add(on)
            elapsed += off + on
        }
        playRhythm(v, timings.toLongArray())
        return true
    }
}
