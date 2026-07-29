import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/image_prep_service.dart';
import 'collage_studio_screen.dart';

class PhotoPickerScreen extends StatefulWidget {
  const PhotoPickerScreen({super.key});

  @override
  State<PhotoPickerScreen> createState() => _PhotoPickerScreenState();
}

enum _PrepStatus { preparing, ready, failed }

class _PickedPhoto {
  final XFile source;
  _PrepStatus status;
  File? prepared;
  _PickedPhoto(this.source) : status = _PrepStatus.preparing;
}

class _PhotoPickerScreenState extends State<PhotoPickerScreen> {
  final _picker = ImagePicker();
  List<_PickedPhoto> _selected = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _pick());
  }

  Future<void> _pick() async {
    final files = await _picker.pickMultiImage(imageQuality: 95);
    if (files.isNotEmpty && mounted) {
      final picked = files.take(4).map(_PickedPhoto.new).toList();
      setState(() => _selected = picked);
      for (final photo in picked) {
        unawaited(_prepare(photo));
      }
    }
  }

  Future<void> _prepare(_PickedPhoto photo) async {
    final result = await ImagePrepService.instance.prepareForStudio(photo.source.path);
    if (!mounted) return;
    setState(() {
      photo.status = result == null ? _PrepStatus.failed : _PrepStatus.ready;
      photo.prepared = result;
    });
  }

  bool get _allReady =>
      _selected.length >= 2 && _selected.every((p) => p.status == _PrepStatus.ready);

  bool get _anyFailed => _selected.any((p) => p.status == _PrepStatus.failed);

  void _next() {
    final paths = _selected.map((p) => p.prepared!.path).toList();
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => CollageStudioScreen(photoPaths: paths),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(
          'Select photos',
          style: GoogleFonts.plusJakartaSans(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_selected.isNotEmpty)
            TextButton(
              onPressed: _pick,
              child: Text(
                'Re-pick',
                style: GoogleFonts.inter(color: Colors.white70, fontSize: 13),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _selected.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.add_photo_alternate_outlined,
                            color: Colors.white38, size: 48),
                        const SizedBox(height: 16),
                        TextButton.icon(
                          onPressed: _pick,
                          icon: const Icon(Icons.photo_library_outlined,
                              color: Color(0xFF00FFFF)),
                          label: Text(
                            'Choose from gallery',
                            style: GoogleFonts.inter(
                                color: const Color(0xFF00FFFF)),
                          ),
                        ),
                      ],
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemCount: _selected.length,
                    itemBuilder: (_, i) {
                      final photo = _selected[i];
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.file(File(photo.source.path), fit: BoxFit.cover),
                            if (photo.status == _PrepStatus.preparing)
                              Container(
                                color: Colors.black45,
                                child: const Center(
                                  child: SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white),
                                  ),
                                ),
                              ),
                            if (photo.status == _PrepStatus.failed)
                              Container(
                                color: Colors.black54,
                                child: Center(
                                  child: TextButton.icon(
                                    onPressed: () {
                                      setState(() => photo.status = _PrepStatus.preparing);
                                      _prepare(photo);
                                    },
                                    icon: const Icon(Icons.refresh, color: Colors.redAccent, size: 18),
                                    label: Text('Retry',
                                        style: GoogleFonts.inter(color: Colors.redAccent, fontSize: 12)),
                                  ),
                                ),
                              ),
                            Positioned(
                              top: 6,
                              left: 6,
                              child: Container(
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: const Color(0xFF2563EB),
                                  border: Border.all(
                                      color: Colors.white, width: 1.5),
                                ),
                                child: Center(
                                  child: Text(
                                    '${i + 1}',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      _selected.isEmpty
                          ? 'Pick 2-4 photos'
                          : _anyFailed
                              ? 'Some photos failed to process'
                              : '${_selected.length} selected',
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.jetBrainsMono(
                          color: _anyFailed ? Colors.redAccent : Colors.white54,
                          fontSize: 12),
                    ),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      disabledBackgroundColor: Colors.white12,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 28, vertical: 12),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: _allReady ? _next : null,
                    child: Text(
                      'Next →',
                      style: GoogleFonts.inter(
                          color: Colors.white, fontWeight: FontWeight.w600),
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
}
