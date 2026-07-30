import 'dart:typed_data';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

/// Function shape used to invoke the system share sheet. Production
/// callers leave it `null` and the service routes through
/// [SharePlus.instance.share]. Unit tests pass a fake to assert the
/// payload without standing up a platform channel.
typedef ShareInvocation = Future<void> Function(String text, {String? subject});
typedef PdfShareInvocation =
    Future<bool> Function(List<int> bytes, {required String filename});

/// Allowlisted supplement fields that are safe for the non-clinical share
/// flow. Medication, profile, warning, score, and condition data have no place
/// in this model, which prevents accidental disclosure by construction.
class SupplementShareItem {
  const SupplementShareItem({
    required this.name,
    this.brand,
    this.dosage,
    this.frequency,
  });

  final String name;
  final String? brand;
  final String? dosage;
  final String? frequency;
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

  ShareService({this._shareOverride, this._pdfShareOverride});

  Future<void> _share(String text, {String? subject}) {
    final override = _shareOverride;
    if (override != null) return override(text, subject: subject);
    return SharePlus.instance.share(ShareParams(text: text, subject: subject));
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
  Future<void> shareProduct({
    required String productName,
    String? brandName,
    double? qualityScore,
    String? qualityTier,
    List<String> qualityHighlights = const [],
  }) async {
    final cleanName = productName.trim().isEmpty
        ? 'Supplement'
        : productName.trim();
    final cleanBrand = brandName?.trim() ?? '';
    final title = cleanBrand.isEmpty ? cleanName : '$cleanName — $cleanBrand';
    final tier = qualityTier?.trim() ?? '';
    final scoreLine = qualityScore == null
        ? null
        : 'PharmaGuide quality: ${qualityScore.round()}/100'
              '${tier.isEmpty ? '' : ' · $tier'}';
    final highlights = qualityHighlights
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .take(3)
        .map((value) => '- $value')
        .join('\n');

    final text = [
      title,
      if (scoreLine != null) scoreLine,
      if (highlights.isNotEmpty) 'Highlights:\n$highlights',
      'Quality reflects the product itself. Personal fit depends on your profile.',
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
          final dosage = item.dosage?.trim() ?? '';
          final frequency = item.frequency?.trim() ?? '';
          final schedule = [dosage, frequency].where((part) => part.isNotEmpty);
          return [
            '• ${brand.isEmpty ? name : '$name — $brand'}',
            if (schedule.isNotEmpty) '  ${schedule.join(' · ')}',
          ].join('\n');
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
