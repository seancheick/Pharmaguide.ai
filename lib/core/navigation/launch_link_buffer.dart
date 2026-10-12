import 'package:flutter/widgets.dart';
import 'package:pharmaguide/app.dart' show normalizePharmaGuideDeepLink;

/// Holds a link that arrives while the startup screen is showing.
///
/// Until the catalog opens, `main.dart` shows a plain [MaterialApp] with no
/// route generator. iOS often delivers the link that opened the app (a
/// product link, the magic-link sign-in callback) a moment after launch, so
/// it reached that MaterialApp, raised "Could not find a generator for
/// route" and was lost (Sentry PHARMAGUIDE-27). This observer, registered
/// before the startup MaterialApp, claims the link instead; the app router
/// then opens on it.
class LaunchLinkBuffer with WidgetsBindingObserver {
  String? _location;
  bool _attached = false;

  void attach() {
    if (_attached) return;
    _attached = true;
    WidgetsBinding.instance.addObserver(this);
  }

  /// Stop claiming links; the app router handles them from here on.
  void detach() {
    if (!_attached) return;
    _attached = false;
    WidgetsBinding.instance.removeObserver(this);
  }

  /// The buffered location, handed over once.
  String? takeLocation() {
    final location = _location;
    _location = null;
    return location;
  }

  @override
  Future<bool> didPushRouteInformation(RouteInformation routeInformation) {
    if (!_attached) return Future.value(false);
    final uri = routeInformation.uri;
    _location = normalizePharmaGuideDeepLink(uri) ?? _pathOf(uri);
    return Future.value(true);
  }

  static String _pathOf(Uri uri) {
    final path = uri.path.isEmpty ? '/' : uri.path;
    return uri.hasQuery ? '$path?${uri.query}' : path;
  }
}
