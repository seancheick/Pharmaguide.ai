import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/widgets/pg_card.dart';
import 'package:pharmaguide/core/widgets/pg_frosted_nav_bar.dart';
import 'package:pharmaguide/core/widgets/pg_interaction_card.dart';
import 'package:url_launcher/url_launcher.dart';

/// A single interaction warning entry parsed from the detail blob.
///
/// This class is public because [product_detail_screen.dart] parses it
/// directly from the detail blob and passes a `List<InteractionWarning>`
/// into [InteractionWarningsList].
class InteractionWarning {
  final Severity severity;
  final EvidenceLevel evidenceLevel;
  final String title;
  final String mechanism;
  final String management;
  final List<String> sourceUrls;

  /// The condition that triggers this warning (e.g. 'pregnancy', 'diabetes').
  /// Null if the warning is not condition-specific (e.g. drug class warning).
  final String? conditionId;

  /// The drug class that triggers this warning (e.g. 'anticoagulants').
  /// Null if the warning is not drug-class-specific.
  final String? drugClassId;

  const InteractionWarning({
    required this.severity,
    required this.evidenceLevel,
    required this.title,
    required this.mechanism,
    required this.management,
    this.sourceUrls = const [],
    this.conditionId,
    this.drugClassId,
  });

  /// Parse from raw JSON map (from detail blob `warnings` list).
  ///
  /// Pipeline emits fields: `detail`, `action`, `sources`, `condition_id`,
  /// `drug_class_id`. Legacy aliases `mechanism`/`management`/`source_urls`
  /// are also accepted for backward compat with older cached blobs.
  factory InteractionWarning.fromJson(Map<String, dynamic> json) {
    final rawUrls = json['sources'] ?? json['source_urls'];
    final urls = rawUrls is List
        ? rawUrls.map((e) => e.toString()).toList()
        : <String>[];

    return InteractionWarning(
      severity: Severity.fromString(json['severity']?.toString() ?? 'safe'),
      evidenceLevel: EvidenceLevel.fromString(
          json['evidence_level']?.toString() ?? 'theoretical'),
      title: json['title']?.toString() ?? '',
      mechanism: (json['detail'] ?? json['mechanism'])?.toString() ?? '',
      management: (json['action'] ?? json['management'])?.toString() ?? '',
      sourceUrls: urls,
      conditionId: json['condition_id']?.toString(),
      drugClassId: json['drug_class_id']?.toString(),
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

  void _showCitations(BuildContext context, InteractionWarning warning) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (ctx) => _CitationsSheet(warning: warning),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // -----------------------------------------------------------------
    // Empty state — "no known interactions." This is GOOD news in a
    // pharma app, so treat it as a positive-tinted card, not a dry
    // single line of gray text.
    // -----------------------------------------------------------------
    if (warnings.isEmpty) {
      return PGCard(
        variant: PGCardVariant.recessed,
        padding: const EdgeInsets.all(AppTheme.space16),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppTheme.severitySafe.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppTheme.radiusFull),
              ),
              child: const Icon(
                Icons.check_rounded,
                color: AppTheme.severitySafe,
                size: 20,
              ),
            ),
            const SizedBox(width: AppTheme.space12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'No known interactions',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Based on your current health profile and this product.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
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
        // Section header row with count pill
        Padding(
          padding: const EdgeInsets.only(bottom: AppTheme.space12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                'Interaction warnings',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(width: AppTheme.space8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                  border: Border.all(
                    color: scheme.outlineVariant,
                    width: 0.8,
                  ),
                ),
                child: Text(
                  '${sorted.length}',
                  style: AppTheme.numeric(
                    TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                      height: 1.2,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Stack of interaction cards with breathing room between
        ...List.generate(sorted.length, (i) {
          final w = sorted[i];
          return Padding(
            padding: EdgeInsets.only(
              bottom: i == sorted.length - 1 ? 0 : AppTheme.space12,
            ),
            child: PGInteractionCard(
              severity: w.severity,
              evidenceLevel: w.evidenceLevel,
              title: w.title,
              mechanism: w.mechanism,
              management: w.management,
              sources: w.sourceUrls,
              // Top-severity card starts expanded — user sees the worst
              // interaction's full details without needing to tap.
              initiallyExpanded: i == 0 && w.severity.weight >= 3,
              onSourceTap: w.sourceUrls.isEmpty
                  ? null
                  : () => _showCitations(context, w),
            ),
          );
        }),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Citations bottom sheet — shown when user taps the "N sources" chip.
// ---------------------------------------------------------------------------

class _CitationsSheet extends StatelessWidget {
  final InteractionWarning warning;

  const _CitationsSheet({required this.warning});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return SingleChildScrollView(
          controller: scrollController,
          // Bottom padding clears the frosted nav bar.
          padding: const EdgeInsets.fromLTRB(
            AppTheme.space20,
            AppTheme.space8,
            AppTheme.space20,
            AppTheme.space32 + kPGNavBarHeight,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Text(
                'Sources',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Clinical references backing this interaction warning.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppTheme.space20),
              // Each source as its own tappable PGCard
              ...warning.sourceUrls.asMap().entries.map((entry) {
                final idx = entry.key;
                final url = entry.value;
                return Padding(
                  padding: const EdgeInsets.only(bottom: AppTheme.space8),
                  child: PGCard(
                    padding: const EdgeInsets.all(AppTheme.space12),
                    onTap: () {
                      final uri = Uri.tryParse(url);
                      if (uri == null) return;
                      // Fire-and-forget — if the OS can't handle the URL
                      // we silently no-op. The scheme is always https from
                      // the pipeline so launch failures are extremely rare;
                      // we deliberately don't await to keep the tap snappy.
                      unawaited(
                        launchUrl(uri, mode: LaunchMode.externalApplication),
                      );
                    },
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHigh,
                            borderRadius:
                                BorderRadius.circular(AppTheme.radiusFull),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '${idx + 1}',
                            style: AppTheme.numeric(
                              theme.textTheme.labelLarge!.copyWith(
                                fontSize: 13,
                                color: scheme.onSurface,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: AppTheme.space12),
                        Expanded(
                          child: Text(
                            _prettyHost(url),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: AppTheme.space8),
                        Icon(
                          Icons.open_in_new_rounded,
                          size: 16,
                          color: scheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  /// Returns a prettier label for a URL — host + last path segment, so
  /// `https://pubmed.ncbi.nlm.nih.gov/12345678/abc` becomes
  /// `pubmed.ncbi.nlm.nih.gov / abc`.
  String _prettyHost(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    final host = uri.host.isEmpty ? url : uri.host;
    final lastSeg = uri.pathSegments.isNotEmpty
        ? uri.pathSegments.lastWhere((s) => s.isNotEmpty, orElse: () => '')
        : '';
    if (lastSeg.isEmpty) return host;
    return '$host  ·  $lastSeg';
  }
}
