import 'dart:convert';
import 'dart:typed_data';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

/// Function shape used to invoke the system share sheet. Production
/// callers leave it `null` and the service routes through
/// [SharePlus.instance.share]. Unit tests pass a fake to assert the
/// payload without standing up a platform channel.
typedef ShareInvocation = Future<void> Function(String text, {String? subject});
typedef PdfShareInvocation =
    Future<void> Function(List<int> bytes, {required String filename});

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

  /// Share the markdown summary built by `ClinicianReportBuilder`.
  ///
  /// Spec: INITIATIVE_STACK_INTELLIGENCE.md, Track C, C2.
  ///
  /// The method is intentionally a thin pass-through — no analytics
  /// ping, no payload reshaping, no fallbacks. The builder owns the
  /// content; this method only routes it into the system share sheet
  /// with a stable subject line.
  Future<void> shareClinicianReport(String markdown) async {
    await _share(markdown, subject: 'My Supplement Stack — Clinician Summary');
  }

  Future<void> shareClinicianReportPdf(List<int> bytes) async {
    const filename = 'pharmaguide-clinician-report.pdf';
    final override = _pdfShareOverride;
    if (override != null) {
      return override(bytes, filename: filename);
    }
    await Printing.sharePdf(
      bytes: Uint8List.fromList(bytes),
      filename: filename,
    );
  }

  /// Share a product using pre-computed fields from products_core.
  Future<void> shareProduct({
    required String? shareTitle,
    required String? shareDescription,
    required String? shareHighlights,
  }) async {
    final title = shareTitle ?? 'Check out this supplement';
    final desc = shareDescription ?? '';

    String highlights = '';
    if (shareHighlights != null && shareHighlights.isNotEmpty) {
      try {
        final decoded = jsonDecode(shareHighlights);
        if (decoded is List) {
          highlights = decoded.map((e) => '- $e').join('\n');
        }
      } on FormatException {
        highlights = '';
      }
    }

    final text = [
      title,
      if (desc.isNotEmpty) '\n$desc',
      if (highlights.isNotEmpty) '\nKey highlights:\n$highlights',
      '\nAnalyzed by PharmaGuide',
    ].join('\n');

    await _share(text, subject: title);
  }

  /// Share a stack summary.
  Future<void> shareStackSummary({
    required int safetyScore,
    required String riskLabel,
    required int productCount,
    required int issueCount,
    required int synergyCount,
  }) async {
    final text =
        '''
My Supplement Stack — PharmaGuide

Stack Safety Score: $safetyScore/100 ($riskLabel)
Products: $productCount
Issues: $issueCount
Synergies: $synergyCount

Analyzed by PharmaGuide
''';

    await SharePlus.instance.share(
      ShareParams(text: text, subject: 'My Supplement Stack'),
    );
  }
}
