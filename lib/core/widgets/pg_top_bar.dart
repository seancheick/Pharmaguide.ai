import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';

/// Large-title app bar — Apple-style title that sits large at rest and
/// collapses into the small app-bar title on scroll.
///
/// Wraps `SliverAppBar.large` with the right theming so the title grows
/// in/out smoothly instead of the default M3 auto-tint behavior.
///
/// ```dart
/// CustomScrollView(
///   slivers: [
///     PGTopBar(
///       title: 'Product',
///       actions: [ IconButton(...) ],
///     ),
///     ...rest of slivers
///   ],
/// )
/// ```
class PGTopBar extends StatelessWidget {
  final String title;
  final List<Widget> actions;
  final Widget? leading;
  final bool automaticallyImplyLeading;

  /// When true, the title stays large even at rest (no small fallback).
  /// Use for root-level screens like Settings.
  final bool pinnedLarge;

  const PGTopBar({
    super.key,
    required this.title,
    this.actions = const [],
    this.leading,
    this.automaticallyImplyLeading = true,
    this.pinnedLarge = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return SliverAppBar.large(
      pinned: true,
      stretch: true,
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      scrolledUnderElevation: 0,
      foregroundColor: scheme.onSurface,
      leading: leading,
      automaticallyImplyLeading: automaticallyImplyLeading,
      actions: actions,
      expandedHeight: pinnedLarge ? 128 : 104,
      collapsedHeight: 56,
      title: Text(
        title,
        style: theme.textTheme.titleLarge?.copyWith(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
      ),
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsetsDirectional.fromSTEB(
          AppTheme.space20,
          0,
          AppTheme.space20,
          AppTheme.space16,
        ),
        expandedTitleScale: 1.8,
        title: Text(
          title,
          style: theme.textTheme.headlineLarge?.copyWith(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
      ),
    );
  }
}
