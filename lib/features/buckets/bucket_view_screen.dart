import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/constants.dart';
import '../../services/bucket_service.dart';
import '../../services/image_prep_service.dart';

// ---------------------------------------------------------------------------
// BucketViewScreen — bucket header + photo grid + drop-a-photo action
// ---------------------------------------------------------------------------
//
// Capture reuses the app's existing primitives (ImagePicker's camera
// source + ImagePrepService's downscale/compress step + the
// StorageService static-upload-method pattern) rather than a new custom
// camera preview UI — ComposerScreen's capture card is a bespoke
// CameraController-driven flow wired specifically to post creation
// (anon toggle, music, reward animation), and repurposing it here would
// mean either forking a lot of unrelated UI or bolting a "bucket mode"
// onto the main composer, which risks regressing the primary post flow
// for a scoped-down v1. Using ImagePicker(source: camera) is the OS
// camera, not a rebuilt one.

class BucketViewScreen extends StatefulWidget {
  const BucketViewScreen({super.key, required this.bucketId});

  final String bucketId;

  @override
  State<BucketViewScreen> createState() => _BucketViewScreenState();
}

class _BucketViewScreenState extends State<BucketViewScreen> {
  late Future<_BucketData> _future;
  bool _uploading = false;
  String? _uploadError;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_BucketData> _load() async {
    final bucket = await BucketService.instance.fetchBucket(widget.bucketId);
    if (bucket == null) {
      throw StateError('Bucket not found or no longer visible');
    }
    final contributions =
        await BucketService.instance.fetchContributions(widget.bucketId);
    return _BucketData(bucket: bucket, contributions: contributions);
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _dropPhoto() async {
    HapticFeedback.lightImpact();
    XFile? picked;
    try {
      picked = await ImagePicker().pickImage(
        source: ImageSource.camera,
        maxWidth: 1600,
        imageQuality: 90,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _uploadError = "Couldn't open the camera.");
      return;
    }
    if (picked == null || !mounted) return;

    setState(() {
      _uploading = true;
      _uploadError = null;
    });

    try {
      final prepared =
          await ImagePrepService.instance.prepareForStudio(picked.path);
      final fileToUpload = prepared ?? File(picked.path);
      await BucketService.instance.addContribution(
        bucketId: widget.bucketId,
        photoFile: fileToUpload,
      );
      if (!mounted) return;
      setState(() => _uploading = false);
      _reload();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _uploadError = "Couldn't add that photo. Try again.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        top: false,
        bottom: false,
        child: FutureBuilder<_BucketData>(
          future: _future,
          builder: (context, snap) {
            final isLoading = snap.connectionState == ConnectionState.waiting;

            return Column(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(16, topPad + 12, 16, 12),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: AppColors.cardSurface,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.border),
                          ),
                          child: const Icon(Icons.arrow_back_ios_new_rounded,
                              size: 15, color: AppColors.textPrimary),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              snap.data?.bucket['title'] as String? ??
                                  (isLoading ? 'Loading…' : 'Bucket'),
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (snap.data != null)
                              Text(
                                _statusLabel(snap.data!.bucket),
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 10,
                                  color: _isExpired(snap.data!.bucket)
                                      ? AppColors.errorRed
                                      : AppColors.textMuted,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(child: _buildBody(snap, isLoading)),
              ],
            );
          },
        ),
      ),
      floatingActionButton: FutureBuilder<_BucketData>(
        future: _future,
        builder: (context, snap) {
          final bucket = snap.data?.bucket;
          if (bucket == null || _isExpired(bucket)) {
            return const SizedBox.shrink();
          }
          return Padding(
            padding: EdgeInsets.only(bottom: bottomPad),
            child: FloatingActionButton(
              onPressed: _uploading ? null : _dropPhoto,
              backgroundColor: AppColors.coral,
              child: _uploading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    )
                  : const Icon(Icons.add_a_photo_rounded, color: Colors.white),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBody(AsyncSnapshot<_BucketData> snap, bool isLoading) {
    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.coral, strokeWidth: 2),
      );
    }

    if (snap.hasError) {
      return _MessageState(
        icon: Icons.error_outline_rounded,
        message: "Couldn't load this bucket.",
        actionLabel: 'Retry',
        onAction: _reload,
      );
    }

    final data = snap.data!;

    return RefreshIndicator(
      color: AppColors.coral,
      backgroundColor: AppColors.cardSurface,
      onRefresh: () async => _reload(),
      child: CustomScrollView(
        slivers: [
          if (_uploadError != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  _uploadError!,
                  style: GoogleFonts.inter(fontSize: 12, color: AppColors.errorRed),
                ),
              ),
            ),
          if (data.contributions.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _MessageState(
                icon: Icons.photo_camera_back_outlined,
                message: _isExpired(data.bucket)
                    ? 'This bucket closed with no photos.'
                    : 'No photos yet.\nBe the first to drop one in.',
                actionLabel: null,
                onAction: null,
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 100),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 4,
                  mainAxisSpacing: 4,
                  childAspectRatio: 0.85,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    final photoUrl =
                        data.contributions[i]['photo_url'] as String?;
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: photoUrl == null
                          ? Container(color: AppColors.cardSurface)
                          : CachedNetworkImage(
                              imageUrl: photoUrl,
                              fit: BoxFit.cover,
                              placeholder: (_, _) =>
                                  Container(color: AppColors.cardSurface),
                              errorWidget: (_, _, _) => Container(
                                color: AppColors.cardSurface,
                                child: const Icon(Icons.broken_image_outlined,
                                    color: AppColors.textMuted, size: 18),
                              ),
                            ),
                    );
                  },
                  childCount: data.contributions.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  bool _isExpired(Map<String, dynamic> bucket) {
    final raw = bucket['expires_at'] as String?;
    if (raw == null) return false;
    final expiresAt = DateTime.tryParse(raw);
    return expiresAt != null && expiresAt.isBefore(DateTime.now().toUtc());
  }

  String _statusLabel(Map<String, dynamic> bucket) {
    final raw = bucket['expires_at'] as String?;
    if (raw == null) return 'Open indefinitely';
    final expiresAt = DateTime.tryParse(raw);
    if (expiresAt == null) return '';
    final now = DateTime.now().toUtc();
    if (expiresAt.isBefore(now)) return 'Closed';
    final remaining = expiresAt.difference(now);
    if (remaining.inHours >= 24) {
      return 'Closes in ${remaining.inDays}d';
    }
    if (remaining.inMinutes >= 60) {
      return 'Closes in ${remaining.inHours}h';
    }
    return 'Closes in ${remaining.inMinutes}m';
  }
}

class _BucketData {
  const _BucketData({required this.bucket, required this.contributions});
  final Map<String, dynamic> bucket;
  final List<Map<String, dynamic>> contributions;
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.icon,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppColors.textMuted, size: 36),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                  fontSize: 13, color: AppColors.textMuted, height: 1.5),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              GestureDetector(
                onTap: onAction,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                  decoration: BoxDecoration(
                    color: AppColors.cardSurface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text(
                    actionLabel!,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
