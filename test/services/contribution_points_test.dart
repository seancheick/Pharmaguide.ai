import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pharmaguide/services/contribution_points.dart';

void main() {
  test(
    'reads every award even when the server returns shortened pages',
    () async {
      final offsets = <int>[];
      final client = SupabaseClient(
        'https://example.test',
        'test-key',
        httpClient: MockClient((request) async {
          expect(request.url.queryParameters['order'], startsWith('id.asc'));
          final offset = int.parse(
            request.url.queryParameters['offset'] ?? '0',
          );
          offsets.add(offset);
          final available = 1005 - offset;
          final count = available <= 0 ? 0 : (available < 37 ? available : 37);
          return http.Response(
            jsonEncode(List.generate(count, (_) => {'points': 10})),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      addTearDown(client.dispose);
      expect(await readOwnContributionPoints(client), 10050);
      expect(offsets.last, 1005);
    },
  );

  test('a later page failure does not return a partial total', () async {
    var calls = 0;
    final client = SupabaseClient(
      'https://example.test',
      'test-key',
      httpClient: MockClient((request) async {
        calls++;
        return calls == 1
            ? http.Response(
                '[{"points":10}]',
                200,
                headers: {'content-type': 'application/json'},
                request: request,
              )
            : http.Response(
                '{"message":"unavailable","code":"42501"}',
                403,
                headers: {'content-type': 'application/json'},
                request: request,
              );
      }),
    );
    addTearDown(client.dispose);
    await expectLater(
      readOwnContributionPoints(client),
      throwsA(isA<PostgrestException>()),
    );
  });

  test('adds up the ledger and skips rows that are not awards', () {
    expect(
      sumLedgerPoints([
        {'points': 10},
        {'points': 10},
        {'points': 'ten'},
        {'points': -10},
        {'points': null},
        <String, Object?>{},
      ]),
      20,
    );
  });

  test('an empty ledger is zero points', () {
    expect(sumLedgerPoints(const []), 0);
  });
}
