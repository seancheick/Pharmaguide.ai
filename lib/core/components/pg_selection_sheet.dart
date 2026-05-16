import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pharmaguide/core/components/pg_eyebrow.dart';
import 'package:pharmaguide/core/components/pg_pill_button.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_motion.dart';
import 'package:pharmaguide/core/theme/v2/v2_shadows.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';

/// One selectable option inside a [showPGSelectionSheet] call.
///
/// IDs are opaque strings; the sheet does not validate them. Pass
/// canonical schema IDs (e.g. `'GOAL_SLEEP_QUALITY'`) and friendly
/// labels rendered to the user.
class PGSelectionOption {
  /// Canonical ID — what the sheet returns through
  /// [PGSelectionResult.selected] when the user picks it.
  final String id;

  /// Visible label.
  final String label;

  /// Optional one-line subtitle below the label. Use for clinical
  /// disambiguation (e.g. "Lower low-blood-sugar risk diabetes meds")
  /// — keep short, this is not body copy.
  final String? subtitle;

  /// When true, the chip renders as disabled and ignores taps. Used
  /// e.g. for the goals max-2 cap on un-selected chips once two are
  /// already picked.
  final bool disabled;

  const PGSelectionOption({
    required this.id,
    required this.label,
    this.subtitle,
    this.disabled = false,
  });
}

/// Result handed back from [showPGSelectionSheet] when the user
/// confirms with Save. `null` is returned when the sheet is dismissed
/// without saving.
class PGSelectionResult {
  /// Real schema IDs the user picked. Empty when [noneSelected] is true.
  final Set<String> selected;

  /// True when the user picked the "None" option at the top of the
  /// sheet. Callers should treat this as an EXPLICIT opt-out distinct
  /// from "selected is empty because the user hasn't decided yet."
  final bool noneSelected;

  const PGSelectionResult({
    required this.selected,
    required this.noneSelected,
  });
}

/// Open the v2 selection bottom sheet.
///
/// ### Visual contract
/// - Cream surface with a 4×40px drag handle pill centered at the top.
/// - 12pt corner radius matching `V2Spacing.radiusSheet`.
/// - Mono-caps eyebrow + Newsreader serif title + Geist Sans helper
///   paragraph in the header.
/// - Optional search bar that materializes when [searchable] is true
///   and the option count is at least [searchableThreshold].
/// - "None" option pinned at the very top of the option list when
///   [noneLabel] is non-null. Selecting it clears every other pick
///   in the draft; tapping any real chip clears the None pick.
/// - Chip wrap below the None card. Selected chips use
///   `V2Colors.accentTint` + a 14px check icon, unselected use the
///   cream surface with hairline outline.
/// - Sticky bottom action bar: primary "Save" pill on the right,
///   ghost "Clear" on the left.
///
/// ### Behavior contract
/// - Draft selection is held INSIDE the sheet — the underlying
///   provider is updated exactly once on Save (or never if dismissed).
/// - Pressing the system back gesture or tapping the scrim dismisses
///   the sheet. If [confirmDiscardOnDismiss] is true and the draft
///   differs from the original selection, an inline confirm dialog
///   asks before discarding.
/// - Haptics fire only on the Save tap (medium impact) and on
///   None-toggle (selection click). Per-chip toggles are silent to
///   avoid haptic fatigue on a long list.
///
/// ### Why a separate component
/// Every v2 selection surface (Goals, Conditions, Allergies,
/// Medications, future Stack filters, Search filters) needs the same
/// shape. Centralizing here keeps them visually + behaviorally
/// identical, and lets the underlying screen logic just call this
/// function with the right options.
Future<PGSelectionResult?> showPGSelectionSheet({
  required BuildContext context,
  required String eyebrow,
  required String title,
  required String helperText,
  required List<PGSelectionOption> options,
  required Set<String> initialSelection,
  bool initialNoneSelected = false,
  String? noneLabel,
  String? noneSubtitle,
  int? maxSelection,
  String? maxSelectionHint,
  bool searchable = false,
  int searchableThreshold = 12,
  bool confirmDiscardOnDismiss = true,
  String saveLabel = 'Save',
  String clearLabel = 'Clear',
  // Phase 11.7L.B.8 — single-select mode for required-single fields
  // (age bracket, sex). Tapping a chip in this mode REPLACES the
  // draft selection instead of toggling, so the user can swap their
  // pick without first clearing. The Save button still gates the
  // commit to the provider — auto-commit-on-tap would break the
  // "draft preserved until Save" contract the multi-select sheet
  // already enforces. Implies the Clear button + a None tile don't
  // make sense; callers should pass `noneLabel: null` and the Clear
  // button auto-disables when the draft only ever holds one entry.
  bool singleSelect = false,
}) {
  return showModalBottomSheet<PGSelectionResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.40),
    isDismissible: true,
    useSafeArea: true,
    builder: (sheetContext) => _PGSelectionSheet(
      eyebrow: eyebrow,
      title: title,
      helperText: helperText,
      options: options,
      singleSelect: singleSelect,
      initialSelection: initialSelection,
      initialNoneSelected: initialNoneSelected,
      noneLabel: noneLabel,
      noneSubtitle: noneSubtitle,
      maxSelection: maxSelection,
      maxSelectionHint: maxSelectionHint,
      searchable: searchable && options.length >= searchableThreshold,
      confirmDiscardOnDismiss: confirmDiscardOnDismiss,
      saveLabel: saveLabel,
      clearLabel: clearLabel,
    ),
  );
}

class _PGSelectionSheet extends StatefulWidget {
  final String eyebrow;
  final String title;
  final String helperText;
  final List<PGSelectionOption> options;
  final Set<String> initialSelection;
  final bool initialNoneSelected;
  final String? noneLabel;
  final String? noneSubtitle;
  final int? maxSelection;
  final String? maxSelectionHint;
  final bool searchable;
  final bool confirmDiscardOnDismiss;
  final String saveLabel;
  final String clearLabel;
  final bool singleSelect;

  const _PGSelectionSheet({
    required this.eyebrow,
    required this.title,
    required this.helperText,
    required this.options,
    required this.initialSelection,
    required this.initialNoneSelected,
    required this.noneLabel,
    required this.noneSubtitle,
    required this.maxSelection,
    required this.maxSelectionHint,
    required this.searchable,
    required this.confirmDiscardOnDismiss,
    required this.saveLabel,
    required this.clearLabel,
    required this.singleSelect,
  });

  @override
  State<_PGSelectionSheet> createState() => _PGSelectionSheetState();
}

class _PGSelectionSheetState extends State<_PGSelectionSheet> {
  late Set<String> _draft;
  late bool _noneSelected;
  late final TextEditingController _searchController;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _draft = {...widget.initialSelection};
    _noneSelected = widget.initialNoneSelected;
    _searchController = TextEditingController();
    if (widget.searchable) {
      _searchController.addListener(() {
        setState(() => _query = _searchController.text.trim().toLowerCase());
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool get _isDirty {
    if (_noneSelected != widget.initialNoneSelected) return true;
    if (_draft.length != widget.initialSelection.length) return true;
    return !_draft.every(widget.initialSelection.contains);
  }

  Future<void> _maybeDismiss() async {
    if (!widget.confirmDiscardOnDismiss || !_isDirty) {
      Navigator.of(context).pop();
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: V2Colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        ),
        title: Text(
          'Discard changes?',
          style: V2Typography.title(color: V2Colors.fg),
        ),
        content: Text(
          'You haven\'t saved this selection yet.',
          style: V2Typography.body(color: V2Colors.fgMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Keep editing',
              style: V2Typography.label(color: V2Colors.accent),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Discard',
              style: V2Typography.label(color: V2Colors.contraindicated),
            ),
          ),
        ],
      ),
    );
    if (discard ?? false) {
      if (!mounted) return;
      Navigator.of(context).pop();
    }
  }

  void _toggleNone() {
    HapticFeedback.selectionClick();
    setState(() {
      _noneSelected = !_noneSelected;
      if (_noneSelected) _draft.clear();
    });
  }

  void _toggleOption(PGSelectionOption option) {
    setState(() {
      // Single-select mode (e.g. age bracket, sex): tapping a chip
      // REPLACES the draft so the user can swap their pick without
      // first clearing. Tapping the currently selected chip leaves
      // it selected — single-select fields are required, so we
      // never let the user back into an empty state from inside
      // the sheet (the Clear button is the explicit escape hatch).
      if (widget.singleSelect) {
        if (_draft.contains(option.id) && _draft.length == 1) return;
        _draft
          ..clear()
          ..add(option.id);
        _noneSelected = false;
        return;
      }
      if (_draft.contains(option.id)) {
        _draft.remove(option.id);
      } else {
        if (widget.maxSelection != null &&
            _draft.length >= widget.maxSelection!) {
          return;
        }
        _draft.add(option.id);
        // Picking any real option clears the explicit None.
        _noneSelected = false;
      }
    });
  }

  void _clear() {
    if (_draft.isEmpty && !_noneSelected) return;
    HapticFeedback.selectionClick();
    setState(() {
      _draft.clear();
      _noneSelected = false;
    });
  }

  void _save() {
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop(
      PGSelectionResult(
        selected: {..._draft},
        noneSelected: _noneSelected,
      ),
    );
  }

  List<PGSelectionOption> get _filteredOptions {
    if (_query.isEmpty) return widget.options;
    return widget.options
        .where((o) => o.label.toLowerCase().contains(_query))
        .toList();
  }

  bool _disabledByMax(PGSelectionOption option) {
    if (option.disabled) return true;
    // Single-select mode has its own swap semantics — no chip should
    // ever look "disabled because cap is hit." The user can always
    // tap a different chip to change their pick.
    if (widget.singleSelect) return false;
    if (widget.maxSelection == null) return false;
    return !_draft.contains(option.id) &&
        _draft.length >= widget.maxSelection!;
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    // 92% screen height ceiling — the sheet feels like a focused
    // surface, not a takeover. SafeArea trims the bottom inset.
    final maxHeight = mq.size.height * 0.92;
    final visibleOptions = _filteredOptions;

    return PopScope(
      canPop: !_isDirty || !widget.confirmDiscardOnDismiss,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _maybeDismiss();
      },
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: V2Colors.bg,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(V2Spacing.radiusSheet),
            ),
            boxShadow: V2Shadows.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: V2Spacing.space12),
              const _DragHandle(),
              const SizedBox(height: V2Spacing.space16),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: V2Spacing.space24,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PGEyebrow(widget.eyebrow),
                    const SizedBox(height: V2Spacing.space8),
                    Text(
                      widget.title,
                      style: V2Typography.displayXs(color: V2Colors.fg),
                    ),
                    const SizedBox(height: V2Spacing.space12),
                    Text(
                      widget.helperText,
                      style: V2Typography.body(color: V2Colors.fgMuted),
                    ),
                  ],
                ),
              ),
              if (widget.searchable) ...[
                const SizedBox(height: V2Spacing.space16),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: V2Spacing.space24,
                  ),
                  child: _SearchField(controller: _searchController),
                ),
              ],
              const SizedBox(height: V2Spacing.space16),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    V2Spacing.space24,
                    0,
                    V2Spacing.space24,
                    V2Spacing.space16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.noneLabel != null) ...[
                        _NoneTile(
                          label: widget.noneLabel!,
                          subtitle: widget.noneSubtitle,
                          selected: _noneSelected,
                          onTap: _toggleNone,
                        ),
                        const SizedBox(height: V2Spacing.space16),
                      ],
                      if (widget.maxSelectionHint != null &&
                          !_noneSelected) ...[
                        Text(
                          widget.maxSelectionHint!,
                          style: V2Typography.caption(
                            color: V2Colors.fgMuted,
                          ),
                        ),
                        const SizedBox(height: V2Spacing.space12),
                      ],
                      if (visibleOptions.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: V2Spacing.space24,
                          ),
                          child: Text(
                            'No matches for "${_searchController.text}"',
                            style: V2Typography.bodySm(
                              color: V2Colors.fgMuted,
                            ),
                          ),
                        )
                      else
                        Wrap(
                          spacing: V2Spacing.space8,
                          runSpacing: V2Spacing.space8,
                          children: visibleOptions.map((option) {
                            final selected = _draft.contains(option.id);
                            return _SheetChip(
                              label: option.label,
                              subtitle: option.subtitle,
                              selected: selected,
                              disabled: _disabledByMax(option),
                              onTap: () => _toggleOption(option),
                            );
                          }).toList(),
                        ),
                    ],
                  ),
                ),
              ),
              _SheetActionBar(
                onClear: _clear,
                onSave: _save,
                clearLabel: widget.clearLabel,
                saveLabel: widget.saveLabel,
                clearEnabled: _draft.isNotEmpty || _noneSelected,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: V2Colors.fgSubtle.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  const _SearchField({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: V2Spacing.space12),
      decoration: BoxDecoration(
        color: V2Colors.surface,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        border: Border.all(color: V2Colors.outline),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.search_rounded,
            size: 18,
            color: V2Colors.fgSubtle,
          ),
          const SizedBox(width: V2Spacing.space8),
          Expanded(
            child: TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: 'Search',
                hintStyle: V2Typography.body(color: V2Colors.fgSubtle),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  vertical: V2Spacing.space12,
                ),
                isCollapsed: true,
              ),
              style: V2Typography.body(color: V2Colors.fg),
              cursorColor: V2Colors.accent,
              cursorWidth: 1.5,
              textInputAction: TextInputAction.search,
            ),
          ),
          if (controller.text.isNotEmpty)
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              icon: const Icon(
                Icons.close_rounded,
                size: 18,
                color: V2Colors.fgSubtle,
              ),
              onPressed: controller.clear,
            ),
        ],
      ),
    );
  }
}

class _NoneTile extends StatelessWidget {
  final String label;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _NoneTile({
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        child: AnimatedContainer(
          duration: V2Motion.fast,
          curve: V2Motion.smooth,
          padding: const EdgeInsets.all(V2Spacing.space16),
          decoration: BoxDecoration(
            color: selected ? V2Colors.accentTint : V2Colors.surface,
            borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
            border: Border.all(
              color: selected ? V2Colors.accent : V2Colors.outline,
              width: selected ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            children: [
              _CheckCircle(selected: selected),
              const SizedBox(width: V2Spacing.space12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: V2Typography.bodyMedium(
                        color: selected ? V2Colors.accent : V2Colors.fg,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: V2Spacing.space4),
                      Text(
                        subtitle!,
                        style: V2Typography.caption(color: V2Colors.fgMuted),
                      ),
                    ],
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

class _CheckCircle extends StatelessWidget {
  final bool selected;
  const _CheckCircle({required this.selected});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: V2Motion.fast,
      curve: V2Motion.smooth,
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? V2Colors.accent : Colors.transparent,
        border: Border.all(
          color: selected ? V2Colors.accent : V2Colors.outline,
          width: selected ? 0 : 1.5,
        ),
      ),
      alignment: Alignment.center,
      child: selected
          ? const Icon(
              Icons.check_rounded,
              size: 13,
              color: Colors.white,
            )
          : null,
    );
  }
}

class _SheetChip extends StatelessWidget {
  final String label;
  final String? subtitle;
  final bool selected;
  final bool disabled;
  final VoidCallback onTap;

  const _SheetChip({
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.disabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected ? V2Colors.accentTint : V2Colors.surface;
    final border = selected ? V2Colors.accent : V2Colors.outline;
    final fg = disabled
        ? V2Colors.fgSubtle
        : (selected ? V2Colors.accent : V2Colors.fg);

    return GestureDetector(
      onTap: disabled ? null : onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: V2Motion.fast,
        curve: V2Motion.smooth,
        padding: const EdgeInsets.symmetric(
          horizontal: V2Spacing.space16,
          vertical: V2Spacing.space12,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
          border: Border.all(
            color: border,
            width: selected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              const Icon(
                Icons.check_rounded,
                size: 14,
                color: V2Colors.accent,
              ),
              const SizedBox(width: V2Spacing.space8),
            ],
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: selected
                        ? V2Typography.label(color: fg)
                        : V2Typography.bodySm(color: fg),
                  ),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        subtitle!,
                        style: V2Typography.caption(color: V2Colors.fgMuted),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetActionBar extends StatelessWidget {
  final VoidCallback onClear;
  final VoidCallback onSave;
  final String clearLabel;
  final String saveLabel;
  final bool clearEnabled;

  const _SheetActionBar({
    required this.onClear,
    required this.onSave,
    required this.clearLabel,
    required this.saveLabel,
    required this.clearEnabled,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: V2Colors.bg,
        border: Border(top: BorderSide(color: V2Colors.outline)),
      ),
      padding: const EdgeInsets.fromLTRB(
        V2Spacing.space24,
        V2Spacing.space12,
        V2Spacing.space24,
        V2Spacing.space16,
      ),
      child: Row(
        children: [
          PGPillButton(
            label: clearLabel,
            variant: PGPillVariant.ghost,
            onPressed: clearEnabled ? onClear : null,
          ),
          const Spacer(),
          PGPillButton(
            label: saveLabel,
            onPressed: onSave,
          ),
        ],
      ),
    );
  }
}
