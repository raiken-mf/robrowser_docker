#!/usr/bin/env python3
"""Check script placement and obsolete references without reading private files."""
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
WRAPPERS = {f"scripts/{name}.sh" for name in (
    "k8s-all", "k8s-client-data", "k8s-mariadb", "k8s-rathena",
    "k8s-robrowser", "render-web-manifests",
)} | {"scripts/check-wsproxy.cjs"}
EXTENSIONS = {".sh", ".py", ".php", ".js", ".cjs", ".mjs"}
OLD_PATH = re.compile(
    r"scripts/(?:sh/(?:check-[\w-]+\.sh|k8s-[\w-]+\.sh|render-web-manifests\.sh|start-compose\.sh)"
    r"|check-[\w-]+\.(?:py|php|sh|cjs)|render-k8s-bootstrap\.py)"
)


def check(root, paths):
    errors = []
    for relative in paths:
        path = root / relative
        parts = Path(relative).parts
        if parts[0] == "scripts" and path.is_symlink():
            errors.append(f"Script symlink: {relative}")
            continue
        if not path.is_file():
            continue
        if parts[0] == "scripts" and (path.suffix in EXTENSIONS or path.stat().st_mode & 0o111):
            allowed = relative in WRAPPERS or (
                len(parts) >= 3 and (
                    (parts[1] == "sh" and len(parts) >= 4 and parts[2] in {"k8s", "compose", "ci", "lib"} and path.suffix == ".sh")
                    or (parts[1] in {"py", "js", "php"} and path.suffix in {
                        "py": {".py"}, "js": {".js", ".cjs", ".mjs"}, "php": {".php"}
                    }[parts[1]])
                )
            )
            if not allowed:
                errors.append(f"Misplaced script: {relative}")
        if relative == "scripts/py/check-script-layout.py" or relative in WRAPPERS or parts[0] == "client":
            continue
        if path.suffix not in EXTENSIONS | {".md", ".yaml", ".yml"} and path.name != "Dockerfile":
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except (UnicodeError, OSError):
            continue
        if any(match.group() not in WRAPPERS for match in OLD_PATH.finditer(text)):
            errors.append(f"Obsolete script reference: {relative}")
    return errors


with tempfile.TemporaryDirectory(prefix="script-layout-") as directory:
    fixture = Path(directory)
    (fixture / "scripts").mkdir()
    (fixture / "scripts/misplaced.sh").write_text("#!/bin/sh\n")
    (fixture / "scripts/check-compose.py").write_text("pass\n")
    (fixture / "scripts/sh/ci").mkdir(parents=True)
    (fixture / "scripts/sh/ci/wrong.py").write_text("pass\n")
    (fixture / "scripts/link.sh").symlink_to("misplaced.sh")
    (fixture / "example.md").write_text("scripts/sh/" + "check-old.sh\n")
    assert len(check(fixture, ["scripts/misplaced.sh", "scripts/check-compose.py", "scripts/sh/ci/wrong.py", "scripts/link.sh", "example.md"])) == 5

paths = subprocess.check_output(
    ["git", "ls-files", "-co", "--exclude-standard", "-z"], cwd=ROOT
).decode().split("\0")
errors = check(ROOT, [path for path in paths if path])
if errors:
    raise SystemExit("\n".join(sorted(set(errors))))
print("PASS script layout and obsolete references")