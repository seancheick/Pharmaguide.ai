import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/scanner/missing_product_submission_sheet.dart';
import 'package:pharmaguide/services/product_submission_service.dart';

const _userId = '3f276b64-0836-4bea-9453-1c8db4d1f8dd';

void main() {
  testWidgets('explains private evidence collection without free text', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MissingProductSubmissionSheet(
            upc: '050428381397',
            service: ProductSubmissionService(
              backend: _Backend(authenticatedUserId: _userId),
            ),
            pickPhoto: (_) async => null,
          ),
        ),
      ),
    );

    expect(find.text('Help add this product'), findsOneWidget);
    expect(find.text('UPC 050428381397'), findsOneWidget);
    expect(find.text('Front label'), findsOneWidget);
    expect(find.text('Supplement Facts'), findsOneWidget);
    expect(find.text('Other Ingredients'), findsOneWidget);
    expect(
      find.textContaining('Do not include pharmacy labels'),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('missing-product-consent')),
      300,
    );
    expect(
      find.textContaining('I consent to send my account identifier'),
      findsOneWidget,
    );
    expect(find.byType(TextField), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('missing-product-submit')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('requires exact evidence then submits through the one service', (
    tester,
  ) async {
    final backend = _Backend(authenticatedUserId: _userId);
    final picked = <ProductSubmissionPhotoSlot>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MissingProductSubmissionSheet(
            upc: '050428381397',
            service: ProductSubmissionService(backend: backend),
            submissionIdFactory: () => '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a11',
            pickPhoto: (slot) async {
              picked.add(slot);
              return ProductSubmissionPhoto(
                slot: slot,
                bytes: Uint8List.fromList([1, 2, 3]),
                contentType: 'image/jpeg',
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Front label'));
    await tester.pump();
    await tester.tap(find.text('Supplement Facts'));
    await tester.pump();

    expect(picked, [
      ProductSubmissionPhotoSlot.front,
      ProductSubmissionPhotoSlot.supplementFacts,
    ]);
    await tester.scrollUntilVisible(
      find.byKey(const Key('missing-product-submit')),
      300,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('missing-product-submit')))
          .onPressed,
      isNull,
      reason: 'Other Ingredients still needs a photo or explicit absence.',
    );

    await tester.tap(find.text('No Other Ingredients panel on this label'));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byKey(const Key('missing-product-consent')),
      300,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('missing-product-submit')))
          .onPressed,
      isNull,
      reason: 'Private processing requires explicit user consent.',
    );

    await tester.tap(
      find.textContaining('I consent to send my account identifier'),
    );
    await tester.pump();
    final submit = tester.widget<FilledButton>(
      find.byKey(const Key('missing-product-submit')),
    );
    expect(submit.onPressed, isNotNull);

    await tester.tap(find.text('Submit'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(backend.persistedKind, 'missing_product');
    expect(find.text('Submitted for review'), findsOneWidget);
  });

  testWidgets('a captured Other Ingredients photo clears the absence choice', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MissingProductSubmissionSheet(
            upc: '050428381397',
            service: ProductSubmissionService(
              backend: _Backend(authenticatedUserId: _userId),
            ),
            pickPhoto: (slot) async => ProductSubmissionPhoto(
              slot: slot,
              bytes: Uint8List.fromList([1, 2, 3]),
              contentType: 'image/jpeg',
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('No Other Ingredients panel on this label'));
    await tester.pump();
    final absent = find.byKey(
      const Key('missing-product-other-ingredients-absent'),
    );
    expect(tester.widget<CheckboxListTile>(absent).value, isTrue);

    await tester.tap(find.text('Other Ingredients'));
    await tester.pump();

    expect(tester.widget<CheckboxListTile>(absent).value, isFalse);
    expect(find.text('Photo added'), findsNWidgets(1));
  });

  testWidgets('retry reuses one immutable submission id', (tester) async {
    final backend = _Backend(
      authenticatedUserId: _userId,
      persistFailuresRemaining: 1,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MissingProductSubmissionSheet(
            upc: '050428381397',
            service: ProductSubmissionService(backend: backend),
            submissionIdFactory: () => '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a11',
            pickPhoto: (slot) async => ProductSubmissionPhoto(
              slot: slot,
              bytes: Uint8List.fromList([1, 2, 3]),
              contentType: 'image/jpeg',
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Front label'));
    await tester.pump();
    await tester.tap(find.text('Supplement Facts'));
    await tester.pump();
    await tester.tap(find.text('No Other Ingredients panel on this label'));
    await tester.scrollUntilVisible(
      find.byKey(const Key('missing-product-consent')),
      300,
    );
    await tester.tap(
      find.textContaining('I consent to send my account identifier'),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('missing-product-submit')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Could not submit this product'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('missing-product-submit')));
    await tester.pumpAndSettle();

    expect(backend.persistedSubmissionIds, [
      '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a11',
      '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a11',
    ]);
    expect(find.text('Submitted for review'), findsOneWidget);
  });
}

class _Backend implements ProductSubmissionBackend {
  _Backend({
    required this.authenticatedUserId,
    this.persistFailuresRemaining = 0,
  });

  @override
  final String? authenticatedUserId;
  String? persistedKind;
  int persistFailuresRemaining;
  final List<String> persistedSubmissionIds = [];
  final Set<String> uploaded = {};
  List<Map<String, Object?>> manifest = const [];

  @override
  Future<void> persistSubmission({
    required String functionName,
    required Map<String, Object?> payload,
  }) async {
    persistedSubmissionIds.add(payload['p_submission_id']! as String);
    if (persistFailuresRemaining > 0) {
      persistFailuresRemaining -= 1;
      throw StateError('ambiguous persist failure');
    }
    persistedKind = payload['p_kind'] as String?;
    manifest = payload['p_photos']! as List<Map<String, Object?>>;
  }

  @override
  Future<void> uploadPhoto({
    required String bucket,
    required String objectPath,
    required Uint8List bytes,
    required String contentType,
  }) async {
    uploaded.add(objectPath);
  }

  @override
  Future<bool> finalizeSubmission({
    required String functionName,
    required String submissionId,
  }) async {
    final expected = manifest.map(
      (photo) => '$_userId/$submissionId/${photo['photo_slot'] as String}',
    );
    return expected.every(uploaded.contains);
  }

  @override
  Future<List<Map<String, Object?>>> listOwnSubmissions({
    required String table,
  }) async {
    return const [];
  }
}
