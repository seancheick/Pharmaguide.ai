// The app caps text scale at 1.4x (lib/app.dart). At that cap, on the smallest
// supported phone (iPhone SE, 375x667 pt), these components overflowed or
// clipped (text-scale audit, 2026-10-02). Each must lay out without a
// rendering exception at 1.4x on that surface.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/components/pg_score_line.dart';
import 'package:pharmaguide/core/components/pg_transparency_footer.dart';
import 'package:pharmaguide/core/widgets/pg_severity_banner.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/features/scanner/product_version_picker_sheet.dart';
import 'package:pharmaguide/features/scanner/v2/camera_permission_v2_screen.dart';
import 'package:pharmaguide/features/stack/widgets/nutrient_progress_bar.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_models.dart';

const _largeText = TextScaler.linear(1.4);

Future<void> _pumpOnSmallPhone(WidgetTester tester, Widget home) async {
  tester.view.devicePixelRatio = 2.0;
  tester.view.physicalSize = const Size(750, 1334);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: _largeText),
          child: child!,
        ),
        home: home,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

Widget _inPage(Widget child) => Scaffold(
  body: SingleChildScrollView(
    child: Padding(padding: const EdgeInsets.all(16), child: child),
  ),
);

ProductsCoreData _product(String id, String name) => ProductsCoreData(
  dsldId: id,
  productName: name,
  brandName: 'Example Brand With A Long Name',
  formFactor: 'softgel',
  netContentsQuantity: 120,
  netContentsUnit: 'Softgels',
  qualityScoreV4100: 82,
  exportVersion: 'test',
  exportedAt: '2026-08-19T00:00:00Z',
);

void main() {
  testWidgets('severity banner action label wraps instead of overflowing', (
    tester,
  ) async {
    await _pumpOnSmallPhone(
      tester,
      _inPage(
        PGSeverityBanner(
          tone: PGBannerTone.caution,
          title: 'Worth a conversation with your doctor',
          body:
              'This product contains an ingredient that interacts with one of your medications.',
          actionLabel: 'Review the interaction details',
          onAction: () {},
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('score line fits the 130pt recent-scan slot and a full row', (
    tester,
  ) async {
    await _pumpOnSmallPhone(
      tester,
      _inPage(
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 130, child: PGScoreLine(score: 82, compact: true)),
            PGScoreLine(score: 82, prominent: true),
            PGScoreLine(score: 82),
          ],
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('82/100'), findsNWidgets(3));
  });

  testWidgets('centered transparency footer keeps its sources inside the row', (
    tester,
  ) async {
    await _pumpOnSmallPhone(
      tester,
      _inPage(
        const PGTransparencyFooter(
          center: true,
          sources: ['NIH ODS', 'PubMed', 'FDA', 'DSLD'],
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('nutrient bar keeps the amount and UL inside the row', (
    tester,
  ) async {
    await _pumpOnSmallPhone(
      tester,
      _inPage(
        const NutrientProgressBar(
          status: NutrientStatus(
            total: NutrientTotal(
              canonicalId: 'magnesium',
              displayName: 'Magnesium (as glycinate)',
              minimumTotalAmount: 1000,
              totalAmount: 1250,
              unit: 'mg',
              contributions: [],
            ),
            tier: NutrientTier.exceedsUl,
            pctOfUl: 357,
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('camera permission gate scrolls instead of clipping', (
    tester,
  ) async {
    await _pumpOnSmallPhone(
      tester,
      CameraPermissionV2Screen(onPrimaryAction: () {}, onManualEntry: () {}),
    );
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.text('Enter code manually'),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Enter code manually'), findsOneWidget);
  });

  testWidgets('bottle picker scrolls its header and candidates together', (
    tester,
  ) async {
    await _pumpOnSmallPhone(
      tester,
      Scaffold(
        body: ProductVersionPickerSheet(
          candidates: [
            _product('one', 'Omega-3 Fish Oil Triple Strength — 60 count'),
            _product('two', 'Omega-3 Fish Oil Triple Strength — 120 count'),
          ],
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
