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
