// Spec: INITIATIVE_PRODUCT_DETAIL_CLEANUP.md, Sprint S2.2, T13 + T16.2g.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/features/product_detail/widgets/alert_summary_card.dart';
import 'package:pharmaguide/features/product_detail/widgets/interaction_warnings.dart';

InteractionWarning _w({
  Severity severity = Severity.caution,
  String title = 'Interaction',
  String mechanism = '',
  String management = '',
}) {
  return InteractionWarning(
    severity: severity,
    evidenceLevel: EvidenceLevel.established,
    title: title,
    mechanism: mechanism,
    management: management,
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required List<InteractionWarning> warnings,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: AlertSummaryCard(warnings: warnings),
        ),
      ),
    ),
  );
}

void main() {
  group('AlertSummaryCard — visibility', () {
    testWidgets('empty warnings → renders nothing', (tester) async {
      await _pump(tester, warnings: const []);
      expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
      expect(find.textContaining('interaction'), findsNothing);
    });

    testWidgets('1 warning → renders singular copy', (tester) async {
      await _pump(tester, warnings: [_w()]);
      expect(find.text('1 interaction to monitor'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      expect(find.byIcon(Icons.expand_more_rounded), findsOneWidget);
    });

    testWidgets('multiple warnings → plural copy with count', (tester) async {
      await _pump(tester, warnings: [_w(), _w(), _w()]);
      expect(find.text('3 interactions to monitor'), findsOneWidget);
    });
  });

  group('AlertSummaryCard — accordion expand (T16.2g)', () {
    testWidgets(
      'starts collapsed — warning bodies not visible',
      (tester) async {
        await _pump(
          tester,
          warnings: [_w(title: 'Caffeine + BP meds', mechanism: 'BP rises')],
        );
        // Header text visible, but row body (mechanism) hidden until tap.
        expect(find.text('1 interaction to monitor'), findsOneWidget);
        expect(find.text('Caffeine + BP meds'), findsNothing);
        expect(find.text('BP rises'), findsNothing);
      },
    );

    testWidgets(
      'tap header → expands to reveal warnings',
      (tester) async {
        await _pump(
          tester,
          warnings: [
            _w(
              severity: Severity.caution,
              title: 'Caffeine + BP meds',
              mechanism: 'BP rises',
              management: 'Limit caffeine.',
            ),
          ],
        );
        await tester.tap(find.text('1 interaction to monitor'));
        await tester.pumpAndSettle();
        expect(find.text('Caffeine + BP meds'), findsOneWidget);
        expect(find.text('BP rises'), findsOneWidget);
        expect(find.text('Limit caffeine.'), findsOneWidget);
        // 2026-04-30 — severity label vocab softened (severity.dart).
        expect(find.text('Use caution'), findsOneWidget);
      },
    );

    testWidgets(
      'tap again → collapses back',
      (tester) async {
        await _pump(
          tester,
          warnings: [_w(title: 'X', mechanism: 'Y')],
        );
        // Expand
        await tester.tap(find.text('1 interaction to monitor'));
        await tester.pumpAndSettle();
        expect(find.text('X'), findsOneWidget);
        // Collapse
        await tester.tap(find.text('1 interaction to monitor'));
        await tester.pumpAndSettle();
        expect(find.text('X'), findsNothing);
      },
    );

    testWidgets(
      'expanded list sorts by severity weight (worst first)',
      (tester) async {
        await _pump(
          tester,
          warnings: [
            _w(severity: Severity.monitor, title: 'M-row'),
            _w(severity: Severity.avoid, title: 'A-row'),
            _w(severity: Severity.caution, title: 'C-row'),
          ],
        );
        await tester.tap(find.text('3 interactions to monitor'));
        await tester.pumpAndSettle();

        // Order check: AVOID > CAUTION > MONITOR by widget Y position.
        final aRect = tester.getRect(find.text('A-row'));
        final cRect = tester.getRect(find.text('C-row'));
        final mRect = tester.getRect(find.text('M-row'));
        expect(aRect.top, lessThan(cRect.top));
        expect(cRect.top, lessThan(mRect.top));
      },
    );
  });
}
