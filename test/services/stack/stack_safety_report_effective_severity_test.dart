// P2 follow-up — StackSafetyReport must weight a food advisory by its REAL
// curated severity (effectiveSeverity), not the informational DISPLAY value.
// Before: overallSeverity/severityCounts read r.severity, so a serious
// grapefruit × statin advisory (authored `avoid`, displayed informational)
// contributed nothing to the banner color or the "1 avoid" badge.

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/models/interaction_result.dart';
import 'package:pharmaguide/data/database/interaction_database.dart';
import 'package:pharmaguide/services/stack/stack_safety_report.dart';

void main() {
  group('StackSafetyReport effective severity', () {
    test(
      'serious food advisory raises overallSeverity to its real severity',
      () {
        final advisory = InteractionResult.fromRow(
          _row(severity: 'avoid', alertStyle: 'food_advisory_note'),
        );
        // Display value is still informational (backward-compat)...
        expect(advisory.severity, Severity.informational);
        final report = StackSafetyReport(medicationInteractions: [advisory]);
        // ...but the report must weight it as avoid.
        expect(report.overallSeverity, Severity.avoid);
      },
    );

    test('food advisory counts under its real severity bucket', () {
      final advisory = InteractionResult.fromRow(
        _row(severity: 'avoid', alertStyle: 'food_advisory_note'),
      );
      final report = StackSafetyReport(medicationInteractions: [advisory]);
      expect(report.severityCounts[Severity.avoid], 1);
      expect(report.severityCounts[Severity.informational], 0);
    });

    test('a non-advisory interaction is unaffected', () {
      final normal = InteractionResult.fromRow(_row(severity: 'caution'));
      final report = StackSafetyReport(stackInteractions: [normal]);
      expect(report.overallSeverity, Severity.caution);
      expect(report.severityCounts[Severity.caution], 1);
    });
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
    noteBody: alertStyle == 'food_advisory_note' ? 'note' : null,
    practicalGuidance: alertStyle == 'food_advisory_note' ? 'guidance' : null,
  );
}
