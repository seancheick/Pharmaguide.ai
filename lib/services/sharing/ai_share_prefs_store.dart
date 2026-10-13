import 'dart:async';
import 'dart:convert';

import 'package:pharmaguide/services/settings/app_preferences.dart';
import 'package:pharmaguide/services/sharing/ai_share_scope.dart';

/// What the user last shared with one connected assistant, and whether
/// they opted in to keeping it updated. Device-only; never uploaded.
class AiShareConnectionPrefs {
  const AiShareConnectionPrefs({
    required this.scope,
    required this.ttlHours,
    this.keepUpdated = false,
  });

  final AiShareScope scope;
  final int ttlHours;

  /// Opt-in refresh after a stack change. Off by default (ADR-009).
  final bool keepUpdated;

  Map<String, Object?> toJson() => {
    'scope': scope.toJson(),
    'ttl_hours': ttlHours,
    'keep_updated': keepUpdated,
  };

  static AiShareConnectionPrefs? tryParse(Object? json) {
    if (json is! Map) return null;
    final scope = json['scope'];
    final ttl = json['ttl_hours'];
    if (scope is! Map || ttl is! int) return null;
    return AiShareConnectionPrefs(
      scope: AiShareScope.fromJson(scope.cast<String, Object?>()),
      ttlHours: ttl,
      keepUpdated: json['keep_updated'] == true,
    );
  }
}

/// Device-only AI-share preferences, keyed by connection id.
///
/// Owner: the app's key-value preference store ([AppPreferencesStore],
/// SharedPreferences-backed). The user database has no key-value table
/// (see `AccountOwnerStore`), so device-only preferences live there.
class AiSharePrefsStore {
  AiSharePrefsStore(this._store);

  static const key = 'ai_share_connection_prefs_v1';

  final AppPreferencesStore _store;

  // Shared across instances because sign-out constructs its own store.
  // This is a cancellation generation, never stored or sent off device.
  static int _revision = 0;
  int get revision => _revision;
  static Future<void>? _pending;

  Future<T> _mutate<T>(Future<T> Function(int generation) action) async {
    final generation = ++_revision;
    while (_pending != null) {
      await _pending;
    }
    final done = Completer<void>();
    _pending = done.future;
    try {
      return await action(generation);
    } finally {
      _pending = null;
      done.complete();
    }
  }

  Future<Map<String, AiShareConnectionPrefs>> readAll() async {
    while (_pending != null) {
      await _pending;
    }
    return _readAll();
  }

  Future<Map<String, AiShareConnectionPrefs>> _readAll() async {
    String? raw;
    try {
      raw = await _store.getString(key);
    } on Object {
      return const {};
    }
    if (raw == null || raw.isEmpty) return const {};
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return const {};
    }
    if (decoded is! Map) return const {};
    final result = <String, AiShareConnectionPrefs>{};
    decoded.forEach((id, value) {
      final prefs = AiShareConnectionPrefs.tryParse(value);
      if (id is String && prefs != null) result[id] = prefs;
    });
    return result;
  }

  Future<AiShareConnectionPrefs?> read(String connectionId) async =>
      (await readAll())[connectionId];

  /// Records the scope and duration the user just shared. Keeps the
  /// existing opt-in so a re-share never silently turns refresh on or off.
  Future<bool> recordShare(
    String connectionId,
    AiShareScope scope,
    int ttlHours, {
    int? expectedRevision,
    bool Function()? isStillOwner,
    bool? keepUpdated,
  }) => _mutate((generation) async {
    bool current() =>
        (expectedRevision == null ||
            (generation == expectedRevision + 1 && generation == _revision)) &&
        (isStillOwner?.call() ?? true);
    if (!current()) return false;
    final all = Map.of(await _readAll());
    if (!current()) return false;
    all[connectionId] = AiShareConnectionPrefs(
      scope: scope.normalized,
      ttlHours: ttlHours,
      keepUpdated: keepUpdated ?? all[connectionId]?.keepUpdated ?? false,
    );
    await _write(all);
    return true;
  });

  /// Turns the opt-in refresh on or off. Turning it on needs a recorded
  /// share: the refresh reuses exactly the scope the user saw then.
  Future<void> setKeepUpdated(String connectionId, bool on) =>
      _mutate((_) async {
        final all = Map.of(await _readAll());
        final current = all[connectionId];
        if (current == null) {
          if (!on) return;
          throw StateError('Share once before keeping this assistant updated.');
        }
        all[connectionId] = AiShareConnectionPrefs(
          scope: current.scope,
          ttlHours: current.ttlHours,
          keepUpdated: on,
        );
        await _write(all);
      });

  Future<void> forget(String connectionId) => _mutate((_) async {
    final all = Map.of(await _readAll());
    if (all.remove(connectionId) != null) await _write(all);
  });

  Future<void> clear() => _mutate((_) => _store.setString(key, '{}'));

  Future<void> _write(Map<String, AiShareConnectionPrefs> all) => _store
      .setString(key, jsonEncode(all.map((k, v) => MapEntry(k, v.toJson()))));
}
