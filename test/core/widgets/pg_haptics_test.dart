import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/severity.dart';
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

  group('PGHaptics.forVerdict mapping', () {
    test('SAFE → successPattern (di-DUP)', () async {
      await PGHaptics.forVerdict('SAFE');
      expect(recorder.calls, [
        'HapticFeedbackType.lightImpact',
        'HapticFeedbackType.mediumImpact',
      ]);
    });

    test('RECOMMENDED → successPattern (di-DUP)', () async {
      await PGHaptics.forVerdict('RECOMMENDED');
      expect(recorder.calls, [
        'HapticFeedbackType.lightImpact',
        'HapticFeedbackType.mediumImpact',
      ]);
    });

    test('GOOD → successPattern', () async {
      await PGHaptics.forVerdict('GOOD');
      expect(recorder.calls, [
        'HapticFeedbackType.lightImpact',
        'HapticFeedbackType.mediumImpact',
      ]);
    });

    test('MODERATE → warning', () async {
      await PGHaptics.forVerdict('MODERATE');
      expect(recorder.calls, ['HapticFeedbackType.mediumImpact']);
    });

    test('CAUTION → warning', () async {
      await PGHaptics.forVerdict('CAUTION');
      expect(recorder.calls, ['HapticFeedbackType.mediumImpact']);
    });

    test('REVIEW → warning', () async {
      await PGHaptics.forVerdict('REVIEW');
      expect(recorder.calls, ['HapticFeedbackType.mediumImpact']);
    });

    test('POOR → danger', () async {
      await PGHaptics.forVerdict('POOR');
      expect(recorder.calls, ['HapticFeedbackType.heavyImpact']);
    });

    test('UNSAFE → danger', () async {
      await PGHaptics.forVerdict('UNSAFE');
      expect(recorder.calls, ['HapticFeedbackType.heavyImpact']);
    });

    test('BLOCKED → errorPattern (di-da-DUP)', () async {
      await PGHaptics.forVerdict('BLOCKED');
      expect(recorder.calls, [
        'HapticFeedbackType.mediumImpact',
        'HapticFeedbackType.mediumImpact',
        'HapticFeedbackType.heavyImpact',
      ]);
    });

    test('NOT_SCORED → success (single light)', () async {
      await PGHaptics.forVerdict('NOT_SCORED');
      expect(recorder.calls, ['HapticFeedbackType.lightImpact']);
    });

    test('NUTRITION_ONLY → success (single light)', () async {
      await PGHaptics.forVerdict('NUTRITION_ONLY');
      expect(recorder.calls, ['HapticFeedbackType.lightImpact']);
    });

    test('null verdict → no haptic', () async {
      await PGHaptics.forVerdict(null);
      expect(recorder.calls, isEmpty);
    });

    test('unknown verdict → no haptic', () async {
      await PGHaptics.forVerdict('GIBBERISH');
      expect(recorder.calls, isEmpty);
    });

    test('whitespace and case insensitive', () async {
      await PGHaptics.forVerdict('  safe  ');
      expect(recorder.calls, [
        'HapticFeedbackType.lightImpact',
        'HapticFeedbackType.mediumImpact',
      ]);
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
