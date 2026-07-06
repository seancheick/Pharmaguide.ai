// Regression: selenium / thyroid_disorder must never render as a positive
// Personal Fit benefit. The pipeline now owns dose-floor evaluation; this app
// test locks the consumer-facing benefit behavior after retiring the local
// condition-threshold table.

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/personal_fit_helpers.dart';
import 'package:pharmaguide/services/warnings/interaction_warning.dart';

InteractionWarning _w({
  required List<String> conditionIds,
  String? ingredientName,
  Severity severity = Severity.monitor,
}) {
  return InteractionWarning(
    severity: severity,
    evidenceLevel: EvidenceLevel.theoretical,
    title: 'Test warning',
    mechanism: 'Test mechanism',
    management: 'Test management',
    conditionIds: conditionIds,
    ingredientName: ingredientName,
  );
}

void main() {
  group(
    'generatePositiveProfileBulletsFromWarnings — selenium is NOT a benefit',
    () {
      test('Selenium + thyroid_disorder emits NO positive bullet', () {
        final bullets = generatePositiveProfileBulletsFromWarnings(
          warnings: [
            _w(conditionIds: ['thyroid_disorder'], ingredientName: 'Selenium'),
          ],
          userConditionIds: const ['thyroid_disorder'],
        );
        expect(
          bullets,
          isEmpty,
          reason:
              'a UL-gated risk must not surface as "supports your thyroid '
              'health" — that encourages a toxic-dose product',
        );
      });
    },
  );
}
