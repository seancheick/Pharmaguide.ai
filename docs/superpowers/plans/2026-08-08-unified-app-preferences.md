# Unified App Preferences Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Profile tab's placeholder Theme and Notifications sheets with persisted app-wide appearance controls and unified local-notification delivery preferences.

**Architecture:** Load one local `AppPreferencesController` before `runApp`, expose it through Riverpod, and make both MaterialApp roots consume the same `ThemeMode`. Normalize platform notification authorization behind one injectable service; keep Stack and Health History databases as reminder sources of truth while their OS projections obey shared delivery preferences. Reserve a typed recall-alert category seam without exposing nonfunctional UI or coupling recall verdicts to notification state.

**Tech Stack:** Flutter/Dart, Riverpod, `SharedPreferencesAsync`, `flutter_local_notifications`, `app_settings`, existing V2 theme/components.

**Spec:** `docs/superpowers/specs/2026-08-08-app-preferences-theme-notifications-design.md`

---

### Task 1: Persisted app-preferences contract

**Files:**
- Create: `lib/services/settings/app_preferences.dart`
- Test: `test/services/settings/app_preferences_test.dart`

- [ ] **Step 1: Write failing model/repository tests**

Cover System defaults, independent malformed-value fallback, round-trip persistence for all theme modes and notification booleans, and write-failure rollback through an injectable store interface.

- [ ] **Step 2: Run the focused test and verify RED**

Run: `flutter test test/services/settings/app_preferences_test.dart`

Expected: compilation failure because the app-preferences contract does not exist.

- [ ] **Step 3: Implement the minimum contract**

Define:

```dart
enum AppThemePreference { system, light, dark }

@immutable
class NotificationPreferences {
  final bool remindersEnabled;
  final bool stackRemindersEnabled;
  final bool healthHistoryRemindersEnabled;
}

@immutable
class AppPreferences {
  final AppThemePreference theme;
  final NotificationPreferences notifications;
}
```

Add an injectable async key-value store, a `SharedPreferencesAsync` production adapter, `AppPreferencesRepository.load/save*`, and `AppPreferencesController extends ChangeNotifier`. The controller updates optimistically, awaits persistence, rolls back on failure, and notifies both transitions.

- [ ] **Step 4: Run the focused test and verify GREEN**

Run: `flutter test test/services/settings/app_preferences_test.dart`

- [ ] **Step 5: Commit only Task 1 files**

### Task 2: App-wide theme wiring

**Files:**
- Modify: `lib/main.dart`
- Modify: `lib/app.dart`
- Test: `test/core/theme/app_theme_preference_test.dart`

- [ ] **Step 1: Write failing root-theme tests**

Test mapping of System/Light/Dark to `ThemeMode`, immediate controller updates, persistence across controller reconstruction, and a System-mode platform-brightness change. Pin that the bootstrap and routed MaterialApps receive the same selected mode.

- [ ] **Step 2: Run the focused test and verify RED**

Run: `flutter test test/core/theme/app_theme_preference_test.dart`

- [ ] **Step 3: Wire the controller once at composition root**

Load preferences before `runApp`; pass the controller into `PharmaGuideBootstrap`; override a single Riverpod provider in its existing `ProviderScope`; convert `PharmaGuideApp` to a `ConsumerWidget`; map the saved preference into both `MaterialApp.themeMode` properties. Do not replace `ProviderScope`, router, databases, or clinical state when theme changes.

- [ ] **Step 4: Run focused theme tests and existing dark-surface test**

Run: `flutter test test/core/theme/app_theme_preference_test.dart test/core/theme/dark_mode_surface_test.dart`

- [ ] **Step 5: Commit only Task 2 files**

### Task 3: Notification authorization boundary

**Files:**
- Add dependency: `pubspec.yaml`, `pubspec.lock` (`app_settings` compatible with the project's CocoaPods iOS setup)
- Create: `lib/services/notifications/notification_authorization_service.dart`
- Create: `lib/features/settings/providers/notification_settings_provider.dart`
- Test: `test/services/notifications/notification_authorization_service_test.dart`
- Test: `test/features/settings/notification_settings_provider_test.dart`

- [ ] **Step 1: Write failing normalized-status tests**

Cover `notDetermined`, `allowed`, `blocked`, `restricted`, `unavailable`, and `unsupported`; explicit request; settings handoff; transient failure; and app-resume refresh. Opening a settings sheet must not request permission.

- [ ] **Step 2: Run focused tests and verify RED**

Run: `flutter test test/services/notifications/notification_authorization_service_test.dart test/features/settings/notification_settings_provider_test.dart`

- [ ] **Step 3: Implement platform adapter and Riverpod controller**

Use `flutter_local_notifications` to query/request authorization and `app_settings` only to open the app notification-settings screen. Keep plugin/platform types behind:

```dart
enum NotificationAuthorizationStatus {
  notDetermined,
  allowed,
  blocked,
  restricted,
  unavailable,
  unsupported,
}
```

The controller implements `WidgetsBindingObserver`, refreshes on resume, and exposes request/retry/open-settings actions.

- [ ] **Step 4: Run focused tests and verify GREEN**

Run: `flutter test test/services/notifications/notification_authorization_service_test.dart test/features/settings/notification_settings_provider_test.dart`

- [ ] **Step 5: Commit only Task 3 files**

### Task 4: Gate both reminder projections with one delivery policy

**Files:**
- Modify: `lib/features/stack/providers/stack_reminder_providers.dart`
- Modify: `lib/features/history/providers/health_history_providers.dart`
- Modify: `lib/services/stack/stack_reminder_scheduler.dart`
- Modify: `lib/services/history/local_health_reminder_service.dart`
- Test: `test/services/stack/stack_reminder_scheduler_test.dart`
- Test: `test/services/history/local_health_reminder_service_test.dart`
- Test: `test/features/settings/reminder_delivery_policy_test.dart`

- [ ] **Step 1: Write failing delivery-policy tests**

Cover master pause cancelling both owned namespaces, category pause cancelling only its namespace, preserved database inputs, re-enable rescheduling without duplicate IDs, confirmed denied/restricted authorization cancelling OS projections while preserving database reminder inputs, and transient authorization read failure leaving existing OS schedules intact.

Add a focused policy-seam test for:

```dart
enum NotificationCategory {
  stackReminders,
  healthHistoryReminders,
  safetyRecallAlerts,
}
```

The test must prove the reminder master controls only the two reminder categories, while future recall delivery remains a distinct category governed by OS authorization and producer availability. It must also prove that no notification preference can affect the in-app recall verdict/state.

- [ ] **Step 2: Run focused tests and verify RED**

- [ ] **Step 3: Add explicit cancellation and derived policy**

Give each scheduler a `cancelOwned()` operation using its existing namespace guard. Add one reusable `NotificationDeliveryPolicy` keyed by `NotificationCategory`; the two existing sync providers consume it instead of reconstructing booleans. The typed `safetyRecallAlerts` category is present but reports unavailable until a producer is wired, and is not controlled by the reminder master. Only confirmed allowed + enabled policy may add/replace schedules. Paused/disabled policy cancels owned schedules. Confirmed denied/restricted authorization cancels owned OS projections but preserves reminder rows/events. Transiently unavailable authorization leaves existing OS schedules untouched. The delivery policy has no dependency on, and no setter for, the in-app recall result.

- [ ] **Step 4: Run focused scheduler/provider tests and verify GREEN**

Run: `flutter test test/services/stack/stack_reminder_scheduler_test.dart test/services/history/local_health_reminder_service_test.dart test/features/settings/reminder_delivery_policy_test.dart`

- [ ] **Step 5: Commit only Task 4 files**

### Task 5: Profile Theme and Notifications experience

**Files:**
- Create: `lib/features/settings/v2/theme_settings_sheet.dart`
- Create: `lib/features/settings/v2/notification_settings_sheet.dart`
- Modify: `lib/features/settings/v2/settings_v2_connected.dart`
- Modify: `lib/features/settings/v2/settings_v2_screen.dart`
- Test: `test/features/settings/v2/app_preferences_settings_test.dart`
- Modify: `test/features/settings/v2/settings_v2_screen_test.dart`

- [ ] **Step 1: Write failing widget tests**

Theme: three accessible rows, selected semantics, live captions, immediate appearance update, and write-error toast. Notifications: every caption/status mapping, explicit permission button, settings handoff, master/category switches, disabled-but-retained category choices, privacy copy, and no Recall Alerts toggle while unwired. Pin the unsupported-platform state: notification controls disabled, no permission action, and no settings handoff.

- [ ] **Step 2: Run widget tests and verify RED**

- [ ] **Step 3: Build the two V2 sheets and connected wiring**

Keep `SettingsV2Screen` presentational by adding caption and open callbacks. Open provider-backed sheets from `SettingsV2Connected`. Use existing palette/typography/spacing, 44-point targets, semantic selected/toggled states, and concise copy from the spec.

- [ ] **Step 4: Run widget tests and verify GREEN**

- [ ] **Step 5: Commit only Task 5 files**

### Task 6: Broad verification and simulator proof

**Files:**
- Review all files changed by Tasks 1–5.

- [ ] **Step 1: Run formatting and diff checks**

Run: `dart format <changed Dart files>` and `git diff --check`.

- [ ] **Step 2: Run static analysis**

Run: `flutter analyze`

- [ ] **Step 3: Run the broad affected test sweep**

Run:

```bash
flutter test \
  test/services/settings/app_preferences_test.dart \
  test/core/theme/app_theme_preference_test.dart \
  test/services/notifications/local_notification_timezone_test.dart \
  test/services/notifications/notification_authorization_service_test.dart \
  test/features/settings/notification_settings_provider_test.dart \
  test/features/settings/reminder_delivery_policy_test.dart \
  test/features/settings/v2/app_preferences_settings_test.dart \
  test/features/settings/v2/settings_v2_screen_test.dart \
  test/services/stack/stack_reminder_scheduler_test.dart \
  test/services/history/local_health_reminder_service_test.dart \
  test/core/theme/dark_mode_surface_test.dart \
  test/release_gate/android_notification_permission_test.dart
```

- [ ] **Step 4: Adversarial review**

Try invalid preference values, denied/restricted/unavailable/unsupported authorization, master on with both categories off, preference-write failure, app resume, System brightness changes, signed-out state, and no scheduled reminders. Confirm recall in-app state has no dependency on notification preferences.

- [ ] **Step 5: Simulator visual verification**

Capture Profile and both sheets in forced Light, forced Dark, and System mode. Check text scaling, contrast, sheet height, selected states, and status/action clarity.

- [ ] **Step 6: Final report**

Report implementation files, exact passing commands/counts, screenshots, and any remaining OS-only limitation. Explicitly state that the clinical pipeline was not run and FDA recall delivery itself remains future scope.
