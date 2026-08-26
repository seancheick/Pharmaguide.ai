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
  });

  final List<SafetyAlert> alerts;

  /// Alert revisions present when this device first obtained a verified feed.
  /// They surface in-app, but never create a retrospective "new" event.
  final Map<String, int> baselineRevisions;
  final bool isComplete;
}

/// Fetches only the public, current release and refuses bytes that do not
/// match its checksum. Last-known-good is retained for display but is marked
/// incomplete, so it can never resolve a safety signal after a failed fetch.
class SafetyAlertRepository {
  SafetyAlertRepository({SupabaseClient? client, SharedPreferencesAsync? preferences})
    : _client = client ?? supabase,
      _preferences = preferences ?? SharedPreferencesAsync();

  static const _cacheKey = 'safety_alert_release_v1';
  static const _watermarkKey = 'safety_alert_baseline_revisions_v1';
  final SupabaseClient _client;
  final SharedPreferencesAsync _preferences;

  Future<SafetyAlertRelease> loadCurrent() async {
    try {
      final row = await _client
          .from(SupabaseContract.safetyAlertReleasesTable)
          .select('feed_path,checksum,manifest')
          .eq('is_current', true)
          .maybeSingle();
      if (row == null) return const SafetyAlertRelease(alerts: [], baselineRevisions: {}, isComplete: true);
      final release = await _decodeRemote(Map<String, dynamic>.from(row));
      await _preferences.setString(_cacheKey, jsonEncode(_cachePayload(release)));
      return await _withWatermark(release, isComplete: true);
    } on Object {
      final cached = await _loadCached();
      if (cached == null) return const SafetyAlertRelease(alerts: [], baselineRevisions: {}, isComplete: false);
      return await _withWatermark(cached, isComplete: false);
    }
  }

  Future<_DecodedRelease> _decodeRemote(Map<String, dynamic> row) async {
    final path = row['feed_path'];
    final checksum = row['checksum'];
    if (path is! String || checksum is! String || !RegExp(r'^sha256:[0-9a-f]{64}$').hasMatch(checksum)) {
      throw const FormatException('Safety-alert release metadata is malformed.');
    }
    final bytes = await _client.storage.from(SupabaseContract.storageBucket).download(path);
    return _decodeBytes(bytes, checksum);
  }

  _DecodedRelease _decodeBytes(Uint8List bytes, String expectedChecksum) {
    final actual = 'sha256:${sha256.convert(bytes).toString()}';
    if (actual != expectedChecksum) throw const FormatException('Safety-alert feed checksum mismatch.');
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map || decoded['alerts'] is! List) {
      throw const FormatException('Safety-alert feed is malformed.');
    }
    final alerts = (decoded['alerts'] as List)
        .map((raw) => SafetyAlert.fromJson(Map<String, Object?>.from(raw as Map)))
        .toList(growable: false);
    return _DecodedRelease(alerts: alerts, checksum: actual);
  }

  Future<_DecodedRelease?> _loadCached() async {
    final raw = await _preferences.getString(_cacheKey);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['feed'] is! String || decoded['checksum'] is! String) return null;
      return _decodeBytes(base64Decode(decoded['feed'] as String), decoded['checksum'] as String);
    } on Object {
      return null;
    }
  }

  Map<String, Object> _cachePayload(_DecodedRelease release) => {
    'checksum': release.checksum,
    'feed': base64Encode(utf8.encode(jsonEncode({'alerts': release.alerts.map(_alertJson).toList()}))),
  };

  Future<SafetyAlertRelease> _withWatermark(_DecodedRelease release, {required bool isComplete}) async {
    final current = {for (final alert in release.alerts) alert.alertId: alert.revision};
    final raw = await _preferences.getString(_watermarkKey);
    if (raw == null) {
      await _preferences.setString(_watermarkKey, jsonEncode(current));
      return SafetyAlertRelease(alerts: release.alerts, baselineRevisions: current, isComplete: isComplete);
    }
    final baseline = <String, int>{};
    try {
      final map = jsonDecode(raw);
      if (map is Map) {
        for (final entry in map.entries) {
          if (entry.key is String && entry.value is int) baseline[entry.key as String] = entry.value as int;
        }
      }
    } on Object {
      // A corrupt watermark is treated like first install: no historical nudges.
      await _preferences.setString(_watermarkKey, jsonEncode(current));
      return SafetyAlertRelease(alerts: release.alerts, baselineRevisions: current, isComplete: isComplete);
    }
    return SafetyAlertRelease(alerts: release.alerts, baselineRevisions: baseline, isComplete: isComplete);
  }

  static Map<String, Object> _alertJson(SafetyAlert alert) => {
    'alert_id': alert.alertId,
    'revision': alert.revision,
    'event_type': alert.eventType == SafetyAlertEventType.ingredientBan ? 'ingredient_ban' : 'product_recall',
    'source_url': alert.sourceUrl.toString(),
    'headline': alert.headline,
    'body': alert.body,
    'action': alert.action,
    'consumer_disposition': alert.disposition.name,
    'resolved_dsld_ids': alert.resolvedDsldIds.toList(),
    'scope': <String, Object>{
      'ingredient_canonical_ids': alert.ingredientCanonicalIds.toList(),
      'dsld_ids': <String>[],
    },
  };
}

final class _DecodedRelease {
  const _DecodedRelease({required this.alerts, required this.checksum});
  final List<SafetyAlert> alerts;
  final String checksum;
}
