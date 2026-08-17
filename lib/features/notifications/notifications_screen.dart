import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants.dart';
import '../ping/ping_view_sheet.dart';

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

enum NotifType {
  ping,         // mystery/known ping ("someone pinged you...")
  photoReply,   // photo reply
  engagement,   // batched reactions
  mention,      // @mention
  pinned,       // pinned person activity — priority, immediate
  discussion,   // community
  digest,       // daily summary
  batchedWatch, // "3 people watched" — debounced cluster
  bigScore,     // "+50 🔥" — rare, exciting
  milestone,    // tier-up / streak / 100 reactions
  mystery,      // "someone's watched you 3× today" — intrigue
  rank,         // position change in leaderboard
}

// Priority level — drives banner appearance and delivery timing
enum NotifPriority { low, normal, high }

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

class AppNotif {
  AppNotif({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.time,
    this.isRead = false,
    this.senderName = '',
    this.avatarColor = const Color(0xFF1A2A3A),
    this.priority = NotifPriority.normal,
    this.rankPosition,
  });

  final String id;
  final NotifType type;
  final String title;
  final String body;
  final String time;
  bool isRead;
  final String senderName;
  final Color avatarColor;
  final NotifPriority priority;
  final int? rankPosition;

  bool get isHighPriority => priority == NotifPriority.high;

  AppNotif copyWith({bool? isRead}) => AppNotif(
        id: id,
        type: type,
        title: title,
        body: body,
        time: time,
        isRead: isRead ?? this.isRead,
        senderName: senderName,
        avatarColor: avatarColor,
        priority: priority,
        rankPosition: rankPosition,
      );
}

// ---------------------------------------------------------------------------
// Dummy seed data
// ---------------------------------------------------------------------------

List<AppNotif> _makeDummies() => [
      // Pinned person — immediate, high priority
      AppNotif(
        id: 'n_pinned_1',
        type: NotifType.pinned,
        title: 'alex (pinned) just watched your moment 👀',
        body: '',
        time: '1m ago',
        isRead: false,
        senderName: 'alex_xyz',
        avatarColor: const Color(0xFF1A3040),
        priority: NotifPriority.high,
      ),
      // Mystery incoming ping — anticipation
      AppNotif(
        id: 'n_ping_1',
        type: NotifType.ping,
        title: 'Someone pinged you...',
        body: 'Hold 2s to find out who',
        time: '3m ago',
        isRead: false,
        priority: NotifPriority.high,
      ),
      // Batched watchers — clubbed together
      AppNotif(
        id: 'n_batch_1',
        type: NotifType.batchedWatch,
        title: 'alex and 2 mystery people watching 👀',
        body: 'Your last moment',
        time: '8m ago',
        isRead: false,
        priority: NotifPriority.normal,
      ),
      // Big score event — rare
      AppNotif(
        id: 'n_score_1',
        type: NotifType.bigScore,
        title: '🔥 You earned +50 score!',
        body: 'Your post blew up',
        time: '15m ago',
        isRead: false,
        priority: NotifPriority.high,
      ),
      // Mystery watcher loop
      AppNotif(
        id: 'n_mystery_1',
        type: NotifType.mystery,
        title: 'Someone\'s watched you 3× today 👀',
        body: '',
        time: '42m ago',
        isRead: false,
        priority: NotifPriority.normal,
      ),
      // Milestone
      AppNotif(
        id: 'n_milestone_1',
        type: NotifType.milestone,
        title: '🏆 Tier up! You\'re now Prominent',
        body: 'Score crossed 150',
        time: '1h ago',
        isRead: true,
        priority: NotifPriority.high,
      ),
      // Batched reactions — not spammy
      AppNotif(
        id: 'n_engage_1',
        type: NotifType.engagement,
        title: '12 people found your post relatable',
        body: '',
        time: '2h ago',
        isRead: true,
      ),
      // Pinned person posted
      AppNotif(
        id: 'n_pinned_2',
        type: NotifType.pinned,
        title: 'alex (pinned) posted a new moment',
        body: '',
        time: '3h ago',
        isRead: true,
        senderName: 'alex_xyz',
        avatarColor: const Color(0xFF1A3040),
        priority: NotifPriority.high,
      ),
      // Daily digest — low priority
      AppNotif(
        id: 'n_digest_1',
        type: NotifType.digest,
        title: 'Yesterday: 14 pings, 18 reactions',
        body: 'You had a good day',
        time: '1d ago',
        isRead: true,
        priority: NotifPriority.low,
      ),
    ];

// ---------------------------------------------------------------------------
// Global notification state
// ---------------------------------------------------------------------------

final notifState = NotifState();

class NotifState extends ChangeNotifier {
  final List<AppNotif> _notifs = _makeDummies();

  // Pinned people — their activity gets immediate, high-priority notifications
  final Set<String> _pinnedPeople = {'alex_xyz'};

  bool _bannerVisible = false;
  AppNotif? _bannerNotif;

  // Watch-queue batching
  Timer? _watchBatchTimer;
  final List<String?> _watchQueue = []; // null = anonymous watcher

  // Throttle: track recent notification timestamps
  final List<DateTime> _recentFireTimes = [];
  static const _kMaxPerHour = 8; // max live notifications per hour
  static const _kBatchDebounce = Duration(seconds: 4);

  // Glass notification queue (right-side, above bottom nav)
  final Queue<AppNotif> _glassQueue = Queue<AppNotif>();
  AppNotif? _glassNotif;
  bool _glassVisible = false;
  Timer? _glassAutoDismissTimer;

  // Cooldowns for strategic triggers (key → last fired time)
  final Map<String, DateTime> _strategicCooldowns = {};

  // Simulation state
  bool _simRunning = false;
  bool get simRunning => _simRunning;

  // Navigation callbacks — wired by MainShell
  VoidCallback? onGoHome;
  VoidCallback? onGoPing;
  VoidCallback? onGoCommunity;
  VoidCallback? onGoProfile;

  // ── Pinned people ────────────────────────────────────────────────────────

  Set<String> get pinnedPeople => Set.unmodifiable(_pinnedPeople);

  bool isPinned(String username) => _pinnedPeople.contains(username);

  void pinPerson(String username) {
    _pinnedPeople.add(username);
    notifyListeners();
  }

  void unpinPerson(String username) {
    _pinnedPeople.remove(username);
    notifyListeners();
  }

  // ── Read access ─────────────────────────────────────────────────────────

  List<AppNotif> get all => List.unmodifiable(_notifs);

  bool get bannerVisible => _bannerVisible;
  AppNotif? get bannerNotif => _bannerNotif;

  int get unreadPings => _notifs
      .where((n) =>
          (n.type == NotifType.ping || n.type == NotifType.photoReply) &&
          !n.isRead)
      .length;

  int get unreadHome => _notifs
      .where((n) =>
          (n.type == NotifType.engagement ||
              n.type == NotifType.mention ||
              n.type == NotifType.batchedWatch ||
              n.type == NotifType.bigScore ||
              n.type == NotifType.milestone ||
              n.type == NotifType.mystery ||
              n.type == NotifType.rank) &&
          !n.isRead)
      .length;

  bool get communityBadge =>
      _notifs.any((n) => n.type == NotifType.discussion && !n.isRead);

  int get totalUnread => _notifs.where((n) => !n.isRead).length;

  // ── Throttle ─────────────────────────────────────────────────────────────

  bool get _isThrottled {
    final now = DateTime.now();
    _recentFireTimes.removeWhere((t) => now.difference(t).inHours >= 1);
    return _recentFireTimes.length >= _kMaxPerHour;
  }

  void _recordFire() => _recentFireTimes.add(DateTime.now());

  // ── Mutations ───────────────────────────────────────────────────────────

  void markAllRead() {
    for (final n in _notifs) {
      n.isRead = true;
    }
    notifyListeners();
  }

  void dismiss(String id) {
    _notifs.removeWhere((n) => n.id == id);
    notifyListeners();
  }

  void clearAll() {
    _notifs.clear();
    notifyListeners();
  }

  void markTypeRead(NotifType type) {
    for (final n in _notifs) {
      if (n.type == type) n.isRead = true;
    }
    notifyListeners();
  }

  // ── Internal fire ────────────────────────────────────────────────────────

  void _fireNotif(AppNotif notif, {bool forceShow = false}) {
    if (!forceShow && _isThrottled && notif.priority == NotifPriority.low) {
      return; // suppress low-priority when throttled
    }
    _recordFire();
    _notifs.insert(0, notif);
    showBanner(notif);
  }

  // ── Watcher batching ─────────────────────────────────────────────────────

  /// Call this whenever someone watches the user's post.
  /// Pinned people fire immediately; everyone else is debounce-batched.
  void addWatcher(String? username) {
    if (username != null && isPinned(username)) {
      // Pinned → immediate, high priority
      _fireNotif(
        AppNotif(
          id: 'pinned_watch_${DateTime.now().millisecondsSinceEpoch}',
          type: NotifType.pinned,
          title: '$username (pinned) just watched your moment 👀',
          body: '',
          time: 'just now',
          senderName: username,
          avatarColor: const Color(0xFF1A3040),
          priority: NotifPriority.high,
        ),
        forceShow: true,
      );
      return;
    }
    // Enqueue and debounce
    _watchQueue.add(username);
    _watchBatchTimer?.cancel();
    _watchBatchTimer = Timer(_kBatchDebounce, _flushWatchBatch);
  }

  void _flushWatchBatch() {
    if (_watchQueue.isEmpty) return;
    final count = _watchQueue.length;
    final named = _watchQueue.whereType<String>().take(2).toList();
    _watchQueue.clear();

    final String title;
    if (count == 1) {
      title = named.isEmpty
          ? 'Someone watched your moment 👀'
          : '${named[0]} watched your moment 👀';
    } else if (named.length >= 2) {
      title = '${named[0]}, ${named[1]} and ${count - 2 > 0 ? "${count - 2} other${count - 2 > 1 ? "s" : ""}" : "1 other"} watching 👀';
    } else if (named.length == 1) {
      title = '${named[0]} and ${count - 1} mystery ${count - 1 == 1 ? "person" : "people"} watching 👀';
    } else {
      title = '$count mystery people watched your moment 👀';
    }

    _fireNotif(AppNotif(
      id: 'watch_${DateTime.now().millisecondsSinceEpoch}',
      type: NotifType.batchedWatch,
      title: title,
      body: 'Your last moment',
      time: 'just now',
    ));
  }

  // ── Public fire methods ──────────────────────────────────────────────────

  void firePing({String? senderName, bool anonymous = true}) {
    final title = anonymous ? 'Someone pinged you...' : '$senderName pinged you';
    final body = anonymous ? 'Hold 2s to find out who' : 'They want to hear from you';
    _fireNotif(
      AppNotif(
        id: 'ping_${DateTime.now().millisecondsSinceEpoch}',
        type: NotifType.ping,
        title: title,
        body: body,
        time: 'just now',
        senderName: senderName ?? '',
        avatarColor: const Color(0xFF1A3040),
        priority: NotifPriority.high,
      ),
      forceShow: true,
    );
  }

  void fireBigScore(int amount) {
    _fireNotif(
      AppNotif(
        id: 'score_${DateTime.now().millisecondsSinceEpoch}',
        type: NotifType.bigScore,
        title: '🔥 You earned +$amount score!',
        body: amount >= 30 ? 'Rare event — you\'re on fire' : 'Keep it going',
        time: 'just now',
        priority: NotifPriority.high,
      ),
      forceShow: true,
    );
  }

  void fireMilestone(String text, {String body = ''}) {
    _fireNotif(
      AppNotif(
        id: 'milestone_${DateTime.now().millisecondsSinceEpoch}',
        type: NotifType.milestone,
        title: text,
        body: body,
        time: 'just now',
        priority: NotifPriority.high,
      ),
      forceShow: true,
    );
  }

  void fireMystery(String text) {
    _fireNotif(AppNotif(
      id: 'mystery_${DateTime.now().millisecondsSinceEpoch}',
      type: NotifType.mystery,
      title: text,
      body: '',
      time: 'just now',
    ));
  }

  // ── Random score (variable reward, slot-machine feel) ────────────────────

  static final _rng = math.Random();

  /// Returns a random score amount. 70% chance of small (3-12),
  /// 20% chance of medium (15-29), 10% chance of big (30-60).
  static int randomScoreAmount() {
    final r = _rng.nextDouble();
    if (r < 0.70) return 3 + _rng.nextInt(10);
    if (r < 0.90) return 15 + _rng.nextInt(15);
    return 30 + _rng.nextInt(31);
  }

  // ── Simulation sequence ──────────────────────────────────────────────────

  /// Fires: batched watchers → pinned-person immediate → big score (+50).
  /// Called from the "Simulate" button in NotificationsScreen.
  Future<void> simulateSequence() async {
    if (_simRunning) return;
    _simRunning = true;
    notifyListeners();

    // Step 1: queue 3 watchers (alex is pinned → fires immediately)
    addWatcher('jordan_23');  // non-pinned
    addWatcher(null);         // anonymous watcher
    addWatcher(null);         // another anonymous
    // (batch fires in 4s — but we want it for the demo, so flush manually)
    await Future<void>.delayed(const Duration(milliseconds: 800));
    _watchBatchTimer?.cancel();
    _flushWatchBatch();

    // Step 2: pinned person — immediate
    await Future<void>.delayed(const Duration(milliseconds: 1800));
    addWatcher('alex_xyz'); // pinned → fires now

    // Step 3: big score event
    await Future<void>.delayed(const Duration(milliseconds: 2000));
    fireBigScore(50);

    await Future<void>.delayed(const Duration(milliseconds: 800));
    _simRunning = false;
    notifyListeners();
  }

  // ── Banner ───────────────────────────────────────────────────────────────

  Timer? _autoDismissTimer;

  void showBanner(AppNotif notif) {
    _bannerNotif = notif;
    _bannerVisible = true;
    _autoDismissTimer?.cancel();
    // High-priority: 4s; normal: 2.5s; low: 2.5s
    final duration = notif.isHighPriority
        ? const Duration(milliseconds: 4000)
        : const Duration(milliseconds: 2500);
    _autoDismissTimer = Timer(duration, dismissBanner);
    notifyListeners();
  }

  void dismissBanner() {
    _autoDismissTimer?.cancel();
    _bannerVisible = false;
    _bannerNotif = null;
    notifyListeners();
  }

  @Deprecated('Use simulateSequence() for the full demo flow')
  void triggerTestBanner() => simulateSequence();

  // ── Glass notification (right-side) ─────────────────────────────────────

  AppNotif? get glassNotif => _glassNotif;
  bool get glassVisible => _glassVisible;

  void showGlass(AppNotif notif) {
    if (_isThrottled && notif.priority == NotifPriority.low) return;
    _recordFire();
    if (_glassVisible) {
      _glassQueue.addLast(notif);
    } else {
      _glassNotif = notif;
      _glassVisible = true;
      _startGlassTimer(notif);
      notifyListeners();
    }
  }

  void _startGlassTimer(AppNotif notif) {
    _glassAutoDismissTimer?.cancel();
    final ms = notif.isHighPriority ? 3500 : 2500;
    _glassAutoDismissTimer = Timer(Duration(milliseconds: ms), dismissGlass);
  }

  void dismissGlass() {
    _glassAutoDismissTimer?.cancel();
    _glassVisible = false;
    _glassNotif = null;
    notifyListeners();
    if (_glassQueue.isNotEmpty) {
      // Wait for slide-out animation to finish before showing next
      Timer(const Duration(milliseconds: 320), () {
        if (_glassQueue.isNotEmpty) {
          final next = _glassQueue.removeFirst();
          _glassNotif = next;
          _glassVisible = true;
          _startGlassTimer(next);
          notifyListeners();
        }
      });
    }
  }

  // ── Cooldown helper ─────────────────────────────────────────────────────

  bool _cooldownOk(String key, Duration minGap) {
    final last = _strategicCooldowns[key];
    if (last == null) return true;
    return DateTime.now().difference(last) >= minGap;
  }

  void _recordCooldown(String key) =>
      _strategicCooldowns[key] = DateTime.now();

  // ── Real-event triggers ─────────────────────────────────────────────────

  void fireProfileView() {
    if (!_cooldownOk('profile_view', const Duration(minutes: 10))) return;
    _recordCooldown('profile_view');
    showGlass(AppNotif(
      id: 'pv_${DateTime.now().millisecondsSinceEpoch}',
      type: NotifType.batchedWatch,
      title: 'Someone viewed your profile 👀',
      body: '',
      time: 'just now',
      priority: NotifPriority.normal,
    ));
  }

  void fireAnonViews(int count) {
    if (count < 3) return;
    showGlass(AppNotif(
      id: 'av_${DateTime.now().millisecondsSinceEpoch}',
      type: NotifType.mystery,
      title: '$count mystery people are watching 👀',
      body: '',
      time: 'just now',
      priority: count >= 5 ? NotifPriority.high : NotifPriority.normal,
    ));
  }

  void firePingReply(String senderName) {
    showGlass(AppNotif(
      id: 'pr_${DateTime.now().millisecondsSinceEpoch}',
      type: NotifType.photoReply,
      title: '$senderName replied to your ping 📸',
      body: 'Tap to see',
      time: 'just now',
      priority: NotifPriority.high,
    ));
  }

  /// Fired when a recipient opens a ping the user sent (see the "Sent"
  /// section on the Ping page) — surfaces as a glass toast and drives that
  /// row's seen indicator.
  void firePingSeen(String recipientName) {
    showGlass(AppNotif(
      id: 'ps_${DateTime.now().millisecondsSinceEpoch}',
      type: NotifType.ping,
      title: 'Your ping to $recipientName was seen 👀',
      body: '',
      time: 'just now',
      priority: NotifPriority.normal,
    ));
  }

  /// RealMoji reaction received (post_realmoji_reactions insert — see
  /// realmoji_service.dart) — routed through the same glass-toast pipe as
  /// firePingSeen above via _buildGenericTitle, rather than a bespoke
  /// string, per the "any notification type through this slot" ask.
  /// Reuses NotifType.engagement (no new enum case needed — navigateTo/
  /// _NotifIcon already handle it, and "someone reacted" is engagement
  /// either way).
  void fireRealmojiReaction(String actorName, String emojiGlyph) {
    if (!_cooldownOk('realmoji', const Duration(seconds: 30))) return;
    _recordCooldown('realmoji');
    showGlass(AppNotif(
      id: 'rm_${DateTime.now().millisecondsSinceEpoch}',
      type: NotifType.engagement,
      title: _buildGenericTitle(
        NotifType.engagement,
        {'name': actorName, 'emoji': emojiGlyph},
      ),
      body: '',
      time: 'just now',
      priority: NotifPriority.normal,
    ));
  }

  /// Pin reveal received (post_author_pin_service.dart — someone the
  /// viewer pinned had their real identity revealed to them). Reuses
  /// NotifType.pinned (navigateTo already routes it to profile).
  void firePinReveal(String username) {
    showGlass(AppNotif(
      id: 'pin_${DateTime.now().millisecondsSinceEpoch}',
      type: NotifType.pinned,
      title: _buildGenericTitle(NotifType.pinned, {'name': username}),
      body: '',
      time: 'just now',
      priority: NotifPriority.high,
    ));
  }

  /// Single source of truth for "notification type -> display text",
  /// keyed on the same NotifType enum every fire* method already tags its
  /// AppNotif with. Existing fire* methods (firePingSeen etc.) keep their
  /// own inline strings — untouched, still correct — this is additive: the
  /// two new fire* methods above route through it, and any FUTURE type can
  /// be added here in one place instead of a new bespoke method each time.
  String _buildGenericTitle(NotifType type, Map<String, dynamic> data) {
    final name = data['name'] as String? ?? 'someone';
    switch (type) {
      case NotifType.engagement:
        final emoji = data['emoji'] as String?;
        return emoji != null
            ? '$name reacted with $emoji'
            : '$name reacted to your post';
      case NotifType.pinned:
        return '$name pinned you 👋';
      case NotifType.ping:
        return '$name pinged you 👋';
      case NotifType.photoReply:
        return '$name replied to your ping 📸';
      case NotifType.mention:
        return '$name mentioned you';
      default:
        return '$name sent you a notification';
    }
  }

  void firePostReaction(int count) {
    if (!_cooldownOk('reaction', const Duration(minutes: 5))) return;
    _recordCooldown('reaction');
    showGlass(AppNotif(
      id: 'react_${DateTime.now().millisecondsSinceEpoch}',
      type: NotifType.engagement,
      title: '$count people reacted to your post',
      body: count >= 10 ? 'Your post is blowing up 🔥' : '',
      time: 'just now',
      priority: count >= 10 ? NotifPriority.high : NotifPriority.normal,
    ));
  }

  void fireComment(String sample) {
    showGlass(AppNotif(
      id: 'cmt_${DateTime.now().millisecondsSinceEpoch}',
      type: NotifType.engagement,
      title: 'Comment: "$sample"',
      body: '',
      time: 'just now',
      priority: NotifPriority.normal,
    ));
  }

  void fireNewFollower(String name) {
    showGlass(AppNotif(
      id: 'fol_${DateTime.now().millisecondsSinceEpoch}',
      type: NotifType.mention,
      title: '$name started following you ✨',
      body: '',
      time: 'just now',
      priority: NotifPriority.high,
    ));
  }

  // ── Strategic encouragement triggers ────────────────────────────────────

  void fireStreakDanger(int currentStreak) {
    if (!_cooldownOk('streak_danger', const Duration(hours: 20))) return;
    _recordCooldown('streak_danger');
    showGlass(AppNotif(
      id: 'sd_${DateTime.now().millisecondsSinceEpoch}',
      type: NotifType.milestone,
      title: '🔥 $currentStreak-day streak at risk!',
      body: 'Post before midnight to keep it alive',
      time: 'just now',
      priority: NotifPriority.high,
    ));
  }

  void fireMilestoneGlass(int score) {
    showGlass(AppNotif(
      id: 'ms_${DateTime.now().millisecondsSinceEpoch}',
      type: NotifType.milestone,
      title: '🏆 You hit $score score!',
      body: 'You\'re climbing fast',
      time: 'just now',
      priority: NotifPriority.high,
    ));
  }

  void fireFOMO() {
    final hour = DateTime.now().hour;
    final isPeak = (hour >= 12 && hour < 14) || (hour >= 18 && hour < 20);
    if (!isPeak) return;
    if (!_cooldownOk('fomo', const Duration(hours: 2))) return;
    _recordCooldown('fomo');
    showGlass(AppNotif(
      id: 'fomo_${DateTime.now().millisecondsSinceEpoch}',
      type: NotifType.batchedWatch,
      title: 'Everyone\'s posting right now 📸',
      body: 'Don\'t miss out',
      time: 'just now',
      priority: NotifPriority.normal,
    ));
  }

  void fireSocialProof(int friendCount) {
    if (!_cooldownOk('social', const Duration(hours: 2))) return;
    _recordCooldown('social');
    showGlass(AppNotif(
      id: 'soc_${DateTime.now().millisecondsSinceEpoch}',
      type: NotifType.discussion,
      title: '$friendCount friends just posted 👥',
      body: 'See what\'s happening',
      time: 'just now',
      priority: NotifPriority.normal,
    ));
  }

  void fireMysteryAwait() {
    if (!_cooldownOk('mystery_await', const Duration(hours: 23))) return;
    _recordCooldown('mystery_await');
    showGlass(AppNotif(
      id: 'ma_${DateTime.now().millisecondsSinceEpoch}',
      type: NotifType.mystery,
      title: '✨ Something special awaits...',
      body: '',
      time: 'just now',
      priority: NotifPriority.normal,
    ));
  }

  void fireComeback() {
    if (!_cooldownOk('comeback', const Duration(hours: 4))) return;
    _recordCooldown('comeback');
    showGlass(AppNotif(
      id: 'cb_${DateTime.now().millisecondsSinceEpoch}',
      type: NotifType.digest,
      title: 'Haven\'t seen you in a while 👋',
      body: 'What\'s happening on campus?',
      time: 'just now',
      priority: NotifPriority.low,
    ));
  }

  void fireStreakAlive(int days) {
    if (!_cooldownOk('streak_alive', const Duration(hours: 20))) return;
    _recordCooldown('streak_alive');
    showGlass(AppNotif(
      id: 'sa_${DateTime.now().millisecondsSinceEpoch}',
      type: NotifType.milestone,
      title: '🔥 $days-day streak! You\'re on fire',
      body: days >= 7 ? 'One week strong!' : 'Keep it going',
      time: 'just now',
      priority: NotifPriority.high,
    ));
  }

  void fireRankChange(int newRank, {int? prevRank, String group = 'CSE'}) {
    if (!_cooldownOk('rank', const Duration(hours: 1))) return;
    _recordCooldown('rank');
    final String title;
    final String body;
    final NotifPriority priority;
    if (prevRank == null || prevRank == newRank) {
      title = 'You\'re #$newRank in $group this week 🏆';
      body = 'Keep posting to climb higher';
      priority = NotifPriority.normal;
    } else if (newRank < prevRank) {
      // moved UP (lower rank number = better)
      title = 'You moved up to #$newRank! 📈';
      body = 'Up from #$prevRank in $group';
      priority = NotifPriority.high;
    } else {
      // moved DOWN
      title = 'Someone passed you — you\'re now #$newRank 😤';
      body = 'Post to reclaim your spot in $group';
      priority = NotifPriority.normal;
    }
    final notif = AppNotif(
      id: 'rank_${DateTime.now().millisecondsSinceEpoch}',
      type: NotifType.rank,
      title: title,
      body: body,
      time: 'just now',
      priority: priority,
      rankPosition: newRank,
    );
    _fireNotif(notif, forceShow: newRank <= 10);
    showGlass(notif);
  }

  void fireTopTenAlert(int rank, String group) {
    if (!_cooldownOk('top10', const Duration(hours: 4))) return;
    _recordCooldown('top10');
    showGlass(AppNotif(
      id: 'top10_${DateTime.now().millisecondsSinceEpoch}',
      type: NotifType.rank,
      title: 'You\'re about to enter the top 10 🔥',
      body: 'Currently #${rank + 1} in $group',
      time: 'just now',
      priority: NotifPriority.high,
      rankPosition: rank + 1,
    ));
  }

  // Callback for when a ping notification is tapped — set by MainShell
  void Function(AppNotif)? onOpenPingNotif;
  // Callback for rank notification tap — set by MainShell
  VoidCallback? onGoLeaderboard;

  void navigateTo(AppNotif notif) {
    switch (notif.type) {
      case NotifType.ping:
        // Open the ping reveal — use dedicated callback if wired, else go to ping tab
        if (onOpenPingNotif != null) {
          onOpenPingNotif!(notif);
        } else {
          onGoPing?.call();
        }
      case NotifType.photoReply:
        if (onOpenPingNotif != null) {
          onOpenPingNotif!(notif);
        } else {
          onGoPing?.call();
        }
      case NotifType.mention:
        onGoProfile?.call();
      case NotifType.engagement:
      case NotifType.batchedWatch:
      case NotifType.bigScore:
      case NotifType.milestone:
      case NotifType.mystery:
        onGoHome?.call();
      case NotifType.pinned:
        onGoProfile?.call();
      case NotifType.discussion:
        onGoCommunity?.call();
      case NotifType.digest:
        onGoHome?.call();
      case NotifType.rank:
        if (onGoLeaderboard != null) {
          onGoLeaderboard!();
        } else {
          onGoProfile?.call();
        }
    }
  }
}

// ---------------------------------------------------------------------------
// NotificationsScreen
// ---------------------------------------------------------------------------

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    notifState.addListener(_onStateChange);
  }

  @override
  void dispose() {
    notifState.removeListener(_onStateChange);
    super.dispose();
  }

  void _onStateChange() {
    if (mounted) setState(() {});
  }

  void _tapNotif(AppNotif notif) {
    notifState.dismiss(notif.id);
    if (notif.type == NotifType.ping) {
      Navigator.of(context).pop();
      showPingViewSheet(
        context,
        senderName:
            notif.senderName.isNotEmpty ? notif.senderName : 'someone',
        type: PingViewType.text,
        promptText: notif.body,
        avatarColor: notif.avatarColor,
      );
      return;
    }
    if (notif.type == NotifType.photoReply) {
      Navigator.of(context).pop();
      showPingViewSheet(
        context,
        senderName:
            notif.senderName.isNotEmpty ? notif.senderName : 'someone',
        type: PingViewType.photo,
        avatarColor: notif.avatarColor,
      );
      return;
    }
    notifState.navigateTo(notif);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final notifs = notifState.all;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          _buildHeader(topPad),
          _PinnedPeopleRow(),
          Expanded(
            child: notifs.isEmpty
                ? const _EmptyState()
                : _buildList(notifs, bottomPad),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(double topPad) {
    final simRunning = notifState.simRunning;
    return Container(
      padding: EdgeInsets.fromLTRB(16, topPad + 10, 12, 12),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: const Icon(
              Icons.arrow_back_ios_new,
              size: 18,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Notifications',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          GestureDetector(
            onTap: simRunning
                ? null
                : () {
                    HapticFeedback.lightImpact();
                    Navigator.of(context).pop();
                    notifState.simulateSequence();
                  },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: simRunning
                    ? AppColors.cardSurface
                    : AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: simRunning
                        ? AppColors.border
                        : AppColors.primary.withValues(alpha: 0.30)),
              ),
              child: Text(
                simRunning ? 'Running…' : 'Simulate',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  color: simRunning ? AppColors.textMuted : AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: notifState.markAllRead,
            child: Text(
              'Mark all read',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: AppColors.textMuted,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(List<AppNotif> notifs, double bottomPad) {
    // Priority (pinned/high) always first
    final priority = notifs.where((n) => n.isHighPriority && !n.isRead).toList();
    final pings = notifs
        .where((n) =>
            (n.type == NotifType.ping || n.type == NotifType.photoReply) &&
            !n.isHighPriority &&
            !n.isRead)
        .toList();
    final activity = notifs
        .where((n) =>
            (n.type == NotifType.engagement ||
                n.type == NotifType.mention ||
                n.type == NotifType.batchedWatch ||
                n.type == NotifType.mystery) &&
            !n.isHighPriority &&
            !n.isRead)
        .toList();
    final read = notifs.where((n) => n.isRead).toList();

    return ListView(
      padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPad + 80),
      children: [
        if (priority.isNotEmpty) ...[
          _SectionLabel(label: '⚡ Priority'),
          const SizedBox(height: 8),
          for (final n in priority) ...[
            _NotifCard(notif: n, onTap: () => _tapNotif(n)),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 16),
        ],
        if (pings.isNotEmpty) ...[
          _SectionLabel(label: 'Pings'),
          const SizedBox(height: 8),
          for (final n in pings) ...[
            _NotifCard(notif: n, onTap: () => _tapNotif(n)),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 16),
        ],
        if (activity.isNotEmpty) ...[
          _SectionLabel(label: 'Activity'),
          const SizedBox(height: 8),
          for (final n in activity) ...[
            _NotifCard(notif: n, onTap: () => _tapNotif(n)),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 16),
        ],
        if (read.isNotEmpty) ...[
          _SectionLabel(label: 'Earlier'),
          const SizedBox(height: 8),
          for (final n in read) ...[
            _NotifCard(notif: n, onTap: () => _tapNotif(n)),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 20),
        ],
        if (notifs.isNotEmpty)
          Center(
            child: GestureDetector(
              onTap: notifState.clearAll,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 9),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  'Clear all',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Pinned people row — shown below header in NotificationsScreen
// ---------------------------------------------------------------------------

class _PinnedPeopleRow extends StatefulWidget {
  @override
  State<_PinnedPeopleRow> createState() => _PinnedPeopleRowState();
}

class _PinnedPeopleRowState extends State<_PinnedPeopleRow> {
  @override
  void initState() {
    super.initState();
    notifState.addListener(_rebuild);
  }

  @override
  void dispose() {
    notifState.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final pinned = notifState.pinnedPeople.toList();
    if (pinned.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.push_pin_rounded,
                size: 11,
                color: AppColors.textMuted,
              ),
              const SizedBox(width: 4),
              Text(
                'Pinned — priority notifications',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 9,
                  color: AppColors.textMuted,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final name in pinned)
                _PinnedChip(
                  name: name,
                  onUnpin: () => notifState.unpinPerson(name),
                ),
              _AddPinChip(),
            ],
          ),
        ],
      ),
    );
  }
}

class _PinnedChip extends StatelessWidget {
  const _PinnedChip({required this.name, required this.onUnpin});
  final String name;
  final VoidCallback onUnpin;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 8),
          const Icon(Icons.push_pin_rounded, size: 10, color: AppColors.primary),
          const SizedBox(width: 4),
          Text(
            name,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 11,
              color: AppColors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onUnpin,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 5, 7, 5),
              child: Icon(
                Icons.close_rounded,
                size: 11,
                color: AppColors.primary.withValues(alpha: 0.70),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddPinChip extends StatelessWidget {
  // Available people to pin (not already pinned)
  static const _kCandidates = [
    ('alex_xyz', Color(0xFF2A3040)),
    ('jordan_23', Color(0xFF30281A)),
    ('study_bug', Color(0xFF1E2A28)),
    ('sunset_chaser', Color(0xFF382818)),
    ('coffee_talk', Color(0xFF182030)),
  ];

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showPinSheet(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.add_rounded, size: 12, color: AppColors.textMuted),
            const SizedBox(width: 4),
            Text(
              'Pin someone',
              style: GoogleFonts.inter(
                fontSize: 11,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPinSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _PinPersonSheet(candidates: _kCandidates),
    );
  }
}

class _PinPersonSheet extends StatelessWidget {
  const _PinPersonSheet({required this.candidates});
  final List<(String, Color)> candidates;

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final alreadyPinned = notifState.pinnedPeople;
    final available =
        candidates.where((c) => !alreadyPinned.contains(c.$1)).toList();

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF131318),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, bottomPad + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Pin someone',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Their activity will notify you immediately',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 14),
          if (available.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  'Everyone is already pinned',
                  style: GoogleFonts.inter(
                      fontSize: 13, color: AppColors.textMuted),
                ),
              ),
            )
          else
            for (final (name, color) in available)
              GestureDetector(
                onTap: () {
                  notifState.pinPerson(name);
                  Navigator.of(context).pop();
                  HapticFeedback.lightImpact();
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color,
                        ),
                        child: Center(
                          child: Text(
                            name[0].toUpperCase(),
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 14,
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          name,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.push_pin_outlined,
                        size: 16,
                        color: AppColors.textMuted,
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section label
// ---------------------------------------------------------------------------

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: GoogleFonts.jetBrainsMono(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: AppColors.textMuted,
        letterSpacing: 1.0,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Notification card
// ---------------------------------------------------------------------------

class _NotifCard extends StatelessWidget {
  const _NotifCard({required this.notif, required this.onTap});

  final AppNotif notif;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isHighPriority = notif.isHighPriority;

    return Dismissible(
      key: ValueKey(notif.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => notifState.dismiss(notif.id),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          color: const Color(0xFFFF4444).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.close, color: Color(0xFFFF4444), size: 18),
      ),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.cardSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: notif.isRead
                  ? AppColors.border
                  : isHighPriority
                      ? AppColors.coral.withValues(alpha: 0.35)
                      : AppColors.primary.withValues(alpha: 0.22),
            ),
            boxShadow: isHighPriority && !notif.isRead
                ? [
                    BoxShadow(
                      color: AppColors.coral.withValues(alpha: 0.08),
                      blurRadius: 12,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _NotifIcon(type: notif.type, priority: notif.priority),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notif.title,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight:
                            notif.isRead ? FontWeight.w400 : FontWeight.w600,
                        color: AppColors.textPrimary,
                        height: 1.35,
                      ),
                    ),
                    if (notif.body.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        notif.body,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: AppColors.textMuted,
                          height: 1.3,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      notif.time,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              if (!notif.isRead)
                Padding(
                  padding: const EdgeInsets.only(left: 8, top: 3),
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: isHighPriority
                          ? AppColors.coral
                          : AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Notification icon per type
// ---------------------------------------------------------------------------

class _NotifIcon extends StatelessWidget {
  const _NotifIcon({required this.type, this.priority = NotifPriority.normal});
  final NotifType type;
  final NotifPriority priority;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color) = switch (type) {
      NotifType.ping =>
        (Icons.notifications_active_outlined, AppColors.coral),
      NotifType.photoReply =>
        (Icons.photo_camera_outlined, AppColors.coral),
      NotifType.engagement => (Icons.thumb_up_alt_outlined, AppColors.primary),
      NotifType.mention => (Icons.alternate_email, AppColors.primary),
      NotifType.pinned => (Icons.push_pin_rounded, AppColors.coral),
      NotifType.discussion => (Icons.forum_outlined, AppColors.primary),
      NotifType.digest => (Icons.summarize_outlined, AppColors.textMuted),
      NotifType.batchedWatch => (Icons.remove_red_eye_outlined, AppColors.primary),
      NotifType.bigScore => (Icons.local_fire_department_rounded, AppColors.coral),
      NotifType.milestone => (Icons.emoji_events_outlined, const Color(0xFFE0A020)),
      NotifType.mystery => (Icons.help_outline_rounded, const Color(0xFF9B8FD4)),
      NotifType.rank => (Icons.leaderboard_outlined, const Color(0xFFE0A020)),
    };
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: priority == NotifPriority.high
            ? Border.all(color: color.withValues(alpha: 0.25), width: 0.8)
            : null,
      ),
      child: Icon(icon, size: 18, color: color),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.notifications_none,
              size: 48,
              color: AppColors.textMuted.withValues(alpha: 0.40)),
          const SizedBox(height: 12),
          Text(
            'All clear',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Pin people to get priority alerts',
            style: GoogleFonts.inter(
              fontSize: 13,
              color: AppColors.textMuted.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// NotifBanner — glass overlay over bottom nav (used from MainShell)
// ---------------------------------------------------------------------------

class NotifBanner extends StatelessWidget {
  const NotifBanner({
    super.key,
    required this.notif,
    required this.onDismiss,
    this.onTap,
  });

  final AppNotif notif;
  final VoidCallback onDismiss;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;

    return Padding(
      padding: EdgeInsets.fromLTRB(12, topPad + 8, 12, 0),
      child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        onDismiss();
        onTap?.call();
        notifState.navigateTo(notif);
      },
      onVerticalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) < -50) onDismiss();
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xEB0D0D11),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0x1FFFFFFF), width: 0.5),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              height: 56,
              child: Row(
                children: [
                  _NotifIcon(type: notif.type, priority: notif.priority),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          notif.title,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (notif.body.isNotEmpty)
                          Text(
                            notif.body,
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: AppColors.textMuted,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      ),
    );
  }
}
