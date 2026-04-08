import 'dart:convert';
import 'package:share_plus/share_plus.dart';

/// Handles sharing products and stack summaries.
class ShareService {
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
        final list = jsonDecode(shareHighlights) as List;
        highlights = list.map((e) => '- $e').join('\n');
      } catch (_) {
        highlights = '';
      }
    }

    final text = [
      title,
      if (desc.isNotEmpty) '\n$desc',
      if (highlights.isNotEmpty) '\nKey highlights:\n$highlights',
      '\nAnalyzed by PharmaGuide',
    ].join('\n');

    await Share.share(text, subject: title);
  }

  /// Share a stack summary.
  Future<void> shareStackSummary({
    required int safetyScore,
    required String riskLabel,
    required int productCount,
    required int issueCount,
    required int synergyCount,
  }) async {
    final text = '''
My Supplement Stack — PharmaGuide

Stack Safety Score: $safetyScore/100 ($riskLabel)
Products: $productCount
Issues: $issueCount
Synergies: $synergyCount

Analyzed by PharmaGuide
''';

    await Share.share(text, subject: 'My Supplement Stack');
  }
}
