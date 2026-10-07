import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/score_gain_service.dart';
import '../../shared/score_tier.dart';
import '../../main_shell.dart' show kTabBarHeight, kTabBarBottomOffset;
import '../profile_v2/profile_v2_menus.dart';
import '../profile_v2/profile_v2_icons.dart';

// ---------------------------------------------------------------------------
// ScoreRewardAnchor — the reward that drops out of a button after an action
// that earned points.
//
// Replaces PingSentAnchor, which was a 178px panel with a grey tick and the
// words "Ping sent! 🎉" — it confirmed the send and said nothing about what
// you got for it. Reported as "its not correct remove that and add the drop
// down there also, make it colourful and like there achieving something".
//
// What it shows instead, all from the server (ScoreGainService):
//   * the REAL points that action paid — +25 for a ping, +20 for answering
//     one, +3 for a comment. Every popup in the app used to say "+10"
//     regardless, which was wrong for every single action.
//   * what the points were for
//   * the progress bar toward the next level, filling to the new total
//
// The LOOK is the composer's anon-post reward card (ComposerPhase.reward's
// _RewardCard), shrunk to this panel — explicit instruction: "there shall be
// a drop down score [page] how it was appearing for anon page... in the same
// design I meant to implement it for pinging someone", with "the drop down
// size... the same as the ping prompts drop down". So the glow circle, the
// 🔥 reason line, the tier caption, the level ring and the elasticOut pop
// are all that screen's, at roughly half scale. The one-row version that
// used to live here (a numeral, a reason and a 3px bar as the panel's bottom
// edge) is gone.
//
// Same anchored-dropdown mechanism as before (PV2MenuAnchor + PV2MenuPanel)
// and the same 178px width, so it drops out of a Send button exactly the way
// the old confirmation did.
// ---------------------------------------------------------------------------

/// Every ping-side confirmation dropdown is this wide, so the score reward
/// and the sent confirmation are the same size — explicit request: "the
/// score drop down shall be same size of ping drop down size".
const kPingDropdownWidth = 178.0;

/// How long those dropdowns stay up before retiring themselves.
const kPingDropdownAutoClose = Duration(milliseconds: 1500);

/// Shows the reward as a floating drop-in, for the actions whose own screen
/// CLOSES on send — the composer and the ping prompt sheet.
///
/// An anchored dropdown cannot work there: it hangs off a button that is
/// being torn down, so the choice was either hold the screen open long
/// enough to read it (the 1600ms/2400ms stalls that were reported as "don't
/// make the user see the send button load") or never show it. This does
/// neither — the screen closes immediately, the send finishes in the
/// background, and the reward drops in over whatever is now on screen.
///
/// [overlay] must be captured BEFORE the caller pops its route, since the
/// popped context can no longer resolve one. [loadGain] runs while nothing
/// is drawn yet — the reward animates in only once it resolves, so the
/// number is ALREADY on it the instant it appears. Reported against the
/// earlier version, which showed itself straight away and sat on a "···"
/// placeholder until the upload finished: "here the score isnt visible at
/// the instant... after sometime it would be visible". When it resolves to
/// nothing (an action that paid no points, or a failed send) nothing is
/// ever shown, rather than a panel claiming "+0".
///
/// [large] renders it at the composer card's own size and geometry, for
/// posting — "this should have been the same size of compose camera". The
/// default is the compact panel a ping drops.
/// See _ScoreRewardDropInState._run's cooldown.
const _kScoreCardCooldown = Duration(minutes: 15);
const _kScoreCardAlwaysShowFrom = 50;
DateTime? _lastScoreCardAt;

void showScoreRewardOverlay({
  required OverlayState overlay,
  required Future<ScoreGain?> Function() loadGain,
  // 2600 -> 1500, matching kPingDropdownAutoClose so every reward surface
  // retires on the same beat. Explicit request: "make it instant when it
  // closes and close the score board also faster".
  Duration hold = kPingDropdownAutoClose,
  bool large = false,
}) {
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => _ScoreRewardDropIn(
      loadGain: loadGain,
      hold: hold,
      large: large,
      onRetire: () {
        if (entry.mounted) entry.remove();
      },
    ),
  );
  overlay.insert(entry);
}

class _ScoreRewardDropIn extends StatefulWidget {
  const _ScoreRewardDropIn({
    required this.loadGain,
    required this.hold,
    required this.large,
    required this.onRetire,
  });

  final Future<ScoreGain?> Function() loadGain;
  final Duration hold;
  final bool large;
  final VoidCallback onRetire;

  @override
  State<_ScoreRewardDropIn> createState() => _ScoreRewardDropInState();
}

class _ScoreRewardDropInState extends State<_ScoreRewardDropIn>
    with SingleTickerProviderStateMixin {
  /// One controller drives both directions — forward to drop in, reverse to
  /// lift away — so the exit is the entrance played backwards rather than a
  /// second, differently-tuned animation.
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  ScoreGain? _gain;
  bool _retiring = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      // Snappier both ways — the reward is a confirmation, not a cutscene.
      duration: const Duration(milliseconds: 260),
      reverseDuration: const Duration(milliseconds: 160),
    );
    _fade = CurvedAnimation(
      parent: _ctrl,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, -0.55),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _ctrl,
      // Overshoots slightly on the way in — the "drop" in drop-in — and
      // retracts straight up on the way out.
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeIn,
    ));
    // Deferred to after this frame, NOT called straight from initState.
    // loadGain runs the caller's own send (see ping_prompt_sheet), whose
    // callbacks setState on the page underneath — doing that while this
    // entry is still being inserted threw "setState() called during build"
    // out of the overlay and took the send down with it, which is why
    // pinging showed no reward at all.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _run();
    });
  }

  Future<void> _run() async {
    ScoreGain? gain;
    try {
      gain = await widget.loadGain();
    } catch (_) {
      // The action itself failed (ping limit reached, already-open ping,
      // self-ping, blocked, or any other refusal) — every caller already
      // shows its own error message for this. This overlay's only job is
      // to celebrate a send that actually happened, so on a failure it
      // must never appear at all, not even the "Sent · +0" fallback.
      // Explicit report: "if the ping was unsuccessful... the score card
      // shall not open and show zero point, the drop down shall not open".
      // Retiring without ever calling setState keeps build() returning
      // SizedBox.shrink() the whole time this entry existed.
      if (mounted) widget.onRetire();
      return;
    }
    if (!mounted) return;
    // COOLDOWN (explicit request, 2026-10-03: "don't show the score card
    // always, it creates irritation"). After one card, the next ones stay
    // hidden for [_kScoreCardCooldown] — unless the gain is genuinely big,
    // which is still worth celebrating. The points are credited either
    // way; only the pop-up is skipped.
    final now = DateTime.now();
    final big = gain != null && gain.gained >= _kScoreCardAlwaysShowFrom;
    final last = _lastScoreCardAt;
    if (!big &&
        last != null &&
        now.difference(last) < _kScoreCardCooldown) {
      widget.onRetire();
      return;
    }
    _lastScoreCardAt = now;
    // An empty/absent gain used to retire WITHOUT EVER DRAWING. That is
    // precisely why the reward card "isn't shown" when pinging from a
    // profile, a group profile, or a group in the ping page — those sends
    // resolve a gain this read sees as empty, so the confirmation silently
    // vanished while the ping itself went through. Explicit follow-up: the
    // card must appear on those surfaces.
    //
    // It now draws either way: with the number when there is one, with the
    // panel's fallback label when there isn't. Suppression is the CALLER's
    // decision now (see showScoreReward on showPingPromptSheet), not a
    // silent side effect of a zero read.
    if (gain == null || gain.isEmpty) {
      setState(() => _gain = ScoreGain.none);
      await _ctrl.forward();
      await Future<void>.delayed(widget.hold);
      if (!mounted) return;
      await _retire();
      return;
    }
    // The number is set BEFORE the entrance plays, so the reward arrives
    // already carrying it — nothing animates in on a placeholder and then
    // corrects itself.
    setState(() => _gain = gain);
    await _ctrl.forward();
    await Future<void>.delayed(widget.hold);
    if (!mounted) return;
    await _retire();
  }

  Future<void> _retire() async {
    if (_retiring) return;
    _retiring = true;
    await _ctrl.reverse();
    if (mounted) widget.onRetire();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gain = _gain;
    // Still nothing until _run has resolved — but an EMPTY gain now draws
    // (fallback label), see _run.
    if (gain == null) return const SizedBox.shrink();

    final media = MediaQuery.of(context);
    final body = IgnorePointer(
      child: FadeTransition(
        opacity: _fade,
        child: SlideTransition(
          position: _slide,
          child: Material(
            color: Colors.transparent,
            child: widget.large
                ? ScoreRewardCard(gain: gain)
                : Center(
                    // The SAME panel chrome the anchored version uses
                    // (PV2MenuPanel, kPingDropdownWidth, radius 16,
                    // padding 0) rather than a bare SizedBox. Both were
                    // already 178 wide, but this one had no panel fill,
                    // border or corner radius, so it read as a large
                    // free-floating block over the page instead of a
                    // dropdown — reported as "the score thing shall be
                    // shown in the same size as the ping drop down".
                    // Same widget treatment now, so they cannot drift.
                    child: PV2MenuPanel(
                      width: kPingDropdownWidth,
                      radius: 16,
                      padding: 0,
                      children: [ScoreRewardBody(gain: gain)],
                    ),
                  ),
          ),
        ),
      ),
    );

    if (!widget.large) {
      // Sits just ABOVE the tab bar with a small gap, rather than pinned to
      // the top of the screen. Explicit follow-up: "let it appear just
      // above the task bar, not that much above, leaving little gap between
      // task bar". kTabBarHeight + kTabBarBottomOffset is the same pair
      // every other bottom-anchored surface in the app reserves, so this
      // tracks the real bar rather than a guessed offset.
      return Positioned(
        bottom: media.padding.bottom + kTabBarHeight + kTabBarBottomOffset + 10,
        left: 0,
        right: 0,
        child: body,
      );
    }

    // The composer card's own geometry (see composer_screen's build: 12pt
    // side inset, 12pt off the bottom, 0.8125 of the screen tall), so the
    // reward lands in exactly the frame the compose camera occupied.
    const pad = 12.0;
    final height = math.min(
      media.size.height * 0.8125,
      media.size.height - pad * 2 - media.padding.top,
    );
    return Positioned(
      left: pad,
      right: pad,
      bottom: pad,
      height: height,
      child: body,
    );
  }
}

class ScoreRewardAnchor extends StatefulWidget {
  const ScoreRewardAnchor({
    super.key,
    required this.open,
    required this.gain,
    required this.onDismissed,
    required this.child,
    this.fallbackLabel = 'Sent',
    this.targetAnchor = Alignment.bottomCenter,
    this.followerAnchor = Alignment.topCenter,
    this.offset = const Offset(0, 8),
  });

  /// Flip to true the moment the action actually succeeded.
  final bool open;

  /// What the action earned. When null or empty the panel still opens, but
  /// shows [fallbackLabel] alone — an action that genuinely pays nothing
  /// must not claim "+0", and a failed score read must not swallow the
  /// confirmation that the thing you did worked.
  final ScoreGain? gain;

  final VoidCallback onDismissed;
  final Widget child;
  final String fallbackLabel;
  final Alignment targetAnchor;
  final Alignment followerAnchor;
  final Offset offset;

  @override
  State<ScoreRewardAnchor> createState() => _ScoreRewardAnchorState();
}

class _ScoreRewardAnchorState extends State<ScoreRewardAnchor> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.open) _startTimer();
  }

  /// Explicit request: "these level drop downs shall close 1.5 secs
  /// automatically". Shared with PingSentAnchor so both confirmations
  /// retire on the same beat.
  void _startTimer() {
    _timer?.cancel();
    _timer = Timer(kPingDropdownAutoClose, () {
      if (mounted) widget.onDismissed();
    });
  }

  @override
  void didUpdateWidget(covariant ScoreRewardAnchor old) {
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
      // Centred anchors need the width to be centred and clamped on
      // screen — without it this panel grew out of the button's middle and
      // off the right edge. See PV2MenuAnchor.menuWidth.
      menuWidth: kPingDropdownWidth,
      // Same 178px width the sent confirmation used, so this drops out of a
      // Send button exactly where that did.
      menu: PV2MenuPanel(
        width: kPingDropdownWidth,
        radius: 16,
        // Edge to edge: the reward's progress bar IS the panel's bottom
        // edge, and the default 5px inset would float it off that edge and
        // leave a sliver of panel fill underneath.
        padding: 0,
        children: [
          ScoreRewardBody(
            gain: widget.gain,
            fallbackLabel: widget.fallbackLabel,
          ),
        ],
      ),
      child: widget.child,
    );
  }
}

/// The panel's contents, split out so the same reward can be shown somewhere
/// that isn't anchored to a button.
class ScoreRewardBody extends StatefulWidget {
  const ScoreRewardBody({
    super.key,
    required this.gain,
    this.fallbackLabel = 'Sent',
  });

  final ScoreGain? gain;
  final String fallbackLabel;

  @override
  State<ScoreRewardBody> createState() => _ScoreRewardBodyState();
}

class _ScoreRewardBodyState extends State<ScoreRewardBody>
    with SingleTickerProviderStateMixin {
  /// The anon reward card's own entrance — elasticOut scale + fade, same
  /// 500ms. It is most of what makes that screen feel like a reward rather
  /// than a receipt, so the dropdown version keeps it.
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();
    _scale = Tween<double>(begin: 0.5, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.gain;
    final fallbackLabel = widget.fallbackLabel;
    if (g == null || g.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_rounded,
                size: 16, color: Color(0xFF29D3E8)),
            const SizedBox(width: 8),
            // Flexible + ellipsis, not a bare Text: the label carries a
            // name ("Sent to abisheksdpatel"), and in a fixed 178px panel
            // an unconstrained Text overflowed the row by ~90px.
            Flexible(
              child: Text(
                fallbackLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // The tier the new total lands in — its colour carries the whole panel,
    // so the reward looks different at Rookie than it does at Legend.
    final info = tierInfoForScore(g.totalScore);
    final away = pointsToNextTier(g.totalScore);
    final reason = g.reasons.isEmpty ? 'points earned' : g.reasons.first.toLowerCase();

    // The anon post's reward card, shrunk to this dropdown's width —
    // explicit instruction: "there shall be a drop down score [page] how it
    // was appearing for anon page... in the same design I meant to implement
    // it for pinging someone", with "the drop down size... the same as the
    // ping prompts drop down". So: the same glow circle, the same 🔥 reason
    // line, the same tier caption and the same level ring the composer's
    // full-screen _RewardCard shows after an anon post — at ~half scale, on
    // the same dark ground, inside the 178px panel a ping already drops.
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        color: const Color(0xFF0A0A10),
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 14),
        child: FadeTransition(
          opacity: _fade,
          child: ScaleTransition(
            scale: _scale,
            child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: info.color.withValues(alpha: 0.12),
                boxShadow: [
                  BoxShadow(
                    color: info.color.withValues(alpha: 0.35),
                    blurRadius: 22,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  '+${g.gained}',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 11),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Blue, like every flame in the app.
                PV2Icons.iceFlame(13),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    reason,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.white.withValues(alpha: 0.90),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              away == null
                  ? '${info.title} · top level'
                  : '${info.title} · $away to next level',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 9.5,
                color: Colors.white.withValues(alpha: 0.42),
              ),
            ),
            const SizedBox(height: 14),
            _RewardLevelRing(gain: g, accent: info.color),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The level ring under the reward number — the same one the composer's
/// anon-post reward card draws, at dropdown scale. Sweeps from the progress
/// the score had BEFORE this action to where it is now, so even a small gain
/// visibly moves; a gain that crossed a level boundary sweeps the new level
/// from empty, since the old progress belongs to a different level's ring.
class _RewardLevelRing extends StatefulWidget {
  const _RewardLevelRing({
    required this.gain,
    required this.accent,
    this.size = 46,
  });

  final ScoreGain gain;
  final Color accent;
  final double size;

  @override
  State<_RewardLevelRing> createState() => _RewardLevelRingState();
}

class _RewardLevelRingState extends State<_RewardLevelRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.gain;
    final to = tierProgressToNext(g.totalScore);
    final crossedLevel = tierInfoForScore(g.totalScore - g.gained).tier !=
        tierInfoForScore(g.totalScore).tier;
    final from = crossedLevel
        ? 0.0
        : tierProgressToNext(g.totalScore - g.gained).clamp(0.0, to);
    final level = tierInfoForScore(g.totalScore).levelNumber;

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final t = Curves.easeOutCubic.transform(_ctrl.value);
        final d = widget.size;
        return SizedBox(
          width: d,
          height: d,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: d,
                height: d,
                child: CircularProgressIndicator(
                  value: from + (to - from) * t,
                  strokeWidth: d >= 64 ? 4 : 3,
                  backgroundColor: Colors.white.withValues(alpha: 0.08),
                  valueColor: AlwaysStoppedAnimation<Color>(widget.accent),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'LVL $level',
                    style: GoogleFonts.inter(
                      fontSize: d >= 64 ? 11 : 8.5,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    '${g.totalScore}',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: d >= 64 ? 9 : 7.5,
                      color: widget.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The reward at the composer card's scale — the same content as
/// [ScoreRewardBody], sized for a full card rather than a 178px panel.
/// Used by the post flow, where it lands in the frame the compose camera
/// just vacated.
class ScoreRewardCard extends StatefulWidget {
  const ScoreRewardCard({super.key, required this.gain});

  final ScoreGain gain;

  @override
  State<ScoreRewardCard> createState() => _ScoreRewardCardState();
}

class _ScoreRewardCardState extends State<ScoreRewardCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();
    _scale = Tween<double>(begin: 0.5, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.gain;
    // The tier the NEW total lands in colours the whole card, so posting at
    // Rookie looks different from posting at Legend.
    final info = tierInfoForScore(g.totalScore);
    final accent = info.color;
    final reason =
        g.reasons.isEmpty ? 'points earned' : g.reasons.first.toLowerCase();
    final away = pointsToNextTier(g.totalScore);

    return ClipRRect(
      borderRadius: const BorderRadius.all(Radius.circular(48)),
      child: Container(
        color: const Color(0xFF0A0A10),
        child: ScaleTransition(
          scale: _scale,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent.withValues(alpha: 0.12),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.35),
                        blurRadius: 40,
                        spreadRadius: 8,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      '+${g.gained}',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 42,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  '\u{1F525}  $reason',
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withValues(alpha: 0.90),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  away == null
                      ? '${info.title} \u00B7 top level'
                      : '${info.title} \u00B7 $away to next level',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.42),
                  ),
                ),
                const SizedBox(height: 36),
                _RewardLevelRing(gain: g, accent: accent, size: 72),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
