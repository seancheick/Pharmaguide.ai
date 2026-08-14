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
        scoreConfidence: 'moderate',
        qualityHighlights: const ['Third-party tested', 'No fillers'],
      );

      expect(capturedSubject, 'Magnesium Glycinate — Example Labs');
      expect(capturedText, contains('PharmaGuide quality: 88/100 · Excellent'));
      expect(capturedText, isNot(contains('Score confidence:')));
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

        await service.shareProduct(
          productName: 'Magnesium Glycinate',
          scoreConfidence: 'low',
        );

        expect(capturedText, isNotNull);
        expect(capturedText, isNot(contains('PharmaGuide quality:')));
        expect(capturedText, isNot(contains('Score confidence:')));
      },
    );

    test('shareProduct preserves a catalog block in fallback text', () async {
      String? capturedText;
      final service = ShareService(
        shareOverride: (text, {subject}) async => capturedText = text,
      );

      await service.shareProduct(
        productName: 'Blocked Product',
        isCatalogBlocked: true,
        qualityHighlights: const ['Third-Party Tested'],
      );

      expect(capturedText, contains('Blocked from quality scoring'));
      expect(capturedText, isNot(contains('Third-Party Tested')));
      expect(capturedText, isNot(contains('PharmaGuide quality:')));
    });

    test('shareProduct never includes a sender profile verdict', () async {
      String? capturedText;
      final service = ShareService(
        shareOverride: (text, {subject}) async => capturedText = text,
      );

      await service.shareProduct(
        productName: 'Daily Multi',
        qualityScore: 90,
        qualityTier: 'Elite',
      );

      expect(capturedText, isNot(contains('for your profile')));
      expect(capturedText, isNot(contains('No profile-specific concerns')));
    });

    test('shareProduct appends the minted link', () async {
      String? capturedText;
      final service = ShareService(
        shareOverride: (text, {subject}) async => capturedText = text,
        linkMinterOverride: (payload) async =>
            'https://pharmaguide.io/s/tc7ebgwy',
      );

      await service.shareProduct(
        dsldId: '1038',
        catalogVersion: '2026.08.13.204005',
        productName: 'Magnesium Glycinate',
        qualityScore: 92,
        qualityTier: 'excellent',
      );

      expect(capturedText, contains('https://pharmaguide.io/s/tc7ebgwy'));
      // The boundary sentence stays above the link so it is read before the
      // recipient taps through, not after.
      expect(
        capturedText!.indexOf('Personal fit depends on your profile'),
        lessThan(capturedText!.indexOf('https://pharmaguide.io/s/')),
      );
    });

    test('shareProduct still shares when the link cannot be minted', () async {
      String? capturedText;
      final service = ShareService(
        shareOverride: (text, {subject}) async => capturedText = text,
        linkMinterOverride: (payload) async => null,
      );

      await service.shareProduct(
        dsldId: '1038',
        catalogVersion: '2026.08.13.204005',
        productName: 'Magnesium Glycinate',
        qualityScore: 92,
        qualityTier: 'excellent',
      );

      expect(capturedText, contains('PharmaGuide quality: 92/100'));
      expect(capturedText, isNot(contains('http')));
    });

    test('shareProduct skips minting without catalog identity', () async {
      var minterCalled = false;
      final service = ShareService(
        shareOverride: (text, {subject}) async {},
        linkMinterOverride: (payload) async {
          minterCalled = true;
          return 'https://pharmaguide.io/s/aaaaaaaa';
        },
      );

      await service.shareProduct(productName: 'Magnesium Glycinate');

      expect(minterCalled, isFalse);

      await service.shareProduct(
        dsldId: '1038',
        productName: 'Magnesium Glycinate',
      );

      expect(minterCalled, isFalse);
    });

    test('minted payload carries only immutable catalog identity', () async {
      Map<String, Object?>? capturedPayload;
      final service = ShareService(
        shareOverride: (text, {subject}) async {},
        linkMinterOverride: (payload) async {
          capturedPayload = payload;
          return null;
        },
      );

      await service.shareProduct(
        dsldId: '1038',
        catalogVersion: '2026.08.13.204005',
        productName: 'Magnesium Glycinate',
        brandName: 'Example Labs',
        qualityScore: 92,
        qualityTier: 'excellent',
        scoreConfidence: 'low',
        qualityHighlights: const ['Third-Party Tested', 'Organic'],
      );

      // The website resolves every public field from the pipeline-published
      // release artifact. A new key added here fails closed in this test so
      // client-authored scores, names, statuses, or claims cannot return.
      expect(capturedPayload, {
        'dsldId': '1038',
        'catalogVersion': '2026.08.13.204005',
      });
    });

    test('shareProduct caps text highlights at three', () async {
      String? capturedText;
      final service = ShareService(
        shareOverride: (text, {subject}) async => capturedText = text,
      );

      await service.shareProduct(
        productName: 'Magnesium Glycinate',
        qualityHighlights: const ['One', 'Two', 'Three', 'Four'],
      );

      expect(capturedText, contains('- One'));
      expect(capturedText, contains('- Two'));
      expect(capturedText, contains('- Three'));
      expect(capturedText, isNot(contains('- Four')));
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

  group('ShareService.shareSupplementList', () {
    test('shares only allowlisted supplement fields', () async {
      String? capturedText;
      String? capturedSubject;
      final service = ShareService(
        shareOverride: (text, {subject}) async {
          capturedText = text;
          capturedSubject = subject;
        },
      );

      await service.shareSupplementList(const [
        SupplementShareItem(name: 'Magnesium Glycinate', brand: 'Example Labs'),
      ]);

      expect(capturedSubject, 'My supplements');
      expect(
        capturedText,
        'My supplements\n\n'
        '• Magnesium Glycinate — Example Labs\n\n'
        'Shared from PharmaGuide',
      );
      expect(capturedText, isNot(contains('medication')));
      expect(capturedText, isNot(contains('condition')));
      expect(capturedText, isNot(contains('safety score')));
    });

    test('does not invent schedule or brand values', () async {
      String? capturedText;
      final service = ShareService(
        shareOverride: (text, {subject}) async => capturedText = text,
      );

      await service.shareSupplementList(const [
        SupplementShareItem(name: 'Vitamin D'),
      ]);

      expect(capturedText, contains('• Vitamin D'));
      expect(capturedText, isNot(contains('null')));
    });
  });
}
