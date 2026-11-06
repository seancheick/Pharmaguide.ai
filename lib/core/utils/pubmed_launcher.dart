// Shared PubMed deep link — single launcher so every evidence surface
// applies the same numeric-PMID guard before handing the value to an
// external URL (no path injection from malformed blob data).

import 'package:url_launcher/url_launcher.dart';

/// Opens `https://pubmed.ncbi.nlm.nih.gov/<pmid>` externally.
///
/// No-op when [pmid] is not a pure digit string — PMIDs come from blob
/// JSON and must never be interpolated into a URL unvalidated.
Future<void> launchPubmed(String pmid) async {
  if (!RegExp(r'^\d+$').hasMatch(pmid)) return;
  final uri = Uri.parse('https://pubmed.ncbi.nlm.nih.gov/$pmid');
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Only absolute HTTPS source links may leave the app. Citation data is untrusted.
Uri? evidenceSourceUri({String? url, String? doi}) {
  final value = url?.trim() ?? '';
  if (value.isNotEmpty) {
    final uri = Uri.tryParse(value);
    if (uri != null &&
        uri.scheme == 'https' &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty &&
        !RegExp(r'\s').hasMatch(value)) {
      return uri;
    }
    return null;
  }
  final identifier = doi?.trim() ?? '';
  if (!RegExp(r'^10\.\d{4,9}/\S+$').hasMatch(identifier)) return null;
  return Uri.https('doi.org', '/$identifier');
}

/// Optional DOI deduplication identity; a valid HTTPS source need not have one.
String? evidenceSourceDoi(Uri? uri) {
  if (uri == null || uri.host != 'doi.org' || uri.path.length <= 1) {
    return null;
  }
  try {
    final identifier = Uri.decodeComponent(uri.path.substring(1));
    return RegExp(r'^10\.\d{4,9}/\S+$').hasMatch(identifier)
        ? identifier.toLowerCase()
        : null;
  } on FormatException {
    return null;
  }
}

Future<void> launchEvidenceSource(Uri uri) async {
  final safe = evidenceSourceUri(url: uri.toString());
  if (safe == null) return;
  await launchUrl(safe, mode: LaunchMode.externalApplication);
}
