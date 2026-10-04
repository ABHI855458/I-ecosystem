import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';
import '../../core/glass.dart' show showGlassToast;
import '../profile_v2/profile_v2_tokens.dart';
import '../profile_v2/profile_v2_widgets.dart';
import 'legal_content.dart';
import 'settings_scaffold.dart';

// ---------------------------------------------------------------------------
// LegalScreen — one scrollable screen used for both Privacy Policy and EULA
// (LegalScreen.privacyPolicy() / LegalScreen.eula()).
//
// Shows BOTH the hosted document and the in-app copy, deliberately:
//   - The button opens the canonical hosted page
//     (AppStrings.privacyPolicyUrl / eulaUrl) — the same URL the Play
//     Console Data Safety form and the signup flow point at, so a reader
//     can always reach the authoritative version, and can share or archive
//     a real link rather than a screenshot of app text.
//   - The text below it is the offline mirror from legal_content.dart, so
//     the policy is still readable with no connectivity and without
//     leaving the app. Previously this was the ONLY copy, which meant the
//     app had no link to the hosted version anywhere.
// Both are kept in sync by hand; see legal_content.dart's own header.
// ---------------------------------------------------------------------------

class LegalScreen extends StatelessWidget {
  const LegalScreen({
    super.key,
    required this.title,
    required this.body,
    required this.hostedUrl,
  });

  factory LegalScreen.privacyPolicy() => const LegalScreen(
        title: 'Privacy Policy',
        body: kPrivacyPolicyBody,
        hostedUrl: AppStrings.privacyPolicyUrl,
      );

  factory LegalScreen.eula() => const LegalScreen(
        title: 'EULA',
        body: kEulaBody,
        hostedUrl: AppStrings.eulaUrl,
      );

  final String title;
  final String body;

  /// The canonical hosted version of this document.
  final String hostedUrl;

  @override
  Widget build(BuildContext context) {
    return SettingsScaffold(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NeuCard(
            radius: 16,
            shadows: PV2.raisedSm,
            border: PV2.hairlinePanel,
            onTap: () => _openHosted(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.open_in_new_rounded, size: 17, color: PV2.accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'View online',
                          style: PV2.body(size: 13.5, weight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Opens the current published version',
                          style: PV2.body(size: 11.5, color: PV2.inkSub),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          SelectableText(
            body,
            style: PV2.body(size: 13.5, color: PV2.inkBio, height: 1.6),
          ),
        ],
      ),
    );
  }

  /// Fails loudly rather than silently: a legal document the user asked to
  /// read and didn't get is worth a visible message, not a dead tap.
  Future<void> _openHosted(BuildContext context) async {
    final uri = Uri.parse(hostedUrl);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) {
        showGlassToast(context, "Couldn't open the browser.", isError: true);
      }
    } catch (_) {
      if (context.mounted) {
        showGlassToast(context, "Couldn't open the browser.", isError: true);
      }
    }
  }
}
