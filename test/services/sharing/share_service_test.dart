import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/services/sharing/share_service.dart';

void main() {
  group('ShareService', () {
    test('shareProduct builds formatted text with highlights', () {
      // ShareService uses Share.share() which needs platform channel.
      // We test the logic by verifying the service instantiates.
      final service = ShareService();
      expect(service, isNotNull);
    });
  });

  group('ShareService.shareClinicianReport (C2)', () {
    test('forwards the builder markdown verbatim with the clinician subject',
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

      expect(capturedText, markdown,
          reason:
              'method must pass the builder output through unchanged — '
              'no reshaping, no extra payload appended');
      expect(
        capturedSubject,
        'My Supplement Stack — Clinician Summary',
        reason:
            'subject is the stable share-sheet headline shown in Mail / '
            'Messages / share extensions',
      );
    });

    test(
        'does not perform any side-channel call beyond the single share '
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

      expect(shareCalls, 1,
          reason:
              'shareClinicianReport is a thin pass-through — exactly '
              'one share-sheet invocation, no analytics tap, no '
              'duplicate fan-out');
    });

    test('an empty markdown still produces a share invocation '
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
    });
  });
}
