import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../services/chat_list_service.dart';
import 'community_board/community_tokens.dart';

// ---------------------------------------------------------------------------
// CommunityChatList — the Community tab's landing view: every community and
// group as a WhatsApp-style chat row (explicit request, 2026-10-02/03: "in
// community make chat like thing like WhatsApp ... for communities and as
// well groups ... same as priority and normal chats").
//
// Two sections, the same split the community board itself uses:
//   PRIORITY — a priority notice I haven't opened yet, or a group ping still
//              waiting on my answer;
//   CHATS    — everything else, newest activity first.
// Row: avatar · name + time · last message + unread dot.
// ---------------------------------------------------------------------------

class CommunityChatList extends StatelessWidget {
  const CommunityChatList({
    super.key,
    required this.chats,
    required this.loading,
    required this.error,
    required this.onOpen,
    required this.onRefresh,
    this.bottomPadding = 140,
  });

  final List<ChatSummary> chats;
  final bool loading;
  final String? error;
  final ValueChanged<ChatSummary> onOpen;
  final Future<void> Function() onRefresh;

  /// Room for the floating tab bar.
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    if (loading && chats.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: CommunityColors.pink,
        ),
      );
    }
    final priority = [for (final c in chats) if (c.isPriority) c];
    final normal = [for (final c in chats) if (!c.isPriority) c];
    return RefreshIndicator(
      onRefresh: onRefresh,
      color: CommunityColors.pink,
      child: ListView(
        primary: false,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(top: 4, bottom: bottomPadding),
        children: [
          if (error != null && chats.isEmpty)
            _Empty(text: error!)
          else if (chats.isEmpty)
            const _Empty(
              text: 'No chats yet.\nJoin a community or make a group to start.',
            ),
          if (priority.isNotEmpty) ...[
            _SectionLabel(
              label: 'PRIORITY',
              color: CommunityColors.amber,
              count: priority.length,
            ),
            for (final c in priority)
              _ChatRow(chat: c, priority: true, onTap: () => onOpen(c)),
          ],
          if (normal.isNotEmpty) ...[
            _SectionLabel(
              label: 'CHATS',
              color: CommunityColors.textDim,
              count: normal.length,
            ),
            for (final c in normal) _ChatRow(chat: c, onTap: () => onOpen(c)),
          ],
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.label,
    required this.color,
    required this.count,
  });
  final String label;
  final Color color;
  final int count;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
    child: Row(
      children: [
        Text(label, style: CommunityType.sectionLabel(color)),
        const SizedBox(width: 8),
        Text('$count', style: CommunityType.sectionMeta),
      ],
    ),
  );
}

class _ChatRow extends StatelessWidget {
  const _ChatRow({
    required this.chat,
    required this.onTap,
    this.priority = false,
  });
  final ChatSummary chat;
  final VoidCallback onTap;
  final bool priority;

  static String timeLabel(DateTime? at) {
    if (at == null) return '';
    final local = at.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return DateFormat('h:mm a').format(local);
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return DateFormat('EEEE').format(local);
    return DateFormat('d/M/yy').format(local);
  }

  @override
  Widget build(BuildContext context) {
    final unread = chat.unread || priority;
    final accent = priority ? CommunityColors.amber : CommunityColors.lime;
    final isGroup = chat.kind == ChatKind.group;
    final preview = chat.lastText?.trim().isNotEmpty == true
        ? chat.lastText!.trim()
        : (isGroup ? 'No messages yet' : 'Say hi to the community');
    return InkWell(
      onTap: onTap,
      splashColor: Colors.white.withValues(alpha: 0.04),
      highlightColor: Colors.white.withValues(alpha: 0.03),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
        child: Row(
          children: [
            _Avatar(chat: chat, ring: priority ? accent : null),
            const SizedBox(width: 13),
            Expanded(
              child: Container(
                padding: const EdgeInsets.only(bottom: 12),
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: CommunityColors.tabDivider),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            chat.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w700,
                              color: CommunityColors.textBright,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          timeLabel(chat.lastAt),
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: unread ? FontWeight.w700 : FontWeight.w400,
                            color: unread ? accent : CommunityColors.textDim,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (priority) ...[
                          Icon(
                            isGroup
                                ? Icons.notifications_active_rounded
                                : Icons.campaign_rounded,
                            size: 14,
                            color: accent,
                          ),
                          const SizedBox(width: 5),
                        ],
                        Expanded(
                          child: Text(
                            preview,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
                              color: unread
                                  ? CommunityColors.textMuted2
                                  : CommunityColors.textSecondary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _KindTag(isGroup: isGroup),
                        if (unread) ...[
                          const SizedBox(width: 8),
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KindTag extends StatelessWidget {
  const _KindTag({required this.isGroup});
  final bool isGroup;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: CommunityColors.chipBorder),
    ),
    child: Text(
      isGroup ? 'GROUP' : 'COMMUNITY',
      style: CommunityType.pollTag,
    ),
  );
}

/// A chat's picture — the community's / group's own DP when it has one.
/// A group WITHOUT a DP shows its members' faces stacked, exactly how the
/// Ping page draws that group (explicit request, 2026-10-03: "the dp shall
/// be same as group dp"); only with no photos at all does it fall back to
/// the initial. Shared by the chat list and GroupChatScreen's header.
class ChatAvatar extends StatelessWidget {
  const ChatAvatar({super.key, required this.chat, this.size = 52});
  final ChatSummary chat;
  final double size;

  Widget _initial(bool isGroup) => Container(
    alignment: Alignment.center,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isGroup
            ? const [Color(0xFF2A3A6B), Color(0xFF16203D)]
            : const [Color(0xFF4A2433), Color(0xFF221218)],
      ),
    ),
    child: Text(
      chat.name.isEmpty ? '?' : chat.name[0].toUpperCase(),
      style: GoogleFonts.inter(
        fontSize: size * 0.38,
        fontWeight: FontWeight.w800,
        color: Colors.white,
      ),
    ),
  );

  Widget _photo(String url, Widget fallback) => CachedNetworkImage(
    imageUrl: url,
    fit: BoxFit.cover,
    memCacheWidth: (size * 3).round(),
    errorWidget: (_, _, _) => fallback,
  );

  @override
  Widget build(BuildContext context) {
    final isGroup = chat.kind == ChatKind.group;
    final fallback = _initial(isGroup);
    final url = chat.iconUrl;
    if (url != null && url.isNotEmpty) {
      return SizedBox(
        width: size,
        height: size,
        child: ClipOval(child: _photo(url, fallback)),
      );
    }
    final faces = isGroup ? chat.memberAvatars : const <String>[];
    if (faces.isEmpty) {
      return SizedBox(width: size, height: size, child: ClipOval(child: fallback));
    }
    if (faces.length == 1) {
      return SizedBox(
        width: size,
        height: size,
        child: ClipOval(child: _photo(faces.first, fallback)),
      );
    }
    // Two overlapping faces: back one top-left, front one bottom-right with
    // a ring in the screen colour so the overlap reads cleanly.
    final face = size * 0.66;
    Widget circle(String u) => Container(
      width: face,
      height: face,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: CommunityColors.screenBg, width: 2),
      ),
      child: ClipOval(child: _photo(u, fallback)),
    );
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          Positioned(left: 0, top: 0, child: circle(faces[0])),
          Positioned(right: 0, bottom: 0, child: circle(faces[1])),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.chat, this.ring});
  final ChatSummary chat;
  final Color? ring;

  @override
  Widget build(BuildContext context) {
    final face = ChatAvatar(chat: chat);
    if (ring == null) return face;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: ring!, width: 2),
      ),
      child: face,
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(32, 80, 32, 0),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: GoogleFonts.inter(
        fontSize: 13.5,
        color: CommunityColors.textDim,
        height: 1.5,
      ),
    ),
  );
}
