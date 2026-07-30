import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:uuid/uuid.dart';

abstract final class HealthEventTypes {
  static const stackItemAdded = 'stack_item_added';
  static const stackItemRemoved = 'stack_item_removed';
  static const stackItemChanged = 'stack_item_changed';
  static const stackItemRestored = 'stack_item_restored';
  static const profileChanged = 'profile_changed';
  static const clinicalSignalAdded = 'clinical_signal_added';
  static const clinicalSignalChanged = 'clinical_signal_changed';
  static const clinicalSignalResolved = 'clinical_signal_resolved';
  static const clinicalSignalViewed = 'clinical_signal_viewed';
  static const clinicalSignalAcknowledged = 'clinical_signal_acknowledged';
  static const appointmentScheduled = 'appointment_scheduled';
  static const appointmentRescheduled = 'appointment_rescheduled';
  static const appointmentCompleted = 'appointment_completed';
  static const appointmentCancelled = 'appointment_cancelled';
  static const examScheduled = 'exam_scheduled';
  static const examCompleted = 'exam_completed';
  static const examCancelled = 'exam_cancelled';
  static const procedureScheduled = 'procedure_scheduled';
  static const procedureCancelled = 'procedure_cancelled';
  static const noteAdded = 'note_added';
  static const procedureRecorded = 'procedure_recorded';
  static const reminderScheduled = 'reminder_scheduled';
  static const reminderCompleted = 'reminder_completed';
  static const reminderCancelled = 'reminder_cancelled';
}

enum HealthEventSource {
  stack('stack'),
  profile('profile'),
  clinicalSignal('clinical_signal'),
  user('user');

  const HealthEventSource(this.id);
  final String id;
}

enum HealthEventState { occurred, scheduled, resolved, cancelled }

/// Typed input for the canonical local event log.
class HealthEventDraft {
  const HealthEventDraft({
    required this.eventType,
    required this.source,
    required this.subjectType,
    required this.title,
    required this.effectiveAt,
    this.subjectId,
    this.state = HealthEventState.occurred,
    this.summary,
    this.previousValue,
    this.currentValue,
    this.metadata,
    this.reminderAt,
    this.dedupeKey,
  });

  final String eventType;
  final HealthEventSource source;
  final String subjectType;
  final String? subjectId;
  final HealthEventState state;
  final String title;
  final String? summary;
  final DateTime effectiveAt;
  final Map<String, Object?>? previousValue;
  final Map<String, Object?>? currentValue;
  final Map<String, Object?>? metadata;
  final DateTime? reminderAt;
  final String? dedupeKey;
}

typedef HealthEventIdFactory = String Function();
typedef HealthEventClock = DateTime Function();

/// The only write/read boundary for Health History.
///
/// Rows are append-only. A later event with the same subject id supersedes the
/// current state for projections, while the earlier fact stays visible for
/// audit and “What changed?” explanations.
class HealthEventRepository {
  HealthEventRepository(
    this._database, {
    HealthEventIdFactory? idFactory,
    HealthEventClock? clock,
  }) : _idFactory = idFactory ?? _newId,
       _clock = clock ?? DateTime.now;

  final UserDatabase _database;
  final HealthEventIdFactory _idFactory;
  final HealthEventClock _clock;

  static String _newId() => const Uuid().v4();

  Future<bool> append(HealthEventDraft draft) async {
    _validate(draft);
    final dedupeKey = _cleanNullable(draft.dedupeKey);
    return _database.transaction(() async {
      if (await _dedupeKeyExists(dedupeKey)) return false;
      await _insert(draft, dedupeKey);
      return true;
    });
  }

  /// Atomically appends a bounded set of related events, such as an exam plus
  /// its follow-up reminder.
  Future<void> appendAll(List<HealthEventDraft> drafts) {
    if (drafts.isEmpty) return Future<void>.value();
    for (final draft in drafts) {
      _validate(draft);
    }
    return _database.transaction(() async {
      for (final draft in drafts) {
        final dedupeKey = _cleanNullable(draft.dedupeKey);
        if (await _dedupeKeyExists(dedupeKey)) continue;
        await _insert(draft, dedupeKey);
      }
    });
  }

  /// Runs a domain mutation and its history append in one SQLite transaction.
  /// This prevents a stack/profile change without its event (or a phantom
  /// event whose mutation rolled back).
  Future<T> mutateAndAppend<T>(
    Future<T> Function() mutation,
    HealthEventDraft draft,
  ) {
    _validate(draft);
    final dedupeKey = _cleanNullable(draft.dedupeKey);
    return _database.transaction(() async {
      if (await _dedupeKeyExists(dedupeKey)) {
        throw StateError('Duplicate health event: $dedupeKey');
      }
      final result = await mutation();
      await _insert(draft, dedupeKey);
      return result;
    });
  }

  Future<List<HealthHistoryEvent>> getTimeline({int limit = 200}) {
    return (_database.select(_database.healthHistoryEvents)
          ..orderBy([
            (table) => OrderingTerm(
              expression: table.effectiveAt,
              mode: OrderingMode.desc,
            ),
            (table) => OrderingTerm(
              expression: table.recordedAt,
              mode: OrderingMode.desc,
            ),
            (table) => OrderingTerm(
              expression: table.sequence,
              mode: OrderingMode.desc,
            ),
          ])
          ..limit(limit))
        .get();
  }

  Stream<List<HealthHistoryEvent>> watchTimeline({int limit = 200}) {
    return (_database.select(_database.healthHistoryEvents)
          ..orderBy([
            (table) => OrderingTerm(
              expression: table.effectiveAt,
              mode: OrderingMode.desc,
            ),
            (table) => OrderingTerm(
              expression: table.recordedAt,
              mode: OrderingMode.desc,
            ),
            (table) => OrderingTerm(
              expression: table.sequence,
              mode: OrderingMode.desc,
            ),
          ])
          ..limit(limit))
        .watch();
  }

  Future<HealthHistoryEvent?> latestForSubject({
    required String subjectType,
    required String subjectId,
  }) {
    return (_database.select(_database.healthHistoryEvents)
          ..where(
            (table) =>
                table.subjectType.equals(subjectType) &
                table.subjectId.equals(subjectId),
          )
          ..orderBy([
            (table) => OrderingTerm(
              expression: table.sequence,
              mode: OrderingMode.desc,
            ),
          ])
          ..limit(1))
        .getSingleOrNull();
  }

  /// Latest lifecycle row per clinical-signal id. Viewed/acknowledged rows are
  /// deliberately excluded because they annotate, rather than replace, the
  /// signal's active/resolved state.
  Future<Map<String, HealthHistoryEvent>>
  getLatestClinicalSignalLifecycleEvents() async {
    final rows =
        await (_database.select(_database.healthHistoryEvents)
              ..where(
                (table) =>
                    table.source.equals(HealthEventSource.clinicalSignal.id) &
                    table.eventType.isIn(const [
                      HealthEventTypes.clinicalSignalAdded,
                      HealthEventTypes.clinicalSignalChanged,
                      HealthEventTypes.clinicalSignalResolved,
                    ]),
              )
              ..orderBy([
                (table) => OrderingTerm(
                  expression: table.sequence,
                  mode: OrderingMode.desc,
                ),
              ]))
            .get();
    final latest = <String, HealthHistoryEvent>{};
    for (final row in rows) {
      final subjectId = row.subjectId;
      if (subjectId != null) latest.putIfAbsent(subjectId, () => row);
    }
    return latest;
  }

  /// Current future items are a projection of the same append-only log.
  /// Reschedules/cancellations win because only the latest row per subject is
  /// considered active.
  Stream<List<HealthHistoryEvent>> watchUpcoming({
    DateTime? now,
    int limit = 100,
  }) {
    final threshold = (now ?? _clock()).toUtc();
    final query = _database.select(_database.healthHistoryEvents)
      ..where(
        (table) => table.subjectType.isIn(const [
          'appointment',
          'exam',
          'procedure',
          'reminder',
        ]),
      )
      ..orderBy([
        (table) =>
            OrderingTerm(expression: table.sequence, mode: OrderingMode.desc),
      ]);

    return query.watch().map((rows) {
      final latest = <String, HealthHistoryEvent>{};
      for (final row in rows) {
        final key = row.subjectId ?? row.id;
        latest.putIfAbsent(key, () => row);
      }
      final scheduled =
          latest.values
              .where(
                (row) =>
                    row.state == HealthEventState.scheduled.name &&
                    !row.effectiveAt.toUtc().isBefore(threshold),
              )
              .toList()
            ..sort((a, b) => a.effectiveAt.compareTo(b.effectiveAt));
      return scheduled.take(limit).toList(growable: false);
    });
  }

  static void _validate(HealthEventDraft draft) {
    if (draft.eventType.trim().isEmpty) {
      throw const FormatException('Health event type cannot be empty.');
    }
    if (draft.subjectType.trim().isEmpty) {
      throw const FormatException('Health event subject type cannot be empty.');
    }
    if (draft.title.trim().isEmpty) {
      throw const FormatException('Health event title cannot be empty.');
    }
    if (draft.dedupeKey != null && draft.dedupeKey!.trim().isEmpty) {
      throw const FormatException('Health event dedupe key cannot be blank.');
    }
  }

  static String? _cleanNullable(String? value) {
    final cleaned = value?.trim();
    return cleaned == null || cleaned.isEmpty ? null : cleaned;
  }

  static String? _encode(Map<String, Object?>? value) {
    return value == null ? null : jsonEncode(value);
  }

  Future<bool> _dedupeKeyExists(String? dedupeKey) async {
    if (dedupeKey == null) return false;
    final existing =
        await (_database.select(_database.healthHistoryEvents)
              ..where((table) => table.dedupeKey.equals(dedupeKey))
              ..limit(1))
            .getSingleOrNull();
    return existing != null;
  }

  Future<void> _insert(HealthEventDraft draft, String? dedupeKey) async {
    await _database
        .into(_database.healthHistoryEvents)
        .insert(
          HealthHistoryEventsCompanion.insert(
            id: _idFactory(),
            eventType: draft.eventType.trim(),
            source: draft.source.id,
            subjectType: draft.subjectType.trim(),
            subjectId: Value(_cleanNullable(draft.subjectId)),
            state: Value(draft.state.name),
            title: draft.title.trim(),
            summary: Value(_cleanNullable(draft.summary)),
            effectiveAt: draft.effectiveAt.toUtc(),
            recordedAt: Value(_clock().toUtc()),
            previousValueJson: Value(_encode(draft.previousValue)),
            currentValueJson: Value(_encode(draft.currentValue)),
            metadataJson: Value(_encode(draft.metadata)),
            reminderAt: Value(draft.reminderAt?.toUtc()),
            dedupeKey: Value(dedupeKey),
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }
}
