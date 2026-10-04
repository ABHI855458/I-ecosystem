import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../screens/feed/widgets/moment_card.dart'
    show
        MomentPalette,
        MomentPaletteRow,
        kMomentPalettes,
        kMomentCaptionMaxChars;
import '../../core/glass.dart' show showGlassToast;
import '../../main.dart' show appNavigatorKey;
import '../../services/circle_service.dart';
import '../../services/community_service.dart';
import '../../services/group_service.dart';
import '../../services/post_service.dart';
import '../../services/post_size_prefs_service.dart';
import '../../services/us_album_service.dart';
import 'profile_v2_data.dart';
import 'profile_v2_icons.dart';
import 'profile_v2_sections.dart';
import 'profile_v2_tokens.dart';
import 'profile_v2_widgets.dart';

/// The three creation flows reached from the self profile's floating + button:
/// [AddMomentScreen], [GroupPostScreen] and [CreateGroupScreen].
///
/// All three share one rule from the design: **the commit button is visible but
/// disabled until its requirement is met**, and Add Moment states the
/// requirement in text below the button. The point is to show what is missing
/// rather than hide the action, so the disabled state must read as "not yet" —
/// hence a filled grey pill rather than a dimmed or absent one.

// ---------------------------------------------------------------------------
// Shared chrome
// ---------------------------------------------------------------------------

/// A create-flow scaffold: back button, title, and body.
/// How long a posting screen stays up after a successful write before it
/// closes itself.
///
/// Posting runs in the BACKGROUND: each flow closes the moment the user
/// taps post, and the upload continues on its own. Explicit correction:
/// "the posting thing is loading too much, let it post in the background
/// and let it drop off to profile page" — waiting on a photo upload before
/// closing meant staring at a spinner for as long as the network took.
///
/// The trade-off is that a failure surfaces after the screen is gone, so
/// [_reportBackgroundPostFailure] raises it on the root navigator instead
/// of a dead context.
void _reportBackgroundPostFailure(String what) {
  final context = appNavigatorKey.currentContext;
  if (context == null) return;
  showGlassToast(context, "Couldn't post that $what.", isError: true);
}

class _FlowScaffold extends StatelessWidget {
  const _FlowScaffold({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PV2.page,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: PV2.columnWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  child: Row(
                    children: [
                      NeuWell(
                        width: 38,
                        height: 38,
                        circle: true,
                        shadows: PV2.insetStd,
                        border: PV2.hairlinePanel,
                        color: PV2.raised,
                        onTap: () => Navigator.of(context).maybePop(),
                        child: PV2Icons.back(22, Colors.white),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: PV2.display(size: 20),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    child: child,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The full-width commit button, in its enabled or not-yet state.
class _CommitButton extends StatelessWidget {
  const _CommitButton({required this.label, required this.enabled, this.onTap});

  final String label;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(25),
        child: Container(
          height: 50,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: enabled ? PV2.accentButton : null,
            color: enabled ? null : PV2.disabledFill,
            borderRadius: BorderRadius.circular(25),
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: PV2.accent.withValues(alpha: 0.4),
                      offset: const Offset(0, 6),
                      blurRadius: 22,
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: PV2.body(
              size: 16,
              weight: FontWeight.w800,
              color: enabled ? PV2.onAccent : PV2.disabledInk,
            ),
          ),
        ),
      ),
    );
  }
}

/// The square back-a-step button that sits beside a commit button.
class _StepBackButton extends StatelessWidget {
  const _StepBackButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(21),
        child: Container(
          width: 42,
          height: 50,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: PV2.recessed,
            borderRadius: BorderRadius.circular(21),
            border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
          ),
          child: PV2Icons.back(22, Colors.white.withValues(alpha: 0.7)),
        ),
      ),
    );
  }
}

/// A tracked caps heading used above a create-flow's input.
class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.label, {this.opacity = 0.38});

  final String label;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: PV2.caps(
        size: 11,
        tracking: 0.08,
        color: Colors.white.withValues(alpha: opacity),
      ),
    );
  }
}

/// A card wrapping a free-text field.
class _InputCard extends StatelessWidget {
  const _InputCard({required this.label, required this.field});

  final String label;
  final Widget field;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: PV2.raised,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [_FieldLabel(label), const SizedBox(height: 8), field],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Add Moment
// ---------------------------------------------------------------------------

/// Two steps: attach a photo, then write a caption. Both are required — the
/// design gates posting on the pair and says so under the button.
class AddMomentScreen extends StatefulWidget {
  const AddMomentScreen({super.key});

  @override
  State<AddMomentScreen> createState() => _AddMomentScreenState();
}

class _AddMomentScreenState extends State<AddMomentScreen> {
  int _step = 1;
  XFile? _photo;
  final _caption = TextEditingController();
  bool _posting = false;

  /// The gradient this moment's feed card will wear — the poster picks it
  /// here and it's stored on the row as `posts.moment_color`.
  MomentPalette _palette = kMomentPalettes.first;

  /// Audience. A Moment used to be hardcoded `visibility: 'everyone'` with
  /// no choice at all — explicit request to "give option for posting in
  /// moments to post [to] communities and as well to friends".
  ///
  /// Pinned TRUE — explicit request ("include friends, not everyone"),
  /// matching the camera composer's own Moment audience. 'friends' is what
  /// can_view_post() gates to accepted friends OR members of any community
  /// in [_audienceCommunityIds] — the same combined, non-exclusive model
  /// GroupPostScreen's own "Also show to" pills use. It used to default to
  /// 'everyone' with a chip beside it, which made campus-wide the
  /// accidental choice in the one screen that asks the question twice.
  final bool _friendsOnly = true;
  final Set<String> _audienceCommunityIds = {};
  final Set<String> _audienceCircleIds = {};
  List<CommunityOption>? _communities;
  String? _communitiesError;
  List<CircleOption>? _circles;

  @override
  void initState() {
    super.initState();
    // The commit button's enabled-ness is derived from the field, so it has to
    // rebuild as the person types.
    _caption.addListener(() => setState(() {}));
    _loadCommunities();
    _loadCircles();
  }

  Future<void> _loadCommunities() async {
    try {
      final communities =
          await CommunityService.instance.fetchJoinedCommunities();
      if (mounted) setState(() => _communities = communities);
    } catch (e) {
      if (mounted) setState(() => _communitiesError = e.toString());
    }
  }

  /// Best-effort — a circles load failure just means no circle pills show,
  /// never blocks posting (same treatment communities get above).
  Future<void> _loadCircles() async {
    try {
      final circles = await CircleService.instance.fetchMyCircles();
      if (mounted) setState(() => _circles = circles);
    } catch (_) {}
  }

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  /// A moment is exactly one photo, sourced from camera or gallery — no
  /// collage, no multi-photo layout. This is deliberately its own upload path
  /// (PostService + `posts.post_type = 'moment'`) rather than a route through
  /// MemoryService/CollageBuilderScreen, which are for multi-photo arranged
  /// collages and would be the wrong shape here.
  Future<void> _pickPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          _SourceSheet(onPick: (s) => Navigator.of(context).pop(s)),
    );
    if (source == null || !mounted) return;

    final file = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1440,
      imageQuality: 90,
    );
    if (file == null || !mounted) return;
    setState(() {
      _photo = file;
      _step = 2;
    });
  }

  Future<void> _post() async {
    final photo = _photo;
    final caption = _caption.text.trim();
    if (photo == null || caption.isEmpty || _posting) return;

    setState(() => _posting = true);
    // Closes immediately; the upload continues in the background. See
    // _reportBackgroundPostFailure.
    final post = PostService.instance.addPostInBackground(
      build: (userId) => LocalPost(
        id: const Uuid().v4(),
        userId: userId,
        // 'friends' is what makes the audience picker mean anything —
        // can_view_post() only consults post_audiences for that
        // visibility; an 'everyone' post is already visible to everyone,
        // so community rows on one would be inert.
        visibility: _friendsOnly ? 'friends' : 'everyone',
        caption: caption,
        photoPath: photo.path,
        postType: 'moment',
        momentColor: _palette.id,
        audienceCommunityIds:
            _friendsOnly ? _audienceCommunityIds.toList() : const [],
        audienceCircleIds: _friendsOnly ? _audienceCircleIds.toList() : const [],
      ),
    );
    unawaited(post.catchError((_) => _reportBackgroundPostFailure('moment')));
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return _FlowScaffold(
      title: 'New Moment',
      child: _step == 1 ? _photoStep() : _captionStep(),
    );
  }

  /// Same pill treatment GroupPostScreen's audience chips use — kept as a
  /// local copy rather than shared because that one is private to its own
  /// State and this file's two flows are otherwise independent.
  /// [onTap] is nullable so a chip can STATE a fixed audience rather than
  /// offer one — the Friends chip above is no longer a choice.
  Widget _audienceChip({
    required String label,
    required bool selected,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? PV2.accent.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? PV2.accent.withValues(alpha: 0.55)
                : Colors.white.withValues(alpha: 0.10),
          ),
        ),
        child: Text(
          label,
          style: PV2.body(
            size: 12.5,
            weight: FontWeight.w700,
            color: selected ? PV2.accent : PV2.inkStamp,
          ),
        ),
      ),
    );
  }

  Widget _photoStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 4 / 5,
          child: DashedBox(
            radius: 26,
            strokeWidth: 2,
            color: PV2.accent.withValues(alpha: 0.32),
            child: Material(
              color: PV2.recessed,
              borderRadius: BorderRadius.circular(26),
              child: InkWell(
                onTap: _pickPhoto,
                borderRadius: BorderRadius.circular(26),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    PV2Icons.camera(34, PV2.accent),
                    const SizedBox(height: 12),
                    Text(
                      'Tap to add photo',
                      style: PV2.body(
                        size: 14,
                        weight: FontWeight.w700,
                        color: PV2.accent.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        // Disabled: this step's only exit is _pickPhoto jumping straight to
        // step 2 once a photo is chosen. Shown anyway so the flow's shape
        // matches step 2's Post button and never looks like a dead end.
        const _CommitButton(label: 'Next →', enabled: false),
      ],
    );
  }

  Widget _captionStep() {
    final photo = _photo;
    final canPost = photo != null && _caption.text.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 4 / 5,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (photo != null)
                  Image.file(File(photo.path), fit: BoxFit.cover)
                else
                  const ColoredBox(color: Color(0xFF2B3B34)),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x00000000), Color(0xB3000000)],
                      stops: [0.55, 1.0],
                    ),
                  ),
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: Container(
                    height: 22,
                    padding: const EdgeInsets.symmetric(horizontal: 9),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: PV2.accent.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(
                        color: PV2.accent.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      'photo added ✓',
                      style: PV2.body(
                        size: 10,
                        weight: FontWeight.w800,
                        color: PV2.accent,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        _InputCard(
          // This caption is the moment's HEADLINE on the feed card (where
          // the design reads "Quad Golden Hour"), not a paragraph — hence
          // one line and a hard character cap rather than a growing box.
          label: 'Your moment title *',
          field: TextField(
            controller: _caption,
            maxLines: 1,
            maxLength: kMomentCaptionMaxChars,
            textCapitalization: TextCapitalization.words,
            cursorColor: PV2.accent,
            style: PV2.body(size: 15, height: 1.5),
            buildCounter:
                (
                  context, {
                  required currentLength,
                  required isFocused,
                  maxLength,
                }) => Text(
                  '$currentLength/$maxLength',
                  style: PV2.body(
                    size: 10,
                    weight: FontWeight.w700,
                    color: currentLength >= (maxLength ?? 0)
                        ? PV2.accent
                        : PV2.inkStamp,
                  ),
                ),
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              errorBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              focusedErrorBorder: InputBorder.none,
              hintText: 'e.g. Quad Golden Hour — required...',
              hintStyle: PV2.body(size: 15, color: PV2.inkStamp, height: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _InputCard(
          label: 'Card colour',
          field: MomentPaletteRow(
            selected: _palette,
            onSelect: (p) => setState(() => _palette = p),
          ),
        ),
        const SizedBox(height: 12),
        _InputCard(
          label: 'Who can see this',
          field: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Your circles decide who sees it: Friends by default, or
              // exactly the circles picked (e.g. Close Friends only). No
              // 'Everyone' for a Moment. See CircleAudience's own doc.
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (_circles == null || _circles!.isEmpty)
                    _audienceChip(label: 'Friends', selected: true, onTap: null)
                  else
                    for (final c in _circles!)
                      _audienceChip(
                        label: c.name,
                        selected: CircleAudience.isSelected(_audienceCircleIds, c.id, _circles),
                        onTap: () => setState(
                          () => CircleAudience.toggle(_audienceCircleIds, c.id, _circles),
                        ),
                      ),
                ],
              ),
              // Communities ADD to the circle audience rather than
              // replacing it.
              if (_friendsOnly) ...[
                const SizedBox(height: 12),
                Text(
                  'ALSO SHOW TO',
                  style: PV2.body(
                    size: 10,
                    weight: FontWeight.w800,
                    color: PV2.inkStamp,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (_communitiesError != null)
                      _audienceChip(
                        label: 'Retry communities',
                        selected: false,
                        onTap: _loadCommunities,
                      ),
                    for (final c in _communities ?? const <CommunityOption>[])
                      _audienceChip(
                        label: c.name,
                        selected: _audienceCommunityIds.contains(c.id),
                        onTap: () => setState(() {
                          if (!_audienceCommunityIds.remove(c.id)) {
                            _audienceCommunityIds.add(c.id);
                          }
                        }),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _StepBackButton(onTap: () => setState(() => _step = 1)),
            const SizedBox(width: 9),
            Expanded(
              child: _CommitButton(
                label: _posting ? 'Posting…' : 'Post Moment',
                enabled: canPost && !_posting,
                onTap: _post,
              ),
            ),
          ],
        ),
        const SizedBox(height: 9),
        Text(
          'Photo + caption both required to post',
          textAlign: TextAlign.center,
          style: PV2.body(
            size: 11,
            weight: FontWeight.w600,
            color: PV2.inkStamp,
          ),
        ),
      ],
    );
  }
}

/// The camera-or-gallery choice for a single photo. Kept to one tap beyond
/// this sheet, matching the requirement that adding a Moment take as few taps
/// as possible.
class _SourceSheet extends StatelessWidget {
  const _SourceSheet({required this.onPick});

  final ValueChanged<ImageSource> onPick;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            NeuCard(
              radius: 20,
              padding: EdgeInsets.zero,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _sourceRow(
                    icon: Icons.photo_camera_outlined,
                    label: 'Camera',
                    onTap: () => onPick(ImageSource.camera),
                  ),
                  const Divider(height: 1, color: PV2.hairline),
                  _sourceRow(
                    icon: Icons.photo_library_outlined,
                    label: 'Gallery',
                    onTap: () => onPick(ImageSource.gallery),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            NeuCard(
              radius: 20,
              padding: EdgeInsets.zero,
              child: _sourceRow(
                icon: Icons.close_rounded,
                label: 'Cancel',
                onTap: () => Navigator.of(context).pop(),
                bold: true,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sourceRow({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool bold = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 15),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: Colors.white),
              const SizedBox(width: 10),
              Text(
                label,
                style: PV2.body(
                  size: 16,
                  weight: bold ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Create Group
// ---------------------------------------------------------------------------

/// Two steps: pick people, then name the group. The title changes per step, so
/// the header states where you are rather than repeating "Create Group".
class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

/// One search result from `GroupService.searchUsers` — a real account, not a
/// placeholder swatch.
class _SearchPerson {
  const _SearchPerson({
    required this.id,
    required this.name,
    required this.photoUrl,
  });

  factory _SearchPerson.fromRow(Map<String, dynamic> row) => _SearchPerson(
    id: row['id'] as String,
    name: (row['name'] as String?)?.trim().isNotEmpty == true
        ? row['name'] as String
        : (row['anon_name'] as String? ?? 'unknown'),
    photoUrl: row['profile_photo_url'] as String?,
  );

  final String id;
  final String name;
  final String? photoUrl;
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  int _step = 1;
  final _search = TextEditingController();
  final _name = TextEditingController();

  final _selected = <String, _SearchPerson>{};
  List<_SearchPerson> _results = [];
  bool _searching = false;
  bool _creating = false;

  /// Bumped on every keystroke; a search reply is discarded unless it is
  /// still the most recent one — otherwise a slow early query can overwrite
  /// results from a faster later one.
  int _searchToken = 0;

  final _groupService = GroupService.instance;

  /// People in the caller's circles, shown as the default roster before
  /// anything is typed. Picked people get an INVITE; they join the group
  /// album only by accepting it. Same row shape searchUsers returns, so
  /// both feed the same _SearchPerson.fromRow.
  List<_SearchPerson> _friends = const [];

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
    _search.addListener(_onSearchChanged);
    _loadFriends();
  }

  Future<void> _loadFriends() async {
    try {
      final rows = await CircleService.instance.fetchPeopleInMyCircles();
      if (!mounted) return;
      setState(() => _friends = rows.map(_SearchPerson.fromRow).toList());
    } catch (_) {
      // Leave the list empty — the search field still works.
    }
  }

  /// What the picker renders right now: search results while a query is
  /// typed, the friend list otherwise (minus anyone already picked).
  List<_SearchPerson> get _visiblePeople => _search.text.trim().isEmpty
      ? [for (final f in _friends) if (!_selected.containsKey(f.id)) f]
      : _results;

  @override
  void dispose() {
    _search.dispose();
    _name.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _search.text.trim();
    final token = ++_searchToken;
    if (query.isEmpty) {
      setState(() {
        _results = [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    // No debounce timer: GroupService.searchUsers is a single indexed ILIKE
    // query against a small table, and the token check above already drops
    // stale replies, so an extra delay would only slow the list down for no
    // correctness benefit.
    _groupService
        .searchUsers(query, excludeIds: _selected.keys.toSet())
        .then(
          (rows) {
            if (!mounted || token != _searchToken) return;
            setState(() {
              _results = rows.map(_SearchPerson.fromRow).toList();
              _searching = false;
            });
          },
          onError: (_) {
            if (!mounted || token != _searchToken) return;
            setState(() => _searching = false);
          },
        );
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty || _creating) return;

    setState(() => _creating = true);
    try {
      await _groupService.createGroup(
        name: name,
        memberUserIds: _selected.keys.toList(),
      );
      if (!mounted) return;
      final n = _selected.length;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Group created — ${n == 1 ? 'invite' : '$n invites'} sent'),
      ));
      Navigator.of(context).maybePop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _creating = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Couldn\'t create group: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return _FlowScaffold(
      title: _step == 1 ? 'Add People' : 'Name Your Group',
      child: _step == 1 ? _peopleStep() : _nameStep(),
    );
  }

  Widget _peopleStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _InputCard(
          label: 'Search people',
          field: TextField(
            controller: _search,
            cursorColor: PV2.accent,
            style: PV2.body(size: 15, weight: FontWeight.w600),
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              errorBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              focusedErrorBorder: InputBorder.none,
              hintText: 'Search by name…',
              hintStyle: PV2.body(size: 15, color: PV2.inkStamp),
            ),
          ),
        ),
        if (_selected.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [for (final p in _selected.values) _selectedChip(p)],
          ),
        ],
        const SizedBox(height: 14),
        if (_searching)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: PV2.accent,
                ),
              ),
            ),
          )
        else if (_visiblePeople.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Text(
              _search.text.trim().isEmpty
                  ? 'Add people to your circles, or search for anyone by name'
                  : 'No one found',
              textAlign: TextAlign.center,
              style: PV2.body(size: 13, color: PV2.inkStamp),
            ),
          )
        else ...[
          if (_search.text.trim().isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8, left: 2),
              child: Text(
                'FROM YOUR CIRCLES',
                style: PV2.caps(size: 9, tracking: 0.14, color: PV2.inkStamp),
              ),
            ),
          for (var i = 0; i < _visiblePeople.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _personRow(_visiblePeople[i]),
          ],
        ],
        const SizedBox(height: 14),
        _CommitButton(
          label: 'Next — ${_selected.length} selected',
          enabled: _selected.isNotEmpty,
          onTap: () => setState(() => _step = 2),
        ),
      ],
    );
  }

  Widget _personRow(_SearchPerson person) {
    final on = _selected.containsKey(person.id);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() {
          if (on) {
            _selected.remove(person.id);
          } else {
            _selected[person.id] = person;
          }
          // A picked person drops out of further search results — nothing
          // useful comes of re-showing someone already added.
          _results = _results
              .where((r) => !_selected.containsKey(r.id))
              .toList();
        }),
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          decoration: BoxDecoration(
            color: on ? PV2.raised : PV2.recessed,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: on
                  ? PV2.accent.withValues(alpha: 0.35)
                  : Colors.white.withValues(alpha: 0.06),
            ),
            boxShadow: on
                ? [
                    BoxShadow(
                      color: PV2.accent.withValues(alpha: 0.18),
                      blurRadius: 12,
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              _avatar(person, 38),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  person.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PV2.body(size: 14, weight: FontWeight.w700),
                ),
              ),
              if (on)
                Container(
                  width: 22,
                  height: 22,
                  decoration: const BoxDecoration(
                    color: PV2.accent,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    size: 14,
                    color: PV2.onAccent,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _nameStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The people picked in step 1, so the name is chosen with the group
        // in view rather than from memory.
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [for (final p in _selected.values) _selectedChip(p)],
        ),
        const SizedBox(height: 16),
        _InputCard(
          label: 'Group name *',
          field: TextField(
            controller: _name,
            cursorColor: PV2.accent,
            style: PV2.body(size: 17, weight: FontWeight.w700),
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              errorBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              focusedErrorBorder: InputBorder.none,
              hintText: 'Terrace Crew',
              hintStyle: PV2.body(
                size: 17,
                weight: FontWeight.w700,
                color: PV2.inkStamp,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _StepBackButton(onTap: () => setState(() => _step = 1)),
            const SizedBox(width: 9),
            Expanded(
              child: _CommitButton(
                label: _creating ? 'Creating…' : 'Create Group',
                enabled: _name.text.trim().isNotEmpty && !_creating,
                onTap: _create,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _avatar(_SearchPerson person, double size) {
    final url = person.photoUrl;
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: PV2.recessed, shape: BoxShape.circle),
      child: url == null || url.isEmpty
          ? Icon(
              Icons.person_rounded,
              size: size * 0.6,
              color: Colors.white.withValues(alpha: 0.4),
            )
          : Image.network(url, fit: BoxFit.cover),
    );
  }

  Widget _selectedChip(_SearchPerson person) {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: PV2.raised,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: PV2.accent.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _avatar(person, 18),
          const SizedBox(width: 6),
          Text(person.name, style: PV2.body(size: 12, weight: FontWeight.w600)),
          const SizedBox(width: 4),
          // Remove from the selection. Emptying it on the name step drops
          // back to the picker, since a group needs at least one member.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() {
              _selected.remove(person.id);
              if (_selected.isEmpty) _step = 1;
            }),
            child: Padding(
              padding: const EdgeInsets.only(left: 2, top: 4, bottom: 4),
              child: Icon(
                Icons.close_rounded,
                size: 15,
                color: Colors.white.withValues(alpha: 0.6),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Group Post — collage selector
// ---------------------------------------------------------------------------

/// The step this flow is on. A [groupId] passed to [GroupPostScreen] skips
/// [_Step.group] entirely — the design never shows a group picker because the
/// canvas assumes a single implicit group, but this screen is reached from
/// the profile-wide FAB with no group in context, so one has to be chosen
/// somewhere. When a future call site knows its group already (e.g. a "+"
/// button on that group's own screen), it should pass [GroupPostScreen.groupId]
/// and this step never appears.
enum _Step { group, photos }

/// Body text below the photo (`note`) — free paragraph, not a single-line
/// title, so it gets real room. No DB CHECK backs this column (unlike
/// dips_caption_len), so 200 is picked to match the closest paragraph-length
/// precedent in this codebase (composer_screen.dart's own
/// `_kDipCaptionMaxChars`) rather than inventing an unrelated number.
const int _kGroupNoteMaxChars = 200;

/// Picks a group, then the photos. Posts render as a swipeable carousel
/// (one photo or many), so there is no arrangement to choose — the old
/// collage-layout step was removed along with the collage cards themselves.
class GroupPostScreen extends StatefulWidget {
  const GroupPostScreen({
    super.key,
    this.groupId,
    this.groupName,
    this.groupIsPublic,
  });

  /// The target group, if already known. Null shows a picker as this
  /// screen's first step.
  final String? groupId;

  /// Name/visibility for the [groupId]-preselected entry point, where this
  /// screen skips its own group-picker step (see group_profile_v2_screen.dart)
  /// and so never loads `_groups` itself to learn either — passed straight
  /// through from a caller who already has them, so the visibility notice
  /// below the audience chips still has a group name and knows what the
  /// group's community will see.
  final String? groupName;
  final bool? groupIsPublic;

  @override
  State<GroupPostScreen> createState() => _GroupPostScreenState();
}

class _GroupPostScreenState extends State<GroupPostScreen> {
  late _Step _step;
  String? _groupId;
  String? _groupName;

  /// Drives the visibility notice's community line — see [_visibilityNotice].
  /// Null means "not known yet" (still loading _groups), not "private".
  bool? _groupIsPublic;

  /// Order IS display order — index 0 is the carousel's cover photo.
  final _photos = <XFile>[];

  /// Optional dual-photo inset. When set, _photos.first is the BACKGROUND
  /// and this is the small inset — the same two-layer model the friends
  /// feed uses, stored in group_posts' own photo_url_secondary column.
  /// Explicit request: group posting had no dual-camera layout option at
  /// all, unlike the friends composer.
  XFile? _dualInset;
  final _caption = TextEditingController();
  final _note = TextEditingController();
  final _place = TextEditingController();

  /// This post's OWN size choice, baked into its own group_posts.aspect_ratio
  /// at post time — local to this screen, never a shared/viewer setting.
  PostSizePreset _postSize = PostSizePreset.big;

  /// When the memory actually happened, if different from whenever this
  /// gets posted — group_posts.taken_at. Null posts with no taken_at
  /// (created_at alone is shown), same as leaving the caption empty.
  DateTime? _takenAt;
  bool _posting = false;

  List<Map<String, dynamic>>? _groups;
  String? _groupsError;

  /// Friends/community audience for this group post — same combined,
  /// non-exclusive model the personal-post composer's _AudiencePicker
  /// uses (C1), reimplemented small and inline here rather than shared
  /// across files, since that picker is composer_screen.dart-private.
  /// Untouched by default: this posts exactly as group posts always have
  /// (visible only to the group's own members).
  bool _includeFriends = false;

  /// Members-only post: hidden from everyone outside the group — even on a
  /// public group's profile — and can't be shared (see
  /// 20260929020000_group_privacy_model.sql).
  bool _private = false;
  final Set<String> _audienceCommunityIds = {};
  List<CommunityOption>? _communities;
  String? _communitiesError;

  /// The poster's circles, shown as chips next to Friends — explicit report:
  /// "while posting in a group the circles aren't visible". The Friends
  /// circle's chip drives [_includeFriends]; every other circle toggles in
  /// [_audienceCircleIds]. Nothing is picked by default: a group post stays
  /// members-only unless you add an audience.
  List<CircleOption>? _circles;
  final Set<String> _audienceCircleIds = {};

  /// Upper bound on one post's carousel. Not a requirement — any count from
  /// 1 up posts fine.
  static const _maxPhotos = 15;

  @override
  void initState() {
    super.initState();
    _groupId = widget.groupId;
    _groupName = widget.groupName;
    _groupIsPublic = widget.groupIsPublic;
    _step = widget.groupId == null ? _Step.group : _Step.photos;
    if (_step == _Step.group) _loadGroups();
    if (widget.groupId != null) _checkGroupMembers(widget.groupId!);
    _loadCommunities();
    _loadGroupPostCircles();
  }

  /// Best-effort, same as the other flows here — a failure just leaves the
  /// plain Friends chip.
  Future<void> _loadGroupPostCircles() async {
    try {
      final circles = await CircleService.instance.fetchMyCircles();
      if (mounted) setState(() => _circles = circles);
    } catch (_) {}
  }

  /// Null = still checking. False = only I have joined (everyone else still
  /// invited) — posting is refused server-side (group_post_requirements),
  /// so the form says so up front instead of failing after upload.
  bool? _groupHasOthers;

  Future<void> _checkGroupMembers(String groupId) async {
    setState(() => _groupHasOthers = null);
    try {
      final members = await GroupService.instance.fetchMembers(groupId);
      if (mounted && _groupId == groupId) {
        setState(() => _groupHasOthers = members.length > 1);
      }
    } catch (_) {
      // Unknown — let the server be the judge rather than block posting.
      if (mounted && _groupId == groupId) setState(() => _groupHasOthers = true);
    }
  }

  /// Everything a group post needs (group_post_requirements): photos,
  /// caption, note, place and date. Empty list = ready.
  List<String> get _missingFields => [
        if (_photos.isEmpty) 'a photo',
        if (_caption.text.trim().isEmpty) 'a caption',
        if (_note.text.trim().isEmpty) 'a note',
        if (_place.text.trim().isEmpty) 'a location',
        if (_takenAt == null) 'a date',
      ];

  Future<void> _loadCommunities() async {
    try {
      final communities = await CommunityService.instance
          .fetchJoinedCommunities();
      if (mounted) setState(() => _communities = communities);
    } catch (e) {
      if (mounted) setState(() => _communitiesError = e.toString());
    }
  }

  @override
  void dispose() {
    _caption.dispose();
    _note.dispose();
    _place.dispose();
    super.dispose();
  }

  Future<void> _pickTakenAt() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _takenAt ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
    );
    if (picked != null && mounted) setState(() => _takenAt = picked);
  }

  Future<void> _loadGroups() async {
    try {
      final groups = await GroupService.instance.fetchMyGroups();
      if (mounted) setState(() => _groups = groups);
    } catch (e) {
      if (mounted) setState(() => _groupsError = e.toString());
    }
  }

  /// Multi-select: one trip to the gallery adds as many photos as the person
  /// picks, rather than one per tap. Everything downstream already handled N
  /// photos (the thumb grid, the counter, GroupService.addPost's photoFiles
  /// list, and the carousel that renders them) — only the picker was
  /// single-shot.
  Future<void> _addPhoto() async {
    // The add tile is already hidden at the cap (see _photosStep's
    // canAddMore), but one multi-pick can still overshoot it, so the cap is
    // enforced here too rather than only in the UI.
    final remaining = _maxPhotos - _photos.length;
    if (remaining <= 0) return;

    final files = await ImagePicker().pickMultiImage(
      maxWidth: 1440,
      imageQuality: 90,
      // MultiImagePickerOptions throws ArgumentError for a limit below 2, so
      // the last free slot has to pass null and lean on the take() below.
      limit: remaining >= 2 ? remaining : null,
    );
    if (files.isEmpty || !mounted) return;
    // take() regardless of `limit`: it's a platform hint, not a guarantee,
    // and it's null in the one-slot case. Appended, not inserted — _photos
    // order is display order and index 0 is the carousel's cover.
    setState(() => _photos.addAll(files.take(remaining)));
  }

  Future<void> _pickDualInset() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1920,
      imageQuality: 88,
    );
    if (file != null && mounted) setState(() => _dualInset = file);
  }

  Future<void> _post() async {
    final groupId = _groupId;
    if (groupId == null || _missingFields.isNotEmpty ||
        _groupHasOthers != true || _posting) {
      return;
    }

    setState(() => _posting = true);
    // Each photo uploads as its own URL and the post renders them as a
    // swipeable carousel — no flattening into one composite image, which
    // is what the removed collage layouts required.
    //
    // Fired, not awaited: the screen closes now and the upload finishes on
    // its own. See _reportBackgroundPostFailure.
    unawaited(
      GroupService.instance
          .addPost(
            groupId: groupId,
            photoFiles: [for (final p in _photos) File(p.path)],
            secondaryPhoto:
                _dualInset == null ? null : File(_dualInset!.path),
            caption: _caption.text.trim().isEmpty ? null : _caption.text.trim(),
            takenAt: _takenAt,
            note: _note.text.trim().isEmpty ? null : _note.text.trim(),
            place: _place.text.trim().isEmpty ? null : _place.text.trim(),
            includeFriends: _private ? false : _includeFriends,
            audienceCommunityIds:
                _private ? const [] : _audienceCommunityIds.toList(),
            audienceCircleIds:
                _private ? const [] : _audienceCircleIds.toList(),
            isPrivate: _private,
            aspectRatio: _postSize.aspect,
          )
          .catchError((_) => _reportBackgroundPostFailure('post')),
    );
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return _FlowScaffold(
      title: switch (_step) {
        _Step.group => 'Post To…',
        // Names the group you picked instead of a generic "Add Photos" —
        // _groupName was being captured on selection and then never read,
        // so the one place it would actually help said nothing.
        _Step.photos => _groupName == null ? 'Add Photos' : 'Add to $_groupName',
      },
      child: switch (_step) {
        _Step.group => _groupStep(),
        _Step.photos => _photosStep(),
      },
    );
  }

  Widget _groupStep() {
    if (_groupsError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          children: [
            Text(
              'Couldn\'t load your groups',
              textAlign: TextAlign.center,
              style: PV2.body(size: 13, weight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              _groupsError!,
              textAlign: TextAlign.center,
              style: PV2.body(size: 11, color: PV2.inkStamp),
            ),
            const SizedBox(height: 14),
            _CommitButton(
              label: 'Retry',
              enabled: true,
              onTap: () => setState(() {
                _groupsError = null;
                _loadGroups();
              }),
            ),
          ],
        ),
      );
    }

    final groups = _groups;
    if (groups == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: CircularProgressIndicator(strokeWidth: 2, color: PV2.accent),
        ),
      );
    }
    if (groups.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Text(
          'Join or create a group first',
          textAlign: TextAlign.center,
          style: PV2.body(size: 13, color: PV2.inkStamp),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < groups.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _groupRow(groups[i]),
        ],
      ],
    );
  }

  Widget _groupRow(Map<String, dynamic> group) {
    final id = group['id'] as String;
    final name = group['name'] as String? ?? 'Unnamed group';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          setState(() {
            _groupId = id;
            _groupName = name;
            _groupIsPublic = group['visibility'] == 'public';
            _step = _Step.photos;
          });
          _checkGroupMembers(id);
        },
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
          decoration: BoxDecoration(
            color: PV2.recessed,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: kGroupGradients[0],
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: PV2.display(size: 15),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PV2.body(size: 14, weight: FontWeight.w700),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: Colors.white.withValues(alpha: 0.3),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _photosStep() {
    // Any count from 1 posts fine — one photo renders as a plain image,
    // several as a swipeable carousel. No fixed slot count to satisfy now
    // that collage layouts are gone.
    final missing = _missingFields;
    final canPost = missing.isEmpty && _groupHasOthers == true;
    final canAddMore = _photos.length < _maxPhotos;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Same global "POST SIZE" preference the friends feed's own header
        // and FriendsPostScreen use — group posts render through the same
        // PostPhotoCarousel and were part of the original ask ("for each
        // post in the friends post and as well group posts as well").
        PostSizePresetPicker(
          value: _postSize,
          onChanged: (v) => setState(() => _postSize = v),
        ),
        const SizedBox(height: 14),
        _FieldLabel(
          _photos.isEmpty
              ? 'Add up to $_maxPhotos photos — swipe to see them all'
              : '${_photos.length} of $_maxPhotos · first one is the cover',
          opacity: 0.35,
        ),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 3,
          // Same fix as FriendsPostScreen's own grid, same root cause:
          // GridView.count's default childAspectRatio (1.0, a square)
          // ignored the POST SIZE picker directly above it.
          childAspectRatio: _postSize.aspect,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (var i = 0; i < _photos.length; i++) _photoThumb(i),
            if (canAddMore)
              AddTile(
                label: 'add',
                icon: PV2Icons.camera(20, PV2.accent),
                radius: 14,
                gap: 6,
                onTap: _addPhoto,
              ),
          ],
        ),
        // Dual layout — only offered once there IS a background photo to
        // inset onto, and only for a single-photo post: a carousel plus an
        // inset has no defined rendering (the feed's DualPhotoView draws
        // one background, not a swipeable set).
        if (_photos.length == 1) ...[
          const SizedBox(height: 14),
          _FieldLabel(
            _dualInset == null
                ? 'Dual photo — add a second, smaller photo on top'
                : 'Dual photo added · tap to replace',
            opacity: 0.35,
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _pickDualInset,
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                Container(
                  width: 62,
                  height: 78,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: PV2.raised,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _dualInset == null
                          ? Colors.white.withValues(alpha: 0.12)
                          : PV2.accent.withValues(alpha: 0.55),
                    ),
                  ),
                  child: _dualInset == null
                      ? Icon(Icons.add_rounded,
                          size: 20, color: PV2.accent)
                      : Image.file(File(_dualInset!.path), fit: BoxFit.cover),
                ),
                const SizedBox(width: 12),
                if (_dualInset != null)
                  GestureDetector(
                    onTap: () => setState(() => _dualInset = null),
                    child: Text('Remove',
                        style: PV2.body(size: 12.5, color: PV2.danger)),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 14),
        _InputCard(
          // This caption becomes the post's single-line card headline on
          // both the feed (DesignGroupCard) and this group's own profile
          // (GroupProfilePostCard) — same downstream shape as a Moment's
          // caption, so it gets the same hard cap rather than an unbounded
          // field that would just get ellipsized unpredictably later.
          label: 'Caption',
          field: TextField(
            controller: _caption,
            onChanged: (_) => setState(() {}),
            maxLines: 1,
            maxLength: kMomentCaptionMaxChars,
            cursorColor: PV2.accent,
            style: PV2.body(size: 14),
            buildCounter:
                (
                  context, {
                  required currentLength,
                  required isFocused,
                  maxLength,
                }) => Text(
                  '$currentLength/$maxLength',
                  style: PV2.body(
                    size: 10,
                    weight: FontWeight.w700,
                    color: currentLength >= (maxLength ?? 0)
                        ? PV2.accent
                        : PV2.inkStamp,
                  ),
                ),
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              errorBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              focusedErrorBorder: InputBorder.none,
              hintText: 'Say something…',
              hintStyle: PV2.body(size: 14, color: PV2.inkStamp),
            ),
          ),
        ),
        const SizedBox(height: 10),
        _InputCard(
          // Body text below the photo — a real paragraph, so it keeps
          // multiple lines and a longer cap than the caption above.
          label: 'Note',
          field: TextField(
            controller: _note,
            onChanged: (_) => setState(() {}),
            maxLines: 4,
            maxLength: _kGroupNoteMaxChars,
            cursorColor: PV2.accent,
            style: PV2.body(size: 14),
            buildCounter:
                (
                  context, {
                  required currentLength,
                  required isFocused,
                  maxLength,
                }) => Text(
                  '$currentLength/$maxLength',
                  style: PV2.body(
                    size: 10,
                    weight: FontWeight.w700,
                    color: currentLength >= (maxLength ?? 0)
                        ? PV2.accent
                        : PV2.inkStamp,
                  ),
                ),
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              errorBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              focusedErrorBorder: InputBorder.none,
              hintText: 'A detail worth remembering…',
              hintStyle: PV2.body(size: 14, color: PV2.inkStamp),
            ),
          ),
        ),
        const SizedBox(height: 10),
        _InputCard(
          label: 'Location',
          field: TextField(
            controller: _place,
            onChanged: (_) => setState(() {}),
            cursorColor: PV2.accent,
            style: PV2.body(size: 14),
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              errorBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              focusedErrorBorder: InputBorder.none,
              hintText: 'Where was this?',
              hintStyle: PV2.body(size: 14, color: PV2.inkStamp),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _pickTakenAt,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              decoration: BoxDecoration(
                color: PV2.raised,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.event_outlined,
                    size: 18,
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _takenAt == null
                          ? 'When did this happen?'
                          : '${_takenAt!.day}/${_takenAt!.month}/${_takenAt!.year}',
                      style: PV2.body(
                        size: 13.5,
                        weight: FontWeight.w600,
                        color: _takenAt == null
                            ? PV2.inkStamp
                            : Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                  ),
                  if (_takenAt != null)
                    GestureDetector(
                      onTap: () => setState(() => _takenAt = null),
                      child: Icon(
                        Icons.close_rounded,
                        size: 16,
                        color: Colors.white.withValues(alpha: 0.4),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _privateToggle(),
        const SizedBox(height: 12),
        if (!_private) ...[
        _FieldLabel('Also show to (optional)', opacity: 0.35),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _audienceChip(
              // The Friends circle can be renamed, so show its current name.
              label: (_circles ?? const <CircleOption>[])
                      .where((c) => c.isFriends)
                      .firstOrNull
                      ?.name ??
                  'Friends',
              selected: _includeFriends,
              onTap: () => setState(() => _includeFriends = !_includeFriends),
            ),
            // Every other circle of yours (Close Friends, Family, custom).
            // The Friends circle itself is the chip above.
            for (final c in _circles ?? const <CircleOption>[])
              if (!c.isFriends)
                _audienceChip(
                  label: c.name,
                  selected: _audienceCircleIds.contains(c.id),
                  onTap: () => setState(() {
                    if (!_audienceCircleIds.remove(c.id)) {
                      _audienceCircleIds.add(c.id);
                    }
                  }),
                ),
            if (_communitiesError != null)
              _audienceChip(label: 'Retry communities', selected: false, onTap: _loadCommunities),
            for (final c in _communities ?? const <CommunityOption>[])
              _audienceChip(
                label: c.name,
                selected: _audienceCommunityIds.contains(c.id),
                onTap: () => setState(() {
                  if (!_audienceCommunityIds.remove(c.id)) {
                    _audienceCommunityIds.add(c.id);
                  }
                }),
              ),
          ],
        ),
        const SizedBox(height: 12),
        ],
        _visibilityNotice(),
        const SizedBox(height: 12),
        if (_groupHasOthers == false) ...[
          Text(
            'Waiting for members to join ${_groupName ?? 'this group'} — '
            'you can post once someone accepts the invite.',
            textAlign: TextAlign.center,
            style: PV2.body(size: 12, color: PV2.inkStamp),
          ),
          const SizedBox(height: 8),
        ] else if (missing.isNotEmpty) ...[
          Text(
            'Add ${missing.length == 1 ? missing.first : '${missing.sublist(0, missing.length - 1).join(', ')} and ${missing.last}'} to post.',
            textAlign: TextAlign.center,
            style: PV2.body(size: 12, color: PV2.inkStamp),
          ),
          const SizedBox(height: 8),
        ],
        _CommitButton(
          label: _posting ? 'Posting…' : 'Post to group',
          enabled: canPost && !_posting,
          onTap: _post,
        ),
      ],
    );
  }

  /// Explicit ask: "while posting notify them that this post is visible" —
  /// the audience chips above pick who ELSE sees a group post, and the line
  /// under it says what the group's community sees without being picked
  /// (group_post_audience_feed, 20260926060000_locked_group_posts_in_feed):
  /// a PUBLIC group's post in full; a PRIVATE group's post with only the
  /// first photo clear and the rest blurred.
  Widget _privateToggle() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _private = !_private),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: _private ? PV2.accent.withValues(alpha: 0.12) : PV2.recessed,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _private
                ? PV2.accent.withValues(alpha: 0.45)
                : Colors.white.withValues(alpha: 0.07),
          ),
        ),
        child: Row(
          children: [
            Icon(
              _private ? Icons.lock_rounded : Icons.lock_open_rounded,
              size: 18,
              color: _private ? PV2.accent : Colors.white.withValues(alpha: 0.5),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Private to the group',
                    style: PV2.body(size: 13.5, weight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Only members see it — in their feed and on the group profile.',
                    style: PV2.body(
                      size: 11.5,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
            Switch.adaptive(
              value: _private,
              activeTrackColor: PV2.accent,
              onChanged: (v) => setState(() => _private = v),
            ),
          ],
        ),
      ),
    );
  }

  Widget _visibilityNotice() {
    if (_private) {
      return Text(
        'Only members of ${_groupName ?? 'this group'} will see this post.',
        textAlign: TextAlign.center,
        style: PV2.body(size: 12, color: PV2.inkStamp),
      );
    }
    final names = [
      for (final c in _communities ?? const <CommunityOption>[])
        if (_audienceCommunityIds.contains(c.id)) c.name,
    ];
    final extras = [
      if (_includeFriends) 'your friends',
      if (names.isNotEmpty) names.join(', '),
    ];
    var text = 'Visible to everyone in ${_groupName ?? 'this group'}';
    if (extras.isNotEmpty) text += ', plus ${extras.join(' and ')}';
    text += '.';

    // Null = group visibility not loaded yet: say nothing rather than guess.
    final String? communityLine = _groupIsPublic == null
        ? null
        : _groupIsPublic!
            ? 'This group is public: anyone who visits its profile sees this post.'
            : _photos.length > 1
                ? 'Others in your community see your first photo; the rest stay '
                    'blurred unless you share it with them.'
                : 'Others in your community can see this post in their feed.';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: PV2.recessed,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.visibility_outlined,
            size: 16,
            color: Colors.white.withValues(alpha: 0.5),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text, style: PV2.body(size: 12.5, color: Colors.white.withValues(alpha: 0.8))),
                if (communityLine != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    communityLine,
                    style: PV2.body(size: 11.5, color: PV2.inkStamp),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _audienceChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? PV2.accent.withValues(alpha: 0.18) : PV2.raised,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: selected
                ? PV2.accent.withValues(alpha: 0.6)
                : Colors.white.withValues(alpha: 0.1),
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: selected
              ? PV2.body(size: 12, weight: FontWeight.w600, color: PV2.accent)
              : PV2.body(size: 12, weight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _photoThumb(int index) {
    return Stack(
      children: [
        Positioned.fill(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.file(File(_photos[index].path), fit: BoxFit.cover),
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            onTap: () => setState(() => _photos.removeAt(index)),
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.close_rounded,
                size: 13,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Duo post
// ---------------------------------------------------------------------------

/// Posting a photo into a Duo — this is now the app's only "personal
/// photo" flow (see this file's own history: FriendsPostScreen, the old
/// standalone personal-post screen, was removed). Same caption + "Also show
/// to" audience chips that screen used to offer, plus one addition: a
/// Lock/Mutual toggle.
///
/// - **Lock** keeps the photo visible only to the two album members — the
///   same "private" state the per-tile lock badge already sets, just chosen
///   up front here.
/// - **Mutual** mirrors it into `posts` with a real audience: friends of the
///   poster by default, plus whichever communities/circles are picked here —
///   exactly the audience a personal post gets. It is always visible to BOTH
///   people in the pair regardless of what's picked, because the mirrored
///   post's `partner_user_id` makes the tagged partner a full co-author (see
///   `can_view_post`) — nothing here has to re-implement that.
///
/// The other album member is never asked for — this screen only ever opens
/// from inside a specific album, so who it's with is already known.
class DuoPostScreen extends StatefulWidget {
  const DuoPostScreen({
    super.key,
    required this.albumId,
    required this.otherName,
  });

  final String albumId;
  final String otherName;

  @override
  State<DuoPostScreen> createState() => _DuoPostScreenState();
}

class _DuoPostScreenState extends State<DuoPostScreen> {
  XFile? _photo;
  final _caption = TextEditingController();

  /// Mutual by default — matches this album's own historical default
  /// (addPhoto hardcoded 'mutual', per that method's own doc on why a
  /// private-by-default photo made the sharing feature unreachable).
  bool _mutual = true;

  final Set<String> _audienceCommunityIds = {};
  final Set<String> _audienceCircleIds = {};
  List<CommunityOption>? _communities;
  String? _communitiesError;
  List<CircleOption>? _circles;

  bool _posting = false;

  @override
  void initState() {
    super.initState();
    _loadCommunities();
    _loadCircles();
  }

  Future<void> _loadCommunities() async {
    try {
      final communities = await CommunityService.instance
          .fetchJoinedCommunities();
      if (mounted) setState(() => _communities = communities);
    } catch (e) {
      if (mounted) setState(() => _communitiesError = e.toString());
    }
  }

  /// Best-effort, same as every other flow in this file — no circles just
  /// means no circle pills, never blocks posting.
  Future<void> _loadCircles() async {
    try {
      final circles = await CircleService.instance.fetchMyCircles();
      if (mounted) setState(() => _circles = circles);
    } catch (_) {}
  }

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1440,
      imageQuality: 90,
    );
    if (file == null || !mounted) return;
    setState(() => _photo = file);
  }

  bool get _canPost => !_posting && _photo != null;

  Future<void> _post() async {
    if (!_canPost) return;
    final photo = _photo!;
    final caption = _caption.text.trim();
    final mutual = _mutual;
    final communityIds = _audienceCommunityIds.toList();
    final circleIds = _audienceCircleIds.toList();
    setState(() => _posting = true);
    // Closes now; the upload runs in the background — same posture as every
    // other create-flow in this file (_reportBackgroundPostFailure).
    unawaited(
      DuoService.instance
          .addPhotoWithAudience(
            albumId: widget.albumId,
            photo: File(photo.path),
            caption: caption,
            mutual: mutual,
            communityIds: communityIds,
            circleIds: circleIds,
          )
          .catchError((_) => _reportBackgroundPostFailure('photo')),
    );
    if (!mounted) return;
    if (mutual) {
      // Not live yet: it waits for the partner to pick their side's
      // audience and approve (approve_duo_photo).
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Sent to ${widget.otherName} — it goes live when they approve'),
      ));
    }
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return _FlowScaffold(
      title: 'With ${widget.otherName}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            onTap: _pickPhoto,
            child: AspectRatio(
              aspectRatio: 1,
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: PV2.raised,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: _photo == null
                    ? Center(
                        child: Icon(
                          Icons.add_photo_alternate_outlined,
                          size: 28,
                          color: PV2.accent.withValues(alpha: 0.8),
                        ),
                      )
                    : Image.file(File(_photo!.path), fit: BoxFit.cover),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: Text(
              'Tap the frame to change the photo',
              style: PV2.body(size: 12, color: Colors.white.withValues(alpha: 0.4)),
            ),
          ),
          const SizedBox(height: 16),
          _InputCard(
            label: 'Caption (optional)',
            field: TextField(
              controller: _caption,
              cursorColor: PV2.accent,
              style: PV2.body(size: 14),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                hintText: 'Say something…',
                hintStyle: PV2.body(size: 14, color: PV2.inkStamp),
              ),
            ),
          ),
          const SizedBox(height: 14),
          _FieldLabel('Who can see it', opacity: 0.35),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _lockMutualChip(
                  label: 'Lock — just us two',
                  icon: PV2Icons.lock(
                    13,
                    _mutual ? Colors.white.withValues(alpha: 0.5) : PV2.accent,
                  ),
                  selected: !_mutual,
                  onTap: () => setState(() => _mutual = false),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _lockMutualChip(
                  label: 'Mutual — my audience',
                  icon: PV2Icons.globe(
                    13,
                    _mutual ? PV2.accent : Colors.white.withValues(alpha: 0.5),
                  ),
                  selected: _mutual,
                  onTap: () => setState(() => _mutual = true),
                ),
              ),
            ],
          ),
          if (_mutual) ...[
            const SizedBox(height: 14),
            _FieldLabel('Your side — ${widget.otherName} picks theirs', opacity: 0.35),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (_circles == null || _circles!.isEmpty)
                  _audienceChip(label: 'Friends', selected: true, onTap: () {})
                else
                  for (final c in _circles!)
                    _audienceChip(
                      label: c.name,
                      selected: CircleAudience.isSelected(_audienceCircleIds, c.id, _circles),
                      onTap: () => setState(
                        () => CircleAudience.toggle(_audienceCircleIds, c.id, _circles),
                      ),
                    ),
              ],
            ),
            const SizedBox(height: 14),
            _FieldLabel('Also show to (optional)', opacity: 0.35),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (_communitiesError != null)
                  _audienceChip(
                    label: 'Retry communities',
                    selected: false,
                    onTap: _loadCommunities,
                  ),
                for (final c in _communities ?? const <CommunityOption>[])
                  _audienceChip(
                    label: c.name,
                    selected: _audienceCommunityIds.contains(c.id),
                    onTap: () => setState(() {
                      if (!_audienceCommunityIds.remove(c.id)) {
                        _audienceCommunityIds.add(c.id);
                      }
                    }),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          _CommitButton(
            label: _posting ? 'Posting…' : 'Post',
            enabled: _canPost,
            onTap: _post,
          ),
        ],
      ),
    );
  }

  Widget _lockMutualChip({
    required String label,
    required Widget icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: selected ? PV2.accent.withValues(alpha: 0.18) : PV2.raised,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? PV2.accent.withValues(alpha: 0.6)
                : Colors.white.withValues(alpha: 0.1),
          ),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            icon,
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: selected
                    ? PV2.body(size: 12, weight: FontWeight.w700, color: PV2.accent)
                    : PV2.body(size: 12, weight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _audienceChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? PV2.accent.withValues(alpha: 0.18) : PV2.raised,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: selected
                ? PV2.accent.withValues(alpha: 0.6)
                : Colors.white.withValues(alpha: 0.1),
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: selected
              ? PV2.body(size: 12, weight: FontWeight.w600, color: PV2.accent)
              : PV2.body(size: 12, weight: FontWeight.w600),
        ),
      ),
    );
  }
}
