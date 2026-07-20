import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";

const REPORT_FIELDS =
  "id,dsld_id,upc,source_record_id,catalog_source_version,formula_fingerprint,mismatch_categories,status,submitted_at,reviewed_at";
const PHOTO_FIELDS =
  "report_id,photo_slot,object_path,content_type,byte_size,created_at";
const PHOTO_BUCKET = "label-mismatch-report-photos";
const SIGNED_URL_TTL_SECONDS = 300;
const PENDING_RETENTION_MILLISECONDS = 24 * 60 * 60 * 1000;
const PENDING_CLEANUP_LIMIT = 100;
const allowedBodyKeys = new Set(["report_id", "status", "cursor", "limit"]);
const allowedCursorKeys = new Set(["submitted_at", "id"]);
type ReviewStatus = "submitted" | "under_review" | "resolved" | "dismissed";
const allowedStatuses = new Set<ReviewStatus>([
  "submitted",
  "under_review",
  "resolved",
  "dismissed",
]);
const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const submittedAtPattern =
  /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})$/;

type ReviewCursor = { submitted_at: string; id: string };
type ReviewRequest = {
  report_id?: string;
  status?: ReviewStatus;
  cursor?: ReviewCursor;
  limit: number;
};
type ReportRow = Record<string, unknown> & { id: string; submitted_at: string };
type PhotoRow = {
  report_id: string;
  photo_slot: string;
  object_path: string;
  content_type: string;
  byte_size: number;
  created_at: string;
};
type MismatchReportRow = ReportRow & {
  dsld_id: string;
  upc: string | null;
  source_record_id: string | null;
  catalog_source_version: string | null;
  formula_fingerprint: string | null;
  mismatch_categories: string[];
  upload_state: "pending" | "ready" | "cleaning";
  status: "submitted" | "under_review" | "resolved" | "dismissed";
  reviewed_at: string | null;
};
type ReviewerDatabase = {
  public: {
    Tables: {
      label_mismatch_reports: {
        Row: MismatchReportRow;
        Insert: Partial<MismatchReportRow>;
        Update: Partial<MismatchReportRow>;
        Relationships: [];
      };
      label_mismatch_report_photos: {
        Row: PhotoRow;
        Insert: Partial<PhotoRow>;
        Update: Partial<PhotoRow>;
        Relationships: [];
      };
    };
    Views: Record<string, never>;
    Functions: Record<string, never>;
    Enums: Record<string, never>;
    CompositeTypes: Record<string, never>;
  };
};
type AdminClient = SupabaseClient<ReviewerDatabase>;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

function auditReviewAccess(
  reviewerId: string,
  outcome: string,
  reportCount = 0,
  signedPhotoCount = 0,
): void {
  console.info(
    JSON.stringify({
      event: "label_mismatch_review_access",
      reviewer_id: reviewerId,
      outcome,
      report_count: reportCount,
      signed_photo_count: signedPhotoCount,
    }),
  );
}

function auditPendingCleanup(
  outcome: "success" | "failed",
  reportCount = 0,
  objectCount = 0,
): void {
  console.info(
    JSON.stringify({
      event: "label_mismatch_pending_cleanup",
      outcome,
      report_count: reportCount,
      object_count: objectCount,
    }),
  );
}

async function cleanupExpiredPendingReports(admin: AdminClient): Promise<void> {
  const cutoff = new Date(
    Date.now() - PENDING_RETENTION_MILLISECONDS,
  ).toISOString();
  const { data: candidateData, error: candidateError } = await admin
    .from("label_mismatch_reports")
    .select("id,upload_state")
    .in("upload_state", ["pending", "cleaning"])
    .lt("submitted_at", cutoff)
    .order("submitted_at", { ascending: true })
    .limit(PENDING_CLEANUP_LIMIT);
  if (candidateError) throw candidateError;

  const candidates = candidateData ?? [];
  const pendingIds = candidates
    .filter((row) => row.upload_state === "pending")
    .map((row) => row.id as string);
  const cleaningIds = candidates
    .filter((row) => row.upload_state === "cleaning")
    .map((row) => row.id as string);
  let claimedIds: string[] = [];
  if (pendingIds.length > 0) {
    const { data: claimedData, error: claimError } = await admin
      .from("label_mismatch_reports")
      .update({ upload_state: "cleaning" })
      .in("id", pendingIds)
      .eq("upload_state", "pending")
      .select("id");
    if (claimError) throw claimError;
    claimedIds = (claimedData ?? []).map((row) => row.id as string);
  }

  const reportIds = [...cleaningIds, ...claimedIds];
  if (reportIds.length === 0) {
    auditPendingCleanup("success");
    return;
  }

  const { data: photoData, error: photoError } = await admin
    .from("label_mismatch_report_photos")
    .select("object_path")
    .in("report_id", reportIds);
  if (photoError) throw photoError;
  const objectPaths = (photoData ?? []).map(
    (row) => row.object_path as string,
  );
  if (objectPaths.length > 0) {
    const { error: removeError } = await admin.storage
      .from(PHOTO_BUCKET)
      .remove(objectPaths);
    if (removeError) throw removeError;
  }

  const { error: deleteError } = await admin
    .from("label_mismatch_reports")
    .delete()
    .in("id", reportIds)
    .eq("upload_state", "cleaning");
  if (deleteError) throw deleteError;
  auditPendingCleanup("success", reportIds.length, objectPaths.length);
}

Deno.serve(async (request: Request): Promise<Response> => {
  if (request.method !== "POST") {
    auditReviewAccess("unverified", "method_not_allowed");
    return json({ error: "Method not allowed" }, 405);
  }

  const authorization = request.headers.get("authorization");
  if (!authorization?.startsWith("Bearer ")) {
    auditReviewAccess("unverified", "missing_authentication");
    return json({ error: "Authentication required" }, 401);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!supabaseUrl || !anonKey) {
    auditReviewAccess("unverified", "server_configuration_error");
    return json({ error: "Reviewer service unavailable" }, 500);
  }

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: authData, error: authError } = await userClient.auth.getUser();
  if (authError || !authData.user) {
    auditReviewAccess("unverified", "invalid_authentication");
    return json({ error: "Authentication required" }, 401);
  }

  const reviewerId = authData.user.id;
  const reviewerIds = new Set(
    (Deno.env.get("LABEL_MISMATCH_REVIEWER_IDS") ?? "")
      .split(",")
      .map((value) => value.trim())
      .filter(Boolean),
  );
  if (!reviewerIds.has(reviewerId)) {
    auditReviewAccess(reviewerId, "forbidden");
    return json({ error: "Reviewer access required" }, 403);
  }

  let body: ReviewRequest;
  try {
    const parsed = await request.json();
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      throw new Error("invalid body");
    }
    const bodyKeys = Object.keys(parsed);
    if (!bodyKeys.every((key) => allowedBodyKeys.has(key))) {
      throw new Error("unknown field");
    }
    const reportId = parsed.report_id;
    if (
      reportId !== undefined &&
      (typeof reportId !== "string" || !uuidPattern.test(reportId))
    ) {
      throw new Error("invalid report id");
    }
    const status = parsed.status;
    if (
      status !== undefined &&
      (typeof status !== "string" ||
        !allowedStatuses.has(status as ReviewStatus))
    ) {
      throw new Error("invalid status");
    }
    const limit = parsed.limit ?? 50;
    if (!Number.isInteger(limit) || !(limit >= 1 && limit <= 100)) {
      throw new Error("invalid limit");
    }
    let cursor: ReviewCursor | undefined;
    if (parsed.cursor !== undefined) {
      if (
        !parsed.cursor || typeof parsed.cursor !== "object" ||
        Array.isArray(parsed.cursor) ||
        !Object.keys(parsed.cursor).every((key) =>
          allowedCursorKeys.has(key)
        ) ||
        Object.keys(parsed.cursor).length !== allowedCursorKeys.size
      ) {
        throw new Error("invalid cursor");
      }
      const submittedAt = parsed.cursor.submitted_at;
      const cursorId = parsed.cursor.id;
      const parsedDate = typeof submittedAt === "string"
        ? new Date(submittedAt)
        : new Date(Number.NaN);
      if (
        typeof submittedAt !== "string" ||
        !submittedAtPattern.test(submittedAt) ||
        Number.isNaN(parsedDate.getTime()) ||
        typeof cursorId !== "string" || !uuidPattern.test(cursorId)
      ) {
        throw new Error("invalid cursor");
      }
      cursor = {
        // Preserve PostgreSQL's full microsecond precision. JavaScript Date
        // truncates to milliseconds and would make keyset pagination skip rows.
        submitted_at: submittedAt,
        id: cursorId.toLowerCase(),
      };
    }
    body = {
      report_id: reportId,
      status: status as ReviewStatus | undefined,
      cursor,
      limit,
    };
  } catch {
    auditReviewAccess(reviewerId, "invalid_request");
    return json({ error: "Invalid request" }, 400);
  }

  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!serviceRoleKey) {
    auditReviewAccess(reviewerId, "server_configuration_error");
    return json({ error: "Reviewer service unavailable" }, 500);
  }
  const admin = createClient<ReviewerDatabase>(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  try {
    await cleanupExpiredPendingReports(admin);
  } catch {
    // Maintenance must never make the ready-only review queue unavailable.
    auditPendingCleanup("failed");
  }

  try {
    let reportQuery = admin
      .from("label_mismatch_reports")
      .select(REPORT_FIELDS)
      .eq("upload_state", "ready")
      .order("submitted_at", { ascending: false })
      .order("id", { ascending: false })
      .limit(body.limit);
    if (body.report_id) reportQuery = reportQuery.eq("id", body.report_id);
    if (body.status) reportQuery = reportQuery.eq("status", body.status);
    if (body.cursor) {
      reportQuery = reportQuery.or(
        `submitted_at.lt.${body.cursor.submitted_at},and(submitted_at.eq.${body.cursor.submitted_at},id.lt.${body.cursor.id})`,
      );
    }
    const { data: reportsData, error: reportsError } = await reportQuery;
    if (reportsError) throw reportsError;
    const reports = (reportsData ?? []) as ReportRow[];

    const reportIds = reports.map((report) => report.id);
    const photosByReport = new Map<string, Array<Record<string, unknown>>>();
    let signedPhotoCount = 0;
    if (reportIds.length > 0) {
      const { data: photosData, error: photosError } = await admin
        .from("label_mismatch_report_photos")
        .select(PHOTO_FIELDS)
        .in("report_id", reportIds)
        .order("photo_slot", { ascending: true });
      if (photosError) throw photosError;

      const photos = (photosData ?? []) as PhotoRow[];
      if (photos.length > 0) {
        const photoPaths = photos.map((photo) => photo.object_path);
        const { data: signedData, error: signedError } = await admin.storage
          .from(PHOTO_BUCKET)
          .createSignedUrls(photoPaths, SIGNED_URL_TTL_SECONDS);
        if (signedError || !signedData) throw signedError;
        const signedUrlsByPath = new Map(
          signedData.map((item) => [item.path, item.signedUrl]),
        );

        for (const photo of photos) {
          const signedUrl = signedUrlsByPath.get(photo.object_path);
          if (!signedUrl) throw new Error("missing signed URL");
          const responsePhoto = {
            photo_slot: photo.photo_slot,
            content_type: photo.content_type,
            byte_size: photo.byte_size,
            created_at: photo.created_at,
            signed_url: signedUrl,
            expires_in_seconds: SIGNED_URL_TTL_SECONDS,
          };
          photosByReport.set(photo.report_id, [
            ...(photosByReport.get(photo.report_id) ?? []),
            responsePhoto,
          ]);
          signedPhotoCount++;
        }
      }
    }

    const responseReports = reports.map((report) => ({
      ...report,
      photos: photosByReport.get(report.id) ?? [],
    }));
    auditReviewAccess(
      reviewerId,
      "success",
      responseReports.length,
      signedPhotoCount,
    );
    const lastReport = reports.at(-1);
    const nextCursor =
      !body.report_id && reports.length === body.limit && lastReport
        ? { submitted_at: lastReport.submitted_at, id: lastReport.id }
        : null;
    return json({ reports: responseReports, next_cursor: nextCursor });
  } catch {
    auditReviewAccess(reviewerId, "backend_error");
    return json({ error: "Reviewer service unavailable" }, 500);
  }
});
