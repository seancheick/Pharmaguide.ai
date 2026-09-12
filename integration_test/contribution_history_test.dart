import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/core/theme/v2/v2_theme.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/providers/detail_blob_provider.dart';
import 'package:pharmaguide/features/scanner/product_version_label_sheet.dart';

import '../test/features/contributions/product_submissions_screen_test.dart'
    show submissionHistoryHarness;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('version confirmation shows source label amounts', (
    tester,
  ) async {
    const product = ProductsCoreData(
      dsldId: 'fixture',
      productName: 'Example prenatal',
      exportVersion: 'test',
      exportedAt: '2026-09-12T00:00:00Z',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          detailBlobProvider('fixture').overrideWith(
            (ref) async => {
              'display_ingredients': [
                {
                  'label_display_name': 'Biotin',
                  'exact_dose_text': '35 mcg',
                  'label_order': 0,
                  'nested_depth': 0,
                  'raw_source_path': 'ingredientRows[0]',
                  'display_disposition': 'label_context',
                  'form_display_state': 'not_applicable',
                },
              ],
            },
          ),
        ],
        child: MaterialApp(
          theme: V2Theme.light,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () =>
                    showProductVersionLabelSheet(context, product: product),
                child: const Text('Compare'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Compare'));
    await tester.pumpAndSettle();
    expect(find.text('35 mcg'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await binding.takeScreenshot('label-version-confirmation');
  });

  testWidgets(
    'history identifies products and keeps the add action in bounds',
    (tester) async {
      await tester.pumpWidget(
        submissionHistoryHarness([
          for (final entry in [
            ('Align Women’s Dual Action', 'approved'),
            ('Grüns Super Greens Gummies', 'rejected'),
            ('One A Day Prenatal Advanced', 'submitted'),
          ])
            {
              'id': entry.$1,
              'kind': 'missing_product',
              'normalized_upc': '030772032565',
              'display_name': entry.$1,
              'upload_state': 'ready',
              'review_status': entry.$2,
              'created_at': '2026-09-12T12:00:00Z',
            },
        ]),
      );
      await tester.pumpAndSettle();
      final add = find.byKey(const Key('contributions-add-product'));
      final rect = tester.getRect(add);
      expect(rect.size, const Size(48, 48));
      expect(
        rect.right,
        lessThanOrEqualTo(
          tester.view.physicalSize.width / tester.view.devicePixelRatio,
        ),
      );
      expect(find.text('Name this product'), findsNothing);
      expect(tester.takeException(), isNull);
      await binding.takeScreenshot('contribution-history-top');
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -480));
      await tester.pumpAndSettle();
      expect(find.text('Align Women’s Dual Action'), findsOneWidget);
      expect(find.text('Grüns Super Greens Gummies'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await binding.takeScreenshot('contribution-history-products');
    },
  );
}
