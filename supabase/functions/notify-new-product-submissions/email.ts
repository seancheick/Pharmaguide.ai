/// Renders the admin notification email for one ready-to-review submission.
///
/// Only fields that actually exist on `product_submissions` at the moment
/// `upload_state` becomes `ready` are included. Automated extraction
/// (`product_submission_extractions`) is opt-in and off by default, so
/// `extractionConfidence` is nullable and omitted from the email when absent
/// rather than shown as a fabricated number.
export interface SubmissionNotificationData {
  submissionId: string;
  kind: "missing_product" | "label_mismatch";
  normalizedUpc: string | null;
  displayName: string | null;
  submittedAt: string | null;
  isResubmission: boolean;
  photoCount: number;
  extractionConfidence: number | null;
}

export interface RenderedNotificationEmail {
  subject: string;
  text: string;
  html: string;
}

const KIND_LABELS: Record<SubmissionNotificationData["kind"], string> = {
  missing_product: "New product",
  label_mismatch: "Label mismatch report",
};

function formatTimestamp(iso: string | null): string {
  if (!iso) return "Unknown";
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return "Unknown";
  return `${
    date.toLocaleString("en-US", {
      timeZone: "UTC",
      dateStyle: "medium",
      timeStyle: "short",
    })
  } UTC`;
}

function subjectLabel(data: SubmissionNotificationData): string {
  return data.displayName?.trim() || data.normalizedUpc ||
    "Unlabeled submission";
}

function escapeHtml(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

interface FieldLine {
  label: string;
  value: string;
}

function buildFields(data: SubmissionNotificationData): FieldLine[] {
  const fields: FieldLine[] = [
    { label: "Type", value: KIND_LABELS[data.kind] },
    {
      label: "Product name (as entered)",
      value: data.displayName?.trim() || "Not provided",
    },
    { label: "Barcode/UPC", value: data.normalizedUpc ?? "Not provided" },
    { label: "Submitted", value: formatTimestamp(data.submittedAt) },
    { label: "Resubmission", value: data.isResubmission ? "Yes" : "No" },
    { label: "Photos uploaded", value: String(data.photoCount) },
  ];
  if (data.extractionConfidence !== null) {
    const percent = Math.round(data.extractionConfidence * 100);
    fields.push({ label: "Extraction confidence", value: `${percent}%` });
  }
  return fields;
}

export function renderSubmissionNotificationEmail(
  data: SubmissionNotificationData,
): RenderedNotificationEmail {
  const fields = buildFields(data);
  const subject = `[PharmaGuide] New Product Submission — ${
    subjectLabel(data)
  }`;

  const textLines = [
    "New product submission ready for review",
    "",
    "SUBMISSION",
    ...fields.map((field) => `${field.label}: ${field.value}`),
    "",
    "REVIEW",
    "Open the reviewer console:",
    "  bash scripts/submission_review/start.sh",
    "",
    `Submission ID: ${data.submissionId}`,
    "",
    "—",
    "PharmaGuide Product Submission System",
  ];
  const text = textLines.join("\n");

  const htmlRows = fields
    .map((field) =>
      `<tr><td style="padding:2px 12px 2px 0;color:#555;white-space:nowrap;">${
        escapeHtml(field.label)
      }</td><td style="padding:2px 0;">${escapeHtml(field.value)}</td></tr>`
    )
    .join("");
  const html =
    `<div style="font-family:-apple-system,Segoe UI,Helvetica,Arial,sans-serif;font-size:14px;color:#111;">
<p style="font-size:16px;font-weight:600;margin:0 0 12px;">New product submission ready for review</p>
<table style="border-collapse:collapse;margin-bottom:16px;">${htmlRows}</table>
<p style="margin:0 0 8px;">Open the reviewer console:</p>
<pre style="background:#f4f4f4;padding:8px 12px;border-radius:4px;margin:0 0 16px;">bash scripts/submission_review/start.sh</pre>
<p style="color:#777;font-size:12px;margin:0 0 4px;">Submission ID: ${
      escapeHtml(data.submissionId)
    }</p>
<p style="color:#999;font-size:12px;margin:16px 0 0;">— PharmaGuide Product Submission System</p>
</div>`;

  return { subject, text, html };
}
