import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

class StreakData {
  const StreakData({
    required this.count,
    required this.postedToday,
    required this.lastPostDate,
  });

  final int count;
  final bool postedToday;
  final DateTime? lastPostDate;

  // Streak is alive if user posted today OR posted yesterday (still has today left)
  bool get isAlive {
    if (postedToday) return true;
    if (lastPostDate == null || count == 0) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final lastDay = DateTime(
        lastPostDate!.year, lastPostDate!.month, lastPostDate!.day);
    return today.difference(lastDay).inDays <= 1;
  }

  // Hours since last post (for "24h left" warning)
  int get hoursSinceLastPost {
    if (lastPostDate == null) return 999;
    return DateTime.now().difference(lastPostDate!).inHours;
  }
}

// ---------------------------------------------------------------------------
// Service — static helpers backed by shared_preferences
// ---------------------------------------------------------------------------

class StreakService {
  static const _kCount = 'streak_count';
  static const _kLastPost = 'streak_last_post_ms';
  static const _kDemoSeeded = 'streak_demo_seeded';

  // Load current streak state from prefs.
  // On first launch, seeds a demo 5-day streak from 22h ago.
  static Future<StreakData> load() async {
    final prefs = await SharedPreferences.getInstance();

    // Seed demo state once so the profile looks interesting on first launch
    if (!(prefs.getBool(_kDemoSeeded) ?? false)) {
      final seedTime =
          DateTime.now().subtract(const Duration(hours: 22)).millisecondsSinceEpoch;
      await prefs.setInt(_kCount, 5);
      await prefs.setInt(_kLastPost, seedTime);
      await prefs.setBool(_kDemoSeeded, true);
    }

    final count = prefs.getInt(_kCount) ?? 0;
    final lastMs = prefs.getInt(_kLastPost);
    final lastPostDate =
        lastMs != null ? DateTime.fromMillisecondsSinceEpoch(lastMs) : null;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    bool postedToday = false;
    if (lastPostDate != null) {
      final lastDay = DateTime(
          lastPostDate.year, lastPostDate.month, lastPostDate.day);
      postedToday = lastDay == today;
    }

    // Check if streak has expired (missed a full day)
    int liveCount = count;
    if (!postedToday && lastPostDate != null) {
      final lastDay = DateTime(
          lastPostDate.year, lastPostDate.month, lastPostDate.day);
      if (today.difference(lastDay).inDays > 1) {
        // Streak broken — reset
        liveCount = 0;
        await prefs.setInt(_kCount, 0);
      }
    }

    return StreakData(
      count: liveCount,
      postedToday: postedToday,
      lastPostDate: lastPostDate,
    );
  }

  // Record a post today — extends or starts streak.
  static Future<StreakData> recordPost() async {
    final prefs = await SharedPreferences.getInstance();
    final current = await load();

    final now = DateTime.now();

    if (current.postedToday) {
      // Already posted today, streak unchanged
      return current;
    }

    int newCount;
    if (current.count == 0 || !current.isAlive) {
      newCount = 1; // Fresh start
    } else {
      newCount = current.count + 1;
    }

    await prefs.setInt(_kCount, newCount);
    await prefs.setInt(_kLastPost, now.millisecondsSinceEpoch);

    return StreakData(
      count: newCount,
      postedToday: true,
      lastPostDate: now,
    );
  }

  // Reset streak (for testing).
  static Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kCount);
    await prefs.remove(_kLastPost);
    await prefs.remove(_kDemoSeeded);
  }
}
