// MedicationEntry v2 — production add-medication surface.
//
// Sean's rule: same medication engine, same RxNorm API, same
// `StackActions.addMedication` contract. Every state machine field,
// debounce constant, key constant, snackbar copy, and method name maps
// to the original medication behavior so the route promotion changed
// presentation without changing the saved payload.
//
// Snackbar routing fix (Sean 2026-05-16):
//
//   The previous route showed its "added — checking interactions"
//   confirmation snackbar via `ScaffoldMessenger.of(context)`
//   immediately before popping. The snackbar overlay attached to
//   the Scaffold that was about to be torn down, so the user often
//   saw nothing on the destination screen. The fix routes the
//   snackbar through the root
//   `scaffoldMessengerKey` (set in `main.dart`) so it lives on
//   the parent surface and survives the pop.
//
// Visual contract:
//
// * Cream Scaffold (`V2Colors.bg`), no Material AppBar.
// * Top row with a back chip + page eyebrow "Add medication".
// * Newsreader serif title that explains the difference between
//   adding a SPECIFIC medication to the stack vs setting
//   MEDICATION CLASSES in the Health Profile.
// * v2 search field (cream surface, accent focus, search icon).
// * Suggestion rows are cream `_SuggestionRow` tiles with the
//   chevron-right affordance every other v2 tile uses.
// * Selection summary is a cream highlighted card with an accent
//   ring + "Change" link.
// * Offline drug-class fallback opens a `PGSelectionSheet` in
//   single-select rows mode rather than dumping a wrap of chips
//   into the body — picking a class is a deliberate action and
//   the sheet pattern matches Profile's age / sex selectors.
// * Optional dose field uses the same `_V2TextField`-style box
//   as ProfileSetup's nickname.
// * Schedule chips use `PGGoalChip` so chip styling matches
//   ProfileSetup goals.
// * Sticky bottom Save uses `PGPillButton.primary` expanded.
//
// Behavior contract:
//
// * `RxNormApiService.search() / .getClasses() / .resolveGenericRxcuis()
//   / .offlineDrugClasses()` calls are byte-identical.
// * `StackActions.addMedication(...)` payload is byte-identical
//   (rxcui, genericRxcui, drugClasses, ingredientRxcuis, dosage,
//   frequency).
// * Debounce timing (300ms), search version semantics, selection
//   suppression of the empty state — all preserved.
// * Schedule cadence options + canonical strings written into the
//   `_frequencyController` (the chip selector from Phase 11.7j.9
//   that Sean approved).
// * Widget-test key constants (med-entry-search,
//   med-entry-suggestion-${rxcui}, med-entry-selection-summary,
//   med-entry-dose, med-entry-freq-*, med-entry-save,
//   med-entry-class-picker, med-entry-suggestion-list,
//   med-entry-class-${classId}).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/components/pg_empty_state.dart';
import 'package:pharmaguide/core/components/pg_eyebrow.dart';
import 'package:pharmaguide/core/components/pg_goal_chip.dart';
import 'package:pharmaguide/core/components/pg_pill_button.dart';
import 'package:pharmaguide/core/components/pg_selection_sheet.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/core/constants/schema_ids.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_motion.dart';
import 'package:pharmaguide/core/theme/v2/v2_shadows.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/features/stack/providers/stack_providers.dart';
import 'package:pharmaguide/services/medications/rxnorm_api_service.dart';
import 'package:pharmaguide/services/medications/rxnorm_providers.dart';
import 'package:pharmaguide/app.dart' show scaffoldMessengerKey;

class MedicationEntryV2Screen extends ConsumerStatefulWidget {
  const MedicationEntryV2Screen({super.key});

  @override
  ConsumerState<MedicationEntryV2Screen> createState() =>
      _MedicationEntryV2ScreenState();
}

class _MedicationEntryV2ScreenState
    extends ConsumerState<MedicationEntryV2Screen> {
  // ───────── controllers + ephemeral state ─────────
  final _searchController = TextEditingController();
  final _doseController = TextEditingController();
  final _frequencyController = TextEditingController();
  final _searchFocusNode = FocusNode();

  Timer? _debounce;
  int _searchVersion = 0;

  String _query = '';
  bool _searching = false;
  List<RxNormSuggestion> _suggestions = const <RxNormSuggestion>[];

  bool _offlineFallbackVisible = false;
  List<String> _offlineClasses = const <String>[];

  String? _selectedName;
  String? _selectedRxcui;
  List<String> _selectedClasses = const <String>[];
  String? _selectedGenericRxcui;
  List<String> _ingredientRxcuis = const <String>[];
  bool _resolvingClasses = false;
  bool _saving = false;

  // Canonical schedule options. Sean 2026-05-16 — same string set
  // and canonical text the downstream interaction logic expects.
  static const List<String> _scheduleOptions = [
    'Once daily',
    'Twice daily',
    '3× daily',
    '4× daily',
    'Weekly',
    'As needed',
  ];

  @override
  void initState() {
    super.initState();
    _searchFocusNode.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _doseController.dispose();
    _frequencyController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  RxNormApiService get _service => ref.read(rxNormApiServiceProvider);

  // ───────── autocomplete plumbing ─────────

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

  // ───────── selection plumbing ─────────

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
    _searchFocusNode.unfocus();

    final classesFuture = _service.getClasses(suggestion.rxcui);
    final genericsFuture = _service.resolveGenericRxcuis(suggestion.rxcui);

    final classesResult = await classesFuture;
    final genericsResult = await genericsFuture;
    if (!mounted) return;

    setState(() {
      _selectedClasses = classesResult;
      _selectedGenericRxcui = genericsResult.isNotEmpty
          ? genericsResult.first
          : null;
      _ingredientRxcuis = genericsResult.length > 1
          ? genericsResult
          : const <String>[];
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
    _searchFocusNode.unfocus();
  }

  /// 'class:ace_inhibitors' → 'ACE Inhibitors'. Resolves through
  /// `SchemaIds.drugClassLabels` first and falls back to a
  /// humanized slug.
  static String _friendlyClassLabel(String classId) {
    final stripped = classId.startsWith('class:')
        ? classId.substring(6)
        : classId;
    return SchemaIds.drugClassLabels[stripped] ?? _humanizeSlug(stripped);
  }

  static String _humanizeSlug(String slug) {
    return slug
        .split('_')
        .where((p) => p.isNotEmpty)
        .map((p) => p[0].toUpperCase() + p.substring(1))
        .join(' ');
  }

  void _clearSelection() {
    setState(() {
      _selectedName = null;
      _selectedRxcui = null;
      _selectedGenericRxcui = null;
      _ingredientRxcuis = const <String>[];
      _selectedClasses = const <String>[];
      _searchController.clear();
      _query = '';
      _suggestions = const <RxNormSuggestion>[];
      _offlineFallbackVisible = false;
    });
    _searchFocusNode.requestFocus();
  }

  // ───────── save (stable payload, hardened snackbar) ─────────

  bool get _canSave =>
      !_saving &&
      !_resolvingClasses &&
      _selectedName != null &&
      ((_selectedRxcui != null && _selectedRxcui!.isNotEmpty) ||
          _selectedClasses.isNotEmpty);

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _saving = true);
    unawaited(HapticFeedback.mediumImpact());

    final actions = ref.read(stackActionsProvider);
    final String newId;
    try {
      newId = await actions.addMedication(
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
    } on StackRequiresSignInException {
      if (!mounted) return;
      setState(() => _saving = false);
      await context.push(Routes.authInvitation);
      return;
    }

    if (!mounted) return;

    // **Sean 2026-05-16 snackbar bug fix.**
    // Showing this snackbar on the local Scaffold immediately before
    // popping can attach it to an about-to-be-disposed overlay. Route
    // through the ROOT scaffold messenger
    // (set on MaterialApp.router via `scaffoldMessengerKey`) so it
    // lives on the parent surface and survives the pop.
    scaffoldMessengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            '${_selectedName!} added — checking interactions…',
            style: V2Typography.bodySm(color: V2Colors.bg),
          ),
          backgroundColor: V2Colors.accent,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(V2Spacing.space16),
          duration: const Duration(seconds: 3),
        ),
      );

    // Pop back to caller. Stack auto-refreshes via _invalidate
    // inside StackActions.addMedication.
    final router = GoRouter.of(context);
    if (router.canPop()) {
      router.pop(newId);
    } else {
      // Standalone deep link → no one to pop to. Fall back to the
      // stack screen so the user sees their newly added medication.
      router.go(Routes.stack);
    }
  }

  // ───────── sheets ─────────

  Future<void> _openClassSheet() async {
    if (_offlineClasses.isEmpty) return;
    final options = [
      for (final c in _offlineClasses)
        PGSelectionOption(
          id: c,
          // Keep the stable selection key naming used by widget tests.
          label: _friendlyClassLabel(c),
        ),
    ];
    final result = await showPGSelectionSheet(
      context: context,
      eyebrow: 'Medication classes',
      title: "Can't find your medication?",
      helperText:
          "Pick the class so we can still catch common interactions. "
          "This adds a class-level entry to your stack — it doesn't "
          'change your Health Profile.',
      options: options,
      initialSelection: const <String>{},
      singleSelect: true,
      layout: PGSheetLayout.rows,
      dismissLabel: 'Never mind',
    );
    if (result == null || !mounted) return;
    if (result.selected.isEmpty) return;
    _selectOfflineClass(result.selected.first);
  }

  // ───────── build ─────────

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: V2Colors.bg,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: V2Colors.bg,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _TopBar(
                onBack: () {
                  final router = GoRouter.of(context);
                  if (router.canPop()) {
                    router.pop();
                  } else {
                    router.go(Routes.home);
                  }
                },
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    V2Spacing.space24,
                    V2Spacing.space8,
                    V2Spacing.space24,
                    96, // sticky save bar clearance
                  ),
                  children: [
                    const _Header(),
                    const SizedBox(height: V2Spacing.space24),
                    const _PrivacyRow(),
                    const SizedBox(height: V2Spacing.space24),
                    _SearchSection(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      onChanged: _onQueryChanged,
                      onClear: _clearSelection,
                      hasSelection: _selectedName != null,
                      query: _query,
                    ),
                    const SizedBox(height: V2Spacing.space12),
                    _SuggestionArea(
                      selectedName: _selectedName,
                      searching: _searching,
                      suggestions: _suggestions,
                      query: _query,
                      offlineFallbackVisible: _offlineFallbackVisible,
                      onSelectSuggestion: _selectSuggestion,
                      onOpenClassSheet: _openClassSheet,
                    ),
                    if (_selectedName != null) ...[
                      const SizedBox(height: V2Spacing.space24),
                      _SelectionSummary(
                        name: _selectedName!,
                        resolvingClasses: _resolvingClasses,
                        classes: _selectedClasses,
                        identityCoverageLimited:
                            !_resolvingClasses &&
                            (_selectedRxcui ?? '').trim().isNotEmpty &&
                            (_selectedGenericRxcui ?? '').trim().isEmpty &&
                            _ingredientRxcuis.isEmpty,
                        friendlyClassLabel: _friendlyClassLabel,
                        onChange: _clearSelection,
                      ),
                    ],
                    const SizedBox(height: V2Spacing.space32),
                    _OptionalSection(
                      doseController: _doseController,
                      frequencyController: _frequencyController,
                      scheduleOptions: _scheduleOptions,
                    ),
                  ],
                ),
              ),
              _StickySaveBar(saving: _saving, canSave: _canSave, onSave: _save),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Top bar — back chip + page eyebrow.
// =============================================================================

class _TopBar extends StatelessWidget {
  final VoidCallback onBack;

  const _TopBar({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        V2Spacing.space16,
        V2Spacing.space12,
        V2Spacing.space16,
        0,
      ),
      child: SizedBox(
        height: 40,
        child: Row(
          children: [
            SizedBox(
              width: 40,
              child: IconButton(
                icon: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: V2Colors.fg,
                  size: 18,
                ),
                onPressed: onBack,
                splashRadius: 20,
              ),
            ),
            const Expanded(child: Center(child: PGEyebrow('Add medication'))),
            const SizedBox(width: 40),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Header — Newsreader title + body helper clarifying specific
// medications (stack) vs medication classes (Health Profile).
// =============================================================================

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Add a medication you take.',
          style: V2Typography.displaySm(color: V2Colors.fg),
        ),
        const SizedBox(height: V2Spacing.space12),
        Text(
          'PharmaGuide uses this to flag supplement–medication '
          'interactions. To set broader medication classes, edit your '
          'Health Profile.',
          style: V2Typography.body(color: V2Colors.fgMuted),
        ),
      ],
    );
  }
}

// =============================================================================
// Privacy row — calm lock-icon affordance, no bordered container.
// =============================================================================

class _PrivacyRow extends StatelessWidget {
  const _PrivacyRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.lock_outline_rounded,
          size: 14,
          color: V2Colors.fgMuted,
        ),
        const SizedBox(width: V2Spacing.space8),
        Expanded(
          child: Text(
            'Your medication list stays on this device. Used only to '
            'check supplement interactions.',
            style: V2Typography.caption(color: V2Colors.fgMuted),
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// Search section — cream search field, focus-on-accent.
// =============================================================================

class _SearchSection extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final bool hasSelection;
  final String query;

  const _SearchSection({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onClear,
    required this.hasSelection,
    required this.query,
  });

  @override
  Widget build(BuildContext context) {
    final focused = focusNode.hasFocus;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PGEyebrow('Find your medication', color: V2Colors.fgMuted),
        const SizedBox(height: V2Spacing.space12),
        AnimatedContainer(
          duration: V2Motion.fast,
          curve: V2Motion.smooth,
          padding: const EdgeInsets.symmetric(horizontal: V2Spacing.space12),
          decoration: BoxDecoration(
            color: V2Colors.surface,
            borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
            border: Border.all(
              color: focused ? V2Colors.accent : V2Colors.outline,
              width: focused ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.search_rounded,
                size: 18,
                color: focused ? V2Colors.accent : V2Colors.fgSubtle,
              ),
              const SizedBox(width: V2Spacing.space8),
              Expanded(
                child: TextField(
                  key: const Key('med-entry-search'),
                  controller: controller,
                  focusNode: focusNode,
                  autofocus: true,
                  maxLines: 1,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search your medication',
                    hintStyle: V2Typography.body(color: V2Colors.fgSubtle),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: V2Spacing.space12,
                    ),
                    isCollapsed: true,
                    isDense: true,
                  ),
                  style: V2Typography.body(color: V2Colors.fg),
                  cursorColor: V2Colors.accent,
                  cursorWidth: 1.5,
                  onChanged: onChanged,
                ),
              ),
              if (controller.text.isNotEmpty)
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: const Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: V2Colors.fgSubtle,
                  ),
                  onPressed: onClear,
                  splashRadius: 16,
                ),
            ],
          ),
        ),
        if (query.trim().length < 2 && !hasSelection) ...[
          const SizedBox(height: V2Spacing.space8),
          Text(
            'Try "warfarin", "metformin", or "levothyroxine".',
            style: V2Typography.caption(color: V2Colors.fgMuted),
          ),
        ],
      ],
    );
  }
}

// =============================================================================
// Suggestion area — selected suppresses entirely (Phase 11.7j.9 fix
// preserved); searching shows a calm cream skeleton placeholder; hits
// render as cream `_SuggestionRow` tiles; misses show an empty state
// + "Pick a class" tile that opens the sheet.
// =============================================================================

class _SuggestionArea extends StatelessWidget {
  final String? selectedName;
  final bool searching;
  final List<RxNormSuggestion> suggestions;
  final String query;
  final bool offlineFallbackVisible;
  final ValueChanged<RxNormSuggestion> onSelectSuggestion;
  final VoidCallback onOpenClassSheet;

  const _SuggestionArea({
    required this.selectedName,
    required this.searching,
    required this.suggestions,
    required this.query,
    required this.offlineFallbackVisible,
    required this.onSelectSuggestion,
    required this.onOpenClassSheet,
  });

  @override
  Widget build(BuildContext context) {
    // Selection is the source of truth — suppress suggestions AND
    // the empty state so we never render "no match" over a chosen
    // medication. Sean's Phase 11.7j.9 invariant preserved.
    if (selectedName != null) return const SizedBox.shrink();

    if (searching) {
      return const _SearchSkeleton();
    }

    if (suggestions.isNotEmpty) {
      return Column(
        key: const Key('med-entry-suggestion-list'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final s in suggestions)
            Padding(
              padding: const EdgeInsets.only(bottom: V2Spacing.space8),
              child: _SuggestionRow(
                key: Key('med-entry-suggestion-${s.rxcui}'),
                name: s.name,
                onTap: () => onSelectSuggestion(s),
              ),
            ),
        ],
      );
    }

    if (query.trim().length >= 2) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PGEmptyState(
            icon: Icons.search_off_rounded,
            headline: 'No match found',
            body:
                "Try a different spelling. If you can't find it, "
                "pick the medication class below — we'll still check "
                'common interactions.',
          ),
          if (offlineFallbackVisible) ...[
            const SizedBox(height: V2Spacing.space16),
            _ClassFallbackTile(onTap: onOpenClassSheet),
          ],
        ],
      );
    }

    return const SizedBox.shrink();
  }
}

class _SuggestionRow extends StatelessWidget {
  final String name;
  final VoidCallback onTap;

  const _SuggestionRow({super.key, required this.name, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: V2Colors.surface,
      borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
            border: Border.all(color: V2Colors.outline),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: V2Spacing.space16,
            vertical: V2Spacing.space16,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  style: V2Typography.bodyMedium(color: V2Colors.fg),
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: V2Colors.fgSubtle),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClassFallbackTile extends StatelessWidget {
  final VoidCallback onTap;

  const _ClassFallbackTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: V2Colors.surface,
      borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
      child: InkWell(
        key: const Key('med-entry-class-picker'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
            border: Border.all(color: V2Colors.outline),
            boxShadow: V2Shadows.sm,
          ),
          padding: const EdgeInsets.fromLTRB(
            V2Spacing.space16,
            V2Spacing.space16,
            V2Spacing.space12,
            V2Spacing.space16,
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: V2Colors.accentTint,
                  borderRadius: BorderRadius.circular(V2Spacing.space8),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.list_alt_outlined,
                  size: 18,
                  color: V2Colors.accent,
                ),
              ),
              const SizedBox(width: V2Spacing.space16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const PGEyebrow(
                      'Medication classes',
                      color: V2Colors.fgMuted,
                    ),
                    const SizedBox(height: V2Spacing.space4),
                    Text(
                      'Pick a class instead',
                      style: V2Typography.titleSm(color: V2Colors.fg),
                    ),
                    const SizedBox(height: V2Spacing.space4),
                    Text(
                      'Catches the most common interactions when an '
                      'exact match isn\'t available.',
                      style: V2Typography.caption(color: V2Colors.fgMuted),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: V2Colors.fgSubtle),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchSkeleton extends StatelessWidget {
  const _SearchSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < 2; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: V2Spacing.space8),
            child: Container(
              decoration: BoxDecoration(
                color: V2Colors.surface,
                borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
                border: Border.all(color: V2Colors.outline),
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: V2Spacing.space16,
                vertical: V2Spacing.space16,
              ),
              child: Row(
                children: [
                  Container(
                    width: 140,
                    height: 14,
                    decoration: BoxDecoration(
                      color: V2Colors.outline,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const Spacer(),
                  Container(
                    width: 12,
                    height: 12,
                    decoration: const BoxDecoration(
                      color: V2Colors.outline,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// =============================================================================
// Selection summary — cream card with accent-tint ring + "Change"
// affordance in the v2 surface language.
// =============================================================================

class _SelectionSummary extends StatelessWidget {
  final String name;
  final bool resolvingClasses;
  final List<String> classes;
  final bool identityCoverageLimited;
  final String Function(String) friendlyClassLabel;
  final VoidCallback onChange;

  const _SelectionSummary({
    required this.name,
    required this.resolvingClasses,
    required this.classes,
    required this.identityCoverageLimited,
    required this.friendlyClassLabel,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('med-entry-selection-summary'),
      decoration: BoxDecoration(
        color: V2Colors.accentTint,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        border: Border.all(color: V2Colors.accent, width: 1.5),
      ),
      padding: const EdgeInsets.all(V2Spacing.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const PGEyebrow('Selected'),
              const Spacer(),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onChange,
                child: Text(
                  'Change',
                  style: V2Typography.label(color: V2Colors.accent),
                ),
              ),
            ],
          ),
          const SizedBox(height: V2Spacing.space8),
          Text(name, style: V2Typography.title(color: V2Colors.fg)),
          if (resolvingClasses) ...[
            const SizedBox(height: V2Spacing.space8),
            Text(
              'Looking up interaction categories…',
              style: V2Typography.caption(color: V2Colors.fgMuted),
            ),
          ] else if (classes.isNotEmpty) ...[
            const SizedBox(height: V2Spacing.space8),
            Text(
              'Used to check: ${classes.map(friendlyClassLabel).join(", ")}',
              style: V2Typography.caption(color: V2Colors.fgMuted),
            ),
          ],
          if (!resolvingClasses && identityCoverageLimited) ...[
            const SizedBox(height: V2Spacing.space8),
            Text(
              'We will check this medication, but generic matching may be limited.',
              style: V2Typography.caption(color: V2Colors.fgMuted),
            ),
          ],
        ],
      ),
    );
  }
}

// =============================================================================
// Optional fields — dose text field + schedule chips.
// =============================================================================

class _OptionalSection extends StatefulWidget {
  final TextEditingController doseController;
  final TextEditingController frequencyController;
  final List<String> scheduleOptions;

  const _OptionalSection({
    required this.doseController,
    required this.frequencyController,
    required this.scheduleOptions,
  });

  @override
  State<_OptionalSection> createState() => _OptionalSectionState();
}

class _OptionalSectionState extends State<_OptionalSection> {
  final FocusNode _doseFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _doseFocus.addListener(() => setState(() {}));
    widget.frequencyController.addListener(_onFrequencyChanged);
  }

  @override
  void dispose() {
    _doseFocus.dispose();
    widget.frequencyController.removeListener(_onFrequencyChanged);
    super.dispose();
  }

  void _onFrequencyChanged() {
    if (mounted) setState(() {});
  }

  void _toggleSchedule(String option) {
    final current = widget.frequencyController.text;
    widget.frequencyController.text = current == option ? '' : option;
  }

  @override
  Widget build(BuildContext context) {
    final doseFocused = _doseFocus.hasFocus;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PGEyebrow('Optional', color: V2Colors.fgMuted),
        const SizedBox(height: V2Spacing.space8),
        Text(
          'Add dose or schedule for your own reference.',
          style: V2Typography.caption(color: V2Colors.fgMuted),
        ),
        const SizedBox(height: V2Spacing.space16),
        Text('Dose', style: V2Typography.label(color: V2Colors.fg)),
        const SizedBox(height: V2Spacing.space8),
        AnimatedContainer(
          duration: V2Motion.fast,
          curve: V2Motion.smooth,
          padding: const EdgeInsets.symmetric(horizontal: V2Spacing.space12),
          decoration: BoxDecoration(
            color: V2Colors.surface,
            borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
            border: Border.all(
              color: doseFocused ? V2Colors.accent : V2Colors.outline,
              width: doseFocused ? 1.5 : 1.0,
            ),
          ),
          child: TextField(
            key: const Key('med-entry-dose'),
            controller: widget.doseController,
            focusNode: _doseFocus,
            maxLines: 1,
            // Sean 2026-05-16: dose entry defaults to the numeric pad.
            // Mirrors the same fix on v1 `medication_entry_screen.dart`
            // — users can still switch the keyboard to letters via the
            // 123↔ABC button to append a unit like "mg" if they want.
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              hintText: 'e.g. 5 mg',
              hintStyle: V2Typography.body(color: V2Colors.fgSubtle),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                vertical: V2Spacing.space16,
              ),
              isCollapsed: true,
              isDense: true,
            ),
            style: V2Typography.body(color: V2Colors.fg),
            cursorColor: V2Colors.accent,
            cursorWidth: 1.5,
          ),
        ),
        const SizedBox(height: V2Spacing.space24),
        Text('Schedule', style: V2Typography.label(color: V2Colors.fg)),
        const SizedBox(height: V2Spacing.space12),
        Wrap(
          spacing: V2Spacing.space8,
          runSpacing: V2Spacing.space8,
          children: [
            for (final option in widget.scheduleOptions)
              KeyedSubtree(
                key: Key(
                  'med-entry-freq-${option.toLowerCase().replaceAll(RegExp(r'\W+'), '-')}',
                ),
                child: PGGoalChip(
                  label: option,
                  selected: widget.frequencyController.text == option,
                  onTap: () => _toggleSchedule(option),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

// =============================================================================
// Sticky save bar.
// =============================================================================

class _StickySaveBar extends StatelessWidget {
  final bool saving;
  final bool canSave;
  final VoidCallback onSave;

  const _StickySaveBar({
    required this.saving,
    required this.canSave,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: V2Colors.bg,
        border: Border(top: BorderSide(color: V2Colors.outline)),
      ),
      padding: EdgeInsets.fromLTRB(
        V2Spacing.space24,
        V2Spacing.space12,
        V2Spacing.space24,
        MediaQuery.of(context).padding.bottom + V2Spacing.space12,
      ),
      child: KeyedSubtree(
        key: const Key('med-entry-save'),
        child: PGPillButton(
          label: saving ? 'Saving…' : 'Add medication',
          expand: true,
          onPressed: (saving || !canSave) ? null : onSave,
        ),
      ),
    );
  }
}
