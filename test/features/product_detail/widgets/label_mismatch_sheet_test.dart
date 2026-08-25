import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/label_match_section.dart';
import 'package:pharmaguide/features/product_detail/widgets/label_mismatch_sheet.dart';
import 'package:pharmaguide/services/product_submission_photo_service.dart';
import 'package:pharmaguide/services/product_submission_service.dart';

const _userId = '3f276b64-0836-4bea-9453-1c8db4d1f8dd';
const _reportId = '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a11';
const _fingerprint =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

void main() {
  group('photo picker boundary', () {
    test(
      'accepts an exact 15 MiB supported image then stores sanitized JPEG',
      () async {
        final photo = await buildProductSubmissionPhotoFromFile(
          file: XFile.fromData(
            Uint8List(ProductSubmissionPhoto.maxByteSize),
            name: 'facts.JPG',
            mimeType: 'image/jpg; charset=binary',
          ),
          categories: const {ProductSubmissionEvidenceCategory.supplementFacts},
          sanitizer: (_) async => Uint8List.fromList([9, 8, 7]),
        );

        expect(photo.categories, {
          ProductSubmissionEvidenceCategory.supplementFacts,
        });
        expect(photo.contentType, 'image/jpeg');
        expect(photo.bytes, [9, 8, 7]);
      },
    );

    test('rejects a source larger than 15 MiB before sanitization', () async {
      var sanitizerCalled = false;

      await _expectPhotoValidation(
        buildProductSubmissionPhotoFromFile(
          file: XFile.fromData(
            Uint8List(ProductSubmissionPhoto.maxByteSize + 1),
            name: 'facts.jpg',
            mimeType: 'image/jpeg',
          ),
          categories: const {ProductSubmissionEvidenceCategory.supplementFacts},
          sanitizer: (_) async {
            sanitizerCalled = true;
            return Uint8List.fromList([1]);
          },
        ),
        ProductSubmissionValidationFailure.photoTooLarge,
      );
      expect(sanitizerCalled, isFalse);
    });

    test(
      'rejects an explicitly unsupported MIME despite an image extension',
      () async {
        var sanitizerCalled = false;

        await _expectPhotoValidation(
          buildProductSubmissionPhotoFromFile(
            file: XFile.fromData(
              Uint8List.fromList([1]),
              name: 'not-an-image.jpg',
              mimeType: 'application/pdf',
            ),
            categories: const {ProductSubmissionEvidenceCategory.frontIdentity},
            sanitizer: (_) async {
              sanitizerCalled = true;
              return Uint8List.fromList([1]);
            },
          ),
          ProductSubmissionValidationFailure.unsupportedPhotoContentType,
        );
        expect(sanitizerCalled, isFalse);
      },
    );

    test('uses an image extension only when MIME is absent', () async {
      final photo = await buildProductSubmissionPhotoFromFile(
        file: XFile.fromData(Uint8List.fromList([1]), path: 'facts.HeIc'),
        categories: const {ProductSubmissionEvidenceCategory.supplementFacts},
        sanitizer: (_) async => Uint8List.fromList([2]),
      );

      expect(photo.contentType, 'image/jpeg');
      expect(photo.bytes, [2]);
    });

    test('rejects empty images and failed metadata sanitization', () async {
      await _expectPhotoValidation(
        buildProductSubmissionPhotoFromFile(
          file: XFile.fromData(
            Uint8List(0),
            name: 'empty.png',
            mimeType: 'image/png',
          ),
          categories: const {ProductSubmissionEvidenceCategory.frontIdentity},
          sanitizer: (_) async => Uint8List.fromList([1]),
        ),
        ProductSubmissionValidationFailure.emptyPhoto,
      );
      await _expectPhotoValidation(
        buildProductSubmissionPhotoFromFile(
          file: XFile.fromData(
            Uint8List.fromList([1]),
            name: 'front.png',
            mimeType: 'image/png',
          ),
          categories: const {ProductSubmissionEvidenceCategory.frontIdentity},
          sanitizer: (_) async => Uint8List(0),
        ),
        ProductSubmissionValidationFailure.photoSanitizationFailed,
      );
    });
  });

  testWidgets('guest follows the exact sign-in route and cannot submit', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: TextButton(
              onPressed: () => showLabelMismatchSheet(
                context,
                product: _metadata(),
                isAuthenticated: false,
              ),
              child: const Text('Open report sheet'),
            ),
          ),
        ),
        GoRoute(
          path: Routes.authInvitation,
          builder: (_, _) =>
              const Scaffold(body: Text('Auth invitation route')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.tap(find.text('Open report sheet'));
    await tester.pumpAndSettle();

    expect(find.text('Sign in to report a mismatch'), findsNWidgets(2));
    expect(
      find.text(
        'Reports are tied to your account so your photos stay private and '
        'reviewers can investigate the correct catalog record.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('label-mismatch-submit')), findsNothing);

    await tester.tap(
      find.widgetWithText(FilledButton, 'Sign in to report a mismatch'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Auth invitation route'), findsOneWidget);
  });

  testWidgets(
    'signed-in sheet exposes only closed categories and three named slots',
    (tester) async {
      await _setLargePhone(tester);
      final backend = _FakeBackend();

      await tester.pumpWidget(
        _sheetHarness(backend: backend, pickPhoto: (_, _) async => null),
      );

      for (final label in const [
        'Product identity',
        'Ingredient missing from the app',
        'Ingredient shown in the app but not on the label',
        'Amount or unit',
        'Form or parenthetical label detail',
        'Serving size or directions',
        'Other Ingredients list',
        'Catalog version or product status',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.byType(CheckboxListTile), findsNWidgets(9));

      for (final slot in const [
        'Front of bottle',
        'Supplement Facts',
        'Other Ingredients',
      ]) {
        expect(find.text(slot), findsOneWidget);
        expect(
          find.bySemanticsLabel('Take $slot photo with camera'),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel('Choose $slot photo from library'),
          findsOneWidget,
        );
      }

      expect(
        find.text(
          'Your account identifier, this product’s catalog identifiers '
          '(including UPC when available), the mismatch categories you '
          'select, and selected product-label photos are sent. We remove '
          'embedded photo metadata before upload. Your profile, medications, '
          'conditions, allergies, and stack stay on this device.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'I consent to send this account-linked product report, its catalog '
          'identifiers, selected categories, and selected label photos to '
          'PharmaGuide for review.',
        ),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(TextFormField), findsNothing);
      expect(find.byType(EditableText), findsNothing);
      expect(backend.operations, isEmpty);
    },
  );

  testWidgets('photo source is explicit and submit is never automatic', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _setLargePhone(tester);
    final backend = _FakeBackend();
    final pickerCalls = <(ProductSubmissionEvidenceCategory, ImageSource)>[];

    await tester.pumpWidget(
      _sheetHarness(
        backend: backend,
        pickPhoto: (category, source) async {
          pickerCalls.add((category, source));
          return _photo(category);
        },
      ),
    );

    await tester.tap(
      find.bySemanticsLabel('Take Front of bottle photo with camera'),
    );
    await tester.pump();

    expect(pickerCalls, [
      (ProductSubmissionEvidenceCategory.frontIdentity, ImageSource.camera),
    ]);
    expect(find.text('Photo selected'), findsOneWidget);
    expect(
      find.byKey(const Key('label-mismatch-photo-front_identity-preview')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Selected Front of bottle photo preview'),
      findsOneWidget,
    );
    expect(backend.operations, isEmpty);

    await tester.tap(
      find.byKey(const Key('label-mismatch-category-form_or_parenthetical')),
    );
    await tester.tap(find.byKey(const Key('label-mismatch-consent')));
    await tester.pump();

    expect(backend.operations, isEmpty);
    await tester.tap(find.byKey(const Key('label-mismatch-submit')));
    await tester.pumpAndSettle();

    expect(backend.operations, [
      'persist',
      'finalize',
      'upload:$_frontPhotoId',
      'finalize',
    ]);
    expect(find.text('Report sent'), findsOneWidget);
    expect(
      find.text(
        'Thanks. We’ll review the catalog record. Your report does not '
        'change the catalog automatically.',
      ),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('announces upload and save progress before success', (
    tester,
  ) async {
    await _setLargePhone(tester);
    final uploadGate = Completer<void>();
    final persistGate = Completer<void>();
    final backend = _FakeBackend(
      uploadGate: uploadGate,
      persistGate: persistGate,
    );

    await tester.pumpWidget(
      _sheetHarness(
        backend: backend,
        pickPhoto: (category, _) async => _photo(category),
      ),
    );
    await tester.tap(
      find.bySemanticsLabel('Choose Supplement Facts photo from library'),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const Key('label-mismatch-category-amount_or_unit')),
    );
    await tester.tap(find.byKey(const Key('label-mismatch-consent')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('label-mismatch-submit')));
    await tester.pump();

    expect(find.text('Saving report…'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    persistGate.complete();
    await tester.pump();
    expect(find.text('Uploading selected photos…'), findsOneWidget);

    uploadGate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Report sent'), findsOneWidget);
  });

  testWidgets('failed save locks inputs and retries the same draft', (
    tester,
  ) async {
    await _setLargePhone(tester);
    final backend = _FakeBackend(persistFailuresRemaining: 1);

    await tester.pumpWidget(
      _sheetHarness(
        backend: backend,
        pickPhoto: (category, _) async => _photo(category),
      ),
    );
    await tester.tap(
      find.bySemanticsLabel('Take Front of bottle photo with camera'),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const Key('label-mismatch-category-product_identity')),
    );
    await tester.tap(find.byKey(const Key('label-mismatch-consent')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('label-mismatch-submit')));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'We couldn’t confirm the report was saved. Retry this same report. '
        'Nothing changes in the catalog automatically.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('label-mismatch-retry')), findsOneWidget);
    expect(
      tester
          .widget<CheckboxListTile>(
            find.byKey(const Key('label-mismatch-category-product_identity')),
          )
          .onChanged,
      isNull,
    );
    expect(
      tester
          .widget<CheckboxListTile>(
            find.byKey(const Key('label-mismatch-consent')),
          )
          .onChanged,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.descendant(
              of: find.byKey(
                const Key('label-mismatch-photo-front_identity-camera'),
              ),
              matching: find.byType(OutlinedButton),
            ),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const Key('label-mismatch-photo-front_identity-remove')),
          )
          .onPressed,
      isNull,
    );

    await tester.tap(find.byKey(const Key('label-mismatch-retry')));
    await tester.pumpAndSettle();

    expect(backend.reportIds, [_reportId, _reportId]);
    expect(find.text('Report sent'), findsOneWidget);
  });

  testWidgets('photo sanitization failure is visible and blocks the slot', (
    tester,
  ) async {
    await _setLargePhone(tester);
    final backend = _FakeBackend();
    await tester.pumpWidget(
      _sheetHarness(
        backend: backend,
        pickPhoto: (_, _) async =>
            throw const ProductSubmissionValidationException(
              ProductSubmissionValidationFailure.photoSanitizationFailed,
            ),
      ),
    );

    await tester.tap(
      find.bySemanticsLabel('Choose Supplement Facts photo from library'),
    );
    await tester.pump();

    expect(
      find.text(
        'We couldn’t remove embedded photo metadata. Choose another image.',
      ),
      findsOneWidget,
    );
    expect(backend.operations, isEmpty);
  });

  testWidgets('normal phone remains usable at 200 percent text scaling', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    final backend = _FakeBackend();

    await tester.pumpWidget(
      _sheetHarness(
        backend: backend,
        pickPhoto: (_, _) async => null,
        textScaler: const TextScaler.linear(2),
      ),
    );

    final consent = find.byKey(const Key('label-mismatch-consent'));
    await tester.scrollUntilVisible(
      consent,
      500,
      scrollable: find.byType(Scrollable),
    );
    await tester.pumpAndSettle();
    expect(consent, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selected preview fits a narrow phone at 200 percent text', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    final backend = _FakeBackend();

    await tester.pumpWidget(
      _sheetHarness(
        backend: backend,
        pickPhoto: (category, _) async => _photo(category),
        textScaler: const TextScaler.linear(2),
      ),
    );

    final camera = find.bySemanticsLabel(
      'Take Front of bottle photo with camera',
    );
    await tester.scrollUntilVisible(
      camera,
      400,
      scrollable: find.byType(Scrollable),
    );
    await tester.tap(camera);
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsLabel('Selected Front of bottle photo preview'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('catalog CTA is accessible and passes exact record lineage', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    LabelMismatchProductMetadata? captured;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: buildLabelMatchSection(
              labelRecord: _labelRecord(),
              dsldId: '999',
              upc: '050428381397',
              onOpenSourceLabel: (_) async {},
              onReportMismatch: (product) async => captured = product,
            ),
          ),
        ),
      ),
    );

    final action = find.bySemanticsLabel(
      'Doesn’t match your bottle? Report a catalog mismatch',
    );
    expect(action, findsOneWidget);
    expect(find.text('Doesn’t match your bottle?'), findsOneWidget);
    await tester.ensureVisible(action);
    await tester.pumpAndSettle();
    await tester.tap(action);
    await tester.pump();

    expect(captured?.dsldId, '999');
    expect(captured?.upc, '050428381397');
    expect(captured?.sourceRecordId, '999');
    expect(captured?.catalogSourceVersion, '7');
    expect(captured?.formulaFingerprint, _fingerprint);
    expect(find.byKey(const Key('source-label-action')), findsOneWidget);
    semantics.dispose();
  });
}

Future<void> _setLargePhone(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(800, 2200);
  addTearDown(tester.view.reset);
}

Widget _sheetHarness({
  required _FakeBackend backend,
  required PickProductSubmissionPhoto pickPhoto,
  TextScaler? textScaler,
}) {
  return MaterialApp(
    builder: textScaler == null
        ? null
        : (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: textScaler),
            child: child!,
          ),
    home: Scaffold(
      body: LabelMismatchSheet(
        product: _metadata(),
        isAuthenticated: true,
        reportService: ProductSubmissionService(backend: backend),
        pickPhoto: pickPhoto,
        reportIdFactory: () => _reportId,
        onSignIn: () async {},
      ),
    ),
  );
}

Future<void> _expectPhotoValidation(
  Future<ProductSubmissionPhoto> future,
  ProductSubmissionValidationFailure reason,
) {
  return expectLater(
    future,
    throwsA(
      isA<ProductSubmissionValidationException>().having(
        (error) => error.reason,
        'reason',
        reason,
      ),
    ),
  );
}

LabelMismatchProductMetadata _metadata() => LabelMismatchProductMetadata(
  dsldId: '999',
  upc: '050428381397',
  sourceRecordId: '999',
  catalogSourceVersion: '7',
  formulaFingerprint: _fingerprint,
);

const _frontPhotoId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1';

ProductSubmissionPhoto _photo(ProductSubmissionEvidenceCategory category) =>
    ProductSubmissionPhoto(
      photoId: _frontPhotoId,
      categories: {category},
      bytes: Uint8List.fromList([1, 2, 3]),
      contentType: 'image/jpeg',
    );

Map<String, dynamic> _labelRecord() {
  const fields = <String, String>{
    'source_name': 'NIH DSLD',
    'source_record_id': '999',
    'catalog_version': '7',
    'formula_fingerprint': _fingerprint,
    'source_date': '2024-01-02',
    'source_updated_date': '2025-03-04T10:11:12Z',
    'product_status': 'active',
    'label_source_url': 'https://example.test/labels/999.png',
    'lineage_key': 'dsld:999',
  };
  return {
    ...fields,
    'metadata_status': 'available',
    'metadata_issues': const <String>[],
    'field_statuses': {for (final key in fields.keys) key: 'available'},
    'formula_history': const <Map<String, dynamic>>[],
    'history_status': 'unavailable',
  };
}

class _FakeBackend implements ProductSubmissionBackend {
  @override
  String? get authenticatedUserId => _userId;
  int persistFailuresRemaining;
  final Completer<void>? uploadGate;
  final Completer<void>? persistGate;

  final operations = <String>[];
  final reportIds = <String>[];
  final Set<String> successfulObjectPaths = {};
  List<Map<String, Object?>> photoRows = const [];

  _FakeBackend({
    this.persistFailuresRemaining = 0,
    this.uploadGate,
    this.persistGate,
  });

  @override
  Future<void> uploadPhoto({
    required String bucket,
    required String objectPath,
    required Uint8List bytes,
    required String contentType,
  }) async {
    operations.add('upload:${objectPath.split('/').last}');
    await uploadGate?.future;
    successfulObjectPaths.add(objectPath);
  }

  @override
  Future<void> persistSubmission({
    required String functionName,
    required Map<String, Object?> payload,
  }) async {
    operations.add('persist');
    reportIds.add(payload['p_submission_id']! as String);
    photoRows = payload['p_photos']! as List<Map<String, Object?>>;
    if (persistFailuresRemaining > 0) {
      persistFailuresRemaining--;
      throw StateError('persist failed');
    }
    await persistGate?.future;
  }

  @override
  Future<bool> finalizeSubmission({
    required String functionName,
    required String submissionId,
  }) async {
    operations.add('finalize');
    return photoRows
        .map((row) => '$_userId/$submissionId/${row['photo_id']}')
        .every(successfulObjectPaths.contains);
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
