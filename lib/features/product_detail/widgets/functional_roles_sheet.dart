// Functional-roles bottom sheet for inactive ingredients.
//
// Extracted from `ingredients_card.dart` 2026-05-17 so Product Detail
// can share one inactive-ingredient explainer. The v2 ingredients
// section previously hardcoded `onInactiveTap: null` because the sheet
// was private — inactive-row taps did nothing in production. This file
// fixes Bug 9 from the 1.0.0+3 walkthrough.
//
// Sean's rules preserved verbatim:
//   • Clinician-locked copy — role notes render exactly as authored
//     in `assets/data/functional_roles_vocab.json`, no paraphrase.
//   • Unknown role ids fall back to a generic "added during
//     manufacturing" line so the user always gets SOMETHING.
//   • Examples + regulatory references are optional per role.

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/data/functional_roles_vocab.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/core/widgets/pg_modal.dart';

/// Open the functional-roles bottom sheet for [ingredient].
///
/// [ingredient] is a pipeline-shaped raw map from
/// `detailBlob['inactive_ingredients']`. Reads:
///   - `name` / `raw_source_text` for the header
///   - `functional_roles[]` for the vocab lookup
///
/// Empty / unknown `functional_roles` → generic fallback copy.
/// First call kicks off vocab asset load; subsequent calls are sync-
/// fast thanks to the process-lifetime cache in
/// `loadFunctionalRolesVocab()`.
void showFunctionalRolesSheet(
  BuildContext context,
  Map<String, dynamic> ingredient,
) {
  PGModal.bottomSheet<void>(
    context: context,
    builder: (sheetCtx) => _FunctionalRolesSheet(ingredient: ingredient),
  );
}

/// Bottom-sheet body explaining an inactive ingredient via the
/// functional-roles vocab. One stacked section per role on the
/// ingredient row.
class _FunctionalRolesSheet extends StatelessWidget {
  final Map<String, dynamic> ingredient;
  const _FunctionalRolesSheet({required this.ingredient});

  @override
  Widget build(BuildContext context) {
    final name =
        ingredient['name']?.toString() ??
        ingredient['raw_source_text']?.toString() ??
        '';
    final roles =
        (ingredient['functional_roles'] as List?)
            ?.map((e) => e.toString())
            .where((id) => id.isNotEmpty)
            .toList(growable: false) ??
        const <String>[];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          V2Spacing.space24,
          V2Spacing.space8,
          V2Spacing.space24,
          V2Spacing.space24,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Ingredient name (the row the user tapped) — in the
              // sheet header so they have anchor context.
              Text(
                name.isEmpty ? 'Inactive ingredient' : name,
                style: V2Typography.titleSm(color: context.v2.fg),
              ),
              const SizedBox(height: V2Spacing.space16),
              if (roles.isEmpty)
                const _GenericFallback()
              else
                FutureBuilder<Map<String, FunctionalRoleEntry>>(
                  future: loadFunctionalRolesVocab(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return SizedBox(
                        height: 80,
                        child: Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: context.v2.accent,
                          ),
                        ),
                      );
                    }
                    final vocab = snapshot.data!;
                    final matched = roles
                        .map((id) => vocab[id])
                        .whereType<FunctionalRoleEntry>()
                        .toList(growable: false);
                    if (matched.isEmpty) {
                      // All ids unknown — fall back so the user gets
                      // something. Could happen during a vocab/data
                      // version skew.
                      return const _GenericFallback();
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < matched.length; i++) ...[
                          if (i > 0) const SizedBox(height: V2Spacing.space24),
                          _RoleSection(role: matched[i]),
                        ],
                      ],
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One vocab role rendered as a stacked section in the modal:
/// title, body (verbatim — clinician-locked), examples chip row,
/// regulatory deep-link row.
class _RoleSection extends StatelessWidget {
  final FunctionalRoleEntry role;
  const _RoleSection({required this.role});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(role.name, style: V2Typography.bodyMedium(color: context.v2.fg)),
        const SizedBox(height: V2Spacing.space8),
        // Notes — verbatim, no paraphrase. Clinician-locked copy.
        Text(role.notes, style: V2Typography.bodySm(color: context.v2.fgMuted)),
        if (role.examples.isNotEmpty) ...[
          const SizedBox(height: V2Spacing.space16),
          Text(
            'Common examples',
            style: V2Typography.eyebrow(color: context.v2.fgSubtle),
          ),
          const SizedBox(height: V2Spacing.space8),
          Wrap(
            spacing: V2Spacing.space8,
            runSpacing: V2Spacing.space8,
            children: [
              for (final ex in role.examples)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: V2Spacing.space8,
                    vertical: V2Spacing.space4,
                  ),
                  decoration: BoxDecoration(
                    color: context.v2.accentTint,
                    borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
                    border: Border.all(color: context.v2.outline),
                  ),
                  child: Text(
                    ex,
                    style: V2Typography.caption(color: context.v2.accent),
                  ),
                ),
            ],
          ),
        ],
        if (role.regulatoryReferences.isNotEmpty) ...[
          const SizedBox(height: V2Spacing.space16),
          Text(
            'Learn more',
            style: V2Typography.eyebrow(color: context.v2.fgSubtle),
          ),
          const SizedBox(height: V2Spacing.space8),
          for (final ref in role.regulatoryReferences)
            Padding(
              padding: const EdgeInsets.only(bottom: V2Spacing.space4),
              child: Text(
                '${ref.jurisdiction} · ${ref.code}',
                style: V2Typography.caption(color: context.v2.accent),
              ),
            ),
        ],
      ],
    );
  }
}

class _GenericFallback extends StatelessWidget {
  const _GenericFallback();

  @override
  Widget build(BuildContext context) {
    return Text(
      'Inactive ingredient — added during manufacturing.',
      style: V2Typography.bodySm(color: context.v2.fgMuted),
    );
  }
}
