import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stores recent search queries in SharedPreferences.
/// Max 10 entries, most recent first. Deduplicates normalized queries.
class RecentSearchesService {
  static const _key = 'recent_searches';
  static const _maxEntries = 10;

  /// Get the list of recent search queries, most recent first.
  Future<List<String>> getRecent() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_key) ?? [];
    final normalized = _normalizedHistory(stored);
    if (!_sameList(stored, normalized)) {
      await prefs.setStringList(_key, normalized);
    }
    return normalized;
  }

  /// Add a search query to the top of the list.
  /// Deduplicates case-insensitively (moves existing entry to top).
  Future<void> addSearch(String query) async {
    final displayQuery = _displayQuery(query);
    if (displayQuery.isEmpty) return;
    final queryKey = _dedupeKey(displayQuery);

    final prefs = await SharedPreferences.getInstance();
    final current = _normalizedHistory(prefs.getStringList(_key) ?? []);

    // Remove existing duplicates from older app versions too.
    current.removeWhere((entry) => _dedupeKey(entry) == queryKey);

    // Add to front
    current.insert(0, displayQuery);

    // Trim to max
    if (current.length > _maxEntries) {
      current.removeRange(_maxEntries, current.length);
    }

    await prefs.setStringList(_key, current);
  }

  /// Remove a specific search from history.
  Future<void> removeSearch(String query) async {
    final prefs = await SharedPreferences.getInstance();
    final current = _normalizedHistory(prefs.getStringList(_key) ?? []);
    final queryKey = _dedupeKey(query);
    current.removeWhere((entry) => _dedupeKey(entry) == queryKey);
    await prefs.setStringList(_key, current);
  }

  /// Clear all recent searches.
  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  static String _displayQuery(String query) {
    return query.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  static String _dedupeKey(String query) {
    return _displayQuery(query).toLowerCase();
  }

  static List<String> _normalizedHistory(List<String> entries) {
    final seen = <String>{};
    final normalized = <String>[];
    for (final entry in entries) {
      final displayQuery = _displayQuery(entry);
      if (displayQuery.isEmpty) continue;
      if (!seen.add(_dedupeKey(displayQuery))) continue;
      normalized.add(displayQuery);
      if (normalized.length == _maxEntries) break;
    }
    return normalized;
  }

  static bool _sameList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Riverpod provider for [RecentSearchesService].
final recentSearchesServiceProvider = Provider<RecentSearchesService>(
  (ref) => RecentSearchesService(),
);
