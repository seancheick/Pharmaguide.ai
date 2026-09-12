import { assertEquals, assertRejects } from "jsr:@std/assert@1.0.14";

import { loadSubmissionDrafts } from "./drafts.ts";

function refusingClient(rpc: (name: string, args: unknown) => unknown) {
  return {
    rpc,
    from(table: string): never {
      throw new Error(`read ${table} directly`);
    },
  } as never;
}

// product_submission_extractions is revoked from every API role, service_role
// included, so a direct select is a permission error in production. The console
// swallows that failure as a refresh that never lands, which leaves a decided
// submission showing its old status and makes the next decision look broken.
Deno.test("drafts are read through the reviewer function, never off the table", async () => {
  const calls: { name: string; args: unknown }[] = [];
  const drafts = await loadSubmissionDrafts(
    refusingClient((name, args) => {
      calls.push({ name, args });
      return Promise.resolve({ data: [{ version: 2 }], error: null });
    }),
    "018f4c79-7c7e-4c70-9d62-7fc3b9ce6a11",
    3,
  );
  assertEquals(calls, [{
    name: "get_product_submission_extractions",
    args: {
      p_submission_id: "018f4c79-7c7e-4c70-9d62-7fc3b9ce6a11",
      p_evidence_revision: 3,
    },
  }]);
  assertEquals(drafts, [{ version: 2 }]);
});

Deno.test("a refused read is an error, never an empty draft list", async () => {
  await assertRejects(() =>
    loadSubmissionDrafts(
      refusingClient(() =>
        Promise.resolve({ data: null, error: new Error("permission denied") })
      ),
      "018f4c79-7c7e-4c70-9d62-7fc3b9ce6a11",
      1,
    )
  );
});

Deno.test("no recorded draft reads as no drafts", async () => {
  assertEquals(
    await loadSubmissionDrafts(
      refusingClient(() => Promise.resolve({ data: null, error: null })),
      "018f4c79-7c7e-4c70-9d62-7fc3b9ce6a11",
      1,
    ),
    [],
  );
});
