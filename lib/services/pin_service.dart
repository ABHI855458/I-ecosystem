import 'package:flutter/material.dart';

class ActivityItem {
  final String postName;
  final String postType; // 'anon' or 'everyone'
  final String duration;
  final String timeAgo;

  const ActivityItem({
    required this.postName,
    required this.postType,
    required this.duration,
    required this.timeAgo,
  });
}

class PinnedUser {
  final String username;
  final String displayName;
  final int secondsViewed;
  final String lingeredOnPost;
  final String lingeredOnDuration;
  final int anonCount;
  final int everyoneCount;
  final String lastActivity;
  final List<ActivityItem> history;

  const PinnedUser({
    required this.username,
    required this.displayName,
    required this.secondsViewed,
    required this.lingeredOnPost,
    required this.lingeredOnDuration,
    required this.anonCount,
    required this.everyoneCount,
    required this.lastActivity,
    required this.history,
  });
}

class NotificationItem {
  final String id;
  final String username;
  final String actionType; // 'like', 'comment', 'view'
  final String postName;
  final String time;
  final String demographicSignal;

  const NotificationItem({
    required this.id,
    required this.username,
    required this.actionType,
    required this.postName,
    required this.time,
    required this.demographicSignal,
  });
}

class PinService extends ChangeNotifier {
  // Singleton Pattern
  static final PinService _instance = PinService._internal();
  factory PinService() => _instance;
  PinService._internal() {
    _initializeData();
  }

  // Active Pinned Users (stores up to 6 slots)
  final List<PinnedUser> _pinnedUsers = [];
  
  // Library of all potential users with their custom metrics/history
  final Map<String, PinnedUser> _allUsersLibrary = {};

  // List of active notifications
  final List<NotificationItem> _notifications = [];

  // Demographic signals list (for non-pinned views)
  final List<String> _demographicSignals = [
    "An EC girl viewed your profile",
    "Someone from CSE viewed your posts",
    "Someone from RV College viewed your memories",
    "A 3rd Year student lingering on your coffee post",
    "An art design member viewed your campus sunset post",
  ];

  List<PinnedUser> get pinnedUsers => List.unmodifiable(_pinnedUsers);
  List<NotificationItem> get notifications => List.unmodifiable(_notifications);
  List<String> get demographicSignals => List.unmodifiable(_demographicSignals);

  void _initializeData() {
    // 1. alex_xyz
    _allUsersLibrary['alex_xyz'] = const PinnedUser(
      username: 'alex_xyz',
      displayName: 'Alex',
      secondsViewed: 823,
      lingeredOnPost: 'Fest collage',
      lingeredOnDuration: '3m 24s',
      anonCount: 2,
      everyoneCount: 1,
      lastActivity: '2h ago',
      history: [
        ActivityItem(postName: 'Fest collage', postType: 'everyone', duration: '3m 24s', timeAgo: '2h ago'),
        ActivityItem(postName: 'Coffee moment', postType: 'everyone', duration: '2m 15s', timeAgo: '4h ago'),
        ActivityItem(postName: 'silent_storm', postType: 'anon', duration: '3m 05s', timeAgo: '1d ago'),
        ActivityItem(postName: 'velvet_echo', postType: 'anon', duration: '4m 59s', timeAgo: '2d ago'),
      ],
    );

    // 2. jordan_23
    _allUsersLibrary['jordan_23'] = const PinnedUser(
      username: 'jordan_23',
      displayName: 'Jordan',
      secondsViewed: 456,
      lingeredOnPost: 'Coffee moment',
      lingeredOnDuration: '1m 45s',
      anonCount: 1,
      everyoneCount: 2,
      lastActivity: '1h ago',
      history: [
        ActivityItem(postName: 'Coffee moment', postType: 'everyone', duration: '1m 45s', timeAgo: '1h ago'),
        ActivityItem(postName: 'Campus sunset', postType: 'everyone', duration: '2m 11s', timeAgo: '5h ago'),
        ActivityItem(postName: 'study_bug', postType: 'anon', duration: '3m 40s', timeAgo: '3h ago'),
      ],
    );

    // 3. study_bug
    _allUsersLibrary['study_bug'] = const PinnedUser(
      username: 'study_bug',
      displayName: 'Study Bug',
      secondsViewed: 234,
      lingeredOnPost: 'Library study',
      lingeredOnDuration: '2m 10s',
      anonCount: 3,
      everyoneCount: 0,
      lastActivity: '45m ago',
      history: [
        ActivityItem(postName: 'Library study', postType: 'anon', duration: '2m 10s', timeAgo: '45m ago'),
        ActivityItem(postName: 'Exam stress', postType: 'anon', duration: '54s', timeAgo: '2h ago'),
        ActivityItem(postName: 'silent_storm', postType: 'anon', duration: '50s', timeAgo: '1d ago'),
      ],
    );

    // 4. sunset_chaser
    _allUsersLibrary['sunset_chaser'] = const PinnedUser(
      username: 'sunset_chaser',
      displayName: 'Sunset Chaser',
      secondsViewed: 567,
      lingeredOnPost: 'Sunset at campus',
      lingeredOnDuration: '4m 02s',
      anonCount: 1,
      everyoneCount: 2,
      lastActivity: '3h ago',
      history: [
        ActivityItem(postName: 'Sunset at campus', postType: 'everyone', duration: '4m 02s', timeAgo: '3h ago'),
        ActivityItem(postName: 'Coffee moment', postType: 'everyone', duration: '4m 00s', timeAgo: '1d ago'),
        ActivityItem(postName: 'silent_storm', postType: 'anon', duration: '1m 25s', timeAgo: '2d ago'),
      ],
    );

    // Populate default pinned users (4 users)
    _pinnedUsers.add(_allUsersLibrary['alex_xyz']!);
    _pinnedUsers.add(_allUsersLibrary['jordan_23']!);
    _pinnedUsers.add(_allUsersLibrary['study_bug']!);
    _pinnedUsers.add(_allUsersLibrary['sunset_chaser']!);

    // Default notifications setup
    _notifications.addAll([
      const NotificationItem(
        id: '1',
        username: 'alex_xyz',
        actionType: 'like',
        postName: 'Fest collage',
        time: '2h ago',
        demographicSignal: 'An EC girl',
      ),
      const NotificationItem(
        id: '2',
        username: 'jordan_23',
        actionType: 'comment',
        postName: 'Coffee moment',
        time: '1h ago',
        demographicSignal: 'Someone from CSE',
      ),
      const NotificationItem(
        id: '3',
        username: 'silent_echo_99',
        actionType: 'like',
        postName: 'Late night snack',
        time: '3h ago',
        demographicSignal: 'A 3rd Year student',
      ),
      const NotificationItem(
        id: '4',
        username: 'unknown_scouter',
        actionType: 'view',
        postName: 'Library study',
        time: '5h ago',
        demographicSignal: 'Someone from CSE',
      ),
    ]);
  }

  // Get or generate a user in the library
  PinnedUser getOrCreateUser(String username) {
    if (_allUsersLibrary.containsKey(username)) {
      return _allUsersLibrary[username]!;
    }
    // Generate some randomized dummy metrics for other users if viewed
    final user = PinnedUser(
      username: username,
      displayName: username.replaceAll('_', ' ').toUpperCase(),
      secondsViewed: 120 + (username.hashCode % 300),
      lingeredOnPost: 'Campus life',
      lingeredOnDuration: '1m 15s',
      anonCount: username.hashCode % 3,
      everyoneCount: (username.hashCode % 2) + 1,
      lastActivity: 'Just now',
      history: [
        ActivityItem(
          postName: 'Campus life',
          postType: 'everyone',
          duration: '1m 15s',
          timeAgo: '1h ago',
        ),
      ],
    );
    _allUsersLibrary[username] = user;
    return user;
  }

  bool isPinned(String username) {
    return _pinnedUsers.any((u) => u.username == username);
  }

  bool pinUser(String username) {
    if (isPinned(username)) return true;
    if (_pinnedUsers.length >= 6) {
      // Limit of 6 pinned users reached
      return false;
    }
    final user = getOrCreateUser(username);
    _pinnedUsers.add(user);
    notifyListeners();
    return true;
  }

  void unpinUser(String username) {
    _pinnedUsers.removeWhere((u) => u.username == username);
    notifyListeners();
  }

  void addSimulatedNotification(String username, String type, String postName) {
    final demographic = username.contains('alex') ? 'An EC girl' : 'Someone from CSE';
    _notifications.insert(0, NotificationItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      username: username,
      actionType: type,
      postName: postName,
      time: 'Just now',
      demographicSignal: demographic,
    ));
    notifyListeners();
  }
}
