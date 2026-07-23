import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/services/sharing/share_service.dart';

void main() {
  group('ShareService', () {
    test('shareProduct builds a product-quality summary', () async {
      String? capturedText;
      String? capturedSubject;
      final service = ShareService(
        shareOverride: (text, {subject}) async {
          capturedText = text;
          capturedSubject = subject;
        },
      );

      await service.shareProduct(
        productName: 'Magnesium Glycinate',
        brandName: 'Example Labs',
        qualityScore: 88.4,
        qualityTier: 'Excellent',
        qualityHighlights: const ['Third-party tested', 'No fillers'],
      );

      expect(capturedSubject, 'Magnesium Glycinate — Example Labs');
      expect(capturedText, contains('PharmaGuide quality: 88/100 · Excellent'));
      expect(capturedText, contains('- Third-party tested'));
      expect(capturedText, contains('- No fillers'));
      expect(capturedText, contains('Personal fit depends on your profile'));
    });

    test(
      'shareProduct omits missing score without inventing quality',
      () async {
        String? capturedText;
        final service = ShareService(
          shareOverride: (text, {subject}) async => capturedText = text,
        );

        await service.shareProduct(productName: 'Magnesium Glycinate');

        expect(capturedText, isNotNull);
        expect(capturedText, isNot(contains('PharmaGuide quality:')));
      },
    );

    test('shareProduct never includes a sender profile verdict', () async {
      String? capturedText;
      final service = ShareService(
        shareOverride: (text, {subject}) async => capturedText = text,
      );

      await service.shareProduct(
        productName: 'Daily Multi',
        qualityScore: 90,
        qualityTier: 'Exceptional',
      );

      expect(capturedText, isNot(contains('for your profile')));
      expect(capturedText, isNot(contains('No profile-specific concerns')));
    });
  });

  group('ShareService.shareClinicianReport (C2)', () {
    test(
      'forwards the builder markdown verbatim with the clinician subject',
      () async {
        String? capturedText;
        String? capturedSubject;
        final service = ShareService(
          shareOverride: (text, {subject}) async {
            capturedText = text;
            capturedSubject = subject;
          },
        );

        const markdown =
            '# My Supplement Stack — Clinician Summary\n\n'
            '**Generated on device · 2026-04-29**\n';
        await service.shareClinicianReport(markdown);

        expect(
          capturedText,
          markdown,
          reason:
              'method must pass the builder output through unchanged — '
              'no reshaping, no extra payload appended',
        );
        expect(
          capturedSubject,
          'My Supplement Stack — Clinician Summary',
          reason:
              'subject is the stable share-sheet headline shown in Mail / '
              'Messages / share extensions',
        );
      },
    );

    test('does not perform any side-channel call beyond the single share '
        'invocation', () async {
      // The whole guarantee in the spec: "no additional payload (no
      // analytics ping with content)". We assert that by counting how
      // many times the share callback fires for one shareClinicianReport
      // call — exactly once — and that no other observable side effect
      // happens via the fake.
      var shareCalls = 0;
      final service = ShareService(
        shareOverride: (text, {subject}) async {
          shareCalls++;
        },
      );

      await service.shareClinicianReport('# anything\n');

      expect(
        shareCalls,
        1,
        reason:
            'shareClinicianReport is a thin pass-through — exactly '
            'one share-sheet invocation, no analytics tap, no '
            'duplicate fan-out',
      );
    });

    test(
      'an empty markdown still produces a share invocation '
      '(builder may legitimately produce an empty body for a tiny stack)',
      () async {
        String? capturedText;
        final service = ShareService(
          shareOverride: (text, {subject}) async {
            capturedText = text;
          },
        );

        await service.shareClinicianReport('');

        expect(capturedText, '');
      },
    );
  });

  group('ShareService.shareClinicianReportPdf', () {
    test('forwards PDF bytes with the clinician filename', () async {
      List<int>? capturedBytes;
      String? capturedFilename;
      final service = ShareService(
        pdfShareOverride: (bytes, {required filename}) async {
          capturedBytes = bytes;
          capturedFilename = filename;
        },
      );

      final bytes = [37, 80, 68, 70, 45];
      await service.shareClinicianReportPdf(bytes);

      expect(capturedBytes, bytes);
      expect(capturedFilename, 'pharmaguide-clinician-report.pdf');
    });
  });
}
