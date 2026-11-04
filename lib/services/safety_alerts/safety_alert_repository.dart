import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pharmaguide/data/supabase/supabase_client.dart';
import 'package:pharmaguide/data/supabase/supabase_contract.dart';
import 'package:pharmaguide/services/release_manifest.dart';
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

  /// No fully readable verified feed is available for an all-clear. This also
  /// covers verified bytes containing unsupported alerts, a missing extended
  /// feed, or a saved copy whose signature this build can't check. A readable
  /// saved copy remains usable when only the network fails.
  final bool neverVerified;
}

/// Fetches only the public, current release, and trusts it only through its
/// signed statement: a missing or bad signature, an older sequence, or bytes that
/// do not match the signed checksum all count as a failed fetch. Last-known-good
/// is retained for display but is marked incomplete, so it can never resolve a
/// safety signal after a failed fetch.
class SafetyAlertRepository {
  SafetyAlertRepository({
    SupabaseClient? client,
    SharedPreferencesAsync? preferences,
    Map<String, String>? verificationKeys,
  }) : _givenClient = client,
       _preferences = preferences ?? SharedPreferencesAsync(),
       _keys = verificationKeys ?? kAlertFeedVerificationKeys;

  static const _cacheKey = 'safety_alert_release_v1';
  static const _watermarkKey = 'safety_alert_baseline_revisions_v1';
  final SupabaseClient? _givenClient;
  final SharedPreferencesAsync _preferences;
  final Map<String, String> _keys;
  Future<void>? _cacheWrite;

  /// Read inside the fetch: Supabase failing to start is a failed fetch, and a
  /// saved copy still counts.
  SupabaseClient get _client => _givenClient ?? supabase;

  Future<SafetyAlertRelease> loadCurrent() async {
    try {
      // Installed builds read these same columns, so the request stays theirs.
      final row = await _client
          .from(SupabaseContract.safetyAlertReleasesTable)
          .select('feed_path,checksum,manifest')
          .eq('is_current', true)
          .maybeSingle();
      if (row == null) {
        // Missing metadata cannot withdraw saved alerts or establish that the
        // reviewed alert set is empty. Use the same verified-cache fallback as
        // an unavailable feed; only verified feed bytes can replace that copy.
        throw const FormatException('No current safety-alert release.');
      }
      final remote = await _decodeRemote(Map<String, dynamic>.from(row));
      return await _storeCurrent(remote);
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

  // Downloads may overlap, but checking the sequence floor and committing its
  // bytes must be one operation. Otherwise a slow older download can erase a
  // newer warning after both requests passed the early replay check.
  Future<SafetyAlertRelease> _storeCurrent(_DecodedRelease remote) async {
    final previous = _cacheWrite;
    final finished = Completer<void>();
    _cacheWrite = finished.future;
    if (previous != null) await previous;
    try {
      final cached = await _loadCached();
      final held = cached?.signed?.sequence;
      if (held != null && remote.signed!.sequence < held) {
        throw const FormatException(
          'Safety-alert release is older than this copy.',
        );
      }
      final release = remote.keeping(
        cached?.rowsFor(remote.unreadableIds) ?? const [],
      );
      await _preferences.setString(
        _cacheKey,
        jsonEncode(_cachePayload(release)),
      );
      return await _withWatermark(release, isComplete: !release.hasUnsupported);
    } finally {
      if (identical(_cacheWrite, finished.future)) _cacheWrite = null;
      finished.complete();
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
    final manifest = row['manifest'];
    // The row's own fields are unsigned, and only older builds still need them.
    final signed = await _verifiedStatement(
      manifest is Map ? manifest['signed_feed'] : null,
    );
    final cached = await _loadCached();
    final held = cached?.signed?.sequence;
    if (held != null && signed.sequence < held) {
      throw const FormatException(
        'Safety-alert release is older than this copy.',
      );
    }
    Future<_DecodedRelease> read(String path, String checksum) async =>
        _decodeBytes(
          await _client.storage
              .from(SupabaseContract.storageBucket)
              .download(path),
          checksum,
          signed: signed,
        );

    // `feed_path` stays readable by every installed build, so event types an
    // older reader would reject live in a superset the manifest names.
    final extended = signed.extended;
    final path = signed.basePath;
    final checksum = signed.baseChecksum;
    if (extended == null) return read(path, checksum);
    try {
      final extendedPath = (extended as Map)['path'];
      final extendedChecksum = extended['checksum'];
      if (extendedPath is! String || extendedChecksum is! String) {
        throw const FormatException('Extended feed location is malformed.');
      }
      // This checksum names the immutable current superset. Reusing its verified
      // bytes avoids degrading a usable saved release on a transient download
      // failure. A new checksum must still be fetched and checked normally, and
      // so must a copy no signature vouches for.
      if (cached?.signed != null && cached?.checksum == extendedChecksum) {
        return cached!.signedBy(signed);
      }
      return await read(extendedPath, extendedChecksum);
    } on Object {
      // Bans and recalls must still arrive. Rules this device already holds
      // stay until a verified fetch can say otherwise.
      return (await read(path, checksum)).missingExtended(
        cached?.alerts
                .where((alert) => alert.interaction != null)
                .map((alert) => alert.alertId) ??
            const [],
      );
    }
  }

  /// Throws unless [block] is a statement about this feed, signed by a key this
  /// build holds. Everything a release can change is read from that signed text.
  Future<_SignedFeed> _verifiedStatement(Object? block) async {
    if (block is! Map ||
        block['statement'] is! String ||
        block['signature'] is! String) {
      throw const FormatException('Safety-alert release is not signed.');
    }
    final statement = block['statement'] as String;
    final signature = block['signature'] as String;
    final keyId = await verifySignedText(
      text: statement,
      signature: signature,
      keys: _keys,
    );
    final decoded = jsonDecode(statement);
    if (decoded is! Map ||
        decoded['purpose'] != 'safety_alert_feed' ||
        decoded['format'] != 1 ||
        decoded['key_id'] != keyId) {
      throw const FormatException('This is not a safety-alert statement.');
    }
    final sequence = decoded['release_sequence'];
    final base = decoded['base_feed'];
    final path = base is Map ? base['path'] : null;
    final checksum = base is Map ? base['checksum'] : null;
    if (sequence is! int ||
        sequence <= 0 ||
        path is! String ||
        checksum is! String ||
        !RegExp(r'^sha256:[0-9a-f]{64}$').hasMatch(checksum)) {
      throw const FormatException(
        'Safety-alert release metadata is malformed.',
      );
    }
    return _SignedFeed(
      statement: statement,
      signature: signature,
      sequence: sequence,
      basePath: path,
      baseChecksum: checksum,
      extended: decoded['extended_feed'],
    );
  }

  _DecodedRelease _decodeBytes(
    Uint8List bytes,
    String expectedChecksum, {
    _SignedFeed? signed,
  }) {
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
      signed: signed,
    );
  }

  /// The saved signature, re-checked so that removing an exposed key takes the
  /// trust of what it signed with it. Null when nothing vouches for this copy,
  /// which includes every copy saved by a build from before signatures.
  Future<_SignedFeed?> _savedSignature(Object? block, String checksum) async {
    try {
      final signed = await _verifiedStatement(block);
      return signed.names(checksum) ? signed : null;
    } on Object {
      return null;
    }
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
      final bytes = _decodeBytes(
        base64Decode(decoded['feed'] as String),
        decoded['checksum'] as String,
      );
      final signed = await _savedSignature(
        decoded['signed_feed'],
        bytes.checksum,
      );
      // Alerts only ever add a signal, so an unvouched copy stays on screen. It
      // just can't give an all-clear.
      final release = signed == null
          ? bytes.unverified()
          : bytes.signedBy(signed);
      final kept = decoded['kept'];
      if (kept == null) {
        return decoded['extended_missing'] == true
            ? release.missingExtended(const [])
            : release;
      }
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
    if (release.signed case final signed?)
      'signed_feed': {
        'statement': signed.statement,
        'signature': signed.signature,
      },
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
        neverVerified: release.hasUnsupported,
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
        neverVerified: release.hasUnsupported,
      );
    }
    return SafetyAlertRelease(
      alerts: release.alerts,
      baselineRevisions: baseline,
      isComplete: isComplete,
      neverVerified: release.hasUnsupported,
    );
  }
}

/// A release's signed statement, verified. Written by the pipeline's
/// scripts/sync_safety_alerts.py::build_statement.
final class _SignedFeed {
  const _SignedFeed({
    required this.statement,
    required this.signature,
    required this.sequence,
    required this.basePath,
    required this.baseChecksum,
    required this.extended,
  });

  final String statement;
  final String signature;

  /// Monotonic. A lower one than this phone has verified is a replay.
  final int sequence;
  final String basePath;
  final String baseChecksum;

  /// The superset's location, or null when the release names none. Read inside
  /// the extended-feed fallback, so a damaged entry only costs the superset.
  final Object? extended;

  bool names(String checksum) =>
      checksum == baseChecksum ||
      (extended is Map && (extended as Map)['checksum'] == checksum);
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
    this.signed,
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

  /// What vouches for these bytes. Null for a saved copy nothing vouches for.
  final _SignedFeed? signed;

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
    signed: signed,
  );

  /// These same bytes, now named by [statement], which may carry a newer sequence.
  _DecodedRelease signedBy(_SignedFeed statement) => _DecodedRelease(
    alerts: alerts,
    rows: rows,
    unreadableIds: unreadableIds,
    hasUnsupported: hasUnsupported,
    checksum: checksum,
    feedBytes: feedBytes,
    keptRows: keptRows,
    extendedMissing: extendedMissing,
    signed: statement,
  );

  /// Nothing vouches for this copy, so it can't count as a complete check.
  _DecodedRelease unverified() => _DecodedRelease(
    alerts: alerts,
    rows: rows,
    unreadableIds: unreadableIds,
    hasUnsupported: true,
    checksum: checksum,
    feedBytes: feedBytes,
    keptRows: keptRows,
    extendedMissing: extendedMissing,
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
      signed: signed,
    );
  }
}
