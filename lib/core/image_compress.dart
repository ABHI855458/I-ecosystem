import 'dart:io';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Compresses [source] down to thumbnail size — used anywhere a photo only
/// ever renders as a small circular thumbnail (face reactions, reaction
/// presets), never full-size, so there's no reason to upload/cache anything
/// larger than this. Shared by reaction_service.dart and
/// reaction_preset_service.dart rather than duplicated in each.
Future<File> compressForThumbnail(File source) async {
  final targetPath = p.join(Directory.systemTemp.path, '${_uuid.v4()}.jpg');
  final result = await FlutterImageCompress.compressAndGetFile(
    source.path,
    targetPath,
    minWidth: 240,
    minHeight: 240,
    quality: 70,
    format: CompressFormat.jpeg,
  );
  return File(result?.path ?? source.path);
}
