#!/usr/bin/env python3
"""Exercise the workflow scope interface with isolated Git trees."""
import os
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest

import yaml

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('ci_scope', ROOT / 'scripts/py/ci-scope.py')
scope = importlib.util.module_from_spec(spec)
spec.loader.exec_module(scope)


def fixture_scope(changes, invalid_base=False, rename=False, pull_request=False):
    with tempfile.TemporaryDirectory(prefix='scope-matrix-') as directory:
        fixture = Path(directory)
        environment = {**os.environ, 'GIT_AUTHOR_NAME': 'Fixture', 'GIT_AUTHOR_EMAIL': 'fixture@example.test',
                       'GIT_COMMITTER_NAME': 'Fixture', 'GIT_COMMITTER_EMAIL': 'fixture@example.test'}
        subprocess.run(['git', 'init', '-q', directory], check=True)
        baseline_pins = (ROOT / 'build/dependencies.env').read_text()
        for filename, content in {'build/dependencies.env': baseline_pins,
                                  'images/remote/httpd.conf': 'fixture\n',
                                  'docs/old.md': 'fixture\n'}.items():
            target = fixture / filename
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(content)
        def commit(parent=None):
            subprocess.run(['git', 'add', '-A'], cwd=fixture, check=True)
            tree = subprocess.check_output(['git', 'write-tree'], cwd=fixture, text=True).strip()
            arguments = ['git', 'commit-tree', tree] + (['-p', parent] if parent else [])
            return subprocess.check_output(arguments, cwd=fixture, env=environment,
                                           input='fixture\n', text=True).strip()
        base = commit()
        for filename, content in changes.items():
            target = fixture / filename
            if content is None:
                target.unlink()
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text(content.replace('$PINS', baseline_pins))
        if rename:
            (fixture / 'images/remote/httpd.conf').rename(fixture / 'docs/renamed.md')
        head = commit(base)
        result = subprocess.run([os.sys.executable, str(ROOT / 'scripts/py/ci-scope.py'),
                                 'invalid' if invalid_base else base, head,
                                 *(['--pull-request'] if pull_request else [])], cwd=fixture,
                                capture_output=True, text=True, check=True)
        return dict(line.split('=') for line in result.stdout.splitlines())


class ScopeTests(unittest.TestCase):
    def test_fixture_loader_never_builds_and_rejects_uncertain_metadata(self):
        with tempfile.TemporaryDirectory(prefix='scope-loader-') as directory:
            fixture = Path(directory)
            log = fixture / 'calls'
            docker = fixture / 'docker'
            docker.write_text('''#!/bin/sh
printf '%s\\n' "$*" >> "$CALL_LOG"
case "$*" in
  *'--format'*) printf '{"digest":"%s"}\\n' "$FIXTURE_DIGEST" ;;
  *'--raw'*) printf '{"annotations":{"org.opencontainers.image.revision":"%s"}}\\n' "$FIXTURE_REVISION" ;;
  pull*|tag*) exit 0 ;;
  *) exit 1 ;;
esac
''')
            docker.chmod(0o700)
            revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
            environment = {**os.environ, 'PATH': str(fixture) + os.pathsep + os.environ['PATH'],
                           'CALL_LOG': str(log), 'OWNER': 'fixture', 'WEB_TESTS': 'true',
                           'FIXTURE_DIGEST': 'sha256:' + 'a' * 64, 'FIXTURE_REVISION': revision}
            command = ['bash', str(ROOT / 'scripts/sh/ci/load-ci-images.sh')]
            result = subprocess.run(command, cwd=ROOT, env=environment, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(sum(line.startswith('pull ') for line in log.read_text().splitlines()), 2)
            self.assertNotIn('buildx build', log.read_text())
            log.write_text('')
            result = subprocess.run(command, cwd=ROOT, env={**environment, 'REMOTE_BUILD': 'true',
                                                           'ROBROWSER_BUILD': 'true'}, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(log.read_text(), '')
            for overrides in ({'FIXTURE_DIGEST': 'invalid'}, {'FIXTURE_REVISION': 'f' * 40}):
                result = subprocess.run(command, cwd=ROOT, env={**environment, **overrides},
                                        capture_output=True, text=True)
                self.assertNotEqual(result.returncode, 0)

    def test_single_image_and_script_matrix(self):
        cases = (
            ('docs/new.md', set()),
            ('deploy/k8s/base/remote.yaml', set()),
            ('scripts/py/check-compose.py', set()),
            ('scripts/sh/ci/check-rathena-pin-scope.sh', set()),
            ('images/remote/tests/check-php.php', set()),
            ('images/remote/httpd.conf', {'remote'}),
            ('images/remote/repository_override/name\nwith-newline.txt', {'remote'}),
            ('images/robrowser/package-lock.json', {'robrowser'}),
            ('images/rathena/templates/config.txt', {'rathena'}),
            ('images/hercules/docker-entrypoint.sh', {'hercules'}),
            ('images/wsproxy/compat.js', {'wsproxy'}),
            ('.dockerignore', {'remote', 'robrowser'}),
            ('images/rathena/.dockerignore', {'rathena'}),
        )
        for path, expected in cases:
            with self.subTest(path=path):
                flags = fixture_scope({path: 'changed\n'})
                self.assertEqual({image for image in scope.IMAGES if flags[image] == 'true'}, expected)

    def test_semantic_dependency_pins(self):
        original = (ROOT / 'build/dependencies.env').read_text()
        for image, prefixes in scope.PINS.items():
            for prefix in prefixes:
                for suffix in ('REF', 'REPOSITORY'):
                    key = prefix + '_' + suffix
                    old = next(line.split('=', 1)[1] for line in original.splitlines() if line.startswith(key + '='))
                    new = 'a' * 40 if suffix == 'REF' else 'https://github.com/fixture/source.git'
                    flags = fixture_scope({'build/dependencies.env': original.replace(key + '=' + old, key + '=' + new)})
                    self.assertEqual({name for name in scope.IMAGES if flags[name] == 'true'}, {image}, key)
        flags = fixture_scope({'build/dependencies.env': '$PINS\n# comment only\n'})
        self.assertEqual(flags['build'], 'false')

    def test_rename_delete_and_multiple_changes(self):
        for changes, renamed, expected in (({}, True, {'remote'}),
                                           ({'images/remote/httpd.conf': None}, False, {'remote'}),
                                           ({'images/wsproxy/compat.js': 'new', 'images/robrowser/vite.config.js': 'new'}, False,
                                            {'wsproxy', 'robrowser'})):
            for pull_request in (False, True):
                flags = fixture_scope(changes, rename=renamed, pull_request=pull_request)
                self.assertEqual({image for image in scope.IMAGES if flags[image] == 'true'}, expected)

    def test_scope_errors_run_all_checks(self):
        for changes, invalid in (({}, True), ({'build/dependencies.env': 'invalid'}, False),
                                 ({'build/dependencies.env': None}, False)):
            flags = fixture_scope(changes, invalid_base=invalid)
            self.assertTrue(all(value == 'true' for value in flags.values()))

    def test_validation_dependencies(self):
        for path, required, excluded in (
            ('scripts/py/check-xerj-monitor.py', ('xerj', 'layout'), ('platform', 'bootstrap', 'compose')),
            ('scripts/py/check-compose.py', ('integration', 'layout'), ('upstream', 'platform', 'bootstrap')),
            ('deploy/clusters/default/ragnarok-app.yaml', ('platform', 'bootstrap'), ('compose', 'upstream')),
            ('scripts/sh/k8s/k8s-setup.sh', ('setup', 'bootstrap'), ('compose', 'upstream')),
            ('docs/new.md', (), scope.GROUPS),
        ):
            flags = fixture_scope({path: 'changed'})
            for group in required:
                self.assertEqual(flags[group], 'true', (path, group))
            for group in excluded:
                self.assertEqual(flags[group], 'false', (path, group))

    def test_copy_inputs_are_explicitly_covered(self):
        for image in scope.IMAGES:
            dockerfile = ROOT / f'images/{image}/Dockerfile'
            for line in dockerfile.read_text().splitlines():
                if not line.startswith('COPY '):
                    continue
                if any(token.startswith('--from=') for token in line.split()[1:-1]):
                    continue
                sources = [token for token in line.split()[1:-1] if not token.startswith('--')]
                for source in sources:
                    source = source.removeprefix(f'images/{image}/')
                    self.assertTrue(scope.matches(source.rstrip('/'), tuple(name.rstrip('/') for name in scope.INPUTS[image])),
                                    (image, source))

    def test_workflow_change_does_not_build_images(self):
        workflow = yaml.safe_load((ROOT / ".github/workflows/ci.yml").read_text())
        command = next(step["run"] for step in workflow["jobs"]["validate"]["steps"]
                       if step.get("id") == "scope")
        with tempfile.TemporaryDirectory(prefix="ci-scope-") as directory:
            fixture = Path(directory)
            subprocess.run(["git", "init", "-q", directory], check=True)
            environment = {**os.environ, "GIT_AUTHOR_NAME": "Fixture",
                           "GIT_AUTHOR_EMAIL": "fixture@example.test",
                           "GIT_COMMITTER_NAME": "Fixture",
                           "GIT_COMMITTER_EMAIL": "fixture@example.test"}
            tree = subprocess.check_output(["git", "write-tree"], cwd=fixture, text=True).strip()
            base = subprocess.check_output(["git", "commit-tree", tree], cwd=fixture,
                                           env=environment, input="base\n", text=True).strip()
            target = fixture / ".github/workflows/ci.yml"
            target.parent.mkdir(parents=True)
            target.write_text("fixture\n")
            subprocess.run(["git", "add", "."], cwd=fixture, check=True)
            tree = subprocess.check_output(["git", "write-tree"], cwd=fixture, text=True).strip()
            head = subprocess.check_output(["git", "commit-tree", tree, "-p", base],
                                           cwd=fixture, env=environment, input="change\n", text=True).strip()
            output = fixture / "output"
            (fixture / "scripts/py").mkdir(parents=True)
            (fixture / "scripts/py/ci-scope.py").write_bytes((ROOT / "scripts/py/ci-scope.py").read_bytes())
            result = subprocess.run(["bash", "-c", command], cwd=fixture,
                                    env={**environment, "BASE_SHA": base, "HEAD_SHA": head,
                                         "GITHUB_EVENT_NAME": "push", "GITHUB_OUTPUT": str(output)},
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("build=false\n", output.read_text())


if __name__ == "__main__":
    unittest.main()