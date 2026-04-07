import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase configuration.
/// In production, these would come from environment variables or dart-define.
/// For now, use placeholders that can be overridden.
abstract final class SupabaseConfig {
  static const url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://placeholder.supabase.co',
  );
  static const anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'placeholder-anon-key',
  );
}

/// Initialize Supabase. Call once in main() before runApp.
Future<void> initSupabase() async {
  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
  );
}

/// Convenience accessor.
SupabaseClient get supabase => Supabase.instance.client;
