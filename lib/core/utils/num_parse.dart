/// Parse a dynamic pipeline value (int, double, or numeric string) into a
/// FINITE double, or null.
///
/// Rejects null, NaN, ±Infinity, and non-numeric strings in EVERY branch — a
/// non-finite value must never enter a score, a dose sum, or a threshold
/// comparison. `double.tryParse('Infinity')` returns a real (non-finite)
/// double, so the string branch guards `isFinite` too.
///
/// Single source of truth: this five-line parse had been hand-copied into
/// ~7 files, and one copy (v4_pillars) dropped the `isFinite` guard — letting
/// a NaN / "Infinity" blob value flow straight into a pillar score. Centralized
/// so the guard can't be forgotten in the next copy.
double? asFiniteDouble(Object? value) {
  if (value is int) return value.toDouble();
  if (value is double) return value.isFinite ? value : null;
  if (value is String) {
    final parsed = double.tryParse(value.trim());
    return (parsed != null && parsed.isFinite) ? parsed : null;
  }
  return null;
}
