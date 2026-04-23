// FLTR-16 — Stack safety override.
//
// [StackActions.addProduct] must refuse to add a product whose verdict
// is BLOCKED or UNSAFE, throwing [StackAddBlockedException]. This is
// the defense-in-depth domain guard that protects any caller bypassing
// the UI short-circuit (deep links, bulk import, automation).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/features/stack/providers/active_stack_provider.dart';

/// Minimal product fixture for guard assertions. We never reach the
/// Drift code path because the guard throws first, so the other
/// columns are unused.
ProductsCoreData _product({
  required String dsldId,
  required String verdict,
}) {
  return ProductsCoreData(
    dsldId: dsldId,
    productName: 'Test Product',
    productStatus: 'active',
    verdict: verdict,
    mappedCoverage: 0.0,
    exportVersion: 'test',
    exportedAt: '2026-04-23T00:00:00Z',
  );
}

void main() {
  group('StackActions.addProduct FLTR-16 verdict guard', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() => container.dispose());

    test('rejects BLOCKED verdict with StackAddBlockedException',
        () async {
      final actions = container.read(stackActionsProvider);
      final product = _product(dsldId: 'DS_BLOCKED', verdict: 'BLOCKED');

      expect(
        () => actions.addProduct(product),
        throwsA(
          isA<StackAddBlockedException>()
              .having((e) => e.dsldId, 'dsldId', 'DS_BLOCKED')
              .having((e) => e.verdict, 'verdict', 'BLOCKED'),
        ),
      );
    });

    test('rejects UNSAFE verdict with StackAddBlockedException',
        () async {
      final actions = container.read(stackActionsProvider);
      final product = _product(dsldId: 'DS_UNSAFE', verdict: 'UNSAFE');

      expect(
        () => actions.addProduct(product),
        throwsA(isA<StackAddBlockedException>()),
      );
    });

    test('lowercase blocked is normalized and still rejected', () async {
      final actions = container.read(stackActionsProvider);
      final product = _product(dsldId: 'DS_LC', verdict: 'blocked');

      expect(
        () => actions.addProduct(product),
        throwsA(isA<StackAddBlockedException>()),
      );
    });

    test('non-blocked verdicts pass the guard (reach Drift layer)',
        () async {
      final actions = container.read(stackActionsProvider);
      final product = _product(dsldId: 'DS_OK', verdict: 'RECOMMENDED');

      // We don't override userDatabaseProvider, so the call proceeds
      // past the guard and fails inside Drift. Any thrown type OTHER
      // than StackAddBlockedException confirms the guard let it
      // through — which is the invariant we want to prove.
      try {
        await actions.addProduct(product);
      } on StackAddBlockedException {
        fail('Non-blocked verdict must not trigger the safety guard');
      } on Object {
        // Expected — downstream database failure is fine for this
        // assertion; we only care that the verdict guard did not fire.
      }
    });

    test('StackAddBlockedException toString includes both fields', () {
      const e = StackAddBlockedException(
        dsldId: 'DS_X',
        verdict: 'BLOCKED',
      );
      expect(e.toString(), contains('DS_X'));
      expect(e.toString(), contains('BLOCKED'));
    });
  });
}
