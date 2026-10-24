import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/theme/v2/v2_theme.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/features/ai_share/ai_connections_screen.dart';
import 'package:pharmaguide/features/ai_share/ai_connections_repository.dart';
import 'package:pharmaguide/features/ai_share/ai_share_consent_screen.dart';
import 'package:pharmaguide/features/ai_share/ai_share_providers.dart';
import 'package:pharmaguide/features/stack/providers/active_stack_provider.dart';
import 'package:pharmaguide/services/auth_state_service.dart';
import 'package:pharmaguide/services/sharing/ai_share_prefs_store.dart';
import 'package:pharmaguide/services/sharing/ai_share_scope.dart';
import 'package:pharmaguide/services/sharing/clinician_report_document_provider.dart';

import 'ai_share_test_fixtures.dart';
import '../../support/app_fonts.dart';

final _synced = DateTime.utc(2026, 10, 12, 13);

List<UserStacksLocalData> _rows() => [
  aiShareEntry('s-1', 'Iron Bisglycinate', 'supplement', syncedAt: _synced),
  aiShareEntry('s-2', 'Calcium Citrate', 'supplement', syncedAt: _synced),
  aiShareEntry('s-3', 'Fish Oil', 'supplement'),
  aiShareEntry('m-1', 'Lisinopril', 'medication'),
];

void main() {
  setUpAll(loadAppFonts);
  late FakeAiShareBackend backend;
  late AiSharePrefsStore prefs;
  late FakeAiConnectionsRepository repo;
  late int signInTaps;

  setUp(() {
    backend = FakeAiShareBackend();
    prefs = AiSharePrefsStore(MemoryPreferencesStore());
    repo = FakeAiConnectionsRepository([aiConnectionFixture()]);
    signInTaps = 0;
  });

  Widget app({
    required bool signedIn,
    bool pairing = false,
    String? approvalCode,
    Future<String?> Function()? pendingRevocation,
  }) => ProviderScope(
    overrides: [
      aiPairingEnabledProvider.overrideWithValue(pairing),
      authStateProvider.overrideWith((ref) {
        final service = AuthStateService();
        if (signedIn) service.onSignedIn();
        return service;
      }),
      activeStackProvider.overrideWith((ref) async => _rows()),
      clinicianReportDataProvider.overrideWith((ref) async => aiShareFixture()),
      aiShareSnapshotClientProvider.overrideWithValue(backend.client()),
      aiSharePrefsStoreProvider.overrideWithValue(prefs),
      aiConnectionsRepositoryProvider.overrideWithValue(repo),
      if (pendingRevocation != null)
        aiPendingRevocationProvider.overrideWith((ref) => pendingRevocation()),
    ],
    child: MaterialApp(
      theme: V2Theme.light,
      home: approvalCode != null
          ? AiPairingScreen(initialCode: approvalCode)
          : AiConnectionsScreen(onSignIn: () => signInTaps++),
    ),
  );

  Finder keepUpdatedSwitch() => find.descendant(
    of: find.byKey(const Key('ai_keep_updated')),
    matching: find.byType(Switch),
  );

  testWidgets('twenty ended connections stay in collapsed history', (
    tester,
  ) async {
    repo = FakeAiConnectionsRepository([
      for (var i = 0; i < 20; i++)
        aiConnectionFixture(
          id: 'old-$i',
          clientId: 'Old assistant $i',
          status: i.isEven ? 'revoked' : 'expired',
        ),
    ]);
    await tester.pumpWidget(app(signedIn: true));
    await tester.pumpAndSettle();
    expect(find.text('No active connections.'), findsOneWidget);
    expect(find.text('Connection history (20)'), findsOneWidget);
    expect(find.text('Old assistant 0'), findsNothing);
    expect(find.text('Disconnect'), findsNothing);
    await tester.tap(find.text('Connection history (20)'));
    await tester.pumpAndSettle();
    expect(find.text('Old assistant 0'), findsOneWidget);
    expect(find.text('Old assistant 19'), findsOneWidget);
    expect(find.text('Manage assistant access'), findsNothing);
    await tester.ensureVisible(find.text('Connection history (20)'));
    await tester.tap(find.text('Connection history (20)'));
    await tester.pumpAndSettle();
    expect(find.text('Old assistant 0'), findsNothing);
  });

  testWidgets('active connection and pending cleanup stay outside history', (
    tester,
  ) async {
    repo = FakeAiConnectionsRepository([
      aiConnectionFixture(id: 'active', clientId: 'Current assistant'),
      aiConnectionFixture(
        id: 'pending',
        clientId: 'Pending assistant',
        status: 'revoked',
      ),
      aiConnectionFixture(
        id: 'older-pending',
        clientId: 'Pending assistant',
        status: 'revoked',
      ),
      aiConnectionFixture(
        id: 'old',
        clientId: 'Old assistant',
        status: 'revoked',
      ),
    ]);
    repo.pendingClient = 'Pending assistant';
    await tester.pumpWidget(app(signedIn: true));
    await tester.pumpAndSettle();
    expect(find.text('Current assistant'), findsOneWidget);
    expect(find.text('Pending assistant'), findsOneWidget);
    expect(find.text('NEEDS ATTENTION'), findsOneWidget);
    expect(find.text('Old assistant'), findsNothing);
    expect(find.text('Connection history (2)'), findsOneWidget);
    expect(find.text('Retry disconnect'), findsOneWidget);
    repo.pendingClient = null;
    await tester.tap(find.byTooltip('Refresh connections'));
    await tester.pumpAndSettle();
    expect(find.text('Pending assistant'), findsNothing);
    expect(find.text('Connection history (3)'), findsOneWidget);
    expect(find.text('Current assistant'), findsOneWidget);
  });

  testWidgets(
    'expired access stays in history even with an active row status',
    (tester) async {
      final now = DateTime.now().toUtc();
      repo = FakeAiConnectionsRepository([
        AiConnection(
          connectionId: 'expired',
          clientId: 'Expired assistant',
          status: 'active',
          createdAt: now.subtract(const Duration(days: 2)),
          expiresAt: now.subtract(const Duration(days: 1)),
        ),
      ]);
      await tester.pumpWidget(app(signedIn: true));
      await tester.pumpAndSettle();
      expect(find.text('Expired assistant'), findsNothing);
      expect(find.text('No active connections.'), findsOneWidget);
      await tester.tap(find.text('Connection history (1)'));
      await tester.pumpAndSettle();
      expect(find.text('EXPIRED'), findsOneWidget);
      expect(find.text('Disconnect'), findsNothing);
      expect(find.text('Manage assistant access'), findsNothing);
    },
  );

  testWidgets('deep-linked connections can return to profile navigation', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: Routes.aiConnections,
      routes: [
        GoRoute(
          path: Routes.aiConnections,
          builder: (_, _) => const AiConnectionsScreen(),
        ),
        GoRoute(
          path: Routes.profile,
          builder: (_, _) => const Scaffold(body: Text('Profile navigation')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateProvider.overrideWith(
            (ref) => AuthStateService()..onSignedOut(),
          ),
        ],
        child: MaterialApp.router(theme: V2Theme.light, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(BackButton), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Profile navigation'), findsOneWidget);
    expect(router.routeInformationProvider.value.uri.path, Routes.profile);
  });

  for (final action in ['cancel', 'back']) {
    testWidgets('root approval $action returns to connections', (tester) async {
      var cancellations = 0;
      repo.preview = (_) async => AiPairingPreview(
        clientName: 'Codex',
        callbackHost: 'chatgpt.com',
        expiresAt: DateTime.now().add(const Duration(minutes: 5)),
      );
      repo.cancel = (_) async {
        cancellations++;
      };
      final router = GoRouter(
        initialLocation: '${Routes.aiConnections}?code=ABCDEFGHJKMN',
        routes: [
          GoRoute(
            path: Routes.aiConnections,
            builder: (_, state) => state.uri.hasQuery
                ? const AiPairingScreen(initialCode: 'ABCDEFGHJKMN')
                : const Scaffold(body: Text('Connections destination')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            aiPairingEnabledProvider.overrideWithValue(true),
            authStateProvider.overrideWith(
              (ref) => AuthStateService()..onSignedIn(),
            ),
            aiConnectionsRepositoryProvider.overrideWithValue(repo),
          ],
          child: MaterialApp.router(theme: V2Theme.light, routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      if (action == 'cancel') {
        await tester.tap(find.text('Cancel request'));
      } else {
        expect(find.byType(BackButton), findsOneWidget);
        await tester.tap(find.byType(BackButton));
      }
      await tester.pumpAndSettle();
      expect(find.text('Connections destination'), findsOneWidget);
      expect(cancellations, action == 'cancel' ? 1 : 0);
    });
  }

  testWidgets('connections opened from settings return to the previous page', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateProvider.overrideWith(
            (ref) => AuthStateService()..onSignedOut(),
          ),
        ],
        child: MaterialApp(
          theme: V2Theme.light,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AiConnectionsScreen(),
                  ),
                ),
                child: const Text('Settings origin'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Settings origin'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Settings origin'), findsOneWidget);
  });

  testWidgets(
    'refresh connections updates revocation without lifecycle event',
    (tester) async {
      await tester.pumpWidget(app(signedIn: true));
      await tester.pumpAndSettle();
      final before = repo.loads;
      repo.connections[0] = aiConnectionFixture(status: 'revoked');
      await tester.tap(find.byTooltip('Refresh connections'));
      await tester.pumpAndSettle();
      expect(repo.loads, greaterThan(before));
      expect(find.text('Connection history (1)'), findsOneWidget);
      expect(find.textContaining('Access ended'), findsNothing);
      expect(find.text('Disconnect'), findsNothing);
    },
  );

  testWidgets('returning from browser refreshes revoked connections', (
    tester,
  ) async {
    await tester.pumpWidget(app(signedIn: true));
    await tester.pumpAndSettle();
    final before = repo.loads;
    repo.connections[0] = aiConnectionFixture(status: 'revoked');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(repo.loads, greaterThan(before));
    expect(find.text('Connection history (1)'), findsOneWidget);
    await tester.tap(find.text('Connection history (1)'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Access ended'), findsOneWidget);
  });

  testWidgets(
    'account switch while preferences write cannot disconnect new account',
    (tester) async {
      final store = MemoryPreferencesStore();
      prefs = AiSharePrefsStore(store);
      await prefs.recordShare(
        repo.connections.first.connectionId,
        AiShareScope.detailedReport,
        24,
        keepUpdated: true,
      );
      final write = Completer<void>();
      store.beforeWrite = () => write.future;
      await tester.pumpWidget(app(signedIn: true));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Disconnect'));
      await tester.tap(find.text('Disconnect'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ai_disconnect_confirm')));
      await tester.pump();
      repo.pairingSessionIdentity = 'different-account';
      write.complete();
      await tester.pumpAndSettle();
      expect(repo.disconnectCalls, 0);
      expect(
        find.text('Assistant disconnected. Access has ended.'),
        findsNothing,
      );
    },
  );

  testWidgets(
    'pending cleanup with no connection row can retry after reopening',
    (tester) async {
      repo.connections.clear();
      repo.pendingClient = 'client_orphan';
      repo.onDisconnect = (id) async {
        expect(id, 'client_orphan');
        repo.pendingClient = null;
        return AiDisconnectResult.disconnected;
      };
      await tester.pumpWidget(app(signedIn: true));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retry disconnect'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ai_disconnect_confirm')));
      await tester.pumpAndSettle();
      expect(repo.disconnectCalls, 1);
      expect(find.text('Retry disconnect'), findsNothing);
    },
  );

  for (final cleanup in ['loaded', 'error']) {
    testWidgets(
      'partial disconnect stays visible while cleanup status $cleanup',
      (tester) async {
        final pendingStatus = Completer<String?>();
        var loadingCleanup = false;
        repo.onDisconnect = (_) async {
          repo.connections[0] = aiConnectionFixture(status: 'revoked');
          loadingCleanup = true;
          return AiDisconnectResult.localAccessEnded;
        };
        await tester.pumpWidget(
          app(
            signedIn: true,
            pendingRevocation: () =>
                loadingCleanup ? pendingStatus.future : Future.value(null),
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Disconnect'));
        await tester.tap(find.text('Disconnect'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('ai_disconnect_confirm')));
        await tester.pumpAndSettle();
        expect(find.text('NEEDS ATTENTION'), findsOneWidget);
        expect(find.text('Connection history (1)'), findsNothing);
        if (cleanup == 'error') {
          pendingStatus.completeError(StateError('offline status'));
        } else {
          pendingStatus.complete(repo.connections.first.clientId);
        }
        await tester.pumpAndSettle();
        expect(find.text('Retry disconnect'), findsOneWidget);
        expect(find.text('NEEDS ATTENTION'), findsOneWidget);
        expect(find.text('Connection history (1)'), findsNothing);
      },
    );
  }

  for (final outcome in ['success', 'partial', 'offline']) {
    testWidgets('native disconnect $outcome is truthful and retryable', (
      tester,
    ) async {
      await prefs.recordShare(
        repo.connections.first.connectionId,
        AiShareScope.detailedReport,
        24,
        keepUpdated: true,
      );
      final pending = Completer<AiDisconnectResult>();
      repo.onDisconnect = (_) => pending.future;
      await tester.pumpWidget(app(signedIn: true));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Disconnect'));
      await tester.tap(find.text('Disconnect'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ai_disconnect_confirm')));
      await tester.pumpAndSettle();
      expect(repo.disconnectCalls, 1);
      expect(await prefs.read(repo.connections.first.connectionId), isNull);
      await tester.tap(find.text('Disconnecting…'));
      await tester.pump();
      expect(repo.disconnectCalls, 1);
      if (outcome == 'offline') {
        pending.completeError(const AiDisconnectException());
      } else {
        repo.connections[0] = aiConnectionFixture(status: 'revoked');
        if (outcome == 'partial') {
          repo.pendingClient = repo.connections.first.clientId;
        }
        pending.complete(
          outcome == 'success'
              ? AiDisconnectResult.disconnected
              : AiDisconnectResult.localAccessEnded,
        );
      }
      await tester.pumpAndSettle();
      expect(backend.deletes, isEmpty);
      if (outcome == 'success') {
        expect(
          find.text('Assistant disconnected. Access has ended.'),
          findsOneWidget,
        );
        expect(find.text('Connection history (1)'), findsOneWidget);
        expect(find.text('claude-ai'), findsNothing);
        expect(find.text('Disconnect'), findsNothing);
      } else if (outcome == 'partial') {
        expect(find.text('Retry disconnect'), findsOneWidget);
        await tester.tap(find.byTooltip('Refresh connections'));
        await tester.pumpAndSettle();
        expect(find.text('Retry disconnect'), findsOneWidget);
        repo.onDisconnect = (_) async {
          repo.pendingClient = null;
          return AiDisconnectResult.disconnected;
        };
        await tester.ensureVisible(find.text('Retry disconnect'));
        await tester.tap(find.text('Retry disconnect'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('ai_disconnect_confirm')));
        await tester.pumpAndSettle();
        expect(repo.disconnectCalls, 2);
        expect(find.text('Retry disconnect'), findsNothing);
      } else {
        expect(
          find.text(
            'Disconnect could not be confirmed. Automatic updates are off. Try again.',
          ),
          findsOneWidget,
        );
        expect(find.text('Retry disconnect'), findsOneWidget);
        expect(find.text('NEEDS ATTENTION'), findsOneWidget);
        expect(find.textContaining('Access ended'), findsNothing);
        expect(find.text('Manage assistant access'), findsNothing);
        repo.onDisconnect = (_) async {
          repo.connections[0] = aiConnectionFixture(status: 'revoked');
          return AiDisconnectResult.disconnected;
        };
        await tester.ensureVisible(find.text('Retry disconnect'));
        await tester.tap(find.text('Retry disconnect'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('ai_disconnect_confirm')));
        await tester.pumpAndSettle();
        expect(repo.disconnectCalls, 2);
        expect(find.text('Retry disconnect'), findsNothing);
        expect(find.text('Connection history (1)'), findsOneWidget);
      }
    });
  }

  testWidgets(
    'pairing previews destination before explicit approval, never shares',
    (tester) async {
      repo.preview = (code) async {
        expect(code, 'ABCDEFGHJKMN');
        return AiPairingPreview(
          clientName: 'Codex',
          callbackHost: 'chatgpt.com',
          expiresAt: DateTime.now().add(const Duration(minutes: 5)),
        );
      };
      var approvals = 0;
      repo.approve = (_) async {
        approvals++;
      };
      await tester.pumpWidget(app(signedIn: true, pairing: true));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enter approval code'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'abcd-efgh jkmn');
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'ABCD-EFGH-JKMN',
      );
      await tester.tap(find.text('Preview destination'));
      await tester.pumpAndSettle();
      expect(find.text('Codex'), findsOneWidget);
      expect(find.text('chatgpt.com'), findsOneWidget);
      expect(approvals, 0);
      await tester.tap(find.text('Approve request'));
      await tester.pumpAndSettle();
      expect(approvals, 1);
      expect(
        find.textContaining('Keep the connection page open'),
        findsOneWidget,
      );
      expect(backend.calls, isEmpty);
    },
  );

  testWidgets('confirmed phone approval returns to refreshed connections', (
    tester,
  ) async {
    repo.preview = (_) async => AiPairingPreview(
      clientName: 'Codex',
      callbackHost: 'chatgpt.com',
      expiresAt: DateTime.now().add(const Duration(minutes: 5)),
    );
    repo.approve = (_) async {};
    repo.approvedConnectionId = '6f1c2a3b-0000-4000-8000-000000000001';
    await tester.pumpWidget(app(signedIn: true, pairing: true));
    await tester.pumpAndSettle();
    final loads = repo.loads;
    await tester.tap(find.text('Enter approval code'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'ABCDEFGHJKMN');
    await tester.tap(find.text('Preview destination'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Approve request'));
    await tester.pumpAndSettle();
    expect(find.text('Your assistant connections'), findsOneWidget);
    expect(find.text('Approved on this phone'), findsNothing);
    expect(repo.loads, greaterThan(loads));
    expect(backend.calls, isEmpty);
  });

  testWidgets('app link previews exact code but never approves automatically', (
    tester,
  ) async {
    var previews = 0;
    var approvals = 0;
    repo.preview = (code) async {
      previews++;
      expect(code, 'ABCDEFGHJKMN');
      return AiPairingPreview(
        clientName: 'Codex',
        callbackHost: 'chatgpt.com',
        expiresAt: DateTime.now().add(const Duration(minutes: 5)),
      );
    };
    repo.approve = (_) async {
      approvals++;
    };
    await tester.pumpWidget(
      app(signedIn: true, pairing: true, approvalCode: 'ABCD-EFGH-JKMN'),
    );
    await tester.pumpAndSettle();
    expect(previews, 1);
    expect(approvals, 0);
    expect(find.text('Check this destination'), findsOneWidget);
    expect(find.textContaining('adults aged 18 and over'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('app link cannot enable disabled phone approvals', (
    tester,
  ) async {
    var previews = 0;
    repo.preview = (_) async {
      previews++;
      throw const AiPairingException();
    };
    await tester.pumpWidget(app(signedIn: true, approvalCode: 'ABCDEFGHJKMN'));
    await tester.pumpAndSettle();
    expect(previews, 0);
    await tester.tap(find.text('Preview destination'));
    await tester.pumpAndSettle();
    expect(previews, 0);
  });

  testWidgets('late pairing response after closing is ignored', (tester) async {
    final pending = Completer<AiPairingPreview>();
    repo.preview = (_) => pending.future;
    await tester.pumpWidget(app(signedIn: true, pairing: true));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enter approval code'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'ABCDEFGHJKMN');
    await tester.tap(find.text('Preview destination'));
    await tester.pump();
    await tester.pageBack();
    await tester.pumpAndSettle();
    pending.complete(
      AiPairingPreview(
        clientName: 'Codex',
        callbackHost: 'chatgpt.com',
        expiresAt: DateTime.now().add(const Duration(minutes: 5)),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Codex'), findsNothing);
  });

  for (final outcome in [
    'expired',
    'account changed',
    'cancel',
    'error',
    'signed out',
  ]) {
    testWidgets('pairing fails closed or cancels: $outcome', (tester) async {
      var approvals = 0;
      var cancellations = 0;
      final pending = Completer<AiPairingPreview>();
      repo.preview = (_) => pending.future;
      repo.approve = (_) async {
        approvals++;
      };
      repo.cancel = (_) async {
        cancellations++;
      };
      await tester.pumpWidget(app(signedIn: true, pairing: true));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enter approval code'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'ABCDEFGHJKMN');
      await tester.tap(find.text('Preview destination'));
      await tester.pump();
      if (outcome == 'account changed') {
        repo.pairingSessionIdentity = 'other-account';
      }
      if (outcome == 'signed out') {
        final container = ProviderScope.containerOf(
          tester.element(find.byType(TextField)),
        );
        container.read(authStateProvider.notifier).onSignedOut();
      }
      if (outcome == 'error') {
        pending.completeError(StateError('secret error payload'));
      } else {
        pending.complete(
          AiPairingPreview(
            clientName: 'Codex',
            callbackHost: 'chatgpt.com',
            expiresAt: DateTime.now().add(const Duration(seconds: 2)),
          ),
        );
      }
      await tester.pumpAndSettle();
      if (outcome == 'expired') {
        await tester.pump(const Duration(seconds: 3));
        expect(find.textContaining('This code has expired'), findsOneWidget);
        await tester.tap(find.text('Approve request'));
      } else if (outcome == 'cancel') {
        await tester.tap(find.text('Cancel request'));
        await tester.pumpAndSettle();
        expect(cancellations, 1);
        expect(find.text('Check this destination'), findsNothing);
      } else {
        expect(find.text('Approve request'), findsNothing);
        expect(
          find.textContaining('This request could not be completed'),
          findsOneWidget,
        );
        expect(find.textContaining('secret error payload'), findsNothing);
      }
      expect(approvals, 0);
      expect(backend.calls, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }

  testWidgets('phone preview fits long destination at larger text size', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    repo.preview = (_) async => AiPairingPreview(
      clientName: 'Codex desktop assistant',
      callbackHost: 'verified-assistant-callback.example.com',
      expiresAt: DateTime.now().add(const Duration(minutes: 5)),
    );
    await tester.pumpWidget(
      RepaintBoundary(
        key: const Key('pairing_render'),
        child: app(signedIn: true, pairing: true),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enter approval code'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'ABCDEFGHJKMN');
    await tester.tap(find.text('Preview destination'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Cancel request'));
    expect(tester.takeException(), isNull);
    final output = Platform.environment['PG_PAIRING_RENDER_PATH'];
    if (output != null) {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('pairing_render')),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(output).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  test('connection parser keeps only valid stored display metadata', () {
    final row = <String, Object?>{
      'connection_id': 'connection-1',
      'client_id': 'opaque-client-id',
      'status': 'active',
      'created_at': '2026-10-13T00:00:00Z',
      'expires_at': '2026-11-13T00:00:00Z',
      'client_name': ' Claude ',
      'callback_host': ' claude.ai ',
    };
    final named = AiConnection.tryParse(row)!;
    expect(named.displayName, 'Claude');
    expect(named.callbackHost, 'claude.ai');
    for (final malformed in [null, '', '   ', 42, 'x' * 201]) {
      final legacy = AiConnection.tryParse({
        ...row,
        'client_name': malformed,
        'callback_host': malformed,
      })!;
      expect(legacy.displayName, 'opaque-client-id');
      expect(legacy.callbackHost, isNull);
    }
  });

  testWidgets('guest: explains an account is needed and never queries', (
    tester,
  ) async {
    await tester.pumpWidget(app(signedIn: false));
    await tester.pumpAndSettle();

    expect(find.textContaining('needs a PharmaGuide account'), findsOneWidget);
    await tester.tap(find.text('Sign in'));
    expect(signInTaps, 1);
    expect(repo.loads, 0);
  });

  testWidgets('signed in: lists the connection and counts only synced '
      'supplements', (tester) async {
    await tester.pumpWidget(app(signedIn: true));
    await tester.pumpAndSettle();

    expect(find.text('claude-ai'), findsOneWidget);
    expect(find.text('Personal access is not enabled'), findsOneWidget);
    expect(find.text('Enter approval code'), findsNothing);
    expect(find.text('ACTIVE'), findsOneWidget);
  });

  testWidgets('shows stored verified assistant name and callback host', (
    tester,
  ) async {
    final now = DateTime.now().toUtc();
    repo = FakeAiConnectionsRepository([
      AiConnection.tryParse({
        'connection_id': 'connection-1',
        'client_id': 'opaque-client-id',
        'client_name': 'Claude',
        'callback_host': 'claude.ai',
        'status': 'active',
        'created_at': now.toIso8601String(),
        'expires_at': now.add(const Duration(days: 1)).toIso8601String(),
      })!,
    ]);
    await tester.pumpWidget(app(signedIn: true));
    await tester.pumpAndSettle();
    expect(find.text('Claude'), findsOneWidget);
    expect(find.textContaining('claude.ai'), findsOneWidget);
    await tester.tap(find.text('Manage assistant access'));
    await tester.pumpAndSettle();
    final consent = find.byKey(const Key('ai_share_consent_card'));
    expect(
      find.descendant(of: consent, matching: find.text('Claude')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: consent, matching: find.text('claude.ai')),
      findsOneWidget,
    );
  });

  testWidgets(
    'durable connection shows until disconnect, independent of snapshots',
    (tester) async {
      repo = FakeAiConnectionsRepository([
        AiConnection.tryParse({
          'connection_id': 'durable-connection',
          'client_id': 'codex-client',
          'client_name': 'Codex',
          'callback_host': '127.0.0.1',
          'status': 'active',
          'created_at': DateTime.now().toUtc().toIso8601String(),
          'expires_at': null,
          'oauth_issuer': 'https://issuer.authkit.app',
          'consent_id': 'app_consent_durable',
        })!,
      ]);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        RepaintBoundary(
          key: const Key('durable_render'),
          child: app(signedIn: true, pairing: true),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Until you disconnect'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final output = Platform.environment['PG_DURABLE_RENDER_PATH'];
      if (output != null) {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const Key('durable_render')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(output).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    },
  );

  testWidgets('keep updated is off by default and needs a first share', (
    tester,
  ) async {
    await tester.pumpWidget(app(signedIn: true));
    await tester.pumpAndSettle();

    final off = tester.widget<Switch>(keepUpdatedSwitch());
    expect(off.value, isFalse);
    expect(off.onChanged, isNull);
  });

  testWidgets('keep updated turns on only for this connection, on device', (
    tester,
  ) async {
    final id = aiConnectionFixture().connectionId;
    await prefs.recordShare(id, AiShareScope.detailedReport, 24);
    await tester.pumpWidget(app(signedIn: true));
    await tester.pumpAndSettle();

    await tester.ensureVisible(keepUpdatedSwitch());
    await tester.tap(keepUpdatedSwitch());
    await tester.pumpAndSettle();

    expect((await prefs.read(id))?.keepUpdated, isTrue);
    expect(backend.calls, isEmpty, reason: 'opting in uploads nothing');
  });

  testWidgets(
    'disconnect forgets device preferences and uses canonical cleanup API',
    (tester) async {
      final id = aiConnectionFixture().connectionId;
      await prefs.recordShare(id, AiShareScope.detailedReport, 24);
      await tester.pumpWidget(app(signedIn: true));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Disconnect'));
      await tester.tap(find.text('Disconnect'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('cannot erase what the assistant already kept'),
        findsWidgets,
      );
      await tester.tap(find.byKey(const Key('ai_disconnect_confirm')));
      await tester.pumpAndSettle();

      expect(backend.deletes, isEmpty);
      expect(await prefs.read(id), isNull);
      expect(repo.disconnectCalls, 1);
    },
  );

  testWidgets('disconnected connection caption says access ended', (
    tester,
  ) async {
    repo = FakeAiConnectionsRepository([
      aiConnectionFixture(status: 'revoked'),
    ]);
    await tester.pumpWidget(app(signedIn: true));
    await tester.pumpAndSettle();
    expect(find.text('Connection history (1)'), findsOneWidget);
    await tester.tap(find.text('Connection history (1)'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Access ended'), findsOneWidget);
    expect(find.textContaining('Access ends '), findsNothing);
    expect(find.textContaining('Until you disconnect'), findsNothing);
  });

  for (final hours in [168, 720]) {
    testWidgets('manage preserves saved scope and $hours hour duration', (
      tester,
    ) async {
      final id = aiConnectionFixture().connectionId;
      await prefs.recordShare(id, AiShareScope.simpleList, hours);
      await prefs.setKeepUpdated(id, true);
      await tester.pumpWidget(app(signedIn: true));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Manage assistant access'));
      await tester.pumpAndSettle();
      expect(backend.calls, isEmpty, reason: 'opening settings never shares');
      final switches = tester.widgetList<Switch>(find.byType(Switch));
      expect(
        switches.where((s) => s.value).length,
        0,
        reason: 'only saved supplement names are enabled',
      );
      await tester.tap(find.byKey(const Key('ai_share_submit')));
      await tester.pumpAndSettle();
      expect(
        backend.uploads.single.body['scope'],
        AiShareScope.simpleList.toJson(),
      );
      expect(backend.uploads.single.body['ttl_hours'], hours);
      final saved = await prefs.read(id);
      expect(saved?.scope, AiShareScope.simpleList);
      expect(saved?.ttlHours, hours);
      expect(saved?.keepUpdated, true);
    });
  }

  testWidgets('share more opens the consent screen for that connection', (
    tester,
  ) async {
    await tester.pumpWidget(app(signedIn: true));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Manage assistant access'));
    await tester.pumpAndSettle();

    expect(find.byType(AiShareConsentScreen), findsOneWidget);
  });
}
