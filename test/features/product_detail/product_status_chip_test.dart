// FLTR-4 — product_status chip renders the pipeline's verbatim
// `display` string as a neutral grey soft signal. Never red,
// never "safe", never an alert.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/product_detail/widgets/product_status_chip.dart';

void main() {
  group('ProductStatusChip', () {
    Widget wrap(Map<String, dynamic> status) {
      return MaterialApp(
        home: Scaffold(body: ProductStatusChip(productStatus: status)),
      );
    }

    testWidgets('renders the pipeline display string verbatim',
        (tester) async {
      await tester.pumpWidget(wrap(const {
        'type': 'discontinued',
        'date': '2017-11-28',
        'display': 'Discontinued · 2017-11-28',
      }));
      expect(find.text('Discontinued · 2017-11-28'), findsOneWidget);
    });

    testWidgets('renders empty when display is missing', (tester) async {
      await tester.pumpWidget(wrap(const {
        'type': 'discontinued',
        'date': '2017-11-28',
      }));
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('renders empty when display is blank', (tester) async {
      await tester.pumpWidget(wrap(const {'display': '   '}));
      expect(find.byType(Text), findsNothing);
    });

    testWidgets(
        'accepts future type values (off_market, reformulated, etc.) — trusts display',
        (tester) async {
      // Forward-compatibility: we never branch on `type`; the pipeline
      // owns the label. A new status type renders the same way.
      await tester.pumpWidget(wrap(const {
        'type': 'reformulated',
        'display': 'Reformulated · 2024',
      }));
      expect(find.text('Reformulated · 2024'), findsOneWidget);
    });
  });
}
