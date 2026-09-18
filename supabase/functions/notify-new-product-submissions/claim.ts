/// Parses and validates rows returned by
/// `claim_admin_submission_notifications`. OCR/extraction confidence is only
/// present once the opt-in extraction worker has run for a submission.
export interface ClaimedNotification {
  notificationId: number;
  submissionId: string;
  kind: "missing_product" | "label_mismatch";
  normalizedUpc: string | null;
  displayName: string | null;
  submittedAt: string | null;
  isResubmission: boolean;
  photoCount: number;
  extractionConfidence: number | null;
}

function isSubmissionKind(
  value: unknown,
): value is ClaimedNotification["kind"] {
  return value === "missing_product" || value === "label_mismatch";
}

export function parseClaimedNotifications(
  rows: unknown,
): ClaimedNotification[] {
  if (!Array.isArray(rows)) {
    throw new Error("expected an array of claimed notification rows");
  }
  return rows.map((row, index) => {
    if (!row || typeof row !== "object") {
      throw new Error(`row ${index} is not an object`);
    }
    const record = row as Record<string, unknown>;
    if (typeof record.notification_id !== "number") {
      throw new Error(`row ${index} has no numeric notification_id`);
    }
    if (typeof record.submission_id !== "string" || !record.submission_id) {
      throw new Error(`row ${index} has no submission_id`);
    }
    if (!isSubmissionKind(record.kind)) {
      throw new Error(`row ${index} has an unrecognized kind`);
    }
    if (typeof record.photo_count !== "number") {
      throw new Error(`row ${index} has no numeric photo_count`);
    }
    return {
      notificationId: record.notification_id,
      submissionId: record.submission_id,
      kind: record.kind,
      normalizedUpc: typeof record.normalized_upc === "string"
        ? record.normalized_upc
        : null,
      displayName: typeof record.display_name === "string"
        ? record.display_name
        : null,
      submittedAt: typeof record.submitted_at === "string"
        ? record.submitted_at
        : null,
      isResubmission: record.is_resubmission === true,
      photoCount: record.photo_count,
      extractionConfidence: typeof record.extraction_confidence === "number"
        ? record.extraction_confidence
        : null,
    };
  });
}
