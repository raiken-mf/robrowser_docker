#!/usr/bin/env python3
"""Check Compose runtime environment boundaries using synthetic configuration."""
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile

root = pathlib.Path(__file__).resolve().parents[2]
common = root / 'deploy/compose/docker-compose-common.yml'
database = {'MARIADB_ROOT_PASSWORD', 'MARIADB_DATABASE', 'MARIADB_USER', 'MARIADB_PASSWORD'}
game = {'MARIADB_HOST', 'MARIADB_DATABASE', 'MARIADB_USER', 'MARIADB_PASSWORD',
        'SET_INTERSRV_USER', 'SET_INTERSRV_PASSWORD', 'SET_MOTD', 'SET_PRERENEWAL',
        'LOGIN_SERVER_HOST', 'CHAR_SERVER_HOST', 'MAP_SERVER_HOST', 'SET_PINCODE_ENABLED', 'SET_NEW_ACCOUNT', 'INIT_DB'}
remote = {'ROBROWSER_ROLE', 'PACKETVER', 'SET_PRERENEWAL', 'ROENGLISH_ADDITIONS',
          'ROENGLISH_ADDONS', 'ROENGLISH_LEGACY_MAPS', 'GRF_ENCODING', 'PATH_MAPPING_ENABLED',
          'CACHE_ENABLED', 'CACHE_MAX_FILES', 'CACHE_MAX_MEMORY_MB'}
frontend = {'ROBROWSER_ROLE', 'HOST', 'PORT_HTTP', 'PORT_FRONTEND', 'PORT_WSPROXY', 'PACKETVER',
            'PACKET_OBFUSCATION_KEY1', 'PACKET_OBFUSCATION_KEY2', 'PACKET_OBFUSCATION_KEY3'}
environment = {key: os.environ[key] for key in ('PATH', 'HOME', 'DOCKER_HOST', 'DOCKER_CONTEXT',
               'DOCKER_CONFIG', 'DOCKER_TLS_VERIFY', 'DOCKER_CERT_PATH') if key in os.environ}
with tempfile.TemporaryDirectory(prefix='compose-starter-') as directory:
    fixture = pathlib.Path(directory)
    (fixture / 'scripts/sh/compose').mkdir(parents=True)
    (fixture / 'deploy/compose').mkdir(parents=True)
    shutil.copy(root / 'scripts/sh/compose/start-compose.sh', fixture / 'scripts/sh/compose')
    shutil.copy(common, fixture / 'deploy/compose')
    shutil.copy(root / 'deploy/compose/docker-compose-rathena.yml', fixture / 'deploy/compose')
    shutil.copy(root / 'deploy/compose/docker-compose-hercules.yml', fixture / 'deploy/compose')
    shutil.copy(root / '.env-tmpl', fixture / '.env')
    shutil.copy(root / '.env-tmpl', fixture / 'alternate.env')
    with (fixture / 'alternate.env').open('a') as alternate:
        alternate.write('\nHOST=alternate.example.invalid\n')
    docker = fixture / 'docker'
    docker.write_text('''#!/bin/bash
set -eu
if [ "$1" = info ] || [ "${2:-}" = version ]; then exit 0; fi
action=${!#}
if [ "$action" = -d ]; then action=up; fi
printf '%s\\n' "$action" >> "$TEST_ACTIONS"
if [ "${FAIL_ACTION:-}" = "$action" ]; then exit 42; fi
args=("${@:2}")
if [ "${args[${#args[@]}-1]}" = -d ]; then unset 'args[${#args[@]}-1]'; fi
unset 'args[${#args[@]}-1]'
if [ "$action" = up ]; then
        PATH="$REAL_PATH" "$REAL_DOCKER" compose "${args[@]}" config --format json | "$PYTHON" -c 'import json, os, sys; services = json.load(sys.stdin)["services"]; assert services["database"]["environment"]["MARIADB_PASSWORD"]; assert services["rathena"]["environment"]["SET_INTERSRV_PASSWORD"]; assert not os.environ.get("EXPECT_ALTERNATE") or services["robrowser"]["environment"]["HOST"] == "alternate.example.invalid"'
else
        PATH="$REAL_PATH" "$REAL_DOCKER" compose "${args[@]}" config --quiet
fi
''')
    docker.chmod(0o700)
    starter_env = {**environment, 'PATH': str(fixture) + os.pathsep + environment['PATH'],
                   'REAL_DOCKER': shutil.which('docker'),
                   'PYTHON': sys.executable, 'REAL_PATH': environment['PATH'],
                   'TEST_ACTIONS': str(fixture / 'actions')}
    starter = ['bash', str(fixture / 'scripts/sh/compose/start-compose.sh')]
    for extra_env in ({}, {'ENV_FILE': str(fixture / 'alternate.env'), 'EXPECT_ALTERNATE': '1'}):
        subprocess.run(starter + ['rathena', 'detached'], cwd=fixture,
                       env={**starter_env, **extra_env}, check=True, text=True)
    (fixture / '.env').unlink()
    missing = subprocess.run(starter + ['rathena'], cwd=fixture, env=starter_env, capture_output=True, text=True)
    assert missing.returncode != 0, 'starter accepted missing configuration'
    missing_alternate = subprocess.run(starter + ['rathena'], cwd=fixture,
                                       env={**starter_env, 'ENV_FILE': 'missing.env'}, capture_output=True, text=True)
    assert missing_alternate.returncode != 0, 'starter accepted missing alternate configuration'
    (fixture / 'alternate.env').write_text('')
    for action in ('stop', 'down'):
        subprocess.run(starter + [action], cwd=fixture, env=starter_env, check=True, capture_output=True, text=True)
        subprocess.run(starter + [action], cwd=fixture,
                       env={**starter_env, 'ENV_FILE': str(fixture / 'alternate.env')},
                       check=True, capture_output=True, text=True)
    assert (fixture / 'actions').read_text().splitlines() == ['up', 'up', 'stop', 'stop', 'stop', 'stop',
                                                               'down', 'down', 'down', 'down']
    failed = subprocess.run(starter + ['stop'], cwd=fixture,
                            env={**starter_env, 'FAIL_ACTION': 'stop'}, capture_output=True, text=True)
    assert failed.returncode == 42, 'starter hid a lifecycle failure'
with tempfile.TemporaryDirectory(prefix='compose-empty-env-') as directory:
    empty_env = pathlib.Path(directory) / 'empty.env'
    empty_env.touch()
    subprocess.run([
        'docker', 'compose', '--env-file', str(empty_env), '-f', str(common),
        '-f', str(root / 'deploy/compose/docker-compose-rathena.yml'), 'config', '--quiet',
    ], cwd=root, env=environment, check=True, capture_output=True, text=True)
for engine in ('rathena', 'hercules'):
    result = subprocess.check_output([
        'docker', 'compose', '--env-file', str(root / '.env-tmpl'), '-f', str(common),
        '-f', str(root / f'deploy/compose/docker-compose-{engine}.yml'),
        'config', '--format', 'json', '--no-env-resolution',
    ], cwd=root, text=True, env=environment)
    config = json.loads(result)
    for service in config['services'].values():
        if 'env_file' in service:
            service['env_file'] = [str(root / '.env-tmpl')]
    result = subprocess.check_output([
        'docker', 'compose', '--env-file', str(root / '.env-tmpl'), '-f', '-',
        'config', '--format', 'json',
    ], cwd=root, input=json.dumps(config), text=True, env=environment)
    services = json.loads(result)['services']
    mounts = services['database']['volumes']
    assert any(volume['type'] == 'bind' and volume['source'] == str(root / 'deploy/compose/conf.d')
               and volume['target'] == '/etc/mariadb.conf.d' and volume['read_only'] for volume in mounts)
    if engine == 'hercules':
        continue
    assert 'SET_PRERENEWAL' not in services['remote']['build']['args']
    assert 'SET_PRERENEWAL' in services['remote']['environment']
    assert 'SET_PRERENEWAL' in services[engine]['build']['args']
    expected = {'database': database, 'remote': remote, 'robrowser': frontend, 'wsproxy': set(),
                engine: game,
                'ragnarok-login': game, 'ragnarok-char': game, 'ragnarok-map': game}
    for name, allowed in expected.items():
        actual = set(services[name].get('environment', {}))
        assert actual <= allowed, f'{engine}/{name}: unexpected environment names: {sorted(actual - allowed)}'
        if name in (engine, 'ragnarok-login', 'ragnarok-char', 'ragnarok-map'):
            assert {'MARIADB_PASSWORD', 'SET_INTERSRV_PASSWORD'} <= actual, f'{engine}/{name}: missing credentials'
            assert services[name]['environment']['MARIADB_PASSWORD'] == 'SomePassword', f'{engine}/{name}: incorrect database credential'
            assert services[name]['environment']['SET_INTERSRV_PASSWORD'] == 'p1', f'{engine}/{name}: incorrect interserver credential'
        build_args = services[name].get('build', {}).get('args', {})
        assert not any('PASSWORD' in key for key in build_args), f'{engine}/{name}: password in build arguments'
print('PASS Compose service environment boundaries')