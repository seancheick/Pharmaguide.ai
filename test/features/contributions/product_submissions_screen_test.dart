import 'dart:async';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/contributions/providers/product_submission_providers.dart';
import 'package:pharmaguide/features/contributions/product_submissions_screen.dart';
import 'package:pharmaguide/features/product_detail/widgets/label_mismatch_sheet.dart';
import 'package:pharmaguide/features/scanner/missing_product_submission_sheet.dart';
import 'package:pharmaguide/services/gtin.dart';
import 'package:pharmaguide/services/product_submission_draft_store.dart';
import 'package:pharmaguide/services/product_submission_service.dart';

Widget _harness(
  List<Map<String, Object?>> rows, {
  CoreDatabase? db,
  Future<void> Function(ProductSubmissionSummary status)? onResubmit,
  Future<void> Function(ProductSubmissionSummary status)? onHide,
  Future<void> Function(ProductSubmissionSummary status)? onRetake,
  List<PendingProductSubmission> pendingDrafts = const [],
  Future<int> Function()? points,
  _Backend? backend,
  GoRouter? router,
}) {
  final database = db ?? CoreDatabase.memory();
  if (db == null) addTearDown(database.close);
  return ProviderScope(
    overrides: [
      productSubmissionServiceProvider.overrideWithValue(
        ProductSubmissionService(backend: backend ?? _Backend(rows)),
      ),
      coreDatabaseProvider.overrideWithValue(database),
      pendingProductSubmissionDraftsProvider.overrideWith(
        (ref) async => pendingDrafts,
      ),
      // The ledger is server state; the screen only displays it.
      contributionPointsProvider.overrideWith(
        (ref) => points == null ? Future.value(0) : points(),
      ),
    ],
    child: router != null
        ? MaterialApp.router(routerConfig: router)
        : MaterialApp(
            home: ProductSubmissionsScreen(
              onResubmit: onResubmit,
              onHide: onHide,
              onRetake: onRetake,
            ),
          ),
  );
}

void main() {
  testWidgets('known UPC offers the catalog product before photos', (
    tester,
  ) async {
    final db = CoreDatabase.memory();
    addTearDown(db.close);
    await db
        .into(db.productsCore)
        .insert(
          ProductsCoreCompanion.insert(
            dsldId: '278454',
            productName: 'Catalog supplement',
            exportVersion: 'test',
            exportedAt: '2026-09-12T00:00:00Z',
            brandName: const Value('Catalog brand'),
            upcSku: const Value('030772032565'),
          ),
        );
    await tester.pumpWidget(_harness(const [], db: db));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('contributions-add-product')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('add-product-gtin-field')),
      '0030772032565',
    );
    await tester.tap(find.byKey(const Key('add-product-continue')));
    await tester.pumpAndSettle();
    expect(find.text('Catalog supplement'), findsOneWidget);
    expect(find.text('Catalog brand'), findsOneWidget);
    expect(find.text('View product'), findsOneWidget);
    expect(find.text('Report incorrect label'), findsOneWidget);
    expect(find.byKey(const Key('missing-product-start')), findsNothing);
  });

  for (final barcode in ['030772032565', '0030772032565', '00030772032565']) {
    testWidgets(
      'equivalent barcode $barcode opens the selected product route',
      (tester) async {
        final db = await _catalog();
        final router = GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => const ProductSubmissionsScreen(),
            ),
            GoRoute(
              path: '/product/:id',
              builder: (_, state) =>
                  Scaffold(body: Text('Product ${state.pathParameters['id']}')),
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(_harness(const [], db: db, router: router));
        await tester.pumpAndSettle();
        await _enterBarcode(tester, barcode);
        await tester.tap(find.text('View product'));
        await tester.pumpAndSettle();
        expect(find.text('Product 278454'), findsOneWidget);
        expect(find.byType(MissingProductSubmissionSheet), findsNothing);
      },
    );
  }

  testWidgets(
    'known product opens existing report with identity and fresh consent',
    (tester) async {
      final db = await _catalog();
      await tester.pumpWidget(_harness(const [], db: db));
      await tester.pumpAndSettle();
      await _enterBarcode(tester, '030772032565');
      await tester.tap(find.text('Report incorrect label'));
      await tester.pumpAndSettle();
      final sheet = tester.widget<LabelMismatchSheet>(
        find.byType(LabelMismatchSheet),
      );
      expect(sheet.product.dsldId, '278454');
      expect(sheet.product.upc, '030772032565');
      expect(sheet.resubmissionOf, isNull);
      expect(sheet.isAuthenticated, isTrue);
      await tester.scrollUntilVisible(
        find.byKey(const Key('label-mismatch-consent')),
        250,
        scrollable: find.byType(Scrollable).last,
      );
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const Key('label-mismatch-consent')),
            )
            .value,
        isFalse,
      );
    },
  );

  testWidgets('signing out before report uses existing sign-in gate', (
    tester,
  ) async {
    final db = await _catalog();
    final backend = _Backend([]);
    await tester.pumpWidget(_harness(const [], db: db, backend: backend));
    await tester.pumpAndSettle();
    await _enterBarcode(tester, '030772032565');
    backend.userId = null;
    await tester.tap(find.text('Report incorrect label'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<LabelMismatchSheet>(find.byType(LabelMismatchSheet))
          .isAuthenticated,
      isFalse,
    );
    expect(find.text('Sign in to report a mismatch'), findsWidgets);
    expect(find.byKey(const Key('label-mismatch-consent')), findsNothing);
  });

  testWidgets(
    'ambiguous unmatched answer permits comparison without missing capture',
    (tester) async {
      final db = await _catalog(ambiguous: true);
      await tester.pumpWidget(_harness(const [], db: db));
      await tester.pumpAndSettle();
      await _enterBarcode(tester, '030772032565');
      expect(find.text('Which bottle matches yours?'), findsOneWidget);
      await tester.tap(find.text('None of these match'));
      await tester.pumpAndSettle();
      expect(find.text('No bottle selected'), findsOneWidget);
      expect(find.text('Report incorrect label'), findsNothing);
      expect(find.byType(MissingProductSubmissionSheet), findsNothing);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text('No bottle selected'), findsNothing);
      await _enterBarcode(tester, '030772032565');
      await tester.tap(find.text('None of these match'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Compare labels'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Second bottle'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Report incorrect label'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<LabelMismatchSheet>(find.byType(LabelMismatchSheet))
            .product
            .dsldId,
        '278455',
      );
    },
  );

  testWidgets('ambiguous cancellation closes intake without a guessed target', (
    tester,
  ) async {
    final db = await _catalog(ambiguous: true);
    await tester.pumpWidget(_harness(const [], db: db));
    await tester.pumpAndSettle();
    await _enterBarcode(tester, '030772032565');
    Navigator.of(
      tester.element(find.text('Which bottle matches yours?')),
    ).pop();
    await tester.pumpAndSettle();

    expect(find.text('No bottle selected'), findsNothing);
    expect(find.text('Report incorrect label'), findsNothing);
    expect(find.byType(LabelMismatchSheet), findsNothing);
    expect(find.byType(MissingProductSubmissionSheet), findsNothing);
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const Key('contributions-add-product')),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('catalog failure is retryable and never a missing product', (
    tester,
  ) async {
    final db = _FailOnceDatabase();
    addTearDown(db.close);
    await _insertCatalogProduct(db);
    await tester.pumpWidget(_harness(const [], db: db));
    await tester.pumpAndSettle();
    await _enterBarcode(tester, '030772032565');
    expect(
      find.textContaining('Couldn’t check your installed catalog'),
      findsOneWidget,
    );
    expect(find.byType(MissingProductSubmissionSheet), findsNothing);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('This barcode is in your catalog'), findsOneWidget);
    expect(db.lookups, 2);
  });

  testWidgets('catalog Retry is harmless after contributions is popped', (
    tester,
  ) async {
    final db = _FailOnceDatabase();
    addTearDown(db.close);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('Home')),
        ),
        GoRoute(
          path: '/contributions',
          builder: (_, _) => const ProductSubmissionsScreen(),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(_harness(const [], db: db, router: router));
    await tester.pumpAndSettle();
    unawaited(router.push<void>('/contributions'));
    await tester.pumpAndSettle();
    await _enterBarcode(tester, '030772032565');
    expect(find.text('Retry'), findsOneWidget);

    router.pop();
    await tester.pumpAndSettle();
    expect(find.byType(ProductSubmissionsScreen), findsNothing);
    expect(find.text('Retry'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(db.lookups, 1);
    expect(find.text('Home'), findsOneWidget);
    expect(find.byType(MissingProductSubmissionSheet), findsNothing);
  });

  testWidgets('saved pending capture is checked without changing its draft', (
    tester,
  ) async {
    final db = await _catalog();
    final pending = _pending('030772032565');
    await tester.pumpWidget(
      _harness(const [], db: db, pendingDrafts: [pending]),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Finish sending'));
    await tester.pumpAndSettle();
    expect(find.text('This barcode is in your catalog'), findsOneWidget);
    expect(find.byType(MissingProductSubmissionSheet), findsNothing);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('3 photos ready to send'), findsOneWidget);
    expect(pending.submissionId, '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a20');
    expect(pending.resubmissionOf, '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a11');
  });

  testWidgets('no-match pending resume retains original lineage', (
    tester,
  ) async {
    final pending = _pending('030772032565');
    await tester.pumpWidget(_harness(const [], pendingDrafts: [pending]));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Finish sending'));
    await tester.pumpAndSettle();
    final sheet = tester.widget<MissingProductSubmissionSheet>(
      find.byType(MissingProductSubmissionSheet),
    );
    expect(sheet.upc, pending.upc);
    expect(sheet.resubmissionOf, pending.resubmissionOf);
  });

  for (final retake in [false, true]) {
    testWidgets(
      'known product guards ${retake ? 'retake' : 'rejected retry'} before evidence preparation',
      (tester) async {
        final db = await _catalog(upc: '050428381397');
        await tester.pumpWidget(
          _harness([
            {
              ..._row(
                id: '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a11',
                reviewStatus: retake ? 'under_review' : 'rejected',
              ),
              if (retake) ...{
                'evidence_revision': 1,
                'evidence_requested_revision': 1,
                'evidence_request_reason': 'label_unreadable',
                'evidence_request_panels': ['barcode'],
              } else
                'resolution_code': 'photo_quality',
            },
          ], db: db),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.text(retake ? 'Retake photos' : 'Try again with new photos'),
        );
        await tester.pumpAndSettle();
        expect(find.text('This barcode is in your catalog'), findsOneWidget);
        expect(find.byType(MissingProductSubmissionSheet), findsNothing);
      },
    );
  }

  testWidgets(
    'unsupported catalog report identity stays viewable without capture',
    (tester) async {
      final db = CoreDatabase.memory();
      addTearDown(db.close);
      await _insertCatalogProduct(db, id: 'PG_SUB_AAAA');
      await tester.pumpWidget(_harness(const [], db: db));
      await tester.pumpAndSettle();
      await _enterBarcode(tester, '030772032565');
      expect(find.text('View product'), findsOneWidget);
      expect(
        find.textContaining(
          'Reporting isn’t available for this catalog record yet',
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Report incorrect label'),
            )
            .onPressed,
        isNull,
      );
      expect(find.byType(MissingProductSubmissionSheet), findsNothing);
    },
  );

  testWidgets('repeated taps open only one intake sheet', (tester) async {
    await tester.pumpWidget(_harness(const []));
    await tester.pumpAndSettle();
    final button = tester.widget<IconButton>(
      find.byKey(const Key('contributions-add-product')),
    );
    button.onPressed!();
    button.onPressed!();
    await tester.pumpAndSettle();
    expect(find.text('Add a product from photos'), findsOneWidget);
    Navigator.of(tester.element(find.text('Add a product from photos'))).pop();
    await tester.pumpAndSettle();
    expect(find.text('Add a product from photos'), findsNothing);
  });

  testWidgets('owner can save a recognizable name without changing the UPC', (
    tester,
  ) async {
    final rows = [
      _row(
        id: '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a11',
        reviewStatus: 'rejected',
      ),
    ];
    await tester.pumpWidget(_harness(rows));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Name this product'));
    await tester.tap(find.text('Name this product'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Seed · DS-01');
    await tester.tap(find.text('Save name'));
    await tester.pumpAndSettle();
    expect(find.text('Seed · DS-01'), findsOneWidget);
    expect(find.textContaining('050428381397'), findsOneWidget);
    expect(rows.single['review_status'], 'rejected');
  });
  testWidgets('shows review and shipped states without exposing other users', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness([
        _row(
          id: '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a11',
          reviewStatus: 'under_review',
        ),
        _row(
          id: '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a12',
          reviewStatus: 'approved',
          catalogVersion: '2026.07.30.1',
        ),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('Your contributions'), findsOneWidget);
    expect(find.text('Under review'), findsOneWidget);
    expect(find.text('Added to catalog'), findsOneWidget);
    expect(find.textContaining('2026.07.30.1'), findsOneWidget);
    expect(find.textContaining('050428381397'), findsNWidgets(2));
  });

  testWidgets('unknown status is unavailable, never a false completion', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness([
        _row(
          id: '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a11',
          reviewStatus: 'future_state',
        ),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('Status unavailable'), findsOneWidget);
    expect(find.text('Added to catalog'), findsNothing);
  });

  testWidgets(
    'unknown upload or kind is unavailable, not an incomplete upload',
    (tester) async {
      await tester.pumpWidget(
        _harness([
          {
            ..._row(
              id: '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a11',
              reviewStatus: 'submitted',
            ),
            'upload_state': 'future_state',
          },
          {
            ..._row(
              id: '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a12',
              reviewStatus: 'submitted',
            ),
            'kind': 'future_kind',
          },
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('Status unavailable'), findsNWidgets(2));
      expect(find.textContaining('start a new submission'), findsNothing);
      expect(find.text('Waiting for review'), findsNothing);
      expect(find.text('Submission details unavailable'), findsOneWidget);
    },
  );

  testWidgets('does not promise an unavailable upload-resume action', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness([
        {
          ..._row(
            id: '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a11',
            reviewStatus: 'submitted',
          ),
          'upload_state': 'pending',
        },
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('start a new submission'), findsOneWidget);
    expect(find.textContaining('reopen the submission'), findsNothing);
  });

  testWidgets('rejection guidance translates the resolution code', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness([
        {
          ..._row(
            id: '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a11',
            reviewStatus: 'rejected',
          ),
          'resolution_code': 'photo_quality',
        },
        {
          ..._row(
            id: '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a12',
            reviewStatus: 'rejected',
          ),
          'resolution_code': 'other',
          'resolution_detail': 'The lot number sticker covered the panel.',
        },
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('too blurry or dark'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('The lot number sticker covered the panel.'),
      200,
    );
    expect(
      find.text('The lot number sticker covered the panel.'),
      findsOneWidget,
    );
  });

  testWidgets('identity mismatch tells the user to rescan the same package', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness([
        {
          ..._row(
            id: '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a13',
            reviewStatus: 'rejected',
          ),
          'resolution_code': 'product_identity_mismatch',
        },
      ]),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('photos didn’t match the scanned product'),
      findsOneWidget,
    );
    expect(find.text('Try again with new photos'), findsOneWidget);
  });

  testWidgets('duplicate outcomes use distinct truthful headlines', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness([
        {
          ..._row(
            id: '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a11',
            reviewStatus: 'duplicate',
          ),
          'resolution_code': 'already_in_catalog',
        },
        {
          ..._row(
            id: '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a12',
            reviewStatus: 'duplicate',
          ),
          'resolution_code': 'duplicate_submission',
        },
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('Already in the catalog'), findsOneWidget);
    expect(find.text('Already on its way'), findsOneWidget);
    expect(find.text('Already under review'), findsNothing);
  });

  testWidgets('offers resubmission only for evidence users can correct', (
    tester,
  ) async {
    ProductSubmissionSummary? retried;
    await tester.pumpWidget(
      _harness([
        {
          ..._row(
            id: '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a11',
            reviewStatus: 'rejected',
          ),
          'resolution_code': 'photo_quality',
        },
        {
          ..._row(
            id: '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a12',
            reviewStatus: 'rejected',
          ),
          'resolution_code': 'not_a_supplement',
        },
      ], onResubmit: (status) async => retried = status),
    );
    await tester.pumpAndSettle();

    final retry = find.text('Try again with new photos');
    expect(retry, findsOneWidget);
    await tester.tap(retry);
    await tester.pump();

    expect(retried?.submissionId, '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a11');
    expect(retried?.upc, '050428381397');
  });

  testWidgets('a reviewer request asks for named panels on the same card', (
    tester,
  ) async {
    const asked = '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a11';
    const answered = '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a12';
    const unfinished = '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a13';
    ProductSubmissionSummary? retaken;
    await tester.pumpWidget(
      _harness([
        {
          ..._row(id: asked, reviewStatus: 'under_review'),
          'evidence_revision': 1,
          'evidence_requested_revision': 1,
          'evidence_request_reason': 'label_unreadable',
          'evidence_request_panels': ['supplement_facts', 'barcode'],
        },
        {
          ..._row(id: answered, reviewStatus: 'under_review'),
          'evidence_revision': 2,
          'evidence_requested_revision': 1,
          'evidence_request_panels': ['barcode'],
        },
        // Same barcode as the open cards above: an unfinished retake is that
        // submission, never an abandoned duplicate shell to hide.
        {
          ..._row(id: unfinished, reviewStatus: 'under_review'),
          'upload_state': 'pending',
          'evidence_revision': 2,
          'evidence_requested_revision': 1,
          'evidence_request_panels': ['barcode'],
        },
      ], onRetake: (status) async => retaken = status),
    );
    await tester.pumpAndSettle();

    expect(find.text('New photos needed'), findsOneWidget);
    expect(
      find.textContaining('Supplement Facts panel and barcode'),
      findsOneWidget,
    );
    expect(find.text('Retake photos'), findsOneWidget);
    // Not the rejection path: the review and the submission stay.
    expect(find.text('Try again with new photos'), findsNothing);
    await tester.tap(find.byKey(const Key('submission-retake-$asked')));
    await tester.pump();
    expect(retaken?.submissionId, asked);

    await tester.scrollUntilVisible(
      find.byKey(const Key('submission-retake-$unfinished')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('New photos not sent yet'), findsOneWidget);
    expect(find.text('Finish sending new photos'), findsOneWidget);
    // Photos already sent for the request leave it answered: no button.
    expect(find.byKey(const Key('submission-retake-$answered')), findsNothing);
  });

  testWidgets('missing-product retry reopens capture for the rejected UPC', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness([
        {
          ..._row(
            id: '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a11',
            reviewStatus: 'rejected',
          ),
          'resolution_code': 'photo_quality',
        },
      ]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Try again with new photos'));
    await tester.pumpAndSettle();

    expect(find.text('Add this product'), findsOneWidget);
    expect(find.text('For barcode 050428381397'), findsOneWidget);
  });

  testWidgets('label-mismatch retry preserves its catalog identity', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness([
        {
          ..._row(
            id: '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a11',
            reviewStatus: 'rejected',
          ),
          'kind': 'label_mismatch',
          'resolution_code': 'label_unreadable',
          'product_submission_mismatch_details': {
            'dsld_id': '278454',
            'source_record_id': 'DSLD-278454',
            'catalog_source_version': '2026.08.25',
            'formula_fingerprint': null,
          },
        },
      ]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Try again with new photos'));
    await tester.pumpAndSettle();

    expect(find.text('Report a label mismatch'), findsOneWidget);
    expect(
      tester
          .widget<LabelMismatchSheet>(find.byType(LabelMismatchSheet))
          .product
          .dsldId,
      '278454',
    );
  });

  testWidgets('deep link renders only when the product exists locally', (
    tester,
  ) async {
    final db = CoreDatabase.memory();
    addTearDown(db.close);
    await db
        .into(db.productsCore)
        .insert(
          ProductsCoreCompanion.insert(
            dsldId: 'PG_SUB_AAAA',
            productName: 'Promoted Product',
            brandName: const Value('Seed'),
            exportVersion: 'test',
            exportedAt: '2026-08-24T00:00:00Z',
            productStatus: const Value('active'),
          ),
        );

    await tester.pumpWidget(
      _harness([
        {
          ..._row(
            id: '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a11',
            reviewStatus: 'approved',
            catalogVersion: '2026.08.30.1',
          ),
          'resolved_dsld_id': 'PG_SUB_AAAA',
        },
        {
          ..._row(
            id: '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a12',
            reviewStatus: 'approved',
            catalogVersion: '2026.08.30.1',
          ),
          'resolved_dsld_id': 'PG_SUB_NOT_INSTALLED',
        },
      ], db: db),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('submission-view-product-PG_SUB_AAAA')),
      findsOneWidget,
    );
    expect(find.text('Seed · Promoted Product'), findsOneWidget);
    expect(
      find.byKey(const Key('submission-view-product-PG_SUB_NOT_INSTALLED')),
      findsNothing,
    );
    expect(
      find.text('Available after your next catalog update.'),
      findsOneWidget,
    );
  });

  testWidgets('unknown rejected product uses a plain name fallback above UPC', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness([
        {
          ..._row(id: 'rejected', reviewStatus: 'rejected'),
          'resolution_code': 'photo_quality',
        },
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('Product name unavailable'), findsOneWidget);
    expect(find.text('UPC 050428381397'), findsOneWidget);
  });

  testWidgets('rejected submission retains its human-readable display name', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness([
        {
          ..._row(id: 'named-rejected', reviewStatus: 'rejected'),
          'display_name': 'Seed · DS-01 Daily Synbiotic',
          'resolution_code': 'photo_quality',
        },
      ]),
    );
    await tester.pumpAndSettle();
    expect(find.text('Seed · DS-01 Daily Synbiotic'), findsOneWidget);
    expect(find.text('Product name unavailable'), findsNothing);
    expect(find.text('Name this product'), findsOneWidget);
  });

  testWidgets('failed cards offer a confirmed non-destructive history hide', (
    tester,
  ) async {
    ProductSubmissionSummary? hidden;
    await tester.pumpWidget(
      _harness([
        {
          ..._row(id: 'rejected', reviewStatus: 'rejected'),
          'resolution_code': 'photo_quality',
        },
        _row(id: 'accepted', reviewStatus: 'approved', catalogVersion: 'v1'),
      ], onHide: (status) async => hidden = status),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Hide from history'), findsOneWidget);
    await tester.tap(find.byTooltip('Hide from history'));
    await tester.pumpAndSettle();

    expect(find.text('Hide this submission?'), findsOneWidget);
    expect(
      find.textContaining('review record stays securely stored'),
      findsOneWidget,
    );
    await tester.tap(find.text('Hide from history'));
    await tester.pumpAndSettle();

    expect(hidden?.submissionId, 'rejected');
  });

  testWidgets('impact grid counts finalized outcomes and catalog impact', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness([
        _row(
          id: '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a11',
          reviewStatus: 'under_review',
        ),
        _row(
          id: '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a12',
          reviewStatus: 'approved',
        ),
        _row(
          id: '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a13',
          reviewStatus: 'approved',
          catalogVersion: '2026.08.25.1',
        ),
        _row(
          id: '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a14',
          reviewStatus: 'rejected',
        ),
        {
          ..._row(
            id: '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a15',
            reviewStatus: 'submitted',
          ),
          'upload_state': 'pending',
        },
      ], points: () async => 10),
    );
    await tester.pumpAndSettle();

    Text statValue(String key) => tester.widget<Text>(
      find
          .descendant(of: find.byKey(Key(key)), matching: find.byType(Text))
          .first,
    );

    expect(statValue('contributions-stat-pending').data, '1');
    expect(statValue('contributions-stat-approved').data, '1');
    expect(statValue('contributions-stat-total').data, '4');
    expect(statValue('contributions-stat-points').data, '10');
    expect(find.text('Catalog additions'), findsOneWidget);
  });

  testWidgets('points card explains one-time awards and future rewards', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness([
        _row(
          id: '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a13',
          reviewStatus: 'approved',
          catalogVersion: '2026.08.25.1',
        ),
      ]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('contributions-stat-points')));
    await tester.pumpAndSettle();

    expect(find.text('How points work'), findsOneWidget);
    expect(
      find.textContaining('Earn 10 points when a product you submit'),
      findsOneWidget,
    );
    expect(
      find.textContaining('plan to make points redeemable'),
      findsOneWidget,
    );
  });

  testWidgets('total card explains finalized outcomes without draft shells', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness([
        _row(id: 'a', reviewStatus: 'under_review'),
        _row(id: 'b', reviewStatus: 'rejected'),
        _row(id: 'c', reviewStatus: 'approved', catalogVersion: '2026.08.25.1'),
        {
          ..._row(id: 'd', reviewStatus: 'submitted'),
          'upload_state': 'pending',
        },
      ]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('contributions-stat-total')));
    await tester.pumpAndSettle();

    expect(find.text('Submission breakdown'), findsOneWidget);
    expect(find.text('Pending review'), findsNWidgets(2));
    expect(find.text('Not added'), findsNWidgets(2));
    expect(find.text('Finalized submissions'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('submission-breakdown-total')),
        matching: find.text('3'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('impact stats remain readable on a narrow large-text screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      _harness([
        for (var index = 0; index < 123; index++)
          _row(
            id: 'submission-$index',
            reviewStatus: 'approved',
            catalogVersion: '2026.08.25.1',
          ),
      ]),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('contributions-stat-points')), findsOneWidget);
  });

  testWidgets('points are what the ledger says, not a count of submissions', (
    tester,
  ) async {
    // One promoted submission on screen, but the ledger holds 30: history
    // from submissions no longer listed must not be re-priced by the app.
    await tester.pumpWidget(
      _harness([
        _row(
          id: '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a13',
          reviewStatus: 'approved',
          catalogVersion: '2026.08.25.1',
        ),
      ], points: () async => 30),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const Key('contributions-stat-points')),
        matching: find.text('30'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('an unreadable ledger shows a dash, never zero', (tester) async {
    await tester.pumpWidget(
      _harness(const [], points: () async => throw StateError('offline')),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const Key('contributions-stat-points')),
        matching: find.text('—'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('unfinished captures are offered before the sent history', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        const [],
        pendingDrafts: [
          PendingProductSubmission(
            submissionId: '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a20',
            upc: '012345678905',
            resubmissionOf: null,
            noSeparateIngredientPanel: false,
            consentVersion: 'pharmaguide.submission_consent.2026-08-25.v1',
            evidenceRevision: 1,
            photoCount: 3,
            capturedAt: DateTime.utc(2026, 9, 9),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('unfinished-captures')), findsOneWidget);
    expect(find.text('3 photos ready to send'), findsOneWidget);
    // The user must not read this as "submitted and waiting for review".
    expect(find.textContaining('still on this phone'), findsOneWidget);
    expect(find.text('Finish sending'), findsOneWidget);
  });

  testWidgets('no unfinished section when this device holds nothing', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(const []));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('unfinished-captures')), findsNothing);
  });

  testWidgets('plus button starts a photo-first submission with a UPC', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(const []));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('contributions-add-product')));
    await tester.pumpAndSettle();
    expect(find.text('Add a product from photos'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('add-product-gtin-field')),
      '030772032565',
    );
    await tester.tap(find.byKey(const Key('add-product-continue')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('missing-product-start')), findsOneWidget);
    expect(
      find.textContaining('Not found in this device’s catalog'),
      findsOneWidget,
    );
    expect(
      find.textContaining('we’ll check whether it already exists'),
      findsOneWidget,
    );
    expect(find.text('Take a photo'), findsOneWidget);
    expect(
      find.byKey(const Key('missing-product-start-library')),
      findsOneWidget,
    );
    expect(find.textContaining('030772032565'), findsOneWidget);
  });
}

Future<void> _enterBarcode(WidgetTester tester, String barcode) async {
  await tester.tap(find.byKey(const Key('contributions-add-product')));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const Key('add-product-gtin-field')),
    barcode,
  );
  await tester.tap(find.byKey(const Key('add-product-continue')));
  await tester.pumpAndSettle();
}

Future<CoreDatabase> _catalog({
  bool ambiguous = false,
  String upc = '030772032565',
}) async {
  final db = CoreDatabase.memory();
  addTearDown(db.close);
  await _insertCatalogProduct(db, upc: upc);
  if (ambiguous) {
    await _insertCatalogProduct(
      db,
      id: '278455',
      name: 'Second bottle',
      upc: upc,
    );
  }
  return db;
}

Future<void> _insertCatalogProduct(
  CoreDatabase db, {
  String id = '278454',
  String name = 'Catalog supplement',
  String upc = '030772032565',
}) => db
    .into(db.productsCore)
    .insert(
      ProductsCoreCompanion.insert(
        dsldId: id,
        productName: name,
        brandName: const Value('Catalog brand'),
        upcSku: Value(upc),
        exportVersion: 'test',
        exportedAt: '2026-09-12T00:00:00Z',
      ),
    );

PendingProductSubmission _pending(String upc) => PendingProductSubmission(
  submissionId: '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a20',
  upc: upc,
  resubmissionOf: '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a11',
  noSeparateIngredientPanel: false,
  consentVersion: 'pharmaguide.submission_consent.2026-08-25.v1',
  evidenceRevision: 1,
  photoCount: 3,
  capturedAt: DateTime.utc(2026, 9, 9),
);

class _FailOnceDatabase extends CoreDatabase {
  _FailOnceDatabase() : super.memory();
  int lookups = 0;

  @override
  Future<UpcResolution> resolveByGtin(GtinIdentity identity) {
    if (++lookups == 1) throw const FormatException('Catalog unreadable');
    return super.resolveByGtin(identity);
  }
}

Map<String, Object?> _row({
  required String id,
  required String reviewStatus,
  String? catalogVersion,
}) {
  return {
    'id': id,
    'kind': 'missing_product',
    'normalized_upc': '050428381397',
    'upload_state': 'ready',
    'review_status': reviewStatus,
    'created_at': '2026-07-30T12:00:00Z',
    'promoted_catalog_version': catalogVersion,
  };
}

class _Backend implements ProductSubmissionBackend {
  @override
  Future<Map<String, Object?>> fetchIntake({
    required String functionName,
    required Map<String, Object?> payload,
  }) async => {'action': 'start_new'};

  _Backend(this.rows);

  final List<Map<String, Object?>> rows;
  @override
  String? get authenticatedUserId => userId;
  String? userId = 'user-id';

  @override
  Future<List<Map<String, Object?>>> listOwnSubmissions({
    required String table,
    required int offset,
    required int limit,
  }) async {
    return rows.skip(offset).take(limit).toList(growable: false);
  }

  @override
  Future<Map<String, Object?>> fetchOwnEvidence({
    required String submissionId,
  }) => throw UnimplementedError();

  @override
  Future<int> openEvidenceRevision({required Map<String, Object?> payload}) =>
      throw UnimplementedError();

  @override
  Future<bool> finalizeSubmission({
    required String functionName,
    required String submissionId,
    int? expectedRevision,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> persistSubmission({
    required String functionName,
    required Map<String, Object?> payload,
  }) async {
    expect(functionName, 'set_product_submission_display_name');
    final row = rows.singleWhere(
      (row) => row['id'] == payload['p_submission_id'],
    );
    row['display_name'] = payload['p_display_name'];
  }

  @override
  Future<void> uploadPhoto({
    required String bucket,
    required String objectPath,
    required Uint8List bytes,
    required String contentType,
  }) {
    throw UnimplementedError();
  }
}
