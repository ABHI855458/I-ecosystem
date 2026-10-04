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
    // Multi-photo demos, exercising the swipeable carousel (Item 1). Photos
    // go entirely into photoUrls, not split with photoUrl: FeedItem.
    // fromLocalPost only ever prepends photoPath (a LOCAL pre-upload file)
    // ahead of photoUrls, never photoUrl (a REMOTE url) — a demo post has
    // no photoPath, so leaving the cover in photoUrl here would silently
    // drop it from the carousel. resolvePostPhotos then reads photoUrls
    // exclusively once it's non-empty (post_photo_carousel.dart:169-173),
    // so the full list below, with the cover as element 0, is what
    // actually renders.
    LocalPost(
      id: 'demo-post-10',
      userId: 'demo_priya',
      username: 'priya_n',
      branch: 'Design',
      visibility: 'everyone',
      caption: 'Studio crit day — swipe for the whole board 🎨',
      photoUrls: [
        'https://picsum.photos/seed/i-app-studio-1/900/1125',
        'https://picsum.photos/seed/i-app-studio-2/900/1125',
        'https://picsum.photos/seed/i-app-studio-3/900/1125',
        'https://picsum.photos/seed/i-app-studio-4/900/1125',
      ],
      localOnly: true,
      createdAt: DateTime.now().subtract(const Duration(minutes: 40)),
    ),
    LocalPost(
      id: 'demo-post-9',
      userId: 'demo_marcus',
      username: 'marcus_l',
      branch: 'Journalism',
      visibility: 'everyone',
      caption: 'Spring formal recap — all the fits 📸',
      photoUrls: [
        'https://picsum.photos/seed/i-app-formal-recap-1/900/1125',
        'https://picsum.photos/seed/i-app-formal-recap-2/900/1125',
        'https://picsum.photos/seed/i-app-formal-recap-3/900/1125',
        'https://picsum.photos/seed/i-app-formal-recap-4/900/1125',
        'https://picsum.photos/seed/i-app-formal-recap-5/900/1125',
        'https://picsum.photos/seed/i-app-formal-recap-6/900/1125',
        'https://picsum.photos/seed/i-app-formal-recap-7/900/1125',
      ],
      localOnly: true,
      createdAt: DateTime.now().subtract(const Duration(hours: 2)),
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
    // Multi-photo group demo — FeedItem has no photoUrl/photoUrls split
    // (unlike LocalPost), so the full list goes straight into `photos`;
    // resolvePostPhotos reads that directly, cover included as element 0.
    FeedItem(
      postId: 'demo-group-post-3',
      type: 'single',
      userId: 'demo_group_hike',
      username: 'zoe_p',
      groupName: 'Outdoors Club',
      communityTag: 'Recreation',
      caption: 'Sunrise summit — worth the 4am alarm ⛰️',
      photos: [
        'https://picsum.photos/seed/i-app-group-hike-1/900/1125',
        'https://picsum.photos/seed/i-app-group-hike-2/900/1125',
        'https://picsum.photos/seed/i-app-group-hike-3/900/1125',
        'https://picsum.photos/seed/i-app-group-hike-4/900/1125',
        'https://picsum.photos/seed/i-app-group-hike-5/900/1125',
      ],
      createdAt: DateTime.now().subtract(const Duration(hours: 3)),
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
