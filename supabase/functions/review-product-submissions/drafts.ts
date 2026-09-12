import type { SupabaseClient } from "npm:@supabase/supabase-js@2.110.7";

type JsonObject = Record<string, unknown>;

/** Drafts recorded against the evidence the reviewer is actually looking at.
 *
 * Filtered to the current revision on purpose: a draft read from photos that
 * have since been replaced is not a reading of what is on screen, and showing
 * it beside the new evidence would invite approving the wrong thing.
 *
 * Read through the reviewer-gated function rather than the table. Extractions
 * are revoked from every API role, service_role included, so a direct select
 * fails on permission — and that failure lands on the console's refresh of the
 * open submission, which keeps showing the status the decision already changed.
 * The caller must pass the reviewer's own client: the function authorizes the
 * signed-in reviewer, not the service key.
 */
export async function loadSubmissionDrafts(
  reviewerClient: SupabaseClient,
  submissionId: string,
  evidenceRevision: number,
): Promise<JsonObject[]> {
  const { data, error } = await reviewerClient.rpc(
    "get_product_submission_extractions",
    {
      p_submission_id: submissionId,
      p_evidence_revision: evidenceRevision,
    },
  );
  if (error) throw error;
  return (data ?? []) as unknown as JsonObject[];
}
