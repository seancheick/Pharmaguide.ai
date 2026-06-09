#!/usr/bin/env python3
"""Build small, real-schema fixture catalogs for the v3/v4 dual-reader tests.

These fixtures let the release-gate test prove the migrated CoreDatabase opens
BOTH the legacy v3 bundle (92 cols, has score_quality_80) and a v4 build
(102 cols, has quality_score_v4_100, dropped /80) without "no such column".

Re-run after a schema change:
    python3 test/fixtures/db/build_dual_schema_fixtures.py

Sources (must exist locally):
  v3: assets/db/pharmaguide_core.db                (the shipped legacy bundle)
  v4: /tmp/pg_v4_both/pharmaguide_core.db          (a real full-corpus v4 build)

Outputs (committed; NOT under assets/ so not Git-LFS tracked):
  test/fixtures/db/core_v3.fixture.db
  test/fixtures/db/core_v4.fixture.db
  test/fixtures/db/blobs/175321.v4.json           (Elite, has quality_pillars_v4)
  test/fixtures/db/blobs/204468.v4.json           (suppressed BLOCKED)
  test/fixtures/db/blobs/175321.v3style.json      (pillars stripped -> v3 fallback)
"""
import json
import os
import shutil
import sqlite3
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
V3_SRC = os.path.join(REPO, "assets/db/pharmaguide_core.db")
V4_SRC = "/tmp/pg_v4_both/pharmaguide_core.db"
V4_BLOBS = "/tmp/pg_v4_both/detail_blobs"
OUT = HERE
BLOBS_OUT = os.path.join(OUT, "blobs")

# Representative ids. v4 ids are verified to exist in the v4 source.
V4_IDS = ["175321", "179791", "78355", "204468"]  # Elite, Elite, Poor, suppressed


def _create_sql(src, name):
    row = src.execute(
        "SELECT sql FROM sqlite_master WHERE name = ? AND sql IS NOT NULL", (name,)
    ).fetchone()
    return row[0] if row else None


def _copy_table_full(src, dst, name):
    cols = [r[1] for r in src.execute(f"PRAGMA table_info({name})")]
    if not cols:
        return
    rows = src.execute(f"SELECT * FROM {name}").fetchall()
    ph = ",".join("?" * len(cols))
    dst.executemany(f"INSERT INTO {name} VALUES ({ph})", rows)


def _copy_selected_products(src, dst, ids):
    cols = [r[1] for r in src.execute("PRAGMA table_info(products_core)")]
    ph_in = ",".join("?" * len(ids))
    rows = src.execute(
        f"SELECT * FROM products_core WHERE dsld_id IN ({ph_in})", ids
    ).fetchall()
    if not rows:
        raise SystemExit(f"FATAL: none of {ids} found in {src}")
    ins_ph = ",".join("?" * len(cols))
    dst.executemany(f"INSERT INTO products_core VALUES ({ins_ph})", rows)
    return len(rows)


def build_fixture(src_path, out_path, ids):
    if not os.path.exists(src_path):
        raise SystemExit(f"FATAL: source missing: {src_path}")
    if os.path.exists(out_path):
        os.remove(out_path)
    src = sqlite3.connect(f"file:{src_path}?mode=ro", uri=True)
    dst = sqlite3.connect(out_path)
    try:
        # products_core schema + selected rows
        core_sql = _create_sql(src, "products_core")
        dst.execute(core_sql)
        n = _copy_selected_products(src, dst, ids)

        # small reference tables copied whole if present
        for tbl in ("export_manifest", "reference_data"):
            sql = _create_sql(src, tbl)
            if sql:
                dst.execute(sql)
                _copy_table_full(src, dst, tbl)

        # any indexes on products_core (e.g. idx_core_score)
        for (idx_sql,) in src.execute(
            "SELECT sql FROM sqlite_master WHERE type='index' "
            "AND tbl_name='products_core' AND sql IS NOT NULL"
        ):
            try:
                dst.execute(idx_sql)
            except sqlite3.OperationalError:
                pass

        # FTS over products_core — recreate + rebuild so search() works
        fts_sql = _create_sql(src, "products_fts")
        if fts_sql:
            dst.execute(fts_sql)
            try:
                dst.execute("INSERT INTO products_fts(products_fts) VALUES('rebuild')")
            except sqlite3.OperationalError as e:
                print(f"  (FTS rebuild skipped: {e}; search falls back to LIKE)")

        dst.commit()
        dst.execute("VACUUM")
        dst.commit()
    finally:
        src.close()
        dst.close()
    size = os.path.getsize(out_path)
    print(f"  wrote {out_path} ({n} products, {size} bytes)")
    return out_path


def pick_v3_ids():
    src = sqlite3.connect(f"file:{V3_SRC}?mode=ro", uri=True)
    try:
        rows = src.execute(
            "SELECT dsld_id FROM products_core "
            "WHERE score_quality_80 IS NOT NULL "
            "ORDER BY score_quality_80 DESC LIMIT 4"
        ).fetchall()
        return [r[0] for r in rows]
    finally:
        src.close()


def copy_blobs():
    os.makedirs(BLOBS_OUT, exist_ok=True)
    for bid, label in (("175321", "v4"), ("204468", "v4")):
        src = os.path.join(V4_BLOBS, f"{bid}.json")
        if os.path.exists(src):
            shutil.copy(src, os.path.join(BLOBS_OUT, f"{bid}.{label}.json"))
            print(f"  blob {bid}.{label}.json")
    # v3-style blob: a real v4 blob with quality_pillars_v4 + v4 keys stripped
    src = os.path.join(V4_BLOBS, "175321.json")
    if os.path.exists(src):
        b = json.load(open(src))
        for k in (
            "quality_pillars_v4",
            "v4_score_explanation",
            "clean_label_flags_v4",
            "v4_safety_gate",
            "v4_completeness_gate",
            "v4_score_provenance",
            "raw_score_v4_100",
        ):
            b.pop(k, None)
        json.dump(b, open(os.path.join(BLOBS_OUT, "175321.v3style.json"), "w"))
        print("  blob 175321.v3style.json (pillars stripped)")


def main():
    print("Building v4 fixture...")
    build_fixture(V4_SRC, os.path.join(OUT, "core_v4.fixture.db"), V4_IDS)
    print("Building v3 fixture...")
    v3_ids = pick_v3_ids()
    print(f"  v3 ids: {v3_ids}")
    build_fixture(V3_SRC, os.path.join(OUT, "core_v3.fixture.db"), v3_ids)
    print("Copying blobs...")
    copy_blobs()
    print("Done.")


if __name__ == "__main__":
    main()
