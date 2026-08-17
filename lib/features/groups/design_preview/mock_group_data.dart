/// Shared mock data for the three Group Profile design-direction previews
/// (1a Cover, 1b Streak, 1c Roster — see
/// design-refs/design_handoff_group_profile/README.md). One instance is
/// reused by all three screens so they're directly comparable. This is a
/// standalone preview tool: no GroupService/Supabase involved, and it does
/// not touch the real, live-data group_profile_screen.dart.
class MockMember {
  const MockMember({
    required this.id,
    required this.name,
    required this.isAdmin,
    required this.dipCount,
    required this.lastDippedLabel,
    required this.hasPostedToday,
    required this.last5Days,
  });

  final String id;
  final String name;
  final bool isAdmin;
  final int dipCount;
  final String lastDippedLabel;
  final bool hasPostedToday;

  /// Oldest → newest, left to right, per the 1c "consistency bar" spec.
  final List<bool> last5Days;
}

class MockCalendarDay {
  const MockCalendarDay({
    required this.hasPost,
    this.isToday = false,
    this.isFuture = false,
  });

  final bool hasPost;
  final bool isToday;
  final bool isFuture;
}

class MockGroupData {
  const MockGroupData({
    required this.name,
    required this.startedLabel,
    required this.isPrivate,
    required this.bio,
    required this.totalDips,
    required this.streak,
    required this.onTimePercent,
    required this.members,
    required this.calendar,
  });

  final String name;
  final String startedLabel;
  final bool isPrivate;
  final String bio;
  final int totalDips;
  final int streak;
  final int onTimePercent;
  final List<MockMember> members;
  final List<MockCalendarDay> calendar;

  int get missingTodayCount => members.where((m) => !m.hasPostedToday).length;

  static const _members = <MockMember>[
    MockMember(
      id: 'sarah',
      name: 'Sarah',
      isAdmin: true,
      dipCount: 38,
      lastDippedLabel: 'Dipped 2h ago',
      hasPostedToday: true,
      last5Days: [true, true, true, true, false],
    ),
    MockMember(
      id: 'maya',
      name: 'Maya',
      isAdmin: false,
      dipCount: 31,
      lastDippedLabel: 'Dipped 5h ago',
      hasPostedToday: true,
      last5Days: [true, true, false, true, true],
    ),
    MockMember(
      id: 'arjun',
      name: 'Arjun',
      isAdmin: false,
      dipCount: 29,
      lastDippedLabel: 'Dipped 8h ago',
      hasPostedToday: true,
      last5Days: [true, false, true, true, true],
    ),
    MockMember(
      id: 'priya',
      name: 'Priya',
      isAdmin: false,
      dipCount: 25,
      lastDippedLabel: 'Dipped 11h ago',
      hasPostedToday: true,
      last5Days: [false, true, true, true, true],
    ),
    MockMember(
      id: 'kian',
      name: 'Kian',
      isAdmin: false,
      dipCount: 22,
      lastDippedLabel: "Hasn't dipped today",
      hasPostedToday: false,
      last5Days: [true, true, true, false, true],
    ),
    MockMember(
      id: 'dev',
      name: 'Dev',
      isAdmin: false,
      dipCount: 18,
      lastDippedLabel: "Hasn't dipped today",
      hasPostedToday: false,
      last5Days: [true, false, true, true, false],
    ),
  ];

  // 28 cells (4 full weeks) — mirrors the design doc's own calendar grid
  // length. Mostly-dipped with a few scattered misses; index 20 is "today";
  // everything after it is "future" (hasn't happened yet).
  static List<MockCalendarDay> _buildCalendar() {
    const missedIndices = {2, 8, 19};
    return List.generate(28, (i) {
      if (i == 20) return const MockCalendarDay(hasPost: false, isToday: true);
      if (i > 20) return const MockCalendarDay(hasPost: false, isFuture: true);
      return MockCalendarDay(hasPost: !missedIndices.contains(i));
    });
  }

  static final instance = MockGroupData(
    name: 'Weekend Crew 🌊',
    startedLabel: 'Mar 2025',
    isPrivate: true,
    bio: "Coastal drives, questionable playlists, one dip a day whether we like it or not.",
    totalDips: 128,
    streak: 41,
    onTimePercent: 92,
    members: _members,
    calendar: _buildCalendar(),
  );
}
