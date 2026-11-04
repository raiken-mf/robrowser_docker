#!/usr/bin/env python3
"""Smoke-test the two web images on disposable Compose networks and loopback ports."""
import json
import http.client
import os
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
for name,port,image in [('remote',8080,sys.argv[1] if len(sys.argv)>1 else 'remote:ci'),('robrowser',3000,sys.argv[2] if len(sys.argv)>2 else 'robrowser:ci')]:
 service=config['services'][name]
 for key in ('container_name','build','depends_on','tty'): service.pop(key,None)
 service['image']=image
 service['restart']='no'
 service['environment']={k:v for k,v in service.get('environment',{}).items() if k in allowed}
 service['ports']=[{'target':port,'published':'0','host_ip':'127.0.0.1','protocol':'tcp'}]
 services[name]=service
if os.environ.get('CLIENT_TEST_ROOT'):
 for volume in services['remote']['volumes']:
  assert volume['type']=='bind' and volume['target']=='/opt/client_files'
  volume['source']=str(pathlib.Path(os.environ['CLIENT_TEST_ROOT']).resolve())
assert all(v.get('read_only') for v in services['remote']['volumes'])
config['services']=services
for network in config['networks'].values():
 network.pop('name',None)
for key in ('name','volumes','configs','secrets'): config.pop(key,None)
workdir=tempfile.TemporaryDirectory(prefix='remote-compose-')
path=pathlib.Path(workdir.name)/'compose.json'
path.write_text(json.dumps(config))
base=['docker','compose','-p','remote-test-'+uuid.uuid4().hex[:10],'-f',str(path)]
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
 for name,port in [('remote',8080),('robrowser',3000)]:
  assert output(*base,'exec','-T',name,'id','-u').strip()=='1000'
  if name=='robrowser':
   assert output(*base,'exec','-T',name,'printenv','PORT_FRONTEND').strip()==services[name]['environment']['PORT_FRONTEND']
  content,headers=request(name,port)
  assert b'/remote/' in content
  if name=='remote':
   assert b'RemoteClient service' in content and b'<script' not in content.lower()
  else:
   assert b'applications/api/api.js' in content
   assert b'customItemInfo: ["SystemEN/itemInfo.lua"]' in content
  print(f'PASS {name}: HTTP 200 and correct service page')
 content,_=request('robrowser',3000,'/applications/api/api.js')
 assert content, 'Frontend readiness module is empty'
 print('PASS frontend API readiness endpoint')
 content,_=request('robrowser',3000,'/src/Renderer/GR2/GR2ModelRenderer.js')
 assert b'granny-ro-js_wasm' in content and b'parseAnimated' in content and b'poseAt' in content
 print('PASS Vite GR2 module transforms')
 container=output(*base,'ps','-q','remote').strip()
 run('docker','cp',str(root/'scripts/check-php.php'),container+':/var/www/localhost/htdocs/ci-php-check.php')
 content,_=request('remote',8080,'/ci-php-check.php')
 assert b'PHP runtime security check passed' in content
 print(content.decode().strip())
 run(*base,'exec','-T','remote','sh','-c',
     'printf probe > /var/www/localhost/htdocs/.git-security-check')
 address=output(*base,'port','remote','8080').strip()
 for path,method,expected in [('/.git-security-check','GET',404),('/applications/api/api.js','GET',404),('/','TRACE',405)]:
  try:
   urllib.request.urlopen(urllib.request.Request('http://'+address+path,method=method),timeout=5)
   raise AssertionError(f'{method} {path} unexpectedly allowed')
  except urllib.error.HTTPError as error:
   assert error.code==expected,(method,error.code)
 print('PASS Git-path blocking and TRACE protection')
 for asset in ('/remote/SystemEN/itemInfo.lua', '/remote/SystemEN/LuaFiles514/itemInfo_f.lua',
               '/remote/SystemEN/Towninfo.lub', '/remote/SystemEN/OngoingQuests.lub'):
  content,_=request('remote',8080,asset)
  assert content, asset
 for asset in ('/remote/resources/DATA.INI', '/remote/configs.php', '/remote/data/%252e%252e/resources/DATA.INI'):
  try:
   urllib.request.urlopen('http://'+address+asset,timeout=5)
   raise AssertionError(f'{asset} unexpectedly allowed')
  except urllib.error.HTTPError as error:
   assert error.code==403,(asset,error.code)
 print('PASS ROEnglishRE static paths and private-file access controls')
 # A real loose AI utility wins. Otherwise Apache redirects to the stock GRF URL.
 client_root=pathlib.Path(next(v['source'] for v in services['remote']['volumes'] if v['target']=='/opt/client_files'))
 host,port=address.rsplit(':',1)
 connection=http.client.HTTPConnection(host,int(port),timeout=5)
 connection.request('GET','/remote/AI/Util.lua', headers={'Origin':'http://frontend.example'})
 response=connection.getresponse()
 if (client_root/'AI'/'Util.lua').is_file():
  assert response.status==200, response.status
 else:
  assert response.status==302 and response.getheader('Location')=='/remote/data/ai/util.lua', (response.status,response.getheader('Location'))
  assert response.getheader('Access-Control-Allow-Origin')=='*'
 response.read()
 connection.close()
 print('PASS AI utility path and loose-file precedence')
 # Exercise loose-file precedence independently of the operator's mounted files.
 fixture=pathlib.Path(workdir.name)/'loose-ai'
 fixture.mkdir(mode=0o755)
 pathlib.Path(workdir.name).chmod(0o755)
 (fixture/'Util.lua').write_bytes(b'-- loose AI fixture\n')
 loose=output('docker','run','-d','--rm','-p','127.0.0.1::8080',
              '--mount',f'type=bind,src={fixture},dst=/opt/client_files/AI,readonly',
              services['remote']['image']).strip()
 try:
  loose_address=output('docker','port',loose,'8080').strip()
  for _ in range(60):
   try:
    with urllib.request.urlopen('http://'+loose_address+'/remote/AI/Util.lua',timeout=2) as res:
     assert res.status==200 and res.read()==b'-- loose AI fixture\n'
    break
   except (urllib.error.URLError, ConnectionError, TimeoutError):
    time.sleep(1)
  else:
   raise RuntimeError('Loose AI fixture server failed to start')
 finally:
  run('docker','stop',loose,stdout=subprocess.DEVNULL)
 print('PASS loose AI fixture takes precedence over redirect')
 frontend=output(*base,'port','robrowser','3000').strip()
 front_host,front_port=frontend.rsplit(':',1)
 connection=http.client.HTTPConnection(front_host,int(front_port),timeout=10)
 connection.request('GET','/remote/AI/Util.lua', headers={'Host':'pi:30000'})
 response=connection.getresponse()
 if (client_root/'AI'/'Util.lua').is_file():
  assert response.status==200 and response.read()==(client_root/'AI'/'Util.lua').read_bytes()
 else:
  assert response.status==302 and response.getheader('Location')=='/remote/data/ai/util.lua'
  response.read()
 connection.close()
 for asset in ('/remote/SystemEN/itemInfo.lua', '/remote/SystemEN/OngoingQuests.lub',
               '/remote/System/PetEvolutionCln.lub'):
  via_frontend,_=request('robrowser',3000,asset)
  direct,_=request('remote',8080,asset)
  assert via_frontend==direct, asset
 for asset in ('/remote/resources/DATA.INI', '/remote/configs.php', '/remote/data/%252e%252e/resources/DATA.INI'):
  try:
   urllib.request.urlopen('http://'+frontend+asset,timeout=5)
   raise AssertionError(f'frontend unexpectedly allows {asset}')
  except urllib.error.HTTPError as error:
   assert error.code==403,(asset,error.code)
 print('PASS frontend proxy resources, relative AI redirect and private-file access controls')
 pet,_=request('remote',8080,'/remote/System/PetEvolutionCln.lub')
 if not (client_root/'System'/'PetEvolutionCln.lub').is_file():
  translated,_=request('remote',8080,'/remote/SystemEN/PetEvolution.lub')
  assert pet==translated and b'InsertEvolutionRecipeLGU' in pet
 print('PASS pet evolution loose-file precedence and translated fallback')
 # This nonexistent filesystem path must route through remote/.htaccess to PHP.
 # Missing GRFs produce a semantic 503 in clean CI, not a routing/PHP failure.
 try:
  response=urllib.request.urlopen('http://'+address+'/remote/api/health/simple',timeout=10)
 except urllib.error.HTTPError as error:
  response=error
 with response:
  assert response.code in (200,503), response.code
  health=json.loads(response.read())
 assert 'grfsLoaded' in health and health['status'] in ('ok','error')
 print('PASS /remote/ .htaccess fallback executes RemoteClient PHP')
 run(*base,'exec','-T','remote','sh','-c','test -f /var/www/localhost/htdocs/put_files_to_override_here.txt && ! command -v node && ! command -v npm')
 run(*base,'exec','-T','robrowser','test','-f','/app/.gitkeep')
 run(*base,'exec','-T','remote','sh','-c',
     'for file in src applications vite.config.js package.json package-lock.json index.html.template; do '
     'test ! -e "/var/www/localhost/htdocs/$file" || exit 1; done')
 run(*base,'exec','-T','robrowser','sh','-c','test -d /app/src && ! command -v php && ! command -v httpd')
 print('PASS image boundaries: frontend only in Vite; Apache contains no frontend artifacts')
 run(*base,'exec','-T','remote','sh','-c',
     'test -f /opt/client_files/data/add-data-folder-files-here.txt && '
     'test -f /opt/client_files/System/add-system-folder-files-here.txt')
 run(*base,'exec','-T','robrowser','node','--input-type=module','-e',
     "const r = await fetch('http://remote:8080/remote/System/add-system-folder-files-here.txt', "
     "{headers: {Origin: 'http://robrowser:3000'}}); "
     "if (r.status !== 200 || r.headers.get('access-control-allow-origin') !== '*') process.exit(1);")
 resources=pathlib.Path(next(v['source'] for v in services['remote']['volumes']
                           if v['target']=='/opt/client_files'))/'resources'
 if (pathlib.Path(resources)/'DATA.INI').is_file():
  run(*base,'exec','-T','remote','php','-r',
      "$m=json_decode(file_get_contents('/var/www/localhost/htdocs/remote/path-mapping.json'),true,512,JSON_THROW_ON_ERROR); "
      "if (empty($m['grfs'])) exit(1);")
  print('PASS encoding mapping generated from mounted GRFs')
  if not (client_root/'AI'/'Util.lua').is_file():
   direct,_=request('remote',8080,'/remote/data/ai/util.lua')
   via_frontend,_=request('robrowser',3000,'/remote/AI/Util.lua')
   assert via_frontend==direct and len(direct)>0
   print('PASS GRF AI utility through frontend and direct RemoteClient')
 print('PASS cross-container RemoteClient loose-file request and CORS')
 print('PASS repository_override payloads, loose-file mounts; Apache has no Node/npm')
finally:
 run(*base,'down','--remove-orphans')
 workdir.cleanup()
