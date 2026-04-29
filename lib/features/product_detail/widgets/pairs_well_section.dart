// PairsWellSection — "Pairs well with your stack" card.
//
// Shows synergy clusters that would activate when the user adds this
// product to their existing stack. Hides completely when the stack is
// empty or when no synergy pairs are found.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/widgets/pg_card.dart';
import 'package:pharmaguide/features/product_detail/providers/pairs_well_provider.dart';
import 'package:pharmaguide/services/stack/synergy_result.dart';

class PairsWellSection extends ConsumerWidget {
  final String dsldId;
  const PairsWellSection({super.key, required this.dsldId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncPairs = ref.watch(pairsWellWithStackProvider(dsldId));
    return asyncPairs.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (pairs) {
        if (pairs.isEmpty) return const SizedBox.shrink();
        return _PairsWellBody(pairs: pairs);
      },
    );
  }
}

class _PairsWellBody extends StatelessWidget {
  final List<SynergyMatch> pairs;
  const _PairsWellBody({required this.pairs});

  Color _tierColor(String tier) {
    switch (tier) {
      case 'strong':
        return AppTheme.severitySafe;
      case 'moderate':
        return AppTheme.scoreGood;
      case 'limited':
        return AppTheme.severityCaution;
      default:
        return AppTheme.insufficientData;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return PGCard(
      padding: const EdgeInsets.all(AppTheme.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.hub_outlined, size: 18, color: scheme.primary),
              const SizedBox(width: AppTheme.space6),
              Text(
                'Pairs Well with Your Stack',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.15,
                ),
              ),
              const SizedBox(width: AppTheme.space8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                ),
                child: Text(
                  '${pairs.length}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.space4),
          Text(
            pairs.length == 1
                ? 'Adding this would activate this ingredient combination '
                    'from your current stack. Tier shows research strength.'
                : 'Adding this would activate these ingredient combinations '
                    'from your current stack. Tier shows research strength.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppTheme.space12),
          ...pairs.map((pair) {
            final tierColor = _tierColor(pair.evidenceTier);
            return Padding(
              padding: const EdgeInsets.only(bottom: AppTheme.space8),
              child: Container(
                padding: const EdgeInsets.all(AppTheme.space12),
                decoration: BoxDecoration(
                  color: tierColor.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                  border: Border.all(
                    color: tierColor.withValues(alpha: 0.25),
                    width: 0.8,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.bolt_rounded, size: 14, color: tierColor),
                        const SizedBox(width: AppTheme.space4),
                        Expanded(
                          child: Text(
                            pair.clusterName,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: tierColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            pair.evidenceTier,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: tierColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (pair.mechanism.isNotEmpty) ...[
                      const SizedBox(height: AppTheme.space4),
                      Text(
                        pair.mechanism,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
