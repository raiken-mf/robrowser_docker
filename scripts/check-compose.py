#!/usr/bin/env python3
"""Smoke-test the two web images on disposable Compose networks and loopback ports."""
import json
import pathlib
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
import uuid
root = pathlib.Path(__file__).resolve().parents[1]
def run(*args, **kw):
    return subprocess.run(args, check=True, text=True, **kw)
def output(*args):
    return subprocess.check_output(args, text=True)
config=json.loads(output('docker','compose','--env-file',str(root/'.env'),'-f',str(root/'deploy/compose/docker-compose-common.yml'),'config','--format','json'))
services={}
allowed={'HOST','PORT_HTTP','PORT_FRONTEND','PORT_WSPROXY','PACKETVER','PACKET_OBFUSCATION_KEY1','PACKET_OBFUSCATION_KEY2','PACKET_OBFUSCATION_KEY3','ROBROWSER_ROLE','GRF_ENCODING','PATH_MAPPING_ENABLED','CACHE_ENABLED','CACHE_MAX_FILES','CACHE_MAX_MEMORY_MB'}
for name,port,image in [('robrowser',8080,sys.argv[1] if len(sys.argv)>1 else 'robrowser:ci'),('vite',3000,sys.argv[2] if len(sys.argv)>2 else 'vite:ci')]:
 service=config['services'][name]
 for key in ('container_name','build','depends_on','tty'): service.pop(key,None)
 service['image']=image
 service['restart']='no'
 service['environment']={k:v for k,v in service.get('environment',{}).items() if k in allowed}
 service['ports']=[{'target':port,'published':'0','host_ip':'127.0.0.1','protocol':'tcp'}]
 services[name]=service
assert all(v.get('read_only') for v in services['robrowser']['volumes'])
config['services']=services
for network in config['networks'].values():
 network.pop('name',None)
for key in ('name','volumes','configs','secrets'): config.pop(key,None)
workdir=tempfile.TemporaryDirectory(prefix='robrowser-compose-')
path=pathlib.Path(workdir.name)/'compose.json'
path.write_text(json.dumps(config))
base=['docker','compose','-p','robrowser-test-'+uuid.uuid4().hex[:10],'-f',str(path)]
try:
 run(*base,'up','-d','--pull','never','--no-build')
 def request(name,port,path='/'):
  addr=output(*base,'port',name,str(port)).strip()
  url='http://'+addr+path
  for _ in range(60):
   try:
    with urllib.request.urlopen(url,timeout=5) as response: return response.read(), response.headers
   except Exception: time.sleep(1)
  raise RuntimeError(f'HTTP readiness failed for {name}')
 for name,port in [('robrowser',8080),('vite',3000)]:
  assert output(*base,'exec','-T',name,'id','-u').strip()=='1000'
  if name=='vite':
   assert output(*base,'exec','-T',name,'printenv','PORT_FRONTEND').strip()==services[name]['environment']['PORT_FRONTEND']
  content,headers=request(name,port)
  assert b'/remote/' in content
  print(f'PASS {name}: HTTP 200 and remote client configuration')
 content,_=request('vite',3000,'/src/Renderer/GR2/GR2ModelRenderer.js')
 assert b'granny-ro-js_wasm' in content and b'parseAnimated' in content and b'poseAt' in content
 print('PASS Vite GR2 module transforms')
 container=output(*base,'ps','-q','robrowser').strip()
 run('docker','cp',str(root/'scripts/check-php.php'),container+':/var/www/localhost/htdocs/ci-php-check.php')
 content,_=request('robrowser',8080,'/ci-php-check.php')
 assert b'PHP runtime security check passed' in content
 print(content.decode().strip())
 run(*base,'exec','-T','robrowser','sh','-c',
     'printf probe > /var/www/localhost/htdocs/.git-security-check')
 address=output(*base,'port','robrowser','8080').strip()
 for path,method,expected in [('/.git-security-check','GET',404),('/','TRACE',405)]:
  try:
   urllib.request.urlopen(urllib.request.Request('http://'+address+path,method=method),timeout=5)
   raise AssertionError(f'{method} {path} unexpectedly allowed')
  except urllib.error.HTTPError as error:
   assert error.code==expected,(method,error.code)
 print('PASS Git-path blocking and TRACE protection')
 run(*base,'exec','-T','robrowser','sh','-c','test -f /var/www/localhost/htdocs/put_files_to_override_here.txt && ! command -v node && ! command -v npm')
 run(*base,'exec','-T','vite','test','-f','/app/.gitkeep')
 run(*base,'exec','-T','robrowser','sh','-c',
     'test -f /var/www/localhost/htdocs/remote/data/add-data-folder-files-here.txt && '
     'test -f /var/www/localhost/htdocs/remote/System/add-system-folder-files-here.txt')
 run(*base,'exec','-T','vite','node','--input-type=module','-e',
     "const r = await fetch('http://robrowser:8080/remote/System/add-system-folder-files-here.txt', "
     "{headers: {Origin: 'http://vite:3000'}}); "
     "if (r.status !== 200 || r.headers.get('access-control-allow-origin') !== '*') process.exit(1);")
 resources=next(v['source'] for v in services['robrowser']['volumes']
                if v['target']=='/opt/client_files/resources')
 if (pathlib.Path(resources)/'DATA.INI').is_file():
  run(*base,'exec','-T','robrowser','php','-r',
      "$m=json_decode(file_get_contents('/var/www/localhost/htdocs/remote/path-mapping.json'),true,512,JSON_THROW_ON_ERROR); "
      "if (empty($m['grfs'])) exit(1);")
  print('PASS encoding mapping generated from mounted GRFs')
 print('PASS cross-container RemoteClient loose-file request and CORS')
 print('PASS repository_override payloads, loose-file mounts; Apache has no Node/npm')
finally:
 run(*base,'down','--remove-orphans')
 workdir.cleanup()
