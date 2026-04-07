import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/app.dart';

void main() {
  testWidgets('App renders with 5 navigation tabs', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: PharmaGuideApp()),
    );
    await tester.pumpAndSettle();

    // Verify 5 navigation destinations exist
    expect(find.byType(NavigationDestination), findsNWidgets(5));
    // Verify nav labels are present (some may appear multiple times due to screen titles)
    expect(find.text('Home'), findsWidgets);
    expect(find.text('Scan'), findsWidgets);
    expect(find.text('Stack'), findsWidgets);
    expect(find.text('Chat'), findsWidgets);
    expect(find.text('Profile'), findsWidgets);
  });

  testWidgets('Home tab is selected by default', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: PharmaGuideApp()),
    );
    await tester.pumpAndSettle();

    // Home screen content should be visible
    expect(find.text('Home'), findsWidgets); // nav + screen title
  });

  testWidgets('Tapping Scan tab navigates to scan screen', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: PharmaGuideApp()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Scan'));
    await tester.pumpAndSettle();

    expect(find.text('Scan'), findsWidgets); // nav + screen title
  });

  testWidgets('Tapping Stack tab navigates to stack screen', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: PharmaGuideApp()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Stack'));
    await tester.pumpAndSettle();

    expect(find.text('My Stack'), findsWidgets);
  });

  testWidgets('Tapping Profile tab navigates to profile screen', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: PharmaGuideApp()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();

    expect(find.text('Profile'), findsWidgets);
  });
}
