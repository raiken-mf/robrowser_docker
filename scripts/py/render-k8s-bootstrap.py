#!/usr/bin/env python3
"""Render private bootstrap Secrets locally. Never contacts Kubernetes."""
import argparse
import base64
import json
import os
from pathlib import Path
import stat
import subprocess

ROOT = Path(__file__).resolve().parents[2]
REQUIRED = ('MARIADB_HOST', 'MARIADB_DATABASE', 'MARIADB_USER',
        'MARIADB_ROOT_PASSWORD', 'MARIADB_PASSWORD',
        'SET_INTERSRV_USER', 'SET_INTERSRV_PASSWORD')
OPTIONAL = {'K8S_NAMESPACE': 'ragnarok', 'SET_PRERENEWAL': '0', 'SET_NEW_ACCOUNT': 'yes',
            'SET_PINCODE_ENABLED': 'no', 'SET_MOTD': 'SORCERY!!!'}
KEYS = REQUIRED + tuple(OPTIONAL)


def read_environment(path, defaults=None):
    # .env is trusted shell configuration, as in the existing deployment scripts.
    code = 'import json,os; print(json.dumps({k:os.environ.get(k, "") for k in ' + repr(KEYS) + '}))'
    result = subprocess.run(
        ['bash', '-c', 'set -ae; source "$1" >/dev/null 2>&1; python3 -c "$2"',
         'bootstrap-env', str(path.resolve()), code],
           env={'PATH': os.environ['PATH'], **(defaults or {}),
               **{key: os.environ[key] for key in KEYS if key in os.environ}}, capture_output=True, text=True,
    )
    if result.returncode:
        raise ValueError('Cannot load the trusted environment file')
    return json.loads(result.stdout)


def render(env_file, output, installer_defaults=False):
    defaults = {'MARIADB_HOST': 'mariadb', 'MARIADB_DATABASE': 'ragnarok',
                'MARIADB_USER': 'ragnarok-user'} if installer_defaults else None
    values = read_environment(env_file, defaults)
    if env_file.name == '.env-tmpl':
        raise ValueError('Use the operator-owned local .env, not the repository template')
    for key in REQUIRED:
        if not values[key]:
            raise ValueError('Missing required setting: ' + key)
    for key, fallback in OPTIONAL.items():
        values[key] = values[key] or fallback
    namespace = values['K8S_NAMESPACE']
    output.mkdir(mode=0o700, parents=True, exist_ok=True)
    info = output.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
        raise ValueError('Output directory must be owned by this user and mode 0700')
    encode = lambda value: base64.b64encode(value.encode()).decode()
    def secret(name, data):
        return {'apiVersion': 'v1', 'kind': 'Secret', 'metadata': {'name': name, 'namespace': namespace},
                'type': 'Opaque', 'data': {key: encode(value) for key, value in data.items()}}
    user = {key: values[key] for key in ('MARIADB_HOST', 'MARIADB_DATABASE', 'MARIADB_USER',
                                       'MARIADB_PASSWORD', 'SET_INTERSRV_USER', 'SET_INTERSRV_PASSWORD')}
    user['password'] = values['MARIADB_PASSWORD']
    objects = [secret('mariadb-root-secret', {'password': values['MARIADB_ROOT_PASSWORD']}),
               secret('mariadb-user-secret', user)]
    config = {key: values[key] for key in ('MARIADB_HOST', 'MARIADB_DATABASE', 'MARIADB_USER',
                                         'SET_PRERENEWAL', 'SET_NEW_ACCOUNT', 'SET_PINCODE_ENABLED', 'SET_MOTD')}
    config.update(LOGIN_SERVER_HOST='ragnarok-login', CHAR_SERVER_HOST='ragnarok-char', MAP_SERVER_HOST='ragnarok-map')
    objects.append({'apiVersion': 'v1', 'kind': 'ConfigMap',
                    'metadata': {'name': 'rathena-config', 'namespace': namespace}, 'data': config})
    destination = output / 'bootstrap.json'
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW
    with os.fdopen(os.open(destination, flags, 0o600), 'w') as stream:
        json.dump({'apiVersion': 'v1', 'kind': 'List', 'items': objects}, stream, indent=2)
        stream.write('\n')
    print('Private bootstrap rendered locally; not applied: ' + str(destination))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--env-file', type=Path, default=ROOT / '.env')
    parser.add_argument('--output-dir', type=Path, required=True)
    parser.add_argument('--installer-defaults', action='store_true')
    args = parser.parse_args()
    try:
        render(args.env_file, args.output_dir, args.installer_defaults)
    except (OSError, ValueError) as error:
        parser.exit(1, str(error) + '\n')
