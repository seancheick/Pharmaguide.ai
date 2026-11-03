import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';

/// Hides the screen whenever the app isn't in front, so the app switcher's
/// preview shows the logo and not someone's health data (ADR-013).
///
/// The app counts as not in front from `inactive`, because the switcher draws
/// its live preview in that state. System sheets over the app, such as a
/// permission prompt or Face ID, cause the same state and show the cover behind
/// them. The child stays mounted, so the app is as it was on return.
class AppSwitcherCover extends StatefulWidget {
  const AppSwitcherCover({required this.child, super.key});

  static const coverKey = Key('app_switcher_cover');

  final Widget child;

  @override
  State<AppSwitcherCover> createState() => _AppSwitcherCoverState();
}

class _AppSwitcherCoverState extends State<AppSwitcherCover>
    with WidgetsBindingObserver {
  bool _covered = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _covered = state != null && state != AppLifecycleState.resumed;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final covered = state != AppLifecycleState.resumed;
    if (covered != _covered) setState(() => _covered = covered);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.passthrough,
      children: [
        ExcludeSemantics(excluding: _covered, child: widget.child),
        if (_covered)
          Positioned.fill(
            key: AppSwitcherCover.coverKey,
            child: ExcludeSemantics(
              child: ColoredBox(
                color: context.v2.bg,
                child: Center(
                  child: Image.asset(
                    'assets/images/splash_logo.png',
                    width: 56,
                    height: 56,
                    filterQuality: FilterQuality.high,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
