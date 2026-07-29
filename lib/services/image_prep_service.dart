import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img_lib;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

/// Downscales picked photos to a max of 1600px on the long edge, off the
/// main isolate, before they ever touch a canvas or get uploaded. This is
/// what fixes the freeze that used to happen when the layout picker decoded
/// several full-resolution photos at once for its chip thumbnails.
class ImagePrepService {
  ImagePrepService._();
  static final instance = ImagePrepService._();

  static const _maxEdge = 1600;
  static const _quality = 90;
  final _uuid = const Uuid();

  /// Returns a downscaled JPEG file, or null if it couldn't be prepared
  /// within [timeout] (caller should show a recoverable error, not hang).
  Future<File?> prepareForStudio(
    String sourcePath, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    try {
      return await _prepare(sourcePath).timeout(timeout);
    } catch (_) {
      return null;
    }
  }

  Future<File> _prepare(String sourcePath) async {
    final bytes = await File(sourcePath).readAsBytes();

    Uint8List? processed;
    try {
      processed = await compute(_decodeResizeEncode, bytes);
    } catch (_) {
      processed = null;
    }

    processed ??= await _nativeFallback(sourcePath);

    final out = File(p.join(Directory.systemTemp.path, '${_uuid.v4()}.jpg'));
    await out.writeAsBytes(processed);
    return out;
  }

  /// Native (platform-channel) decode/resize/encode — only used when the
  /// pure-Dart isolate path can't decode the source format (e.g. a HEIC
  /// that slipped through without being re-encoded by the picker).
  Future<Uint8List> _nativeFallback(String sourcePath) async {
    final result = await FlutterImageCompress.compressWithFile(
      sourcePath,
      minWidth: _maxEdge,
      minHeight: _maxEdge,
      quality: _quality,
      format: CompressFormat.jpeg,
      keepExif: false,
    );
    if (result == null) {
      throw StateError('Native image compression failed for $sourcePath');
    }
    return result;
  }
}

/// Runs in a background isolate via [compute] — pure Dart, no platform
/// channels, safe to run off the main isolate.
Uint8List _decodeResizeEncode(Uint8List bytes) {
  final decoded = img_lib.decodeImage(bytes);
  if (decoded == null) {
    throw const FormatException('Unsupported image format');
  }

  final longEdge = decoded.width > decoded.height ? decoded.width : decoded.height;
  final resized = longEdge > ImagePrepService._maxEdge
      ? img_lib.copyResize(
          decoded,
          width: decoded.width >= decoded.height ? ImagePrepService._maxEdge : null,
          height: decoded.height > decoded.width ? ImagePrepService._maxEdge : null,
          interpolation: img_lib.Interpolation.average,
        )
      : decoded;

  return Uint8List.fromList(img_lib.encodeJpg(resized, quality: ImagePrepService._quality));
}
