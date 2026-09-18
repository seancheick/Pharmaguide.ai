import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1";

import {
  renderSubmissionNotificationEmail,
  type SubmissionNotificationData,
} from "./email.ts";

const BASE: SubmissionNotificationData = {
  submissionId: "7dd4c1a0-1111-4a2b-9c3d-000000000001",
  kind: "missing_product",
  normalizedUpc: "850025250001",
  displayName: "Seed DS-01 Daily Synbiotic",
  submittedAt: "2026-09-18T15:42:00Z",
  isResubmission: false,
  photoCount: 4,
  extractionConfidence: null,
};

Deno.test("subject uses the submitter's product name", () => {
  const email = renderSubmissionNotificationEmail(BASE);
  assertEquals(
    email.subject,
    "[PharmaGuide] New Product Submission — Seed DS-01 Daily Synbiotic",
  );
});

Deno.test("falls back to the UPC when no display name was entered", () => {
  const email = renderSubmissionNotificationEmail({
    ...BASE,
    displayName: null,
  });
  assertStringIncludes(email.subject, "850025250001");
  assertStringIncludes(email.text, "Product name (as entered): Not provided");
});

Deno.test("falls back to 'Unlabeled submission' when neither is known", () => {
  const email = renderSubmissionNotificationEmail({
    ...BASE,
    displayName: null,
    normalizedUpc: null,
  });
  assertStringIncludes(email.subject, "Unlabeled submission");
  assertStringIncludes(email.text, "Barcode/UPC: Not provided");
});

Deno.test("omits extraction confidence when no extraction ran", () => {
  const email = renderSubmissionNotificationEmail(BASE);
  assert(!email.text.includes("Extraction confidence"));
  assert(!email.html.includes("Extraction confidence"));
});

Deno.test("includes extraction confidence as a rounded percent when present", () => {
  const email = renderSubmissionNotificationEmail({
    ...BASE,
    extractionConfidence: 0.914,
  });
  assertStringIncludes(email.text, "Extraction confidence: 91%");
});

Deno.test("labels a label-mismatch report distinctly from a new product", () => {
  const email = renderSubmissionNotificationEmail({
    ...BASE,
    kind: "label_mismatch",
  });
  assertStringIncludes(email.text, "Type: Label mismatch report");
});

Deno.test("flags a resubmission", () => {
  const email = renderSubmissionNotificationEmail({
    ...BASE,
    isResubmission: true,
  });
  assertStringIncludes(email.text, "Resubmission: Yes");
});

Deno.test("shows 'Unknown' for a missing or unparseable timestamp", () => {
  assertStringIncludes(
    renderSubmissionNotificationEmail({ ...BASE, submittedAt: null }).text,
    "Submitted: Unknown",
  );
  assertStringIncludes(
    renderSubmissionNotificationEmail({ ...BASE, submittedAt: "not-a-date" })
      .text,
    "Submitted: Unknown",
  );
});

Deno.test("HTML-escapes a submitter-typed display name", () => {
  const email = renderSubmissionNotificationEmail({
    ...BASE,
    displayName: '<img src=x onerror=alert(1)> & "quoted"',
  });
  assert(!email.html.includes("<img src=x"));
  assertStringIncludes(email.html, "&lt;img src=x onerror=alert(1)&gt;");
  assertStringIncludes(email.html, "&amp;");
  assertStringIncludes(email.html, "&quot;quoted&quot;");
  // The plaintext body is never HTML-rendered, so it keeps the raw text.
  assertStringIncludes(email.text, '<img src=x onerror=alert(1)> & "quoted"');
});

Deno.test("HTML-escapes the submission id and keeps it in the plaintext body", () => {
  const weirdId = "not-a-real-uuid-<script>";
  const email = renderSubmissionNotificationEmail({
    ...BASE,
    submissionId: weirdId,
  });
  assert(!email.html.includes("<script>"));
  assertStringIncludes(email.text, `Submission ID: ${weirdId}`);
});
