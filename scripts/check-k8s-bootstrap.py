#!/usr/bin/env python3
"""Check offline bootstrap confidentiality and credential mappings with fixtures."""
import base64
import json
from pathlib import Path
import stat
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='bootstrap-check-') as directory:
    work = Path(directory)
    fixture = work / 'fixture.env'
    # Deliberately synthetic, never used by a deployment.
    values = {'MARIADB_HOST': 'database', 'MARIADB_DATABASE': 'ragnarok', 'MARIADB_USER': 'ragnarok',
              'MARIADB_ROOT_PASSWORD': 'fixture-root-only', 'MARIADB_PASSWORD': 'fixture-db-only',
              'SET_INTERSRV_USER': 'fixture-server', 'SET_INTERSRV_PASSWORD': 'fixture-server-only'}
    fixture.write_text(''.join(f'{key}={value}\n' for key, value in values.items()))
    command = ['python3', str(ROOT / 'scripts/render-k8s-bootstrap.py')]
    bad = subprocess.run(command + ['--env-file', str(ROOT / '.env-tmpl'), '--output-dir', str(work/'bad')], capture_output=True, text=True)
    assert bad.returncode and not (work/'bad').exists(), 'Repository template accepted as operator configuration'
    result = subprocess.run(command + ['--env-file', str(fixture), '--output-dir', str(work/'private')], capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    for key in ('MARIADB_ROOT_PASSWORD', 'MARIADB_PASSWORD', 'SET_INTERSRV_PASSWORD'):
        assert values[key] not in result.stdout + result.stderr, 'Credential in output'
    path = work/'private/bootstrap.json'
    assert stat.S_IMODE(path.stat().st_mode) == 0o600
    assert stat.S_IMODE(path.parent.stat().st_mode) == 0o700
    objects = json.loads(path.read_text())['items']
    secrets = {o['metadata']['name']: o for o in objects if o['kind']=='Secret'}
    data = {k:base64.b64decode(v).decode() for k,v in secrets['mariadb-user-secret']['data'].items()}
    assert data['password'] == data['MARIADB_PASSWORD'] == values['MARIADB_PASSWORD']
    assert data['SET_INTERSRV_PASSWORD'] == values['SET_INTERSRV_PASSWORD']
    again = subprocess.run(command + ['--env-file', str(fixture), '--output-dir', str(work/'private')], capture_output=True, text=True)
    assert again.returncode, 'Existing private bootstrap overwritten'
print('PASS offline bootstrap: requires operator config, preserves secret mappings, private modes, no output leaks or overwrite')
