import 'dart:ui' as ui;
import '../../core/feature_flags.dart';

import 'package:flutter/material.dart';

import 'profile_v2_tokens.dart';

/// The dropdown-menu system shared by every Profile v2 surface that opens one:
/// the self-profile settings and photo menus, the per-post options menu, the
/// group member-settings menu, the person-profile More menu, and the creation
/// FAB.
///
/// Two things here are deliberate and load-bearing:
///
/// * **Menus render in the app [Overlay], not inline.** The design positions
///   them absolutely with a z-index, which in CSS escapes the parent's bounds.
///   Flutter has no z-index — an inline menu is clipped by any ancestor that
///   clips, and the post-options menu in particular lives inside a
///   `ClipRRect`-ed 128px tile while being 134px wide. Rendered inline it would
///   be cut in half. [PV2MenuAnchor] uses [OverlayPortal] to escape the clip,
///   positioning the panel by measuring the trigger's [GlobalKey] directly
///   rather than via `CompositedTransformFollower`/`LayerLink` — that pairing
///   requires the leader to have painted (and registered itself on the shared
///   `LayerLink`) before the follower's own paint in the same frame, which is
///   exactly the frame the portal is first shown. That ordering isn't
///   guaranteed, and when it loses the race the follower falls back to the
///   overlay [Stack]'s default `topStart` alignment — the panel pins to the
///   screen's top-left instead of its trigger. The measurement happens in
///   [OverlayPortal]'s `overlayChildBuilder` — a build-phase callback — and
///   only ever reads a target that was laid out in a *prior* frame (it's
///   already on screen and tappable before the menu can open), so there's no
///   same-frame ordering to race in the first place.
/// * **Only one menu is open at a time, and any outside tap closes it.** The
///   design enforces this with a global pointer-down listener and a scroll
///   handler; here each anchor owns a full-screen transparent barrier beneath
///   its panel, and screens close on scroll via [PV2Page]'s `onScroll`.

// ---------------------------------------------------------------------------
// Anchor
// ---------------------------------------------------------------------------

/// Anchors an overlay [menu] to a [child] trigger.
///
/// The caller owns the open/closed state — these menus are mutually exclusive
/// per screen, so a single enum on the screen is simpler to reason about than
/// state distributed across anchors.
class PV2MenuAnchor extends StatefulWidget {
  const PV2MenuAnchor({
    super.key,
    required this.open,
    required this.onDismiss,
    required this.menu,
    required this.child,
    this.targetAnchor = Alignment.bottomRight,
    this.followerAnchor = Alignment.topRight,
    this.offset = const Offset(0, 8),
    this.menuWidth,
  });

  /// The panel's width, when the caller knows it.
  ///
  /// Required for a HORIZONTALLY CENTRED [followerAnchor] (x == 0): the
  /// corner-pinning below can only place a left or a right edge, so without
  /// a width a centred anchor silently degraded to left-pinned — the panel
  /// grew rightward out of the trigger's middle and, near the screen edge,
  /// straight off it. With a width the panel is centred properly AND
  /// clamped into the viewport.
  final double? menuWidth;

  final bool open;
  final VoidCallback onDismiss;

  /// The panel. Typically a [PV2MenuPanel].
  final Widget menu;

  /// The trigger the panel is positioned against.
  final Widget child;

  final Alignment targetAnchor;
  final Alignment followerAnchor;
  final Offset offset;

  @override
  State<PV2MenuAnchor> createState() => _PV2MenuAnchorState();
}

class _PV2MenuAnchorState extends State<PV2MenuAnchor> {
  final _targetKey = GlobalKey();
  final _portal = OverlayPortalController();

  @override
  void initState() {
    super.initState();
    if (widget.open) _portal.show();
  }

  @override
  void didUpdateWidget(PV2MenuAnchor old) {
    super.didUpdateWidget(old);
    if (widget.open == old.open) return;
    // Deferred: open/close is driven by the parent's build, and the portal
    // mutates the Overlay, which cannot happen during a build phase.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.open ? _portal.show() : _portal.hide();
    });
  }

  @override
  Widget build(BuildContext context) {
    return OverlayPortal(
      controller: _portal,
      // A build-phase callback, not a layout-phase one — safe to read the
      // target's `RenderBox` here. (An earlier version of this measured the
      // target from a `SingleChildLayoutDelegate.getPositionForChild`, which
      // runs inside another render object's `performLayout`; Flutter asserts
      // on exactly that — `RenderBox.size`/`localToGlobal` may only be read
      // during layout by an object's own parent, with `parentUsesSize: true`.
      // Reading it here instead works precisely because the target has
      // already been laid out in a *prior* frame — it's on screen, visible,
      // and tappable before this menu can ever open — so there's no
      // same-frame ordering to get right.)
      overlayChildBuilder: (context) {
        Offset anchor = widget.offset;
        final targetBox = _targetKey.currentContext?.findRenderObject();
        if (targetBox is RenderBox && targetBox.attached && targetBox.hasSize) {
          final targetRect = targetBox.localToGlobal(Offset.zero) & targetBox.size;
          anchor = widget.targetAnchor.withinRect(targetRect) + widget.offset;
        }
        final overlaySize = MediaQuery.sizeOf(context);

        return Stack(
          children: [
            // Barrier first, so it sits beneath the panel: taps on the panel
            // reach the panel, taps anywhere else dismiss.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onDismiss,
              ),
            ),
            // Pinned by the corner `followerAnchor` names, not by a measured
            // child size: specifying `right`+`bottom` (say) makes Stack place
            // the menu's bottom-right corner at that inset and size the menu
            // to its own content — the same effect as the old anchor math,
            // without ever needing the menu's size before it's laid out.
            // Every caller in this file anchors by an exact corner (-1/1 on
            // each axis); `<= 0` here just resolves the corner cleanly.
            Positioned(
              left: _left(anchor, overlaySize),
              right: _right(anchor, overlaySize),
              top: widget.followerAnchor.y <= 0 ? anchor.dy : null,
              bottom: widget.followerAnchor.y > 0 ? overlaySize.height - anchor.dy : null,
              child: widget.menu,
            ),
          ],
        );
      },
      // Keyed so the builder above can find this element's RenderBox
      // directly — see the race this replaces in the class doc.
      child: KeyedSubtree(key: _targetKey, child: widget.child),
    );
  }

  /// Horizontal edge insets for the panel.
  ///
  /// A corner anchor (x == -1 or 1) pins that edge, as before. A CENTRED
  /// anchor (x == 0) needs [PV2MenuAnchor.menuWidth] to be centred at all —
  /// and once centred it is clamped to [_kEdgeMargin] of either screen
  /// edge, so a trigger near the edge no longer throws half the panel off
  /// screen. Without a width, a centred anchor falls back to the old
  /// left-pinned behaviour rather than guessing.
  static const _kEdgeMargin = 8.0;

  double? _left(Offset anchor, Size overlay) {
    final x = widget.followerAnchor.x;
    final width = widget.menuWidth;
    if (x == 0 && width != null) {
      final centred = anchor.dx - width / 2;
      final maxLeft = overlay.width - width - _kEdgeMargin;
      return maxLeft <= _kEdgeMargin
          ? _kEdgeMargin
          : centred.clamp(_kEdgeMargin, maxLeft);
    }
    return x <= 0 ? anchor.dx : null;
  }

  double? _right(Offset anchor, Size overlay) {
    final x = widget.followerAnchor.x;
    if (x == 0 && widget.menuWidth != null) return null;
    return x > 0 ? overlay.width - anchor.dx : null;
  }
}

// ---------------------------------------------------------------------------
// Panel
// ---------------------------------------------------------------------------

/// The floating panel a menu's items sit in.
class PV2MenuPanel extends StatelessWidget {
  const PV2MenuPanel({
    super.key,
    required this.width,
    required this.children,
    this.radius = 16,
    this.padding = 5,
    this.fill = PV2.menuFill,
    this.border = PV2.menuBorder,
    this.blur = 22,
    this.shadow = const BoxShadow(
      color: Color(0xD9000000),
      offset: Offset(0, 14),
      blurRadius: 34,
      spreadRadius: -10,
    ),
  });

  final double width;
  final List<Widget> children;
  final double radius;
  final double padding;
  final Color fill;
  final Color border;
  final double blur;
  final BoxShadow shadow;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: width,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          boxShadow: [shadow],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: blur / 2, sigmaY: blur / 2),
            child: Container(
              padding: EdgeInsets.all(padding),
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(radius),
                border: Border.all(color: border),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Items
// ---------------------------------------------------------------------------

/// One tappable row in a menu.
///
/// [destructive] switches the icon, label and pressed-state tint to the danger
/// colour — the design uses it for Delete Post, Delete Account, Remove Photo,
/// Exit Group and Destroy Group, and never as emphasis for anything safe.
class PV2MenuItem extends StatelessWidget {
  const PV2MenuItem({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.destructive = false,
    this.iconSize = 16,
    this.fontSize = 13.5,
    this.gap = 10,
    this.radius = 12,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    this.labelColor,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool destructive;
  final double iconSize;
  final double fontSize;
  final double gap;
  final double radius;
  final EdgeInsetsGeometry padding;
  final Color? labelColor;

  /// Trailing affordance pinned to the right — the ADMIN badge on Destroy
  /// Group is the only use in the design.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final fg = destructive
        ? PV2.danger
        : (labelColor ?? Colors.white.withValues(alpha: 0.85));
    final iconColor =
        destructive ? PV2.danger : Colors.white.withValues(alpha: 0.75);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        highlightColor: destructive
            ? PV2.danger.withValues(alpha: 0.1)
            : Colors.white.withValues(alpha: 0.06),
        splashColor: destructive
            ? PV2.danger.withValues(alpha: 0.12)
            : Colors.white.withValues(alpha: 0.07),
        child: Padding(
          padding: padding,
          child: Row(
            children: [
              Icon(icon, size: iconSize, color: iconColor),
              SizedBox(width: gap),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PV2.body(
                    size: fontSize,
                    weight: FontWeight.w600,
                    color: fg,
                  ),
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 6), trailing!],
            ],
          ),
        ),
      ),
    );
  }
}

/// A menu row whose glyph sits in an accent-tinted tile — the creation FAB's
/// three actions, which are destinations rather than settings and are weighted
/// accordingly.
class PV2MenuActionItem extends StatelessWidget {
  const PV2MenuActionItem({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        highlightColor: Colors.white.withValues(alpha: 0.07),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: PV2.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 17, color: PV2.accent),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PV2.body(size: 14, weight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The hairline between a menu's safe actions and its destructive ones.
class PV2MenuDivider extends StatelessWidget {
  const PV2MenuDivider({super.key, this.inset = 5});

  final double inset;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      margin: EdgeInsets.symmetric(vertical: inset),
      color: PV2.menuDivider,
    );
  }
}

/// A small caps heading grouping a menu's items ("Account").
class PV2MenuLabel extends StatelessWidget {
  const PV2MenuLabel({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
      child: Text(
        label.toUpperCase(),
        style: PV2.caps(size: 9, tracking: 0.1, color: PV2.inkStamp),
      ),
    );
  }
}

/// The ADMIN pill on Destroy Group.
class PV2AdminBadge extends StatelessWidget {
  const PV2AdminBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 16,
      // Tighter than the design's 6px: at the panel's 190px width the badge
      // and a full "Destroy Group" label do not both fit, and the label
      // truncating to "Destroy Gr…" loses more than a padding pixel does.
      padding: const EdgeInsets.symmetric(horizontal: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: PV2.danger.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'ADMIN',
        style: PV2.caps(
          size: 8,
          tracking: 0.06,
          color: PV2.danger,
          weight: FontWeight.w800,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Creation FAB
// ---------------------------------------------------------------------------

/// The floating creation button on the self profile, and its three-action menu.
///
/// The plus glyph rotates to an X while the menu is open, so the button doubles
/// as the close affordance.
class PV2CreateFab extends StatelessWidget {
  const PV2CreateFab({
    super.key,
    required this.open,
    required this.onToggle,
    required this.onAddMoment,
    required this.onAddGroupPost,
  });

  final bool open;
  final VoidCallback onToggle;
  final VoidCallback onAddMoment;
  final VoidCallback onAddGroupPost;

  @override
  Widget build(BuildContext context) {
    return PV2MenuAnchor(
      open: open,
      onDismiss: onToggle,
      targetAnchor: Alignment.topRight,
      followerAnchor: Alignment.bottomRight,
      offset: const Offset(0, -6),
      menu: PV2MenuPanel(
        width: 196,
        radius: 18,
        border: PV2.accent.withValues(alpha: 0.22),
        blur: 24,
        shadow: const BoxShadow(
          color: Color(0xE6000000),
          offset: Offset(0, 18),
          blurRadius: 42,
          spreadRadius: -14,
        ),
        children: [
          if (kMomentsEnabled)
            PV2MenuActionItem(
              icon: Icons.shield_outlined,
              label: 'Add Moment',
              onTap: onAddMoment,
            ),
          PV2MenuActionItem(
            icon: Icons.photo_camera_outlined,
            label: 'Add Group Post',
            onTap: onAddGroupPost,
          ),
        ],
      ),
      // With Moments hidden the menu would hold a single item, so "+" goes
      // straight to Add Group Post instead of opening a one-row menu.
      child: GestureDetector(
        onTap: kMomentsEnabled ? onToggle : onAddGroupPost,
        child: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            gradient: PV2.accentButton,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: PV2.accent.withValues(alpha: 0.45),
                offset: const Offset(0, 6),
                blurRadius: 22,
              ),
            ],
          ),
          child: AnimatedRotation(
            turns: open ? 0.125 : 0, // 45°
            duration: const Duration(milliseconds: 200),
            child: const Icon(Icons.add_rounded, size: 26, color: PV2.onAccent),
          ),
        ),
      ),
    );
  }
}
