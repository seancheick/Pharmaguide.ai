// Vocab registry — eager-load all bundled controlled vocabularies once at
// app startup, then expose synchronous lookups for widget render paths.
//
// Background:
//   The 25 vocab JSON assets in assets/data/ are the single source of
//   truth for severity/verdict/condition/etc. labels. Their per-vocab
//   loaders (loadVerdictVocab, loadSeverityVocab, ...) are async because
//   rootBundle.loadString is async.
//
//   But widget render paths (Severity-pill labels, verdict-badge colors,
//   condition picker labels) need synchronous access. Wrapping every
//   widget in a FutureBuilder would be a major refactor.
//
//   This registry preloads every vocab in parallel during app startup,
//   then exposes sync getters. Call init() before runApp(); after that,
//   any widget can do VocabRegistry.instance.verdict('SAFE')?.name.
//
// If a getter is called before init() finishes, it returns null and the
// caller is expected to fall back to its legacy hardcoded value (the
// drift contract tests in test/core/ guarantee the two sources match).

import 'package:flutter/foundation.dart';

import 'package:pharmaguide/core/data/allergen_prevalence_vocab.dart';
import 'package:pharmaguide/core/data/allergen_regulatory_status_vocab.dart';
import 'package:pharmaguide/core/data/ban_context_vocab.dart';
import 'package:pharmaguide/core/data/banned_status_vocab.dart';
import 'package:pharmaguide/core/data/clinical_indication_vocab.dart';
import 'package:pharmaguide/core/data/clinical_risk_vocab.dart';
import 'package:pharmaguide/core/data/condition_vocab.dart';
import 'package:pharmaguide/core/data/confidence_tier_vocab.dart';
import 'package:pharmaguide/core/data/drug_class_vocab.dart';
import 'package:pharmaguide/core/data/effect_direction_vocab.dart';
import 'package:pharmaguide/core/data/efsa_genotoxicity_vocab.dart';
import 'package:pharmaguide/core/data/form_factor_vocab.dart';
import 'package:pharmaguide/core/data/efsa_status_vocab.dart';
import 'package:pharmaguide/core/data/evidence_level_vocab.dart';
import 'package:pharmaguide/core/data/evidence_strength_vocab.dart';
import 'package:pharmaguide/core/data/iqm_category_vocab.dart';
import 'package:pharmaguide/core/data/legal_status_vocab.dart';
import 'package:pharmaguide/core/data/manufacturer_trust_tier_vocab.dart';
import 'package:pharmaguide/core/data/match_mode_vocab.dart';
import 'package:pharmaguide/core/data/primary_outcome_vocab.dart';
import 'package:pharmaguide/core/data/score_contribution_tier_vocab.dart';
import 'package:pharmaguide/core/data/severity_vocab.dart';
import 'package:pharmaguide/core/data/signal_strength_vocab.dart';
import 'package:pharmaguide/core/data/product_type_vocab.dart';
import 'package:pharmaguide/core/data/study_type_vocab.dart';
import 'package:pharmaguide/core/data/user_goals_vocab.dart';
import 'package:pharmaguide/core/data/verdict_vocab.dart';

class VocabRegistry {
  VocabRegistry._();
  static final VocabRegistry instance = VocabRegistry._();

  bool _initialized = false;
  bool get isInitialized => _initialized;

  Map<String, VerdictEntry> _verdicts = const {};
  Map<String, SeverityEntry> _severities = const {};
  Map<String, ConditionEntry> _conditions = const {};
  Map<String, DrugClassEntry> _drugClasses = const {};
  Map<String, UserGoalEntry> _userGoals = const {};
  Map<String, EvidenceLevelEntry> _evidenceLevels = const {};
  Map<String, EvidenceStrengthEntry> _evidenceStrengths = const {};
  Map<String, StudyTypeEntry> _studyTypes = const {};
  Map<String, ClinicalIndicationEntry> _clinicalIndications = const {};
  Map<String, IqmCategoryEntry> _iqmCategories = const {};
  Map<String, BannedStatusEntry> _bannedStatuses = const {};
  Map<String, ClinicalRiskEntry> _clinicalRisks = const {};
  Map<String, LegalStatusEntry> _legalStatuses = const {};
  Map<String, BanContextEntry> _banContexts = const {};
  Map<String, EffectDirectionEntry> _effectDirections = const {};
  Map<String, SignalStrengthEntry> _signalStrengths = const {};
  Map<String, AllergenPrevalenceEntry> _allergenPrevalences = const {};
  Map<String, AllergenRegulatoryStatusEntry> _allergenRegulatoryStatuses =
      const {};
  Map<String, ManufacturerTrustTierEntry> _manufacturerTrustTiers = const {};
  Map<String, EfsaStatusEntry> _efsaStatuses = const {};
  Map<String, EfsaGenotoxicityEntry> _efsaGenotoxicities = const {};
  Map<String, MatchModeEntry> _matchModes = const {};
  Map<String, ConfidenceTierEntry> _confidenceTiers = const {};
  Map<String, ScoreContributionTierEntry> _scoreContributionTiers = const {};
  Map<String, PrimaryOutcomeEntry> _primaryOutcomes = const {};
  Map<String, ProductTypeEntry> _productTypes = const {};
  Map<String, FormFactorEntry> _formFactors = const {};

  /// Eager-load every vocab in parallel. Call once before runApp().
  /// Idempotent — safe to call multiple times.
  Future<void> init() async {
    if (_initialized) return;
    final results = await Future.wait<dynamic>([
      loadVerdictVocab(),
      loadSeverityVocab(),
      loadConditionVocab(),
      loadDrugClassVocab(),
      loadUserGoalsVocab(),
      loadEvidenceLevelVocab(),
      loadEvidenceStrengthVocab(),
      loadStudyTypeVocab(),
      loadClinicalIndicationVocab(),
      loadIqmCategoryVocab(),
      loadBannedStatusVocab(),
      loadClinicalRiskVocab(),
      loadLegalStatusVocab(),
      loadBanContextVocab(),
      loadEffectDirectionVocab(),
      loadSignalStrengthVocab(),
      loadAllergenPrevalenceVocab(),
      loadAllergenRegulatoryStatusVocab(),
      loadManufacturerTrustTierVocab(),
      loadEfsaStatusVocab(),
      loadEfsaGenotoxicityVocab(),
      loadMatchModeVocab(),
      loadConfidenceTierVocab(),
      loadScoreContributionTierVocab(),
      loadPrimaryOutcomeVocab(),
      loadProductTypeVocab(),
      loadFormFactorVocab(),
    ]);

    _verdicts = results[0] as Map<String, VerdictEntry>;
    _severities = results[1] as Map<String, SeverityEntry>;
    _conditions = results[2] as Map<String, ConditionEntry>;
    _drugClasses = results[3] as Map<String, DrugClassEntry>;
    _userGoals = results[4] as Map<String, UserGoalEntry>;
    _evidenceLevels = results[5] as Map<String, EvidenceLevelEntry>;
    _evidenceStrengths = results[6] as Map<String, EvidenceStrengthEntry>;
    _studyTypes = results[7] as Map<String, StudyTypeEntry>;
    _clinicalIndications = results[8] as Map<String, ClinicalIndicationEntry>;
    _iqmCategories = results[9] as Map<String, IqmCategoryEntry>;
    _bannedStatuses = results[10] as Map<String, BannedStatusEntry>;
    _clinicalRisks = results[11] as Map<String, ClinicalRiskEntry>;
    _legalStatuses = results[12] as Map<String, LegalStatusEntry>;
    _banContexts = results[13] as Map<String, BanContextEntry>;
    _effectDirections = results[14] as Map<String, EffectDirectionEntry>;
    _signalStrengths = results[15] as Map<String, SignalStrengthEntry>;
    _allergenPrevalences = results[16] as Map<String, AllergenPrevalenceEntry>;
    _allergenRegulatoryStatuses =
        results[17] as Map<String, AllergenRegulatoryStatusEntry>;
    _manufacturerTrustTiers =
        results[18] as Map<String, ManufacturerTrustTierEntry>;
    _efsaStatuses = results[19] as Map<String, EfsaStatusEntry>;
    _efsaGenotoxicities = results[20] as Map<String, EfsaGenotoxicityEntry>;
    _matchModes = results[21] as Map<String, MatchModeEntry>;
    _confidenceTiers = results[22] as Map<String, ConfidenceTierEntry>;
    _scoreContributionTiers =
        results[23] as Map<String, ScoreContributionTierEntry>;
    _primaryOutcomes = results[24] as Map<String, PrimaryOutcomeEntry>;
    _productTypes = results[25] as Map<String, ProductTypeEntry>;
    _formFactors = results[26] as Map<String, FormFactorEntry>;

    _initialized = true;
  }

  // ── Sync lookups ──────────────────────────────────────────────────────
  // Each returns null if (a) vocab not yet loaded, or (b) ID not in vocab.
  // Callers should fall back to their legacy hardcoded value when null.

  VerdictEntry? verdict(String id) => _verdicts[id];
  SeverityEntry? severity(String id) => _severities[id];
  ConditionEntry? condition(String id) => _conditions[id];
  DrugClassEntry? drugClass(String id) => _drugClasses[id];
  UserGoalEntry? userGoal(String id) => _userGoals[id];
  EvidenceLevelEntry? evidenceLevel(String id) => _evidenceLevels[id];
  EvidenceStrengthEntry? evidenceStrength(String id) => _evidenceStrengths[id];
  StudyTypeEntry? studyType(String id) => _studyTypes[id];
  ClinicalIndicationEntry? clinicalIndication(String id) =>
      _clinicalIndications[id];
  IqmCategoryEntry? iqmCategory(String id) => _iqmCategories[id];
  BannedStatusEntry? bannedStatus(String id) => _bannedStatuses[id];
  ClinicalRiskEntry? clinicalRisk(String id) => _clinicalRisks[id];
  LegalStatusEntry? legalStatus(String id) => _legalStatuses[id];
  BanContextEntry? banContext(String id) => _banContexts[id];
  EffectDirectionEntry? effectDirection(String id) => _effectDirections[id];
  SignalStrengthEntry? signalStrength(String id) => _signalStrengths[id];
  AllergenPrevalenceEntry? allergenPrevalence(String id) =>
      _allergenPrevalences[id];
  AllergenRegulatoryStatusEntry? allergenRegulatoryStatus(String id) =>
      _allergenRegulatoryStatuses[id];
  ManufacturerTrustTierEntry? manufacturerTrustTier(String id) =>
      _manufacturerTrustTiers[id];
  EfsaStatusEntry? efsaStatus(String id) => _efsaStatuses[id];
  EfsaGenotoxicityEntry? efsaGenotoxicity(String id) => _efsaGenotoxicities[id];
  MatchModeEntry? matchMode(String id) => _matchModes[id];
  ConfidenceTierEntry? confidenceTier(String id) => _confidenceTiers[id];
  ScoreContributionTierEntry? scoreContributionTier(String id) =>
      _scoreContributionTiers[id];
  PrimaryOutcomeEntry? primaryOutcome(String id) => _primaryOutcomes[id];
  ProductTypeEntry? productType(String id) => _productTypes[id];
  FormFactorEntry? formFactor(String id) => _formFactors[id];

  /// Test seam — pumps all vocab maps for widget tests without async init.
  @visibleForTesting
  void debugSeed({
    Map<String, VerdictEntry>? verdicts,
    Map<String, SeverityEntry>? severities,
  }) {
    if (verdicts != null) _verdicts = verdicts;
    if (severities != null) _severities = severities;
    _initialized = true;
  }

  /// Test seam — clears the registry so subsequent init() reruns.
  @visibleForTesting
  void debugReset() {
    _verdicts = const {};
    _severities = const {};
    _conditions = const {};
    _drugClasses = const {};
    _userGoals = const {};
    _evidenceLevels = const {};
    _evidenceStrengths = const {};
    _studyTypes = const {};
    _clinicalIndications = const {};
    _iqmCategories = const {};
    _bannedStatuses = const {};
    _clinicalRisks = const {};
    _legalStatuses = const {};
    _banContexts = const {};
    _effectDirections = const {};
    _signalStrengths = const {};
    _allergenPrevalences = const {};
    _allergenRegulatoryStatuses = const {};
    _manufacturerTrustTiers = const {};
    _efsaStatuses = const {};
    _efsaGenotoxicities = const {};
    _matchModes = const {};
    _confidenceTiers = const {};
    _scoreContributionTiers = const {};
    _primaryOutcomes = const {};
    _productTypes = const {};
    _formFactors = const {};
    _initialized = false;
  }
}
