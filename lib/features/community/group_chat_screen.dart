import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/glass.dart' show showGlassToast;
import '../../services/chat_list_service.dart';
import '../../services/group_chat_service.dart';

import '../profile_v2/group_profile_v2_screen.dart';
import 'community_board/community_tokens.dart';
import 'community_chat_list.dart' show ChatAvatar;

// ---------------------------------------------------------------------------
// GroupChatScreen — a group's members-only chat (explicit request,
// 2026-10-03), opened from a GROUP row in the Community tab's WhatsApp-style
// chat list. Only members can read or send: enforced server-side by
// group_messages' RLS, not by this screen.
//
//  * WhatsApp-style bubbles — mine on the right, everyone else's on the
//    left with their photo + name at the start of each run.
//  * Day separators, newest at the bottom, live via realtime.
//  * "+" adds up to 6 photos to a message; tap a photo to view it big.
//  * Messages disappear after 48 hours (server-enforced).
//  * No priority here — that's communities only.
//  * Header → the group's profile. Long-press my own message → Unsend.
// ---------------------------------------------------------------------------

class GroupChatScreen extends StatefulWidget {
  const GroupChatScreen({super.key, required this.chat});

  final ChatSummary chat;

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  List<GroupMessage> _messages = const [];
  final List<GroupMessage> _pending = [];
  bool _loading = true;
  bool _loadingOlder = false;
  bool _hasMore = true;
  String? _error;
  StreamSubscription<dynamic>? _sub;
  Timer? _debounce;

  /// Photos picked with "+" for the next message.
  final List<XFile> _picked = [];

  String get _groupId => widget.chat.id;

  Future<void> _pickPhotos() async {
    final left = GroupChatService.maxPhotos - _picked.length;
    if (left <= 0) {
      showGlassToast(
        context,
        'Limit reached · ${GroupChatService.maxPhotos} photos per message',
        isError: true,
      );
      return;
    }
    try {
      final files = await ImagePicker().pickMultiImage(
        maxWidth: 1440,
        imageQuality: 85,
        limit: left,
      );
      if (!mounted || files.isEmpty) return;
      setState(() => _picked.addAll(files.take(left)));
    } catch (_) {
      if (mounted) {
        showGlassToast(context, "Couldn't open your photos.", isError: true);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
    _sub = GroupChatService.instance.watch(_groupId, () {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 250), _load);
    });
    _scroll.addListener(_maybeLoadOlder);
    _ctrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _sub?.cancel();
    _debounce?.cancel();
    _ctrl.dispose();
    _scroll.dispose();
    // Everything on screen has been seen.
    unawaited(ChatListService.instance.markOpened(widget.chat));
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final page = await GroupChatService.instance.fetch(_groupId);
      if (!mounted) return;
      setState(() {
        // Keep anything older I'd already paged in.
        final older = _messages.where(
          (m) => page.isNotEmpty && m.createdAt.isBefore(page.last.createdAt),
        );
        _messages = [...page, ...older];
        _loading = false;
        _error = null;
        if (page.length < 50 && older.isEmpty) _hasMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = "Couldn't load messages.";
      });
    }
  }

  Future<void> _maybeLoadOlder() async {
    // reverse: true — "older" is toward maxScrollExtent.
    if (_loadingOlder || !_hasMore || _messages.isEmpty) return;
    if (_scroll.position.pixels < _scroll.position.maxScrollExtent - 300) {
      return;
    }
    _loadingOlder = true;
    try {
      final older = await GroupChatService.instance.fetch(
        _groupId,
        before: _messages.last.createdAt,
      );
      if (!mounted) return;
      setState(() {
        _messages = [..._messages, ...older];
        if (older.length < 50) _hasMore = false;
      });
    } catch (_) {
      // Next scroll retries.
    } finally {
      _loadingOlder = false;
    }
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    final photos = List<XFile>.of(_picked);
    if (text.isEmpty && photos.isEmpty) return;
    HapticFeedback.lightImpact();
    final local = GroupMessage(
      id: 'local-${DateTime.now().microsecondsSinceEpoch}',
      senderId: 'me',
      senderName: 'You',
      body: text,
      createdAt: DateTime.now(),
      isMine: true,
      pending: true,
      localPhotos: [for (final p in photos) p.path],
    );
    setState(() {
      _pending.insert(0, local);
      _ctrl.clear();
      _picked.clear();
    });
    if (_scroll.hasClients) {
      unawaited(
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        ),
      );
    }
    try {
      await GroupChatService.instance.send(
        _groupId,
        text,
        photos: [for (final p in photos) File(p.path)],
      );
      await _load();
      if (mounted) setState(() => _pending.remove(local));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _pending.remove(local);
        // Hand the draft back so nothing is lost.
        if (_picked.isEmpty) _picked.addAll(photos);
      });
      if (_ctrl.text.isEmpty) _ctrl.text = text;
      showGlassToast(context, "Couldn't send — try again.", isError: true);
    }
  }

  /// Full-screen look at one photo (pinch to zoom); tap anywhere to close.
  void _viewPhoto(ImageProvider image) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black,
      builder: (ctx) => GestureDetector(
        onTap: () => Navigator.pop(ctx),
        child: InteractiveViewer(
          child: Center(
            child: Image(image: image, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }

  /// A message's photos: one = a big tile, more = a 2-column grid.
  Widget _photos(GroupMessage m) {
    final providers = <ImageProvider>[
      for (final u in m.photoUrls) CachedNetworkImageProvider(u),
      for (final p in m.localPhotos) FileImage(File(p)),
    ];
    if (providers.isEmpty) return const SizedBox.shrink();
    final width = MediaQuery.of(context).size.width * 0.62;
    Widget tile(ImageProvider p, double w, double h) => GestureDetector(
      onTap: m.pending ? null : () => _viewPhoto(p),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image(
          image: p,
          width: w,
          height: h,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => Container(
            width: w,
            height: h,
            color: CommunityColors.cardBg,
            child: const Icon(
              Icons.broken_image_outlined,
              color: CommunityColors.textDim,
            ),
          ),
        ),
      ),
    );
    if (providers.length == 1) {
      return tile(providers.first, width, width * 1.15);
    }
    final cell = (width - 4) / 2;
    return SizedBox(
      width: width,
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [for (final p in providers) tile(p, cell, cell)],
      ),
    );
  }

  Future<void> _confirmUnsend(GroupMessage m) async {
    HapticFeedback.mediumImpact();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: CommunityColors.popoverBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: ListTile(
          leading: const Icon(Icons.undo_rounded, color: CommunityColors.pink),
          title: Text(
            'Unsend message',
            style: GoogleFonts.inter(
              color: CommunityColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          onTap: () => Navigator.pop(ctx, true),
        ),
      ),
    );
    if (ok != true) return;
    try {
      await GroupChatService.instance.unsend(m.id);
      await _load();
    } catch (_) {
      if (mounted) {
        showGlassToast(context, "Couldn't unsend.", isError: true);
      }
    }
  }

  void _openProfile() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GroupProfileV2Screen(groupId: _groupId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final all = [..._pending, ..._messages];
    return Scaffold(
      backgroundColor: CommunityColors.screenBg,
      body: SafeArea(
        child: Column(
          children: [
            _header(),
            // No priority in a group chat (explicit request, 2026-10-03) —
            // priority is a communities-only thing.
            Expanded(
              child: _loading && all.isEmpty
                  ? const Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: CommunityColors.pink,
                      ),
                    )
                  : all.isEmpty
                  ? _emptyState()
                  : ListView.builder(
                      controller: _scroll,
                      reverse: true,
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                      itemCount: all.length,
                      itemBuilder: (_, i) => _row(all, i),
                    ),
            ),
            _composer(),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    final c = widget.chat;
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 6, 12, 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: CommunityColors.tabDivider)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 20,
              color: CommunityColors.textPrimary,
            ),
          ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _openProfile,
              child: Row(
                children: [
                  // Same picture as the chat list row — the group's DP, or
                  // its members' faces when it has none.
                  ChatAvatar(chat: c, size: 40),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          c.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: CommunityType.wordmark.copyWith(fontSize: 17),
                        ),
                        Text(
                          '${c.memberCount} members · messages vanish after 48h',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: CommunityType.subline,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Text(
        _error ??
            'No messages yet.\nSay hi to ${widget.chat.name}.\n\n'
                'Only members can see this chat, and messages\n'
                'disappear after 48 hours.',
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(
          fontSize: 13.5,
          color: CommunityColors.textDim,
          height: 1.5,
        ),
      ),
    ),
  );

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _dayLabel(DateTime d) {
    final now = DateTime.now();
    if (_sameDay(d, now)) return 'Today';
    if (_sameDay(d, now.subtract(const Duration(days: 1)))) return 'Yesterday';
    if (now.difference(d).inDays < 7) return DateFormat('EEEE').format(d);
    return DateFormat('d MMM yyyy').format(d);
  }

  /// [all] is newest-first (reverse list): index+1 is the OLDER neighbour.
  Widget _row(List<GroupMessage> all, int i) {
    final m = all[i];
    final older = i + 1 < all.length ? all[i + 1] : null;
    final newer = i > 0 ? all[i - 1] : null;
    final newDay = older == null || !_sameDay(older.createdAt, m.createdAt);
    final startsRun =
        newDay || older.senderId != m.senderId || older.isMine != m.isMine;
    final endsRun =
        newer == null ||
        newer.senderId != m.senderId ||
        newer.isMine != m.isMine ||
        !_sameDay(newer.createdAt, m.createdAt);
    return Column(
      children: [
        if (newDay)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: CommunityColors.cardBg2,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _dayLabel(m.createdAt),
                style: CommunityType.sectionMeta,
              ),
            ),
          ),
        Padding(
          padding: EdgeInsets.only(top: startsRun ? 8 : 2),
          child: m.isMine ? _mine(m, endsRun) : _theirs(m, startsRun, endsRun),
        ),
      ],
    );
  }

  Widget _time(GroupMessage m, {required bool mine}) => Text(
    m.pending ? 'sending…' : DateFormat('h:mm a').format(m.createdAt),
    style: GoogleFonts.inter(
      fontSize: 10,
      color: mine
          ? Colors.white.withValues(alpha: 0.7)
          : CommunityColors.textDim,
    ),
  );

  Widget _mine(GroupMessage m, bool endsRun) => Align(
    alignment: Alignment.centerRight,
    child: GestureDetector(
      onLongPress: m.pending ? null : () => _confirmUnsend(m),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.76,
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(13, 9, 11, 7),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFA2D64), Color(0xFFD1406E)],
            ),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: const Radius.circular(18),
              bottomRight: Radius.circular(endsRun ? 5 : 18),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (m.photoUrls.isNotEmpty || m.localPhotos.isNotEmpty) ...[
                _photos(m),
                const SizedBox(height: 6),
              ],
              if (m.body.trim().isNotEmpty)
                Text(
                  m.body,
                  style: GoogleFonts.inter(
                    fontSize: 14.5,
                    color: Colors.white,
                    height: 1.35,
                  ),
                ),
              const SizedBox(height: 3),
              _time(m, mine: true),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _theirs(GroupMessage m, bool startsRun, bool endsRun) {
    final url = m.senderAvatar;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        SizedBox(
          width: 30,
          child: endsRun
              ? CircleAvatar(
                  radius: 14,
                  backgroundColor: const Color(0xFF26262F),
                  backgroundImage: url == null || url.isEmpty
                      ? null
                      : CachedNetworkImageProvider(url),
                  child: url == null || url.isEmpty
                      ? Text(
                          m.senderName.isEmpty
                              ? '?'
                              : m.senderName[0].toUpperCase(),
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        )
                      : null,
                )
              : null,
        ),
        const SizedBox(width: 6),
        ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.72,
          ),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 7),
            decoration: BoxDecoration(
              color: CommunityColors.cardBg2,
              border: Border.all(color: CommunityColors.cardBorder),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18),
                topRight: const Radius.circular(18),
                bottomRight: const Radius.circular(18),
                bottomLeft: Radius.circular(endsRun ? 5 : 18),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (startsRun) ...[
                  Text(
                    m.senderName,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: CommunityColors.lime,
                    ),
                  ),
                  const SizedBox(height: 2),
                ],
                if (m.photoUrls.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  _photos(m),
                  const SizedBox(height: 6),
                ],
                if (m.body.trim().isNotEmpty)
                  Text(
                    m.body,
                    style: GoogleFonts.inter(
                      fontSize: 14.5,
                      color: CommunityColors.textBody,
                      height: 1.35,
                    ),
                  ),
                const SizedBox(height: 3),
                _time(m, mine: false),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Picked photos waiting to go with the next message, each removable.
  Widget _pickedStrip() => SizedBox(
    height: 76,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 4),
      itemCount: _picked.length,
      separatorBuilder: (_, _) => const SizedBox(width: 8),
      itemBuilder: (_, i) => Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              File(_picked[i].path),
              width: 64,
              height: 64,
              fit: BoxFit.cover,
            ),
          ),
          Positioned(
            top: -6,
            right: -6,
            child: GestureDetector(
              onTap: () => setState(() => _picked.removeAt(i)),
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF26262F),
                  border: Border.all(color: CommunityColors.screenBg, width: 2),
                ),
                child: const Icon(
                  Icons.close_rounded,
                  size: 13,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _composer() {
    final canSend = _ctrl.text.trim().isNotEmpty || _picked.isNotEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_picked.isNotEmpty) _pickedStrip(),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.fromLTRB(6, 4, 16, 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF17171E),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0x14FFFFFF)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // "+" — add photos (explicit request, 2026-10-03).
                      IconButton(
                        onPressed: _pickPhotos,
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(
                          Icons.add_rounded,
                          size: 26,
                          color: CommunityColors.textSecondary,
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          child: TextField(
                            controller: _ctrl,
                            minLines: 1,
                            maxLines: 5,
                            maxLength: GroupChatService.maxLength,
                            textCapitalization: TextCapitalization.sentences,
                            style: GoogleFonts.inter(
                              fontSize: 15,
                              color: CommunityColors.textPrimary,
                            ),
                            cursorColor: CommunityColors.pink,
                            // Explicit zero padding: the app theme's contentPadding
                            // leaks into collapsed fields (known gotcha).
                            // The app theme's filled + outlined input style drew a white
                            // rounded box INSIDE this pill (explicit report, 2026-10-03:
                            // "why is there a circle inside the box ... remove it") —
                            // every border/fill the theme could supply is off here.
                            decoration: InputDecoration(
                              hintText: 'Message ${widget.chat.name}',
                              hintStyle: GoogleFonts.inter(
                                fontSize: 15,
                                color: CommunityColors.textDimmer,
                              ),
                              counterText: '',
                              isDense: true,
                              isCollapsed: true,
                              contentPadding: EdgeInsets.zero,
                              filled: false,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              disabledBorder: InputBorder.none,
                              errorBorder: InputBorder.none,
                              focusedErrorBorder: InputBorder.none,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: canSend ? _send : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: canSend
                        ? CommunityColors.pink
                        : const Color(0xFF1C1C23),
                  ),
                  child: Icon(
                    Icons.send_rounded,
                    size: 20,
                    color: canSend
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.35),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
