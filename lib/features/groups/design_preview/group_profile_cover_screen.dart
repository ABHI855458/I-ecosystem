import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'mock_group_data.dart';
import 'widgets/avatar.dart';
import 'widgets/frosted_icon_button.dart';

/// Direction 1a "Cover" — collage banner, stats bar, tabbed posts grid. See
/// design-refs/design_handoff_group_profile/README.md §"Direction 1a".
/// Mock data only; does not touch the real group_profile_screen.dart.
class GroupProfileCoverScreen extends StatefulWidget {
  const GroupProfileCoverScreen({super.key});

  @override
  State<GroupProfileCoverScreen> createState() => _GroupProfileCoverScreenState();
}

enum _Tab { posts, members, recaps }

class _GroupProfileCoverScreenState extends State<GroupProfileCoverScreen> {
  _Tab _tab = _Tab.posts;
  bool _loading = false;
  bool _error = false;

  final _data = MockGroupData.instance;

  static const _gridGradients = <List<Color>>[
    [Color(0xFF0C1445), Color(0xFF283593)],
    [Color(0xFF1A0A2E), Color(0xFF4A2C8A)],
    [Color(0xFF0D3B2E), Color(0xFF2D8F6A)],
    [Color(0xFF3D1414), Color(0xFF8F2D2D)],
    [Color(0xFF16213E), Color(0xFF0F3460)],
    [Color(0xFF2A1A3D), Color(0xFF6B4A8F)],
  ];

  void _openOverflow() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF111118),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Wrap(
            children: [
              ListTile(
                leading: Icon(Icons.bug_report_outlined, color: Colors.white.withValues(alpha: 0.7)),
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

  void _openPostDetail(int index) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF111118),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Post #${index + 1} — placeholder detail view', style: GoogleFonts.dmSans(color: Colors.white)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _loading
          ? const _CoverSkeleton()
          : _error
              ? _ErrorBody(onRetry: () => setState(() => _error = false))
              : _content(context),
    );
  }

  Widget _content(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final columns = width >= 600 ? 4 : 3;

    return Stack(
      children: [
        SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _CoverCollage(onBack: () => Navigator.of(context).pop(), onOverflow: _openOverflow),
              Transform.translate(
                offset: const Offset(0, -34),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _data.name,
                        style: GoogleFonts.spaceGrotesk(fontSize: 23, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: Colors.white),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'Started ${_data.startedLabel} · ${_data.isPrivate ? 'Private group' : 'Group'}',
                        style: GoogleFonts.dmSans(fontSize: 12.5, color: Colors.white.withValues(alpha: 0.45)),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _data.bio,
                        style: GoogleFonts.dmSans(fontSize: 14, height: 1.5, color: Colors.white.withValues(alpha: 0.7)),
                      ),
                      const SizedBox(height: 16),
                      GestureDetector(
                        onTap: () => setState(() => _tab = _Tab.members),
                        behavior: HitTestBehavior.opaque,
                        child: Row(
                          children: [
                            AvatarStack(
                              ids: _data.members.take(4).map((m) => m.id).toList(),
                              labels: _data.members.take(4).map((m) => m.name).toList(),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              '${_data.members.length} members',
                              style: GoogleFonts.dmSans(fontSize: 13, color: Colors.white.withValues(alpha: 0.5)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            _StatCell(value: '${_data.totalPosts}', label: 'posts', showDivider: true),
                            _StatCell(value: '${_data.streak}', label: 'day streak', showDivider: true),
                            _StatCell(value: '${_data.onTimePercent}%', label: 'on time', showDivider: false),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              height: 44,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                              child: Text('Post to the group', style: GoogleFonts.dmSans(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black)),
                            ),
                          ),
                          const SizedBox(width: 10),
                          _SquareIconButton(icon: Icons.person_add_alt_1_rounded, onTap: () {}),
                          const SizedBox(width: 10),
                          _SquareIconButton(icon: Icons.settings_outlined, onTap: _openOverflow),
                        ],
                      ),
                      const SizedBox(height: 22),
                      _Tabs(active: _tab, onChanged: (t) => setState(() => _tab = t)),
                    ],
                  ),
                ),
              ),
              Transform.translate(
                offset: const Offset(0, -34),
                child: _tabBody(columns),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tabBody(int columns) {
    switch (_tab) {
      case _Tab.posts:
        return Padding(
          padding: const EdgeInsets.all(12),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 9,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
              childAspectRatio: 4 / 5,
            ),
            itemBuilder: (context, i) {
              final grad = _gridGradients[i % _gridGradients.length];
              final chipGrad = Avatar.gradientFor(_data.members[i % _data.members.length].id);
              return GestureDetector(
                onTap: () => _openPostDetail(i),
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    gradient: LinearGradient(colors: grad, begin: Alignment.topLeft, end: Alignment.bottomRight),
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        top: 5,
                        left: 5,
                        child: Container(
                          width: 22,
                          height: 28,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(color: Colors.black, width: 1.5),
                            gradient: LinearGradient(colors: chipGrad, begin: Alignment.topLeft, end: Alignment.bottomRight),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      case _Tab.members:
        return _PlaceholderTabBody(text: 'Members list — not part of this screen\'s spec, placeholder only.');
      case _Tab.recaps:
        return _PlaceholderTabBody(text: 'Recaps — not part of this screen\'s spec, placeholder only.');
    }
  }
}

class _CoverCollage extends StatelessWidget {
  const _CoverCollage({required this.onBack, required this.onOverflow});
  final VoidCallback onBack;
  final VoidCallback onOverflow;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 230,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Row(
            children: [
              Expanded(
                flex: 2,
                child: Container(
                  margin: const EdgeInsets.only(right: 2),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF1A1A2E), Color(0xFF16213E), Color(0xFF0F3460)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  children: [
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 1),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(colors: [Color(0xFF2D1B69), Color(0xFF4A2C8A)]),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.only(top: 1),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(colors: [Color(0xFF0D3B2E), Color(0xFF1A6B4A)]),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x8C000000), Colors.transparent, Color(0xD9000000)],
                stops: [0, 0.35, 1],
              ),
            ),
          ),
          Positioned(
            top: 52,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                FrostedIconButton(
                  onTap: onBack,
                  child: const Icon(Icons.arrow_back_ios_new_rounded, size: 17, color: Colors.white),
                ),
                FrostedIconButton(
                  onTap: onOverflow,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(
                      3,
                      (_) => Container(
                        width: 3.5,
                        height: 3.5,
                        margin: const EdgeInsets.symmetric(horizontal: 1.5),
                        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                      ),
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
}

class _StatCell extends StatelessWidget {
  const _StatCell({required this.value, required this.label, required this.showDivider});
  final String value;
  final String label;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: showDivider
            ? BoxDecoration(border: Border(right: BorderSide(color: Colors.white.withValues(alpha: 0.07))))
            : null,
        child: Column(
          children: [
            Text(value, style: GoogleFonts.spaceGrotesk(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
            const SizedBox(height: 2),
            Text(label, style: GoogleFonts.dmSans(fontSize: 10.5, color: Colors.white.withValues(alpha: 0.4))),
          ],
        ),
      ),
    );
  }
}

class _SquareIconButton extends StatelessWidget {
  const _SquareIconButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, size: 19, color: Colors.white),
      ),
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs({required this.active, required this.onChanged});
  final _Tab active;
  final ValueChanged<_Tab> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08)))),
      child: Row(
        children: [
          _TabItem(label: 'Posts', selected: active == _Tab.posts, onTap: () => onChanged(_Tab.posts)),
          const SizedBox(width: 22),
          _TabItem(label: 'Members', selected: active == _Tab.members, onTap: () => onChanged(_Tab.members)),
          const SizedBox(width: 22),
          _TabItem(label: 'Recaps', selected: active == _Tab.recaps, onTap: () => onChanged(_Tab.recaps)),
        ],
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: selected ? Colors.white : Colors.transparent, width: 2)),
        ),
        child: Text(
          label,
          style: GoogleFonts.dmSans(
            fontSize: 13.5,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? Colors.white : Colors.white.withValues(alpha: 0.4),
          ),
        ),
      ),
    );
  }
}

class _PlaceholderTabBody extends StatelessWidget {
  const _PlaceholderTabBody({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 32),
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: GoogleFonts.dmSans(fontSize: 13, color: Colors.white.withValues(alpha: 0.35)),
        ),
      ),
    );
  }
}

class _CoverSkeleton extends StatelessWidget {
  const _CoverSkeleton();

  Widget _block({double? width, required double height, double radius = 8}) {
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
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _block(height: 180, radius: 16),
            _block(width: 200, height: 24),
            _block(width: 140, height: 14),
            _block(height: 80, radius: 16),
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
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('Retry', style: GoogleFonts.dmSans(color: Colors.white, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
