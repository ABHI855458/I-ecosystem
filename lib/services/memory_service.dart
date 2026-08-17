import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'current_user_service.dart';

class MemoryService {
  MemoryService._();
  static final instance = MemoryService._();

  // Must match the real Supabase Storage bucket id exactly — bucket ids are
  // case-sensitive, and the project's bucket is "Memories" (capital M).
  static const _bucket = 'Memories';

  final _sb = Supabase.instance.client;
  final _uuid = const Uuid();

  Future<String> _uploadPhoto(
      String userId, String memoryId, String localPath) async {
    final targetPath =
        p.join(Directory.systemTemp.path, '${_uuid.v4()}.jpg');
    try {
      final compressed = await FlutterImageCompress.compressAndGetFile(
        localPath,
        targetPath,
        format: CompressFormat.jpeg,
        quality: 88,
      );
      final fileToUpload = File(compressed?.path ?? localPath);
      final storagePath = '$userId/$memoryId/${_uuid.v4()}.jpg';
      await _sb.storage.from(_bucket).upload(storagePath, fileToUpload);
      return storagePath;
    } catch (e, st) {
      debugPrint('MemoryService._uploadPhoto failed: $e\n$st');
      rethrow;
    }
  }

  Future<void> createMemory({
    required String layoutId,
    required List<String> photoPaths,
    required bool isDraft,
    String backgroundVariant = 'default',
  }) async {
    try {
      final userId = await CurrentUserService.instance.resolveId();
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
    } catch (e, st) {
      debugPrint('MemoryService.createMemory failed: $e\n$st');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> myMemories() async {
    try {
      final userId = await CurrentUserService.instance.resolveId();
      final rows = await _sb
          .from('memories')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .timeout(const Duration(seconds: 8));
      return List<Map<String, dynamic>>.from(rows as List);
    } catch (e, st) {
      debugPrint('MemoryService.myMemories failed: $e\n$st');
      rethrow;
    }
  }

  String publicUrl(String storagePath) =>
      _sb.storage.from(_bucket).getPublicUrl(storagePath);

  Future<void> deleteMemory(String memoryId) async {
    try {
      await _sb.from('memories').delete().eq('id', memoryId);
    } catch (e, st) {
      debugPrint('MemoryService.deleteMemory failed: $e\n$st');
      rethrow;
    }
  }

  Future<void> postDraft(String memoryId) async {
    try {
      final userId = await CurrentUserService.instance.resolveId();
      await _sb
          .from('memories')
          .update({'is_draft': false}).eq('id', memoryId);
      await _sb.from('posts').insert({
        'user_id': userId,
        'post_type': 'memory',
        'memory_id': memoryId,
      });
    } catch (e, st) {
      debugPrint('MemoryService.postDraft failed: $e\n$st');
      rethrow;
    }
  }
}
