// FLTR-4 / FLTR-19 — product_status row.
//
// FLTR-4 baseline: renders the pipeline's structured status block
// as a neutral grey soft signal. Never red, never "safe", never an
// alert.
//
// FLTR-19 polish:
//   - Humanize the date from ISO to "MMM d, yyyy" when parseable.
//   - Row is tappable (whole row, not an icon affordance that used
//     to hint interactivity without delivering it).
//   - Tap opens a bottom sheet with a plain-language explanation.
//   - Falls back to pipeline `display` verbatim when `type` or
//     `date` is missing/unrecognized.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/product_detail/widgets/product_status_chip.dart';

void main() {
  group('ProductStatusChip — FLTR-4 baseline', () {
    Widget wrap(Map<String, dynamic> status) {
      return MaterialApp(
        home: Scaffold(body: ProductStatusChip(productStatus: status)),
      );
    }

    testWidgets(
        'renders empty when no label can be built (no type, no display)',
        (tester) async {
      await tester.pumpWidget(wrap(const {'date': '2017-11-28'}));
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('renders empty when display is blank and no type', (tester) async {
      await tester.pumpWidget(wrap(const {'display': '   '}));
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('falls back to pipeline display string when date absent',
        (tester) async {
      // A future `type` (e.g., off_market) without a date and a
      // pipeline-provided display — just render the display verbatim.
      await tester.pumpWidget(wrap(const {
        'type': 'off_market',
        'display': 'Off market — currently unavailable',
      }));
      expect(
        find.text('Off market — currently unavailable'),
        findsOneWidget,
      );
    });

    testWidgets(
        'falls back to pipeline display when type is unrecognized',
        (tester) async {
      // Forward-compat: unknown type + no humanizable date → trust
      // the pipeline's display string.
      await tester.pumpWidget(wrap(const {
        'type': 'brand_new_type_we_dont_know_yet',
        'display': 'Some custom status',
      }));
      expect(find.text('Some custom status'), findsOneWidget);
    });
  });

  group('ProductStatusChip — FLTR-19 humanized label', () {
    Widget wrap(Map<String, dynamic> status) {
      return MaterialApp(
        home: Scaffold(body: ProductStatusChip(productStatus: status)),
      );
    }

    testWidgets(
        'humanizes ISO date for known type (discontinued)',
        (tester) async {
      await tester.pumpWidget(wrap(const {
        'type': 'discontinued',
        'date': '2017-11-28',
        'display': 'Discontinued · 2017-11-28', // ignored when humanized
      }));
      expect(
        find.text('Product discontinued · Nov 28, 2017'),
        findsOneWidget,
      );
      // Verbatim ISO text must not leak through when we humanize.
      expect(find.text('Discontinued · 2017-11-28'), findsNothing);
    });

    testWidgets('humanizes ISO date for known type (reformulated)',
        (tester) async {
      await tester.pumpWidget(wrap(const {
        'type': 'reformulated',
        'date': '2024-06-15',
      }));
      expect(find.text('Reformulated · Jun 15, 2024'), findsOneWidget);
    });

    testWidgets(
        'falls back to display when date is malformed',
        (tester) async {
      await tester.pumpWidget(wrap(const {
        'type': 'discontinued',
        'date': 'not-a-date',
        'display': 'Discontinued · unknown',
      }));
      expect(find.text('Discontinued · unknown'), findsOneWidget);
    });

    testWidgets('row is tappable — opens explanation sheet',
        (tester) async {
      await tester.pumpWidget(wrap(const {
        'type': 'discontinued',
        'date': '2017-11-28',
      }));
      await tester.tap(find.text('Product discontinued · Nov 28, 2017'));
      await tester.pumpAndSettle();
      expect(find.text('About this product status'), findsOneWidget);
      expect(
        find.textContaining('no longer manufactured'),
        findsOneWidget,
      );
    });

    testWidgets(
        'no leading info-icon (FLTR-19 removed hidden affordance)',
        (tester) async {
      await tester.pumpWidget(wrap(const {
        'type': 'discontinued',
        'date': '2017-11-28',
      }));
      expect(find.byIcon(Icons.info_outline_rounded), findsNothing);
      // A trailing chevron signals the row is tappable.
      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
    });
  });
}
