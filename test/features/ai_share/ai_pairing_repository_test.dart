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
  int lifetime = 3600,
}) => client.auth.setInitialSession(
  jsonEncode({
    'access_token':
        '${base64Url.encode(utf8.encode('{}'))}.${base64Url.encode(utf8.encode(jsonEncode({'sub': user, 'session_id': session, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + lifetime, 'version': version})))}.signature',
    'token_type': 'bearer',
    'refresh_token': 'synthetic',
    'user': {'id': user},
  }),
);

void main() {
  test(
    'disconnect refreshes expired app session and rejects late account replacement',
    () async {
      var refreshes = 0;
      final client = SupabaseClient(
        'https://example.test',
        'anon',
        httpClient: MockClient((request) async {
          expect(request.url.path, '/auth/v1/token');
          refreshes++;
          final refreshed = SupabaseClient('https://example.test', 'anon');
          await signIn(refreshed, version: 2);
          final json = jsonEncode(refreshed.auth.currentSession!.toJson());
          await refreshed.dispose();
          return http.Response(
            json,
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      await signIn(client, lifetime: -60);
      var changeAccount = false;
      var calls = 0;
      final repo = SupabaseAiConnectionsRepository(
        client,
        MockClient((request) async {
          calls++;
          if (changeAccount) {
            await signIn(client, user: 'other', session: 'other-session');
          }
          return http.Response('{"disconnected":true}', 200);
        }),
      );
      expect(
        await repo.disconnect('client_test'),
        AiDisconnectResult.disconnected,
      );
      expect(refreshes, 1);
      expect(calls, 1);
      changeAccount = true;
      await expectLater(
        repo.disconnect('client_test'),
        throwsA(isA<AiDisconnectException>()),
      );
      await client.dispose();
      final signedOut = SupabaseClient('https://example.test', 'anon');
      final noSession = SupabaseAiConnectionsRepository(
        signedOut,
        MockClient((_) async => throw StateError('must not send')),
      );
      await expectLater(
        noSession.disconnect('client_test'),
        throwsA(isA<AiDisconnectException>()),
      );
      await signedOut.dispose();
    },
  );

  test(
    'pending revocation uses existing server barrier and rejects unknown response',
    () async {
      final client = SupabaseClient('https://example.test', 'anon');
      await signIn(client);
      var body = '{"client_id":"client_pending"}';
      final repo = SupabaseAiConnectionsRepository(
        client,
        MockClient((request) async {
          expect(jsonDecode(request.body), {'action': 'revocation_status'});
          return http.Response(body, 200);
        }),
      );
      expect(await repo.pendingRevocation(), 'client_pending');
      body = '{"client_id":null}';
      expect(await repo.pendingRevocation(), isNull);
      body = '{}';
      await expectLater(
        repo.pendingRevocation(),
        throwsA(isA<AiDisconnectException>()),
      );
      await client.dispose();
    },
  );

  test(
    'native disconnect uses authenticated exact origin and reports partial revocation',
    () async {
      final client = SupabaseClient('https://example.test', 'anon');
      await signIn(client);
      var status = 200;
      var body = <String, Object?>{'disconnected': true};
      final repo = SupabaseAiConnectionsRepository(
        client,
        MockClient((request) async {
          expect(
            request.url.toString(),
            'https://pharmaguide.io/api/ai-connections',
          );
          expect(request.followRedirects, isFalse);
          expect(request.headers['authorization'], startsWith('Bearer '));
          expect(jsonDecode(request.body), {
            'action': 'disconnect',
            'client_id': 'client_test',
          });
          return http.Response(jsonEncode(body), status);
        }),
      );
      expect(
        await repo.disconnect('client_test'),
        AiDisconnectResult.disconnected,
      );
      status = 503;
      body = {'provider_handled': true, 'local_access_ended': true};
      expect(
        await repo.disconnect('client_test'),
        AiDisconnectResult.localAccessEnded,
      );
      for (final code in [200, 302, 401, 503]) {
        status = code;
        body = {};
        await expectLater(
          repo.disconnect('client_test'),
          throwsA(isA<AiDisconnectException>()),
        );
      }
      await client.dispose();
    },
  );
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
      response = {
        'approved': true,
        'connection_id': '6f1c2a3b-0000-4000-8000-000000000001',
      };
      expect(
        await repo.approvePairing('ABCDEFGHJKMN'),
        '6f1c2a3b-0000-4000-8000-000000000001',
      );
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
