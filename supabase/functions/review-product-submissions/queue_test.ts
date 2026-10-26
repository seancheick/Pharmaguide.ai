import { assertEquals, assertThrows } from "jsr:@std/assert@1.0.14";

import {
  cursorFilter,
  nextListCursor,
  parseListRequest,
  reviewStatusesForList,
} from "./queue.ts";

Deno.test("open list expands to submitted and under_review", () => {
  const request = parseListRequest({ action: "list", status: "open" });
  assertEquals(reviewStatusesForList(request.status), [
    "submitted",
    "under_review",
  ]);
});

Deno.test("list cursor is the exact submitted_at and UUID pair", () => {
  const request = parseListRequest({
    action: "list",
    limit: 25,
    after: {
      submitted_at: "2026-08-25T16:20:30.123456+00:00",
      id: "018f4c79-7c7e-4c70-9d62-7fc3b9ce6a11",
    },
  });
  assertEquals(request.after, {
    submittedAt: "2026-08-25T16:20:30.123456+00:00",
    id: "018f4c79-7c7e-4c70-9d62-7fc3b9ce6a11",
  });
  assertEquals(
    cursorFilter(request.after!),
    "submitted_at.gt.2026-08-25T16:20:30.123456+00:00," +
      "and(submitted_at.eq.2026-08-25T16:20:30.123456+00:00," +
      "id.gt.018f4c79-7c7e-4c70-9d62-7fc3b9ce6a11)",
  );
});

Deno.test("list cursor and unknown fields fail closed", () => {
  assertThrows(() =>
    parseListRequest({
      action: "list",
      after: { submitted_at: "not-a-time", id: "not-a-uuid" },
    })
  );
  assertThrows(() => parseListRequest({ action: "list", offset: 10 }));
  assertThrows(() =>
    parseListRequest({
      action: "list",
      submission_id: "018f4c79-7c7e-4c70-9d62-7fc3b9ce6a11",
      after: {
        submitted_at: "2026-08-25T16:20:30Z",
        id: "018f4c79-7c7e-4c70-9d62-7fc3b9ce6a11",
      },
    })
  );
});

Deno.test("next cursor is emitted only for a full page", () => {
  const rows = [
    {
      submitted_at: "2026-08-25T16:20:30Z",
      id: "018f4c79-7c7e-4c70-9d62-7fc3b9ce6a11",
    },
    {
      submitted_at: "2026-08-25T16:20:31Z",
      id: "118f4c79-7c7e-4c70-9d62-7fc3b9ce6a22",
    },
  ];
  assertEquals(nextListCursor(rows, 2), rows[1]);
  assertEquals(nextListCursor(rows, 3), null);
});

Deno.test("mixed queue keeps submitter retakes and reviewer staging separate from ready evidence", async () => {
  const { loadQueueEvidence, queuePhotosToSign } = await import("./queue.ts");
  const rows = [
    { id: "retake", upload_state: "pending", evidence_revision: 2 },
    { id: "reviewer", upload_state: "pending", evidence_revision: 3 },
    { id: "ordinary", upload_state: "ready", evidence_revision: 1 },
  ];
  const calls: string[] = [];
  const responses = await Promise.all(rows.map(async (row) => {
    const evidence = await loadQueueEvidence(row, {
      hasReviewerPhotos: async () => row.id === "reviewer",
      pendingReviewer: async () => {
        calls.push(`reviewer:${row.id}`);
        if (row.id !== "reviewer") {
          throw new Error("reviewer RPC denies submitter");
        }
        return {
          evidence_revision: 3,
          manifest_sha256: "a".repeat(64),
          evidence_snapshot: {},
          photos: [{ object_path: "not-uploaded-yet" }],
        };
      },
      ready: async () => {
        calls.push(`ready:${row.id}`);
        return {
          evidence_revision: 1,
          manifest_sha256: "b".repeat(64),
          evidence_snapshot: {},
          photos: [{ object_path: "ready-photo" }],
        };
      },
    });
    return { evidence, sign: queuePhotosToSign(row, evidence) };
  }));
  assertEquals(calls.sort(), ["ready:ordinary", "reviewer:reviewer"]);
  assertEquals(responses[0].evidence, {
    evidence_revision: 2,
    manifest_sha256: null,
    evidence_snapshot: {},
    photos: [],
  });
  assertEquals(responses.map((row) => row.sign), [[], [], [{
    object_path: "ready-photo",
  }]]);
});

Deno.test("pending reviewer evidence access failures remain denied", async () => {
  const { loadQueueEvidence } = await import("./queue.ts");
  let denied = false;
  try {
    await loadQueueEvidence({ upload_state: "pending", evidence_revision: 2 }, {
      hasReviewerPhotos: async () => true,
      ready: async () => {
        throw new Error("must not fall back to ready RPC");
      },
      pendingReviewer: async () => {
        throw new Error("reviewer evidence denied");
      },
    });
  } catch (error) {
    denied = error instanceof Error &&
      error.message === "reviewer evidence denied";
  }
  assertEquals(denied, true);
});
