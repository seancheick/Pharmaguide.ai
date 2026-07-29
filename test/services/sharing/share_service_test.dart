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

  group('ShareService.shareClinicianReportPdf', () {
    test('forwards PDF bytes with the clinician filename', () async {
      List<int>? capturedBytes;
      String? capturedFilename;
      final service = ShareService(
        pdfShareOverride: (bytes, {required filename}) async {
          capturedBytes = bytes;
          capturedFilename = filename;
          return true;
        },
      );

      final bytes = [37, 80, 68, 70, 45];
      final shared = await service.shareClinicianReportPdf(bytes);

      expect(capturedBytes, bytes);
      expect(capturedFilename, 'pharmaguide-clinician-report.pdf');
      expect(shared, isTrue);
    });

    test('preserves a cancelled share-sheet result', () async {
      final service = ShareService(
        pdfShareOverride: (bytes, {required filename}) async => false,
      );

      final shared = await service.shareClinicianReportPdf([37, 80, 68, 70]);

      expect(shared, isFalse);
    });
  });
}
