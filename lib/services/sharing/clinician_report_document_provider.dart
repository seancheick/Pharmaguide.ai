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
import 'package:pharmaguide/services/sharing/clinician_report_data.dart';
import 'package:pharmaguide/services/stack/stack_intelligence_engine.dart';

export 'package:pharmaguide/services/sharing/clinician_report_data.dart';

/// The single canonical stack-export snapshot.
///
/// Profile and Stack surfaces, the clinician PDF and the AI brief all consume
/// this provider. Keeping collection here prevents any entry point from
/// silently omitting a safety provider, provenance field, or
/// unavailable-analysis state. Everything is read on this device; nothing
/// here touches the network.
final clinicianReportDataProvider =
    FutureProvider.autoDispose<ClinicianReportData>((ref) async {
      try {
        return await _collectClinicianReportData(ref);
      } on Object catch (error, stackTrace) {
        CrashReportingService().recordError(
          error,
          stackTrace,
          hint: 'clinician_report:collect_failed',
        );
        rethrow;
      }
    });

/// The clinician PDF rendered from [clinicianReportDataProvider].
final clinicianReportDocumentProvider = FutureProvider.autoDispose<Uint8List>((
  ref,
) async {
  try {
    final data = await ref.watch(clinicianReportDataProvider.future);
    return await _buildClinicianReportDocument(data);
  } on Object catch (error, stackTrace) {
    CrashReportingService().recordError(
      error,
      stackTrace,
      hint: 'clinician_report:build_failed',
    );
    rethrow;
  }
});

Future<ClinicianReportData> _collectClinicianReportData(Ref ref) async {
  final generatedAt = DateTime.now();
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
    // loaded/partial/unavailable report into an empty or false-all-clear
    // export.
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

  final intelligence = const StackIntelligenceEngine().diagnoseFromReports(
    stackSize: stack.length,
    safetyReport: safetyReport,
    recalledReport: recalledReport,
    synergyReport: synergyReport,
    doseThresholdAlerts: doseAlerts,
  );

  return ClinicianReportData(
    profile: profile,
    stack: stack,
    intelligence: intelligence,
    safetyReport: safetyReport,
    depletions: depletionReport.matches,
    depletionStatus: depletionReport.status,
    doseThresholdAlerts: doseAlerts,
    clinicalDataVersion: depletionMetadata['content_version']?.toString(),
    clinicalDataHash: depletionMetadata['content_hash']?.toString(),
    productCatalogVersion: productCatalogVersion,
    interactionRulesVersion: interactionRulesVersion,
    medicationIdentityStatuses: medicationIdentityStatuses,
    conditionLabels: {
      for (final condition in clinicalProfileSchema.selectableConditions)
        condition.id: condition.label,
    },
    generatedAt: generatedAt,
  );
}

Future<Uint8List> _buildClinicianReportDocument(
  ClinicianReportData data,
) async {
  final assets = await Future.wait<ByteData>([
    rootBundle.load('assets/images/report_logo.png'),
    rootBundle.load('assets/fonts/Geist-Regular.ttf'),
    rootBundle.load('assets/fonts/Geist-Medium.ttf'),
  ]);

  return const ClinicianPdfBuilder().build(
    profile: data.profile,
    stack: data.stack,
    intelligence: data.intelligence,
    safetyReport: data.safetyReport,
    depletions: data.depletions,
    depletionStatus: data.depletionStatus,
    clinicalDataVersion: data.clinicalDataVersion,
    clinicalDataHash: data.clinicalDataHash,
    productCatalogVersion: data.productCatalogVersion,
    interactionRulesVersion: data.interactionRulesVersion,
    medicationIdentityStatuses: data.medicationIdentityStatuses,
    conditionLabels: data.conditionLabels,
    generatedAt: data.generatedAt,
    logoBytes: _assetBytes(assets[0]),
    regularFontBytes: _assetBytes(assets[1]),
    mediumFontBytes: _assetBytes(assets[2]),
  );
}

Uint8List _assetBytes(ByteData data) {
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}
