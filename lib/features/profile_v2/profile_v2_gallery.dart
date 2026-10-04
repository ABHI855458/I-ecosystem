import 'package:flutter/material.dart';

import 'group_profile_v2_screen.dart';
import 'my_profile_screen.dart';
import 'profile_v2_data.dart';
import 'profile_v2_tokens.dart';
import 'their_profile_screen.dart';

/// A review harness for the three Profile v2 screens, mirroring the switcher at
/// the top of the design canvas.
///
/// This is a development surface, not a product screen — the real app pushes
/// [TheirProfileScreen], [MyProfileScreen] and [GroupProfileV2Screen] as
/// routes. Point `main.dart` at this to flip between all three without
/// navigating, which is also what makes them screenshot-able side by side.
class ProfileV2Gallery extends StatefulWidget {
  const ProfileV2Gallery({super.key, this.initial = 0});

  final int initial;

  @override
  State<ProfileV2Gallery> createState() => _ProfileV2GalleryState();
}

class _ProfileV2GalleryState extends State<ProfileV2Gallery> {
  late int _screen = widget.initial;

  static const _labels = ['Their profile', 'My profile', 'Group'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PV2.page,
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: PV2.columnWidth),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
                  child: Row(
                    children: [
                      for (var i = 0; i < _labels.length; i++) ...[
                        if (i > 0) const SizedBox(width: 6),
                        Expanded(child: _navButton(i)),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: _screen,
              children: const [
                TheirProfileScreen(showBackButton: false),
                // Only call site allowed to pass mock data — see
                // MyProfileScreen.me's doc.
                MyProfileScreen(me: PV2Data.me, isDesignPreview: true),
                GroupProfileV2Screen(showBackButton: false),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _navButton(int index) {
    final on = index == _screen;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _screen = index),
        borderRadius: BorderRadius.circular(15),
        child: Container(
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? PV2.recessed : PV2.raised,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: on ? PV2.hairlineActive : PV2.hairline,
            ),
          ),
          child: Text(
            _labels[index],
            style: PV2.body(
              size: 11,
              weight: FontWeight.w700,
              color: on ? Colors.white : Colors.white.withValues(alpha: 0.45),
            ),
          ),
        ),
      ),
    );
  }
}
