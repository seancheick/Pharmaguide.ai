import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/repositories/health_event_repository.dart';
import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

class HealthReminderSyncResult {
  const HealthReminderSyncResult({
    required this.scheduled,
    required this.cancelled,
    required this.permissionGranted,
  });

  final int scheduled;
  final int cancelled;
  final bool permissionGranted;
}

abstract interface class HealthReminderScheduler {
  Future<HealthReminderSyncResult> sync(
    List<HealthHistoryEvent> upcomingEvents,
  );
}

abstract interface class HealthReminderNotificationClient {
  Future<void> initialize();
  Future<Set<int>> pendingIds();
  Future<bool> requestPermission();
  Future<void> schedule({required int id, required DateTime at});
  Future<void> cancel(int id);
}

/// Projects the canonical local event log into OS notifications.
///
/// The event log remains the source of truth. Scheduled notifications are a
/// disposable projection rebuilt from it, which prevents a second reminder
/// database from drifting. Lock-screen copy is intentionally generic and the
/// payload contains no medication, condition, appointment, or note details.
class LocalHealthReminderService implements HealthReminderScheduler {
  LocalHealthReminderService({
    HealthReminderNotificationClient? client,
    DateTime Function()? clock,
  }) : _client = client ?? _FlutterHealthReminderNotificationClient(),
       _clock = clock ?? DateTime.now;

  static const _firstOwnedId = 900000000;
  static const _ownedIdSpan = 90000000;
  static const _maxScheduled = 60;
  static const _channelId = 'health_history_reminders';

  final HealthReminderNotificationClient _client;
  final DateTime Function() _clock;

  @override
  Future<HealthReminderSyncResult> sync(
    List<HealthHistoryEvent> upcomingEvents,
  ) async {
    await _client.initialize();
    final now = _clock().toUtc();
    final desired =
        upcomingEvents
            .where(
              (event) =>
                  event.state == HealthEventState.scheduled.name &&
                  event.reminderAt != null &&
                  event.reminderAt!.toUtc().isAfter(now),
            )
            .toList()
          ..sort(
            (a, b) => a.reminderAt!.toUtc().compareTo(b.reminderAt!.toUtc()),
          );
    final bounded = desired.take(_maxScheduled).toList(growable: false);
    final desiredById = {
      for (final event in bounded) _notificationId(event): event,
    };

    final pending = await _client.pendingIds();
    var cancelled = 0;
    for (final id in pending) {
      if (_isOwned(id) && !desiredById.containsKey(id)) {
        await _client.cancel(id);
        cancelled++;
      }
    }

    if (desiredById.isEmpty) {
      return HealthReminderSyncResult(
        scheduled: 0,
        cancelled: cancelled,
        permissionGranted: true,
      );
    }

    final permissionGranted = await _client.requestPermission();
    if (!permissionGranted) {
      return HealthReminderSyncResult(
        scheduled: 0,
        cancelled: cancelled,
        permissionGranted: false,
      );
    }

    for (final entry in desiredById.entries) {
      await _client.schedule(
        id: entry.key,
        at: entry.value.reminderAt!.toUtc(),
      );
    }

    return HealthReminderSyncResult(
      scheduled: desiredById.length,
      cancelled: cancelled,
      permissionGranted: true,
    );
  }

  static int _notificationId(HealthHistoryEvent event) {
    final subject = [event.subjectType, event.subjectId ?? event.id].join(':');
    final digest = sha256.convert(utf8.encode(subject)).bytes;
    final hash =
        ((digest[0] << 24) | (digest[1] << 16) | (digest[2] << 8) | digest[3]) &
        0x7fffffff;
    return _firstOwnedId + (hash % _ownedIdSpan);
  }

  static bool _isOwned(int id) =>
      id >= _firstOwnedId && id < _firstOwnedId + _ownedIdSpan;
}

class _FlutterHealthReminderNotificationClient
    implements HealthReminderNotificationClient {
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  Future<void>? _initialization;

  @override
  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    timezone_data.initializeTimeZones();
    try {
      final local = await FlutterTimezone.getLocalTimezone();
      timezone.setLocalLocation(timezone.getLocation(local.identifier));
    } on Object catch (error) {
      // The event timestamp is stored as an instant. UTC is therefore a safe
      // scheduling fallback when the platform cannot supply an IANA zone.
      debugPrint('[health-reminders] timezone fallback to UTC: $error');
      timezone.setLocalLocation(timezone.UTC);
    }
    await _notifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
  }

  @override
  Future<Set<int>> pendingIds() async {
    final requests = await _notifications.pendingNotificationRequests();
    return requests.map((request) => request.id).toSet();
  }

  @override
  Future<bool> requestPermission() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return await _notifications
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.requestNotificationsPermission() ??
          true;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return await _notifications
              .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin
              >()
              ?.requestPermissions(alert: true, badge: false, sound: true) ??
          false;
    }
    return false;
  }

  @override
  Future<void> schedule({required int id, required DateTime at}) {
    return _notifications.zonedSchedule(
      id: id,
      title: 'PharmaGuide reminder',
      body: 'You have an upcoming health item to review.',
      scheduledDate: timezone.TZDateTime.from(at.toUtc(), timezone.local),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          LocalHealthReminderService._channelId,
          'Health reminders',
          channelDescription:
              'Private reminders created from your on-device Health History.',
          visibility: NotificationVisibility.private,
        ),
        iOS: DarwinNotificationDetails(
          threadIdentifier: LocalHealthReminderService._channelId,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: 'health-history',
    );
  }

  @override
  Future<void> cancel(int id) => _notifications.cancel(id: id);
}
