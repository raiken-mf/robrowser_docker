#!/usr/bin/env python3
"""Build real per-image override fixtures without editing local override payloads."""
import pathlib
import shutil
import subprocess
import tempfile
import time
import uuid

ROOT = pathlib.Path(__file__).resolve().parents[1]
pins = dict(
    line.split("=", 1)
    for line in (ROOT / "build/dependencies.env").read_text().splitlines()
    if line and not line.startswith("#")
)

with tempfile.TemporaryDirectory(prefix="robrowser-override-") as directory:
    context = pathlib.Path(directory)
    shutil.copytree(ROOT / "images", context / "images")
    shutil.copyfile(ROOT / ".dockerignore", context / ".dockerignore")
    for component, port, keys in (
        ("robrowser", 8080, ("REMOTECLIENT", "ROENGLISH")),
        ("vite", 3000, ("ROBROWSER",)),
    ):
        fixture = context / "images" / component / "repository_override"
        (fixture / "boundary-override.txt").write_text(component)
        page = "index.html" if component == "robrowser" else "index.html.template"
        expected = f"custom {component} status"
        content = f"<!doctype html><p>{expected}</p>"
        if component == "vite":
            content += "<p>${HOST}:${PORT_HTTP}</p>"
        (fixture / page).write_text(content)
        image = "robrowser-override-test:" + component
        command = ["docker", "build", "-f", f"images/{component}/Dockerfile", "-t", image]
        for key in keys:
            for suffix in ("REPOSITORY", "REF"):
                variable = f"{key}_{suffix}"
                command.extend(["--build-arg", f"{variable}={pins[variable]}"])
        command.append(".")
        subprocess.run(command, cwd=context, check=True)
        name = "robrowser-override-" + uuid.uuid4().hex[:12]
        try:
            subprocess.run([
                "docker", "run", "-d", "--name", name, "--network", "none",
                "-e", "HOST=override.example", "-e", "PORT_HTTP=31080", image,
            ], check=True)
            root = "/var/www/localhost/htdocs" if component == "robrowser" else "/app"
            marker = subprocess.check_output([
                "docker", "exec", name, "cat", root + "/boundary-override.txt",
            ], text=True)
            assert marker == component, "Override payloads crossed image boundaries"
            if component == "robrowser":
                fetch = ["php", "-r", f"echo file_get_contents('http://127.0.0.1:{port}/');"]
            else:
                fetch = ["node", "--input-type=module", "-e",
                         f"console.log(await (await fetch('http://127.0.0.1:{port}/')).text())"]
            for attempt in range(30):
                result = subprocess.run(
                    ["docker", "exec", name, *fetch], capture_output=True, text=True,
                )
                if result.returncode == 0 and expected in result.stdout:
                    if component == "vite":
                        assert "override.example:31080" in result.stdout
                    break
                time.sleep(1)
            else:
                raise AssertionError(f"{component} override not served after startup")
            print(f"PASS {component}: independent marker and index override after startup")
        finally:
            subprocess.run(["docker", "rm", "-f", name], check=True)
