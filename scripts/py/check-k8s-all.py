#!/usr/bin/env python3
"""Exercise bootstrap ordering/fail-closed behavior against a fake kubectl, never a cluster."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix='k8s-all-check-') as directory:
    work=Path(directory)
    for name in ('scripts','deploy','images/wsproxy/tests'):
        shutil.copytree(ROOT/name,work/name,ignore=shutil.ignore_patterns('__pycache__'))
    shutil.copyfile(ROOT/'.env-tmpl',work/'.env-tmpl')
    fixture=work/'operator.env'
    fixture.write_text('MARIADB_HOST=database\nMARIADB_DATABASE=ragnarok\nMARIADB_USER=ragnarok\nMARIADB_ROOT_PASSWORD=fixture-root-only\nMARIADB_PASSWORD=fixture-db-only\nSET_INTERSRV_USER=fixture-server\nSET_INTERSRV_PASSWORD=fixture-server-only\nSET_PRERENEWAL=0\nHOST=ci.invalid\nPORT_HTTP=32180\nPORT_FRONTEND=32100\nPORT_WSPROXY=32199\n')
    client=work/'client'
    for name in ('AI','BGM','data','System','resources'):(client/name).mkdir(parents=True)
    (client/'resources/DATA.INI').write_text('[Data]\n0=test.grf\n')
    (client/'resources/test.grf').write_bytes(b'x'*64)
    (client/'data/line\nbreak.txt').write_bytes(b'newline-filename-fixture')
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
    names=() if scenario=='missing-flux' else ('flux-system','ragnarok-stack','other-owner')
    print(json.dumps({'items':[{'metadata':{'name':n},'spec':{'suspend':scenario!='active-flux' and not (scenario=='other-active-flux' and n=='other-owner')}} for n in names]}))
 elif kind=='services':print('{"items":[]}')
 elif kind=='crd':print('crd/'+args[i+2])
elif 'create' in args:
 assert '--dry-run=client' in args
 data={a[len('--from-literal='):].split('=',1)[0]:a.split('=',2)[2] for a in args if a.startswith('--from-literal=')}
 print(json.dumps({'apiVersion':'v1','kind':'ConfigMap','metadata':{'name':'robrowser-config','namespace':'ragnarok'},'data':data}))
elif 'apply' in args and pathlib.Path(args[args.index('-f')+1]).name=='rathena.yaml':
 text=pathlib.Path(args[args.index('-f')+1]).read_text()
 assert text.count('image: ghcr.io/raiken-mf/rathena:sha-fixture')==3, 'rAthena deployments must use the checked image tag'
elif 'exec' in args:
 volume=pathlib.Path(os.environ['MOCK_VOLUME'])
 def target(value):return volume/value.removeprefix('/data/')
 if 'mktemp' in args:
  destination=target(args[-1].replace('XXXXXX','fixture'))
  destination.parent.mkdir(parents=True,exist_ok=True);destination.touch()
  print('/data/'+str(destination.relative_to(volume)))
 elif 'tee' in args:
  destination=target(args[-1]);destination.parent.mkdir(parents=True,exist_ok=True)
  payload=sys.stdin.buffer.read()
  destination.write_bytes(payload[:3] if scenario=='upload-interrupted' else payload)
  if scenario=='upload-interrupted':sys.exit(1)
 elif 'stat' in args:print(target(args[-1]).stat().st_size)
 elif 'mv' in args:target(args[-2]).replace(target(args[-1]))
 elif 'rm' in args:target(args[-1]).unlink(missing_ok=True)
 elif '-i' in args:sys.stdin.buffer.read()
''')
    fake.chmod(0o755)
    log=work/'calls.jsonl'
    volume=work/'volume';volume.mkdir()
    def run(scenario,flags,success,script='k8s-all.sh'):
        log.write_text('')
        result=subprocess.run(['bash','scripts/sh/k8s/'+script,*flags],cwd=work,
            env=dict(os.environ,PATH=str(binary)+os.pathsep+os.environ['PATH'],ENV_FILE=str(fixture),
                     CLIENT_SOURCE_DIR=str(client),MOCK_LOG=str(log),MOCK_SCENARIO=scenario,
                     MOCK_VOLUME=str(volume),
                     RATHENA_IMAGE_TAG='sha-fixture'),
            capture_output=True,text=True)
        assert (result.returncode==0)==success, result.stdout+result.stderr
        assert not any(v in result.stdout+result.stderr+log.read_text() for v in ('fixture-root-only','fixture-db-only','fixture-server-only'))
        return [json.loads(line) for line in log.read_text().splitlines()]
    for scenario in ('api-error','active-flux','other-active-flux','missing-flux','existing'):
        calls=run(scenario,['--apply'],False)
        assert not any(any(action in c for action in ('apply','delete','exec')) for c in calls),scenario
    calls=run('fresh',['--check'],True)
    assert not any(any(action in c for action in ('apply','delete','exec')) for c in calls)
    calls=run('fresh',['--apply'],True)
    assert (volume/'resources/test.grf').read_bytes()==b'x'*64, 'Successful upload lost content'
    assert (volume/'data/line\nbreak.txt').read_bytes()==b'newline-filename-fixture', 'Filename was split at newline'
    assert not list(volume.rglob('.upload-*')), 'Successful upload left temporary files'
    applied=[Path(c[c.index('-f')+1]).name for c in calls if 'apply' in c]
    assert applied.index('namespace.yaml')<applied.index('bootstrap.json')<applied.index('mariadb.yaml')<applied.index('rathena.yaml')<applied.index('remote.yaml')<applied.index('robrowser.yaml')
    assert any('wait' in c and any(a.startswith('mariadbs.k8s.mariadb.com/') for a in c) for c in calls)
    assert any('exec' in c and 'deployment/ragnarok-login' in c for c in calls)
    assert not any('delete' in c and 'namespace' in c for c in calls)
    assert not any('resume' in c for c in calls)
    destination=volume/'resources/test.grf'
    destination.write_bytes(b'previous-valid-fixture')
    run('upload-interrupted',['--apply'],False)
    assert destination.read_bytes()==b'previous-valid-fixture', 'Interrupted upload replaced existing asset'
    assert not list(volume.rglob('.upload-*')), 'Interrupted upload left temporary files'
    calls=run('active-flux',[],False,'k8s-robrowser.sh')
    assert not any(any(action in call for action in ('apply','delete','exec')) for call in calls), 'Web installer bypassed Flux guard'
print('PASS bootstrap protocol: check-only, API/Flux/existing-namespace aborts, full-stack ordering, DB check, no credential leaks/namespace deletion/Flux resume')
