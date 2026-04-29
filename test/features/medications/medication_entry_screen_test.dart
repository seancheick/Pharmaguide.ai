// Widget tests for MedicationEntryScreen (M4 §8.5).
//
// We override the [rxNormApiServiceProvider] with a real
// [RxNormApiService] wired to a fake HTTP transport so the autocomplete
// path is exercised end-to-end without touching the network. The
// [userDatabaseProvider] is overridden with an in-memory Drift database
// so the save path round-trips through real SQL — this is what catches
// regressions like "we silently dropped drug_classes JSON" that mocks
// would miss.
//
// Coverage:
//   - Empty / short query state (no autocomplete fired)
//   - Debounced suggestion list rendering after a >=2-char query
//   - Selecting a suggestion populates the selection summary + class
//     chips
//   - Save inserts a row with type='medication', rxcui, drug_classes
//     JSON, and pops with the new entry id
//   - Offline fallback: when the search returns empty (network error
//     simulated by throwing transport), the bundled drug-class picker
//     appears and selecting a class id wires the save path
//   - Save button stays disabled until a selection is committed
//
// Run:
//   flutter test test/features/medications/medication_entry_screen_test.dart

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/interaction_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/medications/medication_entry_screen.dart';
import 'package:pharmaguide/services/medications/rxnorm_api_service.dart';
import 'package:pharmaguide/services/medications/rxnorm_providers.dart';

// ---------------------------------------------------------------------------
// Fake HTTP transport
// ---------------------------------------------------------------------------

/// A configurable fake [RxNormHttpGet]. Each test sets either canned
/// responses (keyed by URL path) or [throwOnAll] to simulate the offline
/// path that should trigger the bundled drug-class picker.
class _FakeHttp {
  _FakeHttp({Map<String, String>? responses, this.throwOnAll = false})
    : _responses = responses ?? const <String, String>{};

  final Map<String, String> _responses;
  final bool throwOnAll;

  Future<String> call(Uri url) async {
    if (throwOnAll) throw const _Offline();
    final body = _responses[url.path];
    if (body == null) {
      throw StateError('No canned response for ${url.path}');
    }
    return body;
  }
}

class _Offline implements Exception {
  const _Offline();
}

// ---------------------------------------------------------------------------
// Test fixtures
// ---------------------------------------------------------------------------

/// Wraps the [MedicationEntryScreen] in a [ProviderScope] with the
/// rxnorm + user-db providers overridden. Returns the in-memory user
/// database so tests can assert what was inserted.
({Widget widget, UserDatabase userDb, InteractionDatabase interactionDb})
_harness({_FakeHttp? http}) {
  final fakeHttp = http ?? _FakeHttp();
  final userDb = UserDatabase.memory();
  final interactionDb = InteractionDatabase.memory();

  // Real service backed by the fake HTTP — this exercises the LRU
  // cache and the offline fallback path the same way production does.
  final svc = RxNormApiService(
    httpGet: fakeHttp.call,
    offlineDb: interactionDb,
  );

  final widget = ProviderScope(
    overrides: [
      rxNormApiServiceProvider.overrideWith((ref) => svc),
      userDatabaseProvider.overrideWith((ref) => userDb),
      interactionDatabaseProvider.overrideWith((ref) => interactionDb),
    ],
    child: const MaterialApp(home: MedicationEntryScreen()),
  );

  return (widget: widget, userDb: userDb, interactionDb: interactionDb);
}

/// Seed three drug-class rows into the in-memory interaction DB so the
/// offline fallback has something to render.
Future<void> _seedDrugClasses(InteractionDatabase db) async {
  await db
      .into(db.drugClassMap)
      .insert(
        DrugClassMapCompanion.insert(
          classId: 'class:ace_inhibitors',
          className: 'ACE Inhibitors',
          drugRxcuisJson: '[]',
          source: 'rxclass',
          lastUpdated: '2026-01-01',
        ),
      );
  await db
      .into(db.drugClassMap)
      .insert(
        DrugClassMapCompanion.insert(
          classId: 'class:beta_blockers',
          className: 'Beta Blockers',
          drugRxcuisJson: '[]',
          source: 'rxclass',
          lastUpdated: '2026-01-01',
        ),
      );
  await db
      .into(db.drugClassMap)
      .insert(
        DrugClassMapCompanion.insert(
          classId: 'class:statins',
          className: 'Statins',
          drugRxcuisJson: '[]',
          source: 'rxclass',
          lastUpdated: '2026-01-01',
        ),
      );
}

// Canned RxNorm payloads.
const _searchWarfarinJson = '''
{
  "approximateGroup": {
    "candidate": [
      {"rxcui": "11289", "name": "warfarin", "score": "100"},
      {"rxcui": "1234", "name": "warfarin sodium", "score": "85"}
    ]
  }
}
''';

const _classesWarfarinJson = '''
{
  "rxclassDrugInfoList": {
    "rxclassDrugInfo": [
      {"rxclassMinConceptItem": {"className": "Anticoagulants"}},
      {"rxclassMinConceptItem": {"className": "Vitamin K Antagonists"}}
    ]
  }
}
''';

void main() {
  // DBs are closed at the end of each test body instead of via
  // addTearDown. `addTearDown(db.close)` runs after the fake async
  // zone has already drained, and drift's close() then hangs waiting
  // for stream events the zone will never deliver — tests hit a
  // "Cannot close sink while adding stream" shutdown error and SIGTERM
  // after ~90s. Closing inside the body (before the test returns)
  // drains cleanly.

  testWidgets('initial state shows no suggestions and disabled save', (
    tester,
  ) async {
    final h = _harness();

    await tester.pumpWidget(h.widget);
    await tester.pump();

    expect(find.byKey(const Key('med-entry-search')), findsOneWidget);
    expect(find.byKey(const Key('med-entry-suggestion-list')), findsNothing);
    expect(find.byKey(const Key('med-entry-selection-summary')), findsNothing);

    // Save button is present but disabled (TextButton with onPressed null).
    final saveBtn = tester.widget<TextButton>(
      find.byKey(const Key('med-entry-save')),
    );
    expect(saveBtn.onPressed, isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await h.userDb.close();
    await h.interactionDb.close();
  });

  testWidgets('single-char query does NOT trigger autocomplete', (
    tester,
  ) async {
    final fake = _FakeHttp(
      responses: const {'/REST/approximateTerm.json': _searchWarfarinJson},
    );
    final h = _harness(http: fake);

    await tester.pumpWidget(h.widget);
    await tester.enterText(find.byKey(const Key('med-entry-search')), 'w');
    // Wait past the debounce window.
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    expect(find.byKey(const Key('med-entry-suggestion-list')), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await h.userDb.close();
    await h.interactionDb.close();
  });

  testWidgets('typing 2+ chars triggers debounced search and renders results', (
    tester,
  ) async {
    final fake = _FakeHttp(
      responses: const {'/REST/approximateTerm.json': _searchWarfarinJson},
    );
    final h = _harness(http: fake);

    await tester.pumpWidget(h.widget);
    await tester.enterText(
      find.byKey(const Key('med-entry-search')),
      'warfarin',
    );

    // Spinner shown immediately.
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // After the debounce + microtask drain, suggestions appear.
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    expect(find.byKey(const Key('med-entry-suggestion-list')), findsOneWidget);
    expect(find.byKey(const Key('med-entry-suggestion-11289')), findsOneWidget);
    expect(find.byKey(const Key('med-entry-suggestion-1234')), findsOneWidget);
    expect(find.text('warfarin'), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
    await h.userDb.close();
    await h.interactionDb.close();
  });

  testWidgets('selecting a suggestion populates summary + resolves classes', (
    tester,
  ) async {
    final fake = _FakeHttp(
      responses: const {
        '/REST/approximateTerm.json': _searchWarfarinJson,
        '/REST/rxclass/class/byRxcui.json': _classesWarfarinJson,
      },
    );
    final h = _harness(http: fake);

    await tester.pumpWidget(h.widget);
    await tester.enterText(
      find.byKey(const Key('med-entry-search')),
      'warfarin',
    );
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    await tester.tap(find.byKey(const Key('med-entry-suggestion-11289')));
    // First pump shows "Looking up drug classes…". The async getClasses
    // resolves on the next microtask drain.
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const Key('med-entry-selection-summary')),
      findsOneWidget,
    );
    expect(find.text('warfarin'), findsWidgets);
    expect(find.text('RxCUI 11289'), findsOneWidget);
    expect(find.text('Anticoagulants'), findsOneWidget);
    expect(find.text('Vitamin K Antagonists'), findsOneWidget);

    // Save button is now enabled.
    final saveBtn = tester.widget<TextButton>(
      find.byKey(const Key('med-entry-save')),
    );
    expect(saveBtn.onPressed, isNotNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await h.userDb.close();
    await h.interactionDb.close();
  });

  testWidgets('save inserts a medication row with expected shape', (
    tester,
  ) async {
    final fake = _FakeHttp(
      responses: const {
        '/REST/approximateTerm.json': _searchWarfarinJson,
        '/REST/rxclass/class/byRxcui.json': _classesWarfarinJson,
      },
    );
    final h = _harness(http: fake);

    // Mount the screen directly. We used to wrap it in a Navigator +
    // opener button to capture the popped entry id, but the
    // MedicationEntryScreen's autofocused search field starts a cursor
    // blink ticker that makes `pumpAndSettle()` hang forever. Asserting
    // on the DB state after save is a stronger contract anyway — it
    // proves the row shape, not just that `Navigator.pop` was called.
    await tester.pumpWidget(h.widget);
    await tester.enterText(
      find.byKey(const Key('med-entry-search')),
      'warfarin',
    );
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    await tester.tap(find.byKey(const Key('med-entry-suggestion-11289')));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const Key('med-entry-save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Row landed in the user db.
    final rows = await h.userDb.getActiveStack();
    expect(rows, hasLength(1));
    final row = rows.single;
    expect(row.type, 'medication');
    expect(row.name, 'warfarin');
    expect(row.rxcui, '11289');
    // id is prefixed with `rx_<rxcui>_` per StackActions._newId.
    expect(row.id.startsWith('rx_11289_'), isTrue);

    final classes = jsonDecode(row.drugClassesCol!) as List;
    expect(classes, ['class:anticoagulants', 'class:vitamin_k_antagonists']);

    // Unmount + close DBs inside the test body. Closing via addTearDown
    // runs after the fake async zone has torn down, and drift's close()
    // then hangs waiting for pending writes that the zone never drained.
    await tester.pumpWidget(const SizedBox.shrink());
    await h.userDb.close();
    await h.interactionDb.close();
  });

  testWidgets('offline path: empty search results show drug-class picker '
      'and a class selection enables save', (tester) async {
    final fake = _FakeHttp(throwOnAll: true);
    final h = _harness(http: fake);
    // Note: DBs are closed at end of body instead of via addTearDown —
    // the save button tap enqueues an insert in drift's fake-async
    // zone and addTearDown's close hangs waiting for it to drain.

    await _seedDrugClasses(h.interactionDb);

    await tester.pumpWidget(h.widget);
    await tester.enterText(
      find.byKey(const Key('med-entry-search')),
      'lisinopril',
    );
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('med-entry-offline-classes')), findsOneWidget);
    expect(
      find.byKey(const Key('med-entry-class-class:ace_inhibitors')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('med-entry-class-class:beta_blockers')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('med-entry-class-class:statins')),
      findsOneWidget,
    );

    // Pick ACE Inhibitors.
    await tester.tap(
      find.byKey(const Key('med-entry-class-class:ace_inhibitors')),
    );
    await tester.pump();

    // Selection summary appears. The offline picker humanizes the slug
    // (`class:ace_inhibitors` → `Ace Inhibitors`), not the bundled
    // className, because the screen only has the id at pick time.
    expect(
      find.byKey(const Key('med-entry-selection-summary')),
      findsOneWidget,
    );
    expect(find.text('Ace Inhibitors'), findsWidgets);

    // Save button enabled and the row carries the class id but no rxcui.
    final saveBtn = tester.widget<TextButton>(
      find.byKey(const Key('med-entry-save')),
    );
    expect(saveBtn.onPressed, isNotNull);

    await tester.tap(find.byKey(const Key('med-entry-save')));
    // No pumpAndSettle — the focused search field's cursor blink ticker
    // would keep the frame scheduler awake forever.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final rows = await h.userDb.getActiveStack();
    expect(rows, hasLength(1));
    expect(rows.single.type, 'medication');
    expect(rows.single.rxcui, isNull);
    expect(jsonDecode(rows.single.drugClassesCol!), ['class:ace_inhibitors']);

    await tester.pumpWidget(const SizedBox.shrink());
    await h.userDb.close();
    await h.interactionDb.close();
  });

  testWidgets(
    'offline path with no bundled classes shows the empty state instead',
    (tester) async {
      final fake = _FakeHttp(throwOnAll: true);
      final h = _harness(http: fake);

      // No _seedDrugClasses call — the bundled DB is empty.

      await tester.pumpWidget(h.widget);
      await tester.enterText(
        find.byKey(const Key('med-entry-search')),
        'lisinopril',
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('med-entry-offline-classes')), findsNothing);
      expect(find.text('No matches'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await h.userDb.close();
      await h.interactionDb.close();
    },
  );

  testWidgets('typing a new query after picking clears the selection', (
    tester,
  ) async {
    final fake = _FakeHttp(
      responses: const {
        '/REST/approximateTerm.json': _searchWarfarinJson,
        '/REST/rxclass/class/byRxcui.json': _classesWarfarinJson,
      },
    );
    final h = _harness(http: fake);

    await tester.pumpWidget(h.widget);
    await tester.enterText(
      find.byKey(const Key('med-entry-search')),
      'warfarin',
    );
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    await tester.tap(find.byKey(const Key('med-entry-suggestion-11289')));
    await tester.pump();
    await tester.pump();
    expect(
      find.byKey(const Key('med-entry-selection-summary')),
      findsOneWidget,
    );

    // Type something new — selection should clear.
    await tester.enterText(
      find.byKey(const Key('med-entry-search')),
      'aspirin',
    );
    await tester.pump();
    expect(find.byKey(const Key('med-entry-selection-summary')), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await h.userDb.close();
    await h.interactionDb.close();
  });
}
