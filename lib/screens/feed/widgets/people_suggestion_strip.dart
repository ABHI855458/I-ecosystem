import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/glass.dart' show showGlassToast;
import '../../../services/circle_service.dart';

const _kCyan = Color(0xFF29D3E8);

/// "New on campus" — a horizontal strip of people mixed into the Friends
/// feed (explicit request: new users' photo + name with an add button, at
/// random spots, so the feed feels alive as people arrive). The people come
/// from PeopleService.suggestedPeople (share a community with me, not in my
/// Friends circle, newest first). Add puts them in my Friends circle —
/// circles are the whole social graph now, there is no request to accept.
class PeopleSuggestionStrip extends StatelessWidget {
  const PeopleSuggestionStrip({
    super.key,
    required this.people,
    required this.added,
    required this.onAdded,
    required this.onDismiss,
  });

  /// suggested_people rows (user_id, name, profile_photo_url, joined_at,
  /// community_name).
  final List<Map<String, dynamic>> people;

  /// Added this session: user id -> the circle they went into. They stay in
  /// place showing "Added to `<circle>`".
  final Map<String, String> added;
  final void Function(String userId, String circleName) onAdded;
  final ValueChanged<String> onDismiss;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: _kCyan,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'New on campus',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'add them to your circle',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.45),
                      fontSize: 12.5,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 212,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: people.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                final p = people[i];
                final id = p['user_id'] as String;
                return _PersonCard(
                  key: ValueKey(id),
                  person: p,
                  addedTo: added[id],
                  onAdded: (circle) => onAdded(id, circle),
                  onDismiss: () => onDismiss(id),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PersonCard extends StatefulWidget {
  const _PersonCard({
    super.key,
    required this.person,
    required this.addedTo,
    required this.onAdded,
    required this.onDismiss,
  });

  final Map<String, dynamic> person;

  /// The circle they were added to this session, null if not yet.
  final String? addedTo;
  final ValueChanged<String> onAdded;
  final VoidCallback onDismiss;

  @override
  State<_PersonCard> createState() => _PersonCardState();
}

class _PersonCardState extends State<_PersonCard> {
  /// My circles, fetched once per app session and shared by every card.
  static Future<List<CircleOption>>? _circles;

  bool _busy = false;

  /// Add → a bottom sheet of my circles (big rows; the anchored dropdown it
  /// replaced was "too awkward"); picking one adds them there and closes.
  Future<void> _add() async {
    if (_busy || widget.addedTo != null) return;
    HapticFeedback.selectionClick();
    List<CircleOption> circles;
    try {
      circles = await (_circles ??= CircleService.instance.fetchMyCircles());
    } catch (_) {
      _circles = null;
      circles = const [];
    }
    if (!mounted) return;
    if (circles.isEmpty) {
      _circles = null;
      showGlassToast(context, "Couldn't load your circles.", isError: true);
      return;
    }
    final name = ((widget.person['name'] as String?) ?? '').trim();
    final picked = await showModalBottomSheet<CircleOption>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _CirclePickerSheet(
        name: name.isEmpty ? 'them' : name,
        photoUrl: widget.person['profile_photo_url'] as String?,
        circles: circles,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await CircleService.instance.addMember(
        picked.id,
        widget.person['user_id'] as String,
        // In-place: no feed-wide reload under the user's finger.
        refreshFeed: false,
      );
      _circles = null; // member counts changed
      widget.onAdded(picked.name);
    } catch (_) {
      if (mounted) {
        showGlassToast(context, "Couldn't add them — try again.", isError: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.person;
    final name = ((p['name'] as String?) ?? '').trim();
    final shown = name.isEmpty ? 'someone' : name;
    final photo = p['profile_photo_url'] as String?;
    final community = (p['community_name'] as String?)?.trim();
    // Friends we share (suggested_people.mutual_count, 2026-10-07). When
    // there are any it is the more telling line, so it replaces the
    // community one.
    final mutual = (p['mutual_count'] as num?)?.toInt() ?? 0;
    final joined = DateTime.tryParse('${p['joined_at'] ?? ''}');
    final isNew = joined != null &&
        DateTime.now().toUtc().difference(joined.toUtc()).inDays < 7;

    return Container(
      width: 144,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 18, 12, 12),
            child: Column(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isNew
                              ? _kCyan.withValues(alpha: 0.8)
                              : Colors.white.withValues(alpha: 0.12),
                          width: 2,
                        ),
                      ),
                      padding: const EdgeInsets.all(3),
                      child: ClipOval(
                        child: photo == null
                            ? ColoredBox(
                                color: Colors.white.withValues(alpha: 0.08),
                                child: Center(
                                  child: Text(
                                    shown[0].toUpperCase(),
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.7),
                                      fontSize: 24,
                                      fontWeight: FontWeight.w600,
                                      decoration: TextDecoration.none,
                                    ),
                                  ),
                                ),
                              )
                            : CachedNetworkImage(
                                imageUrl: photo,
                                fit: BoxFit.cover,
                                memCacheWidth: 216,
                              ),
                      ),
                    ),
                    if (isNew)
                      Positioned(
                        bottom: -4,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _kCyan,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'NEW',
                              style: TextStyle(
                                color: Color(0xFF0B0B0D),
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.6,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  shown,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  mutual > 0
                      ? (mutual == 1
                            ? '1 mutual friend'
                            : '$mutual mutual friends')
                      : community == null || community.isEmpty
                      ? 'on campus'
                      : 'in $community',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: mutual > 0
                        ? _kCyan.withValues(alpha: 0.9)
                        : Colors.white.withValues(alpha: 0.45),
                    fontSize: 11.5,
                    fontWeight: mutual > 0 ? FontWeight.w600 : FontWeight.w400,
                    decoration: TextDecoration.none,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _add,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 34,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: widget.addedTo != null
                          ? Colors.white.withValues(alpha: 0.08)
                          : _kCyan,
                      borderRadius: BorderRadius.circular(17),
                    ),
                    child: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF0B0B0D),
                            ),
                          )
                        : Text(
                            widget.addedTo != null
                                ? 'Added to ${widget.addedTo} ✓'
                                : 'Add',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: widget.addedTo != null
                                  ? Colors.white.withValues(alpha: 0.7)
                                  : const Color(0xFF0B0B0D),
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              decoration: TextDecoration.none,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
          if (widget.addedTo == null)
            Positioned(
              top: 2,
              right: 2,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onDismiss,
                child: SizedBox(
                  width: 36,
                  height: 36,
                  child: Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: Colors.white.withValues(alpha: 0.4),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// "Add `<name>` to…" — their photo and name on top, then one full-width row
/// per circle. Tapping a row returns that circle.
/// "Which circle?" — the same big-row sheet the suggestion cards use, for
/// any other surface that adds a person (people search). Null when the
/// sheet is dismissed or my circles can't be loaded (a toast says so).
Future<CircleOption?> showCirclePicker(
  BuildContext context, {
  required String name,
  String? photoUrl,
}) async {
  List<CircleOption> circles;
  try {
    circles = await CircleService.instance.fetchMyCircles();
  } catch (_) {
    circles = const [];
  }
  if (!context.mounted) return null;
  if (circles.isEmpty) {
    showGlassToast(context, "Couldn't load your circles.", isError: true);
    return null;
  }
  return showModalBottomSheet<CircleOption>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _CirclePickerSheet(
      name: name.trim().isEmpty ? 'them' : name.trim(),
      photoUrl: photoUrl,
      circles: circles,
    ),
  );
}

class _CirclePickerSheet extends StatelessWidget {
  const _CirclePickerSheet({
    required this.name,
    required this.photoUrl,
    required this.circles,
  });

  final String name;
  final String? photoUrl;
  final List<CircleOption> circles;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.75,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF151518),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      padding: EdgeInsets.fromLTRB(16, 10, 16, 16 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              ClipOval(
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: photoUrl == null
                      ? ColoredBox(
                          color: Colors.white.withValues(alpha: 0.08),
                          child: Center(
                            child: Text(
                              name[0].toUpperCase(),
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.7),
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        )
                      : CachedNetworkImage(
                          imageUrl: photoUrl!,
                          fit: BoxFit.cover,
                          memCacheWidth: 132,
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Add $name to…',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Pick a circle — they won\'t be notified',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: circles.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final c = circles[i];
                return Material(
                  color: Colors.white.withValues(alpha: c.isFriends ? 0.07 : 0.04),
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      HapticFeedback.selectionClick();
                      Navigator.of(context).pop(c);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: (c.isFriends ? _kCyan : Colors.white)
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(11),
                            ),
                            child: Icon(
                              c.isFriends
                                  ? Icons.people_alt_rounded
                                  : Icons.workspaces_outline,
                              size: 18,
                              color: c.isFriends ? _kCyan : Colors.white70,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              c.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text(
                            c.memberCount == 1
                                ? '1 person'
                                : '${c.memberCount} people',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.4),
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            Icons.add_rounded,
                            size: 18,
                            color: Colors.white.withValues(alpha: 0.5),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
