/// Strict comparator for pipeline catalog build versions.
///
/// Catalog versions are timestamp strings emitted by the pipeline in the
/// shape `yyyy.MM.dd.HHmmss`, for example `2026.05.17.204805`. OTA update
/// decisions must be monotonic: only a strictly newer remote may replace the
/// local catalog. Unknown shapes fail closed.
class CatalogVersion {
  const CatalogVersion._(this.parts);

  final List<int> parts;

  static CatalogVersion? parse(String? value) {
    final raw = value?.trim();
    if (raw == null || raw.isEmpty) return null;
    final match = RegExp(
      r'^(\d{4})\.(\d{2})\.(\d{2})\.(\d{6})$',
    ).firstMatch(raw);
    if (match == null) return null;

    final parsed = <int>[];
    for (var i = 1; i <= 4; i++) {
      final part = int.tryParse(match.group(i)!);
      if (part == null) return null;
      parsed.add(part);
    }
    return CatalogVersion._(parsed);
  }

  int compareTo(CatalogVersion other) {
    for (var i = 0; i < parts.length; i++) {
      final delta = parts[i].compareTo(other.parts[i]);
      if (delta != 0) return delta;
    }
    return 0;
  }

  static bool isRemoteNewer({
    required String? remoteVersion,
    required String? localVersion,
  }) {
    final remote = parse(remoteVersion);
    if (remote == null) return false;

    if (localVersion == null || localVersion.trim().isEmpty) {
      return true;
    }

    final local = parse(localVersion);
    if (local == null) return false;

    return remote.compareTo(local) > 0;
  }
}
