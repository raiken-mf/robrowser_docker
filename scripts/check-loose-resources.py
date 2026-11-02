#!/usr/bin/env python3
"""Exercise the actual Apache/PHP image using isolated, synthetic client files."""
import http.client
import pathlib
import subprocess
import tempfile
import time
import urllib.parse
import uuid

image = __import__('sys').argv[1] if len(__import__('sys').argv) > 1 else 'remote:ci'
name = 'remote-resource-test-' + uuid.uuid4().hex[:12]
with tempfile.TemporaryDirectory(prefix='remote-resource-test-') as temporary:
    root = pathlib.Path(temporary)
    root.chmod(0o755)  # Container runs as UID 1000; CI runner may use another UID.
    for directory in ['System', 'SystemEN/LuaFiles514', 'data/nested', 'AI', 'BGM', 'resources']:
        (root / directory).mkdir(parents=True, exist_ok=True)
    fixtures = {'System/itemInfo.lua': b'original-system\n',
                'SystemEN/itemInfo.lua': b'translation-systemen\n',
                'SystemEN/LuaFiles514/itemInfo_f.lua': b'return {value = 37}\n',
                'SystemEN/LuaFiles514/probe-dofile.lua': b'return 5\n',
                'SystemEN/probe-main.lua': b'local x = require("SystemEN/LuaFiles514/itemInfo_f"); return x.value + dofile("SystemEN/LuaFiles514/probe-dofile.lua")\n',
                'data/nested/한글.lua': b'korean-bytes\n', 'AI/Util.lua': b'ai-content\n'}
    for path, data in fixtures.items(): (root / path).write_bytes(data)
    (root / 'data/escape.txt').symlink_to('/etc/passwd')
    command = ['docker', 'run', '-d', '--name', name, '-p', '127.0.0.1::8080',
               '-e', 'CLIENT_AUTOEXTRACT=false', '-v', f'{root}:/opt/client_files:ro', image]
    try:
        subprocess.run(command, check=True, stdout=subprocess.DEVNULL)
        port = int(subprocess.check_output(['docker', 'port', name, '8080'], text=True).strip().rsplit(':', 1)[1])
        def request(path, prefix='/remote/'):
            connection = http.client.HTTPConnection('127.0.0.1', port, timeout=20)
            connection.request('GET', prefix + path)
            response = connection.getresponse()
            result = response.status, response.read()
            connection.close()
            return result
        for attempt in range(30):
            try:
                if request('System/itemInfo.lua')[0] == 200: break
            except OSError: pass
            time.sleep(1)
        for path, expected in fixtures.items():
            status, body = request(urllib.parse.quote(path, safe='/'))
            assert (status, body) == (200, expected), (path, status, body[:80])
        baked = subprocess.check_output(['docker', 'exec', name, 'cat',
                                         '/var/www/localhost/htdocs/remote/SystemEN/LuaFiles514/itemInfo.lua'])
        assert request('SystemEN/LuaFiles514/itemInfo.lua') == (200, baked)
        # System wins conflicts; absent System paths use SystemEN without copying.
        assert request('System/LuaFiles514/itemInfo_f.lua') == (200, fixtures['SystemEN/LuaFiles514/itemInfo_f.lua'])
        for path in ['data/escape.txt', 'data/missing.txt', 'data/../configs.php',
                     'data/%2e%2e/configs.php', 'data/%252e%252e/configs.php',
                     'data/%2e%2e/%2e%2e/index.html']:
            status, _ = request(path)
            assert status in (403, 404), (path, status)
        status, _ = request('data/%2e%2e/configs.php', prefix='/r%65mote/')
        assert status in (403, 404), ('encoded remote prefix', status)
        php = r'''chdir("/var/www/localhost/htdocs/remote");
require "Debug.php"; require "Client.php"; $GLOBALS["CONFIGS"] = require "configs.php";
foreach (["data/nested/한글.lua" => true, "AI/Util.lua" => true,
          "data/escape.txt" => false, "data/../System/itemInfo.lua" => false,
          "data/%252e%252e/configs.php" => false, "/etc/passwd" => false] as $path => $expected) {
    if ((Client::getFile($path) !== false) !== $expected) { fwrite(STDERR, "FAIL $path\n"); exit(1); }
}
class FixtureGrf {
    public $loaded = true;
    function getFile($path, &$out) {
        if (strtolower(str_replace("\\", "/", $path)) === "system/luafiles514/iteminfo_f.lua") {
            $out = "grf-original"; return true;
        }
        return false;
    }
}
$property = new ReflectionProperty(Client::class, "grfs");
$property->setValue(null, [new FixtureGrf()]);
if (Client::getFile("System/LuaFiles514/itemInfo_f.lua") !== "grf-original") exit(1);'''
        subprocess.run(['docker', 'exec', name, 'php', '-r', php], check=True)
        print('PASS Apache/PHP and resolver: paths, precedence, Korean names, traversal and symlinks')
        repo = pathlib.Path(__file__).resolve().parent
        frontend = __import__('sys').argv[2] if len(__import__('sys').argv) > 2 else 'robrowser:ci'
        subprocess.run(['docker', 'run', '--rm', '--network', 'host',
                        '-e', f'LUA_HTTP_BASE=http://127.0.0.1:{port}/remote/',
                        '-v', f'{repo / "check-lua-http.test.js"}:/app/tests/core/loose-resource-http.test.js:ro',
                        '-v', f'{repo / "check-lua-vitest.config.mjs"}:/app/resource-vitest.config.mjs:ro',
                        '--entrypoint', 'sh', frontend, '-c',
                        'cd /app && ./node_modules/.bin/vitest run --config resource-vitest.config.mjs tests/core/loose-resource-http.test.js'], check=True)
    finally:
        subprocess.run(['docker', 'stop', name], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run(['docker', 'rm', name], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
