import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'mock_group_data.dart';
import 'widgets/avatar.dart';
import 'widgets/dashed_rrect_painter.dart';
import 'widgets/section_eyebrow.dart';
import 'widgets/stat_pill.dart';

/// Direction 1c "Roster" — people first, each member gets a card with
/// their latest dip. See
/// design-refs/design_handoff_group_profile/README.md §"Direction 1c".
/// Mock data only; does not touch the real group_profile_screen.dart.
class GroupProfileRosterScreen extends StatefulWidget {
  const GroupProfileRosterScreen({super.key});

  @override
  State<GroupProfileRosterScreen> createState() => _GroupProfileRosterScreenState();
}

class _GroupProfileRosterScreenState extends State<GroupProfileRosterScreen> {
  final _data = MockGroupData.instance;
  final _pinged = <String>{};
  bool _onlyMeInGroup = false;
  bool _loading = false;
  bool _error = false;

  static const _you = MockMember(
    id: 'you',
    name: 'You',
    isAdmin: true,
    dipCount: 12,
    lastDippedLabel: 'Dipped 2h ago',
    hasPostedToday: true,
    last5Days: [true, true, true, true, true],
  );

  void _openOverflow() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF111118),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Demo state', style: GoogleFonts.spaceGrotesk(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
              SwitchListTile(
                value: _onlyMeInGroup,
                activeThumbColor: Colors.white,
                contentPadding: EdgeInsets.zero,
                title: Text('Only you in the group', style: GoogleFonts.dmSans(color: Colors.white)),
                onChanged: (v) {
                  Navigator.pop(context);
                  setState(() => _onlyMeInGroup = v);
                },
              ),
              const Divider(color: Colors.white24, height: 24),
              ListTile(
                leading: Icon(Icons.hourglass_empty_rounded, color: Colors.white.withValues(alpha: 0.7)),
                title: Text('Show loading skeleton', style: GoogleFonts.dmSans(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _loading = true;
                    _error = false;
                  });
                  Future.delayed(const Duration(seconds: 2), () {
                    if (mounted) setState(() => _loading = false);
                  });
                },
              ),
              ListTile(
                leading: Icon(Icons.error_outline_rounded, color: Colors.white.withValues(alpha: 0.7)),
                title: Text('Show error state', style: GoogleFonts.dmSans(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _error = true;
                    _loading = false;
                  });
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openDetail(String label) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF111118),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('$label — placeholder detail view', style: GoogleFonts.dmSans(color: Colors.white)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _loading
          ? const _RosterSkeleton()
          : _error
              ? _ErrorBody(onRetry: () => setState(() => _error = false))
              : _content(context),
    );
  }

  Widget _content(BuildContext context) {
    final members = _onlyMeInGroup ? const [_you] : _data.members;

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
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Icon(Icons.arrow_back_ios_new_rounded, size: 19, color: Colors.white.withValues(alpha: 0.7)),
                  ),
                  Text('Group', style: GoogleFonts.dmSans(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.3, color: Colors.white.withValues(alpha: 0.5))),
                  GestureDetector(
                    onTap: _openOverflow,
                    child: Icon(Icons.settings_outlined, size: 19, color: Colors.white.withValues(alpha: 0.7)),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 26, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _data.name,
                    style: GoogleFonts.spaceGrotesk(fontSize: 30, fontWeight: FontWeight.w700, letterSpacing: -0.8, height: 1.1, color: Colors.white),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _data.bio,
                    style: GoogleFonts.dmSans(fontSize: 14, height: 1.5, color: Colors.white.withValues(alpha: 0.55)),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      StatPill('${_data.streak}-day streak'),
                      const SizedBox(width: 8),
                      StatPill('Since ${_data.startedLabel}'),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 26, 16, 0),
              child: Column(
                children: [
                  for (final m in members) ...[
                    _RosterCard(
                      member: m,
                      pinged: _pinged.contains(m.id),
                      onTapCard: () => _openDetail(m.name),
                      onPing: () => setState(() => _pinged.add(m.id)),
                    ),
                    const SizedBox(height: 10),
                  ],
                  _InviteRow(onTap: () => _openDetail('Invite someone')),
                ],
              ),
            ),
            if (!_onlyMeInGroup) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 28, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionEyebrow('Recent together'),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 135,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: 3,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (context, i) {
                          final grad = Avatar.gradientFor(_data.members[i % _data.members.length].id);
                          return GestureDetector(
                            onTap: () => _openDetail('Recent dip #${i + 1}'),
                            child: Container(
                              width: 108,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                gradient: LinearGradient(colors: grad, begin: Alignment.topLeft, end: Alignment.bottomRight),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _RosterCard extends StatelessWidget {
  const _RosterCard({required this.member, required this.pinged, required this.onTapCard, required this.onPing});
  final MockMember member;
  final bool pinged;
  final VoidCallback onTapCard;
  final VoidCallback onPing;

  @override
  Widget build(BuildContext context) {
    if (!member.hasPostedToday) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.02),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Row(
          children: [
            CustomPaint(
              painter: const DashedRRectPainter(color: Color(0x26FFFFFF), radius: 13),
              child: const SizedBox(width: 58, height: 72),
            ),
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
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: pinged ? 0.05 : 0.1),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Text(
                  pinged ? 'Pinged' : 'Ping',
                  style: GoogleFonts.dmSans(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: pinged ? 0.4 : 1)),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final grad = Avatar.gradientFor(member.id);
    return GestureDetector(
      onTap: onTapCard,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.045),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Row(
          children: [
            Container(
              width: 58,
              height: 72,
              alignment: Alignment.bottomCenter,
              padding: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(13),
                gradient: LinearGradient(colors: grad, begin: Alignment.topLeft, end: Alignment.bottomRight),
              ),
              child: Text('today', style: GoogleFonts.jetBrainsMono(fontSize: 8.5, color: Colors.white.withValues(alpha: 0.55))),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(member.name, style: GoogleFonts.spaceGrotesk(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
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
                    '${member.lastDippedLabel} · ${member.dipCount} dips',
                    style: GoogleFonts.dmSans(fontSize: 12.5, color: Colors.white.withValues(alpha: 0.45)),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      for (final dipped in member.last5Days) ...[
                        Container(
                          width: 22,
                          height: 6,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: dipped ? 0.5 : 0.12),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        if (dipped != member.last5Days.last) const SizedBox(width: 4),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InviteRow extends StatelessWidget {
  const _InviteRow({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: CustomPaint(
        painter: const DashedRRectPainter(color: Color(0x1FFFFFFF), radius: 18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.07), shape: BoxShape.circle),
                child: Icon(Icons.add_rounded, size: 18, color: Colors.white.withValues(alpha: 0.55)),
              ),
              const SizedBox(width: 12),
              Text('Invite someone', style: GoogleFonts.dmSans(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.white.withValues(alpha: 0.55))),
            ],
          ),
        ),
      ),
    );
  }
}

class _RosterSkeleton extends StatelessWidget {
  const _RosterSkeleton();

  Widget _block({double? width, required double height, double radius = 14}) {
    return Container(
      width: width,
      height: height,
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(radius)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _block(width: 220, height: 30),
            _block(height: 80),
            _block(height: 80),
            _block(height: 80),
          ],
        ),
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
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
    );
  }
}
