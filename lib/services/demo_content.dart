import 'feed_service.dart';
import 'post_service.dart';
import 'wall_service.dart';

/// Local-only demo content for the Everyone feed and the Wall highlights
/// strip so both have something to show before real posts/highlights exist.
/// Never touches Supabase — see [LocalPost.localOnly] and
/// [WallService]'s in-memory fallback.
class DemoContent {
  DemoContent._();

  static bool _seeded = false;

  static void seedIfNeeded() {
    if (_seeded || PostService.instance.everyonePosts.isNotEmpty) return;
    _seeded = true;
    for (final post in _demoPosts) {
      PostService.instance.addPost(post);
    }
  }

  static final List<LocalPost> _demoPosts = [
    LocalPost(
      id: 'demo-post-8',
      userId: 'demo_riley',
      username: 'riley_m',
      branch: 'CSE',
      visibility: 'everyone',
      caption: 'Sunday library grind 📚',
      photoUrl: 'https://picsum.photos/seed/i-app-library/900/1125',
      localOnly: true,
      createdAt: DateTime.now().subtract(const Duration(hours: 20)),
    ),
    LocalPost(
      id: 'demo-post-7',
      userId: 'demo_jordan',
      username: 'jordan_p',
      branch: 'ECE',
      visibility: 'everyone',
      caption: 'Dorm balcony sunsets hit different 🌆',
      photoUrl: 'https://picsum.photos/seed/i-app-balcony/900/1125',
      musicTitle: 'Sunset Drive',
      musicArtist: 'Nightcall',
      localOnly: true,
      createdAt: DateTime.now().subtract(const Duration(hours: 11)),
    ),
    LocalPost(
      id: 'demo-post-6',
      userId: 'demo_sam',
      username: 'sam_t',
      branch: 'Business',
      visibility: 'everyone',
      caption: 'Gameday energy was unreal tonight 🏈🔥',
      photoUrl: 'https://picsum.photos/seed/i-app-gameday/900/1125',
      localOnly: true,
      createdAt: DateTime.now().subtract(const Duration(hours: 7)),
    ),
    LocalPost(
      id: 'demo-post-5',
      userId: 'demo_ava',
      username: 'ava_l',
      branch: 'Design',
      visibility: 'everyone',
      caption: 'Formal szn 🥂',
      photoUrl: 'https://picsum.photos/seed/i-app-formal/900/1125',
      musicTitle: 'Golden Hour',
      musicArtist: 'Atlas & Co.',
      localOnly: true,
      createdAt: DateTime.now().subtract(const Duration(hours: 4)),
    ),
    LocalPost(
      id: 'demo-post-4',
      userId: 'demo_maya',
      username: 'maya_k',
      branch: 'Bio',
      visibility: 'everyone',
      caption: 'Waterfall hike with the squad 🥾',
      photoUrl: 'https://picsum.photos/seed/i-app-hike/900/1125',
      localOnly: true,
      createdAt: DateTime.now().subtract(const Duration(hours: 2, minutes: 30)),
    ),
    LocalPost(
      id: 'demo-post-3',
      userId: 'demo_devon',
      username: 'devon_r',
      branch: 'Photography',
      visibility: 'everyone',
      caption: 'Field trip flowers 🌸',
      photoUrl: 'https://picsum.photos/seed/i-app-flowers/900/1125',
      localOnly: true,
      createdAt: DateTime.now().subtract(const Duration(hours: 1, minutes: 10)),
    ),
    LocalPost(
      id: 'demo-post-2',
      userId: 'demo_priya',
      username: 'priya_n',
      branch: '3rd Year',
      visibility: 'everyone',
      caption: 'Late night diner run 🍟',
      photoUrl: 'https://picsum.photos/seed/i-app-diner/900/1125',
      musicTitle: 'Drive Home',
      musicArtist: 'Waves & Static',
      localOnly: true,
      createdAt: DateTime.now().subtract(const Duration(minutes: 34)),
    ),
    LocalPost(
      id: 'demo-post-1',
      userId: 'demo_theo',
      username: 'theo_b',
      branch: 'Campus',
      visibility: 'everyone',
      caption: 'Golden hour on the quad 🌇',
      photoUrl: 'https://picsum.photos/seed/i-app-quad/900/1125',
      localOnly: true,
      createdAt: DateTime.now().subtract(const Duration(minutes: 6)),
    ),
  ];

  /// DEMO/PLACEHOLDER group posts for the Everyone feed — group_posts data
  /// is sparse right now, same reasoning as [_demoPosts]. Never touches
  /// Supabase; interleaved into EveryoneFeedScreen's feed alongside real
  /// posts (see everyone_feed_screen.dart). Each carries [FeedItem.
  /// groupName]/[communityTag] so EveryonePostCard renders the "Posted by
  /// {group} · {poster}" attribution + community tag — the one place a
  /// community indicator still belongs, distinct from the individual-post
  /// tag removed in item #4.
  static final List<FeedItem> demoGroupPosts = [
    FeedItem(
      postId: 'demo-group-post-1',
      type: 'single',
      userId: 'demo_group_cse',
      username: 'nina_k',
      groupName: 'CS Study Group',
      communityTag: 'CSE',
      caption: 'Whiteboard finally makes sense after 3 hours 🧠',
      photoUrl: 'https://picsum.photos/seed/i-app-group-cse/900/1125',
      createdAt: DateTime.now().subtract(const Duration(hours: 5)),
    ),
    FeedItem(
      postId: 'demo-group-post-2',
      type: 'single',
      userId: 'demo_group_photo',
      username: 'devon_r',
      groupName: 'Campus Photography Club',
      communityTag: 'Photography',
      caption: 'Golden hour shoot from the roof deck 📷',
      photoUrl: 'https://picsum.photos/seed/i-app-group-photo/900/1125',
      createdAt: DateTime.now().subtract(const Duration(hours: 14)),
    ),
  ];

  static final List<Highlight> demoHighlights = [
    Highlight(
      id: 'demo-wall-1',
      userId: 'demo',
      title: 'Move-In Day',
      photos: const [
        'https://picsum.photos/seed/i-app-movein-1/600/600',
        'https://picsum.photos/seed/i-app-movein-2/600/600',
      ],
    ),
    Highlight(
      id: 'demo-wall-2',
      userId: 'demo',
      title: 'Finals Week',
      photos: const [
        'https://picsum.photos/seed/i-app-finals-1/600/600',
      ],
    ),
    Highlight(
      id: 'demo-wall-3',
      userId: 'demo',
      title: 'Formal Szn',
      photos: const [
        'https://picsum.photos/seed/i-app-formal-1/600/600',
      ],
    ),
    Highlight(
      id: 'demo-wall-4',
      userId: 'demo',
      title: 'Gameday',
      photos: const [
        'https://picsum.photos/seed/i-app-gameday-1/600/600',
      ],
    ),
    Highlight(
      id: 'demo-wall-5',
      userId: 'demo',
      title: 'Spring Break',
      photos: const [
        'https://picsum.photos/seed/i-app-spring-1/600/600',
      ],
    ),
  ];
}
