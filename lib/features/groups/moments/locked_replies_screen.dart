import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';

import '../../../core/supabase_config.dart';
import '../../../services/current_user_service.dart';
import '../../../services/moment_prefs_service.dart';
import '../../../services/moment_service.dart';
import '../../composer/composer_screen.dart';
import '../../moderation/post_actions_menu.dart';

// ---------------------------------------------------------------------------
// Locked Replies — Moments spec §4a. Warm-paper Moments app, dark-chrome
// screen: a horizontal swipe carousel of reply cards, blurred + unlabeled
// until the viewer contributes their own photo ("Add yours"), after which
// the blur lifts and each card's emoji badge + name pill pop in staggered.
// Once revealed there is no way back to locked — no toggle, no re-blur.
//
// Only this screen is built from the "Group Postcards" spec pasted this
// turn — it was called out explicitly as the priority ("Ship the Locked
// Replies change (§4a) as the priority"). The feed cards (§2, already
// under way elsewhere in screens/feed/widgets/group_post_cards/), reaction-
// capture camera (§3), the other 12 Moments screens (§4), and the notched
// post card (§5) are NOT built here — out of scope for this pass.
//
// A REAL Moment (a `posts` row with post_type = 'moment', whose id is a
// UUID) now fetches its own data: the poster's own photo from `posts`, and
// the contributions from `moment_replies` via MomentService. The reveal is
// server-enforced — get_moment_replies returns NOTHING until the viewer has
// contributed (the Moment's author is exempt), so the blur here is a
// presentation of that fact, not the thing enforcing it.
//
// The hardcoded demo Moments (kDemoMoments, id 'demo-moment-N') keep working
// exactly as before: a non-UUID [momentId] means "use the [replies] passed
// in", so no call site had to change. MomentPrefsService survives only as an
// optimistic local hint while the first fetch is in flight; server truth
// wins whenever it disagrees.
// ---------------------------------------------------------------------------

class MomentReply {
  const MomentReply({
    required this.name,
    required this.emoji,
    required this.photoUrl,
    this.isLockedPlaceholder = false,
  });

  final String name;
  final String emoji;
  final String photoUrl;

  /// A stand-in for a real contribution the viewer isn't entitled to see
  /// yet — carries NO photo bytes (photoUrl is unused/empty for one of
  /// these). get_moment_replies never sends the actual photo to a locked
  /// viewer, so there is nothing to blur client-side; this card exists so
  /// "someone replied" is visible before you do ("the posts shall appear
  /// blur first before a user replies"), without ever fetching real
  /// content the viewer hasn't earned yet.
  final bool isLockedPlaceholder;
}

const _kMomentBg = Color(0xFF141216);
const _kMomentText = Color(0xFFF5F1EA);
const _kMomentMuted = Color(0xFF8A8178);
const _kMomentPink = Color(0xFFEE3F84);
const _kMomentPinkCta = Color(0xFFE23C7C);

const _kDimMatrix = <double>[
  0.94, 0, 0, 0, 0,
  0, 0.94, 0, 0, 0,
  0, 0, 0.94, 0, 0,
  0, 0, 0, 1, 0,
];
const _kIdentityMatrix = <double>[
  1, 0, 0, 0, 0,
  0, 1, 0, 0, 0,
  0, 0, 1, 0, 0,
  0, 0, 0, 1, 0,
];

class LockedRepliesScreen extends StatefulWidget {
  const LockedRepliesScreen({
    super.key,
    required this.momentId,
    required this.title,
    required this.replies,
  });

  /// Identifies this Moment for hasPosted persistence — must be stable and
  /// unique per Moment.
  final String momentId;
  final String title;
  final List<MomentReply> replies;

  @override
  State<LockedRepliesScreen> createState() => _LockedRepliesScreenState();
}

class _LockedRepliesScreenState extends State<LockedRepliesScreen>
    with SingleTickerProviderStateMixin {
  // Resolved at layout time rather than fixed, so the carousel fills a tall
  // phone instead of floating a 240x340 card in the middle of one. Written
  // from LayoutBuilder (not setState — they feed the gesture math, which
  // runs after the frame that set them).
  double _cardW = 240;
  double _cardH = 340;
  static const _gap = 16.0;
  double get _step => _cardW + _gap;

  static const _dragThreshold = 46.0;
  static const _snapDuration = Duration(milliseconds: 340);
  // cubic-bezier(.22,.9,.3,1.1) — Cubic supports control points beyond
  // [0,1] directly, which is what gives the slight overshoot on snap.
  static const _snapCurve = Cubic(0.22, 0.9, 0.3, 1.1);

  late final AnimationController _snapCtrl;

  int _index = 0;
  double _focus = 0; // fractional focus position — == _index at rest
  double _focusAtDragStart = 0;
  double _dragAccum = 0;

  // null while the persisted value is still loading (brief — defaults to
  // locked in that window rather than flashing revealed then locking).
  bool? _hasPosted;

  /// A real Moment is a `posts` row, so its id is a UUID. A demo Moment's
  /// id is 'demo-moment-N', which is what tells the two apart — and what
  /// lets kDemoMoments keep rendering from [widget.replies] untouched.
  bool get _isReal => Uuid.isValidUUID(fromString: widget.momentId);

  /// Server-fetched contributions. Empty means LOCKED, not "no replies" —
  /// get_moment_replies returns nothing until the viewer has contributed
  /// (see MomentService's own doc).
  List<MomentReply> _serverReplies = const [];

  /// The Moment's own photo, always shown first and never blurred: it is
  /// the Moment itself, not somebody's reply to it.
  MomentReply? _posterCard;

  /// `posts.user_id` of the Moment's author — decides whether the "..."
  /// menu offers Remove (yours) or Report/Block (someone else's).
  String? _authorUserId;

  /// My own users.id, for that same comparison.
  String? _myUserId;

  /// Whether I am the person whose Moment this is.
  ///
  /// The poster never has to "Add yours" to see the replies — they already
  /// contributed the photo the whole Moment is built around. The server has
  /// always agreed (get_moment_replies exempts the author outright), but the
  /// client's unlock was `replies.isNotEmpty`, and an author whose Moment had
  /// no replies YET got an empty result — indistinguishable, from here, from
  /// being locked. So the poster was shown the lock on their own Moment and
  /// asked to reply to it. Reported as "for the poster no need to reply again
  /// to view the photo".
  ///
  /// Both ids are null until their fetches land, and `null == null` would
  /// unlock every viewer during that window — hence the explicit non-null
  /// check rather than a bare comparison.
  bool get _isAuthor =>
      _authorUserId != null && _myUserId != null && _authorUserId == _myUserId;

  bool _loading = false;

  /// Whether I have contributed a photo to this Moment. Distinct from
  /// "revealed": an EXPIRED Moment opens to everyone, so a viewer can be
  /// looking at the replies without ever having added one — and they are
  /// the one person the revealed footer should still offer Add yours to.
  bool _iContributed = false;

  /// The non-gated contributor COUNT (get_moment_reply_counts) — unlike
  /// [_serverReplies] this is visible to a locked viewer, because a count
  /// reveals no photos. It is what lets the locked state say "3 replies"
  /// instead of the "0 replies" a locked, empty [_serverReplies] used to
  /// show — the count and the (withheld) content were being read off the
  /// same gated list.
  int _lockedReplyCount = 0;

  /// The cards to draw — poster's photo first for a real Moment, then
  /// either the real contributions (once revealed) or that many BLURRED
  /// placeholder cards (while locked) — see MomentReply.isLockedPlaceholder.
  /// Demo Moments keep using the passed-in list, already fully visible.
  List<MomentReply> get _cards {
    if (!_isReal) return widget.replies;
    final revealed = _isAuthor || (_hasPosted ?? false);
    final replies = revealed
        ? _serverReplies
        : List<MomentReply>.generate(
            _lockedReplyCount,
            (_) => const MomentReply(
              name: '',
              emoji: '',
              photoUrl: '',
              isLockedPlaceholder: true,
            ),
          );
    return [?_posterCard, ...replies];
  }

  /// How many of [_cards] are replies rather than the Moment's own photo.
  int get _replyCount {
    if (!_isReal) return widget.replies.length;
    final revealed = _isAuthor || (_hasPosted ?? false);
    return revealed ? _serverReplies.length : _lockedReplyCount;
  }

  @override
  void initState() {
    super.initState();
    unawaited(_resolveMe());
    _snapCtrl = AnimationController(vsync: this, duration: _snapDuration);
    _loadHasPosted();
    if (_isReal) _loadReal();
  }

  Future<void> _loadHasPosted() async {
    final posted = await MomentPrefsService.loadHasPosted(widget.momentId);
    if (!mounted) return;
    // ONLY EVER PROMOTES. This races _loadReal(), and shared_preferences'
    // first read can land after the server round trip — so a bare
    // assignment here would overwrite the server's "revealed" with a stale
    // local false and re-lock a Moment the viewer is entitled to see. That
    // is what put the Add-yours gate back in front of a Moment's own author
    // ("the uploader is still seeing the upload-to-see").
    if (posted && _hasPosted != true) {
      setState(() => _hasPosted = true);
    } else if (_hasPosted == null) {
      setState(() => _hasPosted = posted);
    }
  }

  /// Fetches the Moment's own photo and its contributions. Both fail closed
  /// (poster card stays null, replies stay empty = locked) rather than
  Future<void> _resolveMe() async {
    try {
      final id = await CurrentUserService.instance.resolveId();
      if (mounted) setState(() => _myUserId = id);
    } catch (_) {
      // Not signed in — the menu falls back to Report, which is the safe
      // default for a post you can't prove is yours.
    }
  }

  /// The "..." in the top bar. It was decorative — a literal '···' Text with
  /// no gesture on it at all — so a Moment had no way to be reported or
  /// taken down from the one screen that shows it full-size.
  Future<void> _openMenu() async {
    if (!_isReal) return; // demo Moment: no row to report or remove
    await showPostActionsMenu(
      context,
      postId: widget.momentId,
      isOwnPost: _authorUserId != null && _authorUserId == _myUserId,
      // A Moment is never anonymous (composer_screen posts it as
      // 'everyone'/'friends'), so Block stays available on someone else's.
      isAnonymousPost: false,
      authorUsersId: _authorUserId,
      title: 'THIS MOMENT',
      onDeleted: () {
        if (mounted) Navigator.of(context).maybePop();
      },
    );
  }

  /// throwing into the widget tree, same contract the feeds use.
  Future<void> _loadReal() async {
    setState(() => _loading = true);
    try {
      // The gate is ASKED FOR, not inferred. Both are fetched together so
      // there is no window where the screen has replies but not the flag.
      final results = await Future.wait([
        MomentService.instance.fetchReplies(widget.momentId),
        MomentService.instance.isRevealed(widget.momentId),
        MomentService.instance.replyCounts([widget.momentId]),
      ]);
      final replies = results[0] as List<MomentReplyRow>;
      final revealed = results[1] as bool;
      final counts = results[2] as Map<String, int>;
      Map<String, dynamic>? post;
      try {
        post = Map<String, dynamic>.from(
          await supabase
                  .from('posts')
                  // FK named explicitly: `posts` has TWO paths to `users`
                  // (user_id and partner_user_id, the Duo partner), so
                  // a bare users(...) embed is ambiguous and PostgREST
                  // refuses the whole query with PGRST201. That refusal was
                  // swallowed by the catch below, leaving _posterCard AND
                  // _authorUserId null — so the Moment lost its creator's
                  // photo and its own author failed the _isAuthor check.
                  .select(
                    'image_url, user_id, '
                    'users!posts_user_id_fkey(name, profile_photo_url)',
                  )
                  .eq('id', widget.momentId)
                  .isFilter('deleted_at', null)
                  .maybeSingle()
              as Map,
        );
      } catch (_) {
        post = null;
      }

      if (!mounted) return;
      setState(() {
        _serverReplies = [
          for (final r in replies)
            MomentReply(name: r.name, emoji: '', photoUrl: r.photoUrl),
        ];
        final imageUrl = post?['image_url'] as String?;
        final author = post?['users'] as Map?;
        _authorUserId = post?['user_id'] as String?;
        _posterCard = (imageUrl == null || imageUrl.isEmpty)
            ? null
            : MomentReply(
                name: (author?['name'] as String?)?.trim().isNotEmpty == true
                    ? (author!['name'] as String).trim()
                    : 'the moment',
                emoji: '',
                photoUrl: imageUrl,
              );
        // Server truth, from moment_is_revealed — not inferred from "did
        // any replies come back".
        //
        // The old `replies.isNotEmpty` test conflated "you may look" with
        // "there is something to look at", so a moment with NO replies yet
        // read as locked even to the person who posted it — reported as
        // the poster being shown Add-yours on their own moment. It also
        // kept an expired moment locked for a non-contributor, since an
        // empty reply list is indistinguishable from a refusal.
        //
        // Still only ever promotes: an offline false can't undo an
        // optimistic local unlock.
        _iContributed = replies.any((r) => r.isMe);
        _lockedReplyCount = counts[widget.momentId] ?? 0;
        if (revealed || replies.isNotEmpty) _hasPosted = true;
        _loading = false;
      });
      // Cache the server's yes so a reopen is unlocked on first frame
      // instead of flashing the gate while the round trip runs — "the
      // person opened via replying can anytime reopen it".
      if (revealed || replies.isNotEmpty) {
        unawaited(MomentPrefsService.setHasPosted(widget.momentId, true));
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _snapCtrl.dispose();
    super.dispose();
  }

  void _onDragStart(DragStartDetails d) {
    _snapCtrl.stop();
    _focusAtDragStart = _focus;
    _dragAccum = 0;
  }

  void _onDragUpdate(DragUpdateDetails d) {
    _dragAccum += d.delta.dx;
    final maxIndex = (_cards.length - 1).clamp(0, 1 << 30).toDouble();
    setState(() {
      _focus = (_focusAtDragStart - _dragAccum / _step).clamp(0.0, maxIndex);
    });
  }

  void _onDragEnd(DragEndDetails d) {
    var target = _index;
    if (_dragAccum < -_dragThreshold) {
      target += 1;
    } else if (_dragAccum > _dragThreshold) {
      target -= 1;
    }
    _animateTo(target.clamp(0, (_cards.length - 1).clamp(0, 1 << 30)));
  }

  void _animateTo(int target) {
    final anim = Tween<double>(begin: _focus, end: target.toDouble())
        .animate(CurvedAnimation(parent: _snapCtrl, curve: _snapCurve));
    void listener() => setState(() => _focus = anim.value);
    anim.addListener(listener);
    _snapCtrl
      ..reset()
      ..forward().whenComplete(() {
        anim.removeListener(listener);
        if (!mounted) return;
        setState(() {
          _index = target;
          _focus = target.toDouble();
        });
      });
  }

  /// Opens the Moment-reply camera: one photo, no caption, no destination
  /// pills, wired straight to THIS Moment (openCameraRoute's
  /// lockToMomentPostId). For a real Moment the unlock is then re-read from
  /// the server rather than assumed — returning from the camera no longer
  /// means the reply landed.
  Future<void> _openAddYours() async {
    await Navigator.of(context).push(
      openCameraRoute(
        lockToMomentPostId: _isReal ? widget.momentId : null,
      ),
    );
    if (!mounted) return;
    if (_isReal) {
      await _loadReal();
      if (!mounted) return;
      // Persist only what the server confirmed.
      if (_serverReplies.isNotEmpty) {
        await MomentPrefsService.setHasPosted(widget.momentId, true);
      }
      return;
    }
    // Demo Moments have nothing to confirm against — returning from the
    // capture flow is treated as "posted", as before.
    await MomentPrefsService.setHasPosted(widget.momentId, true);
    if (mounted) setState(() => _hasPosted = true);
  }

  @override
  Widget build(BuildContext context) {
    final revealed = _isAuthor || (_hasPosted ?? false);
    final cards = _cards;
    final n = cards.length;
    // The "N replies" / "Add yours" labels count contributions, never the
    // Moment's own photo card.
    final replyCount = _replyCount;

    return Scaffold(
      backgroundColor: _kMomentBg,
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(title: widget.title, onMenu: _isReal ? _openMenu : null),
            const SizedBox(height: 8),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragStart: _onDragStart,
                onHorizontalDragUpdate: _onDragUpdate,
                onHorizontalDragEnd: _onDragEnd,
                child: LayoutBuilder(
                  builder: (context, bc) {
                    _cardW = math.min(bc.maxWidth * 0.74, 330.0);
                    _cardH = math.min(bc.maxHeight * 0.94, _cardW * 1.44);
                    final centerX = (bc.maxWidth - _cardW) / 2;
                    final centerY = (bc.maxHeight - _cardH) / 2;
                    if (n == 0) {
                      return Center(
                        child: _loading
                            ? const CircularProgressIndicator(
                                strokeWidth: 2,
                                color: _kMomentMuted,
                              )
                            : Text(
                                'No one has added to this yet',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: 0.01 * 12.5,
                                  color: _kMomentMuted,
                                ),
                              ),
                      );
                    }
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        for (var i = 0; i < n; i++)
                          _buildCard(i, centerX, centerY, revealed, cards),
                      ],
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 18),
            _PageDots(count: n, index: _index, onTap: _animateTo),
            const SizedBox(height: 18),
            if (!revealed)
              _AddYoursBar(count: replyCount, onTap: _openAddYours)
            else
              // Revealed used to end in a muted "N replies" and nothing
              // else — dead space under the carousel, and no way to add
              // your own photo once you could see the others. This states
              // where you are (the Moment's author is told it's theirs) and
              // still offers Add yours to anyone who hasn't contributed.
              _RevealedBar(
                replyCount: replyCount,
                isAuthor: _isAuthor,
                canAddYours: _isReal && !_isAuthor && !_iContributed,
                onAddYours: _openAddYours,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(
    int i,
    double centerX,
    double centerY,
    bool revealed,
    List<MomentReply> cards,
  ) {
    final dist = (i - _focus).abs().clamp(0.0, 1.0);
    final scale = 1.0 - 0.1 * dist;
    final opacity = 1.0 - 0.22 * dist;
    final dx = centerX + (i - _focus) * _step;
    return Positioned(
      left: dx,
      top: centerY,
      width: _cardW,
      height: _cardH,
      child: Opacity(
        opacity: opacity,
        child: Transform.scale(
          scale: scale,
          child: _ReplyCard(
            reply: cards[i],
            // REVERSED, explicit instruction: the Moment's own photo used to
            // be exempt from the lock entirely ("it is the Moment, not a
            // reply to it") — now it follows the exact same rule as every
            // reply card. Anyone who is neither the author nor has already
            // contributed sees it blurred too, same as the replies below it,
            // and it unblurs the instant `revealed` flips true (they post, or
            // moment_is_revealed's own expiry clause kicks in) — no separate
            // state to manage, since `revealed` already IS that rule
            // (`_isAuthor || _hasPosted`, computed a few lines up from the
            // server-side moment_is_revealed()).
            revealed: revealed,
            // Still says "the Moment" once revealed — that label is about
            // what the card IS, not whether you may see it yet.
            isMomentPhoto: _isReal && i == 0 && _posterCard != null,
            index: i,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Single reply card — blurred/anonymous while locked, focus-pulls sharp
// with a staggered badge/name-pill pop-in once revealed.
// ---------------------------------------------------------------------------

class _ReplyCard extends StatefulWidget {
  const _ReplyCard({
    required this.reply,
    required this.revealed,
    required this.index,
    this.isMomentPhoto = false,
  });

  final MomentReply reply;
  final bool revealed;
  final int index;

  /// This is the Moment's own photo, not a contribution to it — gets an
  /// accent hairline and a labelled pill so it reads as the origin card.
  final bool isMomentPhoto;

  @override
  State<_ReplyCard> createState() => _ReplyCardState();
}

class _ReplyCardState extends State<_ReplyCard> {
  bool _staggerReady = false;

  @override
  void initState() {
    super.initState();
    if (widget.revealed) _armStagger();
  }

  @override
  void didUpdateWidget(_ReplyCard old) {
    super.didUpdateWidget(old);
    if (widget.revealed && !old.revealed) _armStagger();
  }

  void _armStagger() {
    Future.delayed(Duration(milliseconds: 60 * widget.index), () {
      if (mounted) setState(() => _staggerReady = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final showBadgeAndPill = widget.revealed && _staggerReady;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        // No border on the moment's own photo — reported as not wanted.
        // The "· the moment" name pill (below) still says which card this
        // is; the border was a second, redundant signal.
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: DecoratedBox(
        decoration: const BoxDecoration(color: Color(0xFF1E1B20)),
        child: widget.reply.isLockedPlaceholder
            ? const _LockedReplyPlaceholder()
            : Stack(
          fit: StackFit.expand,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 15.0, end: widget.revealed ? 0.0 : 15.0),
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOut,
              builder: (context, sigma, child) => ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
                child: ColorFiltered(
                  colorFilter: ColorFilter.matrix(
                    sigma > 0.5 ? _kDimMatrix : _kIdentityMatrix,
                  ),
                  child: child,
                ),
              ),
              child: CachedNetworkImage(
              memCacheWidth: 1080,
                imageUrl: widget.reply.photoUrl,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
              ),
            ),
            AnimatedOpacity(
              opacity: showBadgeAndPill ? 1 : 0,
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOut,
              child: AnimatedScale(
                scale: showBadgeAndPill ? 1 : 0.4,
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutBack,
                alignment: Alignment.topRight,
                child: Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    // Empty emoji renders as a bare blurred circle with
                    // nothing in it — the "something in the top right blob"
                    // that showed on every reply, because both real call
                    // sites construct MomentReply with emoji: '' (there is
                    // no per-reply emoji in the backend). Drawn only when
                    // there is actually something to draw.
                    child: widget.reply.emoji.trim().isEmpty
                        ? const SizedBox.shrink()
                        : _EmojiBadge(emoji: widget.reply.emoji),
                  ),
                ),
              ),
            ),
            // A photo with nothing but a name pill floating on it loses the
            // bottom of the image to whatever the photo happens to be — this
            // scrim gives the pill a ground to sit on at any brightness.
            IgnorePointer(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  height: 92,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.55),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            AnimatedOpacity(
              opacity: showBadgeAndPill ? 1 : 0,
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOut,
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: _NamePill(
                    name: widget.reply.name,
                    isMomentPhoto: widget.isMomentPhoto,
                  ),
                ),
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
// Locked reply placeholder — stands in for a contribution the viewer hasn't
// earned yet. Deliberately carries no photo at all: get_moment_replies
// never sends the real bytes to a locked viewer, so there is nothing here
// to blur — this is a drawn card, not a blurred photo, and stays exactly
// this way regardless of [revealed] (a placeholder is swapped out for the
// real card once the server actually hands over the reply; it never
// "reveals" itself).
// ---------------------------------------------------------------------------

class _LockedReplyPlaceholder extends StatelessWidget {
  const _LockedReplyPlaceholder();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2B2730), Color(0xFF1A1720)],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.08),
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.lock_rounded,
                size: 22,
                color: _kMomentMuted,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Reply to reveal',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: _kMomentMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmojiBadge extends StatelessWidget {
  const _EmojiBadge({required this.emoji});
  final String emoji;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _kMomentBg.withValues(alpha: 0.5),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.4),
              width: 1.5,
            ),
          ),
          child: Text(emoji, style: const TextStyle(fontSize: 20)),
        ),
      ),
    );
  }
}

class _NamePill extends StatelessWidget {
  const _NamePill({required this.name, this.isMomentPhoto = false});
  final String name;
  final bool isMomentPhoto;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isMomentPhoto
                ? _kMomentPink.withValues(alpha: 0.9)
                : _kMomentBg.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            isMomentPhoto ? '$name \u00b7 the moment' : name,
            // Was IBM Plex Mono — a code face, which made a username read as
            // terminal output (and rendered wide and loose at 11px). Plus
            // Jakarta is the app's own UI face, used by every other name.
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              color: _kMomentText,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.1,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Top bar — back / centered title / "···", all muted per spec (even the
// back chevron, unlike most of this app's other dark-chrome screens).
// ---------------------------------------------------------------------------

class _TopBar extends StatelessWidget {
  const _TopBar({required this.title, this.onMenu});
  final String title;

  /// Null on a demo Moment — there is no row to act on, so the affordance
  /// is hidden rather than shown doing nothing (which is what it did
  /// before: a bare '···' with no gesture attached).
  final VoidCallback? onMenu;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).maybePop(),
            child: const SizedBox(
              width: 44,
              height: 44,
              child: Icon(Icons.chevron_left, color: _kMomentMuted, size: 26),
            ),
          ),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.02 * 15,
                color: _kMomentText,
              ),
            ),
          ),
          GestureDetector(
            onTap: onMenu,
            behavior: HitTestBehavior.opaque,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Center(
                child: onMenu == null
                    ? const SizedBox.shrink()
                    : const Icon(
                        Icons.more_horiz_rounded,
                        color: _kMomentMuted,
                        size: 22,
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
// Page dots — tappable, active = 20px pink pill, inactive = 7px translucent
// circle.
// ---------------------------------------------------------------------------

class _PageDots extends StatelessWidget {
  const _PageDots({
    required this.count,
    required this.index,
    required this.onTap,
  });

  final int count;
  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          GestureDetector(
            onTap: () => onTap(i),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                width: i == index ? 20 : 7,
                height: 7,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: i == index
                      ? _kMomentPink
                      : Colors.white.withValues(alpha: 0.28),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Revealed-state bottom bar — says where you stand in this Moment, and
// keeps Add yours reachable for the one case where a revealed viewer still
// hasn't contributed (an expired Moment, which opens to everyone).
// ---------------------------------------------------------------------------

class _RevealedBar extends StatelessWidget {
  const _RevealedBar({
    required this.replyCount,
    required this.isAuthor,
    required this.canAddYours,
    required this.onAddYours,
  });

  final int replyCount;
  final bool isAuthor;
  final bool canAddYours;
  final VoidCallback onAddYours;

  @override
  Widget build(BuildContext context) {
    final count = replyCount == 0
        ? 'no replies yet'
        : '$replyCount repl${replyCount == 1 ? 'y' : 'ies'}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: Text(
              isAuthor ? 'Your moment \u00b7 $count' : count,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.01 * 12.5,
                color: _kMomentMuted,
              ),
            ),
          ),
          if (canAddYours) ...[
            const SizedBox(width: 12),
            GestureDetector(
              onTap: onAddYours,
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: _kMomentPinkCta,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Add yours',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.01 * 12.5,
                    color: Colors.white,
                  ),
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
// Locked-state bottom bar — the ONLY way to reveal replies. Removed
// entirely once revealed (see build()'s `else` branch above) — no toggle,
// no re-blur, per spec.
// ---------------------------------------------------------------------------

class _AddYoursBar extends StatelessWidget {
  const _AddYoursBar({required this.count, required this.onTap});
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 15),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            '📷  Add yours to reveal $count repl${count == 1 ? 'y' : 'ies'}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: _kMomentPinkCta,
            ),
          ),
        ),
      ),
    );
  }
}
