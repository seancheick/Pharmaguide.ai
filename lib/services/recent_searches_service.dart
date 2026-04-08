import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stores recent search queries in SharedPreferences.
/// Max 10 entries, most recent first. Deduplicates on add.
class RecentSearchesService {
  static const _key = 'recent_searches';
  static const _maxEntries = 10;

  /// Get the list of recent search queries, most recent first.
  Future<List<String>> getRecent() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_key) ?? [];
  }

  /// Add a search query to the top of the list.
  /// Deduplicates (moves existing entry to top).
  Future<void> addSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getStringList(_key) ?? [];

    // Remove existing duplicate
    current.remove(trimmed);

    // Add to front
    current.insert(0, trimmed);

    // Trim to max
    if (current.length > _maxEntries) {
      current.removeRange(_maxEntries, current.length);
    }

    await prefs.setStringList(_key, current);
  }

  /// Remove a specific search from history.
  Future<void> removeSearch(String query) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getStringList(_key) ?? [];
    current.remove(query);
    await prefs.setStringList(_key, current);
  }

  /// Clear all recent searches.
  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

/// Riverpod provider for [RecentSearchesService].
final recentSearchesServiceProvider = Provider<RecentSearchesService>(
  (ref) => RecentSearchesService(),
);
