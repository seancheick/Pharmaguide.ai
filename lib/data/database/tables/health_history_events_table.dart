import 'package:drift/drift.dart';

/// Canonical, append-only local event log for Health History.
///
/// Every row describes one fact at one point in time. Changes (for example an
/// appointment being rescheduled or a clinical signal resolving) append a new
/// row with the same [subjectId]; callers never rewrite clinical history.
///
/// Privacy contract: this table is device-only health data. It is never part
/// of Supabase sync. Barcode scan events remain in their dedicated Home-tab
/// history and are intentionally not duplicated here.
class HealthHistoryEvents extends Table {
  /// Monotonic local ordering key. SQLite timestamp precision is not a safe
  /// tie-breaker for rapid append-only transitions (for example remove +
  /// undo), so projections fold by this database-owned sequence.
  IntColumn get sequence => integer().autoIncrement()();

  TextColumn get id => text()();

  /// Stable event vocabulary such as `stack_item_added`,
  /// `clinical_signal_resolved`, or `appointment_scheduled`.
  TextColumn get eventType => text().named('event_type')();

  /// Owning subsystem: stack | profile | clinical_signal | user.
  TextColumn get source => text()();

  /// Entity family: supplement | medication | condition | clinical_signal |
  /// appointment | note | procedure | reminder.
  TextColumn get subjectType => text().named('subject_type')();

  /// Stable entity/correlation id. Repeated rows for the same appointment or
  /// signal share this id and are folded by the read model.
  TextColumn get subjectId => text().named('subject_id').nullable()();

  /// occurred | scheduled | resolved | cancelled.
  TextColumn get state => text().withDefault(const Constant('occurred'))();

  TextColumn get title => text()();
  TextColumn get summary => text().nullable()();

  /// When the fact happened or is scheduled to happen.
  DateTimeColumn get effectiveAt => dateTime().named('effective_at')();

  /// When PharmaGuide recorded the fact. Kept separate so backdated user
  /// events remain chronologically and auditably correct.
  DateTimeColumn get recordedAt =>
      dateTime().named('recorded_at').withDefault(currentDateAndTime)();

  /// Structured before/after payloads for “What changed?” explanations.
  TextColumn get previousValueJson =>
      text().named('previous_value_json').nullable()();
  TextColumn get currentValueJson =>
      text().named('current_value_json').nullable()();

  /// Small versioned extension payload. Never store opaque Dart objects.
  TextColumn get metadataJson => text().named('metadata_json').nullable()();
  IntColumn get payloadSchemaVersion => integer()
      .named('payload_schema_version')
      .withDefault(const Constant(1))();

  /// Optional local reminder time. OS scheduling is derived from this log.
  DateTimeColumn get reminderAt => dateTime().named('reminder_at').nullable()();

  /// Deterministic key for idempotent system observations. Nullable because
  /// explicit user-authored events are distinct even when their copy matches.
  TextColumn get dedupeKey => text().named('dedupe_key').nullable()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {id},
  ];

  @override
  String get tableName => 'health_history_events';
}
