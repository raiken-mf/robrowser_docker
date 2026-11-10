#!/usr/bin/env python3
"""Resolve image inputs and validation dependencies without executing pin files."""
import argparse
from pathlib import Path
import re
import subprocess
import sys

IMAGES = ("remote", "robrowser", "rathena", "hercules", "wsproxy")
INPUTS = {
    "remote": ("security.ini", "httpd.conf", "apache-access.conf", "index.html",
               "repository_override/", "roenglish-generate.php", "roenglish-startup.php", "entrypoint.sh"),
    "robrowser": ("package.json", "package-lock.json", "vite.config.js", "index.html.template",
                  "repository_override/", "entrypoint.sh"),
    "rathena": ("templates/", "repository_override/", "entrypoint.sh"),
    "hercules": ("repository_override/", "docker-entrypoint.sh"),
    "wsproxy": ("package.json", "package-lock.json", "compat.js"),
}
PINS = {"remote": ("REMOTECLIENT", "ROENGLISH"), "robrowser": ("ROBROWSER",),
        "rathena": ("RATHENA",), "hercules": ("HERCULES",), "wsproxy": ()}
GROUPS = ("contracts", "layout", "xerj", "upstream", "platform", "web_manifests",
          "setup", "bootstrap", "compose", "integration", "boundaries", "overrides",
          "remote_tests", "robrowser_tests", "rathena_tests", "wsproxy_tests")


def matches(path, patterns):
    return any(path.startswith(pattern) if pattern.endswith("/") else path == pattern
               for pattern in patterns)


def git(*arguments):
    return subprocess.check_output(["git", "--no-pager", *arguments], stderr=subprocess.PIPE)


def pins_at(revision):
    values = {}
    allowed = {f"{prefix}_{suffix}" for prefixes in PINS.values() for prefix in prefixes
               for suffix in ("REPOSITORY", "REF")}
    for line in git("show", f"{revision}:build/dependencies.env").decode().splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        key, separator, value = line.partition("=")
        if not separator or key not in allowed or key in values:
            raise ValueError("Invalid dependency declaration")
        if key.endswith("_REF") and not re.fullmatch("[0-9a-f]{40}", value):
            raise ValueError("Invalid source revision")
        if key.endswith("_REPOSITORY") and not re.fullmatch(r"https://github\.com/[\w.-]+/[\w.-]+\.git", value):
            raise ValueError("Invalid source repository")
        values[key] = value
    if values.keys() != allowed:
        raise ValueError("Incomplete dependency declarations")
    return values


def resolve(base, head, pull_request=False):
    flags = dict.fromkeys((*IMAGES, *GROUPS, "build"), False)
    try:
        if not all(re.fullmatch("[0-9a-f]{40}", revision or "") for revision in (base, head)):
            raise ValueError("Missing or invalid comparison revision")
        git("cat-file", "-e", f"{head}^{{commit}}")
        git("cat-file", "-e", f"{base}^{{commit}}")
        if pull_request:
            base = git("merge-base", base, head).decode().strip()
        paths = [path.decode("utf-8", "surrogateescape") for path in
                 git("diff", "--no-ext-diff", "--no-textconv", "--no-renames", "--name-only", "-z",
                     base, head, "--").split(b"\0") if path]
        changed_pins = set()
        if "build/dependencies.env" in paths:
            old, new = pins_at(base), pins_at(head)
            changed_pins = {key for key in old if old[key] != new[key]}
        for image in IMAGES:
            prefix = f"images/{image}/"
            inputs = (prefix + "Dockerfile", prefix + ".dockerignore",
                      prefix + "Dockerfile.dockerignore", *(prefix + name for name in INPUTS[image]))
            flags[image] = any(matches(path, inputs) for path in paths)
            flags[image] |= any(key.startswith(tuple(f"{pin}_" for pin in PINS[image]))
                                for key in changed_pins) if PINS[image] else False
            if image in ("remote", "robrowser") and ".dockerignore" in paths:
                flags[image] = True
        dependencies = {
            "contracts": (".github/", "build/", "images/", "deploy/k8s/", "deploy/compose/",
                          "scripts/py/ci-scope.py", "scripts/py/check-ci-scope.py",
                          "scripts/py/check-dockerfile-configs.py", "scripts/py/check-publishing.py",
                          "scripts/py/publish-images.py", "scripts/py/check-fork-update-cycle.py",
                          "scripts/sh/ci/check-rathena-pin-scope.sh", ".dockerignore", ".env-tmpl"),
            "layout": ("scripts/", "images/", "deploy/", ".github/", ".gitignore", ".dockerignore"),
            "xerj": ("scripts/py/check-xerj-monitor.py", "scripts/sh/ci/check-xerj-updates.sh",
                     ".github/workflows/xerj-reference-monitor.yml", "docs/best-practices.md"),
            "upstream": ("scripts/sh/ci/check-upstream-layout.sh", "images/robrowser/tests/check-api-override.py"),
            "platform": ("deploy/k8s/", "deploy/clusters/", "scripts/sh/ci/check-platform-config.sh"),
            "web_manifests": ("deploy/k8s/templates/", "scripts/sh/k8s/k8s-render-web-manifests.sh",
                              "scripts/sh/lib/", ".env-tmpl"),
            "setup": ("scripts/sh/k8s/k8s-setup", "scripts/sh/ci/check-k8s-setup.sh"),
            "bootstrap": ("scripts/sh/k8s/", "scripts/sh/lib/", "scripts/py/render-k8s-bootstrap.py",
                          "scripts/py/check-k8s-bootstrap.py", "scripts/py/check-k8s-all.py",
                          "deploy/", "images/wsproxy/tests/", ".env-tmpl"),
            "compose": ("deploy/compose/", "scripts/sh/compose/", "start.sh",
                        "scripts/py/check-compose-contract.py", ".env-tmpl", "build/dependencies.env"),
            "integration": ("deploy/compose/", "scripts/py/check-compose.py", "images/remote/tests/check-php.php",
                            "scripts/sh/ci/load-ci-images.sh", ".env-tmpl"),
            "boundaries": ("scripts/sh/ci/check-image-boundaries.sh",),
            "overrides": ("scripts/py/check-image-overrides.py",),
            "remote_tests": ("images/remote/tests/",),
            "robrowser_tests": ("images/robrowser/tests/",),
            "rathena_tests": ("images/rathena/tests/",),
            "wsproxy_tests": ("images/wsproxy/tests/",),
        }
        for group, patterns in dependencies.items():
            flags[group] = any(matches(path, patterns) or
                               (group == "setup" and path.startswith("scripts/sh/k8s/k8s-setup"))
                               for path in paths)
        flags["upstream"] |= bool(changed_pins)
        if any(path in (".github/workflows/ci.yml", "scripts/py/ci-scope.py", "scripts/py/check-ci-scope.py")
               for path in paths):
            for group in GROUPS:
                flags[group] = True
        for image in ("remote", "robrowser", "rathena", "wsproxy"):
            flags[f"{image}_tests"] |= flags[image]
        web = flags["remote"] or flags["robrowser"]
        flags["integration"] |= web
        flags["boundaries"] |= web
        flags["build"] = any(flags[image] for image in IMAGES)
        return flags
    except (subprocess.CalledProcessError, OSError, ValueError, UnicodeError) as error:
        print(f"Scope unavailable ({type(error).__name__}); running all checks", file=sys.stderr)
        return dict.fromkeys(flags, True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("base")
    parser.add_argument("head")
    parser.add_argument("--pull-request", action="store_true")
    parser.add_argument("--image", choices=IMAGES)
    arguments = parser.parse_args()
    flags = resolve(arguments.base, arguments.head, arguments.pull_request)
    if arguments.image:
        print(f"changed={str(flags[arguments.image]).lower()}")
    else:
        for key, value in flags.items():
            print(f"{key}={str(value).lower()}")


if __name__ == "__main__":
    main()