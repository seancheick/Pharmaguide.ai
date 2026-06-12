/// Shared label-coverage contract.
///
/// SAFETY RULE (CLAUDE.md, non-negotiable): never display "safe" when
/// `mapped_coverage < 0.3`. The threshold and the hedge copy below are two
/// halves of the same contract — every surface that gates on the floor must
/// use these constants so the rule can never drift per-surface.
library;

/// Trust floor for `mapped_coverage`. Below this, a product's ingredients
/// may never fire the interaction/scoring checks, so no surface may render
/// a confident clean/safe result.
const double kLowCoverageFloor = 0.3;

/// Base hedge sentence shown when coverage is below [kLowCoverageFloor]
/// (or data is otherwise incomplete). Surfaces append a context suffix via
/// [coverageHedge].
const String kCoverageHedgeBase = "Some labels couldn't be fully analyzed";

/// Build the standard hedge line, e.g.
/// `coverageHedge('results may be incomplete')` →
/// "Some labels couldn't be fully analyzed — results may be incomplete."
String coverageHedge(String suffix) => '$kCoverageHedgeBase — $suffix.';

/// True when a product's mapped coverage is below the trust floor.
/// Null coverage is treated as 0 (unknown ≠ trustworthy).
bool isLowCoverage(double? mappedCoverage) =>
    (mappedCoverage ?? 0.0) < kLowCoverageFloor;
