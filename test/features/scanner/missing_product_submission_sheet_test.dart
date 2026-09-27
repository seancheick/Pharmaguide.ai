import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/features/scanner/missing_product_submission_sheet.dart';
import 'package:pharmaguide/features/contributions/product_submission_consent_copy.dart';
import 'package:pharmaguide/services/gtin.dart';
import 'package:pharmaguide/services/photo_panel_hints.dart';
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
  ReadSubmissionPhotoText? readPhotoText,
  PickMissingProductPhotos? pickPhotosFromLibrary,
  ProductSubmissionRetake? retake,
}) {
  return MaterialApp(
    home: Scaffold(
      body: MissingProductSubmissionSheet(
        upc: _upc,
        service: ProductSubmissionService(backend: backend),
        submissionIdFactory: submissionIdFactory ?? () => _submissionId,
        qualityGate: qualityGate ?? (_) async => _okQuality,
        resubmissionOf: resubmissionOf,
        retake: retake,
        draftStore: draftStore,
        pickPhoto: pickPhoto ?? (tags) async => _photo(tags),
        pickPhotoFromLibrary: pickPhotoFromLibrary,
        readPhotoText: readPhotoText,
        pickPhotosFromLibrary: pickPhotosFromLibrary,
      ),
    ),
  );
}

/// The title of the step on screen. Every step's title carries this key, so
/// "which step are we on?" never matches the same word in the checklist.
String? _stepTitle(WidgetTester tester) {
  // The title scrolls with the step's content; it names the step even when
  // the user has scrolled past it.
  final title = find.byKey(
    const Key('missing-product-step-title'),
    skipOffstage: false,
  );
  return title.evaluate().isEmpty ? null : tester.widget<Text>(title).data;
}

Finder get _sheetScroll => find
    .descendant(
      of: find.byKey(const Key('missing-product-scroll')),
      matching: find.byType(Scrollable),
    )
    .first;

/// Review's consent sits at the end of its scrolling content, right above
/// the pinned Submit button. The drags leave a fling running, so settle and
/// reveal the whole tile before anything taps it.
Future<void> _scrollToConsent(WidgetTester tester) async {
  final consent = find.byKey(const Key('missing-product-consent'));
  await tester.scrollUntilVisible(consent, 300, scrollable: _sheetScroll);
  await tester.pumpAndSettle();
  await tester.ensureVisible(consent);
  await tester.pumpAndSettle();
}

/// Taps something in the sheet's scrolling content, scrolling down to it
/// first when it sits below the test screen's fold.
Future<void> _tapInSheet(WidgetTester tester, Finder target) async {
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(target, 200, scrollable: _sheetScroll);
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

/// Drives the camera-first flow through the required captures with the
/// facts shots carrying the ingredient list (answered by the question under
/// the facts photo), landing on the review step with the consent in view.
/// Start opens the camera for the front, which advances by itself; Facts
/// stays open so a wrapped panel can receive another angle.
Future<void> _captureRequiredEvidence(WidgetTester tester) async {
  // Start is the front shot: no second "open camera" tap.
  await tester.tap(find.byKey(const Key('missing-product-start')));
  await tester.pumpAndSettle();
  expect(_stepTitle(tester), 'Supplement Facts');
  expect(find.text('Front photo saved.'), findsOneWidget);

  // Facts: the first shot stays put and asks its one question right under
  // the photo; a second angle appends without answering it.
  await tester.tap(
    find.byKey(const Key('missing-product-add-supplement_facts')),
  );
  await tester.pumpAndSettle();
  expect(_stepTitle(tester), 'Supplement Facts');
  expect(find.text('Add another angle'), findsOneWidget);
  expect(
    find.byKey(const Key('missing-product-facts-combined')),
    findsOneWidget,
  );
  expect(find.byKey(const Key('missing-product-next')), findsNothing);

  await tester.tap(
    find.byKey(const Key('missing-product-add-supplement_facts')),
  );
  await tester.pumpAndSettle();
  expect(_stepTitle(tester), 'Supplement Facts');
  expect(find.byTooltip('Remove photo'), findsNWidgets(2));

  // The answer is the continue.
  await tester.tap(find.byKey(const Key('missing-product-facts-combined')));
  await tester.pumpAndSettle();
  expect(_stepTitle(tester), 'Barcode');

  // The barcode is required identity evidence and advances automatically —
  // straight to review; optional panels are offered there.
  await tester.tap(find.byKey(const Key('missing-product-add-barcode')));
  await tester.pumpAndSettle();
  expect(_stepTitle(tester), 'Review & submit');
  await _scrollToConsent(tester);
}

void main() {
  setUp(() => _photoCounter = 0);

  testWidgets(
    'denied camera access says how to fix it, and the library works',
    (tester) async {
      var libraryPicks = 0;
      await tester.pumpWidget(
        _harness(
          backend: _Backend(authenticatedUserId: _userId),
          // What image_picker throws on iOS and Android when the camera
          // permission is off. Retrying can never succeed.
          pickPhoto: (_) async => throw PlatformException(
            code: 'camera_access_denied',
            message: 'The user did not allow camera access.',
          ),
          pickPhotoFromLibrary: (tags) async {
            libraryPicks++;
            return _photo(tags);
          },
        ),
      );
      // Start opens the camera for the front.
      await tester.tap(find.byKey(const Key('missing-product-start')));
      await tester.pumpAndSettle();

      expect(_stepTitle(tester), 'Front of the package');
      expect(find.text('Camera access is off'), findsOneWidget);
      expect(
        find.byKey(const Key('missing-product-open-settings')),
        findsOneWidget,
      );
      expect(find.textContaining('couldn’t open that photo'), findsNothing);
      // The primary button becomes the source that still works; the camera
      // stays one tap away for after the Settings change.
      expect(find.text('Choose a photo'), findsOneWidget);
      expect(find.text('Use camera instead'), findsOneWidget);

      await tester.tap(
        find.byKey(const Key('missing-product-add-front_identity')),
      );
      await tester.pumpAndSettle();
      expect(libraryPicks, 1);
      expect(_stepTitle(tester), 'Supplement Facts');
      expect(find.text('Camera access is off'), findsNothing);
    },
  );

  testWidgets('a blocked library on a library-first start still explains '
      'itself, and the camera becomes the primary', (tester) async {
    await tester.pumpWidget(
      _harness(
        backend: _Backend(authenticatedUserId: _userId),
        pickPhotosFromLibrary: (_) async =>
            throw PlatformException(code: 'photo_access_denied'),
      ),
    );
    await tester.tap(find.byKey(const Key('missing-product-start-library')));
    await tester.pumpAndSettle();

    expect(_stepTitle(tester), 'Front of the package');
    expect(find.text('Photo access is off'), findsOneWidget);
    expect(find.text('Take photo'), findsOneWidget);
    await tester.tap(
      find.byKey(const Key('missing-product-add-front_identity')),
    );
    await tester.pumpAndSettle();
    expect(_photoCounter, 1);
    expect(_stepTitle(tester), 'Supplement Facts');
  });

  testWidgets('a device without a camera carries on from the library', (
    tester,
  ) async {
    var libraryPicks = 0;
    await tester.pumpWidget(
      _harness(
        backend: _Backend(authenticatedUserId: _userId),
        pickPhoto: (_) async =>
            throw PlatformException(code: 'no_available_camera'),
        pickPhotoFromLibrary: (tags) async {
          libraryPicks++;
          return _photo(tags);
        },
      ),
    );
    await tester.tap(find.byKey(const Key('missing-product-start')));
    await tester.pumpAndSettle();

    expect(find.textContaining('No camera is available'), findsOneWidget);
    expect(find.text('Choose a photo'), findsOneWidget);
    await tester.tap(
      find.byKey(const Key('missing-product-add-front_identity')),
    );
    await tester.pumpAndSettle();
    expect(libraryPicks, 1);
    expect(_stepTitle(tester), 'Supplement Facts');
  });

  testWidgets('in library mode, "Use camera instead" opens the camera', (
    tester,
  ) async {
    var cameraPicks = 0;
    var libraryPicks = 0;
    await tester.pumpWidget(
      _harness(
        backend: _Backend(authenticatedUserId: _userId),
        pickPhoto: (tags) async {
          cameraPicks++;
          return _photo(tags);
        },
        pickPhotoFromLibrary: (tags) async {
          libraryPicks++;
          return _photo(tags);
        },
      ),
    );
    await tester.tap(find.byKey(const Key('missing-product-start-library')));
    await tester.pumpAndSettle();
    expect(find.text('Use camera instead'), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('missing-product-library-front_identity')),
    );
    await tester.pumpAndSettle();
    expect(cameraPicks, 1);
    expect(libraryPicks, 0);
  });

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
      expect(_stepTitle(tester), 'Add this product');
      expect(_photoCounter, 0);
      await tester.tap(find.byKey(const Key('missing-product-start')));
      await tester.pumpAndSettle();
      // "Take new photos" continues into the camera for a fresh front shot.
      await tester.tap(find.text('Take new photos'));
      await tester.pumpAndSettle();
      expect(_photoCounter, 1);
      expect(_stepTitle(tester), 'Supplement Facts');
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
    // Choosing retry continues straight into the front shot.
    await tester.tap(find.text('Try again with new photos'));
    await tester.pumpAndSettle();
    expect(_photoCounter, 1);
    // Capture the rest of a fresh, complete photo set.
    await tester.tap(
      find.byKey(const Key('missing-product-add-supplement_facts')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('missing-product-facts-combined')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('missing-product-add-barcode')));
    await tester.pumpAndSettle();
    await _scrollToConsent(tester);
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

    // Continuing does what Start promised: the front shot. Nothing is sent
    // until the user submits.
    expect(_photoCounter, 1);
    expect(_stepTitle(tester), 'Supplement Facts');
    expect(backend.persistedSubmissionIds, isEmpty);
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
    expect(_stepTitle(tester), 'Add this product');
    pending.complete({'action': 'start_new'});
    await tester.pumpAndSettle();
    // One check, one camera: the double tap never opens a second picker.
    expect(backend.intakeCalls, 1);
    expect(_photoCounter, 1);
    expect(_stepTitle(tester), 'Supplement Facts');
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

  testWidgets('start is the front shot; facts asks its one question in place', (
    tester,
  ) async {
    final backend = _Backend(authenticatedUserId: _userId);
    await tester.pumpWidget(_harness(backend: backend));

    // Intro explains the job and owns the only Start affordance. It scopes
    // the miss to this device and promises review, not publication.
    expect(_stepTitle(tester), 'Add this product');
    expect(
      find.text(
        'Take a few clear label photos and we’ll check whether it already '
        'exists or needs an updated label.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('add this product for everyone'), findsNothing);
    expect(find.text('Start with the front'), findsOneWidget);
    await tester.tap(find.byKey(const Key('missing-product-start')));
    await tester.pumpAndSettle();

    // The start button took the front photo and moved on, saying so.
    expect(_photoCounter, 1);
    expect(_stepTitle(tester), 'Supplement Facts');
    expect(find.text('Front photo saved.'), findsOneWidget);
    // No photo yet: there is nothing to continue with.
    expect(find.byKey(const Key('missing-product-next')), findsNothing);
    expect(
      find.byKey(const Key('missing-product-facts-combined')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const Key('missing-product-add-supplement_facts')),
    );
    await tester.pumpAndSettle();
    // Facts stays open (another angle may follow) and asks right here.
    expect(_stepTitle(tester), 'Supplement Facts');
    expect(
      find.text('Is the “Other Ingredients” list on this panel too?'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('missing-product-facts-combined')));
    await tester.pumpAndSettle();
    expect(_stepTitle(tester), 'Barcode');
    expect(find.byKey(const Key('missing-product-next')), findsNothing);
    await tester.tap(find.byKey(const Key('missing-product-add-barcode')));
    await tester.pumpAndSettle();
    expect(_stepTitle(tester), 'Review & submit');
    await _scrollToConsent(tester);

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
    await _scrollToConsent(tester);
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
        find.byKey(const Key('missing-product-add-supplement_facts')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('missing-product-facts-combined')));
      await tester.pumpAndSettle();

      // Below the example on a short screen: reachable by scrolling.
      await tester.scrollUntilVisible(
        find.byKey(const Key('missing-product-reuse-barcode')),
        200,
        scrollable: _sheetScroll,
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

      expect(_stepTitle(tester), 'Review & submit');
      await _scrollToConsent(tester);
      expect(find.byKey(const Key('missing-product-submit')), findsOneWidget);
      await _scrollToConsent(tester);
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
      find.byKey(const Key('missing-product-add-supplement_facts')),
    );
    await tester.pumpAndSettle();
    expect(_stepTitle(tester), 'Supplement Facts');
    await tester.tap(find.byKey(const Key('missing-product-facts-separate')));
    await tester.pumpAndSettle();

    expect(_stepTitle(tester), 'Other Ingredients');
    await tester.tap(
      find.byKey(const Key('missing-product-add-ingredient_disclosure')),
    );
    await tester.pumpAndSettle();
    expect(_stepTitle(tester), 'Barcode');
    await tester.tap(find.byKey(const Key('missing-product-add-barcode')));
    await tester.pumpAndSettle();
    expect(_stepTitle(tester), 'Review & submit');

    await _scrollToConsent(tester);
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

  testWidgets('an ingredients step can say the list was on the facts photo', (
    tester,
  ) async {
    final backend = _Backend(authenticatedUserId: _userId);
    await tester.pumpWidget(_harness(backend: backend));
    await tester.tap(find.byKey(const Key('missing-product-start')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('missing-product-add-supplement_facts')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('missing-product-facts-separate')));
    await tester.pumpAndSettle();
    expect(_stepTitle(tester), 'Other Ingredients');

    // It was on the facts panel after all: no second photo needed.
    await _tapInSheet(
      tester,
      find.byKey(const Key('missing-product-ingredients-on-facts')),
    );
    expect(_stepTitle(tester), 'Barcode');
    await tester.tap(find.byKey(const Key('missing-product-add-barcode')));
    await tester.pumpAndSettle();
    await _scrollToConsent(tester);
    await tester.tap(find.byKey(const Key('missing-product-consent')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('missing-product-submit')));
    await tester.pumpAndSettle();

    expect(backend.persistedCueFlag, isTrue);
    expect(backend.manifest, hasLength(3));
    // Re-tagged in place, never deleted.
    expect(backend.manifest[1]['categories'], [
      'supplement_facts',
      'ingredient_disclosure',
    ]);
  });

  testWidgets('a combined-panel answer can be corrected before submission', (
    tester,
  ) async {
    final backend = _Backend(authenticatedUserId: _userId);
    await tester.pumpWidget(_harness(backend: backend));
    await _captureRequiredEvidence(tester);

    // Back up from the consent to the note under the photos.
    await tester.scrollUntilVisible(
      find.byKey(const Key('missing-product-facts-change-to-separate')),
      -200,
      scrollable: _sheetScroll,
    );
    await tester.ensureVisible(
      find.byKey(const Key('missing-product-facts-change-to-separate')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('missing-product-facts-change-to-separate')),
    );
    await tester.pumpAndSettle();

    expect(_stepTitle(tester), 'Other Ingredients');
    await tester.tap(
      find.byKey(const Key('missing-product-add-ingredient_disclosure')),
    );
    await tester.pumpAndSettle();
    // The barcode is already covered, so capture does not walk the user back
    // through a step they finished.
    expect(_stepTitle(tester), 'Review & submit');
    await _scrollToConsent(tester);
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
                // Like the camera, the on-device text reader is native.
                readPhotoText: (_) async => '',
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    // Start takes the front; the facts step offers the dead-end link.
    await tester.tap(find.byKey(const Key('missing-product-start')));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('missing-product-no-facts-link')),
      200,
      scrollable: _sheetScroll,
    );
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
    // Start opens the camera for the front. Too small: hard block with
    // retake guidance; no photo, no advance.
    await tester.tap(find.byKey(const Key('missing-product-start')));
    await tester.pumpAndSettle();
    expect(find.textContaining('too small to read'), findsOneWidget);
    expect(_stepTitle(tester), 'Front of the package');

    // Blurry: readability self-check; keeping it advances the flow.
    await tester.tap(
      find.byKey(const Key('missing-product-add-front_identity')),
    );
    await tester.pumpAndSettle();
    expect(find.text('That photo looks blurry'), findsOneWidget);
    await tester.tap(find.byKey(const Key('missing-product-blur-use-anyway')));
    await tester.pumpAndSettle();
    expect(_stepTitle(tester), 'Supplement Facts');
  });

  testWidgets('retry reuses one immutable submission id', (tester) async {
    final backend = _Backend(
      authenticatedUserId: _userId,
      persistFailuresRemaining: 1,
    );
    await tester.pumpWidget(_harness(backend: backend));
    await _captureRequiredEvidence(tester);
    await _scrollToConsent(tester);
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
    await _scrollToConsent(tester);
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
      expect(_stepTitle(tester), 'Review & submit');
      await _scrollToConsent(tester);
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
        await _scrollToConsent(tester);
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
      await _scrollToConsent(tester);
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
      await _scrollToConsent(tester);
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
      await _scrollToConsent(tester);
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
      find.byKey(const Key('missing-product-add-supplement_facts')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('missing-product-facts-combined')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('missing-product-add-barcode')));
    await tester.pumpAndSettle();
    // Optional panels are offered on review, not as a step of their own.
    expect(_stepTitle(tester), 'Review & submit');

    final library = find.byKey(
      const Key('missing-product-add-library-directions_warnings'),
    );
    await tester.scrollUntilVisible(library, 200, scrollable: _sheetScroll);
    await tester.pumpAndSettle();
    await tester.ensureVisible(library);
    await tester.pumpAndSettle();
    sources.clear();
    await tester.tap(library);
    await tester.pumpAndSettle();

    expect(sources, ['library']);
    // Still on review: an optional photo never moves the flow.
    expect(find.byKey(const Key('missing-product-submit')), findsOneWidget);
    // The camera route stays exactly where it was, so a contributor holding
    // the bottle is not pushed through the photo library instead.
    sources.clear();
    // The new photo joined the grid above, so the row moved: bring it back.
    await tester.ensureVisible(
      find.byKey(const Key('missing-product-add-directions_warnings')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('missing-product-add-directions_warnings')),
    );
    await tester.pumpAndSettle();
    expect(sources, ['camera']);
    // Both land in the review grid, labelled with their panel.
    expect(find.text('Directions', skipOffstage: false), findsNWidgets(2));
  });

  testWidgets(
    'a blocked camera on an optional panel still says how to fix it',
    (tester) async {
      var blocked = false;
      await tester.pumpWidget(
        _harness(
          backend: _Backend(authenticatedUserId: _userId),
          pickPhoto: (tags) async => blocked
              ? throw PlatformException(code: 'camera_access_denied')
              : _photo(tags),
        ),
      );
      await _captureRequiredEvidence(tester);
      blocked = true;
      final add = find.byKey(
        const Key('missing-product-add-directions_warnings'),
      );
      await tester.scrollUntilVisible(add, -200, scrollable: _sheetScroll);
      await tester.pumpAndSettle();
      await tester.ensureVisible(add);
      await tester.pumpAndSettle();
      await tester.tap(add);
      await tester.pumpAndSettle();

      expect(
        find.text('Camera access is off', skipOffstage: false),
        findsOneWidget,
      );
      expect(find.textContaining('couldn’t open that photo'), findsNothing);
    },
  );

  group('on-device panel hints', () {
    const facts = ProductSubmissionEvidenceCategory.supplementFacts;

    Future<void> tapKey(WidgetTester tester, String key) async {
      final target = find.byKey(Key(key));
      // A notice line can push content below the test screen's fold; the
      // pinned footer actions and dialog buttons are always on stage.
      if (target.evaluate().isEmpty) {
        await tester.scrollUntilVisible(target, 200, scrollable: _sheetScroll);
      }
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      await tester.tap(target);
      await tester.pumpAndSettle();
    }

    Future<void> submitFromReview(WidgetTester tester) async {
      await _scrollToConsent(tester);
      await tester.tap(find.byKey(const Key('missing-product-consent')));
      await tester.pump();
      await tapKey(tester, 'missing-product-submit');
    }

    testWidgets('a directions photo in the Facts slot is questioned first', (
      tester,
    ) async {
      final backend = _Backend(authenticatedUserId: _userId);
      await tester.pumpWidget(
        _harness(
          backend: backend,
          readPhotoText: (photo) async => photo.categories.contains(facts)
              ? 'Directions: take one capsule daily.\n'
                    'Warning: keep out of reach of children.'
              : '',
        ),
      );
      await tapKey(tester, 'missing-product-start');
      expect(find.text('Supplement Facts'), findsOneWidget);

      await tapKey(tester, 'missing-product-add-supplement_facts');
      expect(find.text('Is this the Supplement Facts panel?'), findsOneWidget);
      await tapKey(tester, 'missing-product-hint-retake');
      // Retake discards the shot: nothing was added to the Facts panel.
      expect(find.byTooltip('Remove photo'), findsNothing);

      // The hint is a question, never a block: the user can keep the photo.
      await tapKey(tester, 'missing-product-add-supplement_facts');
      await tapKey(tester, 'missing-product-hint-keep');
      expect(find.byTooltip('Remove photo'), findsOneWidget);
    });

    testWidgets(
      'a Facts photo showing Other Ingredients answers the panel question',
      (tester) async {
        final backend = _Backend(authenticatedUserId: _userId);
        await tester.pumpWidget(
          _harness(
            backend: backend,
            readPhotoText: (photo) async => photo.categories.contains(facts)
                ? 'Supplement Facts\nServing Size 1 Capsule\n'
                      'Other Ingredients: cellulose, rice flour'
                : '',
          ),
        );
        await tapKey(tester, 'missing-product-start');
        await tapKey(tester, 'missing-product-add-supplement_facts');
        // The photo answered the question: Continue, not a question.
        expect(
          find.byKey(const Key('missing-product-facts-combined')),
          findsNothing,
        );
        await tapKey(tester, 'missing-product-next');

        expect(_stepTitle(tester), 'Barcode');
        await tapKey(tester, 'missing-product-add-barcode');
        expect(_stepTitle(tester), 'Review & submit');
        // The answer the photo gave stays correctable on review.
        expect(
          find.byKey(
            const Key('missing-product-facts-change-to-separate'),
            skipOffstage: false,
          ),
          findsOneWidget,
        );
        await submitFromReview(tester);

        expect(backend.persistedCueFlag, isTrue);
        expect(
          backend.manifest[1]['categories'],
          unorderedEquals(['supplement_facts', 'ingredient_disclosure']),
        );
      },
    );

    testWidgets('a readable Facts photo with no Other Ingredients heading is '
        'assumed to have none, not questioned', (tester) async {
      final backend = _Backend(authenticatedUserId: _userId);
      await tester.pumpWidget(
        _harness(
          backend: backend,
          readPhotoText: (photo) async => photo.categories.contains(facts)
              ? 'Supplement Facts\nServing Size 1 Capsule\n'
                    'Servings Per Container 60'
              : '',
        ),
      );
      await tapKey(tester, 'missing-product-start');
      await tapKey(tester, 'missing-product-add-supplement_facts');

      // No taxonomy question — Continue goes straight to Barcode, same as
      // a confirmed combined panel.
      expect(
        find.byKey(const Key('missing-product-facts-combined')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('missing-product-facts-separate')),
        findsNothing,
      );
      await tapKey(tester, 'missing-product-next');
      expect(_stepTitle(tester), 'Barcode');
      await tapKey(tester, 'missing-product-add-barcode');
      // Still correctable on review, same escape hatch as a real
      // OCR-confirmed combined panel.
      expect(
        find.byKey(
          const Key('missing-product-facts-change-to-separate'),
          skipOffstage: false,
        ),
        findsOneWidget,
      );
      await submitFromReview(tester);

      expect(
        backend.manifest[1]['categories'],
        unorderedEquals(['supplement_facts', 'ingredient_disclosure']),
      );
    });

    testWidgets(
      'a Facts photo with nothing legible still asks — the assumption '
      'requires reading the panel, not just failing to read one',
      (tester) async {
        final backend = _Backend(authenticatedUserId: _userId);
        await tester.pumpWidget(
          _harness(backend: backend, readPhotoText: (_) async => ''),
        );
        await tapKey(tester, 'missing-product-start');
        await tapKey(tester, 'missing-product-add-supplement_facts');

        // Asked right under the photo, with no way past it but an answer.
        expect(
          find.text('Is the “Other Ingredients” list on this panel too?'),
          findsOneWidget,
        );
        expect(find.byKey(const Key('missing-product-next')), findsNothing);
      },
    );

    testWidgets('a photo showing the scanned barcode covers the barcode step', (
      tester,
    ) async {
      final backend = _Backend(authenticatedUserId: _userId);
      await tester.pumpWidget(
        _harness(
          backend: backend,
          readPhotoText: (photo) async => photo.categories.contains(facts)
              ? 'Supplement Facts\nServing Size 1 Capsule\n0 50428 38139 7'
              : '',
        ),
      );
      await tapKey(tester, 'missing-product-start');
      await tapKey(tester, 'missing-product-add-supplement_facts');
      expect(
        find.textContaining('Barcode found in this photo'),
        findsOneWidget,
      );

      // No Other Ingredients heading was detected on this panel either, so
      // the assumption already answered the panel question — no question,
      // straight past it.
      await tapKey(tester, 'missing-product-next');
      // No separate barcode photo is asked for.
      expect(_stepTitle(tester), 'Review & submit');
      await submitFromReview(tester);

      expect(backend.manifest, hasLength(2));
      expect(
        backend.manifest[1]['categories'],
        unorderedEquals([
          'supplement_facts',
          'ingredient_disclosure',
          'barcode',
        ]),
      );
    });

    testWidgets('the barcode photo itself gets no "barcode found" note', (
      tester,
    ) async {
      final backend = _Backend(authenticatedUserId: _userId);
      await tester.pumpWidget(
        _harness(
          backend: backend,
          readPhotoText: (photo) async =>
              photo.categories.contains(
                ProductSubmissionEvidenceCategory.barcode,
              )
              ? '0 50428 38139 7'
              : '',
        ),
      );
      await tapKey(tester, 'missing-product-start');
      await tapKey(tester, 'missing-product-add-supplement_facts');
      await tapKey(tester, 'missing-product-facts-combined');
      await tapKey(tester, 'missing-product-add-barcode');
      expect(_stepTitle(tester), 'Review & submit');
      expect(find.textContaining('Barcode found'), findsNothing);
    });

    testWidgets('a photo showing a different barcode is questioned', (
      tester,
    ) async {
      final backend = _Backend(authenticatedUserId: _userId);
      await tester.pumpWidget(
        _harness(
          backend: backend,
          readPhotoText: (photo) async => '0 36000 29145 2',
        ),
      );
      await tapKey(tester, 'missing-product-start');
      expect(find.text('A different barcode?'), findsOneWidget);
      expect(find.textContaining('036000291452'), findsOneWidget);
      await tapKey(tester, 'missing-product-hint-retake');
      expect(find.text('Front of the package'), findsOneWidget);
      expect(find.byTooltip('Remove photo'), findsNothing);

      await tapKey(tester, 'missing-product-add-front_identity');
      await tapKey(tester, 'missing-product-hint-keep');
      expect(find.text('Supplement Facts'), findsOneWidget);
    });

    testWidgets('a Facts photo taken as the front can be moved to Facts', (
      tester,
    ) async {
      final backend = _Backend(authenticatedUserId: _userId);
      var reads = 0;
      await tester.pumpWidget(
        _harness(
          backend: backend,
          readPhotoText: (photo) async =>
              reads++ == 0 ? 'Supplement Facts\nServing Size 2 Tablets' : '',
        ),
      );
      await tapKey(tester, 'missing-product-start');
      expect(
        find.text('This looks like the Supplement Facts panel'),
        findsOneWidget,
      );
      await tapKey(tester, 'missing-product-hint-move-facts');

      // Still asking for the front; the shot was kept where it belongs.
      expect(find.text('Front of the package'), findsOneWidget);
      expect(
        find.textContaining('Saved as your Supplement Facts photo'),
        findsOneWidget,
      );
      await tapKey(tester, 'missing-product-add-front_identity');
      // Facts already has its photo, and with no Other Ingredients heading
      // on it, the assumption already answered that question too — the
      // flow moves straight past Facts to Barcode instead of parking the
      // user on a step that already has everything it needs.
      expect(_stepTitle(tester), 'Barcode');
      await tapKey(tester, 'missing-product-add-barcode');
      await submitFromReview(tester);

      expect(
        backend.manifest[0]['categories'],
        unorderedEquals(['supplement_facts', 'ingredient_disclosure']),
      );
    });

    testWidgets('the photo is kept when the text reader fails', (tester) async {
      final backend = _Backend(authenticatedUserId: _userId);
      await tester.pumpWidget(
        _harness(
          backend: backend,
          readPhotoText: (_) async => throw StateError('no recognizer'),
        ),
      );
      await tapKey(tester, 'missing-product-start');
      expect(find.text('Supplement Facts'), findsOneWidget);
    });
  });

  testWidgets('a cancelled camera leaves Start on the front step, and the '
      'checklist shows what is covered and jumps to a panel', (tester) async {
    final semantics = tester.ensureSemantics();
    final backend = _Backend(authenticatedUserId: _userId);
    var picks = 0;
    await tester.pumpWidget(
      _harness(
        backend: backend,
        // The first camera session is cancelled.
        pickPhoto: (tags) async => picks++ == 0 ? null : _photo(tags),
      ),
    );
    await tester.tap(find.byKey(const Key('missing-product-start')));
    await tester.pumpAndSettle();
    // Cancelling lands on the front step with its example — not back on the
    // intro, and with nothing to continue with.
    expect(_stepTitle(tester), 'Front of the package');
    expect(find.bySemanticsLabel('Front: still needed'), findsOneWidget);
    expect(find.byKey(const Key('missing-product-next')), findsNothing);

    await tester.tap(
      find.byKey(const Key('missing-product-add-front_identity')),
    );
    await tester.pumpAndSettle();
    expect(_stepTitle(tester), 'Supplement Facts');
    expect(find.bySemanticsLabel('Front: done'), findsOneWidget);
    expect(find.bySemanticsLabel('Facts: still needed'), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('missing-product-checklist-front_identity')),
    );
    await tester.pumpAndSettle();
    expect(_stepTitle(tester), 'Front of the package');
    semantics.dispose();
  });

  group('several photos from the library', () {
    const front = ProductSubmissionEvidenceCategory.frontIdentity;

    bool selected(WidgetTester tester, String key) =>
        tester.widget<FilterChip>(find.byKey(Key(key))).selected;

    testWidgets('are sorted by what their printed text shows', (tester) async {
      final photos = [
        _photo({front}),
        _photo({front}),
        _photo({front}),
      ];
      final text = {
        photos[0].photoId:
            'Supplement Facts\nServing Size 1 Capsule\n'
            'Other Ingredients: cellulose\n0 50428 38139 7',
        photos[1].photoId: 'NATURE BRAND\nVitamin D3',
        photos[2].photoId:
            'Directions: take one daily. Warning: keep out '
            'of reach of children.',
      };
      int? askedFor;
      final backend = _Backend(authenticatedUserId: _userId);
      await tester.pumpWidget(
        _harness(
          backend: backend,
          readPhotoText: (photo) async => text[photo.photoId] ?? '',
          pickPhotosFromLibrary: (limit) async {
            askedFor = limit;
            return (photos: photos, unreadable: 0);
          },
        ),
      );
      await tester.tap(find.byKey(const Key('missing-product-start-library')));
      await tester.pumpAndSettle();

      expect(askedFor, ProductSubmissionPhoto.maxPerSubmission);
      expect(find.text('Which panel is each photo?'), findsOneWidget);
      expect(
        selected(tester, 'missing-product-sort-0-supplement_facts'),
        isTrue,
      );
      expect(
        selected(tester, 'missing-product-sort-0-ingredient_disclosure'),
        isTrue,
      );
      expect(selected(tester, 'missing-product-sort-0-barcode'), isTrue);
      expect(
        selected(tester, 'missing-product-sort-1-front_identity'),
        isFalse,
      );
      expect(
        selected(tester, 'missing-product-sort-2-directions_warnings'),
        isTrue,
      );
      // A photo nobody has named yet cannot be added.
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('missing-product-sort-done')),
            )
            .onPressed,
        isNull,
      );

      await tester.tap(
        find.byKey(const Key('missing-product-sort-1-front_identity')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('missing-product-sort-done')));
      await tester.pumpAndSettle();

      // Every required panel is covered: straight to review.
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
      await _scrollToConsent(tester);
      await tester.tap(find.byKey(const Key('missing-product-consent')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('missing-product-submit')));
      await tester.pumpAndSettle();

      expect(backend.persistedCueFlag, isTrue);
      expect(backend.manifest, hasLength(3));
      expect(
        backend.manifest[0]['categories'],
        unorderedEquals([
          'supplement_facts',
          'ingredient_disclosure',
          'barcode',
        ]),
      );
      expect(backend.manifest[1]['categories'], ['front_identity']);
      expect(backend.manifest[2]['categories'], ['directions_warnings']);
    });

    testWidgets('unusable photos are skipped, counted, or left out', (
      tester,
    ) async {
      final kept = _photo({front});
      final tiny = _photo({front});
      final unnamed = _photo({front});
      final duplicate = ProductSubmissionPhoto(
        photoId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
        categories: const {front},
        bytes: kept.bytes,
        contentType: 'image/jpeg',
      );
      final backend = _Backend(authenticatedUserId: _userId);
      await tester.pumpWidget(
        _harness(
          backend: backend,
          readPhotoText: (photo) async =>
              photo.photoId == kept.photoId ? 'Supplement Facts' : '',
          qualityGate: (photo) async => photo.photoId == tiny.photoId
              ? const PhotoQualityResult(
                  verdict: PhotoQualityVerdict.tooSmall,
                  shortSide: 300,
                  blurScore: 500,
                )
              : _okQuality,
          pickPhotosFromLibrary: (_) async =>
              (photos: [kept, tiny, duplicate, unnamed], unreadable: 1),
        ),
      );
      await tester.tap(find.byKey(const Key('missing-product-start-library')));
      await tester.pumpAndSettle();

      // The tiny and duplicate photos never reach the sort sheet.
      expect(
        find.byKey(const Key('missing-product-sort-1-remove')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('missing-product-sort-2-remove')),
        findsNothing,
      );
      await tester.tap(find.byKey(const Key('missing-product-sort-1-remove')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('missing-product-sort-done')));
      await tester.pumpAndSettle();

      // The front is still missing, so capture asks for it.
      expect(find.text('Front of the package'), findsOneWidget);
      expect(find.textContaining('3 photos couldn’t be used'), findsOneWidget);
    });

    testWidgets('photos beyond the submission limit are counted, not added', (
      tester,
    ) async {
      final photos = [
        for (var i = 0; i < ProductSubmissionPhoto.maxPerSubmission + 2; i++)
          _photo({front}),
      ];
      final backend = _Backend(authenticatedUserId: _userId);
      await tester.pumpWidget(
        _harness(
          backend: backend,
          readPhotoText: (_) async => 'Supplement Facts',
          // A picker that ignores the limit it was given.
          pickPhotosFromLibrary: (_) async => (photos: photos, unreadable: 0),
        ),
      );
      await tester.tap(find.byKey(const Key('missing-product-start-library')));
      await tester.pumpAndSettle();
      expect(
        find.text('Add ${ProductSubmissionPhoto.maxPerSubmission} photos'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('missing-product-sort-done')));
      await tester.pumpAndSettle();
      expect(find.textContaining('2 photos couldn’t be used'), findsOneWidget);
    });

    testWidgets('an empty pick falls back to one photo at a time', (
      tester,
    ) async {
      final backend = _Backend(authenticatedUserId: _userId);
      await tester.pumpWidget(
        _harness(
          backend: backend,
          pickPhotosFromLibrary: (_) async =>
              (photos: const <ProductSubmissionPhoto>[], unreadable: 0),
        ),
      );
      await tester.tap(find.byKey(const Key('missing-product-start-library')));
      await tester.pumpAndSettle();
      expect(find.text('Front of the package'), findsOneWidget);
      expect(find.text('Choose a photo'), findsOneWidget);
    });
  });

  testWidgets('skipping ahead still comes back for a missing panel', (
    tester,
  ) async {
    final backend = _Backend(authenticatedUserId: _userId);
    await tester.pumpWidget(_harness(backend: backend));
    await tester.tap(find.byKey(const Key('missing-product-start')));
    await tester.pumpAndSettle();

    // From Facts, straight to the barcode; Facts is still empty.
    await tester.tap(
      find.byKey(const Key('missing-product-checklist-barcode')),
    );
    await tester.pumpAndSettle();
    expect(_stepTitle(tester), 'Barcode');
    await tester.tap(find.byKey(const Key('missing-product-add-barcode')));
    await tester.pumpAndSettle();

    // Not a review the user cannot submit: back for the missing panel.
    expect(_stepTitle(tester), 'Supplement Facts');
  });

  group('requested retake', () {
    const front = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbb01';
    const facts = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbb02';
    const ingredients = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbb03';
    const barcode = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbb04';

    ProductSubmissionRetake factsRetake({Set<String> digests = const {}}) =>
        ProductSubmissionRetake.plan(
          submissionId: _submissionId,
          upc: _upc,
          fromRevision: 1,
          reason: ProductSubmissionResolutionCode.photoQuality,
          requestedPanels: {ProductSubmissionEvidenceCategory.supplementFacts},
          earlierPhotoDigests: digests,
          membership: [
            (
              photoId: front,
              categories: {ProductSubmissionEvidenceCategory.frontIdentity},
            ),
            (
              photoId: facts,
              categories: {ProductSubmissionEvidenceCategory.supplementFacts},
            ),
            (
              photoId: ingredients,
              categories: {
                ProductSubmissionEvidenceCategory.ingredientDisclosure,
              },
            ),
            (
              photoId: barcode,
              categories: {ProductSubmissionEvidenceCategory.barcode},
            ),
          ],
        );

    Future<void> submitFromReview(WidgetTester tester) async {
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
      await _scrollToConsent(tester);
      await tester.tap(find.byKey(const Key('missing-product-consent')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('missing-product-submit')));
      await tester.pumpAndSettle();
    }

    testWidgets('asks only for the requested panel and keeps the rest', (
      tester,
    ) async {
      final backend = _Backend(authenticatedUserId: _userId);
      await tester.pumpWidget(
        _harness(backend: backend, retake: factsRetake()),
      );
      await tester.pumpAndSettle();

      expect(find.text('New photos needed'), findsOneWidget);
      expect(
        find.textContaining('Not found in this device’s catalog'),
        findsNothing,
      );
      expect(
        find.textContaining('new photo of the Supplement Facts panel'),
        findsOneWidget,
      );
      expect(find.textContaining('Your other photos are kept'), findsOneWidget);
      // Start names the one panel asked for.
      expect(find.text('Start with Supplement Facts'), findsOneWidget);

      await tester.tap(find.byKey(const Key('missing-product-start')));
      await tester.pumpAndSettle();
      // Straight to the camera for that panel; the kept front counts as
      // taken.
      expect(_stepTitle(tester), 'Supplement Facts');
      expect(find.byTooltip('Remove photo'), findsOneWidget);
      expect(backend.intakeCalls, 0, reason: 'the submission already exists');

      // The ingredient list is kept, so there is nothing to ask about it,
      // and the kept barcode is not asked for again.
      expect(
        find.byKey(const Key('missing-product-facts-combined')),
        findsNothing,
      );
      await tester.tap(find.byKey(const Key('missing-product-next')));
      await tester.pumpAndSettle();
      expect(_stepTitle(tester), 'Review & submit');

      await submitFromReview(tester);

      expect(find.text('Thanks — it’s in review'), findsOneWidget);
      expect(backend.openPayloads.single['p_submission_id'], _submissionId);
      expect(backend.openPayloads.single['p_keep_photo_ids'], [
        front,
        ingredients,
        barcode,
      ]);
      expect(backend.persistedKind, isNull, reason: 'no second submission');
      expect(backend.manifest.single['categories'], ['supplement_facts']);
    });

    testWidgets('refuses a photo the reviewer already has', (tester) async {
      final repeat = _photo({
        ProductSubmissionEvidenceCategory.supplementFacts,
      });
      final backend = _Backend(authenticatedUserId: _userId);
      await tester.pumpWidget(
        _harness(
          backend: backend,
          retake: factsRetake(digests: {repeat.contentSha256}),
          pickPhoto: (_) async => repeat,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('missing-product-start')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('missing-product-add-supplement_facts')),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('That exact photo is already in this submission.'),
        findsOneWidget,
      );
      expect(find.byTooltip('Remove photo'), findsNothing);
    });

    testWidgets('an unfinished retake resumes under its own submission', (
      tester,
    ) async {
      final store = _MemoryDraftStorage();
      await store.save(
        userId: _userId,
        submissionId: _submissionId,
        upc: _upc,
        photos: [
          _photo({ProductSubmissionEvidenceCategory.supplementFacts}),
        ],
        consentVersion: productSubmissionConsentVersion,
        evidenceRevision: 2,
      );
      final backend = _Backend(authenticatedUserId: _userId);

      // A new capture of the same barcode never adopts it.
      await tester.pumpWidget(_harness(backend: backend, draftStore: store));
      await tester.pumpAndSettle();
      expect(find.text('Finish your photos?'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        _harness(backend: backend, draftStore: store, retake: factsRetake()),
      );
      await tester.pumpAndSettle();
      expect(find.text('Finish your photos?'), findsOneWidget);
      await tester.tap(find.text('Finish sending'));
      await tester.pumpAndSettle();
      expect(find.text('Review & submit'), findsOneWidget);

      await submitFromReview(tester);

      expect(find.text('Thanks — it’s in review'), findsOneWidget);
      expect(store.captures, isEmpty, reason: 'the receipt retires the draft');
    });
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
      evidenceRevision: evidenceRevision,
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
      if (record.retakeOfRevision != null) continue;
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
  Future<Map<String, Object?>> fetchOwnEvidence({
    required String submissionId,
  }) => throw UnimplementedError();

  final List<Map<String, Object?>> openPayloads = [];

  @override
  Future<int> openEvidenceRevision({
    required Map<String, Object?> payload,
  }) async {
    openPayloads.add(payload);
    return (payload['p_expected_revision']! as int) + 1;
  }

  @override
  Future<bool> finalizeSubmission({
    required String functionName,
    required String submissionId,
    int? expectedRevision,
  }) async {
    final expected = manifest.map(
      (photo) => '$_userId/$submissionId/${photo['photo_id'] as String}',
    );
    // A retake revision has nothing new until its photos are recorded.
    if (expectedRevision != null && manifest.isEmpty) return false;
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
