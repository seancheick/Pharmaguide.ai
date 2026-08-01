import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/core/theme/v2/v2_theme.dart';
import 'package:pharmaguide/core/widgets/pg_severity_pill.dart';

/// Widget tests for [PGSeverityPill] — one per Severity enum value, in
/// both compact and full sizes, light and dark mode. These are the
/// first line of defense against severity/color regressions.
void main() {
  Widget wrap(Widget child, {Brightness brightness = Brightness.light}) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: brightness == Brightness.light ? V2Theme.light : V2Theme.dark,
      home: Scaffold(body: Center(child: child)),
    );
  }

  group('PGSeverityPill — labels', () {
    // 2026-04-30 — labels migrated to softer-tone sentence case.
    // See severity.dart for the full vocab + rationale.
    testWidgets('contraindicated renders "Do not use"', (tester) async {
      await tester.pumpWidget(
        wrap(const PGSeverityPill(severity: Severity.contraindicated)),
      );
      expect(find.text('Do not use'), findsOneWidget);
      expect(find.byIcon(Icons.block_rounded), findsOneWidget);
    });

    testWidgets('avoid renders "Not recommended"', (tester) async {
      await tester.pumpWidget(
        wrap(const PGSeverityPill(severity: Severity.avoid)),
      );
      expect(find.text('Not recommended'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    });

    testWidgets('caution renders "Use caution"', (tester) async {
      await tester.pumpWidget(
        wrap(const PGSeverityPill(severity: Severity.caution)),
      );
      expect(find.text('Use caution'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });

    testWidgets('monitor renders "Monitor"', (tester) async {
      await tester.pumpWidget(
        wrap(const PGSeverityPill(severity: Severity.monitor)),
      );
      expect(find.text('Monitor'), findsOneWidget);
      expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
    });

    testWidgets('safe renders "Safe"', (tester) async {
      await tester.pumpWidget(
        wrap(const PGSeverityPill(severity: Severity.safe)),
      );
      expect(find.text('Safe'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline_rounded), findsOneWidget);
    });
  });

  group('PGSeverityPill — compact mode', () {
    testWidgets('compact pill renders all 5 severities without overflow', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PGSeverityPill(severity: Severity.contraindicated, compact: true),
              SizedBox(width: 4),
              PGSeverityPill(severity: Severity.avoid, compact: true),
              SizedBox(width: 4),
              PGSeverityPill(severity: Severity.caution, compact: true),
              SizedBox(width: 4),
              PGSeverityPill(severity: Severity.monitor, compact: true),
              SizedBox(width: 4),
              PGSeverityPill(severity: Severity.safe, compact: true),
            ],
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(PGSeverityPill), findsNWidgets(5));
    });
  });

  group('PGSeverityPill — dark mode', () {
    testWidgets('dark mode uses the dark severity token, not the light one', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const PGSeverityPill(severity: Severity.contraindicated),
          brightness: Brightness.dark,
        ),
      );
      expect(find.text('Do not use'), findsOneWidget);

      final icon = tester.widget<Icon>(find.byIcon(Icons.block_rounded));
      expect(
        icon.color,
        V2Palette.dark.contraindicated,
        reason:
            'The light token measures 2.38:1 on a dark surface — below even '
            'the 3:1 non-text floor.',
      );
      expect(icon.color, isNot(V2Palette.light.contraindicated));
    });

    testWidgets('dark mode fills neutral, never a tint of its own hue', (
      tester,
    ) async {
      // A same-hue tint lifts the background toward the label: at the previous
      // 22% alpha the highest-stakes pill in the app rendered at 2.11:1. The
      // label is 11.5-12.5pt bold, under WCAG's 14pt-bold threshold, so 4.5:1
      // is required and the 3:1 floor is unavailable.
      await tester.pumpWidget(
        wrap(
          const PGSeverityPill(severity: Severity.contraindicated),
          brightness: Brightness.dark,
        ),
      );

      final decorated = tester.widget<Container>(
        find
            .ancestor(
              of: find.byIcon(Icons.block_rounded),
              matching: find.byType(Container),
            )
            .first,
      );
      final fill = (decorated.decoration! as BoxDecoration).color!;

      expect(
        fill,
        V2Palette.dark.surfaceHigh,
        reason: 'dark pills fill with the neutral elevated surface',
      );
      expect(
        fill.a,
        1.0,
        reason: 'an opaque fill keeps the rendered contrast predictable',
      );
    });

    testWidgets('light mode keeps its tinted fill', (tester) async {
      await tester.pumpWidget(
        wrap(const PGSeverityPill(severity: Severity.contraindicated)),
      );
      final icon = tester.widget<Icon>(find.byIcon(Icons.block_rounded));
      expect(icon.color, V2Palette.light.contraindicated);
    });
  });
}
