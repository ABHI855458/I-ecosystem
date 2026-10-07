import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;

import '../../core/supabase_config.dart';
import '../../core/ui/immersive_chrome.dart';
import '../../services/anon_identity.dart';
import '../../services/chat_list_service.dart';
import '../../services/community_service.dart';
import '../../services/community_streaks_service.dart';
import '../../services/current_user_service.dart';
import 'community_board/community_announcements_tab.dart';
import 'community_board/community_join_sheet.dart'
    show CommunityJoinButton, CommunityJoinPopover;
import 'community_board/community_streaks_tab.dart';
import 'community_board/community_tokens.dart';
import 'community_chat_list.dart';
import '../people/find_people_screen.dart';
import '../profile_v2/profile_v2_icons.dart';
import 'group_chat_screen.dart';

// ---------------------------------------------------------------------------
// Community tab — scope owner for the whole screen. Everything below this
// widget (chip strip, priority notices, feed, streaks leaderboard) is scoped
// to exactly ONE community at a time; this is where that selection lives,
// gets persisted (survives app restart), and drives the streaks realtime
// subscription + debounced leaderboard refetch.
//
// Originally a 1:1 port of a Claude Design mockup with a single local bool
// (`_showStreaks`) and otherwise nothing but const mock content — see git
// history / community_board/community_models.dart (now deleted) for the
// pre-rewrite shape.
// ---------------------------------------------------------------------------

const _kSelectedCommunityPrefKey = 'community_selected_id';

/// Set to a `groups.id` to open that group's CHAT as soon as the Community
/// tab is on screen — how a `group_message` notification tap lands on the
/// conversation it is about (see MainShell's 'group_chat' route). Cleared
/// by [CommunityScreen] once consumed, so it never re-fires.
final communityOpenGroupChat = ValueNotifier<String?>(null);

/// The STREAKS scoreboard tab is hidden for launch: a sparse leaderboard
/// reads as an empty app, and a public ranking demotivates everyone below
/// the top few. Personal streaks (Ping page, profile) stay. Flip to bring
/// the tab back — the code behind it is untouched.
const bool kShowCommunityScoreboard = false;

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key, this.debugShowStreaks = false});

  /// Screenshot/debug-harness only — starts on the STREAKS tab instead of
  /// ANNOUNCEMENTS. Not wired to any real navigation path.
  final bool debugShowStreaks;

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  /// Chatter (was Announcements) is the LANDING tab again — explicit
  /// reversal of an earlier ruling: "let the announcements come first[,]
  /// the streak[s second]". debugShowStreaks is kept as the screenshot
  /// harness's override; it just no longer decides the default.
  late bool _showStreaks = false;

  /// Header JOIN -> the Chatter tab's own join popover (see
  /// CommunityAnnouncementsTab.openJoin).
  final ValueNotifier<int> _openJoin = ValueNotifier(0);

  bool _communitiesLoading = true;
  List<CommunityOption> _communities = const [];
  String? _selectedCommunityId;

  bool _leaderboardLoading = true;
  String? _leaderboardError;
  CommunityLeaderboard? _leaderboard;
  RealtimeChannel? _streaksChannel;
  Timer? _debounce;

  String? _handle;
  String? _branchYear;

  /// WhatsApp-style chat list (explicit request, 2026-10-02/03) — the
  /// tab's landing view. Every community + group, newest first, PRIORITY
  /// on top. See community_chat_list.dart / ChatListService.
  List<ChatSummary> _chats = const [];
  bool _chatsLoading = true;
  String? _chatsError;

  /// The community chat currently open in place of the list (its board:
  /// priority notices + member posts + message bar). Null = the list.
  ChatSummary? _openChat;

  /// JOIN popover, shown over the list (the board has its own).
  bool _joinOpen = false;

  @override
  void initState() {
    super.initState();
    _loadCommunities();
    _loadMyProfile();
    _loadChats();
    immersiveChrome.addListener(_onImmersiveChanged);
    communityOpenGroupChat.addListener(_onOpenGroupChatRequested);
    // A tap that arrived before this screen existed.
    if (communityOpenGroupChat.value != null) {
      _onOpenGroupChatRequested();
    }
  }

  /// Consumes [communityOpenGroupChat] — opens that group's chat, loading
  /// the list first if the id isn't in it yet (a notification can land
  /// before the first fetch finishes).
  Future<void> _onOpenGroupChatRequested() async {
    final id = communityOpenGroupChat.value;
    if (id == null) return;
    communityOpenGroupChat.value = null;
    var match = _chats.where((c) => c.kind == ChatKind.group && c.id == id);
    if (match.isEmpty) {
      await _loadChats();
      if (!mounted) return;
      match = _chats.where((c) => c.kind == ChatKind.group && c.id == id);
    }
    if (match.isEmpty || !mounted) return;
    await _openChatRow(match.first);
  }

  Future<void> _loadChats() async {
    if (_chats.isEmpty) setState(() => _chatsLoading = true);
    try {
      final list = await ChatListService.instance.fetch();
      if (!mounted) return;
      setState(() {
        _chats = list;
        _chatsLoading = false;
        _chatsError = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _chatsLoading = false;
        _chatsError = "Couldn't load your chats. Pull to retry.";
      });
    }
  }

  Future<void> _openChatRow(ChatSummary c) async {
    await ChatListService.instance.markOpened(c);
    if (!mounted) return;
    if (c.kind == ChatKind.group) {
      // The group's members-only chat (its header opens the profile).
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => GroupChatScreen(chat: c)),
      );
      if (mounted) unawaited(_loadChats());
      return;
    }
    setState(() => _openChat = c);
    // A chat owns the whole screen — no tab bar inside it (explicit
    // request, 2026-10-03). MainShell drops this flag on any tab switch;
    // _onImmersiveChanged closes the chat when that happens.
    immersiveChrome.value = true;
    // Keeps the board's existing scope plumbing (selected id, persisted
    // pref, streak subscription) pointed at the chat that's open.
    unawaited(_selectCommunity(c.id));
  }

  /// The shell cleared the immersive flag (tab switch) while a chat was
  /// open — close it, so coming back lands on the list with the tab bar.
  void _onImmersiveChanged() {
    if (!immersiveChrome.value && _openChat != null && mounted) _closeChat();
  }

  void _closeChat() {
    final c = _openChat;
    setState(() => _openChat = null);
    if (immersiveChrome.value) immersiveChrome.value = false;
    // Everything read while it was open counts as seen.
    if (c != null) {
      unawaited(
        ChatListService.instance.markOpened(c).then((_) => _loadChats()),
      );
    }
  }

  @override
  void dispose() {
    immersiveChrome.removeListener(_onImmersiveChanged);
    communityOpenGroupChat.removeListener(_onOpenGroupChatRequested);
    _debounce?.cancel();
    _streaksChannel?.unsubscribe();
    _openJoin.dispose();
    super.dispose();
  }

  Future<void> _loadMyProfile() async {
    try {
      final usersId = await CurrentUserService.instance.resolveId();
      final userRow = await supabase
          .from('users')
          .select('name, anon_name, anon_name_2, active_anon_slot')
          .eq('id', usersId)
          .maybeSingle();
      final authId = supabase.auth.currentUser?.id;
      Map<String, dynamic>? profileRow;
      if (authId != null) {
        profileRow = await supabase.from('profiles').select('branch, year').eq('id', authId).maybeSingle();
      }
      if (!mounted) return;
      final anonName = activeAnonName(
        anonName: userRow?['anon_name'] as String?,
        anonName2: userRow?['anon_name_2'] as String?,
        activeAnonSlot: userRow?['active_anon_slot'] as int?,
      );
      final name = userRow?['name'] as String?;
      final branch = profileRow?['branch'] as String?;
      final year = profileRow?['year'] as int?;
      final parts = <String>[
        if (branch != null && branch.trim().isNotEmpty) branch.trim(),
        if (year != null) '$year${_ordinalSuffix(year)} year',
      ];
      setState(() {
        _handle = anonName != null && anonName.isNotEmpty ? '@$anonName' : (name ?? 'you');
        _branchYear = parts.isEmpty ? null : parts.join(' · ');
      });
    } catch (_) {
      // Header falls back to just the wordmark — not worth an error state
      // for a cosmetic subline.
    }
  }

  Future<void> _loadCommunities() async {
    setState(() => _communitiesLoading = true);
    try {
      final list = await CommunityService.instance.fetchJoinedCommunities();
      final prefs = await SharedPreferences.getInstance();
      final savedId = prefs.getString(_kSelectedCommunityPrefKey);
      String? initial;
      if (savedId != null && list.any((c) => c.id == savedId)) {
        initial = savedId;
      } else if (list.isNotEmpty) {
        initial = list.first.id;
      }
      if (!mounted) return;
      setState(() {
        _communities = list;
        _selectedCommunityId = initial;
        _communitiesLoading = false;
      });
      if (initial != null) _selectCommunity(initial, persist: initial != savedId);
    } catch (_) {
      if (!mounted) return;
      setState(() => _communitiesLoading = false);
    }
  }

  Future<void> _selectCommunity(String id, {bool persist = true}) async {
    setState(() {
      _selectedCommunityId = id;
      _leaderboardError = null;
    });
    if (persist) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kSelectedCommunityPrefKey, id);
    }
    _unsubscribeStreaks();
    unawaited(_loadLeaderboard(id));
    _subscribeStreaks(id);
  }

  Future<void> _loadLeaderboard(String id) async {
    setState(() {
      _leaderboardLoading = _leaderboard == null;
      _leaderboardError = null;
    });
    try {
      final lb = await CommunityStreaksService.instance.leaderboard(id);
      if (!mounted || _selectedCommunityId != id) return;
      setState(() {
        _leaderboard = lb;
        _leaderboardLoading = false;
      });
    } catch (_) {
      if (!mounted || _selectedCommunityId != id) return;
      setState(() {
        _leaderboardError = "Couldn't load streaks.";
        _leaderboardLoading = false;
      });
    }
  }

  /// Pull-to-refresh for the Streaks tab. Re-reads the profile header too
  /// — your own rank/handle row sits above the leaderboard and goes stale
  /// with it.
  Future<void> _refreshStreaks() async {
    final id = _selectedCommunityId;
    await Future.wait([
      _loadMyProfile(),
      if (id != null) _loadLeaderboard(id) else _loadCommunities(),
    ]);
  }

  void _subscribeStreaks(String id) {
    _streaksChannel = CommunityStreaksService.instance.subscribe(id, (_) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 600), () {
        if (mounted && _selectedCommunityId == id) _loadLeaderboard(id);
      });
    });
  }

  void _unsubscribeStreaks() {
    _debounce?.cancel();
    _streaksChannel?.unsubscribe();
    _streaksChannel = null;
  }

  /// Called by the manage sheet after a successful join/leave.
  Future<void> _onCommunitiesChanged() async {
    unawaited(_loadChats());
    try {
      final list = await CommunityService.instance.fetchJoinedCommunities();
      if (!mounted) return;
      setState(() => _communities = list);

      final stillJoined = _selectedCommunityId != null && list.any((c) => c.id == _selectedCommunityId);
      if (!stillJoined) {
        final prefs = await SharedPreferences.getInstance();
        if (list.isNotEmpty) {
          await prefs.setString(_kSelectedCommunityPrefKey, list.first.id);
          await _selectCommunity(list.first.id, persist: false);
        } else {
          await prefs.remove(_kSelectedCommunityPrefKey);
          _unsubscribeStreaks();
          setState(() {
            _selectedCommunityId = null;
            _leaderboard = null;
            _leaderboardLoading = false;
          });
        }
      } else if (_selectedCommunityId == null && list.isNotEmpty) {
        await _selectCommunity(list.first.id);
      }
    } catch (_) {
      // The chip strip itself will just show stale data until next visit —
      // not worth surfacing a toast for a background refresh.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kShowCommunityScoreboard) return _scoreboardBuild(context);
    final open = _openChat;
    return PopScope(
      // Back from an open chat returns to the list, not out of the app.
      canPop: open == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _openChat != null) _closeChat();
      },
      child: Container(
        color: CommunityColors.screenBg,
        child: DefaultTextStyle.merge(
          style: const TextStyle(decoration: TextDecoration.none),
          child: SafeArea(
            bottom: false,
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (open == null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 12, 18, 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text('Socio', style: CommunityType.wordmark),
                            ),
                            // Find people (2026-10-07: "in chat section
                            // include a search section to search people and
                            // add them or visit their profile").
                            GestureDetector(
                              key: const ValueKey('chat-find-people'),
                              behavior: HitTestBehavior.opaque,
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => const FindPeopleScreen(),
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
                                child: Icon(
                                  Icons.search_rounded,
                                  size: 24,
                                  color: CommunityColors.textPrimary,
                                ),
                              ),
                            ),
                            CommunityJoinButton(
                              onTap: () => setState(() => _joinOpen = !_joinOpen),
                            ),
                          ],
                        ),
                      )
                    else
                      _ChatHeader(chat: open, onBack: _closeChat),
                    Expanded(
                      child: open == null
                          ? CommunityChatList(
                              chats: _chats,
                              loading: _chatsLoading,
                              error: _chatsError,
                              onOpen: _openChatRow,
                              onRefresh: _loadChats,
                            )
                          : CommunityAnnouncementsTab(
                              key: ValueKey('chat:${open.id}'),
                              communityId: open.id,
                              communityName: open.name,
                              communities: _communities,
                              onSelectCommunity: (_) {},
                              onCommunitiesChanged: _onCommunitiesChanged,
                              showJoinInChips: false,
                              showChips: false,
                            ),
                    ),
                  ],
                ),
                if (open == null && _joinOpen)
                  CommunityJoinPopover(
                    onClose: () => setState(() => _joinOpen = false),
                    onChanged: _onCommunitiesChanged,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The pre-chat-list layout (chip strip + board, STREAKS tab) — only
  /// reachable with kShowCommunityScoreboard on.
  Widget _scoreboardBuild(BuildContext context) {
    final selected = _communities.where((c) => c.id == _selectedCommunityId).toList();
    final selectedName = selected.isEmpty ? null : selected.first.name;
    return Container(
      color: CommunityColors.screenBg,
      // Same inherited-underline fix already established in this codebase
      // (see anon_feed_screen.dart / anonymous_tab.dart) — some app-level
      // ancestor applies a default TextDecoration.underline that isn't part
      // of this screen's own design and must be explicitly cleared.
      child: DefaultTextStyle.merge(
        style: const TextStyle(decoration: TextDecoration.none),
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Streaks is switched off for now (kShowCommunityScoreboard),
              // so there is nothing to tab between and no streak/rank to
              // show: the header is just "Socio" + JOIN (moved up from the
              // chip row, which gets its full width back), and the lone
              // CHATTER tab label and "you are @handle" line are hidden.
              // Flipping the flag back restores the full header + tabs.
              if (kShowCommunityScoreboard) ...[
                _CommunityHeader(handle: _handle, branchYear: _branchYear, me: _leaderboard?.me, memberCount: _leaderboard?.memberCount),
                _CommunityTabsRow(
                  showStreaks: _showStreaks,
                  onSelect: (v) => setState(() => _showStreaks = v),
                ),
              ] else
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 4),
                  child: Row(
                    children: [
                      Expanded(child: Text('Socio', style: CommunityType.wordmark)),
                      CommunityJoinButton(onTap: () => _openJoin.value++),
                    ],
                  ),
                ),
              // Pinned under the tab row (not a scrolled-away ListView
              // item) so it's the first thing read the instant STREAKS
              // opens — no scroll needed. Explicit ask: this board only
              // ever moves from ANONYMOUS posts (see
              // community_streaks_service.dart's own doc — never from
              // friends/group posts), which isn't obvious from the numbers
              // alone.
              Expanded(
                child: _communitiesLoading
                    ? const Center(child: CircularProgressIndicator(strokeWidth: 2, color: CommunityColors.pink))
                    : IndexedStack(
                        index: _showStreaks && kShowCommunityScoreboard ? 1 : 0,
                        children: [
                          CommunityAnnouncementsTab(
                            communityId: _selectedCommunityId,
                            communityName: selectedName,
                            communities: _communities,
                            onSelectCommunity: (id) => _selectCommunity(id),
                            onCommunitiesChanged: _onCommunitiesChanged,
                            openJoin: _openJoin,
                            showJoinInChips: kShowCommunityScoreboard,
                          ),
                          // Pull-to-refresh, matching the Announcements
                          // tab's own RefreshIndicator — streaks move
                          // whenever anyone in the community posts, and
                          // realtime can miss an event if the socket
                          // dropped while the tab was backgrounded.
                          RefreshIndicator(
                            onRefresh: _refreshStreaks,
                            color: CommunityColors.pink,
                            child: CommunityStreaksTab(
                              loading: _leaderboardLoading,
                              error: _leaderboardError,
                              leaderboard: _leaderboard,
                              onRetry: () {
                                final id = _selectedCommunityId;
                                if (id != null) _loadLeaderboard(id);
                              },
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Top bar of an open community chat — WhatsApp-style: back, avatar, name,
/// member count.
class _ChatHeader extends StatelessWidget {
  const _ChatHeader({required this.chat, required this.onBack});
  final ChatSummary chat;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final url = chat.iconUrl;
    final initial = chat.name.isEmpty ? '?' : chat.name[0].toUpperCase();
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 6, 18, 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: CommunityColors.tabDivider)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 20,
              color: CommunityColors.textPrimary,
            ),
          ),
          CircleAvatar(
            radius: 19,
            backgroundColor: const Color(0xFF4A2433),
            backgroundImage: url == null || url.isEmpty ? null : NetworkImage(url),
            child: url == null || url.isEmpty
                ? Text(
                    initial,
                    style: CommunityType.wordmark.copyWith(fontSize: 16),
                  )
                : null,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  chat.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CommunityType.wordmark.copyWith(fontSize: 17),
                ),
                if (chat.memberCount > 0)
                  Text(
                    '${chat.memberCount} members',
                    style: CommunityType.subline,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _ordinalSuffix(int n) {
  if (n % 100 >= 11 && n % 100 <= 13) return 'th';
  switch (n % 10) {
    case 1:
      return 'st';
    case 2:
      return 'nd';
    case 3:
      return 'rd';
    default:
      return 'th';
  }
}

class _CommunityHeader extends StatelessWidget {
  const _CommunityHeader({required this.handle, required this.branchYear, required this.me, required this.memberCount});
  final String? handle;
  final String? branchYear;
  final CommunityMe? me;
  final int? memberCount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Socio', style: CommunityType.wordmark),
                const SizedBox(height: 5),
                if (handle != null)
                  RichText(
                    text: TextSpan(style: CommunityType.subline, children: [
                      const TextSpan(text: 'you are '),
                      TextSpan(text: handle, style: CommunityType.subline.copyWith(color: CommunityColors.lime)),
                      if (branchYear != null) TextSpan(text: ' · $branchYear'),
                    ]),
                  ),
              ],
            ),
          ),
          if (me != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0x29A8E83C),
                    border: Border.all(color: const Color(0x59A8E83C)),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PV2Icons.iceFlame(11),
                      const SizedBox(width: 6),
                      Text('${me!.streak}', style: CommunityType.streakBig.copyWith(fontSize: 13, letterSpacing: -0.3)),
                      const SizedBox(width: 4),
                      Text('DAY', style: CommunityType.priorityPill.copyWith(color: CommunityColors.lime, fontSize: 9.5)),
                    ],
                  ),
                ),
                const SizedBox(height: 5),
                Text('RANK ${me!.rank} OF ${memberCount ?? me!.rank}', style: CommunityType.sectionMeta.copyWith(color: CommunityColors.textDim)),
              ],
            ),
        ],
      ),
    );
  }
}

class _CommunityTabsRow extends StatelessWidget {
  const _CommunityTabsRow({required this.showStreaks, required this.onSelect});
  final bool showStreaks;
  final ValueChanged<bool> onSelect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
      child: Row(
        children: [
          // Chatter first again — explicit reversal: "let the announcements
          // come first[,] the streak[s second]". Label only — CHATTER reads
          // as what this tab actually is (the community's shared posting
          // feed: priority notices + member posts, "makes everyone
          // participate and chat here"). The underlying widget/class stays
          // CommunityAnnouncementsTab; renaming that too is a much larger,
          // purely-cosmetic refactor for no functional gain.
          _TabItem(label: 'CHATTER', active: !showStreaks, showDot: showStreaks && kShowCommunityScoreboard, onTap: () => onSelect(false)),
          if (kShowCommunityScoreboard) ...[
            const SizedBox(width: 22),
            _TabItem(label: 'STREAKS', active: showStreaks, onTap: () => onSelect(true)),
          ],
        ],
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({required this.label, required this.active, required this.onTap, this.showDot = false});
  final String label;
  final bool active;
  final VoidCallback onTap;
  final bool showDot;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      // IntrinsicWidth so the underline below sizes to the label's own
      // width rather than needing an arbitrary fixed width — a naive fixed
      // width here (previously `width: 999, constraints: maxWidth(200)`)
      // overflowed the tabs row on device.
      child: IntrinsicWidth(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: active ? CommunityType.tabActive : CommunityType.tabInactive),
                  if (showDot) ...[
                    const SizedBox(width: 5),
                    Container(width: 5, height: 5, decoration: const BoxDecoration(color: CommunityColors.lime, shape: BoxShape.circle)),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Container(
                height: 2,
                color: active ? CommunityColors.textPrimary : Colors.transparent,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

