import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/live_safety_alert_section.dart';
import 'package:pharmaguide/features/safety_alerts/providers/safety_alert_providers.dart';
import 'package:pharmaguide/services/safety_alerts/safety_alert.dart';
import 'package:pharmaguide/services/safety_alerts/safety_alert_repository.dart';

class _FakeRepository implements SafetyAlertRepository {
  _FakeRepository(this.alerts);
  final List<SafetyAlert> alerts;

  @override
  Future<SafetyAlertRelease> loadCurrent() async =>
      SafetyAlertRelease(alerts: alerts, baselineRevisions: const {}, isComplete: true);

  @override
  Future<List<SafetyAlert>> loadCachedAlerts() async => alerts;
}

SafetyAlert _recall({required String disposition, List<String> dsldIds = const ['700']}) =>
    SafetyAlert.fromJson({
      'alert_id': 'SA_2026_0042',
      'revision': 1,
      'event_type': 'product_recall',
      'source_url': 'https://www.fda.gov/example-recall',
      'headline': 'FDA recall: undeclared sildenafil',
      'body': 'This product was recalled for an undeclared drug ingredient.',
      'action': 'Stop taking this product and talk to your doctor.',
      'consumer_disposition': disposition,
      'resolved_dsld_ids': dsldIds,
      'scope': {'ingredient_canonical_ids': <String>[], 'dsld_ids': <String>[]},
    });

const _product = ProductsCoreData(
  dsldId: '700',
  productName: 'Energy booster',
  productSafetyStatus: 'no_known_catalog_concern',
  exportVersion: 'test',
  exportedAt: '2026-10-01T00:00:00Z',
);

Future<void> _pump(WidgetTester tester, List<SafetyAlert> alerts) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        safetyAlertRepositoryProvider.overrideWithValue(_FakeRepository(alerts)),
      ],
      child: const MaterialApp(
        home: Scaffold(body: LiveSafetyAlertSection(product: _product)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  // A product recalled after the last catalog release has no blocked status
  // yet; the live alert must still reach its product page (roadmap 1.2).
  testWidgets('a matching live recall shows its authored text', (tester) async {
    await _pump(tester, [_recall(disposition: 'block')]);

    expect(find.text('FDA recall: undeclared sildenafil'), findsOneWidget);
    expect(find.textContaining('undeclared drug ingredient'), findsOneWidget);
    expect(find.text('View source'), findsOneWidget);
  });

  testWidgets('an alert for another product shows nothing', (tester) async {
    await _pump(tester, [_recall(disposition: 'block', dsldIds: ['999'])]);

    expect(find.text('FDA recall: undeclared sildenafil'), findsNothing);
  });
}
