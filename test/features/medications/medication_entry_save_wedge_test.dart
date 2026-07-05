// FIX (robustness): a failed medication save must not wedge the Save button.
//
// MedicationEntryV2Screen._save() only caught StackRequiresSignInException;
// any other throw from StackActions.addMedication (network, RxNorm resolve, DB
// write) propagated unhandled and left `_saving = true` forever. Because
// `_canSave` is `!_saving && …` and the sticky bar keys off it, the button
// stuck on "Saving…" with no way to retry — a dead end for recording a
// medication (and its interaction checks) in a medical app.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/interaction_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/data/providers/reference_data_provider.dart';
import 'package:pharmaguide/data/repositories/reference_data_repository.dart';
import 'package:pharmaguide/features/medications/v2/medication_entry_v2_screen.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';
import 'package:pharmaguide/features/stack/providers/active_stack_provider.dart';
import 'package:pharmaguide/services/medications/rxnorm_api_service.dart';
import 'package:pharmaguide/services/medications/rxnorm_providers.dart';

class _FakeRxNormHttp {
  Future<String> call(Uri url) async {
    if (url.path == '/REST/approximateTerm.json') {
      return '{"approximateGroup":{"candidate":['
          '{"rxcui":"202488","name":"Motrin","score":"100"}]}}';
    }
    throw StateError('No fake RxNorm response for $url');
  }
}

class _EmptyRulesRepository extends ReferenceDataRepository {
  @override
  Future<Map<String, dynamic>> loadMedicationProfileGateRules() async {
    return const {'medication_profile_gate_rules': <dynamic>[]};
  }
}

/// StackActions whose addMedication fails with a generic (non-sign-in) error,
/// standing in for a network / DB failure at save time.
class _ThrowingStackActions extends StackActions {
  _ThrowingStackActions(Ref ref) : super(ref);

  @override
  Future<String> addMedication({
    required String name,
    String? rxcui,
    String? genericRxcui,
    List<String> drugClasses = const <String>[],
    List<String> ingredientRxcuis = const <String>[],
    String? dosage,
    String? frequency,
  }) async {
    throw Exception('simulated network failure');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'a failed save resets the button instead of wedging it on "Saving…"',
    (tester) async {
      final interactionDb = InteractionDatabase.memory();
      addTearDown(interactionDb.close);

      final fakeRx = _FakeRxNormHttp();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            interactionDatabaseProvider.overrideWithValue(interactionDb),
            referenceDataRepositoryProvider.overrideWith(
              (ref) => _EmptyRulesRepository(),
            ),
            loadedProfileProvider.overrideWith(
              (ref) async => const ProfileState(),
            ),
            rxNormApiServiceProvider.overrideWithValue(
              RxNormApiService(httpGet: fakeRx.call, offlineDb: interactionDb),
            ),
            stackActionsProvider.overrideWith(
              (ref) => _ThrowingStackActions(ref),
            ),
          ],
          child: const MaterialApp(home: MedicationEntryV2Screen()),
        ),
      );

      await tester.enterText(
        find.byKey(const Key('med-entry-search')),
        'motrin',
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('med-entry-suggestion-202488')));
      await tester.pumpAndSettle();

      // Pre-save: the button is enabled and shows its idle label.
      expect(find.text('Add medication'), findsOneWidget);
      expect(find.text('Saving…'), findsNothing);

      await tester.tap(find.byKey(const Key('med-entry-save')));
      await tester.pumpAndSettle();

      // The failure is swallowed (no unhandled exception) and the button is
      // back to its idle, tappable state — never stuck on the saving spinner.
      expect(tester.takeException(), isNull);
      expect(find.text('Saving…'), findsNothing);
      expect(find.text('Add medication'), findsOneWidget);
    },
  );
}
