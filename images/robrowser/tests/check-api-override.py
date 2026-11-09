#!/usr/bin/env python3
"""Fail source-pin updates if the API bootstrap extraction needs rebasing."""
from pathlib import Path
import re
import sys
import textwrap

root=Path(__file__).resolve().parents[3]
source=Path(sys.argv[1]).read_text()
match=re.search(r'\t\t<script type="module">\n(.*?)\n\t\t</script>',source,re.S)
assert match, 'Pinned API inline module changed; review/rebase the repository override'
folder=root/'images/robrowser/repository_override/applications/api'
expected=source[:match.start()]+'\t\t<script type="module" src="./api-bootstrap.js"></script>'+source[match.end():]
assert (folder/'api.html').read_text()==expected, 'API HTML override differs beyond the module extraction; review against source pin'
assert (folder/'api-bootstrap.js').read_text()==textwrap.dedent(match.group(1))+'\n', 'API bootstrap behavior differs from pinned upstream'
print('PASS API override preserves pinned HTML and exact bootstrap logic; only script location changes')
