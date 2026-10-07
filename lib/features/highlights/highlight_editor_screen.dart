import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../../core/glass.dart' show showGlassToast;
import '../../services/highlight_service.dart';
import '../composer/video_capture.dart' show makeVideoPoster;
import '../profile_v2/profile_v2_tokens.dart';
import 'highlight_models.dart';
import 'polaroid_cover.dart';

// ---------------------------------------------------------------------------
// Make or edit a highlight: pick photos (and short videos) from the phone,
// name it, save.
//
// The polaroid at the top is the real thing being made — it shows the cover
// photo and the name as they are typed, so there is nothing to imagine.
// ---------------------------------------------------------------------------

/// One at a time: several reads/uploads run before this closes, and a fast
/// double tap on a "+ New" tile opened two editors.
bool _editorOpen = false;

/// Opens the editor. [existing] null starts a new highlight (and opens the
/// gallery straight away). Returns true when something was saved or
/// deleted.
Future<bool> openHighlightEditor(
  BuildContext context, {
  Highlight? existing,
}) async {
  if (_editorOpen) return false;
  _editorOpen = true;
  try {
    final result = await Navigator.of(context, rootNavigator: true)
        .push<String>(
          MaterialPageRoute<String>(
            fullscreenDialog: true,
            builder: (_) => HighlightEditorScreen(existing: existing),
          ),
        );
    if (result == null) return false;
    if (context.mounted) showGlassToast(context, result);
    return true;
  } finally {
    _editorOpen = false;
  }
}

class HighlightEditorScreen extends StatefulWidget {
  const HighlightEditorScreen({super.key, this.existing});

  final Highlight? existing;

  @override
  State<HighlightEditorScreen> createState() => _HighlightEditorScreenState();
}

class _HighlightEditorScreenState extends State<HighlightEditorScreen> {
  late final _title = TextEditingController(
    text: widget.existing?.title ?? '',
  );
  late final List<HighlightDraftPhoto> _photos = [
    for (final p in widget.existing?.photos ?? const <HighlightPhoto>[])
      HighlightDraftPhoto.saved(
        postId: p.postId,
        url: p.url,
        isVideo: p.isVideo,
      ),
  ];
  final _picker = ImagePicker();

  bool _picking = false;
  bool _saving = false;
  int _done = 0;
  int _total = 0;

  bool get _isNew => widget.existing == null;
  int get _room => HighlightService.maxPhotos - _photos.length;
  bool get _canSave =>
      !_saving && _photos.isNotEmpty && _title.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    if (_isNew) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _addFromGallery());
    }
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _addFromGallery() async {
    if (_picking || _saving) return;
    if (_room <= 0) {
      showGlassToast(
        context,
        'A highlight holds up to ${HighlightService.maxPhotos} photos.',
        isError: true,
      );
      return;
    }
    _picking = true;
    try {
      // Resized on the way in: a 12 MP original is far more than a phone
      // screen shows, and every photo here is uploaded before the save.
      final List<XFile> picked;
      if (_room == 1) {
        final one = await _picker.pickImage(
          source: ImageSource.gallery,
          imageQuality: 88,
          maxWidth: 1800,
        );
        picked = [?one];
      } else {
        picked = await _picker.pickMultiImage(
          imageQuality: 88,
          maxWidth: 1800,
          limit: _room,
        );
      }
      if (!mounted || picked.isEmpty) return;
      // `limit` is advisory on some Android pickers — enforce it here.
      final room = _room;
      setState(() {
        for (final x in picked.take(room)) {
          _photos.add(HighlightDraftPhoto.local(x.path));
        }
      });
      if (picked.length > room) {
        showGlassToast(
          context,
          'Kept the first $room. A highlight holds up to '
          '${HighlightService.maxPhotos} photos.',
        );
      }
    } catch (e) {
      debugPrint('[HighlightEditor] gallery pick failed: $e');
      if (mounted) {
        showGlassToast(context, "Couldn't open your photos.", isError: true);
      }
    } finally {
      _picking = false;
    }
  }

  Future<void> _addFromCamera() async {
    if (_picking || _saving || _room <= 0) return;
    _picking = true;
    try {
      final shot = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 88,
        maxWidth: 1800,
      );
      if (!mounted || shot == null) return;
      setState(() => _photos.add(HighlightDraftPhoto.local(shot.path)));
    } catch (e) {
      debugPrint('[HighlightEditor] camera failed: $e');
      if (mounted) {
        showGlassToast(context, "Couldn't open the camera.", isError: true);
      }
    } finally {
      _picking = false;
    }
  }

  /// A short video from the gallery. Checked here — length and size —
  /// rather than after a long upload has already failed.
  Future<void> _addVideo() async {
    if (_picking || _saving) return;
    if (_room <= 0) {
      showGlassToast(
        context,
        'A highlight holds up to ${HighlightService.maxPhotos} items.',
        isError: true,
      );
      return;
    }
    _picking = true;
    try {
      final picked = await _picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(
          seconds: HighlightService.maxVideoSeconds,
        ),
      );
      if (!mounted || picked == null) return;
      final file = File(picked.path);
      void refuse(String why) => showGlassToast(context, why, isError: true);

      if (await file.length() > HighlightService.maxVideoBytes) {
        if (!mounted) return;
        refuse('That video is too big. Pick a shorter one.');
        return;
      }
      final ms = await _videoLengthMs(file);
      if (!mounted) return;
      if (ms == null) {
        refuse("Couldn't read that video.");
        return;
      }
      if (ms > HighlightService.maxVideoSeconds * 1000 + 500) {
        refuse(
          'Videos can be up to ${HighlightService.maxVideoSeconds} seconds.',
        );
        return;
      }
      // Posts need a still beside a video, and every polaroid needs
      // something to show.
      final poster = await makeVideoPoster(picked.path);
      if (!mounted) return;
      if (poster == null) {
        refuse("Couldn't read that video.");
        return;
      }
      setState(
        () => _photos.add(
          HighlightDraftPhoto.localVideo(
            videoPath: picked.path,
            posterPath: poster.path,
            videoMs: ms,
          ),
        ),
      );
    } catch (e) {
      debugPrint('[HighlightEditor] video pick failed: $e');
      if (mounted) {
        showGlassToast(context, "Couldn't open your videos.", isError: true);
      }
    } finally {
      _picking = false;
    }
  }

  Future<int?> _videoLengthMs(File file) async {
    final controller = VideoPlayerController.file(file);
    try {
      await controller.initialize();
      return controller.value.duration.inMilliseconds;
    } catch (_) {
      return null;
    } finally {
      await controller.dispose();
    }
  }

  Future<void> _save() async {
    if (!_canSave) return;
    FocusScope.of(context).unfocus();
    HapticFeedback.mediumImpact();
    setState(() {
      _saving = true;
      _done = 0;
      _total = _photos.where((p) => p.isLocal).length;
    });
    try {
      await HighlightService.instance.save(
        id: widget.existing?.id,
        title: _title.text,
        photos: _photos,
        onProgress: (done, total) {
          if (mounted) setState(() => _done = done);
        },
      );
      if (!mounted) return;
      Navigator.of(context).pop(_isNew ? 'Pinned to your profile' : 'Saved');
    } on HighlightException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showGlassToast(context, e.message, isError: true);
    }
  }

  Future<void> _delete() async {
    final existing = widget.existing;
    if (existing == null || _saving) return;
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: PV2.raised,
        title: Text('Delete "${existing.title}"?', style: PV2.display(size: 18)),
        content: Text(
          'Its photos are removed for everyone. This can\'t be undone.',
          style: PV2.body(size: 13.5, color: PV2.inkBio),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Keep', style: PV2.body(size: 14)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'Delete',
              style: PV2.body(
                size: 14,
                weight: FontWeight.w700,
                color: PV2.danger,
              ),
            ),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    setState(() {
      _saving = true;
      _total = 0;
    });
    try {
      await HighlightService.instance.delete(existing.id);
      if (!mounted) return;
      Navigator.of(context).pop('Highlight deleted');
    } on HighlightException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showGlassToast(context, e.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cover = _photos.isEmpty ? null : _photos.first;
    final name = _title.text.trim();
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        backgroundColor: PV2.page,
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _topBar(),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(0, 8, 0, 28),
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      children: [
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 14, bottom: 6),
                            child: PolaroidCover(
                              width: 176,
                              title: name.isEmpty ? 'name it' : name,
                              imageUrl: cover?.url,
                              localPath: cover?.localPath,
                              isVideo: cover?.isVideo ?? false,
                              tilt: -0.035,
                            ),
                          ),
                        ),
                        _nameField(),
                        const SizedBox(height: 22),
                        _photosHeader(),
                        const SizedBox(height: 10),
                        _photoStrip(),
                        const SizedBox(height: 16),
                        _addButtons(),
                        if (!_isNew) ...[
                          const SizedBox(height: 30),
                          Center(
                            child: TextButton(
                              onPressed: _saving ? null : _delete,
                              child: Text(
                                'Delete highlight',
                                style: PV2.body(
                                  size: 13.5,
                                  weight: FontWeight.w700,
                                  color: PV2.danger,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              if (_saving) _savingVeil(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 14, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: _saving ? null : () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.close_rounded, color: Colors.white),
          ),
          Expanded(
            child: Text(
              _isNew ? 'New highlight' : 'Edit highlight',
              style: PV2.display(size: 19),
            ),
          ),
          GestureDetector(
            key: const ValueKey('highlight-save'),
            behavior: HitTestBehavior.opaque,
            onTap: _canSave ? _save : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(100),
                gradient: _canSave ? PV2.accentButton : null,
                color: _canSave ? null : PV2.disabledFill,
              ),
              child: Text(
                _isNew ? 'Pin it' : 'Save',
                style: PV2.body(
                  size: 14,
                  weight: FontWeight.w800,
                  color: _canSave ? PV2.onAccent : PV2.disabledInk,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _nameField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 14, 40, 0),
      child: TextField(
        controller: _title,
        enabled: !_saving,
        textAlign: TextAlign.center,
        textCapitalization: TextCapitalization.sentences,
        maxLength: HighlightService.maxTitle,
        onChanged: (_) => setState(() {}),
        cursorColor: PV2.accent,
        style: GoogleFonts.caveat(
          fontSize: 30,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
        decoration: InputDecoration(
          // Explicit: the app theme's contentPadding otherwise leaks in.
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          isDense: true,
          hintText: 'Name it',
          hintStyle: GoogleFonts.caveat(
            fontSize: 30,
            fontWeight: FontWeight.w700,
            color: Colors.white.withValues(alpha: 0.28),
          ),
          counterStyle: PV2.mono(size: 10.5),
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.16)),
          ),
          focusedBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: PV2.accent, width: 1.4),
          ),
          disabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
          ),
        ),
      ),
    );
  }

  Widget _photosHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Text(
            'PHOTOS AND VIDEOS',
            style: PV2.caps(size: 10.5, tracking: 0.14, color: PV2.inkMember),
          ),
          const SizedBox(width: 8),
          Text(
            '${_photos.length}/${HighlightService.maxPhotos}',
            style: PV2.mono(size: 10.5),
          ),
          const Spacer(),
          if (_photos.length > 1)
            Text(
              'hold and drag to reorder',
              style: PV2.body(size: 11, color: PV2.inkSub),
            ),
        ],
      ),
    );
  }

  Widget _photoStrip() {
    if (_photos.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Container(
          height: 84,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: PV2.recessed,
            border: Border.all(color: PV2.hairlinePanel),
          ),
          child: Text(
            'Nothing yet. Add photos or a short video from your phone.',
            style: PV2.body(size: 12.5, color: PV2.inkSub),
          ),
        ),
      );
    }
    return SizedBox(
      height: 92,
      child: ReorderableListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        buildDefaultDragHandles: false,
        proxyDecorator: (child, _, _) =>
            Material(color: Colors.transparent, child: child),
        itemCount: _photos.length,
        onReorderItem: (from, to) {
          if (_saving) return;
          setState(() => _photos.insert(to, _photos.removeAt(from)));
        },
        itemBuilder: (context, i) {
          final p = _photos[i];
          return ReorderableDelayedDragStartListener(
            key: ValueKey(p.postId ?? p.localPath),
            index: i,
            enabled: !_saving,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
              child: _thumb(p, i),
            ),
          );
        },
      ),
    );
  }

  Widget _thumb(HighlightDraftPhoto p, int i) {
    return SizedBox(
      width: 76,
      height: 84,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            top: 0,
            child: Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: i == 0 ? PV2.accent : PV2.hairlineBright,
                  width: i == 0 ? 2 : 1,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: p.isLocal
                  ? Image.file(File(p.localPath!), fit: BoxFit.cover)
                  : CachedNetworkImage(
                      imageUrl: p.url ?? '',
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) =>
                          const ColoredBox(color: PV2.recessed),
                    ),
            ),
          ),
          if (p.isVideo)
            Positioned(
              right: 5,
              bottom: 13,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withValues(alpha: 0.6),
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  size: 15,
                  color: Colors.white,
                ),
              ),
            ),
          if (i == 0)
            Positioned(
              left: 6,
              bottom: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(100),
                  color: PV2.accent,
                ),
                child: Text(
                  'cover',
                  style: PV2.body(
                    size: 9.5,
                    weight: FontWeight.w800,
                    color: PV2.onAccent,
                  ),
                ),
              ),
            ),
          Positioned(
            right: -5,
            top: -6,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _saving ? null : () => setState(() => _photos.removeAt(i)),
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF1B1B22),
                  border: Border.all(color: PV2.hairlineBright),
                ),
                child: const Icon(
                  Icons.close_rounded,
                  size: 14,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _addButtons() {
    final full = _room <= 0;
    Widget button(IconData icon, String label, VoidCallback onTap) => Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: full || _saving ? null : onTap,
        child: Opacity(
          opacity: full ? 0.4 : 1,
          child: Container(
            height: 50,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: PV2.raised,
              border: Border.all(color: PV2.hairlineBright),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: PV2.accent),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PV2.body(size: 13, weight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          button(Icons.photo_library_outlined, 'Photos', _addFromGallery),
          const SizedBox(width: 8),
          button(Icons.videocam_outlined, 'Video', _addVideo),
          const SizedBox(width: 8),
          button(Icons.photo_camera_outlined, 'Camera', _addFromCamera),
        ],
      ),
    );
  }

  Widget _savingVeil() {
    final label = _total == 0
        ? 'Saving…'
        : 'Uploading ${(_done + 1).clamp(1, _total)} of $_total…';
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.62),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: PV2.accent,
                ),
              ),
              const SizedBox(height: 14),
              Text(label, style: PV2.body(size: 13.5, weight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}
