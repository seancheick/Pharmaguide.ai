# Unified Theme and Notification Preferences

**Status:** Approved for implementation planning  
**Date:** 2026-08-08

## Purpose

Replace the generic Theme and Notifications sheets in the Profile tab with real, persisted controls that drive the whole app. Theme selection must support System, Light, and Dark. Notification settings must coordinate the existing Stack and Health History reminder schedulers and leave a safe extension point for future FDA recall alerts.

This is a local app-preferences feature. It must not store profile or medication data in Supabase and must not run or change the clinical data pipeline.

## Current behavior

- Both app roots provide `V2Theme.light` and `V2Theme.dark` but hard-code `ThemeMode.system`.
- Profile shows a static `System` Theme caption and opens explanatory copy instead of a selector.
- Profile opens explanatory copy for Notifications instead of reporting permission or controlling delivery.
- Stack reminders and Health History reminders already have separate, tested schedulers and non-overlapping notification ID ranges.
- The local database remains the source of truth for reminder times. OS notifications are disposable projections.

## Product decisions

### Theme

The user can select exactly one appearance mode:

1. **System** — follows the current device appearance and updates when the device changes.
2. **Light** — always uses the existing light theme.
3. **Dark** — always uses the existing dark theme.

System is the default for new and existing installs without a saved preference. A selection applies immediately and persists across launches. The Profile tile caption always reflects the saved mode: `System`, `Light`, or `Dark`.

### Notification control model

Notification authorization and PharmaGuide preferences are separate facts:

- **System authorization** is owned by iOS/Android. The app can request it after an explicit user action and can direct the user to system settings, but cannot override a denial.
- **PharmaGuide preferences** decide which eligible local notification producers may project scheduled notifications.
- **Saved reminder data** stays in the local database even when delivery is paused or permission is denied.

The first implementation supports:

- `remindersEnabled` — master pause for reminder delivery.
- `stackRemindersEnabled` — Stack item reminders.
- `healthHistoryRemindersEnabled` — Health History reminders.

All three default to enabled so existing opted-in reminders continue behaving as they do today. A category can deliver only when the master preference and that category preference are both enabled.

### Future FDA recall alerts

Recall alerts are a distinct future notification category, not a reminder subtype.

- The in-app recalled status and red supplement treatment are safety state. They must render from the authoritative recall evaluation regardless of notification authorization or notification preferences.
- A recall notification is only an additional delivery channel. Notification state must never drive, suppress, or downgrade the in-app recall verdict.
- The settings architecture must allow a future `safetyRecallAlerts` category without adding another preference system or scheduler policy.
- No interactive Recall Alerts switch is shown until the recall notification producer can actually deliver. The initial UI must not promise an unwired feature.
- When implemented, recall delivery will deduplicate by stable product/recall-event identity, persist an on-device delivery record, use a dedicated Android channel, and deep-link to the affected recall detail.
- Default lock-screen copy will be generic: `A product in your stack has a recall update. Open PharmaGuide for details.`

## User experience

### Theme sheet

The Theme tile opens a bottom sheet titled **Appearance**. It shows three full-width, single-select rows with an icon/preview, title, short explanation, and checkmark:

- **System** — `Follows your device`
- **Light** — `Always use light appearance`
- **Dark** — `Always use dark appearance`

Rows have at least a 44-point tap target, expose selected state to assistive technology, and remain usable at supported text scales. Selection applies immediately; no Save button is required.

### Notifications sheet

The Notifications tile caption summarizes actual delivery state rather than a feature description:

- `Allowed` when system authorization permits delivery.
- `Not enabled` before permission is requested.
- `Blocked in device settings` after denial.
- `Reminders paused` when system authorization is available but the master preference is off.
- `No reminder types selected` when the master preference is on but both reminder categories are off.
- `Status unavailable` when authorization could not be read because of a transient platform/plugin failure.
- `Unavailable on this device` on a platform that does not support these local notifications.

The sheet contains:

1. **System status**
   - Allowed: calm confirmation and an `Open device settings` secondary action.
   - Not determined: explanation plus `Enable notifications`; the OS prompt appears only after this tap.
   - Denied/restricted: explanation plus `Open device settings`.
   - Transiently unavailable: `Couldn't check notification status.` plus a `Try again` action. Do not offer device settings when the app has not confirmed that settings are the remedy.
   - Unsupported platform: `Notifications aren't available on this device.` with no permission or settings action.
2. **Reminder preferences**
   - `Allow reminders` master switch.
   - `Stack reminders` category switch.
   - `Health History reminders` category switch.
   - Category choices remain stored while the master switch is off. They appear disabled but are restored when reminders resume.
3. **Privacy note**
   - `Lock-screen reminders don't include medication names, doses, conditions, appointments, or notes.`

The sheet refreshes system authorization after returning from device settings so the displayed status cannot remain stale.

## Architecture

### Preferences contract

Add one local preferences repository with a small immutable value object:

```dart
enum AppThemePreference { system, light, dark }

class NotificationPreferences {
  final bool remindersEnabled;
  final bool stackRemindersEnabled;
  final bool healthHistoryRemindersEnabled;
}

class AppPreferences {
  final AppThemePreference theme;
  final NotificationPreferences notifications;
}
```

The repository uses `SharedPreferencesAsync`, the current recommended API for new shared-preferences code. Values are non-sensitive configuration only. Unknown or malformed stored values fall back independently to safe defaults rather than failing app startup.

### State and composition

A single Riverpod controller owns the loaded preferences and mutations.

- `PharmaGuideApp` watches the controller and maps `AppThemePreference` to Flutter `ThemeMode`.
- The bootstrap MaterialApp receives the restored preference too, preventing a light/system flash before the routed app mounts.
- `SettingsV2Connected` watches the same controller and provides live captions and sheets.
- Notification schedulers consume derived delivery-policy providers. Widgets do not call schedulers directly or reconstruct eligibility.

### Notification coordination

Each existing scheduler keeps its current responsibility and ID namespace. The shared preference policy gates its projection:

- Disabled category: cancel only notifications owned by that scheduler; do not delete reminder fields or Health History events.
- Enabled category: rebuild desired OS notifications from the existing local source of truth.
- Permission denied: preserve desired local state, report delivery unavailable, and schedule nothing.
- Preference or authorization changes invalidate/resync both notification projections through one coordinator/provider boundary.

The future recall producer will implement the same notification-category contract but will remain independent of the reminder master switch.

### Platform authorization boundary

Create one injectable notification-authorization service responsible for:

- Reading current authorization status.
- Requesting permission after a user action.
- Opening app notification settings.
- Refreshing status when the app resumes.

The UI depends on this service's normalized status enum, not platform-specific plugin types. The enum distinguishes `unavailable` (a transient read/request failure that can be retried) from `unsupported` (no notification implementation on this platform). Unsupported platforms degrade without crashing, expose no permission/settings action, and disable notification-preference controls.

## Failure behavior

- Preference read failure: use defaults for this launch and keep the app usable.
- Preference write failure: restore the prior in-memory value and show a concise error toast.
- Permission/status request failure: show `Status unavailable`, retain preferences, do not add or replace schedules, and offer `Try again`; do not claim reminders are active. Leave previously scheduled owned notifications intact until a successful status read can make an informed resync decision, so a transient plugin failure does not silently erase reminders.
- Unsupported platform: show `Unavailable on this device`, disable notification-preference controls, and offer no permission or settings action.
- Scheduler failure: preserve database reminder state and surface the existing unavailable/delivery messaging.
- Returning from system settings: re-read authorization before updating captions or rescheduling.
- Theme switching must not rebuild or replace the ProviderScope, databases, router, or clinical state.

## Accessibility and visual requirements

- Do not rely on color alone for selected, allowed, paused, or blocked states.
- Switches and selection rows require descriptive semantics and 44-point minimum targets.
- Light and dark sheets must use existing V2 semantic palette tokens; no hard-coded light-only surfaces.
- Respect the app's supported Dynamic Type range without clipping labels or status copy.
- Device/simulator screenshots are required in System-Light, forced Light, and forced Dark states before completion.

## Testing and acceptance

### Theme

- Missing/invalid preference resolves to System.
- Selecting each mode updates `MaterialApp.themeMode` immediately.
- Saved selection restores after rebuilding the app controller.
- System mode follows simulated platform brightness changes.
- Profile caption matches the saved choice.
- Bootstrap and routed app use the same preference.

### Notifications

- Permission is never requested merely by opening the sheet.
- Tapping Enable requests permission once and refreshes status.
- Denied status offers device settings rather than repeatedly prompting.
- App-resume refresh reflects changes made in system settings.
- Master pause cancels both owned notification projections without clearing saved reminder data.
- Category pause cancels only that category's owned IDs.
- Re-enabling rebuilds schedules from the local database without duplicates.
- Profile caption distinguishes Allowed, Not enabled, Blocked, Reminders paused, No reminder types selected, Status unavailable, and Unavailable on this device.
- Privacy copy remains generic and no notification payload contains medication, dose, condition, appointment, or note text.

### Recall extension seam

- Notification preference/category modeling can add `safetyRecallAlerts` without modifying theme state or either reminder scheduler.
- Existing reminder master pause is not treated as authority over future in-app recall status.
- No Recall Alerts toggle renders while its producer is unavailable.

### Verification

- Focused repository/controller tests.
- Focused notification scheduler/provider tests.
- Profile settings widget tests.
- Theme and dark-surface tests.
- `flutter analyze` and the broad affected Flutter test sweep.
- Simulator screenshots; no clinical pipeline run.

## Out of scope

- Implementing FDA recall polling, matching, delivery, or recall-status UI changes.
- Changing existing reminder content beyond the unified privacy statement.
- Remote/push notification infrastructure.
- Syncing app preferences to Supabase.
- Redesigning unrelated Profile settings.
- Adding new clinical rules or modifying the clinical data pipeline.

## Research basis

- Flutter `MaterialApp.themeMode`: <https://api.flutter.dev/flutter/material/MaterialApp/themeMode.html>
- Flutter shared preferences guidance: <https://pub.dev/packages/shared_preferences>
- Apple notification settings: <https://developer.apple.com/documentation/usernotifications/unnotificationsettings>
- Apple notification-settings deep link: <https://developer.apple.com/documentation/uikit/uiapplication/opennotificationsettingsurlstring>
- Android notification permission: <https://developer.android.com/develop/ui/compose/notifications/notification-permission>
- Android notification channels: <https://developer.android.com/develop/ui/compose/notifications/channels>
- Flutter local notifications: <https://pub.dev/packages/flutter_local_notifications>
