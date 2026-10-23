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
  late List<Uri> opened;
  late int signInTaps;

  setUp(() {
    backend = FakeAiShareBackend();
    prefs = AiSharePrefsStore(MemoryPreferencesStore());
    repo = FakeAiConnectionsRepository([aiConnectionFixture()]);
    opened = [];
    signInTaps = 0;
  });

  Widget app({required bool signedIn, bool pairing = false}) => ProviderScope(
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
    ],
    child: MaterialApp(
      theme: V2Theme.light,
      home: AiConnectionsScreen(
        onSignIn: () => signInTaps++,
        onOpenExternal: (uri) async {
          opened.add(uri);
          return true;
        },
      ),
    ),
  );

  Finder keepUpdatedSwitch() => find.descendant(
    of: find.byKey(const Key('ai_keep_updated')),
    matching: find.byType(Switch),
  );

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
      await tester.tap(find.text('Preview destination'));
      await tester.pumpAndSettle();
      expect(find.text('Codex'), findsOneWidget);
      expect(find.text('chatgpt.com'), findsOneWidget);
      expect(approvals, 0);
      await tester.tap(find.text('Approve request'));
      await tester.pumpAndSettle();
      expect(approvals, 1);
      expect(
        find.textContaining('Return to your assistant or browser'),
        findsOneWidget,
      );
      expect(backend.calls, isEmpty);
    },
  );

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
    await tester.tap(find.text('Share more with this assistant'));
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

  testWidgets('disconnect deletes this connection\'s snapshots, forgets the '
      'device record and opens the website to end access', (tester) async {
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

    expect(backend.deletes.single.body, {'connection_id': id});
    expect(await prefs.read(id), isNull);
    expect(opened, [Uri.parse('https://pharmaguide.io/account/connections')]);
  });

  testWidgets('share more opens the consent screen for that connection', (
    tester,
  ) async {
    await tester.pumpWidget(app(signedIn: true));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Share more with this assistant'));
    await tester.pumpAndSettle();

    expect(find.byType(AiShareConsentScreen), findsOneWidget);
  });
}
