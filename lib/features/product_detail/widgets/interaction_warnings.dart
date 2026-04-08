import 'package:flutter/material.dart';
import 'package:pharmaguide/core/constants/app_colors.dart';
import 'package:pharmaguide/core/constants/severity.dart';

/// A single interaction warning entry parsed from the detail blob.
class InteractionWarning {
  final Severity severity;
  final EvidenceLevel evidenceLevel;
  final String title;
  final String mechanism;
  final String management;
  final List<String> sourceUrls;

  const InteractionWarning({
    required this.severity,
    required this.evidenceLevel,
    required this.title,
    required this.mechanism,
    required this.management,
    this.sourceUrls = const [],
  });

  /// Parse from raw JSON map (from detail blob `interaction_warnings` list).
  factory InteractionWarning.fromJson(Map<String, dynamic> json) {
    final rawUrls = json['source_urls'];
    final urls = rawUrls is List
        ? rawUrls.map((e) => e.toString()).toList()
        : <String>[];

    return InteractionWarning(
      severity: Severity.fromString(json['severity']?.toString() ?? 'safe'),
      evidenceLevel: EvidenceLevel.fromString(
          json['evidence_level']?.toString() ?? 'theoretical'),
      title: json['title']?.toString() ?? '',
      mechanism: json['mechanism']?.toString() ?? '',
      management: json['management']?.toString() ?? '',
      sourceUrls: urls,
    );
  }
}

/// Renders sorted interaction warnings from the detail blob.
/// Sorted by severity (contraindicated first → safe last).
class InteractionWarningsList extends StatelessWidget {
  final List<InteractionWarning> warnings;

  const InteractionWarningsList({super.key, required this.warnings});

  static List<InteractionWarning> sortBySeverity(
      List<InteractionWarning> input) {
    final sorted = List<InteractionWarning>.from(input);
    sorted.sort((a, b) => b.severity.weight.compareTo(a.severity.weight));
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    if (warnings.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          children: [
            const Icon(Icons.check_circle_outline,
                color: AppColors.green, size: 20),
            const SizedBox(width: 8),
            Text(
              'No known interactions found.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
          ],
        ),
      );
    }

    final sorted = sortBySeverity(warnings);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Interaction Warnings',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
        ),
        const SizedBox(height: 12),
        ...sorted.map((w) => _WarningCard(warning: w)),
      ],
    );
  }
}

class _WarningCard extends StatelessWidget {
  final InteractionWarning warning;

  const _WarningCard({required this.warning});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Badges row
            Row(
              children: [
                _SeverityBadge(severity: warning.severity),
                const SizedBox(width: 8),
                _EvidenceBadge(level: warning.evidenceLevel),
              ],
            ),
            const SizedBox(height: 10),
            // Title
            if (warning.title.isNotEmpty)
              Text(
                warning.title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            // Mechanism
            if (warning.mechanism.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                warning.mechanism,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
            // Management guidance
            if (warning.management.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline,
                        size: 14, color: AppColors.textSecondary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        warning.management,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            // Source URLs
            if (warning.sourceUrls.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...warning.sourceUrls.map(
                (url) => _SourceUrlLink(url: url),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SeverityBadge extends StatelessWidget {
  final Severity severity;

  const _SeverityBadge({required this.severity});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: severity.color.withAlpha(25),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: severity.color.withAlpha(80)),
      ),
      child: Text(
        severity.label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: severity.color,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _EvidenceBadge extends StatelessWidget {
  final EvidenceLevel level;

  const _EvidenceBadge({required this.level});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.border,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        level.label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

class _SourceUrlLink extends StatelessWidget {
  final String url;

  const _SourceUrlLink({required this.url});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: GestureDetector(
        onTap: () {
          // TODO: launch url via url_launcher when wired up
        },
        child: Row(
          children: [
            const Icon(Icons.open_in_new,
                size: 12, color: Color(0xFF0A7D6F)),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                url,
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF0A7D6F),
                  decoration: TextDecoration.underline,
                  overflow: TextOverflow.ellipsis,
                ),
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
