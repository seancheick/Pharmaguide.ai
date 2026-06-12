#!/usr/bin/env python3
"""synth_inflate.py — inflate a COPY of the product catalog for load testing.

Copies the bundled catalog to a temp path, then duplicates existing rows
with unique synthetic dsld_id / upc_sku values until products_core reaches
N rows (default 250,000). Rebuilds products_fts and runs ANALYZE so query
plans reflect the inflated stats.

The original database is NEVER touched (copied first, original opened
read-only is not even needed — we only shutil.copy it).

Usage:
    python3 scripts/bench/synth_inflate.py [--source assets/db/pharmaguide_core.db]
                                           [--rows 250000]
                                           [--out /tmp/pharmaguide_core_synth.db]

Then benchmark against the inflated copy:
    scripts/bench/query_bench.sh /tmp/pharmaguide_core_synth.db
"""

import argparse
import os
import shutil
import sqlite3
import sys
import tempfile

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
DEFAULT_SOURCE = os.path.join(REPO_ROOT, "assets", "db", "pharmaguide_core.db")
SYNTH_PREFIX = "synth"


def parse_args():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--source", default=DEFAULT_SOURCE, help="bundled catalog path (read, never modified)")
    p.add_argument("--rows", type=int, default=250_000, help="target products_core row count (default 250000)")
    p.add_argument("--out", default=None, help="output path (default: temp dir)")
    return p.parse_args()


def main():
    args = parse_args()
    source = os.path.abspath(args.source)
    if not os.path.isfile(source):
        sys.exit(f"ERROR: source DB not found: {source}")

    out = args.out or os.path.join(tempfile.mkdtemp(prefix="pg_synth_"), "pharmaguide_core_synth.db")
    out = os.path.abspath(out)
    if os.path.realpath(out) == os.path.realpath(source):
        sys.exit("ERROR: output path must differ from source — originals are never touched")

    print(f"copying {source}\n     -> {out}")
    shutil.copy2(source, out)
    # Strip any sidecar journal that copy2 wouldn't bring; fresh file is clean.

    conn = sqlite3.connect(out)
    try:
        conn.execute("PRAGMA journal_mode = OFF")
        conn.execute("PRAGMA synchronous = OFF")

        (current,) = conn.execute("SELECT COUNT(*) FROM products_core").fetchone()
        target = args.rows
        print(f"current rows: {current:,}  target: {target:,}")
        if current >= target:
            print("already at or above target; rebuilding FTS + ANALYZE only.")
        else:
            cols = [r[1] for r in conn.execute("PRAGMA table_info(products_core)")]
            col_list = ", ".join(f'"{c}"' for c in cols)
            # Build SELECT that overrides dsld_id and upc_sku with unique synthetic values.
            select_cols = []
            for c in cols:
                if c == "dsld_id":
                    select_cols.append(f"'{SYNTH_PREFIX}_' || ?1 || '_' || rowid")
                elif c == "upc_sku":
                    # 12-digit-ish unique synthetic UPC: 9 + zero-padded counter base.
                    select_cols.append("printf('9%011d', ?1 * 1000000 + rowid)")
                else:
                    select_cols.append(f'"{c}"')
            insert_sql = (
                f"INSERT INTO products_core ({col_list}) "
                f"SELECT {', '.join(select_cols)} FROM products_core "
                f"WHERE dsld_id NOT LIKE '{SYNTH_PREFIX}_%' LIMIT ?2"
            )
            batch = 0
            while True:
                (n,) = conn.execute("SELECT COUNT(*) FROM products_core").fetchone()
                remaining = target - n
                if remaining <= 0:
                    break
                batch += 1
                conn.execute(insert_sql, (batch, remaining))
                conn.commit()
                print(f"  batch {batch}: {min(n + remaining, target):,} rows")

        (final,) = conn.execute("SELECT COUNT(*) FROM products_core").fetchone()
        print(f"final rows: {final:,}")

        # Rebuild FTS so synthetic rows are searchable and stats are honest.
        fts = conn.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='products_fts'"
        ).fetchone()
        if fts:
            print("rebuilding products_fts ...")
            conn.execute("INSERT INTO products_fts(products_fts) VALUES('rebuild')")
            conn.commit()
        else:
            print("WARNING: products_fts not found in this snapshot; skipping rebuild")

        print("running ANALYZE ...")
        conn.execute("ANALYZE")
        conn.commit()
    finally:
        conn.close()

    print(f"\ndone. inflated copy: {out}")
    print(f"benchmark it with:\n  scripts/bench/query_bench.sh {out}")


if __name__ == "__main__":
    main()
