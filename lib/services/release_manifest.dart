// The signed description of one catalog and rules release (ADR-012).
//
// `export_manifest.signed_release` holds the exact JSON text the release key
// signed, and everything that affects activation is read from those verified
// bytes. The pipeline owner is scripts/release_manifest.py.

import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:pharmaguide/core/utils/app_version.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/data/supabase/supabase_contract.dart';
import 'package:pharmaguide/data/supabase/sync_service.dart';

/// Verification keys by key ID, as hex. A build with no keys ignores signed
/// fields and takes catalog-only updates, so it can never activate remote
/// rules. Empty until the pipeline signs production releases and A9 is
/// complete; rotation is in the pipeline's docs/RELEASE_SIGNING_RUNBOOK.md.
const Map<String, String> _kProductionReleaseKeys = {};

const String _kTestKeyId = String.fromEnvironment(
  'PHARMAGUIDE_RELEASE_TEST_KEY_ID',
);
const String _kTestKey = String.fromEnvironment('PHARMAGUIDE_RELEASE_TEST_KEY');

/// Test builds add a key through a dart-define, which release mode ignores.
Map<String, String> get kReleaseVerificationKeys => {
  ..._kProductionReleaseKeys,
  if (!kReleaseMode && _kTestKeyId.isNotEmpty && _kTestKey.isNotEmpty)
    _kTestKeyId: _kTestKey,
};

/// Verification keys for the safety-alert feed, by key ID, as hex. Separate from
/// the release keys: a key there puts catalog updates into signed-only mode and is
/// held back until A9 finishes, and the feed must not wait on that or change it.
/// With no key here every feed is unverified, so this build shows no alert from the
/// feed and no all-clear. scripts/require_alert_feed_key.sh keeps that out of store
/// builds; steps are in the pipeline's docs/RELEASE_SIGNING_RUNBOOK.md.
const Map<String, String> _kProductionAlertFeedKeys = {
  'alert-feed-2026-11':
      '86931cbd3b7ccff1fdd2564a582964d96fe1ce7417f9dd57fea4e5af6cad46fa',
  'alert-feed-standby':
      'd0184fbe88be20df2753fb6acaffa0b41f18722dd5e97d1053645b8e26e9bb9e',
};

/// Test builds add the same dart-define key, which release mode ignores.
Map<String, String> get kAlertFeedVerificationKeys => {
  ..._kProductionAlertFeedKeys,
  if (!kReleaseMode && _kTestKeyId.isNotEmpty && _kTestKey.isNotEmpty)
    _kTestKeyId: _kTestKey,
};

/// The highest `format` this build reads.
const int kSupportedReleaseFormat = 1;

/// Refuses activation: the phone keeps the pair it has.
class ReleaseManifestException implements Exception {
  const ReleaseManifestException(this.message);

  final String message;

  @override
  String toString() => 'ReleaseManifestException: $message';
}

class ReleaseArtifact {
  const ReleaseArtifact({
    required this.version,
    required this.path,
    required this.sha256,
    required this.schemaVersion,
    required this.minAppVersion,
    this.compressed,
  });

  final String version;
  final String path;
  final String sha256;
  final String schemaVersion;
  final String minAppVersion;

  /// Only a catalog has one, and only from releases published since compression.
  final CompressedCatalog? compressed;

  static ReleaseArtifact _parse(Object? raw, String name) {
    if (raw is! Map) throw ReleaseManifestException('$name is not an object');
    String field(String key) {
      final value = raw[key];
      if (value is! String || value.trim().isEmpty) {
        throw ReleaseManifestException('$name.$key is missing');
      }
      return value;
    }

    final sha256 = field('sha256').toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256)) {
      throw ReleaseManifestException('$name.sha256 is not a SHA-256 hash');
    }
    return ReleaseArtifact(
      version: field('version'),
      path: field('path'),
      sha256: sha256,
      schemaVersion: field('schema_version'),
      minAppVersion: field('min_app_version'),
      compressed: name == 'catalog'
          ? CompressedCatalog.tryParse(
              raw['compressed'],
              expectedPath: SupabaseContract.compressedCoreDbPath(
                field('version'),
              ),
            )
          : null,
    );
  }
}

class ReleaseManifest {
  const ReleaseManifest({
    required this.sequence,
    required this.catalog,
    required this.rules,
    required this.minRulesVersion,
    required this.blockedCatalog,
    required this.blockedRules,
  });

  /// Monotonic, and separate from the catalog and rules content versions.
  final int sequence;
  final ReleaseArtifact catalog;

  /// Null for a catalog-only release, which keeps the phone's rules.
  final ReleaseArtifact? rules;
  final String minRulesVersion;
  final Set<String> blockedCatalog;
  final Set<String> blockedRules;

  /// Verifies [signature] (`<key id>:<base64>`) over the exact [signedRelease]
  /// text, then parses that text. Throws [ReleaseManifestException] on anything
  /// it can't vouch for.
  static Future<ReleaseManifest> verify({
    required String signedRelease,
    required String signature,
    required Map<String, String> keys,
  }) async {
    final keyId = await verifySignedText(
      text: signedRelease,
      signature: signature,
      keys: keys,
    );

    final manifest = _parse(signedRelease);
    if (manifest.$2 != keyId) {
      throw const ReleaseManifestException('Release signed by the wrong key');
    }
    return manifest.$1;
  }

  static (ReleaseManifest, String?) _parse(String signedRelease) {
    final Object? decoded;
    try {
      decoded = jsonDecode(signedRelease);
    } on FormatException {
      throw const ReleaseManifestException('Signed release is not JSON');
    }
    if (decoded is! Map) {
      throw const ReleaseManifestException('Signed release is not an object');
    }
    final format = decoded['format'];
    if (format is! int || format < 1 || format > kSupportedReleaseFormat) {
      throw ReleaseManifestException('Unsupported release format $format');
    }
    final sequence = decoded['release_sequence'];
    if (sequence is! int || sequence <= 0) {
      throw const ReleaseManifestException('Invalid release sequence');
    }
    final minRules = decoded['min_rules_version'];
    if (minRules is! String || minRules.trim().isEmpty) {
      throw const ReleaseManifestException('min_rules_version is missing');
    }
    final blocked = decoded['blocked_versions'];
    if (blocked is! Map) {
      throw const ReleaseManifestException('blocked_versions is missing');
    }
    Set<String> list(String key) {
      final value = blocked[key];
      if (value is! List || value.any((item) => item is! String)) {
        throw ReleaseManifestException('blocked_versions.$key is invalid');
      }
      return value.cast<String>().toSet();
    }

    final rules = decoded['rules'];
    final keyId = decoded['key_id'];
    return (
      ReleaseManifest(
        sequence: sequence,
        catalog: ReleaseArtifact._parse(decoded['catalog'], 'catalog'),
        rules: rules == null ? null : ReleaseArtifact._parse(rules, 'rules'),
        minRulesVersion: minRules,
        blockedCatalog: list('catalog'),
        blockedRules: list('rules'),
      ),
      keyId is String ? keyId : null,
    );
  }

  /// The pair rule. [currentRulesVersion] is the phone's rules, which stay when
  /// this is a catalog-only release. Throws when this build can't read a file
  /// or the pair doesn't belong together. An unparseable version fails closed.
  void requireCompatible({
    required String? currentRulesVersion,
    String appVersion = kAppVersion,
  }) {
    SyncService.enforceCatalogVersionGate(
      minAppVersion: catalog.minAppVersion,
      schemaVersion: catalog.schemaVersion,
      appVersion: appVersion,
    );
    final named = rules;
    if (named != null) {
      enforceInteractionDatabaseVersionGate(
        minAppVersion: named.minAppVersion,
        schemaVersion: named.schemaVersion,
        appVersion: appVersion,
      );
    }
    final rulesVersion = named?.version ?? currentRulesVersion;
    if (rulesVersion == null) {
      throw const ReleaseManifestException('This phone has no rules to keep');
    }
    final comparison = compareSemver(rulesVersion, minRulesVersion);
    if (comparison == null || comparison < 0) {
      throw ReleaseManifestException(
        'Catalog ${catalog.version} needs rules >= $minRulesVersion, '
        'pair has $rulesVersion',
      );
    }
    if (blockedCatalog.contains(catalog.version) ||
        blockedRules.contains(rulesVersion)) {
      throw const ReleaseManifestException('The pair names a blocked version');
    }
  }
}

/// Verifies [signature] (`<key id>:<base64>`) over the exact [text] and returns
/// the key ID. Says nothing about what the text means: each caller parses its own
/// document and checks the key ID it names.
Future<String> verifySignedText({
  required String text,
  required String signature,
  required Map<String, String> keys,
}) async {
  final separator = signature.indexOf(':');
  if (separator <= 0) {
    throw const ReleaseManifestException('Malformed release signature');
  }
  final keyId = signature.substring(0, separator);
  final keyHex = keys[keyId];
  if (keyHex == null) {
    throw ReleaseManifestException('Unknown release key $keyId');
  }

  final List<int> signatureBytes;
  try {
    signatureBytes = base64.decode(signature.substring(separator + 1));
  } on FormatException {
    throw const ReleaseManifestException('Malformed release signature');
  }
  if (signatureBytes.length != 64) {
    throw const ReleaseManifestException('Malformed release signature');
  }

  final bool valid;
  try {
    valid = await Ed25519().verify(
      utf8.encode(text),
      signature: Signature(
        signatureBytes,
        publicKey: SimplePublicKey(
          _hexBytes(keyHex),
          type: KeyPairType.ed25519,
        ),
      ),
    );
  } on Object catch (e) {
    throw ReleaseManifestException('Release signature check failed: $e');
  }
  if (!valid) {
    throw const ReleaseManifestException('Invalid release signature');
  }
  return keyId;
}

List<int> _hexBytes(String hex) {
  if (hex.length.isOdd) throw const FormatException('Odd hex length');
  return [
    for (var i = 0; i < hex.length; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ];
}
