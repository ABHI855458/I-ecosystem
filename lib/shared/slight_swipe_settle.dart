import 'package:flutter/widgets.dart';

/// Page physics where a light swipe commits the turn, but the settle
/// animation still ends at Flutter's normal tolerance.
///
/// Both pagers (MainShell's tabs, HomeScreen's Dip/Friends) used to lower
/// `toleranceFor(...).velocity` to 0.2 so any still-moving release carries
/// the page across. PageScrollPhysics uses that same tolerance for TWO
/// things: which page to land on, and when the spring simulation counts as
/// finished. The second one hurt: a Scrollable ignores all pointers while
/// its ballistic activity runs, so the long-tailed settle left the page
/// under it (Ping especially) refusing to scroll for a moment after every
/// swipe — "sometimes I'm unable to scroll the ping page".
///
/// So the landing decision keeps the 0.2 threshold, and the simulation gets
/// the default tolerance back.
mixin SlightSwipeSettle on PageScrollPhysics {
  static const double _commitVelocity = 0.2;

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    // Overscrolled past either end: the stock behaviour (spring back).
    if ((velocity <= 0.0 && position.pixels <= position.minScrollExtent) ||
        (velocity >= 0.0 && position.pixels >= position.maxScrollExtent)) {
      return super.createBallisticSimulation(position, velocity);
    }
    final fraction =
        position is PageMetrics ? position.viewportFraction : 1.0;
    final pageExtent = position.viewportDimension * fraction;
    if (pageExtent <= 0) return super.createBallisticSimulation(position, velocity);

    var page = position.pixels / pageExtent;
    if (velocity < -_commitVelocity) {
      page -= 0.5;
    } else if (velocity > _commitVelocity) {
      page += 0.5;
    }
    final target = (page.roundToDouble() * pageExtent)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    if ((target - position.pixels).abs() < 0.5) return null;
    return ScrollSpringSimulation(
      spring,
      position.pixels,
      target,
      velocity,
      tolerance: toleranceFor(position), // default — see class doc
    );
  }
}
