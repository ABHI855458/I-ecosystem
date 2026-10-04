import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/glass.dart' show showGlassToast;
import '../../../core/supabase_config.dart';
import '../../../services/community_feed_service.dart';
import '../../../services/current_user_service.dart';
import 'community_tokens.dart';

// ---------------------------------------------------------------------------
// CommunityMessageBar — the WhatsApp-style message box at the bottom of the
// community page ("a blob like thing to type there immediately").
//
//  * One slim pill: "+" | text | identity avatar | send (send only appears
//    once there's something to send).
//  * The identity avatar is who you post as: your photo = real name, the
//    mask = your anon name. Tap it to switch. While you're composing, one
//    quiet line above the pill spells it out.
//  * "+" opens Photos / Document (PDF) / My posts. Past the per-message limit
//    (kCommunityPostMaxImages photos, kCommunityPostMaxPdfs PDFs) it says
//    "Limit reached" instead of opening a picker.
//  * Attachments sit as small removable previews above the text; on the
//    feed the message renders like a chat message with them underneath.
//    An anonymous author is masked server-side (community_posts_feed).
// ---------------------------------------------------------------------------

/// One tap region for the whole message box (text field, "+", avatar,
/// send), so only taps OUTSIDE it close the keyboard.
const _barTapGroup = 'community_message_bar';

const _pillBg = Color(0xFF17171E);
const _pillBorder = Color(0x14FFFFFF);

class CommunityMessageBar extends StatefulWidget {
  const CommunityMessageBar({
    super.key,
    required this.communityId,
    required this.communityName,
    required this.onPosted,
    required this.onOpenMyPosts,
  });

  final String communityId;
  final String communityName;
  final ValueChanged<CommunityPost> onPosted;
  final VoidCallback onOpenMyPosts;

  @override
  State<CommunityMessageBar> createState() => _CommunityMessageBarState();
}

class _CommunityMessageBarState extends State<CommunityMessageBar> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  final List<XFile> _images = [];
  final List<PlatformFile> _pdfs = [];
  bool _isAnonymous = false;
  bool _sending = false;
  String? _realName;
  String? _anonName;
  String? _realPhoto;
  String? _anonPhoto;

  bool get _hasContent =>
      _ctrl.text.trim().isNotEmpty || _images.isNotEmpty || _pdfs.isNotEmpty;

  bool get _composing => _focus.hasFocus || _hasContent;

  String get _realLabel => (_realName ?? '').isEmpty ? 'your name' : _realName!;
  String get _anonLabel => (_anonName ?? '').isEmpty ? 'anonymous' : _anonName!;

  // Built directly: GoogleFonts bakes the weight into the family name, so a
  // copyWith(fontWeight:) on the bold post style kept the text bold.
  static final _inputStyle = GoogleFonts.inter(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.35,
    color: CommunityColors.textPrimary,
  );

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
    _ctrl.addListener(() => setState(() {}));
    _loadMe();
  }

  Future<void> _loadMe() async {
    try {
      final id = await CurrentUserService.instance.resolveId();
      final row = await supabase
          .from('users')
          .select('name, anon_name, profile_photo_url, anon_photo_url')
          .eq('id', id)
          .maybeSingle();
      if (!mounted || row == null) return;
      setState(() {
        _realName = (row['name'] as String?)?.trim();
        _anonName = (row['anon_name'] as String?)?.trim();
        _realPhoto = row['profile_photo_url'] as String?;
        _anonPhoto = row['anon_photo_url'] as String?;
      });
    } catch (_) {
      // Falls back to generic labels and icons.
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _toggleIdentity() {
    HapticFeedback.selectionClick();
    setState(() => _isAnonymous = !_isAnonymous);
    showGlassToast(
      context,
      _isAnonymous ? 'Posting as $_anonLabel (anonymous)' : 'Posting as $_realLabel',
    );
  }

  Future<void> _openPlusMenu() async {
    HapticFeedback.selectionClick();
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _PlusMenuSheet(
        photosLeft: kCommunityPostMaxImages - _images.length,
        pdfsLeft: kCommunityPostMaxPdfs - _pdfs.length,
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'photos':
        await _addPhotos();
      case 'pdf':
        await _addPdfs();
      case 'mine':
        widget.onOpenMyPosts();
    }
  }

  Future<void> _addPhotos() async {
    final remaining = kCommunityPostMaxImages - _images.length;
    if (remaining <= 0) {
      showGlassToast(context, 'Limit reached · $kCommunityPostMaxImages photos per message', isError: true);
      return;
    }
    try {
      final picked = await ImagePicker().pickMultiImage(maxWidth: 1440, imageQuality: 90, limit: remaining);
      if (picked.isEmpty || !mounted) return;
      if (picked.length > remaining) {
        showGlassToast(context, 'Limit reached · only $remaining more photo${remaining == 1 ? '' : 's'} added');
      }
      setState(() => _images.addAll(picked.take(remaining)));
    } catch (_) {
      if (mounted) showGlassToast(context, "Couldn't open your photos.", isError: true);
    }
  }

  Future<void> _addPdfs() async {
    final remaining = kCommunityPostMaxPdfs - _pdfs.length;
    if (remaining <= 0) {
      showGlassToast(context, 'Limit reached · $kCommunityPostMaxPdfs documents per message', isError: true);
      return;
    }
    try {
      final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
      if (picked.isEmpty || !mounted) return;
      final toAdd = <PlatformFile>[];
      for (final f in picked) {
        if (toAdd.length >= remaining) {
          if (mounted) showGlassToast(context, 'Limit reached · $kCommunityPostMaxPdfs documents per message');
          break;
        }
        if (await f.length() > kCommunityPostMaxPdfBytes) {
          if (mounted) showGlassToast(context, '${f.name} is over the 10 MB limit', isError: true);
          continue;
        }
        toAdd.add(f);
      }
      if (toAdd.isNotEmpty && mounted) setState(() => _pdfs.addAll(toAdd));
    } catch (_) {
      if (mounted) showGlassToast(context, "Couldn't open your files.", isError: true);
    }
  }

  Future<void> _send() async {
    if (!_hasContent || _sending) return;
    final text = _ctrl.text.trim();
    if (text.length > kCommunityPostMaxBodyChars) {
      showGlassToast(context, 'Keep it under $kCommunityPostMaxBodyChars characters', isError: true);
      return;
    }
    setState(() => _sending = true);
    HapticFeedback.mediumImpact();
    try {
      final post = await CommunityFeedService.instance.createPost(
        communityId: widget.communityId,
        body: text.isEmpty ? null : text,
        imageFiles: _images.map((x) => File(x.path)).toList(),
        pdfFiles: _pdfs.where((f) => f.path != null).map((f) => File(f.path!)).toList(),
        isAnonymous: _isAnonymous,
      );
      if (!mounted) return;
      _ctrl.clear();
      setState(() {
        _images.clear();
        _pdfs.clear();
      });
      // Close the keyboard after sending, like any chat app.
      _focus.unfocus();
      FocusManager.instance.primaryFocus?.unfocus();
      await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      widget.onPosted(post);
    } catch (_) {
      if (mounted) showGlassToast(context, "Couldn't send — try again.", isError: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TapRegion(
      groupId: _barTapGroup,
      child: _buildBar(context),
    );
  }

  Widget _buildBar(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // One quiet line while composing: who this will post as.
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          child: _composing
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                  child: GestureDetector(
                    onTap: _toggleIdentity,
                    behavior: HitTestBehavior.opaque,
                    child: Text.rich(
                      TextSpan(
                        style: CommunityType.postTime.copyWith(fontSize: 11, color: CommunityColors.textDim),
                        children: [
                          const TextSpan(text: 'Posting as '),
                          TextSpan(
                            text: _isAnonymous ? _anonLabel : _realLabel,
                            style: TextStyle(
                              color: _isAnonymous ? CommunityColors.pinkHover : CommunityColors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          TextSpan(text: _isAnonymous ? ' · anonymous · ' : ' · '),
                          const TextSpan(
                            text: 'switch',
                            style: TextStyle(decoration: TextDecoration.underline),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(6, 5, 6, 5),
          decoration: BoxDecoration(
            color: _pillBg,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: _pillBorder),
            boxShadow: const [
              BoxShadow(color: Color(0x80000000), blurRadius: 20, offset: Offset(0, 6)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_images.isNotEmpty || _pdfs.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
                  child: SizedBox(
                    height: 52,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (var i = 0; i < _images.length; i++)
                          _AttachmentThumb(
                            image: File(_images[i].path),
                            onRemove: () => setState(() => _images.removeAt(i)),
                          ),
                        for (var i = 0; i < _pdfs.length; i++)
                          _AttachmentThumb(
                            fileName: _pdfs[i].name,
                            onRemove: () => setState(() => _pdfs.removeAt(i)),
                          ),
                      ],
                    ),
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _GhostIcon(
                    icon: Icons.add_rounded,
                    onTap: _sending ? null : _openPlusMenu,
                  ),
                  const SizedBox(width: 2),
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      focusNode: _focus,
                      // readOnly, not enabled:false — disabling the field
                      // mid-send dropped its focus in a way that left the
                      // keyboard open after sending.
                      readOnly: _sending,
                      // Tapping anywhere outside the message box (other than
                      // the keyboard) closes the keyboard; taps on "+" or the
                      // avatar are inside the same group, so they don't.
                      groupId: _barTapGroup,
                      onTapOutside: (_) => _focus.unfocus(),
                      minLines: 1,
                      maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                      style: _inputStyle,
                      cursorColor: CommunityColors.pink,
                      cursorWidth: 1.6,
                      cursorRadius: const Radius.circular(2),
                      decoration: InputDecoration(
                        isCollapsed: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 10),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        hintText: 'Message ${widget.communityName}',
                        hintStyle: _inputStyle.copyWith(color: CommunityColors.textDimmer),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  _IdentityAvatar(
                    anonymous: _isAnonymous,
                    realPhoto: _realPhoto,
                    anonPhoto: _anonPhoto,
                    onTap: _sending ? null : _toggleIdentity,
                  ),
                  // Send only once there's something to send.
                  AnimatedSize(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    child: _hasContent || _sending
                        ? Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: _SendButton(busy: _sending, onTap: _send),
                          )
                        : const SizedBox(height: 38),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _GhostIcon extends StatelessWidget {
  const _GhostIcon({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 38,
        height: 38,
        child: Icon(icon, size: 24, color: CommunityColors.textSecondary),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({required this.busy, required this.onTap});
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: busy ? null : onTap,
      child: Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: const BoxDecoration(shape: BoxShape.circle, color: CommunityColors.pink),
        child: busy
            ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.arrow_upward_rounded, size: 20, color: Colors.white),
      ),
    );
  }
}

/// Who you post as, in 30px: your photo (real name) or the mask / your anon
/// avatar with a pink ring (anonymous). Tap to switch.
class _IdentityAvatar extends StatelessWidget {
  const _IdentityAvatar({
    required this.anonymous,
    required this.realPhoto,
    required this.anonPhoto,
    required this.onTap,
  });
  final bool anonymous;
  final String? realPhoto;
  final String? anonPhoto;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final photo = anonymous ? anonPhoto : realPhoto;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 38,
        height: 38,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 30,
            height: 30,
            padding: const EdgeInsets.all(1.5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: anonymous ? CommunityColors.pink : const Color(0x33FFFFFF),
                width: 1.5,
              ),
            ),
            child: ClipOval(
              child: photo != null && photo.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: photo,
                      fit: BoxFit.cover,
                      memCacheWidth: 90,
                      placeholder: (_, _) => _fallback(),
                      errorWidget: (_, _, _) => _fallback(),
                    )
                  : _fallback(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _fallback() => Container(
        color: anonymous ? const Color(0x33FA2D64) : CommunityColors.cardBg2,
        alignment: Alignment.center,
        child: Icon(
          anonymous ? Icons.theater_comedy_rounded : Icons.person_rounded,
          size: 15,
          color: anonymous ? CommunityColors.pinkHover : CommunityColors.textSecondary,
        ),
      );
}

class _AttachmentThumb extends StatelessWidget {
  const _AttachmentThumb({this.image, this.fileName, required this.onRemove});
  final File? image;
  final String? fileName;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8, top: 4),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: image != null
                ? Image.file(image!, width: 46, height: 46, fit: BoxFit.cover)
                : Container(
                    width: 128,
                    height: 46,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    color: CommunityColors.cardBg2,
                    child: Row(
                      children: [
                        const Icon(Icons.picture_as_pdf_rounded, size: 18, color: CommunityColors.pinkHover),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            fileName ?? 'Document',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: CommunityType.postTime.copyWith(color: CommunityColors.textBody),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
          Positioned(
            top: -6,
            right: -6,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                width: 18,
                height: 18,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF2A2A34),
                  border: Border.all(color: _pillBg, width: 1.5),
                ),
                child: const Icon(Icons.close_rounded, size: 11, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlusMenuSheet extends StatelessWidget {
  const _PlusMenuSheet({required this.photosLeft, required this.pdfsLeft});
  final int photosLeft;
  final int pdfsLeft;

  @override
  Widget build(BuildContext context) {
    Widget item(String key, IconData icon, String title, String subtitle) => InkWell(
          onTap: () => Navigator.of(context).pop(key),
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0x1FFA2D64),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, size: 19, color: CommunityColors.pinkHover),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                          color: CommunityColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(subtitle, style: CommunityType.postTime),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: _pillBg,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: _pillBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            item('photos', Icons.photo_library_rounded, 'Photos',
                photosLeft > 0 ? 'Up to $photosLeft more' : 'Limit reached'),
            item('pdf', Icons.picture_as_pdf_rounded, 'Document (PDF)',
                pdfsLeft > 0 ? 'Up to $pdfsLeft more · 10 MB each' : 'Limit reached'),
            item('mine', Icons.forum_rounded, 'My posts', 'See and delete what you posted here'),
          ],
        ),
      ),
    );
  }
}
