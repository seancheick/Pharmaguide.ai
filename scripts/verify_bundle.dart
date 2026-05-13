/// Bundle / Supabase storage alignment verifier (ADR-0001 P4).
///
/// Independent second-line defense against the 2026-05-12 failure mode.
/// The pipeline-side gates (P1) prevent destructive cleanup from running
/// when bundled-on-main and dist disagree. P4 lives in the Flutter repo
/// and verifies — from the consumer's perspective — that the bundle as
/// currently committed is consistent with what's in Supabase storage.
///
/// What it does
/// ============
///   1. Reads ``assets/db/export_manifest.json`` → captures ``db_version``
///      and ``checksum_sha256``.
///   2. SHA-256s the bundled catalog DB → asserts it matches the
///      committed manifest checksum. Catches local corruption / LFS
///      pointer issues before any network work.
///   3. Selects ``sample-size`` (default 20) random products from
///      ``products_core``. Seeded by ``db_version`` so two runs on the
///      same bundle produce the SAME sample (HR-9 idempotency).
///   4. For each sampled product, fetches its detail blob from
///      ``{SUPABASE_URL}/storage/v1/object/pharmaguide/shared/details/sha256/{shard}/{hash}.json``
///      using the anon key.
///   5. Asserts each response is HTTP 200, parseable JSON, and has the
///      expected top-level keys (``dsld_id``, ``ingredients``, ``warnings``).
///   6. Exits 0 on all-pass; exits non-zero with a structured failure
///      summary on any failure.
///
/// Acceptance criteria (P4)
/// ========================
///   - Replaying the 2026-05-12 incident: against a stale bundle whose
///     blob hashes are no longer in storage, the script must FAIL with
///     404 reasons in the failure list.
///   - Against an aligned bundle, the script must PASS.
///   - Two consecutive runs against the same inputs must select the
///     SAME sample (deterministic seed).
///   - Sample size of 20 is a small enough N to run in seconds and
///     large enough to catch systematic breakage with high probability.
///
/// Usage
/// =====
///   dart run scripts/verify_bundle.dart \\
///       [--manifest assets/db/export_manifest.json] \\
///       [--db assets/db/pharmaguide_core.db] \\
///       [--supabase-url $SUPABASE_URL] \\
///       [--anon-key $SUPABASE_ANON_KEY] \\
///       [--sample-size 20]
///
/// Or via Makefile:
///   make verify-bundle
///
/// SUPABASE_URL + SUPABASE_ANON_KEY default to the env vars (loaded
/// from .env via the Makefile target).

// Anonymous `library;` declaration anchors the file-level doc comment
// above so it isn't flagged as dangling. The script is a standalone
// executable; this is the cheapest analyzer-clean way to keep the doc
// on top.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:args/args.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:sqlite3/sqlite3.dart';

const _bucket = 'pharmaguide';
const _blobPrefix = 'shared/details/sha256';
const _requiredBlobKeys = <String>['dsld_id', 'ingredients', 'warnings'];

// ---------------------------------------------------------------------------
// Result types — public for tests + main entry
// ---------------------------------------------------------------------------

class BlobFailure {
  final String dsldId;
  final String blobHash;
  final String reason;

  const BlobFailure({
    required this.dsldId,
    required this.blobHash,
    required this.reason,
  });

  @override
  String toString() =>
      'dsld=$dsldId hash=${blobHash.substring(0, 16)}... — $reason';
}

class VerifyBundleResult {
  /// Overall pass/fail. True iff checksum matched AND every sampled blob
  /// fetched + parsed + had the expected top-level keys.
  final bool passed;

  /// db_version from the manifest (always present even on failure).
  final String dbVersion;

  /// Actual SHA-256 of the bundled DB file. May differ from the
  /// manifest's expected checksum on failure.
  final String dbChecksum;

  /// Number of products sampled (0 when checksum failed before sampling).
  final int sampleSize;

  /// Hashes selected by the deterministic sampler. Stable across two
  /// identical runs (used for idempotency assertions).
  final List<String> sampledHashes;

  /// Per-blob failures. Empty when all sampled blobs passed.
  final List<BlobFailure> failures;

  /// Non-null when the bundled DB checksum did not match the manifest.
  /// In that case the run short-circuits before sampling.
  final String? checksumError;

  const VerifyBundleResult({
    required this.passed,
    required this.dbVersion,
    required this.dbChecksum,
    required this.sampleSize,
    required this.sampledHashes,
    required this.failures,
    required this.checksumError,
  });

  String summary() {
    final buf = StringBuffer();
    if (passed) {
      buf.writeln('verify-bundle: PASS');
      buf.writeln('  db_version:  $dbVersion');
      buf.writeln('  db_checksum: $dbChecksum');
      buf.writeln(
        '  sampled:     $sampleSize blob(s) — all 200 OK + valid JSON',
      );
    } else {
      buf.writeln('verify-bundle: FAIL');
      buf.writeln('  db_version:  $dbVersion');
      buf.writeln('  db_checksum: $dbChecksum');
      if (checksumError != null) {
        buf.writeln('  checksum:    $checksumError');
      }
      if (failures.isNotEmpty) {
        buf.writeln('  blob fetch failures (${failures.length}/$sampleSize):');
        for (final f in failures) {
          buf.writeln('    - $f');
        }
      }
    }
    return buf.toString();
  }
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Run the verifier end-to-end and return a structured result.
///
/// [httpClient] is injectable so tests can mock the HTTP layer without
/// touching the network. Production callers leave it null and the
/// function constructs + closes its own client.
Future<VerifyBundleResult> verifyBundle({
  required String manifestPath,
  required String dbPath,
  required String supabaseUrl,
  required String anonKey,
  int sampleSize = 20,
  http.Client? httpClient,
}) async {
  // Step 1: read manifest ----------------------------------------------------
  final manifestRaw = File(manifestPath).readAsStringSync();
  final manifest = jsonDecode(manifestRaw) as Map<String, dynamic>;
  final dbVersion = (manifest['db_version'] as String?) ?? '';
  final expectedChecksum = (manifest['checksum_sha256'] as String?) ?? '';

  if (dbVersion.isEmpty) {
    return VerifyBundleResult(
      passed: false,
      dbVersion: '',
      dbChecksum: '',
      sampleSize: 0,
      sampledHashes: const [],
      failures: const [],
      checksumError: 'Manifest at $manifestPath is missing "db_version".',
    );
  }
  if (expectedChecksum.isEmpty) {
    return VerifyBundleResult(
      passed: false,
      dbVersion: dbVersion,
      dbChecksum: '',
      sampleSize: 0,
      sampledHashes: const [],
      failures: const [],
      checksumError: 'Manifest at $manifestPath is missing "checksum_sha256".',
    );
  }

  // Step 2: verify DB checksum ----------------------------------------------
  final dbBytes = File(dbPath).readAsBytesSync();
  final actualChecksum = sha256.convert(dbBytes).toString();
  if (actualChecksum != expectedChecksum) {
    return VerifyBundleResult(
      passed: false,
      dbVersion: dbVersion,
      dbChecksum: actualChecksum,
      sampleSize: 0,
      sampledHashes: const [],
      failures: const [],
      checksumError:
          'Bundled DB SHA-256 ($actualChecksum) does not match committed '
          'manifest checksum ($expectedChecksum). Possible causes: '
          'Git LFS pointer (run `git lfs pull`), local edit, or stale checkout.',
    );
  }

  // Step 3: sample products -------------------------------------------------
  final db = sqlite3.open(dbPath, mode: OpenMode.readOnly);
  late final List<_Product> sampled;
  try {
    final allRows = db.select(
      'SELECT dsld_id, detail_blob_sha256 FROM products_core '
      "WHERE detail_blob_sha256 IS NOT NULL AND detail_blob_sha256 != '' "
      'ORDER BY dsld_id',
    );
    if (allRows.isEmpty) {
      return VerifyBundleResult(
        passed: false,
        dbVersion: dbVersion,
        dbChecksum: actualChecksum,
        sampleSize: 0,
        sampledHashes: const [],
        failures: const [],
        checksumError:
            'Catalog has no products with non-null detail_blob_sha256. '
            'Cannot verify storage alignment.',
      );
    }

    final products = <_Product>[];
    for (final row in allRows) {
      products.add(
        _Product(
          dsldId: row['dsld_id'] as String,
          hash: row['detail_blob_sha256'] as String,
        ),
      );
    }

    // Deterministic sampler — seed = SHA-256(db_version) truncated to int32.
    // Two runs on the same bundle pick the SAME sample. (HR-9.)
    final rng = Random(_seedFromString(dbVersion));
    final indices = List<int>.generate(products.length, (i) => i);
    indices.shuffle(rng);
    final n = sampleSize > products.length ? products.length : sampleSize;
    sampled = [for (final i in indices.take(n)) products[i]];
  } finally {
    db.dispose();
  }

  // Step 4–5: fetch + validate each sampled blob ----------------------------
  final ownsClient = httpClient == null;
  final client = httpClient ?? http.Client();
  final failures = <BlobFailure>[];
  final sampledHashes = <String>[];

  try {
    for (final p in sampled) {
      sampledHashes.add(p.hash);

      final shard = p.hash.substring(0, 2);
      final url = Uri.parse(
        '$supabaseUrl/storage/v1/object/$_bucket/$_blobPrefix/$shard/${p.hash}.json',
      );

      http.Response response;
      try {
        response = await client.get(
          url,
          headers: {'Authorization': 'Bearer $anonKey', 'apikey': anonKey},
        );
      } on Object catch (e) {
        failures.add(
          BlobFailure(
            dsldId: p.dsldId,
            blobHash: p.hash,
            reason: 'Network error fetching blob: $e',
          ),
        );
        continue;
      }

      if (response.statusCode != 200) {
        failures.add(
          BlobFailure(
            dsldId: p.dsldId,
            blobHash: p.hash,
            reason:
                'HTTP ${response.statusCode}: blob not present in storage. '
                'Bundle references a hash that does not exist in Supabase '
                '(this is the 2026-05-12 failure mode).',
          ),
        );
        continue;
      }

      dynamic parsed;
      try {
        parsed = jsonDecode(response.body);
      } on FormatException catch (e) {
        failures.add(
          BlobFailure(
            dsldId: p.dsldId,
            blobHash: p.hash,
            reason: 'Blob is not valid JSON: $e',
          ),
        );
        continue;
      }

      if (parsed is! Map) {
        failures.add(
          BlobFailure(
            dsldId: p.dsldId,
            blobHash: p.hash,
            reason: 'Blob top-level is ${parsed.runtimeType}, expected Map.',
          ),
        );
        continue;
      }

      String? missing;
      for (final key in _requiredBlobKeys) {
        if (!parsed.containsKey(key)) {
          missing = key;
          break;
        }
      }
      if (missing != null) {
        failures.add(
          BlobFailure(
            dsldId: p.dsldId,
            blobHash: p.hash,
            reason: 'Blob missing required top-level key: $missing',
          ),
        );
        continue;
      }
    }
  } finally {
    if (ownsClient) client.close();
  }

  return VerifyBundleResult(
    passed: failures.isEmpty,
    dbVersion: dbVersion,
    dbChecksum: actualChecksum,
    sampleSize: sampled.length,
    sampledHashes: sampledHashes,
    failures: failures,
    checksumError: null,
  );
}

// ---------------------------------------------------------------------------
// Internals
// ---------------------------------------------------------------------------

class _Product {
  final String dsldId;
  final String hash;
  const _Product({required this.dsldId, required this.hash});
}

/// Map a string to a 32-bit non-negative int seed for ``Random``.
/// SHA-256 the input, take the first 4 bytes as a positive int.
int _seedFromString(String s) {
  final hash = sha256.convert(utf8.encode(s)).bytes;
  // Take first 4 bytes as a 31-bit int (signed range stays positive).
  return ((hash[0] << 23) | (hash[1] << 15) | (hash[2] << 7) | (hash[3] >> 1)) &
      0x7fffffff;
}

// ---------------------------------------------------------------------------
// CLI entry point
// ---------------------------------------------------------------------------

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption(
      'manifest',
      defaultsTo: 'assets/db/export_manifest.json',
      help: 'Path to the bundled export_manifest.json.',
    )
    ..addOption(
      'db',
      defaultsTo: 'assets/db/pharmaguide_core.db',
      help: 'Path to the bundled catalog SQLite DB.',
    )
    ..addOption(
      'supabase-url',
      help: 'Supabase project URL. Defaults to \$SUPABASE_URL.',
    )
    ..addOption(
      'anon-key',
      help: 'Supabase anon key. Defaults to \$SUPABASE_ANON_KEY.',
    )
    ..addOption(
      'sample-size',
      defaultsTo: '20',
      help: 'Number of random products to verify (default 20).',
    )
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show usage.');

  late ArgResults parsed;
  try {
    parsed = parser.parse(args);
  } on FormatException catch (e) {
    stderr.writeln('Error: ${e.message}');
    stderr.writeln(parser.usage);
    exit(2);
  }

  if (parsed['help'] as bool) {
    // CLI script: stdout is the right surface for help text.
    // ignore: avoid_print
    print(parser.usage);
    exit(0);
  }

  final supabaseUrl =
      (parsed['supabase-url'] as String?) ??
      Platform.environment['SUPABASE_URL'];
  final anonKey =
      (parsed['anon-key'] as String?) ??
      Platform.environment['SUPABASE_ANON_KEY'];

  if (supabaseUrl == null || supabaseUrl.isEmpty) {
    stderr.writeln(
      'Error: --supabase-url or SUPABASE_URL env var is required.',
    );
    exit(2);
  }
  if (anonKey == null || anonKey.isEmpty) {
    stderr.writeln(
      'Error: --anon-key or SUPABASE_ANON_KEY env var is required.',
    );
    exit(2);
  }

  int sampleSize;
  try {
    sampleSize = int.parse(parsed['sample-size'] as String);
    if (sampleSize <= 0) throw const FormatException('must be > 0');
  } on FormatException catch (e) {
    stderr.writeln('Error: --sample-size must be a positive int ($e)');
    exit(2);
  }

  final result = await verifyBundle(
    manifestPath: parsed['manifest'] as String,
    dbPath: parsed['db'] as String,
    supabaseUrl: supabaseUrl,
    anonKey: anonKey,
    sampleSize: sampleSize,
  );

  stdout.write(result.summary());
  exit(result.passed ? 0 : 1);
}
