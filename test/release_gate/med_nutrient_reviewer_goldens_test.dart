@Tags(['golden'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pharmaguide/features/stack/v2/widgets/pg_depletion_card.dart';
import 'package:pharmaguide/services/stack/depletion_checker.dart';

Future<void> _pumpCard(
  WidgetTester tester,
  Widget child, {
  double height = 1400,
}) async {
  await tester.binding.setSurfaceSize(Size(430, height));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(fontFamily: 'Geist'),
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Align(alignment: Alignment.topCenter, child: child),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('reviewer screenshot: verified consumer presentation', (
    tester,
  ) async {
    final artifact =
        jsonDecode(
              File(
                'assets/reference_data/medication_depletions.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final matches = DepletionChecker().check(
      medications: const [],
      medicationIdentities: const [
        DepletionMedicationIdentity(name: 'metformin', rxcui: '6809'),
        DepletionMedicationIdentity(
          name: 'warfarin',
          rxcui: '11289',
          drugClassIds: ['class:anticoagulants'],
        ),
      ],
      depletionsData: artifact,
    );

    expect(matches.map((match) => match.depletionId), {
      'DEP_METFORMIN_VITAMINB12',
      'DEP_ANTICOAGULANTS_VITAMINK',
    });
    await _pumpCard(tester, PGDepletionCard(depletions: matches));

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/med_nutrient_verified.png'),
    );
  });

  testWidgets('reviewer screenshot: unavailable is not an all-clear', (
    tester,
  ) async {
    await _pumpCard(tester, const PGDepletionUnavailableCard(), height: 360);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/med_nutrient_unavailable.png'),
    );
  });
}
