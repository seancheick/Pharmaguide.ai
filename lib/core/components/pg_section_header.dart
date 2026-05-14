import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_eyebrow.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';

/// Section header block — mono caps eyebrow + sans title + optional body.
///
/// Use the [serif] flag only for hero/emotional/empty-state contexts.
/// **Never** on warnings, clinical content, settings, or navigation.
/// Default body weight stays 400 (Geist Sans).
class PGSectionHeader extends StatelessWidget {
  /// Mono caps eyebrow string — caller passes any case, widget uppercases.
  final String? eyebrow;
  final String title;
  final String? subtitle;

  /// When true, [title] renders in Newsreader serif.
  /// Use sparingly — accent contexts only.
  final bool serif;

  /// Tail widget rendered at the trailing edge of the eyebrow row
  /// (e.g. "View all" pill button).
  final Widget? trailing;

  const PGSectionHeader({
    super.key,
    required this.title,
    this.eyebrow,
    this.subtitle,
    this.serif = false,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (eyebrow != null || trailing != null)
          Row(
            children: [
              if (eyebrow != null) PGEyebrow(eyebrow!),
              const Spacer(),
              if (trailing != null) trailing!,
            ],
          ),
        if (eyebrow != null || trailing != null)
          const SizedBox(height: V2Spacing.space12),
        Text(
          title,
          style: serif
              ? V2Typography.displayXs(color: V2Colors.fg)
              : V2Typography.title(color: V2Colors.fg),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: V2Spacing.space8),
          Text(
            subtitle!,
            style: V2Typography.body(color: V2Colors.fgMuted),
          ),
        ],
      ],
    );
  }
}
