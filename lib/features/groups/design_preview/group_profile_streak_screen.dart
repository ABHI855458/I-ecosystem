import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'mock_group_data.dart';
import 'widgets/dashed_rrect_painter.dart';
import 'widgets/section_eyebrow.dart';

enum _DemoState { normal, streakBroken, allDippedToday }

/// Direction 1b "Streak" — today's slots, streak number, calendar of dips.
/// See design-refs/design_handoff_group_profile/README.md §"Direction 1b".
/// This is a mock-data sibling of the production, real-data
/// group_profile_screen.dart — built independently against this preview's
/// shared primitives/data, not a copy of that file's code. Unlike the real
/// screen (which has no backend for streaks and omits that language), this
/// one follows the original spec verbatim, streak copy included, since it's
/// explicitly a pixel-fidelity design comparison tool.
class GroupProfileStreakScreen extends StatefulWidget {
  const GroupProfileStreakScreen({super.key});

  @override
  State<GroupProfileStreakScreen> createState() => _GroupProfileStreakScreenState();
}

class _GroupProfileStreakScreenState extends State<GroupProfileStreakScreen> {
  final _data = MockGroupData.instance;
  _DemoState _demo = _DemoState.normal;
  bool _loading = false;
  bool _error = false;

  bool get _viewerPostedToday => _demo == _DemoState.allDippedToday;

  bool _posted(int index) => _demo == _DemoState.allDippedToday ? true : _data.members[index].hasPostedToday;

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
              const SizedBox(height: 8),
              _demoTile('Normal', _DemoState.normal),
              _demoTile('Streak broken', _DemoState.streakBroken),
              _demoTile('Everyone dipped today', _DemoState.allDippedToday),
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

  Widget _demoTile(String label, _DemoState value) {
    final selected = _demo == value;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
        color: selected ? Colors.white : Colors.white.withValues(alpha: 0.4),
      ),
      title: Text(label, style: GoogleFonts.dmSans(color: Colors.white)),
      onTap: () {
        Navigator.pop(context);
        setState(() => _demo = value);
      },
    );
  }

  void _openDayDetail(String label) {
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
          ? const _StreakSkeleton()
          : _error
              ? _ErrorBody(onRetry: () => setState(() => _error = false))
              : _content(context),
    );
  }

  Widget _content(BuildContext context) {
    return Stack(
      children: [
        SingleChildScrollView(
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 96),
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
                        GestureDetector(
                          onTap: _openOverflow,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: List.generate(
                              3,
                              (_) => Container(
                                width: 3.5,
                                height: 3.5,
                                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.6), shape: BoxShape.circle),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                    child: Column(
                      children: [
                        Container(
                          width: 76,
                          height: 76,
                          decoration: const BoxDecoration(
                            borderRadius: BorderRadius.all(Radius.circular(26)),
                            gradient: LinearGradient(
                              colors: [Color(0xFFC471F5), Color(0xFFFA71CD), Color(0xFFF68084)],
                              stops: [0, 0.55, 1],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            _data.name.isNotEmpty ? _data.name[0].toUpperCase() : '?',
                            style: GoogleFonts.spaceGrotesk(fontSize: 30, fontWeight: FontWeight.w700, color: Colors.white),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          _data.name,
                          style: GoogleFonts.spaceGrotesk(fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: Colors.white),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '${_data.members.length} members · ${_data.isPrivate ? 'private' : 'public'}',
                          style: GoogleFonts.dmSans(fontSize: 12.5, color: Colors.white.withValues(alpha: 0.45)),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
                    child: _StreakHero(
                      streak: _demo == _DemoState.streakBroken ? 0 : _data.streak,
                      broken: _demo == _DemoState.streakBroken,
                      allDipped: _demo == _DemoState.allDippedToday,
                      missingCount: _data.missingTodayCount,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SectionEyebrow('Today'),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 112,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: _data.members.length,
                            separatorBuilder: (_, _) => const SizedBox(width: 10),
                            itemBuilder: (context, i) {
                              final m = _data.members[i];
                              final posted = _posted(i);
                              final firstNotPosted = !posted && _data.members.take(i).every((mm) => mm.hasPostedToday || _demo == _DemoState.allDippedToday);
                              return _TodaySlot(name: m.name, posted: posted, showPlus: firstNotPosted, id: m.id);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 26, 16, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            const SectionEyebrow('August'),
                            Text(
                              '${_data.totalDips} dips all-time',
                              style: GoogleFonts.dmSans(fontSize: 12, color: Colors.white.withValues(alpha: 0.35)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _data.calendar.length,
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 7,
                            mainAxisSpacing: 5,
                            crossAxisSpacing: 5,
                            childAspectRatio: 1,
                          ),
                          itemBuilder: (context, i) {
                            final day = _data.calendar[i];
                            return GestureDetector(
                              onTap: day.hasPost ? () => _openDayDetail('Day ${i + 1}') : null,
                              child: _CalendarCell(day: day, id: 'day$i'),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        _StickyCta(
          hasPostedToday: _viewerPostedToday,
          onPost: () => _openDayDetail('Post a dip'),
        ),
      ],
    );
  }
}

class _StreakHero extends StatelessWidget {
  const _StreakHero({required this.streak, required this.broken, required this.allDipped, required this.missingCount});
  final int streak;
  final bool broken;
  final bool allDipped;
  final int missingCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
        gradient: broken
            ? null
            : const LinearGradient(
                colors: [Color(0x2EC471F5), Color(0x14FA71CD)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
        color: broken ? Colors.white.withValues(alpha: 0.06) : null,
      ),
      child: Column(
        children: [
          SectionEyebrow(
            broken ? 'Start a new streak' : 'Current streak',
            fontSize: 10,
            letterSpacing: 1.6,
            color: Colors.white.withValues(alpha: 0.45),
          ),
          const SizedBox(height: 6),
          Text(
            '$streak',
            style: GoogleFonts.spaceGrotesk(fontSize: 52, fontWeight: FontWeight.w700, height: 1.05, letterSpacing: -2, color: Colors.white),
          ),
          const SizedBox(height: 2),
          Text('days without a miss', style: GoogleFonts.dmSans(fontSize: 13, color: Colors.white.withValues(alpha: 0.55))),
          Container(
            margin: const EdgeInsets.only(top: 16),
            padding: const EdgeInsets.only(top: 14),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.1)))),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(color: allDipped ? const Color(0xFF38EF7D) : const Color(0xFFFF6F61), shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Text(
                  allDipped ? "Everyone's dipped today" : "$missingCount haven't dipped today",
                  style: GoogleFonts.dmSans(fontSize: 12.5, color: Colors.white.withValues(alpha: 0.7)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TodaySlot extends StatelessWidget {
  const _TodaySlot({required this.name, required this.posted, required this.showPlus, required this.id});
  final String name;
  final bool posted;
  final bool showPlus;
  final String id;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 68,
      child: Column(
        children: [
          if (posted)
            Container(
              width: 68,
              height: 86,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: 0.2), width: 2),
                gradient: LinearGradient(
                  colors: _gradientFor(id),
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            )
          else
            CustomPaint(
              painter: const DashedRRectPainter(color: Color(0x29FFFFFF), radius: 14),
              child: SizedBox(
                width: 68,
                height: 86,
                child: showPlus ? Center(child: Icon(Icons.add_rounded, size: 18, color: Colors.white.withValues(alpha: 0.3))) : null,
              ),
            ),
          const SizedBox(height: 6),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.dmSans(fontSize: 10.5, color: Colors.white.withValues(alpha: posted ? 0.6 : 0.3)),
          ),
        ],
      ),
    );
  }

  static const _gradients = <List<Color>>[
    [Color(0xFF0C1445), Color(0xFF283593)],
    [Color(0xFF1A0A2E), Color(0xFF4A2C8A)],
    [Color(0xFF0D3B2E), Color(0xFF2D8F6A)],
    [Color(0xFF3D1414), Color(0xFF8F2D2D)],
    [Color(0xFF16213E), Color(0xFF0F3460)],
    [Color(0xFF2A1A3D), Color(0xFF6B4A8F)],
  ];

  static List<Color> _gradientFor(String id) => _gradients[id.hashCode.abs() % _gradients.length];
}

class _CalendarCell extends StatelessWidget {
  const _CalendarCell({required this.day, required this.id});
  final MockCalendarDay day;
  final String id;

  static const _gradients = <List<Color>>[
    [Color(0xFF0C1445), Color(0xFF283593)],
    [Color(0xFF1A0A2E), Color(0xFF4A2C8A)],
    [Color(0xFF0D3B2E), Color(0xFF2D8F6A)],
    [Color(0xFF3D1414), Color(0xFF8F2D2D)],
    [Color(0xFF16213E), Color(0xFF0F3460)],
    [Color(0xFF2A1A3D), Color(0xFF6B4A8F)],
  ];

  @override
  Widget build(BuildContext context) {
    if (day.hasPost) {
      final grad = _gradients[id.hashCode.abs() % _gradients.length];
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(7),
          gradient: LinearGradient(colors: grad, begin: Alignment.topLeft, end: Alignment.bottomRight),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(7),
        color: Colors.white.withValues(alpha: day.isToday || day.isFuture ? 0.03 : 0.05),
        border: day.isToday ? Border.all(color: Colors.white.withValues(alpha: 0.35), width: 1.5) : null,
      ),
    );
  }
}

class _StickyCta extends StatelessWidget {
  const _StickyCta({required this.hasPostedToday, required this.onPost});
  final bool hasPostedToday;
  final VoidCallback onPost;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Color(0xF2000000)],
            stops: [0, 0.4],
          ),
        ),
        child: GestureDetector(
          onTap: onPost,
          child: Container(
            height: 50,
            decoration: BoxDecoration(
              color: hasPostedToday ? Colors.white.withValues(alpha: 0.09) : Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.camera_alt_outlined, size: 18, color: hasPostedToday ? Colors.white : Colors.black),
                const SizedBox(width: 8),
                Text(
                  hasPostedToday ? "View today's dips" : 'Keep the streak alive',
                  style: GoogleFonts.dmSans(fontSize: 15, fontWeight: FontWeight.w600, color: hasPostedToday ? Colors.white : Colors.black),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StreakSkeleton extends StatelessWidget {
  const _StreakSkeleton();

  Widget _block({double? width, required double height, double radius = 8}) {
    return Container(
      width: width,
      height: height,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(radius)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _block(width: 76, height: 76, radius: 26),
            _block(width: 160, height: 22),
            _block(height: 170, radius: 20),
            _block(height: 90, radius: 14),
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
