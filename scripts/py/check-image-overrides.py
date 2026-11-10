#!/usr/bin/env python3
"""Build real per-image override fixtures without editing local override payloads."""
import os
import argparse
import pathlib
import shutil
import subprocess
import tempfile
import time
import uuid

ROOT = pathlib.Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--component', choices=('remote', 'robrowser'))
parser.add_argument('--no-build', action='store_true')
arguments = parser.parse_args()
pins = dict(
    line.split("=", 1)
    for line in (ROOT / "build/dependencies.env").read_text().splitlines()
    if line and not line.startswith("#")
)

with tempfile.TemporaryDirectory(prefix="remote-override-") as directory:
    context = pathlib.Path(directory)
    tracked = subprocess.check_output(['git', 'ls-files', '-z', '--', 'images'], cwd=ROOT).decode().split('\0')
    for relative in tracked:
        if not relative or (arguments.component and not relative.startswith('images/' + arguments.component + '/')):
            continue
        source = ROOT / relative
        destination = context / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, destination)
    shutil.copyfile(ROOT / ".dockerignore", context / ".dockerignore")
    for component, port, keys in (
        ("remote", 8080, ("REMOTECLIENT", "ROENGLISH")),
        ("robrowser", 3000, ("ROBROWSER",)),
    ):
        if arguments.component and arguments.component != component:
            continue
        fixture = context / "images" / component / "repository_override"
        (fixture / "boundary-override.txt").write_text(component)
        page = "index.html" if component == "remote" else "index.html.template"
        expected = f"custom {component} status"
        content = f"<!doctype html><p>{expected}</p>"
        if component == "robrowser":
            content += "<p>${HOST}:${PORT_HTTP}</p>"
        (fixture / page).write_text(content)
        image = "remote-override-test:" + component
        command = ["docker", "buildx", "build", "--load"] if os.environ.get("OVERRIDE_BUILDX") == "1" else ["docker", "build"]
        command.extend(["-f", f"images/{component}/Dockerfile", "-t", image])
        for key in keys:
            for suffix in ("REPOSITORY", "REF"):
                variable = f"{key}_{suffix}"
                command.extend(["--build-arg", f"{variable}={pins[variable]}"])
        command.append(".")
        if not arguments.no_build:
            subprocess.run(command, cwd=context, check=True)
        else:
            image = component + ':ci'
        name = "remote-override-" + uuid.uuid4().hex[:12]
        try:
            root = "/var/www/localhost/htdocs" if component == "remote" else "/app"
            subprocess.run([
                "docker", "create", "--name", name, "--network", "none",
                "-e", "HOST=override.example", "-e", "PORT_HTTP=31080", image,
            ], check=True)
            if arguments.no_build:
                for filename in ('boundary-override.txt', page):
                    subprocess.run(['docker', 'cp', str(fixture / filename), name + ':' + root + '/' + filename], check=True)
            subprocess.run(['docker', 'start', name], check=True)
            marker = subprocess.check_output([
                "docker", "exec", name, "cat", root + "/boundary-override.txt",
            ], text=True)
            assert marker == component, "Override payloads crossed image boundaries"
            if component == "remote":
                fetch = ["php", "-r", f"echo file_get_contents('http://127.0.0.1:{port}/');"]
            else:
                fetch = ["node", "--input-type=module", "-e",
                         f"console.log(await (await fetch('http://127.0.0.1:{port}/')).text())"]
            for attempt in range(30):
                result = subprocess.run(
                    ["docker", "exec", name, *fetch], capture_output=True, text=True,
                )
                if result.returncode == 0 and expected in result.stdout:
                    if component == "robrowser":
                        assert "override.example:31080" in result.stdout
                    break
                time.sleep(1)
            else:
                raise AssertionError(f"{component} override not served after startup")
            print(f"PASS {component}: independent marker and index override after startup")
        finally:
            subprocess.run(["docker", "rm", "-f", name], check=True)
