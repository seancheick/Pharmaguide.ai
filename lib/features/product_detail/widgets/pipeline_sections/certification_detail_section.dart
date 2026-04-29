// Certification detail — GMP, purity, heavy metal, label accuracy,
// third-party programs (NSF Sport, USP Verified, etc.).

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/extensions/json_helpers.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/widgets/pg_card.dart';

class CertificationDetailSection extends StatelessWidget {
  final Map<String, dynamic>? certificationDetail;
  const CertificationDetailSection({super.key, this.certificationDetail});

  @override
  Widget build(BuildContext context) {
    if (certificationDetail == null) return const SizedBox.shrink();
    final theme = Theme.of(context);

    final checks = <(String, bool)>[
      ('GMP Certified', certificationDetail!.safeBool('gmp')),
      ('Purity Verified', certificationDetail!.safeBool('purity_verified')),
      ('Heavy Metal Tested',
          certificationDetail!.safeBool('heavy_metal_tested')),
      ('Label Accuracy Verified',
          certificationDetail!.safeBool('label_accuracy_verified')),
    ];

    // Only show if at least one certification is true
    if (!checks.any((c) => c.$2)) return const SizedBox.shrink();

    return PGCard(
      padding: const EdgeInsets.all(AppTheme.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.workspace_premium_outlined, size: 18,
                  color: AppTheme.severitySafe),
              const SizedBox(width: AppTheme.space6),
              Text(
                'Certifications',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.15,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.space12),
          ...checks.map((check) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Icon(
                      check.$2
                          ? Icons.check_circle_rounded
                          : Icons.cancel_outlined,
                      size: 16,
                      color: check.$2
                          ? AppTheme.severitySafe
                          : theme.colorScheme.outlineVariant,
                    ),
                    const SizedBox(width: AppTheme.space8),
                    Text(
                      check.$1,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: check.$2
                            ? theme.colorScheme.onSurface
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              )),
          // Third-party program badges (NSF Sport, USP Verified, etc.).
          //
          // Pipeline ships `programs` in two shapes — legacy plain
          // strings, and newer `[{name, verified}, ...]` maps. The
          // older `safeStringList` path called `.toString()` on the
          // maps and produced "{name: Informed Choice, verified: true}"
          // verbatim in the badge — same JSON-leak class as T0.3.
          // Extract the `name` field defensively, fall through to the
          // raw string when the entry is already a string.
          Builder(builder: (context) {
            final programs = certificationDetail!
                .safeMap('third_party_programs')
                .safeList('programs')
                .map<String>((e) {
                  if (e is String) return e.trim();
                  if (e is Map) return (e['name']?.toString() ?? '').trim();
                  return '';
                })
                .where((s) => s.isNotEmpty)
                .toList(growable: false);
            if (programs.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: AppTheme.space12),
                Text(
                  'Third-Party Verified',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppTheme.space8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: programs
                      .map((prog) => Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppTheme.space12,
                                vertical: AppTheme.space6),
                            decoration: BoxDecoration(
                              color: AppTheme.severitySafe
                                  .withValues(alpha: 0.08),
                              borderRadius:
                                  BorderRadius.circular(AppTheme.radiusFull),
                              border: Border.all(
                                color: AppTheme.severitySafe
                                    .withValues(alpha: 0.35),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.verified_rounded,
                                  size: 12,
                                  color: AppTheme.severitySafe,
                                ),
                                const SizedBox(width: AppTheme.space4),
                                Text(
                                  prog,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.severitySafe,
                                  ),
                                ),
                              ],
                            ),
                          ))
                      .toList(),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }
}
