#!/usr/bin/env python3
"""Assemble the shared project's migration stream from immutable Git sources.

Production timestamp aliases are preserved. Replay prerequisites reconstruct
schema whose historical stamps were already reconciled out of the live ledger;
they are never scheduled by `db push` against the existing project.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess


APP_ALIASES = {
    "20261023193612": "20261023223116",
    "20261023210000": "20261023223135",
    "20261023232641": "20261023233300",
}
PIPELINE_ALIASES = {
    "20261013213803": "20261014151044",
    "20261023190000": "20261023191950",
}
REPLAY_PREREQUISITES = (
    "scripts/sql/supabase_schema.sql",
    "scripts/sql/migrations/20260710210008_pipeline_distribution_contract.sql",
    "scripts/sql/migrations/20260711022522_catalog_release_promotion.sql",
)
MIGRATION_NAME = re.compile(r"^(\d{14})_(.+)\.sql$")


def git(repo: Path, *args: str) -> bytes:
    return subprocess.check_output(["git", "-C", str(repo), *args])


def assemble(app: Path, pipeline: Path, app_ref: str, pipeline_ref: str,
             output: Path, through: str | None = None) -> dict:
    commits = {
        "app": git(app, "rev-parse", "--verify", f"{app_ref}^{{commit}}").decode().strip(),
        "pipeline": git(pipeline, "rev-parse", "--verify", f"{pipeline_ref}^{{commit}}").decode().strip(),
    }
    if through is not None and not re.fullmatch(r"\d{14}", through):
        raise ValueError("through must be a 14-digit migration version")
    entries = []
    objects: dict[str, bytes] = {}

    def source(repository: str, path: str, destination: str, **extra) -> dict:
        repo = app if repository == "app" else pipeline
        raw = git(repo, "show", f"{commits[repository]}:{path}")
        objects[destination] = raw
        return {
            "repository": repository, "commit": commits[repository],
            "source": path, "destination": destination,
            "sha256": hashlib.sha256(raw).hexdigest(), **extra,
        }

    seen = set()
    for repository, repo, folder, aliases in (
        ("app", app, "supabase/migrations", APP_ALIASES),
        ("pipeline", pipeline, "scripts/sql/migrations", PIPELINE_ALIASES),
    ):
        files = git(repo, "ls-tree", "--name-only", commits[repository], f"{folder}/").decode().splitlines()
        found_aliases = set()
        for path in files:
            match = MIGRATION_NAME.fullmatch(Path(path).name)
            if not match:
                raise ValueError(f"unrecognized migration source: {path}")
            version, name = match.groups()
            if repository == "pipeline" and version not in aliases:
                if path not in REPLAY_PREREQUISITES:
                    raise ValueError(f"pipeline migration has no deployment classification: {path}")
                continue
            canonical = aliases.get(version, version)
            if version in aliases:
                found_aliases.add(version)
            if through is not None and canonical > through:
                continue
            if canonical in seen:
                raise ValueError(f"duplicate canonical migration: {canonical}")
            seen.add(canonical)
            entries.append(source(repository, path,
                f"supabase/migrations/{canonical}_{name}.sql",
                version=canonical, source_version=version))
        if found_aliases != set(aliases):
            raise ValueError(f"missing expected {repository} migration alias")

    prerequisites = [source("pipeline", path,
        f"replay_prerequisites/{index:02d}_{Path(path).name}")
        for index, path in enumerate(REPLAY_PREREQUISITES)]
    config = source("app", "supabase/config.toml", "supabase/config.toml")
    receipt = {"commits": commits,
               "migrations": sorted(entries, key=lambda item: item["version"]),
               "replay_prerequisites": prerequisites, "config": config}
    # Never overwrite a deployment directory or any operator-owned files.
    output.mkdir(parents=True, exist_ok=False)
    for destination, raw in objects.items():
        target = output / destination
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(raw)
    (output / "migration_sources.json").write_text(
        json.dumps(receipt, indent=2, sort_keys=True) + "\n")
    return receipt


def main() -> None:
    import sys
    if len(sys.argv) == 4 and sys.argv[1] == "--compare-schema":
        def canonical(value):
            if isinstance(value, str):
                # pg_get_functiondef retains source comments and indentation.
                value = re.sub(r"^\s*--.*$", "", value, flags=re.MULTILINE)
                return "\n".join(line.strip() for line in value.splitlines()
                                 if line.strip())
            if isinstance(value, list):
                return [canonical(item) for item in value]
            if isinstance(value, dict):
                return {key: canonical(item) for key, item in value.items()}
            return value
        receipts = []
        for path in sys.argv[2:]:
            rows = json.loads(Path(path).read_text())
            receipts.append({(row["kind"], row["name"]): canonical(row["value"])
                             for row in rows})
        left, right = receipts
        differences = sorted(key for key in left.keys() | right.keys()
                             if left.get(key) != right.get(key))
        if differences:
            raise ValueError(f"schema differences: {differences}")
        print(f"Schema parity: {len(left)} public objects match")
        return
    if len(sys.argv) == 3 and sys.argv[1] == "--verify":
        root = Path(sys.argv[2])
        receipt = json.loads((root / "migration_sources.json").read_text())
        sql_entries = receipt["migrations"] + receipt["replay_prerequisites"]
        entries = sql_entries + [receipt["config"]]
        expected = {entry["destination"] for entry in sql_entries}
        actual = {str(path.relative_to(root)) for folder in ("supabase/migrations", "replay_prerequisites")
                  for path in (root / folder).glob("*.sql")}
        if actual != expected:
            raise ValueError("deployment SQL file census differs from receipt")
        for entry in entries:
            path = Path(entry["destination"])
            if path.is_absolute() or ".." in path.parts:
                raise ValueError("invalid receipt path")
            if hashlib.sha256((root / path).read_bytes()).hexdigest() != entry["sha256"]:
                raise ValueError(f"deployment source hash changed: {path}")
        print(f"Verified {len(sql_entries)} pinned SQL sources and deployment config")
        return
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app-repo", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--pipeline-repo", type=Path, required=True)
    parser.add_argument("--app-ref", required=True)
    parser.add_argument("--pipeline-ref", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--through")
    args = parser.parse_args()
    receipt = assemble(args.app_repo, args.pipeline_repo, args.app_ref,
                       args.pipeline_ref, args.output, args.through)
    print(json.dumps({"output": str(args.output), "commits": receipt["commits"],
                      "migration_count": len(receipt["migrations"])}))


if __name__ == "__main__":
    main()
