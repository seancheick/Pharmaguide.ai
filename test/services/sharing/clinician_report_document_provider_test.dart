import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/interaction_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/safety_alerts/providers/safety_alert_providers.dart';
import 'package:pharmaguide/features/stack/providers/stack_providers.dart';
import 'package:pharmaguide/services/safety_alerts/safety_alert.dart';
import 'package:pharmaguide/services/sharing/clinician_report_document_provider.dart';
import 'package:pharmaguide/services/sharing/clinician_pdf_builder.dart';
import 'package:pharmaguide/services/sharing/ai_brief_builder.dart';
import 'package:pharmaguide/services/sharing/ai_share_scope.dart';
import 'package:pharmaguide/services/stack/depletion_checker.dart';
import 'package:pharmaguide/services/stack/recalled_ingredient_result.dart';
import 'package:pharmaguide/services/stack/stack_safety_report.dart';
import 'package:pharmaguide/services/stack/synergy_result.dart';

SafetyAlert _alert(int index) {
  final json =
      jsonDecode(
            File(
              'test/fixtures/safety_alerts/interaction_rule_feed.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  return SafetyAlert.fromJson(
    Map<String, Object?>.from((json['alerts'] as List)[index] as Map),
  );
}

SafetyAlertMatchSet _matches({
  int? alertIndex,
  bool neverVerified = false,
  bool deviceComplete = true,
  bool fresh = true,
}) => SafetyAlertMatchSet(
  matches: [
    if (alertIndex != null) (alert: _alert(alertIndex), dsldId: '9990001'),
  ],
  baselineSignalKeys: const {},
  isComplete: fresh,
  neverVerified: neverVerified,
  isDeviceComplete: deviceComplete,
);

ProviderContainer _container(Future<SafetyAlertMatchSet> Function() matches) {
  final user = UserDatabase.memory();
  final core = CoreDatabase.memory();
  final interactions = InteractionDatabase.memory();
  final container = ProviderContainer(
    overrides: [
      userDatabaseProvider.overrideWithValue(user),
      coreDatabaseProvider.overrideWithValue(core),
      interactionDatabaseProvider.overrideWithValue(interactions),
      activeStackProvider.overrideWith((ref) async => const []),
      stackSafetyReportProvider.overrideWith(
        (ref) async => const StackSafetyReport(),
      ),
      synergyReportProvider.overrideWith((ref) async => SynergyReport.empty()),
      recalledIngredientsReportProvider.overrideWith(
        (ref) async => RecalledIngredientsReport.empty(),
      ),
      depletionReportProvider.overrideWith(
        (ref) async => (
          status: MedNutrientLoadStatus.loaded,
          matches: const <DepletionMatch>[],
        ),
      ),
      stackDoseThresholdAlertsProvider.overrideWith((ref) async => const []),
      safetyAlertMatchesProvider.overrideWith((ref) => matches()),
    ],
  );
  final subscription = container.listen(clinicianReportDataProvider, (_, _) {});
  addTearDown(() async {
    subscription.close();
    container.dispose();
    await user.close();
    await core.close();
    await interactions.close();
  });
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'canonical report includes a matched alert even with an otherwise clean report',
    () async {
      final container = _container(() async => _matches(alertIndex: 0));
      final data = await container.read(clinicianReportDataProvider.future);
      expect(
        data.intelligence.issues.map((i) => i.headline).join(' '),
        contains('Fakeroot'),
      );
    },
  );

  for (final state in [
    'never verified',
    'unreadable device',
    'provider failure',
  ]) {
    test('canonical report cannot all-clear when alerts are $state', () async {
      final container = _container(() async {
        if (state == 'provider failure') throw StateError('fixture unreadable');
        return _matches(
          neverVerified: state == 'never verified',
          deviceComplete: state != 'unreadable device',
        );
      });
      final data = await container.read(clinicianReportDataProvider.future);
      expect(data.intelligence.analysisIncomplete, isTrue);
      final brief = const AiBriefBuilder().build(data, const AiShareScope());
      expect(
        brief,
        contains('At least one safety check could not be completed'),
      );
      final pdf = await _pdfText(data);
      expect(
        pdf,
        isNot(contains('No stack warnings in the current snapshot.')),
      );
      expect(pdf, contains('not an all-clear'));
    });
  }

  for (final fresh in [false, true]) {
    test(
      'readable saved/empty feed remains complete (fresh: $fresh)',
      () async {
        final container = _container(() async => _matches(fresh: fresh));
        final data = await container.read(clinicianReportDataProvider.future);
        expect(data.intelligence.analysisIncomplete, isFalse);
      },
    );
  }

  test(
    'report waits for the current alert match instead of exporting a loading all-clear',
    () async {
      final pending = Completer<SafetyAlertMatchSet>();
      final started = Completer<void>();
      final container = _container(() {
        started.complete();
        return pending.future;
      });
      var finished = false;
      final report = container.read(clinicianReportDataProvider.future).then((
        data,
      ) {
        finished = true;
        return data;
      });
      await started.future;
      expect(finished, isFalse);
      pending.complete(_matches(alertIndex: 3));
      final data = await report;
      expect(data.intelligence.issues, isNotEmpty);
    },
  );
  test(
    'PDF and full AI brief keep alert evidence and source without duplicate fallbacks',
    () async {
      final container = _container(() async => _matches(alertIndex: 0));
      final data = await container.read(clinicianReportDataProvider.future);
      final brief = const AiBriefBuilder().build(
        data,
        const AiShareScope(medicationNames: true, profile: true),
      );
      expect(brief, contains('Testoprilex'));
      expect(brief, contains('Evidence level: established'));
      expect(brief, contains('https://example.org/fake-interaction-source'));
      expect('Regulatory update:'.allMatches(brief), hasLength(1));
      final pdf = await _pdfText(data);
      expect(pdf, contains('Testoprilex'));
      expect(pdf, contains('Established'));
      expect(pdf, contains('fake-interaction-source'));
      expect(
        pdf,
        isNot(contains('No stack warnings in the current snapshot.')),
      );
    },
  );

  for (final alertIndex in [0, 2]) {
    test(
      'AI brief hides alert-derived private category $alertIndex unless shared',
      () async {
        final container = _container(
          () async => _matches(alertIndex: alertIndex),
        );
        final data = await container.read(clinicianReportDataProvider.future);
        final brief = const AiBriefBuilder().build(data, const AiShareScope());
        expect(brief, isNot(contains('Testoprilex')));
        expect(brief, isNot(contains('Fakeroot')));
        expect(brief, isNot(contains('fake-interaction-source')));
        expect(brief, contains('1 finding was withheld'));
        final allowed = const AiBriefBuilder().build(
          data,
          AiShareScope(
            medicationNames: alertIndex == 0,
            profile: alertIndex == 2,
          ),
        );
        expect(allowed, contains('Fakeroot'));
        expect(allowed, contains('Evidence level: established'));
        final withoutFindings = const AiBriefBuilder().build(
          data,
          const AiShareScope(
            medicationNames: true,
            profile: true,
            findings: false,
          ),
        );
        expect(withoutFindings, isNot(contains('fake-interaction-source')));
      },
    );
  }

  test(
    'supplement-only recall remains shareable without medication or profile consent',
    () async {
      final container = _container(() async => _matches(alertIndex: 3));
      final data = await container.read(clinicianReportDataProvider.future);
      final brief = const AiBriefBuilder().build(data, const AiShareScope());
      expect(brief, contains('Fakeroot capsules recall'));
      expect(brief, contains('https://example.org/fake-ban-source'));
      final hidden = const AiBriefBuilder().build(
        data,
        const AiShareScope(supplementNames: false),
      );
      expect(hidden, isNot(contains('Fakeroot')));
      expect(hidden, isNot(contains('fake-ban-source')));
    },
  );

  test(
    'known recall survives an incomplete device match in both reports',
    () async {
      final container = _container(
        () async => _matches(alertIndex: 3, deviceComplete: false),
      );
      final data = await container.read(clinicianReportDataProvider.future);
      expect(data.intelligence.analysisIncomplete, isTrue);
      final brief = const AiBriefBuilder().build(data, const AiShareScope());
      expect(brief, contains('Fakeroot capsules recall'));
      expect(
        brief,
        contains('At least one safety check could not be completed'),
      );
      final pdf = await _pdfText(data);
      expect(pdf, contains('Fakeroot capsules recall'));
      expect(
        pdf,
        isNot(contains('No stack warnings in the current snapshot.')),
      );
    },
  );
}

Future<String> _pdfText(ClinicianReportData data) async {
  final bytes = await const ClinicianPdfBuilder(compress: false).build(
    profile: data.profile,
    stack: data.stack,
    intelligence: data.intelligence,
    safetyReport: data.safetyReport,
    depletions: data.depletions,
    generatedAt: data.generatedAt,
    regulatorySafetyAlerts: data.regulatorySafetyAlerts,
  );
  // The built-in PDF fonts emit some lines as one text operand per word.
  // Extract operands so assertions check rendered text, not drawing syntax.
  final raw = latin1.decode(bytes, allowInvalid: true);
  return RegExp(r'\(((?:\\.|[^\\()])*)\)')
      .allMatches(raw)
      .map((m) => m.group(1)!.replaceAll(r'\(', '(').replaceAll(r'\)', ')'))
      .join(' ')
      .replaceAll(RegExp(r'\s+'), ' ');
}
