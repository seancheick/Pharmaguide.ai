// ShareClinicianReportButton — UI entrypoint that gathers on-device
// state (profile + stack + safety reports), runs them through
// `ClinicianReportBuilder`, and hands the markdown to the system share
// sheet via `ShareService`.
//
// Spec: INITIATIVE_STACK_INTELLIGENCE.md, Track C, C3.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/models/interaction_result.dart';
import 'package:pharmaguide/core/models/synergy_result.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/stack/providers/stack_providers.dart';
import 'package:pharmaguide/services/sharing/clinician_report_builder.dart';
import 'package:pharmaguide/services/sharing/share_service.dart';
import 'package:pharmaguide/services/stack/stack_intelligence_engine.dart';
import 'package:pharmaguide/services/stack/stack_safety_scorer.dart';

/// Tappable share-icon button. Place inside an `AppBar.actions` list on
/// the stack screen.
///
/// `shareService` is an optional override for unit tests so they can
/// capture the markdown handed to the share sheet without invoking a
/// real platform channel. Production callers omit it and the default
/// `ShareService()` runs through `share_plus`.
class ShareClinicianReportButton extends ConsumerWidget {
  const ShareClinicianReportButton({super.key, this.shareService});

  final ShareService? shareService;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      tooltip: 'Share with clinician',
      icon: const Icon(Icons.ios_share_rounded),
      onPressed: () => _onTap(context, ref),
    );
  }

  Future<void> _onTap(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final service = shareService ?? ShareService();

    try {
      // Snapshot every input the builder needs at the moment of tap.
      // Each `read` returns the latest cached value if loaded; the
      // `.future` form awaits if still in flight.
      final userDb = ref.read(userDatabaseProvider);
      final profile = await userDb.getProfile();
      final stack = await ref.read(activeStackProvider.future);
      final safetyReport = await ref.read(stackSafetyReportProvider.future);
      final synergyReport = await ref.read(synergyReportProvider.future);
      final recalledReport = await ref.read(
        recalledIngredientsReportProvider.future,
      );

      // Quality score: feed the safety scorer with the same shape
      // home_stack_health uses so the diagnosis tier matches what the
      // user sees on the home screen.
      final allIssues = <InteractionResult>[
        ...safetyReport.medicationPairInteractions,
        ...safetyReport.medicationInteractions,
        ...safetyReport.stackInteractions,
        ...safetyReport.categoryWarnings,
      ];
      final synergies = synergyReport.matches
          .map(
            (m) => SynergyResult(
              ingredient1: m.matchedIngredients.isNotEmpty
                  ? m.matchedIngredients.first
                  : m.clusterId,
              ingredient2: m.matchedIngredients.length > 1
                  ? m.matchedIngredients[1]
                  : m.clusterName,
              description: m.mechanism,
              evidenceLevel: EvidenceLevel.established,
              bonus: m.bonusPoints,
            ),
          )
          .toList(growable: false);
      final safetyScore = const StackSafetyScorer().compute(
        issues: allIssues,
        synergies: synergies,
      );

      final intelligence = const StackIntelligenceEngine().diagnose(
        stackSize: stack.length,
        safetyReport: safetyReport,
        recalledReport: recalledReport,
        synergyReport: synergyReport,
        qualityScore: safetyScore.score,
      );

      final markdown = const ClinicianReportBuilder().build(
        profile: profile,
        stack: stack,
        intelligence: intelligence,
        generatedAt: DateTime.now(),
      );

      await service.shareClinicianReport(markdown);
    } on Object {
      // Anything failing in the input collection (DB, providers) drops
      // a non-blocking error to the user and bails. The share sheet
      // never opens with partial data.
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not build the report — try again in a moment.'),
          duration: Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}
