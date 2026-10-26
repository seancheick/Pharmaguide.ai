#!/usr/bin/env python3
"""Read-only identity/evidence capture for an explicitly selected iOS simulator.

Does not launch, seed, import, publish or change the app's data. Runtime source
and special-mode claims require a matching native journey receipt.
"""
import argparse
from contextlib import closing
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import sqlite3
import subprocess


def command(*args):
    return subprocess.check_output(args, text=True).strip()


def digest(path):
    checksum = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            checksum.update(chunk)
    return checksum.hexdigest()


def inspect_catalog(path, product_id):
    before = digest(path)
    with closing(sqlite3.connect(path.resolve().as_uri() + '?mode=ro', uri=True)) as db:
        db.row_factory = sqlite3.Row
        db.execute('BEGIN')
        manifest = dict(db.execute('SELECT key,value FROM export_manifest'))
        row = db.execute('SELECT * FROM products_core WHERE dsld_id = ?', (product_id,)).fetchone()
        selected = ('dsld_id', 'product_name', 'brand_name', 'export_version',
                    'detail_blob_sha256', 'quality_score_v4_100',
                    'quality_score_status', 'quality_assessment_status', 'product_safety_status')
        product = {key: row[key] for key in selected if row is not None and key in row.keys()}
    if digest(path) != before:
        raise ValueError('Catalog changed during identity capture; repeat the read-only check')
    return {'path': str(path), 'file_sha256': before, 'manifest': manifest, 'product': product}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', required=True, help='Explicit simulator UUID; never booted alias')
    parser.add_argument('--bundle-id', default='com.pharmaguide.app')
    parser.add_argument('--product', default='295048')
    parser.add_argument('--output', type=Path, required=True, help='New durable evidence directory')
    parser.add_argument('--expected-catalog')
    args = parser.parse_args()
    if args.device == 'booted':
        parser.error('select one owned simulator UUID explicitly')
    args.output.mkdir(parents=True, exist_ok=False)
    report = {'device': args.device, 'bundle_id': args.bundle_id,
              'captured_at': datetime.now(timezone.utc).isoformat(),
              'runtime_mode': 'unverified_without_current_journey_receipt',
              'limitations': [
                  'Installed file identity does not establish the currently running process, source revision, or UI behavior.',
                  'A recorded detail hash identifies the catalog reference; this check does not fetch or verify the detail payload.',
                  'Historical journey files require reconciliation with a current launch, action log, and successful runner exit.',
                  'Identity capture does not establish assessment completeness, publication success, or scientific approval.',
              ]}
    try:
        devices = json.loads(command('xcrun', 'simctl', 'list', 'devices', '-j'))
        device = next((d for group in devices['devices'].values() for d in group if d['udid'] == args.device), None)
        if device is None:
            raise ValueError('Selected simulator UUID was not found')
        report['device_name'] = device['name']
        report['device_state'] = device['state']
        application = Path(command('xcrun', 'simctl', 'get_app_container', args.device, args.bundle_id, 'app'))
        data = Path(command('xcrun', 'simctl', 'get_app_container', args.device, args.bundle_id, 'data'))
        with (application / 'Info.plist').open('rb') as stream:
            info = plistlib.load(stream)
        report['app_version'] = info.get('CFBundleShortVersionString')
        report['app_build'] = info.get('CFBundleVersion')
        report['installed_executable_sha256'] = digest(application / info['CFBundleExecutable'])
        dart_framework = application / 'Frameworks/App.framework'
        report['installed_dart_framework_sha256'] = digest(dart_framework / 'App')
        dart_assets = dart_framework / 'flutter_assets'
        report['installed_dart_snapshot_sha256'] = {
            name: digest(dart_assets / name)
            for name in ('kernel_blob.bin', 'vm_snapshot_data', 'isolate_snapshot_data')
            if (dart_assets / name).is_file()
        }
        report['installed_catalog'] = inspect_catalog(data / 'Documents/pharmaguide_core.db', args.product)
        bundle_db = application / 'Frameworks/App.framework/flutter_assets/assets/db/pharmaguide_core.db'
        if bundle_db.exists():
            report['bundled_catalog'] = inspect_catalog(bundle_db, args.product)
        journey = data / 'Documents/verification'
        if journey.is_dir():
            shutil.copytree(journey, args.output / 'native-journey')
            report['journey_receipt'] = 'native-journey/native_journey.json'
            report['journey_note'] = 'Historical receipt until its launch source, catalog and action log are reconciled; not proof current app is running.'
        if not report['installed_catalog']['product']:
            raise ValueError('Requested label is absent from installed catalog')
        version = report['installed_catalog']['manifest'].get('db_version')
        report['expected_catalog_matches'] = None if args.expected_catalog is None else version == args.expected_catalog
        report['result'] = 'identity_captured'
        if args.expected_catalog and version != args.expected_catalog:
            raise ValueError('Installed catalog differs from requested catalog')
    except Exception as error:
        report['result'] = 'unverified'
        report['error'] = str(error)
    (args.output / 'doctor.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({k: report.get(k) for k in ('result','app_version','app_build','expected_catalog_matches','error')}, indent=2))
    return 0 if report['result'] == 'identity_captured' else 1


if __name__ == '__main__':
    raise SystemExit(main())
