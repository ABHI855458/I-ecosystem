import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../services/current_user_service.dart';
import '../../services/group_service.dart';
import '../../shared/time_ago.dart';
import 'design_preview/widgets/avatar.dart';
import 'design_preview/widgets/dashed_rrect_painter.dart';
import 'design_preview/widgets/section_eyebrow.dart';
import 'design_preview/widgets/stat_pill.dart';
import 'group_profile_screen.dart';

// ---------------------------------------------------------------------------
// GroupRosterScreen — "Roster" direction (1c), real data. Reached from
// GroupProfileCoverScreen's Members tab. Each member card shows real dip
// count, real last-dipped relative time, a real 5-day consistency bar
// (computed from that member's actual post dates), and real "hasn't dipped
// today" detection — all client-side over GroupService.fetchMembers +
// fetchPosts, same pattern GroupProfileScreen already uses for its Today
// strip and calendar.
//
// "Recent together" from the design spec has no backing: group_posts has no
// co-tagged-members column, so there's no real "posted together" signal.
// Repurposed as "Recent posts" (the group's most recent real photos) rather
// than fabricating a togetherness signal.
//
// Ping is local/session-only per the original design doc's own State
// Management section (`pingedMemberIds` — a local set, cleared at daily
// reset) — this is spec'd ephemeral UI state, not a claim about a real
// notification being sent.
// ---------------------------------------------------------------------------

class GroupRosterScreen extends StatefulWidget {
  const GroupRosterScreen({super.key, required this.groupId});

  final String groupId;

  @override
  State<GroupRosterScreen> createState() => _GroupRosterScreenState();
}

class _GroupRosterScreenState extends State<GroupRosterScreen> {
  late Future<_RosterData> _future;
  final _pinged = <String>{};

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_RosterData> _load() async {
    final group = await GroupService.instance.fetchGroup(widget.groupId);
    if (group == null) {
      throw StateError('Group not found or no longer visible');
    }
    final results = await Future.wait([
      GroupService.instance.fetchMembers(widget.groupId),
      GroupService.instance.fetchPosts(widget.groupId),
      CurrentUserService.instance.resolveId(),
    ]);
    return _RosterData(
      group: group,
      members: results[0] as List<Map<String, dynamic>>,
      posts: results[1] as List<Map<String, dynamic>>,
      myUserId: results[2] as String,
    );
  }

  void _reload() => setState(() => _future = _load());

  void _openSettings() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => GroupProfileScreen(groupId: widget.groupId)),
    ).then((_) {
      if (mounted) _reload();
    });
  }

  static int _streakFor(List<Map<String, dynamic>> posts) {
    final days = <DateTime>{};
    for (final p in posts) {
      final dt = DateTime.tryParse(p['created_at'] as String? ?? '')?.toLocal();
      if (dt != null) days.add(DateTime(dt.year, dt.month, dt.day));
    }
    final today = DateTime.now();
    var cursor = DateTime(today.year, today.month, today.day);
    if (!days.contains(cursor)) {
      cursor = cursor.subtract(const Duration(days: 1));
      if (!days.contains(cursor)) return 0;
    }
    var streak = 0;
    while (days.contains(cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  static String _startedLabel(String? createdAtRaw) {
    final dt = createdAtRaw == null ? null : DateTime.tryParse(createdAtRaw)?.toLocal();
    return dt == null ? '—' : DateFormat('MMM yyyy').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: FutureBuilder<_RosterData>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const _RosterSkeleton();
          }
          if (snap.hasError) {
            return _ErrorBody(onRetry: _reload, onBack: () => Navigator.of(context).pop());
          }

          final data = snap.data!;
          final streak = _streakFor(data.posts);
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);

          final memberStats = <_MemberStat>[];
          for (final m in data.members) {
            final userId = m['user_id'] as String?;
            final user = m['users'] as Map?;
            final name = user?['name'] as String? ?? '?';
            final myPosts = data.posts.where((p) => p['user_id'] == userId).toList()
              ..sort((a, b) => (b['created_at'] as String? ?? '').compareTo(a['created_at'] as String? ?? ''));
            final lastPost = myPosts.isEmpty ? null : myPosts.first;
            final lastDippedAt = lastPost == null ? null : DateTime.tryParse(lastPost['created_at'] as String? ?? '')?.toLocal();
            final hasPostedToday = lastDippedAt != null && DateTime(lastDippedAt.year, lastDippedAt.month, lastDippedAt.day) == today;
            final last5Days = List.generate(5, (i) {
              final day = today.subtract(Duration(days: 4 - i));
              return myPosts.any((p) {
                final dt = DateTime.tryParse(p['created_at'] as String? ?? '')?.toLocal();
                return dt != null && DateTime(dt.year, dt.month, dt.day) == day;
              });
            });
            memberStats.add(_MemberStat(
              userId: userId ?? '',
              name: name,
              isAdmin: m['role'] == 'admin',
              dipCount: myPosts.length,
              lastDippedLabel: lastDippedAt == null ? null : formatRelativeTime(lastDippedAt, withAgo: true),
              hasPostedToday: hasPostedToday,
              latestPhotoUrl: lastPost?['photo_url'] as String?,
              last5Days: last5Days,
            ));
          }

          final recentPosts = data.posts.take(6).toList();

          return SafeArea(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        GestureDetector(onTap: () => Navigator.of(context).pop(), child: Icon(Icons.arrow_back_ios_new_rounded, size: 19, color: Colors.white.withValues(alpha: 0.7))),
                        Text('Group', style: GoogleFonts.dmSans(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.3, color: Colors.white.withValues(alpha: 0.5))),
                        GestureDetector(onTap: _openSettings, child: Icon(Icons.settings_outlined, size: 19, color: Colors.white.withValues(alpha: 0.7))),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 26, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          data.group['name'] as String? ?? 'Group',
                          style: GoogleFonts.spaceGrotesk(fontSize: 30, fontWeight: FontWeight.w700, letterSpacing: -0.8, height: 1.1, color: Colors.white),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '${data.members.length} ${data.members.length == 1 ? 'person' : 'people'}, ${data.posts.length} dips',
                          style: GoogleFonts.dmSans(fontSize: 14, height: 1.5, color: Colors.white.withValues(alpha: 0.55)),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            StatPill('$streak-day streak'),
                            const SizedBox(width: 8),
                            StatPill('Since ${_startedLabel(data.group['created_at'] as String?)}'),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 26, 16, 0),
                    child: Column(
                      children: [
                        for (final m in memberStats) ...[
                          _RosterCard(
                            member: m,
                            pinged: _pinged.contains(m.userId),
                            onPing: () => setState(() => _pinged.add(m.userId)),
                          ),
                          const SizedBox(height: 10),
                        ],
                      ],
                    ),
                  ),
                  if (recentPosts.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 28, 16, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SectionEyebrow('Recent posts'),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 135,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: recentPosts.length,
                              separatorBuilder: (_, _) => const SizedBox(width: 8),
                              itemBuilder: (context, i) {
                                final photoUrl = recentPosts[i]['photo_url'] as String?;
                                return Container(
                                  width: 108,
                                  clipBehavior: Clip.antiAlias,
                                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), color: Colors.white.withValues(alpha: 0.05)),
                                  child: photoUrl == null ? null : CachedNetworkImage(imageUrl: photoUrl, fit: BoxFit.cover),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RosterData {
  const _RosterData({required this.group, required this.members, required this.posts, required this.myUserId});
  final Map<String, dynamic> group;
  final List<Map<String, dynamic>> members;
  final List<Map<String, dynamic>> posts;
  final String myUserId;
}

class _MemberStat {
  const _MemberStat({
    required this.userId,
    required this.name,
    required this.isAdmin,
    required this.dipCount,
    required this.lastDippedLabel,
    required this.hasPostedToday,
    required this.latestPhotoUrl,
    required this.last5Days,
  });
  final String userId;
  final String name;
  final bool isAdmin;
  final int dipCount;
  final String? lastDippedLabel;
  final bool hasPostedToday;
  final String? latestPhotoUrl;
  final List<bool> last5Days;
}

class _RosterCard extends StatelessWidget {
  const _RosterCard({required this.member, required this.pinged, required this.onPing});
  final _MemberStat member;
  final bool pinged;
  final VoidCallback onPing;

  @override
  Widget build(BuildContext context) {
    if (!member.hasPostedToday) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.02), borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.white.withValues(alpha: 0.1))),
        child: Row(
          children: [
            CustomPaint(painter: const DashedRRectPainter(color: Color(0x26FFFFFF), radius: 13), child: const SizedBox(width: 58, height: 72)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(member.name, style: GoogleFonts.spaceGrotesk(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.5))),
                  const SizedBox(height: 4),
                  Text("Hasn't dipped today", style: GoogleFonts.dmSans(fontSize: 12.5, color: Colors.white.withValues(alpha: 0.3))),
                ],
              ),
            ),
            GestureDetector(
              onTap: pinged ? null : onPing,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: pinged ? 0.05 : 0.1), borderRadius: BorderRadius.circular(30)),
                child: Text(pinged ? 'Pinged' : 'Ping', style: GoogleFonts.dmSans(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: pinged ? 0.4 : 1))),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.045), borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.white.withValues(alpha: 0.06))),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 72,
            clipBehavior: Clip.antiAlias,
            alignment: Alignment.bottomCenter,
            padding: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              gradient: member.latestPhotoUrl == null ? LinearGradient(colors: Avatar.gradientFor(member.userId), begin: Alignment.topLeft, end: Alignment.bottomRight) : null,
            ),
            child: member.latestPhotoUrl != null ? CachedNetworkImage(imageUrl: member.latestPhotoUrl!, fit: BoxFit.cover, width: 58, height: 72) : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(child: Text(member.name, overflow: TextOverflow.ellipsis, style: GoogleFonts.spaceGrotesk(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white))),
                    if (member.isAdmin) ...[
                      const SizedBox(width: 7),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                        child: Text('ADMIN', style: GoogleFonts.dmSans(fontSize: 9.5, fontWeight: FontWeight.w600, letterSpacing: 0.4, color: Colors.white.withValues(alpha: 0.6))),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${member.lastDippedLabel ?? 'Dipped'} · ${member.dipCount} ${member.dipCount == 1 ? 'dip' : 'dips'}',
                  style: GoogleFonts.dmSans(fontSize: 12.5, color: Colors.white.withValues(alpha: 0.45)),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (final dipped in member.last5Days) ...[
                      Container(width: 22, height: 6, decoration: BoxDecoration(color: Colors.white.withValues(alpha: dipped ? 0.5 : 0.12), borderRadius: BorderRadius.circular(3))),
                      if (dipped != member.last5Days.last) const SizedBox(width: 4),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RosterSkeleton extends StatelessWidget {
  const _RosterSkeleton();

  Widget _block({double? width, required double height, double radius = 14}) => Container(
        width: width,
        height: height,
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(radius)),
      );

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_block(width: 220, height: 30), _block(height: 80), _block(height: 80), _block(height: 80)]),
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.onRetry, required this.onBack});
  final VoidCallback onRetry;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Align(alignment: Alignment.centerLeft, child: GestureDetector(onTap: onBack, child: Icon(Icons.arrow_back_ios_new_rounded, size: 19, color: Colors.white.withValues(alpha: 0.7)))),
          ),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline_rounded, color: Colors.white.withValues(alpha: 0.4), size: 32),
                  const SizedBox(height: 12),
                  Text("Couldn't load this group.", style: GoogleFonts.dmSans(color: Colors.white.withValues(alpha: 0.5))),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: onRetry,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.09), borderRadius: BorderRadius.circular(10)),
                      child: Text('Retry', style: GoogleFonts.dmSans(color: Colors.white, fontWeight: FontWeight.w600)),
                    ),
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
