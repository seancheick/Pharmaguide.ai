import { assertEquals } from "jsr:@std/assert@1.0.14";

// The entry point refuses any action that is not in ACTIONS before a handler
// is reached, so a handler added without its allowlist entry is dead code that
// every parser test still passes. This ties the two lists together.
// Run with: deno test --allow-read actions_test.ts
const source = Deno.readTextFileSync(new URL("./index.ts", import.meta.url));

function allowlist(): Set<string> {
  const block = source.match(/const ACTIONS = new Set\(\[([\s\S]*?)\]\);/);
  if (!block) throw new Error("ACTIONS allowlist not found");
  return new Set([...block[1].matchAll(/"([a-z_]+)"/g)].map((m) => m[1]));
}

function handled(): Set<string> {
  return new Set(
    [...source.matchAll(/if \(action === "([a-z_]+)"\)/g)].map((m) => m[1]),
  );
}

Deno.test("every action with a handler is allowed through the entry check", () => {
  const allowed = allowlist();
  const missing = [...handled()].filter((action) => !allowed.has(action));
  assertEquals(missing, []);
});

Deno.test("every allowed action has a handler, apart from the transition fallthrough", () => {
  const dead = [...allowlist()].filter((action) =>
    action !== "transition" && !handled().has(action)
  );
  assertEquals(dead, []);
});
