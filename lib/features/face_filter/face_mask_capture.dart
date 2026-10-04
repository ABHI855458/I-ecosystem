import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show rootBundle;
import 'package:image_picker/image_picker.dart' show XFile;

import 'face_mask_presets.dart';
import 'face_mask_transform.dart';

// ---------------------------------------------------------------------------
// Bakes the mask into the captured photo file, same dart:ui Canvas approach
// (decode -> PictureRecorder -> drawImageRect with transforms -> re-encode)
// dual_photo_compositor.dart already uses for the BeReal-style composite, so
// the two live side by side without a second, differently-built image
// pipeline. On any failure, returns the original photo untouched — a failed
// bake should never block posting.
// ---------------------------------------------------------------------------

Future<XFile> bakeFaceMaskIntoPhoto({
  required XFile photo,
  required String maskAssetPath,
  required FaceMaskTransform transform,
  required ui.Size analysisImageSize,
  required bool mirrored,
  FaceMaskAnchor? anchor,
}) async {
  try {
    final photoBytes = await File(photo.path).readAsBytes();
    final photoCodec = await ui.instantiateImageCodec(photoBytes);
    final photoImage = (await photoCodec.getNextFrame()).image;

    final maskBytes = await rootBundle.load(maskAssetPath);
    final maskCodec = await ui.instantiateImageCodec(
      maskBytes.buffer.asUint8List(),
    );
    final maskImage = (await maskCodec.getNextFrame()).image;

    final photoW = photoImage.width.toDouble();
    final photoH = photoImage.height.toDouble();

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawImageRect(
      photoImage,
      ui.Rect.fromLTWH(0, 0, photoW, photoH),
      ui.Rect.fromLTWH(0, 0, photoW, photoH),
      ui.Paint(),
    );

    // The SAME placement maths the live overlay uses — see
    // computeMaskPlacement. This function used to compute its own, and
    // missed every fix the overlay got (eye anchoring, the iOS mirror,
    // eye-based sizing), plus scaled by height alone so any aspect
    // difference between the analysis frame and the captured JPEG shifted
    // the mask sideways. That is why the preview tracked correctly and the
    // saved photo put the mask somewhere else.
    final placement = computeMaskPlacement(
      transform: transform,
      analysisImageSize: analysisImageSize,
      targetSize: ui.Size(photoW, photoH),
      maskAspect: maskImage.width / maskImage.height,
      mirrored: mirrored,
      anchor: anchor,
    );
    if (placement == null) {
      photoImage.dispose();
      maskImage.dispose();
      return photo;
    }

    canvas.save();
    canvas.translate(placement.center.dx, placement.center.dy);
    canvas.rotate(placement.rotation);
    canvas.drawImageRect(
      maskImage,
      ui.Rect.fromLTWH(
        0,
        0,
        maskImage.width.toDouble(),
        maskImage.height.toDouble(),
      ),
      ui.Rect.fromCenter(
        center: ui.Offset.zero,
        width: placement.width,
        height: placement.height,
      ),
      ui.Paint()
        ..filterQuality = ui.FilterQuality.high
        ..isAntiAlias = true,
    );
    canvas.restore();

    final picture = recorder.endRecording();
    final composite = await picture.toImage(photoW.toInt(), photoH.toInt());
    final pngData = await composite.toByteData(format: ui.ImageByteFormat.png);

    photoImage.dispose();
    maskImage.dispose();
    composite.dispose();

    final dir = File(photo.path).parent;
    final outPath =
        '${dir.path}/masked_${DateTime.now().millisecondsSinceEpoch}.png';
    await File(outPath).writeAsBytes(pngData!.buffer.asUint8List());
    return XFile(outPath);
  } catch (_) {
    return photo;
  }
}
