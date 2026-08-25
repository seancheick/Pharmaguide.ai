import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/scanner/missing_product_submission_sheet.dart';
import 'package:pharmaguide/services/photo_quality_gate.dart';
import 'package:pharmaguide/services/product_submission_service.dart';

const _userId = '3f276b64-0836-4bea-9453-1c8db4d1f8dd';
const _submissionId = '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a11';
const _upc = '050428381397';

const _okQuality = PhotoQualityResult(
  verdict: PhotoQualityVerdict.ok,
  shortSide: 1200,
  blurScore: 500,
);

var _photoCounter = 0;

ProductSubmissionPhoto _photo(Set<ProductSubmissionEvidenceCategory> tags) {
  _photoCounter += 1;
  final suffix = _photoCounter.toRadixString(16).padLeft(2, '0');
  return ProductSubmissionPhoto(
    photoId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa$suffix',
    categories: tags,
    bytes: Uint8List.fromList([1, 2, 3, _photoCounter]),
    contentType: 'image/jpeg',
  );
}

Widget _harness({
  required _Backend backend,
  PickMissingProductPhoto? pickPhoto,
  EvaluatePhotoQuality? qualityGate,
}) {
  return MaterialApp(
    home: Scaffold(
      body: MissingProductSubmissionSheet(
        upc: _upc,
        service: ProductSubmissionService(backend: backend),
        submissionIdFactory: () => _submissionId,
        qualityGate: qualityGate ?? (_) async => _okQuality,
        pickPhoto: pickPhoto ?? (tags) async => _photo(tags),
      ),
    ),
  );
}

/// Drives the guided flow through the three required capture steps with the
/// facts photo dual-tagged (no separate ingredient panel), landing on the
/// review step.
Future<void> _captureRequiredEvidence(WidgetTester tester) async {
  // Front step.
  await tester.tap(find.byKey(const Key('missing-product-add-front_identity')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('missing-product-next')));
  await tester.pumpAndSettle();

  // Facts step: declare the combined panel FIRST so the capture is tagged
  // with both categories and the ingredients step disappears.
  await tester.tap(
    find.byKey(const Key('missing-product-facts-carries-ingredients')),
  );
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(const Key('missing-product-add-supplement_facts')),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('missing-product-next')));
  await tester.pumpAndSettle();

  // Extras step — skip straight to review.
  await tester.tap(find.byKey(const Key('missing-product-next')));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => _photoCounter = 0);

  testWidgets('guides required evidence before allowing review', (
    tester,
  ) async {
    final backend = _Backend(authenticatedUserId: _userId);
    await tester.pumpWidget(_harness(backend: backend));

    // Cannot advance past the front step without a photo.
    await tester.tap(find.byKey(const Key('missing-product-next')));
    await tester.pump();
    expect(
      find.text('Add at least one photo of the front label.'),
      findsOneWidget,
    );

    await _captureRequiredEvidence(tester);

    expect(find.text('Review & submit'), findsOneWidget);
    expect(find.byKey(const Key('missing-product-consent')), findsOneWidget);
    expect(backend.persistedSubmissionIds, isEmpty);
  });

  testWidgets('submits the dual-tagged manifest through the one service', (
    tester,
  ) async {
    final backend = _Backend(authenticatedUserId: _userId);
    await tester.pumpWidget(_harness(backend: backend));
    await _captureRequiredEvidence(tester);

    // Consent gates submission.
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('missing-product-submit')))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const Key('missing-product-consent')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('missing-product-submit')));
    await tester.pumpAndSettle();

    expect(backend.persistedKind, 'missing_product');
    expect(backend.persistedCueFlag, isTrue);
    expect(backend.manifest, hasLength(2));
    expect(backend.manifest[0]['seq'], 1);
    expect(backend.manifest[0]['categories'], ['front_identity']);
    expect(backend.manifest[1]['seq'], 2);
    expect(backend.manifest[1]['categories'], [
      'supplement_facts',
      'ingredient_disclosure',
    ]);
    expect(find.text('Thanks — it’s in review'), findsOneWidget);
  });

  testWidgets('ticking the combined-panel box after the shot retags in place', (
    tester,
  ) async {
    final backend = _Backend(authenticatedUserId: _userId);
    await tester.pumpWidget(_harness(backend: backend));

    await tester.tap(
      find.byKey(const Key('missing-product-add-front_identity')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('missing-product-next')));
    await tester.pumpAndSettle();

    // Natural order: photograph the facts panel FIRST, then notice the
    // ingredient list lives on it and tick the box. The capture must survive
    // and gain the ingredient tag (regression: the toggle used to delete it).
    await tester.tap(
      find.byKey(const Key('missing-product-add-supplement_facts')),
    );
    await tester.pumpAndSettle();
    expect(find.text('No photo yet'), findsNothing);
    await tester.tap(
      find.byKey(const Key('missing-product-facts-carries-ingredients')),
    );
    await tester.pumpAndSettle();
    expect(find.text('No photo yet'), findsNothing);

    // Unticking reverts the tag but never removes the capture.
    await tester.tap(
      find.byKey(const Key('missing-product-facts-carries-ingredients')),
    );
    await tester.pumpAndSettle();
    expect(find.text('No photo yet'), findsNothing);
    await tester.tap(
      find.byKey(const Key('missing-product-facts-carries-ingredients')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('missing-product-next')));
    await tester.pumpAndSettle();
    // Combined panel: the ingredients step is skipped straight to extras.
    await tester.tap(find.byKey(const Key('missing-product-next')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('missing-product-consent')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('missing-product-submit')));
    await tester.pumpAndSettle();

    expect(backend.manifest, hasLength(2));
    expect(backend.manifest[1]['categories'], [
      'supplement_facts',
      'ingredient_disclosure',
    ]);
  });

  testWidgets('hard-blocks tiny photos and soft-warns blurry ones', (
    tester,
  ) async {
    final backend = _Backend(authenticatedUserId: _userId);
    final verdicts = <PhotoQualityResult>[
      const PhotoQualityResult(
        verdict: PhotoQualityVerdict.tooSmall,
        shortSide: 300,
        blurScore: double.nan,
      ),
      const PhotoQualityResult(
        verdict: PhotoQualityVerdict.likelyBlurry,
        shortSide: 1200,
        blurScore: 3,
      ),
    ];
    await tester.pumpWidget(
      _harness(
        backend: backend,
        qualityGate: (_) async =>
            verdicts.isEmpty ? _okQuality : verdicts.removeAt(0),
      ),
    );

    // Too small: hard block with retake guidance, photo NOT added.
    await tester.tap(
      find.byKey(const Key('missing-product-add-front_identity')),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('too small to read'), findsOneWidget);
    expect(find.text('No photo yet'), findsOneWidget);

    // Blurry: dialog offers Retake / Use anyway; choosing Use anyway keeps it.
    await tester.tap(
      find.byKey(const Key('missing-product-add-front_identity')),
    );
    await tester.pumpAndSettle();
    expect(find.text('That photo looks blurry'), findsOneWidget);
    await tester.tap(find.byKey(const Key('missing-product-blur-use-anyway')));
    await tester.pumpAndSettle();
    expect(find.text('No photo yet'), findsNothing);
  });

  testWidgets('retry reuses one immutable submission id', (tester) async {
    final backend = _Backend(
      authenticatedUserId: _userId,
      persistFailuresRemaining: 1,
    );
    await tester.pumpWidget(_harness(backend: backend));
    await _captureRequiredEvidence(tester);
    await tester.tap(find.byKey(const Key('missing-product-consent')));
    await tester.pump();

    await tester.tap(find.byKey(const Key('missing-product-submit')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Could not submit this product'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('missing-product-submit')));
    await tester.pumpAndSettle();

    expect(backend.persistedSubmissionIds, [_submissionId, _submissionId]);
    expect(find.text('Thanks — it’s in review'), findsOneWidget);
  });

  testWidgets('maps an open-submission conflict to actionable copy', (
    tester,
  ) async {
    final backend = _Backend(
      authenticatedUserId: _userId,
      persistError: StateError(
        'duplicate key value violates unique constraint '
        '"idx_product_submissions_user_open_upc"',
      ),
    );
    await tester.pumpWidget(_harness(backend: backend));
    await _captureRequiredEvidence(tester);
    await tester.tap(find.byKey(const Key('missing-product-consent')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('missing-product-submit')));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('already have an open submission'),
      findsOneWidget,
    );
  });
}

class _Backend implements ProductSubmissionBackend {
  _Backend({
    required this.authenticatedUserId,
    this.persistFailuresRemaining = 0,
    this.persistError,
  });

  @override
  final String? authenticatedUserId;
  String? persistedKind;
  bool? persistedCueFlag;
  int persistFailuresRemaining;
  final Object? persistError;
  final List<String> persistedSubmissionIds = [];
  final Set<String> uploaded = {};
  List<Map<String, Object?>> manifest = const [];

  @override
  Future<void> persistSubmission({
    required String functionName,
    required Map<String, Object?> payload,
  }) async {
    persistedSubmissionIds.add(payload['p_submission_id']! as String);
    if (persistError != null) throw persistError!;
    if (persistFailuresRemaining > 0) {
      persistFailuresRemaining -= 1;
      throw StateError('ambiguous persist failure');
    }
    persistedKind = payload['p_kind'] as String?;
    persistedCueFlag = payload['p_no_separate_ingredient_panel'] as bool?;
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
      (photo) => '$_userId/$submissionId/${photo['photo_id'] as String}',
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
