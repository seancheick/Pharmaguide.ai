// Release gate: the AI brief is composed and shared entirely on the device.
//
// The brief can carry medications, conditions and PharmaGuide findings when
// the user switches them on. ADR-009 allows that data to leave the device
// only through the user's own paste into an assistant, never through a
// PharmaGuide network call. This static scan pins the whole path:
//
//   1. The renderer and its inputs are pure Dart: no Flutter, Riverpod,
//      Drift, network or Supabase imports.
//   2. The preview screen that shows the text imports no network client.
//   3. `ShareService.shareAiBrief` is a pass-through to the system share
//      sheet: it never mints a link or performs an HTTP call.
//
// Nothing here talks to the network or Drift. It is a file-system scan so it
// runs in milliseconds and cannot flake.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _pureFiles = <String>[
  'lib/services/sharing/ai_brief_builder.dart',
  'lib/services/sharing/ai_share_scope.dart',
  'lib/services/sharing/clinician_report_data.dart',
  'lib/services/sharing/report_text.dart',
];

const _previewScreen =
    'lib/features/stack/widgets/ai_brief_preview_screen.dart';
const _shareService = 'lib/services/sharing/share_service.dart';

final _networkImport = RegExp(
  r"^import\s+'(package:http/|package:dio/|package:supabase|dart:io)",
  multiLine: true,
);
final _frameworkImport = RegExp(
  r"^import\s+'(package:flutter/|package:flutter_riverpod/|package:drift/)",
  multiLine: true,
);

void main() {
  group('release gate: AI brief never leaves the device by itself', () {
    for (final path in _pureFiles) {
      test('$path imports no framework or network code', () async {
        final source = await File(path).readAsString();
        expect(
          _networkImport.hasMatch(source),
          isFalse,
          reason: '$path must not import a network client',
        );
        expect(
          _frameworkImport.hasMatch(source),
          isFalse,
          reason: '$path must stay pure Dart so the export is testable',
        );
      });
    }

    test('the preview screen imports no network client', () async {
      final source = await File(_previewScreen).readAsString();
      expect(_networkImport.hasMatch(source), isFalse);
      expect(source, isNot(contains('supabase')));
    });

    test('ShareService.shareAiBrief is a pure pass-through', () async {
      final source = await File(_shareService).readAsString();
      final start = source.indexOf('Future<void> shareAiBrief(');
      expect(start, isNonNegative, reason: 'shareAiBrief must exist');
      final end = source.indexOf('\n}', start);
      final body = source.substring(start, end);
      expect(body, isNot(contains('_mintShareLink')));
      expect(body, isNot(contains('http.')));
      expect(body, isNot(contains('Uri.parse')));
      expect(body, contains('_share('));
    });
  });
}
