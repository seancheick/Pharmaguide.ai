import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/components/pg_review_before_use_card.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/widgets/pg_severity_pill.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/review_before_use_helpers.dart';
import 'package:pharmaguide/features/product_detail/widgets/interaction_warnings.dart';

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );
  }

  group('pipeline severity vocabulary', () {
    const cases = <String, Severity>{
      'critical': Severity.contraindicated,
      'high': Severity.avoid,
      'moderate': Severity.caution,
      'low': Severity.monitor,
      'no_data': Severity.monitor,
    };

    test('InteractionWarning.fromJson parses every emitted value', () {
      for (final entry in cases.entries) {
        final warning = InteractionWarning.fromJson({
          'severity': entry.key,
          'title': 'Pipeline warning',
        });

        expect(warning.severity, entry.value, reason: entry.key);
      }
    });

    test('warning sorting keeps critical/high above softer severities', () {
      final warnings = [
        InteractionWarning.fromJson({'severity': 'low', 'title': 'Low'}),
        InteractionWarning.fromJson({
          'severity': 'critical',
          'title': 'Critical',
        }),
        InteractionWarning.fromJson({
          'severity': 'moderate',
          'title': 'Moderate',
        }),
        InteractionWarning.fromJson({'severity': 'high', 'title': 'High'}),
      ];

      final sorted = sortWarningsBySeverity(warnings);

      expect(sorted.map((w) => w.title), [
        'Critical',
        'High',
        'Moderate',
        'Low',
      ]);
    });

    test('tone mapping never renders pipeline severities as safe', () {
      expect(
        toneForWarning(Severity.fromString('critical')),
        PGReviewTone.danger,
      );
      expect(toneForWarning(Severity.fromString('high')), PGReviewTone.danger);
      expect(
        toneForWarning(Severity.fromString('moderate')),
        PGReviewTone.caution,
      );
      expect(toneForWarning(Severity.fromString('low')), PGReviewTone.caution);
      expect(
        toneForWarning(Severity.fromString('no_data')),
        PGReviewTone.caution,
      );
    });

    testWidgets('pipeline severities render expected pill labels and icons', (
      tester,
    ) async {
      final cases = [
        (
          raw: 'critical',
          text: 'Do not use',
          icon: Icons.block_rounded,
          color: const Color(0xFFDC2626),
        ),
        (
          raw: 'high',
          text: 'Not recommended',
          icon: Icons.error_outline_rounded,
          color: const Color(0xFFDC2626),
        ),
        (
          raw: 'moderate',
          text: 'Use caution',
          icon: Icons.warning_amber_rounded,
          color: const Color(0xFFF97316),
        ),
        (
          raw: 'low',
          text: 'Monitor',
          icon: Icons.visibility_outlined,
          color: const Color(0xFFEAB308),
        ),
        (
          raw: 'no_data',
          text: 'Monitor',
          icon: Icons.visibility_outlined,
          color: const Color(0xFFEAB308),
        ),
      ];

      for (final c in cases) {
        final severity = Severity.fromString(c.raw);
        expect(severity.color, c.color, reason: c.raw);

        await tester.pumpWidget(wrap(PGSeverityPill(severity: severity)));
        expect(find.text(c.text), findsOneWidget, reason: c.raw);
        expect(find.byIcon(c.icon), findsOneWidget, reason: c.raw);
      }
    });

    testWidgets('critical banned warning maps to critical pill, never safe', (
      tester,
    ) async {
      final warning = InteractionWarning.fromJson({
        'type': 'banned_substance',
        'severity': 'critical',
        'title': 'Banned substance: Brominated Vegetable Oil',
        'detail': 'Not permitted for dietary supplements.',
      });

      expect(warning.severity, Severity.contraindicated);
      expect(warning.title, 'Banned substance: Brominated Vegetable Oil');

      await tester.pumpWidget(wrap(PGSeverityPill(severity: warning.severity)));

      expect(find.text('Do not use'), findsWidgets);
      expect(find.byIcon(Icons.block_rounded), findsWidgets);
      expect(find.text('Safe'), findsNothing);
    });
  });
}
