#!/usr/bin/env python3
"""Exercise the XERJ monitor with local Git and a fake GitHub CLI."""
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
MONITOR = ROOT / 'scripts/sh/ci/check-xerj-updates.sh'

with tempfile.TemporaryDirectory(prefix='xerj-monitor-') as directory:
    work = Path(directory)
    upstream = work / 'upstream'
    upstream.mkdir()
    def git(*args):
        return subprocess.check_output(['git', '-C', str(upstream), *args], text=True).strip()
    git('init', '-q', '-b', 'main')
    git('config', 'user.name', 'Fixture')
    git('config', 'user.email', 'fixture@example.invalid')
    (upstream / 'AGENTS.md').write_text('Initial reference\n')
    git('add', 'AGENTS.md')
    git('commit', '-qm', 'Initial fixture')
    baseline = git('rev-parse', 'HEAD')
    baseline_file = work / 'baseline'
    baseline_file.write_text(baseline + '\n')
    binary = work / 'bin'
    binary.mkdir()
    fake = binary / 'gh'
    fake.write_text('''#!/usr/bin/env bash
set -euo pipefail
printf '%s\\n' "$*" >> "$MOCK_LOG"
if [[ "$1" == api ]]; then
  [[ -z "${MOCK_FAIL:-}" || "$*" != *"$MOCK_FAIL"* ]] || exit 1
  if [[ "$*" == *'--method PUT'* ]]; then
    while [[ $# -gt 0 ]]; do
      if [[ "$1" == --input ]]; then
        jq -e '.message == "chore: update XERJ reference review" and .branch == "automation/xerj-reference-review" and (.content | @base64d | startswith("Reviewed: "))' "$2" >/dev/null
        break
      fi
      shift
    done
    exit 0
  fi
  case "$*" in
    *'/pulls?'*) printf '%s' "${MOCK_ISSUES:-}" ;;
    *'/git/matching-refs/'*) [[ -z "${MOCK_ISSUES:-}${MOCK_FOREIGN:-}" ]] || printf '%s\\n' 'refs/heads/automation/xerj-reference-review' ;;
    *'/git/trees/'*) : ;;
    *'/git/ref/heads/'*) printf '%040d\\n' 1 ;;
  esac
elif [[ "$1 $2" == 'pr create' || "$1 $2" == 'pr edit' ]]; then
  while [[ $# -gt 0 ]]; do
    if [[ "$1" == --body-file ]]; then cp "$2" "$MOCK_BODY"; break; fi
    shift
  done
fi
''')
    fake.chmod(0o755)
    log = work / 'calls'
    body = work / 'body'
    env = dict(os.environ, PATH=str(binary) + os.pathsep + os.environ['PATH'],
               XERJ_BASELINE_FILE=str(baseline_file), XERJ_REPOSITORY=str(upstream),
               GITHUB_REPOSITORY='fixture/project', MOCK_LOG=str(log), MOCK_BODY=str(body))
    def run(issues='', success=True, **extra):
        log.write_text('')
        try:
            result = subprocess.run(['bash', str(MONITOR)], env=dict(env, MOCK_ISSUES=issues, **extra),
                      capture_output=True, text=True, timeout=10)
        except subprocess.TimeoutExpired as error:
          raise AssertionError(f'Monitor timed out: {error.stderr!r}') from error
        assert (result.returncode == 0) == success, result.stdout + result.stderr
        return log.read_text()
    assert not run()
    (upstream / 'unrelated.txt').write_text('Unrelated\n')
    git('add', 'unrelated.txt')
    git('commit', '-qm', 'Unrelated change')
    assert not run()
    (upstream / 'AGENTS.md').write_text('Run regression tests\nProtect secrets\n```\n@everyone\n')
    git('add', 'AGENTS.md')
    git('commit', '-qm', 'Reference change')
    head = git('rev-parse', 'HEAD')
    assert 'pr create' in run()
    assert baseline in body.read_text() and head in body.read_text()
    assert 'AGENTS.md' in body.read_text() and '/compare/' in body.read_text()
    assert '```diff' in body.read_text() and 'focused regression command' in body.read_text()
    assert 'credentials are stored' in body.read_text() and 'Run regression tests' in body.read_text()
    assert '+` ` `' in body.read_text() and '@ everyone' in body.read_text()
    assert baseline_file.read_text().strip() == baseline
    calls = run('42\n')
    assert 'pr edit 42' in calls and 'pr create' not in calls
    assert 'PUT' in calls and 'PATCH' not in calls
    assert 'PUT' not in run(success=False, MOCK_FOREIGN='1')
    assert 'pr create' not in run(success=False, MOCK_FAIL='repos/fixture/project/git/matching-refs/heads/automation/xerj-reference-review')
    for name in ('CONTRIBUTING.md', 'SECURITY.md', 'docs/SECURITY_MODEL.md', '.github/AI_CONTRIBUTIONS.md'):
      path = upstream / name
      path.parent.mkdir(parents=True, exist_ok=True)
      path.write_text('Reference change\n')
      git('add', name)
      git('commit', '-qm', 'Reference change')
      assert 'pr create' in run()
      assert name in body.read_text()
      assert 'No catalog rule matched added lines' in body.read_text()
    (upstream / 'AGENTS.md').write_text('Large reference\n' + 'x' * 30000 + '\n')
    git('add', 'AGENTS.md')
    git('commit', '-qm', 'Large reference change')
    assert 'pr create' in run()
    assert len(body.read_bytes()) < 30000
    git('checkout', '-q', '--orphan', 'rewritten')
    git('commit', '-qm', 'Rewritten history')
    git('branch', '-f', 'main', 'HEAD')
    assert not run(success=False)
    baseline_file.write_text('invalid\n')
    assert not run(success=False)
    print('PASS XERJ monitor: unchanged, unrelated, PR creation/update, rewritten and invalid-baseline cases')