import 'dart:io';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class MemoryService {
  MemoryService._();
  static final instance = MemoryService._();

  final _sb = Supabase.instance.client;
  final _uuid = const Uuid();

  Future<String> _uploadPhoto(
      String userId, String memoryId, String localPath) async {
    final targetPath =
        p.join(Directory.systemTemp.path, '${_uuid.v4()}.jpg');
    final compressed = await FlutterImageCompress.compressAndGetFile(
      localPath,
      targetPath,
      format: CompressFormat.jpeg,
      quality: 88,
    );
    final fileToUpload = File(compressed?.path ?? localPath);
    final storagePath = '$userId/$memoryId/${_uuid.v4()}.jpg';
    await _sb.storage.from('memories').upload(storagePath, fileToUpload);
    return storagePath;
  }

  Future<void> createMemory({
    required String layoutId,
    required List<String> photoPaths,
    required bool isDraft,
    String backgroundVariant = 'default',
  }) async {
    final userId = _sb.auth.currentUser!.id;
    final memoryId = _uuid.v4();

    final uploaded = <String>[];
    for (final path in photoPaths) {
      uploaded.add(await _uploadPhoto(userId, memoryId, path));
    }

    await _sb.from('memories').insert({
      'id': memoryId,
      'user_id': userId,
      'layout_id': layoutId,
      'background_variant': backgroundVariant,
      'photos': uploaded,
      'is_draft': isDraft,
    });

    if (!isDraft) {
      await _sb.from('posts').insert({
        'user_id': userId,
        'post_type': 'memory',
        'memory_id': memoryId,
      });
    }
  }

  Future<List<Map<String, dynamic>>> myMemories() async {
    try {
      final userId = _sb.auth.currentUser?.id;
      if (userId == null) return [];
      final rows = await _sb
          .from('memories')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .timeout(const Duration(seconds: 8));
      return List<Map<String, dynamic>>.from(rows as List);
    } catch (_) {
      return [];
    }
  }

  String publicUrl(String storagePath) =>
      _sb.storage.from('memories').getPublicUrl(storagePath);

  Future<void> deleteMemory(String memoryId) async {
    await _sb.from('memories').delete().eq('id', memoryId);
  }

  Future<void> postDraft(String memoryId) async {
    final userId = _sb.auth.currentUser!.id;
    await _sb
        .from('memories')
        .update({'is_draft': false}).eq('id', memoryId);
    await _sb.from('posts').insert({
      'user_id': userId,
      'post_type': 'memory',
      'memory_id': memoryId,
    });
  }
}
