import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/features/product_detail/widgets/interaction_warnings.dart';

void main() {
  group('InteractionWarning.fromJson', () {
    test('parses valid JSON', () {
      final json = {
        'severity': 'caution',
        'evidence_level': 'established',
        'title': 'Ginkgo + Anticoagulants',
        'mechanism': 'Increased bleeding risk',
        'management': 'Monitor closely',
        'source_urls': ['https://pubmed.ncbi.nlm.nih.gov/12345/'],
      };
      final warning = InteractionWarning.fromJson(json);
      expect(warning.severity, Severity.caution);
      expect(warning.evidenceLevel, EvidenceLevel.established);
      expect(warning.title, 'Ginkgo + Anticoagulants');
      expect(warning.sourceUrls, hasLength(1));
    });

    test('handles missing fields gracefully', () {
      final json = <String, dynamic>{
        'title': 'Test warning',
      };
      final warning = InteractionWarning.fromJson(json);
      expect(warning.severity, Severity.safe);
      expect(warning.evidenceLevel, EvidenceLevel.theoretical);
      expect(warning.sourceUrls, isEmpty);
    });
  });

  group('InteractionWarning sorting', () {
    test('sorts by severity weight descending', () {
      final warnings = [
        const InteractionWarning(
          severity: Severity.monitor,
          evidenceLevel: EvidenceLevel.theoretical,
          title: 'Low',
          mechanism: '',
          management: '',
        ),
        const InteractionWarning(
          severity: Severity.contraindicated,
          evidenceLevel: EvidenceLevel.established,
          title: 'Critical',
          mechanism: '',
          management: '',
        ),
        const InteractionWarning(
          severity: Severity.caution,
          evidenceLevel: EvidenceLevel.probable,
          title: 'Medium',
          mechanism: '',
          management: '',
        ),
      ];
      warnings.sort((a, b) => b.severity.weight.compareTo(a.severity.weight));
      expect(warnings[0].title, 'Critical');
      expect(warnings[1].title, 'Medium');
      expect(warnings[2].title, 'Low');
    });
  });

  // -----------------------------------------------------------------------
  // Pipeline schema v5.2 — profile-gating contract
  //
  // Each warning carries `display_mode_default` from the pipeline, plus
  // `severity_contextual` (calmer tier to render when no user profile
  // match) and optional authored copy fields (alert_headline / alert_body
  // / informational_note).
  //
  // These tests lock down the parse + the matchesProfile() helper so the
  // product detail screen's filter works correctly. See
  // scripts/SAFETY_DATA_PATH_C_PLAN.md in the pipeline repo.
  // -----------------------------------------------------------------------
  group('InteractionWarning v5.2 profile-gating fields', () {
    test('parses display_mode_default + severity_contextual', () {
      final json = {
        'severity': 'avoid',
        'severity_contextual': 'informational',
        'display_mode_default': 'informational',
        'title': 'Berberine / hypoglycemics',
        'detail': 'Blood sugar lowering',
        'action': 'Monitor glucose',
        'drug_class_id': 'hypoglycemics',
      };
      final w = InteractionWarning.fromJson(json);
      expect(w.severity, Severity.avoid);
      expect(w.severityContextual, Severity.informational);
      expect(w.displayModeDefault, 'informational');
      expect(w.drugClassId, 'hypoglycemics');
    });

    test('parses authored copy fields when pipeline emits them', () {
      final json = {
        'severity': 'avoid',
        'display_mode_default': 'informational',
        'title': 'Fallback title',
        'alert_headline': 'May boost your diabetes medication',
        'alert_body':
            'If you take a diabetes medication, talk to your prescriber.',
        'informational_note':
            'Berberine has blood-sugar effects relevant to people on diabetes meds.',
        'drug_class_id': 'hypoglycemics',
      };
      final w = InteractionWarning.fromJson(json);
      expect(w.alertHeadline, 'May boost your diabetes medication');
      expect(w.alertBody, contains('talk to your prescriber'));
      expect(w.informationalNote, contains('blood-sugar effects'));
    });

    test('authored fields are null on legacy blobs (pre-v5.2)', () {
      final json = {
        'severity': 'avoid',
        'title': 'Legacy',
      };
      final w = InteractionWarning.fromJson(json);
      expect(w.alertHeadline, isNull);
      expect(w.alertBody, isNull);
      expect(w.informationalNote, isNull);
      expect(w.displayModeDefault, isNull);
      expect(w.severityContextual, isNull);
    });
  });

  group('InteractionWarning.matchesProfile', () {
    const conditionWarning = InteractionWarning(
      severity: Severity.avoid,
      evidenceLevel: EvidenceLevel.established,
      title: 'Berberine / diabetes',
      mechanism: '',
      management: '',
      conditionId: 'diabetes',
    );
    const drugClassWarning = InteractionWarning(
      severity: Severity.avoid,
      evidenceLevel: EvidenceLevel.established,
      title: 'Berberine / hypoglycemics',
      mechanism: '',
      management: '',
      drugClassId: 'hypoglycemics',
    );
    const genericWarning = InteractionWarning(
      severity: Severity.avoid,
      evidenceLevel: EvidenceLevel.established,
      title: 'Generic warning',
      mechanism: '',
      management: '',
    );

    test('condition match returns true', () {
      expect(
        conditionWarning.matchesProfile(
          userConditions: {'diabetes'},
          userDrugClasses: <String>{},
        ),
        isTrue,
      );
    });

    test('drug class match returns true', () {
      expect(
        drugClassWarning.matchesProfile(
          userConditions: <String>{},
          userDrugClasses: {'hypoglycemics'},
        ),
        isTrue,
      );
    });

    test('no match returns false (not the old return-true fallback)', () {
      // This is the canonical bug: a berberine-scary warning firing for a
      // user who has neither diabetes nor hypoglycemic meds declared.
      expect(
        drugClassWarning.matchesProfile(
          userConditions: {'hypertension'},
          userDrugClasses: {'antihypertensives'},
        ),
        isFalse,
        reason:
            'Warning with drug_class_id=hypoglycemics must NOT match a '
            'user whose declared drug classes are antihypertensives only. '
            'See scripts/SAFETY_DATA_PATH_C_PLAN.md.',
      );
    });

    test('warning with neither condition nor drug class returns false', () {
      // Generic warnings cannot "match" a profile — they either render
      // based on display_mode_default or not at all. The filter logic
      // on product_detail_screen.dart uses display_mode_default to
      // decide whether to render these.
      expect(
        genericWarning.matchesProfile(
          userConditions: {'diabetes'},
          userDrugClasses: {'hypoglycemics'},
        ),
        isFalse,
      );
    });

    test('empty string condition is treated as absent', () {
      const w = InteractionWarning(
        severity: Severity.avoid,
        evidenceLevel: EvidenceLevel.established,
        title: 'Edge case',
        mechanism: '',
        management: '',
        conditionId: '',
      );
      expect(
        w.matchesProfile(
          userConditions: {'diabetes'},
          userDrugClasses: <String>{},
        ),
        isFalse,
      );
    });
  });

  // -----------------------------------------------------------------------
  // Sprint D5.4 — Dr Pham's medically-authored user-facing copy fields.
  //
  // The pipeline's enricher propagates 10 additional fields from the
  // banned_recalled / harmful_additives / interaction rules / allergens
  // data files into each warning entry. These power the detail-sheet
  // rendering (banner tint by clinical_risk, population warning bullet
  // list, regulatory_date context, etc.). Prior to D5.4 Flutter dropped
  // them on the floor — users saw only technical jargon.
  // -----------------------------------------------------------------------
  group('InteractionWarning.fromJson — Dr Pham fields', () {
    test('parses high_risk_ingredient fields (banned_recalled source)', () {
      // Exactly the shape the pipeline emits for banned/recalled/high-risk
      // / watchlist entries (see build_final_db.py around line 1410).
      final json = <String, dynamic>{
        'type': 'high_risk_ingredient',
        'severity': 'moderate',
        'title': 'High-risk ingredient: Titanium Dioxide',
        'detail': 'Technical explanation',
        'source': 'banned_recalled_ingredients',
        'safety_warning':
            'A white-pigment additive EFSA ruled in 2021 could no longer '
            'be considered safe due to genotoxicity concerns.',
        'safety_warning_one_liner': 'EU-banned white pigment. Avoid when possible.',
        'ban_context': 'watchlist',
        'clinical_risk': 'high',
        'regulatory_date': '2022-08-07',
        'regulatory_date_label': 'EU ban effective date',
        'identifiers': {'cui': 'C0040476', 'unii': '15FIX9V2JP'},
      };
      final w = InteractionWarning.fromJson(json);
      expect(w.clinicalRisk, 'high');
      expect(w.banContext, 'watchlist');
      expect(w.regulatoryDate, '2022-08-07');
      expect(w.regulatoryDateLabel, 'EU ban effective date');
      // Dr Pham's copy flows into the unified alertHeadline/alertBody.
      expect(w.alertHeadline, 'EU-banned white pigment. Avoid when possible.');
      expect(w.alertBody, contains('EFSA ruled in 2021'));
      expect(w.identifiers, isNotNull);
      expect(w.identifiers!['cui'], 'C0040476');
    });

    test('parses harmful_additive fields (mechanism + population_warnings)', () {
      final json = <String, dynamic>{
        'type': 'harmful_additive',
        'severity': 'moderate',
        'title': 'Contains Titanium Dioxide',
        'safety_summary':
            'Nanoparticle concerns in gut epithelium at prolonged exposure.',
        'safety_summary_one_liner': 'Possibly genotoxic pigment.',
        'mechanism_of_harm':
            'Nanoparticle form (<100nm) shows increased intestinal '
            'absorption and genotoxic concern.',
        'population_warnings': <String>[
          'Children — immature gut barrier',
          'People with IBD — may aggravate inflammation',
        ],
        'category': 'colorant',
      };
      final w = InteractionWarning.fromJson(json);
      expect(w.mechanismOfHarm, contains('Nanoparticle form'));
      expect(w.populationWarnings, hasLength(2));
      expect(w.populationWarnings.first, startsWith('Children'));
      expect(w.additiveCategory, 'colorant');
      expect(w.alertHeadline, 'Possibly genotoxic pigment.');
    });

    test('parses interaction fields (dose_threshold_evaluation)', () {
      final json = <String, dynamic>{
        'type': 'drug_interaction',
        'severity': 'avoid',
        'severity_contextual': 'caution',
        'title': 'Berberine + hypoglycemic agents',
        'alert_headline': 'Blood sugar may drop too low',
        'alert_body':
            'Berberine has its own blood-sugar-lowering effect; combining '
            'with insulin or sulfonylureas amplifies hypoglycemia risk.',
        'informational_note':
            'This rule kicks in at doses above 500 mg/day and with '
            'concurrent hypoglycemic therapy.',
        'dose_threshold_evaluation': {
          'triggered': true,
          'threshold_mg': 500,
          'product_dose_mg': 1000,
        },
      };
      final w = InteractionWarning.fromJson(json);
      expect(w.doseThresholdEvaluation, isNotNull);
      expect(w.doseThresholdEvaluation!['threshold_mg'], 500);
      expect(w.doseThresholdEvaluation!['triggered'], true);
    });

    test('parses allergen fields (prevalence + supplement_context)', () {
      final json = <String, dynamic>{
        'type': 'allergen',
        'severity': 'moderate',
        'title': 'Allergen: Soy',
        'prevalence': 'high',
        'supplement_context':
            'Common emulsifier in soft-gels and in protein products.',
      };
      final w = InteractionWarning.fromJson(json);
      expect(w.allergenPrevalence, 'high');
      expect(w.supplementContext, contains('soft-gels'));
    });

    test('defaults are safe when fields are absent', () {
      // Legacy blobs pre-D5.4 don't carry Dr Pham fields — model must
      // default sensibly, not crash.
      final w = InteractionWarning.fromJson(<String, dynamic>{
        'title': 'Legacy warning',
      });
      expect(w.clinicalRisk, isNull);
      expect(w.mechanismOfHarm, isNull);
      expect(w.populationWarnings, isEmpty);
      expect(w.doseThresholdEvaluation, isNull);
      expect(w.regulatoryDate, isNull);
      expect(w.regulatoryDateLabel, isNull);
      expect(w.additiveCategory, isNull);
      expect(w.allergenPrevalence, isNull);
      expect(w.supplementContext, isNull);
      expect(w.identifiers, isNull);
    });
  });
}
