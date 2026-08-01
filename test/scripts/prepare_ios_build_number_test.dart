import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;
  late File pubspec;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync(
      'pharmaguide-build-number-test-',
    );
    pubspec = File('${tempDir.path}/pubspec.yaml')
      ..writeAsStringSync('name: test_app\nversion: 1.0.0+14\n');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  Future<ProcessResult> prepare({required int latestSuccessfulBuild}) {
    return Process.run(
      'bash',
      ['scripts/prepare_ios_build_number.sh', pubspec.path],
      environment: {
        ...Platform.environment,
        'PHARMAGUIDE_LATEST_IPA_BUILD': '$latestSuccessfulBuild',
      },
    );
  }

  File createIpa({required String name, required int buildNumber}) {
    final packageRoot = Directory('${tempDir.path}/$name')..createSync();
    final app = Directory('${packageRoot.path}/Payload/Runner.app')
      ..createSync(recursive: true);
    File('${app.path}/Info.plist').writeAsStringSync('''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleShortVersionString</key>
  <string>1.0.0</string>
  <key>CFBundleVersion</key>
  <string>$buildNumber</string>
</dict>
</plist>
''');
    final ipa = File('${tempDir.path}/$name.ipa');
    final zipResult = Process.runSync('zip', [
      '-q',
      '-r',
      ipa.path,
      'Payload',
    ], workingDirectory: packageRoot.path);
    expect(zipResult.exitCode, 0, reason: '${zipResult.stderr}');
    return ipa;
  }

  File createExecutable(String name, String body) {
    final file = File('${tempDir.path}/$name')..writeAsStringSync(body);
    final chmodResult = Process.runSync('chmod', ['+x', file.path]);
    expect(chmodResult.exitCode, 0, reason: '${chmodResult.stderr}');
    return file;
  }

  Future<ProcessResult> buildWith(File fakeFlutter) {
    return Process.run(
      'bash',
      ['scripts/build_ios_release.sh', fakeFlutter.path],
      environment: {
        ...Platform.environment,
        'PHARMAGUIDE_IOS_BUILD_ROOT': tempDir.path,
      },
    );
  }

  test(
    'advances when the current build number already has a successful IPA',
    () async {
      final result = await prepare(latestSuccessfulBuild: 14);

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(pubspec.readAsStringSync(), contains('version: 1.0.0+15'));
    },
  );

  test(
    'preserves a reserved build number while retrying a failed export',
    () async {
      final result = await prepare(latestSuccessfulBuild: 13);

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(pubspec.readAsStringSync(), contains('version: 1.0.0+14'));
    },
  );

  test(
    'catches up when the local pubspec is behind the successful IPA',
    () async {
      final result = await prepare(latestSuccessfulBuild: 19);

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(pubspec.readAsStringSync(), contains('version: 1.0.0+20'));
    },
  );

  test(
    'fails when Flutter returns success without exporting the reserved IPA',
    () async {
      final ipaDirectory = Directory('${tempDir.path}/build/ios/ipa')
        ..createSync(recursive: true);
      createIpa(
        name: 'previous',
        buildNumber: 13,
      ).copySync('${ipaDirectory.path}/pharmaguide.ipa');
      final fakeFlutter = createExecutable('flutter', '#!/bin/bash\nexit 0\n');

      final result = await buildWith(fakeFlutter);

      expect(result.exitCode, isNot(0));
      expect(
        result.stderr,
        contains('no App Store IPA matching reserved build +14'),
      );
      expect(pubspec.readAsStringSync(), contains('version: 1.0.0+14'));
    },
  );

  test('accepts only an IPA whose build matches the reserved number', () async {
    final ipaDirectory = Directory('${tempDir.path}/build/ios/ipa')
      ..createSync(recursive: true);
    createIpa(
      name: 'previous',
      buildNumber: 13,
    ).copySync('${ipaDirectory.path}/pharmaguide.ipa');
    final expectedIpa = createIpa(name: 'expected', buildNumber: 14);
    final fakeFlutter = createExecutable('flutter', r'''
#!/bin/bash
set -eu
cp "$PHARMAGUIDE_FAKE_IPA_SOURCE" "$PHARMAGUIDE_IOS_BUILD_ROOT/build/ios/ipa/pharmaguide.ipa"
''');

    final result = await Process.run(
      'bash',
      ['scripts/build_ios_release.sh', fakeFlutter.path],
      environment: {
        ...Platform.environment,
        'PHARMAGUIDE_IOS_BUILD_ROOT': tempDir.path,
        'PHARMAGUIDE_FAKE_IPA_SOURCE': expectedIpa.path,
      },
    );

    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(pubspec.readAsStringSync(), contains('version: 1.0.0+14'));
  });
}
