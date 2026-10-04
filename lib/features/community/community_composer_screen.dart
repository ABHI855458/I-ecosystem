import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/glass.dart' show showGlassToast;
import '../../services/community_feed_service.dart';
import 'community_board/community_post_menu.dart' show confirmDeleteCommunityPost;
import 'community_board/community_tokens.dart';

// ---------------------------------------------------------------------------
// The community feed's post composer — there was no post affordance on this
// screen at all before this change; the only existing composer
// (composer_screen.dart) is reachable solely from the bottom-nav camera and
// writes to `posts`, not `community_posts`. This is a new, self-contained
// screen rather than a reuse of that one: `posts` carries baggage
// (music/moments/24h anon window) that must not leak onto a community
// noticeboard post — see the header of
// supabase/migrations/20260904000000_community_posts.sql for the full
// argument.
//
// Multi-photo picking mirrors GroupPostScreen's pattern (profile_v2_
// create_flows.dart:1013) — pickMultiImage at maxWidth 1440/quality 90,
// picked at PICK time rather than post-processed, same mechanism, +
// different cap (4 here vs that flow's 15).
//
// TWO MODES, one screen, switched by the header toggle: NEW POST (the
// original compose form) and MY POSTS (every post the caller has made in
// this community, each with a delete action). Delete moved HERE from the
// feed card's "..." menu deliberately — that menu is Report/Block only now
// (see community_post_menu.dart's header comment for the full reasoning);
// managing what you posted lives with posting, not mixed into the
// moderation menu you'd use on someone else's content.
// ---------------------------------------------------------------------------

enum _ComposerMode { newPost, myPosts }

class CommunityComposerScreen extends StatefulWidget {
  const CommunityComposerScreen({
    super.key,
    required this.communityId,
    required this.communityName,
    this.startInMyPosts = false,
  });

  final String communityId;
  final String communityName;

  /// Open straight onto "My Posts" (the message bar's "+" → My posts).
  final bool startInMyPosts;

  @override
  State<CommunityComposerScreen> createState() => _CommunityComposerScreenState();
}

class _CommunityComposerScreenState extends State<CommunityComposerScreen> {
  _ComposerMode _mode = _ComposerMode.newPost;

  final _bodyCtrl = TextEditingController();
  final List<XFile> _images = [];
  final List<PlatformFile> _pdfs = [];
  bool _isAnonymous = false;
  bool _submitting = false;
  String? _error;

  bool _myPostsLoading = true;
  String? _myPostsError;
  List<CommunityPost> _myPosts = const [];
  bool _myPostsLoadedOnce = false;

  @override
  void initState() {
    super.initState();
    if (widget.startInMyPosts) _selectMode(_ComposerMode.myPosts);
  }

  @override
  void dispose() {
    _bodyCtrl.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      !_submitting && (_bodyCtrl.text.trim().isNotEmpty || _images.isNotEmpty) && _bodyCtrl.text.length <= kCommunityPostMaxBodyChars;

  void _selectMode(_ComposerMode mode) {
    setState(() => _mode = mode);
    if (mode == _ComposerMode.myPosts && !_myPostsLoadedOnce) {
      _loadMyPosts();
    }
  }

  Future<void> _loadMyPosts() async {
    setState(() {
      _myPostsLoading = true;
      _myPostsError = null;
    });
    try {
      final posts = await CommunityFeedService.instance.fetchMyPosts(widget.communityId);
      if (!mounted) return;
      setState(() {
        _myPosts = posts;
        _myPostsLoading = false;
        _myPostsLoadedOnce = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _myPostsError = "Couldn't load your posts.";
        _myPostsLoading = false;
      });
    }
  }

  Future<void> _deleteMyPost(CommunityPost post) async {
    final deleted = await confirmDeleteCommunityPost(context, communityPostId: post.id);
    if (deleted && mounted) {
      setState(() => _myPosts = _myPosts.where((p) => p.id != post.id).toList());
    }
  }

  Future<void> _addImages() async {
    final remaining = kCommunityPostMaxImages - _images.length;
    if (remaining <= 0) return;
    try {
      final picked = await ImagePicker().pickMultiImage(maxWidth: 1440, imageQuality: 90, limit: remaining);
      if (picked.isEmpty) return;
      setState(() => _images.addAll(picked.take(remaining)));
    } catch (_) {
      if (mounted) showGlassToast(context, "Couldn't open the photo picker.", isError: true);
    }
  }

  Future<void> _addPdfs() async {
    final remaining = kCommunityPostMaxPdfs - _pdfs.length;
    if (remaining <= 0) return;
    try {
      final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
      if (picked.isEmpty) return;
      final toAdd = <PlatformFile>[];
      for (final f in picked.take(remaining)) {
        final size = await f.length();
        if (size > kCommunityPostMaxPdfBytes) {
          if (mounted) showGlassToast(context, '${f.name} is over the 10 MB PDF limit', isError: true);
          continue;
        }
        toAdd.add(f);
      }
      if (toAdd.isNotEmpty) setState(() => _pdfs.addAll(toAdd));
    } catch (_) {
      if (mounted) showGlassToast(context, "Couldn't open the file picker.", isError: true);
    }
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final post = await CommunityFeedService.instance.createPost(
        communityId: widget.communityId,
        body: _bodyCtrl.text.trim().isEmpty ? null : _bodyCtrl.text.trim(),
        imageFiles: _images.map((x) => File(x.path)).toList(),
        pdfFiles: _pdfs.where((f) => f.path != null).map((f) => File(f.path!)).toList(),
        isAnonymous: _isAnonymous,
      );
      if (!mounted) return;
      Navigator.of(context).pop(post);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = "Couldn't post — try again.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CommunityColors.screenBg,
      appBar: AppBar(
        backgroundColor: CommunityColors.screenBg,
        elevation: 0,
        title: Text(
          widget.startInMyPosts ? 'My posts · ${widget.communityName}' : 'Post to ${widget.communityName}',
          style: CommunityType.cardTitle.copyWith(fontSize: 15),
        ),
        actions: [
          if (_mode == _ComposerMode.newPost)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: GestureDetector(
                  onTap: _canSubmit ? _submit : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: _canSubmit ? CommunityColors.pink : CommunityColors.cardBg2,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: _submitting
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text('Post', style: TextStyle(color: _canSubmit ? Colors.white : CommunityColors.textDimmer, fontWeight: FontWeight.w700, fontSize: 13)),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Opened as "My posts" (from the message box's "+"): only your
            // posts, no New Post tab — writing happens in the message box.
            if (!widget.startInMyPosts)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
                child: _ModeToggle(mode: _mode, onChanged: _selectMode),
              ),
            Expanded(
              child: _mode == _ComposerMode.newPost ? _buildNewPost() : _buildMyPosts(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNewPost() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
      children: [
        _PostAsToggle(
          isAnonymous: _isAnonymous,
          onChanged: (v) => setState(() => _isAnonymous = v),
        ),
        const SizedBox(height: 6),
        Text(
          'Anonymous community posts do not count toward your streak — only anonymous posts to the main feed do.',
          style: CommunityType.pollMeta,
        ),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(color: CommunityColors.cardBg, border: Border.all(color: CommunityColors.cardBorder), borderRadius: BorderRadius.circular(13)),
          padding: const EdgeInsets.all(14),
          child: TextField(
            controller: _bodyCtrl,
            maxLines: 6,
            minLines: 3,
            maxLength: kCommunityPostMaxBodyChars,
            style: CommunityType.postBody,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              errorBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              focusedErrorBorder: InputBorder.none,
              counterStyle: CommunityType.pollMeta,
              hintText: "What's happening?",
              hintStyle: CommunityType.postBody.copyWith(color: CommunityColors.textDimmer),
            ),
          ),
        ),
        const SizedBox(height: 16),
        _AttachmentSection(
          label: 'PHOTOS',
          count: _images.length,
          max: kCommunityPostMaxImages,
          onAdd: _addImages,
          chips: [
            for (final img in _images)
              _ImageChip(file: img, onRemove: () => setState(() => _images.remove(img))),
          ],
        ),
        const SizedBox(height: 16),
        _AttachmentSection(
          label: 'PDFs',
          count: _pdfs.length,
          max: kCommunityPostMaxPdfs,
          onAdd: _addPdfs,
          chips: [
            for (final pdf in _pdfs)
              _PdfChip(file: pdf, onRemove: () => setState(() => _pdfs.remove(pdf))),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          Text(_error!, style: CommunityType.pollMeta.copyWith(color: const Color(0xFFE0607F))),
        ],
      ],
    );
  }

  Widget _buildMyPosts() {
    if (_myPostsLoading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2, color: CommunityColors.pink));
    }
    if (_myPostsError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_myPostsError!, style: CommunityType.pollMeta),
            const SizedBox(height: 8),
            TextButton(onPressed: _loadMyPosts, child: Text('Retry', style: CommunityType.pollCta)),
          ],
        ),
      );
    }
    if (_myPosts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            "You haven't posted here yet.",
            textAlign: TextAlign.center,
            style: CommunityType.pollMeta.copyWith(color: CommunityColors.textSecondary),
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadMyPosts,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
        itemCount: _myPosts.length,
        separatorBuilder: (_, _) => const SizedBox(height: 9),
        itemBuilder: (context, i) => _MyPostRow(post: _myPosts[i], onDelete: () => _deleteMyPost(_myPosts[i])),
      ),
    );
  }
}

class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.mode, required this.onChanged});
  final _ComposerMode mode;
  final ValueChanged<_ComposerMode> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget segment(String label, _ComposerMode value) {
      final selected = mode == value;
      return Expanded(
        child: GestureDetector(
          onTap: () => onChanged(value),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? CommunityColors.pink : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              label,
              style: selected
                  ? CommunityType.chipActive.copyWith(color: Colors.white)
                  : CommunityType.chipInactive,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: CommunityColors.cardBg2, border: Border.all(color: CommunityColors.chipBorder), borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          segment('New Post', _ComposerMode.newPost),
          segment('My Posts', _ComposerMode.myPosts),
        ],
      ),
    );
  }
}

class _MyPostRow extends StatelessWidget {
  const _MyPostRow({required this.post, required this.onDelete});
  final CommunityPost post;
  final VoidCallback onDelete;

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().toUtc().difference(dt.toUtc());
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }

  @override
  Widget build(BuildContext context) {
    final thumb = post.photoUrls.isNotEmpty ? post.photoUrls.first : null;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: CommunityColors.cardBg, border: Border.all(color: CommunityColors.cardBorder), borderRadius: BorderRadius.circular(13)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (thumb != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: CachedNetworkImage(
              memCacheWidth: 144,imageUrl: thumb, width: 48, height: 48, fit: BoxFit.cover),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    if (post.isAnonymous) ...[
                      Icon(Icons.masks_rounded, size: 12, color: CommunityColors.textDim),
                      const SizedBox(width: 4),
                    ],
                    Text(_relativeTime(post.createdAt), style: CommunityType.postTime),
                    if (post.documents.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.picture_as_pdf_rounded, size: 12, color: CommunityColors.textDim),
                    ],
                  ],
                ),
                if (post.body != null && post.body!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(post.body!, style: CommunityType.postBody.copyWith(fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onDelete,
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(Icons.delete_outline_rounded, size: 19, color: Color(0xFFE0607F)),
            ),
          ),
        ],
      ),
    );
  }
}

class _PostAsToggle extends StatelessWidget {
  const _PostAsToggle({required this.isAnonymous, required this.onChanged});
  final bool isAnonymous;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget segment(String label, bool selected, VoidCallback onTap) => Expanded(
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 9),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? CommunityColors.textPrimary : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(label, style: selected ? CommunityType.chipActive : CommunityType.chipInactive),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: CommunityColors.cardBg2, border: Border.all(color: CommunityColors.chipBorder), borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          segment('Your name', !isAnonymous, () => onChanged(false)),
          segment('Anonymous', isAnonymous, () => onChanged(true)),
        ],
      ),
    );
  }
}

class _AttachmentSection extends StatelessWidget {
  const _AttachmentSection({required this.label, required this.count, required this.max, required this.onAdd, required this.chips});
  final String label;
  final int count;
  final int max;
  final VoidCallback onAdd;
  final List<Widget> chips;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: CommunityType.sectionLabel(CommunityColors.textSecondary)),
            const SizedBox(width: 8),
            Text('$count/$max', style: CommunityType.sectionMeta),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ...chips,
            if (count < max)
              GestureDetector(
                onTap: onAdd,
                child: Container(
                  width: 64,
                  height: 64,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border.all(color: CommunityColors.chipBorder),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.add_rounded, color: CommunityColors.textSecondary, size: 22),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _ImageChip extends StatelessWidget {
  const _ImageChip({required this.file, required this.onRemove});
  final XFile file;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.file(File(file.path), width: 64, height: 64, fit: BoxFit.cover),
        ),
        Positioned(
          top: -4,
          right: -4,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              width: 18,
              height: 18,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: Colors.black87, shape: BoxShape.circle),
              child: const Icon(Icons.close_rounded, size: 12, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}

class _PdfChip extends StatelessWidget {
  const _PdfChip({required this.file, required this.onRemove});
  final PlatformFile file;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 160),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: CommunityColors.cardBg2, border: Border.all(color: CommunityColors.chipBorder), borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.picture_as_pdf_rounded, size: 16, color: Color(0xFFE0607F)),
          const SizedBox(width: 6),
          Flexible(child: Text(file.name, style: CommunityType.joinRowMeta, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 6),
          GestureDetector(onTap: onRemove, child: const Icon(Icons.close_rounded, size: 14, color: CommunityColors.textSecondary)),
        ],
      ),
    );
  }
}
