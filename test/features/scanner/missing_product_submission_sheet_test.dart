import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/scanner/missing_product_submission_sheet.dart';
import 'package:pharmaguide/services/gtin.dart';
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

/// Drives the camera-first flow through the required captures with the
/// facts shots carrying the ingredient list (answered via the one-tap
/// question), landing on the review step. Front advances automatically;
/// Facts stays open so a wrapped panel can receive another angle.
Future<void> _captureRequiredEvidence(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('missing-product-start')));
  await tester.pumpAndSettle();

  // Front: one shot, auto-advances to the facts step.
  await tester.tap(find.byKey(const Key('missing-product-add-front_identity')));
  await tester.pumpAndSettle();
  expect(find.text('Supplement Facts'), findsOneWidget);

  // Facts: the first shot stays put, a second angle appends, and only
  // Continue opens the combined-panel question.
  await tester.tap(
    find.byKey(const Key('missing-product-add-supplement_facts')),
  );
  await tester.pumpAndSettle();
  expect(find.text('Supplement Facts'), findsOneWidget);
  expect(find.text('Add another angle'), findsOneWidget);
  expect(find.byKey(const Key('missing-product-facts-combined')), findsNothing);

  await tester.tap(
    find.byKey(const Key('missing-product-add-supplement_facts')),
  );
  await tester.pumpAndSettle();
  expect(find.text('Supplement Facts'), findsOneWidget);
  expect(find.byTooltip('Remove photo'), findsNWidgets(2));
  expect(find.byKey(const Key('missing-product-facts-combined')), findsNothing);

  await tester.tap(find.byKey(const Key('missing-product-next')));
  await tester.pumpAndSettle();
  expect(
    find.byKey(const Key('missing-product-facts-combined')),
    findsOneWidget,
  );
  await tester.tap(find.byKey(const Key('missing-product-facts-combined')));
  await tester.pumpAndSettle();
  expect(find.text('Barcode'), findsOneWidget);

  // The barcode is required identity evidence and advances automatically.
  await tester.tap(find.byKey(const Key('missing-product-add-barcode')));
  await tester.pumpAndSettle();
  expect(find.text('Anything else?'), findsOneWidget);

  // Extras are skippable; move straight to review.
  await tester.tap(find.byKey(const Key('missing-product-next')));
  await tester.pumpAndSettle();
  expect(find.text('Review & submit'), findsOneWidget);
  await tester.scrollUntilVisible(
    find.byKey(const Key('missing-product-submit')),
    300,
    scrollable: find
        .descendant(
          of: find.byKey(const Key('missing-product-scroll')),
          matching: find.byType(Scrollable),
        )
        .first,
  );
}

void main() {
  setUp(() => _photoCounter = 0);

  testWidgets('invalid GTIN never opens the capture flow', (tester) async {
    final backend = _Backend(authenticatedUserId: _userId);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showMissingProductSubmissionSheet(
                context,
                upc: '123456789',
                service: ProductSubmissionService(backend: backend),
                qualityGate: (_) async => _okQuality,
                pickPhoto: (tags) async => _photo(tags),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text(invalidGtinMessage), findsOneWidget);
    expect(find.text('Add this product'), findsNothing);
    expect(backend.persistedSubmissionIds, isEmpty);
  });

  testWidgets('front advances automatically while facts waits for Continue', (
    tester,
  ) async {
    final backend = _Backend(authenticatedUserId: _userId);
    await tester.pumpWidget(_harness(backend: backend));

    // Intro explains the job and owns the only Start affordance.
    expect(find.text('Add this product'), findsOneWidget);
    expect(find.textContaining('A few clear photos'), findsOneWidget);
    await tester.tap(find.byKey(const Key('missing-product-start')));
    await tester.pumpAndSettle();

    // No photo yet: there is nothing to continue with — the forward
    // button does not exist until the step is satisfied.
    expect(find.text('Front of the package'), findsOneWidget);
    expect(find.byKey(const Key('missing-product-next')), findsNothing);

    await tester.tap(
      find.byKey(const Key('missing-product-add-front_identity')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Supplement Facts'), findsOneWidget);
    await tester.tap(
      find.byKey(const Key('missing-product-add-supplement_facts')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Supplement Facts'), findsOneWidget);
    expect(
      find.byKey(const Key('missing-product-facts-combined')),
      findsNothing,
    );
    await tester.tap(find.byKey(const Key('missing-product-next')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('missing-product-facts-combined')));
    await tester.pumpAndSettle();
    expect(find.text('Barcode'), findsOneWidget);
    expect(find.byKey(const Key('missing-product-next')), findsNothing);
    await tester.tap(find.byKey(const Key('missing-product-add-barcode')));
    await tester.pumpAndSettle();
    expect(find.text('Anything else?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('missing-product-next')));
    await tester.pumpAndSettle();
    expect(find.text('Review & submit'), findsOneWidget);

    expect(find.byKey(const Key('missing-product-consent')), findsOneWidget);
    expect(
      find.text(
        'I consent to send this account-linked product submission, barcode, '
        'and selected label photos privately to PharmaGuide for review. A '
        'third-party AI service may read the label, but a human reviewer '
        'approves every entry. If approved, the front-label photo—including '
        'a crop—may be published as the product image. I confirm the photos '
        'contain no pharmacy stickers or other personal health information.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('missing-product-privacy')));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Your account identifier, this barcode, and selected product-label '
        'photos go privately to PharmaGuide for review. We strip embedded '
        'photo metadata (EXIF) before upload, but anything visible in the '
        'pixels remains. Do not include pharmacy stickers, names, '
        'prescription numbers, or other personal health information.\n\n'
        'A third-party AI service may read the label to prepare a draft. A '
        'human reviewer approves every catalog entry. If approved, the '
        'front-label photo—including a crop—may be published as the product '
        'image. Your health profile, medications, conditions, allergies, and '
        'stack stay on this device.',
      ),
      findsOneWidget,
    );
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
    // The combined-panel answer re-tagged the facts capture in place —
    // both photos survived the question (regression: a checkbox used to
    // delete the shot it described).
    expect(backend.manifest, hasLength(4));
    expect(backend.manifest[0]['seq'], 1);
    expect(backend.manifest[0]['categories'], ['front_identity']);
    expect(backend.manifest[1]['seq'], 2);
    expect(backend.manifest[1]['categories'], [
      'supplement_facts',
      'ingredient_disclosure',
    ]);
    expect(backend.manifest[2]['seq'], 3);
    expect(backend.manifest[2]['categories'], [
      'supplement_facts',
      'ingredient_disclosure',
    ]);
    expect(backend.manifest[3]['seq'], 4);
    expect(backend.manifest[3]['categories'], ['barcode']);
    expect(find.text('Thanks — it’s in review'), findsOneWidget);
  });

  testWidgets('a separate ingredient panel gets its own capture step', (
    tester,
  ) async {
    final backend = _Backend(authenticatedUserId: _userId);
    await tester.pumpWidget(_harness(backend: backend));

    await tester.tap(find.byKey(const Key('missing-product-start')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('missing-product-add-front_identity')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('missing-product-add-supplement_facts')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Supplement Facts'), findsOneWidget);
    await tester.tap(find.byKey(const Key('missing-product-next')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('missing-product-facts-separate')));
    await tester.pumpAndSettle();

    expect(find.text('Other Ingredients'), findsOneWidget);
    await tester.tap(
      find.byKey(const Key('missing-product-add-ingredient_disclosure')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Barcode'), findsOneWidget);
    await tester.tap(find.byKey(const Key('missing-product-add-barcode')));
    await tester.pumpAndSettle();
    expect(find.text('Anything else?'), findsOneWidget);

    await tester.tap(find.byKey(const Key('missing-product-next')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('missing-product-consent')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('missing-product-submit')));
    await tester.pumpAndSettle();

    expect(backend.persistedCueFlag, isFalse);
    expect(backend.manifest, hasLength(4));
    expect(backend.manifest[1]['categories'], ['supplement_facts']);
    expect(backend.manifest[2]['categories'], ['ingredient_disclosure']);
    expect(backend.manifest[3]['categories'], ['barcode']);
  });

  testWidgets('a combined-panel answer can be corrected before submission', (
    tester,
  ) async {
    final backend = _Backend(authenticatedUserId: _userId);
    await tester.pumpWidget(_harness(backend: backend));
    await _captureRequiredEvidence(tester);

    await tester.tap(
      find.byKey(const Key('missing-product-facts-change-to-separate')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Other Ingredients'), findsOneWidget);
    await tester.tap(
      find.byKey(const Key('missing-product-add-ingredient_disclosure')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Barcode'), findsOneWidget);
    await tester.tap(find.byKey(const Key('missing-product-next')));
    await tester.pumpAndSettle();
    expect(find.text('Anything else?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('missing-product-next')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('missing-product-consent')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('missing-product-submit')));
    await tester.pumpAndSettle();

    expect(backend.persistedCueFlag, isFalse);
    expect(backend.manifest, hasLength(5));
    expect(backend.manifest[1]['categories'], ['supplement_facts']);
    expect(backend.manifest[2]['categories'], ['supplement_facts']);
    expect(backend.manifest[3]['categories'], ['barcode']);
    expect(backend.manifest[4]['categories'], ['ingredient_disclosure']);
  });

  testWidgets('the no-facts dead end explains why and can cancel', (
    tester,
  ) async {
    final backend = _Backend(authenticatedUserId: _userId);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showMissingProductSubmissionSheet(
                context,
                upc: _upc,
                service: ProductSubmissionService(backend: backend),
                submissionIdFactory: () => _submissionId,
                qualityGate: (_) async => _okQuality,
                pickPhoto: (tags) async => _photo(tags),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('missing-product-start')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('missing-product-add-front_identity')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('missing-product-no-facts-link')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Check the outer box'),
      findsOneWidget,
      reason: 'The dead end must offer the box hint before giving up.',
    );
    await tester.tap(find.byKey(const Key('missing-product-no-facts-cancel')));
    await tester.pumpAndSettle();

    // The sheet is gone and nothing was submitted.
    expect(find.text('Supplement Facts'), findsNothing);
    expect(backend.persistedSubmissionIds, isEmpty);
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
    await tester.tap(find.byKey(const Key('missing-product-start')));
    await tester.pumpAndSettle();

    // Too small: hard block with retake guidance; no photo, no advance.
    await tester.tap(
      find.byKey(const Key('missing-product-add-front_identity')),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('too small to read'), findsOneWidget);
    expect(find.text('Front of the package'), findsOneWidget);

    // Blurry: readability self-check; keeping it advances the flow.
    await tester.tap(
      find.byKey(const Key('missing-product-add-front_identity')),
    );
    await tester.pumpAndSettle();
    expect(find.text('That photo looks blurry'), findsOneWidget);
    await tester.tap(find.byKey(const Key('missing-product-blur-use-anyway')));
    await tester.pumpAndSettle();
    expect(find.text('Supplement Facts'), findsOneWidget);
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
    required int offset,
    required int limit,
  }) async {
    return const [];
  }
}
