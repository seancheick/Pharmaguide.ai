// RefillReminderCard — surfaces the v1.3.1 refill timing on the product
// detail screen for items already in the user's stack.
//
// Inputs (all sourced from the product detail state):
//
//   servingsPerContainer  — products_core.servings_per_container (int)
//   netContentsQuantity   — products_core.net_contents_quantity (REAL)
//   netContentsUnit       — products_core.net_contents_unit (TEXT)
//   dosingSummary         — products_core.dosing_summary (TEXT) like
//                           "Take 1 capsule daily" or "Chew 2 gummies
//                           twice daily"
//   addedAt               — UserStacksLocalData.addedAt (DateTime).
//                           When the user added this product to their
//                           stack. We treat this as the "started taking"
//                           date for the days-remaining estimate.
//
// Behavior:
//
//   The card auto-hides if the product is not in the user's stack
//   (addedAt == null) or if servingsPerContainer is missing.
//
//   It estimates daily servings by parsing the dosing_summary text for
//   common frequency phrases ("twice daily", "three times daily", "N
//   times daily"), defaulting to 1 if unparseable. Then:
//
//     daysWorth      = servingsPerContainer / dailyServings
//     daysSinceStart = max(0, now - addedAt in days)
//     daysRemaining  = max(0, daysWorth - daysSinceStart)
//
//   Status tiers (for color and icon):
//
//     out (0)         — red,    "Out — refill now"
//     refill-soon     — orange, "Refill soon (N days left)"   1-7 days
//     almost-out      — amber,  "{N} days left"               8-14 days
//     plenty (>14)    — green,  "{N} days left"
//
// The estimate is heuristic. We do not attempt to track actual
// consumption — that would require dose logging. The card is best-effort
// guidance, and the dosing assumption is shown so users can interpret it.

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/constants/app_colors.dart';

enum RefillTier { out, refillSoon, almostOut, plenty }

class RefillReminderCard extends StatelessWidget {
  final int? servingsPerContainer;
  final double? netContentsQuantity;
  final String? netContentsUnit;
  final String? dosingSummary;
  final DateTime? addedAt;

  const RefillReminderCard({
    super.key,
    required this.servingsPerContainer,
    required this.netContentsQuantity,
    required this.netContentsUnit,
    required this.dosingSummary,
    required this.addedAt,
  });

  // ---------------------------------------------------------------------
  // Pure computation (testable, no Flutter dependencies)
  // ---------------------------------------------------------------------

  /// Parse a dosing_summary string for the daily serving frequency.
  /// Returns 1 by default — the safest assumption when we can't parse.
  ///
  /// Recognizes:
  ///   "twice daily"           → 2
  ///   "three times daily"     → 3
  ///   "four times daily"      → 4
  ///   "{N} times daily"       → N (any digit-based count)
  ///   anything else / null    → 1
  static int estimateDailyServings(String? dosingSummary) {
    if (dosingSummary == null || dosingSummary.isEmpty) return 1;
    final lower = dosingSummary.toLowerCase();

    // Check digit-based "N times daily" first — most general.
    final digitMatch = RegExp(r'(\d+)\s+times\s+daily').firstMatch(lower);
    if (digitMatch != null) {
      final n = int.tryParse(digitMatch.group(1)!);
      if (n != null && n > 0) return n;
    }

    if (lower.contains('twice daily') || lower.contains('two times daily')) {
      return 2;
    }
    if (lower.contains('three times daily')) return 3;
    if (lower.contains('four times daily')) return 4;
    return 1;
  }

  /// Compute the estimated days remaining in the bottle. Returns null
  /// when the input is insufficient (no servingsPerContainer or no
  /// addedAt anchor).
  ///
  /// Clamps to [0, daysWorth] — never returns negative numbers and
  /// never exceeds the bottle's full capacity (defends against future
  /// addedAt clock skew).
  static int? estimateDaysRemaining({
    required int? servingsPerContainer,
    required int dailyServings,
    required DateTime? addedAt,
  }) {
    if (servingsPerContainer == null || servingsPerContainer <= 0) return null;
    if (addedAt == null) return null;
    if (dailyServings <= 0) return null;

    final daysWorth = (servingsPerContainer / dailyServings).floor();

    final now = DateTime.now();
    var daysSinceStart = now.difference(addedAt).inDays;
    if (daysSinceStart < 0) daysSinceStart = 0;

    final remaining = daysWorth - daysSinceStart;
    if (remaining < 0) return 0;
    if (remaining > daysWorth) return daysWorth;
    return remaining;
  }

  static RefillTier tierForDays(int days) {
    if (days <= 0) return RefillTier.out;
    if (days <= 7) return RefillTier.refillSoon;
    if (days <= 14) return RefillTier.almostOut;
    return RefillTier.plenty;
  }

  // ---------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (servingsPerContainer == null || addedAt == null) {
      return const SizedBox.shrink();
    }

    final dailyServings = estimateDailyServings(dosingSummary);
    final daysRemaining = estimateDaysRemaining(
      servingsPerContainer: servingsPerContainer,
      dailyServings: dailyServings,
      addedAt: addedAt,
    );

    if (daysRemaining == null) {
      return const SizedBox.shrink();
    }

    final tier = tierForDays(daysRemaining);
    final resolved = AppColors.of(context);
    final styling = _stylingForTier(tier, context);

    return Card(
      key: const Key('refill-reminder-card'),
      color: AppColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        side: BorderSide(color: styling.borderColor, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.space16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              key: Key('refill-tier-${_tierKey(tier)}'),
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: styling.iconBackgroundColor,
                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
              ),
              child: Icon(
                styling.icon,
                color: styling.iconColor,
                size: 22,
              ),
            ),
            const SizedBox(width: AppTheme.space12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    styling.headline(daysRemaining),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: styling.headlineColor,
                    ),
                  ),
                  if (_subtitleText() != null) ...[
                    const SizedBox(height: AppTheme.space4),
                    Text(
                      _subtitleText()!,
                      style: TextStyle(
                        fontSize: 12,
                        color: resolved.textSecondary,
                      ),
                    ),
                  ],
                  if (dosingSummary != null && dosingSummary!.isNotEmpty) ...[
                    const SizedBox(height: AppTheme.space2),
                    Text(
                      'Estimate based on "$dosingSummary"',
                      style: TextStyle(
                        fontSize: 11,
                        color: resolved.textSecondary,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? _subtitleText() {
    if (netContentsQuantity == null || netContentsUnit == null) return null;
    final qty = netContentsQuantity!;
    final qtyText = qty == qty.truncateToDouble()
        ? qty.toInt().toString()
        : qty.toString();
    return 'Bottle: $qtyText $netContentsUnit';
  }

  static String _tierKey(RefillTier tier) {
    switch (tier) {
      case RefillTier.out:
        return 'out';
      case RefillTier.refillSoon:
        return 'refill-soon';
      case RefillTier.almostOut:
        return 'almost-out';
      case RefillTier.plenty:
        return 'plenty';
    }
  }

  static _TierStyling _stylingForTier(RefillTier tier, BuildContext context) {
    switch (tier) {
      case RefillTier.out:
        return _TierStyling(
          icon: Icons.error_outline,
          iconColor: const Color(0xFFC62828),
          iconBackgroundColor: const Color(0xFFFFEBEE),
          borderColor: const Color(0xFFEF9A9A),
          headlineColor: const Color(0xFFC62828),
          headline: (_) => 'Out — refill now',
        );
      case RefillTier.refillSoon:
        return _TierStyling(
          icon: Icons.schedule,
          iconColor: const Color(0xFFE65100),
          iconBackgroundColor: const Color(0xFFFFF3E0),
          borderColor: const Color(0xFFFFCC80),
          headlineColor: const Color(0xFFE65100),
          headline: (days) => 'Refill soon — $days days left',
        );
      case RefillTier.almostOut:
        return _TierStyling(
          icon: Icons.access_time,
          iconColor: const Color(0xFFF57F17),
          iconBackgroundColor: const Color(0xFFFFFDE7),
          borderColor: const Color(0xFFFFF59D),
          headlineColor: const Color(0xFFF57F17),
          headline: (days) => 'Almost out — $days days left',
        );
      case RefillTier.plenty:
        return _TierStyling(
          icon: Icons.check_circle_outline,
          iconColor: AppColors.green,
          iconBackgroundColor: const Color(0xFFE8F5E9),
          borderColor: const Color(0xFFA5D6A7),
          headlineColor: AppColors.of(context).textPrimary,
          headline: (days) => '$days days left',
        );
    }
  }
}

class _TierStyling {
  final IconData icon;
  final Color iconColor;
  final Color iconBackgroundColor;
  final Color borderColor;
  final Color headlineColor;
  final String Function(int daysRemaining) headline;

  const _TierStyling({
    required this.icon,
    required this.iconColor,
    required this.iconBackgroundColor,
    required this.borderColor,
    required this.headlineColor,
    required this.headline,
  });
}
