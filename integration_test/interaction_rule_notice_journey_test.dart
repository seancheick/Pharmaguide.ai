// The fictional reconnect journey on a simulator, with its screenshots as
// evidence. Serves the pipeline's fake feed from memory and uses in-memory
// databases, so nothing is published and no account data is read:
//
// VERIFY_EVIDENCE_DIR=<new folder> flutter drive \
//   --driver test_driver/native_catalog_driver.dart \
//   --target integration_test/interaction_rule_notice_journey_test.dart \
//   --dart-define=INTERACTION_FEED_BASE64="$(base64 < test/fixtures/safety_alerts/interaction_rule_feed.json)" \
//   -d <device>

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/features/safety_alerts/interaction_rule_journey.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a new contraindication appears when the connection returns', (
    tester,
  ) async {
    final feedBytes = base64.decode(
      const String.fromEnvironment('INTERACTION_FEED_BASE64'),
    );
    expect(
      'sha256:${sha256.convert(feedBytes)}',
      'sha256:7c17891cabd3e4fa495c19bd2d42765e229ef4bb46dd3176ce11d84e006b0219',
    );

    await binding.convertFlutterSurfaceToImage();
    await runInteractionRuleJourney(
      tester,
      feedBytes: feedBytes,
      settle: () async {
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 300));
        }
      },
      onStep: (step) async {
        if (step == 'after_reconnect') {
          await tester.ensureVisible(find.byKey(noticeKey));
          await tester.pump(const Duration(milliseconds: 500));
        }
        await binding.takeScreenshot(step);
      },
    );
  });
}
