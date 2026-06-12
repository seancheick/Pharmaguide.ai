import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stores recent search queries in SharedPreferences.
/// Max 10 entries, most recent first. Deduplicates on add.
class RecentSearchesService {
  static const _key = 'recent_searches';
  static const _maxEntries = 10;

  /// Get the list of recent search queries, most recent first.
  ///
  /// Collapses stale keystroke fragments: an entry that is a strict
  /// prefix of a newer entry (e.g. "thor" when "thorne" is newer) is
  /// dropped. Cheap cleanup for lists persisted before commit-only
  /// recording landed.
  Future<List<String>> getRecent() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    return _collapsePrefixes(raw);
  }

  /// Drop entries that are strict prefixes (case-insensitive) of a
  /// newer entry, and case-insensitive duplicates of a newer entry.
  static List<String> _collapsePrefixes(List<String> entries) {
    final out = <String>[];
    for (final entry in entries) {
      final lower = entry.toLowerCase();
      final shadowedByNewer = out.any((newer) {
        final n = newer.toLowerCase();
        return n == lower || (n.startsWith(lower) && n.length > lower.length);
      });
      if (!shadowedByNewer) out.add(entry);
    }
    return out;
  }

  /// Add a search query to the top of the list.
  /// Deduplicates case-insensitively (moves existing entry to top).
  Future<void> addSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getStringList(_key) ?? [];

    // Remove existing duplicate (case-insensitive)
    current.removeWhere((e) => e.toLowerCase() == trimmed.toLowerCase());

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
