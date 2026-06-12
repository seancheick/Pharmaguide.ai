import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/app.dart';

void main() {
  group('normalizePharmaGuideDeepLink', () {
    test('turns custom-scheme product links into router paths', () {
      final out = normalizePharmaGuideDeepLink(
        Uri.parse('pharmaguide://product/1038?section=ingredients'),
      );

      expect(out, '/product/1038?section=ingredients');
    });

    test('handles triple-slash app paths', () {
      final out = normalizePharmaGuideDeepLink(
        Uri.parse('pharmaguide:///quick-check'),
      );

      expect(out, '/quick-check');
    });

    test('keeps auth callback routable while Supabase finishes exchange', () {
      final out = normalizePharmaGuideDeepLink(
        Uri.parse('pharmaguide://auth/callback?code=abc'),
      );

      expect(out, '/auth/callback?code=abc');
    });

    test('ignores non-PharmaGuide links', () {
      final out = normalizePharmaGuideDeepLink(
        Uri.parse('https://example.com/product/1038'),
      );

      expect(out, isNull);
    });
  });

  group('compareSelfRedirect', () {
    test('/compare/X/X redirects to /product/X', () {
      expect(compareSelfRedirect('12345', '12345'), '/product/12345');
    });

    test('distinct ids do not redirect', () {
      expect(compareSelfRedirect('12345', '67890'), isNull);
    });

    test('empty ids do not redirect (route 404s normally)', () {
      expect(compareSelfRedirect('', ''), isNull);
    });
  });
}
