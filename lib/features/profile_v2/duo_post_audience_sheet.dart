import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/glass.dart' show showGlassToast;
import '../../core/supabase_config.dart';
import '../../services/circle_service.dart';
import '../../services/feed_refresh_signal.dart';
import 'profile_v2_tokens.dart';

// ---------------------------------------------------------------------------
// "Choose your audience" for a Duo post your partner made (explicit request,
// 2026-10-03: "if either one posts it shall appear in feed and the other
// person shall be notified as posted — choose your audience and post").
//
// A Duo post is ONE row owned by whoever shot it, so the partner doesn't
// re-post it; they ADD their own circles to its audience, and the same photo
// starts reaching their friends too. The rows go in `post_audiences`, which
// post_audience_admits already ORs over — see
// 20261003070000_duo_shared_posts_and_qr_friends.sql for the policies that
// let the partner write them.
//
// The same sheet also carries the two shared controls, because this is where
// the partner lands when they tap the notification:
//   * Make it private — hides it from BOTH feeds (one row, one flag).
//   * Remove it — either partner may delete the post outright.
// ---------------------------------------------------------------------------

Future<void> showDuoPostAudienceSheet(
  BuildContext context, {
  required String postId,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (_) => _DuoPostAudienceSheet(postId: postId),
);

class _DuoPostAudienceSheet extends StatefulWidget {
  const _DuoPostAudienceSheet({required this.postId});
  final String postId;

  @override
  State<_DuoPostAudienceSheet> createState() => _DuoPostAudienceSheetState();
}

class _DuoPostAudienceSheetState extends State<_DuoPostAudienceSheet> {
  List<CircleOption>? _circles;
  final Set<String> _picked = {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final circles = await CircleService.instance.fetchMyCircles();
      // Already-added circles start ticked, so reopening the sheet shows
      // the truth rather than an empty slate.
      final existing = await supabase
          .from('post_audiences')
          .select('circle_id')
          .eq('post_id', widget.postId)
          .eq('audience_kind', 'circle');
      if (!mounted) return;
      setState(() {
        _circles = circles;
        for (final r in (existing as List).cast<Map<String, dynamic>>()) {
          final id = r['circle_id'] as String?;
          if (id != null) _picked.add(id);
        }
      });
    } catch (_) {
      if (mounted) setState(() => _circles = const []);
    }
  }

  Future<void> _post() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      // Replace this partner's selection wholesale: drop the circle rows,
      // then insert the ticked ones.
      await supabase
          .from('post_audiences')
          .delete()
          .eq('post_id', widget.postId)
          .eq('audience_kind', 'circle');
      if (_picked.isNotEmpty) {
        await supabase.from('post_audiences').insert([
          for (final id in _picked)
            {
              'post_id': widget.postId,
              'audience_kind': 'circle',
              'circle_id': id,
            },
        ]);
      }
      signalFeedRefresh();
      if (!mounted) return;
      Navigator.of(context).pop();
      showGlassToast(
        context,
        _picked.isEmpty ? 'Audience cleared' : 'Posted to your circles 💞',
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      showGlassToast(context, "Couldn't update the audience.", isError: true);
    }
  }

  Future<void> _makePrivate() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await supabase
          .from('posts')
          .update({'show_in_feed': false})
          .eq('id', widget.postId);
      signalFeedRefresh();
      if (!mounted) return;
      Navigator.of(context).pop();
      showGlassToast(context, 'Private now — hidden from both your feeds');
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      showGlassToast(context, "Couldn't make it private.", isError: true);
    }
  }

  Future<void> _remove() async {
    if (_busy) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PV2.raised,
        title: Text('Remove this Duo post?', style: PV2.display(size: 18)),
        content: Text(
          'It goes for both of you. This cannot be undone.',
          style: GoogleFonts.inter(fontSize: 13.5, color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Remove',
              style: TextStyle(color: Color(0xFFFF6B7A)),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      // Soft delete — the same thing the author's own "delete post" does.
      await supabase
          .from('posts')
          .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', widget.postId);
      signalFeedRefresh();
      if (!mounted) return;
      Navigator.of(context).pop();
      showGlassToast(context, 'Removed for both of you');
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      showGlassToast(context, "Couldn't remove it.", isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final circles = _circles;
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: PV2.page,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Choose your audience', style: PV2.display(size: 21)),
            const SizedBox(height: 6),
            Text(
              'Your Duo posted this. Pick who of yours sees it too.',
              style: GoogleFonts.inter(fontSize: 13, color: Colors.white60),
            ),
            const SizedBox(height: 16),
            if (circles == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white54,
                  ),
                ),
              )
            else if (circles.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  'No circles yet.',
                  style: GoogleFonts.inter(fontSize: 13, color: Colors.white38),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final c in circles)
                      _CircleRow(
                        name: c.name,
                        picked: _picked.contains(c.id),
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() {
                            _picked.contains(c.id)
                                ? _picked.remove(c.id)
                                : _picked.add(c.id);
                          });
                        },
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 14),
            GestureDetector(
              onTap: _busy ? null : _post,
              child: Container(
                height: 50,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(25),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF4A5BDE), Color(0xFFD1406E)],
                  ),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        'Post to my circles',
                        style: GoogleFonts.inter(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: _busy ? null : _makePrivate,
                    child: Text(
                      'Make private',
                      style: GoogleFonts.inter(
                        fontSize: 13.5,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: TextButton(
                    onPressed: _busy ? null : _remove,
                    child: Text(
                      'Remove post',
                      style: GoogleFonts.inter(
                        fontSize: 13.5,
                        color: const Color(0xFFFF6B7A),
                      ),
                    ),
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

class _CircleRow extends StatelessWidget {
  const _CircleRow({
    required this.name,
    required this.picked,
    required this.onTap,
  });

  final String name;
  final bool picked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          Expanded(
            child: Text(
              name,
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: picked ? FontWeight.w700 : FontWeight.w500,
                color: picked ? Colors.white : Colors.white70,
              ),
            ),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: picked ? const Color(0xFFD1406E) : Colors.transparent,
              border: Border.all(
                color: picked ? const Color(0xFFD1406E) : Colors.white30,
                width: 2,
              ),
            ),
            child: picked
                ? const Icon(Icons.check_rounded, size: 15, color: Colors.white)
                : null,
          ),
        ],
      ),
    ),
  );
}
