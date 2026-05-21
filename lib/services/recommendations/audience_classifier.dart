// Audience classifier — Phase 11.7L.F.
//
// PharmaGuide's bundled catalog doesn't carry an explicit "audience"
// column. We infer audience from the product name (and, when needed,
// the brand) for the Better Alternatives ranker so we can hard-block
// recommendations that cross clinical-audience lines.
//
// What we infer:
//
//   * kids        — children's chewables, juniors, gummies for kids
//   * prenatal    — pregnancy, TTC (trying to conceive), nursing
//   * mens        — male-specific multis / male performance / men's brands
//   * womens      — female-specific multis / women's brands
//   * senior      — 50+ / 60+ / mature / "for adults over 50"
//   * sport       — pre-workout / post-workout / endurance / athletic
//   * general     — none of the above (the fallback)
//
// The ranker's policy:
//
//   * Kids and prenatal are **HARD walls**. Don't ever cross them.
//     Sean's call: recommending an adult prenatal to a parent
//     shopping for a kids' multi is tone-deaf at best.
//   * Sport ↔ general is **HARD unless ingredient-family overlap
//     ≥ 0.5**. Carve-out implemented in the ranker, not here.
//   * Men's / women's / senior are **SOFT** — preferred-same but
//     general is allowed as a swap. Implemented as a tier-demote
//     in the ranker, not here.

import 'package:pharmaguide/data/database/core_database.dart';

/// Inferred product audience. The enum values exist for clinical
/// hard-block logic in `BetterAlternativesRanker` — they are NOT
/// surfaced anywhere in the UI today.
enum Audience { kids, prenatal, mens, womens, senior, sport, general }

/// Pure inference helper. Reads the product's name (and, as a
/// secondary signal, brand name) and returns the most-specific
/// audience marker that matches. Returns [Audience.general] when no
/// marker matches.
///
/// Ordering matters: kids is checked before mens/womens so "Kids
/// Multi For Boys" classifies as `kids`, not `mens`. Same for
/// prenatal over womens.
Audience inferAudience(ProductsCoreData product) {
  final name = product.productName.toLowerCase();
  final brand = (product.brandName ?? '').toLowerCase();
  final haystack = '$name $brand';

  // Order of checks is INTENTIONAL. Most clinical first.
  if (_hasAny(haystack, _prenatalMarkers)) return Audience.prenatal;
  if (_hasAny(haystack, _kidsMarkers)) return Audience.kids;
  if (_hasAny(haystack, _seniorMarkers)) return Audience.senior;
  // Sport is checked BEFORE mens/womens because "Men's Performance"
  // should bucket as sport (intent) not mens (audience). We're
  // optimising for the recommendation's purpose, not the marketing
  // label.
  if (_hasAny(haystack, _sportMarkers)) return Audience.sport;
  if (_hasAny(haystack, _mensMarkers)) return Audience.mens;
  if (_hasAny(haystack, _womensMarkers)) return Audience.womens;
  return Audience.general;
}

/// Hard audience compatibility check for the Better Alternatives
/// ranker. Returns `true` when the candidate is an acceptable swap
/// for the current product on audience grounds alone (other hard
/// filters and ranking still apply).
///
/// Rules (from Sean 2026-05-16):
///
///   * Kids products only swap with kids.
///   * Prenatal products only swap with prenatal.
///   * Sport ↔ general carve-out is handled in the ranker (it needs
///     the ingredient-overlap fraction); here we treat sport and
///     general as compatible — the ranker downgrades the bucket if
///     ingredient overlap is below 0.5.
///   * Men's / women's / senior are pairwise blocked from each
///     other but compatible with general (the ranker may further
///     demote a non-same-audience match to a lower tier).
///
/// Returns false when the recommendation would cross a hard wall.
bool isAudienceCompatible(Audience current, Audience candidate) {
  // Kids is a complete wall.
  if (current == Audience.kids || candidate == Audience.kids) {
    return current == candidate;
  }
  // Prenatal is a complete wall.
  if (current == Audience.prenatal || candidate == Audience.prenatal) {
    return current == candidate;
  }
  // Specific-audience cross-blocks: mens ↔ womens, mens ↔ senior,
  // womens ↔ senior never recommend each other. They DO compatible
  // with general (verified via the explicit general check below).
  const specific = {Audience.mens, Audience.womens, Audience.senior};
  if (specific.contains(current) && specific.contains(candidate)) {
    return current == candidate;
  }
  // Sport ↔ general handled at the ranker level — here we allow it
  // through so the ranker can apply the ingredient-overlap carveout.
  return true;
}

bool _hasAny(String haystack, List<RegExp> patterns) {
  for (final p in patterns) {
    if (p.hasMatch(haystack)) return true;
  }
  return false;
}

// Word boundaries matter — "for kids" should match, but "for adults"
// must not match "kids" via substring. Use \b on both sides of every
// marker. Single-word markers get an exact-word check; compound
// markers stay as phrases. Case-insensitive by lowercasing both
// sides at call time, so no `i` flag needed.

final List<RegExp> _kidsMarkers = [
  RegExp(r"\bkids?\b"),
  RegExp(r"\bkid['’]s\b"),
  RegExp(r"\bchildrens?\b"),
  RegExp(r"\bchildren['’]s\b"),
  RegExp(r"\bchild\b"),
  RegExp(r"\bjunior\b"),
  RegExp(r"\binfant\b"),
  RegExp(r"\btoddler\b"),
  RegExp(r"\bbaby\b"),
];

final List<RegExp> _prenatalMarkers = [
  RegExp(r"\bprenatal\b"),
  RegExp(r"\bpre[- ]natal\b"),
  RegExp(r"\bpregnancy\b"),
  RegExp(r"\bttc\b"),
  RegExp(r"\btrying to conceive\b"),
  RegExp(r"\bnursing\b"),
  RegExp(r"\bpostpartum\b"),
  RegExp(r"\bfertility\b"),
];

final List<RegExp> _mensMarkers = [
  RegExp(r"\bmen['’]s\b"),
  RegExp(r"\bfor men\b"),
  RegExp(r"\b(?:mens|mega men|gnc men)\b"),
];

final List<RegExp> _womensMarkers = [
  RegExp(r"\bwomen['’]s\b"),
  RegExp(r"\bfor women\b"),
  RegExp(r"\b(?:womens|her daily|her multi)\b"),
];

final List<RegExp> _seniorMarkers = [
  RegExp(r"\bseniors?\b"),
  // `\b` doesn't work as a trailing anchor for `+` (non-word char
  // followed by non-word char yields no boundary). Use a lookahead
  // for whitespace, dash, or end-of-string instead.
  RegExp(r"\b50\+(?=\s|$|[-,.])"),
  RegExp(r"\b60\+(?=\s|$|[-,.])"),
  RegExp(r"\b70\+(?=\s|$|[-,.])"),
  RegExp(r"\bover 50\b"),
  RegExp(r"\bover 60\b"),
  RegExp(r"\bover 70\b"),
  RegExp(r"\bmature(?: adult)?\b"),
];

final List<RegExp> _sportMarkers = [
  RegExp(r"\bsport\b"),
  RegExp(r"\bperformance\b"),
  RegExp(r"\bathletic\b"),
  RegExp(r"\bathletes?\b"),
  RegExp(r"\b(?:pre|post)[- ]?workout\b"),
  RegExp(r"\bendurance\b"),
  RegExp(r"\bmuscle (?:builder|growth|recovery|gain)\b"),
  RegExp(r"\bbodybuilding\b"),
];
