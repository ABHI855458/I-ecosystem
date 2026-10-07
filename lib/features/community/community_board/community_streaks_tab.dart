import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../services/community_streaks_service.dart';
import '../../../services/score_leaderboard_service.dart';
import '../../../shared/score_tier.dart';
import 'community_tokens.dart';
import '../../profile_v2/profile_v2_icons.dart';

// ---------------------------------------------------------------------------
// STREAKS tab — STANDINGS (global score board), "Top Engaged This Week"
// podium + leaderboard, TOP STREAKS list, and an AROUND YOU list under
// each board.
//
// Both boards are CAPPED and paired with their own AROUND YOU section
// (top 8 for score, top 5 for streaks — see _kScoreTopCount /
// _kStreakTopCount). AROUND YOU renders only when the caller placed
// outside that cap; a top-8/top-5 player is already visible above, so
// showing it again would just repeat their row.
//
// The green LEVEL/XP + day-grid card that used to lead this tab was
// removed on explicit request — its numbers are still live in the
// header's streak pill and in _TopEngagedCard.
//
// Every number here now comes from CommunityLeaderboard (community_
// streaks_service.dart), which wraps the community_leaderboard(uuid) RPC —
// see supabase/migrations/20260904010000_community_streaks.sql. Loading/
// fetching/realtime is owned by CommunityScreen (the scope owner); this
// widget is purely a renderer of whatever it's handed.
//
// Two disclosed simplifications versus the original mock, because the
// schema has no rank-history table to compute them honestly:
//   - The header's "▵ N THIS WEEK" pill and the leader rows' "↑41/↓8"
//     deltas both implied RANK MOVEMENT over time. Nothing here tracks a
//     rank snapshot from a week ago, so both are redefined to show WEEKLY
//     XP EARNED instead (a real, current number) rather than fabricate a
//     rank delta. See _weekDeltaPill and _LeaderRowWidget.
//   - The rival nudge's "post today to pass them" — see CommunityRival —
//     is the one hardcoded mock line that DID have a real backing field
//     (`fires_behind`); that one is now genuinely computed by the RPC.
// ---------------------------------------------------------------------------

class CommunityStreaksTab extends StatefulWidget {
  const CommunityStreaksTab({
    super.key,
    required this.loading,
    required this.error,
    required this.leaderboard,
    required this.onRetry,
  });

  /// True while a fetch is in flight AND no data has ever loaded yet — a
  /// background refresh (realtime-triggered) with existing data present
  /// does NOT set this, so the tab never flickers back to a skeleton.
  final bool loading;
  final String? error;
  final CommunityLeaderboard? leaderboard;
  final VoidCallback onRetry;

  @override
  State<CommunityStreaksTab> createState() => _CommunityStreaksTabState();
}

class _CommunityStreaksTabState extends State<CommunityStreaksTab> {
  /// How many rows each board shows before it cuts off — explicit request
  /// ("always show top 8 on score and top 5 on streaks"). Anyone ranked
  /// past these appears under AROUND YOU instead, never by extending the
  /// list.
  static const _kScoreTopCount = 8;
  static const _kStreakTopCount = 5;

  /// The app-wide COMBINED-score board (anon + ping), by anon name only.
  /// Distinct from every other list on this tab, which is per-community
  /// streak/XP — this one is global and score-ranked.
  List<ScoreLeaderboardEntry>? _scoreBoard;

  /// [_scoreBoard] split into the two things that render separately.
  ///
  /// The RPC hands back the top block PLUS a +/-3 window around the caller
  /// (migration 20260926100000_score_leaderboard_me_window), concatenated
  /// into one rank-ordered list — so the split is by RANK, not by index:
  /// everything at rank <= _kScoreTopCount is the top block, the rest is
  /// the caller's own neighbourhood. Reading it off the rank keeps this
  /// correct even if the RPC's own limit and _kScoreTopCount ever drift
  /// apart (e.g. the service asks for 8 but a future caller asks for 20).
  List<ScoreLeaderboardEntry> get _scoreTop => [
        for (final e in _scoreBoard ?? const <ScoreLeaderboardEntry>[])
          if (e.rank <= _kScoreTopCount) e,
      ];

  /// Empty whenever the caller is already inside the top block — that's
  /// what makes AROUND YOU disappear for a top-8 player rather than
  /// showing them their own row a second time.
  List<ScoreLeaderboardEntry> get _scoreAround => [
        for (final e in _scoreBoard ?? const <ScoreLeaderboardEntry>[])
          if (e.rank > _kScoreTopCount) e,
      ];

  /// TOP STREAKS, capped the same way. Unlike the score board this one
  /// arrives as a plain full list (community_leaderboard's own
  /// `top_streaks`), so the cap is a simple take().
  List<CommunityLeaderboardEntry> get _streakTop =>
      widget.leaderboard!.topStreaks.take(_kStreakTopCount).toList();

  /// Mirrors [_scoreAround]'s rule for the streak board: show AROUND YOU
  /// only when the caller isn't already visible in the capped top list.
  ///
  /// Keyed on the caller's RANK, not on `isYou` in [_streakTop]. The RPC
  /// only sets `is_you` on the aroundYou rows — the top_streaks rows carry
  /// `is_top` instead and leave `is_you` false even for the caller's own
  /// row. Checking isYou there therefore never matched, and AROUND YOU
  /// rendered under TOP STREAKS showing the caller twice (caught on
  /// device: "@anon cat" appeared as TOP STREAKS 01 and again as AROUND
  /// YOU 01). Comparing the rank the caller actually holds against the cap
  /// is what the dedupe always meant.
  bool get _showStreakAround {
    final lb = widget.leaderboard!;
    if (lb.aroundYou.isEmpty) return false;
    final mine = lb.aroundYou.where((e) => e.isYou);
    if (mine.isEmpty) return true; // can't place them — show it rather than hide
    return mine.first.rank > _kStreakTopCount;
  }

  @override
  void initState() {
    super.initState();
    _loadScoreBoard();
  }

  Future<void> _loadScoreBoard() async {
    final rows = await ScoreLeaderboardService.instance.fetch();
    if (mounted) setState(() => _scoreBoard = rows);
  }

  @override
  Widget build(BuildContext context) {
    final lb = widget.leaderboard;

    if (lb == null && widget.loading) {
      return const _StreaksSkeleton();
    }
    if (lb == null && widget.error != null) {
      return _StreaksError(message: widget.error!, onRetry: widget.onRetry);
    }
    if (lb == null) {
      // No community selected / not a member of any — CommunityScreen is
      // responsible for the page-level "join a community" empty state, so
      // this is a defensive fallback, not the primary empty path.
      return const _StreaksSkeleton();
    }

    return ListView(
      // Own scroll position, not the shared PrimaryScrollController — see
      // community_announcements_tab.dart's ListView for why.
      primary: false,
      // AlwaysScrollable so a short leaderboard still overscrolls far
      // enough to trigger the tab's RefreshIndicator.
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 108),
      children: [
        // TOP ENGAGED THIS WEEK FIRST — explicit request (screenshot of this
        // card, "include this first"), ahead of STANDINGS. See
        // score_leaderboard_guarantee_me migration: the caller's own row is
        // always present in _scoreBoard, so "Your rank" reads a real global
        // rank here.
        _TopEngagedCard(me: lb.me, scoreBoard: _scoreBoard ?? const []),
        const SizedBox(height: 16),
        // STANDINGS next — it used to lead ("let the standings be on the
        // top first"). This whole board used to sit below the XP/streak
        // cards; it leads now, because where you actually place against
        // everyone is the thing people open this tab for.
        //
        // Sourced from _scoreBoard (not lb.podium/lb.leaders, which rank
        // only THIS community's members) — otherwise the same person shows
        // up at two different ranks on one screen (e.g. #2 here, #6 below)
        // for the same total_score, which reads as broken data, not two
        // legitimately different boards.
        //
        // Capped at kScoreTopCount, NOT the full board — explicit request
        // ("in score don't give the full sheet"). The RPC returns the top
        // block plus a window around the caller; _scoreTop/_scoreAround
        // split those two apart so each renders under its own heading.
        if (_scoreTop.isNotEmpty) ...[
          const _SectionDivider(label: 'STANDINGS', trailing: 'ALL COMMUNITIES'),
          const SizedBox(height: 10),
          Column(
            children: [
              for (var i = 0; i < _scoreTop.length; i++) ...[
                _ScoreRow(entry: _scoreTop[i]),
                if (i != _scoreTop.length - 1) const SizedBox(height: 7),
              ],
            ],
          ),
          // Only when the caller placed OUTSIDE the top block — if they're
          // already shown above, repeating them here would be the same row
          // twice ("if not, remove it").
          if (_scoreAround.isNotEmpty) ...[
            const SizedBox(height: 16),
            _SectionDivider(
              label: 'AROUND YOU',
              trailing: '#${_scoreAround.first.rank} — #${_scoreAround.last.rank}',
            ),
            const SizedBox(height: 10),
            Column(
              children: [
                for (var i = 0; i < _scoreAround.length; i++) ...[
                  _ScoreRow(entry: _scoreAround[i]),
                  if (i != _scoreAround.length - 1) const SizedBox(height: 7),
                ],
              ],
            ),
          ],
          const SizedBox(height: 16),
        ],
        // The green LEVEL/XP + day-grid card (_XpLevelCard) that used to
        // sit here is REMOVED — explicit request, with a screenshot of
        // that exact card. Its level/XP/streak numbers are all still live
        // elsewhere (the header's own streak pill, _TopEngagedCard's rank
        // and XP); this only drops the one oversized card that restated
        // them.
        const SizedBox(height: 16),
        const SizedBox(height: 12),
        _SectionDivider(label: 'TOP STREAKS', trailing: '${lb.memberCount} MEMBERS'),
        const SizedBox(height: 10),
        if (_streakTop.isEmpty)
          const _EmptyLeaderboardNote(text: 'No one has posted here yet — be the first.')
        else
          Column(
            children: [
              for (var i = 0; i < _streakTop.length; i++) ...[
                _StreakRow(entry: _streakTop[i]),
                if (i != _streakTop.length - 1) const SizedBox(height: 7),
              ],
            ],
          ),
        // Same rule as STANDINGS above: AROUND YOU shows only when the
        // caller isn't already in the top block. lb.aroundYou is the RPC's
        // own per-community window and is used as-is.
        if (_showStreakAround) ...[
          const SizedBox(height: 16),
          _SectionDivider(
            label: 'AROUND YOU',
            trailing: '#${lb.aroundYou.first.rank} — #${lb.aroundYou.last.rank}',
          ),
          const SizedBox(height: 10),
          Column(
            children: [
              for (var i = 0; i < lb.aroundYou.length; i++) ...[
                _AroundYouRow(entry: lb.aroundYou[i]),
                if (i != lb.aroundYou.length - 1) const SizedBox(height: 7),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

// ── Loading / error scaffolding ─────────────────────────────────────────

class _StreaksSkeleton extends StatelessWidget {
  const _StreaksSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget block(double height, {double radius = 14}) => Container(
          height: height,
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(color: CommunityColors.cardBg, borderRadius: BorderRadius.circular(radius)),
        );
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 108),
      physics: const NeverScrollableScrollPhysics(),
      children: [
        block(300),
        block(260),
        block(52),
        block(52),
        block(52),
      ],
    );
  }
}

class _StreaksError extends StatelessWidget {
  const _StreaksError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center, style: CommunityType.pollMeta.copyWith(color: CommunityColors.textSecondary)),
            const SizedBox(height: 12),
            TextButton(onPressed: onRetry, child: Text('Retry', style: CommunityType.pollCta)),
          ],
        ),
      ),
    );
  }
}

class _EmptyLeaderboardNote extends StatelessWidget {
  const _EmptyLeaderboardNote({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Text(text, style: CommunityType.pollMeta),
    );
  }
}

class _SectionDivider extends StatelessWidget {
  const _SectionDivider({required this.label, required this.trailing});
  final String label;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label, style: CommunityType.sectionLabel(CommunityColors.textSecondary)),
        const SizedBox(width: 10),
        Expanded(child: Container(height: 1, color: CommunityColors.cardBorder)),
        const SizedBox(width: 10),
        Text(trailing, style: CommunityType.sectionMeta),
      ],
    );
  }
}

// ── XP / level card ────────────────────────────────────────────────────

Color _streakColor(double v) {
  if (v <= 0) return CommunityColors.streakEmpty;
  if (v <= 0.25) return const Color(0xFF3A5518);
  if (v <= 0.5) return CommunityColors.streakMed;
  return CommunityColors.streakHigh;
}

// ── Top Engaged This Week ─────────────────────────────────────────────

/// Days (date-only, IST) until the next weekly XP reset. India has no DST,
/// so a fixed +5:30 offset is exact — no `timezone` package init dependency
/// needed for this display-only calculation. Mirrors current_week_start()
/// in 20260904010000_community_streaks.sql: if today IS Monday, the reset
/// already happened this morning, so the NEXT one is 7 days out.
String _resetsInLabel() {
  final nowIst = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
  final daysUntilMonday = (8 - nowIst.weekday) % 7;
  final nextMondayMidnight = DateTime(nowIst.year, nowIst.month, nowIst.day)
      .add(Duration(days: daysUntilMonday == 0 ? 7 : daysUntilMonday));
  final diff = nextMondayMidnight.difference(nowIst);
  final d = diff.inDays;
  final h = diff.inHours.remainder(24);
  return '${d}D ${h}H';
}

class _TopEngagedCard extends StatelessWidget {
  const _TopEngagedCard({required this.me, required this.scoreBoard});
  final CommunityMe me;
  final List<ScoreLeaderboardEntry> scoreBoard;

  @override
  Widget build(BuildContext context) {
    final podium = scoreBoard.take(3).toList();
    final leaders = scoreBoard.length > 3 ? scoreBoard.sublist(3, scoreBoard.length > 6 ? 6 : scoreBoard.length) : const <ScoreLeaderboardEntry>[];
    final topScore = scoreBoard.isNotEmpty ? scoreBoard.first.totalScore : 0;
    ScoreLeaderboardEntry? mine;
    for (final e in scoreBoard) {
      if (e.isMe) {
        mine = e;
        break;
      }
    }
    // Falls back to the community-scoped rank/score only if the caller's
    // row genuinely isn't in scoreBoard yet (still loading, or a real
    // zero-score user the RPC excludes) — never as the steady-state path.
    final myRank = mine?.rank ?? me.weekRank;
    final myScore = mine?.totalScore ?? me.weekXp;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
      decoration: BoxDecoration(color: CommunityColors.cardBg, border: Border.all(color: CommunityColors.cardBorder), borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Top Engaged This Week', style: CommunityType.cardTitle),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(border: Border.all(color: const Color(0x59FA2D64)), borderRadius: BorderRadius.circular(10)),
                child: Column(
                  children: [
                    Text('RESETS IN', style: CommunityType.resetsLabel),
                    Text(_resetsInLabel(), style: CommunityType.resetsValue),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            margin: const EdgeInsets.only(bottom: 18),
            decoration: BoxDecoration(color: const Color(0x14FA2D64), border: Border.all(color: const Color(0x4DFA2D64)), borderRadius: BorderRadius.circular(10)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Your rank', style: CommunityType.yourRankLabel),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text('#$myRank', style: CommunityType.yourRankValue),
                    const SizedBox(width: 8),
                    Text('$myScore XP', style: CommunityType.yourRankPts),
                  ],
                ),
              ],
            ),
          ),
          if (podium.isEmpty)
            const _EmptyLeaderboardNote(text: 'No activity this week yet.')
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(child: _podiumSlotFor(podium, 2, '🥈', false)),
                const SizedBox(width: 11),
                Expanded(child: _podiumSlotFor(podium, 1, '🥇', true)),
                const SizedBox(width: 11),
                Expanded(child: _podiumSlotFor(podium, 3, '🥉', false)),
              ],
            ),
          if (leaders.isNotEmpty) ...[
            const SizedBox(height: 11),
            Column(
              children: [for (final row in leaders) _LeaderRowWidget(entry: row, topScore: topScore)],
            ),
          ],
        ],
      ),
    );
  }

  Widget _podiumSlotFor(List<ScoreLeaderboardEntry> podium, int rank, String medal, bool lead) {
    ScoreLeaderboardEntry? entry;
    for (final p in podium) {
      if (p.rank == rank) {
        entry = p;
        break;
      }
    }
    if (entry == null) return const SizedBox.shrink();
    return _PodiumSpot(entry: entry, medal: medal, lead: lead);
  }
}

class _PodiumSpot extends StatelessWidget {
  const _PodiumSpot({required this.entry, required this.medal, required this.lead});
  final ScoreLeaderboardEntry entry;
  final String medal;
  final bool lead;

  @override
  Widget build(BuildContext context) {
    final avatarSize = lead ? 64.0 : 52.0;
    final avatarUrl = entry.avatarUrl;
    final initial = entry.anonName.isNotEmpty ? entry.anonName[0].toUpperCase() : '?';
    return Column(
      children: [
        if (!lead) Text(medal, style: const TextStyle(fontSize: 16, height: 1)),
        Container(
          width: avatarSize,
          height: avatarSize,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: CommunityColors.cardBg2,
            shape: BoxShape.circle,
            border: Border.all(color: lead ? CommunityColors.pink : const Color(0x66FA2D64), width: lead ? 2 : 1.5),
            boxShadow: [BoxShadow(color: CommunityColors.pink.withValues(alpha: lead ? 0.4 : 0.18), blurRadius: lead ? 22 : 14)],
          ),
          // ClipOval + a hard-sized child, not the Container's own
          // decoration-clip — that clips to the OUTER edge of the box, so
          // the border painted centered on that same edge visibly ate into
          // the photo on one side (fine for the plain-color initial circle,
          // which has no image to misalign against). Explicit clip forces
          // the photo itself to fill edge-to-edge inside the border,
          // matching the mask photo's fit exactly regardless of the source
          // image's own aspect ratio.
          child: avatarUrl != null
              ? ClipOval(
                  child: SizedBox(
                    width: avatarSize,
                    height: avatarSize,
                    child: CachedNetworkImage(memCacheWidth: 1080, imageUrl: avatarUrl, fit: BoxFit.cover, width: avatarSize, height: avatarSize),
                  ),
                )
              : Text(initial, style: lead ? CommunityType.podiumAvatarInitialLead : CommunityType.podiumAvatarInitial),
        ),
        if (lead) Padding(padding: const EdgeInsets.only(top: 6), child: Text(medal, style: const TextStyle(fontSize: 13, height: 1))),
        const SizedBox(height: 6),
        Text(entry.anonName, style: lead ? CommunityType.podiumNameLead : CommunityType.podiumName, overflow: TextOverflow.ellipsis),
        Text('${entry.totalScore}', style: lead ? CommunityType.podiumScoreLead : CommunityType.podiumScore),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          height: lead ? 76 : 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: lead ? const Color(0x24FA2D64) : null,
            border: Border.all(color: lead ? const Color(0x80FA2D64) : CommunityColors.chipBorder),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text('#${entry.rank}', style: lead ? CommunityType.podiumRankTagLead : CommunityType.podiumRankTag),
        ),
      ],
    );
  }
}

class _LeaderRowWidget extends StatelessWidget {
  const _LeaderRowWidget({required this.entry, required this.topScore});
  final ScoreLeaderboardEntry entry;
  final int topScore;

  @override
  Widget build(BuildContext context) {
    final initial = entry.anonName.isNotEmpty ? entry.anonName[0].toUpperCase() : '?';
    final progress = topScore > 0 ? entry.totalScore / topScore : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          SizedBox(width: 20, child: Text('#${entry.rank}', style: CommunityType.leaderRank)),
          const SizedBox(width: 11),
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: CommunityColors.cardBg2, shape: BoxShape.circle, border: Border.all(color: const Color(0x4DFA2D64))),
            child: Text(initial, style: CommunityType.leaderAvatarInitial),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(entry.anonName, style: CommunityType.leaderHandle, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: Container(
                    height: 3,
                    color: const Color(0xFF20222B),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: progress.clamp(0.0, 1.0),
                      child: Container(color: CommunityColors.textSecondary),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 11),
          Text('${entry.totalScore}', style: CommunityType.leaderScore),
        ],
      ),
    );
  }
}

// ── TOP STREAKS / AROUND YOU rows ─────────────────────────────────────

class _StreakRow extends StatelessWidget {
  const _StreakRow({required this.entry});
  final CommunityLeaderboardEntry entry;

  @override
  Widget build(BuildContext context) {
    final days = entry.days ?? const [];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: CommunityColors.cardBg, border: Border.all(color: CommunityColors.cardBorder), borderRadius: BorderRadius.circular(12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 22,
            child: Text(entry.rank.toString().padLeft(2, '0'), style: entry.isTop ? CommunityType.streakRowRank : CommunityType.streakRowRankDim),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(child: Text(entry.handle, style: CommunityType.streakRowHandle, overflow: TextOverflow.ellipsis)),
                    if (entry.isTop) ...[
                      const SizedBox(width: 7),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(color: CommunityColors.lime, borderRadius: BorderRadius.circular(4)),
                        child: Text('TOP', style: CommunityType.streakRowTopTag),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    for (var i = 0; i < days.length; i++) ...[
                      Container(width: 7, height: 11, decoration: BoxDecoration(color: _streakColor(days[i]), borderRadius: BorderRadius.circular(2))),
                      if (i != days.length - 1) const SizedBox(width: 2.5),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PV2Icons.iceFlame(10),
                  const SizedBox(width: 4),
                  Text('${entry.streak ?? 0}', style: entry.isTop ? CommunityType.streakRowFire : CommunityType.streakRowFireDim),
                ],
              ),
              const SizedBox(height: 4),
              Text('${entry.postCount ?? 0} POSTS', style: CommunityType.streakRowPosts),
            ],
          ),
        ],
      ),
    );
  }
}



/// One row of the per-community AROUND YOU list.
///
/// Same shape as [_StreakRow] (rank, handle, day-grid, fire count) but with
/// the caller's own row given a lime border, gradient fill and a "YOU" tag,
/// so their position is findable at a glance in a list whose whole purpose
/// is showing where they sit. Everyone else renders in the dimmed,
/// ordinary treatment.
class _AroundYouRow extends StatelessWidget {
  const _AroundYouRow({required this.entry});
  final CommunityLeaderboardEntry entry;

  @override
  Widget build(BuildContext context) {
    final days = entry.days ?? const [];
    final you = entry.isYou;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: you
          ? BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1A1F12), Color(0xFF15161C)],
              ),
              border: Border.all(color: CommunityColors.lime, width: 1.5),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: CommunityColors.lime.withValues(alpha: 0.14),
                  blurRadius: 24,
                ),
              ],
            )
          : BoxDecoration(
              color: CommunityColors.cardBg,
              border: Border.all(color: CommunityColors.cardBorder),
              borderRadius: BorderRadius.circular(12),
            ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 22,
            child: Text(
              entry.rank.toString().padLeft(2, '0'),
              style: you
                  ? CommunityType.streakRowRank
                  : CommunityType.streakRowRankDim,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        entry.handle,
                        style: you
                            ? CommunityType.streakRowHandleYou
                            : CommunityType.streakRowHandle,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (you) ...[
                      const SizedBox(width: 7),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: CommunityColors.lime,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text('YOU', style: CommunityType.streakRowYouTag),
                      ),
                      if (entry.level != null) ...[
                        const SizedBox(width: 7),
                        Text(
                          'LVL ${entry.level}',
                          style: CommunityType.streakRowLevelTag,
                        ),
                      ],
                    ],
                  ],
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    for (var i = 0; i < days.length; i++) ...[
                      Container(
                        width: 7,
                        height: 11,
                        decoration: BoxDecoration(
                          color: _streakColor(days[i]),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      if (i != days.length - 1) const SizedBox(width: 2.5),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PV2Icons.iceFlame(10),
              const SizedBox(width: 4),
              Text(
                '${entry.streak ?? 0}',
                style: you
                    ? CommunityType.streakRowFire
                    : CommunityType.streakRowFireDim,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One row of the app-wide combined-score board.
///
/// Anon name only — this board is public, and the RPC behind it never
/// returns a real name or a user id, so there is nothing here to leak.
class _ScoreRow extends StatelessWidget {
  const _ScoreRow({required this.entry});

  final ScoreLeaderboardEntry entry;

  @override
  Widget build(BuildContext context) {
    final info = tierInfoForScore(entry.totalScore);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: entry.isMe
            ? CommunityColors.pink.withValues(alpha: 0.10)
            : Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: entry.isMe
              ? CommunityColors.pink.withValues(alpha: 0.35)
              : Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: Text('#${entry.rank}', style: entry.isMe ? CommunityType.streakRowRank : CommunityType.streakRowRankDim),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  entry.isMe ? '${entry.anonName} (you)' : entry.anonName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: entry.isMe
                      ? CommunityType.streakRowHandleYou
                      : CommunityType.streakRowHandle,
                ),
                const SizedBox(height: 2),
                Text(info.title.toUpperCase(), style: CommunityType.chipInactive),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text('${entry.totalScore}', style: CommunityType.streakRowFire),
        ],
      ),
    );
  }
}
