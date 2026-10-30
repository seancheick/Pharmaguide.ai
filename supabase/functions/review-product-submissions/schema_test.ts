import { assertEquals, assertRejects } from "jsr:@std/assert@1.0.14";

import {
  collectManualLabelDiagnostics,
  validateManualLabelV1,
} from "./schema.ts";
import fixtureJson from "./fixtures/manual_label_v1_cases.json" with {
  type: "json",
};

const FIXTURE_SHA256 =
  "25d0904d4d811688b9e82d6a2a449ea50730af6589a1f18ab6ea5f7f40fa3803";
const fixture = fixtureJson as {
  cases: Array<
    {
      name: string;
      valid: boolean;
      payload: unknown;
      path?: string;
      typescript_message?: string;
    }
  >;
};

/** The JSON location a rejection names: structure, not prose. */
function rejectedPath(message: string): string {
  const head = message.split(" ")[0];
  return head.includes("[") || head.includes(".") ? head : "$";
}

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
      const error = await assertRejects(
        async () => validateManualLabelV1(testCase.payload),
        Error,
        undefined,
        testCase.name,
      );
      // Both the location and the exact wording are pinned. manual_label_v1 is
      // implemented twice — here for the approval gate and in Python for the
      // catalog gate — so the only defence against the two drifting apart is
      // that neither can change what it says without this failing.
      assertEquals(error.message, testCase.typescript_message, testCase.name);
      assertEquals(rejectedPath(error.message), testCase.path, testCase.name);
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
  "4e72ee1884ed9b941281bc4977288f77ca0d44180d11de3be969769a86300761";
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

Deno.test("canonical approval envelope uses the same writer as label attestations", async () => {
  const { canonicalJson } = await import("./schema.ts");
  assertEquals(
    canonicalJson({
      label: { fullName: "D3", brandName: "Éxample" },
      identity: { observed: null, match_check_id: 12 },
    }),
    '{"identity":{"match_check_id":12,"observed":null},"label":{"brandName":"Éxample","fullName":"D3"}}',
  );
});

Deno.test("an approximate servings count must be a whole number", () => {
  const base = fixture.cases.find((c) => c.name === "valid_declared_none")!
    .payload as Record<string, unknown>;
  for (const printed of ["about 17", "About 50", "about 1,000"]) {
    validateManualLabelV1({ ...base, servingsPerContainer: printed });
  }
  for (const printed of ["about 1.5", "about 0.5"]) {
    let message = "";
    try {
      validateManualLabelV1({ ...base, servingsPerContainer: printed });
    } catch (error) {
      message = (error as Error).message;
    }
    assertEquals(message, "servingsPerContainer must be positive", printed);
  }
});
