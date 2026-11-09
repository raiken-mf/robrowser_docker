#!/usr/bin/env python3
"""Check Compose runtime environment boundaries using synthetic configuration."""
import json
import os
import pathlib
import subprocess
import tempfile
import uuid

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
with tempfile.TemporaryDirectory(prefix='compose-empty-env-') as directory:
    empty_env = pathlib.Path(directory) / 'empty.env'
    empty_env.touch()
    subprocess.run([
        'docker', 'compose', '--env-file', str(empty_env), '-f', str(common),
        '-f', str(root / 'deploy/compose/docker-compose-rathena.yml'), 'config', '--quiet',
    ], cwd=root, env=environment, check=True, capture_output=True, text=True)
    project = 'compose-lifecycle-' + uuid.uuid4().hex
    for action in ('stop', 'down'):
        subprocess.run([
            'docker', 'compose', '--env-file', str(empty_env), '-p', project, '-f', str(common),
            '-f', str(root / 'deploy/compose/docker-compose-rathena.yml'), action,
        ], cwd=root, env=environment, check=True, capture_output=True, text=True)
for engine in ('rathena',):
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