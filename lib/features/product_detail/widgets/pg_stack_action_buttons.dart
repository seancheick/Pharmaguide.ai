import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/widgets/pg_haptics.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/product_detail/widgets/safety_check_sheet.dart';
import 'package:pharmaguide/features/stack/providers/stack_providers.dart';

/// Action buttons at the bottom of the product detail screen:
/// Add-to-Stack (or In-Stack with remove), Share, Save.
///
/// - **Add flow:** runs the safety check sheet first, then (if confirmed)
///   inserts and shows a success snackbar with Undo.
/// - **Already-in-stack state:** Add button is replaced with a pill
///   showing "In your stack" + a quick Remove button.
/// - **Remove flow:** fires the soft-delete action and shows a snackbar
///   with a 5-second Undo window that calls `stackActions.restore(id)`.
class PGStackActionButtons extends ConsumerWidget {
  final String dsldId;
  final VoidCallback? onShare;
  final VoidCallback? onSave;

  const PGStackActionButtons({
    super.key,
    required this.dsldId,
    this.onShare,
    this.onSave,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entryAsync = ref.watch(stackEntryForDsldIdProvider(dsldId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        entryAsync.when(
          loading: () => const _LoadingPrimary(),
          error: (_, __) => _AddButton(
            onTap: () => _handleAdd(context, ref),
          ),
          data: (entry) {
            if (entry == null) {
              return _AddButton(
                onTap: () => _handleAdd(context, ref),
              );
            }
            return _InStackPanel(
              entryId: entry.id,
              onRemove: () => _handleRemove(context, ref, entry.id),
            );
          },
        ),
        const SizedBox(height: AppTheme.space12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onShare,
                icon: const Icon(Icons.ios_share_rounded, size: 18),
                label: const Text('Share'),
              ),
            ),
            const SizedBox(width: AppTheme.space12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onSave,
                icon: const Icon(Icons.bookmark_border_rounded, size: 18),
                label: const Text('Save'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // Add flow
  // ---------------------------------------------------------------------
  Future<void> _handleAdd(BuildContext context, WidgetRef ref) async {
    await PGHaptics.press();

    // Fetch the product up front so we can pass its name into the sheet
    // and into the addProduct call on confirm.
    final coreDb = ref.read(coreDatabaseProvider);
    ProductsCoreData? product;
    try {
      product = await coreDb.findById(dsldId);
    } on Exception {
      product = null;
    }
    if (!context.mounted) return;
    if (product == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load product.')),
      );
      return;
    }

    final confirmed = await showSafetyCheckSheet(
      context,
      ref,
      dsldId: dsldId,
      productName: product.productName,
    );
    if (!confirmed || !context.mounted) return;

    final actions = ref.read(stackActionsProvider);
    try {
      await actions.addProduct(product);
    } on Exception {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not add to stack.')),
      );
      return;
    }

    // Fire haptic first so the await doesn't reintroduce the context gap.
    await PGHaptics.success();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Added ${product.productName} to your stack'),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Remove flow (with undo)
  // ---------------------------------------------------------------------
  Future<void> _handleRemove(
    BuildContext context,
    WidgetRef ref,
    String entryId,
  ) async {
    final actions = ref.read(stackActionsProvider);
    await PGHaptics.press();
    try {
      await actions.remove(entryId);
    } on Exception {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not remove from stack.')),
      );
      return;
    }
    if (!context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: const Text('Removed from stack'),
        duration: const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            try {
              await actions.restore(entryId);
            } on Exception {
              // Silent — UI state already optimistic.
            }
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sub-widgets
// ---------------------------------------------------------------------------

class _LoadingPrimary extends StatelessWidget {
  const _LoadingPrimary();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppTheme.radiusFull),
      ),
      alignment: Alignment.center,
      child: SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  final VoidCallback onTap;
  const _AddButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.add_rounded, size: 20),
      label: const Text('Add to my stack'),
    );
  }
}

class _InStackPanel extends StatelessWidget {
  final String entryId;
  final VoidCallback onRemove;

  const _InStackPanel({
    required this.entryId,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.space16),
      decoration: BoxDecoration(
        color: AppTheme.severitySafe.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppTheme.radiusFull),
        border: Border.all(
          color: AppTheme.severitySafe.withValues(alpha: 0.22),
          width: 0.8,
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle_outline_rounded,
            size: 20,
            color: AppTheme.severitySafe,
          ),
          const SizedBox(width: AppTheme.space8),
          Text(
            'In your stack',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppTheme.severitySafe,
            ),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: onRemove,
            style: TextButton.styleFrom(
              foregroundColor: scheme.onSurfaceVariant,
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.space12,
                vertical: AppTheme.space8,
              ),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: const Icon(Icons.delete_outline_rounded, size: 16),
            label: const Text('Remove'),
          ),
        ],
      ),
    );
  }
}
