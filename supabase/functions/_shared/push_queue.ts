// Supersession policy for the submission push-delivery queue.
//
// A submission can accumulate several pending delivery rows while the
// transport is down (each review transition inserts one). Sending the whole
// backlog replays outdated statuses — the field case: an old `under_review`
// nudge delivered minutes after the submission was already approved. Only
// the newest pending row per submission still reflects reality; the rest
// are discarded, not sent. `review_events` remains the durable audit trail
// of every transition, so dropping superseded queue rows loses nothing.

export interface PendingDeliveryRow {
  id: number;
  submission_id: string;
  user_id: string | null;
  attempts: number;
  created_at: string;
}

export interface DeliveryPartition {
  latest: PendingDeliveryRow[];
  superseded: PendingDeliveryRow[];
}

/// Splits pending rows into the newest row per submission (to send) and
/// every older sibling (to discard). Ordering is by `created_at`, with `id`
/// as the tiebreak — rows are inserted in transition order, so the largest
/// pair is the latest status.
export function partitionSupersededDeliveries(
  rows: PendingDeliveryRow[],
): DeliveryPartition {
  const newestBySubmission = new Map<string, PendingDeliveryRow>();
  for (const row of rows) {
    const current = newestBySubmission.get(row.submission_id);
    if (!current || isNewer(row, current)) {
      newestBySubmission.set(row.submission_id, row);
    }
  }
  const latest: PendingDeliveryRow[] = [];
  const superseded: PendingDeliveryRow[] = [];
  for (const row of rows) {
    if (newestBySubmission.get(row.submission_id) === row) {
      latest.push(row);
    } else {
      superseded.push(row);
    }
  }
  return { latest, superseded };
}

function isNewer(a: PendingDeliveryRow, b: PendingDeliveryRow): boolean {
  if (a.created_at !== b.created_at) return a.created_at > b.created_at;
  return a.id > b.id;
}
