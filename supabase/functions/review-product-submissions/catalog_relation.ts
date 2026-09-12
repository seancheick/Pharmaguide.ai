/** What an approval decided about a catalog record that shares its barcode.
 *
 * A barcode already in the catalog is not automatically a duplicate. Either
 * the catalog record is this label transcribed wrongly — correct it in place,
 * keeping its id so a stack that points at it keeps the same product — or it
 * is a genuinely different formula sold under the same barcode, which is left
 * alone while this label becomes its own product. The two are not
 * interchangeable, so at most one may be claimed and only on an approval.
 */
export type CatalogRelation = {
  correctionTargetDsldId: string | null;
  editionOfDsldId: string | null;
};

const CATALOG_ID = /^[0-9]{1,30}$/;

function catalogId(value: unknown, name: string): string | null {
  if (value === undefined || value === null) return null;
  if (typeof value !== "string" || !CATALOG_ID.test(value)) {
    throw new Error(`${name} must be a catalog id`);
  }
  return value;
}

export function parseCatalogRelation(
  body: Record<string, unknown>,
  toStatus: string,
): CatalogRelation {
  const correctionTargetDsldId = catalogId(
    body.correction_target_dsld_id,
    "correction target",
  );
  const editionOfDsldId = catalogId(body.edition_of_dsld_id, "edition of");
  if (correctionTargetDsldId !== null && editionOfDsldId !== null) {
    throw new Error("a submission is either a correction or a separate edition");
  }
  if (
    toStatus !== "approved" &&
    (correctionTargetDsldId !== null || editionOfDsldId !== null)
  ) {
    throw new Error("catalog relation is only part of an approval");
  }
  return { correctionTargetDsldId, editionOfDsldId };
}
