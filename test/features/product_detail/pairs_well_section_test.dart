import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/product_detail/providers/pairs_well_provider.dart';
import 'package:pharmaguide/features/product_detail/widgets/pairs_well_section.dart';
import 'package:pharmaguide/services/stack/synergy_result.dart';

void main() {
  Widget wrap(Widget child, {List<Override> overrides = const []}) =>
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(home: Scaffold(body: child)),
      );

  testWidgets('renders nothing when loading', (tester) async {
    await tester.pumpWidget(wrap(const PairsWellSection(dsldId: '12345')));
    await tester.pump(); // don't settle async
    expect(find.text('Pairs Well with Your Stack'), findsNothing);
  });

  testWidgets('renders nothing when no pairs found', (tester) async {
    await tester.pumpWidget(wrap(
      const PairsWellSection(dsldId: '12345'),
      overrides: [
        pairsWellWithStackProvider('12345').overrideWith((_) async => []),
      ],
    ));
    await tester.pumpAndSettle();
    expect(find.text('Pairs Well with Your Stack'), findsNothing);
  });

  testWidgets('renders section title and cluster name when pairs found',
      (tester) async {
    final match = SynergyMatch(
      clusterId: 'iron_vitamin_c',
      clusterName: 'Iron + Vitamin C',
      matchedIngredients: const ['iron', 'vitamin_c'],
      mechanism: 'Vitamin C converts Fe3+ to Fe2+, which is better absorbed.',
      bonusPoints: 3,
      evidenceTier: 'strong',
      citations: const ['32891485'],
    );
    await tester.pumpWidget(wrap(
      const PairsWellSection(dsldId: '12345'),
      overrides: [
        pairsWellWithStackProvider('12345')
            .overrideWith((_) async => [match]),
      ],
    ));
    await tester.pumpAndSettle();
    expect(find.text('Pairs Well with Your Stack'), findsOneWidget);
    expect(find.text('Iron + Vitamin C'), findsOneWidget);
  });

  testWidgets('shows mechanism text when available', (tester) async {
    final match = SynergyMatch(
      clusterId: 'curcumin_piperine',
      clusterName: 'Curcumin + Piperine',
      matchedIngredients: const ['curcumin', 'piperine'],
      mechanism:
          'Piperine inhibits glucuronidation, increasing curcumin bioavailability 20x.',
      bonusPoints: 4,
      evidenceTier: 'strong',
      citations: const [],
    );
    await tester.pumpWidget(wrap(
      const PairsWellSection(dsldId: '12345'),
      overrides: [
        pairsWellWithStackProvider('12345')
            .overrideWith((_) async => [match]),
      ],
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('Piperine inhibits'), findsOneWidget);
  });
}
