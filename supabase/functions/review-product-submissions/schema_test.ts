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
