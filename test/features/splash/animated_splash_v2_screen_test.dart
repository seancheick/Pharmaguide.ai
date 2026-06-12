import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/splash/v2/animated_splash_v2_screen.dart';

void main() {
  Widget buildSubject() {
    return const MaterialApp(home: AnimatedSplashV2Screen(autoNavigate: false));
  }

  testWidgets('first frame keeps the logo visible and exactly centered', (
    tester,
  ) async {
    await tester.pumpWidget(buildSubject());

    final logo = find.image(const AssetImage('assets/images/splash_logo.png'));
    expect(logo, findsOneWidget);

    final logoCenter = tester.getCenter(logo);
    final viewportCenter = tester.getCenter(find.byType(Scaffold));
    expect(logoCenter.dx, closeTo(viewportCenter.dx, 0.1));
    expect(logoCenter.dy, closeTo(viewportCenter.dy, 0.1));

    final opacity = tester.widget<Opacity>(
      find.ancestor(of: logo, matching: find.byType(Opacity)).first,
    );
    expect(opacity.opacity, 1);
  });

  testWidgets('holds the centered handoff frame before motion begins', (
    tester,
  ) async {
    await tester.pumpWidget(buildSubject());

    final logo = find.image(const AssetImage('assets/images/splash_logo.png'));
    final initialCenter = tester.getCenter(logo);

    await tester.pump(const Duration(milliseconds: 40));
    expect(tester.getCenter(logo).dy, closeTo(initialCenter.dy, 0.1));

    await tester.pump(const Duration(milliseconds: 80));
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.getCenter(logo).dy, lessThan(initialCenter.dy - 4));
  });

  testWidgets('completed entrance lifts the logo and reveals the tagline', (
    tester,
  ) async {
    await tester.pumpWidget(buildSubject());

    final logo = find.image(const AssetImage('assets/images/splash_logo.png'));
    final initialCenter = tester.getCenter(logo);

    await tester.pump(const Duration(milliseconds: 64));
    await tester.pump(const Duration(milliseconds: 960));

    expect(tester.getCenter(logo).dy, lessThan(initialCenter.dy - 70));
    expect(find.text('Scan with confidence'), findsOneWidget);
  });
}
