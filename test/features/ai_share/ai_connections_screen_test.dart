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

final _synced = DateTime.utc(2026, 10, 12, 13);

List<UserStacksLocalData> _rows() => [
  aiShareEntry('s-1', 'Iron Bisglycinate', 'supplement', syncedAt: _synced),
  aiShareEntry('s-2', 'Calcium Citrate', 'supplement', syncedAt: _synced),
  aiShareEntry('s-3', 'Fish Oil', 'supplement'),
  aiShareEntry('m-1', 'Lisinopril', 'medication'),
];

void main() {
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

  Widget app({required bool signedIn}) => ProviderScope(
    overrides: [
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
    expect(find.text('2 supplements available to assistants'), findsOneWidget);
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
