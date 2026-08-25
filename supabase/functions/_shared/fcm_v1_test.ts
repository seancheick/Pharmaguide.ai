import {
  buildSafetyAlertMessage,
  buildSubmissionUpdateMessage,
  fcmAccessToken,
  sendFcmMessage,
  SUBMISSION_UPDATE_BODY,
  SUBMISSION_UPDATE_TITLE,
} from "./fcm_v1.ts";

Deno.test("missing service account fails closed", async () => {
  let rejected = false;
  try {
    await fcmAccessToken(() => undefined);
  } catch {
    rejected = true;
  }
  if (!rejected) throw new Error("missing credentials accepted");
});

Deno.test("malformed service account fails closed", async () => {
  for (const raw of ["[]", '"text"', "{}", '{"project_id":" "}']) {
    let rejected = false;
    try {
      await fcmAccessToken(() => raw);
    } catch {
      rejected = true;
    }
    if (!rejected) throw new Error(`malformed credentials accepted: ${raw}`);
  }
});

Deno.test("submission update message stays generic", () => {
  const message = buildSubmissionUpdateMessage({
    token: "device-token",
    submissionId: "f77e0a92-ea48-4e56-9308-7f02e0da557c",
  });
  const notification = message.notification as Record<string, unknown>;
  if (notification.title !== SUBMISSION_UPDATE_TITLE) {
    throw new Error("unexpected notification title");
  }
  if (notification.body !== SUBMISSION_UPDATE_BODY) {
    throw new Error("unexpected notification body");
  }
  // The visible copy must be the exported constants verbatim: no status,
  // product, or payload text may reach a lock screen.
  if (
    String(notification.title).includes("f77e0a92") ||
    String(notification.body).includes("f77e0a92")
  ) {
    throw new Error("submission data leaked into visible copy");
  }
  const data = message.data as Record<string, unknown>;
  if (data.type !== "submission_update") {
    throw new Error("missing submission route data");
  }
  if (data.submission_id !== "f77e0a92-ea48-4e56-9308-7f02e0da557c") {
    throw new Error("missing submission id route data");
  }
});

Deno.test("sendFcmMessage classifies UNREGISTERED as invalid token", async () => {
  const access = { token: "t", projectId: "p" };
  const gone = await sendFcmMessage(
    access,
    { token: "x" },
    () =>
      Promise.resolve(
        new Response('{"error":{"status":"NOT_FOUND","details":"UNREGISTERED"}}', {
          status: 404,
        }),
      ),
  );
  if (gone.delivered || !gone.invalidToken) {
    throw new Error("UNREGISTERED not classified as invalid token");
  }
  if (gone.retryable) {
    throw new Error("invalid token must not be retryable");
  }

  const throttled = await sendFcmMessage(
    access,
    { token: "x" },
    () => Promise.resolve(new Response("quota", { status: 429 })),
  );
  if (throttled.delivered || throttled.invalidToken) {
    throw new Error("transient failure misclassified");
  }
  if (!throttled.retryable) {
    throw new Error("429 must stay retryable so the delivery is not lost");
  }

  const outage = await sendFcmMessage(
    access,
    { token: "x" },
    () => Promise.resolve(new Response("upstream", { status: 503 })),
  );
  if (outage.delivered || outage.invalidToken || !outage.retryable) {
    throw new Error("5xx must stay retryable so the delivery is not lost");
  }
  if (!outage.detail.includes("HTTP 503")) {
    throw new Error("failure detail must record the transport status");
  }

  const badRequest = await sendFcmMessage(
    access,
    { token: "x" },
    () => Promise.resolve(new Response("bad payload", { status: 400 })),
  );
  if (badRequest.delivered || badRequest.invalidToken || badRequest.retryable) {
    throw new Error("4xx request errors are not transient");
  }

  const ok = await sendFcmMessage(
    access,
    { token: "x" },
    () => Promise.resolve(new Response("{}", { status: 200 })),
  );
  if (!ok.delivered || ok.invalidToken || ok.retryable || ok.detail !== "") {
    throw new Error("success misclassified");
  }
});

Deno.test("send posts to the project-scoped FCM v1 endpoint", async () => {
  let capturedUrl = "";
  let capturedBody = "";
  await sendFcmMessage(
    { token: "secret-token", projectId: "pharma guide" },
    { token: "device" },
    (input, init) => {
      capturedUrl = String(input);
      capturedBody = String((init as RequestInit | undefined)?.body ?? "");
      return Promise.resolve(new Response("{}", { status: 200 }));
    },
  );
  if (
    capturedUrl !==
      "https://fcm.googleapis.com/v1/projects/pharma%20guide/messages:send"
  ) {
    throw new Error(`unexpected endpoint: ${capturedUrl}`);
  }
  const parsed = JSON.parse(capturedBody) as { message?: { token?: string } };
  if (parsed.message?.token !== "device") {
    throw new Error("message envelope missing");
  }
});

Deno.test("safety alert message keeps its generic copy and route data", () => {
  const message = buildSafetyAlertMessage({
    token: "device-token",
    alertId: "alert-1",
    revision: 3,
  });
  const notification = message.notification as Record<string, unknown>;
  if (notification.title !== "PharmaGuide safety update") {
    throw new Error("unexpected notification title");
  }
  if (notification.body !== "A product in your stack has a safety update.") {
    throw new Error("unexpected notification body");
  }
  const data = message.data as Record<string, unknown>;
  if (
    data.type !== "safety_alert" || data.alert_id !== "alert-1" ||
    data.revision !== "3"
  ) {
    throw new Error("missing alert route data");
  }
});
