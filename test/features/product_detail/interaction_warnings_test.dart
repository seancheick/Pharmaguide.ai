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
      final json = <String, dynamic>{'title': 'Test warning'};
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
      final json = {'severity': 'avoid', 'title': 'Legacy'};
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
      conditionIds: ['diabetes'],
    );
    const drugClassWarning = InteractionWarning(
      severity: Severity.avoid,
      evidenceLevel: EvidenceLevel.established,
      title: 'Berberine / hypoglycemics',
      mechanism: '',
      management: '',
      drugClassIds: ['hypoglycemics'],
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
        // Empty-string entries are filtered at parse time; the in-memory
        // constructor accepts a raw empty list the same way.
        conditionIds: <String>[],
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
  // FLTR-1 — profile-gated warning visibility (handoff v2 §4).
  //
  // Pipeline v5.2 emits condition_ids / drug_class_ids as arrays.
  // A warning must match the user's profile on ANY of its tags, not
  // just the first one. This fixes the pre-FLTR-1 regression where
  // a warning tagged ['pregnancy', 'lactation'] would miss a user
  // who declared only 'lactation'.
  //
  // The 5 handoff scenarios:
  //   1. Male with no conditions → no pregnancy warning (suppress)
  //   2. Pregnancy in profile → pregnancy warning appears
  //   3. Lactation in profile → lactation warning appears
  //   4. Liver disease in profile → liver warning appears
  //   5. No profile → suppress warnings hidden
  // -----------------------------------------------------------------------
  group('FLTR-1 — condition_ids plural parsing + ANY-match', () {
    test('parses condition_ids plural array into conditionIds', () {
      final json = <String, dynamic>{
        'severity': 'avoid',
        'title': 'Retinol + pregnancy/lactation',
        'condition_ids': ['pregnancy', 'lactation'],
      };
      final w = InteractionWarning.fromJson(json);
      expect(w.conditionIds, ['pregnancy', 'lactation']);
      // Singular getter still returns first for backward-compat readers.
      expect(w.conditionId, 'pregnancy');
    });

    test('legacy singular condition_id lifts into one-element list', () {
      final json = <String, dynamic>{
        'severity': 'avoid',
        'title': 'Legacy blob',
        'condition_id': 'pregnancy',
      };
      final w = InteractionWarning.fromJson(json);
      expect(w.conditionIds, ['pregnancy']);
    });

    test('empty-string entries are filtered out at parse', () {
      final json = <String, dynamic>{
        'severity': 'avoid',
        'title': 'Sparse array',
        'condition_ids': ['', 'lactation', ''],
      };
      final w = InteractionWarning.fromJson(json);
      expect(w.conditionIds, ['lactation']);
    });

    test('multi-tag ANY match: user has only the 2nd tag → match', () {
      // Regression pin for the pre-FLTR-1 bug where only the first
      // tag was checked. With condition_ids=['pregnancy','lactation']
      // a user who declared 'lactation' but not 'pregnancy' MUST match.
      const w = InteractionWarning(
        severity: Severity.avoid,
        evidenceLevel: EvidenceLevel.established,
        title: 'Preformed Vitamin A / reproductive',
        mechanism: '',
        management: '',
        conditionIds: ['pregnancy', 'lactation'],
      );
      expect(
        w.matchesProfile(
          userConditions: {'lactation'},
          userDrugClasses: <String>{},
        ),
        isTrue,
        reason: 'ANY match in the plural array must return true',
      );
    });

    test('multi-tag no match when user has neither tag', () {
      const w = InteractionWarning(
        severity: Severity.avoid,
        evidenceLevel: EvidenceLevel.established,
        title: 'Preformed Vitamin A / reproductive',
        mechanism: '',
        management: '',
        conditionIds: ['pregnancy', 'lactation'],
      );
      expect(
        w.matchesProfile(
          userConditions: {'diabetes'},
          userDrugClasses: <String>{},
        ),
        isFalse,
      );
    });

    test('drug_class_ids multi-tag ANY match', () {
      const w = InteractionWarning(
        severity: Severity.avoid,
        evidenceLevel: EvidenceLevel.established,
        title: 'Ginkgo / antiplatelets or anticoagulants',
        mechanism: '',
        management: '',
        drugClassIds: ['antiplatelets', 'anticoagulants'],
      );
      expect(
        w.matchesProfile(
          userConditions: <String>{},
          userDrugClasses: {'anticoagulants'},
        ),
        isTrue,
      );
    });

    // The 5 handoff scenarios below model the `shouldShowWarning`
    // contract as it's actually composed by [_DetailSection.build]:
    //   (a) profile match → show
    //   (b) display_mode_default == 'critical'|'informational' → show
    //   (c) display_mode_default == 'suppress' → hide
    //   (d) legacy no-display_mode + condition/drug tag → hide (safer)
    //   (e) legacy no-display_mode + no tag → show
    // Each test constructs a warning and asserts the composed verdict
    // for the given user profile.

    bool shouldShow(
      InteractionWarning w, {
      required Set<String> userConditions,
      required Set<String> userDrugClasses,
    }) {
      if (w.matchesProfile(
        userConditions: userConditions,
        userDrugClasses: userDrugClasses,
      )) {
        return true;
      }
      final mode = w.displayModeDefault;
      if (mode == 'critical' || mode == 'informational') return true;
      if (mode == 'suppress') return false;
      if (w.conditionIds.isNotEmpty) return false;
      if (w.drugClassIds.isNotEmpty) return false;
      return true;
    }

    const pregnancyWarning = InteractionWarning(
      severity: Severity.avoid,
      evidenceLevel: EvidenceLevel.established,
      title: 'Pregnancy-gated warning',
      mechanism: '',
      management: '',
      displayModeDefault: 'suppress',
      conditionIds: ['pregnancy'],
    );
    const lactationWarning = InteractionWarning(
      severity: Severity.avoid,
      evidenceLevel: EvidenceLevel.established,
      title: 'Lactation-gated warning',
      mechanism: '',
      management: '',
      displayModeDefault: 'suppress',
      conditionIds: ['lactation'],
    );
    const liverWarning = InteractionWarning(
      severity: Severity.avoid,
      evidenceLevel: EvidenceLevel.established,
      title: 'Liver-gated warning',
      mechanism: '',
      management: '',
      displayModeDefault: 'suppress',
      conditionIds: ['liver_disease'],
    );

    test('scenario 1: male, no conditions → pregnancy warning hidden', () {
      expect(
        shouldShow(
          pregnancyWarning,
          userConditions: <String>{},
          userDrugClasses: <String>{},
        ),
        isFalse,
      );
    });

    test('scenario 2: pregnancy in profile → pregnancy warning shown', () {
      expect(
        shouldShow(
          pregnancyWarning,
          userConditions: {'pregnancy'},
          userDrugClasses: <String>{},
        ),
        isTrue,
      );
    });

    test('scenario 3: lactation in profile → lactation warning shown', () {
      expect(
        shouldShow(
          lactationWarning,
          userConditions: {'lactation'},
          userDrugClasses: <String>{},
        ),
        isTrue,
      );
    });

    test('scenario 4: liver disease in profile → liver warning shown', () {
      expect(
        shouldShow(
          liverWarning,
          userConditions: {'liver_disease'},
          userDrugClasses: <String>{},
        ),
        isTrue,
      );
    });

    test('scenario 5: empty profile keeps every suppress warning hidden', () {
      final empty = <String>{};
      for (final w in [pregnancyWarning, lactationWarning, liverWarning]) {
        expect(
          shouldShow(w, userConditions: empty, userDrugClasses: empty),
          isFalse,
          reason: 'suppress warnings must never leak through on empty profile',
        );
      }
    });

    test('critical display mode always renders regardless of profile', () {
      const w = InteractionWarning(
        severity: Severity.contraindicated,
        evidenceLevel: EvidenceLevel.established,
        title: 'Substance-level critical',
        mechanism: '',
        management: '',
        displayModeDefault: 'critical',
      );
      expect(
        shouldShow(w, userConditions: <String>{}, userDrugClasses: <String>{}),
        isTrue,
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
        'safety_warning_one_liner':
            'EU-banned white pigment. Avoid when possible.',
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

    test(
      'parses harmful_additive fields (mechanism + population_warnings)',
      () {
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
      },
    );

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

  // -----------------------------------------------------------------------
  // FLTR-12 — Warning dedup (composite key + severity normalization)
  //
  // Real blobs duplicate warnings in two shapes:
  //   (a) cross-list: same entry in both `warnings` and
  //       `warnings_profile_gated` (1 overlap confirmed on dsld 15640)
  //   (b) within-list: pipeline emits the same semantic entry twice
  //       inside one list (e.g., "Vitamin A / pregnancy" 2× on 15640)
  //
  // The dedup key is (sorted condition_ids, sorted drug_class_ids,
  // normalized headline, normalized body). Severity is excluded so
  // "monitor" and "caution" versions of the same message collapse —
  // highest severity wins.
  // -----------------------------------------------------------------------
  group('InteractionWarning.dedupe (FLTR-12)', () {
    InteractionWarning warning({
      Severity severity = Severity.caution,
      String title = 'Some warning',
      String mechanism = 'detail body',
      List<String> conditionIds = const [],
      List<String> drugClassIds = const [],
      String? alertHeadline,
      String? alertBody,
    }) {
      return InteractionWarning(
        severity: severity,
        evidenceLevel: EvidenceLevel.established,
        title: title,
        mechanism: mechanism,
        management: '',
        conditionIds: conditionIds,
        drugClassIds: drugClassIds,
        alertHeadline: alertHeadline,
        alertBody: alertBody,
      );
    }

    test('collapses two identical entries into one', () {
      final a = warning(title: 'Vitamin A / pregnancy');
      final b = warning(title: 'Vitamin A / pregnancy');
      expect(InteractionWarning.dedupe([a, b]), hasLength(1));
    });

    test('keeps highest severity when duplicates differ in severity', () {
      final monitor = warning(
        severity: Severity.monitor,
        title: 'Niacin / cholesterol',
      );
      final caution = warning(
        severity: Severity.caution,
        title: 'Niacin / cholesterol',
      );
      final out = InteractionWarning.dedupe([monitor, caution]);
      expect(out, hasLength(1));
      expect(
        out.single.severity,
        Severity.caution,
        reason: 'severity-normalize-before-dedup picks highest',
      );
    });

    test('severity order is stable regardless of input order', () {
      // Caution-first then monitor — still keep caution.
      final caution = warning(severity: Severity.caution, title: 'same');
      final monitor = warning(severity: Severity.monitor, title: 'same');
      final flipped = InteractionWarning.dedupe([caution, monitor]);
      expect(flipped.single.severity, Severity.caution);
    });

    test('normalizes whitespace and case in headline/body', () {
      final a = warning(title: 'Vitamin A / pregnancy', mechanism: 'DETAIL');
      final b = warning(
        title: '  vitamin a / pregnancy  ',
        mechanism: '  detail  ',
      );
      expect(InteractionWarning.dedupe([a, b]), hasLength(1));
    });

    test('different condition_ids are NOT deduped', () {
      final pregnancy = warning(
        title: 'Vitamin A',
        mechanism: 'Teratogenic risk at high dose',
        conditionIds: ['pregnancy'],
      );
      final lactation = warning(
        title: 'Vitamin A',
        mechanism: 'Teratogenic risk at high dose',
        conditionIds: ['lactation'],
      );
      expect(InteractionWarning.dedupe([pregnancy, lactation]), hasLength(2));
    });

    test('condition_ids order does not affect dedup (sorted internally)', () {
      final a = warning(
        title: 'Vitamin A',
        conditionIds: ['pregnancy', 'lactation'],
      );
      final b = warning(
        title: 'Vitamin A',
        conditionIds: ['lactation', 'pregnancy'],
      );
      expect(InteractionWarning.dedupe([a, b]), hasLength(1));
    });

    test('preserves first-occurrence order across distinct warnings', () {
      final first = warning(title: 'First warning');
      final second = warning(title: 'Second warning');
      final dupeOfFirst = warning(title: 'First warning');
      final out = InteractionWarning.dedupe([first, second, dupeOfFirst]);
      expect(out.map((w) => w.title), ['First warning', 'Second warning']);
    });

    test('uses authored alertHeadline/alertBody for key when present', () {
      // displayHeadline/displayBody prefer the authored fields; the
      // dedup key follows the same preference so two entries that
      // share an authored alert collapse even if their raw
      // title/mechanism differ.
      final a = warning(
        title: 'Legacy title A',
        mechanism: 'Legacy detail A',
        alertHeadline: 'Authored headline',
        alertBody: 'Authored body',
      );
      final b = warning(
        title: 'Legacy title B',
        mechanism: 'Legacy detail B',
        alertHeadline: 'Authored headline',
        alertBody: 'Authored body',
      );
      expect(InteractionWarning.dedupe([a, b]), hasLength(1));
    });

    test('empty input returns empty output', () {
      expect(InteractionWarning.dedupe(const []), isEmpty);
    });

    test('single-element input is unchanged', () {
      final a = warning(title: 'Only one');
      final out = InteractionWarning.dedupe([a]);
      expect(out, hasLength(1));
      expect(identical(out.single, a), isTrue);
    });

    test('drug_class_ids discrimination: same body but different classes '
        'stays as two entries', () {
      final a = warning(
        title: 'Same body',
        mechanism: 'same',
        drugClassIds: ['anticoagulants'],
      );
      final b = warning(
        title: 'Same body',
        mechanism: 'same',
        drugClassIds: ['antiplatelets'],
      );
      expect(InteractionWarning.dedupe([a, b]), hasLength(2));
    });
  });
}
