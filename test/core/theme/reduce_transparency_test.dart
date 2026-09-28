import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/theme/reduce_transparency.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(ReduceTransparency.channel, null);
    ReduceTransparency.channel.setMethodCallHandler(null);
    ReduceTransparency.enabled.value = false;
    debugDefaultTargetPlatformOverride = null;
  });

  test('on iOS it reads the setting from the runner at start', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    messenger.setMockMethodCallHandler(ReduceTransparency.channel, (call) {
      expect(call.method, 'reduceTransparency');
      return Future.value(true);
    });
    await ReduceTransparency.listen();
    expect(ReduceTransparency.enabled.value, isTrue);
  });

  test('on iOS it follows changes the runner pushes', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    messenger.setMockMethodCallHandler(
      ReduceTransparency.channel,
      (_) => Future.value(false),
    );
    await ReduceTransparency.listen();
    expect(ReduceTransparency.enabled.value, isFalse);

    await messenger.handlePlatformMessage(
      ReduceTransparency.channel.name,
      ReduceTransparency.channel.codec.encodeMethodCall(
        const MethodCall('reduceTransparencyChanged', true),
      ),
      (_) {},
    );
    expect(ReduceTransparency.enabled.value, isTrue);
  });

  test('a runner without the channel leaves it off', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await ReduceTransparency.listen();
    expect(ReduceTransparency.enabled.value, isFalse);
  });

  test('other platforms never ask', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    var asked = false;
    messenger.setMockMethodCallHandler(ReduceTransparency.channel, (_) {
      asked = true;
      return Future.value(true);
    });
    await ReduceTransparency.listen();
    expect(asked, isFalse);
    expect(ReduceTransparency.enabled.value, isFalse);
  });

  testWidgets('of() is false without a scope and rebuilds with one', (
    tester,
  ) async {
    final values = <bool>[];
    Widget probe() => Builder(
      builder: (context) {
        values.add(ReduceTransparency.of(context));
        return const SizedBox();
      },
    );

    await tester.pumpWidget(probe());
    expect(values.last, isFalse);

    final notifier = ValueNotifier(false);
    addTearDown(notifier.dispose);
    await tester.pumpWidget(
      ReduceTransparencyScope(notifier: notifier, child: probe()),
    );
    notifier.value = true;
    await tester.pump();
    expect(values.last, isTrue);
  });
}
