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
        linkMinterOverride: (payload) async => 'https://pharmaguide.io/s/tc7ebgwy',
      );

      await service.shareProduct(
        dsldId: '1038',
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
        productName: 'Magnesium Glycinate',
        qualityScore: 92,
        qualityTier: 'excellent',
      );

      expect(capturedText, contains('PharmaGuide quality: 92/100'));
      expect(capturedText, isNot(contains('http')));
    });

    test('shareProduct skips minting entirely without a dsldId', () async {
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
    });

    test('minted payload carries no profile or personal data', () async {
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
        productName: 'Magnesium Glycinate',
        brandName: 'Example Labs',
        qualityScore: 92,
        qualityTier: 'excellent',
        scoreConfidence: 'low',
        qualityHighlights: const ['Third-Party Tested', 'Organic'],
      );

      // Allowlist assertion, not a denylist: anything not named here must not
      // be leaving the device, and a new key added upstream fails this test
      // rather than silently shipping.
      expect(
        capturedPayload!.keys.toSet(),
        {
          'dsldId',
          'productName',
          'brandName',
          'qualityScore',
          'qualityTier',
          'confidence',
          'highlights',
        },
      );
      expect(capturedPayload!['qualityScore'], 92);
      expect(capturedPayload!['confidence'], 'Limited');
      expect(capturedPayload!['highlights'], ['Third-Party Tested', 'Organic']);
    });

    test('minted payload never sends a tier without its score', () async {
      Map<String, Object?>? capturedPayload;
      final service = ShareService(
        shareOverride: (text, {subject}) async {},
        linkMinterOverride: (payload) async {
          capturedPayload = payload;
          return null;
        },
      );

      // A blocked product: the call site nulls the score but a stale tier
      // string could still arrive. The pair must break together, or the
      // website would be asked to render a verdict with nothing behind it.
      await service.shareProduct(
        dsldId: '9',
        productName: 'Blocked Thing',
        qualityScore: null,
        qualityTier: 'excellent',
      );

      expect(capturedPayload!['qualityScore'], isNull);
      expect(capturedPayload!['qualityTier'], isNull);
    });

    test('minted payload caps highlights at three', () async {
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
        productName: 'Magnesium Glycinate',
        qualityHighlights: const [
          'Third-Party Tested',
          'Organic',
          'Non-GMO',
          'Vegan',
        ],
      );

      expect(capturedPayload!['highlights'], [
        'Third-Party Tested',
        'Organic',
        'Non-GMO',
      ]);
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
