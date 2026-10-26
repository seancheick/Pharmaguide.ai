import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';
import 'package:pharmaguide/features/contributions/add_missing_product_sheet.dart';
import 'package:pharmaguide/services/gtin.dart';
import 'package:pharmaguide/services/product_submission_service.dart';

import '../../support/app_fonts.dart';

void main() {
  testWidgets(
    'alternate entry explains review instead of promising numeric lookup',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showAddMissingProductIdentitySheet(context),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Enter the UPC/GTIN'), findsOneWidget);
      await tester.tap(find.byKey(const Key('add-product-alternate-code')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Enter the UPC/GTIN'), findsNothing);
      expect(find.textContaining('TCIN and DPCI'), findsNothing);
      expect(find.textContaining('continue without a UPC'), findsOneWidget);
      await tester.tap(find.byKey(const Key('add-product-alternate-code')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Enter the UPC/GTIN'), findsOneWidget);
    },
  );

  testWidgets(
    'whitespace optional listing URL continues without rewriting printed code',
    (tester) async {
      Object? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showAddMissingProductIdentitySheet(context);
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('add-product-alternate-code')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('add-product-brand')),
        'Natgrown',
      );
      await tester.enterText(
        find.byKey(const Key('add-product-name')),
        'Fixture',
      );
      await tester.enterText(
        find.byKey(const Key('add-product-listing')),
        '   ',
      );
      await tester.enterText(
        find.byKey(const Key('add-product-gtin-field')),
        ' X002FLZ3X7 ',
      );
      await tester.ensureVisible(find.byKey(const Key('add-product-continue')));
      await tester.tap(find.byKey(const Key('add-product-continue')));
      await tester.pumpAndSettle();
      expect(result, isA<ProductSubmissionIdentifier>());
      expect((result as ProductSubmissionIdentifier).listingUrl, isNull);
      expect(
        (result as ProductSubmissionIdentifier).observedCode,
        ' X002FLZ3X7 ',
      );
      expect(find.text('Add a product from photos'), findsNothing);
    },
  );

  testWidgets('OCR suggestion fills a validated UPC and can be confirmed', (
    tester,
  ) async {
    final identity = GtinIdentity.parse('030772032565');
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showAddMissingProductIdentitySheet(
                context,
                pickReference: () async =>
                    XFile.fromData(Uint8List.fromList(<int>[1])),
                readReference: (_) async => [identity],
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-product-read-upc')));
    await tester.pumpAndSettle();

    expect(
      (tester
              .widget<TextField>(
                find.byKey(const Key('add-product-gtin-field')),
              )
              .controller!)
          .text,
      '030772032565',
    );
    await tester.tap(find.byKey(const Key('add-product-continue')));
    await tester.pumpAndSettle();
    expect(find.text('Add a product from photos'), findsNothing);
  });

  testWidgets('offers a camera path for reading a printed UPC', (tester) async {
    var cameraPicked = false;
    final identity = GtinIdentity.parse('030772032565');
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showAddMissingProductIdentitySheet(
                context,
                takeReference: () async {
                  cameraPicked = true;
                  return XFile.fromData(Uint8List.fromList(<int>[2]));
                },
                readReference: (_) async => [identity],
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-product-take-upc')));
    await tester.pumpAndSettle();

    expect(cameraPicked, isTrue);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('add-product-gtin-field')))
          .controller!
          .text,
      identity.submissionIdentity,
    );
  });

  // Real glyphs, not the test font's full-width boxes: whether a label fits
  // is a question about the font users actually see.
  setUpAll(loadAppFonts);

  Future<void> openSheet(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'Geist'),
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showAddMissingProductIdentitySheet(context),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('the two photo buttons are equal halves of the Continue width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await openSheet(tester);

    final library = tester.getRect(
      find.byKey(const Key('add-product-read-upc')),
    );
    final camera = tester.getRect(
      find.byKey(const Key('add-product-take-upc')),
    );
    final continueButton = tester.getRect(
      find.byKey(const Key('add-product-continue')),
    );
    expect(library.width, moreOrLessEquals(camera.width, epsilon: 0.5));
    expect(
      library.height,
      moreOrLessEquals(continueButton.height, epsilon: 0.5),
    );
    expect(
      camera.height,
      moreOrLessEquals(continueButton.height, epsilon: 0.5),
    );
    expect(library.left, moreOrLessEquals(continueButton.left, epsilon: 0.5));
    expect(camera.right, moreOrLessEquals(continueButton.right, epsilon: 0.5));

    // Half-width labels must fit whole, and say what the buttons read.
    expect(find.text('Or read the number from a photo'), findsOneWidget);
    for (final label in ['Photo library', 'Take photo']) {
      expect(
        tester
            .renderObject<RenderParagraph>(find.text(label))
            .didExceedMaxLines,
        isFalse,
        reason: '$label is cut off',
      );
    }
  });

  testWidgets('large text stacks the photo buttons at full width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await openSheet(tester);

    final library = tester.getRect(
      find.byKey(const Key('add-product-read-upc')),
    );
    final camera = tester.getRect(
      find.byKey(const Key('add-product-take-upc')),
    );
    final continueButton = tester.getRect(
      find.byKey(const Key('add-product-continue')),
    );
    expect(library.width, moreOrLessEquals(continueButton.width, epsilon: 0.5));
    expect(camera.width, moreOrLessEquals(continueButton.width, epsilon: 0.5));
    expect(camera.top, greaterThan(library.bottom));
    expect(tester.takeException(), isNull);
  });
}
