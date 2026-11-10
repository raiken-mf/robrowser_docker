#!/usr/bin/env python3
"""Check offline bootstrap confidentiality and credential mappings with fixtures."""
import base64
import json
import os
from pathlib import Path
import stat
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix='bootstrap-check-') as directory:
    work = Path(directory)
    fixture = work / 'fixture.env'
    # Deliberately synthetic, never used by a deployment.
    values = {'MARIADB_HOST': 'database', 'MARIADB_DATABASE': 'ragnarok', 'MARIADB_USER': 'ragnarok',
              'MARIADB_ROOT_PASSWORD': 'fixture-root-only', 'MARIADB_PASSWORD': 'fixture-db-only',
              'SET_INTERSRV_USER': 'fixture-server', 'SET_INTERSRV_PASSWORD': 'fixture-server-only'}
    fixture.write_text(''.join(f'{key}={value}\n' for key, value in values.items()))
    command = ['python3', str(ROOT / 'scripts/py/render-k8s-bootstrap.py')]
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
    selected = subprocess.run(command + ['--env-file', str(fixture), '--output-dir', str(work/'selected')],
                              env=dict(os.environ, K8S_NAMESPACE='fixture-selected'), capture_output=True, text=True)
    assert selected.returncode == 0, selected.stderr
    assert all(item['metadata']['namespace'] == 'fixture-selected'
               for item in json.loads((work/'selected/bootstrap.json').read_text())['items']), 'Environment namespace lost'
    explicit = work / 'explicit.env'
    explicit.write_text(fixture.read_text() + 'K8S_NAMESPACE=fixture-explicit\n')
    selected = subprocess.run(command + ['--env-file', str(explicit), '--output-dir', str(work/'explicit')],
                              env=dict(os.environ, K8S_NAMESPACE='fixture-selected'), capture_output=True, text=True)
    assert selected.returncode == 0, selected.stderr
    assert all(item['metadata']['namespace'] == 'fixture-explicit'
               for item in json.loads((work/'explicit/bootstrap.json').read_text())['items']), 'File namespace must take precedence'
    again = subprocess.run(command + ['--env-file', str(fixture), '--output-dir', str(work/'private')], capture_output=True, text=True)
    assert again.returncode, 'Existing private bootstrap overwritten'
    installer_fixture = work / 'installer.env'
    installer_fixture.write_text(''.join(f'{key}={value}\n' for key, value in values.items()
                                         if key not in ('MARIADB_HOST', 'MARIADB_DATABASE', 'MARIADB_USER')))
    binary = work / 'bin'
    binary.mkdir()
    fake = binary / 'kubectl'
    fake.write_text('''#!/usr/bin/env python3
import json, os, sys
args = sys.argv[1:]
with open(os.environ['MOCK_LOG'], 'a') as stream:
    stream.write(json.dumps(args) + '\\n')
if 'get' in args and 'endpoints' in args:
    if os.environ.get('MOCK_ENDPOINTS') != 'missing': print('127.0.0.1')
elif 'get' in args and ('crd' in args or 'deployment' in args):
    if os.environ.get('MOCK_EXISTING') == 'true': print('fixture-existing')
elif 'create' in args:
    print('kind: Namespace')
elif 'apply' in args:
    data = sys.stdin.read()
    if data.startswith('{'):
        with open(os.environ['MOCK_MANIFEST'], 'w') as stream:
            stream.write(data)
''')
    fake.chmod(0o755)
    helm = binary / 'helm'
    helm.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$MOCK_HELM_LOG"\nexit 0\n')
    helm.chmod(0o755)
    envsubst = binary / 'envsubst'
    envsubst.write_text('#!/bin/sh\ncat\n')
    envsubst.chmod(0o755)
    sleep = binary / 'sleep'
    sleep.write_text('#!/bin/sh\nexit 0\n')
    sleep.chmod(0o755)
    log, manifest = work / 'calls.jsonl', work / 'manifest.json'
    env = {'PATH': str(binary) + os.pathsep + os.environ['PATH'], 'ENV_FILE': str(installer_fixture),
            'MOCK_LOG': str(log), 'MOCK_MANIFEST': str(manifest), 'TMPDIR': str(work),
            'MOCK_HELM_LOG': str(work/'helm.log'), 'MARIADB_OPERATOR_VERSION': '1.2.3'}
    result = subprocess.run(['bash', str(ROOT / 'scripts/sh/k8s/k8s-mariadb.sh')], cwd=ROOT,
                            env=env, capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    assert not any(values[key] in result.stdout + result.stderr + log.read_text()
                   for key in ('MARIADB_ROOT_PASSWORD', 'MARIADB_PASSWORD', 'SET_INTERSRV_PASSWORD'))
    items = json.loads(manifest.read_text())['items']
    assert len(items) == 2 and all(item['kind'] == 'Secret' for item in items)
    user = next(item for item in items if item['metadata']['name'] == 'mariadb-user-secret')
    decoded = {key: base64.b64decode(value).decode() for key, value in user['data'].items()}
    assert decoded['MARIADB_HOST'] == 'mariadb' and decoded['MARIADB_USER'] == 'ragnarok-user'
    assert decoded['SET_INTERSRV_PASSWORD'] == values['SET_INTERSRV_PASSWORD']
    upgrades = [line for line in (work/'helm.log').read_text().splitlines() if line.startswith('upgrade')]
    assert len(upgrades) == 2 and all('--version 1.2.3' in line for line in upgrades), 'Operator and CRDs must use the reviewed version'
    for extra in ({'MARIADB_OPERATOR_VERSION': ''}, {'MOCK_EXISTING': 'true'}):
        (work/'helm.log').write_text('')
        result = subprocess.run(['bash', str(ROOT / 'scripts/sh/k8s/k8s-mariadb.sh')], cwd=ROOT,
                                env={**env, **extra}, capture_output=True, text=True)
        assert result.returncode != 0, 'Unpinned or existing installation accepted'
        assert not (work/'helm.log').read_text(), 'Unsafe preflight invoked Helm'
    log.write_text('')
    result = subprocess.run(['bash', str(ROOT / 'scripts/sh/k8s/k8s-mariadb.sh')], cwd=ROOT,
                            env={**env, 'MOCK_ENDPOINTS': 'missing'}, capture_output=True, text=True)
    assert result.returncode != 0, 'Webhook timeout must abort installation'
    assert not any('apply' in json.loads(line) for line in log.read_text().splitlines()), 'Webhook failure applied resources'
print('PASS offline bootstrap: requires operator config, preserves secret mappings, private modes, no output leaks or overwrite')
