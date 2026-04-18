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
}
