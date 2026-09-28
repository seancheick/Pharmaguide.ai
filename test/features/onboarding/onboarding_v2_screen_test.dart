import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/onboarding/v2/onboarding_v2_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // The first onboarding page showed "Thorne · Magnesium Glycinate ·
  // 86/100 Very good". The catalog's Thorne product is Magnesium
  // Bisglycinate at 91/100 Excellent, so a real brand wore a score it never
  // earned. The preview must read as an illustration, not a catalog result.
  testWidgets('score preview is labelled as an example, not a real brand', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: OnboardingV2Screen(autoFinish: false)),
      ),
    );
    await tester.pump();

    expect(find.text('86/100'), findsOneWidget);
    expect(find.textContaining('Thorne'), findsNothing);
    expect(find.textContaining('THORNE'), findsNothing);
    expect(find.textContaining('EXAMPLE'), findsOneWidget);
  });
}
