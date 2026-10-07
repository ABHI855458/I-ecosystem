import 'package:flutter_test/flutter_test.dart';
import 'package:i/features/highlights/highlight_models.dart';
import 'package:i/features/highlights/highlights_wall_screen.dart';
import 'package:i/features/highlights/polaroid_cover.dart';
import 'package:i/features/people/find_people_screen.dart';
import 'package:i/features/profile_v2/circle_people_screen.dart';

/// The pure ordering / parsing rules behind the polaroids, the people
/// search and the circle list.
void main() {
  Highlight h(String id, {String owner = 'friend', String updated = '2026-10-07T10:00:00'}) =>
      Highlight(
        id: id,
        ownerId: owner,
        title: id,
        updatedAt: updated,
        photos: const [HighlightPhoto(postId: 'p', url: 'https://x/y.jpg')],
      );

  group('sortForWall', () {
    test('new ones first, then watched; newest update first in each', () {
      final all = [
        h('seen-old', updated: '2026-10-01T10:00:00'),
        h('new-old', updated: '2026-10-02T10:00:00'),
        h('seen-new', updated: '2026-10-06T10:00:00'),
        h('new-new', updated: '2026-10-07T09:00:00'),
      ];
      final got = sortForWall(all, isNew: (x) => x.id.startsWith('new'));
      expect(got.map((x) => x.id), ['new-new', 'new-old', 'seen-new', 'seen-old']);
    });
  });

  group('orderForWall', () {
    test("friends' new, then mine, then friends' watched", () {
      final all = [
        h('mine', owner: 'me', updated: '2026-10-07T12:00:00'),
        h('watched', updated: '2026-10-06T10:00:00'),
        h('fresh', updated: '2026-10-05T10:00:00'),
      ];
      final got = orderForWall(
        all,
        isNew: (x) => x.id == 'fresh',
        isMine: (x) => x.ownerId == 'me',
      );
      expect(got.map((x) => x.id), ['fresh', 'mine', 'watched']);
    });
  });

  group('Highlight.fromRow', () {
    Map<String, dynamic> row(List<Map<String, dynamic>> items) => {
      'id': 'h1',
      'user_id': 'u1',
      'title': '  Goa  ',
      'updated_at': '2026-10-07T10:00:00',
      'users': {'name': 'Riya', 'username': 'riya', 'profile_photo_url': null},
      'highlight_items': items,
    };

    test('orders photos by position and reads the aspect ratio', () {
      final got = Highlight.fromRow(
        row([
          {
            'position': 1,
            'post_id': 'b',
            'posts': {'id': 'b', 'image_url': 'https://x/b.jpg', 'aspect_ratio': '4:5'},
          },
          {
            'position': 0,
            'post_id': 'a',
            'posts': {'id': 'a', 'image_url': 'https://x/a.jpg', 'aspect_ratio': '1.5'},
          },
        ]),
      )!;
      expect(got.title, 'Goa');
      expect(got.ownerName, 'Riya');
      expect(got.photos.map((p) => p.postId), ['a', 'b']);
      expect(got.coverUrl, 'https://x/a.jpg');
      expect(got.photos[0].aspect, 1.5);
      expect(got.photos[1].aspect, closeTo(0.8, 0.0001));
    });

    test('skips photos this viewer may not see, or that were deleted', () {
      final got = Highlight.fromRow(
        row([
          // RLS hid the post: the embed comes back null.
          {'position': 0, 'post_id': 'hidden', 'posts': null},
          {
            'position': 1,
            'post_id': 'gone',
            'posts': {
              'id': 'gone',
              'image_url': 'https://x/gone.jpg',
              'deleted_at': '2026-10-07T09:00:00',
            },
          },
          {
            'position': 2,
            'post_id': 'ok',
            'posts': {'id': 'ok', 'image_url': 'https://x/ok.jpg'},
          },
        ]),
      )!;
      expect(got.photos.map((p) => p.postId), ['ok']);
    });

    test('a highlight with nothing visible is dropped entirely', () {
      expect(
        Highlight.fromRow(
          row([
            {'position': 0, 'post_id': 'hidden', 'posts': null},
          ]),
        ),
        isNull,
      );
      expect(Highlight.fromRow(row(const [])), isNull);
    });
  });

  group('sortByMutuals', () {
    test('most mutual friends first; ties keep their order', () {
      final rows = [
        {'id': 'a', 'name': 'A'},
        {'id': 'b', 'name': 'B'},
        {'id': 'c', 'name': 'C'},
        {'id': 'd', 'name': 'D'},
      ];
      final got = sortByMutuals(rows, {'c': 4, 'b': 1, 'd': 1});
      expect(got.map((r) => r['id']), ['c', 'b', 'd', 'a']);
    });

    test('reads suggestion rows too (keyed by user_id)', () {
      final rows = [
        {'user_id': 'x'},
        {'user_id': 'y'},
      ];
      expect(sortByMutuals(rows, {'y': 2}).map((r) => r['user_id']), ['y', 'x']);
    });
  });

  group('polaroid shape', () {
    test('follows the photo: portrait is taller than square, landscape '
        'shorter', () {
      const w = 100.0;
      final portrait = polaroidHeightFor(w, aspect: 3 / 4);
      final square = polaroidHeightFor(w);
      final landscape = polaroidHeightFor(w, aspect: 4 / 3);
      expect(portrait, greaterThan(square));
      expect(landscape, lessThan(square));
      // The window is the photo's own shape: 86 wide, so 86 / (3/4) tall.
      expect(portrait, closeTo(7 + 86 / 0.75 + 26, 0.001));
    });

    test('a very tall or very wide photo stops at the limits', () {
      const w = 100.0;
      expect(
        polaroidHeightFor(w, aspect: 9 / 21),
        polaroidHeightFor(w, aspect: kPolaroidMinAspect),
      );
      expect(
        polaroidHeightFor(w, aspect: 3),
        polaroidHeightFor(w, aspect: kPolaroidMaxAspect),
      );
      expect(polaroidMaxHeightFor(w), polaroidHeightFor(w, aspect: 0.1));
    });
  });

  group('a video in a highlight', () {
    test('is read from the post, with its poster as the cover', () {
      final got = Highlight.fromRow({
        'id': 'h1',
        'user_id': 'u1',
        'title': 'Trip',
        'updated_at': '2026-10-07T10:00:00',
        'highlight_items': [
          {
            'position': 0,
            'post_id': 'v',
            'posts': {
              'id': 'v',
              'image_url': 'https://x/poster.jpg',
              'video_url': 'https://x/clip.mp4',
              'video_duration_ms': 8200,
              'aspect_ratio': '0.5625',
            },
          },
          {
            'position': 1,
            'post_id': 'p',
            'posts': {'id': 'p', 'image_url': 'https://x/p.jpg'},
          },
        ],
      })!;
      expect(got.coverIsVideo, isTrue);
      expect(got.coverUrl, 'https://x/poster.jpg');
      expect(got.coverAspect, 0.5625);
      expect(got.photos[0].videoMs, 8200);
      expect(got.photos[1].isVideo, isFalse);
    });
  });

  group('filterCirclePeople', () {
    final people = [
      {'id': 'u1', 'name': 'Asha Rao', 'username': 'asha'},
      {'id': 'u2', 'name': 'Ravi', 'username': 'ravi_k'},
      {'id': 'u3', 'name': 'Meera', 'username': 'meera'},
    ];
    final membership = {
      'u1': {'friends', 'close'},
      'u2': {'friends'},
      'u3': {'family'},
    };

    test('All shows everyone', () {
      expect(filterCirclePeople(people, membership).length, 3);
    });

    test('a chip narrows to that circle', () {
      final got = filterCirclePeople(people, membership, circleId: 'friends');
      expect(got.map((p) => p['id']), ['u1', 'u2']);
    });

    test('search matches name or username, inside the chosen circle', () {
      expect(
        filterCirclePeople(people, membership, query: 'RAV').map((p) => p['id']),
        ['u2'],
      );
      expect(
        filterCirclePeople(
          people,
          membership,
          circleId: 'family',
          query: 'asha',
        ),
        isEmpty,
      );
    });
  });
}
