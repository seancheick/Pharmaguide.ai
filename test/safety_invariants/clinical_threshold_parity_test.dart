// Clinical-threshold parity gate: the B7 UL-exceedance threshold.
//
// PipelineUlVerdict.exceedsUl (lib/services/stack/stack_nutrient_aggregator.dart)
// falls back to `pctUl > 100.0` to judge a nutrient "over UL" when the pipeline
// emitted a percentage but no definitive `over_ul` bool. That 100 mirrors the
// pipeline's confirmed-exceedance threshold (dose_safety_ceiling.
// exceeds_above_pct in quality_score.json, Dose V4.1).
//
// This test pins the value; the pipeline repo's test_clinical_threshold_parity.py
// pins the identical value. The two identical pins are the parity contract — the
// app must not silently diverge from the pipeline's clinical UL policy.
//
// (Only this single value is locked. The app's 50/80/100/200 intake/UL tier
// bands in stack_ul_checker.dart are app-owned UI classification with no pipeline
// equivalent — the pipeline owns the UL verdict via `over_ul`, which the app
// already defers to — so they are intentionally NOT pinned here.)

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // MUST equal PINNED_B7_UL_PCT_THRESHOLD in the pipeline repo's
  // scripts/tests/test_clinical_threshold_parity.py.
  const pinnedB7UlPctThreshold = 100.0;

  test('app B7 UL-exceedance fallback matches the pinned pipeline threshold', () {
    final src = File(
      'lib/services/stack/stack_nutrient_aggregator.dart',
    ).readAsStringSync();

    // exceedsUl fallback: `return (pctUl ?? 0) > <threshold>;`
    final match = RegExp(
      r'pctUl\s*\?\?\s*0\)\s*>\s*(\d+(?:\.\d+)?)',
    ).firstMatch(src);

    expect(
      match,
      isNotNull,
      reason:
          'Could not locate the UL-exceedance fallback (`pctUl ?? 0) > …`) '
          'in stack_nutrient_aggregator.dart. If the getter was refactored, '
          'update this parity test to match the new shape.',
    );

    final appThreshold = double.parse(match!.group(1)!);
    expect(
      appThreshold,
      pinnedB7UlPctThreshold,
      reason:
          'App B7 fallback ($appThreshold) drifted from the pinned pipeline '
          'b7_ul_pct_threshold ($pinnedB7UlPctThreshold). Update in lockstep '
          'with scripts/tests/test_clinical_threshold_parity.py.',
    );
  });
}
