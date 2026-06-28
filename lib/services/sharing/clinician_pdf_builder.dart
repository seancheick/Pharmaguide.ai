import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pharmaguide/core/models/stack_intelligence.dart';
import 'package:pharmaguide/core/models/timing_optimization.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/services/stack/depletion_checker.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_models.dart';
import 'package:pharmaguide/services/stack/stack_safety_report.dart';

class ClinicianPdfBuilder {
  const ClinicianPdfBuilder({this.compress = true});

  final bool compress;

  Future<Uint8List> build({
    required UserProfile? profile,
    required List<UserStacksLocalData> stack,
    required StackIntelligence intelligence,
    required StackSafetyReport safetyReport,
    required List<DepletionMatch> depletions,
    required DateTime generatedAt,
    Uint8List? logoBytes,
    Uint8List? regularFontBytes,
    Uint8List? mediumFontBytes,
  }) async {
    final doc = pw.Document(
      compress: compress,
      title: 'PharmaGuide Supplement Stack Report',
      author: 'PharmaGuide',
      creator: 'PharmaGuide',
      subject: 'Patient-generated supplement stack summary',
    );

    final logo = _decodeLogo(logoBytes);
    final theme = _Theme(
      regularFont: _decodeFont(regularFontBytes),
      mediumFont: _decodeFont(mediumFontBytes),
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.fromLTRB(40, 34, 40, 42),
        footer: (context) => _footer(context, theme),
        build: (context) => [
          _header(theme, logo, generatedAt),
          _about(theme),
          _profileSection(theme, profile),
          _stackSection(theme, 'Medications', stack, 'medication'),
          _stackSection(theme, 'Supplements', stack, 'supplement'),
          _summarySection(theme, intelligence),
          _warningsSection(theme, intelligence),
          _nutrientSection(theme, safetyReport.nutrientStatuses),
          _timingSection(theme, safetyReport.timingOptimizations),
          _depletionSection(theme, depletions),
          _limitations(theme),
        ],
      ),
    );

    return doc.save();
  }

  pw.ImageProvider? _decodeLogo(Uint8List? logoBytes) {
    if (logoBytes == null || logoBytes.isEmpty) return null;
    try {
      return pw.MemoryImage(logoBytes);
    } on Object {
      return null;
    }
  }

  pw.Font? _decodeFont(Uint8List? fontBytes) {
    if (fontBytes == null || fontBytes.isEmpty) return null;
    try {
      return pw.Font.ttf(ByteData.sublistView(fontBytes));
    } on Object {
      return null;
    }
  }

  pw.Widget _header(
    _Theme theme,
    pw.ImageProvider? logo,
    DateTime generatedAt,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 18),
      decoration: pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: theme.border)),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          if (logo != null)
            pw.Container(
              width: 38,
              height: 38,
              margin: const pw.EdgeInsets.only(right: 12),
              child: pw.Image(logo),
            ),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('PharmaGuide', style: theme.brand),
                pw.SizedBox(height: 4),
                pw.Text('Supplement Stack Report', style: theme.title),
                pw.SizedBox(height: 6),
                pw.Text(
                  'Generated ${_formatDate(generatedAt)} - For clinician review',
                  style: theme.caption,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _about(_Theme theme) {
    return _section(theme, 'About this report', [
      pw.Text(
        _clean(
          'This report summarizes supplements, medications, nutrient totals, timing guidance, and safety signals reported in the user\'s PharmaGuide stack. Generated entirely on this device; PharmaGuide does not upload or store this report on a server.',
        ),
        style: theme.body,
      ),
      pw.SizedBox(height: 6),
      pw.Text(
        'Educational summary, not medical advice. It is not an EHR medication reconciliation or a substitute for clinician judgment.',
        style: theme.body,
      ),
    ]);
  }

  pw.Widget _profileSection(_Theme theme, UserProfile? profile) {
    if (profile == null) return pw.SizedBox.shrink();
    final rows = <String>[];

    void add(String label, String? value) {
      if (value == null || value.trim().isEmpty) return;
      rows.add('$label: ${value.trim()}');
    }

    add('Age', profile.ageBracket);
    add('Sex', profile.sex);
    _addJsonList(rows, 'Conditions', profile.conditions);
    _addJsonList(rows, 'Drug classes', profile.drugClasses);
    _addJsonList(rows, 'Goals', profile.goals);
    _addJsonList(rows, 'Allergens', profile.allergens);

    if (rows.isEmpty) return pw.SizedBox.shrink();
    return _section(theme, 'Patient profile', rows.map((r) => _line(theme, r)));
  }

  pw.Widget _stackSection(
    _Theme theme,
    String title,
    List<UserStacksLocalData> stack,
    String type,
  ) {
    final items = stack.where((e) => e.type == type).toList(growable: false);
    if (items.isEmpty) return pw.SizedBox.shrink();

    return _section(
      theme,
      '$title (${items.length})',
      items.map((item) => _line(theme, _formatStackLine(item))),
    );
  }

  pw.Widget _summarySection(_Theme theme, StackIntelligence intelligence) {
    final rows = <String>[
      'Tier: ${_tierLabel(intelligence.tier)}',
      'Stack size: ${intelligence.stackSize}',
      'Interactions flagged: ${intelligence.interactionCount}',
      'Nutrient warnings: ${intelligence.nutrientWarningCount}',
      if (intelligence.qualityScore != null)
        'Stack quality score: ${intelligence.qualityScore}/100',
      if (intelligence.hasContraindicatedInteraction)
        'Contraindicated interaction detected',
      if (intelligence.hasBannedIngredient) 'Banned ingredient detected',
      if (intelligence.hasRecalledIngredient) 'Recalled ingredient detected',
    ];
    return _section(theme, 'Stack summary', rows.map((r) => _line(theme, r)));
  }

  pw.Widget _warningsSection(_Theme theme, StackIntelligence intelligence) {
    final issues = _sortedIssues(intelligence.issues);
    if (issues.isEmpty) {
      return _section(theme, 'Warnings', [
        _line(theme, 'No stack warnings in the current snapshot.'),
      ]);
    }

    return _section(
      theme,
      'Warnings',
      issues.map(
        (issue) => _severityLine(theme, issue.severity.label, issue.headline),
      ),
    );
  }

  pw.Widget _nutrientSection(_Theme theme, List<NutrientStatus> statuses) {
    if (statuses.isEmpty) return pw.SizedBox.shrink();

    final sorted = [...statuses]
      ..sort((a, b) {
        final warn = (b.shouldWarn ? 1 : 0).compareTo(a.shouldWarn ? 1 : 0);
        if (warn != 0) return warn;
        return (b.pctOfUl ?? b.pctOfRda ?? 0).compareTo(
          a.pctOfUl ?? a.pctOfRda ?? 0,
        );
      });

    return _section(
      theme,
      'Nutrient totals',
      sorted.take(10).map((status) {
        final total = status.total;
        final parts = <String>[
          '${total.displayName}: ${_formatNumber(total.totalAmount)} ${total.unit}',
          if (status.pctOfUl != null) '${_formatNumber(status.pctOfUl!)}% UL',
          if (status.pctOfRda != null)
            '${_formatNumber(status.pctOfRda!)}% RDA',
          _nutrientTierLabel(status.tier),
        ];
        return _line(theme, parts.join(' - '));
      }),
    );
  }

  pw.Widget _timingSection(
    _Theme theme,
    List<TimingOptimization> optimizations,
  ) {
    if (optimizations.isEmpty) return pw.SizedBox.shrink();

    final sorted = [...optimizations]
      ..sort((a, b) => b.displayPriority.compareTo(a.displayPriority));

    return _section(
      theme,
      'Timing recommendations',
      sorted.take(8).map((item) {
        final hours = item.separationHours == null
            ? ''
            : ' (${item.separationHours}h separation)';
        return _line(theme, '${item.advice}$hours');
      }),
    );
  }

  pw.Widget _depletionSection(_Theme theme, List<DepletionMatch> depletions) {
    if (depletions.isEmpty) return pw.SizedBox.shrink();

    return _section(
      theme,
      'Medication nutrient notes',
      depletions.take(8).map((match) {
        final headline = match.alertHeadline?.trim().isNotEmpty == true
            ? match.alertHeadline!.trim()
            : '${match.drugDisplayName} may affect ${match.nutrientName}';
        final tip = match.monitoringTipShort?.trim().isNotEmpty == true
            ? ' - ${match.monitoringTipShort!.trim()}'
            : '';
        return _line(theme, '$headline$tip');
      }),
    );
  }

  pw.Widget _limitations(_Theme theme) {
    return _section(theme, 'Limitations', [
      _line(
        theme,
        'This is patient-generated health data based on the user\'s current in-app stack.',
      ),
      _line(
        theme,
        'It may omit prescriptions, over-the-counter products, doses, labs, diagnoses, or changes not entered by the user.',
      ),
      _line(
        theme,
        'Do not use this report alone to start, stop, or change therapy.',
      ),
    ]);
  }

  pw.Widget _footer(pw.Context context, _Theme theme) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 8),
      decoration: pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: theme.border)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('PharmaGuide - generated on device', style: theme.footer),
          pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: theme.footer,
          ),
        ],
      ),
    );
  }

  pw.Widget _section(_Theme theme, String title, Iterable<pw.Widget> children) {
    final list = children.toList(growable: false);
    if (list.isEmpty) return pw.SizedBox.shrink();
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 18),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(title.toUpperCase(), style: theme.sectionTitle),
          pw.SizedBox(height: 8),
          ...list,
        ],
      ),
    );
  }

  pw.Widget _line(_Theme theme, String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 5),
      child: pw.Text(_clean(text), style: theme.body),
    );
  }

  pw.Widget _severityLine(_Theme theme, String label, String text) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 6),
      padding: const pw.EdgeInsets.all(9),
      decoration: pw.BoxDecoration(
        color: theme.warningBg,
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(color: theme.warningBorder),
      ),
      child: pw.RichText(
        text: pw.TextSpan(
          children: [
            pw.TextSpan(text: '${_clean(label)}: ', style: theme.bodyBold),
            pw.TextSpan(text: _clean(text), style: theme.body),
          ],
        ),
      ),
    );
  }

  void _addJsonList(List<String> rows, String label, String? raw) {
    final list = _decodeJsonStringList(raw);
    if (list.isNotEmpty) rows.add('$label: ${list.join(", ")}');
  }

  List<String> _decodeJsonStringList(String? raw) {
    if (raw == null || raw.isEmpty) return const <String>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .map((e) => e.toString().trim())
            .where((s) => s.isNotEmpty)
            .toList(growable: false);
      }
    } on Object {
      return const <String>[];
    }
    return const <String>[];
  }

  List<StackIssue> _sortedIssues(List<StackIssue> issues) {
    final sorted = issues.indexed
        .map((entry) => _RankedIssue(entry.$2, entry.$1))
        .toList(growable: false);
    sorted.sort((a, b) {
      final severity = b.issue.severity.weight.compareTo(
        a.issue.severity.weight,
      );
      if (severity != 0) return severity;
      return a.ordinal.compareTo(b.ordinal);
    });
    return sorted.map((entry) => entry.issue).toList(growable: false);
  }

  String _formatStackLine(UserStacksLocalData item) {
    final dosage = (item.dosage ?? '').trim();
    final frequency = (item.frequency ?? '').trim();
    if (dosage.isEmpty && frequency.isEmpty) return item.name;
    if (dosage.isNotEmpty && frequency.isEmpty) return '${item.name} - $dosage';
    if (dosage.isEmpty && frequency.isNotEmpty) {
      return '${item.name} - $frequency';
    }
    return '${item.name} - $dosage, $frequency';
  }

  String _tierLabel(StackTier tier) => switch (tier) {
    StackTier.optimized => 'Optimized',
    StackTier.solid => 'Solid',
    StackTier.decent => 'Decent',
    StackTier.concerning => 'Concerning',
    StackTier.unsafe => 'Unsafe',
    StackTier.incomplete => 'More info needed',
  };

  String _nutrientTierLabel(NutrientTier tier) => switch (tier) {
    NutrientTier.noRda => 'No RDA data',
    NutrientTier.underFifty => 'Below 50% RDA',
    NutrientTier.adequate => 'Adequate',
    NutrientTier.aboveAdequateNoUl => 'Above target (no upper limit)',
    NutrientTier.abundant => 'Above RDA',
    NutrientTier.aboveTypical => 'Above typical',
    NutrientTier.approachingUl => 'Approaching upper limit',
    NutrientTier.exceedsUl => 'Exceeds upper limit',
  };

  String _formatDate(DateTime d) {
    final month = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$month-$day';
  }

  String _formatNumber(num value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(1);
  }

  String _clean(String value) {
    return value
        .replaceAll('\u2013', '-')
        .replaceAll('\u2014', '-')
        .replaceAll('\u2022', '-')
        .replaceAll('\u00b7', '-')
        .replaceAll('\u2018', "'")
        .replaceAll('\u2019', "'")
        .replaceAll('\u201c', '"')
        .replaceAll('\u201d', '"')
        .replaceAll(RegExp(r'[\u{10000}-\u{10FFFF}]', unicode: true), '');
  }
}

class _RankedIssue {
  const _RankedIssue(this.issue, this.ordinal);

  final StackIssue issue;
  final int ordinal;
}

class _Theme {
  _Theme({this.regularFont, this.mediumFont});

  final pw.Font? regularFont;
  final pw.Font? mediumFont;

  final accent = PdfColor.fromHex('#183B3F');
  final ink = PdfColor.fromHex('#181A1B');
  final muted = PdfColor.fromHex('#5C5F61');
  final subtle = PdfColor.fromHex('#8A8D90');
  final border = PdfColor.fromHex('#E5E2DB');
  final warningBg = PdfColor.fromHex('#F6F0E2');
  final warningBorder = PdfColor.fromHex('#AD7A24');

  late final brand = pw.TextStyle(
    font: mediumFont,
    color: accent,
    fontSize: 12,
  );

  late final title = pw.TextStyle(font: mediumFont, color: ink, fontSize: 22);

  late final sectionTitle = pw.TextStyle(
    font: mediumFont,
    color: accent,
    fontSize: 10,
    letterSpacing: 1,
  );

  late final body = pw.TextStyle(
    font: regularFont,
    color: ink,
    fontSize: 10.5,
    lineSpacing: 2,
  );
  late final bodyBold = pw.TextStyle(
    font: mediumFont,
    color: ink,
    fontSize: 10.5,
  );
  late final caption = pw.TextStyle(
    font: regularFont,
    color: muted,
    fontSize: 9.5,
  );
  late final footer = pw.TextStyle(
    font: regularFont,
    color: subtle,
    fontSize: 8,
  );
}
