import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/theme/v2/v2_theme.dart';
import 'package:pharmaguide/core/widgets/pg_frosted_app_bar.dart';

void main() {
  group('PGFrostedAppBar', () {
    testWidgets('renders title centered', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                PGFrostedAppBar(title: 'My Stack'),
                SliverToBoxAdapter(child: SizedBox(height: 800)),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('My Stack'), findsOneWidget);
    });

    testWidgets('renders leading back button by default in nested route', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                child: const Text('open'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const Scaffold(
                      body: CustomScrollView(
                        slivers: [PGFrostedAppBar(title: 'Detail')],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      // Default leading icon is the back chevron.
      expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsOneWidget);
    });

    testWidgets('renders custom actions', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                PGFrostedAppBar(
                  title: 'Profile',
                  actions: [
                    IconButton(icon: const Icon(Icons.edit), onPressed: () {}),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.edit), findsOneWidget);
    });

    testWidgets('hides leading when automaticallyImplyLeading is false', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                PGFrostedAppBar(title: 'Tab', automaticallyImplyLeading: false),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsNothing);
    });

    testWidgets('title follows a live appearance change', (tester) async {
      Widget app(ThemeData theme) => MaterialApp(
        theme: theme,
        home: const Scaffold(
          body: CustomScrollView(
            slivers: [
              PGFrostedAppBar(
                title: 'Appearance',
                automaticallyImplyLeading: false,
              ),
            ],
          ),
        ),
      );

      await tester.pumpWidget(app(V2Theme.light));
      await tester.pumpAndSettle();
      final light = tester.widget<Text>(find.text('Appearance')).style?.color;

      await tester.pumpWidget(app(V2Theme.dark));
      await tester.pumpAndSettle();
      final dark = tester.widget<Text>(find.text('Appearance')).style?.color;

      expect(light, V2Theme.light.textTheme.titleMedium?.color);
      expect(dark, V2Theme.dark.textTheme.titleMedium?.color);
      expect(dark, isNot(light));
    });
  });
}
