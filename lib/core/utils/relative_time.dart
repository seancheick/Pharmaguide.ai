/// Returns a compact human-readable relative timestamp for a past
/// [DateTime].
///
/// Output ladder:
/// - `< 1 minute` → `"Just now"`
/// - `< 60 minutes` → `"Nm ago"`
/// - `< 24 hours` → `"Nh ago"`
/// - exactly `1 day` → `"Yesterday"`
/// - `>= 2 days` → `"Nd ago"`
///
/// [now] is exposed for testability — production callers omit it.
///
/// This matches the ladder previously duplicated inside the home Recents
/// widgets. Centralized so a copy or threshold tweak only happens in one
/// place. Callers should pass past timestamps; future timestamps are
/// treated as "Just now" because [Duration.inMinutes] of a negative
/// difference is `<= 0`.
String relativeTime(DateTime when, {DateTime? now}) {
  final ref = now ?? DateTime.now();
  final diff = ref.difference(when);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays == 1) return 'Yesterday';
  return '${diff.inDays}d ago';
}
