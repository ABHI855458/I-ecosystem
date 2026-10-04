import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'profile_v2_sections.dart' show AccentButton;
import '../../services/circle_service.dart';
import '../../services/community_service.dart';
import 'profile_v2_tokens.dart';
import 'profile_v2_widgets.dart';

/// What the viewer picked in [showAudiencePickerSheet].
class AudienceChoice {
  const AudienceChoice({required this.circleIds, required this.communityIds});

  /// Empty = "my Friends circle" (the default; see CircleAudience).
  final Set<String> circleIds;
  final Set<String> communityIds;
}

/// "Who sees it on your side" — your circles (Friends preselected) plus any
/// of your communities. Shared by the two places someone ELSE's post asks
/// for YOUR audience:
///  * approving a Duo photo your partner added (approve_duo_photo), and
///  * sharing a group post onward (share_group_post).
///
/// Returns null on dismiss. [initialCircleIds]/[initialCommunityIds] pre-fill
/// a previous choice.
Future<AudienceChoice?> showAudiencePickerSheet(
  BuildContext context, {
  required String title,
  required String subtitle,
  required String confirmLabel,
  Set<String> initialCircleIds = const {},
  Set<String> initialCommunityIds = const {},
}) {
  return showModalBottomSheet<AudienceChoice>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AudiencePickerSheet(
      title: title,
      subtitle: subtitle,
      confirmLabel: confirmLabel,
      initialCircleIds: initialCircleIds,
      initialCommunityIds: initialCommunityIds,
    ),
  );
}

class _AudiencePickerSheet extends StatefulWidget {
  const _AudiencePickerSheet({
    required this.title,
    required this.subtitle,
    required this.confirmLabel,
    required this.initialCircleIds,
    required this.initialCommunityIds,
  });

  final String title;
  final String subtitle;
  final String confirmLabel;
  final Set<String> initialCircleIds;
  final Set<String> initialCommunityIds;

  @override
  State<_AudiencePickerSheet> createState() => _AudiencePickerSheetState();
}

class _AudiencePickerSheetState extends State<_AudiencePickerSheet> {
  List<CircleOption>? _circles;
  List<CommunityOption>? _communities;
  late final Set<String> _circleIds = {...widget.initialCircleIds};
  late final Set<String> _communityIds = {...widget.initialCommunityIds};

  @override
  void initState() {
    super.initState();
    CircleService.instance.fetchMyCircles().then((c) {
      if (mounted) setState(() => _circles = c);
    }).catchError((_) {
      if (mounted) setState(() => _circles = const []);
    });
    CommunityService.instance.fetchJoinedCommunities().then((c) {
      if (mounted) setState(() => _communities = c);
    }).catchError((_) {
      if (mounted) setState(() => _communities = const []);
    });
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? PV2.accent.withValues(alpha: 0.18) : PV2.recessed,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? PV2.accent : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Text(
          label,
          style: PV2.body(
            size: 12.5,
            weight: FontWeight.w600,
            color: selected ? PV2.accent : Colors.white.withValues(alpha: 0.75),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loading = _circles == null || _communities == null;
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
        child: GlassSurface(
          radius: 20,
          fill: const Color(0xF0141416),
          border: const Color(0x14FFFFFF),
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.title, style: PV2.body(size: 15, weight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(widget.subtitle, style: PV2.body(size: 12, color: PV2.inkBio)),
              const SizedBox(height: 14),
              if (loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator(color: PV2.accent)),
                )
              else
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('YOUR CIRCLES', style: PV2.caps(size: 9, tracking: 0.14, color: PV2.inkStamp)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final c in _circles!)
                              _chip(
                                c.name,
                                CircleAudience.isSelected(_circleIds, c.id, _circles),
                                () => setState(() => CircleAudience.toggle(_circleIds, c.id, _circles)),
                              ),
                          ],
                        ),
                        if (_communities!.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Text('ALSO SHOW TO', style: PV2.caps(size: 9, tracking: 0.14, color: PV2.inkStamp)),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final c in _communities!)
                                _chip(
                                  c.name,
                                  _communityIds.contains(c.id),
                                  () => setState(() {
                                    if (!_communityIds.remove(c.id)) _communityIds.add(c.id);
                                  }),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: AccentButton(
                  label: widget.confirmLabel,
                  onTap: loading
                      ? null
                      : () => Navigator.of(context).pop(
                            AudienceChoice(circleIds: _circleIds, communityIds: _communityIds),
                          ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
