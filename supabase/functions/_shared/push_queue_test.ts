import {
  partitionSupersededDeliveries,
  type PendingDeliveryRow,
} from "./push_queue.ts";

function row(
  id: number,
  submissionId: string,
  createdAt: string,
): PendingDeliveryRow {
  return {
    id,
    submission_id: submissionId,
    user_id: "user-1",
    attempts: 0,
    created_at: createdAt,
  };
}

function assertIds(actual: PendingDeliveryRow[], expected: number[]): void {
  const ids = actual.map((r) => r.id).join(",");
  if (ids !== expected.join(",")) {
    throw new Error(`expected ids [${expected.join(",")}], got [${ids}]`);
  }
}

Deno.test("keeps only the newest pending row per submission", () => {
  const { latest, superseded } = partitionSupersededDeliveries([
    row(1, "sub-a", "2026-08-25T15:54:51Z"),
    row(2, "sub-a", "2026-08-25T16:09:28Z"),
    row(3, "sub-a", "2026-08-26T13:44:52Z"),
  ]);
  assertIds(latest, [3]);
  assertIds(superseded, [1, 2]);
});

Deno.test("submissions do not supersede each other", () => {
  const { latest, superseded } = partitionSupersededDeliveries([
    row(1, "sub-a", "2026-08-25T10:00:00Z"),
    row(2, "sub-b", "2026-08-25T11:00:00Z"),
  ]);
  assertIds(latest, [1, 2]);
  assertIds(superseded, []);
});

Deno.test("equal timestamps fall back to the larger id", () => {
  const { latest, superseded } = partitionSupersededDeliveries([
    row(2, "sub-a", "2026-08-25T10:00:00Z"),
    row(1, "sub-a", "2026-08-25T10:00:00Z"),
  ]);
  assertIds(latest, [2]);
  assertIds(superseded, [1]);
});

Deno.test("empty input yields empty partitions", () => {
  const { latest, superseded } = partitionSupersededDeliveries([]);
  assertIds(latest, []);
  assertIds(superseded, []);
});
