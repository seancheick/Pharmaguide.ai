import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/models/research_pair_evidence.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/research_evidence_section.dart';

ResearchPairEvidence _evidence({
  String pairId = 'C0042878-C0043031',
  String entityAName = 'Vitamin K',
  String entityBName = 'Warfarin',
  int paperCount = 12,
}) {
  return ResearchPairEvidence(
    pairId: pairId,
    entityAName: entityAName,
    entityBName: entityBName,
    entityAType: 'supplement',
    entityBType: 'drug',
    canonicalIdA: 'vitamin_k',
    canonicalIdB: null,
    rxcuiA: null,
    rxcuiB: '11289',
    paperCount: paperCount,
    humanStudyCount: 3,
    clinicalStudyCount: 2,
    latestPaperYear: 2024,
    topSentences: const [
      ResearchPairSentence(
        pmid: '12345',
        sentence: 'Vitamin K and warfarin appeared together in patients.',
      ),
    ],
    topPmids: const ['12345'],
  );
}

Widget _harness({
  required List<ResearchPairEvidence> evidence,
  List<String> canonicalIds = const ['vitamin_k'],
}) {
  return ProviderScope(
    overrides: [
      researchEvidenceForProductProvider(
        ResearchEvidenceRequest(canonicalIds: canonicalIds),
      ).overrideWith((ref) async => evidence),
    ],
    child: MaterialApp(
      home: Scaffold(body: ResearchEvidenceSection(canonicalIds: canonicalIds)),
    ),
  );
}

void main() {
  testWidgets('renders a neutral research evidence chip', (tester) async {
    await tester.pumpWidget(_harness(evidence: [_evidence()]));
    await tester.pumpAndSettle();

    expect(find.text('RESEARCH AVAILABLE'), findsOneWidget);
    expect(find.textContaining('published papers mention'), findsOneWidget);
    expect(find.textContaining('not a safety warning'), findsOneWidget);
  });

  testWidgets('does not render when canonical ids are empty', (tester) async {
    await tester.pumpWidget(
      _harness(evidence: [_evidence()], canonicalIds: const []),
    );
    await tester.pumpAndSettle();

    expect(find.text('RESEARCH AVAILABLE'), findsNothing);
  });

  testWidgets('does not render when lookup returns no evidence', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(evidence: const []));
    await tester.pumpAndSettle();

    expect(find.text('RESEARCH AVAILABLE'), findsNothing);
  });

  testWidgets('opens drawer with sentences and PMID chips', (tester) async {
    await tester.pumpWidget(_harness(evidence: [_evidence()]));
    await tester.pumpAndSettle();

    await tester.tap(find.text('RESEARCH AVAILABLE'));
    await tester.pumpAndSettle();

    expect(find.text('RESEARCH EVIDENCE'), findsOneWidget);
    expect(find.text('PubMed co-occurrences from supp.ai'), findsOneWidget);
    expect(
      find.text('Vitamin K and warfarin appeared together in patients.'),
      findsOneWidget,
    );
    expect(find.text('PMID 12345'), findsOneWidget);
  });

  testWidgets('shows top evidence pills without severity language', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        evidence: [
          _evidence(entityBName: 'Warfarin', paperCount: 12),
          _evidence(
            pairId: 'C0042878-C9999999',
            entityBName: 'Aspirin',
            paperCount: 8,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Vitamin K + Warfarin'), findsOneWidget);
    expect(find.textContaining('Vitamin K + Aspirin'), findsOneWidget);
    expect(find.textContaining('Avoid'), findsNothing);
    expect(find.textContaining('Caution'), findsNothing);
  });
}
