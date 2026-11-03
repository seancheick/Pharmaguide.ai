import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/core/widgets/pg_severity_banner.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';

const String kRulesWithheldNotice =
    'Interaction checks are temporarily unavailable. Product information is '
    'still available.';

const String kQualityWithheldNotice =
    'Quality scores are temporarily unavailable. Product information is still '
    'available.';

/// Notices above a list that fills the rest of the screen. An upright phone
/// keeps 400 points for the app bar and the list; on a short screen, such as a
/// phone on its side, the notices stop at 30% and scroll.
class WithheldNoticeArea extends StatelessWidget {
  const WithheldNoticeArea({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final visibleHeight =
        MediaQuery.sizeOf(context).height -
        MediaQuery.viewInsetsOf(context).bottom;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: math.max(visibleHeight * 0.3, visibleHeight - 400),
      ),
      child: SingleChildScrollView(
        primary: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }
}

/// Rules that are withheld (ADR-012) or failed to open leave
/// [interactionDatabaseProvider] failing, and that failure is the one signal.
/// Watch this on any screen that could otherwise read as a clean result.
bool interactionRulesUnavailable(WidgetRef ref) {
  try {
    ref.watch(interactionDatabaseProvider);
    return false;
  } on Object {
    return true;
  }
}

/// Stays on screen for as long as the checks are withheld. Shows nothing
/// otherwise.
class RulesWithheldNotice extends ConsumerWidget {
  const RulesWithheldNotice({super.key, this.margin = EdgeInsets.zero});

  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!interactionRulesUnavailable(ref)) return const SizedBox.shrink();
    return PGSeverityBanner(
      key: const Key('rules-withheld-notice'),
      tone: PGBannerTone.neutral,
      title: kRulesWithheldNotice,
      margin: margin,
    );
  }
}

/// False when no catalog is open, since there are no scores to withhold then.
bool qualityScoresWithheld(WidgetRef ref) {
  try {
    return ref.watch(coreDatabaseProvider).qualityWithheld;
  } on Object {
    return false;
  }
}

/// Stays on screen for as long as the catalog in use has its scores withheld.
/// Shows nothing otherwise.
class QualityWithheldNotice extends ConsumerWidget {
  const QualityWithheldNotice({super.key, this.margin = EdgeInsets.zero});

  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!qualityScoresWithheld(ref)) return const SizedBox.shrink();
    return PGSeverityBanner(
      key: const Key('quality-withheld-notice'),
      tone: PGBannerTone.neutral,
      title: kQualityWithheldNotice,
      margin: margin,
    );
  }
}
