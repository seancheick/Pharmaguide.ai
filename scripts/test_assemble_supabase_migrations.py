"""Behavioral tests for immutable cross-repository migration assembly."""
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location(
    "migration_assembly", Path(__file__).with_name("assemble_supabase_migrations.py"))
assembly = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(assembly)


class MigrationAssemblyTest(unittest.TestCase):
    def test_pinned_sources_aliases_receipt_and_tamper_refusal(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            repos = {}
            for name in ("app", "pipeline"):
                repo = root / name
                repo.mkdir()
                subprocess.run(["git", "init", "-q", str(repo)], check=True)
                repos[name] = repo
            def write(repo, path, contents):
                target = repo / path
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text(contents)
            write(repos["app"], "supabase/config.toml", 'project_id = "fixture"\n')
            for version in assembly.APP_ALIASES:
                write(repos["app"], f"supabase/migrations/{version}_fixture.sql", f"SELECT '{version}';\n")
            for version in assembly.PIPELINE_ALIASES:
                write(repos["pipeline"], f"scripts/sql/migrations/{version}_fixture.sql", f"SELECT '{version}';\n")
            for path in assembly.REPLAY_PREREQUISITES:
                write(repos["pipeline"], path, f"-- prerequisite: {path}\n")
            for repo in repos.values():
                subprocess.run(["git", "-C", str(repo), "add", "."], check=True)
                subprocess.run(["git", "-C", str(repo), "-c", "user.name=Fixture",
                                "-c", "user.email=fixture@example.invalid", "commit", "-qm", "fixture"], check=True)
            # A dirty source must never enter a deployment pinned to a commit.
            first = next(iter(assembly.APP_ALIASES))
            write(repos["app"], f"supabase/migrations/{first}_fixture.sql", "SELECT 'dirty';")
            output = root / "deployment"
            receipt = assembly.assemble(repos["app"], repos["pipeline"], "HEAD", "HEAD", output)
            self.assertEqual(len(receipt["migrations"]), 5)
            self.assertEqual(len(receipt["replay_prerequisites"]), 3)
            for entry in receipt["migrations"]:
                self.assertNotIn("dirty", (output / entry["destination"]).read_text())
                self.assertNotEqual(entry["version"], entry["source_version"])
            script = Path(assembly.__file__)
            subprocess.run(["python3", str(script), "--verify", str(output)], check=True)
            config = output / "supabase/config.toml"
            original_config = config.read_bytes()
            config.write_text('project_id = "tampered"\n')
            refused_config = subprocess.run(
                ["python3", str(script), "--verify", str(output)], capture_output=True)
            self.assertNotEqual(refused_config.returncode, 0)
            self.assertIn(b"source hash changed", refused_config.stderr)
            config.write_bytes(original_config)
            target = output / receipt["migrations"][0]["destination"]
            target.write_text("SELECT 'tampered';")
            refused = subprocess.run(["python3", str(script), "--verify", str(output)], capture_output=True)
            self.assertNotEqual(refused.returncode, 0)
            self.assertIn(b"source hash changed", refused.stderr)
            with self.assertRaises(FileExistsError):
                assembly.assemble(repos["app"], repos["pipeline"], "HEAD", "HEAD", output)


if __name__ == "__main__":
    unittest.main()
