"""Read-only native identity capture; all simulator responses are local fixtures."""
from contextlib import closing, redirect_stdout
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import plistlib
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / 'verify_native_app.py'
spec = importlib.util.spec_from_file_location('verify_native_app', SCRIPT)
doctor = importlib.util.module_from_spec(spec)
spec.loader.exec_module(doctor)


class NativeDoctorTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.app = self.root / 'Runner.app'
        self.dart = self.app / 'Frameworks/App.framework'
        self.dart.mkdir(parents=True)
        (self.app / 'Runner').write_bytes(b'runner binary')
        (self.dart / 'App').write_bytes(b'dart framework binary')
        (self.dart / 'flutter_assets').mkdir()
        (self.dart / 'flutter_assets/kernel_blob.bin').write_bytes(b'debug dart code')
        (self.app / 'Info.plist').write_bytes(plistlib.dumps({
            'CFBundleExecutable': 'Runner', 'CFBundleShortVersionString': '1.0',
            'CFBundleVersion': '42',
        }))
        self.data = self.root / 'data'
        documents = self.data / 'Documents'
        documents.mkdir(parents=True)
        self.catalog = documents / 'pharmaguide_core.db'
        with closing(sqlite3.connect(self.catalog)) as db, db:
            db.executescript('''
                CREATE TABLE export_manifest(key TEXT,value TEXT);
                INSERT INTO export_manifest VALUES('db_version','fixture.1'),('schema_version','2.5.0');
                CREATE TABLE products_core(dsld_id TEXT,product_name TEXT,brand_name TEXT,
                    export_version TEXT,detail_blob_sha256 TEXT,quality_score_v4_100 REAL,
                    quality_score_status TEXT,quality_assessment_status TEXT,product_safety_status TEXT);
                INSERT INTO products_core VALUES('295048','Caffeine','Fixture','fixture.1',
                    'declared-detail-hash',78,'scored','partial','review');
            ''')
        (documents / 'user_data.db').write_bytes(b'user data must remain unchanged')
        self.inputs = {p: p.read_bytes() for p in self.root.rglob('*') if p.is_file()}
        self.calls = []

    def simctl(self, *args):
        self.calls.append(args)
        if args == ('xcrun', 'simctl', 'list', 'devices', '-j'):
            return json.dumps({'devices': {'ios': [{'udid': 'device-1', 'name': 'QA', 'state': 'Booted'}]}})
        if args == ('xcrun', 'simctl', 'get_app_container', 'device-1', 'com.pharmaguide.app', 'app'):
            return str(self.app)
        if args == ('xcrun', 'simctl', 'get_app_container', 'device-1', 'com.pharmaguide.app', 'data'):
            return str(self.data)
        raise AssertionError(f'Unexpected command, possibly a mutation: {args}')

    def run_doctor(self, *extra, command=None):
        output = self.root / 'evidence'
        with patch.object(sys, 'argv', [str(SCRIPT), '--device', 'device-1', '--output', str(output), *extra]), \
                patch.object(doctor, 'command', side_effect=command or self.simctl), redirect_stdout(io.StringIO()):
            result = doctor.main()
        return result, json.loads((output / 'doctor.json').read_text())

    def test_exact_installed_schema_and_binary_identity_are_read_only(self):
        result, report = self.run_doctor('--expected-catalog', 'fixture.1')
        self.assertEqual(result, 0)
        self.assertEqual(report['result'], 'identity_captured')
        self.assertTrue(report['expected_catalog_matches'])
        self.assertEqual(report['installed_catalog']['product']['dsld_id'], '295048')
        self.assertEqual(report['installed_catalog']['product']['quality_assessment_status'], 'partial')
        self.assertEqual(report['installed_dart_framework_sha256'], hashlib.sha256(b'dart framework binary').hexdigest())
        self.assertEqual(report['installed_dart_snapshot_sha256']['kernel_blob.bin'], hashlib.sha256(b'debug dart code').hexdigest())
        self.assertEqual(report['installed_executable_sha256'], hashlib.sha256(b'runner binary').hexdigest())
        for path, before in self.inputs.items():
            self.assertEqual(path.read_bytes(), before, str(path))
        self.assertEqual(len(self.calls), 3)

    def test_catalog_change_during_read_cannot_produce_a_mixed_receipt(self):
        with patch.object(doctor, 'digest', side_effect=['before', 'after']):
            with self.assertRaisesRegex(ValueError, 'changed during identity capture'):
                doctor.inspect_catalog(self.catalog, '295048')

    def test_missing_exact_label_fails_instead_of_selecting_another_product(self):
        result, report = self.run_doctor('--product', 'not-the-label')
        self.assertEqual(result, 1)
        self.assertEqual(report['result'], 'unverified')
        self.assertEqual(report['installed_catalog']['product'], {})

    def test_expected_catalog_mismatch_is_not_success(self):
        result, report = self.run_doctor('--expected-catalog', 'fixture.2')
        self.assertEqual(result, 1)
        self.assertFalse(report['expected_catalog_matches'])
        self.assertEqual(report['result'], 'unverified')
        self.assertEqual(report['installed_catalog']['manifest']['db_version'], 'fixture.1')

    def test_noninstalled_app_fails_without_launching_or_installing(self):
        def missing(*args):
            if args[2] == 'get_app_container':
                raise subprocess.CalledProcessError(1, args, stderr='Application is not installed')
            return self.simctl(*args)
        result, report = self.run_doctor(command=missing)
        self.assertEqual(result, 1)
        self.assertEqual(report['result'], 'unverified')
        self.assertNotIn('installed_catalog', report)

    def test_missing_catalog_is_not_created(self):
        self.catalog.unlink()
        result, report = self.run_doctor()
        self.assertEqual(result, 1)
        self.assertEqual(report['result'], 'unverified')
        self.assertFalse(self.catalog.exists())

    def test_old_journey_does_not_establish_runtime_mode_or_current_success(self):
        journey = self.data / 'Documents/verification'
        journey.mkdir()
        previous = {'result': 'passed', 'source_revision_at_launch': 'old', 'installed_catalog_version': 'old'}
        (journey / 'native_journey.json').write_text(json.dumps(previous))
        result, report = self.run_doctor()
        self.assertEqual(result, 0)
        self.assertEqual(report['result'], 'identity_captured')
        self.assertEqual(report['runtime_mode'], 'unverified_without_current_journey_receipt')
        self.assertIn('journey_note', report)
        self.assertEqual(json.loads((self.root / 'evidence/native-journey/native_journey.json').read_text()), previous)

    def test_missing_dart_code_cannot_claim_complete_identity(self):
        (self.dart / 'App').unlink()
        result, report = self.run_doctor()
        self.assertEqual(result, 1)
        self.assertEqual(report['result'], 'unverified')


if __name__ == '__main__':
    unittest.main()
