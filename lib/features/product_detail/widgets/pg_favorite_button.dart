// Wishlist heart for product detail app bar.
//
// Guests cannot save — tap routes to the production auth invitation
// (same path as stack "Add to my stack"). Signed-in users toggle an
// on-device favorites row via [favoritesActionsProvider].

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/components/pg_toast.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/core/widgets/pg_haptics.dart';
import 'package:pharmaguide/features/stack/providers/active_stack_provider.dart';
import 'package:pharmaguide/features/stack/providers/favorites_providers.dart';
import 'package:pharmaguide/services/auth_state_service.dart';
import 'package:pharmaguide/services/crash_reporting_service.dart';

/// App-bar heart that saves the product to Wishlist when signed in.
class PGFavoriteButton extends ConsumerStatefulWidget {
  final String dsldId;

  const PGFavoriteButton({super.key, required this.dsldId});

  @override
  ConsumerState<PGFavoriteButton> createState() => _PGFavoriteButtonState();
}

class _PGFavoriteButtonState extends ConsumerState<PGFavoriteButton> {
  bool _isUpdating = false;

  @override
  Widget build(BuildContext context) {
    final authMode = ref.watch(authStateProvider);
    final isGuest = authMode == AuthMode.guest;
    final savedAsync = ref.watch(isFavoriteProvider(widget.dsldId));
    final isSaved = !isGuest && (savedAsync.asData?.value ?? false);
    final label = isSaved ? 'Remove from Wishlist' : 'Save to Wishlist';

    return Semantics(
      button: true,
      toggled: isSaved,
      label: label,
      child: IconButton(
        key: const Key('product-favorite-heart'),
        tooltip: label,
        icon: Icon(
          isSaved ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          color: isSaved ? context.v2.accent : context.v2.fg,
        ),
        onPressed: _isUpdating
            ? null
            : () => unawaited(_onTap(isGuest: isGuest)),
      ),
    );
  }

  Future<void> _onTap({required bool isGuest}) async {
    if (_isUpdating) return;
    setState(() => _isUpdating = true);
    unawaited(PGHaptics.press());

    try {
      // Guests never touch the DB — prompt sign-in first.
      if (isGuest) {
        await context.push(Routes.authInvitation);
        return;
      }

      final actions = ref.read(favoritesActionsProvider);
      final nowSaved = await actions.toggle(widget.dsldId);
      if (!mounted) return;
      if (nowSaved) {
        unawaited(PGHaptics.success());
        PGToast.show(
          context,
          'Saved to Wishlist',
          variant: PGToastVariant.success,
          duration: const Duration(seconds: 3),
          actionLabel: 'View',
          onAction: () => context.go('${Routes.stack}?tab=wishlist'),
        );
      } else {
        PGToast.show(
          context,
          'Removed from Wishlist',
          variant: PGToastVariant.info,
          duration: const Duration(seconds: 2),
        );
      }
    } on StackRequiresSignInException {
      // Session can flip mid-tap; match stack-add auth handoff.
      if (!mounted) return;
      await context.push(Routes.authInvitation);
    } on Exception catch (e, st) {
      CrashReportingService().recordError(e, st, hint: 'wishlist:toggle');
      if (!mounted) return;
      PGToast.show(
        context,
        'Could not update Wishlist.',
        variant: PGToastVariant.error,
      );
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }
}
