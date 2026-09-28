import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// iOS Settings › Accessibility › Display & Text Size › Reduce Transparency.
///
/// Flutter's `AccessibilityFeatures` carries Reduce Motion, Increase
/// Contrast and Bold Text but not this one, so the iOS runner
/// (`AppDelegate.swift`) reports it on [channel] and pushes changes.
/// Every blur surface (frosted nav bar, frosted header, glass tab bar)
/// reads [of] and swaps its blur for a solid fill when it is on, as the
/// native materials do. Always off on other platforms.
abstract final class ReduceTransparency {
  static const channel = MethodChannel('pharmaguide/accessibility');

  /// The app-wide value; [ReduceTransparencyScope] exposes it to widgets.
  static final ValueNotifier<bool> enabled = ValueNotifier(false);

  /// Reads the current setting and subscribes to changes. Safe to call
  /// before `runApp`; a runner without the channel leaves it off.
  static Future<void> listen() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'reduceTransparencyChanged') {
        enabled.value = call.arguments == true;
      }
    });
    try {
      enabled.value =
          await channel.invokeMethod<bool>('reduceTransparency') ?? false;
    } on MissingPluginException {
      // Test hosts and older runners: keep the default.
    } on PlatformException {
      // Same.
    }
  }

  /// Whether blur surfaces should render solid. Rebuilds [context] when
  /// the setting changes; false when no scope is mounted.
  static bool of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<ReduceTransparencyScope>()
          ?.notifier
          ?.value ??
      false;
}

/// Mounted once in the `MaterialApp.router` builder over
/// [ReduceTransparency.enabled]; tests mount their own notifier.
class ReduceTransparencyScope extends InheritedNotifier<ValueNotifier<bool>> {
  const ReduceTransparencyScope({
    super.key,
    required ValueNotifier<bool> super.notifier,
    required super.child,
  });
}
