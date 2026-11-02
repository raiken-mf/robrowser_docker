#!/usr/bin/env python3
"""Exercise bootstrap ordering/fail-closed behavior against a fake kubectl, never a cluster."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='k8s-all-check-') as directory:
    work=Path(directory)
    for name in ('scripts','deploy'):
        shutil.copytree(ROOT/name,work/name,ignore=shutil.ignore_patterns('__pycache__'))
    shutil.copyfile(ROOT/'.env-tmpl',work/'.env-tmpl')
    fixture=work/'operator.env'
    fixture.write_text('MARIADB_HOST=database\nMARIADB_DATABASE=ragnarok\nMARIADB_USER=ragnarok\nMARIADB_ROOT_PASSWORD=fixture-root-only\nMARIADB_PASSWORD=fixture-db-only\nSET_INTERSRV_USER=fixture-server\nSET_INTERSRV_PASSWORD=fixture-server-only\nSET_PRERENEWAL=0\nHOST=ci.invalid\nPORT_HTTP=32180\nPORT_FRONTEND=32100\nPORT_WSPROXY=32199\n')
    client=work/'client'
    for name in ('AI','BGM','data','System','resources'):(client/name).mkdir(parents=True)
    (client/'resources/DATA.INI').write_text('[Data]\n0=test.grf\n')
    (client/'resources/test.grf').write_bytes(b'x'*64)
    binary=work/'bin';binary.mkdir()
    fake=binary/'kubectl'
    fake.write_text('''#!/usr/bin/env python3
import json,os,pathlib,sys
args=sys.argv[1:]
with open(os.environ['MOCK_LOG'],'a') as f:f.write(json.dumps(args)+'\\n')
scenario=os.environ['MOCK_SCENARIO']
if 'get' in args:
 i=args.index('get');kind=args[i+1]
 if kind=='namespace':
  if scenario=='api-error':sys.exit(1)
  if scenario=='existing':print('namespace/ragnarok')
 elif kind=='deployments':
  print(json.dumps({'items':[{'metadata':{'name':n},'spec':{'replicas':1},'status':{'availableReplicas':1}} for n in ('mariadb-operator','mariadb-operator-webhook')]}))
 elif kind=='kustomizations':
  print(json.dumps({'items':[{'metadata':{'name':n},'spec':{'suspend':scenario!='active-flux'}} for n in ('flux-system','ragnarok-stack')]}))
 elif kind=='services':print('{"items":[]}')
 elif kind=='crd':print('crd/'+args[i+2])
elif 'create' in args:
 assert '--dry-run=client' in args
 data={a[len('--from-literal='):].split('=',1)[0]:a.split('=',2)[2] for a in args if a.startswith('--from-literal=')}
 print(json.dumps({'apiVersion':'v1','kind':'ConfigMap','metadata':{'name':'robrowser-config','namespace':'ragnarok'},'data':data}))
elif 'exec' in args:
 if 'stat' in args:
  relative=args[-1].removeprefix('/data/')
  print((pathlib.Path(os.environ['CLIENT_SOURCE_DIR'])/relative).stat().st_size)
 elif '-i' in args:sys.stdin.buffer.read()
''')
    fake.chmod(0o755)
    log=work/'calls.jsonl'
    def run(scenario,flags,success):
        log.write_text('')
        result=subprocess.run(['bash','scripts/k8s-all.sh',*flags],cwd=work,
            env=dict(os.environ,PATH=str(binary)+os.pathsep+os.environ['PATH'],ENV_FILE=str(fixture),
                     CLIENT_SOURCE_DIR=str(client),MOCK_LOG=str(log),MOCK_SCENARIO=scenario),
            capture_output=True,text=True)
        assert (result.returncode==0)==success, result.stdout+result.stderr
        assert not any(v in result.stdout+result.stderr+log.read_text() for v in ('fixture-root-only','fixture-db-only','fixture-server-only'))
        return [json.loads(line) for line in log.read_text().splitlines()]
    for scenario in ('api-error','active-flux','existing'):
        calls=run(scenario,['--apply'],False)
        assert not any(any(action in c for action in ('apply','delete','exec')) for c in calls),scenario
    calls=run('fresh',['--check'],True)
    assert not any(any(action in c for action in ('apply','delete','exec')) for c in calls)
    calls=run('fresh',['--apply'],True)
    applied=[Path(c[c.index('-f')+1]).name for c in calls if 'apply' in c]
    assert applied.index('namespace.yaml')<applied.index('bootstrap.json')<applied.index('mariadb.yaml')<applied.index('rathena.yaml')<applied.index('remote.yaml')<applied.index('robrowser.yaml')
    assert any('wait' in c and any(a.startswith('mariadbs.k8s.mariadb.com/') for a in c) for c in calls)
    assert any('exec' in c and 'deployment/ragnarok-login' in c for c in calls)
    assert not any('delete' in c and 'namespace' in c for c in calls)
    assert not any('resume' in c for c in calls)
print('PASS bootstrap protocol: check-only, API/Flux/existing-namespace aborts, full-stack ordering, DB check, no credential leaks/namespace deletion/Flux resume')
