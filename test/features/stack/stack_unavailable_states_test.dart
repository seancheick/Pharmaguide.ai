// Two states the Stack tab used to swallow.
//
// Both share a root cause: a result that says "we could not check" was computed
// correctly and then discarded by its only consumer, leaving the user with a
// screen indistinguishable from "we checked and found nothing".
//
// low_coverage_not_safe_stack_test.dart already pumps StackSafetyBanner
// directly and passes — the widget was never the bug. The slot returned before
// the widget could run, so that test is green while the path is dead. The
// guard is now the shared snapshot's `analysisIncomplete` — which covers
// every incomplete flag (checks, coverage, recalls, dose sums) — exercised
// here through the real engine and pinned to the slot's source below, so a
// regression in either half fails.

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/models/stack_intelligence.dart';
import 'package:pharmaguide/features/stack/providers/stack_reminder_providers.dart';
import 'package:pharmaguide/services/stack/recalled_ingredient_result.dart';
import 'package:pharmaguide/services/stack/stack_intelligence_engine.dart';
import 'package:pharmaguide/services/stack/stack_reminder_scheduler.dart';
import 'package:pharmaguide/services/stack/stack_safety_report.dart';
import 'package:pharmaguide/services/stack/synergy_result.dart';

void main() {
  group('an incomplete check never reads as a clean stack', () {
    StackIntelligence diagnose(StackSafetyReport report) =>
        const StackIntelligenceEngine().diagnoseFromReports(
          stackSize: 1,
          safetyReport: report,
          recalledReport: RecalledIngredientsReport.empty(),
          synergyReport: SynergyReport.empty(),
        );

    test('a clean, complete report has nothing to hedge', () {
      final intelligence = diagnose(const StackSafetyReport());
      expect(intelligence.analysisIncomplete, isFalse);
      expect(intelligence.tier, isNot(StackTier.incomplete));
    });

    test('an empty report with failed checks must still hedge', () {
      final intelligence = diagnose(
        const StackSafetyReport(checksIncomplete: true),
      );
      expect(
        intelligence.analysisIncomplete,
        isTrue,
        reason:
            'a timing or interaction pass that threw must not vanish into a '
            'blank screen',
      );
      expect(intelligence.tier, StackTier.incomplete);
    });

    test('an empty report with incomplete coverage must still hedge', () {
      final intelligence = diagnose(
        const StackSafetyReport(coverageIncomplete: true),
      );
      expect(intelligence.analysisIncomplete, isTrue);
      expect(intelligence.tier, StackTier.incomplete);
    });

    test('the stack banner slot only hides on complete, signal-free analysis', () {
      final source = File(
        'lib/features/stack/v2/stack_v2_screen.dart',
      ).readAsStringSync();
      final start = source.indexOf('class _StackSafetyBannerSlot');
      expect(start, isNonNegative, reason: 'the slot was renamed');
      final slot = source.substring(start, source.indexOf('\nclass ', start));

      expect(slot, contains('stackHealthSnapshotProvider'));
      expect(
        slot,
        contains('!snapshot.intelligence.analysisIncomplete'),
        reason:
            'the shrink guard must account for every incomplete-analysis flag '
            '(checks, coverage, recalls, dose sums), not findings alone',
      );
      // Naive findings-only guards are what made the hedge unreachable.
      // Scoped to this slot: _GoalSupportSlot guards a different report type
      // on its own isEmpty.
      expect(slot, isNot(contains('if (report.isEmpty) return')));
      expect(slot, isNot(contains('hasNothingToReport')));
    });
  });

  group('a saved reminder never promises a notification it cannot deliver', () {
    ProviderContainer containerWith(StackReminderSyncResult result) {
      final container = ProviderContainer(
        overrides: [
          stackReminderSyncProvider.overrideWith((ref) async => result),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    Future<bool> deliverableFor(StackReminderSyncResult result) async {
      final container = containerWith(result);
      await container.read(stackReminderSyncProvider.future);
      return container.read(stackRemindersDeliverableProvider);
    }

    test('granted permission keeps the scheduled label', () async {
      expect(
        await deliverableFor(
          const StackReminderSyncResult(
            scheduled: 2,
            cancelled: 0,
            permissionGranted: true,
            omittedDueToLimit: 0,
          ),
        ),
        isTrue,
      );
    });

    test('denied permission is surfaced, not discarded', () async {
      expect(
        await deliverableFor(
          const StackReminderSyncResult(
            scheduled: 0,
            cancelled: 0,
            permissionGranted: false,
            omittedDueToLimit: 0,
          ),
        ),
        isFalse,
      );
    });

    test('a still-loading sync does not claim reminders are off', () {
      final container = ProviderContainer(
        overrides: [
          stackReminderSyncProvider.overrideWith(
            (ref) => Future<StackReminderSyncResult>.delayed(
              const Duration(seconds: 30),
              () => const StackReminderSyncResult(
                scheduled: 0,
                cancelled: 0,
                permissionGranted: false,
                omittedDueToLimit: 0,
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      expect(
        container.read(stackRemindersDeliverableProvider),
        isTrue,
        reason:
            'a transient failure to ask must not tell the user their reminders '
            'are off',
      );
    });

    test('reminders dropped by the platform cap are reported', () async {
      final container = containerWith(
        const StackReminderSyncResult(
          scheduled: 60,
          cancelled: 0,
          permissionGranted: true,
          omittedDueToLimit: 4,
        ),
      );
      await container.read(stackReminderSyncProvider.future);
      expect(container.read(stackRemindersOmittedProvider), 4);
    });

    test('the stack row label is gated on deliverability', () {
      final source = File(
        'lib/features/stack/v2/stack_v2_screen.dart',
      ).readAsStringSync();
      expect(source, contains('stackRemindersDeliverableProvider'));
      expect(
        source,
        contains('Reminder saved — notifications are off for PharmaGuide'),
      );
    });
  });
}
