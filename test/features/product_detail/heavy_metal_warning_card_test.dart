import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/heavy_metal_section.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('renders nothing when heavyMetalDetail is null', (tester) async {
    await tester.pumpWidget(
      wrap(buildHeavyMetalSection(heavyMetalDetail: null)),
    );
    await tester.pump();
    expect(find.text('HEAVY METAL RISK'), findsNothing);
  });

  testWidgets('renders nothing when signals list is empty', (tester) async {
    await tester.pumpWidget(
      wrap(
        buildHeavyMetalSection(
          heavyMetalDetail: {'signals': <Map<String, dynamic>>[]},
        ),
      ),
    );
    await tester.pump();
    expect(find.text('HEAVY METAL RISK'), findsNothing);
  });

  testWidgets('renders card title and ingredient when signals present', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        buildHeavyMetalSection(
          heavyMetalDetail: {
            'signals': [
              {
                'ingredient': 'Kelp',
                'limit_source': 'Prop 65',
                'risk_level': 'high',
                'notes': 'Iodine accumulates heavy metals from seawater.',
              },
            ],
          },
        ),
      ),
    );
    await tester.pump();
    expect(find.text('HEAVY METAL RISK'), findsOneWidget);
    expect(find.text('Kelp'), findsOneWidget);
  });
}
