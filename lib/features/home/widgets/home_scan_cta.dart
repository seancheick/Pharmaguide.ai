// Primary scan CTA — gradient pill card. The single most distinctive thing
// on the home screen; everything else is restrained.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';

class HomeScanCta extends StatelessWidget {
  const HomeScanCta({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final darkerBrand = Color.lerp(scheme.primary, scheme.scrim, 0.25)!;
    // Dynamic Type clamp — the gradient card has a fixed icon well and
    // right chevron, so unbounded text scaling breaks the layout. Cap
    // the text scaler at 1.3x on this single hero surface; long body
    // content on this screen still honors full Dynamic Type.
    final clampedScaler = MediaQuery.textScalerOf(context)
        .clamp(minScaleFactor: 1.0, maxScaleFactor: 1.3);

    return Semantics(
      button: true,
      label: 'Scan a supplement barcode to check its quality and safety',
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppTheme.radiusXLarge),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => GoRouter.of(context).go(Routes.scan),
          child: Ink(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [scheme.primary, darkerBrand],
              ),
              borderRadius: BorderRadius.circular(AppTheme.radiusXLarge),
              boxShadow: [
                BoxShadow(
                  color: scheme.primary.withValues(alpha: 0.25),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                  spreadRadius: -6,
                ),
              ],
            ),
            child: MediaQuery(
              data:
                  MediaQuery.of(context).copyWith(textScaler: clampedScaler),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTheme.space20,
                  AppTheme.space20,
                  AppTheme.space16,
                  AppTheme.space20,
                ),
                child: Row(
                  children: [
                    // Icon well
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: scheme.onPrimary.withValues(alpha: 0.18),
                        borderRadius:
                            BorderRadius.circular(AppTheme.radiusLarge),
                        border: Border.all(
                          color: scheme.onPrimary.withValues(alpha: 0.22),
                          width: 0.8,
                        ),
                      ),
                      child: Icon(
                        Icons.qr_code_scanner_rounded,
                        color: scheme.onPrimary,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: AppTheme.space16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Scan a supplement',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: scheme.onPrimary,
                              letterSpacing: -0.25,
                              height: 1.22,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Check safety & interactions instantly',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                              color:
                                  scheme.onPrimary.withValues(alpha: 0.82),
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppTheme.space8),
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 22,
                      color: scheme.onPrimary.withValues(alpha: 0.88),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
