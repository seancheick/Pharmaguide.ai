import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/services/pending_submission_intent.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('consume returns a typed missing-product intent exactly once', () async {
    await PendingSubmissionIntent.saveMissingProduct('0 50428 38139 7');

    final intent = await PendingSubmissionIntent.consume();
    expect(intent?.kind, PendingSubmissionIntentKind.missingProduct);
    expect(intent?.identifier, '050428381397');
    expect(
      await PendingSubmissionIntent.consume(),
      isNull,
      reason: 'A consumed intent must never fire twice.',
    );
  });

  test('expired intents are dropped, not resurrected', () async {
    final saved = DateTime.utc(2026, 8, 24, 12);
    await PendingSubmissionIntent.saveMissingProduct(
      '050428381397',
      now: () => saved,
    );

    final justInside = saved.add(
      PendingSubmissionIntent.ttl - const Duration(seconds: 1),
    );
    final outside = saved.add(
      PendingSubmissionIntent.ttl + const Duration(seconds: 1),
    );

    // Past the TTL: dropped AND cleared.
    SharedPreferences.setMockInitialValues({});
    await PendingSubmissionIntent.saveMissingProduct(
      '050428381397',
      now: () => saved,
    );
    expect(await PendingSubmissionIntent.consume(now: () => outside), isNull);
    expect(await PendingSubmissionIntent.consume(), isNull);

    // Inside the TTL: consumed normally.
    SharedPreferences.setMockInitialValues({});
    await PendingSubmissionIntent.saveMissingProduct(
      '050428381397',
      now: () => saved,
    );
    final intent = await PendingSubmissionIntent.consume(now: () => justInside);
    expect(intent?.identifier, '050428381397');
  });

  test('clock skew (created in the future) fails closed', () async {
    final saved = DateTime.utc(2026, 8, 24, 12);
    await PendingSubmissionIntent.saveMissingProduct(
      '050428381397',
      now: () => saved,
    );

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
    await PendingSubmissionIntent.saveMissingProduct('no digits at all');

    expect(await PendingSubmissionIntent.consume(), isNull);
  });

  test('label mismatch persists its kind and DSLD identity', () async {
    await PendingSubmissionIntent.saveLabelMismatch(' 999 ');

    final intent = await PendingSubmissionIntent.consume();
    expect(intent?.kind, PendingSubmissionIntentKind.labelMismatch);
    expect(intent?.identifier, '999');
  });

  test('legacy payload without kind defaults to missing product', () async {
    SharedPreferences.setMockInitialValues({
      PendingSubmissionIntent.storageKey:
          '{"upc":"050428381397","created_at":"2026-08-24T12:00:00.000Z"}',
    });

    final intent = await PendingSubmissionIntent.consume(
      now: () => DateTime.utc(2026, 8, 24, 12, 30),
    );
    expect(intent?.kind, PendingSubmissionIntentKind.missingProduct);
    expect(intent?.identifier, '050428381397');
  });

  test('routes each kind once and drops a missing catalog record', () async {
    final openedMissing = <String>[];
    final lookedUpMismatch = <String>[];
    final openedMismatch = <String>[];

    await routePendingSubmissionIntent<String>(
      const PendingSubmissionIntentValue.missingProduct('050428381397'),
      openMissingProduct: openedMissing.add,
      resolveLabelMismatch: (id) async {
        lookedUpMismatch.add(id);
        return 'product:$id';
      },
      openLabelMismatch: openedMismatch.add,
    );
    await routePendingSubmissionIntent<String>(
      const PendingSubmissionIntentValue.labelMismatch('999'),
      openMissingProduct: openedMissing.add,
      resolveLabelMismatch: (id) async {
        lookedUpMismatch.add(id);
        return 'product:$id';
      },
      openLabelMismatch: openedMismatch.add,
    );
    await routePendingSubmissionIntent<String>(
      const PendingSubmissionIntentValue.labelMismatch('404'),
      openMissingProduct: openedMissing.add,
      resolveLabelMismatch: (id) async {
        lookedUpMismatch.add(id);
        return null;
      },
      openLabelMismatch: openedMismatch.add,
    );

    expect(openedMissing, ['050428381397']);
    expect(lookedUpMismatch, ['999', '404']);
    expect(openedMismatch, ['product:999']);
  });
}
