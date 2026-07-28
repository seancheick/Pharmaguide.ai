// RxNorm API service — thin wrapper around the public NLM RxNorm REST
// endpoints used by the medication-entry flow (M4 §8.4).
//
// Endpoints we hit:
//
//   - /REST/approximateTerm.json   (autocomplete suggestions)
//   - /REST/rxcui.json             (resolve drug name → RXCUI)
//   - /REST/rxcui/{rxcui}/properties.json (drug name + tty + synonyms)
//   - /REST/rxclass/class/byRxcui.json (drug → drug class memberships)
//
// Constraints from the spec:
//
//   - No auth, no API key.
//   - **20 req/sec** client-side cap. We enforce this with a sliding
//     1-second window of recent request timestamps.
//   - **50-entry in-memory LRU cache** keyed on the RPC name + args.
//     Search volume is low (typing speed is human-bound) so we can
//     dedupe without persisting anything.
//   - **Offline fallback.** When the network is unreachable, we don't
//     try to retry — we hand the caller a list of `class:*` ids
//     enumerated from the bundled interaction DB so the user can still
//     pick a drug-class entry without network access. Per-RXCUI lookups
//     simply return null when offline; the caller should treat that as
//     "couldn't resolve, fall back to class-only".
//
// The HTTP transport is injected (`RxNormHttpGet`) so unit tests can
// supply canned JSON without touching the real network. The default
// transport uses `dart:io HttpClient` (no extra package dependency).

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:pharmaguide/data/database/interaction_database.dart';
import 'package:pharmaguide/services/medications/medication_class_bridge.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Result of an `approximateTerm` autocomplete query.
@immutable
class RxNormSuggestion {
  const RxNormSuggestion({
    required this.name,
    required this.rxcui,
    required this.score,
  });

  final String name;
  final String rxcui;
  final int score;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RxNormSuggestion &&
          other.name == name &&
          other.rxcui == rxcui &&
          other.score == score);

  @override
  int get hashCode => Object.hash(name, rxcui, score);
}

/// Subset of the `/rxcui/{rxcui}/properties.json` payload we surface to
/// the medication-entry flow. We only need a stable display name; the
/// full payload is dropped to keep memory bounded.
@immutable
class RxNormDrugInfo {
  const RxNormDrugInfo({
    required this.rxcui,
    required this.name,
    this.synonym,
    this.tty,
  });

  final String rxcui;
  final String name;
  final String? synonym;
  final String? tty;
}

/// HTTP transport contract — `Future<String> Function(Uri)`. Tests
/// inject fakes; production uses [defaultRxNormHttpGet] which talks to
/// the real RxNorm REST endpoints over `dart:io`.
typedef RxNormHttpGet = Future<String> Function(Uri url);

/// Default transport. Times out at 5s — RxNorm is normally <500ms, but
/// users on slow networks shouldn't be left hanging on the entry
/// screen. The medication-entry flow treats a timeout as "fall back to
/// the class picker".
Future<String> defaultRxNormHttpGet(Uri url) async {
  final client = HttpClient();
  int? statusCode;
  final endpoint = _rxNormEndpointLabel(url);
  final span = _startRxNormSpan(endpoint);
  SpanStatus spanStatus = const SpanStatus.ok();
  try {
    client.connectionTimeout = const Duration(seconds: 5);
    final req = await client.getUrl(url);
    req.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final res = await req.close().timeout(const Duration(seconds: 5));
    statusCode = res.statusCode;
    spanStatus = SpanStatus.fromHttpStatusCode(res.statusCode);
    span?.setData('http.response.status_code', res.statusCode);
    if (res.statusCode != 200) {
      throw HttpException('RxNorm GET $endpoint returned ${res.statusCode}');
    }
    final bodyBytes = await _readResponseBytes(res);
    span?.setData('http.response.body.size', bodyBytes.length);
    return utf8.decode(bodyBytes);
  } on Object catch (error) {
    spanStatus = _rxNormSpanStatusForError(error, fallback: spanStatus);
    span?.throwable = error;
    rethrow;
  } finally {
    await _finishRxNormSpan(span, spanStatus);
    client.close(force: false);
    // Manual Sentry breadcrumb — rxnorm uses dart:io HttpClient, not
    // package:http, so SentryHttpClient can't wrap it. Recording here
    // gives the same per-request signal we get from the wrapped clients.
    //
    // The raw RxNorm URL can include typed medication names or RXCUIs.
    // Send only the coarse endpoint class; no query/path identifiers.
    unawaited(
      Sentry.addBreadcrumb(
        Breadcrumb.http(
          url: Uri.https(url.host, '/REST/$endpoint'),
          method: 'GET',
          statusCode: statusCode,
          level: (statusCode == null || statusCode >= 400)
              ? SentryLevel.warning
              : SentryLevel.info,
        ),
      ),
    );
  }
}

ISentrySpan? _startRxNormSpan(String endpoint) {
  try {
    final parent = Sentry.getSpan();
    final span =
        parent?.startChild(
          'http.client',
          description: 'GET RxNorm $endpoint',
        ) ??
        Sentry.startTransaction(
          'GET RxNorm $endpoint',
          'http.client',
          bindToScope: false,
        );
    span
      ..setTag('pg.surface', 'rxnorm')
      ..setData('server.address', 'rxnav.nlm.nih.gov')
      ..setData('http.request.method', 'GET')
      ..setData('rxnorm.endpoint', endpoint);
    return span;
  } on Object {
    return null;
  }
}

Future<void> _finishRxNormSpan(ISentrySpan? span, SpanStatus status) async {
  if (span == null || span.finished) return;
  await span.finish(status: status);
}

SpanStatus _rxNormSpanStatusForError(Object error, {SpanStatus? fallback}) {
  if (error is TimeoutException) return const SpanStatus.deadlineExceeded();
  if (error is SocketException) return const SpanStatus.unavailable();
  if (error is HttpException) {
    return fallback == const SpanStatus.ok()
        ? const SpanStatus.unknownError()
        : fallback ?? const SpanStatus.unknownError();
  }
  return fallback == const SpanStatus.ok()
      ? const SpanStatus.unknownError()
      : fallback ?? const SpanStatus.unknownError();
}

String _rxNormEndpointLabel(Uri url) {
  final path = url.path;
  if (path.endsWith('/approximateTerm.json')) return 'approximate_term';
  if (path.endsWith('/rxcui.json')) return 'rxcui_by_name';
  if (path.endsWith('/properties.json')) return 'properties';
  if (path.endsWith('/related.json')) return 'related';
  if (path.endsWith('/rxclass/class/byRxcui.json')) return 'class_by_rxcui';
  return 'unknown';
}

Future<Uint8List> _readResponseBytes(HttpClientResponse response) async {
  final builder = BytesBuilder(copy: false);
  await for (final chunk in response) {
    builder.add(chunk);
  }
  return builder.takeBytes();
}

class RxNormApiService {
  RxNormApiService({
    RxNormHttpGet? httpGet,
    this._offlineDb,
    this._cacheSize = 50,
    this._requestsPerSecond = 20,
    this._baseUrl = 'https://rxnav.nlm.nih.gov',
  }) : _httpGet = httpGet ?? defaultRxNormHttpGet;

  final RxNormHttpGet _httpGet;
  final InteractionDatabase? _offlineDb;
  final int _cacheSize;
  final int _requestsPerSecond;
  final String _baseUrl;

  // Insertion-ordered cache. We evict from the front (oldest insert)
  // when we cross [_cacheSize], and re-insert on hit so recently used
  // entries bubble back to the end (true LRU semantics).
  final LinkedHashMap<String, Object?> _cache =
      LinkedHashMap<String, Object?>();

  // Sliding window of recent request timestamps. We enforce
  // `_requestsPerSecond` by sleeping until the oldest timestamp falls
  // out of the 1-second window.
  final Queue<DateTime> _recent = Queue<DateTime>();

  /// Autocomplete suggestions for a partial drug name. Returns at most
  /// 10 ranked results, deduplicated by rxcui. Returns an empty list
  /// when offline or when the query is shorter than 2 chars (RxNorm
  /// rejects single-char queries).
  Future<List<RxNormSuggestion>> search(String query) async {
    final q = query.trim();
    if (q.length < 2) return const <RxNormSuggestion>[];

    final cacheKey = 'search:${q.toLowerCase()}';
    final cached = _readCache<List<RxNormSuggestion>>(cacheKey);
    if (cached != null) return cached;

    final url = Uri.parse(
      '$_baseUrl/REST/approximateTerm.json?term=${Uri.encodeQueryComponent(q)}&maxEntries=10',
    );

    final raw = await _safeGet(url);
    if (raw == null) {
      _writeCache(cacheKey, const <RxNormSuggestion>[]);
      return const <RxNormSuggestion>[];
    }

    final suggestions = _parseSearch(raw);
    _writeCache(cacheKey, suggestions);
    return suggestions;
  }

  /// Resolve a drug name to its primary RXCUI. Returns null if RxNorm
  /// has no exact match (the caller should fall back to `search` and
  /// let the user pick).
  Future<String?> getRxcui(String drugName) async {
    final q = drugName.trim();
    if (q.isEmpty) return null;

    final cacheKey = 'rxcui:${q.toLowerCase()}';
    final cached = _readCache<String?>(cacheKey);
    if (cached != null) return cached;

    final url = Uri.parse(
      '$_baseUrl/REST/rxcui.json?name=${Uri.encodeQueryComponent(q)}',
    );

    final raw = await _safeGet(url);
    if (raw == null) {
      _writeCache(cacheKey, null);
      return null;
    }

    String? rxcui;
    try {
      final body = jsonDecode(raw);
      if (body is Map) {
        final group = body['idGroup'];
        if (group is Map) {
          final ids = group['rxnormId'];
          if (ids is List && ids.isNotEmpty) {
            rxcui = ids.first.toString();
          }
        }
      }
    } on FormatException {
      rxcui = null;
    }

    _writeCache(cacheKey, rxcui);
    return rxcui;
  }

  /// Drug class ids the given RXCUI belongs to. Returned ids are
  /// normalized to the `class:*` form the bundled interaction DB uses
  /// (lowercase, snake-case) so they can be persisted directly into
  /// `user_stacks_local.drug_classes` and used by
  /// [StackInteractionChecker.checkMedicationInteractions] without
  /// further translation.
  ///
  /// Returns an empty list when offline (the caller should still allow
  /// the user to add the medication; the interaction check will simply
  /// be a no-op until they're back online).
  Future<List<String>> getClasses(String rxcui) async {
    final r = rxcui.trim();
    if (r.isEmpty) return const <String>[];

    final cacheKey = 'classes:$r';
    final cached = _readCache<List<String>>(cacheKey);
    if (cached != null) return cached;

    // Fetch from multiple class sources in parallel for broader matching.
    // ATC = therapeutic classification (existing).
    // MEDRT = VA MED-RT (MOA, EPC) — catches "all SSRIs", "all ACE inhibitors"
    //   at the mechanism-of-action level so a single curated rule covers
    //   every drug in the class.
    final atcUrl = Uri.parse(
      '$_baseUrl/REST/rxclass/class/byRxcui.json?rxcui=$r&relaSource=ATC',
    );
    final medrtUrl = Uri.parse('$_baseUrl/REST/rxclass/class/byRxcui.json')
        .replace(
          queryParameters: {
            'rxcui': r,
            'relaSource': 'MEDRT',
            'relas': 'has_moa has_pe',
          },
        );

    final atcFuture = _safeGet(atcUrl);
    final medrtFuture = _safeGet(medrtUrl);

    final atcRaw = await atcFuture;
    final medrtRaw = await medrtFuture;

    final classes = <String>{};
    if (atcRaw != null) classes.addAll(_parseClasses(atcRaw));
    if (medrtRaw != null) {
      classes.addAll(
        _parseClasses(medrtRaw, allowedRelations: const {'has_moa', 'has_pe'}),
      );
    }

    final db = _offlineDb;
    if (db != null) {
      final resolution = await MedicationClassBridge(db: db).resolve(
        selectedRxcui: r,
        runtimeClassIds: classes.toList(growable: false),
      );
      classes
        ..clear()
        ..addAll(resolution.mergedInteractionClassIds);
    }

    final result = classes.toList(growable: false)..sort();
    _writeCache(cacheKey, result);
    return result;
  }

  /// Hydrate a single rxcui to its display name + TTY. Returns null on
  /// network failure or unknown rxcui.
  Future<RxNormDrugInfo?> getDrugInfo(String rxcui) async {
    final r = rxcui.trim();
    if (r.isEmpty) return null;

    final cacheKey = 'props:$r';
    final cached = _readCache<RxNormDrugInfo?>(cacheKey);
    if (cached != null) return cached;

    final url = Uri.parse('$_baseUrl/REST/rxcui/$r/properties.json');
    final raw = await _safeGet(url);
    if (raw == null) {
      _writeCache(cacheKey, null);
      return null;
    }

    RxNormDrugInfo? info;
    try {
      final body = jsonDecode(raw);
      if (body is Map) {
        final props = body['properties'];
        if (props is Map) {
          final name = props['name'];
          if (name is String && name.isNotEmpty) {
            info = RxNormDrugInfo(
              rxcui: r,
              name: name,
              synonym: props['synonym'] is String
                  ? props['synonym'] as String
                  : null,
              tty: props['tty'] is String ? props['tty'] as String : null,
            );
          }
        }
      }
    } on FormatException {
      info = null;
    }

    _writeCache(cacheKey, info);
    return info;
  }

  /// Resolve a brand or dose-specific RXCUI to its base generic ingredient
  /// RXCUI (TTY=IN). This is critical for interaction matching because
  /// curated interactions are keyed on generic RXCUIs (e.g., levothyroxine
  /// = 10582), but users often pick brand names (Synthroid = 224920).
  ///
  /// Returns the generic IN-level RXCUI, or null if:
  ///   - The input is already an IN (no resolution needed — caller should
  ///     check `getDrugInfo(rxcui).tty == 'IN'` first)
  ///   - Network is unreachable
  ///   - RxNorm doesn't have a related IN concept
  ///
  /// Also resolves combination drugs to their individual ingredient RXCUIs
  /// when the related concepts include multiple IN entries.
  ///
  /// API: `GET /REST/rxcui/{rxcui}/related.json?tty=IN`
  Future<List<String>> resolveGenericRxcuis(String rxcui) async {
    final r = rxcui.trim();
    if (r.isEmpty) return const <String>[];

    final cacheKey = 'generic:$r';
    final cached = _readCache<List<String>>(cacheKey);
    if (cached != null) return cached;

    final url = Uri.parse('$_baseUrl/REST/rxcui/$r/related.json?tty=IN');
    final raw = await _safeGet(url);
    if (raw == null) {
      _writeCache(cacheKey, const <String>[]);
      return const <String>[];
    }

    final generics = <String>[];
    try {
      final body = jsonDecode(raw);
      if (body is Map) {
        final groups = body['relatedGroup']?['conceptGroup'];
        if (groups is List) {
          for (final group in groups) {
            if (group is! Map) continue;
            final tty = group['tty'];
            if (tty != 'IN') continue;
            final props = group['conceptProperties'];
            if (props is! List) continue;
            for (final prop in props) {
              if (prop is Map) {
                final cui = prop['rxcui'];
                if (cui is String &&
                    cui.isNotEmpty &&
                    !generics.contains(cui)) {
                  generics.add(cui);
                }
              }
            }
          }
        }
      }
    } on FormatException {
      // Malformed JSON — return empty.
    }

    _writeCache(cacheKey, generics);
    return generics;
  }

  /// Convenience: resolve a single brand RXCUI to its primary generic.
  /// Returns null when offline or no generic exists.
  Future<String?> resolveGenericRxcui(String rxcui) async {
    final generics = await resolveGenericRxcuis(rxcui);
    return generics.isNotEmpty ? generics.first : null;
  }

  /// Offline fallback: list every drug class id the bundled interaction
  /// DB knows about, sorted alphabetically. The medication-entry screen
  /// shows this as a picker when the network is down or RxNorm has no
  /// exact match for the user's typed drug name.
  ///
  /// Returns an empty list if no [InteractionDatabase] was passed at
  /// construction time (e.g. in unit tests that don't need the
  /// fallback).
  Future<List<String>> offlineDrugClasses() async {
    final db = _offlineDb;
    if (db == null) return const <String>[];
    final rows = await db.select(db.drugClassMap).get();
    final ids = rows.map((r) => r.classId).toList()..sort();
    return ids;
  }

  // ---------------------------------------------------------------------------
  // parsing helpers
  // ---------------------------------------------------------------------------

  static List<RxNormSuggestion> _parseSearch(String raw) {
    try {
      final body = jsonDecode(raw);
      if (body is! Map) return const <RxNormSuggestion>[];
      final group = body['approximateGroup'];
      if (group is! Map) return const <RxNormSuggestion>[];
      final candidates = group['candidate'];
      if (candidates is! List) return const <RxNormSuggestion>[];

      final out = <RxNormSuggestion>[];
      final seenRxcui = <String>{};
      for (final c in candidates) {
        if (c is! Map) continue;
        final rxcui = c['rxcui']?.toString();
        if (rxcui == null || rxcui.isEmpty) continue;
        if (!seenRxcui.add(rxcui)) continue;
        final name = c['name']?.toString() ?? '';
        if (name.isEmpty) continue;
        final scoreStr = c['score']?.toString() ?? '0';
        final score = int.tryParse(scoreStr) ?? 0;
        out.add(RxNormSuggestion(name: name, rxcui: rxcui, score: score));
      }
      out.sort((a, b) => b.score.compareTo(a.score));
      return out;
    } on FormatException {
      return const <RxNormSuggestion>[];
    }
  }

  /// Parse `/rxclass/class/byRxcui.json` and translate the human class
  /// names into the `class:*` form the interaction DB uses.
  ///
  /// RxClass returns names like `"ACE Inhibitors"`; the M2 pipeline
  /// stores them as `class:ace_inhibitors`. We do the slug here so the
  /// id round-trips with the bundle without the caller having to know
  /// the convention.
  static List<String> _parseClasses(
    String raw, {
    Set<String>? allowedRelations,
  }) {
    try {
      final body = jsonDecode(raw);
      if (body is! Map) return const <String>[];
      final group = body['rxclassDrugInfoList'];
      if (group is! Map) return const <String>[];
      final infos = group['rxclassDrugInfo'];
      if (infos is! List) return const <String>[];

      final out = <String>[];
      final seen = <String>{};
      for (final info in infos) {
        if (info is! Map) continue;
        final relation = info['rela']?.toString().toLowerCase();
        if (allowedRelations != null && !allowedRelations.contains(relation)) {
          continue;
        }
        final concept = info['rxclassMinConceptItem'];
        if (concept is! Map) continue;
        final name = concept['className']?.toString();
        if (name == null || name.isEmpty) continue;
        final slug = _slugifyClassName(name);
        if (seen.add(slug)) out.add(slug);
      }
      return out;
    } on FormatException {
      return const <String>[];
    }
  }

  /// `"ACE Inhibitors"` → `"class:ace_inhibitors"`.
  /// `"5-HT3 Receptor Antagonists"` → `"class:5_ht3_receptor_antagonists"`.
  static String _slugifyClassName(String name) {
    final lower = name.toLowerCase();
    final slug = lower
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return 'class:$slug';
  }

  // ---------------------------------------------------------------------------
  // cache + rate limit
  // ---------------------------------------------------------------------------

  T? _readCache<T>(String key) {
    if (!_cache.containsKey(key)) return null;
    // Re-insert to bubble to the back (most-recently-used).
    final value = _cache.remove(key);
    _cache[key] = value;
    return value as T?;
  }

  void _writeCache(String key, Object? value) {
    if (_cache.containsKey(key)) _cache.remove(key);
    _cache[key] = value;
    while (_cache.length > _cacheSize) {
      _cache.remove(_cache.keys.first);
    }
  }

  /// Sliding 1-second window rate limiter. Sleeps until the oldest
  /// recorded request falls out of the window if we'd exceed
  /// [_requestsPerSecond] in the next call.
  Future<void> _throttle() async {
    while (true) {
      final now = DateTime.now();
      while (_recent.isNotEmpty &&
          now.difference(_recent.first) > const Duration(seconds: 1)) {
        _recent.removeFirst();
      }
      if (_recent.length < _requestsPerSecond) {
        _recent.addLast(now);
        return;
      }
      final sleepFor =
          const Duration(seconds: 1) -
          now.difference(_recent.first) +
          const Duration(milliseconds: 5);
      if (sleepFor > Duration.zero) {
        await Future<void>.delayed(sleepFor);
      }
    }
  }

  /// Throttle, then GET — but never throw upstream. Network/timeout
  /// errors return null and the caller treats that as "no result";
  /// the medication-entry flow uses [offlineDrugClasses] for the
  /// fallback path.
  Future<String?> _safeGet(Uri url) async {
    await _throttle();
    try {
      return await _httpGet(url);
    } on Object {
      return null;
    }
  }

  /// Test/debug accessor for the LRU snapshot. Returns a copy.
  @visibleForTesting
  Map<String, Object?> debugCacheSnapshot() => Map.unmodifiable(_cache);
}
