// Safety invariant: the scanned barcode never reaches a Sentry breadcrumb.
//
// The failed-scan privacy contract (failed_scans_table.dart +
// CrashReportingService) is that the UPC is persisted ON-DEVICE ONLY —
// aggregate counts, no user identifier — and is never sent to Sentry.
// CrashReportingService._scrubBreadcrumb scrubs the breadcrumb DATA MAP
// but not the MESSAGE, so interpolating the barcode into a log() call
// (e.g. `log('scan_failed_missing_upc: $upc')`) ships the raw scanned
// code to Sentry, violating the service's own contract.
//
// This static-scan test (same pattern as failed_scans_no_pii_test.dart)
// locks every `CrashReportingService().log(...)` call in the scanner
// screen down to constant string literals: no `$` interpolation, no
// expressions outside quotes. Breadcrumbs are event names, not payloads.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _scannerScreenPath = 'lib/features/scanner/scanner_screen.dart';

/// Everything in [arg] that sits OUTSIDE single-quoted string literals.
/// For a compliant constant-literal breadcrumb this is only whitespace
/// (adjacent-literal concatenation across lines is fine).
String _outsideQuotes(String arg) {
  final buf = StringBuffer();
  var inString = false;
  for (var i = 0; i < arg.length; i++) {
    final c = arg[i];
    if (c == "'") {
      inString = !inString;
      continue;
    }
    if (!inString) buf.write(c);
  }
  return buf.toString();
}

void main() {
  group('Safety invariant: scanner breadcrumbs carry no scanned barcode', () {
    test(
      'every CrashReportingService().log() call uses a constant message',
      () {
        final file = File(_scannerScreenPath);
        expect(
          file.existsSync(),
          isTrue,
          reason:
              'Expected $_scannerScreenPath to exist. If the scanner screen '
              'moved, update this test to point at the new file.',
        );
        final source = file.readAsStringSync();

        final logCalls = RegExp(
          r'CrashReportingService\(\)\s*\.log\(([^;]*?)\)\s*;',
          dotAll: true,
        ).allMatches(source).toList();

        expect(
          logCalls,
          isNotEmpty,
          reason:
              'No CrashReportingService().log calls found — if the '
              'breadcrumb API or call style changed, update this scan so '
              'the invariant keeps being enforced.',
        );

        for (final match in logCalls) {
          final arg = match.group(1)!;

          expect(
            arg.contains(r'$'),
            isFalse,
            reason:
                'Breadcrumb message interpolates a value: `log($arg)`. '
                'Breadcrumb MESSAGES are not scrubbed (_scrubBreadcrumb '
                'only scrubs the data map), so the scanned barcode must '
                'never be interpolated — log the event name only. The '
                'local failed-scan sensor already persists the UPC '
                'on-device.',
          );

          expect(
            _outsideQuotes(arg).trim(),
            isEmpty,
            reason:
                'Breadcrumb message must be a constant string literal, '
                'not an expression: `log($arg)`. Concatenating or passing '
                'variables can leak the scanned barcode to Sentry.',
          );
        }
      },
    );

    test('the historical leak pattern is gone', () {
      final source = File(_scannerScreenPath).readAsStringSync();
      expect(
        source.contains(r'scan_failed_missing_upc: $'),
        isFalse,
        reason:
            'scan_failed_missing_upc must be logged WITHOUT the barcode — '
            'the raw UPC in a breadcrumb message reaches Sentry unscrubbed.',
      );
    });
  });
}
