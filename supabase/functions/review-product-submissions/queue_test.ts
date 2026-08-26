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
