import 'dart:io';

import 'package:deepar_flutter_plus/deepar_flutter_plus.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Wraps DeepArControllerPlus (deepar_flutter_plus) — real AR camera preview
/// + lens/mask/filter switching, no bespoke state machine of our own beyond
/// what the SDK's own controller already tracks (isInitialized, isRecording,
/// etc. are read straight through).
///
/// License keys come from .env (DEEPAR_IOS_KEY / DEEPAR_ANDROID_KEY, see
/// main.dart's dotenv.load) — never hardcoded, never asked for in chat.
/// [isConfigured] reflects a genuinely empty/missing key (e.g. a fresh
/// clone before the user fills in .env) so callers can show a real "not set
/// up yet" state instead of the SDK throwing deep inside initialize().
class DeepArService {
  DeepArService._();
  static final instance = DeepArService._();

  // NOT final — see initializeWithDefaults()'s own doc for why this gets
  // replaced with a fresh instance on every (re-)initialization rather than
  // being reused for the app's whole lifetime.
  DeepArControllerPlus _controller = DeepArControllerPlus();
  DeepArControllerPlus get controller => _controller;

  String? get _iosKey {
    final v = dotenv.maybeGet('DEEPAR_IOS_KEY');
    return (v == null || v.isEmpty) ? null : v;
  }

  String? get _androidKey {
    final v = dotenv.maybeGet('DEEPAR_ANDROID_KEY');
    return (v == null || v.isEmpty) ? null : v;
  }

  /// False until a real (non-empty) key exists for the current platform —
  /// checked BEFORE calling [initialize], since DeepArControllerPlus.
  /// initialize() asserts non-null keys rather than failing gracefully.
  bool get isConfigured => Platform.isIOS ? _iosKey != null : _androidKey != null;

  bool _initialized = false;
  bool get isInitialized => _initialized && controller.isInitialized;

  /// Beautification is a DeepAR filter, not a controller flag — DeepAR's
  /// own docs apply it via switchFilter with a beauty .deepar file, same as
  /// any other filter (see DeepArLens.beautification below). No such asset
  /// ships with this repo yet; see that constant's own doc.
  ///
  /// A `DeepArControllerPlus` instance can only ever be initialize()'d ONCE
  /// — confirmed against the real package source: `late final Resolution
  /// _resolution` is set inside initialize() and never cleared by
  /// destroy()'s _resetState(), so calling initialize() again on the SAME
  /// instance (e.g. reopening a camera screen after closing it once, with
  /// the old singleton-style `final controller` field this used to be)
  /// throws "LateInitializationError: Field '_resolution' has already been
  /// initialized" — reproduced live on-device. Fix: every call here
  /// destroys whatever controller was previously live (if any — cheap/safe
  /// even if already destroyed, destroy() is idempotent) and swaps in a
  /// brand-new instance before initializing, so `late final _resolution` is
  /// always virgin.
  Future<InitializeResult> initializeWithDefaults() async {
    if (!isConfigured) {
      return const InitializeResult(
        success: false,
        message: 'DeepAR not configured — fill in DEEPAR_IOS_KEY/DEEPAR_ANDROID_KEY in .env',
      );
    }
    if (_initialized) {
      await _controller.destroy();
    }
    _controller = DeepArControllerPlus();
    final result = await _controller.initialize(
      androidLicenseKey: _androidKey,
      iosLicenseKey: _iosKey,
      resolution: Resolution.medium,
    );
    _initialized = result.success;
    if (result.success) {
      // Best-effort — a missing asset shouldn't fail the whole camera
      // screen, just leave the preview unbeautified.
      await applyLens(DeepArLens.beautification);
    }
    return result;
  }

  /// On iOS, `initialize()` resolving `success: true` does NOT mean the
  /// native platform view/texture exists yet — confirmed in the package's
  /// own README, which documents polling `isInitialized` (backed by
  /// `_textureId != null`) after a successful initialize() before doing
  /// anything else. Skipping this and calling something like flipCamera()
  /// immediately crashes for real on-device with "Null check operator used
  /// on a null value" inside the package's own iOS closure (`_textureId!`)
  /// — reproduced live. Callers must await this before touching the
  /// controller any further post-initialize.
  Future<bool> waitUntilViewReady({
    Duration timeout = const Duration(seconds: 10),
    Duration pollEvery = const Duration(milliseconds: 200),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (_controller.isInitialized) return true;
      await Future.delayed(pollEvery);
    }
    return _controller.isInitialized;
  }

  /// Applies one named lens/filter/mask — see [DeepArLens] for the real
  /// switchFilter/switchFaceMask routing per slot.
  ///
  /// Checks the asset actually exists in the Flutter bundle FIRST, via a
  /// plain Dart-level rootBundle.load (safe, catchable) — reproduced live
  /// on-device: calling switchFilter/switchFaceMask with a path that isn't a
  /// real bundled asset doesn't fail gracefully on iOS, it hard-crashes the
  /// whole app natively (EXC_BREAKPOINT inside libobjc, right after the
  /// native log line "Asset not found: .../flutter_assets/"). A native crash
  /// can't be caught by the try/catch below — Dart exception handling only
  /// covers errors that come back through the platform channel's normal
  /// error path, not a native-side fault. None of DeepArLens's asset paths
  /// are real files yet (see that enum's own doc) nor registered in
  /// pubspec.yaml's assets list, so right now this always no-ops — that's
  /// correct/expected until real .deepar files are added, not a bug.
  Future<void> applyLens(DeepArLens lens) async {
    try {
      await rootBundle.load(lens.assetPath);
    } catch (_) {
      // Not a real bundled asset — do NOT call into native code with this
      // path, it crashes rather than erroring. Silent no-op is correct
      // here: the caller (the filter strip) already only debounces to a
      // settled selection, there's nothing else useful to show/do for a
      // lens with no real asset behind it yet.
      return;
    }
    try {
      if (lens.isMask) {
        await controller.switchFaceMask(lens.assetPath);
      } else {
        await controller.switchFilter(lens.assetPath);
      }
    } catch (_) {
      // Swallow — genuine native/runtime failures still shouldn't crash the
      // capture screen. Caller can check controller state / retry.
    }
  }

  /// Clears the current effect. NOTE: deepar_flutter_plus 0.2.1 has no
  /// dedicated "clear effect" method (checked its real source — only
  /// switchEffect/switchFilter/switchFaceMask/switchEffectWithSlot exist,
  /// all of which load something, none unload). switchEffect('') is an
  /// UNVERIFIED best guess at the underlying native SDK's convention, not
  /// something confirmed in this package's Dart source or README — verify
  /// against DeepAR's own native docs (help.deepar.ai) or test on-device
  /// before relying on this. Wrapped so a wrong guess degrades silently
  /// rather than crashing the capture screen.
  Future<void> clearLens() async {
    try {
      await controller.switchEffect('');
    } catch (_) {}
  }

  Future<void> dispose() async {
    _initialized = false;
    await controller.destroy();
  }
}

/// Named lens slots for this app's two real use cases — Anonymous persona
/// masks (face-covering, so a captured photo can't be tied to the poster's
/// real face) and Ping's fun filters. Asset paths are placeholders: no
/// actual .deepar effect files ship with this repo (they're binary design
/// assets, not something to fabricate) — add real files at these paths
/// (asset bundles registered in pubspec.yaml under flutter/assets, same as
/// any other bundled asset) before shipping, or swap in real URLs
/// (switchFilter/switchFaceMask both accept a remote URL and cache it, per
/// deepar_flutter_plus's own README).
enum DeepArLens {
  beautification('assets/deepar/filter_beautification.deepar', isMask: false),
  anonymousMaskOne('assets/deepar/mask_anonymous_1.deepar', isMask: true),
  anonymousMaskTwo('assets/deepar/mask_anonymous_2.deepar', isMask: true),
  pingFilterOne('assets/deepar/filter_ping_1.deepar', isMask: false),
  pingFilterTwo('assets/deepar/filter_ping_2.deepar', isMask: false);

  const DeepArLens(this.assetPath, {required this.isMask});

  final String assetPath;
  final bool isMask;
}
