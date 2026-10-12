import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/features/ai_share/ai_share_providers.dart';
import 'package:pharmaguide/features/stack/providers/active_stack_provider.dart';
import 'package:pharmaguide/services/auth_state_service.dart';
import 'package:pharmaguide/services/crash_reporting_service.dart';
import 'package:pharmaguide/services/sharing/ai_brief_builder.dart';
import 'package:pharmaguide/services/sharing/ai_share_prefs_store.dart';
import 'package:pharmaguide/services/sharing/ai_share_snapshot_client.dart';
import 'package:pharmaguide/services/sharing/clinician_report_document_provider.dart';

/// Opt-in refresh of a connected assistant's snapshot (ADR-009).
///
/// Runs only for connections where the user switched on "Keep this
/// assistant updated" (device-only, off by default), only while signed in,
/// and only with the scope and duration the user saw at their last share.
/// A category the user did not choose then (a new medication, condition or
/// pregnancy flag) stays out, because [AiBriefBuilder] withholds it with its
/// findings. This never touches the stack sync queue or its medication
/// guards: it is a separate, consented path.
class AiShareSnapshotPusher {
  AiShareSnapshotPusher({
    required this.isSignedIn,
    required this.prefs,
    required this.client,
    required this.loadData,
  });

  final bool Function() isSignedIn;
  final AiSharePrefsStore prefs;
  final AiShareSnapshotClient client;
  final Future<ClinicianReportData> Function() loadData;

  /// Re-uploads every opted-in connection. Returns how many succeeded.
  /// Never throws: failures are logged without payload content.
  Future<int> refreshAfterStackChange() async {
    if (!isSignedIn()) return 0;
    final targets = (await prefs.readAll()).entries
        .where((e) => e.value.keepUpdated)
        .toList(growable: false);
    if (targets.isEmpty) return 0;

    final ClinicianReportData data;
    try {
      data = await loadData();
    } on Object catch (error, stackTrace) {
      _log(error, stackTrace, 'ai_share:refresh_collect_failed');
      return 0;
    }
    var refreshed = 0;
    for (final target in targets) {
      final saved = target.value;
      try {
        await client.upload(
          connectionId: target.key,
          scope: saved.scope,
          stackRevision: AiShareSnapshotClient.stackRevisionForScope(
            data.stack,
            saved.scope,
          ),
          ttlHours: saved.ttlHours,
          payload: const AiBriefBuilder().build(data, saved.scope),
        );
        refreshed++;
      } on AiShareNotSignedIn {
        return refreshed;
      } on Object catch (error, stackTrace) {
        _log(error, stackTrace, 'ai_share:refresh_upload_failed');
      }
    }
    return refreshed;
  }

  static void _log(Object error, StackTrace stackTrace, String hint) =>
      CrashReportingService().recordError(error, stackTrace, hint: hint);
}

final aiShareSnapshotPusherProvider = Provider<AiShareSnapshotPusher>((ref) {
  return AiShareSnapshotPusher(
    isSignedIn: () => ref.read(authStateProvider.notifier).isSignedIn,
    prefs: ref.read(aiSharePrefsStoreProvider),
    client: ref.read(aiShareSnapshotClientProvider),
    loadData: () async {
      // Hold the auto-dispose collector open until this read completes.
      final sub = ref.listen(clinicianReportDataProvider.future, (_, _) {});
      try {
        return await sub.read();
      } finally {
        sub.close();
      }
    },
  );
});

/// Always-on observer: after a real local stack change (supplement or
/// medication, the same mutations that invalidate [activeStackProvider]),
/// asks the pusher to refresh opted-in connections. The first load is not
/// a change, and a reload with identical rows does nothing.
final aiShareSnapshotListenerProvider = Provider<void>((ref) {
  ref.keepAlive();
  String? lastRevision;
  ref.listen<AsyncValue<List<UserStacksLocalData>>>(activeStackProvider, (
    _,
    next,
  ) {
    final rows = next.asData?.value;
    if (rows == null) return;
    final revision = AiShareSnapshotClient.stackRevisionFor(rows);
    final previous = lastRevision;
    lastRevision = revision;
    if (previous == null || previous == revision) return;
    unawaited(
      ref.read(aiShareSnapshotPusherProvider).refreshAfterStackChange(),
    );
  }, fireImmediately: true);
});
