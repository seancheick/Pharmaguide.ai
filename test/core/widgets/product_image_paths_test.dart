// Every image path a catalog on a phone can carry, through the reader they all
// share. The pipeline owner is scripts/supabase_client.py::product_image_remote_path.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/widgets/branded_placeholder.dart';
import 'package:pharmaguide/core/widgets/product_image.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/services/product_image_resolver.dart';

const _hashA =
    'e4dd1d2e9505c1d7e9a6b4c2f0e8d6a4c2b0f8e6d4c2a0b8f6e4d2c0a8b6f4e2';
const _hashB =
    '07ab1d2e9505c1d7e9a6b4c2f0e8d6a4c2b0f8e6d4c2a0b8f6e4d2c0a8b6f4e2';
const _base = 'https://cdn.example.com/storage/v1/object/public/product-images';

void main() {
  group('the object a catalog value names', () {
    final cases = {
      'a hash-named image': (
        'product-images/sha256/e4/$_hashA.webp',
        'sha256/e4/$_hashA.webp',
      ),
      'the mutable name in the bundled catalog': (
        'product-images/1024.webp',
        '1024.webp',
      ),
      'a version folder': (
        'product-images/v2026.11.02.191010/1024.webp',
        'v2026.11.02.191010/1024.webp',
      ),
    };
    cases.forEach((name, value) {
      test(name, () {
        expect(
          ProductImageResolver.normalizeDsldImageObjectPath(value.$1),
          value.$2,
        );
      });
    });
  });

  group('showing a product', () {
    late UserDatabase db;

    setUp(() => db = UserDatabase.memory());

    tearDown(() async {
      ProductImageResolver.resetSemaphore();
      await db.close();
    });

    Widget imageOf(String dsldId, String productName, String path) =>
        ProviderScope(
          overrides: [
            productImageResolverProvider.overrideWithValue(
              ProductImageResolver(db),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ProductImage(
                key: ValueKey(dsldId),
                dsldId: dsldId,
                dsldImagePath: path,
                productName: productName,
                brandName: 'Brand',
              ),
            ),
          ),
        );

    Future<CachedNetworkImage> shownFor(
      WidgetTester tester,
      String path,
    ) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(imageOf('1', 'Product One', path));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      return tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
    }

    testWidgets('an object that is missing falls to this product\'s own '
        'placeholder, never a picture from elsewhere', (tester) async {
      // A picture cached for this product must not stand in for the catalog's.
      await db.cacheImageUrl('1', 'https://other.example/another-picture.jpg');
      final image = await shownFor(tester, '$_base/sha256/e4/$_hashA.webp');
      expect(image.imageUrl, '$_base/sha256/e4/$_hashA.webp');

      // What a 400 from Storage reaches. Image loading itself needs a device.
      final fallback = image.errorWidget!(
        tester.element(find.byType(CachedNetworkImage)),
        image.imageUrl,
        Exception('400'),
      );
      expect((fallback as BrandedPlaceholder).productName, 'Product One');
    });

    testWidgets('a changed picture asks for its new object, never the old '
        'one', (tester) async {
      final before = await shownFor(tester, '$_base/sha256/e4/$_hashA.webp');
      expect(before.imageUrl, '$_base/sha256/e4/$_hashA.webp');
      final after = await shownFor(tester, '$_base/sha256/07/$_hashB.webp');
      expect(after.imageUrl, '$_base/sha256/07/$_hashB.webp');
    });
  });
}
