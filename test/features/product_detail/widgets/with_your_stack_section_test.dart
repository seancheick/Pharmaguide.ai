// Spec: INITIATIVE_PRODUCT_TRUST_AND_IA.md, Sprint 1, T1.7.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/features/product_detail/widgets/interaction_warnings.dart';
import 'package:pharmaguide/features/product_detail/widgets/with_your_stack_section.dart';

InteractionWarning _warning({
  required Severity severity,
  String title = 'Test interaction',
  String mechanism = 'Mechanism explanation',
  String management = 'Recommendation copy',
  String? alertHeadline,
  String? alertBody,
  List<String> drugClassIds = const [],
  List<String> conditionIds = const [],
  List<String> sourceUrls = const [],
  EvidenceLevel evidenceLevel = EvidenceLevel.theoretical,
}) {
  return InteractionWarning(
    severity: severity,
    evidenceLevel: evidenceLevel,
    title: title,
    mechanism: mechanism,
    management: management,
    alertHeadline: alertHeadline,
    alertBody: alertBody,
    drugClassIds: drugClassIds,
    conditionIds: conditionIds,
    sourceUrls: sourceUrls,
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required List<InteractionWarning> warnings,
  Set<String> userDrugClasses = const {},
  Set<String> userConditions = const {},
  double width = 480,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: WithYourStackSection(
              warnings: warnings,
              userDrugClasses: userDrugClasses,
              userConditions: userConditions,
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('WithYourStackSection — visibility gates', () {
    testWidgets(
      'empty profile (no drug classes + no conditions) → section hides '
      'entirely',
      (tester) async {
        await _pump(tester, warnings: const []);
        await tester.pumpAndSettle();

        expect(find.text('With your stack'), findsNothing);
      },
    );

    testWidgets(
      'profile has drug classes but warnings list is empty → '
      '✓ rows render for each',
      (tester) async {
        await _pump(
          tester,
          warnings: const [],
          userDrugClasses: {'statins', 'anticoagulants'},
        );
        await tester.pumpAndSettle();

        expect(find.text('With your stack'), findsOneWidget);
        expect(find.text('Statins'), findsOneWidget);
        expect(find.text('Anticoagulants'), findsOneWidget);
        // Both render the positive trust line.
        expect(find.text('No known interaction'), findsNWidgets(2));
      },
    );
  });

  group('WithYourStackSection — ⚠ row for matched warning', () {
    testWidgets(
      'drug class with matching avoid warning → severity label + '
      'tappable row',
      (tester) async {
        await _pump(
          tester,
          warnings: [
            _warning(
              severity: Severity.avoid,
              alertHeadline: 'Reduces statin absorption',
              drugClassIds: const ['statins'],
            ),
          ],
          userDrugClasses: {'statins'},
        );
        await tester.pumpAndSettle();

        expect(find.text('Statins'), findsOneWidget);
        expect(
          find.textContaining('AVOID'),
          findsOneWidget,
          reason: 'severity label prefix should render in the row sub-line',
        );
        expect(find.textContaining('Reduces statin absorption'), findsOneWidget);
      },
    );

    testWidgets(
      'matched row with no underlying mechanism falls back to title',
      (tester) async {
        await _pump(
          tester,
          warnings: [
            _warning(
              severity: Severity.caution,
              title: 'Aspirin caution',
              alertHeadline: null,
              drugClassIds: const ['nsaids'],
            ),
          ],
          userDrugClasses: {'nsaids'},
        );
        await tester.pumpAndSettle();

        expect(find.text('Nsaids'), findsOneWidget);
        expect(find.textContaining('Aspirin caution'), findsOneWidget);
      },
    );

    testWidgets('worst severity wins when multiple warnings match a class',
        (tester) async {
      // Two warnings tagged for "anticoagulants" — caution + contraindicated.
      // The row must surface the worst (contraindicated) plus its
      // headline.
      await _pump(
        tester,
        warnings: [
          _warning(
            severity: Severity.caution,
            alertHeadline: 'Caution-tier note',
            drugClassIds: const ['anticoagulants'],
          ),
          _warning(
            severity: Severity.contraindicated,
            alertHeadline: 'Do not combine — bleeding risk',
            drugClassIds: const ['anticoagulants'],
          ),
        ],
        userDrugClasses: {'anticoagulants'},
      );
      await tester.pumpAndSettle();

      expect(find.text('Anticoagulants'), findsOneWidget);
      expect(find.textContaining('Do not combine'), findsOneWidget);
      // The caution-tier note should NOT be the surfaced one.
      expect(find.textContaining('Caution-tier note'), findsNothing);
    });
  });

  group('WithYourStackSection — ✓ row for no match', () {
    testWidgets(
      'drug class with no matching warning → ✓ "No known interaction"',
      (tester) async {
        await _pump(
          tester,
          warnings: [
            _warning(
              severity: Severity.avoid,
              drugClassIds: const ['statins'],
            ),
          ],
          // User has DIFFERENT drug class — should NOT match the
          // statins-only warning.
          userDrugClasses: {'beta_blockers'},
        );
        await tester.pumpAndSettle();

        expect(find.text('Beta Blockers'), findsOneWidget);
        expect(find.text('No known interaction'), findsOneWidget);
      },
    );

    testWidgets('✓ row is NOT tappable (no expand chevron rendered)',
        (tester) async {
      await _pump(
        tester,
        warnings: const [],
        userDrugClasses: {'statins'},
      );
      await tester.pumpAndSettle();

      // The ✓ row uses Icons.check_circle_outline_rounded; the
      // expand chevron only renders when there's a matched warning.
      expect(
        find.byIcon(Icons.keyboard_arrow_down_rounded),
        findsNothing,
        reason: '✓ rows must not show an expand chevron — there\'s '
            'nothing to expand',
      );
    });
  });

  group('WithYourStackSection — tap-expand reveals detail', () {
    testWidgets(
      'tapping a ⚠ row reveals mechanism + recommendation + evidence',
      (tester) async {
        await _pump(
          tester,
          warnings: [
            _warning(
              severity: Severity.avoid,
              alertHeadline: 'Reduces absorption',
              alertBody: 'Calcium binds to the active ingredient and '
                  'reduces gut absorption by ~40%.',
              management: 'Take 4 hours apart from your statin dose.',
              evidenceLevel: EvidenceLevel.established,
              drugClassIds: const ['statins'],
              sourceUrls: const ['https://example.com/study1'],
            ),
          ],
          userDrugClasses: {'statins'},
        );
        await tester.pumpAndSettle();

        // Pre-tap: detail labels are NOT visible.
        expect(find.text('Mechanism'), findsNothing);
        expect(find.text('Recommendation'), findsNothing);

        await tester.tap(find.text('Statins'));
        await tester.pumpAndSettle();

        // Detail surfaces: mechanism + recommendation + evidence chip.
        expect(find.text('Mechanism'), findsOneWidget);
        expect(find.text('Recommendation'), findsOneWidget);
        expect(find.textContaining('Calcium binds'), findsOneWidget);
        expect(find.textContaining('4 hours apart'), findsOneWidget);
        expect(find.text('Strong Evidence'), findsOneWidget);
        // Citation chip with count.
        expect(find.text('1 citation'), findsOneWidget);
      },
    );

    testWidgets(
      'second tap collapses — mechanism + recommendation hide again',
      (tester) async {
        await _pump(
          tester,
          warnings: [
            _warning(
              severity: Severity.caution,
              alertHeadline: 'Monitor closely',
              drugClassIds: const ['statins'],
            ),
          ],
          userDrugClasses: {'statins'},
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Statins'));
        await tester.pumpAndSettle();
        expect(find.text('Mechanism'), findsOneWidget);

        await tester.tap(find.text('Statins'));
        await tester.pumpAndSettle();
        expect(find.text('Mechanism'), findsNothing);
      },
    );

    testWidgets(
      'pluralizes "citations" correctly (2 → "2 citations")',
      (tester) async {
        await _pump(
          tester,
          warnings: [
            _warning(
              severity: Severity.avoid,
              drugClassIds: const ['statins'],
              sourceUrls: const [
                'https://example.com/study1',
                'https://example.com/study2',
              ],
            ),
          ],
          userDrugClasses: {'statins'},
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Statins'));
        await tester.pumpAndSettle();

        expect(find.text('2 citations'), findsOneWidget);
      },
    );

    testWidgets(
      'no citations on the warning → no citation chip rendered',
      (tester) async {
        await _pump(
          tester,
          warnings: [
            _warning(
              severity: Severity.caution,
              alertHeadline: 'Caution headline',
              drugClassIds: const ['statins'],
              sourceUrls: const [],
            ),
          ],
          userDrugClasses: {'statins'},
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Statins'));
        await tester.pumpAndSettle();

        expect(find.textContaining('citation'), findsNothing);
      },
    );
  });

  group('WithYourStackSection — sort + condition support', () {
    testWidgets(
      'rows sort by severity weight desc, then alpha within same weight',
      (tester) async {
        await _pump(
          tester,
          warnings: [
            _warning(
              severity: Severity.caution,
              drugClassIds: const ['statins'],
              alertHeadline: 'Statins note',
            ),
            _warning(
              severity: Severity.contraindicated,
              drugClassIds: const ['anticoagulants'],
              alertHeadline: 'Bleed risk',
            ),
            _warning(
              severity: Severity.avoid,
              drugClassIds: const ['nsaids'],
              alertHeadline: 'NSAID conflict',
            ),
          ],
          userDrugClasses: {'statins', 'anticoagulants', 'nsaids'},
        );
        await tester.pumpAndSettle();

        // Worst-first ordering: contraindicated > avoid > caution.
        final contraY =
            tester.getTopLeft(find.text('Anticoagulants')).dy;
        final avoidY = tester.getTopLeft(find.text('Nsaids')).dy;
        final cautionY = tester.getTopLeft(find.text('Statins')).dy;
        expect(contraY, lessThan(avoidY));
        expect(avoidY, lessThan(cautionY));
      },
    );

    testWidgets(
      'condition row also matches via conditionIds (not just drugClassIds)',
      (tester) async {
        await _pump(
          tester,
          warnings: [
            _warning(
              severity: Severity.contraindicated,
              alertHeadline: 'Contraindicated in pregnancy',
              conditionIds: const ['pregnancy'],
            ),
          ],
          userConditions: {'pregnancy'},
        );
        await tester.pumpAndSettle();

        expect(find.text('Pregnancy'), findsOneWidget);
        expect(find.textContaining('Contraindicated in pregnancy'),
            findsOneWidget);
      },
    );
  });
}
