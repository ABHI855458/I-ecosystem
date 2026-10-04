import 'dart:async';

import 'package:flutter/material.dart';

import '../profile_v2/profile_v2_menus.dart';
import 'score_reward_dropdown.dart' show kPingDropdownAutoClose, kPingDropdownWidth;

// Matches ping_page.dart's kCyan — not imported directly to avoid a
// circular import (ping_page.dart is this widget's own caller).
const _kCyan = Color(0xFF29D3E8);

// ---------------------------------------------------------------------------
// PingSentAnchor — the one "sent" confirmation for both ping paths.
//
// Replaces two different confirmations that used to exist:
//   - ping_prompt_sheet.dart's _buildSentState: an 80×80 coral circle with
//     an elasticOut check icon, in a 260px-tall SizedBox, holding the whole
//     sheet open for 1.5s.
//   - ping_page.dart's reply composer: no animation at all — success just
//     appended a static cyan chip to a growing list.
//
// Both are replaced with the same compact dropdown-panel confirmation,
// reusing the app's existing anchored-menu system (PV2MenuAnchor +
// PV2MenuPanel, profile_v2_menus.dart) rather than inventing a second
// floating-panel mechanism: same OverlayPortal escape-the-clip approach,
// same glass panel styling, same "any outside tap or timeout dismisses" the
// dropdown menu, that the reactions/three-dot menus already have.
// ---------------------------------------------------------------------------

class PingSentAnchor extends StatefulWidget {
  const PingSentAnchor({
    super.key,
    required this.open,
    required this.onDismissed,
    required this.child,
    this.label = 'Ping sent! 🎉',
    this.targetAnchor = Alignment.bottomCenter,
    this.followerAnchor = Alignment.topCenter,
    this.offset = const Offset(0, 8),
  });

  /// Caller-owned, same as [PV2MenuAnchor.open] — flip to `true` the moment
  /// a send/reply actually succeeds.
  final bool open;

  /// Fired once the confirmation's own auto-dismiss timer elapses, or an
  /// outside tap closes it early — set [open] back to `false` here.
  final VoidCallback onDismissed;

  /// The trigger the dropdown expands below (e.g. the Send button).
  final Widget child;

  final String label;
  final Alignment targetAnchor;
  final Alignment followerAnchor;
  final Offset offset;

  @override
  State<PingSentAnchor> createState() => _PingSentAnchorState();
}

class _PingSentAnchorState extends State<PingSentAnchor> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.open) _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer(kPingDropdownAutoClose, () {
      if (mounted) widget.onDismissed();
    });
  }

  @override
  void didUpdateWidget(covariant PingSentAnchor old) {
    super.didUpdateWidget(old);
    if (widget.open && !old.open) {
      _startTimer();
    } else if (!widget.open && old.open) {
      _timer?.cancel();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PV2MenuAnchor(
      open: widget.open,
      onDismiss: widget.onDismissed,
      targetAnchor: widget.targetAnchor,
      followerAnchor: widget.followerAnchor,
      offset: widget.offset,
      menu: PV2MenuPanel(
        width: kPingDropdownWidth,
        radius: 14,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  size: 16,
                  color: _kCyan,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      child: widget.child,
    );
  }
}
