// v1.5.0 canonical ingredient contract — Flutter consumption.
//
// Six tests pinning the new contract reads so a future refactor can't
// silently regress what Flutter renders. Mirrors the pipeline-side
// contract documented at scripts/FINAL_EXPORT_SCHEMA_V1.md (v1.5.0).

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/product_detail/widgets/inactive_color.dart';

void main() {
  // -- Inactive severity_status routing -------------------------------------

  group('inactiveColorRank — v1.5.0 severity_status', () {
    test('critical → red (always show in RBU)', () {
      expect(
        inactiveColorRank({'severity_status': 'critical'}),
        InactiveTone.red,
      );
    });

    test('informational → orange (notable but not hazardous)', () {
      expect(
        inactiveColorRank({'severity_status': 'informational'}),
        InactiveTone.orange,
      );
    });

    test('suppress → yellow (silicon dioxide, MCC — Tradeoffs only)', () {
      expect(
        inactiveColorRank({
          'severity_status': 'suppress',
          'is_safety_concern': false,
        }),
        InactiveTone.yellow,
      );
    });

    test('n/a → green (non-additive or non-harmful)', () {
      expect(
        inactiveColorRank({'severity_status': 'n/a'}),
        InactiveTone.green,
      );
    });

    test('falls back to harmful_severity on cached blobs without severity_status', () {
      // severity_level retired; harmful_severity carries the same enum.
      expect(
        inactiveColorRank({'harmful_severity': 'high'}),
        InactiveTone.red,
      );
      expect(
        inactiveColorRank({'harmful_severity': 'low'}),
        InactiveTone.yellow,
      );
    });
  });
}
