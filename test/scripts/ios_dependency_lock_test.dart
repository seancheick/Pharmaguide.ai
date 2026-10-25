import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS Podfile enables the ML Kit Apple-silicon simulator owner', () {
    final podfile = File('ios/Podfile').readAsStringSync();

    expect(
      podfile,
      contains(
        '.symlinks/plugins/google_mlkit_commons/ios/scripts/'
        'apple_silicon_simulator',
      ),
      reason:
          'ML Kit ships the simulator compatibility owner, but the Podfile '
          'must load it before pod installation',
    );
    expect(
      podfile,
      contains('mlkit_apple_silicon_simulator_patch(installer)'),
      reason:
          'post_install must apply the ML Kit owner so arm64 simulator '
          'destinations remain buildable',
    );
  });

  test('development run recipes do not echo injected configuration', () {
    final makefile = File('Makefile').readAsStringSync();
    for (final target in [
      'run',
      'run-ios',
      'run-android',
      'run-v2',
      'run-v2-ios',
      'run-v2-android',
    ]) {
      final recipe = RegExp(
        '^${RegExp.escape(target)}:.*?\n(\\t.*?DART_DEFINES.*)\$',
        multiLine: true,
      ).firstMatch(makefile)?.group(1);
      expect(recipe, isNotNull, reason: '$target must inject DART_DEFINES');
      expect(
        recipe,
        startsWith('\t@'),
        reason: '$target must not print injected configuration to the terminal',
      );
    }
  });

  test('iOS run recipe can target an exact iOS 26 simulator', () {
    final makefile = File('Makefile').readAsStringSync();

    expect(makefile, contains('IOS_DEVICE ?= iPhone'));
    expect(makefile, contains('-d "\$(IOS_DEVICE)"'));
  });

  test('iOS Firebase lock matches the resolved plugin SDK requirement', () {
    // Firebase Core owns the native SDK version shared by FlutterFire plugins.
    // Read that owner rather than pinning another SDK version in this test.
    final configFile = File('.dart_tool/package_config.json').absolute;
    final config =
        jsonDecode(configFile.readAsStringSync()) as Map<String, dynamic>;
    final packages = (config['packages'] as List).cast<Map<String, dynamic>>();
    final firebase = packages.singleWhere(
      (package) => package['name'] == 'firebase_core',
    );
    final root = Directory.fromUri(
      configFile.parent.uri.resolve(firebase['rootUri'] as String),
    ).uri;
    final sdkSource = File.fromUri(
      root.resolve('ios/firebase_sdk_version.rb'),
    ).readAsStringSync();
    final version = RegExp(
      r"'([0-9]+\.[0-9]+\.[0-9]+)'",
    ).firstMatch(sdkSource)?.group(1);
    expect(
      version,
      isNotNull,
      reason: 'Resolved Firebase plugin must declare its native SDK',
    );

    final lock = File('ios/Podfile.lock').readAsStringSync();
    for (final pod in ['Firebase/CoreOnly', 'Firebase/Messaging']) {
      expect(
        lock,
        contains('  - $pod ($version):'),
        reason:
            '$pod must match the resolved FlutterFire SDK; update the native lock after plugin upgrades',
      );
    }
  });
}
