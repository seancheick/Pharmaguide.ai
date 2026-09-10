import { assertEquals, assertRejects } from "jsr:@std/assert@1.0.14";

import {
  collectManualLabelDiagnostics,
  validateManualLabelV1,
} from "./schema.ts";
import fixtureJson from "./fixtures/manual_label_v1_cases.json" with {
  type: "json",
};

const FIXTURE_SHA256 =
  "3498b58d19399f187aa6d71d78f5bf1aa6583f21ff2479190956cf07fa7bd0de";
const fixture = fixtureJson as {
  cases: Array<{ name: string; valid: boolean; payload: unknown }>;
};

function canonicalJson(value: unknown): string {
  if (
    value === null || typeof value === "boolean" ||
    typeof value === "string" || typeof value === "number"
  ) {
    return JSON.stringify(value);
  }
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(",")}]`;
  if (typeof value === "object") {
    const object = value as Record<string, unknown>;
    return `{${
      Object.keys(object).sort().map((key) =>
        `${JSON.stringify(key)}:${canonicalJson(object[key])}`
      ).join(",")
    }}`;
  }
  throw new Error("unsupported fixture value");
}

async function sha256Hex(value: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", value.slice().buffer);
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

Deno.test("manual_label_v1 fixture contract stays checksum pinned", async () => {
  const bytes = new TextEncoder().encode(canonicalJson(fixture));
  assertEquals(await sha256Hex(bytes), FIXTURE_SHA256);
});

Deno.test("manual_label_v1 accepts and rejects the shared contract cases", async () => {
  for (const testCase of fixture.cases) {
    if (testCase.valid) {
      validateManualLabelV1(testCase.payload);
    } else {
      await assertRejects(
        async () => validateManualLabelV1(testCase.payload),
        Error,
        undefined,
        testCase.name,
      );
    }
  }
});

Deno.test("manual-label diagnostics retain the whole-payload failure", () => {
  const payload: Record<string, unknown> = {
    brandName: "Example",
    unexpected: true,
    ingredientRows: [{ name: "Vitamin C", ingredientGroup: "vitamins" }],
  };
  const diagnostics = collectManualLabelDiagnostics(payload);
  assertEquals(diagnostics[0].path, "$");
  assertEquals(
    diagnostics[0].message,
    "approved payload contains unknown field unexpected",
  );
});

// ---------------------------------------------------------------------------
// label_draft_v1: the partial, provenance-bound draft an extractor produces.
// Paired with scripts/submission_review/fixtures/label_draft_v1_cases.json in
// the pipeline repo; both sides pin the checksum so the validators cannot drift.

import { validateLabelDraftV1 } from "./schema.ts";
import mutationFixture from "./fixtures/label_draft_v1_mutations.json" with {
  type: "json",
};
import draftFixtureJson from "./fixtures/label_draft_v1_cases.json" with {
  type: "json",
};

const DRAFT_FIXTURE_SHA256 =
  "849eb10a21f5f4901b579a3f7be070c0eaf861bb72551c30f27bebbe1cb04c15";
const DRAFT_MUTATIONS_SHA256 =
  "a4b24d91433ab34e7c4eef22e8f75e09d9fddc37dddf637d0fe06ade8050c0c4";
const draftFixture = draftFixtureJson as {
  cases: Array<{ name: string; valid: boolean; payload: unknown }>;
};

for (const testCase of mutationFixture.cases) {
  Deno.test(`label draft provenance: ${testCase.name}`, () => {
    const draft = structuredClone(draftFixture.cases[0].payload) as Record<
      string,
      unknown
    >;
    for (const change of testCase.changes) {
      let target: any = draft;
      for (const part of change.path.slice(0, -1)) target = target[part];
      target[change.path.at(-1)!] = change.value;
    }
    function removeRefs(value: unknown): void {
      if (Array.isArray(value)) value.forEach(removeRefs);
      else if (value !== null && typeof value === "object") {
        delete (value as Record<string, unknown>).input_id;
        Object.values(value).forEach(removeRefs);
      }
    }
    if ("remove_input_refs" in testCase && testCase.remove_input_refs) {
      removeRefs(draft);
    }
    let error: unknown;
    try {
      validateLabelDraftV1(draft);
    } catch (caught) {
      error = caught;
    }
    assertEquals(error === undefined, testCase.valid, testCase.name);
  });
}

Deno.test("label_draft_v1 fixture contract stays checksum pinned", async () => {
  const digest = await sha256Hex(
    new TextEncoder().encode(canonicalJson(draftFixtureJson)),
  );
  assertEquals(digest, DRAFT_FIXTURE_SHA256);
  assertEquals(
    await sha256Hex(new TextEncoder().encode(canonicalJson(mutationFixture))),
    DRAFT_MUTATIONS_SHA256,
  );
});

Deno.test("label_draft_v1 accepts and rejects the shared contract cases", () => {
  for (const testCase of draftFixture.cases) {
    if (testCase.valid) {
      const validated = validateLabelDraftV1(testCase.payload);
      assertEquals(validated, testCase.payload, testCase.name);
    } else {
      let threw = false;
      try {
        validateLabelDraftV1(testCase.payload);
      } catch {
        threw = true;
      }
      assertEquals(threw, true, `expected rejection: ${testCase.name}`);
    }
  }
});
