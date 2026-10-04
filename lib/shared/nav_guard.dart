import 'package:flutter/widgets.dart';

// ---------------------------------------------------------------------------
// NavGuard — one place that stops a double tap becoming two screens.
//
// Reported: "tapping the task bar multiple times opens the page multiple
// times". The tab strip itself is safe (it drives a PageView via
// animateToPage, which is idempotent), but every tap that PUSHES a route is
// not, and the async ones are the worst:
//
//   openProfile() awaits resolveId() and then fetchById() BEFORE pushing.
//   Two taps during that round trip produce two in-flight calls, both of
//   which reach their push, and the user ends up closing the same profile
//   twice. 25 push sites in lib/ have an await before the push.
//
// Two conditions, because one is not enough:
//   * _inFlight  — covers the async gap, where the work has started but no
//                  route exists yet, so Navigator has nothing to dedupe on.
//   * _cooldown  — covers the synchronous case (the camera button), where
//                  _inFlight is set and cleared inside the same tap and
//                  would never block a second one.
//
// Deliberately NOT awaiting the pushed route: Navigator.push's Future
// completes when the route is POPPED, so holding the flag until then would
// block all navigation for as long as the screen stayed open.
// ---------------------------------------------------------------------------

class NavGuard {
  NavGuard._();

  static bool _inFlight = false;
  static DateTime _lastStart = DateTime.fromMillisecondsSinceEpoch(0);

  /// Long enough to swallow a fast double tap, short enough that a person
  /// deliberately opening two things in a row never notices it.
  static const Duration _cooldown = Duration(milliseconds: 500);

  static bool get _blocked =>
      _inFlight || DateTime.now().difference(_lastStart) < _cooldown;

  /// A tap that pushes immediately, with no async work first.
  static void push(BuildContext context, Route<void> route) {
    if (_blocked) return;
    _lastStart = DateTime.now();
    Navigator.of(context).push(route);
  }

  /// A tap that must look something up before it can decide what to push.
  /// [action] must not await the route it pushes — see the note above.
  static Future<void> run(Future<void> Function() action) async {
    if (_blocked) return;
    _inFlight = true;
    _lastStart = DateTime.now();
    try {
      await action();
    } finally {
      _inFlight = false;
      // Cooldown runs from when the work FINISHED, so a slow lookup does not
      // hand back a wide-open window the moment it lands.
      _lastStart = DateTime.now();
    }
  }
}

// ---------------------------------------------------------------------------
// App-wide double-tap guard. Reported: "clicking several times on Add people
// opens the dropdown many times — nowhere in the app should that happen".
// Individual NavGuard call sites can't cover every button, so this does it
// once, at the root: whenever ANY route opens (screen, bottom sheet, dialog,
// menu), taps are ignored for a moment — about as long as the open
// animation. The second tap of a double tap lands inside that window and is
// dropped instead of opening a second copy. A gesture already in progress
// is unaffected (hit-testing happens on finger-down only).
// ---------------------------------------------------------------------------

final ValueNotifier<bool> navTapLock = ValueNotifier<bool>(false);

class TapLockNavigatorObserver extends NavigatorObserver {
  static const _window = Duration(milliseconds: 420);
  int _generation = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    // The very first route (app start) has no previous one: nothing to guard.
    if (previousRoute == null) return;
    final gen = ++_generation;
    navTapLock.value = true;
    Future<void>.delayed(_window, () {
      if (gen == _generation) navTapLock.value = false;
    });
  }
}

/// Wraps the app (MaterialApp.builder) so [navTapLock] can swallow taps.
class TapLockScope extends StatelessWidget {
  const TapLockScope({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: navTapLock,
        builder: (_, locked, c) => AbsorbPointer(absorbing: locked, child: c),
        child: child,
      );
}
