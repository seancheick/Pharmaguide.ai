import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/app.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/core/navigation/launch_link_buffer.dart';

/// What the iOS engine sends when the app is opened from a link.
Future<void> _deliverLink(WidgetTester tester, String location) async {
  const codec = JSONMethodCodec();
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/navigation',
    codec.encodeMethodCall(
      MethodCall('pushRouteInformation', {'location': location}),
    ),
    (_) {},
  );
  await tester.pump();
}

/// The startup screen: a plain MaterialApp with no route generator, as in
/// main.dart before the catalog opens.
Widget _startupScreen() => const MaterialApp(home: Text('Preparing'));

void main() {
  // Sentry PHARMAGUIDE-27: a product link that arrived while the startup
  // screen showed raised "Could not find a generator for route" and was lost.
  testWidgets('a link during startup is kept, not dropped', (tester) async {
    final buffer = LaunchLinkBuffer()..attach();
    addTearDown(buffer.detach);
    await tester.pumpWidget(_startupScreen());

    await _deliverLink(tester, 'pharmaguide://product/214452');

    expect(tester.takeException(), isNull);
    expect(buffer.takeLocation(), Routes.productDetail('214452'));
    expect(buffer.takeLocation(), isNull, reason: 'handed over once');
  });

  testWidgets('the magic-link callback is kept too', (tester) async {
    final buffer = LaunchLinkBuffer()..attach();
    addTearDown(buffer.detach);
    await tester.pumpWidget(_startupScreen());

    await _deliverLink(tester, 'pharmaguide://auth/callback?code=abc');

    expect(tester.takeException(), isNull);
    expect(buffer.takeLocation(), '/auth/callback?code=abc');
  });

  testWidgets('once released, links go to the app router', (tester) async {
    final buffer = LaunchLinkBuffer()..attach();
    addTearDown(buffer.detach);
    await tester.pumpWidget(_startupScreen());
    buffer.detach();

    await _deliverLink(tester, 'pharmaguide://product/1');

    // Nothing buffered: after startup the router, not the buffer, owns links.
    expect(buffer.takeLocation(), isNull);
    tester.takeException(); // the bare test MaterialApp has no generator
  });

  test('a launch link wins over onboarding and home', () {
    expect(
      initialAppLocation(
        hasSeenOnboarding: false,
        launchLocation: Routes.productDetail('9'),
      ),
      Routes.productDetail('9'),
    );
    expect(
      initialAppLocation(hasSeenOnboarding: true, launchLocation: null),
      Routes.home,
    );
  });
}
