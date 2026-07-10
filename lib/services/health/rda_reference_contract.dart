/// RDA/UL reference-stamp validation shared by product-detail surfaces.
///
/// Product blobs are built from pipeline reference data, while stack totals
/// use the bundled app copy. A product-detail UL verdict is trustworthy only
/// when both identify the same version and semantic fingerprint.
library;

bool hasCurrentRdaReference({
  required Map<String, dynamic>? appReferenceData,
  required Map<String, dynamic>? productRdaUlData,
}) {
  final appStamp = _appReferenceStamp(appReferenceData);
  final productStamp = _productReferenceStamp(productRdaUlData);
  return appStamp != null && productStamp != null && appStamp == productStamp;
}

({String version, String fingerprint})? _appReferenceStamp(
  Map<String, dynamic>? data,
) {
  final metadata = data?['_metadata'];
  if (metadata is! Map) return null;
  final contract = metadata['reference_data_contract'];
  if (contract is! Map) return null;
  final version = contract['reference_version']?.toString().trim();
  final fingerprint = contract['semantic_fingerprint']?.toString().trim();
  if (version == null ||
      version.isEmpty ||
      fingerprint == null ||
      fingerprint.isEmpty) {
    return null;
  }
  return (version: version, fingerprint: fingerprint);
}

({String version, String fingerprint})? _productReferenceStamp(
  Map<String, dynamic>? data,
) {
  final version = data?['reference_data_version']?.toString().trim();
  final fingerprint = data?['reference_data_fingerprint']?.toString().trim();
  if (version == null ||
      version.isEmpty ||
      fingerprint == null ||
      fingerprint.isEmpty) {
    return null;
  }
  return (version: version, fingerprint: fingerprint);
}
