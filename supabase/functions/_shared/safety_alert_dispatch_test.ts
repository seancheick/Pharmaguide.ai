import {
  constantTimeEquals,
  parseReleaseDispatchRequest,
} from "./safety_alert_dispatch.ts";

Deno.test("dispatch requests require one UUID release identifier", async () => {
  const parsed = await parseReleaseDispatchRequest(
    new Request("https://example.test", {
      method: "POST",
      body: JSON.stringify({ release_id: "f77e0a92-ea48-4e56-9308-7f02e0da557c" }),
    }),
  );
  if (parsed !== "f77e0a92-ea48-4e56-9308-7f02e0da557c") {
    throw new Error(`unexpected release id: ${parsed}`);
  }
});

Deno.test("dispatch request rejects unknown fields and malformed identifiers", async () => {
  for (const body of [
    {},
    { release_id: "not-a-uuid" },
    { release_id: "f77e0a92-ea48-4e56-9308-7f02e0da557c", extra: true },
  ]) {
    let rejected = false;
    try {
      await parseReleaseDispatchRequest(
        new Request("https://example.test", {
          method: "POST",
          body: JSON.stringify(body),
        }),
      );
    } catch {
      rejected = true;
    }
    if (!rejected) throw new Error(`accepted invalid request: ${JSON.stringify(body)}`);
  }
});


Deno.test("dispatch secret comparison is exact and length-aware", async () => {
  if (!await constantTimeEquals("expected", "expected")) {
    throw new Error("equal secrets rejected");
  }
  if (await constantTimeEquals("expected", "unexpected")) {
    throw new Error("different secrets accepted");
  }
  if (await constantTimeEquals("expected", "expected-longer")) {
    throw new Error("different-length secrets accepted");
  }
});
