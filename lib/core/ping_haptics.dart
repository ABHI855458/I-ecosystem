import 'package:flutter/services.dart'
    show
        HapticFeedback,
        MethodChannel,
        MissingPluginException,
        PlatformException;

// ---------------------------------------------------------------------------
// Ping haptics — the "feel" of pinging.
//
// SMOOTH AND CONTINUOUS (explicit request, 2026-10-03: "the vibrations
// shall be soothing, smooth and continuous, not sudden — just like the
// vibration when we call Hey Siri"). Flutter's own HapticFeedback can only
// fire single discrete taps, which is exactly the sudden feel that was
// being complained about, so the real patterns live natively:
//
//   * iOS      — CoreHaptics continuous events with intensity/sharpness
//                curves (ios/Runner/SmoothHaptics.swift). This is the same
//                mechanism the Siri invocation haptic uses: a soft swell,
//                never a click.
//   * Android  — VibrationEffect.createWaveform with a per-step amplitude
//                curve (MainActivity.kt).
//
// If the channel isn't there (older device, simulator, hot-reload before a
// native rebuild), every call degrades to the old discrete taps rather than
// going silent — see the `_fallback*` functions.
//
//   [pingThud]   — a ping SENT: two soft swells, "tud tud".
//   [pingReward] — answering someone (ping back / photo / text reply): a
//                  rise, a full body, then a gentle fade.
//   [HoldHaptics] — hold-to-unblur: one continuous swell that grows with
//                  the hold and is cancelled the moment the finger lifts.
// ---------------------------------------------------------------------------

const _channel = MethodChannel('i/haptics');

Future<void> _gap(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

/// Returns true when the native engine handled it.
Future<bool> _native(String method, [Map<String, Object?>? args]) async {
  try {
    final ok = await _channel.invokeMethod<bool>(method, args);
    return ok ?? false;
  } on MissingPluginException {
    return false;
  } on PlatformException {
    return false;
  }
}

/// Starts the native haptic engine ahead of time. iOS creates a
/// CHHapticEngine on first use, and that start-up delay landed on the very
/// first buzz after opening the app — felt as a lag (explicit report,
/// 2026-10-03). Called once when the Ping tab is built.
Future<void> warmHaptics() async {
  await _native('warm');
}

/// "tud tud" — sent a ping.
Future<void> pingThud() async {
  if (await _native('thud')) return;
  await _fallbackThud();
}

Future<void> _fallbackThud() async {
  // One tap, to match the native single thud.
  await HapticFeedback.mediumImpact();
}

/// The reward — replied / pinged back.
Future<void> pingReward() async {
  if (await _native('reward')) return;
  await _fallbackReward();
}

Future<void> _fallbackReward() async {
  // Densely spaced light taps read as closer to a swell than heavy hits do.
  for (var i = 0; i < 5; i++) {
    await HapticFeedback.lightImpact();
    await _gap(45);
  }
  await HapticFeedback.mediumImpact();
  await _gap(60);
  await HapticFeedback.lightImpact();
}

/// Hold-to-unblur — the "Hey Siri" feel (explicit request): one continuous
/// swell for the whole hold, cancelled the instant the finger lifts.
///
/// BUG FIX (2026-10-03, reported as the vibration still feeling sudden):
/// `start` can only learn whether the native engine took the pattern
/// asynchronously, and until that answer came back the old code treated
/// native as "not running" and fired its discrete fallback ticks anyway —
/// so on a 1s hold you felt clicks layered over the smooth swell for most
/// of it. The mode is now explicitly PENDING until the channel answers, and
/// ticks only ever fire once native has actually declined.
enum _HoldMode { pending, native, fallback }

class HoldHaptics {
  _HoldMode _mode = _HoldMode.pending;
  int _next = 0;

  /// Fallback ticks only — the native path needs no per-frame work.
  static const _steps = [
    .10,
    .22,
    .33,
    .43,
    .52,
    .60,
    .67,
    .74,
    .80,
    .85,
    .90,
    .94,
    .97,
    .99,
  ];

  void start(Duration holdFor) {
    _next = 0;
    _mode = _HoldMode.pending;
    _native('ramp', {'ms': holdFor.inMilliseconds}).then((ok) {
      // A cancel that lands first wins — don't resurrect a finished hold.
      if (_mode == _HoldMode.pending) {
        _mode = ok ? _HoldMode.native : _HoldMode.fallback;
      }
    });
  }

  /// Fed the hold progress (0→1) every frame. Silent unless the native
  /// swell was unavailable.
  void update(double p) {
    if (_mode != _HoldMode.fallback) return;
    while (_next < _steps.length && p >= _steps[_next]) {
      _next++;
      HapticFeedback.selectionClick();
    }
  }

  /// The hold completed. The native swell has already peaked and ends on
  /// its own, so this adds nothing there — a tap on top of it is exactly
  /// the "sudden" edge being complained about. Only the fallback, which has
  /// no swell to finish, marks the moment.
  void finish() {
    if (_mode == _HoldMode.fallback) HapticFeedback.selectionClick();
    _next = _steps.length;
    _mode = _HoldMode.fallback;
  }

  void cancel() {
    // Exhaust the tick list rather than resetting it: an `update` for the
    // same frame can still arrive after this, and it must stay silent.
    _next = _steps.length;
    final wasNative = _mode == _HoldMode.native || _mode == _HoldMode.pending;
    _mode = _HoldMode.fallback;
    // Stop even while pending: the ramp may still be starting up, and it
    // must not outlive the gesture.
    if (wasNative) _native('stop');
  }
}

// holdUnlocked() is gone — see HoldHaptics.finish(), which knows whether a
// native swell is already finishing and stays silent when it is.
