import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/components/pg_compare_pillar_row.dart';
import 'package:pharmaguide/core/scoring/v4_pillars.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/score_breakdown_section.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/tradeoffs_section.dart';

// V4.1 accounting contract (pipeline AUDIT.md §8): every pillar point the
// pipeline awards is visible. The receipt is parsed for parity checks, but the
// user card shows only the reason and one key fact (Sean, 2026-10-20).

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
  for (final reason in [
    'No third-party product certification found in the reviewed registries.',
    'Verification assessment is incomplete.',
    'Independent testing or certification: unconfirmed.',
  ]) {
    testWidgets('verification renders the pipeline finding verbatim: $reason', (
      tester,
    ) async {
      final pillars = _pillars();
      pillars['verification'] = {'score': 6.0, 'max': 15, 'reason': reason};
      await tester.pumpWidget(_section(pillars));
      await tester.ensureVisible(find.text('Testing & Brand'));
      await tester.tap(find.text('Testing & Brand'));
      await tester.pumpAndSettle();
      expect(find.text(reason), findsOneWidget);
      expect(find.text('6/15'), findsOneWidget);
      expect(find.textContaining('gets neutral credit'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

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

  testWidgets(
    'an expanded pillar shows its reason, not the points arithmetic',
    (tester) async {
      await tester.pumpWidget(
        _section(
          _pillars(
            doseReceipt: _receipt({
              'neutral': 11.4286,
              'rounding': -0.0286,
            }, 8.6),
          ),
        ),
      );
      await tester.tap(find.text('Dose'));
      await tester.pumpAndSettle();
      expect(
        find.text('Dose disclosed, but adequacy cannot be determined.'),
        findsOneWidget,
      );
      for (final hidden in [
        'How these points add up',
        'Earned',
        'Neutral credit',
        'Disclosure credit',
        'Deductions',
        'Floors, caps and rounding',
        'Not earned',
        '+11.4286',
        '−0.0286',
        '8.6',
      ]) {
        expect(find.text(hidden), findsNothing, reason: hidden);
      }
      // The pillar sum stays: it is the one place the six scores add up.
      expect(find.text('= 56/100'), findsOneWidget);
    },
  );

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
