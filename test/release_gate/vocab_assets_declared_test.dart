// Release gate: every controlled-vocab loader must point at a bundled asset.
//
// This catches the merge-miss class where a new `assets/data/*_vocab.json`
// file and loader exist, but pubspec.yaml does not declare the asset, causing
// VocabRegistry startup to fail at runtime.
//
// Run with: flutter test test/release_gate/vocab_assets_declared_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('release gate: controlled vocab assets', () {
    final vocabLoaderDir = Directory('lib/core/data');
    final pubspecFile = File('pubspec.yaml');

    test('every loader asset path is declared in pubspec.yaml', () {
      expect(vocabLoaderDir.existsSync(), isTrue);
      expect(pubspecFile.existsSync(), isTrue);

      final pubspec = pubspecFile.readAsStringSync();
      final assetPaths = <String>{};
      final pathPattern = RegExp(r'assets/data/[a-z0-9_]+_vocab\.json');

      for (final entity in vocabLoaderDir.listSync()) {
        if (entity is! File || !entity.path.endsWith('_vocab.dart')) {
          continue;
        }

        final source = entity.readAsStringSync();
        assetPaths.addAll(pathPattern.allMatches(source).map((m) => m[0]!));
      }

      expect(
        assetPaths,
        isNotEmpty,
        reason:
            'No controlled-vocab asset paths were found in lib/core/data. '
            'The release gate may need updating if loader layout changed.',
      );

      final missing = <String>[];
      for (final path in assetPaths.toList()..sort()) {
        expect(
          File(path).existsSync(),
          isTrue,
          reason: 'Loader references a missing controlled-vocab asset: $path',
        );

        if (!RegExp(
          r'^\s*-\s+' + RegExp.escape(path) + r'\s*$',
          multiLine: true,
        ).hasMatch(pubspec)) {
          missing.add(path);
        }
      }

      expect(
        missing,
        isEmpty,
        reason:
            'Every assets/data/*_vocab.json referenced by lib/core/data '
            'must be declared under flutter.assets in pubspec.yaml.',
      );
    });
  });
}
