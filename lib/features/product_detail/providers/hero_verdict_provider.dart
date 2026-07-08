// HeroVerdict — safety-aware verdict computer for the score-led hero.
//
// Spec: INITIATIVE_PRODUCT_TRUST_AND_IA.md, Sprint 1, T1.1.
//
// The product detail hero shows a Quality Score ring + identity. A
// safety-aware verdict banner is rendered in the hero ONLY when a
// product is product-side blocking (UNSAFE/BLOCKED) or when the
// user's stack carries an Avoid/Contraindicated interaction with
// the product. Lower-severity verdicts (Caution / Monitor / Safe /
// Recommended / etc.) live in Section 2 ("For You") — they don't
// belong in the hero alongside the product score.
//
// The "provider" naming in the file path tracks the spec; this
// module exposes a pure-function helper rather than a Riverpod
// provider. Call sites do their own watching of the upstream data
// (product verdict, blockingReason, topWarnings list,
// bannedSubstanceDetail blob), pass the resolved values in, get a
// sealed result back, and dispatch on it.

import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/widgets/verdict_badge.dart'
    show isUnsafeVerdict;
import 'package:pharmaguide/services/warnings/interaction_warning.dart';

/// Sealed verdict outcome the hero renders.
sealed class HeroVerdict {
  const HeroVerdict();
}

/// Product is UNSAFE or BLOCKED at the product-side scoring level.
/// Render the existing `_BlockedBanner` (severity-banner-as-banner +
/// banned-substance detail + FDA links).
final class HeroVerdictBlocked extends HeroVerdict {
  /// The raw verdict string from the product (`'BLOCKED'` or `'UNSAFE'`).
  final String verdict;
  final String blockingReason;
  final List<Map<String, dynamic>> topWarnings;
  final Map<String, dynamic>? bannedSubstanceDetail;

  const HeroVerdictBlocked({
    required this.verdict,
    required this.blockingReason,
    required this.topWarnings,
    this.bannedSubstanceDetail,
  });
}

/// Product is otherwise valid but the user's stack has an
/// Avoid- or Contraindicated-tier interaction with it. Render a
/// danger-tone banner whose headline is the [headline] string —
/// "Use caution with metformin" / "Not recommended with warfarin"
/// / etc.
final class HeroVerdictAvoid extends HeroVerdict {
  /// Either [Severity.avoid] or [Severity.contraindicated].
  final Severity severity;

  /// Best-effort name of the offending medication / supplement /
  /// condition (e.g. "metformin"). Null when the warning shape
  /// didn't surface a clear agent name; in that case [headline]
  /// degrades to "Use caution for your stack" / "Not recommended
  /// for your stack" copy.
  final String? offendingAgent;

  const HeroVerdictAvoid({required this.severity, this.offendingAgent})
    : assert(
        // NB: a const-constructor assert can't call the `isHard` getter
        // (not a compile-time constant), so this one site keeps the explicit
        // enum comparison. Behaviourally identical to `severity.isHard`.
        severity == Severity.avoid || severity == Severity.contraindicated,
        'HeroVerdictAvoid is only valid for Avoid or Contraindicated '
        'severities — lower tiers belong in Section 2.',
      );

  /// Banner headline, composed from severity + agent. Public so the
  /// hero widget can render it directly without re-deriving.
  ///
  /// Voice — PharmaGuide brand voice per pharmaguide.io: clinical
  /// precision without alarm. The danger-tone banner color already
  /// carries the urgency; the headline copy is calm advisory.
  ///
  ///   - `contraindicated` → "Not recommended" (strongest tier,
  ///     stack-side conflict, banner-red)
  ///   - `avoid`           → "Use caution"     (next tier down,
  ///     banner-red but copy is hedged)
  ///
  /// Voice rule per feedback_copy_voice.md: no "Stop", "Avoid",
  /// "Don't take" imperatives in Flutter-derived strings.
  String get headline {
    final base = severity == Severity.contraindicated
        ? 'Not recommended'
        : 'Use caution';
    // Hoist into a local so the null-check and the use can't be torn
    // apart by a future edit (no `!` on a re-read field).
    final agent = offendingAgent?.trim();
    if (agent != null && agent.isNotEmpty) {
      return '$base with $agent';
    }
    return '$base for your stack';
  }
}

/// No banner. Lower-severity verdicts (Caution, Monitor, Safe,
/// Recommended, etc.) flow through to Section 2 ("For You").
final class HeroVerdictNone extends HeroVerdict {
  const HeroVerdictNone();
}

/// Decide which verdict banner (if any) the hero should show.
///
/// Decision order (highest priority first):
///   1. Product-side BLOCKED / UNSAFE → [HeroVerdictBlocked]. The
///      product's own verdict is the most serious signal — wins
///      regardless of what the stack interactions look like.
///   2. Stack-side max severity is Avoid or Contraindicated →
///      [HeroVerdictAvoid] with the offending agent (when the
///      warning shape exposes one). A medication-side Avoid/Contra
///      overrides a product-side RECOMMENDED/GOOD/etc., because
///      "safety > goal match" is the locked rule for this initiative.
///   3. Otherwise → [HeroVerdictNone]. Nothing in the hero. The
///      verdict information surfaces in Section 2 instead.
///
/// Pure function — no I/O, no provider deps. Test by constructing
/// inputs directly and asserting on the returned variant.
///
/// When [guardedWarnings] is provided (profile exists and the caller
/// already ran the warning compose pipeline), the stack-side severity
/// walk in step (2) uses those typed warnings instead of the raw
/// [topWarnings] maps — they carry live stack context the static
/// blob maps can't know about.
HeroVerdict computeHeroVerdict({
  required String? productVerdict,
  required String blockingReason,
  required List<Map<String, dynamic>> topWarnings,
  Map<String, dynamic>? bannedSubstanceDetail,
  List<InteractionWarning>? guardedWarnings,
}) {
  // (1) Product-side blocking takes precedence.
  if (isUnsafeVerdict(productVerdict)) {
    return HeroVerdictBlocked(
      verdict: (productVerdict ?? 'BLOCKED').trim().toUpperCase(),
      blockingReason: blockingReason,
      topWarnings: topWarnings,
      bannedSubstanceDetail: bannedSubstanceDetail,
    );
  }

  // (2) Walk the stack-side warnings, hold onto the worst severity
  // and the warning that produced it (so we can extract the agent).
  // Typed guarded warnings (when supplied) take precedence over the
  // raw blob maps.
  if (guardedWarnings != null) {
    Severity? maxTypedSeverity;
    InteractionWarning? offendingTyped;
    for (final w in guardedWarnings) {
      if (w.severity.weight > (maxTypedSeverity?.weight ?? -1)) {
        maxTypedSeverity = w.severity;
        offendingTyped = w;
      }
    }
    if (maxTypedSeverity == Severity.contraindicated ||
        maxTypedSeverity == Severity.avoid) {
      return HeroVerdictAvoid(
        severity: maxTypedSeverity!,
        offendingAgent: _agentNameFromWarning(offendingTyped),
      );
    }
    return const HeroVerdictNone();
  }

  Severity? maxSeverity;
  Map<String, dynamic>? offendingWarning;
  for (final w in topWarnings) {
    // Defensive read — pipeline drift could ship an int / bool / null
    // under the `severity` key. Anything that isn't a non-empty String
    // is treated as "no severity here" rather than a cast crash.
    final rawValue = w['severity'];
    if (rawValue is! String) continue;
    final raw = rawValue.toLowerCase().trim();
    if (raw.isEmpty) continue;
    final sev = Severity.values.firstWhere(
      (s) => s.name == raw,
      orElse: () => Severity.safe,
    );
    if (sev.weight > (maxSeverity?.weight ?? -1)) {
      maxSeverity = sev;
      offendingWarning = w;
    }
  }

  if (maxSeverity == Severity.contraindicated ||
      maxSeverity == Severity.avoid) {
    return HeroVerdictAvoid(
      severity: maxSeverity!,
      offendingAgent: _extractAgentName(offendingWarning),
    );
  }

  // (3) Caution / Monitor / Informational / Safe / Recommended /
  //     Good / Moderate / Review / NOT_SCORED — none of these gate
  //     the hero. Their verdict information lives in Section 2.
  return const HeroVerdictNone();
}

/// Best-effort extraction of an offending agent's display name from
/// a warning map. Different pipeline producers stamp the agent
/// under different field names; this walks a small allowlist of
/// likely keys and returns the first non-empty match. Returns null
/// when no clear name surfaces — caller's headline copy degrades
/// to a generic "Avoid for your stack".
/// Best-effort agent name from a typed [InteractionWarning]. The
/// personalized pipeline stamps titles as "Because you're taking X";
/// extract X when that shape is present, otherwise return null so the
/// headline degrades to the generic "for your stack" copy.
String? _agentNameFromWarning(InteractionWarning? warning) {
  if (warning == null) return null;
  const prefix = "Because you're taking ";
  final title = warning.title.trim();
  if (title.startsWith(prefix)) {
    final agent = title.substring(prefix.length).trim();
    if (agent.isNotEmpty) return agent;
  }
  return null;
}

String? _extractAgentName(Map<String, dynamic>? warning) {
  if (warning == null) return null;
  // Order is intentional: most specific first. `with` is the
  // pipeline's canonical "interacts with X" key when present;
  // `medication` / `drug` / `agent` cover variant producers.
  for (final key in const [
    'with',
    'interacting_with',
    'medication',
    'drug',
    'agent',
    'name',
  ]) {
    final v = warning[key]?.toString().trim();
    if (v != null && v.isNotEmpty) return v;
  }
  return null;
}
