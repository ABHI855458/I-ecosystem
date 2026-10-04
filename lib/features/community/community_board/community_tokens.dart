import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ---------------------------------------------------------------------------
// Design tokens for the Community Board redesign — ported 1:1 from the
// Claude Design source ("Community Board.dc.html", project "Community feed
// screen design", https://claude.ai/design/p/125ba18f-c2e3-4557-9f8e-
// 1b211c283313). Dedicated token file (not AppColors) because these are
// exact spec hex values, not this app's generic dark-theme palette — same
// reasoning anon_feed_tokens.dart already established for a comparably
// pixel-precise redesign.
// ---------------------------------------------------------------------------

class CommunityColors {
  CommunityColors._();

  static const screenBg = Color(0xFF0B0B0E);

  // Accents
  static const pink = Color(0xFFFA2D64);
  static const pinkHover = Color(0xFFFF5C86);
  static const lime = Color(0xFFA8E83C);
  static const amber = Color(0xFFF5B13D);
  static const amberDark = Color(0xFFE8912B);

  // Priority (pinned notice) card
  static const priorityCardBg = Color(0xFF16150F);
  static const priorityCardBorder = Color(0xFF3A3116);
  static const priorityPillText = Color(0xFFF0BD6A);

  // Text
  static const textBright = Color(0xFFF4F5F8);
  static const textPrimary = Color(0xFFECEDF0);
  static const textSecondary = Color(0xFF8F90A0);
  static const textDim = Color(0xFF7C7D8C);
  static const textDimmer = Color(0xFF5C5D6B);
  static const textFaint = Color(0xFF6A6B79);
  static const textBody = Color(0xFFD6D7DE);
  static const textMuted2 = Color(0xFFC9CAD3);

  // Surfaces / borders
  static const cardBg = Color(0xFF13131A);
  static const cardBg2 = Color(0xFF1A1A22);
  static const popoverBg = Color(0xFF15151C);
  static const tabDivider = Color(0xFF1C1C23);
  static const cardBorder = Color(0xFF1F1F27);
  static const chipBorder = Color(0xFF26262F);
  static const chipBorderHover = Color(0xFF3A3B47);
  static const popoverBorder = Color(0xFF2A2A34);
  static const pollOptionBorder = Color(0xFF23232C);
  static const levelRingCenter = Color(0xFF14170F);
  static const photoStripeA = Color(0xFF1A1A22);
  static const photoStripeB = Color(0xFF16161D);
  static const streakEmpty = Color(0xFF22262B);
  static const streakLow = Color(0xFF3A5518);
  static const streakMed = Color(0xFF5F8A24);
  static const streakHigh = Color(0xFFA8E83C);

  // Poll fill states
  static const pollFillLead = Color(0x2EA8E83C); // rgba(168,232,60,0.18)
  static const pollFillOther = Color(0x248F90A0); // rgba(143,144,160,0.14)
  static const pollEdgeOther = Color(0xFF4A4B58);
}

class CommunityType {
  CommunityType._();

  static TextStyle _m({
    required double size,
    required FontWeight weight,
    Color? color,
    double? letterSpacing,
    double? height,
  }) =>
      GoogleFonts.inter(
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: letterSpacing,
        height: height,
      );

  // "community" wordmark
  static TextStyle wordmark = _m(size: 20, weight: FontWeight.w600, color: CommunityColors.textPrimary, letterSpacing: -0.5);
  static TextStyle subline = _m(size: 10.5, weight: FontWeight.w400, color: CommunityColors.textDimmer, letterSpacing: 0.02 * 10.5);

  // Tabs
  static TextStyle tabActive = _m(size: 12.5, weight: FontWeight.w600, color: CommunityColors.textPrimary, letterSpacing: 0.03 * 12.5);
  static TextStyle tabInactive = _m(size: 12.5, weight: FontWeight.w600, color: CommunityColors.textDimmer, letterSpacing: 0.03 * 12.5);

  // Chips
  static TextStyle chipActive = _m(size: 11.5, weight: FontWeight.w600, color: CommunityColors.screenBg, letterSpacing: 0.02 * 11.5);
  static TextStyle chipInactive = _m(size: 11.5, weight: FontWeight.w500, color: CommunityColors.textSecondary, letterSpacing: 0.02 * 11.5);
  static TextStyle chipCount = _m(size: 9, weight: FontWeight.w700, color: Colors.white);

  // Section headers ("PRIORITY", "THE FEED", "TOP STREAKS"...)
  static TextStyle sectionLabel(Color color) => _m(size: 9.5, weight: FontWeight.w700, color: color, letterSpacing: 0.14 * 9.5);
  static TextStyle sectionMeta = _m(size: 9.5, weight: FontWeight.w600, color: CommunityColors.textDimmer, letterSpacing: 0.08 * 9.5);

  // Priority card
  static TextStyle priorityBadge = _m(size: 9.5, weight: FontWeight.w700, color: CommunityColors.amber, letterSpacing: 0.04 * 9.5);
  static TextStyle priorityHandle = _m(size: 10.5, weight: FontWeight.w500, color: CommunityColors.textMuted2);
  static TextStyle priorityTime = _m(size: 10, weight: FontWeight.w400, color: CommunityColors.textDim);
  static TextStyle priorityBody = _m(size: 16, weight: FontWeight.w800, color: CommunityColors.textBright, letterSpacing: -0.3, height: 1.4);
  static TextStyle priorityPill = _m(size: 10, weight: FontWeight.w600, color: CommunityColors.priorityPillText, letterSpacing: 0.02 * 10);
  static TextStyle reactionCount = _m(size: 11, weight: FontWeight.w400, color: CommunityColors.textSecondary);

  // Feed cards
  static TextStyle postHandle = _m(size: 10.5, weight: FontWeight.w500, color: CommunityColors.textSecondary);
  static TextStyle postTime = _m(size: 10, weight: FontWeight.w400, color: CommunityColors.textDim);
  static TextStyle postBody = _m(size: 15, weight: FontWeight.w700, color: CommunityColors.textBody, letterSpacing: -0.1, height: 1.5);
  static TextStyle liveFireCount = _m(size: 9.5, weight: FontWeight.w600, color: CommunityColors.lime);
  static TextStyle pollTag = _m(size: 9, weight: FontWeight.w600, color: CommunityColors.textDimmer, letterSpacing: 0.08 * 9);
  static TextStyle photoCaption = _m(size: 9.5, weight: FontWeight.w400, color: CommunityColors.textFaint, letterSpacing: 0.06 * 9.5);

  // Poll
  static TextStyle pollOption(Color color) => _m(size: 12, weight: FontWeight.w500, color: color);
  static TextStyle pollPct(Color color) => _m(size: 11, weight: FontWeight.w700, color: color);
  static TextStyle pollMeta = _m(size: 9.5, weight: FontWeight.w400, color: CommunityColors.textDim, letterSpacing: 0.04 * 9.5);
  static TextStyle pollCta = _m(size: 9.5, weight: FontWeight.w700, color: CommunityColors.lime, letterSpacing: 0.06 * 9.5);
  static TextStyle pollVoted = _m(size: 9.5, weight: FontWeight.w700, color: const Color(0xFF7FA832), letterSpacing: 0.06 * 9.5);

  // Streaks tab
  static TextStyle levelTag = _m(size: 9.5, weight: FontWeight.w700, color: const Color(0xFF7FA832), letterSpacing: 0.12 * 9.5);
  static TextStyle levelName = _m(size: 16, weight: FontWeight.w600, color: CommunityColors.textPrimary, letterSpacing: -0.4);
  static TextStyle rankLabel = _m(size: 9.5, weight: FontWeight.w700, color: CommunityColors.textDimmer, letterSpacing: 0.12 * 9.5);
  static TextStyle rankNumber = _m(size: 26, weight: FontWeight.w700, color: CommunityColors.textPrimary, letterSpacing: -1);
  static TextStyle rankOutOf = _m(size: 12, weight: FontWeight.w400, color: CommunityColors.textDim);
  static TextStyle rankDeltaWeek = _m(size: 9.5, weight: FontWeight.w700, color: CommunityColors.lime);
  static TextStyle xpLabel = _m(size: 9.5, weight: FontWeight.w400, color: CommunityColors.textSecondary, letterSpacing: 0.04 * 9.5);
  static TextStyle streakBig = _m(size: 26, weight: FontWeight.w700, color: CommunityColors.lime, letterSpacing: -1);
  static TextStyle streakLabel = _m(size: 11, weight: FontWeight.w400, color: const Color(0xFF7FA832));
  static TextStyle streakBest = _m(size: 9.5, weight: FontWeight.w400, color: CommunityColors.textDim, letterSpacing: 0.04 * 9.5);
  static TextStyle streakDayLabel = _m(size: 9, weight: FontWeight.w400, color: CommunityColors.textDim, letterSpacing: 0.06 * 9);
  static TextStyle nudgeText = _m(size: 12, weight: FontWeight.w400, color: const Color(0xFFF2B5C6), height: 1.35);
  static TextStyle nudgeBold = _m(size: 12, weight: FontWeight.w700, color: CommunityColors.pink);

  static TextStyle cardTitle = _m(size: 16, weight: FontWeight.w600, color: CommunityColors.textBright, letterSpacing: -0.3);
  static TextStyle cardSubtitlePink = _m(size: 10, weight: FontWeight.w600, color: CommunityColors.pink, letterSpacing: 0.04 * 10);
  static TextStyle resetsLabel = _m(size: 9, weight: FontWeight.w400, color: CommunityColors.textSecondary, letterSpacing: 0.04 * 9);
  static TextStyle resetsValue = _m(size: 13, weight: FontWeight.w700, color: CommunityColors.pink, letterSpacing: -0.2);
  static TextStyle yourRankLabel = _m(size: 11.5, weight: FontWeight.w400, color: CommunityColors.textMuted2, letterSpacing: 0.02 * 11.5);
  static TextStyle yourRankValue = _m(size: 18, weight: FontWeight.w700, color: CommunityColors.pink, letterSpacing: -0.3);
  static TextStyle yourRankPts = _m(size: 12, weight: FontWeight.w400, color: CommunityColors.textSecondary);

  static TextStyle podiumAvatarInitial = _m(size: 17, weight: FontWeight.w700, color: CommunityColors.textMuted2);
  static TextStyle podiumAvatarInitialLead = _m(size: 21, weight: FontWeight.w700, color: CommunityColors.textBright);
  static TextStyle podiumName = _m(size: 11, weight: FontWeight.w400, color: CommunityColors.textMuted2);
  static TextStyle podiumNameLead = _m(size: 12.5, weight: FontWeight.w500, color: CommunityColors.textBright);
  static TextStyle podiumScore = _m(size: 13, weight: FontWeight.w700, color: CommunityColors.pink);
  static TextStyle podiumScoreLead = _m(size: 15, weight: FontWeight.w700, color: CommunityColors.pink);
  static TextStyle podiumRankTag = _m(size: 13, weight: FontWeight.w700, color: CommunityColors.textSecondary);
  static TextStyle podiumRankTagLead = _m(size: 15, weight: FontWeight.w700, color: CommunityColors.pink);

  static TextStyle leaderRank = _m(size: 11.5, weight: FontWeight.w700, color: CommunityColors.textSecondary);
  static TextStyle leaderAvatarInitial = _m(size: 11, weight: FontWeight.w700, color: CommunityColors.textMuted2);
  static TextStyle leaderHandle = _m(size: 12, weight: FontWeight.w400, color: const Color(0xFFE4E5EA));
  static TextStyle leaderScore = _m(size: 14, weight: FontWeight.w700, color: const Color(0xFFE4E5EA));
  static TextStyle leaderDeltaUp = _m(size: 9, weight: FontWeight.w400, color: const Color(0xFF7FA832));
  static TextStyle leaderDeltaDown = _m(size: 9, weight: FontWeight.w400, color: const Color(0xFFE0607F));

  static TextStyle streakRowRank = _m(size: 12, weight: FontWeight.w700, color: CommunityColors.lime, letterSpacing: -0.3);
  static TextStyle streakRowRankDim = _m(size: 12, weight: FontWeight.w700, color: CommunityColors.textDim, letterSpacing: -0.3);
  static TextStyle streakRowHandle = _m(size: 12.5, weight: FontWeight.w500, color: const Color(0xFFE4E5EA));
  static TextStyle streakRowHandleYou = _m(size: 12.5, weight: FontWeight.w600, color: CommunityColors.textBright);
  static TextStyle streakRowTopTag = _m(size: 8.5, weight: FontWeight.w700, color: CommunityColors.screenBg, letterSpacing: 0.08 * 8.5);
  static TextStyle streakRowYouTag = _m(size: 8.5, weight: FontWeight.w700, color: CommunityColors.screenBg, letterSpacing: 0.08 * 8.5);
  static TextStyle streakRowRivalTag = _m(size: 8.5, weight: FontWeight.w700, color: CommunityColors.pink, letterSpacing: 0.08 * 8.5);
  static TextStyle streakRowLevelTag = _m(size: 8.5, weight: FontWeight.w700, color: const Color(0xFF7FA832), letterSpacing: 0.06 * 8.5);
  static TextStyle streakRowFire = _m(size: 14, weight: FontWeight.w700, color: CommunityColors.lime, letterSpacing: -0.4);
  static TextStyle streakRowFireDim = _m(size: 14, weight: FontWeight.w700, color: CommunityColors.textMuted2, letterSpacing: -0.4);
  static TextStyle streakRowPosts = _m(size: 9, weight: FontWeight.w400, color: CommunityColors.textDim, letterSpacing: 0.04 * 9);

  // Join popover
  static TextStyle popoverTitle = _m(size: 11, weight: FontWeight.w700, color: CommunityColors.textSecondary, letterSpacing: 0.1 * 11);
  static TextStyle searchInput = _m(size: 12, weight: FontWeight.w400, color: const Color(0xFFE4E5EA), letterSpacing: 0.01 * 12);
  static TextStyle joinRowName = _m(size: 13, weight: FontWeight.w700, color: CommunityColors.textBright);
  static TextStyle joinRowMeta = _m(size: 9.5, weight: FontWeight.w400, color: CommunityColors.textDim, letterSpacing: 0.02 * 9.5);
  static TextStyle joinBtnJoined = _m(size: 10, weight: FontWeight.w700, color: CommunityColors.lime, letterSpacing: 0.02 * 10);
  static TextStyle joinBtnNotJoined = _m(size: 10, weight: FontWeight.w700, color: Colors.white, letterSpacing: 0.04 * 10);
  static TextStyle noResults = _m(size: 11, weight: FontWeight.w400, color: CommunityColors.textFaint);
  static TextStyle joinPillLabel = _m(size: 11.5, weight: FontWeight.w600, color: CommunityColors.pink, letterSpacing: 0.02 * 11.5);
}

class CommunityCurves {
  CommunityCurves._();
  static const chipDuration = Duration(milliseconds: 200);
  static const popoverDuration = Duration(milliseconds: 220);
  static const pollFillDuration = Duration(milliseconds: 850);
  static const xpBarDuration = Duration(milliseconds: 1100);
  static const voteRingDuration = Duration(milliseconds: 700);
}
