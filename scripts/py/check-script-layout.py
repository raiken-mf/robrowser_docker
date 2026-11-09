#!/usr/bin/env python3
"""Check script placement and obsolete references without reading private files."""
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
EXTENSIONS = {".sh", ".py", ".rb", ".php", ".js", ".cjs", ".mjs"}
OLD_PATH = re.compile(
    r"scripts/(?:sh/(?:check-[\w-]+\.sh|k8s-[\w-]+\.sh|render-web-manifests\.sh|start-compose\.sh)"
    r"|(?:rb/ci/check-[\w-]+|sh/ci/check-pr-image-matrix)\.rb|check-[\w-]+\.(?:py|php|sh|cjs)|render-k8s-bootstrap\.py|k8s-[\w-]+\.sh|render-web-manifests\.sh)"
)
OLD_FLUX_PATHS = ("clusters/" + "pi-cluster", "deploy/" + "overlays/flux")


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
        if "__pycache__" in parts or path.suffix in {".pyc", ".pyo"}:
            errors.append(f"Python cache artifact: {relative}")
            continue
        if parts[0] == "scripts" and (path.suffix in EXTENSIONS or path.stat().st_mode & 0o111):
            allowed = (
                len(parts) >= 3 and (
                    (parts[1] == "sh" and len(parts) >= 4 and parts[2] in {"k8s", "compose", "ci", "lib"} and path.suffix == ".sh")
                    or (parts[1] in {"py", "js", "php"} and path.suffix in {
                        "py": {".py"}, "js": {".js", ".cjs", ".mjs"}, "php": {".php"}
                    }[parts[1]])
                )
            )
            if not allowed:
                errors.append(f"Misplaced script: {relative}")
            try:
                first_line = path.open(encoding="utf-8").readline().strip()
            except (UnicodeError, OSError):
                first_line = ""
            if first_line.startswith("#!"):
                interpreter = first_line[2:].split()
                executable = Path(interpreter[0]).name if interpreter else ""
                if executable == "env" and len(interpreter) > 1:
                    executable = interpreter[1]
                language = re.sub(r"[0-9.]+$", "", executable)
                expected = {"sh": ".sh", "bash": ".sh", "dash": ".sh", "zsh": ".sh", "python": ".py", "ruby": ".rb", "node": path.suffix, "php": ".php"}.get(language)
                if expected and (path.suffix != expected or (language == "node" and path.suffix not in {".js", ".cjs", ".mjs"})):
                    errors.append(f"Script interpreter mismatch: {relative}")
        if relative == "scripts/py/check-script-layout.py" or parts[0] == "client":
            continue
        if path.suffix not in EXTENSIONS | {".md", ".yaml", ".yml"} and path.name not in {"Dockerfile", ".gitignore", ".dockerignore"}:
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except (UnicodeError, OSError):
            continue
        if OLD_PATH.search(text):
            errors.append(f"Obsolete script reference: {relative}")
        if parts[0] not in {"docs", "README.md", "CHANGELOG.md"} and any(old in text for old in OLD_FLUX_PATHS):
            errors.append(f"Obsolete Flux reference: {relative}")
    return errors


with tempfile.TemporaryDirectory(prefix="script-layout-") as directory:
    fixture = Path(directory)
    (fixture / "scripts").mkdir()
    (fixture / "scripts/misplaced.sh").write_text("#!/bin/sh\n")
    (fixture / "scripts/check-compose.py").write_text("pass\n")
    (fixture / "scripts/sh/ci").mkdir(parents=True)
    (fixture / "scripts/sh/ci/wrong.py").write_text("pass\n")
    (fixture / "scripts/sh/ci/wrong.rb").write_text("puts 'wrong'\n")
    (fixture / "scripts/rb/ci").mkdir(parents=True)
    (fixture / "scripts/rb/ci/right.rb").write_text("puts 'wrong'\n")
    (fixture / "scripts/py").mkdir()
    (fixture / "scripts/py/wrong.py").write_text("#!/usr/bin/env ruby\n")
    (fixture / "scripts/link.sh").symlink_to("misplaced.sh")
    (fixture / "example.md").write_text("scripts/sh/" + "check-old.sh\n")
    (fixture / "ruby-reference.md").write_text("scripts/sh/ci/" + "check-pr-image-matrix.rb\n")
    (fixture / ".github/workflows").mkdir(parents=True)
    (fixture / ".github/workflows/old.yml").write_text(OLD_FLUX_PATHS[0])
    (fixture / ".dockerignore").write_text(OLD_FLUX_PATHS[1])
    (fixture / "scripts/py/__pycache__").mkdir()
    (fixture / "scripts/py/__pycache__/old.pyc").write_bytes(b"")
    assert len(check(fixture, ["scripts/misplaced.sh", "scripts/check-compose.py", "scripts/sh/ci/wrong.py", "scripts/sh/ci/wrong.rb", "scripts/rb/ci/right.rb", "scripts/py/wrong.py", "scripts/link.sh", "example.md", "ruby-reference.md", ".github/workflows/old.yml", ".dockerignore", "scripts/py/__pycache__/old.pyc"])) == 12

paths = subprocess.check_output(
    ["git", "ls-files", "-co", "--exclude-standard", "-z"], cwd=ROOT
).decode().split("\0")
errors = check(ROOT, [path for path in paths if path])
if errors:
    raise SystemExit("\n".join(sorted(set(errors))))
print("PASS script layout and obsolete references")