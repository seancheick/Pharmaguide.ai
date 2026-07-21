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
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/widgets/pg_haptics.dart';
import 'package:pharmaguide/features/stack/providers/active_stack_provider.dart';
import 'package:pharmaguide/features/stack/providers/favorites_providers.dart';
import 'package:pharmaguide/services/auth_state_service.dart';
import 'package:pharmaguide/services/crash_reporting_service.dart';

/// App-bar heart that saves the product to Wishlist when signed in.
class PGFavoriteButton extends ConsumerWidget {
  final String dsldId;

  const PGFavoriteButton({super.key, required this.dsldId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authMode = ref.watch(authStateProvider);
    final isGuest = authMode == AuthMode.guest;
    final savedAsync = ref.watch(isFavoriteProvider(dsldId));
    final isSaved = !isGuest && (savedAsync.asData?.value ?? false);

    return IconButton(
      key: const Key('product-favorite-heart'),
      tooltip: isSaved ? 'Remove from Wishlist' : 'Save to Wishlist',
      icon: Icon(
        isSaved ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        color: isSaved ? V2Colors.contraindicated : V2Colors.fg,
      ),
      onPressed: () => unawaited(_onTap(context, ref, isGuest: isGuest)),
    );
  }

  Future<void> _onTap(
    BuildContext context,
    WidgetRef ref, {
    required bool isGuest,
  }) async {
    unawaited(PGHaptics.press());

    // Guests never touch the DB — prompt sign-in first.
    if (isGuest) {
      if (!context.mounted) return;
      await context.push(Routes.authInvitation);
      return;
    }

    final actions = ref.read(favoritesActionsProvider);
    try {
      final nowSaved = await actions.toggle(dsldId);
      if (!context.mounted) return;
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
      if (!context.mounted) return;
      await context.push(Routes.authInvitation);
    } on Exception catch (e, st) {
      CrashReportingService().recordError(e, st, hint: 'wishlist:toggle');
      if (!context.mounted) return;
      PGToast.show(
        context,
        'Could not update Wishlist.',
        variant: PGToastVariant.error,
      );
    }
  }
}
