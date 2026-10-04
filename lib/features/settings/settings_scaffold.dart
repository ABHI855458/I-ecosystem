import 'package:flutter/material.dart';

import '../profile_v2/profile_v2_icons.dart';
import '../profile_v2/profile_v2_tokens.dart';
import '../profile_v2/profile_v2_widgets.dart';

// ---------------------------------------------------------------------------
// SettingsScaffold — shared chrome for the settings-menu destination screens
// (Edit Profile, Blocked Users, legal content, Delete Account). Mirrors
// profile_v2_create_flows.dart's private `_FlowScaffold` (same back button,
// title, and scroll-body shape) so these screens read as part of the same
// PV2 surface they're opened from, rather than a private copy per file.
// ---------------------------------------------------------------------------

class SettingsScaffold extends StatelessWidget {
  const SettingsScaffold({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PV2.page,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: PV2.columnWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  child: Row(
                    children: [
                      NeuWell(
                        width: 38,
                        height: 38,
                        circle: true,
                        shadows: PV2.insetStd,
                        border: PV2.hairlinePanel,
                        color: PV2.raised,
                        onTap: () => Navigator.of(context).maybePop(),
                        child: PV2Icons.back(22, Colors.white),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: PV2.display(size: 20),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    child: child,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A card wrapping a labeled field — mirrors `_InputCard`/`_FieldLabel` from
/// profile_v2_create_flows.dart.
class SettingsInputCard extends StatelessWidget {
  const SettingsInputCard({super.key, required this.label, required this.field});

  final String label;
  final Widget field;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: PV2.raised,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: PV2.caps(size: 11, tracking: 0.08, color: Colors.white.withValues(alpha: 0.38)),
          ),
          const SizedBox(height: 8),
          field,
        ],
      ),
    );
  }
}

/// The full-width commit button, in its enabled or not-yet state — mirrors
/// `_CommitButton` from profile_v2_create_flows.dart.
class SettingsCommitButton extends StatelessWidget {
  const SettingsCommitButton({
    super.key,
    required this.label,
    required this.enabled,
    this.onTap,
    this.destructive = false,
    this.loading = false,
  });

  final String label;
  final bool enabled;
  final VoidCallback? onTap;
  final bool destructive;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled && !loading ? onTap : null,
        borderRadius: BorderRadius.circular(25),
        child: Container(
          height: 50,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: enabled && !destructive ? PV2.accentButton : null,
            color: !enabled
                ? PV2.disabledFill
                : destructive
                    ? PV2.danger
                    : null,
            borderRadius: BorderRadius.circular(25),
          ),
          child: loading
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: enabled ? PV2.onAccent : PV2.disabledInk,
                  ),
                )
              : Text(
                  label,
                  style: PV2.body(
                    size: 16,
                    weight: FontWeight.w800,
                    color: enabled ? (destructive ? Colors.white : PV2.onAccent) : PV2.disabledInk,
                  ),
                ),
        ),
      ),
    );
  }
}
