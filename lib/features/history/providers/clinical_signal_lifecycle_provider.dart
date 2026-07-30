import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/data/providers/reference_data_provider.dart'
    as reference_data;
import 'package:pharmaguide/features/stack/providers/stack_providers.dart';
import 'package:pharmaguide/services/crash_reporting_service.dart';
import 'package:pharmaguide/services/signals/clinical_signal_lifecycle_service.dart';
import 'package:pharmaguide/services/signals/stack_signal_aggregator.dart';
import 'package:pharmaguide/services/stack/depletion_checker.dart';

/// Keeps the canonical on-device clinical-signal lifecycle synchronized with
/// the current Stack analysis.
///
/// Empty results only resolve previous signals when every analysis source and
/// provenance lookup completed. An unavailable/partial check therefore
/// remains fail-closed and can never erase history as a false all-clear.
final clinicalSignalLifecycleProvider = FutureProvider<SignalLifecycleDiff>((
  ref,
) async {
  final report = await ref.watch(stackSafetyReportProvider.future);
  final depletionReport = await ref.watch(depletionReportProvider.future);
  final signals = allClinicalSignalsFrom(
    report: report,
    medicationNutrientMatches: depletionReport.matches,
  );

  var analysisComplete =
      !report.checksIncomplete &&
      !report.coverageIncomplete &&
      depletionReport.status == MedNutrientLoadStatus.loaded;
  String? catalogVersion;
  String? ruleVersion;

  try {
    catalogVersion = await ref
        .read(coreDatabaseProvider)
        .validateCatalogSnapshot();
  } on Object catch (error, stackTrace) {
    analysisComplete = false;
    CrashReportingService().recordError(
      error,
      stackTrace,
      hint: 'clinical_signal_lifecycle:catalog_version_unavailable',
    );
  }

  try {
    final interactionVersion =
        (await ref.read(interactionDatabaseProvider).getMetadata())
            .interactionDbVersion;
    final depletionArtifact = await ref
        .read(reference_data.referenceDataRepositoryProvider)
        .loadMedicationDepletions();
    final metadata = depletionArtifact.data['_metadata'];
    final clinicalVersion = metadata is Map
        ? metadata['content_version']?.toString()
        : null;
    ruleVersion = [
      'interaction:$interactionVersion',
      if (clinicalVersion != null) 'medication_nutrient:$clinicalVersion',
    ].join('|');
  } on Object catch (error, stackTrace) {
    analysisComplete = false;
    CrashReportingService().recordError(
      error,
      stackTrace,
      hint: 'clinical_signal_lifecycle:rule_version_unavailable',
    );
  }

  return ClinicalSignalLifecycleService(
    ref.read(healthEventRepositoryProvider),
  ).reconcile(
    currentSignals: signals,
    analysisComplete: analysisComplete,
    ruleVersion: ruleVersion,
    catalogVersion: catalogVersion,
  );
});
