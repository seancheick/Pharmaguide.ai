import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase configuration.
///
/// Values come from `--dart-define=SUPABASE_URL=…` and `SUPABASE_ANON_KEY=…`
/// which the `Makefile` injects from `.env` on every `make run`. Raw
/// `flutter run` without dart-defines produces the placeholder values below,
/// which is why the startup guard fires in debug mode (see [initSupabase]).
abstract final class SupabaseConfig {
  static const _placeholderUrl = 'https://placeholder.supabase.co';
  static const _placeholderKey = 'placeholder-anon-key';

  static const url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: _placeholderUrl,
  );
  static const anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: _placeholderKey,
  );

  /// True when either of the two env vars are still at placeholder. Used by
  /// [initSupabase] to fail fast in debug builds and by the scanner / catalog
  /// sync to skip network calls that will definitely fail.
  static bool get isPlaceholder =>
      url == _placeholderUrl || anonKey == _placeholderKey;

  static void validateForRuntime({required bool releaseMode}) {
    if (!isPlaceholder) return;
    if (releaseMode || kDebugMode) {
      throw const SupabasePlaceholderConfigException();
    }
  }
}

/// Thrown in debug mode when the app is started without `--dart-define`
/// flags for Supabase. Release mode silently runs on placeholders because
/// guest-mode is still partially functional on the bundled catalog.
class SupabasePlaceholderConfigException implements Exception {
  const SupabasePlaceholderConfigException();

  @override
  String toString() =>
      'SupabasePlaceholderConfigException: '
      'SUPABASE_URL or SUPABASE_ANON_KEY is still at placeholder. '
      'Run the app via `make run` (or `make run-ios` / `make run-android`) '
      'so the Makefile injects --dart-define flags from your .env file. '
      'Raw `flutter run` does NOT pass dart-defines.';
}

/// Initialize Supabase. Call once in main() before runApp.
///
/// **Debug mode fail-fast:** if the URL is still at placeholder when we
/// reach this call, we throw [SupabasePlaceholderConfigException] so the
/// engineer notices immediately instead of chasing a "Failed host lookup"
/// error 10 seconds into the session.
///
/// **Release mode fail-fast:** production builds must be signed with the
/// proper dart-defines. Placeholder Supabase config disables auth, sync, and
/// OTA catalog refresh, so it is treated as a build/release error.
Future<void> initSupabase() async {
  SupabaseConfig.validateForRuntime(releaseMode: kReleaseMode);
  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
  );
}

/// Convenience accessor.
SupabaseClient get supabase => Supabase.instance.client;
