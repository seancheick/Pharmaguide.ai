// SPIKE SHIM for `package:flutter/foundation.dart` (server-side engine build).
//
// The engine files only use annotations and a few helpers from foundation.
// Real Flutter's foundation pulls in dart:ui, which neither `dart compile js`
// nor `dart compile exe` can build. Production fix: engine files import
// `package:meta/meta.dart` (and `package:collection`) directly instead.
export 'package:meta/meta.dart'
    show immutable, visibleForTesting, protected, mustCallSuper, required;

const bool kDebugMode = false;
const bool kReleaseMode = true;
const bool kProfileMode = false;
const bool kIsWeb = false;

void debugPrint(String? message, {int? wrapWidth}) {
  if (message != null) print(message);
}

bool listEquals<T>(List<T>? a, List<T>? b) {
  if (a == null) return b == null;
  if (b == null || a.length != b.length) return false;
  if (identical(a, b)) return true;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool setEquals<T>(Set<T>? a, Set<T>? b) {
  if (a == null) return b == null;
  if (b == null || a.length != b.length) return false;
  return a.containsAll(b);
}

bool mapEquals<K, V>(Map<K, V>? a, Map<K, V>? b) {
  if (a == null) return b == null;
  if (b == null || a.length != b.length) return false;
  for (final key in a.keys) {
    if (!b.containsKey(key) || b[key] != a[key]) return false;
  }
  return true;
}
