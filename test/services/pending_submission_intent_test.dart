import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/services/pending_submission_intent.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('consume returns the barcode exactly once', () async {
    await PendingSubmissionIntent.save('0 50428 38139 7');

    expect(await PendingSubmissionIntent.consume(), '050428381397');
    expect(
      await PendingSubmissionIntent.consume(),
      isNull,
      reason: 'A consumed intent must never fire twice.',
    );
  });

  test('expired intents are dropped, not resurrected', () async {
    final saved = DateTime.utc(2026, 8, 24, 12);
    await PendingSubmissionIntent.save('050428381397', now: () => saved);

    final justInside = saved.add(
      PendingSubmissionIntent.ttl - const Duration(seconds: 1),
    );
    final outside = saved.add(
      PendingSubmissionIntent.ttl + const Duration(seconds: 1),
    );

    // Past the TTL: dropped AND cleared.
    SharedPreferences.setMockInitialValues({});
    await PendingSubmissionIntent.save('050428381397', now: () => saved);
    expect(
      await PendingSubmissionIntent.consume(now: () => outside),
      isNull,
    );
    expect(await PendingSubmissionIntent.consume(), isNull);

    // Inside the TTL: consumed normally.
    SharedPreferences.setMockInitialValues({});
    await PendingSubmissionIntent.save('050428381397', now: () => saved);
    expect(
      await PendingSubmissionIntent.consume(now: () => justInside),
      '050428381397',
    );
  });

  test('clock skew (created in the future) fails closed', () async {
    final saved = DateTime.utc(2026, 8, 24, 12);
    await PendingSubmissionIntent.save('050428381397', now: () => saved);

    expect(
      await PendingSubmissionIntent.consume(
        now: () => saved.subtract(const Duration(minutes: 1)),
      ),
      isNull,
    );
  });

  test('malformed stored payloads are cleared and ignored', () async {
    SharedPreferences.setMockInitialValues({
      PendingSubmissionIntent.storageKey: 'not json',
    });

    expect(await PendingSubmissionIntent.consume(), isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(PendingSubmissionIntent.storageKey), isNull);
  });

  test('non-numeric input never persists an intent', () async {
    await PendingSubmissionIntent.save('no digits at all');

    expect(await PendingSubmissionIntent.consume(), isNull);
  });
}
