// The About caption showed "build 1" while the installed binary was build 17
// (2026-08-29): the caption was a hardcoded literal and pubspec had moved on.
// These tests read pubspec.yaml directly so any future drift between the
// displayed constants and the real bundle version fails CI instead of
// shipping a lie.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/utils/app_version.dart';

void main() {
  test('kAppVersion and kAppBuildNumber match pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsLinesSync();
    final versionLine = pubspec.firstWhere(
      (line) => line.trimLeft().startsWith('version:'),
      orElse: () => fail('pubspec.yaml has no version: line'),
    );
    final raw = versionLine.split(':').last.trim();
    final parts = raw.split('+');
    expect(parts, hasLength(2),
        reason: 'pubspec version must be semver+build, got "$raw"');

    expect(kAppVersion, parts[0],
        reason: 'kAppVersion drifted from pubspec.yaml — update both together');
    expect(kAppBuildNumber, int.parse(parts[1]),
        reason:
            'kAppBuildNumber drifted from pubspec.yaml — update both together');
  });
}
