import 'package:pharmaguide/data/repositories/health_event_repository.dart';
import 'package:uuid/uuid.dart';

enum UserHealthEventKind { doctorVisit, examOrTest, procedure, personalNote }

enum UserHealthEventStatus { scheduled, completed, cancelled }

class LocalHealthAttachment {
  const LocalHealthAttachment({
    required this.path,
    required this.displayName,
    this.mimeType,
  });

  final String path;
  final String displayName;
  final String? mimeType;

  Map<String, Object?> toJson() => {
    'path': path,
    'display_name': displayName,
    if (mimeType != null) 'mime_type': mimeType,
  };
}

class UserHealthEventInput {
  const UserHealthEventInput({
    required this.kind,
    required this.title,
    required this.date,
    this.status = UserHealthEventStatus.completed,
    this.note,
    this.followUpAt,
    this.reminderAt,
    this.attachments = const [],
  });

  final UserHealthEventKind kind;
  final String title;
  final DateTime date;
  final UserHealthEventStatus status;
  final String? note;
  final DateTime? followUpAt;
  final DateTime? reminderAt;
  final List<LocalHealthAttachment> attachments;
}

typedef UserHealthSubjectIdFactory = String Function();

/// Writes user-authored appointments, exams, procedures, notes, and follow-ups
/// into the same append-only log used by stack/profile/signal history.
class UserHealthEventService {
  UserHealthEventService(
    this._history, {
    UserHealthSubjectIdFactory? subjectIdFactory,
  }) : _subjectIdFactory = subjectIdFactory ?? _newSubjectId;

  final HealthEventRepository _history;
  final UserHealthSubjectIdFactory _subjectIdFactory;

  static String _newSubjectId() => const Uuid().v4();

  Future<String> create(UserHealthEventInput input) async {
    final title = input.title.trim();
    if (title.isEmpty) {
      throw const FormatException('Health event title cannot be empty.');
    }
    final subjectId = _subjectIdFactory();
    final drafts = <HealthEventDraft>[_eventDraft(input, subjectId: subjectId)];
    final followUpAt = input.followUpAt?.toUtc();
    if (followUpAt != null) {
      drafts.add(
        HealthEventDraft(
          eventType: HealthEventTypes.reminderScheduled,
          source: HealthEventSource.user,
          subjectType: 'reminder',
          subjectId: '$subjectId:follow_up',
          state: HealthEventState.scheduled,
          title: 'Follow up: $title',
          summary: 'Follow-up related to $title.',
          effectiveAt: followUpAt,
          // The appointment reminder belongs to the primary event. A
          // follow-up is a distinct scheduled subject and must not inherit an
          // unrelated reminder time from the original appointment.
          reminderAt: followUpAt,
          metadata: {
            'related_subject_id': subjectId,
            'related_subject_type': _subjectType(input.kind),
          },
        ),
      );
    }
    await _history.appendAll(drafts);
    return subjectId;
  }

  Future<void> reschedule({
    required UserHealthEventKind kind,
    required String subjectId,
    required String title,
    required DateTime newDate,
    String? note,
    DateTime? reminderAt,
  }) {
    if (kind == UserHealthEventKind.personalNote) {
      throw const FormatException('A personal note cannot be rescheduled.');
    }
    return _history
        .append(
          HealthEventDraft(
            eventType: kind == UserHealthEventKind.doctorVisit
                ? HealthEventTypes.appointmentRescheduled
                : kind == UserHealthEventKind.examOrTest
                ? HealthEventTypes.examScheduled
                : HealthEventTypes.procedureScheduled,
            source: HealthEventSource.user,
            subjectType: _subjectType(kind),
            subjectId: subjectId,
            state: HealthEventState.scheduled,
            title: title,
            summary: _clean(note),
            effectiveAt: newDate,
            reminderAt: reminderAt,
          ),
        )
        .then((_) {});
  }

  Future<void> complete({
    required UserHealthEventKind kind,
    required String subjectId,
    required String title,
    required DateTime completedAt,
    String? note,
  }) {
    return _history
        .append(
          HealthEventDraft(
            eventType: _completedType(kind),
            source: HealthEventSource.user,
            subjectType: _subjectType(kind),
            subjectId: subjectId,
            title: title,
            summary: _clean(note),
            effectiveAt: completedAt,
          ),
        )
        .then((_) {});
  }

  Future<void> cancel({
    required UserHealthEventKind kind,
    required String subjectId,
    required String title,
    required DateTime effectiveAt,
  }) {
    if (kind == UserHealthEventKind.personalNote) {
      throw const FormatException('A personal note cannot be cancelled.');
    }
    return _history
        .append(
          HealthEventDraft(
            eventType: _cancelledType(kind),
            source: HealthEventSource.user,
            subjectType: _subjectType(kind),
            subjectId: subjectId,
            state: HealthEventState.cancelled,
            title: '$title cancelled',
            effectiveAt: effectiveAt,
          ),
        )
        .then((_) {});
  }
}

HealthEventDraft _eventDraft(
  UserHealthEventInput input, {
  required String subjectId,
}) {
  return HealthEventDraft(
    eventType: _eventType(input.kind, input.status),
    source: HealthEventSource.user,
    subjectType: _subjectType(input.kind),
    subjectId: subjectId,
    state: switch (input.status) {
      UserHealthEventStatus.scheduled => HealthEventState.scheduled,
      UserHealthEventStatus.completed => HealthEventState.occurred,
      UserHealthEventStatus.cancelled => HealthEventState.cancelled,
    },
    title: input.title.trim(),
    summary: _clean(input.note),
    effectiveAt: input.date,
    reminderAt: input.reminderAt,
    metadata: {
      if (input.attachments.isNotEmpty)
        'attachments': input.attachments
            .map((attachment) => attachment.toJson())
            .toList(growable: false),
    },
  );
}

String _eventType(UserHealthEventKind kind, UserHealthEventStatus status) {
  if (status == UserHealthEventStatus.cancelled) {
    return _cancelledType(kind);
  }
  if (status == UserHealthEventStatus.completed) {
    return _completedType(kind);
  }
  return switch (kind) {
    UserHealthEventKind.doctorVisit => HealthEventTypes.appointmentScheduled,
    UserHealthEventKind.examOrTest => HealthEventTypes.examScheduled,
    UserHealthEventKind.procedure => HealthEventTypes.procedureScheduled,
    UserHealthEventKind.personalNote => HealthEventTypes.noteAdded,
  };
}

String _completedType(UserHealthEventKind kind) => switch (kind) {
  UserHealthEventKind.doctorVisit => HealthEventTypes.appointmentCompleted,
  UserHealthEventKind.examOrTest => HealthEventTypes.examCompleted,
  UserHealthEventKind.procedure => HealthEventTypes.procedureRecorded,
  UserHealthEventKind.personalNote => HealthEventTypes.noteAdded,
};

String _cancelledType(UserHealthEventKind kind) => switch (kind) {
  UserHealthEventKind.doctorVisit => HealthEventTypes.appointmentCancelled,
  UserHealthEventKind.examOrTest => HealthEventTypes.examCancelled,
  UserHealthEventKind.procedure => HealthEventTypes.procedureCancelled,
  UserHealthEventKind.personalNote => HealthEventTypes.reminderCancelled,
};

String _subjectType(UserHealthEventKind kind) => switch (kind) {
  UserHealthEventKind.doctorVisit => 'appointment',
  UserHealthEventKind.examOrTest => 'exam',
  UserHealthEventKind.procedure => 'procedure',
  UserHealthEventKind.personalNote => 'note',
};

String? _clean(String? value) {
  final cleaned = value?.trim();
  return cleaned == null || cleaned.isEmpty ? null : cleaned;
}
