import 'package:flutter/material.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/theme/app_motion.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/widgets/pg_evidence_badge.dart';
import 'package:pharmaguide/core/widgets/pg_severity_pill.dart';

/// The single most important widget in PharmaGuide — this is how a medical
/// interaction warning is rendered. Everything about it signals trust:
///
/// - Severity pill + evidence badge in a single row (reads in <1s)
/// - Left accent strip + tinted wash matching severity
/// - Progressive disclosure (mechanism truncates; tap to expand for management)
/// - "What to do:" highlighted block for actionable guidance
/// - Source count chip tied to a citation sheet
///
/// ```dart
/// PGInteractionCard(
///   severity: Severity.caution,
///   evidenceLevel: EvidenceLevel.established,
///   title: 'St. John's Wort + SSRIs',
///   mechanism: 'Induces CYP3A4 metabolism, reducing SSRI plasma levels.',
///   management: 'Avoid combination. Consult prescriber before using.',
///   sources: warning.sourceUrls,
///   onSourceTap: () => showCitationsSheet(context, warning.sourceUrls),
/// )
/// ```
class PGInteractionCard extends StatefulWidget {
  final Severity severity;
  final EvidenceLevel evidenceLevel;
  final String title;
  final String mechanism;
  final String management;
  final List<String> sources;
  final VoidCallback? onSourceTap;
  final bool initiallyExpanded;

  const PGInteractionCard({
    super.key,
    required this.severity,
    required this.evidenceLevel,
    required this.title,
    required this.mechanism,
    required this.management,
    this.sources = const [],
    this.onSourceTap,
    this.initiallyExpanded = false,
  });

  @override
  State<PGInteractionCard> createState() => _PGInteractionCardState();
}

class _PGInteractionCardState extends State<PGInteractionCard> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  Color _accent() {
    switch (widget.severity) {
      case Severity.contraindicated:
        return AppTheme.severityContraindicated;
      case Severity.avoid:
        return AppTheme.severityAvoid;
      case Severity.caution:
        return AppTheme.severityCaution;
      case Severity.monitor:
        return AppTheme.severityMonitor;
      case Severity.informational:
        return AppTheme.severityInformational;
      case Severity.safe:
        return AppTheme.severitySafe;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final accent = _accent();
    final tint = accent.withValues(alpha: isDark ? 0.10 : 0.045);

    return AnimatedContainer(
      duration: AppMotion.medium,
      curve: AppMotion.standard,
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(color: scheme.outlineVariant, width: 0.8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Soft severity wash
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [tint, Colors.transparent],
                  stops: const [0.0, 0.45],
                ),
              ),
            ),
          ),
          // Left accent strip
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(width: 3, color: accent),
          ),
          // Body
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTheme.space16 + 3, // extra 3 to clear the accent strip
              AppTheme.space16,
              AppTheme.space16,
              AppTheme.space12,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    PGSeverityPill(severity: widget.severity, compact: true),
                    PGEvidenceBadge(level: widget.evidenceLevel),
                  ],
                ),
                if (widget.title.isNotEmpty) ...[
                  const SizedBox(height: AppTheme.space12),
                  Text(
                    widget.title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                ],
                if (widget.mechanism.isNotEmpty) ...[
                  const SizedBox(height: AppTheme.space6),
                  AnimatedCrossFade(
                    duration: AppMotion.medium,
                    sizeCurve: AppMotion.standard,
                    firstCurve: AppMotion.standard,
                    secondCurve: AppMotion.standard,
                    crossFadeState: _expanded
                        ? CrossFadeState.showSecond
                        : CrossFadeState.showFirst,
                    firstChild: Text(
                      widget.mechanism,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    secondChild: Text(
                      widget.mechanism,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
                AnimatedSize(
                  duration: AppMotion.medium,
                  curve: AppMotion.standard,
                  alignment: Alignment.topCenter,
                  child: _expanded && widget.management.isNotEmpty
                      ? Padding(
                          padding: const EdgeInsets.only(
                              top: AppTheme.space12),
                          child: _ManagementBlock(
                            text: widget.management,
                            accent: accent,
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                const SizedBox(height: AppTheme.space8),
                Row(
                  children: [
                    _InlineAction(
                      onTap: () => setState(() => _expanded = !_expanded),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _expanded ? 'Show less' : 'Show more',
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontSize: 13,
                              color: scheme.primary,
                            ),
                          ),
                          const SizedBox(width: AppTheme.space2),
                          AnimatedRotation(
                            turns: _expanded ? 0.5 : 0,
                            duration: AppMotion.medium,
                            curve: AppMotion.standard,
                            child: Icon(
                              Icons.keyboard_arrow_down_rounded,
                              size: 18,
                              color: scheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    if (widget.sources.isNotEmpty)
                      _InlineAction(
                        onTap: widget.onSourceTap,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.menu_book_outlined,
                              size: 14,
                              color: scheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: AppTheme.space4),
                            Text(
                              '${widget.sources.length} source'
                              '${widget.sources.length == 1 ? '' : 's'}',
                              style: theme.textTheme.labelMedium?.copyWith(
                                fontSize: 12,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ManagementBlock extends StatelessWidget {
  final String text;
  final Color accent;

  const _ManagementBlock({required this.text, required this.accent});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(AppTheme.space12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: scheme.outlineVariant, width: 0.8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lightbulb_outline_rounded, size: 16, color: accent),
          const SizedBox(width: AppTheme.space8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurface,
                  height: 1.5,
                  fontSize: 13,
                ),
                children: [
                  TextSpan(
                    text: 'What to do: ',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: accent,
                    ),
                  ),
                  TextSpan(text: text),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineAction extends StatelessWidget {
  final VoidCallback? onTap;
  final Widget child;

  const _InlineAction({required this.onTap, required this.child});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusFull),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: child,
      ),
    );
  }
}
