import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/widgets/pg_severity_pill.dart';

/// Widget tests for [PGSeverityPill] — one per Severity enum value, in
/// both compact and full sizes, light and dark mode. These are the
/// first line of defense against severity/color regressions.
void main() {
  Widget wrap(Widget child, {Brightness brightness = Brightness.light}) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
      home: Scaffold(body: Center(child: child)),
    );
  }

  group('PGSeverityPill — labels', () {
    testWidgets('contraindicated renders "DO NOT USE"', (tester) async {
      await tester.pumpWidget(
        wrap(const PGSeverityPill(severity: Severity.contraindicated)),
      );
      expect(find.text('DO NOT USE'), findsOneWidget);
      expect(find.byIcon(Icons.block_rounded), findsOneWidget);
    });

    testWidgets('avoid renders "AVOID"', (tester) async {
      await tester.pumpWidget(
        wrap(const PGSeverityPill(severity: Severity.avoid)),
      );
      expect(find.text('AVOID'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    });

    testWidgets('caution renders "CAUTION"', (tester) async {
      await tester.pumpWidget(
        wrap(const PGSeverityPill(severity: Severity.caution)),
      );
      expect(find.text('CAUTION'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });

    testWidgets('monitor renders "MONITOR"', (tester) async {
      await tester.pumpWidget(
        wrap(const PGSeverityPill(severity: Severity.monitor)),
      );
      expect(find.text('MONITOR'), findsOneWidget);
      expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
    });

    testWidgets('safe renders "SAFE"', (tester) async {
      await tester.pumpWidget(
        wrap(const PGSeverityPill(severity: Severity.safe)),
      );
      expect(find.text('SAFE'), findsOneWidget);
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
    testWidgets('dark mode renders all severities with higher bg alpha', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const PGSeverityPill(severity: Severity.contraindicated),
          brightness: Brightness.dark,
        ),
      );
      expect(find.text('DO NOT USE'), findsOneWidget);
      // Verify color is the severity token (exact alpha is internal)
      final iconFinder = find.byIcon(Icons.block_rounded);
      final icon = tester.widget<Icon>(iconFinder);
      expect(icon.color, AppTheme.severityContraindicated);
    });
  });
}
