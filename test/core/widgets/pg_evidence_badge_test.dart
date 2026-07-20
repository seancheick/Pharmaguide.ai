import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/widgets/pg_evidence_badge.dart';

Future<void> _pump(WidgetTester tester, EvidenceLevel level) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: PGEvidenceBadge(level: level)),
    ),
  );
}

void main() {
  testWidgets('moderate renders its own label, not "Evidence not graded"', (
    tester,
  ) async {
    await _pump(tester, EvidenceLevel.moderate);
    expect(find.text('Moderate evidence'), findsOneWidget);
    expect(find.text('Evidence not graded'), findsNothing);
  });

  testWidgets('every SP-6 tier renders a distinct, non-empty label', (
    tester,
  ) async {
    const expected = <EvidenceLevel, String>{
      EvidenceLevel.established: 'Strong evidence',
      EvidenceLevel.probable: 'Good evidence',
      EvidenceLevel.moderate: 'Moderate evidence',
      EvidenceLevel.limited: 'Limited evidence',
      EvidenceLevel.theoretical: 'Theoretical',
      EvidenceLevel.noData: 'No evidence data',
      EvidenceLevel.ungraded: 'Evidence not graded',
    };
    for (final entry in expected.entries) {
      await _pump(tester, entry.key);
      expect(find.text(entry.value), findsOneWidget, reason: entry.key.name);
    }
  });
}
