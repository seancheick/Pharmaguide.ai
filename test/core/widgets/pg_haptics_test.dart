import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/scoring/catalog_product_semantics.dart';
import 'package:pharmaguide/core/widgets/pg_haptics.dart';

/// Captures `HapticFeedback.*` platform-channel calls so tests can assert the
/// exact sequence of intensities a chained pattern produces.
class _HapticCallRecorder {
  final calls = <String>[];

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            calls.add(
              call.arguments as String? ?? 'HapticFeedbackType.vibrate',
            );
          }
          return null;
        });
  }

  void uninstall() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _HapticCallRecorder recorder;

  setUp(() {
    recorder = _HapticCallRecorder()..install();
  });

  tearDown(() {
    recorder.uninstall();
  });

  group('PGHaptics single-pulse helpers', () {
    test('success fires lightImpact', () async {
      await PGHaptics.success();
      expect(recorder.calls, ['HapticFeedbackType.lightImpact']);
    });

    test('warning fires mediumImpact', () async {
      await PGHaptics.warning();
      expect(recorder.calls, ['HapticFeedbackType.mediumImpact']);
    });

    test('danger fires heavyImpact', () async {
      await PGHaptics.danger();
      expect(recorder.calls, ['HapticFeedbackType.heavyImpact']);
    });
  });

  group('PGHaptics chained patterns', () {
    test('successPattern fires light → medium (di-DUP)', () async {
      await PGHaptics.successPattern();
      expect(recorder.calls, [
        'HapticFeedbackType.lightImpact',
        'HapticFeedbackType.mediumImpact',
      ]);
    });

    test('errorPattern fires medium → medium → heavy (di-da-DUP)', () async {
      await PGHaptics.errorPattern();
      expect(recorder.calls, [
        'HapticFeedbackType.mediumImpact',
        'HapticFeedbackType.mediumImpact',
        'HapticFeedbackType.heavyImpact',
      ]);
    });

    testWidgets('successPattern is a no-op under reduce-motion', (
      tester,
    ) async {
      late BuildContext capturedContext;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Builder(
            builder: (ctx) {
              capturedContext = ctx;
              return const SizedBox();
            },
          ),
        ),
      );
      await PGHaptics.successPattern(capturedContext);
      expect(
        recorder.calls,
        isEmpty,
        reason: 'reduce-motion suppresses decorative haptic patterns',
      );
    });

    test(
      'errorPattern fires even under reduce-motion (safety-critical)',
      () async {
        // errorPattern doesn't accept context — it's always-fires by design.
        await PGHaptics.errorPattern();
        expect(recorder.calls.length, 3);
      },
    );
  });

  group('PGHaptics.forSafetyStatus mapping', () {
    test(
      'a clean catalog product plays the success pattern (di-DUP)',
      () async {
        await PGHaptics.forSafetyStatus(
          CatalogProductSafetyStatus.noKnownCatalogConcern,
        );
        expect(recorder.calls, [
          'HapticFeedbackType.lightImpact',
          'HapticFeedbackType.mediumImpact',
        ]);
      },
    );

    test('caution → warning', () async {
      await PGHaptics.forSafetyStatus(CatalogProductSafetyStatus.caution);
      expect(recorder.calls, ['HapticFeedbackType.mediumImpact']);
    });

    test('unsafe → danger', () async {
      await PGHaptics.forSafetyStatus(CatalogProductSafetyStatus.unsafe);
      expect(recorder.calls, ['HapticFeedbackType.heavyImpact']);
    });

    test('blocked → errorPattern (di-da-DUP)', () async {
      await PGHaptics.forSafetyStatus(CatalogProductSafetyStatus.blocked);
      expect(recorder.calls, [
        'HapticFeedbackType.mediumImpact',
        'HapticFeedbackType.mediumImpact',
        'HapticFeedbackType.heavyImpact',
      ]);
    });

    test('not assessed → success (single light)', () async {
      await PGHaptics.forSafetyStatus(CatalogProductSafetyStatus.notAssessed);
      expect(recorder.calls, ['HapticFeedbackType.lightImpact']);
    });
  });

  group('PGHaptics.forSeverity mapping', () {
    test('contraindicated now uses errorPattern (was: heavy only)', () async {
      await PGHaptics.forSeverity(Severity.contraindicated);
      expect(recorder.calls, [
        'HapticFeedbackType.mediumImpact',
        'HapticFeedbackType.mediumImpact',
        'HapticFeedbackType.heavyImpact',
      ]);
    });

    test('avoid → danger (heavy)', () async {
      await PGHaptics.forSeverity(Severity.avoid);
      expect(recorder.calls, ['HapticFeedbackType.heavyImpact']);
    });

    test('caution → warning (medium)', () async {
      await PGHaptics.forSeverity(Severity.caution);
      expect(recorder.calls, ['HapticFeedbackType.mediumImpact']);
    });

    test('safe → success (light)', () async {
      await PGHaptics.forSeverity(Severity.safe);
      expect(recorder.calls, ['HapticFeedbackType.lightImpact']);
    });
  });
}
