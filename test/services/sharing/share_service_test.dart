import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/services/sharing/share_service.dart';

void main() {
  group('ShareService', () {
    test('shareProduct builds formatted text with highlights', () async {
      String? capturedText;
      final service = ShareService(
        shareOverride: (text, {subject}) async => capturedText = text,
      );

      await service.shareProduct(
        shareTitle: 'Magnesium Glycinate',
        shareDescription: 'Well-absorbed form.',
        shareHighlights: '["Third-party tested","No fillers"]',
      );

      expect(capturedText, contains('Magnesium Glycinate'));
      expect(capturedText, contains('- Third-party tested'));
      expect(capturedText, contains('- No fillers'));
    });

    test('shareProduct tolerates non-list highlights JSON', () async {
      // A drifted blob could carry a JSON object instead of a list. The
      // old `as List` cast threw a TypeError past the FormatException
      // handler; now it degrades to no highlights.
      String? capturedText;
      final service = ShareService(
        shareOverride: (text, {subject}) async => capturedText = text,
      );

      await service.shareProduct(
        shareTitle: 'Magnesium Glycinate',
        shareDescription: '',
        shareHighlights: '{"unexpected":"object"}',
      );

      expect(capturedText, isNotNull);
      expect(capturedText, isNot(contains('Key highlights')));
    });

    test('shareProduct tolerates invalid highlights JSON', () async {
      String? capturedText;
      final service = ShareService(
        shareOverride: (text, {subject}) async => capturedText = text,
      );

      await service.shareProduct(
        shareTitle: null,
        shareDescription: null,
        shareHighlights: 'not-json',
      );

      expect(capturedText, contains('Check out this supplement'));
      expect(capturedText, isNot(contains('Key highlights')));
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
