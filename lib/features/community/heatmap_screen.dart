import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants.dart';

// ---------------------------------------------------------------------------
// Enums + data models
// ---------------------------------------------------------------------------

enum _TimeFilter { today, week, allTime }

extension _TimeFilterX on _TimeFilter {
  String get label => switch (this) {
        _TimeFilter.today => 'Today',
        _TimeFilter.week => 'Last 7 days',
        _TimeFilter.allTime => 'All time',
      };
}

class _HeatmapPost {
  const _HeatmapPost({
    required this.handle,
    required this.text,
    required this.time,
  });

  final String handle;
  final String text;
  final String time;
}

class _Hotspot {
  const _Hotspot({
    required this.id,
    required this.name,
    required this.x,
    required this.y,
    required this.postCount,
    required this.handles,
    required this.posts,
  });

  final String id;
  final String name;
  final double x;
  final double y;
  final int postCount;
  final List<String> handles;
  final List<_HeatmapPost> posts;
}

// ---------------------------------------------------------------------------
// Dummy data — RV College
// ---------------------------------------------------------------------------

const _kRvToday = [
  _Hotspot(
    id: 'lib',
    name: 'Library',
    x: 0.35,
    y: 0.25,
    postCount: 23,
    handles: [
      'velvet_echo',
      'paper_crane',
      'cloud_walker',
      'study_bug',
      'silent_storm',
      'amber_drift'
    ],
    posts: [
      _HeatmapPost(
          handle: 'velvet_echo',
          text: "Can't focus today but love this corner",
          time: '12m'),
      _HeatmapPost(
          handle: 'paper_crane',
          text: 'Found the best quiet floor',
          time: '1h'),
      _HeatmapPost(
          handle: 'cloud_walker',
          text: 'Library wifi is broken again',
          time: '2h'),
    ],
  ),
  _Hotspot(
    id: 'quad',
    name: 'Quad / Canteen',
    x: 0.60,
    y: 0.55,
    postCount: 34,
    handles: [
      'study_bug',
      'sunset_chaser',
      'midnight_owl',
      'amber_drift',
      'ghost_runner',
      'neon_fog'
    ],
    posts: [
      _HeatmapPost(
          handle: 'study_bug',
          text: 'Canteen masala chai is carrying me through finals',
          time: '5m'),
      _HeatmapPost(
          handle: 'sunset_chaser',
          text: 'The quad is packed today, something happening?',
          time: '23m'),
      _HeatmapPost(
          handle: 'midnight_owl',
          text: 'Sitting under the tree, this is my spot',
          time: '45m'),
    ],
  ),
  _Hotspot(
    id: 'physics',
    name: 'Physics Dept',
    x: 0.76,
    y: 0.30,
    postCount: 8,
    handles: ['amber_drift', 'neon_fog', 'loop_forever'],
    posts: [
      _HeatmapPost(
          handle: 'amber_drift',
          text: 'Physics lab after 6pm is peak study hours',
          time: '3h'),
      _HeatmapPost(
          handle: 'neon_fog',
          text: 'Prof just added a surprise assignment',
          time: '4h'),
    ],
  ),
  _Hotspot(
    id: 'parking',
    name: 'Parking Lot',
    x: 0.20,
    y: 0.70,
    postCount: 6,
    handles: ['coffee_talk', 'adventure_seeker'],
    posts: [
      _HeatmapPost(
          handle: 'coffee_talk',
          text: "This is where everyone sneaks off to eat 😂",
          time: '2h'),
      _HeatmapPost(
          handle: 'adventure_seeker',
          text: 'Parking lot vibes are unmatched',
          time: '5h'),
    ],
  ),
];

const _kRvWeek = [
  _Hotspot(
    id: 'lib',
    name: 'Library',
    x: 0.35,
    y: 0.25,
    postCount: 67,
    handles: [
      'velvet_echo',
      'paper_crane',
      'cloud_walker',
      'study_bug',
      'silent_storm',
      'amber_drift',
      'debug_zero',
      'null_ptr'
    ],
    posts: [
      _HeatmapPost(
          handle: 'velvet_echo',
          text: "Can't focus today but love this corner",
          time: '1d'),
      _HeatmapPost(
          handle: 'paper_crane', text: 'Found the best quiet floor', time: '2d'),
      _HeatmapPost(
          handle: 'cloud_walker',
          text: 'Library wifi is broken again',
          time: '3d'),
    ],
  ),
  _Hotspot(
    id: 'quad',
    name: 'Quad / Canteen',
    x: 0.60,
    y: 0.55,
    postCount: 89,
    handles: [
      'study_bug',
      'sunset_chaser',
      'midnight_owl',
      'amber_drift',
      'ghost_runner',
      'neon_fog',
      'loop_forever',
      'coffee_talk'
    ],
    posts: [
      _HeatmapPost(
          handle: 'study_bug',
          text: 'Canteen masala chai is carrying me through finals',
          time: '1d'),
      _HeatmapPost(
          handle: 'sunset_chaser',
          text: 'The quad is packed today, something happening?',
          time: '2d'),
      _HeatmapPost(
          handle: 'midnight_owl',
          text: 'Sitting under the tree, this is my spot',
          time: '4d'),
    ],
  ),
  _Hotspot(
    id: 'physics',
    name: 'Physics Dept',
    x: 0.76,
    y: 0.30,
    postCount: 31,
    handles: ['amber_drift', 'neon_fog', 'loop_forever', 'ghost_runner'],
    posts: [
      _HeatmapPost(
          handle: 'amber_drift',
          text: 'Physics lab after 6pm is peak study hours',
          time: '2d'),
      _HeatmapPost(
          handle: 'neon_fog',
          text: 'Prof just added a surprise assignment',
          time: '3d'),
    ],
  ),
  _Hotspot(
    id: 'parking',
    name: 'Parking Lot',
    x: 0.20,
    y: 0.70,
    postCount: 18,
    handles: ['coffee_talk', 'adventure_seeker', 'loop_forever'],
    posts: [
      _HeatmapPost(
          handle: 'coffee_talk',
          text: "This is where everyone sneaks off to eat 😂",
          time: '2d'),
      _HeatmapPost(
          handle: 'adventure_seeker',
          text: 'Parking lot vibes are unmatched',
          time: '4d'),
    ],
  ),
  _Hotspot(
    id: 'sports',
    name: 'Sports Ground',
    x: 0.48,
    y: 0.80,
    postCount: 12,
    handles: ['ghost_runner', 'sunset_chaser', 'neon_fog'],
    posts: [
      _HeatmapPost(
          handle: 'ghost_runner',
          text: 'Morning run before labs, the BEST decision',
          time: '2d'),
      _HeatmapPost(
          handle: 'sunset_chaser',
          text: 'Sports ground at sunset 🧡',
          time: '5d'),
    ],
  ),
];

const _kRvAllTime = [
  _Hotspot(
    id: 'lib',
    name: 'Library',
    x: 0.35,
    y: 0.25,
    postCount: 234,
    handles: [
      'velvet_echo',
      'paper_crane',
      'cloud_walker',
      'study_bug',
      'silent_storm',
      'amber_drift',
      'debug_zero',
      'null_ptr',
      'loop_forever'
    ],
    posts: [
      _HeatmapPost(
          handle: 'velvet_echo',
          text: "Can't focus today but love this corner",
          time: '1mo'),
      _HeatmapPost(
          handle: 'paper_crane', text: 'Found the best quiet floor', time: '2mo'),
      _HeatmapPost(
          handle: 'study_bug',
          text: 'Library at midnight hits different',
          time: '3mo'),
    ],
  ),
  _Hotspot(
    id: 'quad',
    name: 'Quad / Canteen',
    x: 0.60,
    y: 0.55,
    postCount: 312,
    handles: [
      'study_bug',
      'sunset_chaser',
      'midnight_owl',
      'amber_drift',
      'ghost_runner',
      'neon_fog',
      'loop_forever',
      'coffee_talk',
      'cloud_walker'
    ],
    posts: [
      _HeatmapPost(
          handle: 'study_bug',
          text: 'Canteen masala chai is carrying me through finals',
          time: '1w'),
      _HeatmapPost(
          handle: 'sunset_chaser',
          text: 'The quad is packed today, something happening?',
          time: '2w'),
      _HeatmapPost(
          handle: 'midnight_owl',
          text: 'Sitting under the tree, this is my spot',
          time: '1mo'),
    ],
  ),
  _Hotspot(
    id: 'physics',
    name: 'Physics Dept',
    x: 0.76,
    y: 0.30,
    postCount: 89,
    handles: [
      'amber_drift',
      'neon_fog',
      'loop_forever',
      'ghost_runner',
      'debug_zero'
    ],
    posts: [
      _HeatmapPost(
          handle: 'amber_drift',
          text: 'Physics lab after 6pm is peak study hours',
          time: '1w'),
      _HeatmapPost(
          handle: 'neon_fog',
          text: 'Prof just added a surprise assignment',
          time: '2w'),
    ],
  ),
  _Hotspot(
    id: 'parking',
    name: 'Parking Lot',
    x: 0.20,
    y: 0.70,
    postCount: 67,
    handles: [
      'coffee_talk',
      'adventure_seeker',
      'loop_forever',
      'ghost_runner'
    ],
    posts: [
      _HeatmapPost(
          handle: 'coffee_talk',
          text: "This is where everyone sneaks off to eat 😂",
          time: '1w'),
      _HeatmapPost(
          handle: 'adventure_seeker',
          text: 'Parking lot vibes are unmatched',
          time: '2w'),
    ],
  ),
  _Hotspot(
    id: 'sports',
    name: 'Sports Ground',
    x: 0.48,
    y: 0.80,
    postCount: 45,
    handles: [
      'ghost_runner',
      'sunset_chaser',
      'neon_fog',
      'amber_drift'
    ],
    posts: [
      _HeatmapPost(
          handle: 'ghost_runner',
          text: 'Morning run before labs, the BEST decision',
          time: '2w'),
      _HeatmapPost(
          handle: 'sunset_chaser',
          text: 'Sports ground at sunset 🧡',
          time: '3w'),
    ],
  ),
  _Hotspot(
    id: 'blockc',
    name: 'Block C',
    x: 0.14,
    y: 0.40,
    postCount: 23,
    handles: ['velvet_echo', 'null_ptr', 'debug_zero'],
    posts: [
      _HeatmapPost(
          handle: 'velvet_echo',
          text: 'Block C has the best AC in the whole college',
          time: '3w'),
      _HeatmapPost(
          handle: 'null_ptr',
          text: 'Found a secret staircase here',
          time: '1mo'),
    ],
  ),
];

// ---------------------------------------------------------------------------
// Dummy data — CSE Branch
// ---------------------------------------------------------------------------

const _kCseToday = [
  _Hotspot(
    id: 'cslab',
    name: 'CS Lab',
    x: 0.42,
    y: 0.32,
    postCount: 18,
    handles: ['debug_zero', 'null_ptr', 'loop_forever', 'coffee_talk'],
    posts: [
      _HeatmapPost(
          handle: 'debug_zero',
          text: 'Lab PCs take forever to boot',
          time: '20m'),
      _HeatmapPost(
          handle: 'null_ptr',
          text: 'Someone left their code on the screen 👀',
          time: '1h'),
    ],
  ),
  _Hotspot(
    id: 'cse_canteen',
    name: 'Canteen',
    x: 0.62,
    y: 0.62,
    postCount: 22,
    handles: [
      'loop_forever',
      'coffee_talk',
      'ghost_runner',
      'amber_drift',
      'velvet_echo'
    ],
    posts: [
      _HeatmapPost(
          handle: 'loop_forever',
          text: 'Stress eating during DBMS season',
          time: '30m'),
      _HeatmapPost(
          handle: 'coffee_talk',
          text: 'Coffee machine broke again',
          time: '2h'),
    ],
  ),
  _Hotspot(
    id: 'lecthall',
    name: 'Lecture Hall',
    x: 0.26,
    y: 0.52,
    postCount: 14,
    handles: ['debug_zero', 'paper_crane', 'cloud_walker'],
    posts: [
      _HeatmapPost(
          handle: 'debug_zero',
          text: 'Prof moved the OS submission to Friday',
          time: '1h'),
      _HeatmapPost(
          handle: 'paper_crane',
          text: 'Front row seats are cursed',
          time: '2h'),
    ],
  ),
];

const _kCseWeek = [
  _Hotspot(
    id: 'cslab',
    name: 'CS Lab',
    x: 0.42,
    y: 0.32,
    postCount: 56,
    handles: [
      'debug_zero',
      'null_ptr',
      'loop_forever',
      'coffee_talk',
      'ghost_runner'
    ],
    posts: [
      _HeatmapPost(
          handle: 'debug_zero',
          text: 'Lab PCs take forever to boot',
          time: '2d'),
      _HeatmapPost(
          handle: 'null_ptr',
          text: 'Someone left their code on the screen 👀',
          time: '3d'),
    ],
  ),
  _Hotspot(
    id: 'cse_canteen',
    name: 'Canteen',
    x: 0.62,
    y: 0.62,
    postCount: 67,
    handles: [
      'loop_forever',
      'coffee_talk',
      'ghost_runner',
      'amber_drift',
      'velvet_echo',
      'sunset_chaser'
    ],
    posts: [
      _HeatmapPost(
          handle: 'loop_forever',
          text: 'Stress eating during DBMS season',
          time: '2d'),
      _HeatmapPost(
          handle: 'coffee_talk',
          text: 'Coffee machine broke again',
          time: '4d'),
    ],
  ),
  _Hotspot(
    id: 'lecthall',
    name: 'Lecture Hall',
    x: 0.26,
    y: 0.52,
    postCount: 45,
    handles: ['debug_zero', 'paper_crane', 'cloud_walker', 'amber_drift'],
    posts: [
      _HeatmapPost(
          handle: 'debug_zero',
          text: 'Prof moved the OS submission to Friday',
          time: '3d'),
      _HeatmapPost(
          handle: 'paper_crane',
          text: 'Front row seats are cursed',
          time: '5d'),
    ],
  ),
];

const _kCseAllTime = [
  _Hotspot(
    id: 'cslab',
    name: 'CS Lab',
    x: 0.42,
    y: 0.32,
    postCount: 189,
    handles: [
      'debug_zero',
      'null_ptr',
      'loop_forever',
      'coffee_talk',
      'ghost_runner',
      'velvet_echo'
    ],
    posts: [
      _HeatmapPost(
          handle: 'debug_zero',
          text: 'Lab PCs take forever to boot',
          time: '1mo'),
      _HeatmapPost(
          handle: 'null_ptr',
          text: 'Someone left their code on the screen 👀',
          time: '2mo'),
    ],
  ),
  _Hotspot(
    id: 'cse_canteen',
    name: 'Canteen',
    x: 0.62,
    y: 0.62,
    postCount: 223,
    handles: [
      'loop_forever',
      'coffee_talk',
      'ghost_runner',
      'amber_drift',
      'velvet_echo',
      'sunset_chaser',
      'study_bug'
    ],
    posts: [
      _HeatmapPost(
          handle: 'loop_forever',
          text: 'Stress eating during DBMS season',
          time: '2w'),
      _HeatmapPost(
          handle: 'coffee_talk',
          text: 'Coffee machine broke again',
          time: '1mo'),
    ],
  ),
  _Hotspot(
    id: 'lecthall',
    name: 'Lecture Hall',
    x: 0.26,
    y: 0.52,
    postCount: 156,
    handles: [
      'debug_zero',
      'paper_crane',
      'cloud_walker',
      'amber_drift',
      'null_ptr'
    ],
    posts: [
      _HeatmapPost(
          handle: 'debug_zero',
          text: 'Prof moved the OS submission to Friday',
          time: '2w'),
      _HeatmapPost(
          handle: 'paper_crane',
          text: 'Front row seats are cursed',
          time: '3w'),
    ],
  ),
  _Hotspot(
    id: 'cse_lib',
    name: 'Library (CSE shelf)',
    x: 0.35,
    y: 0.18,
    postCount: 34,
    handles: ['debug_zero', 'null_ptr', 'cloud_walker'],
    posts: [
      _HeatmapPost(
          handle: 'debug_zero',
          text: 'Found Knuth TAOCP vol 3 here',
          time: '3w'),
      _HeatmapPost(
          handle: 'null_ptr',
          text: 'CSE section is always empty 🙁',
          time: '1mo'),
    ],
  ),
];

// ---------------------------------------------------------------------------
// Data lookup
// ---------------------------------------------------------------------------

const _kMinPool = 5;

const _kHeatmapCommunities = [
  ('rv_college', 'RV College'),
  ('cse_branch', 'CSE Branch'),
];

List<_Hotspot> _getHotspots(String communityId, _TimeFilter filter) {
  final List<_Hotspot> raw = switch ((communityId, filter)) {
    ('rv_college', _TimeFilter.today) => _kRvToday,
    ('rv_college', _TimeFilter.week) => _kRvWeek,
    ('rv_college', _TimeFilter.allTime) => _kRvAllTime,
    ('cse_branch', _TimeFilter.today) => _kCseToday,
    ('cse_branch', _TimeFilter.week) => _kCseWeek,
    ('cse_branch', _TimeFilter.allTime) => _kCseAllTime,
    _ => [],
  };
  return raw.where((h) => h.postCount >= _kMinPool).toList();
}

Color _heatColor(int count) {
  if (count >= 100) return const Color(0xFF880000);
  if (count >= 50) return const Color(0xFFAA1111);
  if (count >= 25) return const Color(0xFFDD2222);
  if (count >= 12) return const Color(0xFFFF4444);
  return const Color(0xFFFF7777);
}

double _hotspotRadius(int count) =>
    (14.0 + count * 0.55).clamp(18.0, 58.0);

// ---------------------------------------------------------------------------
// HeatmapScreen
// ---------------------------------------------------------------------------

class HeatmapScreen extends StatefulWidget {
  const HeatmapScreen({super.key});

  @override
  State<HeatmapScreen> createState() => _HeatmapScreenState();
}

class _HeatmapScreenState extends State<HeatmapScreen> {
  String _communityId = 'rv_college';
  _TimeFilter _filter = _TimeFilter.today;

  List<_Hotspot> get _hotspots => _getHotspots(_communityId, _filter);

  String get _communityName => _kHeatmapCommunities
      .firstWhere((c) => c.$1 == _communityId,
          orElse: () => ('', 'Unknown'))
      .$2;

  void _openHotspot(_Hotspot spot) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.cardSurface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        maxChildSize: 0.88,
        minChildSize: 0.35,
        builder: (sheetCtx, scrollCtrl) =>
            _HotspotSheet(hotspot: spot, scrollCtrl: scrollCtrl),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          _buildHeader(topPad),
          Expanded(
            child: _CampusMap(
              hotspots: _hotspots,
              onHotspotTap: _openHotspot,
            ),
          ),
          _LegendBar(bottomPad: bottomPad),
        ],
      ),
    );
  }

  Widget _buildHeader(double topPad) {
    return Container(
      padding: EdgeInsets.fromLTRB(16, topPad + 10, 16, 12),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                  '$_communityName · Heatmap',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Text(
                '${_hotspots.length} hotspots',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Community selector
          SizedBox(
            height: 30,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final (id, name) in _kHeatmapCommunities)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => setState(() => _communityId = id),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding:
                            const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: _communityId == id
                              ? AppColors.primary
                              : AppColors.cardSurface,
                          borderRadius: BorderRadius.circular(15),
                          border: _communityId == id
                              ? null
                              : Border.all(color: AppColors.border),
                        ),
                        child: Center(
                          child: Text(
                            name,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: _communityId == id
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: _communityId == id
                                  ? Colors.white
                                  : AppColors.textMuted,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // Time filter
          Row(
            children: [
              for (final f in _TimeFilter.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _filter = f),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: _filter == f
                            ? AppColors.primary.withValues(alpha: 0.12)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _filter == f
                              ? AppColors.primary.withValues(alpha: 0.40)
                              : AppColors.border,
                        ),
                      ),
                      child: Text(
                        f.label,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          fontWeight: _filter == f
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: _filter == f
                              ? AppColors.primary
                              : AppColors.textMuted,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Campus map — CustomPainter + tap overlay
// ---------------------------------------------------------------------------

class _CampusMap extends StatelessWidget {
  const _CampusMap({
    required this.hotspots,
    required this.onHotspotTap,
  });

  final List<_Hotspot> hotspots;
  final void Function(_Hotspot) onHotspotTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        return Stack(
          children: [
            // Base map with heat circles
            RepaintBoundary(
              child: CustomPaint(
                size: Size(w, h),
                painter: _MapPainter(hotspots: hotspots),
              ),
            ),
            // Tap targets (invisible, positioned over each hotspot)
            for (final spot in hotspots) ...[
              Positioned(
                left: spot.x * w - _hotspotRadius(spot.postCount),
                top: spot.y * h - _hotspotRadius(spot.postCount),
                child: GestureDetector(
                  onTap: () => onHotspotTap(spot),
                  onLongPress: () => onHotspotTap(spot),
                  behavior: HitTestBehavior.opaque,
                  child: SizedBox(
                    width: _hotspotRadius(spot.postCount) * 2,
                    height: _hotspotRadius(spot.postCount) * 2,
                  ),
                ),
              ),
              // Post-count label below circle
              Positioned(
                left: spot.x * w - 22,
                top: spot.y * h + _hotspotRadius(spot.postCount) + 3,
                child: IgnorePointer(
                  child: SizedBox(
                    width: 44,
                    child: Text(
                      '${spot.postCount}',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 9,
                        color: _heatColor(spot.postCount)
                            .withValues(alpha: 0.85),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Map painter — campus background + heat circles
// ---------------------------------------------------------------------------

class _MapPainter extends CustomPainter {
  const _MapPainter({required this.hotspots});

  final List<_Hotspot> hotspots;

  Offset _pt(double x, double y, Size s) =>
      Offset(x * s.width, y * s.height);

  Rect _rect(double l, double t, double r, double b, Size s) =>
      Rect.fromLTRB(l * s.width, t * s.height, r * s.width, b * s.height);

  @override
  void paint(Canvas canvas, Size size) {
    _drawBackground(canvas, size);
    _drawGrid(canvas, size);
    _drawPaths(canvas, size);
    _drawBuildings(canvas, size);
    _drawAreaLabels(canvas, size);
    _drawHeatCircles(canvas, size);
  }

  void _drawBackground(Canvas canvas, Size size) {
    // Full background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0xFF0A0A0B),
    );
    // Campus boundary
    final campusRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(10, 10, size.width - 20, size.height - 20),
      const Radius.circular(14),
    );
    canvas.drawRRect(
      campusRRect,
      Paint()..color = const Color(0xFF0E0E12),
    );
    canvas.drawRRect(
      campusRRect,
      Paint()
        ..color = const Color(0xFF252530)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );
  }

  void _drawGrid(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF16161C)
      ..strokeWidth = 0.5;
    const steps = 10;
    for (int i = 1; i < steps; i++) {
      final x = size.width * i / steps;
      final y = size.height * i / steps;
      canvas.drawLine(
          Offset(x, 14), Offset(x, size.height - 14), paint);
      canvas.drawLine(
          Offset(14, y), Offset(size.width - 14, y), paint);
    }
  }

  void _drawPaths(Canvas canvas, Size size) {
    final roadPaint = Paint()
      ..color = const Color(0xFF1C1C24)
      ..strokeWidth = 5.0
      ..strokeCap = StrokeCap.round;
    final pathPaint = Paint()
      ..color = const Color(0xFF181820)
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    // Main horizontal road at y=0.52
    canvas.drawLine(
        _pt(0.04, 0.52, size), _pt(0.96, 0.52, size), roadPaint);
    // Main vertical road at x=0.38
    canvas.drawLine(
        _pt(0.38, 0.04, size), _pt(0.38, 0.96, size), roadPaint);
    // Secondary paths
    canvas.drawLine(
        _pt(0.62, 0.38, size), _pt(0.62, 0.52, size), pathPaint);
    canvas.drawLine(
        _pt(0.32, 0.70, size), _pt(0.38, 0.70, size), pathPaint);
    canvas.drawLine(
        _pt(0.38, 0.70, size), _pt(0.48, 0.72, size), pathPaint);
    canvas.drawLine(
        _pt(0.76, 0.38, size), _pt(0.76, 0.52, size), pathPaint);
  }

  void _drawBuildings(Canvas canvas, Size size) {
    final fill = Paint()
      ..color = const Color(0xFF18181E)
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = const Color(0xFF2C2C38)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    const radius = Radius.circular(5);

    final rects = [
      _rect(0.18, 0.08, 0.50, 0.44, size), // Library
      _rect(0.44, 0.38, 0.82, 0.68, size), // Canteen/Quad
      _rect(0.64, 0.08, 0.92, 0.38, size), // Physics
      _rect(0.04, 0.60, 0.34, 0.82, size), // Parking
      _rect(0.32, 0.72, 0.66, 0.92, size), // Sports ground
      _rect(0.04, 0.16, 0.16, 0.52, size), // Block C
    ];

    for (final r in rects) {
      final rr = RRect.fromRectAndRadius(r, radius);
      canvas.drawRRect(rr, fill);
      canvas.drawRRect(rr, stroke);
    }

    // Sports ground slightly greener
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          _rect(0.32, 0.72, 0.66, 0.92, size), radius),
      Paint()..color = const Color(0xFF121A12),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          _rect(0.32, 0.72, 0.66, 0.92, size), radius),
      stroke,
    );

    // Inner room lines for library building
    final innerPaint = Paint()
      ..color = const Color(0xFF202028)
      ..strokeWidth = 0.5;
    canvas.drawLine(
        _pt(0.34, 0.08, size), _pt(0.34, 0.44, size), innerPaint);
    canvas.drawLine(
        _pt(0.18, 0.26, size), _pt(0.50, 0.26, size), innerPaint);
  }

  void _drawAreaLabels(Canvas canvas, Size size) {
    final labels = [
      ('LIBRARY', 0.34, 0.10),
      ('CANTEEN', 0.59, 0.41),
      ('PHYSICS', 0.72, 0.11),
      ('PARKING', 0.17, 0.63),
      ('SPORTS', 0.46, 0.75),
      ('BLOCK C', 0.07, 0.19),
    ];

    for (final (text, x, y) in labels) {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: const TextStyle(
            fontSize: 7.5,
            color: Color(0xFF3A3A48),
            fontWeight: FontWeight.w700,
            letterSpacing: 0.9,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(x * size.width - tp.width / 2, y * size.height),
      );
    }
  }

  void _drawHeatCircles(Canvas canvas, Size size) {
    for (final spot in hotspots) {
      _drawHeatCircle(
        canvas,
        Offset(spot.x * size.width, spot.y * size.height),
        spot.postCount,
      );
    }
  }

  void _drawHeatCircle(Canvas canvas, Offset center, int count) {
    final r = _hotspotRadius(count);
    final intensity = (count / 60.0).clamp(0.35, 1.0);
    final core = _heatColor(count);

    // Outer soft glow
    final outerRect = Rect.fromCircle(center: center, radius: r * 2.0);
    canvas.drawCircle(
      center,
      r * 2.0,
      Paint()
        ..shader = RadialGradient(
          colors: [
            core.withValues(alpha: 0.25 * intensity),
            core.withValues(alpha: 0.0),
          ],
        ).createShader(outerRect),
    );

    // Main heat blob
    final mainRect = Rect.fromCircle(center: center, radius: r);
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = RadialGradient(
          colors: [
            core.withValues(alpha: 0.82 * intensity),
            core.withValues(alpha: 0.50 * intensity),
            core.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(mainRect),
    );

    // Bright center dot
    canvas.drawCircle(
      center,
      r * 0.18,
      Paint()..color = core.withValues(alpha: 0.95),
    );
  }

  @override
  bool shouldRepaint(_MapPainter old) => old.hotspots != hotspots;
}

// ---------------------------------------------------------------------------
// Hotspot detail sheet
// ---------------------------------------------------------------------------

class _HotspotSheet extends StatelessWidget {
  const _HotspotSheet({
    required this.hotspot,
    required this.scrollCtrl,
  });

  final _Hotspot hotspot;
  final ScrollController scrollCtrl;

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final showHandles = hotspot.postCount >= 15;

    return Column(
      children: [
        const SizedBox(height: 8),
        Center(
          child: Container(
            width: 36,
            height: 3,
            decoration: BoxDecoration(
              color: AppColors.textMuted,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: _heatColor(hotspot.postCount),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: _heatColor(hotspot.postCount)
                              .withValues(alpha: 0.4),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    hotspot.name,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${hotspot.postCount} posts from this area',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 10),
              if (showHandles) ...[
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final h in hotspot.handles.take(5))
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Text(
                          h,
                          style: GoogleFonts.jetBrainsMono(
                              fontSize: 10, color: AppColors.primary),
                        ),
                      ),
                    if (hotspot.handles.length > 5)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Text(
                          '+${hotspot.handles.length - 5} more',
                          style: GoogleFonts.jetBrainsMono(
                              fontSize: 10, color: AppColors.textMuted),
                        ),
                      ),
                  ],
                ),
              ] else ...[
                Row(
                  children: [
                    const Icon(Icons.lock_outline,
                        size: 12, color: AppColors.textMuted),
                    const SizedBox(width: 6),
                    Text(
                      'Handles hidden · pool < 15',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: AppColors.textMuted,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const Divider(color: AppColors.border, height: 1),
        Expanded(
          child: ListView.separated(
            controller: scrollCtrl,
            padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPad + 16),
            itemCount: hotspot.posts.length,
            separatorBuilder: (context2, index) =>
                const SizedBox(height: 10),
            itemBuilder: (context2, index) =>
                _PostPreviewCard(post: hotspot.posts[index]),
          ),
        ),
      ],
    );
  }
}

class _PostPreviewCard extends StatelessWidget {
  const _PostPreviewCard({required this.post});

  final _HeatmapPost post;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                post.handle,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
              const Spacer(),
              Text(
                post.time,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            post.text,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: AppColors.textPrimary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Legend bar
// ---------------------------------------------------------------------------

class _LegendBar extends StatelessWidget {
  const _LegendBar({required this.bottomPad});

  final double bottomPad;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 10, 16, bottomPad + 10),
      decoration: const BoxDecoration(
        color: AppColors.cardSurface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Text(
            'Low',
            style: GoogleFonts.jetBrainsMono(
                fontSize: 9, color: AppColors.textMuted),
          ),
          const SizedBox(width: 6),
          Container(
            height: 8,
            width: 100,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              gradient: const LinearGradient(
                colors: [
                  Color(0xFFFF9999),
                  Color(0xFFFF4444),
                  Color(0xFFDD2222),
                  Color(0xFF880000),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'High',
            style: GoogleFonts.jetBrainsMono(
                fontSize: 9, color: AppColors.textMuted),
          ),
          const Spacer(),
          Text(
            '≥$_kMinPool posts to show',
            style: GoogleFonts.jetBrainsMono(
                fontSize: 9, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Heatmap entry card (used in CommunityScreen)
// ---------------------------------------------------------------------------

class HeatmapFeatureCard extends StatelessWidget {
  const HeatmapFeatureCard({super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const HeatmapScreen(),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFFDD2222).withValues(alpha: 0.28),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFDD2222).withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.whatshot_outlined,
                color: Color(0xFFDD2222),
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Campus Heatmap',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'See where people are posting from',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              color: AppColors.textMuted,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}
