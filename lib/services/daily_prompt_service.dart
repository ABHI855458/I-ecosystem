import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/supabase_config.dart';
import 'prompt_service.dart';

/// One entry in the anon feed's rotating prompt bar — one per joined
/// community, sourced from the dashboard-authored `daily_prompts` row for
/// that community.
class DailyPrompt {
  const DailyPrompt({
    required this.id,
    required this.communityId,
    required this.communityName,
    required this.text,
    this.kind = 'photo',
    this.responseCount,
    this.windowKey,
  });

  final String id;
  final String communityId;
  final String communityName;
  final String text;

  /// 'photo' | 'text' — how this prompt expects to be answered.
  final String kind;

  /// Responses so far in this window, from the scored RPC. Null for the
  /// legacy rotation path, which fetches counts separately.
  final int? responseCount;

  /// Which of the eight daily windows this was chosen for. Null on the
  /// legacy path.
  final String? windowKey;
}

/// Feeds the anon feed's prompt bar from the dashboard-managed
/// `daily_prompts` table, instead of the fully client-side hardcoded list
/// in prompt_service.dart. One prompt per joined community, ordered by
/// community name then created_at so the rotation order is stable across
/// rebuilds — the anon feed screen cycles through this list on a timer.
class DailyPromptService {
  DailyPromptService._();
  static final instance = DailyPromptService._();

  /// `promptId|windowKey` pairs already sent by [commitShown] this session.
  final Set<String> _committedShown = {};

  /// Interleaves prompts so consecutive entries come from different
  /// communities. Deterministic: communities are ordered by name and their
  /// prompts by id, so the rotation is identical across rebuilds and between
  /// two members of the same set of communities.
  static List<DailyPrompt> _roundRobin(List<DailyPrompt> prompts) {
    if (prompts.length < 2) return prompts;

    final byCommunity = <String, List<DailyPrompt>>{};
    for (final p in prompts) {
      byCommunity.putIfAbsent(p.communityId, () => <DailyPrompt>[]).add(p);
    }
    for (final list in byCommunity.values) {
      list.sort((a, b) => a.id.compareTo(b.id));
    }

    final order = byCommunity.keys.toList()
      ..sort((a, b) {
        final an = byCommunity[a]!.first.communityName.toLowerCase();
        final bn = byCommunity[b]!.first.communityName.toLowerCase();
        final byName = an.compareTo(bn);
        return byName != 0 ? byName : a.compareTo(b);
      });

    final out = <DailyPrompt>[];
    var round = 0;
    var added = true;
    while (added) {
      added = false;
      for (final key in order) {
        final list = byCommunity[key]!;
        if (round < list.length) {
          out.add(list[round]);
          added = true;
        }
      }
      round++;
    }
    return out;
  }

  /// Returns one active prompt per community the signed-in user has
  /// joined (via `community_members`, keyed on auth.uid() — see
  /// community_service.dart). Falls back to the global (`community_id IS
  /// NULL`) default set when the user has joined nothing, then to
  /// PromptService's hardcoded list as a last resort so the bar is never
  /// empty.
  Future<List<DailyPrompt>> fetchRotation() async {
    final authId = supabase.auth.currentUser?.id;
    if (authId != null) {
      try {
        // Same fix as CommunityService.fetchMyCommunities: without the
        // !inner + deleted_at filter, a stale membership in a since-
        // deactivated community still pulled that community's prompts
        // into this (fallback-only) rotation.
        final memberRows = await supabase
            .from('community_members')
            .select('community_id, communities!inner(deleted_at)')
            .eq('user_id', authId)
            .isFilter('communities.deleted_at', null)
            .timeout(const Duration(seconds: 10));
        final communityIds = (memberRows as List)
            .map((r) => (r as Map)['community_id'] as String?)
            .whereType<String>()
            .toSet()
            .toList();

        if (communityIds.isNotEmpty) {
          final rows = await supabase
              .from('daily_prompts')
              .select('id, prompt_text, community_id, communities(name)')
              .eq('active', true)
              .inFilter('community_id', communityIds)
              .timeout(const Duration(seconds: 10));
          final prompts = (rows as List)
              .map((r) {
                final m = r as Map;
                final community = m['communities'] as Map?;
                return DailyPrompt(
                  id: m['id'] as String,
                  communityId: m['community_id'] as String,
                  communityName: community?['name'] as String? ?? 'Community',
                  text: m['prompt_text'] as String,
                );
              })
              .toList();
          // ROUND-ROBIN across communities, not grouped by community.
          //
          // Sorting by (community, id) put every prompt from the first
          // community before any prompt from the second, so a member of four
          // communities saw the same community's prompts over and over before
          // the bar ever reached the next one. Interleaving takes the first
          // prompt of each community in turn, then the second of each, and so
          // on — so every community is represented early, and a community
          // with more prompts than the others simply keeps contributing after
          // the shorter ones are exhausted. The bar loops back to the start
          // once the whole list is consumed (see the caller's index wrap).
          final interleaved = _roundRobin(prompts);
          if (interleaved.isNotEmpty) return interleaved;
        }
      } catch (_) {
        // Falls through to the global/offline fallback below.
      }
    }

    try {
      final rows = await supabase
          .from('daily_prompts')
          .select('id, prompt_text')
          .eq('active', true)
          .isFilter('community_id', null)
          .order('created_at')
          .timeout(const Duration(seconds: 10));
      final prompts = (rows as List)
          .map((r) => DailyPrompt(
                id: (r as Map)['id'] as String,
                communityId: '',
                communityName: 'Everyone',
                text: r['prompt_text'] as String,
              ))
          .toList();
      if (prompts.isNotEmpty) return prompts;
    } catch (_) {
      // Falls through to the offline fallback below.
    }

    // Last resort: PromptService's hardcoded list, one entry, no DB ids —
    // composing against it should not attach a community_id/prompt_id.
    return [
      DailyPrompt(
        id: '',
        communityId: '',
        communityName: 'Everyone',
        text: PromptService.instance.current,
      ),
    ];
  }

  /// The SCORED prompt bar — one ranked list for the current window.
  ///
  /// Replaces [fetchRotation]'s client-side round-robin, which cycled every
  /// prompt from every joined community on a 30s timer. That ignored
  /// context entirely: a gym prompt could land at 11pm and a hostel prompt
  /// at 9am. Ranking happens server-side in `prompt_bar_for_user`
  /// (affinity x drift x freshness x social_proof x novelty) so the app,
  /// the dashboard and the simulator cannot disagree about the rules.
  ///
  /// Index 0 is the prompt bar. The rest are the runner-up chips — the
  /// choice exists but is not demanded.
  ///
  /// Returns an empty list rather than throwing; the caller falls back to
  /// [fetchRotation], so a network blip degrades to the old behaviour
  /// instead of an empty bar.
  Future<List<DailyPrompt>> fetchScoredBar({String feedScope = 'everyone'}) async {
    try {
      final rows = await supabase
          .rpc('prompt_bar_for_user', params: {'p_feed_scope': feedScope})
          .timeout(const Duration(seconds: 10));
      return [
        for (final r in (rows as List))
          DailyPrompt(
            id: (r as Map)['prompt_id'] as String,
            communityId: r['community_id'] as String? ?? '',
            communityName: r['community_name'] as String? ?? 'Everyone',
            text: r['prompt_text'] as String? ?? '',
            kind: r['prompt_kind'] as String? ?? 'photo',
            responseCount: (r['response_count'] as num?)?.toInt(),
            windowKey: r['window_key'] as String?,
          ),
      ]..removeWhere((p) => p.text.isEmpty);
    } catch (_) {
      return const [];
    }
  }

  /// Records that [prompt] was actually SHOWN, which is what makes the
  /// freshness and novelty terms accumulate. Without this the score
  /// silently degenerates to affinity x drift. Fails soft — a missed
  /// impression is a ranking nudge, never worth interrupting the feed.
  ///
  /// Once per prompt per window per app session: the bar's 5s cycle calls
  /// this on every rotation, which sent ~45k calls/day and pushed every
  /// prompt's seen_count past 1 with last_seen_at always "now", flattening
  /// the freshness term for everyone.
  Future<void> commitShown(DailyPrompt prompt) async {
    if (prompt.id.isEmpty) return;
    if (!_committedShown.add('${prompt.id}|${prompt.windowKey ?? ''}')) return;
    try {
      await supabase.rpc('commit_prompt_bar', params: {
        'p_community_id': prompt.communityId.isEmpty ? null : prompt.communityId,
        'p_prompt_id': prompt.id,
      }).timeout(const Duration(seconds: 8));
    } catch (_) {
      // Ignored on purpose — see doc above.
    }
  }

  /// Live count of anon posts answering [promptId] — the prompt bar's
  /// "N responding" figure. Reads `posts_feed`, not `posts` directly:
  /// `posts_select`'s RLS only lets a viewer read their OWN anonymous
  /// rows, so a plain count against `posts` would only ever count the
  /// caller's own replies. `posts_feed` is the one read path anyone can
  /// see other members' anon posts through (subject to its own
  /// community-membership scoping), and now carries `prompt_id` (see
  /// migration 20260904140000_posts_feed_prompt_id.sql).
  ///
  /// Returns 0 for an empty/client-only prompt id (the PromptService
  /// hardcoded fallback has no DB row to count against) rather than
  /// erroring — 0 is the correct, meaningful answer for "how many people
  /// have answered a prompt with no backing row," not a fallback default.
  Future<int> fetchResponseCount(String promptId) async {
    if (promptId.isEmpty) return 0;
    try {
      final rows = await supabase
          .from('posts_feed')
          .select('id')
          .eq('prompt_id', promptId)
          .timeout(const Duration(seconds: 10));
      return (rows as List).length;
    } catch (_) {
      return 0;
    }
  }
}

/// Shared cycling behavior for any screen that shows [DailyPromptService]'s
/// scored bar — the anon feed's peek prompt and the friends feed's prompt
/// bar both use this now, instead of each screen owning its own copy of
/// the rotation array, the 5s cycle timer, the 5-min window-change poll,
/// and the impression/response-count bookkeeping. One controller means a
/// fix or a behavior change lands in both places at once, not just
/// whichever screen happened to get edited.
///
/// [feedScope] is 'anon' or 'everyone' — passed straight through to
/// [DailyPromptService.fetchScoredBar]/[DailyPromptService.fetchRotation].
///
/// Usage: create one per screen (`late final _bar = PromptBarController
/// (feedScope: 'anon')`), call [load] once (e.g. from initState — it also
/// starts both internal timers, idempotently), `addListener` to trigger a
/// rebuild, and call [dispose] from the owning State's own dispose.
class PromptBarController extends ChangeNotifier {
  PromptBarController({required this.feedScope});

  final String feedScope;

  List<DailyPrompt> _rotation = const [];
  int _idx = 0;

  /// Live "N responding" per prompt id — same map shape and same
  /// null-while-loading semantics the anon feed's own field used to have,
  /// now shared. Public: both screens' widgets read straight from this.
  final Map<String, int> responseCounts = {};

  Timer? _windowTimer;
  Timer? _cycleTimer;
  bool _started = false;

  /// Every notifyListeners() below sits AFTER an `await` on a network call,
  /// so the owning State can dispose this controller while that call is
  /// still in flight — ChangeNotifier then throws "A PromptBarController
  /// was used after being disposed". Cancelling the timers in dispose isn't
  /// enough: it's the in-flight fetch, not the timer, that lands late.
  ///
  /// Normally invisible because the fetch returns in milliseconds. It shows
  /// up for real whenever the request is slow or failing — observed on an
  /// emulator whose DNS had stopped resolving, where every fetch hung long
  /// enough for a screen dispose to always beat it.
  bool _disposed = false;

  List<DailyPrompt> get rotation => _rotation;

  /// The prompt on screen right now — index 0 until [_advance] has run,
  /// then whichever entry the 5s cycle has reached. The `%` means a stale
  /// index from a longer previous rotation can never run off the end of a
  /// shorter new one.
  DailyPrompt? get active =>
      _rotation.isEmpty ? null : _rotation[_idx % _rotation.length];

  /// Fetches the current window's ranked bar and (re)starts the two
  /// timers. Safe to call more than once — a pull-to-refresh re-loading
  /// the whole screen calls this again, and the timers are only ever
  /// started the first time ([_started] guards it), never doubled up.
  Future<void> load() async {
    await _fetchAndShow(resetIndex: true);
    if (_started) return;
    _started = true;
    // Re-checks whether the window has turned over — current_prompt_window
    // decides when, this only asks. Does not reshuffle who's eligible or
    // how they're scored; see _advance's own doc for why cycling through
    // the result is safe against the "N responding" problem this system
    // was built to avoid.
    _windowTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _refreshForWindow(),
    );
    // Cycles the DISPLAY through the whole ranked set for the window that
    // is actually open — reinstated by explicit request. Every entry in
    // [_rotation] already passed this window's own affinity/drift/
    // freshness/social_proof/novelty gate, exactly like index 0 always
    // has, so "N responding" for whichever one is on screen is still that
    // prompt's own real count, never a borrowed one. Not a return to the
    // old client-side round-robin over every joined community regardless
    // of time of day, which is what the original "prompt bar is constant"
    // correction was actually about.
    _cycleTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _advance(),
    );
  }

  Future<void> _fetchAndShow({required bool resetIndex}) async {
    try {
      var prompts = await DailyPromptService.instance.fetchScoredBar(
        feedScope: feedScope,
      );
      if (prompts.isEmpty) {
        prompts = await DailyPromptService.instance.fetchRotation();
      }
      if (_disposed) return;
      _rotation = prompts;
      if (resetIndex) _idx = 0;
      notifyListeners();
      unawaited(_onEnteredView(active));
    } catch (_) {
      // Leaves _rotation as it was — the caller falls back to its own
      // static prompt text when active is null.
    }
  }

  /// Re-asks the server for the window's bar. A no-op almost every time;
  /// it only changes anything once a window boundary has passed while the
  /// screen sat open. Compares against index 0 of the OLD set specifically
  /// (not whatever [active] currently is mid-cycle) — the window is what
  /// changed or didn't, and index 0 is what the top scorer was before this
  /// check, regardless of where the 5s cycle had wandered to.
  Future<void> _refreshForWindow() async {
    // Same already-queued-callback reasoning as _advance, plus the
    // post-await recheck below.
    if (_disposed) return;
    final rows = await DailyPromptService.instance.fetchScoredBar(
      feedScope: feedScope,
    );
    if (_disposed || rows.isEmpty) return;
    final next = rows.first;
    final previousTop = _rotation.isEmpty ? null : _rotation.first;
    if (previousTop != null && previousTop.id == next.id) return;
    _rotation = rows;
    _idx = 0;
    notifyListeners();
    unawaited(_onEnteredView(active));
  }

  void _advance() {
    // Guarded even though dispose() cancels _cycleTimer: a periodic
    // callback already queued on the event loop still runs after cancel(),
    // and this one calls notifyListeners() synchronously. Observed as
    // "A PromptBarController was used after being disposed" with _advance
    // at the top of the stack.
    if (_disposed || _rotation.length < 2) return;
    _idx = (_idx + 1) % _rotation.length;
    notifyListeners();
    unawaited(_onEnteredView(active));
  }

  /// A prompt entering view — whether that's the very first load, a fresh
  /// window, or a runner-up cycling in — gets the same impression/
  /// response-count treatment index 0 always got. A runner-up cycling into
  /// view is a real impression, not a preview.
  Future<void> _onEnteredView(DailyPrompt? prompt) async {
    if (prompt == null) return;
    if (prompt.responseCount != null) {
      responseCounts[prompt.id] = prompt.responseCount!;
    } else if (!responseCounts.containsKey(prompt.id)) {
      final count = await DailyPromptService.instance.fetchResponseCount(
        prompt.id,
      );
      if (_disposed) return;
      responseCounts[prompt.id] = count;
      notifyListeners();
    }
    unawaited(DailyPromptService.instance.commitShown(prompt));
  }

  @override
  void dispose() {
    _disposed = true;
    _windowTimer?.cancel();
    _cycleTimer?.cancel();
    super.dispose();
  }
}
