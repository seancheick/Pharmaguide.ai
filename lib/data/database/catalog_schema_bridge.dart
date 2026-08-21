// Pure compatibility readers for the schema-2.3 -> 2.4 -> prepared-3.0
// catalog bridge. New app code consumes canonical names; legacy names are
// read only here (or once during SQLite open) and disappear with schema 3.

String? catalogQualityScoreConfidence(Map<String, dynamic> core) {
  final raw = core['quality_score_confidence'] ?? core['v4_confidence'];
  final normalized = raw?.toString().trim().toLowerCase();
  return const {'high', 'moderate', 'low'}.contains(normalized)
      ? normalized
      : null;
}

Map<String, dynamic>? catalogProductStatusDetail(
  Map<String, dynamic> detailBlob,
) {
  final raw =
      detailBlob['product_status_detail'] ?? detailBlob['product_status'];
  if (raw is! Map) return null;
  return Map<String, dynamic>.from(raw);
}

bool catalogHasCanonicalProductStatus({
  required String? coreStatus,
  required Map<String, dynamic> detailBlob,
}) {
  if (coreStatus?.trim().isNotEmpty == true) return true;
  return catalogProductStatusDetail(detailBlob) != null;
}

String? catalogSynergyClusterId(Map<String, dynamic> cluster) {
  final raw = cluster['cluster_id'] ?? cluster['id'];
  final value = raw?.toString().trim();
  return value == null || value.isEmpty ? null : value;
}
