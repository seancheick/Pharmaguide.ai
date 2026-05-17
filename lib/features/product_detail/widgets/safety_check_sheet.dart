import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/models/interaction_result.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/widgets/pg_card.dart';
import 'package:pharmaguide/core/widgets/pg_haptics.dart';
import 'package:pharmaguide/core/widgets/pg_modal.dart';
import 'package:pharmaguide/core/widgets/pg_severity_banner.dart';
import 'package:pharmaguide/core/widgets/pg_severity_pill.dart';
import 'package:pharmaguide/core/widgets/verdict_badge.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/stack/providers/stack_providers.dart';

/// Looks up the verdict for a single product so the safety sheet can
/// refuse to show "Safe to add" on a BLOCKED/UNSAFE product even if a
/// future caller skips the upstream FLTR-16 UI guard.
final _sheetProductVerdictProvider = FutureProvider.family
    .autoDispose<String?, String>((ref, dsldId) async {
      final db = ref.watch(coreDatabaseProvider);
      final product = await db.findById(dsldId);
      return product?.verdict;
    });

/// Pre-add safety check sheet.
///
/// Shown when the user taps "Add to Stack" on a product detail screen.
/// Runs [safetyCheckForAddProvider] against their current stack and:
///
/// - If no warnings → immediately shows the confirm button
/// - If warnings → shows severity-tinted banners + each warning as a
///   PGCard with mechanism and management text
///
/// Pressing "Add anyway" fires the add action. The caller is responsible
/// for showing the follow-up success snackbar.
///
/// Returns `true` if the user confirmed the add, `false` otherwise.
Future<bool> showSafetyCheckSheet(
  BuildContext context,
  WidgetRef ref, {
  required String dsldId,
  required String productName,
}) async {
  final result = await PGModal.bottomSheet<bool>(
    context: context,
    builder: (ctx) =>
        _SafetyCheckSheet(dsldId: dsldId, productName: productName),
  );
  return result ?? false;
}

class _SafetyCheckSheet extends ConsumerWidget {
  final String dsldId;
  final String productName;

  const _SafetyCheckSheet({required this.dsldId, required this.productName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final safetyAsync = ref.watch(safetyCheckForAddProvider(dsldId));

    // FLTR-16 — third-layer defense. If the product's verdict is
    // BLOCKED/UNSAFE, the sheet must not display a "Safe to add"
    // banner under any circumstances, even if a direct opener
    // skipped the [PGStackActionButtons] guard. The verdict loads
    // alongside the interaction check; we treat pending verdict as
    // "not yet known, assume safe to render loading" — the check
    // completes in the same frame as the interaction check.
    final verdictAsync = ref.watch(_sheetProductVerdictProvider(dsldId));
    final isUnsafe = isUnsafeVerdict(verdictAsync.asData?.value);

    return Padding(
      // `viewInsetsOf.bottom` lifts content above the keyboard when
      // an input inside the sheet is focused. `PGModal.bottomSheet`
      // already wraps in `SafeArea`, so the inner padding only needs
      // the design-system 24pt gutter — the prior
      // `paddingOf(context).bottom + space24` double-counted the
      // safe-area inset.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppTheme.space20,
          AppTheme.space8,
          AppTheme.space20,
          AppTheme.space24,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Add to your stack',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: AppTheme.space4),
            Text(
              productName,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppTheme.space20),

            if (isUnsafe)
              const _UnsafeProductBanner()
            else
              safetyAsync.when(
                loading: () => const _VerifyingSafety(),
                error: (_, __) => const _SafetyCheckError(),
                data: (warnings) => _SafetyResults(warnings: warnings),
              ),

            const SizedBox(height: AppTheme.space20),

            // Action buttons — primary disables entirely when
            // the product is BLOCKED/UNSAFE. We never offer an
            // "Add anyway" escape hatch for products that fail
            // the product-level safety gate.
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text(isUnsafe ? 'Close' : 'Cancel'),
                  ),
                ),
                const SizedBox(width: AppTheme.space12),
                Expanded(
                  child: isUnsafe
                      ? const FilledButton(
                          onPressed: null,
                          child: Text('Cannot add'),
                        )
                      : safetyAsync.maybeWhen(
                          data: (warnings) => FilledButton(
                            onPressed: () {
                              _fireHaptic(warnings);
                              Navigator.of(context).pop(true);
                            },
                            child: Text(
                              warnings.isEmpty ? 'Add to stack' : 'Add anyway',
                            ),
                          ),
                          orElse: () => const FilledButton(
                            onPressed: null,
                            child: Text('Add to stack'),
                          ),
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _fireHaptic(List<InteractionResult> warnings) {
    if (warnings.isEmpty) {
      PGHaptics.success();
      return;
    }
    // Fire haptic matching the most severe warning.
    final worst = warnings
        .map((w) => w.severity.weight)
        .reduce((a, b) => a > b ? a : b);
    final severity = Severity.values.firstWhere(
      (s) => s.weight == worst,
      orElse: () => Severity.caution,
    );
    PGHaptics.forSeverity(severity);
  }
}

class _VerifyingSafety extends StatelessWidget {
  const _VerifyingSafety();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PGCard(
      variant: PGCardVariant.recessed,
      padding: const EdgeInsets.all(AppTheme.space16),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: scheme.primary,
            ),
          ),
          const SizedBox(width: AppTheme.space12),
          Expanded(
            child: Text(
              'Checking interactions with your stack…',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _SafetyCheckError extends StatelessWidget {
  const _SafetyCheckError();

  @override
  Widget build(BuildContext context) {
    return const PGSeverityBanner(
      tone: PGBannerTone.neutral,
      title: 'Could not verify interactions',
      body:
          'Add is still available, but we recommend reviewing your '
          'stack for potential overlap.',
    );
  }
}

/// FLTR-16 — third-layer defense banner. Rendered in place of
/// [_SafetyResults] when the product itself carries a BLOCKED/UNSAFE
/// verdict. Replaces the "Safe to add" success state so a blocked
/// product never reads as addable, even if the sheet is opened
/// directly. The primary button is disabled alongside.
class _UnsafeProductBanner extends StatelessWidget {
  const _UnsafeProductBanner();

  @override
  Widget build(BuildContext context) {
    return const PGSeverityBanner(
      tone: PGBannerTone.danger,
      title: 'This product cannot be added',
      body:
          'It is flagged as unsafe at the product level. Stack '
          'interaction checks are skipped — the safety concern '
          'applies regardless of what else you are taking.',
    );
  }
}

class _SafetyResults extends StatelessWidget {
  final List<InteractionResult> warnings;

  const _SafetyResults({required this.warnings});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (warnings.isEmpty) {
      return const PGSeverityBanner(
        tone: PGBannerTone.success,
        title: 'No stack interactions found',
        body:
            'This product does not overlap with anything currently in '
            'your stack. Safe to add.',
      );
    }

    // Find worst severity for the banner
    final worstWeight = warnings
        .map((w) => w.severity.weight)
        .reduce((a, b) => a > b ? a : b);
    PGBannerTone tone;
    String bannerTitle;
    if (worstWeight >= 4) {
      tone = PGBannerTone.danger;
      bannerTitle = 'Stack conflict detected';
    } else if (worstWeight >= 3) {
      tone = PGBannerTone.caution;
      bannerTitle = 'Review before adding';
    } else {
      tone = PGBannerTone.info;
      bannerTitle = 'Minor stack overlap';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PGSeverityBanner(
          tone: tone,
          title: bannerTitle,
          body:
              'Found ${warnings.length} issue'
              '${warnings.length == 1 ? '' : 's'} with your current stack.',
        ),
        const SizedBox(height: AppTheme.space12),
        ...warnings.map(
          (w) => Padding(
            padding: const EdgeInsets.only(bottom: AppTheme.space8),
            child: PGCard(
              padding: const EdgeInsets.all(AppTheme.space12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PGSeverityPill(severity: w.severity, compact: true),
                  const SizedBox(height: AppTheme.space8),
                  Text(
                    'With ${w.agent2Name}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppTheme.space4),
                  Text(
                    w.mechanism,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.45,
                    ),
                  ),
                  if (w.management.isNotEmpty) ...[
                    const SizedBox(height: AppTheme.space8),
                    Container(
                      padding: const EdgeInsets.all(AppTheme.space8),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(
                          AppTheme.radiusMedium,
                        ),
                      ),
                      child: Text(
                        w.management,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurface,
                          fontWeight: FontWeight.w500,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
