// Medication entry screen — M4 §8.5.
//
// Lets the user add a medication to their personal stack so the M4
// curated interaction checker can fan it against existing supplements.
//
// Flow:
//   1. Autocomplete text field hits `RxNormApiService.search()` on a
//      300 ms debounce. While the user is still typing or while the
//      query is in flight we show a shimmer suggestion list.
//   2. The user picks a suggestion → we resolve its rxcui's drug
//      classes via `RxNormApiService.getClasses()` so the curated
//      check can match class-level rows.
//   3. Optional dose / frequency text fields (for user reference only —
//      the interaction engine does not use them yet).
//   4. Save → calls `StackActions.addMedication()` which inserts a
//      `type='medication'` row with rxcui + drug_classes JSON. The
//      privacy grep test guarantees that path never reaches Supabase
//      sync.
//   5. After save we pop immediately, returning the new entry id so the
//      caller can fan a snackbar + kick off the post-add interaction
//      check. Depletion nudges surface later on the stack screen.
//
// Offline fallback (spec §8.4): if the autocomplete query yields zero
// suggestions AND we know we're offline, we surface the bundled
// drug-class picker — the user can still add a class-level entry
// without a network round-trip.
//
// The screen is intentionally feature-flag-free and self-contained.
// All HTTP / DB / sync calls are routed through Riverpod providers so
// widget tests can swap them out for fakes.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/core/constants/schema_ids.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/widgets/pg_card.dart';
import 'package:pharmaguide/core/widgets/pg_empty_state.dart';
import 'package:pharmaguide/core/widgets/pg_search_field.dart';
import 'package:pharmaguide/features/stack/providers/stack_providers.dart';
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

class _MedicationEntryScreenState extends ConsumerState<MedicationEntryScreen> {
  // Autocomplete state ------------------------------------------------------
  final _searchController = TextEditingController();
  final _doseController = TextEditingController();
  final _frequencyController = TextEditingController();

  Timer? _debounce;
  int _searchVersion = 0;

  String _query = '';
  bool _searching = false;
  List<RxNormSuggestion> _suggestions = const <RxNormSuggestion>[];

  bool _offlineFallbackVisible = false;
  List<String> _offlineClasses = const <String>[];

  // Selection state ---------------------------------------------------------
  String? _selectedName;
  String? _selectedRxcui;
  List<String> _selectedClasses = const <String>[];
  String? _selectedGenericRxcui;
  List<String> _ingredientRxcuis = const <String>[];
  bool _resolvingClasses = false;
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

    final classesFuture = _service.getClasses(suggestion.rxcui);
    final genericsFuture = _service.resolveGenericRxcuis(suggestion.rxcui);

    final classesResult = await classesFuture;
    final genericsResult = await genericsFuture;
    if (!mounted) return;

    setState(() {
      _selectedClasses = classesResult;
      _selectedGenericRxcui =
          genericsResult.isNotEmpty ? genericsResult.first : null;
      _ingredientRxcuis =
          genericsResult.length > 1 ? genericsResult : const <String>[];
      _resolvingClasses = false;
    });
  }

  void _selectOfflineClass(String classId) {
    setState(() {
      _selectedName = _friendlyClassLabel(classId);
      _selectedRxcui = null;
      _selectedClasses = <String>[classId];
      _searchController.text = _friendlyClassLabel(classId);
      _searchController.selection = TextSelection.fromPosition(
        TextPosition(offset: _searchController.text.length),
      );
      _suggestions = const <RxNormSuggestion>[];
      _offlineFallbackVisible = false;
    });
  }

  /// Look up the user-friendly label from SchemaIds.drugClassLabels,
  /// falling back to a humanized version of the slug.
  static String _friendlyClassLabel(String classId) {
    final stripped =
        classId.startsWith('class:') ? classId.substring(6) : classId;
    return SchemaIds.drugClassLabels[stripped] ?? _humanizeSlug(stripped);
  }

  /// `ace_inhibitors` → `Ace Inhibitors`.
  static String _humanizeSlug(String slug) {
    return slug
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

    // Pop immediately — the first reward should be "medication added,
    // we'll now check interactions." Depletion nudges surface later on
    // the stack screen, not as a blocking modal here.
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop(newId);
    } else {
      setState(() => _saving = false);
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
        title: const Text('Add a medication'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(AppTheme.space16),
                children: [
                  _buildIntroCard(theme),
                  const SizedBox(height: AppTheme.space16),
                  PGSearchField(
                    key: const Key('med-entry-search'),
                    hintText: 'Search medication name',
                    controller: _searchController,
                    onChanged: _onQueryChanged,
                    autofocus: true,
                  ),
                  if (_query.trim().length < 2) ...[
                    const SizedBox(height: AppTheme.space8),
                    Text(
                      'Try "warfarin," "metformin," or "levothyroxine."',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppTheme.space12),
                  _buildSuggestionArea(theme),
                  const SizedBox(height: AppTheme.space24),
                  _buildSelectionSummary(theme),
                  const SizedBox(height: AppTheme.space16),
                  _buildOptionalFields(theme),
                  // Extra bottom padding so content isn't hidden behind
                  // the sticky button.
                  const SizedBox(height: 80),
                ],
              ),
            ),
            // Sticky bottom CTA
            _buildStickyButton(theme),
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
              'Your medication list is private. We use it only to check '
              'supplement interactions on this device.',
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
                      child: Text(
                        s.name,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
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
        description: 'Try a different spelling, or pick a medication type below.',
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
            "We couldn't search medications right now.\n"
            'Choose a medication type instead so we can still check '
            'common interactions.',
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
                label: Text(_friendlyClassLabel(cls)),
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
            'Selected',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: AppTheme.space4),
          Text(
            _selectedName!,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (_resolvingClasses)
            Padding(
              padding: const EdgeInsets.only(top: AppTheme.space8),
              child: Text(
                'Looking up interaction categories\u2026',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else if (_selectedClasses.isNotEmpty) ...[
            const SizedBox(height: AppTheme.space4),
            Text(
              'Used to check: ${_selectedClasses.map(_friendlyClassLabel).join(', ')}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOptionalFields(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Optional',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppTheme.space4),
        Text(
          'Add dose or schedule for your own reference.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppTheme.space12),
        TextField(
          key: const Key('med-entry-dose'),
          controller: _doseController,
          decoration: const InputDecoration(
            labelText: 'Dose',
            hintText: 'e.g. 5 mg',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: AppTheme.space8),
        TextField(
          key: const Key('med-entry-frequency'),
          controller: _frequencyController,
          decoration: const InputDecoration(
            labelText: 'Schedule',
            hintText: 'e.g. once daily',
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }

  Widget _buildStickyButton(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.space16,
        AppTheme.space12,
        AppTheme.space16,
        AppTheme.space16,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: FilledButton(
          key: const Key('med-entry-save'),
          onPressed: _canSave ? _save : null,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Add medication'),
        ),
      ),
    );
  }
}
