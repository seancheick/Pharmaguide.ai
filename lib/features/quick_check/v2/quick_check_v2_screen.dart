// QuickCheck v2 — Phase 11.7L.E.3.
//
// Visual mirror of `QuickCheckScreen` ("Safe to Take Together?") on
// the v2 design system. Same pair-check logic, same providers, same
// result states, same routing — only the chrome and the result card
// change.
//
// What this screen does NOT touch:
//
//   * `coreDatabaseProvider.searchProducts(query, limit: 8)` — the
//     debounced autocomplete on both fields.
//   * `interactionDatabaseProvider` lookup via the existing
//     `runPairCheck(a, b, db)` helper in `quick_check_logic.dart`.
//   * The four legacy result states (error / insufficientData /
//     clean / has-interactions) and the 300ms debounce.
//   * The severity-gated `PGHaptics.forSeverity` celebration / nudge
//     that fires when results land.
//
// What it does change visually:
//
//   * Cream `V2Colors.bg` Scaffold, no Material AppBar.
//   * Top row: back chip + page eyebrow "Check together".
//   * Newsreader serif header that names the moment plainly
//     ("Check two things together.") plus a calm helper line.
//   * Two `_ProductSearchSection` cards — cream surface + v2 search
//     field (accent-on-focus). Suggestions render inline below
//     the field as cream pressable rows, each showing product name
//     + brand + quality score chip. Selecting a product collapses
//     the search into a cream "selected" tile with a Change CTA.
//   * Check button is `PGPillButton.primary` expanded with a
//     severity-neutral icon. Loading state replaces the icon with
//     a small accent spinner.
//   * Result card families:
//       - **Error** — cream card with `Icons.cloud_off_rounded` in
//         caution and a "Database unavailable" headline.
//       - **Insufficient data** — cream card with
//         `Icons.help_outline_rounded` in monitor and a
//         "Ingredient data is incomplete" headline. Sean
//         requirement #7: the fallback behavior the legacy screen
//         already implements (one or both products missing
//         ingredient data) renders here unchanged.
//       - **Clean** — `V2Colors.safe` accent-tint card with a
//         check icon, "No known interactions" headline, and a
//         calm "Always check with your clinician" footer.
//       - **One or more interactions** — count badge eyebrow at
//         the top, then one `_InteractionCard` per result. Each
//         card shows item A · item B, the severity verdict with
//         label + tint, the mechanism (reason), the management
//         (recommended action), and the evidence level overline.
//         Cards stack with 12pt rhythm.
//
// What did NOT change in copy:
//
//   * No new scary language. Severity labels come from the
//     existing `Severity.label` strings ("Do not use" /
//     "Not recommended" / "Use caution" / "Monitor" /
//     "Informational" / "Safe"), which Sean tuned in the
//     2026-04-30 softer-tone sweep.
//   * The "educational information, not medical advice" disclaimer
//     under the results list is preserved verbatim.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/components/pg_eyebrow.dart';
import 'package:pharmaguide/core/components/pg_pill_button.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/models/interaction_result.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_motion.dart';
import 'package:pharmaguide/core/theme/v2/v2_shadows.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/core/widgets/pg_haptics.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/quick_check/quick_check_logic.dart';

class QuickCheckV2Screen extends ConsumerStatefulWidget {
  const QuickCheckV2Screen({super.key});

  @override
  ConsumerState<QuickCheckV2Screen> createState() =>
      _QuickCheckV2ScreenState();
}

class _QuickCheckV2ScreenState extends ConsumerState<QuickCheckV2Screen> {
  // ───────── state (1:1 with legacy) ─────────
  final _controller1 = TextEditingController();
  final _controller2 = TextEditingController();
  final _focus1 = FocusNode();
  final _focus2 = FocusNode();

  List<ProductsCoreData> _suggestions1 = const [];
  List<ProductsCoreData> _suggestions2 = const [];
  ProductsCoreData? _product1;
  ProductsCoreData? _product2;

  List<InteractionResult>? _results;
  bool _checking = false;
  bool _checkError = false;
  bool _insufficientData = false;
  Timer? _debounce1;
  Timer? _debounce2;

  @override
  void initState() {
    super.initState();
    _focus1.addListener(() => setState(() {}));
    _focus2.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller1.dispose();
    _controller2.dispose();
    _focus1.dispose();
    _focus2.dispose();
    _debounce1?.cancel();
    _debounce2?.cancel();
    super.dispose();
  }

  void _onQuery1Changed(String query) {
    _debounce1?.cancel();
    if (query.trim().length < 2) {
      setState(() => _suggestions1 = const []);
      return;
    }
    _debounce1 = Timer(const Duration(milliseconds: 300), () async {
      final db = ref.read(coreDatabaseProvider);
      final results = await db.searchProducts(query.trim(), limit: 8);
      if (mounted) setState(() => _suggestions1 = results);
    });
  }

  void _onQuery2Changed(String query) {
    _debounce2?.cancel();
    if (query.trim().length < 2) {
      setState(() => _suggestions2 = const []);
      return;
    }
    _debounce2 = Timer(const Duration(milliseconds: 300), () async {
      final db = ref.read(coreDatabaseProvider);
      final results = await db.searchProducts(query.trim(), limit: 8);
      if (mounted) setState(() => _suggestions2 = results);
    });
  }

  void _selectProduct1(ProductsCoreData product) {
    setState(() {
      _product1 = product;
      _suggestions1 = const [];
      _results = null;
      _controller1.text = product.productName;
    });
    _focus1.unfocus();
  }

  void _selectProduct2(ProductsCoreData product) {
    setState(() {
      _product2 = product;
      _suggestions2 = const [];
      _results = null;
      _controller2.text = product.productName;
    });
    _focus2.unfocus();
  }

  void _clearProduct1() {
    setState(() {
      _product1 = null;
      _controller1.clear();
      _suggestions1 = const [];
      _results = null;
    });
  }

  void _clearProduct2() {
    setState(() {
      _product2 = null;
      _controller2.clear();
      _suggestions2 = const [];
      _results = null;
    });
  }

  Future<void> _checkInteractions() async {
    if (_product1 == null || _product2 == null) return;
    setState(() {
      _checking = true;
      _results = null;
      _checkError = false;
      _insufficientData = false;
    });
    unawaited(HapticFeedback.selectionClick());

    try {
      final interactionDb = ref.read(interactionDatabaseProvider);
      final idsA = extractCanonicalIds(_product1!.ingredientFingerprint);
      final idsB = extractCanonicalIds(_product2!.ingredientFingerprint);
      if (idsA.isEmpty || idsB.isEmpty) {
        if (mounted) {
          setState(() {
            _insufficientData = true;
            _checking = false;
          });
        }
        return;
      }

      final results = await runPairCheck(
        _product1!,
        _product2!,
        interactionDb,
      );
      if (!mounted) return;
      setState(() {
        _results = results;
        _checking = false;
      });
      // Severity-gated haptic — matches the legacy screen's
      // "feel the verdict before reading it" pattern.
      if (results.isNotEmpty) {
        final worst = results.fold<Severity>(
          Severity.safe,
          (acc, r) => r.severity.index < acc.index ? r.severity : acc,
        );
        if (mounted) unawaited(PGHaptics.forSeverity(worst, context));
      } else {
        if (mounted) unawaited(PGHaptics.success(context));
      }
    } on UnimplementedError {
      if (mounted) {
        setState(() {
          _checkError = true;
          _checking = false;
        });
      }
    } on Exception {
      if (mounted) {
        setState(() {
          _checkError = true;
          _checking = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final canCheck = _product1 != null && _product2 != null && !_checking;

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
              _TopBar(onBack: () {
                final router = GoRouter.of(context);
                if (router.canPop()) {
                  router.pop();
                } else {
                  router.go(Routes.home);
                }
              }),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    V2Spacing.space24,
                    V2Spacing.space8,
                    V2Spacing.space24,
                    V2Spacing.space48,
                  ),
                  children: [
                    const _Header(),
                    const SizedBox(height: V2Spacing.space24),
                    _ProductSearchSection(
                      eyebrow: 'First product',
                      icon: Icons.looks_one_outlined,
                      controller: _controller1,
                      focusNode: _focus1,
                      selected: _product1,
                      suggestions: _suggestions1,
                      onChanged: (v) {
                        if (_product1 != null) _clearProduct1();
                        _onQuery1Changed(v);
                      },
                      onSelect: _selectProduct1,
                      onClear: _clearProduct1,
                    ),
                    const SizedBox(height: V2Spacing.space12),
                    _ProductSearchSection(
                      eyebrow: 'Second product',
                      icon: Icons.looks_two_outlined,
                      controller: _controller2,
                      focusNode: _focus2,
                      selected: _product2,
                      suggestions: _suggestions2,
                      onChanged: (v) {
                        if (_product2 != null) _clearProduct2();
                        _onQuery2Changed(v);
                      },
                      onSelect: _selectProduct2,
                      onClear: _clearProduct2,
                    ),
                    const SizedBox(height: V2Spacing.space24),
                    PGPillButton(
                      label: _checking
                          ? 'Checking…'
                          : 'Check interactions',
                      icon: Icons.health_and_safety_outlined,
                      expand: true,
                      onPressed: canCheck ? _checkInteractions : null,
                    ),
                    const SizedBox(height: V2Spacing.space24),
                    if (_checkError)
                      const _StateCard(
                        icon: Icons.cloud_off_rounded,
                        tint: V2Colors.caution,
                        headline: 'Database unavailable',
                        body:
                            'The interaction database could not be loaded. '
                            'Try again in a moment.',
                      )
                    else if (_insufficientData)
                      const _StateCard(
                        icon: Icons.help_outline_rounded,
                        tint: V2Colors.monitor,
                        headline: 'Ingredient data is incomplete',
                        body:
                            'One or both products lack the detailed '
                            'ingredient list we use for pair checks. '
                            'Worth a conversation with your clinician.',
                      )
                    else if (_results != null)
                      _ResultsBlock(
                        results: _results!,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Top bar
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
            const Expanded(
              child: Center(child: PGEyebrow('Check together')),
            ),
            const SizedBox(width: 40),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Check two things\ntogether.',
          style: V2Typography.displaySm(color: V2Colors.fg),
        ),
        const SizedBox(height: V2Spacing.space12),
        Text(
          'Pick two supplements or medications and we’ll flag known '
          'interactions worth a clinician conversation. Used only on '
          'this device.',
          style: V2Typography.body(color: V2Colors.fgMuted),
        ),
      ],
    );
  }
}

// =============================================================================
// Product search section — cream tile with v2 search field, inline
// suggestion list, and selected-state collapse.
// =============================================================================

class _ProductSearchSection extends StatelessWidget {
  final String eyebrow;
  final IconData icon;
  final TextEditingController controller;
  final FocusNode focusNode;
  final ProductsCoreData? selected;
  final List<ProductsCoreData> suggestions;
  final ValueChanged<String> onChanged;
  final ValueChanged<ProductsCoreData> onSelect;
  final VoidCallback onClear;

  const _ProductSearchSection({
    required this.eyebrow,
    required this.icon,
    required this.controller,
    required this.focusNode,
    required this.selected,
    required this.suggestions,
    required this.onChanged,
    required this.onSelect,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final focused = focusNode.hasFocus;
    return Container(
      decoration: BoxDecoration(
        color: V2Colors.surface,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        border: Border.all(
          color: selected != null ? V2Colors.accent : V2Colors.outline,
          width: selected != null ? 1.5 : 1.0,
        ),
        boxShadow: V2Shadows.sm,
      ),
      padding: const EdgeInsets.fromLTRB(
        V2Spacing.space16,
        V2Spacing.space16,
        V2Spacing.space16,
        V2Spacing.space16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: V2Colors.accentTint,
                  borderRadius: BorderRadius.circular(V2Spacing.space8),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 16, color: V2Colors.accent),
              ),
              const SizedBox(width: V2Spacing.space12),
              PGEyebrow(eyebrow, color: V2Colors.fgMuted),
            ],
          ),
          const SizedBox(height: V2Spacing.space12),
          if (selected != null)
            _SelectedProductRow(product: selected!, onClear: onClear)
          else
            AnimatedContainer(
              duration: V2Motion.fast,
              curve: V2Motion.smooth,
              padding:
                  const EdgeInsets.symmetric(horizontal: V2Spacing.space12),
              decoration: BoxDecoration(
                color: V2Colors.bg,
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
                      controller: controller,
                      focusNode: focusNode,
                      maxLines: 1,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: 'Search by name',
                        hintStyle:
                            V2Typography.body(color: V2Colors.fgSubtle),
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
                ],
              ),
            ),
          if (selected == null && suggestions.isNotEmpty) ...[
            const SizedBox(height: V2Spacing.space12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: suggestions.length,
                separatorBuilder: (_, __) => const Divider(
                  height: 1,
                  thickness: 0.5,
                  color: V2Colors.outline,
                ),
                itemBuilder: (context, i) => _SuggestionRow(
                  product: suggestions[i],
                  onTap: () => onSelect(suggestions[i]),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SuggestionRow extends StatelessWidget {
  final ProductsCoreData product;
  final VoidCallback onTap;

  const _SuggestionRow({required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: V2Spacing.space4,
            vertical: V2Spacing.space12,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.productName,
                      style: V2Typography.bodyMedium(color: V2Colors.fg),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (product.brandName != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        product.brandName!,
                        style: V2Typography.caption(color: V2Colors.fgMuted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              if (product.score100Equivalent != null) ...[
                const SizedBox(width: V2Spacing.space12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: V2Spacing.space8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: V2Colors.accentTint,
                    borderRadius:
                        BorderRadius.circular(V2Spacing.radiusPill),
                  ),
                  child: Text(
                    '${product.score100Equivalent!.round()}',
                    style: V2Typography.eyebrow(color: V2Colors.accent),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectedProductRow extends StatelessWidget {
  final ProductsCoreData product;
  final VoidCallback onClear;

  const _SelectedProductRow({required this.product, required this.onClear});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(
          Icons.check_circle_rounded,
          size: 18,
          color: V2Colors.accent,
        ),
        const SizedBox(width: V2Spacing.space12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                product.productName,
                style: V2Typography.bodyMedium(color: V2Colors.fg),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (product.brandName != null) ...[
                const SizedBox(height: 2),
                Text(
                  product.brandName!,
                  style: V2Typography.caption(color: V2Colors.fgMuted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onClear,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: V2Spacing.space8,
              vertical: V2Spacing.space4,
            ),
            child: Text(
              'Change',
              style: V2Typography.label(color: V2Colors.accent),
            ),
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// State card — used by error / insufficient-data / clean-check.
// =============================================================================

class _StateCard extends StatelessWidget {
  final IconData icon;
  final Color tint;
  final String headline;
  final String body;

  const _StateCard({
    required this.icon,
    required this.tint,
    required this.headline,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(V2Spacing.space24),
      decoration: BoxDecoration(
        color: V2Colors.surface,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        border: Border.all(color: V2Colors.outline),
        boxShadow: V2Shadows.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(V2Spacing.space8),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 18, color: tint),
          ),
          const SizedBox(height: V2Spacing.space12),
          Text(
            headline,
            style: V2Typography.titleSm(color: V2Colors.fg),
          ),
          const SizedBox(height: V2Spacing.space8),
          Text(
            body,
            style: V2Typography.body(color: V2Colors.fgMuted),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Results block — clean-check card or list of `_InteractionCard`.
// =============================================================================

class _ResultsBlock extends StatelessWidget {
  final List<InteractionResult> results;
  const _ResultsBlock({required this.results});

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(V2Spacing.space24),
        decoration: BoxDecoration(
          color: V2Colors.safeTint,
          borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
          border: Border.all(color: V2Colors.safe, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(
                  Icons.check_circle_rounded,
                  color: V2Colors.safe,
                  size: 22,
                ),
                SizedBox(width: V2Spacing.space12),
                PGEyebrow('No known interactions', color: V2Colors.safe),
              ],
            ),
            const SizedBox(height: V2Spacing.space12),
            Text(
              "Based on our pair database, these two appear safe to take "
              'together. Always check with your clinician — this is '
              'educational, not medical advice.',
              style: V2Typography.body(color: V2Colors.fg),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            PGEyebrow(
              '${results.length} interaction${results.length == 1 ? '' : 's'}'
              ' found',
            ),
          ],
        ),
        const SizedBox(height: V2Spacing.space12),
        for (final r in results) ...[
          _InteractionCard(result: r),
          const SizedBox(height: V2Spacing.space12),
        ],
        const SizedBox(height: V2Spacing.space4),
        Text(
          'This is educational information, not medical advice. '
          'Always consult your healthcare provider.',
          style: V2Typography.caption(color: V2Colors.fgMuted),
        ),
      ],
    );
  }
}

class _InteractionCard extends StatelessWidget {
  final InteractionResult result;
  const _InteractionCard({required this.result});

  Color get _severityColor => switch (result.severity) {
        Severity.contraindicated => V2Colors.contraindicated,
        Severity.avoid => V2Colors.avoid,
        Severity.caution => V2Colors.caution,
        Severity.monitor => V2Colors.monitor,
        Severity.informational => V2Colors.fgMuted,
        Severity.safe => V2Colors.safe,
      };

  Color get _severityTint => switch (result.severity) {
        Severity.contraindicated => V2Colors.contraindicatedTint,
        Severity.avoid => V2Colors.avoidTint,
        Severity.caution => V2Colors.cautionTint,
        Severity.monitor => V2Colors.monitorTint,
        Severity.informational => V2Colors.outline,
        Severity.safe => V2Colors.safeTint,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: V2Colors.surface,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        border: Border.all(color: V2Colors.outline),
        boxShadow: V2Shadows.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Severity strip + label
          Container(
            decoration: BoxDecoration(
              color: _severityTint,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(V2Spacing.radiusCard),
              ),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: V2Spacing.space16,
              vertical: V2Spacing.space12,
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _severityColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: V2Spacing.space8),
                Text(
                  result.severity.label.toUpperCase(),
                  style: V2Typography.eyebrow(color: _severityColor),
                ),
                const Spacer(),
                Text(
                  result.evidenceLevel.label,
                  style: V2Typography.overline(color: V2Colors.fgMuted),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(V2Spacing.space16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _PairLine(
                  a: result.agent1Name,
                  b: result.agent2Name,
                ),
                if (result.mechanism.isNotEmpty) ...[
                  const SizedBox(height: V2Spacing.space16),
                  const PGEyebrow('Why', color: V2Colors.fgMuted),
                  const SizedBox(height: V2Spacing.space4),
                  Text(
                    result.mechanism,
                    style: V2Typography.body(color: V2Colors.fg),
                  ),
                ],
                if (result.management.isNotEmpty) ...[
                  const SizedBox(height: V2Spacing.space16),
                  const PGEyebrow(
                    'What to do',
                    color: V2Colors.fgMuted,
                  ),
                  const SizedBox(height: V2Spacing.space4),
                  Text(
                    result.management,
                    style: V2Typography.body(color: V2Colors.fg),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PairLine extends StatelessWidget {
  final String a;
  final String b;
  const _PairLine({required this.a, required this.b});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            a,
            style: V2Typography.titleSm(color: V2Colors.fg),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: V2Spacing.space8),
          child: Text(
            '·',
            style: TextStyle(
              fontSize: 16,
              color: V2Colors.fgMuted,
            ),
          ),
        ),
        Expanded(
          child: Text(
            b,
            style: V2Typography.titleSm(color: V2Colors.fg),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}
