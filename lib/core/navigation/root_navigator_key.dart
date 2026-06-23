import 'package:flutter/widgets.dart';

/// Root navigator key wired into the app's GoRouter.
///
/// Sentry PHARMAGUIDE-15: sheets launched from router-level callbacks
/// (e.g. the AuthInvitation route's `onEmail`) captured the route
/// pageBuilder's context, which can be deactivated or sit above the
/// Navigator by the time the user taps — crashing with "Navigator
/// operation requested with a context that does not include a
/// Navigator." Resolving through this key always yields a live context
/// under the root navigator.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'pg-root-navigator',
);
