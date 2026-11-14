"""Offline release contract checks. Python 3.10+, no third-party packages."""
import argparse
import hashlib
import json
import re
import subprocess
import sys
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT, text=True).strip()


def validate(root=ROOT, base_ref=None):
    errors = []
    manifest = json.loads((root / 'schema-version.json').read_text(encoding='utf-8'))
    version = manifest['schema_version']
    if not re.fullmatch(r'\d+\.\d+\.\d+', version):
        errors.append('schema_version must be numeric SemVer')
    date.fromisoformat(manifest['updated_at'])
    migrations = manifest['migrations']
    ids = [m['id'] for m in migrations]
    if not ids or ids != sorted(set(ids)) or any(not re.fullmatch(r'\d{14}', i) for i in ids):
        errors.append('Migration IDs must be unique, ordered 14-digit timestamps')
    if not ids or manifest['latest_migration'] != ids[-1]:
        errors.append('latest_migration must match the final migration')
    paths = [m['path'] for m in migrations]
    actual = sorted(p.relative_to(root).as_posix() for p in (root / 'supabase/migrations').glob('*.sql'))
    if sorted(paths) != actual or len(set(paths)) != len(paths):
        errors.append('Manifest and migration SQL inventory differ')
    for m in migrations:
        if not re.fullmatch(r'supabase/migrations/' + re.escape(m['id']) + r'_[a-z0-9_]+\.sql', m['path']):
            errors.append(f"Invalid migration path: {m['path']}")
            continue
        p = root / m['path']
        if not p.is_file() or hashlib.sha256(p.read_bytes()).hexdigest() != m['sha256']:
            errors.append(f"Migration checksum mismatch: {m['path']}")
    readme = (root / 'README.md').read_text(encoding='utf-8')
    notice = f"SCHEMA CONTRACT: {version} | Latest migration: {manifest['latest_migration']} | Updated: {manifest['updated_at']}"
    if notice not in '\n'.join(readme.splitlines()[:6]):
        errors.append('README top notice does not match schema-version.json')
    changelog = (root / 'CHANGELOG.md').read_text(encoding='utf-8')
    releases = re.findall(r'^## \[(\d+\.\d+\.\d+)\] - (\d{4}-\d{2}-\d{2})$', changelog, re.M)
    if not releases or releases[0] != (version, manifest['updated_at']):
        errors.append('Newest CHANGELOG release must match version/date')
    for required in ['AGENTS.md', 'docs/module-contracts.md', 'docs/integration.md', 'docs/change-workflow.md', 'tests/verify_access.sql']:
        if not (root / required).is_file():
            errors.append(f'Missing required contract file: {required}')

    if base_ref:
        old = json.loads(git('show', f'{base_ref}:schema-version.json'))
        changes = git('diff', '--name-status', '--no-renames', base_ref, 'HEAD').splitlines()
        changed = {line.split('\t', 1)[1] for line in changes if '\t' in line}
        for m in old['migrations']:
            if m not in migrations:
                errors.append(f"Released manifest entry was changed/removed: {m['id']}")
            if m['path'] in changed:
                errors.append(f"Released migration was edited/removed: {m['path']}")
        new_migrations = [m for m in migrations if m['id'] not in {x['id'] for x in old['migrations']}]
        if new_migrations:
            if tuple(map(int, version.split('.'))) <= tuple(map(int, old['schema_version'].split('.'))):
                errors.append('New migrations require a higher schema version')
            if any(m['id'] <= old['latest_migration'] for m in new_migrations):
                errors.append('New migration IDs must sort after the released baseline')
            for p in ['schema-version.json', 'README.md', 'CHANGELOG.md']:
                if p not in changed:
                    errors.append(f'New migration requires an update to {p}')
            if not any(p.startswith('docs/') for p in changed):
                errors.append('New migration requires updated integration/design documentation')
            if not any(p.startswith('tests/') for p in changed):
                errors.append('New migration requires updated verification')
        elif version != old['schema_version']:
            errors.append('Schema version changed without a new migration')
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base-ref', help='Compare committed HEAD with an existing Git base revision')
    args = parser.parse_args()
    try:
        errors = validate(base_ref=args.base_ref)
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as e:
        print(f'FAIL: cannot validate contract: {e}', file=sys.stderr)
        return 2
    if errors:
        print('\n'.join('FAIL: ' + e for e in errors), file=sys.stderr)
        return 1
    print('PASS: migration inventory/checksums, version notice and documentation contract')
    return 0


if __name__ == '__main__':
    sys.exit(main())
