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
}

/// Thrown in debug mode when the app is started without `--dart-define`
/// flags for Supabase. Release mode silently runs on placeholders because
/// guest-mode is still partially functional on the bundled catalog.
class SupabasePlaceholderConfigException implements Exception {
  const SupabasePlaceholderConfigException();

  @override
  String toString() => 'SupabasePlaceholderConfigException: '
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
/// **Release mode graceful fallback:** production builds are assumed to be
/// signed with the proper dart-defines. If they somehow aren't, we silently
/// continue and let the catalog sync fall back to the bundled DB (guest mode
/// works without network as long as `pharmaguide_core.db` is bundled).
Future<void> initSupabase() async {
  if (SupabaseConfig.isPlaceholder) {
    if (kDebugMode) {
      throw const SupabasePlaceholderConfigException();
    }
    // Release build — still call initialize() so `Supabase.instance.client`
    // exists, but catalog sync will no-op.
  }
  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
  );
}

/// Convenience accessor.
SupabaseClient get supabase => Supabase.instance.client;
