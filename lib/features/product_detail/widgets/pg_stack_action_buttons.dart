import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/core/widgets/pg_haptics.dart';
import 'package:pharmaguide/core/widgets/verdict_badge.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/product_detail/widgets/safety_check_sheet.dart';
import 'package:pharmaguide/features/stack/providers/stack_providers.dart';

/// Sticky action bar at the bottom of the product detail screen.
///
/// The bar is **persistent** — once a product is in the user's stack,
/// the green "In your stack | Remove" pill stays visible so the user
/// can remove without leaving the page. The 3s ephemeral confirmation
/// lives on the snackbar; the bar itself does not auto-collapse.
///
/// Conditional primary button per state:
///   - **Unsafe verdict (BLOCKED / UNSAFE):** "See safer alternatives" —
///     onTap scrolls the screen to the Better Alternatives section
///     (the screen wires the actual scroll via [onSeeAlternatives]).
///   - **Already in stack:** [_InStackPanel] with Remove inline.
///   - **Default (safe, not in stack):** "Add to my stack" — runs the
///     safety-check sheet → addProduct flow.
class PGStackActionButtons extends ConsumerWidget {
  final String dsldId;

  /// True when the product carries a BLOCKED or UNSAFE verdict —
  /// caller passes `isUnsafeVerdict(_product?.verdict)`. Drives the
  /// "See safer alternatives" primary swap.
  final bool isUnsafe;

  /// Tap target when the unsafe-state primary fires. Screen wires
  /// this to scroll the page to the Better Alternatives section.
  /// No-op if null.
  final VoidCallback? onSeeAlternatives;

  const PGStackActionButtons({
    super.key,
    required this.dsldId,
    this.isUnsafe = false,
    this.onSeeAlternatives,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entryAsync = ref.watch(stackEntryForDsldIdProvider(dsldId));
    return Container(
      padding: EdgeInsets.fromLTRB(
        V2Spacing.space24,
        V2Spacing.space12,
        V2Spacing.space24,
        MediaQuery.of(context).padding.bottom + V2Spacing.space12,
      ),
      decoration: const BoxDecoration(
        color: V2Colors.surface,
        border: Border(top: BorderSide(color: V2Colors.outline)),
      ),
      child: _primary(context, ref, entryAsync),
    );
  }

  Widget _primary(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<UserStacksLocalData?> entryAsync,
  ) {
    // Unsafe always wins over in-stack — even if the user already has
    // the product in their stack, the right primary action is to
    // direct them to safer alternatives, not let them re-open the
    // remove flow as the loudest button.
    if (isUnsafe) {
      return _SeeSaferButton(
        onTap: () {
          PGHaptics.press();
          onSeeAlternatives?.call();
        },
      );
    }
    return entryAsync.when(
      loading: () => const _LoadingPrimary(),
      error: (_, __) => _AddButton(onTap: () => _handleAdd(context, ref)),
      data: (entry) {
        if (entry != null) {
          return _InStackPanel(
            entryId: entry.id,
            onRemove: () => _handleRemove(context, ref, entry.id),
          );
        }
        return _AddButton(onTap: () => _handleAdd(context, ref));
      },
    );
  }

  // ---------------------------------------------------------------------
  // Add flow.
  // ---------------------------------------------------------------------
  Future<void> _handleAdd(BuildContext context, WidgetRef ref) async {
    unawaited(PGHaptics.press());

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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not load product.')));
      return;
    }

    // FLTR-16 — Safety override. Blocked/unsafe products cannot be
    // added. Short-circuit BEFORE the safety check sheet so the user
    // never sees a "no stack interactions found — safe to add" banner
    // on a banned product. The domain layer ([StackActions.addProduct])
    // will also throw for defense in depth.
    if (isUnsafeVerdict(product.verdict)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This product cannot be added due to safety concerns.'),
          duration: Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ),
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
    } on StackRequiresSignInException {
      if (!context.mounted) return;
      await context.push(Routes.authInvitation);
      return;
    } on Exception {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not add to stack.')));
      return;
    }

    unawaited(PGHaptics.success());
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Added ${product.productName} to your stack'),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'Go to Stack',
          onPressed: () => context.go(Routes.stack),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Remove flow (with undo).
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

    // Sean 2026-05-05 — `clearSnackBars()` immediately followed by
    // `showSnackBar()` was preventing auto-dismiss in practice. The
    // synchronous tear-down + queue add desyncs the new SnackBar's
    // duration timer from its display state. Calling
    // `hideCurrentSnackBar()` instead lets the existing snackbar close
    // through its normal animation path so the new timer starts cleanly.
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: const Text('Removed from stack'),
        duration: const Duration(seconds: 4),
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
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: V2Colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
      ),
      alignment: Alignment.center,
      child: const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: V2Colors.accent,
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
      style: FilledButton.styleFrom(
        backgroundColor: V2Colors.accent,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(52),
      ),
      icon: const Icon(Icons.add_rounded, size: 20),
      label: const Text('Add to my stack'),
    );
  }
}

/// Unsafe-verdict primary — replaces "Add to my stack" when the
/// product is BLOCKED or UNSAFE. Tap scrolls the screen to the
/// Better Alternatives section.
class _SeeSaferButton extends StatelessWidget {
  final VoidCallback onTap;
  const _SeeSaferButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: V2Colors.avoid,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(52),
      ),
      icon: const Icon(Icons.shield_outlined, size: 20),
      label: const Text('See safer alternatives'),
    );
  }
}

/// Green pill confirming the product is in the user's stack, with an
/// inline Remove affordance. Persistent — does not auto-collapse.
class _InStackPanel extends StatelessWidget {
  final String entryId;
  final VoidCallback onRemove;

  const _InStackPanel({required this.entryId, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: V2Spacing.space16),
      decoration: BoxDecoration(
        color: V2Colors.safeTint,
        borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
        border: Border.all(
          color: V2Colors.safe.withValues(alpha: 0.22),
          width: 0.8,
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle_outline_rounded,
            size: 20,
            color: V2Colors.safe,
          ),
          const SizedBox(width: V2Spacing.space8),
          Text(
            'In your stack',
            style: V2Typography.label(color: V2Colors.safe),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: onRemove,
            style: TextButton.styleFrom(
              foregroundColor: V2Colors.fgMuted,
              padding: const EdgeInsets.symmetric(
                horizontal: V2Spacing.space12,
                vertical: V2Spacing.space8,
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
