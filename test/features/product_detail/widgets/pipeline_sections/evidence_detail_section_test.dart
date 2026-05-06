// Spec: INITIATIVE_PRODUCT_TRUST_AND_IA.md, Sprint 1, T1.10.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/product_detail/widgets/pipeline_sections/evidence_detail_section.dart';

Map<String, dynamic> _match({
  String ingredient = 'Ashwagandha',
  String evidence = 'moderate',
  List<String> pmids = const [],
}) {
  return {'ingredient': ingredient, 'evidence_level': evidence, 'pmids': pmids};
}

Future<void> _pump(WidgetTester tester, {Map<String, dynamic>? evidenceData}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: EvidenceDetailSection(evidenceData: evidenceData),
        ),
      ),
    ),
  );
}

void main() {
  group('evidenceTotalStudies — pure logic', () {
    test('empty matches → 0', () {
      expect(evidenceTotalStudies(const []), 0);
    });

    test('sums PMIDs across matches', () {
      final n = evidenceTotalStudies([
        _match(pmids: const ['1', '2', '3']),
        _match(pmids: const ['4', '5']),
      ]);
      expect(n, 5);
    });

    test('dedupes the same PMID across matches', () {
      // The pipeline emits per-ingredient PMID lists; the same study
      // can legitimately appear under two ingredients. Counting it
      // twice would inflate the tier.
      final n = evidenceTotalStudies([
        _match(pmids: const ['1', '2', '3']),
        _match(pmids: const ['2', '3', '4']),
      ]);
      expect(n, 4);
    });

    test('ignores blank PMIDs', () {
      final n = evidenceTotalStudies([
        _match(pmids: const ['1', '', '   ', '2']),
      ]);
      expect(n, 2);
    });
  });

  group('evidenceHasMetaQuality', () {
    test('any "strong" → true', () {
      expect(
        evidenceHasMetaQuality([
          _match(evidence: 'limited'),
          _match(evidence: 'strong'),
        ]),
        isTrue,
      );
    });

    test('"established" matches the canonical pipeline label', () {
      expect(evidenceHasMetaQuality([_match(evidence: 'established')]), isTrue);
    });

    test('"high" forward-compat with scoring-pipeline pillar levels', () {
      expect(evidenceHasMetaQuality([_match(evidence: 'High')]), isTrue);
    });

    test('only "moderate"/"limited" → false', () {
      expect(
        evidenceHasMetaQuality([
          _match(evidence: 'moderate'),
          _match(evidence: 'limited'),
        ]),
        isFalse,
      );
    });

    test('empty input → false', () {
      expect(evidenceHasMetaQuality(const []), isFalse);
    });
  });

  group('evidenceTier — boundary thresholds', () {
    test('0 studies → LIMITED', () {
      expect(evidenceTier(const []), EvidenceTier.limited);
    });

    test('2 studies (any quality) → LIMITED', () {
      expect(
        evidenceTier([
          _match(evidence: 'strong', pmids: const ['1', '2']),
        ]),
        EvidenceTier.limited,
      );
    });

    test('3 studies, no meta → MODERATE', () {
      expect(
        evidenceTier([
          _match(evidence: 'moderate', pmids: const ['1', '2', '3']),
        ]),
        EvidenceTier.moderate,
      );
    });

    test('4 studies, no meta → MODERATE', () {
      expect(
        evidenceTier([
          _match(evidence: 'limited', pmids: const ['1', '2', '3', '4']),
        ]),
        EvidenceTier.moderate,
      );
    });

    test('5 studies but no meta → MODERATE (downgraded)', () {
      // Volume alone isn't enough — pipeline needs to signal at least
      // one meta-quality match before STRONG fires.
      expect(
        evidenceTier([
          _match(evidence: 'moderate', pmids: const ['1', '2', '3', '4', '5']),
        ]),
        EvidenceTier.moderate,
      );
    });

    test('5 studies + meta available → STRONG', () {
      expect(
        evidenceTier([
          _match(evidence: 'strong', pmids: const ['1', '2', '3']),
          _match(evidence: 'moderate', pmids: const ['4', '5']),
        ]),
        EvidenceTier.strong,
      );
    });

    test('STRONG threshold matches spec — ≥5 studies, meta available', () {
      // Spec says: "Strong evidence (≥5 studies, meta available) → STRONG"
      expect(
        evidenceTier([
          _match(
            evidence: 'established',
            pmids: const ['1', '2', '3', '4', '5'],
          ),
        ]),
        EvidenceTier.strong,
      );
    });

    test('LIMITED threshold matches spec — <3 studies', () {
      // Spec says: "Limited evidence (<3 studies) → LIMITED"
      for (final n in [0, 1, 2]) {
        final pmids = List.generate(n, (i) => '$i');
        expect(
          evidenceTier([_match(evidence: 'strong', pmids: pmids)]),
          EvidenceTier.limited,
          reason: '$n studies should be LIMITED',
        );
      }
    });

    test('T7 — 0 studies + meta-quality match → LIMITED (not STRONG)', () {
      // Pipeline can ship a clinical_match with `evidence_level:
      // 'strong'` but `pmids: []` — meaning the literature claims
      // meta-quality evidence exists but no PMIDs were attached.
      // The tier MUST resolve to LIMITED because volume threshold
      // is unmet. A naive `if (meta) return strong` would mis-read
      // this as STRONG; pin the behavior so a future refactor
      // can't regress it.
      expect(
        evidenceTier([_match(evidence: 'strong', pmids: const [])]),
        EvidenceTier.limited,
      );
      expect(
        evidenceTier([_match(evidence: 'established', pmids: const [])]),
        EvidenceTier.limited,
      );
    });
  });

  group('EvidenceDetailSection — render', () {
    testWidgets('null evidenceData → section hides entirely', (tester) async {
      await _pump(tester, evidenceData: null);
      await tester.pumpAndSettle();
      expect(find.byType(EvidenceDetailSection), findsOneWidget);
      expect(find.text('Evidence & Research'), findsNothing);
    });

    testWidgets('matchCount=0 + no matches → section hides entirely', (
      tester,
    ) async {
      await _pump(
        tester,
        evidenceData: const {
          'match_count': 0,
          'clinical_matches': <Map<String, dynamic>>[],
        },
      );
      await tester.pumpAndSettle();
      expect(find.text('Evidence & Research'), findsNothing);
    });

    testWidgets('STRONG tier renders label + study count + meta line', (
      tester,
    ) async {
      await _pump(
        tester,
        evidenceData: {
          'match_count': 1,
          'clinical_matches': [
            _match(
              evidence: 'strong',
              pmids: const ['111', '222', '333', '444', '555'],
            ),
          ],
        },
      );
      await tester.pumpAndSettle();
      expect(find.text('Evidence & Research'), findsOneWidget);
      expect(find.text('STRONG'), findsOneWidget);
      expect(
        find.text('5 studies reviewed · meta-analysis available'),
        findsOneWidget,
      );
    });

    testWidgets('LIMITED tier renders without meta line', (tester) async {
      await _pump(
        tester,
        evidenceData: {
          'match_count': 1,
          'clinical_matches': [
            _match(evidence: 'limited', pmids: const ['111']),
          ],
        },
      );
      await tester.pumpAndSettle();
      expect(find.text('LIMITED'), findsOneWidget);
      expect(find.text('1 study reviewed'), findsOneWidget);
      expect(find.textContaining('meta-analysis'), findsNothing);
    });

    testWidgets(
      'T7 — 0-PMID match renders "Limited evidence available", not the contradiction',
      (tester) async {
        // The buggy pre-T7 render was self-contradictory: tier banner
        // claimed "Clinical support: LIMITED" while the subline said
        // "0 studies reviewed". Sean's 2026-04-29 walkthrough caught
        // it — surfacing as "looks like a crash" because the empty
        // citation sheet (T5) magnified the broken impression.
        await _pump(
          tester,
          evidenceData: {
            'match_count': 1,
            'clinical_matches': [_match(evidence: 'strong', pmids: const [])],
          },
        );
        await tester.pumpAndSettle();

        // Honest single-line banner present.
        expect(find.text('Limited evidence available'), findsOneWidget);
        // The contradictory copy must NOT render.
        expect(find.text('0 studies reviewed'), findsNothing);
        expect(find.textContaining('Clinical support:'), findsNothing);
        expect(find.text('LIMITED'), findsNothing);
        // Section itself still renders (the per-ingredient rows are
        // untouched — this fix is scoped to the tier banner only).
        expect(find.text('Evidence & Research'), findsOneWidget);
      },
    );

    testWidgets('MODERATE tier renders for 3-4 studies', (tester) async {
      await _pump(
        tester,
        evidenceData: {
          'match_count': 1,
          'clinical_matches': [
            _match(evidence: 'moderate', pmids: const ['1', '2', '3']),
          ],
        },
      );
      await tester.pumpAndSettle();
      expect(find.text('MODERATE'), findsOneWidget);
    });

    testWidgets('NO editorial quote in V1', (tester) async {
      // Defensive — none of the static section text should include
      // anything that resembles a curated research summary. The
      // pipeline doesn't curate them yet, so any text we wrote here
      // would be unverifiable.
      await _pump(
        tester,
        evidenceData: {
          'match_count': 1,
          'clinical_matches': [
            _match(evidence: 'strong', pmids: const ['1', '2', '3', '4', '5']),
          ],
        },
      );
      await tester.pumpAndSettle();
      // Common phrases that would betray an editorial blurb:
      for (final phrase in const [
        'has been shown',
        'clinically proven',
        'studies suggest',
        'research shows',
      ]) {
        expect(
          find.textContaining(phrase),
          findsNothing,
          reason: 'editorial phrase "$phrase" should not appear in V1',
        );
      }
    });

    testWidgets(
      'tap aggregate tier banner → opens citations sheet with all PMIDs',
      (tester) async {
        await _pump(
          tester,
          evidenceData: {
            'match_count': 2,
            'clinical_matches': [
              _match(ingredient: 'Ashwagandha', pmids: const ['111', '222']),
              _match(ingredient: 'L-Theanine', pmids: const ['333']),
            ],
          },
        );
        await tester.pumpAndSettle();

        // Tap the tier banner.
        await tester.tap(find.text('MODERATE'));
        await tester.pumpAndSettle();

        // Sheet header.
        expect(find.text('Citations'), findsOneWidget);
        // Both ingredients listed.
        expect(find.text('Ashwagandha'), findsWidgets);
        expect(find.text('L-Theanine'), findsWidgets);
        // All three PMIDs surfaced (not just the first).
        expect(find.text('PMID: 111'), findsOneWidget);
        expect(find.text('PMID: 222'), findsOneWidget);
        expect(find.text('PMID: 333'), findsOneWidget);
      },
    );

    testWidgets(
      'tap per-row PubMed pill → opens citations sheet for that ingredient',
      (tester) async {
        await _pump(
          tester,
          evidenceData: {
            'match_count': 1,
            'clinical_matches': [
              _match(ingredient: 'Ashwagandha', pmids: const ['111', '222']),
            ],
          },
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('PubMed'));
        await tester.pumpAndSettle();

        expect(find.text('PMID: 111'), findsOneWidget);
        expect(find.text('PMID: 222'), findsOneWidget);
      },
    );

    testWidgets('renders unsubstantiated claims when present', (tester) async {
      await _pump(
        tester,
        evidenceData: {
          'match_count': 1,
          'clinical_matches': [
            _match(evidence: 'limited', pmids: const ['111']),
          ],
          'unsubstantiated_claims': const ['Cures all illness'],
        },
      );
      await tester.pumpAndSettle();
      expect(find.text('Unsubstantiated claims'), findsOneWidget);
      expect(find.text('Cures all illness'), findsOneWidget);
    });
  });
}
