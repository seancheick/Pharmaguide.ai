import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:printing/printing.dart';
import 'package:pharmaguide/core/scoring/catalog_product_semantics.dart';
import 'package:share_plus/share_plus.dart';

/// Function shape used to invoke the system share sheet. Production
/// callers leave it `null` and the service routes through
/// [SharePlus.instance.share]. Unit tests pass a fake to assert the
/// payload without standing up a platform channel.
typedef ShareInvocation = Future<void> Function(String text, {String? subject});
typedef PdfShareInvocation =
    Future<bool> Function(List<int> bytes, {required String filename});

/// Mints the public link for a shared product, or returns `null` when no link
/// could be created. Injected so tests can exercise both outcomes without a
/// network.
typedef ShareLinkMinter =
    Future<String?> Function(Map<String, Object?> payload);

/// Base URL of the website that hosts `/api/share` and `/s/{code}`.
///
/// Overridable via `--dart-define=PHARMAGUIDE_WEB_URL=…` so a staging build
/// mints staging links instead of writing test rows into production.
const String _webBaseUrl = String.fromEnvironment(
  'PHARMAGUIDE_WEB_URL',
  defaultValue: 'https://pharmaguide.io',
);

/// The share sheet cannot open until the text is final, so this timeout is
/// felt directly as a delay between the tap and the sheet. Three seconds is
/// the ceiling for that to still read as responsive on a weak mobile
/// connection; past it we give up and share the text alone.
const Duration _mintTimeout = Duration(seconds: 3);

/// Allowlisted supplement fields that are safe for the non-clinical share
/// flow. Medication, profile, warning, score, and condition data have no place
/// in this model, which prevents accidental disclosure by construction.
class SupplementShareItem {
  const SupplementShareItem({required this.name, this.brand});

  final String name;
  final String? brand;
}

/// Handles sharing products and stack summaries.
class ShareService {
  /// Optional override for the share-sheet invocation. Wired in by
  /// tests so they can capture the text/subject the service hands to
  /// `share_plus` without invoking the real platform channel.
  /// Production constructs `ShareService()` and the default
  /// [SharePlus] path runs.
  final ShareInvocation? _shareOverride;
  final PdfShareInvocation? _pdfShareOverride;
  final ShareLinkMinter? _linkMinterOverride;

  ShareService({
    this._shareOverride,
    this._pdfShareOverride,
    this._linkMinterOverride,
  });

  Future<void> _share(String text, {String? subject}) {
    final override = _shareOverride;
    if (override != null) return override(text, subject: subject);
    return SharePlus.instance.share(ShareParams(text: text, subject: subject));
  }

  /// POST the allowlisted payload to the website and return the public URL.
  ///
  /// Every failure path returns `null` rather than throwing. Sharing is a
  /// gesture already in flight: if the link cannot be minted, the right
  /// outcome is the text-only share that shipped before links existed, not an
  /// error dialog over a share sheet the user is waiting on.
  Future<String?> _mintShareLink(Map<String, Object?> payload) async {
    final override = _linkMinterOverride;
    if (override != null) return override(payload);

    try {
      final response = await http
          .post(
            Uri.parse('$_webBaseUrl/api/share'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(_mintTimeout);
      if (response.statusCode != 201) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return null;
      final url = decoded['url'];
      return url is String && url.isNotEmpty ? url : null;
    } on Exception {
      return null;
    }
  }

  /// Returns `true` only when the platform confirms that the PDF was shared.
  /// A dismissed system share sheet is a normal cancellation, not an error.
  Future<bool> shareClinicianReportPdf(List<int> bytes) async {
    const filename = 'pharmaguide-clinician-report.pdf';
    final override = _pdfShareOverride;
    if (override != null) {
      return override(bytes, filename: filename);
    }
    return Printing.sharePdf(
      bytes: Uint8List.fromList(bytes),
      filename: filename,
    );
  }

  /// Share a product-quality summary. Profile results are deliberately absent:
  /// the recipient has a different health context and must run their own check.
  ///
  /// When [dsldId] is supplied the service also mints a public link and appends
  /// it, so the recipient gets a page instead of a wall of text. Callers that
  /// omit it — or a mint that fails — fall back to the text-only share.
  ///
  /// A public link is minted only when both [dsldId] and [catalogVersion] are
  /// present. The website resolves the product name, score, disposition, and
  /// trust tags from that immutable pipeline release; none of those trusted
  /// fields are accepted from this client.
  Future<void> shareProduct({
    required String productName,
    String? brandName,
    double? qualityScore,
    String? qualityTier,
    String? scoreConfidence,
    List<String> qualityHighlights = const [],
    bool isCatalogBlocked = false,
    String? dsldId,
    String? catalogVersion,
  }) async {
    final cleanName = productName.trim().isEmpty
        ? 'Supplement'
        : productName.trim();
    final cleanBrand = brandName?.trim() ?? '';
    final title = cleanBrand.isEmpty ? cleanName : '$cleanName — $cleanBrand';
    final tier = qualityTier?.trim() ?? '';
    final scoreLine = qualityScore == null || isCatalogBlocked
        ? null
        : 'PharmaGuide quality: ${qualityScore.round()}/100'
              '${tier.isEmpty ? '' : ' · $tier'}';
    final confidenceLabel = qualityScore == null || isCatalogBlocked
        ? null
        : catalogScoreConfidenceLabel(scoreConfidence);
    final confidenceLine = confidenceLabel == null
        ? null
        : 'Score confidence: $confidenceLabel';
    final cleanHighlights = isCatalogBlocked
        ? const <String>[]
        : qualityHighlights
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty)
              .take(3)
              .toList(growable: false);
    final highlights = cleanHighlights.map((value) => '- $value').join('\n');

    // The link is minted before the sheet opens because the text must be final
    // by then. A null result is the normal offline/slow-network path.
    final cleanDsldId = dsldId?.trim() ?? '';
    final cleanCatalogVersion = catalogVersion?.trim() ?? '';
    final shareUrl = cleanDsldId.isEmpty || cleanCatalogVersion.isEmpty
        ? null
        : await _mintShareLink({
            'dsldId': cleanDsldId,
            'catalogVersion': cleanCatalogVersion,
          });

    final text = [
      title,
      if (isCatalogBlocked) 'Blocked from quality scoring in PharmaGuide',
      if (scoreLine != null) scoreLine,
      if (confidenceLine != null) confidenceLine,
      if (highlights.isNotEmpty) 'Highlights:\n$highlights',
      'Quality reflects the product itself. Personal fit depends on your profile.',
      if (shareUrl != null) shareUrl,
      'Reviewed in PharmaGuide',
    ].join('\n\n');

    await _share(text, subject: title);
  }

  /// Share supplements only. The narrow [SupplementShareItem] contract keeps
  /// medications and health-profile inferences out of this general-purpose
  /// share path.
  Future<void> shareSupplementList(List<SupplementShareItem> items) async {
    final lines = items
        .map((item) {
          final name = item.name.trim().isEmpty
              ? 'Supplement'
              : item.name.trim();
          final brand = item.brand?.trim() ?? '';
          return '• ${brand.isEmpty ? name : '$name — $brand'}';
        })
        .join('\n');

    final text = [
      'My supplements',
      lines.isEmpty ? 'No supplements saved.' : lines,
      'Shared from PharmaGuide',
    ].join('\n\n');

    await _share(text, subject: 'My supplements');
  }
}
