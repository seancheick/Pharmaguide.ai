import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/core/widgets/pg_frosted_nav_bar.dart';

/// One tab: SF Symbols for Apple's bar, Material icons for the fallback.
@immutable
class PGTab {
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final String symbol;
  final String selectedSymbol;

  const PGTab({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.symbol,
    required this.selectedSymbol,
  });
}

/// The app's bottom tab bar.
///
/// - **iOS 26+:** Apple's own `UITabBar` (`ios/Runner/NativeTabBar.swift`),
///   which the system draws in Liquid Glass with its lens, springs and
///   haptics. Flutter can only imitate that material (HIG, Liquid Glass:
///   "Apple ships the material inside its system frameworks"), so the real
///   bar is hosted instead. It adapts itself to Reduce Transparency,
///   Increase Contrast, Reduce Motion and VoiceOver.
/// - **Everywhere else** (Android, iOS 18–25): [PGFrostedNavBar].
class PGTabBar extends StatelessWidget {
  final List<PGTab> tabs;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  /// Test hook. Null decides from the platform ([supportsNativeLiquidGlass]).
  final bool? nativeGlass;

  const PGTabBar({
    super.key,
    required this.tabs,
    required this.selectedIndex,
    required this.onSelected,
    this.nativeGlass,
  });

  @override
  Widget build(BuildContext context) {
    if (nativeGlass ?? supportsNativeLiquidGlass) {
      return _NativeTabBar(
        tabs: tabs,
        selectedIndex: selectedIndex,
        onSelected: onSelected,
      );
    }
    return PGFrostedNavBar(
      selectedIndex: selectedIndex,
      onDestinationSelected: onSelected,
      destinations: [
        for (final tab in tabs)
          NavigationDestination(
            icon: Icon(tab.icon),
            selectedIcon: Icon(tab.selectedIcon),
            label: tab.label,
          ),
      ],
    );
  }
}

/// iOS reports e.g. "Version 26.5 (Build 23F77)".
@visibleForTesting
int? iosMajorVersion(String operatingSystemVersion) {
  final match = RegExp(r'\d+').firstMatch(operatingSystemVersion);
  return match == null ? null : int.tryParse(match.group(0)!);
}

/// Liquid Glass ships with iOS 26.
final bool supportsNativeLiquidGlass =
    !kIsWeb &&
    Platform.isIOS &&
    (iosMajorVersion(Platform.operatingSystemVersion) ?? 0) >= 26;

/// Height of Apple's tab bar above the home indicator, matching the
/// iOS 26 floating bar.
const double _nativeBarHeight = 62;

class _NativeTabBar extends StatefulWidget {
  final List<PGTab> tabs;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const _NativeTabBar({
    required this.tabs,
    required this.selectedIndex,
    required this.onSelected,
  });

  @override
  State<_NativeTabBar> createState() => _NativeTabBarState();
}

class _NativeTabBarState extends State<_NativeTabBar> {
  static const _viewType = 'pharmaguide/tab_bar';

  MethodChannel? _channel;
  Map<String, Object>? _sentStyle;

  Map<String, Object> _style(BuildContext context) => {
    'dark': Theme.of(context).brightness == Brightness.dark,
    'tint': context.v2.accent.toARGB32(),
  };

  void _onCreated(int id) {
    _channel = MethodChannel('${_viewType}_$id')
      ..setMethodCallHandler((call) async {
        if (call.method == 'select' && call.arguments is int) {
          widget.onSelected(call.arguments as int);
        }
      });
  }

  @override
  void didUpdateWidget(_NativeTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      _channel?.invokeMethod<void>('setSelectedIndex', widget.selectedIndex);
    }
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = _style(context);
    final sent = _sentStyle;
    if (sent == null) {
      _sentStyle = style;
    } else if (!mapEquals(sent, style)) {
      _sentStyle = style;
      _channel?.invokeMethod<void>('setStyle', style);
    }

    return SizedBox(
      height: _nativeBarHeight + MediaQuery.paddingOf(context).bottom,
      child: UiKitView(
        viewType: _viewType,
        creationParams: {
          'labels': [for (final t in widget.tabs) t.label],
          'symbols': [for (final t in widget.tabs) t.symbol],
          'selectedSymbols': [for (final t in widget.tabs) t.selectedSymbol],
          'selectedIndex': widget.selectedIndex,
          ...style,
        },
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _onCreated,
        // Touches go straight to UIKit so the lens tracks the finger from
        // touch-down, as in Apple's apps.
        gestureRecognizers: {
          const Factory<OneSequenceGestureRecognizer>(
            EagerGestureRecognizer.new,
          ),
        },
      ),
    );
  }
}
