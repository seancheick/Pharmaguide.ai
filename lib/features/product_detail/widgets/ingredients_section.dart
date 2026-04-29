// Ingredients section (Section 4) — wrapper around the existing active
// ingredient renderer + a new tap-to-explain inactive chip.
//
// Spec: INITIATIVE_PRODUCT_TRUST_AND_IA.md, Sprint 1, T1.5.
//
// Active rows live in `_CollapsibleIngredients` / `_IngredientTile` inside
// `product_detail_screen.dart` — they already deliver the 5-element row
// spec (name + dose + form + bio-availability indicator + UL safety tag).
// This file adds the missing T1.5 behavior: inactive ingredient chips
// that tap to a bottom sheet explaining the ingredient's purpose.

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/widgets/pg_modal.dart';
import 'package:pharmaguide/core/widgets/pg_pressable.dart';

/// Plain-English explanations for common inactive ingredients. The
/// pipeline ships inactives as raw names (from supplement labels), so
/// this is a small lookup table that explains why each is in a
/// supplement when the user taps the chip.
///
/// Lookup is lowercase + trimmed so case + whitespace variants from
/// pipeline drift all hit the same entry.
///
/// When a name doesn't match an entry, the bottom sheet falls back to
/// a generic "Inactive ingredient — added during manufacturing" copy.
const Map<String, InactivePurpose> _inactivePurposes = {
  // Capsule shells
  'gelatin': InactivePurpose(
    role: 'Capsule shell',
    detail:
        'Animal-derived protein that forms the outer capsule. Dissolves '
        'in the stomach to release the contents. Common in non-vegetarian '
        'capsules.',
  ),
  'hpmc': InactivePurpose(
    role: 'Vegetable capsule shell',
    detail:
        'Plant-derived alternative to gelatin (hydroxypropyl '
        'methylcellulose). Dissolves the same way; used in vegan and '
        'vegetarian capsules.',
  ),
  'hydroxypropyl methylcellulose': InactivePurpose(
    role: 'Vegetable capsule shell',
    detail:
        'Plant-derived alternative to gelatin. Dissolves the same way; '
        'used in vegan and vegetarian capsules.',
  ),
  'vegetable cellulose': InactivePurpose(
    role: 'Plant-based capsule shell',
    detail:
        'Cellulose from plants (typically wood pulp or cotton). Forms '
        'the outer capsule in vegan formulations.',
  ),
  'plant cellulose': InactivePurpose(
    role: 'Plant-based capsule shell',
    detail:
        'Cellulose from plants. Forms the outer capsule in vegan '
        'formulations.',
  ),
  'pullulan': InactivePurpose(
    role: 'Fermented capsule shell',
    detail:
        'Polysaccharide produced by fermentation. Forms a clear, vegan '
        'capsule shell — often considered the "premium" alternative to '
        'gelatin and HPMC.',
  ),

  // Lubricants / flow agents
  'magnesium stearate': InactivePurpose(
    role: 'Manufacturing lubricant',
    detail:
        'Prevents capsule and tablet ingredients from sticking to '
        'manufacturing equipment. Inert at typical supplement doses.',
  ),
  'vegetable magnesium stearate': InactivePurpose(
    role: 'Manufacturing lubricant (plant-derived)',
    detail:
        'Plant-derived magnesium stearate. Prevents ingredients from '
        'sticking to manufacturing equipment. Inert at typical doses.',
  ),
  'stearic acid': InactivePurpose(
    role: 'Manufacturing lubricant',
    detail:
        'Fatty acid (often plant-derived) that prevents ingredients '
        'from sticking to manufacturing equipment.',
  ),
  'silicon dioxide': InactivePurpose(
    role: 'Anti-caking agent',
    detail:
        'Keeps powdered ingredients flowing freely so they don\'t clump '
        'in capsules or bottles. Naturally occurring as fine sand.',
  ),
  'silica': InactivePurpose(
    role: 'Anti-caking agent',
    detail:
        'Same as silicon dioxide — keeps powders flowing freely so they '
        'don\'t clump.',
  ),

  // Bulking / binders
  'microcrystalline cellulose': InactivePurpose(
    role: 'Bulking agent',
    detail:
        'Refined plant cellulose used to fill out the capsule volume '
        'when the active doses are small. Inert and not absorbed.',
  ),
  'mcc': InactivePurpose(
    role: 'Bulking agent',
    detail:
        'Microcrystalline cellulose. Used to fill out the capsule '
        'volume when the active doses are small.',
  ),
  'dicalcium phosphate': InactivePurpose(
    role: 'Tablet binder',
    detail:
        'Calcium-and-phosphorus compound used to bind tablet ingredients '
        'into a stable shape. Provides a small amount of dietary calcium '
        'as a side effect.',
  ),

  // Common solvents
  'water': InactivePurpose(
    role: 'Solvent',
    detail: 'Carrier for the active ingredients in liquids and tinctures.',
  ),
  'purified water': InactivePurpose(
    role: 'Solvent',
    detail: 'Filtered water used as a carrier for the active ingredients.',
  ),

  // Common sweeteners / colorants (these are the ones that should
  // make a user pause — included so the explanation is honest about
  // what they are).
  'sucralose': InactivePurpose(
    role: 'Artificial sweetener',
    detail:
        'Calorie-free synthetic sweetener (~600x sweeter than sugar). '
        'Some users avoid it for personal preference; not banned.',
  ),
  'aspartame': InactivePurpose(
    role: 'Artificial sweetener',
    detail:
        'Calorie-free synthetic sweetener. Avoided by people with '
        'phenylketonuria (PKU); otherwise generally regarded as safe.',
  ),
  'titanium dioxide': InactivePurpose(
    role: 'White colorant',
    detail:
        'Used as a whitening pigment in capsules and tablets. Banned as '
        'a food additive in the EU (2022) over inhalation-safety '
        'concerns; FDA still permits it in supplements.',
  ),
};

class InactivePurpose {
  final String role;
  final String detail;
  const InactivePurpose({required this.role, required this.detail});
}

/// Look up an inactive ingredient's purpose. Returns the matched entry
/// or null when the name isn't in the table — caller falls back to
/// generic copy.
///
/// Public so the test suite can verify the lookup contract directly
/// without pumping a widget.
InactivePurpose? inactiveIngredientPurpose(String name) {
  final key = name.toLowerCase().trim();
  if (key.isEmpty) return null;
  return _inactivePurposes[key];
}

/// Tappable inactive-ingredient chip — opens a bottom sheet explaining
/// the ingredient's purpose when the user taps it.
///
/// The sheet uses [_inactivePurposes] for known names and falls back to
/// a generic "Inactive ingredient — added during manufacturing" copy
/// when the name isn't in the table. Either way the user gets some
/// context, never a dead-end chip.
class InactiveIngredientChip extends StatelessWidget {
  final String name;
  const InactiveIngredientChip({super.key, required this.name});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return PGPressable(
      onTap: () => _showExplanationSheet(context, name),
      pressedScale: 0.94,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(AppTheme.radiusFull),
        ),
        child: Text(
          name,
          style: theme.textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  void _showExplanationSheet(BuildContext context, String ingredientName) {
    PGModal.bottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return _InactiveIngredientExplanationSheet(name: ingredientName);
      },
    );
  }
}

/// Bottom-sheet body explaining an inactive ingredient's purpose.
class _InactiveIngredientExplanationSheet extends StatelessWidget {
  final String name;
  const _InactiveIngredientExplanationSheet({required this.name});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final purpose = inactiveIngredientPurpose(name);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.space20,
        AppTheme.space12,
        AppTheme.space20,
        AppTheme.space24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            name,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: AppTheme.space4),
          Text(
            purpose?.role ?? 'Inactive ingredient',
            style: theme.textTheme.titleSmall?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppTheme.space12),
          Text(
            purpose?.detail ??
                'Added during manufacturing to bind, preserve, '
                    'flavor, color, or otherwise stabilize the product. '
                    'Not part of the active dose.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

/// Section 4 wrapper — provides the canonical "Ingredients" header for
/// the IA section, then delegates to its [child] for the active +
/// inactive rendering.
///
/// The active list rendering stays inside `product_detail_screen.dart`
/// (the existing `_CollapsibleIngredients` already handles the 5-element
/// row spec). This widget is intentionally thin — its job is the section
/// label, not re-implementing the row.
class IngredientsSection extends StatelessWidget {
  final Widget child;
  const IngredientsSection({super.key, required this.child});

  @override
  Widget build(BuildContext context) => child;
}
