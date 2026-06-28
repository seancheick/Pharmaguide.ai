import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/components/pg_transparency_footer.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/transparency_footer_section.dart';

Widget _wrap(Widget child) {
  return MaterialApp(home: Scaffold(body: child));
}

void main() {
  group('PGTransparencyFooter', () {
    testWidgets('renders v2 sources, freshness, and disclaimer', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const PGTransparencyFooter(freshnessLabel: 'Updated May 18, 2026'),
        ),
      );

      expect(find.text('DATA SOURCES'), findsOneWidget);
      expect(find.text('NIH ODS · PubMed · FDA'), findsOneWidget);
      expect(find.text('Updated May 18, 2026'), findsOneWidget);
      expect(
        find.text(
          'PharmaGuide is for informational purposes only — talk to your '
          'doctor before changing your stack.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('freshness line hides when no freshness label is available', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const PGTransparencyFooter()));

      expect(find.textContaining('Updated'), findsNothing);
      expect(find.text('NIH ODS · PubMed · FDA'), findsOneWidget);
    });

    testWidgets('does not render the retired coverage segment', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const PGTransparencyFooter(freshnessLabel: 'Updated May 18, 2026'),
        ),
      );

      expect(find.textContaining('Coverage:'), findsNothing);
    });

    testWidgets('does not use italic styling', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const PGTransparencyFooter(freshnessLabel: 'Updated May 18, 2026'),
        ),
      );

      final textWidgets = tester.widgetList<Text>(find.byType(Text));
      expect(textWidgets, isNotEmpty, reason: 'footer should render text');
      for (final text in textWidgets) {
        expect(text.style?.fontStyle, isNot(FontStyle.italic));
      }
    });

    testWidgets('supports centered home footer variant', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const PGTransparencyFooter(
            freshnessLabel: 'Updated May 18, 2026',
            center: true,
          ),
        ),
      );

      final disclaimer = tester.widget<Text>(
        find.text(
          'PharmaGuide is for informational purposes only — talk to your '
          'doctor before changing your stack.',
        ),
      );
      expect(disclaimer.textAlign, TextAlign.center);
    });

    testWidgets('product detail adapter uses centered footer variant', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            catalogInfoProvider.overrideWith(
              (ref) async => CatalogInfo(
                productCount: 9270,
                buildDate: DateTime.utc(2026, 6, 12),
              ),
            ),
          ],
          child: _wrap(const TransparencyFooterSection()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('DATA SOURCES'), findsOneWidget);
      expect(find.text('NIH ODS · PubMed · FDA'), findsOneWidget);
      expect(find.text('Updated Jun 12, 2026'), findsOneWidget);

      final disclaimer = tester.widget<Text>(
        find.text(
          'PharmaGuide is for informational purposes only — talk to your '
          'doctor before changing your stack.',
        ),
      );
      expect(disclaimer.textAlign, TextAlign.center);
    });
  });
}
