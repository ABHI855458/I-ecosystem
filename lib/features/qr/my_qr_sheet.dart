import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/constants.dart' show AppStrings;
import '../../core/glass.dart' show showGlassToast;
import '../../core/supabase_config.dart';
import 'qr_payload.dart';

/// Bottom sheet showing a scannable QR — one shared shell for both "My QR"
/// entry points (a user's own Duo slot, a group's join code). Purely
/// presentational: encoding is [QrPayload]'s job, decoding + routing is
/// qr_scanner_screen.dart's.
void showMyQrSheet(
  BuildContext context, {
  required QrPayload payload,
  required String title,
  required String subtitle,
}) {
  HapticFeedback.lightImpact();
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) =>
        _MyQrSheet(payload: payload, title: title, subtitle: subtitle),
  );
}

/// A group's banner QR. Fetches the members-only join code first
/// (get_group_join_code) so the QR works for private groups too.
/// My secret Duo code (get_my_duo_code) — what makes a Duo QR proof that
/// the scanner actually saw it. Null when it can't be fetched (offline).
Future<String?> fetchMyDuoCode() async {
  try {
    final code = await supabase.rpc('get_my_duo_code');
    return code is String && code.isNotEmpty ? code : null;
  } on Object catch (e) {
    debugPrint('[fetchMyDuoCode] failed: $e');
    return null;
  }
}

Future<void> showGroupQrSheet(
  BuildContext context, {
  required String groupId,
  required String groupName,
}) async {
  try {
    final code =
        await supabase.rpc(
              'get_group_join_code',
              params: {'p_group_id': groupId},
            )
            as String;
    if (!context.mounted) return;
    showMyQrSheet(
      context,
      payload: QrPayload(kind: QrPayloadKind.group, id: groupId, code: code),
      title: 'Join $groupName',
      subtitle: 'Anyone who scans this joins the group instantly.',
    );
  } on Object catch (e) {
    if (!context.mounted) return;
    showGlassToast(
      context,
      "Couldn't load the group QR — try again.",
      isError: true,
    );
    debugPrint('[showGroupQrSheet] $groupId failed: $e');
  }
}

class _MyQrSheet extends StatelessWidget {
  const _MyQrSheet({
    required this.payload,
    required this.title,
    required this.subtitle,
  });

  final QrPayload payload;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 22),
        decoration: BoxDecoration(
          gradient: _brandGradient,
          borderRadius: BorderRadius.circular(32),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 22),
              decoration: BoxDecoration(
                color: const Color(0x66FFFFFF),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Instagram-style white card: the code, then the name in brand
            // gradient text underneath.
            Container(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 30,
                    offset: Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PingQrCode(data: payload.encode(), size: 230),
                  const SizedBox(height: 18),
                  ShaderMask(
                    blendMode: BlendMode.srcIn,
                    shaderCallback: _qrGradient.createShader,
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      color: const Color(0xFF6B6C78),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.asset(_logoAsset, width: 22, height: 22),
                ),
                const SizedBox(width: 8),
                Text(
                  AppStrings.appName,
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Open ${AppStrings.appName} → Camera → Scan',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: const Color(0xCCFFFFFF),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const _logoAsset = 'assets/brand/logo.png';

/// The logo's own gradient (sampled from assets/brand/logo.png).
const _brandGradient = LinearGradient(
  begin: Alignment.bottomLeft,
  end: Alignment.topRight,
  colors: [Color(0xFFD20097), Color(0xFF424DB9), Color(0xFF0DD8D9)],
);

/// Only the DARK end of the brand gradient: a scanner needs strong contrast
/// against white, and the logo's pale cyan corner would read as background.
const _qrGradient = LinearGradient(
  begin: Alignment.bottomLeft,
  end: Alignment.topRight,
  colors: [Color(0xFFD20097), Color(0xFF6A2BB0), Color(0xFF3A46B5)],
);

/// The branded QR itself: brand-gradient rounded dots with the app logo in
/// the middle, like Instagram's. Error correction is H (30% recoverable),
/// and the logo covers ~5% of the area, so it scans reliably.
class PingQrCode extends StatelessWidget {
  const PingQrCode({super.key, required this.data, this.size = 230});

  final String data;
  final double size;

  @override
  Widget build(BuildContext context) {
    final logo = size * 0.22;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: _qrGradient.createShader,
            child: QrImageView(
              data: data,
              version: QrVersions.auto,
              errorCorrectionLevel: QrErrorCorrectLevel.H,
              size: size,
              padding: EdgeInsets.zero,
              // Square eyes on purpose: circular finder patterns failed to
              // decode at all in testing (OpenCV); round DOTS are fine.
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: Colors.black,
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.circle,
                color: Colors.black,
              ),
            ),
          ),
          Container(
            width: logo + 10,
            height: logo + 10,
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular((logo + 10) * 0.28),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(logo * 0.24),
              child: Image.asset(_logoAsset, fit: BoxFit.cover),
            ),
          ),
        ],
      ),
    );
  }
}
