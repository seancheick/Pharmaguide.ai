import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/data/providers/reference_data_provider.dart'
    as reference_data;
import 'package:pharmaguide/features/stack/providers/medication_identity_providers.dart';
import 'package:pharmaguide/features/stack/providers/stack_providers.dart';
import 'package:pharmaguide/services/crash_reporting_service.dart';
import 'package:pharmaguide/services/medications/medication_identity_status.dart';
import 'package:pharmaguide/services/sharing/clinician_pdf_builder.dart';
import 'package:pharmaguide/services/stack/stack_intelligence_engine.dart';

/// The single canonical clinician-report snapshot.
///
/// Profile and Stack surfaces both consume this provider. Keeping collection
/// and PDF assembly here prevents either entry point from silently omitting a
/// safety provider, provenance field, or unavailable-analysis state.
final clinicianReportDocumentProvider = FutureProvider.autoDispose<Uint8List>((
  ref,
) async {
  try {
    return await _buildClinicianReportDocument(ref);
  } on Object catch (error, stackTrace) {
    CrashReportingService().recordError(
      error,
      stackTrace,
      hint: 'clinician_report:build_failed',
    );
    rethrow;
  }
});

Future<Uint8List> _buildClinicianReportDocument(Ref ref) async {
  final userDb = ref.read(userDatabaseProvider);
  final profile = await userDb.getProfile();
  final referenceDataRepository = ref.read(
    reference_data.referenceDataRepositoryProvider,
  );
  final clinicalProfileSchema = await referenceDataRepository
      .loadClinicalProfileSchema();
  final stack = await ref.read(activeStackProvider.future);
  final medicationIdentityStatuses =
      stack.any((entry) => entry.type == 'medication')
      ? (await ref.read(
          medicationIdentityAssessmentsProvider.future,
        )).map((id, assessment) => MapEntry(id, assessment.status))
      : const <String, MedicationIdentityStatus>{};
  final safetyReport = await ref.read(stackSafetyReportProvider.future);
  final synergyReport = await ref.read(synergyReportProvider.future);
  final recalledReport = await ref.read(
    recalledIngredientsReportProvider.future,
  );
  final depletionReport = await ref.read(depletionReportProvider.future);
  final doseAlerts = await ref.read(stackDoseThresholdAlertsProvider.future);

  Map<String, dynamic> depletionMetadata = const <String, dynamic>{};
  try {
    final depletionArtifact = await referenceDataRepository
        .loadMedicationDepletions();
    final rawMetadata = depletionArtifact.data['_metadata'];
    if (rawMetadata is Map) {
      depletionMetadata = Map<String, dynamic>.from(rawMetadata);
    }
  } on Object catch (error, stackTrace) {
    // Provenance is useful context, but its absence must not turn a valid
    // loaded/partial/unavailable report into an empty or false-all-clear PDF.
    CrashReportingService().recordError(
      error,
      stackTrace,
      hint: 'clinician_report:clinical_metadata_unavailable',
    );
  }

  String? productCatalogVersion;
  try {
    productCatalogVersion = await ref
        .read(coreDatabaseProvider)
        .validateCatalogSnapshot();
  } on Object catch (error, stackTrace) {
    CrashReportingService().recordError(
      error,
      stackTrace,
      hint: 'clinician_report:catalog_metadata_unavailable',
    );
  }

  String? interactionRulesVersion;
  try {
    final interactionMetadata = await ref
        .read(interactionDatabaseProvider)
        .getMetadata();
    interactionRulesVersion = interactionMetadata.interactionDbVersion;
  } on Object catch (error, stackTrace) {
    CrashReportingService().recordError(
      error,
      stackTrace,
      hint: 'clinician_report:interaction_metadata_unavailable',
    );
  }

  final assets = await Future.wait<ByteData>([
    rootBundle.load('assets/images/report_logo.png'),
    rootBundle.load('assets/fonts/Geist-Regular.ttf'),
    rootBundle.load('assets/fonts/Geist-Medium.ttf'),
  ]);

  final intelligence = const StackIntelligenceEngine().diagnoseFromReports(
    stackSize: stack.length,
    safetyReport: safetyReport,
    recalledReport: recalledReport,
    synergyReport: synergyReport,
    doseThresholdAlerts: doseAlerts,
  );

  return const ClinicianPdfBuilder().build(
    profile: profile,
    stack: stack,
    intelligence: intelligence,
    safetyReport: safetyReport,
    depletions: depletionReport.matches,
    depletionStatus: depletionReport.status,
    clinicalDataVersion: depletionMetadata['content_version']?.toString(),
    clinicalDataHash: depletionMetadata['content_hash']?.toString(),
    productCatalogVersion: productCatalogVersion,
    interactionRulesVersion: interactionRulesVersion,
    medicationIdentityStatuses: medicationIdentityStatuses,
    conditionLabels: {
      for (final condition in clinicalProfileSchema.selectableConditions)
        condition.id: condition.label,
    },
    generatedAt: DateTime.now(),
    logoBytes: _assetBytes(assets[0]),
    regularFontBytes: _assetBytes(assets[1]),
    mediumFontBytes: _assetBytes(assets[2]),
  );
}

Uint8List _assetBytes(ByteData data) {
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}
