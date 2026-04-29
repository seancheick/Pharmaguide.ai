import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/services/product_image_resolver.dart';

void main() {
  late UserDatabase db;

  setUp(() {
    db = UserDatabase.memory();
  });

  tearDown(() async {
    ProductImageResolver.resetSemaphore();
    await db.close();
  });

  // Helper: build a MockClient that returns a fixed response.
  MockClient mockOff({
    required int httpStatus,
    required Map<String, dynamic> body,
  }) {
    return MockClient((request) async {
      return http.Response(json.encode(body), httpStatus);
    });
  }

  // Helper: successful OFF response with an image.
  Map<String, dynamic> successBody(String imageUrl) => {
    'status': 1,
    'product': {
      'code': '123456789',
      'product_name': 'Test Product',
      'image_front_url': imageUrl,
      'image_front_small_url': '${imageUrl}_small',
    },
  };

  // Helper: OFF response with status 0 (product not found).
  Map<String, dynamic> notFoundBody() => {
    'status': 0,
    'status_verbose': 'product not found',
  };

  // Helper: OFF response with status 1 but no image.
  Map<String, dynamic> noImageBody() => {
    'status': 1,
    'product': {'code': '123456789', 'product_name': 'Test Product'},
  };

  group('ProductImageResolver', () {
    test('OFF API returns image → URL returned and cached', () async {
      const expectedUrl = 'https://images.off.org/test.jpg';
      final client = mockOff(httpStatus: 200, body: successBody(expectedUrl));
      final resolver = ProductImageResolver(db, httpClient: client);

      final result = await resolver.resolve('dsld-1', '123456789');

      expect(result, equals(expectedUrl));

      // Verify it was cached
      final cached = await db.getCachedImage('dsld-1');
      expect(cached, isNotNull);
      expect(cached!.imageUrl, equals(expectedUrl));
    });

    test('OFF API returns 404 → null returned, "no_image" cached', () async {
      final client = mockOff(httpStatus: 404, body: {'status': 0});
      final resolver = ProductImageResolver(db, httpClient: client);

      final result = await resolver.resolve('dsld-2', '999999999');

      expect(result, isNull);

      final cached = await db.getCachedImage('dsld-2');
      expect(cached, isNotNull);
      expect(cached!.imageUrl, equals('no_image'));
    });

    test(
      'OFF API returns status 0 → null returned, "no_image" cached',
      () async {
        final client = mockOff(httpStatus: 200, body: notFoundBody());
        final resolver = ProductImageResolver(db, httpClient: client);

        final result = await resolver.resolve('dsld-3', '888888888');

        expect(result, isNull);

        final cached = await db.getCachedImage('dsld-3');
        expect(cached, isNotNull);
        expect(cached!.imageUrl, equals('no_image'));
      },
    );

    test(
      'OFF API timeout → null returned, NOT cached (retry next time)',
      () async {
        final client = MockClient((request) async {
          // Simulate a timeout by delaying longer than the resolver's timeout.
          // We throw TimeoutException directly since MockClient doesn't support
          // actual delays past the resolver's .timeout() call.
          throw TimeoutException('Request timed out');
        });
        final resolver = ProductImageResolver(db, httpClient: client);

        final result = await resolver.resolve('dsld-4', '777777777');

        expect(result, isNull);

        // Crucially: nothing should be cached after a timeout
        final cached = await db.getCachedImage('dsld-4');
        expect(cached, isNull);
      },
    );

    test(
      'Product with no UPC → null immediately, "no_image" cached, no API call',
      () async {
        var apiCalled = false;
        final client = MockClient((request) async {
          apiCalled = true;
          return http.Response('{}', 200);
        });
        final resolver = ProductImageResolver(db, httpClient: client);

        final result = await resolver.resolve('dsld-5', null);

        expect(result, isNull);
        expect(apiCalled, isFalse);

        final cached = await db.getCachedImage('dsld-5');
        expect(cached, isNotNull);
        expect(cached!.imageUrl, equals('no_image'));
      },
    );

    test('Product with empty UPC → null immediately, no API call', () async {
      var apiCalled = false;
      final client = MockClient((request) async {
        apiCalled = true;
        return http.Response('{}', 200);
      });
      final resolver = ProductImageResolver(db, httpClient: client);

      final result = await resolver.resolve('dsld-6', '  ');

      expect(result, isNull);
      expect(apiCalled, isFalse);
    });

    test('Cache hit within TTL → returns cached URL, no API call', () async {
      // Pre-populate cache with a fresh entry
      await db.cacheImageUrl('dsld-7', 'https://cached.example.com/img.jpg');

      var apiCalled = false;
      final client = MockClient((request) async {
        apiCalled = true;
        return http.Response('{}', 200);
      });
      final resolver = ProductImageResolver(db, httpClient: client);

      final result = await resolver.resolve('dsld-7', '666666666');

      expect(result, equals('https://cached.example.com/img.jpg'));
      expect(apiCalled, isFalse);
    });

    test('Negative cache hit within TTL → returns null, no API call', () async {
      // Pre-populate cache with a "no_image" entry
      await db.cacheImageUrl('dsld-8', 'no_image');

      var apiCalled = false;
      final client = MockClient((request) async {
        apiCalled = true;
        return http.Response('{}', 200);
      });
      final resolver = ProductImageResolver(db, httpClient: client);

      final result = await resolver.resolve('dsld-8', '555555555');

      expect(result, isNull);
      expect(apiCalled, isFalse);
    });

    test('Cache expired → re-queries OFF API', () async {
      // Insert a cache entry with a date older than 30 days
      await db
          .into(db.productImageCache)
          .insert(
            ProductImageCacheCompanion.insert(
              dsldId: 'dsld-9',
              imageUrl: 'https://old.example.com/stale.jpg',
              cachedAt: Value(
                DateTime.now().subtract(const Duration(days: 31)),
              ),
            ),
          );

      const freshUrl = 'https://new.example.com/fresh.jpg';
      final client = mockOff(httpStatus: 200, body: successBody(freshUrl));
      final resolver = ProductImageResolver(db, httpClient: client);

      final result = await resolver.resolve('dsld-9', '444444444');

      expect(result, equals(freshUrl));

      // Cache should be updated
      final cached = await db.getCachedImage('dsld-9');
      expect(cached!.imageUrl, equals(freshUrl));
    });

    test('No crashes on malformed OFF response body', () async {
      final client = MockClient((request) async {
        return http.Response('{"status": 1, "product": "not_a_map"}', 200);
      });
      final resolver = ProductImageResolver(db, httpClient: client);

      // Should not throw — gracefully handle malformed JSON structure
      final result = await resolver.resolve('dsld-10', '333333333');
      expect(result, isNull);
    });

    test('No crashes on completely invalid JSON', () async {
      final client = MockClient((request) async {
        return http.Response('this is not json at all', 200);
      });
      final resolver = ProductImageResolver(db, httpClient: client);

      final result = await resolver.resolve('dsld-11', '222222222');
      expect(result, isNull);
    });

    test(
      'OFF response with status 1 but missing image_front_url → no_image cached',
      () async {
        final client = mockOff(httpStatus: 200, body: noImageBody());
        final resolver = ProductImageResolver(db, httpClient: client);

        final result = await resolver.resolve('dsld-12', '111111111');

        expect(result, isNull);

        final cached = await db.getCachedImage('dsld-12');
        expect(cached!.imageUrl, equals('no_image'));
      },
    );

    test('UPC with spaces is cleaned before querying OFF', () async {
      String? requestedPath;
      final client = MockClient((request) async {
        requestedPath = request.url.path;
        return http.Response(
          json.encode(successBody('https://img.off.org/clean.jpg')),
          200,
        );
      });
      final resolver = ProductImageResolver(db, httpClient: client);

      await resolver.resolve('dsld-13', '123 456 789');

      expect(requestedPath, contains('123456789'));
      expect(requestedPath, isNot(contains(' ')));
    });
  });
}
