import 'dart:async';
import 'dart:io';

import '../core/supabase_config.dart';
import 'current_user_service.dart';
import 'storage_service.dart';

// ---------------------------------------------------------------------------
// GroupChatService — members-only group chat (explicit request, 2026-10-03),
// opened from the Community tab's chat list. Backed by `group_messages`
// (20261003020000_group_messages.sql): RLS lets only the group's members
// read or send; group_messages_page() joins in sender names/photos.
// ---------------------------------------------------------------------------

class GroupMessage {
  const GroupMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.body,
    required this.createdAt,
    required this.isMine,
    this.senderAvatar,
    this.pending = false,
    this.photoUrls = const [],
    this.localPhotos = const [],
  });

  /// Up to [GroupChatService.maxPhotos] photos sent with the message.
  final List<String> photoUrls;

  /// Optimistic only: the picked files, shown until the upload lands.
  final List<String> localPhotos;

  final String id;
  final String senderId;
  final String senderName;
  final String? senderAvatar;
  final String body;
  final DateTime createdAt;
  final bool isMine;

  /// Optimistic local row, not yet confirmed by the server.
  final bool pending;

  factory GroupMessage.fromRow(Map<String, dynamic> r) => GroupMessage(
    id: r['id'] as String,
    senderId: r['sender_id'] as String,
    senderName: (r['sender_name'] as String?) ?? 'Member',
    senderAvatar: r['sender_avatar'] as String?,
    body: (r['body'] as String?) ?? '',
    createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
    isMine: r['is_mine'] == true,
    photoUrls: [
      for (final u in (r['photo_urls'] as List?) ?? const [])
        if (u is String && u.isNotEmpty) u,
    ],
  );
}

class GroupChatService {
  GroupChatService._();
  static final instance = GroupChatService._();

  static const maxLength = 1000;
  static const maxPhotos = 6;

  /// Messages disappear after this (explicit request, 2026-10-03: "let
  /// group chat go off after 48 hrs") — enforced server-side; this is for
  /// the UI's own wording.
  static const lifetime = Duration(hours: 48);

  /// Newest first. [before] pages further back.
  Future<List<GroupMessage>> fetch(
    String groupId, {
    DateTime? before,
    int limit = 50,
  }) async {
    final rows = await supabase
        .rpc(
          'group_messages_page',
          params: {
            'p_group': groupId,
            'p_before': before?.toUtc().toIso8601String(),
            'p_limit': limit,
          },
        )
        .timeout(const Duration(seconds: 10)) as List;
    return rows
        .cast<Map<String, dynamic>>()
        .map(GroupMessage.fromRow)
        .toList();
  }

  /// Text, photos, or both. Photos upload first (in parallel); if any
  /// upload fails the whole send throws, so nothing half-sent appears.
  Future<void> send(
    String groupId,
    String body, {
    List<File> photos = const [],
  }) async {
    final text = body.trim();
    if (text.isEmpty && photos.isEmpty) return;
    final me = await CurrentUserService.instance.resolveId();
    final urls = await Future.wait([
      for (var i = 0; i < photos.length && i < maxPhotos; i++)
        StorageService.uploadGroupChatPhoto(
          file: photos[i],
          groupId: groupId,
          userId: me,
          index: i,
        ),
    ]);
    if (urls.any((u) => u == null)) {
      throw StateError('photo upload failed');
    }
    await supabase.from('group_messages').insert({
      'group_id': groupId,
      'sender_id': me,
      'body': text.length > maxLength ? text.substring(0, maxLength) : text,
      'photo_urls': urls.cast<String>(),
    });
  }

  /// "Unsend" my own message (soft delete; RLS allows only the sender).
  Future<void> unsend(String messageId) async {
    await supabase
        .from('group_messages')
        .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', messageId);
  }

  /// Fires whenever this group's messages change (RLS-filtered, so only a
  /// member ever receives anything). The caller refetches.
  StreamSubscription<List<Map<String, dynamic>>> watch(
    String groupId,
    void Function() onChange,
  ) {
    return supabase
        .from('group_messages')
        .stream(primaryKey: ['id'])
        .eq('group_id', groupId)
        .order('created_at', ascending: false)
        .limit(1)
        .listen((_) => onChange(), onError: (_) {});
  }
}
