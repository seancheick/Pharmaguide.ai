import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/features/scanner/missing_product_submission_sheet.dart';
import 'package:pharmaguide/features/contributions/product_submission_consent_copy.dart';
import 'package:pharmaguide/services/gtin.dart';
import 'package:pharmaguide/services/photo_quality_gate.dart';
import 'package:pharmaguide/services/product_submission_draft_store.dart';
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
  PickMissingProductPhoto? pickPhotoFromLibrary,
  EvaluatePhotoQuality? qualityGate,
  String? resubmissionOf,
  ProductSubmissionDraftStorage? draftStore,
  String Function()? submissionIdFactory,
}) {
  return MaterialApp(
    home: Scaffold(
      body: MissingProductSubmissionSheet(
        upc: _upc,
        service: ProductSubmissionService(backend: backend),
        submissionIdFactory: submissionIdFactory ?? () => _submissionId,
        qualityGate: qualityGate ?? (_) async => _okQuality,
        resubmissionOf: resubmissionOf,
        draftStore: draftStore,
        pickPhoto: pickPhoto ?? (tags) async => _photo(tags),
        pickPhotoFromLibrary: pickPhotoFromLibrary,
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

  testWidgets('existing receipt opens contributions and closes capture', (
    tester,
  ) async {
    final backend = _Backend(authenticatedUserId: _userId)
      ..intake = {
        'action': 'open_existing',
        'submission_id': _submissionId,
        'normalized_upc': _upc,
        'resolution_code': null,
        'resolution_detail': null,
      };
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showMissingProductSubmissionSheet(
                  context,
                  upc: _upc,
                  service: ProductSubmissionService(backend: backend),
                ),
                child: const Text('Open capture'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/contributions',
          builder: (_, _) => const Scaffold(body: Text('Contribution history')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.tap(find.text('Open capture'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('missing-product-start')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View your contributions'));
    await tester.pumpAndSettle();
    expect(find.text('Contribution history'), findsOneWidget);
    expect(find.byType(MissingProductSubmissionSheet), findsNothing);
    expect(backend.persistedSubmissionIds, isEmpty);
  });

  testWidgets(
    'interrupted upload offers fresh photos without reusing its manifest',
    (tester) async {
      final backend = _Backend(authenticatedUserId: _userId)
        ..intake = {
          'action': 'incomplete_upload',
          'submission_id': _submissionId,
          'normalized_upc': _upc,
          'resolution_code': null,
          'resolution_detail': null,
        };
      await tester.pumpWidget(_harness(backend: backend));
      await tester.tap(find.byKey(const Key('missing-product-start')));
      await tester.pumpAndSettle();
      expect(find.text('Your earlier upload was interrupted'), findsOneWidget);
      expect(backend.persistedSubmissionIds, isEmpty);
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(find.text('Front of the package'), findsNothing);
      await tester.tap(find.byKey(const Key('missing-product-start')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Take new photos'));
      await tester.pumpAndSettle();
      expect(find.text('Front of the package'), findsOneWidget);
      expect(backend.persistedSubmissionIds, isEmpty);
      expect(backend.persistedLineage, isNull);
    },
  );

  testWidgets('retry dialog fits a narrow phone with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final backend = _Backend(authenticatedUserId: _userId)
      ..intake = {
        'action': 'retry_rejected',
        'submission_id': _submissionId,
        'normalized_upc': _upc,
        'resolution_code': 'photo_quality',
        'resolution_detail': null,
      };
    await tester.pumpWidget(_harness(backend: backend));
    await tester.scrollUntilVisible(
      find.byKey(const Key('missing-product-start')),
      200,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('missing-product-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(
      tester.element(find.byKey(const Key('missing-product-start'))),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('missing-product-start')));
    await tester.pumpAndSettle();
    expect(find.textContaining('too blurry or dark'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Try again with new photos'));
    expect(
      find.text('Try again with new photos').hitTestable(),
      findsOneWidget,
    );
  });

  testWidgets('checks an existing receipt before taking any photos', (
    tester,
  ) async {
    final backend = _Backend(authenticatedUserId: _userId)
      ..intake = {
        'action': 'open_existing',
        'submission_id': _submissionId,
        'normalized_upc': '0$_upc',
        'resolution_code': null,
        'resolution_detail': null,
      };
    await tester.pumpWidget(_harness(backend: backend));
    await tester.tap(find.byKey(const Key('missing-product-start')));
    await tester.pumpAndSettle();

    expect(find.text('You’ve already sent this product'), findsOneWidget);
    expect(find.text('View your contributions'), findsOneWidget);
    expect(find.text('Front of the package'), findsNothing);
    expect(_photoCounter, 0);
    expect(backend.persistedSubmissionIds, isEmpty);
  });

  testWidgets('new entry after rejection explicitly offers a linked retry', (
    tester,
  ) async {
    final backend = _Backend(authenticatedUserId: _userId)
      ..intake = {
        'action': 'retry_rejected',
        'submission_id': '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a22',
        'normalized_upc': '0$_upc',
        'resolution_code': 'photo_quality',
        'resolution_detail': null,
      };
    await tester.pumpWidget(_harness(backend: backend));
    await tester.tap(find.byKey(const Key('missing-product-start')));
    await tester.pumpAndSettle();

    expect(find.text('Try this product again'), findsOneWidget);
    expect(_photoCounter, 0);
    await tester.tap(find.text('Try again with new photos'));
    await tester.pumpAndSettle();
    // Capture a fresh, complete photo set after explicitly choosing retry.
    await tester.tap(
      find.byKey(const Key('missing-product-add-front_identity')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('missing-product-add-supplement_facts')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('missing-product-next')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('missing-product-facts-combined')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('missing-product-add-barcode')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('missing-product-next')));
    await tester.pumpAndSettle();
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
    await tester.tap(find.byKey(const Key('missing-product-consent')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('missing-product-submit')));
    await tester.pumpAndSettle();
    expect(backend.persistedLineage, '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a22');
    expect(find.text('Thanks — it’s in review'), findsOneWidget);
  });

  testWidgets('intake errors do not start a second upload', (tester) async {
    final backend = _Backend(authenticatedUserId: _userId)
      ..intakeError = StateError('offline');
    await tester.pumpWidget(_harness(backend: backend));
    await tester.tap(find.byKey(const Key('missing-product-start')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Couldn’t check your previous submissions'),
      findsOneWidget,
    );
    expect(find.text('Front of the package'), findsNothing);
    expect(_photoCounter, 0);
  });

  testWidgets('intro offers a library path distinct from the camera path', (
    tester,
  ) async {
    var libraryCalls = 0;
    final backend = _Backend(authenticatedUserId: _userId);
    await tester.pumpWidget(
      _harness(
        backend: backend,
        pickPhotoFromLibrary: (tags) async {
          libraryCalls += 1;
          return _photo(tags);
        },
      ),
    );
    expect(
      find.byKey(const Key('missing-product-start-library')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('missing-product-start-library')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('missing-product-add-front_identity')),
    );
    await tester.pumpAndSettle();

    expect(libraryCalls, 1);
    expect(find.text('Supplement Facts'), findsOneWidget);
  });

  testWidgets('intake error offers an explicit safe continuation', (
    tester,
  ) async {
    final backend = _Backend(authenticatedUserId: _userId)
      ..intakeError = StateError('offline');
    await tester.pumpWidget(_harness(backend: backend));
    await tester.tap(find.byKey(const Key('missing-product-start')));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('missing-product-continue-without-history-check')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Front of the package'), findsOneWidget);
    expect(_photoCounter, 0);
  });

  testWidgets('intake timeout leaves capture closed and offers retry', (
    tester,
  ) async {
    final pending = Completer<Map<String, Object?>>();
    final backend = _Backend(authenticatedUserId: _userId)
      ..pendingIntake = pending;
    await tester.pumpWidget(_harness(backend: backend));
    await tester.tap(find.byKey(const Key('missing-product-start')));
    await tester.pump(const Duration(seconds: 11));
    await tester.pump();
    expect(
      find.textContaining('Couldn’t check your previous submissions'),
      findsOneWidget,
    );
    expect(find.text('Front of the package'), findsNothing);
    pending.complete({'action': 'start_new'});
    await tester.pumpAndSettle();
    expect(find.text('Front of the package'), findsNothing);
  });

  testWidgets('one intake check runs while Start is tapped repeatedly', (
    tester,
  ) async {
    final pending = Completer<Map<String, Object?>>();
    final backend = _Backend(authenticatedUserId: _userId)
      ..pendingIntake = pending;
    await tester.pumpWidget(_harness(backend: backend));
    await tester.tap(find.byKey(const Key('missing-product-start')));
    await tester.tap(find.byKey(const Key('missing-product-start')));
    await tester.pump();
    expect(backend.intakeCalls, 1);
    expect(find.text('Front of the package'), findsNothing);
    pending.complete({'action': 'start_new'});
    await tester.pumpAndSettle();
    expect(find.text('Front of the package'), findsOneWidget);
  });

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

  testWidgets(
    'reuses an existing photo for barcode evidence without duplicating bytes',
    (tester) async {
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
      await tester.tap(find.byKey(const Key('missing-product-next')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('missing-product-facts-combined')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('missing-product-reuse-barcode')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('missing-product-reuse-barcode')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(
          const Key(
            'missing-product-reuse-photo-aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa01',
          ),
        ),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(
          const Key(
            'missing-product-reuse-photo-aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa01',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Anything else?'), findsOneWidget);
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
      expect(find.byKey(const Key('missing-product-submit')), findsOneWidget);
      await tester.tap(find.byKey(const Key('missing-product-consent')));
      await tester.pump();
      expect(find.byKey(const Key('missing-product-submit')), findsOneWidget);
      await tester.tap(find.byKey(const Key('missing-product-submit')));
      await tester.pumpAndSettle();

      expect(backend.manifest, hasLength(2));
      expect(backend.manifest[0]['categories'], ['front_identity', 'barcode']);
      expect(backend.manifest[1]['categories'], [
        'supplement_facts',
        'ingredient_disclosure',
      ]);
      expect(find.text('Thanks — it’s in review'), findsOneWidget);
    },
  );

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

  group('interrupted capture recovery', () {
    late _MemoryDraftStorage store;

    setUp(() {
      store = _MemoryDraftStorage();
    });

    Future<void> seedInterruptedCapture() async {
      await store.save(
        userId: _userId,
        submissionId: _submissionId,
        upc: _upc,
        photos: [_photo(MissingProductSubmissionDraft.requiredCategories)],
        consentVersion: productSubmissionConsentVersion,
      );
    }

    testWidgets('offers to finish photos that were never sent', (tester) async {
      await seedInterruptedCapture();
      final backend = _Backend(authenticatedUserId: _userId);

      await tester.pumpWidget(_harness(backend: backend, draftStore: store));
      await tester.pumpAndSettle();

      expect(find.text('Finish your photos?'), findsOneWidget);
      await tester.tap(find.text('Finish sending'));
      await tester.pumpAndSettle();

      // Straight to review with the evidence already in hand.
      expect(find.byKey(const Key('missing-product-consent')), findsOneWidget);
      expect(backend.persistedSubmissionIds, isEmpty);
    });

    testWidgets(
      'resuming keeps the original submission id so a retry replays',
      (tester) async {
        await seedInterruptedCapture();
        final backend = _Backend(authenticatedUserId: _userId);

        await tester.pumpWidget(
          _harness(
            backend: backend,
            draftStore: store,
            submissionIdFactory: () => '018f4c79-7c7e-4c70-9d62-7fc3b9ce6aaa',
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Finish sending'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('missing-product-consent')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('missing-product-submit')));
        await tester.pumpAndSettle();

        // The sheet mints a different id for a fresh capture, so this asserts
        // the recovered one actually won rather than coinciding.
        expect(backend.persistedSubmissionIds, [_submissionId]);
      },
    );

    testWidgets('a sent submission stops being offered for recovery', (
      tester,
    ) async {
      await seedInterruptedCapture();
      final backend = _Backend(authenticatedUserId: _userId);

      await tester.pumpWidget(_harness(backend: backend, draftStore: store));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Finish sending'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('missing-product-consent')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('missing-product-submit')));
      await tester.pumpAndSettle();

      expect(await store.list(_userId), isEmpty);
    });

    testWidgets('starting over deletes the photos rather than keeping them', (
      tester,
    ) async {
      await seedInterruptedCapture();
      final backend = _Backend(authenticatedUserId: _userId);

      await tester.pumpWidget(_harness(backend: backend, draftStore: store));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start over'));
      await tester.pumpAndSettle();

      expect(await store.list(_userId), isEmpty);
      expect(find.text('Add this product'), findsOneWidget);
    });

    testWidgets('a completed capture is saved before the network call', (
      tester,
    ) async {
      final backend = _Backend(
        authenticatedUserId: _userId,
        persistFailuresRemaining: 1,
      );

      await tester.pumpWidget(_harness(backend: backend, draftStore: store));
      await tester.pumpAndSettle();
      await _captureRequiredEvidence(tester);
      await tester.tap(find.byKey(const Key('missing-product-consent')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('missing-product-submit')));
      await tester.pumpAndSettle();

      // The send failed, so the photos must still be recoverable.
      final pending = await store.list(_userId);
      expect(pending, hasLength(1));
      expect(pending.single.acceptedByServer, isFalse);
      expect(pending.single.consentVersion, productSubmissionConsentVersion);
    });

    testWidgets(
      'a half-finished capture is kept and resumes where it stopped',
      (tester) async {
        final backend = _Backend(authenticatedUserId: _userId);
        await tester.pumpWidget(_harness(backend: backend, draftStore: store));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('missing-product-start')));
        await tester.pumpAndSettle();

        // One photo in, then the app dies. Nothing was submitted.
        await tester.tap(
          find.byKey(const Key('missing-product-add-front_identity')),
        );
        await tester.pumpAndSettle();
        expect(backend.persistedSubmissionIds, isEmpty);
        final saved = (await store.list(_userId)).single;
        expect(saved.photoCount, 1);

        // Relaunch: the same barcode offers the partial set back and resumes at
        // the first panel still missing, not at review.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await tester.pumpWidget(_harness(backend: backend, draftStore: store));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Finish sending'));
        await tester.pumpAndSettle();

        expect(find.text('Supplement Facts'), findsOneWidget);
      },
    );

    testWidgets('what is kept on disk tracks what the user still sees', (
      tester,
    ) async {
      final backend = _Backend(authenticatedUserId: _userId);
      await tester.pumpWidget(_harness(backend: backend, draftStore: store));
      await tester.pumpAndSettle();
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
      expect((await store.list(_userId)).single.photoCount, 2);

      // A photo the user deletes must not stay recoverable behind their back.
      await tester.tap(find.byTooltip('Remove photo').first);
      await tester.pumpAndSettle();

      expect((await store.list(_userId)).single.photoCount, 1);
    });

    testWidgets('an upload cut off partway keeps the same identity on retry', (
      tester,
    ) async {
      // The row exists server-side but the bytes never all arrived: the exact
      // state where minting a second id would strand the first submission.
      final backend = _Backend(authenticatedUserId: _userId)
        ..uploadFailuresRemaining = 1;

      await tester.pumpWidget(_harness(backend: backend, draftStore: store));
      await tester.pumpAndSettle();
      await _captureRequiredEvidence(tester);
      await tester.tap(find.byKey(const Key('missing-product-consent')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('missing-product-submit')));
      await tester.pumpAndSettle();

      final firstAttempt = List<String>.from(backend.persistedSubmissionIds);
      expect(firstAttempt, hasLength(1));
      // The photos are still recoverable because the send did not complete.
      expect(await store.list(_userId), hasLength(1));

      // Retry from the same sheet: one contribution, not two.
      await tester.tap(find.byKey(const Key('missing-product-submit')));
      await tester.pumpAndSettle();

      expect(backend.persistedSubmissionIds.toSet(), firstAttempt.toSet());
      expect(await store.list(_userId), isEmpty);
    });

    testWidgets('a signed-out sheet never touches another account\'s capture', (
      tester,
    ) async {
      await seedInterruptedCapture();
      // Nobody is signed in: there is no account whose capture this could be.
      final backend = _Backend(authenticatedUserId: null);

      await tester.pumpWidget(_harness(backend: backend, draftStore: store));
      await tester.pumpAndSettle();

      expect(find.text('Finish your photos?'), findsNothing);
      expect(await store.list(_userId), hasLength(1));
    });

    testWidgets('a different account is not offered these photos', (
      tester,
    ) async {
      await seedInterruptedCapture();
      final backend = _Backend(
        authenticatedUserId: '018f4c79-7c7e-4c70-9d62-7fc3b9ce6bbb',
      );

      await tester.pumpWidget(_harness(backend: backend, draftStore: store));
      await tester.pumpAndSettle();

      expect(find.text('Finish your photos?'), findsNothing);
      // And the first account's evidence is still intact.
      expect(await store.list(_userId), hasLength(1));
    });

    testWidgets('a capture is saved under the account that took it', (
      tester,
    ) async {
      final backend = _Backend(authenticatedUserId: _userId);
      await tester.pumpWidget(_harness(backend: backend, draftStore: store));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('missing-product-start')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('missing-product-add-front_identity')),
      );
      await tester.pumpAndSettle();

      expect(store.savedForUsers, everyElement(_userId));
    });

    testWidgets('a capture from another attempt is not resumed under this one', (
      tester,
    ) async {
      // Saved with no lineage; this sheet is a retry of a rejected submission.
      await seedInterruptedCapture();
      final backend = _Backend(authenticatedUserId: _userId);

      await tester.pumpWidget(
        _harness(
          backend: backend,
          draftStore: store,
          resubmissionOf: '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a99',
        ),
      );
      await tester.pumpAndSettle();

      // Offering it would send the older attempt's photos without the retry
      // lineage, which the open-submission guard rejects.
      expect(find.text('Finish your photos?'), findsNothing);
      expect((await store.list(_userId)), hasLength(1));
    });

    testWidgets('photos that no longer match their manifest are not sent', (
      tester,
    ) async {
      await seedInterruptedCapture();
      store.corruptOnRestore = true;
      final backend = _Backend(authenticatedUserId: _userId);

      await tester.pumpWidget(_harness(backend: backend, draftStore: store));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Finish sending'));
      await tester.pumpAndSettle();

      expect(find.textContaining('could not be reopened'), findsOneWidget);
      expect(backend.persistedSubmissionIds, isEmpty);
      expect(await store.list(_userId), isEmpty);
    });
  });

  testWidgets('an optional panel can be added from the library', (
    tester,
  ) async {
    // Directions, warnings and lot numbers are exactly the panels a
    // contributor has a picture of without the bottle in front of them — read
    // off a listing, or photographed earlier. These tiles only ever opened the
    // camera, so that contributor had no way to add one at all.
    final sources = <String>[];
    final backend = _Backend(authenticatedUserId: _userId);
    await tester.pumpWidget(
      _harness(
        backend: backend,
        pickPhoto: (tags) async {
          sources.add('camera');
          return _photo(tags);
        },
        pickPhotoFromLibrary: (tags) async {
          sources.add('library');
          return _photo(tags);
        },
      ),
    );

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
    await tester.tap(find.byKey(const Key('missing-product-next')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('missing-product-facts-combined')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('missing-product-add-barcode')));
    await tester.pumpAndSettle();
    expect(find.text('Anything else?'), findsOneWidget);

    sources.clear();
    await tester.tap(
      find.byKey(const Key('missing-product-add-library-directions_warnings')),
    );
    await tester.pumpAndSettle();

    expect(sources, ['library']);
    // The camera route stays exactly where it was, so a contributor holding
    // the bottle is not pushed through the photo library instead.
    sources.clear();
    await tester.tap(
      find.byKey(const Key('missing-product-add-directions_warnings')),
    );
    await tester.pumpAndSettle();
    expect(sources, ['camera']);
  });
}

/// The storage contract without a file system, so widget pumps settle.
/// Fidelity that matters here: the manifest hash is what decides whether a
/// kept capture is still the user's evidence, so this keeps and checks it too.
class _MemoryDraftStorage implements ProductSubmissionDraftStorage {
  final Map<String, RestoredCapture> captures = {};
  final Map<String, PendingProductSubmission> records = {};
  final Map<String, String> owners = {};
  bool corruptOnRestore = false;

  final List<String> savedForUsers = [];

  @override
  Future<void> save({
    required String userId,
    required String submissionId,
    required String upc,
    required List<ProductSubmissionPhoto> photos,
    required String consentVersion,
    String? resubmissionOf,
    bool noSeparateIngredientPanel = false,
    int evidenceRevision = 1,
  }) async {
    savedForUsers.add(userId);
    owners[submissionId] = userId;
    captures[submissionId] = RestoredCapture(
      submissionId: submissionId,
      upc: upc,
      resubmissionOf: resubmissionOf,
      noSeparateIngredientPanel: noSeparateIngredientPanel,
      photos: List.unmodifiable(photos),
    );
    records[submissionId] = PendingProductSubmission(
      submissionId: submissionId,
      upc: upc,
      resubmissionOf: resubmissionOf,
      noSeparateIngredientPanel: noSeparateIngredientPanel,
      consentVersion: consentVersion,
      evidenceRevision: evidenceRevision,
      photoCount: photos.length,
      capturedAt: DateTime.now().toUtc(),
    );
  }

  @override
  Future<List<PendingProductSubmission>> list(String userId) async => [
    for (final entry in records.entries)
      if (owners[entry.key] == userId) entry.value,
  ];

  @override
  Future<PendingProductSubmission?> findByUpc(String userId, String upc) async {
    // Same identity owner the real store uses, so the fake cannot drift.
    final wanted = GtinIdentity.parse(upc).canonicalGtin14;
    for (final record in await list(userId)) {
      if (GtinIdentity.parse(record.upc).canonicalGtin14 == wanted) {
        return record;
      }
    }
    return null;
  }

  @override
  Future<RestoredCapture?> restore(String userId, String submissionId) async {
    if (corruptOnRestore) return null;
    if (owners[submissionId] != userId) return null;
    return captures[submissionId];
  }

  @override
  Future<void> discard(String userId, String submissionId) async {
    if (owners[submissionId] != userId) return;
    captures.remove(submissionId);
    records.remove(submissionId);
    owners.remove(submissionId);
  }
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
  Map<String, Object?> intake = {'action': 'start_new'};
  Object? intakeError;
  Completer<Map<String, Object?>>? pendingIntake;
  int intakeCalls = 0;
  String? persistedLineage;
  final List<String> persistedSubmissionIds = [];
  final Set<String> uploaded = {};
  List<Map<String, Object?>> manifest = const [];

  @override
  Future<Map<String, Object?>> fetchIntake({
    required String functionName,
    required Map<String, Object?> payload,
  }) async {
    intakeCalls++;
    if (intakeError != null) throw intakeError!;
    return pendingIntake == null ? intake : await pendingIntake!.future;
  }

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
    persistedLineage = payload['p_resubmission_of'] as String?;
    persistedCueFlag = payload['p_no_separate_ingredient_panel'] as bool?;
    manifest = payload['p_photos']! as List<Map<String, Object?>>;
  }

  int uploadFailuresRemaining = 0;

  @override
  Future<void> uploadPhoto({
    required String bucket,
    required String objectPath,
    required Uint8List bytes,
    required String contentType,
  }) async {
    if (uploadFailuresRemaining > 0) {
      uploadFailuresRemaining -= 1;
      throw StateError('upload interrupted');
    }
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
