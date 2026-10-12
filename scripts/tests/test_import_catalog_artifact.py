"""Exercise the real local import gate without modifying bundled assets."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import sqlite3
import subprocess
import tempfile
import unittest

IMPORTER = Path(__file__).resolve().parents[1] / 'import_catalog_artifact.sh'


class ImportInteractionContract(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.dist = Path(self.temp.name)
        db = self.dist / 'pharmaguide_core.db'
        with sqlite3.connect(db) as con:
            con.executescript("CREATE TABLE products_core(export_version TEXT); INSERT INTO products_core VALUES('fixture'); CREATE TABLE export_manifest(key TEXT,value TEXT); INSERT INTO export_manifest VALUES('db_version','fixture'),('schema_version','2.3.0');")
        manifest = dict(db_version='fixture', schema_version='2.3.0', pipeline_version='fixture', scoring_version='fixture', product_count=1, min_app_version='1', generated_at='2026-10-12', checksum_sha256=self.digest(db))
        (self.dist / 'export_manifest.json').write_text(json.dumps(manifest))

    @staticmethod
    def digest(path):
        return hashlib.sha256(path.read_bytes()).hexdigest()

    def interaction(self, major=3, exclusions='["2473","4845"]'):
        db = self.dist / 'interaction_db.sqlite'
        with sqlite3.connect(db) as con:
            con.executescript(f"PRAGMA user_version={major}; CREATE TABLE interactions(retired_at TEXT); INSERT INTO interactions VALUES(NULL); CREATE TABLE research_pairs(rxcui_a TEXT,rxcui_b TEXT,canonical_id_a TEXT,canonical_id_b TEXT); CREATE TABLE interaction_db_metadata(key TEXT,value TEXT);")
            con.execute('CREATE TABLE drug_class_map(class_id TEXT, excluded_drug_rxcuis_json TEXT)')
            con.execute('INSERT INTO drug_class_map VALUES(?,?)', ('class:nsaids', exclusions))
            meta = dict(schema_version=f'{major}.0.0', total_interactions=1, source_suppai_count=0)
            if major >= 2:
                con.executescript('CREATE TABLE profile_warning_rules(rule_id TEXT); INSERT INTO profile_warning_rules VALUES("pregnancy");')
                meta.update(profile_warning_rules_count=1, profile_warning_rules_version='fixture')
            con.executemany('INSERT INTO interaction_db_metadata VALUES(?,?)', [(k,str(v)) for k,v in meta.items()])
        manifest = dict(meta, built_at='2026-10-12', db_version='fixture', source_drafts_count=1, interaction_db_version='fixture', pipeline_version='fixture', min_app_version='1', drug_class_count=1)
        self.manifest = manifest
        self.rehash()

    def rehash(self):
        self.manifest['checksum_sha256'] = self.digest(self.dist / 'interaction_db.sqlite')
        (self.dist / 'interaction_db_manifest.json').write_text(json.dumps(self.manifest))

    def run_gate(self):
        return subprocess.run(['bash', str(IMPORTER), str(self.dist), '--min-products', '1', '--dry-run'], text=True, capture_output=True)

    def test_schemas_one_two_three(self):
        for major in (1,2,3):
            with self.subTest(major=major):
                if (self.dist / 'interaction_db.sqlite').exists():
                    (self.dist / 'interaction_db.sqlite').unlink()
                self.interaction(major)
                result = self.run_gate()
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn('no files written', result.stdout)

    def test_schema_three_rejects_malformed_exclusions(self):
        for value in ('null', '{}', '[2473]', '["not-an-rxcui"]', 'invalid'):
            with self.subTest(value=value):
                db = self.dist / 'interaction_db.sqlite'
                if db.exists(): db.unlink()
                self.interaction(exclusions=value)
                result = self.run_gate()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('class exclusion', result.stderr)

    def test_schema_three_rejects_missing_exclusion_column(self):
        self.interaction()
        with sqlite3.connect(self.dist / 'interaction_db.sqlite') as con:
            con.execute('ALTER TABLE drug_class_map DROP COLUMN excluded_drug_rxcuis_json')
        self.rehash()
        result = self.run_gate()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('class exclusion', result.stderr)

    def test_schema_three_retains_profile_and_class_count_checks(self):
        self.interaction()
        self.manifest['profile_warning_rules_count'] = 2
        self.rehash()
        result = self.run_gate()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('profile warning rule count split-brain', result.stderr)
        self.manifest['profile_warning_rules_count'] = 1
        self.manifest['drug_class_count'] = 2
        self.rehash()
        result = self.run_gate()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('class count', result.stderr)

    def test_schema_three_rejects_wrong_version_and_missing_profile_table(self):
        self.interaction()
        db = self.dist / 'interaction_db.sqlite'
        with sqlite3.connect(db) as con:
            con.execute('PRAGMA user_version=2')
        self.rehash()
        result = self.run_gate()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('PRAGMA user_version mismatch', result.stderr)
        with sqlite3.connect(db) as con:
            con.execute('PRAGMA user_version=3')
            con.execute('DROP TABLE profile_warning_rules')
        self.rehash()
        result = self.run_gate()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('missing profile_warning_rules', result.stderr)

    @unittest.skipUnless(os.environ.get('IMPORT_TEST_INTERACTION_DB'), 'explicit private candidate measurement only')
    def test_actual_private_candidate(self):
        source = Path(os.environ['IMPORT_TEST_INTERACTION_DB'])
        shutil.copyfile(source, self.dist / 'interaction_db.sqlite')
        self.manifest = json.loads(Path(os.environ['IMPORT_TEST_INTERACTION_MANIFEST']).read_text())
        self.rehash()
        result = self.run_gate()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
