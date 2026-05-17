import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/models/timing_optimization.dart';
import 'package:pharmaguide/features/stack/v2/widgets/pg_timing_advice_card.dart';

void main() {
  testWidgets('PGTimingAdviceCard lays out inside a scrollable stack list', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: PGTimingAdviceCard(
                  optimizations: [
                    TimingOptimization(
                      ruleId: 'timing_magnesium_food',
                      ingredient1: 'magnesium',
                      ingredient2: '',
                      advice: 'Take magnesium with a meal',
                      ruleType: TimingRuleType.takeWithFood,
                      scoreImpact: 0,
                      evidenceLevel: EvidenceLevel.theoretical,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Timing optimization'), findsOneWidget);
    expect(find.text('Take magnesium with a meal'), findsOneWidget);
  });
}
