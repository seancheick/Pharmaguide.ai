import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_eyebrow.dart';
import 'package:pharmaguide/core/components/pg_pill_button.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';

/// Empty-state surface — designed placeholder for "no data yet" screens.
///
/// Per the v2 plan: replace bare empty states ("No data") with a single
/// generous, crafted moment. One halo, one serif title, one body line,
/// one CTA. Never multiple competing empty illustrations.
///
/// **Structure:**
/// - Optional mono caps eyebrow ("YOUR STACK")
/// - Soft icon tile in accent-tint background
/// - Newsreader serif headline (empty-state context = governance-approved
///   serif moment)
/// - Geist Sans body line beneath
/// - Optional primary + secondary CTA pair
class PGEmptyState extends StatelessWidget {
  final IconData icon;
  final String headline;
  final String? eyebrow;
  final String? body;

  /// Primary CTA (e.g. "Add supplement"). Renders as a primary pill.
  final String? primaryLabel;
  final IconData? primaryIcon;
  final VoidCallback? onPrimaryTap;

  /// Secondary CTA (e.g. "Learn more"). Renders as a ghost pill below
  /// the primary action.
  final String? secondaryLabel;
  final VoidCallback? onSecondaryTap;

  const PGEmptyState({
    super.key,
    required this.icon,
    required this.headline,
    this.eyebrow,
    this.body,
    this.primaryLabel,
    this.primaryIcon,
    this.onPrimaryTap,
    this.secondaryLabel,
    this.onSecondaryTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: V2Spacing.space32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: V2Colors.accentTint,
              borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
            ),
            child: Icon(icon, size: 36, color: V2Colors.accent),
          ),
          const SizedBox(height: V2Spacing.space24),
          if (eyebrow != null) ...[
            PGEyebrow(eyebrow!),
            const SizedBox(height: V2Spacing.space8),
          ],
          Text(
            headline,
            style: V2Typography.displayXs(color: V2Colors.fg),
            textAlign: TextAlign.center,
          ),
          if (body != null) ...[
            const SizedBox(height: V2Spacing.space12),
            Text(
              body!,
              style: V2Typography.body(color: V2Colors.fgMuted),
              textAlign: TextAlign.center,
            ),
          ],
          if (primaryLabel != null) ...[
            const SizedBox(height: V2Spacing.space24),
            PGPillButton(
              label: primaryLabel!,
              icon: primaryIcon,
              onPressed: onPrimaryTap,
            ),
          ],
          if (secondaryLabel != null) ...[
            const SizedBox(height: V2Spacing.space8),
            PGPillButton(
              label: secondaryLabel!,
              variant: PGPillVariant.ghost,
              onPressed: onSecondaryTap,
            ),
          ],
        ],
      ),
    );
  }
}
