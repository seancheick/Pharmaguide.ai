import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
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
