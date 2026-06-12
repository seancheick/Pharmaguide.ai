// Safety-rule regression tests (2026-06 safety fixes).
//
// Covers the non-negotiable rules:
//   * NEVER display "safe" when mapped_coverage < 0.3 — stack banner
//     and Quick Check must hedge instead of implying a clean result.
//   * ALWAYS show evidence_level on interaction warnings.
//   * Malformed pipeline data degrades gracefully (skip, never crash,
//     never throw away sibling valid entries).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/models/interaction_result.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/user_database.dart' as udb;
import 'package:pharmaguide/features/product_detail/v2/warnings_pipeline.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';
import 'package:pharmaguide/features/quick_check/quick_check_logic.dart';
import 'package:pharmaguide/features/stack/widgets/stack_safety_banner.dart';
import 'package:pharmaguide/services/stack/stack_safety_report.dart';
import 'package:pharmaguide/services/warnings/profile_gate_evaluator.dart'
    as gate;

ProductsCoreData _product({double? mappedCoverage}) {
  return ProductsCoreData(
    dsldId: 'TEST-1',
    productName: 'Test Supplement',
    productStatus: 'active',
    mappedCoverage: mappedCoverage,
    exportVersion: 'test',
    exportedAt: '2026-06-11T00:00:00Z',
  );
}

InteractionResult _interaction({
  Severity severity = Severity.caution,
  EvidenceLevel evidenceLevel = EvidenceLevel.probable,
}) {
  return InteractionResult(
    id: 'INT-1',
    type: InteractionType.supplementSupplement,
    severity: severity,
    evidenceLevel: evidenceLevel,
    agent1Name: 'Magnesium',
    agent2Name: 'Calcium',
    mechanism: 'Competes for absorption.',
    management: 'Worth spacing doses apart.',
    doseDependant: false,
    doseThreshold: null,
    sourceUrls: const [],
    source: InteractionSource.pipeline,
  );
}

/// Object whose toString() throws — simulates a blob entry that makes
/// `InteractionWarning.fromJson` blow up mid-parse.
class _Boom {
  @override
  String toString() => throw StateError('boom');
}

void main() {
  group('StackSafetyBanner — low coverage hedge', () {
    Future<void> pump(WidgetTester tester, StackSafetyReport report) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: StackSafetyBanner(report: report)),
        ),
      );
    }

    testWidgets('empty report + coverageIncomplete renders hedge, '
        'not SizedBox.shrink', (tester) async {
      await pump(tester, const StackSafetyReport(coverageIncomplete: true));
      expect(
        find.text("Some labels couldn't be fully analyzed"),
        findsOneWidget,
      );
      expect(find.textContaining('results may be incomplete'), findsOneWidget);
    });

    testWidgets('empty report without coverage flag stays hidden', (
      tester,
    ) async {
      await pump(tester, const StackSafetyReport());
      expect(find.byKey(const Key('stack-safety-banner')), findsNothing);
    });

    testWidgets('empty report with failed checks renders caution hedge', (
      tester,
    ) async {
      await pump(tester, const StackSafetyReport(checksIncomplete: true));
      expect(find.text("Interactions couldn't be checked"), findsOneWidget);
      expect(find.textContaining('results may be incomplete'), findsOneWidget);
    });

    testWidgets('safe-only signals + coverageIncomplete downgrade the '
        'success tone to the caution hedge', (tester) async {
      final report = StackSafetyReport(
        categoryWarnings: [_interaction(severity: Severity.safe)],
        coverageIncomplete: true,
      );
      await pump(tester, report);
      expect(
        find.text("Some labels couldn't be fully analyzed"),
        findsOneWidget,
      );
      // The success-toned "Safe — ..." title must NOT render.
      expect(find.textContaining('Safe —'), findsNothing);
    });

    testWidgets('safe-only signals + checksIncomplete downgrade success', (
      tester,
    ) async {
      final report = StackSafetyReport(
        categoryWarnings: [_interaction(severity: Severity.safe)],
        checksIncomplete: true,
      );
      await pump(tester, report);
      expect(find.text("Interactions couldn't be checked"), findsOneWidget);
      expect(find.textContaining('Safe —'), findsNothing);
    });

    testWidgets('real warnings still render normally when coverage is '
        'incomplete (caution/danger tones are already honest)', (tester) async {
      final report = StackSafetyReport(
        stackInteractions: [_interaction(severity: Severity.avoid)],
        coverageIncomplete: true,
      );
      await pump(tester, report);
      expect(find.textContaining('Magnesium × Calcium'), findsOneWidget);
    });

    testWidgets('interaction banner body shows the evidence level label', (
      tester,
    ) async {
      final report = StackSafetyReport(
        stackInteractions: [
          _interaction(evidenceLevel: EvidenceLevel.established),
        ],
      );
      await pump(tester, report);
      expect(find.textContaining('Strong Evidence'), findsOneWidget);
    });
  });

  group('QuickCheckItem.coverageIncomplete', () {
    test('supplement with mappedCoverage 0.2 is coverage-incomplete', () {
      final item = QuickCheckItem.supplement(_product(mappedCoverage: 0.2));
      expect(item.coverageIncomplete, isTrue);
      // hydrationIncomplete stays a medication-only concept.
      expect(item.hydrationIncomplete, isFalse);
    });

    test('supplement with null mappedCoverage is coverage-incomplete '
        '(unknown coverage is not trusted)', () {
      final item = QuickCheckItem.supplement(_product(mappedCoverage: null));
      expect(item.coverageIncomplete, isTrue);
    });

    test('supplement with mappedCoverage 0.8 is fully covered', () {
      final item = QuickCheckItem.supplement(_product(mappedCoverage: 0.8));
      expect(item.coverageIncomplete, isFalse);
    });

    test('medication with failed RxNorm hydration is coverage-incomplete', () {
      final item = QuickCheckItem.medication(name: 'Drug X', rxcui: '123');
      expect(item.hydrationIncomplete, isTrue);
      expect(item.coverageIncomplete, isTrue);
    });

    test('medication with class taxonomy is fully covered', () {
      final item = QuickCheckItem.medication(
        name: 'Drug X',
        rxcui: '123',
        drugClasses: const ['ace_inhibitors'],
      );
      expect(item.coverageIncomplete, isFalse);
    });
  });

  group('parseBlobWarnings — per-entry resilience', () {
    test('skips a malformed entry but keeps the valid siblings', () {
      final blob = <String, dynamic>{
        'warnings': [
          {
            'severity': 'caution',
            'title': 'Valid warning A',
            'detail': 'mechanism A',
          },
          // toString() on this severity value throws inside fromJson.
          {'severity': _Boom(), 'title': 'Malformed'},
          {
            'severity': 'avoid',
            'title': 'Valid warning B',
            'detail': 'mechanism B',
          },
        ],
      };
      final out = parseBlobWarnings(blob);
      expect(out.map((w) => w.title), ['Valid warning A', 'Valid warning B']);
    });
  });

  group('ProfileState._decodeList — mixed-type JSON list', () {
    test('fromDbRow with non-string list entries does not throw and '
        'keeps the string entries', () {
      final row = udb.UserProfile(
        id: 1,
        goals: '["energy", 7, null, "sleep"]',
        conditions: '[]',
        drugClasses: '[]',
        allergens: '[]',
        profileFlags: '[]',
        createdAt: DateTime(2026),
        lastUpdated: DateTime(2026),
      );
      final state = ProfileState.fromDbRow(row);
      expect(state.goals, ['energy', 'sleep']);
    });
  });

  group('profile_gate evaluator — non-string severity values', () {
    Map<String, dynamic> doseGate(Map<String, dynamic> dose) {
      return {
        'gate_type': 'condition',
        'requires': {
          'conditions_any': ['diabetes'],
          'drug_classes_any': <String>[],
          'profile_flags_any': <String>[],
        },
        'excludes': {
          'conditions_any': <String>[],
          'drug_classes_any': <String>[],
          'profile_flags_any': <String>[],
          'product_forms_any': <String>[],
          'nutrient_forms_any': <String>[],
        },
        'dose': dose,
      };
    }

    const user = gate.UserProfile(conditions: {'diabetes'});

    test('non-string severity_if_not_met does not throw; base severity '
        'stands', () {
      final result = gate.evaluateProfileGate(
        doseGate({
          'comparator': '>=',
          'value': 100,
          'severity_if_met': 'avoid',
          'severity_if_not_met': 123, // pipeline drift — not a String
        }),
        user,
        const gate.ProductContext(dosePerDay: 50), // not met
        baseSeverity: 'caution',
      );
      expect(result.fires, isTrue);
      expect(result.severity, 'caution');
    });

    test('non-string severity_if_met does not throw; base severity '
        'stands', () {
      final result = gate.evaluateProfileGate(
        doseGate({
          'comparator': '>=',
          'value': 100,
          'severity_if_met': true, // pipeline drift — not a String
          'severity_if_not_met': 'monitor',
        }),
        user,
        const gate.ProductContext(dosePerDay: 200), // met
        baseSeverity: 'caution',
      );
      expect(result.fires, isTrue);
      expect(result.severity, 'caution');
    });

    test('unknown comparator with non-string severity_if_not_met does '
        'not throw', () {
      final result = gate.evaluateProfileGate(
        doseGate({
          'comparator': '~=', // unknown comparator
          'value': 100,
          'severity_if_met': 'avoid',
          'severity_if_not_met': <String>[], // not a String
        }),
        user,
        const gate.ProductContext(dosePerDay: 200),
        baseSeverity: 'monitor',
      );
      expect(result.fires, isTrue);
      expect(result.severity, 'monitor');
    });
  });
}
