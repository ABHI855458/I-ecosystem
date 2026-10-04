// ---------------------------------------------------------------------------
// QR payload encode/decode for Ping's two "scan to join" flows (the 'palster:' prefix below predates the rename to Ping and stays so already-shared codes keep scanning).
//
// Deliberately a plain in-app string, not a URI scheme or a Universal/App
// Link — this is scanned by Palster's OWN camera (see qr_scanner_screen.dart)
// and parsed straight from the decoded text, so there is nothing for the OS
// to resolve. Opening a Palster QR code with some OTHER app (Google Lens,
// the stock camera) still just shows this plain string; it does not launch
// Palster and does not fall through to the Play Store. That "scanned by any
// camera, opens the app if installed, else the store" behaviour needs real
// Android App Links / iOS Universal Links, which need a hosted domain
// serving assetlinks.json / apple-app-site-association — deliberately out
// of scope until that domain decision is made. This file is the interim,
// fully-working "instant QR scanning" the in-app scanner delivers today.
// ---------------------------------------------------------------------------

enum QrPayloadKind { duo, group }

class QrPayload {
  const QrPayload({required this.kind, required this.id, this.code});

  final QrPayloadKind kind;

  /// A user's id for [QrPayloadKind.duo] (whose Duo slot this code
  /// represents); a group's id for [QrPayloadKind.group].
  final String id;

  /// A group's secret join code (get_group_join_code, members-only). Lets a
  /// PRIVATE group's QR work: the id alone isn't secret, id + code is.
  /// Null only for older, id-only public-group codes.
  final String? code;

  static const _duoPrefix = 'palster:duo:';
  static const _groupPrefix = 'palster:group:';

  String encode() => switch (kind) {
    // Duo codes carry the person's secret code since 2026-10-04 — the
    // server only connects a Duo when it matches (security hardening).
    QrPayloadKind.duo =>
      code == null ? '$_duoPrefix$id' : '$_duoPrefix$id:$code',
    QrPayloadKind.group =>
      code == null ? '$_groupPrefix$id' : '$_groupPrefix$id:$code',
  };

  /// Null for anything that isn't one of ours — a scanned code that turns
  /// out to be a boarding pass or a wifi QR is silently not-ours, never a
  /// crash.
  static QrPayload? tryDecode(String raw) {
    final text = raw.trim();
    if (text.startsWith(_duoPrefix)) {
      final parts = text.substring(_duoPrefix.length).split(':');
      final id = parts.first;
      final code = parts.length > 1 && parts[1].isNotEmpty ? parts[1] : null;
      return id.isEmpty
          ? null
          : QrPayload(kind: QrPayloadKind.duo, id: id, code: code);
    }
    if (text.startsWith(_groupPrefix)) {
      final parts = text.substring(_groupPrefix.length).split(':');
      final id = parts.first;
      final code = parts.length > 1 && parts[1].isNotEmpty ? parts[1] : null;
      return id.isEmpty
          ? null
          : QrPayload(kind: QrPayloadKind.group, id: id, code: code);
    }
    return null;
  }
}
