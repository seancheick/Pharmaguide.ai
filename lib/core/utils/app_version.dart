// App version + catalog compatibility constants.
//
// [kAppVersion] MUST be kept in sync with the `version:` field in
// pubspec.yaml (semver part only, no build number). It gates OTA catalog
// activation: a downloaded catalog whose embedded `min_app_version`
// exceeds this value is refused (see SyncService._validateStagedDatabase).
//
// Why a constant instead of package_info_plus: the version gate runs
// during catalog staging (possibly before the widget tree is up), and
// package_info_plus is not a direct dependency of this app. A compile-time
// constant is deterministic, testable, and cannot fail at runtime.

/// Current app semver. Keep in sync with pubspec.yaml `version:`.
const String kAppVersion = '1.0.0';

/// Highest catalog export-manifest `schema_version` MAJOR this app build
/// can read. Mirrors APP_SUPPORTED_SCHEMAS in
/// scripts/import_catalog_artifact.sh (currently up to 2.1.0).
const int kMaxSupportedCatalogSchemaMajor = 2;

/// Compares two semver-ish strings (`major.minor.patch`, tolerant of
/// missing components and `-pre`/`+build` suffixes).
///
/// Returns a negative number when `a < b`, 0 when equal, positive when
/// `a > b`, or **null when either side is unparseable** — callers decide
/// whether to fail open or closed on null.
int? compareSemver(String a, String b) {
  List<int>? parse(String v) {
    final core = v.trim().split('+').first.split('-').first;
    if (core.isEmpty) return null;
    final nums = <int>[];
    for (final part in core.split('.')) {
      final n = int.tryParse(part);
      if (n == null || n < 0) return null;
      nums.add(n);
    }
    while (nums.length < 3) {
      nums.add(0);
    }
    return nums;
  }

  final pa = parse(a);
  final pb = parse(b);
  if (pa == null || pb == null) return null;
  for (var i = 0; i < 3; i++) {
    if (pa[i] != pb[i]) return pa[i].compareTo(pb[i]);
  }
  return 0;
}
