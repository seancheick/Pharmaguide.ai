// Medication entry screen — M4 §8.5.
//
// Lets the user add a medication to their personal stack so the M4
// curated interaction checker can fan it against existing supplements.
//
// Flow:
//   1. Autocomplete text field hits `RxNormApiService.search()` on a
//      300 ms debounce. While the user is still typing or while the
//      query is in flight we show a "shimmer" suggestion list.
//   2. The user picks a suggestion → we resolve its rxcui's drug
//      classes via `RxNormApiService.getClasses()` so the curated
//      check can match class-level rows.
//   3. Optional dose / frequency text fields. We don't validate them
//      beyond non-empty: every device shows a different label and the
//      M5 interaction renderer doesn't read them.
//   4. Save → calls `StackActions.addMedication()` which inserts a
//      `type='medication'` row with rxcui + drug_classes JSON. The
//      privacy grep test guarantees that path never reaches Supabase
//      sync.
//   5. After save we pop the screen with `Navigator.pop(context, ...)`
//      returning the new entry id so the caller can fan a snackbar +
//      kick off the post-add interaction check (G11 wires that).
//
// Offline fallback (spec §8.4): if the autocomplete query yields zero
// suggestions AND we know we're offline (the network call returned
// null), we fold the bundled drug-class picker into the suggestion
// list — the user can still add a class-level entry like "ACE
// Inhibitors" without a single network round-trip. The class picker
// pulls its options from `RxNormApiService.offlineDrugClasses()`,
// which reads the bundled InteractionDb's `drug_class_map` table.
//
// The screen is intentionally feature-flag-free and self-contained.
// All HTTP / DB / sync calls are routed through Riverpod providers so
// widget tests can swap them out for fakes. See
// `test/features/medications/medication_entry_screen_test.dart`.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/widgets/pg_card.dart';
import 'package:pharmaguide/core/widgets/pg_empty_state.dart';
import 'package:pharmaguide/core/widgets/pg_search_field.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/stack/providers/stack_nutrient_providers.dart';
import 'package:pharmaguide/features/stack/providers/stack_providers.dart';
import 'package:pharmaguide/features/stack/widgets/depletion_nudge_sheet.dart';
import 'package:pharmaguide/services/medications/rxnorm_api_service.dart';
import 'package:pharmaguide/services/medications/rxnorm_providers.dart';

/// Public route widget. Push with `Navigator.of(context).push(...)`
/// or via go_router; on success it pops with the new entry id.
class MedicationEntryScreen extends ConsumerStatefulWidget {
  const MedicationEntryScreen({super.key});

  @override
  ConsumerState<MedicationEntryScreen> createState() =>
      _MedicationEntryScreenState();
}

class _MedicationEntryScreenState
    extends ConsumerState<MedicationEntryScreen> {
  // Autocomplete state ------------------------------------------------------
  final _searchController = TextEditingController();
  final _doseController = TextEditingController();
  final _frequencyController = TextEditingController();

  Timer? _debounce;
  int _searchVersion = 0;

  String _query = '';
  bool _searching = false;
  List<RxNormSuggestion> _suggestions = const <RxNormSuggestion>[];

  /// True once a search has come back with zero results AND we have
  /// reason to believe the user is offline (the suggestions list is
  /// empty even after a fresh search). We then surface the bundled
  /// drug-class picker as a fallback.
  bool _offlineFallbackVisible = false;
  List<String> _offlineClasses = const <String>[];

  // Selection state ---------------------------------------------------------
  /// The user-picked drug name (either an RxNorm display name or a
  /// `class:*` slug from the offline picker).
  String? _selectedName;

  /// rxcui resolved when the user picked a real RxNorm suggestion.
  /// Null when the user fell back to the offline class picker.
  String? _selectedRxcui;

  /// Drug classes resolved for the selected rxcui (or a single class
  /// slug when the offline picker is in play).
  List<String> _selectedClasses = const <String>[];

  /// Generic ingredient RXCUI resolved from the user's pick. When the
  /// user selects a brand name (e.g., Synthroid → 224920), this holds
  /// the base generic IN-level RXCUI (levothyroxine → 10582). Used for
  /// interaction matching so brand picks match curated entries keyed on
  /// the generic. Null when offline or already generic.
  String? _selectedGenericRxcui;

  /// Individual ingredient RXCUIs for combination drugs. When the user
  /// picks "Lisinopril/HCTZ", this holds [lisinopril_rxcui, hctz_rxcui]
  /// so each ingredient can be checked independently against interactions.
  List<String> _ingredientRxcuis = const <String>[];

  /// Set while we're fetching classes for the just-picked suggestion
  /// so the save button can stay disabled.
  bool _resolvingClasses = false;

  /// Set while we're inserting the row.
  bool _saving = false;

  // -------------------------------------------------------------------------

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _doseController.dispose();
    _frequencyController.dispose();
    super.dispose();
  }

  RxNormApiService get _service => ref.read(rxNormApiServiceProvider);

  // -------------------------------------------------------------------------
  // Autocomplete plumbing
  // -------------------------------------------------------------------------

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    final trimmed = value.trim();
    setState(() {
      _query = value;
      _selectedName = null;
      _selectedRxcui = null;
      _selectedClasses = const <String>[];
      _offlineFallbackVisible = false;
    });

    if (trimmed.length < 2) {
      setState(() {
        _searching = false;
        _suggestions = const <RxNormSuggestion>[];
      });
      return;
    }

    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _runSearch(trimmed);
    });
  }

  Future<void> _runSearch(String query) async {
    final version = ++_searchVersion;
    final results = await _service.search(query);
    if (!mounted || version != _searchVersion) return;

    setState(() {
      _suggestions = results;
      _searching = false;
    });

    // Empty results triggers the offline fallback. We treat zero hits
    // and a network error identically: the medication-entry flow
    // promises a usable picker either way.
    if (results.isEmpty) {
      await _loadOfflineFallback();
    }
  }

  Future<void> _loadOfflineFallback() async {
    final classes = await _service.offlineDrugClasses();
    if (!mounted) return;
    setState(() {
      _offlineClasses = classes;
      _offlineFallbackVisible = classes.isNotEmpty;
    });
  }

  // -------------------------------------------------------------------------
  // Selection plumbing
  // -------------------------------------------------------------------------

  Future<void> _selectSuggestion(RxNormSuggestion suggestion) async {
    setState(() {
      _selectedName = suggestion.name;
      _selectedRxcui = suggestion.rxcui;
      _selectedGenericRxcui = null;
      _ingredientRxcuis = const <String>[];
      _selectedClasses = const <String>[];
      _resolvingClasses = true;
      _searchController.text = suggestion.name;
      _searchController.selection = TextSelection.fromPosition(
        TextPosition(offset: suggestion.name.length),
      );
      _suggestions = const <RxNormSuggestion>[];
      _offlineFallbackVisible = false;
    });

    // Fire class resolution + generic resolution + ingredient decomposition
    // in parallel — all are non-blocking and independent.
    final classesFuture = _service.getClasses(suggestion.rxcui);
    final genericsFuture = _service.resolveGenericRxcuis(suggestion.rxcui);

    final classesResult = await classesFuture;
    final genericsResult = await genericsFuture;
    if (!mounted) return;

    final classes = classesResult;
    final generics = genericsResult;

    setState(() {
      _selectedClasses = classes;
      // If multiple IN-level ingredients → combination drug.
      // Store the first as the generic_rxcui, all as ingredient_rxcuis.
      _selectedGenericRxcui = generics.isNotEmpty ? generics.first : null;
      _ingredientRxcuis = generics.length > 1 ? generics : const <String>[];
      _resolvingClasses = false;
    });
  }

  void _selectOfflineClass(String classId) {
    setState(() {
      _selectedName = _humanizeClass(classId);
      _selectedRxcui = null;
      _selectedClasses = <String>[classId];
      _searchController.text = _humanizeClass(classId);
      _searchController.selection = TextSelection.fromPosition(
        TextPosition(offset: _searchController.text.length),
      );
      _suggestions = const <RxNormSuggestion>[];
      _offlineFallbackVisible = false;
    });
  }

  /// `class:ace_inhibitors` → `ACE Inhibitors`. Title-cases the slug
  /// for display. The underlying id is preserved verbatim in the
  /// stack row.
  static String _humanizeClass(String classId) {
    final stripped = classId.startsWith('class:')
        ? classId.substring(6)
        : classId;
    return stripped
        .split('_')
        .where((p) => p.isNotEmpty)
        .map((p) => p[0].toUpperCase() + p.substring(1))
        .join(' ');
  }

  // -------------------------------------------------------------------------
  // Save
  // -------------------------------------------------------------------------

  bool get _canSave =>
      !_saving &&
      !_resolvingClasses &&
      _selectedName != null &&
      ((_selectedRxcui != null && _selectedRxcui!.isNotEmpty) ||
          _selectedClasses.isNotEmpty);

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _saving = true);

    final actions = ref.read(stackActionsProvider);
    final newId = await actions.addMedication(
      name: _selectedName!,
      rxcui: _selectedRxcui,
      genericRxcui: _selectedGenericRxcui,
      drugClasses: _selectedClasses,
      ingredientRxcuis: _ingredientRxcuis,
      dosage: _doseController.text.trim().isEmpty
          ? null
          : _doseController.text.trim(),
      frequency: _frequencyController.text.trim().isEmpty
          ? null
          : _frequencyController.text.trim(),
    );

    if (!mounted) return;

    // Depletion nudge (Phase 4 of depletion UX plan) — resolve whether
    // this medication has a gentle "since you take X, here's something
    // worth knowing" suggestion, and surface it once per (med, nutrient)
    // pair before we pop. This runs off the main add-medication path, so
    // any nudge failure must NOT block the save UI.
    try {
      await _maybeShowDepletionNudge(newId, _selectedName!, _selectedClasses);
    } on Exception {
      // Intentional: nudge is a non-critical enhancement. Never block
      // the save flow on its plumbing.
    }

    if (!mounted) return;
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop(newId);
    } else {
      // Screen mounted as the root (e.g. in widget tests) — there's
      // nothing to pop to. Reset save state so tests / callers that
      // rely on the post-save UI don't see a stuck spinner.
      setState(() => _saving = false);
    }
  }

  /// Compute and (if present) surface the depletion nudge for the
  /// medication we just saved. Reads the bundled depletions asset,
  /// filters by user-profile stack coverage, and presents a calm
  /// modal sheet. Tracks dismissal state in SharedPreferences so
  /// returning users don't re-see the same suggestion.
  Future<void> _maybeShowDepletionNudge(
    String newStackEntryId,
    String medicationName,
    List<String> drugClasses,
  ) async {
    final nudgeSvc = ref.read(medicationDepletionNudgeServiceProvider);
    final repo = ref.read(referenceDataRepositoryProvider);
    final Map<String, dynamic> depletionsData =
        await repo.loadMedicationDepletions();

    // Build coveredIds from existing supplements in the stack, same
    // logic as depletionReportProvider. We skip dose data here —
    // presence-only is enough to avoid nudging users who are already
    // at least partially covered.
    final stack = await ref.read(activeStackProvider.future);
    final coreDb = ref.read(coreDatabaseProvider);
    final coveredIds = <String>{};
    for (final supp in stack.where((e) => e.type == 'supplement')) {
      if (supp.dsldId == null) continue;
      final product = await coreDb.findById(supp.dsldId!);
      if (product?.keyIngredientTags == null) continue;
      try {
        final tags = jsonDecode(product!.keyIngredientTags!);
        if (tags is List) {
          for (final t in tags) {
            coveredIds.add(t.toString().toLowerCase());
          }
        }
      } on FormatException {
        // skip malformed rows
      }
    }

    final nudge = await nudgeSvc.computePendingNudge(
      stackEntryId: newStackEntryId,
      medicationName: medicationName,
      drugClassIds: drugClasses,
      depletionsData: depletionsData,
      stackCanonicalIds: coveredIds,
    );

    if (nudge == null || nudge.isEmpty) return;
    if (!mounted) return;
    final dismissed = await showDepletionNudgeSheet(context, nudge: nudge);
    // If user chose "Not now" (explicit dismiss) OR "Got it" (read and
    // acknowledged), mark the pair seen. Only leave it re-surfaceable
    // if the sheet closed via scrim/back — signals indecision, not
    // dismissal.
    if (dismissed == true || dismissed == false) {
      await nudgeSvc.markAllSeen(nudge);
    }
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add medication'),
        actions: [
          TextButton(
            key: const Key('med-entry-save'),
            onPressed: _canSave ? _save : null,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.all(AppTheme.space16),
          children: [
            _buildIntroCard(theme),
            const SizedBox(height: AppTheme.space16),
            PGSearchField(
              key: const Key('med-entry-search'),
              hintText: 'Search RxNorm — e.g. "warfarin"',
              controller: _searchController,
              onChanged: _onQueryChanged,
              autofocus: true,
            ),
            const SizedBox(height: AppTheme.space12),
            _buildSuggestionArea(theme),
            const SizedBox(height: AppTheme.space24),
            _buildSelectionSummary(theme),
            const SizedBox(height: AppTheme.space16),
            _buildOptionalFields(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildIntroCard(ThemeData theme) {
    return PGCard(
      variant: PGCardVariant.recessed,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.lock_outline_rounded,
            size: 20,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: AppTheme.space12),
          Expanded(
            child: Text(
              'Medications stay on this device. We use them only to '
              'check for interactions with your supplements.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestionArea(ThemeData theme) {
    if (_searching) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppTheme.space16),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_suggestions.isNotEmpty) {
      return Column(
        key: const Key('med-entry-suggestion-list'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final s in _suggestions)
            Padding(
              padding: const EdgeInsets.only(bottom: AppTheme.space8),
              child: PGCard(
                key: Key('med-entry-suggestion-${s.rxcui}'),
                onTap: () => _selectSuggestion(s),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.name,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'RxCUI ${s.rxcui}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    }

    if (_offlineFallbackVisible) {
      return _buildOfflineFallback(theme);
    }

    if (_query.trim().length >= 2) {
      return const PGEmptyState(
        icon: Icons.search_off_rounded,
        title: 'No matches',
        description: 'Try a different spelling, or pick a drug class below.',
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildOfflineFallback(ThemeData theme) {
    return Column(
      key: const Key('med-entry-offline-classes'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppTheme.space8),
          child: Text(
            "Can't reach RxNorm — pick a drug class so we can still "
            'check for interactions:',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Wrap(
          spacing: AppTheme.space8,
          runSpacing: AppTheme.space8,
          children: [
            for (final cls in _offlineClasses)
              ActionChip(
                key: Key('med-entry-class-$cls'),
                label: Text(_humanizeClass(cls)),
                onPressed: () => _selectOfflineClass(cls),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildSelectionSummary(ThemeData theme) {
    if (_selectedName == null) return const SizedBox.shrink();
    return PGCard(
      key: const Key('med-entry-selection-summary'),
      variant: PGCardVariant.highlighted,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _selectedName!,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppTheme.space4),
          if (_selectedRxcui != null)
            Text(
              'RxCUI ${_selectedRxcui!}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          if (_resolvingClasses)
            Padding(
              padding: const EdgeInsets.only(top: AppTheme.space8),
              child: Text(
                'Looking up drug classes…',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else if (_selectedClasses.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppTheme.space8),
              child: Wrap(
                spacing: AppTheme.space4,
                runSpacing: AppTheme.space4,
                children: [
                  for (final cls in _selectedClasses)
                    Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text(_humanizeClass(cls)),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOptionalFields(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Optional details',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppTheme.space8),
        TextField(
          key: const Key('med-entry-dose'),
          controller: _doseController,
          decoration: const InputDecoration(
            labelText: 'Dose (e.g. "5 mg")',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: AppTheme.space8),
        TextField(
          key: const Key('med-entry-frequency'),
          controller: _frequencyController,
          decoration: const InputDecoration(
            labelText: 'Frequency (e.g. "once daily")',
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }
}
