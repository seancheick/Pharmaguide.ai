import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/app.dart';
import 'package:pharmaguide/data/supabase/supabase_client.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase (will use placeholders if no env vars set)
  try {
    await initSupabase();
  } catch (_) {
    // Supabase init may fail with placeholder URL — app still works offline
    debugPrint('Supabase init skipped (no valid URL configured)');
  }

  runApp(
    const ProviderScope(
      child: PharmaGuideApp(),
    ),
  );
}
