import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/data/repositories/health_event_repository.dart';
import 'package:pharmaguide/services/history/health_attachment_store.dart';
import 'package:pharmaguide/services/history/user_health_event_service.dart';
import 'package:pharmaguide/services/history/local_health_reminder_service.dart';
import 'package:pharmaguide/services/signals/clinical_signal_lifecycle_service.dart';

enum HealthHistoryCategory { signal, stack, care, profile, note }

class HealthHistoryItem {
  const HealthHistoryItem(this.event);

  final HealthHistoryEvent event;

  HealthHistoryCategory get category => switch (event.source) {
    'clinical_signal' => HealthHistoryCategory.signal,
    'stack' => HealthHistoryCategory.stack,
    'profile' => HealthHistoryCategory.profile,
    _ when event.subjectType == 'note' => HealthHistoryCategory.note,
    _ => HealthHistoryCategory.care,
  };

  bool get isInternalAnnotation =>
      event.eventType == HealthEventTypes.clinicalSignalViewed ||
      event.eventType == HealthEventTypes.clinicalSignalAcknowledged;

  bool get isUpcoming =>
      event.state == HealthEventState.scheduled.name &&
      event.effectiveAt.isAfter(DateTime.now());

  String get searchText =>
      '${event.title} ${event.summary ?? ''} ${event.subjectType}'
          .toLowerCase();

  String get whyChanged {
    if (event.eventType == HealthEventTypes.clinicalSignalResolved) {
      final reason = _metadata['resolution_reason']?.toString();
      return reason == 'catalog_or_rule_version_changed'
          ? 'A complete recheck no longer found this signal after reviewed '
                'clinical data changed.'
          : 'A complete recheck no longer found this signal in the current '
                'stack and health profile.';
    }
    if (event.eventType == HealthEventTypes.clinicalSignalChanged) {
      return 'The same reviewed signal remains active, but its severity, '
          'wording, subjects, or source version changed.';
    }
    if (event.eventType == HealthEventTypes.clinicalSignalAdded) {
      return 'A complete stack and profile check detected this reviewed '
          'signal for the first time.';
    }
    if (event.eventType == HealthEventTypes.profileChanged) {
      final fields = _metadata['changed_fields'];
      if (fields is List && fields.isNotEmpty) {
        return 'Your saved ${fields.join(', ')} changed.';
      }
      return 'Your saved health profile changed.';
    }
    if (event.eventType == HealthEventTypes.stackItemAdded ||
        event.eventType == HealthEventTypes.stackItemRestored) {
      return 'This item became active in your saved stack.';
    }
    if (event.eventType == HealthEventTypes.stackItemRemoved) {
      return 'This item was removed from your active stack.';
    }
    if (event.eventType == HealthEventTypes.appointmentRescheduled) {
      return 'A newer date was saved for this appointment. The original '
          'event remains in history.';
    }
    return event.summary ?? 'This event was recorded on your device.';
  }

  List<String> get changedFieldLabels {
    final previous = _decodeMap(event.previousValueJson);
    final current = _decodeMap(event.currentValueJson);
    if (previous.isEmpty || current.isEmpty) return const [];
    final keys = <String>{
      ...previous.keys,
      ...current.keys,
    }.where((key) => previous[key].toString() != current[key].toString());
    return keys
        .where((key) => !_internalDiffFields.contains(key))
        .map((key) => _diffFieldLabels[key] ?? _humanize(key))
        .toList(growable: false);
  }

  List<LocalHealthAttachment> get attachments {
    final raw = _metadata['attachments'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map((value) {
          final attachmentPath = value['path']?.toString().trim() ?? '';
          final displayName = value['display_name']?.toString().trim() ?? '';
          if (attachmentPath.isEmpty || displayName.isEmpty) return null;
          return LocalHealthAttachment(
            path: attachmentPath,
            displayName: displayName,
            mimeType: value['mime_type']?.toString(),
          );
        })
        .whereType<LocalHealthAttachment>()
        .toList(growable: false);
  }

  Map<String, dynamic> get _metadata {
    return _decodeMap(event.metadataJson);
  }

  static Map<String, dynamic> _decodeMap(String? raw) {
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : const <String, dynamic>{};
    } on Object {
      return const {};
    }
  }
}

const _internalDiffFields = {
  'signal_id',
  'signal_id_canonical',
  'source_rule_id',
  'copy_id',
};

const _diffFieldLabels = {
  'clinical_severity': 'Clinical severity',
  'consumer_disposition': 'Recommended action',
  'evaluation_status': 'Analysis status',
  'title': 'Headline',
  'body': 'Explanation',
  'subject_ids': 'Affected items',
  'source_urls': 'Evidence sources',
  'rule_version': 'Clinical rule version',
  'catalog_version': 'Catalog version',
};

String _humanize(String value) {
  final words = value.replaceAll('_', ' ');
  return words.isEmpty
      ? value
      : '${words[0].toUpperCase()}${words.substring(1)}';
}

final userHealthEventServiceProvider = Provider<UserHealthEventService>((ref) {
  return UserHealthEventService(ref.watch(healthEventRepositoryProvider));
});

final healthAttachmentStoreProvider = Provider<HealthAttachmentStore>((ref) {
  return HealthAttachmentStore();
});

final clinicalSignalLifecycleServiceProvider =
    Provider<ClinicalSignalLifecycleService>((ref) {
      return ClinicalSignalLifecycleService(
        ref.watch(healthEventRepositoryProvider),
      );
    });

final healthHistoryTimelineProvider =
    StreamProvider.autoDispose<List<HealthHistoryItem>>((ref) {
      return ref
          .watch(healthEventRepositoryProvider)
          .watchTimeline()
          .map(
            (events) => events
                .map(HealthHistoryItem.new)
                .where((item) => !item.isInternalAnnotation)
                .toList(growable: false),
          );
    });

final healthHistoryUpcomingProvider =
    StreamProvider.autoDispose<List<HealthHistoryItem>>((ref) {
      return ref
          .watch(healthEventRepositoryProvider)
          .watchUpcoming()
          .map(
            (events) =>
                events.map(HealthHistoryItem.new).toList(growable: false),
          );
    });

final healthReminderSchedulerProvider = Provider<HealthReminderScheduler>((
  ref,
) {
  return LocalHealthReminderService();
});

/// Keeps OS reminders synchronized as a projection of the same append-only
/// log. No notification-specific health database exists.
final healthReminderSyncProvider =
    FutureProvider.autoDispose<HealthReminderSyncResult>((ref) async {
      final items = await ref.watch(healthHistoryUpcomingProvider.future);
      return ref
          .watch(healthReminderSchedulerProvider)
          .sync(items.map((item) => item.event).toList(growable: false));
    });
