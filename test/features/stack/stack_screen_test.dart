import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/stack/stack_screen.dart';

void main() {
  Widget buildTestWidget() {
    return const ProviderScope(
      child: MaterialApp(home: StackScreen()),
    );
  }

  group('StackScreen', () {
    testWidgets('shows stack and wishlist tabs', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('My Stack'), findsWidgets);
      expect(find.text('Wishlist'), findsOneWidget);
    });

    testWidgets('shows empty stack state and wishlist empty state', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Your stack is empty'), findsOneWidget);

      await tester.tap(find.text('Wishlist'));
      await tester.pumpAndSettle();

      expect(find.text('No saved products'), findsOneWidget);
    });
  });
}
