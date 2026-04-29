import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';

/// A generated product card widget used when no real product photo is
/// available. Derives a consistent brand color from the brand name hash
/// and displays the product initial, name, brand, form factor icon, and
/// an optional mini score bar.
///
/// 100% offline, no network, deterministic output for the same brand.
class BrandedPlaceholder extends StatelessWidget {
  final String productName;
  final String brand;
  final String? formFactor;
  final double? score;
  final double size;

  /// When true, force the simple colored-square-with-initial layout
  /// regardless of [size]. Use this for hero contexts where the
  /// placeholder must fit cleanly into a 1:1 box at large sizes —
  /// the default multi-row "full card" layout is sized to fit
  /// list-item dimensions and overflows by ~2px when stretched
  /// to hero proportions (96pt+) due to its inner Column metrics.
  final bool compact;

  const BrandedPlaceholder({
    super.key,
    required this.productName,
    required this.brand,
    this.formFactor,
    this.score,
    this.size = 52,
    this.compact = false,
  });

  /// Derives a stable hue from the brand name so the same brand always
  /// gets the same color across sessions.
  Color _brandColor() {
    final source = brand.isNotEmpty ? brand : productName;
    final hash = source.hashCode & 0x7FFFFFFF;
    final hue = (hash % 360).toDouble();
    return HSLColor.fromAHSL(1.0, hue, 0.35, 0.45).toColor();
  }

  IconData _formIcon() => switch (formFactor?.toLowerCase()) {
        'capsule' => Icons.medication_outlined,
        'softgel' => Icons.circle_outlined,
        'tablet' => Icons.crop_square_rounded,
        'gummy' => Icons.favorite_outline,
        'powder' => Icons.grain,
        'liquid' => Icons.water_drop_outlined,
        _ => Icons.medication_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _brandColor();
    final initial = productName.isNotEmpty ? productName[0].toUpperCase() : '?';
    // Computed foreground for the brand-colored surface. Brand hue always
    // has L=0.45 (dark) but we derive dynamically so it adapts if that changes.
    final onBrand =
        ThemeData.estimateBrightnessForColor(color) == Brightness.dark
            ? Colors.white
            : Colors.black;

    // Compact mode — just the colored square with initial (for list
    // items, OR when the caller forces it via [compact] for hero use).
    if (compact || size <= 56) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        ),
        alignment: Alignment.center,
        child: Text(
          initial,
          style: theme.textTheme.titleLarge?.copyWith(
            fontSize: size * 0.42,
            fontWeight: FontWeight.w700,
            color: onBrand,
          ),
        ),
      );
    }

    // Full card mode — initial + name + brand + form/score
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(
          color: color.withValues(alpha: 0.18),
          width: 0.8,
        ),
      ),
      padding: const EdgeInsets.all(AppTheme.space8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Brand-colored square with initial
          Container(
            width: size * 0.38,
            height: size * 0.38,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            ),
            alignment: Alignment.center,
            child: Text(
              initial,
              style: theme.textTheme.titleLarge?.copyWith(
                fontSize: size * 0.18,
                fontWeight: FontWeight.w700,
                color: onBrand,
              ),
            ),
          ),
          const SizedBox(height: AppTheme.space6),
          // Product name
          Text(
            productName,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
              height: 1.2,
            ),
          ),
          if (brand.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              brand,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 9,
                fontWeight: FontWeight.w400,
                color: color.withValues(alpha: 0.7),
              ),
            ),
          ],
          const Spacer(),
          // Form icon + mini score
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(_formIcon(), size: 12, color: color.withValues(alpha: 0.6)),
              if (score != null) ...[
                const SizedBox(width: 4),
                SizedBox(
                  width: 24,
                  height: 4,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: (score! / 100).clamp(0.0, 1.0),
                      backgroundColor: color.withValues(alpha: 0.15),
                      valueColor: AlwaysStoppedAnimation(color),
                      minHeight: 4,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
