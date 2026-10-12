// Canonical, comparable encoding of engine findings. Shared by the spike entry
// (compiled against the overlay) and the app-side golden parity test
// (compiled against the real lib/), so both sides serialize identically.
import 'package:pharmaguide/core/models/interaction_result.dart';
import 'package:pharmaguide/services/stack/depletion_checker.dart';

Map<String, Object?> encodeInteraction(InteractionResult r) => {
  'id': r.id,
  'type': r.type.name,
  'severity': r.severity.name,
  'curated_severity': r.curatedSeverity?.name,
  'evidence_level': r.evidenceLevel.name,
  'effect_type': r.effectType?.name,
  'agent1': r.agent1Name,
  'agent2': r.agent2Name,
  'source': r.source.name,
  'matched_supplement': r.matchedSupplementCanonicalId,
  'matched_med_classes': r.matchedMedicationClassIds,
  'dose_dependent': r.doseDependant,
  'source_urls': r.sourceUrls,
  'mechanism': r.mechanism,
  'management': r.management,
};

Map<String, Object?> encodeDepletion(DepletionMatch m) => {
  'id': m.depletionId,
  'drug': m.drugDisplayName,
  'drug_class': m.drugClassId,
  'nutrient': m.nutrientCanonicalId,
  'type': m.depletionType,
  'severity': m.severity,
  'evidence_level': m.evidenceLevel,
  'source_urls': m.sourceUrls,
};

Map<String, Object?> encodeFindings({
  required List<InteractionResult> preAddResults,
  required bool preAddChecksIncomplete,
  required String depletionStatus,
  required List<DepletionMatch> depletions,
}) => {
  'pre_add': {
    'checks_incomplete': preAddChecksIncomplete,
    'results': [for (final r in preAddResults) encodeInteraction(r)],
  },
  'depletion': {
    'status': depletionStatus,
    'matches': [for (final m in depletions) encodeDepletion(m)],
  },
};
