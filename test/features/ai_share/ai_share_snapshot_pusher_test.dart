import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/features/ai_share/ai_share_snapshot_pusher.dart';
import 'package:pharmaguide/features/stack/providers/active_stack_provider.dart';
import 'package:pharmaguide/services/sharing/ai_brief_builder.dart';
import 'package:pharmaguide/services/sharing/ai_share_prefs_store.dart';
import 'package:pharmaguide/services/sharing/ai_share_scope.dart';

import 'ai_share_test_fixtures.dart';

void main() {
  late FakeAiShareBackend backend;
  late AiSharePrefsStore prefs;
  late int loads;

  AiShareSnapshotPusher pusher({bool signedIn = true}) {
    backend.signedIn = signedIn;
    return AiShareSnapshotPusher(
      isSignedIn: () => signedIn,
      prefs: prefs,
      client: backend.client(),
      loadData: () async {
        loads++;
        return aiShareFixture();
      },
    );
  }

  setUp(() {
    backend = FakeAiShareBackend();
    prefs = AiSharePrefsStore(MemoryPreferencesStore());
    loads = 0;
  });

  for (final stop in [
    'disable',
    'forget',
    'clear',
    'scope change',
    'disable then enable',
  ]) {
    test('pending refresh honors $stop before sending', () async {
      await prefs.recordShare(
        'c-1',
        const AiShareScope(medicationNames: true),
        24,
      );
      await prefs.setKeepUpdated('c-1', true);
      final entered = Completer<void>();
      final release = Completer<void>();
      final worker = AiShareSnapshotPusher(
        isSignedIn: () => true,
        prefs: prefs,
        client: backend.client(),
        loadData: () async {
          entered.complete();
          await release.future;
          return aiShareFixture();
        },
      );
      final pending = worker.refreshAfterStackChange();
      await entered.future;
      switch (stop) {
        case 'disable':
          await prefs.setKeepUpdated('c-1', false);
        case 'forget':
          await prefs.forget('c-1');
        case 'clear':
          await prefs.clear();
        case 'disable then enable':
          await prefs.setKeepUpdated('c-1', false);
          await prefs.setKeepUpdated('c-1', true);
        case 'scope change':
          await prefs.recordShare('c-1', AiShareScope.detailedReport, 24);
      }
      release.complete();
      await pending;
      expect(backend.uploads, isEmpty);
    });
  }

  test(
    'concurrent refreshes collect and upload in stack-change order',
    () async {
      await prefs.recordShare('c-1', AiShareScope.detailedReport, 24);
      await prefs.setKeepUpdated('c-1', true);
      final firstEntered = Completer<void>();
      final releaseFirst = Completer<void>();
      var calls = 0;
      final worker = AiShareSnapshotPusher(
        isSignedIn: () => true,
        prefs: prefs,
        client: backend.client(),
        loadData: () async {
          calls++;
          final name = calls == 1 ? 'Old stack' : 'New stack';
          if (calls == 1) {
            firstEntered.complete();
            await releaseFirst.future;
          }
          return aiShareFixture(
            stack: [aiShareEntry('s-1', name, 'supplement')],
          );
        },
      );
      final first = worker.refreshAfterStackChange();
      await firstEntered.future;
      final second = worker.refreshAfterStackChange();
      await pumpEventQueue();
      releaseFirst.complete();
      await Future.wait([first, second]);
      expect(backend.uploads.last.body['payload'], contains('New stack'));
    },
  );

  test('clear cannot be undone by an earlier preference write', () async {
    final saving = prefs.recordShare('c-1', AiShareScope.detailedReport, 24);
    final clearing = prefs.clear();
    await Future.wait([saving, clearing]);
    expect(await prefs.readAll(), isEmpty);
  });

  test(
    'a pending opt-out write blocks reads used to start a refresh',
    () async {
      final store = _HeldWriteStore();
      prefs = AiSharePrefsStore(store);
      await prefs.recordShare('c-1', AiShareScope.detailedReport, 24);
      await prefs.setKeepUpdated('c-1', true);
      store.hold = true;
      final disabling = prefs.setKeepUpdated('c-1', false);
      await store.entered.future;
      final refreshing = pusher().refreshAfterStackChange();
      await pumpEventQueue();
      final prematureUploads = backend.uploads.length;
      store.release.complete();
      await disabling;
      await refreshing;
      expect(prematureUploads, 0);
      expect(backend.uploads, isEmpty);
    },
  );

  test('off by default: a recorded share alone never re-uploads', () async {
    await prefs.recordShare('c-1', AiShareScope.detailedReport, 24);

    expect(await pusher().refreshAfterStackChange(), 0);
    expect(backend.calls, isEmpty);
    expect(loads, 0, reason: 'nothing is even prepared while off');
  });

  test('on: re-uploads with the saved scope and duration only, so a newly '
      'added medication stays out', () async {
    await prefs.recordShare('c-1', AiShareScope.detailedReport, 168);
    await prefs.setKeepUpdated('c-1', true);

    expect(await pusher().refreshAfterStackChange(), 1);

    final body = backend.uploads.single.body;
    expect(body['connection_id'], 'c-1');
    expect(body['ttl_hours'], 168);
    expect(body['scope'], AiShareScope.detailedReport.normalized.toJson());
    expect(
      body['payload'],
      const AiBriefBuilder().build(
        aiShareFixture(),
        AiShareScope.detailedReport,
      ),
    );
    for (final sensitive in aiShareSensitiveStrings) {
      expect(body['payload'], isNot(contains(sensitive)), reason: sensitive);
    }
  });

  test(
    'a medication is refreshed only when that category was chosen',
    () async {
      const withMeds = AiShareScope(medicationNames: true);
      await prefs.recordShare('c-1', withMeds, 24);
      await prefs.setKeepUpdated('c-1', true);

      await pusher().refreshAfterStackChange();

      expect(backend.uploads.single.body['payload'], contains('Lisinopril'));
      expect(
        backend.uploads.single.body['payload'],
        isNot(contains('Pregnan')),
      );
    },
  );

  test('only opted-in connections are refreshed', () async {
    await prefs.recordShare('c-1', AiShareScope.detailedReport, 24);
    await prefs.recordShare('c-2', AiShareScope.detailedReport, 24);
    await prefs.setKeepUpdated('c-2', true);

    await pusher().refreshAfterStackChange();

    expect(backend.uploads.map((c) => c.body['connection_id']), ['c-2']);
  });

  test('never runs for guests', () async {
    await prefs.recordShare('c-1', AiShareScope.detailedReport, 24);
    await prefs.setKeepUpdated('c-1', true);

    expect(await pusher(signedIn: false).refreshAfterStackChange(), 0);
    expect(backend.calls, isEmpty);
    expect(loads, 0);
  });

  test('keep-updated cannot be switched on before a share was made', () async {
    await expectLater(prefs.setKeepUpdated('c-1', true), throwsStateError);
    expect(await prefs.readAll(), isEmpty);
  });

  test('a failed refresh is contained and does not throw', () async {
    await prefs.recordShare('c-1', AiShareScope.detailedReport, 24);
    await prefs.setKeepUpdated('c-1', true);
    backend.failWith = StateError('offline');

    expect(await pusher().refreshAfterStackChange(), 0);
  });

  test('listener refreshes after a real stack change, not on first load or '
      'an unchanged reload', () async {
    var rows = <UserStacksLocalData>[
      aiShareEntry('supp-1', 'Iron Bisglycinate', 'supplement'),
    ];
    var refreshes = 0;
    final container = ProviderContainer(
      overrides: [
        activeStackProvider.overrideWith((ref) async => rows),
        aiShareSnapshotPusherProvider.overrideWithValue(
          _CountingPusher(() => refreshes++),
        ),
      ],
    );
    addTearDown(container.dispose);

    container.listen(aiShareSnapshotListenerProvider, (_, _) {});
    await container.read(activeStackProvider.future);
    await pumpEventQueue();
    expect(refreshes, 0);

    container.invalidate(activeStackProvider);
    await container.read(activeStackProvider.future);
    await pumpEventQueue();
    expect(refreshes, 0, reason: 'same rows');

    rows = [...rows, aiShareEntry('med-1', 'Lisinopril', 'medication')];
    container.invalidate(activeStackProvider);
    await container.read(activeStackProvider.future);
    await pumpEventQueue();
    expect(refreshes, 1);
  });
}

class _CountingPusher implements AiShareSnapshotPusher {
  _CountingPusher(this.onRefresh);

  final void Function() onRefresh;

  @override
  Future<int> refreshAfterStackChange() async {
    onRefresh();
    return 0;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _HeldWriteStore extends MemoryPreferencesStore {
  bool hold = false;
  final entered = Completer<void>();
  final release = Completer<void>();
  @override
  Future<void> setString(String key, String value) async {
    if (hold) {
      entered.complete();
      await release.future;
    }
    await super.setString(key, value);
  }
}
