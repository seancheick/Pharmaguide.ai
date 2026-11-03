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
import 'package:pharmaguide/services/stack/recalled_ingredient_result.dart';
import 'package:pharmaguide/services/stack/stack_intelligence_engine.dart';
import 'package:pharmaguide/services/stack/stack_safety_report.dart';
import 'package:pharmaguide/services/stack/synergy_result.dart';
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
      final snapshot = const StackIntelligenceEngine().summarizeFromReports(
        stackSize: 1,
        safetyReport: report,
        recalledReport: RecalledIngredientsReport.empty(),
        synergyReport: SynergyReport.empty(),
      );
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: StackSafetyBanner(snapshot: snapshot)),
        ),
      );
    }

    testWidgets('empty report + coverageIncomplete renders hedge, '
        'not SizedBox.shrink', (tester) async {
      await pump(tester, const StackSafetyReport(coverageIncomplete: true));
      expect(
        find.text("Some products couldn't be fully checked"),
        findsOneWidget,
      );
      expect(find.textContaining('may not include it yet'), findsOneWidget);
    });

    testWidgets('a low-coverage product is named, never reported as clear', (
      tester,
    ) async {
      await pump(
        tester,
        const StackSafetyReport(
          coverageIncomplete: true,
          limitedDataProducts: [LimitedDataProduct('Fructose')],
        ),
      );
      expect(find.text("We can't fully check Fructose"), findsOneWidget);
      expect(find.textContaining('may not include it'), findsOneWidget);
      expect(find.textContaining('Safe'), findsNothing);
    });

    testWidgets('low coverage preserves an independent failed check', (
      tester,
    ) async {
      await pump(
        tester,
        const StackSafetyReport(
          coverageIncomplete: true,
          limitedDataProducts: [LimitedDataProduct('Fructose')],
          checksIncomplete: true,
        ),
      );
      expect(find.text("We can't fully check Fructose"), findsOneWidget);
      expect(
        find.textContaining('Some stack safety checks could not finish'),
        findsOneWidget,
      );
    });

    testWidgets('several low-coverage products are all named', (tester) async {
      await pump(
        tester,
        const StackSafetyReport(
          coverageIncomplete: true,
          limitedDataProducts: [
            LimitedDataProduct('Fructose'),
            LimitedDataProduct('Sucralose'),
          ],
        ),
      );
      expect(find.text("We can't fully check 2 products"), findsOneWidget);
      expect(find.textContaining('Fructose, Sucralose'), findsOneWidget);
    });

    group('words the gap by the pipeline reason', () {
      const incomplete = 'blocked_by_completeness_gate';
      const intentional = 'intentional_non_scoreable_product';

      Future<void> expectBody(
        WidgetTester tester,
        List<LimitedDataProduct> products,
        String body,
      ) async {
        await pump(
          tester,
          StackSafetyReport(
            coverageIncomplete: true,
            limitedDataProducts: products,
          ),
        );
        expect(find.text(body), findsOneWidget);
        expect(find.textContaining('Safe'), findsNothing);
      }

      const today =
          "We can't match enough of its label to our safety data, so your "
          'stack results may not include it.';

      testWidgets('incomplete label details, one product', (tester) async {
        await expectBody(
          tester,
          const [
            LimitedDataProduct('Adrenal', scoreUnavailableReason: incomplete),
          ],
          "The label details we have aren't complete enough to check it, so "
          'your stack results may not include it.',
        );
        expect(find.text("We can't fully check Adrenal"), findsOneWidget);
      });

      testWidgets('incomplete label details, several products', (tester) async {
        await expectBody(
          tester,
          const [
            LimitedDataProduct('A', scoreUnavailableReason: incomplete),
            LimitedDataProduct('B', scoreUnavailableReason: incomplete),
          ],
          "The label details we have aren't complete enough to check them, "
          'so your stack results may not include them: A, B.',
        );
      });

      testWidgets('no quality score, one product', (tester) async {
        await expectBody(
          tester,
          const [LimitedDataProduct('A', scoreUnavailableReason: intentional)],
          "We don't provide a quality score for this product, and its safety "
          'checks may be incomplete.',
        );
      });

      testWidgets('no quality score, several', (tester) async {
        await expectBody(
          tester,
          const [
            LimitedDataProduct('A', scoreUnavailableReason: intentional),
            LimitedDataProduct('B', scoreUnavailableReason: intentional),
          ],
          "We don't provide quality scores for these products, and their "
          'safety checks may be incomplete: A, B.',
        );
      });

      testWidgets('mixed reasons', (tester) async {
        const mixed =
            "We can't check these fully, so your stack results may not "
            'include them: A, B.';
        await expectBody(tester, const [
          LimitedDataProduct('A', scoreUnavailableReason: incomplete),
          LimitedDataProduct('B', scoreUnavailableReason: intentional),
        ], mixed);
        await expectBody(tester, const [
          LimitedDataProduct('A', scoreUnavailableReason: incomplete),
          LimitedDataProduct('B'),
        ], mixed);
      });

      testWidgets('a reason is read regardless of case and spacing', (
        tester,
      ) async {
        await expectBody(
          tester,
          const [
            LimitedDataProduct(
              'A',
              scoreUnavailableReason: ' Blocked_By_Completeness_Gate ',
            ),
          ],
          "The label details we have aren't complete enough to check it, so "
          'your stack results may not include it.',
        );
      });

      for (final reason in [
        null,
        '',
        'blocked_by_safety_gate',
        'release_assessment_incomplete',
        'safety_assessment_incomplete',
        'safety_policy_review_required',
        'probiotic_afu_reference_unavailable',
        'a_reason_this_build_has_never_seen',
      ]) {
        testWidgets('reason "$reason" keeps the conservative wording', (
          tester,
        ) async {
          await expectBody(tester, [
            LimitedDataProduct('A', scoreUnavailableReason: reason),
          ], today);
        });
      }

      testWidgets('several unknown reasons keep the conservative wording', (
        tester,
      ) async {
        await expectBody(
          tester,
          const [
            LimitedDataProduct('A', scoreUnavailableReason: 'one'),
            LimitedDataProduct('B', scoreUnavailableReason: 'two'),
          ],
          "We can't match enough of their labels to our safety data, so "
          'your stack results may not include them: A, B.',
        );
      });
    });

    testWidgets('a product the recall card already names gets no second card', (
      tester,
    ) async {
      final snapshot = const StackIntelligenceEngine().summarizeFromReports(
        stackSize: 1,
        safetyReport: const StackSafetyReport(coverageIncomplete: true),
        recalledReport: const RecalledIngredientsReport(
          violations: [],
          incomplete: true,
          notInCatalog: ['Old Brand Magnesium'],
        ),
        synergyReport: SynergyReport.empty(),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: StackSafetyBanner(snapshot: snapshot)),
        ),
      );
      expect(find.byKey(const Key('stack-safety-banner')), findsNothing);
      expect(snapshot.intelligence.analysisIncomplete, isTrue);
    });

    testWidgets('a failed check still shows beside a product not in the '
        'catalog', (tester) async {
      final snapshot = const StackIntelligenceEngine().summarizeFromReports(
        stackSize: 1,
        safetyReport: const StackSafetyReport(checksIncomplete: true),
        recalledReport: const RecalledIngredientsReport(
          violations: [],
          incomplete: true,
          notInCatalog: ['Old Brand Magnesium'],
        ),
        synergyReport: SynergyReport.empty(),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: StackSafetyBanner(snapshot: snapshot)),
        ),
      );
      expect(find.text('More info needed'), findsOneWidget);
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
      expect(find.text('More info needed'), findsOneWidget);
      expect(find.textContaining('results may be incomplete'), findsOneWidget);
    });

    testWidgets('safe-only signals + coverageIncomplete downgrade the '
        'success tone to the caution hedge', (tester) async {
      final report = StackSafetyReport(
        stackInteractions: [_interaction(severity: Severity.safe)],
        coverageIncomplete: true,
      );
      await pump(tester, report);
      expect(
        find.text("Some products couldn't be fully checked"),
        findsOneWidget,
      );
      // The success-toned "Safe — ..." title must NOT render.
      expect(find.textContaining('Safe —'), findsNothing);
    });

    testWidgets('safe-only signals + checksIncomplete downgrade success', (
      tester,
    ) async {
      final report = StackSafetyReport(
        stackInteractions: [_interaction(severity: Severity.safe)],
        checksIncomplete: true,
      );
      await pump(tester, report);
      expect(find.text('More info needed'), findsOneWidget);
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
      expect(find.textContaining('Strong supporting evidence'), findsOneWidget);
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
