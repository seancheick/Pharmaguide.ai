import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/widgets/pg_frosted_header.dart';
import 'package:pharmaguide/core/widgets/pg_circular_icon_button.dart';

/// Apple-grade frosted app bar — sliver variant.
///
/// Mounted as the first sliver in a `CustomScrollView`. At scroll offset 0
/// the surrounding chrome is fully transparent (looks like page material);
/// once content scrolls past below, [PGFrostedHeader] inside the delegate
/// fades in a translucent surface + bottom hairline. Settings / Mail / App
/// Store top-chrome pattern.
///
/// Use this on every sub-page (and on tab destinations that don't have a
/// pinned search) so the whole app shares the same iOS top chrome.
///
/// ```dart
/// CustomScrollView(
///   slivers: [
///     PGFrostedAppBar(title: 'My Stack'),
///     // ... rest of slivers ...
///   ],
/// )
/// ```
class PGFrostedAppBar extends StatelessWidget {
  /// The title rendered centered in the bar. Required.
  final String title;

  /// Optional widget rendered to the left of the title (replaces the
  /// default back button if set). Pass `const SizedBox.shrink()` to hide
  /// the leading slot entirely; pass null to use the default back button
  /// when `automaticallyImplyLeading` is true.
  final Widget? leading;

  /// Whether to imply a back button when [leading] is null and the route
  /// can pop. Defaults to true. Set false on tab-root screens (Stack,
  /// Settings) where there's nothing to go back to.
  final bool automaticallyImplyLeading;

  /// Optional trailing actions. Rendered to the right of the title in
  /// the order given. Typical use: a single `IconButton` for share /
  /// edit / settings.
  final List<Widget> actions;

  /// Override the blur sigma. Defaults to 30 (matches PGFrostedHeader);
  /// pass a smaller value (e.g. 18) for tab destinations where the
  /// background is more colorful and the full blur over-softens it.
  final double blurSigma;

  const PGFrostedAppBar({
    super.key,
    required this.title,
    this.leading,
    this.automaticallyImplyLeading = true,
    this.actions = const <Widget>[],
    this.blurSigma = 30,
  });

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return SliverPersistentHeader(
      pinned: true,
      delegate: _PGFrostedAppBarDelegate(
        title: title,
        leading: leading,
        automaticallyImplyLeading: automaticallyImplyLeading,
        actions: actions,
        blurSigma: blurSigma,
        topPadding: mq.padding.top,
      ),
    );
  }
}

class _PGFrostedAppBarDelegate extends SliverPersistentHeaderDelegate {
  final String title;
  final Widget? leading;
  final bool automaticallyImplyLeading;
  final List<Widget> actions;
  final double blurSigma;
  final double topPadding;

  static const double _barHeight = 44; // iOS standard nav bar content
  static const double _verticalPadding = 6;

  _PGFrostedAppBarDelegate({
    required this.title,
    required this.leading,
    required this.automaticallyImplyLeading,
    required this.actions,
    required this.blurSigma,
    required this.topPadding,
  });

  double get _height => topPadding + _verticalPadding * 2 + _barHeight;

  @override
  double get minExtent => _height;
  @override
  double get maxExtent => _height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final theme = Theme.of(context);

    Widget? leadingWidget = leading;
    if (leadingWidget == null && automaticallyImplyLeading) {
      final canPop = ModalRoute.of(context)?.canPop ?? false;
      if (canPop) {
        leadingWidget = PGCircularIconButton(
          icon: Icons.arrow_back_ios_new_rounded,
          onTap: () => Navigator.of(context).maybePop(),
        );
      }
    }

    return PGFrostedHeader(
      scrollProgress: overlapsContent ? 1.0 : 0.0,
      blurSigma: blurSigma,
      child: Padding(
        padding: EdgeInsets.only(
          top: topPadding + _verticalPadding,
          left: AppTheme.space12,
          right: AppTheme.space12,
          bottom: _verticalPadding,
        ),
        child: SizedBox(
          height: _barHeight,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Centered title — Cupertino-style.
              Center(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (leadingWidget != null)
                Align(alignment: Alignment.centerLeft, child: leadingWidget),
              if (actions.isNotEmpty)
                Align(
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: actions,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _PGFrostedAppBarDelegate oldDelegate) {
    return oldDelegate.title != title ||
        oldDelegate.leading != leading ||
        oldDelegate.automaticallyImplyLeading != automaticallyImplyLeading ||
        oldDelegate.actions.length != actions.length ||
        oldDelegate.blurSigma != blurSigma ||
        oldDelegate.topPadding != topPadding;
  }
}
