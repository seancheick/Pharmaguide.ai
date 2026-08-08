import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/core/components/pg_eyebrow.dart';
import 'package:pharmaguide/core/components/pg_pill_button.dart';
import 'package:pharmaguide/core/components/pg_settings_tile.dart';
import 'package:pharmaguide/core/components/pg_toast.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/features/settings/providers/app_preferences_provider.dart';
import 'package:pharmaguide/features/settings/providers/notification_settings_provider.dart';
import 'package:pharmaguide/services/notifications/notification_authorization_service.dart';
import 'package:pharmaguide/services/settings/app_preferences.dart';

String notificationSettingsCaption(
  NotificationAuthorizationStatus status,
  NotificationPreferences preferences, {
  bool isLoading = false,
}) {
  if (isLoading) return 'Checking status…';
  return switch (status) {
    NotificationAuthorizationStatus.notDetermined => 'Not enabled',
    NotificationAuthorizationStatus.blocked ||
    NotificationAuthorizationStatus.restricted => 'Blocked in device settings',
    NotificationAuthorizationStatus.unavailable => 'Status unavailable',
    NotificationAuthorizationStatus.unsupported => 'Unavailable on this device',
    NotificationAuthorizationStatus.allowed
        when !preferences.remindersEnabled =>
      'Reminders paused',
    NotificationAuthorizationStatus.allowed
        when !preferences.stackRemindersEnabled &&
            !preferences.healthHistoryRemindersEnabled =>
      'No reminder types selected',
    NotificationAuthorizationStatus.allowed => 'Allowed',
  };
}

class NotificationSettingsSheet extends ConsumerWidget {
  const NotificationSettingsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authorization = ref.watch(notificationSettingsControllerProvider);
    final preferences = ref
        .watch(appPreferencesControllerProvider)
        .preferences
        .notifications;
    final unsupported =
        authorization.status == NotificationAuthorizationStatus.unsupported;
    final categoryEnabled = preferences.remindersEnabled && !unsupported;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        V2Spacing.space24,
        V2Spacing.space8,
        V2Spacing.space24,
        V2Spacing.space24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Notifications',
            style: V2Typography.titleSm(color: context.v2.fg),
          ),
          const SizedBox(height: V2Spacing.space16),
          _AuthorizationStatusCard(controller: authorization),
          const SizedBox(height: V2Spacing.space24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: V2Spacing.space8),
            child: PGEyebrow('Reminder preferences', color: context.v2.fgMuted),
          ),
          const SizedBox(height: V2Spacing.space8),
          PGSettingsGroup(
            children: [
              PGSettingsTile(
                icon: Icons.notifications_active_outlined,
                title: 'Allow reminders',
                caption: 'Pause or resume all reminder delivery',
                trailing: Semantics(
                  label: 'Allow reminders',
                  toggled: preferences.remindersEnabled,
                  enabled: !unsupported,
                  excludeSemantics: true,
                  onTap: unsupported
                      ? null
                      : () => _savePreference(
                          context,
                          ref
                              .read(appPreferencesControllerProvider)
                              .updateRemindersEnabled(
                                !preferences.remindersEnabled,
                              ),
                        ),
                  child: Switch.adaptive(
                    key: const Key('allow-reminders-switch'),
                    value: preferences.remindersEnabled,
                    onChanged: unsupported
                        ? null
                        : (value) => _savePreference(
                            context,
                            ref
                                .read(appPreferencesControllerProvider)
                                .updateRemindersEnabled(value),
                          ),
                  ),
                ),
              ),
              PGSettingsTile(
                icon: Icons.medication_outlined,
                title: 'Stack reminders',
                caption: 'Times saved on supplement and medication cards',
                trailing: Semantics(
                  label: 'Stack reminders',
                  toggled: preferences.stackRemindersEnabled,
                  enabled: categoryEnabled,
                  excludeSemantics: true,
                  onTap: categoryEnabled
                      ? () => _savePreference(
                          context,
                          ref
                              .read(appPreferencesControllerProvider)
                              .updateStackRemindersEnabled(
                                !preferences.stackRemindersEnabled,
                              ),
                        )
                      : null,
                  child: Switch.adaptive(
                    key: const Key('stack-reminders-switch'),
                    value: preferences.stackRemindersEnabled,
                    onChanged: categoryEnabled
                        ? (value) => _savePreference(
                            context,
                            ref
                                .read(appPreferencesControllerProvider)
                                .updateStackRemindersEnabled(value),
                          )
                        : null,
                  ),
                ),
              ),
              PGSettingsTile(
                icon: Icons.event_note_outlined,
                title: 'Health History reminders',
                caption: 'Appointments, tests, and follow-ups',
                trailing: Semantics(
                  label: 'Health History reminders',
                  toggled: preferences.healthHistoryRemindersEnabled,
                  enabled: categoryEnabled,
                  excludeSemantics: true,
                  onTap: categoryEnabled
                      ? () => _savePreference(
                          context,
                          ref
                              .read(appPreferencesControllerProvider)
                              .updateHealthHistoryRemindersEnabled(
                                !preferences.healthHistoryRemindersEnabled,
                              ),
                        )
                      : null,
                  child: Switch.adaptive(
                    key: const Key('health-history-reminders-switch'),
                    value: preferences.healthHistoryRemindersEnabled,
                    onChanged: categoryEnabled
                        ? (value) => _savePreference(
                            context,
                            ref
                                .read(appPreferencesControllerProvider)
                                .updateHealthHistoryRemindersEnabled(value),
                          )
                        : null,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: V2Spacing.space16),
          Semantics(
            label: 'Notification privacy',
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.lock_outline_rounded,
                  size: 18,
                  color: context.v2.fgMuted,
                ),
                const SizedBox(width: V2Spacing.space8),
                Expanded(
                  child: Text(
                    "Lock-screen reminders don't include medication names, "
                    'doses, conditions, appointments, or notes.',
                    style: V2Typography.bodySm(color: context.v2.fgMuted),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _savePreference(
    BuildContext context,
    Future<void> update,
  ) async {
    try {
      await update;
    } on Object {
      if (!context.mounted) return;
      PGToast.show(
        context,
        'Could not save notification settings. Try again.',
        variant: PGToastVariant.error,
      );
    }
  }
}

class _AuthorizationStatusCard extends StatelessWidget {
  const _AuthorizationStatusCard({required this.controller});

  final NotificationSettingsController controller;

  @override
  Widget build(BuildContext context) {
    final presentation = _StatusPresentation.from(controller.status);
    final busy = controller.isLoading || controller.isActionInProgress;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(V2Spacing.space16),
      decoration: BoxDecoration(
        color: context.v2.surface,
        border: Border.all(color: context.v2.outline),
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                presentation.icon,
                size: 22,
                color: presentation.color(context),
              ),
              const SizedBox(width: V2Spacing.space12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      busy && controller.isLoading
                          ? 'Checking notification status'
                          : presentation.title,
                      style: V2Typography.bodyMedium(color: context.v2.fg),
                    ),
                    const SizedBox(height: V2Spacing.space4),
                    Text(
                      presentation.body,
                      style: V2Typography.bodySm(color: context.v2.fgMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (presentation.action != _StatusAction.none) ...[
            const SizedBox(height: V2Spacing.space16),
            PGPillButton(
              key: const Key('notification-status-action'),
              label: presentation.action.label,
              variant: PGPillVariant.secondary,
              expand: true,
              onPressed: busy ? null : () => _runAction(presentation.action),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _runAction(_StatusAction action) => switch (action) {
    _StatusAction.enable => controller.requestPermission(),
    _StatusAction.openSettings => controller.openSettings(),
    _StatusAction.retry => controller.refresh(),
    _StatusAction.none => Future<void>.value(),
  };
}

enum _StatusAction {
  none(''),
  enable('Enable notifications'),
  openSettings('Open device settings'),
  retry('Try again');

  const _StatusAction(this.label);

  final String label;
}

class _StatusPresentation {
  const _StatusPresentation({
    required this.title,
    required this.body,
    required this.icon,
    required this.action,
    required this.color,
  });

  final String title;
  final String body;
  final IconData icon;
  final _StatusAction action;
  final Color Function(BuildContext context) color;

  factory _StatusPresentation.from(NotificationAuthorizationStatus status) {
    return switch (status) {
      NotificationAuthorizationStatus.allowed => _StatusPresentation(
        title: 'Notifications allowed',
        body: 'Choose which reminders PharmaGuide may schedule.',
        icon: Icons.check_circle_outline_rounded,
        action: _StatusAction.openSettings,
        color: (context) => context.v2.accent,
      ),
      NotificationAuthorizationStatus.notDetermined => _StatusPresentation(
        title: 'Enable notifications',
        body: 'PharmaGuide asks only after you tap Enable.',
        icon: Icons.notifications_none_rounded,
        action: _StatusAction.enable,
        color: (context) => context.v2.fgMuted,
      ),
      NotificationAuthorizationStatus.blocked => _StatusPresentation(
        title: 'Notifications are blocked',
        body: 'Allow notifications in device settings to receive reminders.',
        icon: Icons.notifications_off_outlined,
        action: _StatusAction.openSettings,
        color: (context) => context.v2.caution,
      ),
      NotificationAuthorizationStatus.restricted => _StatusPresentation(
        title: 'Notifications are restricted',
        body: 'Device controls currently prevent notification delivery.',
        icon: Icons.notifications_off_outlined,
        action: _StatusAction.openSettings,
        color: (context) => context.v2.caution,
      ),
      NotificationAuthorizationStatus.unavailable => _StatusPresentation(
        title: "Couldn't check notification status.",
        body: 'Your saved reminder choices have not changed.',
        icon: Icons.sync_problem_outlined,
        action: _StatusAction.retry,
        color: (context) => context.v2.caution,
      ),
      NotificationAuthorizationStatus.unsupported => _StatusPresentation(
        title: "Notifications aren't available on this device.",
        body: 'Reminder delivery is unavailable here.',
        icon: Icons.notifications_off_outlined,
        action: _StatusAction.none,
        color: (context) => context.v2.fgMuted,
      ),
    };
  }
}
