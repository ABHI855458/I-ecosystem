import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants.dart';
import '../../core/supabase_config.dart';
import '../../features/qr/my_qr_sheet.dart' show PingQrCode, fetchMyDuoCode;
import '../../features/qr/qr_payload.dart';
import '../../features/qr/qr_scanner_screen.dart';
import '../../main_shell.dart';
import '../../services/block_service.dart';
import '../../services/current_user_service.dart';
import '../../services/group_service.dart';
import '../../services/us_album_service.dart';

/// Duo requests a user must have sent (or accepted) before reaching the feed.
// 3 -> 2 for launch (explicit request: "us album request reduce it to 2").
const kMinOnboardingDuos = 2;

/// The Duo requirement for one person: [kMinOnboardingDuos], capped at how
/// many people they could actually send to (already sent + still
/// available). A student whose clubs hold fewer than 3 other people is
/// never locked out; one with plenty still has to send 3.
int onboardingDuosRequired({
  required int sentCount,
  required int availableUnsent,
}) {
  final possible = sentCount + availableUnsent;
  return possible < kMinOnboardingDuos ? possible : kMinOnboardingDuos;
}

/// Everyone the Duo step can suggest: other active, unblocked members of
/// [communityIds] (the caller's clubs when null). Shared by the Duo screen
/// and AuthGate so both judge the requirement against the same pool.
Future<List<Map<String, dynamic>>> loadDuoCandidates(
  List<String>? communityIds,
) async {
  final myAuthId = supabase.auth.currentUser!.id;
  communityIds ??= [
    for (final r
        in await supabase
                .from('community_members')
                .select('community_id')
                .eq('user_id', myAuthId)
            as List)
      (r as Map)['community_id'] as String,
  ];
  if (communityIds.isEmpty) return [];
  final memberRows = await supabase
      .from('community_members')
      .select('user_id')
      .inFilter('community_id', communityIds);
  final authIds = {
    for (final r in memberRows as List) (r as Map)['user_id'] as String,
  }..remove(myAuthId);
  if (authIds.isEmpty) return [];
  final blocked = await BlockService.instance.blockedUserIds();
  final userRows = await supabase
      .from('users')
      .select('id, name, username, profile_photo_url')
      .inFilter('auth_id', authIds.toList())
      .isFilter('deleted_at', null);
  return [
    for (final u in (userRows as List).cast<Map<String, dynamic>>())
      if (!blocked.contains(u['id'])) u,
  ]..sort(
    (a, b) => ((a['name'] as String?) ?? '').toLowerCase().compareTo(
      ((b['name'] as String?) ?? '').toLowerCase(),
    ),
  );
}

// ---------------------------------------------------------------------------
// OnboardingDuoScreen — last mandatory step before the feed (explicit
// request: "make it compulsory to send duo album requests to minimum 3
// people ... and show them their duo qr code there"). New users reach it
// from OnboardingPinPeopleScreen; returning users with fewer than
// [kMinOnboardingDuos] are routed here by AuthGate. No skip: Continue unlocks
// only once DuoService.fetchDuoPartnerIds() reaches the minimum, and it is
// re-read from the server so a scan (QrScannerScreen) counts too.
// ---------------------------------------------------------------------------

class OnboardingDuoScreen extends StatefulWidget {
  /// Communities to draw suggested people from. Null = look up the caller's
  /// own (the AuthGate path, where no fresh club pick is in hand).
  const OnboardingDuoScreen({
    super.key,
    this.communityIds,
    this.optional = false,
  });

  final List<String>? communityIds;

  /// The post-first-post ask (see [maybeAskForFirstDuo]): one Duo, a Skip
  /// button, and finishing just closes the screen instead of replacing the
  /// whole stack with MainShell.
  final bool optional;

  @override
  State<OnboardingDuoScreen> createState() => _OnboardingDuoScreenState();
}

class _OnboardingDuoScreenState extends State<OnboardingDuoScreen> {
  String? _myId;
  String? _myDuoCode;
  bool _loading = true;
  bool _loadError = false;
  List<Map<String, dynamic>> _suggested = const [];
  List<Map<String, dynamic>>? _searchResults;
  Set<String> _sent = const {};
  final Set<String> _pending = {};
  final _search = TextEditingController();
  Timer? _debounce;

  /// How many Duo requests THIS person must send: [kMinOnboardingDuos], or
  /// fewer when that many people don't exist yet. On launch day a student's
  /// clubs may hold nobody (or one person) to send to, and a fixed "send 3"
  /// with no way past locked them out of the app entirely. Same rule the
  /// Friends step uses for an empty pool. See [onboardingDuosRequired].
  int get _required {
    final n = onboardingDuosRequired(
      sentCount: _sent.length,
      availableUnsent: _suggested
          .where((p) => !_sent.contains(p['id'] as String?))
          .length,
    );
    return widget.optional ? (n > 1 ? 1 : n) : n;
  }

  bool get _done => _sent.length >= _required;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final myId = await CurrentUserService.instance.resolveId();
      final duoCode = await fetchMyDuoCode();
      final people = await loadDuoCandidates(widget.communityIds);
      final sent = await DuoService.instance.fetchDuoPartnerIds();
      if (!mounted) return;
      setState(() {
        _myId = myId;
        _myDuoCode = duoCode;
        _suggested = people;
        _sent = sent;
        _loading = false;
        _loadError = false;
      });
    } catch (e, st) {
      debugPrint('[OnboardingDuoScreen._load] failed: $e\n$st');
      if (!mounted) return;
      setState(() {
        _loadError = true;
        _loading = false;
      });
    }
  }

  Future<void> _refreshSent() async {
    try {
      final sent = await DuoService.instance.fetchDuoPartnerIds();
      if (mounted) setState(() => _sent = sent);
    } catch (_) {}
  }

  void _onSearchChanged(String q) {
    _debounce?.cancel();
    if (q.trim().isEmpty) {
      setState(() => _searchResults = null);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final rows = await GroupService.instance.searchUsers(q);
        if (mounted && _search.text == q) setState(() => _searchResults = rows);
      } catch (_) {
        if (mounted) setState(() => _searchResults = const []);
      }
    });
  }

  Future<void> _sendDuo(String userId) async {
    if (_pending.contains(userId) || _sent.contains(userId)) return;
    setState(() => _pending.add(userId));
    HapticFeedback.selectionClick();
    try {
      await DuoService.instance.sendOrAccept(userId);
      if (mounted) setState(() => _sent = {..._sent, userId});
    } catch (e) {
      debugPrint('[OnboardingDuoScreen._sendDuo] $userId failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Couldn't send that Duo request — try again."),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _pending.remove(userId));
    }
  }

  Future<void> _scan() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const QrScannerScreen()));
    await _refreshSent();
  }

  void _finish() {
    if (!_done) return;
    if (widget.optional) {
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const MainShell()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final remaining = (_required - _sent.length).clamp(0, kMinOnboardingDuos);
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                    sliver: SliverList.list(
                      children: [
                        if (widget.optional)
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: Text(
                                'Skip for now',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ),
                          ),
                        Text(
                          widget.optional
                              ? 'Start a Duo 💞'
                              : 'Start Your Duos',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'A Duo is a shared album between you and one friend. '
                          '${_required == 0
                              ? 'No one from your clubs is here yet — you can add Duos later from anyone\'s profile.'
                              : widget.optional
                              ? 'Pick one person to share it with — photos start once they accept.'
                              : 'Send Duo requests to at least $_required ${_required == 1 ? 'person' : 'people'} to get in.'}',
                          style: GoogleFonts.inter(
                            fontSize: 13.5,
                            color: AppColors.textMuted,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 18),
                        _qrCard(),
                        const SizedBox(height: 22),
                        _progress(),
                        const SizedBox(height: 14),
                        _searchField(),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                  ..._peopleSlivers(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _done ? _finish : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.onPrimary,
                    disabledBackgroundColor: AppColors.glassSurface,
                    disabledForegroundColor: AppColors.textMuted,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    _done ? 'Continue' : 'Send $remaining more to continue',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _qrCard() {
    final myId = _myId;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.bottomLeft,
          end: Alignment.topRight,
          colors: [Color(0xFFD20097), Color(0xFF424DB9), Color(0xFF0DD8D9)],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
            ),
            child: myId == null || _myDuoCode == null
                ? const SizedBox.square(dimension: 124)
                : PingQrCode(
                    data: QrPayload(
                      kind: QrPayloadKind.duo,
                      id: myId,
                      code: _myDuoCode,
                    ).encode(),
                    size: 124,
                  ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your Duo QR',
                  style: GoogleFonts.inter(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Friends who scan this connect with you in Duo instantly.',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: const Color(0xDDFFFFFF),
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: _scan,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0x33FFFFFF),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0x55FFFFFF)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.qr_code_scanner_rounded,
                          size: 16,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          "Scan a friend's",
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _progress() {
    return Row(
      children: [
        for (var i = 0; i < _required; i++) ...[
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              height: 6,
              decoration: BoxDecoration(
                color: i < _sent.length
                    ? AppColors.neonCyan
                    : AppColors.glassSurface,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          if (i < _required - 1) const SizedBox(width: 6),
        ],
        const SizedBox(width: 12),
        Text(
          '${_sent.length}/$_required sent',
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.textMuted,
          ),
        ),
      ],
    );
  }

  Widget _searchField() {
    return TextField(
      controller: _search,
      onChanged: _onSearchChanged,
      style: GoogleFonts.inter(fontSize: 14, color: AppColors.textPrimary),
      decoration: InputDecoration(
        hintText: 'Search anyone on ${AppStrings.appName}',
        hintStyle: GoogleFonts.inter(fontSize: 14, color: AppColors.textMuted),
        prefixIcon: const Icon(
          Icons.search_rounded,
          color: AppColors.textMuted,
          size: 20,
        ),
        filled: true,
        fillColor: AppColors.cardSurface,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.border),
        ),
      ),
    );
  }

  List<Widget> _peopleSlivers() {
    Widget centered(Widget child) => SliverFillRemaining(
      hasScrollBody: false,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(child: child),
      ),
    );

    if (_loading) {
      return [
        centered(const CircularProgressIndicator(color: AppColors.primary)),
      ];
    }
    if (_loadError) {
      return [
        centered(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Couldn't load people.",
                style: GoogleFonts.inter(
                  color: AppColors.textMuted,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () {
                  setState(() => _loading = true);
                  _load();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ];
    }
    final people = _searchResults ?? _suggested;
    if (people.isEmpty) {
      return [
        centered(
          Text(
            _searchResults != null
                ? 'No one found by that name.'
                : 'Search for friends by name, or scan their Duo QR.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 14),
          ),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
        sliver: SliverToBoxAdapter(
          child: Text(
            _searchResults != null ? 'RESULTS' : 'PEOPLE IN YOUR CLUBS',
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.textMuted,
              letterSpacing: 0.6,
            ),
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
        sliver: SliverList.separated(
          itemCount: people.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, i) => _personRow(people[i]),
        ),
      ),
    ];
  }

  Widget _personRow(Map<String, dynamic> person) {
    final id = person['id'] as String;
    final name = (person['name'] as String?)?.trim().isNotEmpty == true
        ? person['name'] as String
        : 'someone';
    final username = person['username'] as String?;
    final photoUrl = person['profile_photo_url'] as String?;
    final sent = _sent.contains(id);
    final pending = _pending.contains(id);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: sent ? AppColors.neonCyan : AppColors.border),
      ),
      child: Row(
        children: [
          ClipOval(
            child: photoUrl == null
                ? Container(width: 40, height: 40, color: AppColors.background)
                : Image.network(
                    photoUrl,
                    width: 40,
                    height: 40,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      width: 40,
                      height: 40,
                      color: AppColors.background,
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (username != null && username.isNotEmpty)
                  Text(
                    '@$username',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: sent || pending ? null : () => _sendDuo(id),
            style: OutlinedButton.styleFrom(
              backgroundColor: sent
                  ? AppColors.neonCyan.withValues(alpha: 0.14)
                  : AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              side: BorderSide(
                color: sent ? AppColors.neonCyan : AppColors.primary,
              ),
              minimumSize: Size.zero,
            ),
            icon: pending
                ? const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.onPrimary,
                    ),
                  )
                : Icon(
                    sent ? Icons.check_rounded : Icons.favorite_rounded,
                    size: 14,
                    color: sent ? AppColors.neonCyan : AppColors.onPrimary,
                  ),
            label: Text(
              sent ? 'Sent' : 'Send Duo',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: sent ? AppColors.neonCyan : AppColors.onPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const _kAskedFirstDuoKey = 'asked_first_duo_v1';

/// After someone's FIRST post, ask once (skippable) for a single Duo —
/// replaces the old "send 2–3 Duos before you can enter" gate. Does nothing
/// if they already have a Duo or were already asked on this device.
Future<void> maybeAskForFirstDuo(NavigatorState? nav) async {
  if (nav == null) return;
  try {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kAskedFirstDuoKey) ?? false) return;
    final partners = await DuoService.instance.fetchDuoPartnerIds();
    await prefs.setBool(_kAskedFirstDuoKey, true);
    if (partners.isNotEmpty || !nav.mounted) return;
    await nav.push(
      MaterialPageRoute<void>(
        builder: (_) => const OnboardingDuoScreen(optional: true),
      ),
    );
  } catch (_) {
    // Nice-to-have ask — never block or crash posting over it.
  }
}
