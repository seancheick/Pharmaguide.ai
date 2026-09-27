import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Sentry PHARMAGUIDE-23. GoTrue's auth stream is a broadcast subject, and a
// failed background token refresh is added to it as an error, so every
// subscriber receives it. A subscription without onError hands the error to
// the zone, and main.dart records uncaught errors as FATAL. Sentry's
// de-duplication used to hide those copies behind the app-level report; once
// that listener stopped reporting dropped refreshes, they would surface.
// Only app.dart's listener decides whether an auth error is worth a report.
void main() {
  test('every onAuthStateChange subscription handles its errors', () {
    final missing = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      final calls = RegExp(r'onAuthStateChange\s*\.listen\(');
      for (final match in calls.allMatches(source)) {
        if (!_callArguments(source, match.end - 1).contains('onError:')) {
          final line =
              '\n'.allMatches(source.substring(0, match.start)).length + 1;
          missing.add('${entity.path}:$line');
        }
      }
    }
    expect(
      missing,
      isEmpty,
      reason: 'Pass onError; app.dart _onAuthError owns reporting.',
    );
  });
}

/// A call's argument list, from its opening parenthesis to the matching
/// close. Line comments are skipped so a parenthesis in one cannot unbalance
/// the count.
String _callArguments(String source, int openParen) {
  var depth = 0;
  for (var i = openParen; i < source.length; i++) {
    if (source.startsWith('//', i)) {
      final end = source.indexOf('\n', i);
      if (end < 0) break;
      i = end;
      continue;
    }
    final char = source[i];
    if (char == '(') depth++;
    if (char == ')' && --depth == 0) return source.substring(openParen, i + 1);
  }
  return source.substring(openParen);
}
