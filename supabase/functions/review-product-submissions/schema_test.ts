import { assertEquals, assertRejects } from "jsr:@std/assert@1.0.14";

import { validateManualLabelV1 } from "./schema.ts";
import fixtureJson from "./fixtures/manual_label_v1_cases.json" with {
  type: "json",
};

const FIXTURE_SHA256 =
  "6dd08b64eaab05530e4c3b2e97e1e483bc203c5ed7750affb0cd981db086767a";
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

// ---------------------------------------------------------------------------
// label_draft_v1: the partial, provenance-bound draft an extractor produces.
// Paired with scripts/submission_review/fixtures/label_draft_v1_cases.json in
// the pipeline repo; both sides pin the checksum so the validators cannot drift.

import { validateLabelDraftV1 } from "./schema.ts";
import draftFixtureJson from "./fixtures/label_draft_v1_cases.json" with {
  type: "json",
};

const DRAFT_FIXTURE_SHA256 =
  "6e7e5499704a3b142aa9d85dbadf717f4b2fb1d46bd01b0bda3bc5ad4bdf2924";
const draftFixture = draftFixtureJson as {
  cases: Array<{ name: string; valid: boolean; payload: unknown }>;
};

Deno.test("label_draft_v1 fixture contract stays checksum pinned", async () => {
  const digest = await sha256Hex(
    new TextEncoder().encode(canonicalJson(draftFixtureJson)),
  );
  assertEquals(digest, DRAFT_FIXTURE_SHA256);
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
