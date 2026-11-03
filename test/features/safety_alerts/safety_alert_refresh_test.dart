import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/features/safety_alerts/providers/safety_alert_providers.dart';
import 'package:pharmaguide/features/stack/providers/active_stack_provider.dart';
import 'package:pharmaguide/features/stack/providers/medication_identity_providers.dart';
import 'package:pharmaguide/services/connectivity_service.dart';
import 'package:pharmaguide/services/safety_alerts/safety_alert.dart';
import 'package:pharmaguide/services/safety_alerts/safety_alert_repository.dart';

class _CountingRepository implements SafetyAlertRepository {
  int fetches = 0;

  @override
  Future<SafetyAlertRelease> loadCurrent() async {
    fetches++;
    return const SafetyAlertRelease(
      alerts: <SafetyAlert>[],
      baselineRevisions: {},
      isComplete: true,
    );
  }

  @override
  Future<List<SafetyAlert>> loadCachedAlerts() async => const [];
}

const _product = ProductsCoreData(
  dsldId: '700',
  productName: 'Fictional product',
  productSafetyStatus: 'no_known_catalog_concern',
  exportVersion: 'test',
  exportedAt: '2026-10-01T00:00:00Z',
);

void main() {
  late _CountingRepository repository;
  late StreamController<ConnectionStatus> connection;
  late ProviderContainer container;

  // Riverpod rebuilds on a zero timer, which a zero-length pump doesn't reach.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 1));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 1));
  }

  Future<void> resumeFromBackground(WidgetTester tester) async {
    final binding = tester.binding;
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      binding.handleAppLifecycleStateChanged(state);
    }
    await settle(tester);
  }

  // No push service anywhere in this setup: refresh must not depend on Firebase.
  Future<void> launch(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    repository = _CountingRepository();
    connection = StreamController<ConnectionStatus>.broadcast();
    container = ProviderContainer(
      overrides: [
        safetyAlertRepositoryProvider.overrideWithValue(repository),
        activeStackProvider.overrideWith((ref) async => const []),
        localMedicationIdentityProvider.overrideWith((ref) async => const {}),
        connectionStatusProvider.overrideWith((ref) => connection.stream),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(connection.close);
    container.listen(safetyAlertRefreshProvider, (_, _) {});
    await settle(tester);
  }

  testWidgets('launch fetches the feed', (tester) async {
    await launch(tester);
    expect(repository.fetches, 1);
  });

  testWidgets('resume fetches it again', (tester) async {
    await launch(tester);
    await resumeFromBackground(tester);
    expect(repository.fetches, 2);
  });

  testWidgets('coming back online fetches it again', (tester) async {
    await launch(tester);
    connection.add(ConnectionStatus.offline);
    await settle(tester);
    expect(repository.fetches, 1, reason: 'Going offline fetches nothing.');

    connection.add(ConnectionStatus.online);
    await settle(tester);
    expect(repository.fetches, 2);
  });

  testWidgets('a sync between offline and online still counts as coming back', (
    tester,
  ) async {
    await launch(tester);
    connection.add(ConnectionStatus.offline);
    await settle(tester);
    connection.add(ConnectionStatus.syncing);
    await settle(tester);
    connection.add(ConnectionStatus.online);
    await settle(tester);
    expect(repository.fetches, 2);
  });

  testWidgets('staying online fetches nothing extra', (tester) async {
    await launch(tester);
    connection.add(ConnectionStatus.online);
    await settle(tester);
    connection.add(ConnectionStatus.syncing);
    await settle(tester);
    connection.add(ConnectionStatus.online);
    await settle(tester);
    expect(repository.fetches, 1);
  });

  testWidgets('an open product page gets the new feed too', (tester) async {
    await launch(tester);
    container.listen(productSafetyAlertsProvider(_product), (_, _) {});
    await settle(tester);
    final beforeResume = repository.fetches;

    await resumeFromBackground(tester);

    expect(
      repository.fetches,
      beforeResume + 2,
      reason: 'The stack matches and the open product page each re-fetch.',
    );
  });
}
