import CoreHaptics
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // Smooth continuous haptics — see SmoothHaptics below in this file.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "SmoothHaptics") {
      SmoothHaptics.register(with: registrar)
    }
  }
}

/// Smooth, CONTINUOUS haptics (explicit request, 2026-10-03: "the
/// vibrations shall be soothing, smooth and continuous, not sudden — just
/// like the vibration when we call Hey Siri").
///
/// Flutter's own HapticFeedback only exposes discrete taps
/// (light/medium/heavy impact), which is exactly the "sudden" feel being
/// complained about. CoreHaptics can play a CONTINUOUS event whose
/// intensity and sharpness follow a curve, which is what the Siri
/// invocation haptic is: a soft swell that rises and settles, never a
/// click.
///
/// Patterns, all low-sharpness (soft/rounded rather than crisp):
///   * `ramp`   — a swell that rises over `ms`, for hold-to-unblur. Starts
///                faint and gets fuller as the hold completes; `stop`
///                cancels it the moment the finger lifts.
///   * `reward` — the reply/ping-back celebration: a quick rise, a full
///                sustained body, then a gentle fade out.
///   * `thud`   — sending a ping: two soft swells, "tud tud", with none of
///                the click of a heavy impact.
///
/// Falls back to UIImpactFeedbackGenerator on devices without CoreHaptics
/// (iPhone 7 and earlier, iPad), so the app never goes silent in the hand.
@objc class SmoothHaptics: NSObject {
  private var engine: CHHapticEngine?
  private var player: CHHapticAdvancedPatternPlayer?
  private let supported = CHHapticEngine.capabilitiesForHardware().supportsHaptics

  @objc static func register(with registrar: FlutterPluginRegistrar) {
    let instance = SmoothHaptics()
    let channel = FlutterMethodChannel(
      name: "i/haptics",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      instance.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    switch call.method {
    case "ramp":
      let ms = (args?["ms"] as? Int) ?? 1000
      ramp(seconds: Double(ms) / 1000.0)
      result(supported)
    case "warm":
      // Spin the engine up ahead of the first real haptic, so that first
      // buzz isn't late by the engine's own start-up time.
      _ = ensureEngine()
      result(supported)
    case "stop":
      stopPlayer()
      result(nil)
    case "reward":
      reward()
      result(supported)
    case "thud":
      thud()
      result(supported)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Engine

  private func ensureEngine() -> CHHapticEngine? {
    guard supported else { return nil }
    if let e = engine { return e }
    do {
      let e = try CHHapticEngine()
      // The engine is stopped by the system on interruptions (a call, the
      // app backgrounding). Restart lazily rather than going dead.
      e.stoppedHandler = { [weak self] _ in self?.engine = nil }
      e.resetHandler = { [weak self] in
        try? self?.engine?.start()
      }
      e.playsHapticsOnly = true
      try e.start()
      engine = e
      return e
    } catch {
      return nil
    }
  }

  private func stopPlayer() {
    try? player?.stop(atTime: CHHapticTimeImmediate)
    player = nil
  }

  private func play(_ pattern: CHHapticPattern) {
    guard let e = ensureEngine() else { return }
    stopPlayer()
    do {
      let p = try e.makeAdvancedPlayer(with: pattern)
      try p.start(atTime: CHHapticTimeImmediate)
      player = p
    } catch {
      // Engine may have been reclaimed between ensureEngine and start.
      engine = nil
    }
  }

  /// One continuous event with intensity/sharpness curves — the building
  /// block all three patterns are made of.
  private func continuousEvent(
    start: TimeInterval,
    duration: TimeInterval,
    intensity: Float,
    sharpness: Float
  ) -> CHHapticEvent {
    CHHapticEvent(
      eventType: .hapticContinuous,
      parameters: [
        CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
        CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
      ],
      relativeTime: start,
      duration: duration
    )
  }

  // MARK: - Patterns

  /// Hold-to-unblur: a swell that grows with the hold, soft throughout.
  private func ramp(seconds: TimeInterval) {
    guard supported else {
      UIImpactFeedbackGenerator(style: .light).impactOccurred()
      return
    }
    let curve = CHHapticParameterCurve(
      parameterID: .hapticIntensityControl,
      // Soft and rounded, Siri-invocation style — a purr that grows, not a
      // buzz. Deliberately tops out below full intensity (explicit request,
      // 2026-10-03: "soothing, smooth and continuous, not sudden").
      controlPoints: [
        .init(relativeTime: 0, value: 0.08),
        .init(relativeTime: seconds * 0.5, value: 0.3),
        .init(relativeTime: seconds * 0.8, value: 0.52),
        .init(relativeTime: seconds, value: 0.7),
      ],
      relativeTime: 0
    )
    do {
      let pattern = try CHHapticPattern(
        events: [
          continuousEvent(
            start: 0,
            duration: seconds,
            intensity: 0.7,
            sharpness: 0.05
          )
        ],
        parameterCurves: [curve]
      )
      play(pattern)
    } catch {}
  }

  /// Replied / pinged back: rise, body, gentle fade — a finished gesture.
  private func reward() {
    guard supported else {
      UINotificationFeedbackGenerator().notificationOccurred(.success)
      return
    }
    let total: TimeInterval = 0.85
    let curve = CHHapticParameterCurve(
      parameterID: .hapticIntensityControl,
      controlPoints: [
        .init(relativeTime: 0, value: 0.25),
        .init(relativeTime: 0.18, value: 1.0),
        .init(relativeTime: 0.42, value: 0.9),
        .init(relativeTime: 0.62, value: 0.55),
        .init(relativeTime: total, value: 0.0),
      ],
      relativeTime: 0
    )
    let sharpnessCurve = CHHapticParameterCurve(
      parameterID: .hapticSharpnessControl,
      controlPoints: [
        .init(relativeTime: 0, value: 0.35),
        .init(relativeTime: total, value: 0.0),
      ],
      relativeTime: 0
    )
    do {
      let pattern = try CHHapticPattern(
        events: [
          continuousEvent(
            start: 0,
            duration: total,
            intensity: 0.9,
            sharpness: 0.2
          )
        ],
        parameterCurves: [curve, sharpnessCurve]
      )
      play(pattern)
    } catch {}
  }

  /// Sent a ping, or pinged back: ONE thud (explicit request, 2026-10-03:
  /// "ping back button, or pinged, let there be single thud feeling, not
  /// vibrations"). A single short swell — body without a click, and over
  /// before it can read as a pattern.
  private func thud() {
    guard supported else {
      UIImpactFeedbackGenerator(style: .medium).impactOccurred()
      return
    }
    let total: TimeInterval = 0.14
    let curve = CHHapticParameterCurve(
      parameterID: .hapticIntensityControl,
      controlPoints: [
        .init(relativeTime: 0, value: 0.45),
        .init(relativeTime: 0.04, value: 1.0),
        .init(relativeTime: total, value: 0.0),
      ],
      relativeTime: 0
    )
    do {
      let pattern = try CHHapticPattern(
        events: [
          continuousEvent(
            start: 0,
            duration: total,
            intensity: 1.0,
            sharpness: 0.3
          )
        ],
        parameterCurves: [curve]
      )
      play(pattern)
    } catch {}
  }
}
