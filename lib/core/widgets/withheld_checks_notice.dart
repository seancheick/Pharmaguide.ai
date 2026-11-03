import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/core/widgets/pg_severity_banner.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';

const String kRulesWithheldNotice =
    'Interaction checks are temporarily unavailable. Product information is '
    'still available.';

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
