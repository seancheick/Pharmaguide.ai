import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';
import 'package:pharmaguide/features/contributions/add_missing_product_sheet.dart';
import 'package:pharmaguide/services/gtin.dart';

void main() {
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
}
