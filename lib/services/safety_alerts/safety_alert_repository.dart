import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pharmaguide/data/supabase/supabase_client.dart';
import 'package:pharmaguide/data/supabase/supabase_contract.dart';
import 'package:pharmaguide/services/safety_alerts/safety_alert.dart';

final class SafetyAlertRelease {
  const SafetyAlertRelease({
    required this.alerts,
    required this.baselineRevisions,
    required this.isComplete,
    this.neverVerified = false,
  });

  final List<SafetyAlert> alerts;

  /// Alert revisions present when this device first obtained a verified feed.
  /// They surface in-app, but never create a retrospective "new" event.
  final Map<String, int> baselineRevisions;
  final bool isComplete;

  /// A fetch failed and this device holds no verified copy, so [alerts] being
  /// empty says nothing about any product.
  final bool neverVerified;
}

/// Fetches only the public, current release and refuses bytes that do not
/// match its checksum. Last-known-good is retained for display but is marked
/// incomplete, so it can never resolve a safety signal after a failed fetch.
class SafetyAlertRepository {
  SafetyAlertRepository({
    SupabaseClient? client,
    SharedPreferencesAsync? preferences,
  }) : _givenClient = client,
       _preferences = preferences ?? SharedPreferencesAsync();

  static const _cacheKey = 'safety_alert_release_v1';
  static const _watermarkKey = 'safety_alert_baseline_revisions_v1';
  final SupabaseClient? _givenClient;
  final SharedPreferencesAsync _preferences;

  /// Read inside the fetch: Supabase failing to start is a failed fetch, and a
  /// saved copy still counts.
  SupabaseClient get _client => _givenClient ?? supabase;

  Future<SafetyAlertRelease> loadCurrent() async {
    try {
      final row = await _client
          .from(SupabaseContract.safetyAlertReleasesTable)
          .select('feed_path,checksum,manifest')
          .eq('is_current', true)
          .maybeSingle();
      if (row == null) {
        return const SafetyAlertRelease(
          alerts: [],
          baselineRevisions: {},
          isComplete: true,
        );
      }
      final remote = await _decodeRemote(Map<String, dynamic>.from(row));
      final release = remote.keeping(
        (await _loadCached())?.rowsFor(remote.unreadableIds) ?? const [],
      );
      await _preferences.setString(
        _cacheKey,
        jsonEncode(_cachePayload(release)),
      );
      return await _withWatermark(release, isComplete: !release.hasUnsupported);
    } on Object {
      final cached = await _loadCached();
      if (cached == null) {
        return const SafetyAlertRelease(
          alerts: [],
          baselineRevisions: {},
          isComplete: false,
          neverVerified: true,
        );
      }
      return await _withWatermark(cached, isComplete: false);
    }
  }

  /// Alerts from the last verified release stored on this device, without a
  /// network call. For instant decisions such as a scan result; display
  /// paths use [loadCurrent]. Empty when nothing has been cached yet.
  Future<List<SafetyAlert>> loadCachedAlerts() async {
    try {
      return (await _loadCached())?.alerts ?? const [];
    } on Object {
      return const [];
    }
  }

  Future<_DecodedRelease> _decodeRemote(Map<String, dynamic> row) async {
    final path = row['feed_path'];
    final checksum = row['checksum'];
    if (path is! String ||
        checksum is! String ||
        !RegExp(r'^sha256:[0-9a-f]{64}$').hasMatch(checksum)) {
      throw const FormatException(
        'Safety-alert release metadata is malformed.',
      );
    }
    Future<_DecodedRelease> read(String path, String checksum) async =>
        _decodeBytes(
          await _client.storage
              .from(SupabaseContract.storageBucket)
              .download(path),
          checksum,
        );

    // `feed_path` stays readable by every installed build, so event types an
    // older reader would reject live in a superset the manifest names.
    final manifest = row['manifest'];
    final extended = manifest is Map ? manifest['extended_feed'] : null;
    if (extended == null) return read(path, checksum);
    try {
      final extendedPath = extended['path'];
      final extendedChecksum = extended['checksum'];
      if (extendedPath is! String || extendedChecksum is! String) {
        throw const FormatException('Extended feed location is malformed.');
      }
      return await read(extendedPath, extendedChecksum);
    } on Object {
      // Bans and recalls must still arrive. Rules this device already holds
      // stay until a verified fetch can say otherwise.
      return (await read(path, checksum)).missingExtended(
        (await _loadCached())?.alerts
                .where((alert) => alert.interaction != null)
                .map((alert) => alert.alertId) ??
            const [],
      );
    }
  }

  _DecodedRelease _decodeBytes(Uint8List bytes, String expectedChecksum) {
    final actual = 'sha256:${sha256.convert(bytes).toString()}';
    if (actual != expectedChecksum) {
      throw const FormatException('Safety-alert feed checksum mismatch.');
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map || decoded['alerts'] is! List) {
      throw const FormatException('Safety-alert feed is malformed.');
    }
    final alerts = <SafetyAlert>[];
    final rows = <String, Map<String, Object?>>{};
    final unreadableIds = <String>{};
    var hasUnsupported = false;
    for (final raw in decoded['alerts'] as List) {
      final row = Map<String, Object?>.from(raw as Map);
      try {
        final alert = SafetyAlert.fromJson(row);
        alerts.add(alert);
        rows[alert.alertId] = row;
      } on UnsupportedSafetyAlert {
        hasUnsupported = true;
        unreadableIds.add((row['alert_id'] as String).trim());
      }
    }
    return _DecodedRelease(
      alerts: List.unmodifiable(alerts),
      rows: rows,
      unreadableIds: unreadableIds,
      hasUnsupported: hasUnsupported,
      checksum: actual,
      feedBytes: Uint8List.fromList(bytes).asUnmodifiableView(),
    );
  }

  Future<_DecodedRelease?> _loadCached() async {
    final raw = await _preferences.getString(_cacheKey);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map ||
          decoded['feed'] is! String ||
          decoded['checksum'] is! String) {
        return null;
      }
      final release = _decodeBytes(
        base64Decode(decoded['feed'] as String),
        decoded['checksum'] as String,
      );
      final kept = decoded['kept'];
      if (kept == null) return release;
      if (kept is! String || decoded['kept_checksum'] != _checksumOf(kept)) {
        return null;
      }
      final rows = [
        for (final row in jsonDecode(kept) as List)
          Map<String, Object?>.from(row as Map),
      ];
      return (decoded['extended_missing'] == true
              ? release.missingExtended(
                  rows.map((row) => (row['alert_id'] as String).trim()),
                )
              : release)
          .keeping(rows);
    } on Object {
      return null;
    }
  }

  Map<String, Object> _cachePayload(_DecodedRelease release) => {
    'checksum': release.checksum,
    // Retain exactly the verified downloaded bytes: re-encoding parsed alert
    // models loses feed metadata/formatting and invalidates the checksum.
    'feed': base64Encode(release.feedBytes),
    if (release.extendedMissing) 'extended_missing': true,
    if (release.keptRows.isNotEmpty)
      ...() {
        final kept = jsonEncode(release.keptRows);
        return {'kept': kept, 'kept_checksum': _checksumOf(kept)};
      }(),
  };

  String _checksumOf(String text) =>
      'sha256:${sha256.convert(utf8.encode(text))}';

  Future<SafetyAlertRelease> _withWatermark(
    _DecodedRelease release, {
    required bool isComplete,
  }) async {
    final current = {
      for (final alert in release.alerts) alert.alertId: alert.revision,
    };
    final raw = await _preferences.getString(_watermarkKey);
    if (raw == null) {
      await _preferences.setString(_watermarkKey, jsonEncode(current));
      return SafetyAlertRelease(
        alerts: release.alerts,
        baselineRevisions: current,
        isComplete: isComplete,
      );
    }
    final baseline = <String, int>{};
    try {
      final map = jsonDecode(raw);
      if (map is Map) {
        for (final entry in map.entries) {
          if (entry.key is String && entry.value is int) {
            baseline[entry.key as String] = entry.value as int;
          }
        }
      }
    } on Object {
      // A corrupt watermark is treated like first install: no historical nudges.
      await _preferences.setString(_watermarkKey, jsonEncode(current));
      return SafetyAlertRelease(
        alerts: release.alerts,
        baselineRevisions: current,
        isComplete: isComplete,
      );
    }
    return SafetyAlertRelease(
      alerts: release.alerts,
      baselineRevisions: baseline,
      isComplete: isComplete,
    );
  }
}

final class _DecodedRelease {
  const _DecodedRelease({
    required this.alerts,
    required this.rows,
    required this.unreadableIds,
    required this.hasUnsupported,
    required this.checksum,
    required this.feedBytes,
    this.keptRows = const [],
    this.extendedMissing = false,
  });
  final List<SafetyAlert> alerts;

  /// The raw record behind each alert in [alerts], so one can be carried into
  /// a later release.
  final Map<String, Map<String, Object?>> rows;

  /// Alerts whose current revision this build can't read.
  final Set<String> unreadableIds;

  /// Earlier revisions carried over for [unreadableIds]. A revision this build
  /// can't read must not take away a warning the device already shows; it goes
  /// when the publisher withdraws the alert or a readable revision arrives.
  final List<Map<String, Object?>> keptRows;

  /// The feed held alerts this build can't read, so it can never count as a
  /// complete check.
  final bool hasUnsupported;

  /// This is the base feed standing in for a superset that couldn't be read.
  final bool extendedMissing;
  final String checksum;
  final Uint8List feedBytes;

  List<Map<String, Object?>> rowsFor(Set<String> ids) => [
    for (final id in ids)
      if (rows[id] case final row?) row,
  ];

  /// The superset couldn't be read, so this can't count as a complete check, and
  /// [heldIds] may be carried over as if this build couldn't read them.
  _DecodedRelease missingExtended(Iterable<String> heldIds) => _DecodedRelease(
    alerts: alerts,
    rows: rows,
    unreadableIds: {...unreadableIds, ...heldIds},
    hasUnsupported: true,
    checksum: checksum,
    feedBytes: feedBytes,
    keptRows: keptRows,
    extendedMissing: true,
  );

  _DecodedRelease keeping(List<Map<String, Object?>> kept) {
    // Re-evaluate carried rows with this reader: an app upgrade may now read
    // the current revision. Withdrawn or readable alerts must not be revived.
    kept = [
      for (final row in kept)
        if (row['alert_id'] case final String id)
          if (unreadableIds.contains(id.trim()) && !rows.containsKey(id.trim()))
            row,
    ];
    if (kept.isEmpty) return this;
    final keptAlerts = kept.map(SafetyAlert.fromJson).toList();
    return _DecodedRelease(
      alerts: List.unmodifiable([...alerts, ...keptAlerts]),
      rows: {
        ...rows,
        for (final (i, alert) in keptAlerts.indexed) alert.alertId: kept[i],
      },
      unreadableIds: unreadableIds,
      hasUnsupported: hasUnsupported,
      checksum: checksum,
      feedBytes: feedBytes,
      keptRows: kept,
      extendedMissing: extendedMissing,
    );
  }
}
