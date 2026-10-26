"""Exercise the real local import gate without modifying bundled assets."""
from contextlib import closing
import hashlib
import json
import os
import re
from pathlib import Path
import shutil
import sqlite3
import subprocess
import tempfile
import time
import unittest

IMPORTER = Path(__file__).resolve().parents[1] / 'import_catalog_artifact.sh'


class ImportInteractionContract(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.dist = Path(self.temp.name)
        db = self.dist / 'pharmaguide_core.db'
        with closing(sqlite3.connect(db)) as con, con:
            con.executescript("CREATE TABLE products_core(export_version TEXT); INSERT INTO products_core VALUES('fixture'); CREATE TABLE export_manifest(key TEXT,value TEXT); INSERT INTO export_manifest VALUES('db_version','fixture'),('schema_version','2.3.0');")
        manifest = dict(db_version='fixture', schema_version='2.3.0', pipeline_version='fixture', scoring_version='fixture', product_count=1, min_app_version='1', generated_at='2026-10-12', checksum_sha256=self.digest(db))
        (self.dist / 'export_manifest.json').write_text(json.dumps(manifest))

    @staticmethod
    def digest(path):
        return hashlib.sha256(path.read_bytes()).hexdigest()

    def interaction(self, major=3, exclusions='["2473","4845"]'):
        db = self.dist / 'interaction_db.sqlite'
        with closing(sqlite3.connect(db)) as con, con:
            con.executescript(f"PRAGMA user_version={major}; CREATE TABLE interactions(retired_at TEXT); INSERT INTO interactions VALUES(NULL); CREATE TABLE research_pairs(rxcui_a TEXT,rxcui_b TEXT,canonical_id_a TEXT,canonical_id_b TEXT); CREATE TABLE interaction_db_metadata(key TEXT,value TEXT);")
            con.execute('CREATE TABLE drug_class_map(class_id TEXT, excluded_drug_rxcuis_json TEXT)')
            con.execute('INSERT INTO drug_class_map VALUES(?,?)', ('class:nsaids', exclusions))
            if major >= 4:
                con.execute('ALTER TABLE interactions ADD COLUMN profile_gate_json TEXT')
                con.execute('ALTER TABLE interactions ADD COLUMN medication_exceptions_json TEXT')
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

    def test_pre_corpus_compatibility_requires_no_candidate_and_rejects_unknown_schemas(self):
        for catalog, interaction, expected in [('2.5.0', '4.0.0', 0),
                                                ('99.0.0', '4.0.0', 1),
                                                ('2.5.0', '99.0.0', 1)]:
            with self.subTest(catalog=catalog, interaction=interaction):
                result = subprocess.run(['bash', str(IMPORTER), '--check-compatibility',
                                         catalog, interaction], text=True, capture_output=True)
                self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
        result = subprocess.run(['bash', str(IMPORTER), '--check-compatibility', '2.5.0'],
                                text=True, capture_output=True)
        self.assertNotEqual(result.returncode, 0)

    def test_supported_historical_and_current_schemas(self):
        for major in (1,2,3,4):
            with self.subTest(major=major):
                if (self.dist / 'interaction_db.sqlite').exists():
                    (self.dist / 'interaction_db.sqlite').unlink()
                self.interaction(major)
                result = self.run_gate()
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn('no files written', result.stdout)

    def test_current_reader_schema_is_supported_without_override(self):
        reader = IMPORTER.parents[1] / 'lib/data/database/interaction_database.dart'
        major = int(re.search(r'int get schemaVersion => (\d+);', reader.read_text()).group(1))
        self.interaction(major)
        result = self.run_gate()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_schema_four_retains_profile_and_class_guards(self):
        self.interaction(4)
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

    def test_schema_four_rejects_missing_reader_columns(self):
        self.interaction(4)
        db = self.dist / 'interaction_db.sqlite'
        for column in ('profile_gate_json', 'medication_exceptions_json'):
            with self.subTest(column=column):
                with closing(sqlite3.connect(db)) as con, con:
                    con.execute(f'ALTER TABLE interactions DROP COLUMN {column}')
                self.rehash()
                result = self.run_gate()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('schema-4 interaction column', result.stderr)
                with closing(sqlite3.connect(db)) as con, con:
                    con.execute(f'ALTER TABLE interactions ADD COLUMN {column} TEXT')

    def test_schema_four_rejects_malformed_gate_json(self):
        self.interaction(4)
        for column, invalid in (('profile_gate_json', '[]'), ('profile_gate_json', 'invalid'),
                                ('medication_exceptions_json', '{}'), ('medication_exceptions_json', 'null'),
                                ('profile_gate_json', '{"conditions":NaN}'),
                                ('profile_gate_json', '{"conditions":Infinity}'),
                                ('medication_exceptions_json', '[NaN]'),
                                ('medication_exceptions_json', '[-Infinity]')):
            with self.subTest(column=column, invalid=invalid):
                with closing(sqlite3.connect(self.dist / 'interaction_db.sqlite')) as con, con:
                    con.execute('UPDATE interactions SET profile_gate_json=NULL, medication_exceptions_json=NULL')
                    con.execute(f'UPDATE interactions SET {column}=?', (invalid,))
                self.rehash()
                result = self.run_gate()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('schema-4 interaction JSON', result.stderr)

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
        with closing(sqlite3.connect(self.dist / 'interaction_db.sqlite')) as con, con:
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
        with closing(sqlite3.connect(db)) as con, con:
            con.execute('PRAGMA user_version=2')
        self.rehash()
        result = self.run_gate()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('PRAGMA user_version mismatch', result.stderr)
        with closing(sqlite3.connect(db)) as con, con:
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


class ImportBundleRecovery(unittest.TestCase):
    """Run the actual importer in a disposable repo; never touch app assets."""
    names = ('pharmaguide_core.db', 'export_manifest.json',
             'interaction_db.sqlite', 'interaction_db_manifest.json')
    digest = staticmethod(ImportInteractionContract.digest)
    interaction = ImportInteractionContract.interaction
    rehash = ImportInteractionContract.rehash

    def setUp(self):
        ImportInteractionContract.setUp(self)
        self.repo = self.dist / 'app'
        (self.repo / 'scripts').mkdir(parents=True)
        self.importer = self.repo / 'scripts' / IMPORTER.name
        shutil.copyfile(IMPORTER, self.importer)
        self.assets = self.repo / 'assets/db'
        self.assets.mkdir(parents=True)
        (self.assets / 'user_data.db').write_bytes(b'preserved user data')
        self.inject = self.dist / 'inject'
        self.inject.mkdir()
        # Inject at the real filesystem operation, without a production bypass.
        (self.inject / 'sitecustomize.py').write_text(r"""
import os, pathlib, signal
_real_replace = os.replace
def replace(src, dst, *args, **kwargs):
    target = pathlib.Path(dst)
    if target.name == 'journal.json' and os.environ.get('IMPORT_FAIL_MODE') == 'commit-kill':
        import json
        if json.loads(pathlib.Path(src).read_text()).get('state') == 'committed':
            _real_replace(src, dst, *args, **kwargs)
            os.kill(os.getpid(), signal.SIGKILL)
    if (str(src).endswith('.new') and target.parent == pathlib.Path(os.environ['IMPORT_ASSETS'])
            and target.name in ('pharmaguide_core.db', 'export_manifest.json',
                                'interaction_db.sqlite', 'interaction_db_manifest.json')):
        counter = pathlib.Path(os.environ['IMPORT_COUNTER'])
        n = int(counter.read_text()) + 1 if counter.exists() else 1
        counter.write_text(str(n))
        if n == int(os.environ['IMPORT_FAIL_AT']):
            if os.environ['IMPORT_FAIL_MODE'] == 'pause':
                import time
                result = _real_replace(src, dst, *args, **kwargs)
                pathlib.Path(os.environ['IMPORT_PAUSED']).touch()
                deadline = time.monotonic() + 15
                while not pathlib.Path(os.environ['IMPORT_CONTINUE']).exists():
                    if time.monotonic() > deadline:
                        raise TimeoutError('test did not release paused promotion')
                    time.sleep(0.02)
                return result
            if os.environ['IMPORT_FAIL_MODE'] in ('kill', 'term'):
                _real_replace(src, dst, *args, **kwargs)
                os.kill(os.getpid(), signal.SIGKILL if os.environ['IMPORT_FAIL_MODE'] == 'kill' else signal.SIGTERM)
            raise OSError('injected promotion failure')
    return _real_replace(src, dst, *args, **kwargs)
os.replace = replace
""")
        shim = self.inject / 'mv'
        shim.write_text("""#!/usr/bin/env python3
import os, pathlib, signal, subprocess, sys
src, dst = sys.argv[-2:]
if src.endswith('.new') and pathlib.Path(dst).parent == pathlib.Path(os.environ['IMPORT_ASSETS']):
    counter = pathlib.Path(os.environ['IMPORT_COUNTER'])
    n = int(counter.read_text()) + 1 if counter.exists() else 1
    counter.write_text(str(n))
    if n == int(os.environ['IMPORT_FAIL_AT']):
        if os.environ['IMPORT_FAIL_MODE'] == 'kill':
            subprocess.check_call(['/bin/mv', *sys.argv[1:]])
            os.kill(os.getppid(), signal.SIGKILL)
        sys.exit(73)
os.execv('/bin/mv', ['/bin/mv', *sys.argv[1:]])
""")
        shim.chmod(0o755)

    def prepare(self, interaction, existing):
        if interaction:
            self.interaction(4)
        names = self.names if interaction else self.names[:2]
        if existing:
            for name in names:
                shutil.copyfile(self.dist / name, self.assets / name)
        # Old and new versions are both valid and visibly different.
        for name in names:
            path = self.dist / name
            if name.endswith(('.db', '.sqlite')):
                with closing(sqlite3.connect(path)) as con, con:
                    con.execute('PRAGMA application_id=73')
            else:
                data = json.loads(path.read_text())
                data['generated_at'] = '2026-10-26'
                db = 'pharmaguide_core.db' if name == 'export_manifest.json' else 'interaction_db.sqlite'
                data['checksum_sha256'] = self.digest(self.dist / db)
                path.write_text(json.dumps(data))
        return {n: (self.assets / n).read_bytes() if (self.assets / n).exists() else None for n in names}

    def run_import(self, fail_at=None, mode='raise', dry_run=False):
        env = os.environ.copy()
        if fail_at is not None:
            env.update(IMPORT_ASSETS=str(self.assets), IMPORT_COUNTER=str(self.dist / 'counter'),
                       IMPORT_FAIL_AT=str(fail_at), IMPORT_FAIL_MODE=mode,
                       PYTHONPATH=str(self.inject), PATH=str(self.inject) + os.pathsep + env['PATH'])
        command = ['bash', str(self.importer), str(self.dist), '--min-products', '1']
        if dry_run:
            command.append('--dry-run')
        return subprocess.run(command, text=True, capture_output=True, env=env)

    def assert_bundle(self, expected):
        self.assertEqual((self.assets / 'user_data.db').read_bytes(), b'preserved user data')
        for name, contents in expected.items():
            path = self.assets / name
            self.assertEqual(path.read_bytes() if path.exists() else None, contents, name)

    def test_promotion_failure_restores_previous_bundle(self):
        before = self.prepare(interaction=True, existing=True)
        result = self.run_import(fail_at=2)
        self.assertNotEqual(result.returncode, 0)
        self.assert_bundle(before)

    def test_each_replacement_failure_is_recoverable(self):
        for interaction in (False, True):
            for existing in (False, True):
                for mode in ('raise', 'kill'):
                    for boundary in range(1, 5 if interaction else 3):
                        with self.subTest(interaction=interaction, existing=existing, mode=mode, boundary=boundary):
                            # Independent disposable target/input for each boundary.
                            with ImportBundleRecovery() as case:
                                before = case.prepare(interaction, existing)
                                result = case.run_import(boundary, mode)
                                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                                self.assertEqual(int((case.dist / 'counter').read_text()), boundary)
                                if mode == 'raise':
                                    case.assert_bundle(before)
                                else:
                                    partial = {p.name: p.read_bytes() for p in case.assets.iterdir() if p.is_file()}
                                    dry = case.run_import(dry_run=True)
                                    self.assertNotEqual(dry.returncode, 0)
                                    self.assertEqual(partial, {p.name: p.read_bytes() for p in case.assets.iterdir() if p.is_file()})
                                retry = case.run_import()
                                self.assertEqual(retry.returncode, 0, retry.stdout + retry.stderr)
                                case.assert_bundle({n: (case.dist / n).read_bytes() for n in before})
                                for name, contents in before.items():
                                    if contents is not None:
                                        self.assertEqual((case.assets / (name + '.previous')).read_bytes(), contents)
                                self.assertFalse((case.assets / '.catalog-import-transaction').exists())

    def test_recovery_precedes_invalid_new_source_validation(self):
        before = self.prepare(interaction=True, existing=True)
        interrupted = self.run_import(2, 'kill')
        self.assertNotEqual(interrupted.returncode, 0)
        (self.dist / 'export_manifest.json').write_text('invalid')
        result = self.run_import()
        self.assertNotEqual(result.returncode, 0)
        self.assert_bundle(before)
        self.assertFalse((self.assets / '.catalog-import-transaction').exists())

    def test_corrupt_recovery_backup_is_retained_and_refused(self):
        self.prepare(interaction=True, existing=True)
        interrupted = self.run_import(2, 'kill')
        self.assertNotEqual(interrupted.returncode, 0)
        transaction = self.assets / '.catalog-import-transaction'
        (transaction / 'pharmaguide_core.db.original').write_bytes(b'corrupt')
        partial = {p.name: p.read_bytes() for p in self.assets.iterdir() if p.is_file()}
        result = self.run_import()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('backup checksum mismatch', result.stderr)
        self.assertEqual(partial, {p.name: p.read_bytes() for p in self.assets.iterdir() if p.is_file()})
        self.assertTrue((transaction / 'journal.json').exists())

    def test_catalog_only_import_keeps_existing_interaction_bundle(self):
        self.prepare(interaction=False, existing=True)
        for name in self.names[2:]:
            (self.assets / name).write_bytes(('existing ' + name).encode())
        result = self.run_import()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        for name in self.names[2:]:
            self.assertEqual((self.assets / name).read_bytes(), ('existing ' + name).encode())

    def test_termination_signal_rolls_back_immediately(self):
        before = self.prepare(interaction=True, existing=True)
        result = self.run_import(3, 'term')
        self.assertNotEqual(result.returncode, 0)
        self.assert_bundle(before)
        self.assertFalse((self.assets / '.catalog-import-transaction').exists())

    def test_committed_interruption_finishes_backups_without_rollback(self):
        before = self.prepare(interaction=True, existing=True)
        expected = {n: (self.dist / n).read_bytes() for n in before}
        result = self.run_import(99, 'commit-kill')
        self.assertNotEqual(result.returncode, 0)
        self.assert_bundle(expected)
        # Force the retry to stop after recovery, before any new import.
        (self.dist / 'export_manifest.json').write_text('invalid')
        retry = self.run_import()
        self.assertNotEqual(retry.returncode, 0)
        self.assert_bundle(expected)
        for name, contents in before.items():
            self.assertEqual((self.assets / (name + '.previous')).read_bytes(), contents)
        self.assertFalse((self.assets / '.catalog-import-transaction').exists())

    def test_concurrent_imports_share_lock_despite_different_tmpdir(self):
        self.prepare(interaction=True, existing=True)
        tmp_a, tmp_b = self.dist / 'tmp-a', self.dist / 'tmp-b'
        tmp_a.mkdir()
        tmp_b.mkdir()
        paused, resume = self.dist / 'paused', self.dist / 'resume'
        attempted, acquired = self.dist / 'attempted', self.dist / 'acquired'
        observer = self.dist / 'observer'
        observer.mkdir()
        (observer / 'sitecustomize.py').write_text("""
import fcntl, os, pathlib
original = fcntl.flock
def flock(fd, operation):
    pathlib.Path(os.environ['IMPORT_LOCK_ATTEMPT']).touch()
    result = original(fd, operation)
    pathlib.Path(os.environ['IMPORT_LOCK_ACQUIRED']).touch()
    return result
fcntl.flock = flock
""")
        command = ['bash', str(self.importer), str(self.dist), '--min-products', '1']
        first_env = dict(os.environ, TMPDIR=str(tmp_a), PYTHONPATH=str(self.inject),
                         IMPORT_ASSETS=str(self.assets), IMPORT_COUNTER=str(self.dist / 'counter'),
                         IMPORT_FAIL_AT='1', IMPORT_FAIL_MODE='pause',
                         IMPORT_PAUSED=str(paused), IMPORT_CONTINUE=str(resume))
        second_env = dict(os.environ, TMPDIR=str(tmp_b), PYTHONPATH=str(observer),
                          IMPORT_LOCK_ATTEMPT=str(attempted), IMPORT_LOCK_ACQUIRED=str(acquired))
        first = subprocess.Popen(command, text=True, stdout=subprocess.PIPE,
                                 stderr=subprocess.PIPE, env=first_env)
        second = None
        def wait_for(path):
            deadline = time.monotonic() + 10
            while not path.exists() and time.monotonic() < deadline:
                time.sleep(0.02)
            self.assertTrue(path.exists(), str(path))
        try:
            wait_for(paused)
            second = subprocess.Popen(command, text=True, stdout=subprocess.PIPE,
                                      stderr=subprocess.PIPE, env=second_env)
            wait_for(attempted)
            deadline = time.monotonic() + 1
            while not acquired.exists() and time.monotonic() < deadline:
                time.sleep(0.02)
            self.assertFalse(acquired.exists(), 'second importer entered a live transaction')
            resume.touch()
            first_output = first.communicate(timeout=15)
            second_output = second.communicate(timeout=15)
            self.assertEqual(first.returncode, 0, ''.join(first_output))
            self.assertEqual(second.returncode, 0, ''.join(second_output))
            self.assert_bundle({name: (self.dist / name).read_bytes() for name in self.names})
            self.assertFalse((self.assets / '.catalog-import-transaction').exists())
        finally:
            resume.touch()
            for process in (first, second):
                if process is not None:
                    try:
                        process.communicate(timeout=15)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.communicate()

    def __enter__(self):
        self.setUp()
        return self

    def __exit__(self, *_):
        self.doCleanups()


if __name__ == '__main__':
    unittest.main()
