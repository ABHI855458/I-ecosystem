import 'package:flutter/foundation.dart';

/// Set while a screen is showing something that must own the whole display —
/// currently the reply-photo viewer, which is a timed, hold-to-hold reveal and
/// would be broken by the tab bar sitting over its bottom edge.
///
/// MainShell listens and fades its bottom nav out. Kept as a free-standing
/// notifier so the page that hides the chrome and the shell that owns it stay
/// decoupled — neither imports the other.
final immersiveChrome = ValueNotifier<bool>(false);
