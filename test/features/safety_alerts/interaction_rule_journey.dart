// One fictional journey, shared by the widget test and the simulator run: a
// phone taking the medication is offline, the connection returns, and the new
// contraindication appears on the product page by itself.

import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/interaction_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/product_detail/providers/detail_blob_provider.dart';
import 'package:pharmaguide/features/product_detail/v2/product_detail_v2_connected.dart';
import 'package:pharmaguide/features/safety_alerts/providers/safety_alert_providers.dart';
import 'package:pharmaguide/services/connectivity_service.dart';
import 'package:pharmaguide/services/safety_alerts/safety_alert_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _dsldId = '9990001';
const noticeKey = Key('live-safety-alert-SA_9999_0001');

/// Runs the journey with the pipeline's fake feed [feedBytes]. [onStep] fires
/// with the page on screen, before and after the connection returns.
Future<void> runInteractionRuleJourney(
  WidgetTester tester, {
  required List<int> feedBytes,
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

  var online = false;
  final client = SupabaseClient(
    'https://example.test',
    'test-key',
    httpClient: MockClient((request) async {
      if (!online) throw http.ClientException('offline');
      if (request.url.path.contains('/storage/')) {
        return http.Response.bytes(feedBytes, 200, request: request);
      }
      return http.Response(
        jsonEncode({
          'feed_path': 'safety/feed.json',
          'checksum': 'sha256:${sha256.convert(feedBytes)}',
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
        connectionStatusProvider.overrideWith((ref) => connection.stream),
        safetyAlertRepositoryProvider.overrideWithValue(
          SafetyAlertRepository(
            client: client,
            preferences: _MemoryPreferences(),
          ),
        ),
      ],
      child: Consumer(
        builder: (context, ref, child) {
          ref.watch(safetyAlertRefreshProvider);
          return child!;
        },
        child: const MaterialApp(
          home: ProductDetailV2ConnectedScreen(dsldId: _dsldId),
        ),
      ),
    ),
  );
  connection.add(ConnectionStatus.offline);
  await settle();

  expect(find.byKey(noticeKey), findsNothing);
  await onStep('before_reconnect');

  online = true;
  connection.add(ConnectionStatus.online);
  await settle();

  expect(find.byKey(noticeKey), findsOneWidget);
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
