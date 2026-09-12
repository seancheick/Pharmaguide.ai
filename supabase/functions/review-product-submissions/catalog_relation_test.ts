import { assertEquals, assertThrows } from "jsr:@std/assert@1.0.14";

import { parseCatalogRelation } from "./catalog_relation.ts";

Deno.test("an approval may correct a catalog record or stand beside it", () => {
  assertEquals(
    parseCatalogRelation({ correction_target_dsld_id: "178392" }, "approved"),
    { correctionTargetDsldId: "178392", editionOfDsldId: null },
  );
  assertEquals(
    parseCatalogRelation({ edition_of_dsld_id: "178392" }, "approved"),
    { correctionTargetDsldId: null, editionOfDsldId: "178392" },
  );
  assertEquals(parseCatalogRelation({}, "approved"), {
    correctionTargetDsldId: null,
    editionOfDsldId: null,
  });
});

Deno.test("it is never both, because they mean opposite things", () => {
  assertThrows(() =>
    parseCatalogRelation(
      { correction_target_dsld_id: "1", edition_of_dsld_id: "2" },
      "approved",
    )
  );
});

Deno.test("a rejection or a duplicate carries no catalog relation", () => {
  for (const status of ["rejected", "duplicate", "under_review"]) {
    assertThrows(() =>
      parseCatalogRelation({ edition_of_dsld_id: "178392" }, status)
    );
  }
});

Deno.test("only a catalog id, never a submission id or free text", () => {
  for (
    const value of [
      "PG_SUB_018F",
      "17-8392",
      "",
      " 178392",
      178392,
      "1".repeat(31),
    ]
  ) {
    assertThrows(() =>
      parseCatalogRelation({ edition_of_dsld_id: value }, "approved")
    );
  }
});
