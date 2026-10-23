import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/ai_share/ai_connections_repository.dart';

Future<void> signIn(
  SupabaseClient client, {
  String user = 'user-a',
  String session = 'session-a',
  int version = 0,
}) => client.auth.setInitialSession(
  jsonEncode({
    'access_token':
        '${base64Url.encode(utf8.encode('{}'))}.${base64Url.encode(utf8.encode(jsonEncode({'sub': user, 'session_id': session, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600, 'version': version})))}.signature',
    'token_type': 'bearer',
    'refresh_token': 'synthetic',
    'user': {'id': user},
  }),
);

void main() {
  test(
    'durable connection requires explicit WorkOS identity and stays revocable',
    () {
      final row = <String, Object?>{
        'connection_id': 'connection',
        'client_id': 'codex',
        'status': 'active',
        'created_at': '2026-10-23T00:00:00Z',
        'expires_at': null,
        'oauth_issuer': 'https://issuer.authkit.app',
        'consent_id': 'app_consent_exact',
      };
      final connection = AiConnection.tryParse(row);
      expect(connection, isNotNull);
      expect(connection!.isLiveAt(DateTime.utc(2027)), isTrue);
      expect(
        AiConnection.tryParse({
          ...row,
          'status': 'revoked',
        })!.isLiveAt(DateTime.utc(2027)),
        isFalse,
      );
      expect(AiConnection.tryParse({...row, 'oauth_issuer': null}), isNull);
      expect(AiConnection.tryParse({...row, 'expires_at': 'invalid'}), isNull);
    },
  );
  test(
    'preview and cancel use canonical RPCs and require valid replies',
    () async {
      final calls = <http.Request>[];
      var response = <String, Object?>{
        'client_name': 'Codex',
        'callback_host': 'chatgpt.com',
        'expires_at': DateTime.now()
            .add(const Duration(minutes: 5))
            .toIso8601String(),
      };
      final client = SupabaseClient(
        'https://example.test',
        'anon',
        httpClient: MockClient((request) async {
          calls.add(request);
          return http.Response(
            jsonEncode(response),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      await signIn(client);
      final repo = SupabaseAiConnectionsRepository(client);
      expect((await repo.previewPairing('abcd-efgh jkmn')).clientName, 'Codex');
      expect(calls.last.url.path, '/rest/v1/rpc/preview_ai_connection_pairing');
      response = {'cancelled': true};
      await repo.cancelPairing('abcd-efgh jkmn');
      expect(
        calls.last.url.path,
        '/rest/v1/rpc/cancel_my_ai_connection_pairing',
      );
      expect(jsonDecode(calls.last.body), {'p_code': 'ABCDEFGHJKMN'});
      for (final invalid in <Map<String, Object?>>[
        {},
        {'approved': 'true'},
        {'approved': false},
        {'error': 'pairing_unavailable'},
      ]) {
        response = invalid;
        await expectLater(
          repo.approvePairing('ABCDEFGHJKMN'),
          throwsA(isA<AiPairingException>()),
        );
        await expectLater(
          repo.cancelPairing('ABCDEFGHJKMN'),
          throwsA(isA<AiPairingException>()),
        );
      }
      await client.dispose();
    },
  );

  test(
    'RPC rejects changed session but accepts token refresh of same session',
    () async {
      for (final changedSession in [true, false]) {
        late SupabaseClient client;
        final calls = <http.Request>[];
        client = SupabaseClient(
          'https://example.test',
          'anon',
          httpClient: MockClient((request) async {
            calls.add(request);
            await signIn(
              client,
              session: changedSession ? 'session-b' : 'session-a',
              version: 1,
            );
            return http.Response(
              '{"approved":true}',
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }),
        );
        await signIn(client);
        expect(SupabaseAiConnectionsRepository(client).pairingSessionIdentity, (
          'user-a',
          'session-a',
        ));
        final request = SupabaseAiConnectionsRepository(
          client,
        ).approvePairing('abcd-efgh jkmn');
        if (changedSession) {
          await expectLater(request, throwsA(isA<AiPairingException>()));
        } else {
          await request;
        }
        expect(
          calls.single.url.path,
          '/rest/v1/rpc/approve_ai_connection_pairing',
        );
        expect(jsonDecode(calls.single.body), {'p_code': 'ABCDEFGHJKMN'});
        await client.dispose();
      }
    },
  );

  test('RPC signed out, malformed and error payloads fail closed', () async {
    var requests = 0;
    final client = SupabaseClient(
      'https://example.test',
      'anon',
      httpClient: MockClient((request) async {
        requests++;
        return http.Response(
          '{"approved":true,"error":"private payload"}',
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    final repo = SupabaseAiConnectionsRepository(client);
    await expectLater(
      repo.approvePairing('ABCDEFGHJKMN'),
      throwsA(isA<AiPairingException>()),
    );
    expect(requests, 0);
    await signIn(client);
    await expectLater(
      repo.approvePairing('bad'),
      throwsA(isA<AiPairingException>()),
    );
    expect(requests, 0);
    await expectLater(
      repo.approvePairing('ABCDEFGHJKMN'),
      throwsA(isA<AiPairingException>()),
    );
    expect(requests, 1);
    await client.dispose();
  });

  test(
    'canonical code accepts separators and rejects ambiguous characters',
    () {
      expect(AiPairingPreview.normalizeCode('abcd-efgh jkmn'), 'ABCDEFGHJKMN');
      for (final code in ['ABCDEFGHIJKL', '', 'ABCDEFGHJKM!', 'ABCDEFGHJKM']) {
        expect(
          () => AiPairingPreview.normalizeCode(code),
          throwsA(isA<AiPairingException>()),
        );
      }
    },
  );
  test('preview requires complete verified metadata and future expiry', () {
    final now = DateTime.utc(2026, 10, 23);
    final row = <String, Object?>{
      'client_name': 'Codex',
      'callback_host': 'chatgpt.com',
      'expires_at': now.add(const Duration(minutes: 5)).toIso8601String(),
    };
    expect(AiPairingPreview.parse(row, now).clientName, 'Codex');
    for (final bad in [
      null,
      {...row, 'error': 'private'},
      {...row, 'client_name': ''},
      {...row, 'callback_host': null},
      {...row, 'expires_at': now.toIso8601String()},
    ]) {
      expect(
        () => AiPairingPreview.parse(bad, now),
        throwsA(isA<AiPairingException>()),
      );
    }
  });
}
