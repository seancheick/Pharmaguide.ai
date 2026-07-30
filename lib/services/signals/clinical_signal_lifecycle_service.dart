import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/repositories/health_event_repository.dart';
import 'package:pharmaguide/services/signals/clinical_signal_envelope.dart';

class SignalLifecycleDiff {
  const SignalLifecycleDiff({
    required this.added,
    required this.changed,
    required this.resolved,
    required this.unchanged,
    required this.resolutionDeferred,
  });

  final int added;
  final int changed;
  final int resolved;
  final int unchanged;
  final bool resolutionDeferred;
}

/// Persists added/changed/resolved clinical-signal diffs to the one local
/// Health History event log.
class ClinicalSignalLifecycleService {
  const ClinicalSignalLifecycleService(this._history);

  final HealthEventRepository _history;

  Future<SignalLifecycleDiff> reconcile({
    required List<ClinicalSignal> currentSignals,
    required bool analysisComplete,
    String? ruleVersion,
    String? catalogVersion,
    DateTime? observedAt,
  }) async {
    final now = (observedAt ?? DateTime.now()).toUtc();
    final current = <String, _SignalSnapshot>{};
    for (final signal in currentSignals) {
      if (current.containsKey(signal.signalId)) {
        throw StateError('Duplicate clinical signal id: ${signal.signalId}');
      }
      current[signal.signalId] = _SignalSnapshot.fromSignal(
        signal,
        fallbackRuleVersion: ruleVersion,
        fallbackCatalogVersion: catalogVersion,
      );
    }

    final previous = await _history.getLatestClinicalSignalLifecycleEvents();
    var added = 0;
    var changed = 0;
    var resolved = 0;
    var unchanged = 0;

    for (final entry in current.entries) {
      final oldEvent = previous[entry.key];
      final oldSnapshot = _snapshotFrom(oldEvent);
      final wasResolved =
          oldEvent?.eventType == HealthEventTypes.clinicalSignalResolved;
      final snapshot = entry.value;
      if (oldSnapshot == null || wasResolved) {
        await _history.append(
          _lifecycleDraft(
            eventType: HealthEventTypes.clinicalSignalAdded,
            state: HealthEventState.occurred,
            snapshot: snapshot,
            previous: oldSnapshot,
            observedAt: now,
          ),
        );
        added++;
      } else if (oldSnapshot.hash != snapshot.hash) {
        await _history.append(
          _lifecycleDraft(
            eventType: HealthEventTypes.clinicalSignalChanged,
            state: HealthEventState.occurred,
            snapshot: snapshot,
            previous: oldSnapshot,
            observedAt: now,
          ),
        );
        changed++;
      } else {
        unchanged++;
      }
    }

    if (analysisComplete) {
      for (final entry in previous.entries) {
        if (current.containsKey(entry.key) ||
            entry.value.eventType == HealthEventTypes.clinicalSignalResolved) {
          continue;
        }
        final oldSnapshot = _snapshotFrom(entry.value);
        if (oldSnapshot == null) continue;
        final reason = _resolutionReason(
          oldSnapshot,
          ruleVersion: ruleVersion,
          catalogVersion: catalogVersion,
        );
        await _history.append(
          HealthEventDraft(
            eventType: HealthEventTypes.clinicalSignalResolved,
            source: HealthEventSource.clinicalSignal,
            subjectType: 'clinical_signal',
            subjectId: entry.key,
            state: HealthEventState.resolved,
            title: 'Resolved: ${oldSnapshot.title}',
            summary: _resolutionSummary(reason),
            effectiveAt: now,
            previousValue: oldSnapshot.data,
            metadata: {'resolution_reason': reason},
            dedupeKey:
                'clinical_signal:${entry.key}:resolved:${oldSnapshot.hash}',
          ),
        );
        resolved++;
      }
    }

    return SignalLifecycleDiff(
      added: added,
      changed: changed,
      resolved: resolved,
      unchanged: unchanged,
      resolutionDeferred: !analysisComplete,
    );
  }

  Future<void> markViewed(String signalId, {DateTime? at}) async {
    await _appendAnnotation(
      eventType: HealthEventTypes.clinicalSignalViewed,
      signalId: signalId,
      at: at,
    );
  }

  Future<void> acknowledge(String signalId, {DateTime? at}) async {
    await _appendAnnotation(
      eventType: HealthEventTypes.clinicalSignalAcknowledged,
      signalId: signalId,
      at: at,
    );
  }

  Future<void> _appendAnnotation({
    required String eventType,
    required String signalId,
    DateTime? at,
  }) async {
    final cleaned = signalId.trim();
    if (cleaned.isEmpty) {
      throw const FormatException('Clinical signal id cannot be blank.');
    }
    await _history.append(
      HealthEventDraft(
        eventType: eventType,
        source: HealthEventSource.clinicalSignal,
        subjectType: 'clinical_signal',
        subjectId: cleaned,
        title: eventType == HealthEventTypes.clinicalSignalViewed
            ? 'Viewed clinical signal'
            : 'Acknowledged clinical signal',
        effectiveAt: (at ?? DateTime.now()).toUtc(),
        dedupeKey: 'clinical_signal:$cleaned:$eventType',
      ),
    );
  }
}

HealthEventDraft _lifecycleDraft({
  required String eventType,
  required HealthEventState state,
  required _SignalSnapshot snapshot,
  required _SignalSnapshot? previous,
  required DateTime observedAt,
}) {
  return HealthEventDraft(
    eventType: eventType,
    source: HealthEventSource.clinicalSignal,
    subjectType: 'clinical_signal',
    subjectId: snapshot.signalId,
    state: state,
    title: eventType == HealthEventTypes.clinicalSignalAdded
        ? 'New: ${snapshot.title}'
        : 'Changed: ${snapshot.title}',
    summary: snapshot.body,
    effectiveAt: observedAt,
    previousValue: previous?.data,
    currentValue: snapshot.data,
    metadata: {'snapshot_hash': snapshot.hash},
    dedupeKey:
        'clinical_signal:${snapshot.signalId}:$eventType:${snapshot.hash}',
  );
}

_SignalSnapshot? _snapshotFrom(HealthHistoryEvent? event) {
  final raw = event?.currentValueJson;
  if (raw == null || raw.isEmpty) return null;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    return _SignalSnapshot.fromData(Map<String, Object?>.from(decoded));
  } on Object {
    return null;
  }
}

String _resolutionReason(
  _SignalSnapshot previous, {
  String? ruleVersion,
  String? catalogVersion,
}) {
  if (previous.ruleVersion != ruleVersion ||
      previous.catalogVersion != catalogVersion) {
    return 'catalog_or_rule_version_changed';
  }
  return 'no_longer_present_after_complete_analysis';
}

String _resolutionSummary(String reason) {
  return reason == 'catalog_or_rule_version_changed'
      ? 'No longer detected after verified clinical data changed.'
      : 'No longer detected in the current stack and health profile.';
}

class _SignalSnapshot {
  _SignalSnapshot._(this.data, this.hash);

  factory _SignalSnapshot.fromSignal(
    ClinicalSignal signal, {
    String? fallbackRuleVersion,
    String? fallbackCatalogVersion,
  }) {
    final data = <String, Object?>{
      'signal_id': signal.signalId,
      'signal_id_canonical': signal.signalIdCanonical,
      'family': signal.family.name,
      'source_rule_id': signal.sourceRuleId,
      'subject_ids': List<String>.from(signal.subjectIds),
      'clinical_severity': signal.clinicalSeverity.name,
      'consumer_disposition': signal.consumerDisposition.name,
      'evaluation_status': signal.evaluationStatus.name,
      'title': signal.title,
      'body': signal.body,
      'copy_id': signal.copyId,
      'source_urls': List<String>.from(signal.sourceUrls),
      'rule_version': signal.ruleVersion ?? fallbackRuleVersion,
      'catalog_version': signal.catalogVersion ?? fallbackCatalogVersion,
    };
    return _SignalSnapshot.fromData(data);
  }

  factory _SignalSnapshot.fromData(Map<String, Object?> data) {
    final canonicalJson = jsonEncode(data);
    return _SignalSnapshot._(
      data,
      sha256.convert(utf8.encode(canonicalJson)).toString(),
    );
  }

  final Map<String, Object?> data;
  final String hash;

  String get signalId => data['signal_id']?.toString() ?? '';
  String get title => data['title']?.toString() ?? 'Clinical signal';
  String get body => data['body']?.toString() ?? '';
  String? get ruleVersion => data['rule_version']?.toString();
  String? get catalogVersion => data['catalog_version']?.toString();
}
