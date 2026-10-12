// Release gate S5 (ADR-009): app sign-out deletes that user's AI-share
// snapshots while the session JWT can still authorize the delete, stops any
// opt-in refresh, and still completes sign-out when the purge fails.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/services/auth/pg_auth_service.dart';
import 'package:pharmaguide/services/sharing/ai_share_prefs_store.dart';
import 'package:pharmaguide/services/sharing/ai_share_scope.dart';

import '../features/ai_share/ai_share_test_fixtures.dart';

void main() {
  test('sign-out calls deleteAll before the session is destroyed and stops '
      'every opt-in refresh', () async {
    final backend = FakeAiShareBackend();
    final prefs = AiSharePrefsStore(MemoryPreferencesStore());
    await prefs.recordShare('c-1', AiShareScope.detailedReport, 24);
    await prefs.setKeepUpdated('c-1', true);
    final events = <String>[];
    final client = backend.client();

    final auth = PGAuthService(
      aiShareSnapshots: client,
      aiSharePrefs: prefs,
      signOutRemote: () async {
        events.add('signOut:${backend.deletes.length}');
      },
    );
    await auth.signOut();

    expect(backend.deletes.single.body, {'all': true});
    expect(events, ['signOut:1'], reason: 'deleteAll must run first');
    expect(await prefs.readAll(), isEmpty);
  });

  test('a failed purge is logged and sign-out still completes', () async {
    final backend = FakeAiShareBackend()..failWith = StateError('offline');
    final prefs = AiSharePrefsStore(MemoryPreferencesStore());
    var signedOut = false;

    await PGAuthService(
      aiShareSnapshots: backend.client(),
      aiSharePrefs: prefs,
      signOutRemote: () async => signedOut = true,
    ).signOut();

    expect(backend.deletes, hasLength(1));
    expect(signedOut, isTrue);
  });

  test(
    'the production sign-out path purges before supabase.auth.signOut()',
    () {
      final source = File(
        'lib/services/auth/pg_auth_service.dart',
      ).readAsStringSync();
      final purgeAt = source.indexOf('_purgeAiShareBeforeSignOut()');
      final signOutAt = source.indexOf('supabase.auth.signOut()');
      expect(purgeAt, greaterThan(-1));
      expect(signOutAt, greaterThan(purgeAt));
    },
  );
}
