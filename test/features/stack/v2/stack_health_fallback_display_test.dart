// FIX 2 — the Stack Health card must never fall through to green
// "No data yet" when a safety subsystem errored. The tone/label decision
// is extracted into [stackHealthFallbackDisplay] so it can be unit-tested
// without pumping the (provider-heavy) card widget.

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/features/stack/widgets/stack_health_fallback_display.dart';

void main() {
  group('stackHealthFallbackDisplay', () {
    test('analyzing → safe tone + "Analyzing"', () {
      final d = stackHealthFallbackDisplay(palette: V2Palette.light, isAnalyzing: true, hasError: false);
      expect(d.tone, V2Palette.light.safe);
      expect(d.label, 'Analyzing');
    });

    test('errored + settled → neutral tone (NOT green) + hedge label', () {
      final d = stackHealthFallbackDisplay(palette: V2Palette.light, isAnalyzing: false, hasError: true);
      expect(
        d.tone,
        isNot(V2Palette.light.safe),
        reason: 'an errored safety check must never read as green/all-clear',
      );
      expect(d.tone, V2Palette.light.fgMuted);
      expect(d.label, "Couldn't check");
    });

    test('no error + settled + no verdict → safe tone + "No data yet"', () {
      final d = stackHealthFallbackDisplay(palette: V2Palette.light, isAnalyzing: false, hasError: false);
      expect(d.tone, V2Palette.light.safe);
      expect(d.label, 'No data yet');
    });

    test('analyzing wins over a concurrent error (transient loading)', () {
      final d = stackHealthFallbackDisplay(palette: V2Palette.light, isAnalyzing: true, hasError: true);
      expect(d.label, 'Analyzing');
      expect(d.tone, V2Palette.light.safe);
    });

    test('errored summary explicitly rejects an all-clear', () {
      final summary = stackHealthFallbackSummary(
        isAnalyzing: false,
        hasError: true,
      );
      expect(summary, contains('not an all-clear'));
    });
  });
}
