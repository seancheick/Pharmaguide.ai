import { createClient } from "npm:@supabase/supabase-js@2";

const PHOTO_BUCKET = "product-submission-photos";
const CLEANUP_LIMIT = 100;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

function secretsMatch(left: string, right: string): boolean {
  const leftBytes = new TextEncoder().encode(left);
  const rightBytes = new TextEncoder().encode(right);
  if (leftBytes.length !== rightBytes.length) return false;
  let difference = 0;
  for (let index = 0; index < leftBytes.length; index++) {
    difference |= leftBytes[index] ^ rightBytes[index];
  }
  return difference === 0;
}

function audit(
  outcome: string,
  completed: number,
  failed: number,
  objects: number,
): void {
  console.info(JSON.stringify({
    event: "product_submission_cleanup",
    outcome,
    completed_submission_count: completed,
    failed_submission_count: failed,
    removed_object_count: objects,
  }));
}

Deno.serve(async (request: Request): Promise<Response> => {
  if (request.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }
  const configuredSecret = Deno.env.get("PRODUCT_SUBMISSION_CLEANUP_SECRET");
  const suppliedSecret = request.headers.get("x-cleanup-secret") ?? "";
  if (
    !configuredSecret || !suppliedSecret ||
    !secretsMatch(configuredSecret, suppliedSecret)
  ) {
    audit("unauthorized", 0, 0, 0);
    return json({ error: "Authentication required" }, 401);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    audit("configuration_error", 0, 0, 0);
    return json({ error: "Cleanup service unavailable" }, 500);
  }
  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: claims, error: claimError } = await admin.rpc(
    "claim_product_submission_cleanup",
    { p_limit: CLEANUP_LIMIT },
  );
  if (claimError || !Array.isArray(claims)) {
    audit("claim_failed", 0, 0, 0);
    return json({ error: "Cleanup service unavailable" }, 500);
  }

  const completedSubmissionIds: string[] = [];
  const failedSubmissionIds: string[] = [];
  let removedObjectCount = 0;
  for (const claim of claims) {
    const submissionId = claim.submission_id;
    const rawObjectPaths: unknown[] = Array.isArray(claim.object_paths)
      ? claim.object_paths
      : [];
    const objectPaths = rawObjectPaths.filter((path): path is string =>
      typeof path === "string" && path.length > 0
    );
    if (typeof submissionId !== "string") continue;
    if (objectPaths.length > 0) {
      const { error: removeError } = await admin.storage
        .from(PHOTO_BUCKET)
        .remove(objectPaths);
      if (removeError) {
        failedSubmissionIds.push(submissionId);
        continue;
      }
      removedObjectCount += objectPaths.length;
    }
    completedSubmissionIds.push(submissionId);
  }

  if (completedSubmissionIds.length > 0) {
    const { data: completed, error: completeError } = await admin.rpc(
      "complete_product_submission_cleanup",
      { p_submission_ids: completedSubmissionIds },
    );
    if (
      completeError || typeof completed !== "number" ||
      completed !== completedSubmissionIds.length
    ) {
      audit(
        "manifest_delete_failed",
        0,
        failedSubmissionIds.length,
        removedObjectCount,
      );
      return json({ error: "Cleanup service unavailable" }, 500);
    }
  }

  const outcome = failedSubmissionIds.length === 0 ? "success" : "partial";
  audit(
    outcome,
    completedSubmissionIds.length,
    failedSubmissionIds.length,
    removedObjectCount,
  );
  return json({
    completed_submission_count: completedSubmissionIds.length,
    failed_submission_count: failedSubmissionIds.length,
    removed_object_count: removedObjectCount,
  });
});
