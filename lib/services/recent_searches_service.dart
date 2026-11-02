import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/services/auth/account_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stores recent search queries in SharedPreferences, per account: they are the
/// user's health-interest queries (ADR-013).
/// Max 10 entries, most recent first. Deduplicates on add.
class RecentSearchesService {
  RecentSearchesService({String scope = AccountStorage.guestScope})
    : _key = keyFor(scope);

  static const legacyKey = 'recent_searches';
  static const _maxEntries = 10;

  static String keyFor(String scope) => '$legacyKey.$scope';

  final String _key;

  /// The pre-ADR-013 shared list goes to whoever owned the shared database.
  static Future<void> adoptLegacyEntries(String scope) =>
      _move(legacyKey, keyFor(scope));

  /// The guest's list follows the guest's data on a first sign-in.
  static Future<void> moveScope({required String from, required String to}) =>
      _move(keyFor(from), keyFor(to));

  static Future<void> deleteScope(String scope) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(keyFor(scope));
  }

  static Future<void> _move(String from, String to) async {
    final prefs = await SharedPreferences.getInstance();
    final entries = prefs.getStringList(from);
    if (entries == null) return;
    if (prefs.getStringList(to) == null) {
      await prefs.setStringList(to, entries);
    }
    await prefs.remove(from);
  }

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
  (ref) => RecentSearchesService(scope: ref.watch(activeAccountProvider).scope),
);
