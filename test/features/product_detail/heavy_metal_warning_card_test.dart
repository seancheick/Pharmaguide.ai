import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/product_detail/widgets/heavy_metal_warning_card.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('renders nothing when heavyMetalDetail is null', (tester) async {
    await tester.pumpWidget(
      wrap(const HeavyMetalWarningCard(heavyMetalDetail: null)),
    );
    await tester.pump();
    expect(find.text('Heavy Metal Risk'), findsNothing);
  });

  testWidgets('renders nothing when signals list is empty', (tester) async {
    await tester.pumpWidget(
      wrap(
        const HeavyMetalWarningCard(
          heavyMetalDetail: {'signals': <Map<String, dynamic>>[]},
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Heavy Metal Risk'), findsNothing);
  });

  testWidgets('renders card title and ingredient when signals present', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        const HeavyMetalWarningCard(
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
    expect(find.text('Heavy Metal Risk'), findsOneWidget);
    expect(find.text('Kelp'), findsOneWidget);
  });
}
