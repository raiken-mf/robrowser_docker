#!/usr/bin/env python3
"""Resolve cache-busted iframe HTML and its Vite modules in an isolated image."""
import pathlib
from html.parser import HTMLParser
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

ROOT = pathlib.Path(__file__).resolve().parents[1]
class Modules(HTMLParser):
    def __init__(self):
        super().__init__()
        self.sources = []
    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == 'script' and attrs.get('type') == 'module':
            assert attrs.get('src'), 'Unexpected inline module in served iframe HTML'
            self.sources.append(attrs['src'])

name = 'api-module-test-' + uuid.uuid4().hex[:12]
try:
    subprocess.run(['docker', 'run', '-d', '--name', name, '-p', '127.0.0.1::3000',
                    sys.argv[1] if len(sys.argv)>1 else 'robrowser:ci'], check=True, stdout=subprocess.DEVNULL)
    address = subprocess.check_output(['docker', 'port', name, '3000'], text=True).strip()
    base = 'http://' + address
    def get(url):
        try:
            with urllib.request.urlopen(url, timeout=30) as response:
                assert response.status == 200, url
                return response.read().decode(), response.headers
        except urllib.error.HTTPError as error:
            body = error.read().decode(errors='replace')
            reason = 'No matching HTML proxy module' if 'No matching HTML proxy module' in body else error.reason
            raise AssertionError(f'HTTP {error.code} resolving {url}: {reason}') from error
    # Do not warm api.html without a query: that hides the original Vite cache bug.
    for attempt in range(60):
        try:
            get(base + '/@vite/client')
            break
        except Exception:
            if attempt == 59: raise
            time.sleep(1)
    for query in ('?0.138571#fixture', '?0.937421', ''):
        page = base + '/applications/api/api.html' + query
        html, _ = get(page)
        parser = Modules(); parser.feed(html)
        assert parser.sources, 'Iframe has no module scripts'
        for source in parser.sources:
            module_url = urllib.parse.urljoin(page, source)
            body, headers = get(module_url)
            assert 'javascript' in headers.get('Content-Type', ''), module_url
            assert 'No matching HTML proxy module' not in body
        print('PASS actual iframe HTML + Vite module resolution:', query or '(no query)', flush=True)
    engine, headers = get(base + '/src/main.js')
    assert engine and 'javascript' in headers.get('Content-Type', '')
    print('PASS actual dynamic engine entry transforms through Vite', flush=True)
    protocol = ROOT / 'scripts/check-api-handshake.cjs'
    subprocess.run(['docker', 'exec', '-i', name, 'node', '--experimental-vm-modules', '-'],
                   input=protocol.read_text(), text=True, check=True)
finally:
    subprocess.run(['docker', 'rm', '-f', name], check=True, stdout=subprocess.DEVNULL)
