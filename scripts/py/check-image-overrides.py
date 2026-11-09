#!/usr/bin/env python3
"""Build real per-image override fixtures without editing local override payloads."""
import os
import pathlib
import shutil
import subprocess
import tempfile
import time
import uuid

ROOT = pathlib.Path(__file__).resolve().parents[2]
pins = dict(
    line.split("=", 1)
    for line in (ROOT / "build/dependencies.env").read_text().splitlines()
    if line and not line.startswith("#")
)

with tempfile.TemporaryDirectory(prefix="remote-override-") as directory:
    context = pathlib.Path(directory)
    shutil.copytree(ROOT / "images", context / "images")
    shutil.copyfile(ROOT / ".dockerignore", context / ".dockerignore")
    for component, port, keys in (
        ("remote", 8080, ("REMOTECLIENT", "ROENGLISH")),
        ("robrowser", 3000, ("ROBROWSER",)),
    ):
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
        subprocess.run(command, cwd=context, check=True)
        name = "remote-override-" + uuid.uuid4().hex[:12]
        try:
            subprocess.run([
                "docker", "run", "-d", "--name", name, "--network", "none",
                "-e", "HOST=override.example", "-e", "PORT_HTTP=31080", image,
            ], check=True)
            root = "/var/www/localhost/htdocs" if component == "remote" else "/app"
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
