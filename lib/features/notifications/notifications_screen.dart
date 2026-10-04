import 'dart:async';
import 'dart:collection';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants.dart';
import '../../core/supabase_config.dart';
import '../../services/group_service.dart';
import '../profile_v2/audience_picker_sheet.dart';
import '../../services/notification_feed_service.dart';
import '../../services/us_album_service.dart';
import 'blurred_actor_name.dart';
import '../../shared/time_ago.dart';

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

enum NotifType {
  ping,           // real: someone pinged you (pings)
  photoReply,     // photo reply
  engagement,     // real: reaction (reactions) + local batched-reaction UX
  mention,        // @mention
  duoInvite,      // real: someone started a Duo with you (us_albums, pending)
  groupInvite,    // real: invited into a group album (group_invites)
  branchView,     // real: branch-only visitor signal (profile_views)
  usAlbumMutual,  // real: a Us-album photo was tagged mutual (us_album_photos)
  reportFiled,    // real: your report was received (reports INSERT trigger)
  reportResolved, // real: a moderator acted on your report (resolve_report)
  discussion,     // community
  digest,         // daily summary
  batchedWatch,   // "3 people watched" — local debounced cluster
  bigScore,       // "+50 🔥" — local, rare/exciting
  milestone,      // tier-up / streak / 100 reactions — local
  mystery,        // "someone's watched you 3× today" — local intrigue
  rank,           // position change in leaderboard — local
}

// Priority level — drives banner appearance and delivery timing
enum NotifPriority { low, normal, high }

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

/// Recovers the sender's display name from a `ping` notification's
/// `title` — see [AppNotif.fromRow]'s own doc for why this exists instead
/// of a dedicated column. Matches notify_ping()'s exact non-anonymous
/// format, `'<name> pinged you'`; anything else (unexpected title shape)
/// falls back to '' so callers' existing `senderName.isNotEmpty ? ... :
/// 'someone'` guard still degrades gracefully instead of showing a mangled
/// string.
String _pingSenderNameFromTitle(String title) {
  const suffix = ' pinged you';
  if (!title.endsWith(suffix)) return '';
  return title.substring(0, title.length - suffix.length).trim();
}

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
    this.isPersisted = false,
    this.createdAt,
    this.pingId,
    this.actorName,
    this.revealed = false,
    this.postId,
    this.data = const {},
    this.rawType = '',
  });

  /// The server's own `notifications.type` string (e.g. 'us_album_invite').
  /// [type] buckets several of these together; routing sometimes needs the
  /// exact one. Empty for local, non-persisted notifs.
  final String rawType;

  /// From a real `notifications` row (NotificationFeedService) — the
  /// persisted inbox. type/tier map onto NotifType/NotifPriority 1:1 with
  /// the CHECK constraints on that table.
  factory AppNotif.fromRow(NotificationRow r) => AppNotif(
        id: r.id,
        rawType: r.type,
        // Every `type` the notifications_type_check constraint allows has a
        // case here. The server grew 18 new types with
        // notification_system_spec.md (§2's missing events, §4's streak and
        // level sends); they deliberately reuse the existing NotifType cases
        // rather than adding enum values, because NotifType drives the
        // unread badges (unreadPings / unreadHome / communityBadge) and the
        // icon+navigation switches, and every new event maps cleanly onto a
        // surface that already exists. A type with no case still falls
        // through to `mystery` and renders, it just lands in the wrong badge
        // — which is why the default stays.
        type: switch (r.type) {
          'reaction' => NotifType.engagement,
          'comment' => NotifType.engagement,
          'moment_contribution' => NotifType.engagement,
          // "X posted a Moment" / the 3h+8h unreplied nudges — same bucket
          // as a Moment reply landing: all three are "something in a
          // Moment wants your attention".
          'moment_new_post' || 'moment_reply_nudge' => NotifType.engagement,
          // Also real (4 live rows), also fell to mystery/Home before this
          // fix: "a pinned person viewed your post" is engagement on your
          // own content, the same bucket a reaction or comment lands in.
          // pinned_group_post_view is the same event on a group post — it
          // used to be written into the notifications table AS
          // 'pinned_post_view' (notify_pinned_group_post_view's own
          // mistyped literal), so this case never had anything to match
          // until that was fixed. Same bucket either way: still "a pinned
          // person viewed your content."
          'pinned_post_view' || 'pinned_group_post_view' => NotifType.engagement,
          'ping' => NotifType.ping,
          // A group ping is still a ping — it belongs in the ping badge.
          // ping_unanswered/group_ping_waiting/group_ping_replied all have
          // real live rows (10/5/2 at last count) but NO case here before
          // this fix, so all three fell to the `_ => mystery` default and
          // navigated to Home instead of the Ping tab — a real dead-ish tap
          // for something that is, at heart, still about a ping.
          'group_streak_ping' ||
          'ping_unanswered' ||
          // Sender side: "<name> didn't open / saw but didn't reply to
          // your ping" (notify_unanswered_pings, 20260929000000).
          'ping_unreplied' ||
          'group_ping_waiting' ||
          'group_ping_replied' =>
            NotifType.ping,
          'ping_answered' => NotifType.photoReply,
          // "Your photo got a ❤️" (toggle_ping_reply_like) — same screen/data
          // shape as ping_answered (screen:'ping_reveal', ping_id,
          // ping_reply_id), so it opens the exact same reply. Added at the
          // same time as the type itself; without this case it fell to the
          // `_ => mystery` default below and navigated to Home on tap,
          // exactly the class of bug this file's own history is full of
          // fixing for other ping types.
          'ping_reply_liked' => NotifType.photoReply,
          // Somebody reacted to my reply / ping with a RealMoji
          // (notify_ping_realmoji). Same bucket as a liked reply.
          'ping_realmoji' => NotifType.photoReply,
          // Both are "someone looked at your profile", and both must land
          // on the profile's own viewed-by surface rather than Home.
          // pinned_profile_view carries NO actor (see
          // notify_pinned_profile_view) — the pinned person is never named,
          // so there is deliberately nobody here to navigate to.
          'branch_view' || 'pinned_profile_view' => NotifType.branchView,
          // us_album_accepted ("X said yes 💞", notify_us_album_accepted)
          // opens the same Duo album.
          // us_album_ended ("X ended your Duo 💔", end_duo) opens the profile.
          'us_album_mutual' || 'us_album_accepted' || 'us_album_ended' =>
            NotifType.usAlbumMutual,
          // Your Duo partner posted — tapping it opens "choose your
          // audience" for the shared post (notify_duo_post).
          'duo_post' => NotifType.usAlbumMutual,
          // Consent requests — rendered with inline Accept / Decline.
          'us_album_invite' => NotifType.duoInvite,
          'group_invite' => NotifType.groupInvite,
          'report_filed' => NotifType.reportFiled,
          'report_resolved' => NotifType.reportResolved,
          // Group/community fan-outs drive the community dot.
          // group_profile_view: "Someone in CS opened <group>'s profile"
          // (notify_group_profile_view) opens the group like the others.
          // group_message: somebody posted in a group CHAT
          // (notify_group_message) — it opens that chat, which lives under
          // Community, so it shares the community dot with the rest.
          'group_added' || 'group_post' || 'group_dip' || 'community_post' ||
          'group_profile_view' || 'group_message' =>
            NotifType.discussion,
          // Phase 5 rhythm. window_prompt and break_live_count both open the
          // anon feed (that is where the prompt and the room are);
          // midday_report opens the feed; day_digest is a summary of your own
          // content, so it lands in engagement.
          'window_prompt' || 'break_live_count' => NotifType.mystery,
          'midday_report' => NotifType.batchedWatch,
          // Phase 6 win-backs. Cooling points at the streak that is about to
          // break, so it shares the milestone bucket; lapsed/dormant are
          // "come look at the feed".
          // Phase 6A. The graduation celebration is a milestone in the most
          // literal sense; the activation drip points at the thing they have
          // not made yet, so it rides the same bucket as other "go do this".
          'graduation' => NotifType.milestone,
          'activation_nudge' => NotifType.batchedWatch,
          'lifecycle_cooling' => NotifType.milestone,
          'lifecycle_lapsed' || 'lifecycle_dormant' => NotifType.batchedWatch,
          'day_digest' => NotifType.engagement,
          // "3 friends posted today" — a batched home-feed nudge.
          // Moments are NOT in this batch: moment_new_post owns them (see
          // notify_post_fanout's post_type guard) and maps to engagement
          // above, where it can open the Moment itself.
          'friend_post' => NotifType.batchedWatch,
          // Phase 4: the start-a-streak nudge and the daily standing line are
          // both "where your streak stands" — same bucket as the risk
          // warnings they lead into.
          'start_streak_nudge' ||
          'streak_standing' ||
          'streak_risk_red' ||
          'streak_risk_blue' ||
          'streak_milestone_blue' ||
          'group_streak_risk' ||
          'group_streak_broken' ||
          'level_progress' =>
            NotifType.milestone,
          'level_up' => NotifType.bigScore,
          // Phase 3 rank movement. All four carry NO actor — a leaderboard
          // notification names people by their ANON handle only, and an
          // actor_id would hand the client their real name through the
          // users embed (the same leak Phase 2 closed on pinned views).
          'leaderboard_movement' ||
          'rank_overtaken' ||
          'rank_regained' ||
          'streak_rank_overtaken' =>
            NotifType.rank,
          'announcement' => NotifType.discussion,
          // Habit loops (20260928130000): the daily drop opens the camera
          // on the day's prompt; the weekly recap opens your profile.
          'daily_drop' => NotifType.digest,
          'weekly_recap' => NotifType.branchView,
          _ => NotifType.mystery,
        },
        title: r.title,
        body: r.body ?? '',
        time: formatRelativeTime(r.createdAt, withAgo: true),
        isRead: r.isRead,
        // notify_ping() (supabase/migrations/20260907020000_notifications.sql)
        // never writes a separate sender-name column — the real name is
        // already baked into `title` ("Alex pinged you"), so recover it from
        // there rather than leaving the tap-through sheet's senderName blank
        // (which always fell back to the literal word "someone", even for a
        // named ping). Only for a NAMED ping: an anonymous ping's
        // notify_ping() branch sets actor_id NULL specifically so the
        // sender can never be identified client-side, so r.actorId == null
        // must keep senderName empty here too.
        senderName: r.type == 'ping' && r.actorId != null
            ? _pingSenderNameFromTitle(r.title)
            : '',
        priority: switch (r.tier) {
          // A group chat message is tier 'major' SERVER-side so it pushes
          // straight away rather than waiting for the digest, but in the
          // inbox it belongs under Activity, not ⚡ Priority — chat would
          // otherwise crowd out the things that actually need answering.
          _ when r.type == 'group_message' => NotifPriority.normal,
          'major' => NotifPriority.high,
          'minor' => NotifPriority.low,
          _ => NotifPriority.normal,
        },
        isPersisted: true,
        createdAt: r.createdAt,
        // 'ping:<id>' for the original ping notification, 'ping_unanswered:
        // <id>' for the "you still haven't replied" nudge (real, 10 live
        // rows) — both dedupe_key formats carry a genuine pings.id after a
        // single prefix, so both can focus PingPage on the exact card.
        // group_streak_ping / group_ping_waiting / group_ping_replied are
        // deliberately NOT handled here: their dedupe_key is
        // '<group_id>:<...>', a GROUP's ping wall, not one ping row — there
        // is no single card to focus, so those fall through to null and
        // the tap just opens the Ping tab (see notifState.navigateTo).
        pingId: r.dedupeKey?.startsWith('ping:') ?? false
            ? r.dedupeKey!.substring('ping:'.length)
            : r.dedupeKey?.startsWith('ping_unanswered:') ?? false
                ? r.dedupeKey!.substring('ping_unanswered:'.length).split(':').first
                : r.dedupeKey?.startsWith('ping_unreplied:') ?? false
                    ? r.dedupeKey!.substring('ping_unreplied:'.length)
                    : null,
        // Resolved through the actor_id FK by NotificationFeedService.
        // Null for an anonymous ping by construction (notify_ping() nulls
        // actor_id in that branch), so there is nothing to blur and the
        // server's own 'Someone pinged you 👋' title is what renders.
        actorName: r.actorName,
        revealed: r.isRevealed,
        postId: r.postId,
        data: r.data,
      );

  final String id;
  final NotifType type;
  final String title;
  final String body;
  final String time;
  bool isRead;
  final String senderName;

  /// The actor's real display name, when there is one to show. Rendered
  /// blurred-until-held for ping / ping-reply rows — see BlurredActorLine.
  final String? actorName;

  /// Whether this row's [actorName] has already been hold-revealed.
  /// Persisted server-side (notifications.revealed_at), so a reveal
  /// survives scroll, refetch, restart and a second device — matching
  /// HoldToRevealBlur's "once true, never re-blurs" contract.
  bool revealed;

  /// The post this notification is about, for entity-level deep links.
  /// Null when the notification isn't about a post, or the post was
  /// deleted (the FK is ON DELETE SET NULL).
  final String? postId;

  /// The row's `data` jsonb — for the invite types: album_id / group_id /
  /// invite_id, used by the inline Accept / Decline.
  final Map<String, dynamic> data;

  /// Set once the user accepts/declines an invite from this row.
  String? inviteOutcome;
  final Color avatarColor;
  final NotifPriority priority;
  final int? rankPosition;

  /// True for a real row from the `notifications` table — read state is
  /// persisted server-side for these (see NotifState.dismiss/markAllRead).
  /// False for the local/ephemeral banner+glass-toast nudges (streak
  /// reminders, FOMO, rank alerts, …), which have no server backing and
  /// only ever lived in this in-memory list.
  final bool isPersisted;
  final DateTime? createdAt;

  /// The `pings.id` this notification is about — recovered from the row's
  /// `dedupe_key` (`'ping:<uuid>'`, set by notify_ping()). Null for every
  /// non-ping notification, and for a local/ephemeral fire* nudge (no
  /// server row, no dedupe_key). Lets a tap deep-link straight to that ping
  /// in the real Ping tab instead of a generic 'go to Ping tab'.
  final String? pingId;

  bool get isHighPriority => priority == NotifPriority.high;
}

// ---------------------------------------------------------------------------
// Global notification state
// ---------------------------------------------------------------------------

final notifState = NotifState();

class NotifState extends ChangeNotifier {
  /// Starts empty — populated by [loadReal] (real `notifications` rows)
  /// plus whatever local/ephemeral fire* nudges have fired this session.
  final List<AppNotif> _notifs = [];

  bool _bannerVisible = false;
  AppNotif? _bannerNotif;

  // Throttle: track recent notification timestamps
  final List<DateTime> _recentFireTimes = [];
  static const _kMaxPerHour = 8; // max live notifications per hour

  // Glass notification queue (right-side, above bottom nav)
  final Queue<AppNotif> _glassQueue = Queue<AppNotif>();
  AppNotif? _glassNotif;
  bool _glassVisible = false;
  Timer? _glassAutoDismissTimer;

  // Cooldowns for strategic triggers (key → last fired time)
  final Map<String, DateTime> _strategicCooldowns = {};

  // Navigation callbacks — wired by MainShell
  VoidCallback? onGoHome;
  VoidCallback? onGoPing;
  VoidCallback? onGoCommunity;
  VoidCallback? onGoProfile;

  // ── Real, persisted inbox ────────────────────────────────────────────────

  bool _loadedOnce = false;

  /// Fetches the real `notifications` table and starts a realtime
  /// subscription so new rows (a reaction, a friend request, …) appear
  /// without a manual refresh. Safe to call more than once — MainShell
  /// calls it once at startup so badge counts are correct before the inbox
  /// screen is ever opened; NotificationsScreen calls it again on open as
  /// a fallback in case the startup fetch hadn't landed yet.
  Future<void> loadReal() async {
    try {
      final rows = await NotificationFeedService.instance.fetchPage();
      _mergeReal(rows.map(AppNotif.fromRow).toList());
    } catch (_) {
      // No session yet / network hiccup — the inbox just stays whatever it
      // was (empty on cold start), same non-fatal doc as elsewhere in this
      // codebase's real-data services.
    }
    if (!_loadedOnce) {
      _loadedOnce = true;
      // Fire-and-forget: notifState is a permanent, never-disposed global
      // singleton (same lifetime as the app), so there's nothing to cancel
      // this subscription into — it's created exactly once, guarded by
      // _loadedOnce, and lives as long as the process does.
      // The stream is used as a CHANGE SIGNAL, not as the data itself.
      // Supabase's .stream() cannot carry a PostgREST embed, so its rows
      // have no `actor` join and therefore no resolved actor name — piping
      // them straight into _mergeReal (as this used to) replaced the
      // fetchPage rows that DID have names with ones that didn't, blanking
      // every blurred-name notification the moment anything changed.
      // Refetching costs one request per change and keeps exactly one code
      // path that knows how to resolve an actor.
      NotificationFeedService.instance.watch().listen(
        (_) async {
          try {
            final rows = await NotificationFeedService.instance.fetchPage();
            _mergeReal(rows.map(AppNotif.fromRow).toList());
          } catch (_) {}
        },
        onError: (_) {},
      );
    }
  }

  void _mergeReal(List<AppNotif> real) {
    _notifs.removeWhere((n) => n.isPersisted);
    _notifs.insertAll(0, real);
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
              n.type == NotifType.duoInvite ||
              n.type == NotifType.groupInvite ||
              n.type == NotifType.branchView ||
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
  //
  // A real (isPersisted) row's read state lives server-side — read_at on
  // the `notifications` table — so marking one read/all-read here also
  // writes through NotificationFeedService. A real row is never actually
  // deleted (the table has no client DELETE policy, by design: every row
  // is server-written and the client's only right over its own rows is
  // read/unread), so "dismiss" on a real notification marks it read and
  // keeps it in the list — it just drops out of the unread badge count and
  // moves to the "Earlier" section, same as any read notification would.
  // A local/ephemeral fire* nudge (no server row) keeps its old behavior:
  // dismiss really does remove it, since there was never anything to
  // persist.

  void markAllRead() {
    for (final n in _notifs) {
      n.isRead = true;
    }
    notifyListeners();
    NotificationFeedService.instance.markAllRead().catchError((_) {});
  }

  /// Clears the Ping tab's own badge — called when the tab becomes active
  /// and after a ping is revealed or answered (explicit report, 2026-10-02:
  /// "the 9+ and notifications aren't changing at all"). Unlike
  /// [markAllRead], this only touches ping/photoReply rows, so Home's and
  /// the inbox's own unread counts are untouched.
  void markPingsRead() {
    final ids = [
      for (final n in _notifs)
        if ((n.type == NotifType.ping || n.type == NotifType.photoReply) &&
            !n.isRead)
          n.id,
    ];
    if (ids.isEmpty) return;
    for (final n in _notifs) {
      if ((n.type == NotifType.ping || n.type == NotifType.photoReply)) {
        n.isRead = true;
      }
    }
    notifyListeners();
    NotificationFeedService.instance.markManyRead(ids).catchError((_) {});
  }

  void dismiss(String id) {
    AppNotif? notif;
    for (final n in _notifs) {
      if (n.id == id) {
        notif = n;
        break;
      }
    }
    if (notif == null) return;
    if (notif.isPersisted) {
      notif.isRead = true;
      notifyListeners();
      NotificationFeedService.instance.markRead(id).catchError((_) {});
    } else {
      _notifs.removeWhere((n) => n.id == id);
      notifyListeners();
    }
  }

  /// Records a hold-reveal of this notification's actor name. Optimistic:
  /// the UI un-blurs immediately and the write follows, because the reveal
  /// gesture already cost the user a full second of holding and should not
  /// also wait on the network. A failed write re-blurs on next load, which
  /// is the safe direction to fail in.
  void revealActor(String id) {
    for (final n in _notifs) {
      if (n.id == id) {
        if (n.revealed) return;
        n.revealed = true;
        notifyListeners();
        if (n.isPersisted) {
          NotificationFeedService.instance.markRevealed(id);
        }
        return;
      }
    }
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

  // ── Public fire methods ──────────────────────────────────────────────────

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

  /// Entity-level deep link: open one specific post. Wired by MainShell.
  /// When null (or the post is gone) the tap degrades to the feed tab
  /// rather than doing nothing — see navigateTo's post-family branch.
  void Function(String postId)? onOpenPost;

  /// Exact-destination router (MainShell): reads the row's own server
  /// payload (`data.screen` + ids) and opens the precise place — the post,
  /// the group, the group wall, the Dip or Friends side, the camera.
  /// Returns false to fall back to the coarse per-type routing below.
  bool Function(AppNotif notif)? onRouteNotif;

  void navigateTo(AppNotif notif) {
    if (onRouteNotif?.call(notif) ?? false) return;
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
      // Post-family: a reaction/comment/moment event is ABOUT a specific
      // post, so it opens that post rather than the feed it happens to
      // live in. postId is null for the batched/local types (bigScore,
      // milestone, mystery, batchedWatch never carry one) and for any row
      // whose post has since been deleted — both fall through to the feed,
      // which is the honest destination when the subject no longer exists.
      case NotifType.engagement:
        final pid = notif.postId;
        if (pid != null && onOpenPost != null) {
          onOpenPost!(pid);
        } else {
          onGoHome?.call();
        }
      case NotifType.batchedWatch:
      case NotifType.bigScore:
      case NotifType.milestone:
      case NotifType.mystery:
        onGoHome?.call();
      case NotifType.duoInvite:
      case NotifType.groupInvite:
      case NotifType.branchView:
      case NotifType.usAlbumMutual:
        onGoProfile?.call();
      // Deliberately inert: a report notification carries no actor_id and
      // no post_id (see notify_report_filed / resolve_report), precisely so
      // reporting can't be used to reach or identify the reported author.
      // There is nothing safe to navigate to, so tapping just marks it read.
      case NotifType.reportFiled:
      case NotifType.reportResolved:
        break;
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
// HeaderBellButton — the notifications entry point. Was home_screen.dart's
// private `_HeaderBellButton` (Home page header only); moved here and made
// public so it can also be dropped into MyProfileScreen's own banner chrome
// (explicit request to swap places with ViewedByBannerButton — see that
// screen's own doc, and viewed_by_section.dart's, for the other half of the
// swap). Self-contained: reads notifState.totalUnread directly, same as
// before — refreshes whenever an ancestor (MainShell's own notifState
// listener) rebuilds this subtree, no extra wiring needed at either call
// site.
// ---------------------------------------------------------------------------

class HeaderBellButton extends StatelessWidget {
  const HeaderBellButton({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final totalUnread = notifState.totalUnread;
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A20).withValues(alpha: 0.92),
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.border),
            ),
            child: const Icon(
              Icons.notifications_outlined,
              size: 18,
              color: AppColors.textPrimary,
            ),
          ),
          if (totalUnread > 0)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.background, width: 1.5),
                ),
                child: Center(
                  child: Text(
                    totalUnread > 9 ? '9+' : '$totalUnread',
                    style: const TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                      color: AppColors.onPrimary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
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
    // Fallback in case MainShell's startup loadReal() hasn't landed yet —
    // loadReal is safe to call more than once (see its own doc).
    notifState.loadReal();
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
    // Ping/photoReply used to push a mock PingViewSheet here (a name+colour
    // overlay with no real data, no camera, no ping id) — replaced by a
    // real deep link: navigateTo's ping/photoReply branches now call
    // MainShell.onOpenPingNotif, which switches to the real Ping tab and
    // focuses the actual ping card (see main_shell.dart's own doc). No
    // sheet is pushed on top of this screen any more, so there's no
    // next-frame timing to get right — navigateTo can run before or after
    // the pop below without racing anything.
    // Close the list FIRST, then route. It used to route and then pop,
    // and when the destination was a pushed screen (a post, a group) that
    // pop closed the destination instead — the tap looked like it did
    // nothing.
    Navigator.of(context).pop();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => notifState.navigateTo(notif),
    );
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
    // High priority (real 'major'-tier rows — pings — plus any local
    // high-priority nudge) always first.
    final priority = notifs.where((n) => n.isHighPriority && !n.isRead).toList();
    final pings = notifs
        .where((n) =>
            (n.type == NotifType.ping || n.type == NotifType.photoReply) &&
            !n.isHighPriority &&
            !n.isRead)
        .toList();
    // LAUNCH-BLOCKING FIX. This used to be an allowlist of 7 specific
    // NotifTypes. NotifType.discussion, .milestone, .rank, .usAlbumMutual,
    // .reportFiled, .reportResolved and .digest were never in it, so an
    // unread, non-major row of any of those types fell into NONE of the
    // four buckets below — invisible in the inbox while still counting
    // toward totalUnread/unreadHome, i.e. a badge pointing at nothing the
    // user could see or dismiss. Verified live (unread, non-major rows):
    // discussion 52 (community_post/group_added/group_dip/group_post),
    // milestone 69 (streak_risk_red/streak_standing/level_progress/
    // start_streak_nudge/streak_risk_blue), rank 12, usAlbumMutual 4,
    // reportFiled 1 — 138 total, and growing every cron tick.
    //
    // Now a genuine catch-all: everything that isn't Priority (major tier)
    // and isn't a ping lands here. Priority is exhaustive by TIER, not
    // type, so this list can never miss a future NotifType the way the
    // old allowlist did — there is no third state for an unread row to
    // fall into.
    final activity = notifs
        .where((n) =>
            n.type != NotifType.ping &&
            n.type != NotifType.photoReply &&
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
      ],
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
                    _NotifTitle(notif: notif),
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
                    if (notif.type == NotifType.duoInvite ||
                        notif.type == NotifType.groupInvite)
                      _InviteActions(notif: notif),
                    if ((notif.type == NotifType.usAlbumMutual &&
                            notif.data['action'] == 'approve') ||
                        notif.data['group_post_id'] != null)
                      _AudienceAction(notif: notif),
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
      NotifType.duoInvite => (Icons.photo_album_outlined, AppColors.coral),
      NotifType.groupInvite => (Icons.group_add_outlined, AppColors.coral),
      NotifType.branchView => (Icons.school_outlined, AppColors.textMuted),
      NotifType.usAlbumMutual => (Icons.photo_library_outlined, AppColors.primary),
      NotifType.reportFiled => (Icons.flag_outlined, AppColors.textMuted),
      NotifType.reportResolved => (Icons.gavel_rounded, AppColors.coral),
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
            "You'll see reactions, pings, and friend activity here",
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


// ---------------------------------------------------------------------------
// _NotifTitle — the inbox row's headline.
//
// For a ping or ping-reply that HAS a resolvable actor, renders the actor's
// name blurred until hold-revealed. Everything else renders the server's
// own title verbatim, unchanged.
//
// The name is composed CLIENT-SIDE rather than by rewriting the trigger's
// title text, deliberately: `notifications.title` is also what the push
// payload carries, and a push notification cannot be hold-revealed on a
// lock screen. The server keeps writing the unnamed, anonymity-safe
// 'Someone pinged you 👋' — this only enriches the in-app row, where the
// gesture actually exists.
// ---------------------------------------------------------------------------

class _NotifTitle extends StatelessWidget {
  const _NotifTitle({required this.notif});

  final AppNotif notif;

  /// The sentence tail for the two types that carry a blurred name. Null
  /// for every other type, which is what routes them to the plain title.
  String? get _suffix => switch (notif.type) {
        NotifType.ping => ' pinged you 👋',
        NotifType.photoReply => ' replied to your ping 🔥',
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final style = GoogleFonts.inter(
      fontSize: 13,
      fontWeight: notif.isRead ? FontWeight.w400 : FontWeight.w600,
      color: AppColors.textPrimary,
      height: 1.35,
    );

    final name = notif.actorName;
    final suffix = _suffix;

    // No actor (anonymous ping, system notification) or not a ping-family
    // row: nothing to mask, show exactly what the server wrote.
    if (name == null || name.isEmpty || suffix == null) {
      return Text(notif.title, style: style);
    }

    return BlurredActorLine(
      actorName: name,
      suffix: suffix,
      revealed: notif.revealed,
      onRevealed: () => notifState.revealActor(notif.id),
      style: style,
    );
  }
}

// ---------------------------------------------------------------------------
// Inline Accept / Decline for consent requests (Duo + group album invites).
// Both stay pending until the recipient acts; the outcome is kept on the
// AppNotif so the row doesn't offer the buttons again this session. An
// invite already answered elsewhere (profile, other device) just reports
// that it's no longer pending.
// ---------------------------------------------------------------------------

class _InviteActions extends StatefulWidget {
  const _InviteActions({required this.notif});
  final AppNotif notif;

  @override
  State<_InviteActions> createState() => _InviteActionsState();
}

class _InviteActionsState extends State<_InviteActions> {
  bool _busy = false;

  /// Null until checked. Accepting/declining a request that was already
  /// answered (or withdrawn) is a silent RLS no-op, so the buttons are only
  /// offered for an invite that is actually still pending.
  bool? _pending;

  @override
  void initState() {
    super.initState();
    if (widget.notif.inviteOutcome == null) _checkPending();
  }

  Future<void> _checkPending() async {
    final n = widget.notif;
    bool pending;
    try {
      if (n.type == NotifType.duoInvite) {
        final albumId = n.data['album_id'] as String?;
        final row = albumId == null
            ? null
            : await supabase.from('us_albums').select('status').eq('id', albumId).maybeSingle();
        pending = row?['status'] == 'pending';
      } else {
        final inviteId = n.data['invite_id'] as String?;
        final row = inviteId == null
            ? null
            : await supabase.from('group_invites').select('id').eq('id', inviteId).maybeSingle();
        pending = row != null;
      }
    } catch (_) {
      pending = true; // offline: let the tap itself report the outcome
    }
    if (mounted) setState(() => _pending = pending);
  }

  Future<void> _respond(bool accept) async {
    final n = widget.notif;
    HapticFeedback.selectionClick();
    // Optimistic: the row reads "Accepted"/"Declined" the instant it's
    // tapped instead of spinning until the server answers; a refusal
    // corrects it to "No longer pending" below.
    setState(() {
      _busy = true;
      n.inviteOutcome = accept ? 'Accepted' : 'Declined';
      n.isRead = true;
    });
    String outcome;
    try {
      if (n.type == NotifType.duoInvite) {
        final albumId = n.data['album_id'] as String?;
        if (albumId == null) throw StateError('no album');
        if (accept) {
          await DuoService.instance.accept(albumId);
        } else {
          await DuoService.instance.declinePending(albumId);
        }
      } else {
        final inviteId = n.data['invite_id'] as String?;
        final groupId = n.data['group_id'] as String?;
        final done = inviteId != null
            ? await GroupService.instance.respondInvite(inviteId, accept: accept)
            : groupId == null
                ? null
                : await GroupService.instance.respondInviteForGroup(groupId, accept: accept);
        if (done == null) throw StateError('no longer pending');
      }
      outcome = accept ? 'Accepted' : 'Declined';
    } catch (_) {
      outcome = 'No longer pending';
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      n.inviteOutcome = outcome;
      n.isRead = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final outcome = widget.notif.inviteOutcome ??
        (_pending == false ? 'No longer pending' : null);
    if (_pending == null && outcome == null) return const SizedBox(height: 8);
    if (outcome != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          outcome,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textMuted,
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          ElevatedButton(
            onPressed: _busy ? null : () => _respond(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Accept', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: _busy ? null : () => _respond(false),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              side: const BorderSide(color: AppColors.border),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Decline', style: TextStyle(fontSize: 12.5)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// "Pick your audience" actions on someone else's shared-album post:
//  * Duo photo waiting on me: choose my side's audience and approve — that
//    is what puts it live (approve_duo_photo).
//  * Group post: share it onward to my circles/communities
//    (share_group_post). Re-sharing replaces my earlier choice.
// ---------------------------------------------------------------------------

class _AudienceAction extends StatefulWidget {
  const _AudienceAction({required this.notif});
  final AppNotif notif;

  @override
  State<_AudienceAction> createState() => _AudienceActionState();
}

class _AudienceActionState extends State<_AudienceAction> {
  bool get _isDuo => widget.notif.type == NotifType.usAlbumMutual;

  /// Duo only: null until checked; false once approved (here or elsewhere).
  bool? _awaiting;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (_isDuo && widget.notif.inviteOutcome == null) _check();
  }

  Future<void> _check() async {
    final photoId = widget.notif.data['photo_id'] as String?;
    bool awaiting;
    try {
      final row = photoId == null
          ? null
          : await supabase
              .from('us_album_photos')
              .select('partner_approved_at, visibility')
              .eq('id', photoId)
              .maybeSingle();
      awaiting = row != null &&
          row['visibility'] == 'mutual' &&
          row['partner_approved_at'] == null;
    } catch (_) {
      awaiting = true;
    }
    if (mounted) setState(() => _awaiting = awaiting);
  }

  Future<void> _act() async {
    final n = widget.notif;
    setState(() => _busy = true);
    try {
      if (_isDuo) {
        final choice = await showAudiencePickerSheet(
          context,
          title: 'Post this Duo photo',
          subtitle: 'Pick who sees it on your side. It goes live to both of your audiences.',
          confirmLabel: 'Approve & post',
        );
        if (choice == null) return;
        await DuoService.instance.approvePhoto(
          n.data['photo_id'] as String,
          circleIds: choice.circleIds.toList(),
          communityIds: choice.communityIds.toList(),
        );
        n.inviteOutcome = 'Posted';
      } else {
        final postId = n.data['group_post_id'] as String;
        final prev = await GroupService.instance.myShare(postId);
        if (!mounted) return;
        final choice = await showAudiencePickerSheet(
          context,
          title: 'Share this group post',
          subtitle: 'Also show it to your own circles or communities.',
          confirmLabel: 'Share',
          initialCircleIds: prev.circleIds,
          initialCommunityIds: prev.communityIds,
        );
        if (choice == null) return;
        await GroupService.instance.sharePost(
          postId,
          circleIds: choice.circleIds,
          communityIds: choice.communityIds,
        );
        n.inviteOutcome = 'Shared';
      }
      n.isRead = true;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("That didn't go through — try again.")),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final outcome = widget.notif.inviteOutcome ??
        (_isDuo && _awaiting == false ? 'Already posted' : null);
    if (_isDuo && _awaiting == null && outcome == null) return const SizedBox(height: 8);
    if (outcome != null && _isDuo) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          outcome,
          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMuted),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: ElevatedButton.icon(
        onPressed: _busy ? null : _act,
        icon: Icon(_isDuo ? Icons.check_rounded : Icons.ios_share_rounded, size: 15),
        label: Text(
          _isDuo
              ? 'Choose audience & post'
              : (outcome == 'Shared' ? 'Shared · edit' : 'Share to my circles'),
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }
}
