import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/components/pg_compare_pillar_row.dart';
import 'package:pharmaguide/core/scoring/v4_pillars.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/score_breakdown_section.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/tradeoffs_section.dart';

// V4.1 accounting contract (pipeline AUDIT.md §8): every pillar point the
// pipeline awards is visible and its receipt shows how the points add up.

Map<String, dynamic> _receipt(Map<String, double> byKind, double unawarded) => {
  'entries': [
    for (final entry in byKind.entries)
      {
        'id': entry.key,
        'kind': entry.key,
        'source': 'test',
        'points': entry.value,
      },
  ],
  'nominal_deductions': byKind['deduction'] ?? 0,
  'realized_deductions': byKind['deduction'] ?? 0,
  'unawarded': unawarded,
};

Map<String, dynamic> _pillars({
  double evidence = 0,
  String? evidenceState,
  Map<String, dynamic>? doseReceipt,
}) => {
  'formulation': {
    'score': 13.3,
    'max': 20,
    'reason': 'Credited: recognized botanical identity.',
  },
  'dose': {
    'score': 11.4,
    'max': 20,
    'reason': 'Dose disclosed, but adequacy cannot be determined.',
    if (doseReceipt != null) 'receipt': doseReceipt,
  },
  'evidence': {
    'score': evidence,
    'max': 20,
    'reason': 'Research certainty 10/10; product applicability 0/6.',
    if (evidenceState != null) 'display_state': evidenceState,
  },
  'transparency': {
    'score': 15.0,
    'max': 15,
    'reason': 'Fully transparent label.',
  },
  'verification': {
    'score': 6.0,
    'max': 15,
    'reason': 'Unknown: no independent verification on file.',
  },
  'safety_hygiene': {
    'score': 10.0,
    'max': 10,
    'reason': 'No catalog-level formula concerns found.',
  },
};

Widget _section(Map<String, dynamic> pillars) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(
      child: buildScoreBreakdownSection(
        heroScore: 55.7,
        qualityPillarsV4: pillars,
      ),
    ),
  ),
);

void main() {
  group('receipt parsing', () {
    test('sums entries by kind and keeps unawarded apart', () {
      final pillars = parseV4Pillars(
        _pillars(
          doseReceipt: _receipt({'neutral': 11.4286, 'rounding': -0.0286}, 8.6),
        ),
      );
      final receipt = pillars.firstWhere((p) => p.key == 'dose').receipt!;
      expect(receipt.points('neutral'), closeTo(11.4286, 1e-9));
      expect(receipt.adjustments, closeTo(-0.0286, 1e-9));
      expect(receipt.unawarded, 8.6);
    });

    test('a malformed receipt is dropped, never half-rendered', () {
      final bad = _receipt({'neutral': 11.4}, 8.6)
        ..['entries'] = [
          {'id': 'x', 'kind': 'bonus', 'points': 1.0},
        ];
      final pillars = parseV4Pillars(_pillars(doseReceipt: bad));
      expect(pillars.firstWhere((p) => p.key == 'dose').receipt, isNull);
    });
  });

  group('pillar numbers', () {
    testWidgets(
      'awarded points show even when applicability is not established',
      (tester) async {
        await tester.pumpWidget(
          _section(
            _pillars(
              evidence: 10.0,
              evidenceState: 'applicability_unestablished',
            ),
          ),
        );
        expect(find.text('10/20'), findsOneWidget);
        expect(find.text('Applicability not established'), findsOneWidget);
      },
    );

    testWidgets('a zero with no verdict is still withheld', (tester) async {
      await tester.pumpWidget(
        _section(
          _pillars(evidence: 0.0, evidenceState: 'applicability_unestablished'),
        ),
      );
      expect(find.text('0/20'), findsNothing);
      expect(find.text('Applicability not established'), findsOneWidget);
    });

    testWidgets('compare shows awarded points under a no-verdict state', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PGComparePillarRow(
              label: 'Evidence',
              maxA: 20,
              maxB: 20,
              scoreA: 10.0,
              scoreB: 0.0,
              displayStateA: 'applicability_unestablished',
              displayStateB: 'applicability_unestablished',
            ),
          ),
        ),
      );
      expect(find.text('10/20'), findsOneWidget);
      expect(find.text('0/20'), findsNothing);
    });
  });

  testWidgets('an expanded pillar shows how its points add up', (tester) async {
    await tester.pumpWidget(
      _section(
        _pillars(
          doseReceipt: _receipt({'neutral': 11.4286, 'rounding': -0.0286}, 8.6),
        ),
      ),
    );
    await tester.tap(find.text('Dose'));
    await tester.pumpAndSettle();
    expect(find.text('How these points add up'), findsOneWidget);
    expect(find.text('Neutral credit'), findsOneWidget);
    expect(find.text('+11.4'), findsOneWidget);
    expect(find.text('Not earned'), findsOneWidget);
    expect(find.text('8.6'), findsOneWidget);
    // A residue that rounds to 0.0 is not shown as its own row.
    expect(find.text('Floors, caps and rounding'), findsNothing);
  });

  testWidgets(
    'the sixth-pillar drag caption uses the pillar name the app shows',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: buildTradeoffsSection(
                detailBlob: {
                  'v4_score_explanation': {
                    'strengths': <Map<String, dynamic>>[],
                    'drags': [
                      {
                        'pillar': 'safety_hygiene',
                        'reason':
                            'Safety concern: it contains a restricted additive.',
                      },
                    ],
                  },
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Holds back: formula & quality checks'), findsOneWidget);
      expect(find.text('Holds back: safety hygiene'), findsNothing);
    },
  );
}
