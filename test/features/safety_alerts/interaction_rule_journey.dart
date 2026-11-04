// One fictional journey, shared by the widget test and the simulator run: a
// phone taking the medication is offline, the connection returns, and the new
// contraindication appears on the product page by itself.

import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pharmaguide/core/theme/v2/v2_theme.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/interaction_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/product_detail/providers/detail_blob_provider.dart';
import 'package:pharmaguide/features/product_detail/v2/product_detail_v2_connected.dart';
import 'package:pharmaguide/features/safety_alerts/providers/safety_alert_providers.dart';
import 'package:pharmaguide/services/connectivity_service.dart';
import 'package:pharmaguide/services/safety_alerts/safety_alert_repository.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/safety_alerts/signed_feed_support.dart';

const _dsldId = '9990001';
const noticeKey = Key('live-safety-alert-SA_9999_0001');
const pregnancyNoticeKey = Key('live-safety-alert-SA_9999_0003');

/// Runs the journey with the pipeline's fake feeds: [baseBytes] at `feed_path`,
/// [feedBytes] as the superset the manifest names. With [pregnant], the person
/// takes no medication and their profile is what matches. [onStep] fires
/// with the page on screen, before and after the connection returns.
Future<void> runInteractionRuleJourney(
  WidgetTester tester, {
  required List<int> baseBytes,
  required List<int> feedBytes,
  bool pregnant = false,
  List<Override> extraOverrides = const [],
  Future<void> Function(String step) onStep = _noStep,
  Future<void> Function() settle = _noSettle,
}) async {
  final coreDb = CoreDatabase.memory();
  final userDb = UserDatabase.memory();
  final interactionDb = InteractionDatabase.memory();
  final connection = StreamController<ConnectionStatus>.broadcast();

  await coreDb
      .into(coreDb.productsCore)
      .insert(
        ProductsCoreCompanion.insert(
          dsldId: _dsldId,
          productName: 'Fakeroot capsules (fictional)',
          brandName: const Value('Test fixture'),
          keyIngredientTags: const Value('["fake_fakeroot"]'),
          productSafetyStatus: const Value('no_known_catalog_concern'),
          exportVersion: 'test',
          exportedAt: '2026-11-03T00:00:00Z',
        ),
      );
  final now = DateTime.utc(2026, 11, 3, 12);
  if (!pregnant) {
    await userDb
        .into(userDb.userStacksLocal)
        .insert(
          UserStacksLocalCompanion.insert(
            id: 'med-fake',
            type: const Value('medication'),
            name: 'Testoprilex (fictional)',
            rxcui: const Value('0000001'),
            addedAt: Value(now),
            clientUpdatedAt: Value(now),
          ),
        );
  }
  final key = pregnant ? pregnancyNoticeKey : noticeKey;
  final otherKey = pregnant ? noticeKey : pregnancyNoticeKey;

  var online = false;
  final client = SupabaseClient(
    'https://example.test',
    'test-key',
    httpClient: MockClient((request) async {
      if (!online) throw http.ClientException('offline');
      if (request.url.path.contains('safety/extended.json')) {
        return http.Response.bytes(feedBytes, 200, request: request);
      }
      if (request.url.path.contains('/storage/')) {
        return http.Response.bytes(baseBytes, 200, request: request);
      }
      return http.Response(
        jsonEncode({
          'feed_path': 'safety/feed.json',
          'checksum': 'sha256:${sha256.convert(baseBytes)}',
          'manifest': {
            'signed_feed': await signedFeedBlock(
              path: 'safety/feed.json',
              checksum: 'sha256:${sha256.convert(baseBytes)}',
              extended: {
                'path': 'safety/extended.json',
                'checksum': 'sha256:${sha256.convert(feedBytes)}',
              },
            ),
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
        request: request,
      );
    }),
  );
  // Nothing here signs in, and its refresh timer would outlive the test.
  client.auth.stopAutoRefresh();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        coreDatabaseProvider.overrideWithValue(coreDb),
        userDatabaseProvider.overrideWithValue(userDb),
        interactionDatabaseProvider.overrideWithValue(interactionDb),
        detailBlobProvider.overrideWith((ref, dsldId) async => null),
        ...extraOverrides,
        if (pregnant)
          loadedProfileProvider.overrideWith(
            (ref) async => const ProfileState(conditions: ['pregnancy']),
          ),
        connectionStatusProvider.overrideWith((ref) => connection.stream),
        safetyAlertRepositoryProvider.overrideWithValue(
          SafetyAlertRepository(
            client: client,
            preferences: _MemoryPreferences(),
            verificationKeys: testAlertFeedKeys,
          ),
        ),
      ],
      child: Consumer(
        builder: (context, ref, child) {
          ref.watch(safetyAlertRefreshProvider);
          return child!;
        },
        child: MaterialApp(
          theme: V2Theme.light,
          home: const ProductDetailV2ConnectedScreen(dsldId: _dsldId),
        ),
      ),
    ),
  );
  connection.add(ConnectionStatus.offline);
  await settle();

  expect(find.byKey(key), findsNothing);
  await onStep('before_reconnect');

  online = true;
  connection.add(ConnectionStatus.online);
  await settle();

  expect(find.byKey(key), findsOneWidget);
  expect(find.byKey(otherKey), findsNothing);
  await onStep('after_reconnect');
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
  await connection.close();
  await coreDb.close();
  await userDb.close();
  await interactionDb.close();
}

Future<void> _noStep(String step) async {}
Future<void> _noSettle() async {}

class _MemoryPreferences implements SharedPreferencesAsync {
  final values = <String, String>{};

  @override
  Future<String?> getString(String key) async => values[key];

  @override
  Future<void> setString(String key, String value) async => values[key] = value;

  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
