// FIX (P2) regression lock — food-advisory rows must PRESERVE their real
// curated severity on the model.
//
// Before: `InteractionResult.fromRow` set
//   severity: isFoodAdvisory ? Severity.informational : Severity.fromString(...)
// so a genuinely serious advisory (grapefruit × statin, authored
// `severity='avoid'`) was force-painted informational and contributed 0
// to any severity-weighting consumer (overallSeverity, the detail sheet).
//
// After: `severity` keeps the informational DISPLAY affordance (so the
// existing "Food note" styling / the curated-checker test that asserts
// `severity == informational` stay green), but the real curated severity
// is preserved on `curatedSeverity`, and `effectiveSeverity` exposes the
// value consumers should weight by (curatedSeverity ?? severity).

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/models/interaction_result.dart';
import 'package:pharmaguide/data/database/interaction_database.dart';

void main() {
  group('InteractionResult food-advisory curated severity', () {
    test(
      'serious food advisory (severity=avoid) keeps informational DISPLAY '
      'but preserves the real severity on curatedSeverity/effectiveSeverity',
      () {
        final r = InteractionResult.fromRow(
          _row(severity: 'avoid', alertStyle: 'food_advisory_note'),
        );

        // Display affordance unchanged — backward compatible with the
        // existing "Food note" styling and curated-checker assertions.
        expect(r.severity, Severity.informational);
        expect(r.isFoodAdvisoryNote, isTrue);

        // Real curated severity preserved for weighting.
        expect(r.curatedSeverity, Severity.avoid);
        expect(r.effectiveSeverity, Severity.avoid);
      },
    );

    test('monitor-level food advisory preserves monitor as effective', () {
      final r = InteractionResult.fromRow(
        _row(severity: 'monitor', alertStyle: 'food_advisory_note'),
      );

      expect(r.severity, Severity.informational);
      expect(r.curatedSeverity, Severity.monitor);
      expect(r.effectiveSeverity, Severity.monitor);
    });

    test(
      'non-food-advisory row is unchanged — effectiveSeverity == severity',
      () {
        final r = InteractionResult.fromRow(_row(severity: 'avoid'));

        expect(r.severity, Severity.avoid);
        expect(r.curatedSeverity, Severity.avoid);
        expect(r.effectiveSeverity, Severity.avoid);
      },
    );

    test(
      'direct constructor without curatedSeverity falls back to severity '
      '(backward compatible with existing call sites)',
      () {
        const r = InteractionResult(
          id: 'X',
          type: InteractionType.drugSupplement,
          severity: Severity.caution,
          evidenceLevel: EvidenceLevel.established,
          agent1Name: 'A',
          agent2Name: 'B',
          mechanism: 'm',
          management: 'g',
          doseDependant: false,
          doseThreshold: null,
          sourceUrls: <String>[],
          source: InteractionSource.pipeline,
        );

        expect(r.curatedSeverity, isNull);
        expect(r.effectiveSeverity, Severity.caution);
      },
    );
  });
}

InteractionRow _row({required String severity, String? alertStyle}) {
  return InteractionRow(
    id: 'TEST_ROW',
    agent1Type: 'drug_class',
    agent1Name: 'Statins',
    agent1Id: 'class:statins',
    agent2Type: alertStyle == 'food_advisory_note' ? 'food' : 'supplement',
    agent2Name: 'Grapefruit',
    agent2Id: 'food:grapefruit',
    severity: severity,
    mechanism: 'Grapefruit can raise levels of some statins.',
    management: 'Skip grapefruit or ask about another statin.',
    evidenceLevel: 'established',
    sourceUrlsJson: '[]',
    sourcePmidsJson: '[]',
    bidirectional: 1,
    doseDependent: 0,
    typeAuthored: 'drug_supplement',
    source: 'curated',
    provenance: 'test',
    versionAdded: 'test',
    versionLastModified: 'test',
    lastUpdated: 'test',
    alertStyle: alertStyle,
    noteBody: alertStyle == 'food_advisory_note'
        ? 'Grapefruit can raise levels of some statins.'
        : null,
    practicalGuidance: alertStyle == 'food_advisory_note'
        ? 'Skip grapefruit or ask about another statin.'
        : null,
  );
}
