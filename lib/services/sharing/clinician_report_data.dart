import 'package:pharmaguide/core/models/stack_intelligence.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/services/medications/medication_identity_status.dart';
import 'package:pharmaguide/services/stack/depletion_checker.dart';
import 'package:pharmaguide/services/stack/stack_dose_summer.dart';
import 'package:pharmaguide/services/stack/stack_safety_report.dart';

/// The single collected snapshot behind every stack export.
///
/// The clinician PDF, the AI brief and (later) the consented connector
/// snapshot all render from this one value, so no export can silently omit
/// a safety provider, a provenance field or an unavailable-analysis state.
/// Collection lives in `clinician_report_document_provider.dart`; this type
/// imports no Flutter, Riverpod or network code so renderers stay pure.
class ClinicianReportData {
  const ClinicianReportData({
    required this.profile,
    required this.stack,
    required this.intelligence,
    required this.safetyReport,
    required this.depletions,
    required this.generatedAt,
    this.depletionStatus = MedNutrientLoadStatus.loaded,
    this.doseThresholdAlerts = const <StackDoseThresholdAlert>[],
    this.clinicalDataVersion,
    this.clinicalDataHash,
    this.productCatalogVersion,
    this.interactionRulesVersion,
    this.medicationIdentityStatuses =
        const <String, MedicationIdentityStatus>{},
    this.conditionLabels = const <String, String>{},
  });

  final UserProfile? profile;
  final List<UserStacksLocalData> stack;
  final StackIntelligence intelligence;
  final StackSafetyReport safetyReport;
  final List<DepletionMatch> depletions;
  final MedNutrientLoadStatus depletionStatus;
  final List<StackDoseThresholdAlert> doseThresholdAlerts;
  final String? clinicalDataVersion;
  final String? clinicalDataHash;
  final String? productCatalogVersion;
  final String? interactionRulesVersion;
  final Map<String, MedicationIdentityStatus> medicationIdentityStatuses;
  final Map<String, String> conditionLabels;
  final DateTime generatedAt;

  List<UserStacksLocalData> get medications =>
      stack.where((e) => e.type == 'medication').toList(growable: false);

  List<UserStacksLocalData> get supplements =>
      stack.where((e) => e.type == 'supplement').toList(growable: false);
}
