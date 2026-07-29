import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/constants.dart';
import '../../services/anon_persona_service.dart';
import '../../services/post_service.dart';
import '../../services/storage_service.dart';
import '../../services/streak_service.dart';
import '../../services/bucket_service.dart';
import '../../services/community_photos_service.dart';
import '../groups/group_circles_row.dart';
import '../../shared/score_tier.dart';
import '../composer/photo_collage_builder.dart';
import '../../screens/memory/photo_picker_screen.dart';
import '../../services/memory_service.dart';
import '../../data/layouts.dart';
import '../../widgets/memory_canvas.dart';
import '../buckets/bucket_create_screen.dart';
import '../buckets/bucket_view_screen.dart';

// ---------------------------------------------------------------------------
// Profile constants
// ---------------------------------------------------------------------------

const _profileName = 'Abhishek Patel';
const _profileUsername = '@abhishek_patel';
const _profileScore = 230;

const _scoreBreakdown = <({String label, String time})>[
  (label: '+5  anonymous post', time: '2h ago'),
  (label: '+2  ping reply received', time: '4h ago'),
  (label: '+2  relatable on your post', time: '6h ago'),
  (label: '+2  streak maintained', time: '1d ago'),
  (label: '+5  anonymous post', time: '2d ago'),
];

// ---------------------------------------------------------------------------
// Data models
// ---------------------------------------------------------------------------

class _EveryonePost {
  const _EveryonePost({required this.color, required this.label});
  final Color color;
  final String label;
}

// ---------------------------------------------------------------------------
// Dummy data
// ---------------------------------------------------------------------------

const _everyonePosts = [
  _EveryonePost(color: Color(0xFF2A3050), label: 'Fest collage'),
  _EveryonePost(color: Color(0xFF2A1822), label: 'Coffee moment'),
  _EveryonePost(color: Color(0xFF1E2A28), label: 'Library study'),
  _EveryonePost(color: Color(0xFF382818), label: 'Campus sunset'),
  _EveryonePost(color: Color(0xFF2A2018), label: 'Friend group'),
  _EveryonePost(color: Color(0xFF281A1A), label: 'Late night snack'),
];

// ---------------------------------------------------------------------------
// Bio model
// ---------------------------------------------------------------------------

class _UserBio {
  const _UserBio({
    this.headline = 'CSE Student 🎓 | Photography 📸 | Always coding',
    this.bioText =
        '3rd year at RV College. Love capturing moments and building cool products. Let\'s collaborate! ✨',
    this.education = 'RV College of Engineering',
    this.major = 'Computer Science',
    this.year = '3rd Year',
    this.location = 'Bengaluru, India',
    this.interests = const ['Photography', 'Design', 'Coding', 'Music'],
    this.instagram = 'abhishek.lens',
    this.twitter = '',
    this.linkedin = 'abhishekpatel',
    this.portfolio = '',
  });

  final String headline;
  final String bioText;
  final String education;
  final String major;
  final String year;
  final String location;
  final List<String> interests;
  final String instagram;
  final String twitter;
  final String linkedin;
  final String portfolio;

  _UserBio copyWith({
    String? headline,
    String? bioText,
    String? education,
    String? major,
    String? year,
    String? location,
    List<String>? interests,
    String? instagram,
    String? twitter,
    String? linkedin,
    String? portfolio,
  }) =>
      _UserBio(
        headline: headline ?? this.headline,
        bioText: bioText ?? this.bioText,
        education: education ?? this.education,
        major: major ?? this.major,
        year: year ?? this.year,
        location: location ?? this.location,
        interests: interests ?? this.interests,
        instagram: instagram ?? this.instagram,
        twitter: twitter ?? this.twitter,
        linkedin: linkedin ?? this.linkedin,
        portfolio: portfolio ?? this.portfolio,
      );
}

// ---------------------------------------------------------------------------
// ProfileScreen
// ---------------------------------------------------------------------------

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  StreakData? _streak;
  _UserBio _bio = const _UserBio();

  // Glow ring level-up
  double _glowFlashBoost = 1.0;
  bool _showLevelUpBanner = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);
    _loadStreak();
    _scheduleLevelUpDemo();
  }

  void _scheduleLevelUpDemo() {
    // Demo: simulate hitting Tier 3 after 4 s
    Future.delayed(const Duration(seconds: 4), () {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      SystemSound.play(SystemSoundType.alert);
      setState(() {
        _glowFlashBoost = 4.0;
        _showLevelUpBanner = true;
      });
      // Flash fades back over 1.4 s
      Future.delayed(const Duration(milliseconds: 1400), () {
        if (mounted) setState(() => _glowFlashBoost = 1.0);
      });
      // Banner auto-dismisses after 3.5 s
      Future.delayed(const Duration(milliseconds: 3500), () {
        if (mounted) setState(() => _showLevelUpBanner = false);
      });
    });
  }

  Future<void> _loadStreak() async {
    final data = await StreakService.load();
    if (mounted) setState(() => _streak = data);
  }

  Future<void> _onPost() async {
    final data = await StreakService.recordPost();
    if (mounted) setState(() => _streak = data);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  void _openEdit() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _EditProfileSheet(),
    );
  }

  void _openBioEdit() {
    HapticFeedback.lightImpact();
    showModalBottomSheet<_UserBio?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BioEditSheet(bio: _bio),
    ).then((updated) {
      if (updated != null && mounted) setState(() => _bio = updated);
    });
  }

  void _openSearch() {
    HapticFeedback.lightImpact();
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => const _SearchScreen(),
      ),
    );
  }

  void _openPinModal() {
    HapticFeedback.lightImpact();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _PinModal(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;

    // Root cause of the "profile page doesn't scroll" bug: this used to be
    // a plain Column — [header Column, sticky tab bar, Expanded(TabBarView)]
    // — with no SingleChildScrollView/CustomScrollView anywhere. The header
    // (banner, avatar, bio, anon persona photo, score strip, groups row) was
    // sized to its own intrinsic height inside that bare Column with no
    // Expanded/Flexible around it, so whenever its content got taller than
    // the space left after the sticky tab bar and Expanded(TabBarView), it
    // just overflowed (we saw exactly this as a "RenderFlex overflowed by 47
    // pixels" warning) instead of scrolling — and there was no way to
    // scroll it into view at all, since a bare Column isn't scrollable and
    // nothing wrapped it in one. Each individual tab (GridView/ListView) was
    // independently scrollable, but the header itself never was.
    //
    // Fix: NestedScrollView — header + pinned tab bar become slivers in
    // headerSliverBuilder, and the existing TabBarView (each tab already a
    // GridView/ListView) becomes the body. This lets the header scroll away
    // with the page instead of being clipped, while the tab bar stays
    // pinned and each tab's own scrolling keeps working unchanged.
    return Scaffold(
      backgroundColor: AppColors.background,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverToBoxAdapter(
            child: _ProfileHeaderSection(
              topPad: topPad,
              streak: _streak,
              showLevelUpBanner: _showLevelUpBanner,
              glowFlashBoost: _glowFlashBoost,
              bio: _bio,
              onEdit: _openEdit,
              onSearch: _openSearch,
              onPin: _openPinModal,
              onEditBio: _openBioEdit,
              onPost: _onPost,
            ),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _StickyTabBarDelegate(_StickyTabBar(controller: _tabCtrl)),
          ),
        ],
        body: TabBarView(
          controller: _tabCtrl,
          children: const [
            _EveryoneTab(),
            _PrivateTab(),
            _MemoriesTab(),
            _GroupsTab(),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sticky tab bar sliver delegate — pins _StickyTabBar below the scrolling
// header inside the NestedScrollView.
// ---------------------------------------------------------------------------

class _StickyTabBarDelegate extends SliverPersistentHeaderDelegate {
  const _StickyTabBarDelegate(this.child);
  final Widget child;

  @override
  double get minExtent => kTextTabBarHeight;
  @override
  double get maxExtent => kTextTabBarHeight;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => child;

  @override
  bool shouldRebuild(covariant _StickyTabBarDelegate oldDelegate) => child != oldDelegate.child;
}

// ---------------------------------------------------------------------------
// Profile header section — wraps all header widgets
// ---------------------------------------------------------------------------

class _ProfileHeaderSection extends StatelessWidget {
  const _ProfileHeaderSection({
    required this.topPad,
    required this.streak,
    required this.showLevelUpBanner,
    required this.glowFlashBoost,
    required this.bio,
    required this.onEdit,
    required this.onSearch,
    required this.onPin,
    required this.onEditBio,
    required this.onPost,
  });

  final double topPad;
  final StreakData? streak;
  final bool showLevelUpBanner;
  final double glowFlashBoost;
  final _UserBio bio;
  final VoidCallback onEdit;
  final VoidCallback onSearch;
  final VoidCallback onPin;
  final VoidCallback onEditBio;
  final VoidCallback onPost;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (streak != null && !streak!.postedToday && streak!.isAlive)
          _StreakReminderBanner(streak: streak!, onPost: onPost),
        if (showLevelUpBanner)
          _LevelUpBanner(
            tierName: 'Prominent',
            tierNumber: 3,
            color: const Color(0xFFFF6B4A),
          ),
        _ProfileHeader(
          topPad: topPad,
          onEdit: onEdit,
          onSearch: onSearch,
          onPin: onPin,
          bio: bio,
          onEditBio: onEditBio,
          streak: streak,
          glowFlashBoost: glowFlashBoost,
        ),
        const SizedBox(height: 12),
        const GroupCirclesRow(),
        const SizedBox(height: 4),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Sticky tab bar — plain widget, no sliver, no assertion issues
// ---------------------------------------------------------------------------

class _StickyTabBar extends StatelessWidget {
  const _StickyTabBar({required this.controller});
  final TabController controller;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      child: TabBar(
        controller: controller,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        indicatorColor: AppColors.primary,
        indicatorWeight: 2,
        dividerColor: Colors.transparent,
        labelColor: AppColors.textPrimary,
        unselectedLabelColor: AppColors.textMuted,
        labelPadding: const EdgeInsets.symmetric(horizontal: 14),
        labelStyle: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600),
        unselectedLabelStyle:
            GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w400),
        tabs: const [
          Tab(text: 'Posts'),
          Tab(text: 'Private'),
          Tab(text: 'Moments'),
          Tab(text: 'Groups'),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Profile header — banner + circle + bio + score (Snapchat-style)
// ---------------------------------------------------------------------------

class _ProfileHeader extends StatefulWidget {
  const _ProfileHeader({
    required this.topPad,
    required this.onEdit,
    required this.onSearch,
    required this.onPin,
    required this.bio,
    required this.onEditBio,
    this.streak,
    this.glowFlashBoost = 1.0,
  });

  final double topPad;
  final VoidCallback onEdit;
  final VoidCallback onSearch;
  final VoidCallback onPin;
  final _UserBio bio;
  final VoidCallback onEditBio;
  final StreakData? streak;
  final double glowFlashBoost;

  @override
  State<_ProfileHeader> createState() => _ProfileHeaderState();
}

class _ProfileHeaderState extends State<_ProfileHeader> {
  int _bannerIdx = 0;

  static const _banners = <LinearGradient>[
    LinearGradient(
      colors: [Color(0xFF1A1040), Color(0xFF3B1E50), Color(0xFF6B2D5E)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    LinearGradient(
      colors: [Color(0xFF0D2B45), Color(0xFF1A4060), Color(0xFF0D3050)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    LinearGradient(
      colors: [Color(0xFF1A2820), Color(0xFF2A4030), Color(0xFF1E4028)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    LinearGradient(
      colors: [Color(0xFF2A1A10), Color(0xFF4A2A18), Color(0xFF3A1E10)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    LinearGradient(
      colors: [Color(0xFF1A1A2A), Color(0xFF2A2040), Color(0xFF1E1830)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final bio = widget.bio;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Top bar: search (left) · pin · spacer · edit ──
        Padding(
          padding: EdgeInsets.fromLTRB(16, widget.topPad + 12, 16, 0),
          child: Row(
            children: [
              GestureDetector(
                onTap: widget.onSearch,
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppColors.cardSurface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Icon(Icons.search_rounded, size: 18, color: AppColors.textPrimary),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: widget.onPin,
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppColors.cardSurface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      const Icon(Icons.push_pin_rounded, size: 18, color: AppColors.textPrimary),
                      Positioned(
                        top: 7,
                        right: 7,
                        child: Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(
                            color: AppColors.coral,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: widget.onEdit,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.30)),
                  ),
                  child: Text(
                    'Edit',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ── Banner + profile circle overlapping bottom-left ──
        Stack(
          clipBehavior: Clip.none,
          children: [
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                setState(() => _bannerIdx = (_bannerIdx + 1) % _banners.length);
              },
              child: Container(
                width: double.infinity,
                height: 150,
                decoration: BoxDecoration(gradient: _banners[_bannerIdx]),
                child: Align(
                  alignment: Alignment.bottomRight,
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Tap to change',
                        style: GoogleFonts.inter(
                          fontSize: 9,
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Profile circle: overlaps banner's bottom-left edge
            Positioned(
              bottom: -43,
              left: 16,
              child: _ProfileAvatar(glowFlashBoost: widget.glowFlashBoost),
            ),
          ],
        ),
        // 43px circle overflow + 12px gap before name
        const SizedBox(height: 55),

        // ── Bio: name, username, headline, bio text, location, interests ──
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    _profileName,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (widget.streak != null && widget.streak!.count > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.coral.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.coral.withValues(alpha: 0.35)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('🔥', style: TextStyle(fontSize: 11)),
                          const SizedBox(width: 3),
                          Text(
                            '${widget.streak!.count}d',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: AppColors.coral,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(
                _profileUsername,
                style: GoogleFonts.jetBrainsMono(fontSize: 11, color: AppColors.textMuted),
              ),
              if (bio.headline.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  bio.headline,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
              if (bio.bioText.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  bio.bioText,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppColors.textMuted,
                    height: 1.5,
                  ),
                ),
              ],
              if (bio.location.isNotEmpty || bio.education.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    if (bio.location.isNotEmpty)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.location_on_outlined, size: 11, color: AppColors.textMuted),
                          const SizedBox(width: 3),
                          Text(bio.location, style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted)),
                        ],
                      ),
                    if (bio.education.isNotEmpty)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.school_outlined, size: 11, color: AppColors.textMuted),
                          const SizedBox(width: 3),
                          Text(bio.education, style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted)),
                        ],
                      ),
                  ],
                ),
              ],
              if (bio.interests.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: bio.interests
                      .map(
                        (tag) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.primary.withValues(alpha: 0.20)),
                          ),
                          child: Text(
                            '#$tag',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
              const SizedBox(height: 10),
              GestureDetector(
                onTap: widget.onEditBio,
                child: Text(
                  'Edit bio',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary.withValues(alpha: 0.75),
                    decoration: TextDecoration.underline,
                    decorationColor: AppColors.primary.withValues(alpha: 0.40),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // ── Anon persona photo — a separate image the user picks to
        // represent their anonymous identity. Never the real profile photo
        // above, never shows _profileName; only ever used on anon posts. ──
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: Row(
            children: [
              const _AnonPersonaPhotoPicker(),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Anon persona photo',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Shown on your anonymous posts. Not your real photo or name.',
                      style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted, height: 1.3),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // ── Compact score strip with glow ring ──
        _CompactScoreStrip(
          score: _profileScore,
          glowFlashBoost: widget.glowFlashBoost,
        ),
        const SizedBox(height: 14),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Anon persona photo picker — same upload mechanics as _ProfileAvatar
// (gallery pick → StorageService → public URL) but writes to a distinct
// storage path via uploadPersonaPhoto and publishes through
// AnonPersonaService rather than any real-profile field. Deliberately no
// ScoreGlowRing here — that ring is a real-identity status signal; the
// persona photo is anonymous by definition.
// ---------------------------------------------------------------------------

class _AnonPersonaPhotoPicker extends StatefulWidget {
  const _AnonPersonaPhotoPicker();

  @override
  State<_AnonPersonaPhotoPicker> createState() => _AnonPersonaPhotoPickerState();
}

class _AnonPersonaPhotoPickerState extends State<_AnonPersonaPhotoPicker> {
  File? _localImage;
  bool _isUploading = false;
  bool _hasError = false;

  Future<void> _pickAndUpload() async {
    final picker = ImagePicker();
    final xFile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1080,
      imageQuality: 85,
    );
    if (xFile == null || !mounted) return;
    final file = File(xFile.path);
    setState(() {
      _localImage = file;
      _isUploading = true;
      _hasError = false;
    });
    final url = await StorageService.uploadPersonaPhoto(
      file: file,
      userId: 'user_abhishek',
    );
    if (!mounted) return;
    setState(() => _isUploading = false);
    if (url != null) {
      AnonPersonaService.instance.setPhoto(url);
    } else {
      setState(() => _hasError = true);
    }
  }

  Widget _buildImage() {
    final uploadedUrl = AnonPersonaService.instance.photoUrl;
    if (_localImage != null) {
      return ClipOval(
        child: Image.file(_localImage!, width: 52, height: 52, fit: BoxFit.cover),
      );
    }
    if (uploadedUrl != null) {
      return ClipOval(
        child: CachedNetworkImage(
          imageUrl: uploadedUrl,
          width: 52,
          height: 52,
          fit: BoxFit.cover,
          placeholder: (context, url) => const Center(
            child: SizedBox(
              width: 16, height: 16,
              child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2),
            ),
          ),
          errorWidget: (context, url, error) =>
              const Icon(Icons.theater_comedy_outlined, color: AppColors.textMuted, size: 22),
        ),
      );
    }
    return const Icon(Icons.theater_comedy_outlined, color: AppColors.textMuted, size: 22);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _isUploading ? null : _pickAndUpload,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.cardSurface,
              border: Border.all(color: Colors.white.withValues(alpha: 0.18), width: 1.5),
            ),
            child: _hasError
                ? const Icon(Icons.error_outline, color: AppColors.errorRed, size: 20)
                : _buildImage(),
          ),
          if (_isUploading)
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.black.withValues(alpha: 0.50)),
              child: const Center(
                child: SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2),
                ),
              ),
            ),
          if (!_isUploading)
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.background, width: 1.5),
                ),
                child: const Icon(Icons.camera_alt, size: 10, color: AppColors.onPrimary),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Compact horizontal score strip
// ---------------------------------------------------------------------------

class _CompactScoreStrip extends StatelessWidget {
  const _CompactScoreStrip({required this.score, this.glowFlashBoost = 1.0});

  final int score;
  final double glowFlashBoost;

  @override
  Widget build(BuildContext context) {
    final info = tierInfoForScore(score);
    final progress = tierProgressToNext(score);
    final ptsAway = pointsToNextTier(score);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: info.color.withValues(alpha: 0.30)),
          boxShadow: [
            BoxShadow(
              color: info.color.withValues(alpha: 0.12 * glowFlashBoost),
              blurRadius: 16,
            ),
          ],
        ),
        child: Row(
          children: [
            ScoreGlowRing(
              score: score,
              size: 52,
              borderWidth: 2.5,
              flashBoost: glowFlashBoost,
              child: Container(color: AppColors.background),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      '$score',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: info.color,
                        height: 1.0,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: info.color.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: info.color.withValues(alpha: 0.28)),
                      ),
                      child: Text(
                        info.title.toLowerCase(),
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 8,
                          color: info.color,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  'anon score',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 8,
                    color: AppColors.textMuted,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
            if (ptsAway != null) ...[
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '~$ptsAway pts to next',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 9,
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: progress,
                        backgroundColor: info.color.withValues(alpha: 0.15),
                        valueColor: AlwaysStoppedAnimation<Color>(info.color),
                        minHeight: 4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Profile avatar
// ---------------------------------------------------------------------------

class _ProfileAvatar extends StatefulWidget {
  const _ProfileAvatar({this.glowFlashBoost = 1.0});

  final double glowFlashBoost;

  @override
  State<_ProfileAvatar> createState() => _ProfileAvatarState();
}

class _ProfileAvatarState extends State<_ProfileAvatar> {
  File? _localImage;
  String? _uploadedUrl;
  bool _isUploading = false;
  bool _hasError = false;

  Future<void> _pickAndUpload() async {
    final picker = ImagePicker();
    final xFile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1080,
      imageQuality: 85,
    );
    if (xFile == null || !mounted) return;
    final file = File(xFile.path);
    setState(() {
      _localImage = file;
      _isUploading = true;
      _hasError = false;
    });
    final url = await StorageService.uploadAvatar(
      file: file,
      userId: 'user_abhishek',
    );
    if (!mounted) return;
    setState(() {
      _isUploading = false;
      if (url != null) {
        _uploadedUrl = url;
      } else {
        _hasError = true;
      }
    });
  }

  Widget _buildImage() {
    if (_localImage != null) {
      return ClipOval(
        child: Image.file(_localImage!, width: 82, height: 82, fit: BoxFit.cover),
      );
    }
    if (_uploadedUrl != null) {
      return ClipOval(
        child: CachedNetworkImage(
          imageUrl: _uploadedUrl!,
          width: 82,
          height: 82,
          fit: BoxFit.cover,
          placeholder: (context, url) => const Center(
            child: CircularProgressIndicator(
              color: AppColors.primary,
              strokeWidth: 2,
            ),
          ),
          errorWidget: (context, url, error) => Center(
            child: Text(
              'A',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 32,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ),
        ),
      );
    }
    return Center(
      child: Text(
        'A',
        style: GoogleFonts.plusJakartaSans(
          fontSize: 32,
          fontWeight: FontWeight.w700,
          color: AppColors.primary,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _isUploading ? null : _pickAndUpload,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Glow ring wraps the avatar
          ScoreGlowRing(
            score: _profileScore,
            size: 86,
            borderWidth: 2.5,
            flashBoost: widget.glowFlashBoost,
            child: Container(
              color: AppColors.cardSurface,
              child: _hasError
                  ? const Center(
                      child: Icon(Icons.error_outline,
                          color: AppColors.errorRed, size: 28))
                  : _buildImage(),
            ),
          ),
          // Uploading spinner overlay
          if (_isUploading)
            Container(
              width: 86,
              height: 86,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withValues(alpha: 0.50),
              ),
              child: const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    color: AppColors.primary,
                    strokeWidth: 2,
                  ),
                ),
              ),
            ),
          // Camera icon badge (tap hint)
          if (!_isUploading)
            Positioned(
              bottom: 2,
              right: 2,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.background, width: 1.5),
                ),
                child: const Icon(
                  Icons.camera_alt,
                  size: 12,
                  color: AppColors.onPrimary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Score ring (uses shared ScoreTier system)
// ---------------------------------------------------------------------------

class _ScoreRing extends StatefulWidget {
  const _ScoreRing({required this.score});

  final int score;

  @override
  State<_ScoreRing> createState() => _ScoreRingState();
}

class _ScoreRingState extends State<_ScoreRing>
    with SingleTickerProviderStateMixin {
  AnimationController? _pulseCtrl;
  Animation<double>? _pulseAnim;

  @override
  void initState() {
    super.initState();
    final info = tierInfoForScore(widget.score);
    if (info.tier == ScoreTier.legend) {
      _pulseCtrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 2000),
      )..repeat(reverse: true);
      _pulseAnim = Tween<double>(begin: 0.35, end: 1.0).animate(
        CurvedAnimation(parent: _pulseCtrl!, curve: Curves.easeInOut),
      );
    }
  }

  @override
  void dispose() {
    _pulseCtrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final info = tierInfoForScore(widget.score);
    final color = info.color;
    final next = nextTierThreshold(widget.score);
    final progress = tierProgressToNext(widget.score);

    if (_pulseAnim != null) {
      return AnimatedBuilder(
        animation: _pulseAnim!,
        builder: (context2, child2) => _buildContent(
          info: info,
          color: color,
          glowAlpha: _pulseAnim!.value,
          next: next,
          progress: progress,
        ),
      );
    }
    return _buildContent(
      info: info,
      color: color,
      glowAlpha: 1.0,
      next: next,
      progress: progress,
    );
  }

  Widget _buildContent({
    required ScoreTierInfo info,
    required Color color,
    required double glowAlpha,
    required int? next,
    required double progress,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            // Glow halo
            if (info.glowBlur > 0)
              Container(
                width: 116,
                height: 116,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.35 * glowAlpha),
                      blurRadius: info.glowBlur + 8,
                      spreadRadius: 4,
                    ),
                  ],
                ),
              ),
            // Ring border
            Container(
              width: 108,
              height: 108,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 3),
                color: AppColors.background,
              ),
            ),
            // Score number + label
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${widget.score}',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    color: color,
                    height: 1.0,
                  ),
                ),
                Text(
                  'anon score',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 8,
                    color: AppColors.textMuted,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Tier badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.28)),
          ),
          child: Text(
            info.title.toLowerCase(),
            style: GoogleFonts.jetBrainsMono(
              fontSize: 9,
              color: color,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ),
        // Progress bar to next tier
        if (next != null) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: 108,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${widget.score} pts',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 8,
                        color: AppColors.textMuted,
                      ),
                    ),
                    Text(
                      '$next to ${_nextTierTitle(info.tier)}',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 8,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: color.withValues(alpha: 0.15),
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                    minHeight: 3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  String _nextTierTitle(ScoreTier current) {
    switch (current) {
      case ScoreTier.lurker:
        return 'Active';
      case ScoreTier.active:
        return 'Prominent';
      case ScoreTier.prominent:
        return 'Legend';
      case ScoreTier.legend:
        return '';
    }
  }
}

// ---------------------------------------------------------------------------
// Level-up banner — slides in from top on tier upgrade
// ---------------------------------------------------------------------------

class _LevelUpBanner extends StatefulWidget {
  const _LevelUpBanner({
    required this.tierName,
    required this.tierNumber,
    required this.color,
  });

  final String tierName;
  final int tierNumber;
  final Color color;

  @override
  State<_LevelUpBanner> createState() => _LevelUpBannerState();
}

class _LevelUpBannerState extends State<_LevelUpBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    )..forward();
    _slide = Tween<Offset>(
      begin: const Offset(0, -1.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack));
    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slide,
      child: FadeTransition(
        opacity: _opacity,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: widget.color.withValues(alpha: 0.15),
            border: Border(
              bottom: BorderSide(
                  color: widget.color.withValues(alpha: 0.40), width: 1),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color.withValues(alpha: 0.15),
                  border: Border.all(
                      color: widget.color.withValues(alpha: 0.55), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: widget.color.withValues(alpha: 0.45),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    '${widget.tierNumber}',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: widget.color,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'You reached Tier ${widget.tierNumber} — ${widget.tierName}! ✨',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: widget.color,
                      ),
                    ),
                    Text(
                      'Your glow ring just got brighter',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: widget.color.withValues(alpha: 0.75),
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

// ---------------------------------------------------------------------------
// Streak reminder banner — appears at top when user hasn't posted today
// ---------------------------------------------------------------------------

class _StreakReminderBanner extends StatelessWidget {
  const _StreakReminderBanner({
    required this.streak,
    required this.onPost,
  });

  final StreakData streak;
  final VoidCallback onPost;

  @override
  Widget build(BuildContext context) {
    final isUrgent = streak.hoursSinceLastPost >= 20;
    final message = isUrgent
        ? '24h left to keep your streak 🔥'
        : 'Your ${streak.count}-day streak is alive! Post today to keep it 🔥';

    return GestureDetector(
      onTap: onPost,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isUrgent
              ? AppColors.coral.withValues(alpha: 0.14)
              : AppColors.coral.withValues(alpha: 0.08),
          border: Border(
            bottom: BorderSide(
              color: AppColors.coral.withValues(alpha: isUrgent ? 0.40 : 0.22),
            ),
          ),
        ),
        child: Row(
          children: [
            Text('🔥', style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.coral,
                  height: 1.35,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.coral,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Post now',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Community badges
// ---------------------------------------------------------------------------
// Score breakdown
// ---------------------------------------------------------------------------

class _ScoreBreakdown extends StatefulWidget {
  const _ScoreBreakdown();

  @override
  State<_ScoreBreakdown> createState() => _ScoreBreakdownState();
}

class _ScoreBreakdownState extends State<_ScoreBreakdown> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.cardSurface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.bolt_rounded,
                      size: 13,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Recent activity',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textMuted,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 16,
                      color: AppColors.textMuted,
                    ),
                  ],
                ),
                if (_expanded) ...[
                  const SizedBox(height: 10),
                  for (final item in _scoreBreakdown)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Text(
                            item.label,
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 11,
                              color: item.label.startsWith('+')
                                  ? AppColors.primary
                                  : AppColors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            item.time,
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 9,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Creation buttons (Collage + Highlight)
// ---------------------------------------------------------------------------

class _CreationButtons extends StatelessWidget {
  const _CreationButtons({this.onCreated});
  final VoidCallback? onCreated;

  void _openCollage(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => const CollageBuilderScreen(),
      ),
    );
  }

  void _openHighlight(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => HighlightCreatorView(
          onClose: () => Navigator.of(context).pop(),
          onBack: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  void _openMemoryCreator(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => const PhotoPickerScreen(),
      ),
    ).then((_) => onCreated?.call());
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Primary "Create Memory" button — full width, accent
        GestureDetector(
          onTap: () => _openMemoryCreator(context),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 13),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1e3a8a), Color(0xFF2563EB)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: const Color(0xFF2563EB).withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 4))],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.auto_awesome_mosaic_rounded, size: 16, color: Colors.white),
                const SizedBox(width: 8),
                Text(
                  'Create Memory',
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        // Secondary row
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () => _openCollage(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: BoxDecoration(
                    color: AppColors.cardSurface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.grid_view_rounded, size: 16, color: AppColors.textPrimary),
                      const SizedBox(height: 4),
                      Text('Collage', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GestureDetector(
                onTap: () => _openHighlight(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: BoxDecoration(
                    color: AppColors.cardSurface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.auto_awesome_rounded, size: 16, color: AppColors.textPrimary),
                      const SizedBox(height: 4),
                      Text('Highlight', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Pin modal — bottom sheet showing pinned people
// ---------------------------------------------------------------------------

class _PinModal extends StatefulWidget {
  const _PinModal();

  @override
  State<_PinModal> createState() => _PinModalState();
}

class _PinModalState extends State<_PinModal> {
  late final List<_PinnedPerson> _pinned;

  @override
  void initState() {
    super.initState();
    _pinned = List.from(_pinnedPeople);
  }

  void _unpin(int index) {
    HapticFeedback.lightImpact();
    setState(() => _pinned.removeAt(index));
  }

  void _openDetail(_PinnedPerson person) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PinnedDetailSheet(person: person),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 0),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 14),
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Icon(Icons.push_pin_rounded, size: 16, color: AppColors.textPrimary),
                const SizedBox(width: 8),
                Text(
                  'Your Pinned People',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
                  ),
                  child: Text(
                    '${_pinned.length}/6',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.border),
                    ),
                    child: const Icon(Icons.close_rounded, size: 14, color: AppColors.textMuted),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Silent. They\'ll never know.',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 10,
                color: AppColors.textMuted,
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: AppColors.border),

          // Pinned list
          if (_pinned.isEmpty)
            Padding(
              padding: EdgeInsets.fromLTRB(20, 32, 20, bottomPad + 32),
              child: Column(
                children: [
                  const Icon(Icons.push_pin_outlined, size: 28, color: AppColors.textMuted),
                  const SizedBox(height: 10),
                  Text(
                    'No pinned people yet.\nGo to a profile and tap Pin.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(fontSize: 13, color: AppColors.textMuted, height: 1.5),
                  ),
                ],
              ),
            )
          else
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.55,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPad + 20),
                itemCount: _pinned.length,
                separatorBuilder: (context, _) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final person = _pinned[i];
                  return _PinModalRow(
                    person: person,
                    onUnpin: () => _unpin(i),
                    onTap: () => _openDetail(person),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _PinModalRow extends StatelessWidget {
  const _PinModalRow({
    required this.person,
    required this.onUnpin,
    required this.onTap,
  });

  final _PinnedPerson person;
  final VoidCallback onUnpin;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: person.avatarColor,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.35), width: 1.5),
              ),
              child: Center(
                child: Text(
                  person.avatarInitial,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    person.displayName,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    '@${person.username} · ${person.lastActivityLabel}',
                    style: GoogleFonts.jetBrainsMono(fontSize: 9, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'pinned',
                style: GoogleFonts.jetBrainsMono(fontSize: 8, color: AppColors.primary, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onUnpin,
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: AppColors.errorRed.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.errorRed.withValues(alpha: 0.25)),
                ),
                child: const Icon(Icons.close_rounded, size: 13, color: AppColors.errorRed),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Search screen — full-screen with People | Communities | Following tabs
// ---------------------------------------------------------------------------

class _SearchPerson {
  _SearchPerson({
    required this.name,
    required this.handle,
    required this.avatarColor,
    required this.isFollowing,
  });
  final String name;
  final String handle;
  final Color avatarColor;
  bool isFollowing;
}

class _SearchCommunity {
  _SearchCommunity({
    required this.name,
    required this.members,
    required this.joined,
  });
  final String name;
  final int members;
  bool joined;
}

class _SearchScreen extends StatefulWidget {
  const _SearchScreen();

  @override
  State<_SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<_SearchScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _queryCtrl = TextEditingController();
  String _query = '';

  final _people = <_SearchPerson>[
    _SearchPerson(name: 'Aarav Mehta', handle: 'debug_zero', avatarColor: const Color(0xFF1A2840), isFollowing: false),
    _SearchPerson(name: 'Priya Sinha', handle: 'null_ptr', avatarColor: const Color(0xFF2A1822), isFollowing: true),
    _SearchPerson(name: 'Rishi Kapoor', handle: 'rooftop_kid', avatarColor: const Color(0xFF201412), isFollowing: false),
    _SearchPerson(name: 'Kavya Menon', handle: 'silent_river', avatarColor: const Color(0xFF12181A), isFollowing: true),
    _SearchPerson(name: 'Arjun Kumar', handle: 'third_life', avatarColor: const Color(0xFF1A1828), isFollowing: false),
    _SearchPerson(name: 'Vikram Iyer', handle: 'resume_run', avatarColor: const Color(0xFF1A2818), isFollowing: false),
    _SearchPerson(name: 'Sneha Gupta', handle: 'hex_dreams', avatarColor: const Color(0xFF201828), isFollowing: true),
    _SearchPerson(name: 'Kabir Patel', handle: 'shutter_soul', avatarColor: const Color(0xFF18101A), isFollowing: false),
  ];

  final _communities = <_SearchCommunity>[
    _SearchCommunity(name: 'CSE', members: 547, joined: true),
    _SearchCommunity(name: '3rd Year', members: 623, joined: true),
    _SearchCommunity(name: 'Campus', members: 2341, joined: false),
    _SearchCommunity(name: 'Photo Club', members: 89, joined: false),
    _SearchCommunity(name: 'Art Society', members: 134, joined: false),
    _SearchCommunity(name: 'Coding Club', members: 212, joined: false),
  ];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _queryCtrl.addListener(() => setState(() => _query = _queryCtrl.text.trim().toLowerCase()));
  }

  @override
  void dispose() {
    _tabs.dispose();
    _queryCtrl.dispose();
    super.dispose();
  }

  List<_SearchPerson> get _filteredPeople {
    if (_query.isEmpty) return _people;
    return _people
        .where((p) => p.name.toLowerCase().contains(_query) || p.handle.toLowerCase().contains(_query))
        .toList();
  }

  List<_SearchPerson> get _following => _people.where((p) => p.isFollowing).toList();

  void _toggleFollow(_SearchPerson person) {
    HapticFeedback.lightImpact();
    setState(() => person.isFollowing = !person.isFollowing);
  }

  void _toggleJoin(_SearchCommunity c) {
    HapticFeedback.lightImpact();
    setState(() => c.joined = !c.joined);
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          // ── Top bar ─────────────────────────────────────────────────────
          Container(
            padding: EdgeInsets.fromLTRB(16, topPad + 10, 16, 10),
            decoration: const BoxDecoration(
              color: AppColors.background,
              border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
            ),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.cardSurface,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.border),
                    ),
                    child: const Icon(Icons.close_rounded, size: 16, color: AppColors.textPrimary),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.cardSurface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: TextField(
                      controller: _queryCtrl,
                      autofocus: true,
                      style: GoogleFonts.inter(fontSize: 14, color: AppColors.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'Search people, communities…',
                        hintStyle: GoogleFonts.inter(fontSize: 13, color: AppColors.textMuted),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        prefixIcon: const Icon(Icons.search_rounded, size: 16, color: AppColors.textMuted),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Tabs ────────────────────────────────────────────────────────
          DecoratedBox(
            decoration: const BoxDecoration(
              color: AppColors.background,
              border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
            ),
            child: TabBar(
              controller: _tabs,
              indicatorColor: AppColors.coral,
              indicatorWeight: 2,
              dividerColor: Colors.transparent,
              labelColor: AppColors.textPrimary,
              unselectedLabelColor: AppColors.textMuted,
              labelStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
              unselectedLabelStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w400),
              tabs: const [
                Tab(text: 'People'),
                Tab(text: 'Communities'),
                Tab(text: 'Following'),
              ],
            ),
          ),

          // ── Tab content ─────────────────────────────────────────────────
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                // People tab
                ListView.separated(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPad + 20),
                  itemCount: _filteredPeople.isEmpty ? 1 : _filteredPeople.length,
                  separatorBuilder: (context, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    if (_filteredPeople.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40),
                        child: Center(
                          child: Text(
                            'No people found',
                            style: GoogleFonts.inter(fontSize: 13, color: AppColors.textMuted),
                          ),
                        ),
                      );
                    }
                    return _SearchPersonRow(
                      person: _filteredPeople[i],
                      onToggleFollow: () => _toggleFollow(_filteredPeople[i]),
                    );
                  },
                ),

                // Communities tab
                ListView.separated(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPad + 20),
                  itemCount: _communities.length,
                  separatorBuilder: (context, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) => _CommunityRow(
                    community: _communities[i],
                    onToggle: () => _toggleJoin(_communities[i]),
                  ),
                ),

                // Following tab
                _following.isEmpty
                    ? Center(
                        child: Text(
                          'Not following anyone yet',
                          style: GoogleFonts.inter(fontSize: 13, color: AppColors.textMuted),
                        ),
                      )
                    : ListView.separated(
                        padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPad + 20),
                        itemCount: _following.length,
                        separatorBuilder: (context, _) => const SizedBox(height: 8),
                        itemBuilder: (context, i) => _SearchPersonRow(
                          person: _following[i],
                          onToggleFollow: () => _toggleFollow(_following[i]),
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

class _SearchPersonRow extends StatelessWidget {
  const _SearchPersonRow({required this.person, required this.onToggleFollow});

  final _SearchPerson person;
  final VoidCallback onToggleFollow;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          ScoreGlowRing(
            score: 150,
            size: 40,
            borderWidth: 1.5,
            child: Container(
              decoration: BoxDecoration(color: person.avatarColor, shape: BoxShape.circle),
              child: Center(
                child: Text(
                  person.name[0],
                  style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  person.name,
                  style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                ),
                Text(
                  '@${person.handle}',
                  style: GoogleFonts.jetBrainsMono(fontSize: 10, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onToggleFollow,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: person.isFollowing
                    ? AppColors.cardSurface
                    : AppColors.primary,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: person.isFollowing
                      ? AppColors.border
                      : AppColors.primary,
                ),
              ),
              child: Text(
                person.isFollowing ? 'Following' : 'Follow',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: person.isFollowing ? AppColors.textMuted : Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CommunityRow extends StatelessWidget {
  const _CommunityRow({required this.community, required this.onToggle});

  final _SearchCommunity community;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: community.joined ? AppColors.coral.withValues(alpha: 0.40) : AppColors.border,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: community.joined
                  ? AppColors.coral.withValues(alpha: 0.14)
                  : AppColors.background,
              shape: BoxShape.circle,
              border: Border.all(
                color: community.joined
                    ? AppColors.coral.withValues(alpha: 0.40)
                    : AppColors.border,
              ),
            ),
            child: Center(
              child: Text(
                community.name[0],
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: community.joined ? AppColors.coral : AppColors.textPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  community.name,
                  style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                ),
                Text(
                  '${community.members} members',
                  style: GoogleFonts.jetBrainsMono(fontSize: 10, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onToggle,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: community.joined ? AppColors.cardSurface : AppColors.coral,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: community.joined ? AppColors.border : AppColors.coral,
                ),
              ),
              child: Text(
                community.joined ? 'Joined' : 'Join',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: community.joined ? AppColors.textMuted : Colors.white,
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
// Bio edit sheet
// ---------------------------------------------------------------------------

class _BioEditSheet extends StatefulWidget {
  const _BioEditSheet({required this.bio});
  final _UserBio bio;

  @override
  State<_BioEditSheet> createState() => _BioEditSheetState();
}

class _BioEditSheetState extends State<_BioEditSheet> {
  late final TextEditingController _headlineCtrl;
  late final TextEditingController _bioTextCtrl;
  late final TextEditingController _locationCtrl;
  late final TextEditingController _educationCtrl;
  late final TextEditingController _majorCtrl;
  late final TextEditingController _instagramCtrl;
  late final TextEditingController _twitterCtrl;
  late final TextEditingController _linkedinCtrl;
  late final TextEditingController _portfolioCtrl;
  late final TextEditingController _interestAddCtrl;

  late String _selectedYear;
  late List<String> _interests;

  static const _years = [
    '1st Year',
    '2nd Year',
    '3rd Year',
    '4th Year',
    'Alumni',
  ];

  @override
  void initState() {
    super.initState();
    final b = widget.bio;
    _headlineCtrl = TextEditingController(text: b.headline);
    _bioTextCtrl = TextEditingController(text: b.bioText);
    _locationCtrl = TextEditingController(text: b.location);
    _educationCtrl = TextEditingController(text: b.education);
    _majorCtrl = TextEditingController(text: b.major);
    _instagramCtrl = TextEditingController(text: b.instagram);
    _twitterCtrl = TextEditingController(text: b.twitter);
    _linkedinCtrl = TextEditingController(text: b.linkedin);
    _portfolioCtrl = TextEditingController(text: b.portfolio);
    _interestAddCtrl = TextEditingController();
    _selectedYear = _years.contains(b.year) ? b.year : '3rd Year';
    _interests = List.from(b.interests);
  }

  @override
  void dispose() {
    _headlineCtrl.dispose();
    _bioTextCtrl.dispose();
    _locationCtrl.dispose();
    _educationCtrl.dispose();
    _majorCtrl.dispose();
    _instagramCtrl.dispose();
    _twitterCtrl.dispose();
    _linkedinCtrl.dispose();
    _portfolioCtrl.dispose();
    _interestAddCtrl.dispose();
    super.dispose();
  }

  void _addInterest(String tag) {
    final trimmed = tag.trim().replaceAll('#', '');
    if (trimmed.isEmpty || _interests.contains(trimmed)) return;
    setState(() => _interests.add(trimmed));
    _interestAddCtrl.clear();
  }

  void _removeInterest(String tag) => setState(() => _interests.remove(tag));

  void _save() {
    final updated = widget.bio.copyWith(
      headline: _headlineCtrl.text.trim(),
      bioText: _bioTextCtrl.text.trim(),
      location: _locationCtrl.text.trim(),
      education: _educationCtrl.text.trim(),
      major: _majorCtrl.text.trim(),
      year: _selectedYear,
      interests: List.from(_interests),
      instagram: _instagramCtrl.text.trim(),
      twitter: _twitterCtrl.text.trim(),
      linkedin: _linkedinCtrl.text.trim(),
      portfolio: _portfolioCtrl.text.trim(),
    );
    Navigator.of(context).pop(updated);
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final keyboardPad = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 60, 10, 0),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: Row(
              children: [
                Text(
                  'Edit Bio',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.inter(fontSize: 13, color: AppColors.textMuted),
                  ),
                ),
                const SizedBox(width: 16),
                GestureDetector(
                  onTap: _save,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Save',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: AppColors.border),

          // Scrollable form
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                  20, 16, 20, bottomPad + keyboardPad + 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _BioEditField(
                    label: 'HEADLINE',
                    controller: _headlineCtrl,
                    hint: 'CSE Student | Photography | Always coding',
                    maxLength: 80,
                  ),
                  const SizedBox(height: 14),
                  _BioEditField(
                    label: 'BIO',
                    controller: _bioTextCtrl,
                    hint: 'Tell your campus what you\'re about…',
                    maxLines: 4,
                    maxLength: 200,
                  ),
                  const SizedBox(height: 14),
                  _BioEditField(
                    label: 'LOCATION',
                    controller: _locationCtrl,
                    hint: 'Bengaluru, India',
                  ),
                  const SizedBox(height: 14),
                  _BioEditField(
                    label: 'COLLEGE / UNIVERSITY',
                    controller: _educationCtrl,
                    hint: 'RV College of Engineering',
                  ),
                  const SizedBox(height: 14),
                  _BioEditField(
                    label: 'MAJOR / FIELD',
                    controller: _majorCtrl,
                    hint: 'Computer Science',
                  ),
                  const SizedBox(height: 14),

                  // Year selector chips
                  _BioFieldLabel('YEAR'),
                  const SizedBox(height: 6),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _years.map((y) {
                        final selected = y == _selectedYear;
                        return GestureDetector(
                          onTap: () =>
                              setState(() => _selectedYear = y),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: selected
                                  ? AppColors.primary
                                  : AppColors.background,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: selected
                                    ? AppColors.primary
                                    : AppColors.border,
                              ),
                            ),
                            child: Text(
                              y,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: selected
                                    ? Colors.white
                                    : AppColors.textMuted,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),

                  const SizedBox(height: 16),
                  const Divider(height: 1, color: AppColors.border),
                  const SizedBox(height: 16),

                  // Interests
                  _BioFieldLabel('INTERESTS'),
                  const SizedBox(height: 8),
                  if (_interests.isNotEmpty) ...[
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _interests
                          .map((tag) => _InterestTagEditable(
                                label: tag,
                                onRemove: () => _removeInterest(tag),
                              ))
                          .toList(),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: TextField(
                            controller: _interestAddCtrl,
                            style: GoogleFonts.inter(
                                fontSize: 13,
                                color: AppColors.textPrimary),
                            onSubmitted: _addInterest,
                            decoration: InputDecoration(
                              border: InputBorder.none,
                              hintText: 'Add interest…',
                              hintStyle: GoogleFonts.inter(
                                  fontSize: 13,
                                  color: AppColors.textMuted),
                              contentPadding:
                                  const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 10),
                              prefixText: '#',
                              prefixStyle: GoogleFonts.inter(
                                fontSize: 13,
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () =>
                            _addInterest(_interestAddCtrl.text),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.add_rounded,
                              size: 18, color: Colors.white),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),
                  const Divider(height: 1, color: AppColors.border),
                  const SizedBox(height: 16),

                  // Social links
                  _BioFieldLabel('SOCIAL LINKS'),
                  const SizedBox(height: 10),
                  _BioEditField(
                    label: 'Instagram handle',
                    controller: _instagramCtrl,
                    hint: 'your.handle',
                    prefixEmoji: '📸',
                  ),
                  const SizedBox(height: 10),
                  _BioEditField(
                    label: 'Twitter / X handle',
                    controller: _twitterCtrl,
                    hint: '@yourhandle',
                    prefixEmoji: '🐦',
                  ),
                  const SizedBox(height: 10),
                  _BioEditField(
                    label: 'LinkedIn handle',
                    controller: _linkedinCtrl,
                    hint: 'linkedin-handle',
                    prefixEmoji: '💼',
                  ),
                  const SizedBox(height: 10),
                  _BioEditField(
                    label: 'Portfolio URL',
                    controller: _portfolioCtrl,
                    hint: 'myportfolio.com',
                    prefixEmoji: '🔗',
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

class _BioFieldLabel extends StatelessWidget {
  const _BioFieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.jetBrainsMono(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: AppColors.textMuted,
        letterSpacing: 0.6,
      ),
    );
  }
}

class _BioEditField extends StatelessWidget {
  const _BioEditField({
    required this.label,
    required this.controller,
    this.hint = '',
    this.maxLines = 1,
    this.maxLength,
    this.prefixEmoji,
  });

  final String label;
  final TextEditingController controller;
  final String hint;
  final int maxLines;
  final int? maxLength;
  final String? prefixEmoji;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 10,
            color: AppColors.textMuted,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (prefixEmoji != null)
                Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Text(prefixEmoji!,
                      style: const TextStyle(fontSize: 14)),
                ),
              Expanded(
                child: TextField(
                  controller: controller,
                  maxLines: maxLines,
                  maxLength: maxLength,
                  style: GoogleFonts.inter(
                      fontSize: 13, color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: hint,
                    hintStyle: GoogleFonts.inter(
                        fontSize: 13, color: AppColors.textMuted),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: prefixEmoji != null ? 8 : 12,
                      vertical: 10,
                    ),
                    counterStyle: GoogleFonts.jetBrainsMono(
                        fontSize: 9, color: AppColors.textMuted),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InterestTagEditable extends StatelessWidget {
  const _InterestTagEditable(
      {required this.label, required this.onRemove});
  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 4, 6, 4),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '#$label',
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            child: Icon(
              Icons.close_rounded,
              size: 13,
              color: AppColors.primary.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Edit profile sheet
// ---------------------------------------------------------------------------

class _EditProfileSheet extends StatefulWidget {
  const _EditProfileSheet();

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  late final TextEditingController _nameCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: _profileName);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final keyboardPad = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: EdgeInsets.fromLTRB(20, 20, 20, bottomPad + keyboardPad + 20),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Sheet handle
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Edit Profile',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 20),
          _EditField(label: 'Name', controller: _nameCtrl),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: () {
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Profile updated!',
                    style: GoogleFonts.inter(color: Colors.white),
                  ),
                  backgroundColor: AppColors.primary,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              );
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: Text(
                  'Save changes',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
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

class _EditField extends StatelessWidget {
  const _EditField({required this.label, required this.controller});

  final String label;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 10,
            color: AppColors.textMuted,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: TextField(
            controller: controller,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: AppColors.textPrimary,
            ),
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// TAB 1 — Everyone posts grid
// ---------------------------------------------------------------------------

class _EveryoneTab extends StatefulWidget {
  const _EveryoneTab();

  @override
  State<_EveryoneTab> createState() => _EveryoneTabState();
}

class _EveryoneTabState extends State<_EveryoneTab> {
  late final StreamSubscription<List<LocalPost>> _sub;
  List<LocalPost> _myPosts = [];

  @override
  void initState() {
    super.initState();
    _myPosts = PostService.instance.everyonePosts;
    _sub = PostService.instance.myPostsStream.listen((all) {
      if (mounted) setState(() => _myPosts = all.where((p) => p.isEveryone).toList());
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final realCount = _myPosts.length;
    final mockCount = _everyonePosts.length;

    return GridView.builder(
      padding: EdgeInsets.fromLTRB(12, 12, 12, bottomPad + 80),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
        childAspectRatio: 0.88,
      ),
      itemCount: realCount + mockCount,
      itemBuilder: (context, i) {
        if (i < realCount) return _UserPostThumbnail(post: _myPosts[i]);
        return _PostThumbnail(post: _everyonePosts[i - realCount]);
      },
    );
  }
}

class _UserPostThumbnail extends StatelessWidget {
  const _UserPostThumbnail({required this.post});

  final LocalPost post;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Stack(
        fit: StackFit.expand,
        children: [
          post.photoPath != null
              ? Image.file(File(post.photoPath!), fit: BoxFit.cover)
              : Container(color: const Color(0xFF1A1A28)),

          // "new" badge
          Positioned(
            top: 5, right: 5,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                gradient: AppColors.instaGradient,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'new',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 8, color: Colors.white, fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),

          // Caption scrim
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(6, 12, 6, 6),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black.withValues(alpha: 0.75), Colors.transparent],
                ),
              ),
              child: Text(
                post.caption.isNotEmpty ? post.caption : 'just now',
                style: GoogleFonts.inter(
                  fontSize: 9, color: Colors.white, fontWeight: FontWeight.w500,
                ),
                maxLines: 1, overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PostThumbnail extends StatelessWidget {
  const _PostThumbnail({required this.post});

  final _EveryonePost post;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => _PostDetailView(post: post),
        ),
      ),
      onLongPress: () => _showOptions(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: post.color),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(6, 12, 6, 6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.75),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Text(
                  post.label,
                  style: GoogleFonts.inter(
                    fontSize: 9,
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showOptions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _OptionTile(icon: Icons.delete_outline, label: 'Delete post', color: AppColors.errorRed, onTap: () => Navigator.pop(context)),
            _OptionTile(icon: Icons.flag_outlined, label: 'Report', color: AppColors.textMuted, onTap: () => Navigator.pop(context)),
            _OptionTile(icon: Icons.share_outlined, label: 'Share', color: AppColors.textPrimary, onTap: () => Navigator.pop(context)),
          ],
        ),
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 12),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 14,
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PostDetailView extends StatelessWidget {
  const _PostDetailView({required this.post});

  final _EveryonePost post;

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: 1.0,
              child: Container(color: post.color),
            ),
          ),
          Positioned(
            top: topPad + 10,
            left: 14,
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: Colors.white,
                  size: 16,
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                post.label,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
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
// TAB 2 — Memories calendar
// ---------------------------------------------------------------------------

class _MemoriesTab extends StatefulWidget {
  const _MemoriesTab();

  @override
  State<_MemoriesTab> createState() => _MemoriesTabState();
}

// Moments = memories/collages AND bucket contributions, together in one
// scrollable tab. Chosen layout: two GROUPED sections (Memories, then
// Buckets) rather than one interleaved chronological grid — a memory is a
// single photo/collage cell, a bucket is a named container you contributed
// *to* (title + open/closed status, not a photo itself), so forcing both
// into one homogeneous grid would mix two visually different card types in
// the same cells. Grouped sections keep each its own natural treatment
// while still living under one "Moments" tab, satisfying "shown together
// in one grid/section" as one section per source rather than one grid.
class _MemoriesTabState extends State<_MemoriesTab> {
  late Future<List<Map<String, dynamic>>> _memoriesFuture;
  late Future<List<Map<String, dynamic>>> _bucketsFuture;

  @override
  void initState() {
    super.initState();
    _memoriesFuture = MemoryService.instance.myMemories();
    _bucketsFuture = BucketService.instance.fetchMyContributedBuckets();
  }

  void _reloadMemories() =>
      setState(() => _memoriesFuture = MemoryService.instance.myMemories());

  void _reloadBuckets() => setState(() =>
      _bucketsFuture = BucketService.instance.fetchMyContributedBuckets());

  void _openCreateBucket() {
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (_) => const BucketCreateScreen(),
          ),
        )
        .then((_) => _reloadBuckets());
  }

  void _openBucket(String bucketId) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BucketViewScreen(bucketId: bucketId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return ListView(
      padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPad + 80),
      children: [
        _CreationButtons(onCreated: _reloadMemories),
        const SizedBox(height: 20),

        _MomentsSectionLabel('MEMORIES'),
        const SizedBox(height: 10),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _memoriesFuture,
          builder: (context, snap) {
            final isLoading = snap.connectionState == ConnectionState.waiting;
            final memories = snap.data ?? [];

            if (isLoading) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: CircularProgressIndicator(
                      color: Color(0xFF2563EB), strokeWidth: 2),
                ),
              );
            }
            if (snap.hasError) {
              return _TabMessageState(
                icon: Icons.error_outline_rounded,
                message: "Couldn't load your memories.",
                actionLabel: 'Retry',
                onAction: _reloadMemories,
              );
            }
            if (memories.isEmpty) {
              return const _TabMessageState(
                icon: Icons.auto_awesome_mosaic_outlined,
                message: 'No moments yet.\nCreate your first collage!',
              );
            }
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 9 / 16,
              ),
              itemCount: memories.length,
              itemBuilder: (_, i) {
                final m = memories[i];
                final layout = layoutById(
                    m['layout_id'] as String? ?? 'triple_horizontal');
                final imgs = (m['photos'] as List? ?? [])
                    .map<ImageProvider?>((path) => NetworkImage(
                        MemoryService.instance.publicUrl(path.toString())))
                    .toList();
                final isDraft = (m['is_draft'] as bool?) ?? true;

                return GestureDetector(
                  onLongPress: () =>
                      _showMemoryOptions(m['id'] as String, isDraft),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: MemoryCanvas(layout: layout, images: imgs),
                      ),
                      if (isDraft)
                        Positioned(
                          top: 8,
                          left: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.65),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text('Draft',
                                style: GoogleFonts.jetBrainsMono(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ),
                    ],
                  ),
                );
              },
            );
          },
        ),

        const SizedBox(height: 28),

        _MomentsSectionLabel('BUCKETS'),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: _openCreateBucket,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 13),
            decoration: BoxDecoration(
              color: AppColors.coral,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.add_rounded, size: 18, color: Colors.white),
                const SizedBox(width: 6),
                Text(
                  'New Bucket',
                  style: GoogleFonts.inter(
                      fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _bucketsFuture,
          builder: (context, snap) {
            final isLoading = snap.connectionState == ConnectionState.waiting;
            final buckets = snap.data ?? [];

            if (isLoading) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.coral, strokeWidth: 2),
                ),
              );
            }
            if (snap.hasError) {
              return _TabMessageState(
                icon: Icons.error_outline_rounded,
                message: "Couldn't load your buckets.",
                actionLabel: 'Retry',
                onAction: _reloadBuckets,
              );
            }
            if (buckets.isEmpty) {
              return const _TabMessageState(
                icon: Icons.inventory_2_outlined,
                message: "You haven't contributed to a bucket yet.",
              );
            }
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 1.3,
              ),
              itemCount: buckets.length,
              itemBuilder: (_, i) => _BucketCard(
                bucket: buckets[i],
                onTap: () => _openBucket(buckets[i]['id'] as String),
              ),
            );
          },
        ),
      ],
    );
  }

  void _showMemoryOptions(String memoryId, bool isDraft) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF111118),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            if (isDraft)
              ListTile(
                leading: const Icon(Icons.send_rounded, color: Color(0xFF2563EB)),
                title: Text('Post now',
                    style: GoogleFonts.inter(color: Colors.white)),
                onTap: () async {
                  Navigator.pop(context);
                  await MemoryService.instance.postDraft(memoryId);
                  _reloadMemories();
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded,
                  color: Colors.redAccent),
              title: Text('Delete',
                  style: GoogleFonts.inter(color: Colors.redAccent)),
              onTap: () async {
                Navigator.pop(context);
                await MemoryService.instance.deleteMemory(memoryId);
                _reloadMemories();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// TAB 3 — Private (own anonymous posts, own profile only)
// ---------------------------------------------------------------------------
//
// Reads through PostService.myAnonymousPosts(), which queries the
// posts_feed view filtered to this user's own id — see that method's doc
// comment for why that filter is safe even if this tab were ever reached
// from a "view someone else's profile" context (no such context exists in
// this app today; ProfileScreen has no userId param, it is always "my
// profile"). If a view-other-profile screen gets built later, it must not
// render this tab for a non-self profile — that's a UI-level guard this
// code can't provide on its own, the real enforcement is server-side.

class _PrivateTab extends StatefulWidget {
  const _PrivateTab();

  @override
  State<_PrivateTab> createState() => _PrivateTabState();
}

class _PrivateTabState extends State<_PrivateTab> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = PostService.instance.myAnonymousPosts();
  }

  void _reload() =>
      setState(() => _future = PostService.instance.myAnonymousPosts());

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snap) {
        final isLoading = snap.connectionState == ConnectionState.waiting;

        if (isLoading) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2),
          );
        }
        if (snap.hasError) {
          return _TabMessageState(
            icon: Icons.error_outline_rounded,
            message: "Couldn't load your private posts.",
            actionLabel: 'Retry',
            onAction: _reload,
          );
        }

        final posts = snap.data ?? [];
        if (posts.isEmpty) {
          return const _TabMessageState(
            icon: Icons.lock_outline_rounded,
            message: 'No anonymous posts yet.\nOnly you can see this tab.',
          );
        }

        return GridView.builder(
          padding: EdgeInsets.fromLTRB(12, 12, 12, bottomPad + 80),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 4,
            mainAxisSpacing: 4,
            childAspectRatio: 0.88,
          ),
          itemCount: posts.length,
          itemBuilder: (context, i) => _PrivatePostThumbnail(post: posts[i]),
        );
      },
    );
  }
}

class _PrivatePostThumbnail extends StatelessWidget {
  const _PrivatePostThumbnail({required this.post});
  final Map<String, dynamic> post;

  @override
  Widget build(BuildContext context) {
    final imageUrl = post['image_url'] as String?;
    final content = post['content'] as String?;

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        color: AppColors.cardSurface,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (imageUrl != null)
              CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                placeholder: (_, _) => Container(color: AppColors.cardSurface),
                errorWidget: (_, _, _) => const Icon(
                    Icons.broken_image_outlined, color: AppColors.textMuted, size: 18),
              )
            else
              // Anonymous posts made via the composer today don't upload a
              // photo (StorageService.uploadPostImage is never called from
              // ComposerScreen._send — see PART 1/2 summary), so a real
              // fetched row commonly has no image_url. Fall back to text.
              Padding(
                padding: const EdgeInsets.all(8),
                child: Center(
                  child: Text(
                    (content == null || content.isEmpty) ? '🔒' : content,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(fontSize: 10, color: AppColors.textPrimary),
                  ),
                ),
              ),
            Positioned(
              top: 5, right: 5,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.lock_rounded, size: 9, color: Colors.white70),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// TAB 4 — Groups (community-scoped photos from communities the user is in)
// ---------------------------------------------------------------------------

class _GroupsTab extends StatefulWidget {
  const _GroupsTab();

  @override
  State<_GroupsTab> createState() => _GroupsTabState();
}

class _GroupsTabState extends State<_GroupsTab> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = CommunityPhotosService.instance.myGroupPhotos();
  }

  void _reload() =>
      setState(() => _future = CommunityPhotosService.instance.myGroupPhotos());

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snap) {
        final isLoading = snap.connectionState == ConnectionState.waiting;

        if (isLoading) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2),
          );
        }
        if (snap.hasError) {
          return _TabMessageState(
            icon: Icons.error_outline_rounded,
            message: "Couldn't load group photos.",
            actionLabel: 'Retry',
            onAction: _reload,
          );
        }

        final photos = snap.data ?? [];
        if (photos.isEmpty) {
          return const _TabMessageState(
            icon: Icons.groups_outlined,
            message: 'No group photos yet.\nJoin a community to see its posts here.',
          );
        }

        return GridView.builder(
          padding: EdgeInsets.fromLTRB(12, 12, 12, bottomPad + 80),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 4,
            mainAxisSpacing: 4,
            childAspectRatio: 0.88,
          ),
          itemCount: photos.length,
          itemBuilder: (context, i) {
            final imageUrl = photos[i]['image_url'] as String?;
            return ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: imageUrl == null
                  ? Container(color: AppColors.cardSurface)
                  : CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, _) => Container(color: AppColors.cardSurface),
                      errorWidget: (_, _, _) => Container(
                        color: AppColors.cardSurface,
                        child: const Icon(Icons.broken_image_outlined,
                            color: AppColors.textMuted, size: 18),
                      ),
                    ),
            );
          },
        );
      },
    );
  }
}

class _BucketCard extends StatelessWidget {
  const _BucketCard({required this.bucket, required this.onTap});
  final Map<String, dynamic> bucket;
  final VoidCallback onTap;

  bool get _isExpired {
    final raw = bucket['expires_at'] as String?;
    if (raw == null) return false;
    final expiresAt = DateTime.tryParse(raw);
    return expiresAt != null && expiresAt.isBefore(DateTime.now().toUtc());
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Icon(Icons.inventory_2_rounded, size: 20, color: AppColors.coral),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  bucket['title'] as String? ?? 'Untitled bucket',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                      fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 3),
                Text(
                  _isExpired ? 'Closed' : 'Active',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 9,
                    color: _isExpired ? AppColors.textMuted : AppColors.coral,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Small section label — separates Memories from Buckets within Moments.
// ---------------------------------------------------------------------------

class _MomentsSectionLabel extends StatelessWidget {
  const _MomentsSectionLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: GoogleFonts.jetBrainsMono(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        color: AppColors.textMuted,
        letterSpacing: 0.6,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared loading/empty/error state for the new tabs
// ---------------------------------------------------------------------------

class _TabMessageState extends StatelessWidget {
  const _TabMessageState({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.textMuted, size: 32),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 13, color: AppColors.textMuted, height: 1.5),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 14),
            GestureDetector(
              onTap: onAction,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  actionLabel!,
                  style: GoogleFonts.inter(
                      fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// PIN FEATURE — data models, dummy data, widgets
// ---------------------------------------------------------------------------

class _ViewHistoryEntry {
  const _ViewHistoryEntry({
    required this.postName,
    required this.duration,
    required this.timestamp,
    required this.isAnon,
  });
  final String postName;
  final String duration;
  final String timestamp;
  final bool isAnon;
}

class _PinnedPerson {
  _PinnedPerson({
    required this.username,
    required this.displayName,
    required this.avatarColor,
    required this.avatarInitial,
    required this.totalSeconds,
    required this.lingeredPost,
    required this.lingeredDuration,
    required this.anonPostsViewed,
    required this.everyonePostsViewed,
    required this.lastActivityLabel,
    required this.viewHistory,
  });
  final String username;
  final String displayName;
  final Color avatarColor;
  final String avatarInitial;
  final int totalSeconds;
  final String lingeredPost;
  final String lingeredDuration;
  final int anonPostsViewed;
  final int everyonePostsViewed;
  final String lastActivityLabel;
  final List<_ViewHistoryEntry> viewHistory;
}

String _fmtSec(int s) {
  if (s < 60) return '${s}s';
  final m = s ~/ 60;
  final r = s % 60;
  return r == 0 ? '${m}m' : '${m}m ${r}s';
}

final _pinnedPeople = <_PinnedPerson>[
  _PinnedPerson(
    username: 'alex_xyz',
    displayName: 'Alex',
    avatarColor: const Color(0xFF2A3050),
    avatarInitial: 'A',
    totalSeconds: 823,
    lingeredPost: 'Fest collage',
    lingeredDuration: '3m 24s',
    anonPostsViewed: 2,
    everyonePostsViewed: 1,
    lastActivityLabel: '2h ago',
    viewHistory: const [
      _ViewHistoryEntry(postName: 'Fest collage', duration: '3m 24s', timestamp: '2h ago', isAnon: false),
      _ViewHistoryEntry(postName: 'Late night thoughts', duration: '1m 12s', timestamp: '5h ago', isAnon: true),
      _ViewHistoryEntry(postName: 'Campus wandering', duration: '48s', timestamp: '1d ago', isAnon: true),
      _ViewHistoryEntry(postName: 'Coffee moment', duration: '39s', timestamp: '2d ago', isAnon: false),
    ],
  ),
  _PinnedPerson(
    username: 'jordan_23',
    displayName: 'Jordan',
    avatarColor: const Color(0xFF1E2A28),
    avatarInitial: 'J',
    totalSeconds: 456,
    lingeredPost: 'Coffee moment',
    lingeredDuration: '1m 45s',
    anonPostsViewed: 1,
    everyonePostsViewed: 2,
    lastActivityLabel: '1h ago',
    viewHistory: const [
      _ViewHistoryEntry(postName: 'Coffee moment', duration: '1m 45s', timestamp: '1h ago', isAnon: false),
      _ViewHistoryEntry(postName: 'Fest collage', duration: '1m 08s', timestamp: '3h ago', isAnon: false),
      _ViewHistoryEntry(postName: 'Midnight spiral', duration: '1m 03s', timestamp: '6h ago', isAnon: true),
    ],
  ),
  _PinnedPerson(
    username: 'study_bug',
    displayName: 'StudyBug',
    avatarColor: const Color(0xFF2A1E2A),
    avatarInitial: 'S',
    totalSeconds: 234,
    lingeredPost: 'Library study',
    lingeredDuration: '2m 10s',
    anonPostsViewed: 3,
    everyonePostsViewed: 0,
    lastActivityLabel: '45m ago',
    viewHistory: const [
      _ViewHistoryEntry(postName: 'Library study', duration: '2m 10s', timestamp: '45m ago', isAnon: false),
      _ViewHistoryEntry(postName: 'Exam anxiety', duration: '54s', timestamp: '2h ago', isAnon: true),
      _ViewHistoryEntry(postName: 'Overheard at canteen', duration: '30s', timestamp: '4h ago', isAnon: true),
      _ViewHistoryEntry(postName: 'Semester feels', duration: '20s', timestamp: '1d ago', isAnon: true),
    ],
  ),
  _PinnedPerson(
    username: 'sunset_chaser',
    displayName: 'Sunset',
    avatarColor: const Color(0xFF382818),
    avatarInitial: 'S',
    totalSeconds: 567,
    lingeredPost: 'Sunset at campus',
    lingeredDuration: '4m 02s',
    anonPostsViewed: 1,
    everyonePostsViewed: 2,
    lastActivityLabel: '3h ago',
    viewHistory: const [
      _ViewHistoryEntry(postName: 'Sunset at campus', duration: '4m 02s', timestamp: '3h ago', isAnon: false),
      _ViewHistoryEntry(postName: 'Friend group', duration: '1m 15s', timestamp: '5h ago', isAnon: false),
      _ViewHistoryEntry(postName: 'Night sky thoughts', duration: '1m 10s', timestamp: '8h ago', isAnon: true),
    ],
  ),
];

const _demographicSignals = <({String label, IconData icon})>[
  (label: 'An EC girl viewed your profile', icon: Icons.visibility_outlined),
  (label: 'Someone from CSE viewed your posts', icon: Icons.school_outlined),
  (label: '3 people from 3rd year lingered on your anon post', icon: Icons.people_outline),
];

// ---------------------------------------------------------------------------
// TAB 4 — Pinned dashboard
// ---------------------------------------------------------------------------

class _PinnedTab extends StatefulWidget {
  const _PinnedTab();

  @override
  State<_PinnedTab> createState() => _PinnedTabState();
}

class _PinnedTabState extends State<_PinnedTab> {
  late final List<_PinnedPerson> _pinned;

  @override
  void initState() {
    super.initState();
    _pinned = List.from(_pinnedPeople);
  }

  void _unpin(int index) {
    setState(() => _pinned.removeAt(index));
  }

  void _openDetail(BuildContext context, _PinnedPerson person) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PinnedDetailSheet(person: person),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return ListView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, bottomPad + 80),
      children: [
        // Header row
        Row(
          children: [
            Text(
              'People you\'re watching',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
              ),
              child: Text(
                '${_pinned.length}/6',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Silent. They\'ll never know.',
          style: GoogleFonts.jetBrainsMono(
            fontSize: 10,
            color: AppColors.textMuted,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 14),

        // Pinned person cards
        for (int i = 0; i < _pinned.length; i++) ...[
          _PinnedPersonCard(
            person: _pinned[i],
            onUnpin: () => _unpin(i),
            onTap: () => _openDetail(context, _pinned[i]),
          ),
          const SizedBox(height: 10),
        ],

        if (_pinned.isEmpty)
          const _EmptyPinSlot(
            message: 'No one pinned yet.\nGo to a profile and tap Pin.',
          ),

        if (_pinned.isNotEmpty && _pinned.length < 6) ...[
          const SizedBox(height: 4),
          _EmptyPinHint(remaining: 6 - _pinned.length),
        ],

        // Demographic signals
        const SizedBox(height: 24),
        const _DemographicSignalsSection(),
      ],
    );
  }
}

class _EmptyPinSlot extends StatelessWidget {
  const _EmptyPinSlot({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          const Icon(Icons.push_pin_outlined, size: 28, color: AppColors.textMuted),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: AppColors.textMuted,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyPinHint extends StatelessWidget {
  const _EmptyPinHint({required this.remaining});
  final int remaining;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Text(
        '$remaining slot${remaining > 1 ? "s" : ""} available — visit a profile to pin',
        style: GoogleFonts.jetBrainsMono(
          fontSize: 10,
          color: AppColors.textMuted,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pinned person card
// ---------------------------------------------------------------------------

class _PinnedPersonCard extends StatelessWidget {
  const _PinnedPersonCard({
    required this.person,
    required this.onUnpin,
    required this.onTap,
  });

  final _PinnedPerson person;
  final VoidCallback onUnpin;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: avatar + name + last activity + unpin
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: person.avatarColor,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.35),
                      width: 1.5,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      person.avatarInitial,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      person.displayName,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      '@${person.username}',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.circle, size: 6, color: Color(0xFF4CAF50)),
                      const SizedBox(width: 4),
                      Text(
                        person.lastActivityLabel,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 9,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: onUnpin,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: AppColors.errorRed.withValues(alpha: 0.10),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.errorRed.withValues(alpha: 0.25),
                      ),
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      size: 13,
                      color: AppColors.errorRed,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(height: 0.5, color: AppColors.border),
            const SizedBox(height: 12),
            // Stats pills
            Row(
              children: [
                _StatPill(
                  icon: Icons.timer_outlined,
                  label: _fmtSec(person.totalSeconds),
                  sublabel: 'total',
                  color: AppColors.primary,
                ),
                const SizedBox(width: 8),
                _StatPill(
                  icon: Icons.lock_outline,
                  label: '${person.anonPostsViewed}',
                  sublabel: 'anon',
                  color: AppColors.secondary,
                ),
                const SizedBox(width: 8),
                _StatPill(
                  icon: Icons.people_outline,
                  label: '${person.everyonePostsViewed}',
                  sublabel: 'public',
                  color: const Color(0xFF9B8EC4),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Lingered post
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.15),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.bookmark_border_rounded,
                    size: 12,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Lingered on',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 9,
                      color: AppColors.primary,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      person.lingeredPost,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    person.lingeredDuration,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Spacer(),
                Text(
                  'tap for full history',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 9,
                    color: AppColors.textMuted.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(width: 3),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 12,
                  color: AppColors.textMuted.withValues(alpha: 0.6),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String sublabel;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.18)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 11, color: color),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              sublabel,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 8,
                color: color.withValues(alpha: 0.70),
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pinned detail sheet
// ---------------------------------------------------------------------------

class _PinnedDetailSheet extends StatelessWidget {
  const _PinnedDetailSheet({required this.person});

  final _PinnedPerson person;

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: person.avatarColor,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.4),
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      person.avatarInitial,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      person.displayName,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      '@${person.username} · ${_fmtSec(person.totalSeconds)} total',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(height: 0.5, color: AppColors.border),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Text(
                  'View history',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const Spacer(),
                Text(
                  '${person.viewHistory.length} interactions',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 300),
            child: ListView.separated(
              padding: EdgeInsets.fromLTRB(20, 0, 20, bottomPad + 24),
              shrinkWrap: true,
              itemCount: person.viewHistory.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (_, i) => _HistoryEntryRow(entry: person.viewHistory[i]),
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryEntryRow extends StatelessWidget {
  const _HistoryEntryRow({required this.entry});

  final _ViewHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final typeColor = entry.isAnon ? AppColors.secondary : const Color(0xFF9B8EC4);
    final typeLabel = entry.isAnon ? 'anon' : 'public';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: typeColor.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              typeLabel,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 9,
                color: typeColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              entry.postName,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          Text(
            entry.duration,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            entry.timestamp,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 9,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Demographic signals section
// ---------------------------------------------------------------------------

class _DemographicSignalsSection extends StatelessWidget {
  const _DemographicSignalsSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Anonymous traffic',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.secondary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.secondary.withValues(alpha: 0.20)),
              ),
              child: Text(
                'pool ≥15',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 9,
                  color: AppColors.secondary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'People not pinned — identity hidden.',
          style: GoogleFonts.jetBrainsMono(
            fontSize: 10,
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(height: 12),
        for (final signal in _demographicSignals) ...[
          _DemographicSignalTile(label: signal.label, icon: signal.icon),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _DemographicSignalTile extends StatelessWidget {
  const _DemographicSignalTile({
    required this.label,
    required this.icon,
  });

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppColors.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: AppColors.textPrimary,
                height: 1.4,
              ),
            ),
          ),
          const Icon(Icons.lock_outline, size: 12, color: AppColors.textMuted),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// VIEWERS TAB — demographic visitor signals with pool-gating
// ---------------------------------------------------------------------------

const int _minPool = 15;

class _ViewerSignal {
  const _ViewerSignal({
    required this.demographic,
    required this.poolCount,
    required this.lastViewedAgo,
    required this.icon,
    required this.mostViewedPost,
    required this.mostViewedPostCount,
    required this.postBreakdown,
  });

  final String demographic;
  final int poolCount;
  final String lastViewedAgo;
  final IconData icon;
  final String mostViewedPost;
  final int mostViewedPostCount;
  final List<({String post, int count})> postBreakdown;

  bool get isVisible => poolCount >= _minPool;
}

class _PinnedViewerNotif {
  const _PinnedViewerNotif({
    required this.username,
    required this.avatarColor,
    required this.avatarInitial,
    required this.viewedWhat,
    required this.timeAgo,
  });

  final String username;
  final Color avatarColor;
  final String avatarInitial;
  final String viewedWhat;
  final String timeAgo;
}

const _viewerSignals = <_ViewerSignal>[
  _ViewerSignal(
    demographic: 'EC girls',
    poolCount: 56,
    lastViewedAgo: '2h ago',
    icon: Icons.person_outline,
    mostViewedPost: 'Fest collage',
    mostViewedPostCount: 23,
    postBreakdown: [
      (post: 'Fest collage', count: 23),
      (post: 'Library study', count: 19),
      (post: 'Coffee moment', count: 14),
    ],
  ),
  _ViewerSignal(
    demographic: 'CSE students',
    poolCount: 34,
    lastViewedAgo: '1h ago',
    icon: Icons.school_outlined,
    mostViewedPost: 'Library study',
    mostViewedPostCount: 18,
    postBreakdown: [
      (post: 'Library study', count: 18),
      (post: 'Fest collage', count: 12),
      (post: 'Late night snack', count: 4),
    ],
  ),
  _ViewerSignal(
    demographic: '3rd year students',
    poolCount: 71,
    lastViewedAgo: '45m ago',
    icon: Icons.people_outline,
    mostViewedPost: 'Fest collage',
    mostViewedPostCount: 31,
    postBreakdown: [
      (post: 'Fest collage', count: 31),
      (post: 'Coffee moment', count: 22),
      (post: 'Campus sunset', count: 18),
    ],
  ),
  _ViewerSignal(
    demographic: 'RV College students',
    poolCount: 22,
    lastViewedAgo: '3h ago',
    icon: Icons.location_city_outlined,
    mostViewedPost: 'Coffee moment',
    mostViewedPostCount: 12,
    postBreakdown: [
      (post: 'Coffee moment', count: 12),
      (post: 'Fest collage', count: 8),
      (post: 'Library study', count: 2),
    ],
  ),
  // Suppressed — pool < 15
  _ViewerSignal(
    demographic: 'ECE girls',
    poolCount: 8,
    lastViewedAgo: '6h ago',
    icon: Icons.person_outline,
    mostViewedPost: 'Library study',
    mostViewedPostCount: 4,
    postBreakdown: [],
  ),
  _ViewerSignal(
    demographic: 'CS+AI students',
    poolCount: 11,
    lastViewedAgo: '4h ago',
    icon: Icons.school_outlined,
    mostViewedPost: 'Campus sunset',
    mostViewedPostCount: 6,
    postBreakdown: [],
  ),
];

const _pinnedViewerNotifs = <_PinnedViewerNotif>[
  _PinnedViewerNotif(
    username: 'alex_xyz',
    avatarColor: Color(0xFF2A3050),
    avatarInitial: 'A',
    viewedWhat: 'Fest collage',
    timeAgo: '2h ago',
  ),
  _PinnedViewerNotif(
    username: 'study_bug',
    avatarColor: Color(0xFF2A1E2A),
    avatarInitial: 'S',
    viewedWhat: 'your profile',
    timeAgo: '45m ago',
  ),
];

// ---------------------------------------------------------------------------
// TAB 5 — Viewers
// ---------------------------------------------------------------------------

class _ViewersTab extends StatefulWidget {
  const _ViewersTab();

  @override
  State<_ViewersTab> createState() => _ViewersTabState();
}

class _ViewersTabState extends State<_ViewersTab> {
  bool _refreshing = false;

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (mounted) setState(() => _refreshing = false);
  }

  void _openBreakdown(BuildContext context, _ViewerSignal signal) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SignalBreakdownSheet(signal: signal),
    );
  }

  void _openPinnedDetail(BuildContext context, _PinnedViewerNotif notif) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _PinnedViewerSheet(notif: notif),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final visible = _viewerSignals.where((s) => s.isVisible).toList();
    final suppressed = _viewerSignals.where((s) => !s.isVisible).toList();

    return RefreshIndicator(
      onRefresh: _refresh,
      color: AppColors.primary,
      backgroundColor: AppColors.cardSurface,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16, 16, 16, bottomPad + 80),
        children: [
          // Header
          Row(
            children: [
              Text(
                'Who\'s viewing you',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              if (_refreshing)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primary,
                  ),
                )
              else
                GestureDetector(
                  onTap: _refresh,
                  child: const Icon(
                    Icons.refresh_rounded,
                    size: 16,
                    color: AppColors.textMuted,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Pool ≥$_minPool required to show a signal.',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 16),

          // Pinned person notifications
          if (_pinnedViewerNotifs.isNotEmpty) ...[
            _SectionLabel(
              label: 'Pinned — real names',
              badge: '${_pinnedViewerNotifs.length}',
              badgeColor: AppColors.primary,
            ),
            const SizedBox(height: 10),
            for (final notif in _pinnedViewerNotifs) ...[
              _PinnedViewerCard(
                notif: notif,
                onTap: () => _openPinnedDetail(context, notif),
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 20),
          ],

          // Demographic signals (visible only)
          _SectionLabel(
            label: 'Anonymous traffic',
            badge: '${visible.length} signal${visible.length != 1 ? "s" : ""}',
            badgeColor: AppColors.secondary,
          ),
          const SizedBox(height: 10),
          if (visible.isEmpty)
            _EmptySignals()
          else
            for (final signal in visible) ...[
              _DemographicSignalCard(
                signal: signal,
                onTap: () => _openBreakdown(context, signal),
              ),
              const SizedBox(height: 10),
            ],

          // Suppressed signals
          if (suppressed.isNotEmpty) ...[
            const SizedBox(height: 20),
            _SectionLabel(
              label: 'Privacy shield',
              badge: '${suppressed.length} hidden',
              badgeColor: AppColors.textMuted,
            ),
            const SizedBox(height: 6),
            Text(
              'These groups have < $_minPool viewers — identity protected.',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 10,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 10),
            for (final signal in suppressed) ...[
              _SuppressedSignalCard(signal: signal),
              const SizedBox(height: 8),
            ],
          ],
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.label,
    required this.badge,
    required this.badgeColor,
  });

  final String label;
  final String badge;
  final Color badgeColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: AppColors.textMuted,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: badgeColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: badgeColor.withValues(alpha: 0.25)),
          ),
          child: Text(
            badge,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 9,
              color: badgeColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptySignals extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          const Icon(Icons.visibility_off_outlined, size: 24, color: AppColors.textMuted),
          const SizedBox(height: 8),
          Text(
            'No signals yet — pool threshold not met.',
            style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Demographic signal card (pool-gated, visible)
// ---------------------------------------------------------------------------

class _DemographicSignalCard extends StatelessWidget {
  const _DemographicSignalCard({
    required this.signal,
    required this.onTap,
  });

  final _ViewerSignal signal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.secondary.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.secondary.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Icon(signal.icon, size: 16, color: AppColors.secondary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Text(
                            '${signal.poolCount}',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                              height: 1.0,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            signal.demographic,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        'viewed your content · ${signal.lastViewedAgo}',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 9,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: AppColors.textMuted,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(height: 0.5, color: AppColors.border),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(
                  Icons.bookmark_border_rounded,
                  size: 11,
                  color: AppColors.secondary,
                ),
                const SizedBox(width: 5),
                Text(
                  'Most viewed: ',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 9,
                    color: AppColors.textMuted,
                  ),
                ),
                Expanded(
                  child: Text(
                    signal.mostViewedPost,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${signal.mostViewedPostCount} views',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 9,
                    color: AppColors.secondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Pool indicator
            Row(
              children: [
                const Icon(Icons.shield_outlined, size: 11, color: AppColors.secondary),
                const SizedBox(width: 5),
                Text(
                  'Pool: ${signal.poolCount} ≥ $_minPool ✓',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 9,
                    color: AppColors.secondary,
                  ),
                ),
                const Spacer(),
                Text(
                  'tap for breakdown',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 9,
                    color: AppColors.textMuted.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Suppressed signal card (pool < 15)
// ---------------------------------------------------------------------------

class _SuppressedSignalCard extends StatelessWidget {
  const _SuppressedSignalCard({required this.signal});

  final _ViewerSignal signal;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.cardSurface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.lock_outline,
            size: 14,
            color: AppColors.textMuted,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '░░░░░░░░░ • suppressed',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    color: AppColors.textMuted.withValues(alpha: 0.6),
                    letterSpacing: 0.2,
                  ),
                ),
                Text(
                  'Pool: ${signal.poolCount} < $_minPool — identity protected',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 9,
                    color: AppColors.textMuted.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.textMuted.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              '${signal.poolCount}/$_minPool',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 9,
                color: AppColors.textMuted.withValues(alpha: 0.6),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pinned viewer card
// ---------------------------------------------------------------------------

class _PinnedViewerCard extends StatelessWidget {
  const _PinnedViewerCard({required this.notif, required this.onTap});

  final _PinnedViewerNotif notif;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: notif.avatarColor,
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.50),
                  width: 1.5,
                ),
              ),
              child: Center(
                child: Text(
                  notif.avatarInitial,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(
                        notif.username,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'pinned',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 8,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    'Viewed ${notif.viewedWhat}',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              notif.timeAgo,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 9,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(width: 6),
            const Icon(
              Icons.chevron_right_rounded,
              size: 14,
              color: AppColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Signal breakdown sheet
// ---------------------------------------------------------------------------

class _SignalBreakdownSheet extends StatelessWidget {
  const _SignalBreakdownSheet({required this.signal});

  final _ViewerSignal signal;

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.secondary.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.secondary.withValues(alpha: 0.30),
                    ),
                  ),
                  child: Icon(signal.icon, size: 20, color: AppColors.secondary),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${signal.poolCount} ${signal.demographic}',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      'last viewed ${signal.lastViewedAgo}',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(height: 0.5, color: AppColors.border),
          ),
          const SizedBox(height: 14),
          // Stats row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                _StatChip(label: 'pool count', value: '${signal.poolCount}'),
                const SizedBox(width: 8),
                _StatChip(label: 'threshold', value: '≥$_minPool ✓'),
                const SizedBox(width: 8),
                _StatChip(label: 'last view', value: signal.lastViewedAgo),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Post breakdown
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Text(
                  'Views by post',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          for (final item in signal.postBreakdown)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: _PostViewRow(
                post: item.post,
                count: item.count,
                maxCount: signal.postBreakdown
                    .map((e) => e.count)
                    .reduce((a, b) => a > b ? a : b),
              ),
            ),
          SizedBox(height: bottomPad + 24),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 8,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PostViewRow extends StatelessWidget {
  const _PostViewRow({
    required this.post,
    required this.count,
    required this.maxCount,
  });

  final String post;
  final int count;
  final int maxCount;

  @override
  Widget build(BuildContext context) {
    final barFrac = maxCount > 0 ? count / maxCount : 0.0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  post,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Text(
                '$count views',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.secondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: barFrac,
              backgroundColor: AppColors.secondary.withValues(alpha: 0.12),
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.secondary),
              minHeight: 3,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pinned viewer detail sheet
// ---------------------------------------------------------------------------

class _PinnedViewerSheet extends StatelessWidget {
  const _PinnedViewerSheet({required this.notif});

  final _PinnedViewerNotif notif;

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, bottomPad + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Avatar + name
            Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: notif.avatarColor,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.5),
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      notif.avatarInitial,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text(
                          notif.username,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: AppColors.primary.withValues(alpha: 0.30),
                            ),
                          ),
                          child: Text(
                            'pinned',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 9,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      'You pinned them — real name visible',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.18),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.visibility_outlined,
                        size: 14,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Viewed: ${notif.viewedWhat}',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    notif.timeAgo,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.cardSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.shield_outlined,
                    size: 13,
                    color: AppColors.secondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Pool gating bypassed — you explicitly pinned this person.',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: AppColors.textMuted,
                        height: 1.4,
                      ),
                    ),
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

// ---------------------------------------------------------------------------
// Stub — HighlightCreatorView (not yet implemented)
// ---------------------------------------------------------------------------

class HighlightCreatorView extends StatelessWidget {
  const HighlightCreatorView({
    super.key,
    required this.onClose,
    required this.onBack,
  });

  final VoidCallback onClose;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0C),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: onClose,
                    child: const Icon(Icons.close_rounded,
                        color: Colors.white, size: 24),
                  ),
                  const Spacer(),
                  Text(
                    'Highlights',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(width: 24),
                ],
              ),
            ),
            const Expanded(
              child: Center(
                child: Text(
                  'Coming soon',
                  style: TextStyle(color: Colors.white38, fontSize: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Screenshot helpers — expose private sheets for main.dart test modes
void showProfilePinModal(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _PinModal(),
  );
}

void pushProfileSearch(BuildContext context) {
  Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => const _SearchScreen(),
    ),
  );
}
