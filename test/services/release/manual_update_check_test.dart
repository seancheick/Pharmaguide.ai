// The Settings update check, from the tile down: the real PharmaGuideBootstrap,
// ReleaseStore, updater and SyncService, over real HTTP to a local server, with
// real SQLite files. Only the app under the ProviderScope is small.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pharmaguide/app.dart' show scaffoldMessengerKey;
import 'package:pharmaguide/core/components/pg_settings_tile.dart';
import 'package:pharmaguide/core/navigation/launch_link_buffer.dart';
import 'package:pharmaguide/core/widgets/withheld_checks_notice.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/interaction_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/settings/providers/notification_settings_provider.dart';
import 'package:pharmaguide/features/settings/v2/settings_v2_connected.dart';
import 'package:pharmaguide/main.dart';
import 'package:pharmaguide/services/auth/account_storage.dart';
import 'package:pharmaguide/services/auth/pg_auth_service.dart';
import 'package:pharmaguide/services/catalog_updater_service.dart';
import 'package:pharmaguide/services/crash_reporting_service.dart';
import 'package:pharmaguide/services/notifications/notification_authorization_service.dart';
import 'package:pharmaguide/services/release_store.dart';
import 'package:pharmaguide/services/settings/app_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'release_fixtures.dart';

const _bundledCatalog = '2026.01.01.000000';
const _newerCatalog = '2026.02.01.000000';
const _tile = 'Check for updates';
const _upToDate = 'You’re up to date.';
const _updateReady = 'An update is ready and now in use.';
const _couldNotCheck = 'Couldn’t check right now.';
const _deviceChanged = 'PharmaGuide changed the data used on this device.';

class _Publisher {
  HttpServer? server;
  int _port = 0;
  int get port => _port;
  Map<String, Object?>? row;
  final Map<String, Uint8List> files = {};
  final List<String> downloads = [];
  bool failing = false;

  Future<void> start() async {
    final bound = await HttpServer.bind(InternetAddress.loopbackIPv4, _port);
    server = bound;
    _port = bound.port;
    bound.listen((request) async {
      final path = request.uri.path;
      final response = request.response;
      if (failing) {
        response.statusCode = 503;
      } else if (path == '/rest/v1/export_manifest') {
        final wantsObject = request.headers
            .value('accept')
            ?.contains('vnd.pgrst.object');
        response.headers.contentType = ContentType.json;
        response.write(
          jsonEncode(wantsObject == true ? row : [if (row != null) row]),
        );
      } else if (path.startsWith('/storage/v1/object/public/pharmaguide/')) {
        final key = path.substring(
          '/storage/v1/object/public/pharmaguide/'.length,
        );
        final bytes = files[key];
        if (bytes == null) {
          response.statusCode = 404;
        } else {
          downloads.add(key);
          response.contentLength = bytes.length;
          response.add(bytes);
        }
      } else {
        response.statusCode = 503;
      }
      await response.close();
    });
  }

  /// Connection refused, which is what a phone with no network gets.
  Future<void> goOffline() async {
    await server?.close(force: true);
    server = null;
  }
}

/// Stands in for the app: Settings over the bootstrap's own scope. It counts
/// mounts, because a new mount means the app rebuilt under whoever was reading.
class _App extends ConsumerStatefulWidget {
  const _App({required this.onMount, required this.userDb});

  /// [rules] is null when the bootstrap has withheld them.
  final void Function(CoreDatabase core, InteractionDatabase? rules) onMount;
  final UserDatabase userDb;

  @override
  ConsumerState<_App> createState() => _AppState();
}

class _AppState extends ConsumerState<_App> {
  @override
  void initState() {
    super.initState();
    InteractionDatabase? rules;
    try {
      rules = ref.read(interactionDatabaseProvider);
    } on Object {
      rules = null;
    }
    widget.onMount(ref.read(coreDatabaseProvider), rules);
  }

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        notificationSettingsControllerProvider.overrideWith(
          (ref) => NotificationSettingsController(
            service: const _NotificationsAllowed(),
          ),
        ),
      ],
      child: MaterialApp(
        scaffoldMessengerKey: scaffoldMessengerKey,
        home: const SettingsV2Connected(),
      ),
    );
  }
}

class _NotificationsAllowed implements NotificationAuthorizationService {
  const _NotificationsAllowed();

  @override
  Future<NotificationAuthorizationStatus> readStatus() async =>
      NotificationAuthorizationStatus.allowed;

  @override
  Future<NotificationAuthorizationStatus> requestPermission() async =>
      NotificationAuthorizationStatus.allowed;

  @override
  Future<void> openNotificationSettings() async {}
}

class _MemoryStore implements AppPreferencesStore {
  final Map<String, Object> _values = {};

  @override
  Future<String?> getString(String key) async => _values[key] as String?;

  @override
  Future<bool?> getBool(String key) async => _values[key] as bool?;

  @override
  Future<void> setString(String key, String value) async =>
      _values[key] = value;

  @override
  Future<void> setBool(String key, bool value) async => _values[key] = value;
}

void main() {
  late _Publisher publisher;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    await CrashReportingService().initialize();
    publisher = _Publisher();
    await publisher.start();
    await Supabase.initialize(
      url: 'http://127.0.0.1:${publisher.port}',
      publishableKey: 'fixture-only',
      debug: false,
    );
  });

  tearDownAll(() => publisher.goOffline());

  late Directory workspace;
  late FakeReleaseBundle bundle;
  late ReleaseStore store;
  late bool failOpen;
  late bool diskFull;
  late AccountSwitchGuard guard;
  late int mounts;
  late CoreDatabase core;
  late InteractionDatabase? rules;

  /// A launch's own guard. The last one's database closed with its app.
  Future<AccountSwitchGuard> openAccount() async {
    final root = Directory(p.join(workspace.path, 'account'))
      ..createSync(recursive: true);
    final opened = AccountSwitchGuard(
      ownerStore: AccountOwnerStore(),
      storage: AccountStorage(
        supportDirectory: () async => root,
        documentsDirectory: () async => root,
      ),
      openDatabase: (path) async => UserDatabase.open(path),
    );
    await opened.boot(sessionUid: null);
    return opened;
  }

  setUp(() async {
    if (publisher.server == null) await publisher.start();
    workspace = await Directory.systemTemp.createTemp('manual-update-check');
    final documents = Directory(p.join(workspace.path, 'documents'))
      ..createSync();
    bundle = await FakeReleaseBundle.build(
      workspace,
      catalogVersion: _bundledCatalog,
      rulesVersion: '1.0.15',
    );
    failOpen = false;
    diskFull = false;
    store = ReleaseStore(
      documents: documents,
      bundle: bundle,
      onStep: (step) {
        if (failOpen && step == ReleaseStep.openNew) {
          throw StateError('This file will not open here');
        }
        if (diskFull && step == ReleaseStep.writeRecord) {
          throw StateError('The disk is full');
        }
      },
    );
    guard = await openAccount();
    mounts = 0;
    publisher
      ..row = null
      ..files.clear()
      ..downloads.clear()
      ..failing = false;
  });

  tearDown(() => workspace.delete(recursive: true));

  Future<void> settleReal(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 6000 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump();
    }
    expect(done(), isTrue, reason: 'timed out waiting');
  }

  Future<void> boot(
    WidgetTester tester, {
    bool supabaseReady = true,
    Widget? app,
    ReleaseStore? relaunchedStore,
  }) async {
    // Settings is a long list; the tile has to be built to be tapped.
    tester.view.physicalSize = const Size(1200, 6000);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      PharmaGuideBootstrap(
        accountGuard: guard,
        supabaseReady: supabaseReady,
        hasSeenOnboarding: true,
        appPreferencesController: AppPreferencesController(
          repository: AppPreferencesRepository(_MemoryStore()),
        ),
        launchLinks: LaunchLinkBuffer(),
        releaseStoreForTesting: relaunchedStore ?? store,
        appForTesting:
            app ??
            _App(
              userDb: guard.database!,
              onMount: (c, r) {
                mounts++;
                core = c;
                rules = r;
              },
            ),
      ),
    );
    if (app == null) {
      await settleReal(tester, () => tester.any(find.text('Offline mode')));
    }
  }

  /// Taps the real tile on the real event loop, and waits for its line.
  Future<void> checkForUpdates(WidgetTester tester) async {
    final tile = tester.widget<PGSettingsTile>(
      find.widgetWithText(PGSettingsTile, _tile),
    );
    await tester.runAsync(() async => tile.onTap!());
    await settleReal(
      tester,
      () =>
          tester.any(find.text(_upToDate)) ||
          tester.any(find.text(_updateReady)) ||
          tester.any(find.text(_couldNotCheck)) ||
          tester.any(find.text(_deviceChanged)),
    );
  }

  /// What a result on screen is computed from.
  Future<Map<String, Object?>> results() async {
    final row = await core
        .customSelect(
          'SELECT quality_score_v4_100, quality_tier, product_safety_status '
          'FROM products_core WHERE dsld_id = ?',
          variables: [Variable.withString(kFixtureProduct)],
        )
        .getSingle();
    return {...row.data, 'rule': await severityIn(rules!)};
  }

  Future<void> expectNothingChanged(
    WidgetTester tester,
    Future<void> Function() arrange, {
    Future<void> Function()? afterFirstCheck,
  }) async {
    await boot(tester);
    final releaseBefore = store.active!.id;
    final coreBefore = core;
    final rulesBefore = rules;
    final resultsBefore = await tester.runAsync(results);

    await tester.runAsync(arrange);
    await checkForUpdates(tester);
    await afterFirstCheck?.call();

    expect(find.text(_couldNotCheck), findsOneWidget);
    expect(find.text(_upToDate), findsNothing);
    expect(find.text(_updateReady), findsNothing);
    expect(store.active!.id, releaseBefore);
    expect(mounts, 1, reason: 'a failed check must not rebuild the app');
    expect(identical(core, coreBefore), isTrue);
    expect(identical(rules, rulesBefore), isTrue);
    expect(await tester.runAsync(results), resultsBefore);
    await tester.pumpWidget(const SizedBox());
  }

  Future<Uint8List> catalogFile(String version) async {
    final path = p.join(workspace.path, 'published-$version.db');
    await buildCatalog(path, version: version, score: 12);
    return File(path).readAsBytesSync();
  }

  String sha(Uint8List bytes) => sha256.convert(bytes).toString();

  testWidgets('offline: says it could not check and changes nothing', (
    tester,
  ) async {
    await expectNothingChanged(tester, publisher.goOffline);
  });

  testWidgets('failed check: says it could not check and changes nothing', (
    tester,
  ) async {
    await expectNothingChanged(tester, () async => publisher.failing = true);
  });

  testWidgets('a corrupt download changes nothing and is not "up to date"', (
    tester,
  ) async {
    await expectNothingChanged(tester, () async {
      final bytes = await catalogFile(_newerCatalog);
      publisher.files['v$_newerCatalog/pharmaguide_core.db'] = Uint8List(64);
      publisher.row = {
        'db_version': _newerCatalog,
        'checksum': 'sha256:${sha(bytes)}',
        'is_current': true,
      };
    });
    expect(publisher.downloads, isNotEmpty);
  });

  testWidgets('no manifest row is "could not check", not "up to date"', (
    tester,
  ) async {
    await expectNothingChanged(tester, () async => publisher.row = null);
  });

  testWidgets('same version: says up to date and changes nothing', (
    tester,
  ) async {
    await boot(tester);
    final coreBefore = core;
    publisher.row = {
      'db_version': _bundledCatalog,
      'checksum': 'sha256:${sha(bundle.catalog!)}',
      'is_current': true,
    };

    await checkForUpdates(tester);

    expect(find.text(_upToDate), findsOneWidget);
    expect(mounts, 1);
    expect(identical(core, coreBefore), isTrue);
    expect(publisher.downloads, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a newer release: moves onto it and shows one calm line', (
    tester,
  ) async {
    await boot(tester);
    final bytes = await tester.runAsync(() => catalogFile(_newerCatalog));
    publisher.files['v$_newerCatalog/pharmaguide_core.db'] = bytes!;
    publisher.row = {
      'db_version': _newerCatalog,
      'checksum': 'sha256:${sha(bytes)}',
      'is_current': true,
    };

    await checkForUpdates(tester);

    expect(find.text(_updateReady), findsOneWidget);
    expect(
      find.textContaining('Catalog updated to'),
      findsNothing,
      reason: 'one line per outcome: it replaces the routine toast',
    );
    expect(store.active!.catalogVersion, _newerCatalog);
    expect(mounts, 2);
    expect((await tester.runAsync(results))!['quality_score_v4_100'], 12);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a tap while another run is in flight is not "up to date"', (
    tester,
  ) async {
    await boot(tester);
    publisher.row = {
      'db_version': _bundledCatalog,
      'checksum': 'sha256:${sha(bundle.catalog!)}',
      'is_current': true,
    };
    final container = ProviderScope.containerOf(
      tester.element(find.byType(_App)),
    );
    final check = container.read(checkForUpdatesProvider)!;

    final outcomes = await tester.runAsync(
      () => Future.wait([check(), check()]),
    );

    expect(outcomes!.first, UpdateCheckOutcome.upToDate);
    expect(outcomes.last, UpdateCheckOutcome.couldNotCheck);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a release that fails to open is refused, then refused without '
      'a second download, and neither time is "up to date"', (tester) async {
    await expectNothingChanged(
      tester,
      () async {
        failOpen = true;
        final bytes = await catalogFile(_newerCatalog);
        publisher.files['v$_newerCatalog/pharmaguide_core.db'] = bytes;
        publisher.row = {
          'db_version': _newerCatalog,
          'checksum': 'sha256:${sha(bytes)}',
          'is_current': true,
        };
      },
      afterFirstCheck: () async {
        expect(store.refused, isNotEmpty);
        expect(publisher.downloads, hasLength(1));
        scaffoldMessengerKey.currentState!.removeCurrentSnackBar();
        await tester.pump();
        expect(find.text(_couldNotCheck), findsNothing);
        await checkForUpdates(tester);
        expect(publisher.downloads, hasLength(1));
      },
    );
  });

  testWidgets('rules withheld during a live check are not "up to date"', (
    tester,
  ) async {
    await boot(tester);
    final coreBefore = core;
    await tester.runAsync(() async {
      await store.recordVerified(
        sequence: 1,
        blockedCatalog: const {},
        blockedRules: const {'1.0.15'},
      );
      publisher.row = {
        'db_version': _bundledCatalog,
        'checksum': 'sha256:${sha(bundle.catalog!)}',
        'is_current': true,
      };
    });

    await checkForUpdates(tester);

    expect(find.text(_deviceChanged), findsOneWidget);
    expect(find.text(_upToDate), findsNothing);
    expect(mounts, 2, reason: 'the app moved onto the settled release');
    expect(rules, isNull, reason: 'the blocked rules are closed');
    expect(identical(core, coreBefore), isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'rules withheld during a failed check are not "nothing changed"',
    (tester) async {
      await boot(tester);
      await tester.runAsync(() async {
        await store.recordVerified(
          sequence: 1,
          blockedCatalog: const {},
          blockedRules: const {'1.0.15'},
        );
        await publisher.goOffline();
      });

      await checkForUpdates(tester);

      expect(find.text(_deviceChanged), findsOneWidget);
      expect(find.text(_couldNotCheck), findsNothing);
      expect(mounts, 2, reason: 'the app moved onto the settled release');
      expect(rules, isNull, reason: 'the blocked rules are closed');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('a blocked release that cannot be left yet is not "up to date"', (
    tester,
  ) async {
    await boot(tester);
    final releaseBefore = store.active!.id;
    final coreBefore = core;
    await tester.runAsync(() async {
      await store.recordVerified(
        sequence: 1,
        blockedCatalog: const {_bundledCatalog},
        blockedRules: const {},
      );
      publisher.row = {
        'db_version': _bundledCatalog,
        'checksum': 'sha256:${sha(bundle.catalog!)}',
        'is_current': true,
      };
      diskFull = true;
    });

    await checkForUpdates(tester);

    expect(find.text(_couldNotCheck), findsOneWidget);
    expect(find.text(_upToDate), findsNothing);
    expect(store.active!.id, releaseBefore);
    expect(mounts, 1, reason: 'nothing moved');
    expect(identical(core, coreBefore), isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  group('the notices come back on a relaunch with no network', () {
    Future<void> relaunchOffline(
      WidgetTester tester, {
      required Set<String> blockedCatalog,
      required Set<String> blockedRules,
    }) async {
      await boot(tester);
      await tester.runAsync(() async {
        await store.recordVerified(
          sequence: 1,
          blockedCatalog: blockedCatalog,
          blockedRules: blockedRules,
        );
        await publisher.goOffline();
      });
      await checkForUpdates(tester);
      expect(find.text(_deviceChanged), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async => guard = await openAccount());

      // Sean's line has gone with the old screen. A fresh store is what a
      // relaunch opens from the same files.
      await boot(
        tester,
        app: const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [RulesWithheldNotice(), QualityWithheldNotice()],
            ),
          ),
        ),
        relaunchedStore: ReleaseStore(
          documents: store.documents,
          bundle: bundle,
        ),
      );
      await settleReal(
        tester,
        () =>
            tester.any(find.text(kRulesWithheldNotice)) ||
            tester.any(find.text(kQualityWithheldNotice)),
      );
    }

    testWidgets('rules withheld', (tester) async {
      await relaunchOffline(
        tester,
        blockedCatalog: const {},
        blockedRules: const {'1.0.15'},
      );

      expect(find.text(kRulesWithheldNotice), findsOneWidget);
      expect(find.text(kQualityWithheldNotice), findsNothing);
      expect(find.text(_deviceChanged), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('scores withheld', (tester) async {
      await relaunchOffline(
        tester,
        blockedCatalog: const {_bundledCatalog},
        blockedRules: const {},
      );

      expect(find.text(kQualityWithheldNotice), findsOneWidget);
      expect(find.text(kRulesWithheldNotice), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('with no backend this session, Settings offers no check', (
    tester,
  ) async {
    await boot(tester, supabaseReady: false);

    expect(find.text(_tile), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  test('the wording stays calm and never implies results are stale', () {
    final lines = UpdateCheckOutcome.values.map(updateCheckLine).toList();
    expect(lines, [_upToDate, _updateReady, _couldNotCheck, _deviceChanged]);
    for (final line in lines) {
      expect(
        line,
        isNot(
          matches(
            RegExp(
              'stale|outdated|out of date|old|unconfirmed|nothing|'
              r'stop|avoid|do not|\d{4}',
              caseSensitive: false,
            ),
          ),
        ),
      );
    }
  });
}
