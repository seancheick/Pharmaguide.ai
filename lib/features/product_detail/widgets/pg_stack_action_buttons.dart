import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/widgets/pg_haptics.dart';
import 'package:pharmaguide/core/widgets/verdict_badge.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/product_detail/widgets/safety_check_sheet.dart';
import 'package:pharmaguide/features/stack/providers/stack_providers.dart';

/// Sticky action bar at the bottom of the product detail screen.
///
/// Spec: INITIATIVE_PRODUCT_TRUST_AND_IA.md, Sprint 1, T1.15
/// (T8 follow-up 2026-04-29 — Log Dose secondary button removed
/// from this widget per `INITIATIVE_PRODUCT_DETAIL_CLEANUP.md` S2.1).
///
/// Conditional primary button per state:
///   - **Unsafe verdict (BLOCKED / UNSAFE):** "See safer alternatives" —
///     onTap scrolls the screen to the Better Alternatives section
///     (the screen wires the actual scroll via [onSeeAlternatives]).
///   - **Already in stack:** [_InStackPanel] with Remove inline.
///   - **Default (safe, not in stack):** "Add to my stack" — runs the
///     safety-check sheet → addProduct flow (unchanged from V0).
///
/// Log Dose lives on the stack screen now — the product page is for
/// "should I add this?" decisions, not "I just took my dose"
/// telemetry. Trying to do both burned the bottom action bar with
/// two buttons users were equally likely to mis-tap.
///
/// **2026-04-30 — auto-collapsing in-stack bar.** Sean's feedback: the
/// green "In your stack | Remove" pill was persistent (rendered for as
/// long as the user stayed on the page). *"It should be present for
/// maybe 2 seconds, 3 seconds max, and then disappear."* The widget
/// now owns the bar's chrome (padding, surface bg, top border) so the
/// whole bar — pill AND chrome — cross-fades to height 0 after a 3s
/// confirmation window. To remove a product after the window expires
/// the user navigates to the Stack tab.
class PGStackActionButtons extends ConsumerStatefulWidget {
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
  ConsumerState<PGStackActionButtons> createState() =>
      _PGStackActionButtonsState();
}

class _PGStackActionButtonsState extends ConsumerState<PGStackActionButtons> {
  static const Duration _inStackVisibleWindow = Duration(seconds: 3);

  /// True once the in-stack confirmation window has elapsed and the
  /// whole bar should collapse. Reset back to false when the entry
  /// transitions away (user removed) or the watched entry id changes.
  bool _inStackDismissed = false;

  /// Last seen entry id, used to detect transitions and re-arm the
  /// dismiss timer for newly-added products.
  String? _lastEntryId;

  Timer? _dismissTimer;

  @override
  void dispose() {
    _dismissTimer?.cancel();
    super.dispose();
  }

  /// Reconcile internal state with the latest [entryId]. Called from
  /// build via a post-frame callback so we don't setState during build.
  void _syncWithEntry(String? entryId) {
    if (entryId == _lastEntryId) return;
    _lastEntryId = entryId;
    _dismissTimer?.cancel();
    if (entryId == null) {
      // Removed (or never was in stack) — wipe dismissed flag so the
      // next add starts a fresh window.
      if (_inStackDismissed) {
        setState(() => _inStackDismissed = false);
      }
    } else {
      // New / different entry — show the pill again and re-arm.
      if (_inStackDismissed) {
        setState(() => _inStackDismissed = false);
      }
      _dismissTimer = Timer(_inStackVisibleWindow, () {
        if (mounted) setState(() => _inStackDismissed = true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final entryAsync = ref.watch(stackEntryForDsldIdProvider(widget.dsldId));

    // Schedule reconciliation post-frame so setState fires on the next
    // frame rather than during build.
    entryAsync.whenData((entry) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncWithEntry(entry?.id);
      });
    });

    final entry = entryAsync.valueOrNull;
    // The in-stack-and-dismissed state is the only one where the bar
    // collapses entirely. Unsafe overrides everything (always show the
    // "See safer alternatives" CTA).
    final shouldCollapse =
        !widget.isUnsafe && entry != null && _inStackDismissed;

    return AnimatedCrossFade(
      duration: const Duration(milliseconds: 250),
      sizeCurve: Curves.easeOutCubic,
      crossFadeState: shouldCollapse
          ? CrossFadeState.showSecond
          : CrossFadeState.showFirst,
      firstChild: _buildBar(context, entryAsync),
      // Width=infinity keeps the cross-fade size stable so the
      // animation only transitions vertically.
      secondChild: const SizedBox(width: double.infinity, height: 0),
    );
  }

  /// The bar with full chrome (padding, surface bg, top border) wrapped
  /// around whichever primary widget the current state demands.
  Widget _buildBar(
    BuildContext context,
    AsyncValue<UserStacksLocalData?> entryAsync,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.fromLTRB(
        AppTheme.space20,
        AppTheme.space12,
        AppTheme.space20,
        MediaQuery.of(context).padding.bottom + AppTheme.space12,
      ),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          top: BorderSide(color: scheme.outlineVariant, width: 0.5),
        ),
      ),
      child: _primary(context, entryAsync),
    );
  }

  Widget _primary(
    BuildContext context,
    AsyncValue<UserStacksLocalData?> entryAsync,
  ) {
    // Unsafe always wins over in-stack — even if the user already has
    // the product in their stack, the right primary action is to
    // direct them to safer alternatives, not let them re-open the
    // remove flow as the loudest button.
    if (widget.isUnsafe) {
      return _SeeSaferButton(
        onTap: () {
          PGHaptics.press();
          widget.onSeeAlternatives?.call();
        },
      );
    }
    return entryAsync.when(
      loading: () => const _LoadingPrimary(),
      error: (_, __) => _AddButton(onTap: () => _handleAdd(context)),
      data: (entry) {
        if (entry != null) {
          return _InStackPanel(
            entryId: entry.id,
            onRemove: () => _handleRemove(context, entry.id),
          );
        }
        return _AddButton(onTap: () => _handleAdd(context));
      },
    );
  }

  // ---------------------------------------------------------------------
  // Add flow — unchanged from V0 per T1.15 acceptance:
  // "Tap [Add to Stack] → existing flow (no behavior change)".
  // ---------------------------------------------------------------------
  Future<void> _handleAdd(BuildContext context) async {
    await PGHaptics.press();

    // Fetch the product up front so we can pass its name into the sheet
    // and into the addProduct call on confirm.
    final coreDb = ref.read(coreDatabaseProvider);
    ProductsCoreData? product;
    try {
      product = await coreDb.findById(widget.dsldId);
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
      dsldId: widget.dsldId,
      productName: product.productName,
    );
    if (!confirmed || !context.mounted) return;

    final actions = ref.read(stackActionsProvider);
    try {
      await actions.addProduct(product);
    } on Exception {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not add to stack.')));
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
  // Remove flow (with undo) — unchanged from V0.
  // ---------------------------------------------------------------------
  Future<void> _handleRemove(BuildContext context, String entryId) async {
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
        // Sean 2026-04-30 — was 5s, felt persistent. Floating snackbars
        // are swipe-to-dismiss by default, so 3s + swipe gives the
        // user enough time to hit Undo without the bar lingering.
        duration: const Duration(seconds: 3),
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
        backgroundColor: AppTheme.severityAvoid,
        foregroundColor: Colors.white,
      ),
      icon: const Icon(Icons.shield_outlined, size: 20),
      label: const Text('See safer alternatives'),
    );
  }
}

/// Green pill confirming the product is in the user's stack, with an
/// inline Remove affordance. Auto-dismiss timing lives one level up
/// in [PGStackActionButtons] so the entire bar (chrome included) can
/// collapse cleanly after the 3s window — see the doc on that class.
class _InStackPanel extends StatelessWidget {
  final String entryId;
  final VoidCallback onRemove;

  const _InStackPanel({required this.entryId, required this.onRemove});

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
