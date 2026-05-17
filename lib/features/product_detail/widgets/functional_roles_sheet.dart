// Functional-roles bottom sheet for inactive ingredients.
//
// Extracted from `ingredients_card.dart` 2026-05-17 so both v1 and v2
// product-detail surfaces can share it. The v2 ingredients section
// (`product_detail/v2/sections/ingredients_section.dart`) previously
// hardcoded `onInactiveTap: null` because the sheet was private —
// inactive-row taps did nothing in production. This file fixes Bug 9
// from the 1.0.0+3 walkthrough.
//
// Sean's rules preserved verbatim:
//   • Clinician-locked copy — role notes render exactly as authored
//     in `assets/data/functional_roles_vocab.json`, no paraphrase.
//   • Unknown role ids fall back to a generic "added during
//     manufacturing" line so the user always gets SOMETHING.
//   • Examples + regulatory references are optional per role.

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/widgets/pg_modal.dart';
import 'package:pharmaguide/features/product_detail/data/functional_roles_vocab.dart';

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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
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
          AppTheme.space20,
          AppTheme.space12,
          AppTheme.space20,
          AppTheme.space20,
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
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: AppTheme.space12),
              if (roles.isEmpty)
                _GenericFallback(scheme: scheme, theme: theme)
              else
                FutureBuilder<Map<String, FunctionalRole>>(
                  future: loadFunctionalRolesVocab(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const SizedBox(
                        height: 80,
                        child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      );
                    }
                    final vocab = snapshot.data!;
                    final matched = roles
                        .map((id) => vocab[id])
                        .whereType<FunctionalRole>()
                        .toList(growable: false);
                    if (matched.isEmpty) {
                      // All ids unknown — fall back so the user gets
                      // something. Could happen during a vocab/data
                      // version skew.
                      return _GenericFallback(scheme: scheme, theme: theme);
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < matched.length; i++) ...[
                          if (i > 0) const SizedBox(height: AppTheme.space20),
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
  final FunctionalRole role;
  const _RoleSection({required this.role});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          role.name,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppTheme.space6),
        // Notes — verbatim, no paraphrase. Clinician-locked copy.
        Text(
          role.notes,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
            height: 1.4,
          ),
        ),
        if (role.examples.isNotEmpty) ...[
          const SizedBox(height: AppTheme.space12),
          Text(
            'Common examples',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppTheme.space6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final ex in role.examples)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                  ),
                  child: Text(
                    ex,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ],
        if (role.regulatoryReferences.isNotEmpty) ...[
          const SizedBox(height: AppTheme.space12),
          Text(
            'Learn more',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppTheme.space6),
          for (final ref in role.regulatoryReferences)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                '${ref.jurisdiction} · ${ref.code}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _GenericFallback extends StatelessWidget {
  final ColorScheme scheme;
  final ThemeData theme;
  const _GenericFallback({required this.scheme, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Text(
      'Inactive ingredient — added during manufacturing.',
      style: theme.textTheme.bodyMedium?.copyWith(
        color: scheme.onSurfaceVariant,
        height: 1.4,
      ),
    );
  }
}
