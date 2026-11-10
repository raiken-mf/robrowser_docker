#!/usr/bin/env python3
"""Verify declarative Dockerfile configs, templates, and build-arg validation."""
import os
import importlib.util
import json
import pathlib
import re
import subprocess
import sys
import tempfile

import yaml

ROOT = pathlib.Path(__file__).resolve().parents[2]

spec = importlib.util.spec_from_file_location("fork_cycle", ROOT / "scripts/py/check-fork-update-cycle.py")
cycle = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cycle)


def yaml_document(path):
    return yaml.safe_load(path.read_text())


template_values = {
    "NAMESPACE": "ragnarok", "MARIADB_HOST": "database", "MARIADB_DATABASE": "ragnarok",
    "MARIADB_USER": "ragnarok", "RATHENA_IMAGE_TAG": "stable", "REMOTE_IMAGE_TAG": "stable",
    "VITE_IMAGE_TAG": "stable", "WSPROXY_IMAGE_TAG": "stable", "PORT_HTTP": "30080",
    "PORT_FRONTEND": "30000", "PORT_WSPROXY": "30599",
}
templates = sorted((ROOT / "deploy/k8s/templates").glob("*.yaml"))
assert {template.name for template in templates} == {
    "mariadb.yaml", "namespace.yaml", "network-policy.yaml", "pvc-client-data.yaml",
    "pvc-helper.yaml", "rathena.yaml", "remote.yaml", "robrowser.yaml", "wsproxy.yaml",
}
for template in templates:
    base = ROOT / "deploy/k8s/base" / template.name
    assert base.is_file(), f"Missing base for {template.name}"
    rendered = re.sub(r"\$\{([A-Z_]+)\}", lambda match: template_values[match.group(1)], template.read_text())
    assert list(yaml.safe_load_all(rendered)) == list(yaml.safe_load_all(base.read_text())), f"Template drift: {template.name}"


def validate_matrix(matrix):
    assert sorted(matrix["image"]) == sorted(["remote", "robrowser", "rathena", "hercules", "wsproxy"])
    assert sorted(matrix["arch"]) == ["amd64", "arm64"]
    assert "exclude" not in matrix
    assert all(set(entry) == {"arch", "runner"} for entry in matrix["include"])
    assert sorted((entry["arch"], entry["runner"]) for entry in matrix["include"]) == [
        ("amd64", "ubuntu-latest"), ("arm64", "ubuntu-24.04-arm")]


def pull(author="automation", branch=cycle.BRANCH, state="open", created="2026-11-09T12:00:00Z", labels=(), body=None, closed=None):
    return {"user": {"login": author}, "head": {"ref": branch}, "base": {"ref": "main"},
            "state": state, "created_at": created, "closed_at": closed, "body": body,
            "labels": [{"name": label} for label in labels]}


version = pull(author="dependabot[bot]", branch="dependabot/dependencies")
security = pull(author="dependabot[bot]", branch="dependabot/npm/security", labels=["security"])
unknown_security = pull(author="dependabot[bot]", branch="dependabot/npm_and_yarn/security-123")
old_pin = pull(created="2026-11-01T12:00:00Z")
for pulls, when, expected in (
    ([], "2026-11-10T10:59:59Z", False), ([], "2026-11-10T11:00:00Z", True),
    ([version], "2026-11-10T12:00:00Z", False), ([security], "2026-11-10T12:00:00Z", True),
    ([unknown_security], "2026-11-10T12:00:00Z", False), ([pull(state="closed")], "2026-11-10T12:00:00Z", False),
    ([old_pin], "2026-11-10T12:00:00Z", True),
    ([pull(state="closed", created="2026-11-01T12:00:00Z", body="<!-- fork-pin-cycle:2026-11-09 -->")], "2026-11-10T12:00:00Z", False),
    ([pull(state="closed", created="2026-11-01T12:00:00Z", closed="2026-11-10T11:30:00Z")], "2026-11-10T12:00:00Z", False),
    ([pull(state="closed")], "2026-11-17T12:00:00Z", True),
    ([], "2026-07-07T09:59:59Z", False), ([], "2026-07-07T10:00:00Z", True),
    ([], "2026-03-31T10:00:00Z", True),
):
    assert (cycle.decision(pulls, cycle.timestamp(when)) is None) == expected, when

with tempfile.TemporaryDirectory(prefix="fork-cycle-") as directory:
    fixture = pathlib.Path(directory)
    gh = fixture / "gh"
    output = fixture / "output"
    gh.write_text('#!/bin/sh\n[ "$1" = api ] && [ "$2" = --paginate ] && [ "$3" = --slurp ] || exit 2\nprintf "%s" "$FIXTURE"\n')
    gh.chmod(0o700)
    environment = {**os.environ, "PATH": f"{fixture}{os.pathsep}{os.environ['PATH']}",
                   "GITHUB_REPOSITORY": "owner/repo", "GITHUB_OUTPUT": str(output)}
    helper = [sys.executable, str(ROOT / "scripts/py/check-fork-update-cycle.py")]
    for pages, expected_number in (([[], []], ""), ([[], [{**old_pin, "number": 42}]], "42")):
        output.write_text("")
        subprocess.run(helper, env={**environment, "FIXTURE": json.dumps(pages)}, check=True, capture_output=True)
        assert f"pr_number={expected_number}\n" in output.read_text()
    for invalid in ('{"message":"error"}', '[]', 'invalid'):
        assert subprocess.run(helper, env={**environment, "FIXTURE": invalid}, capture_output=True).returncode != 0
    for number in (0, False, "42"):
        pages = [[{**old_pin, "number": number}]]
        assert subprocess.run(helper, env={**environment, "FIXTURE": json.dumps(pages)}, capture_output=True).returncode != 0
    pages = [[{**old_pin, "number": 1}, {**old_pin, "number": 2}]]
    assert subprocess.run(helper, env={**environment, "FIXTURE": json.dumps(pages)}, capture_output=True).returncode != 0
    gh.write_text("#!/bin/sh\nexit 1\n")
    assert subprocess.run(helper, env=environment, capture_output=True).returncode != 0

with tempfile.TemporaryDirectory(prefix="rathena-scope-") as directory:
    fixture = pathlib.Path(directory)
    (fixture / "build").mkdir()
    pins = fixture / "build/dependencies.env"
    original = f"ROBROWSER_REF={'a' * 40}\nRATHENA_REF={'b' * 40}\n"
    pins.write_text(original)
    subprocess.run(["git", "init", "-q", directory], check=True)
    subprocess.run(["git", "add", "build/dependencies.env"], cwd=fixture, check=True)
    tree = subprocess.check_output(["git", "write-tree"], cwd=fixture, text=True).strip()
    scope = ["bash", str(ROOT / "scripts/sh/ci/check-rathena-pin-scope.sh")]
    for content, expected in ((original, True), (original.replace('a' * 40, 'c' * 40), True),
                              (original.replace('b' * 40, 'c' * 40), False), (original + "UNKNOWN_REF=new\n", False),
                              (original.replace('a' * 40, 'invalid'), False),
                              (original.replace('a' * 40, 'c' * 40) + "+RATHENA_REF=invalid\n", False)):
        pins.write_text(content)
        subprocess.run(["git", "add", "build/dependencies.env"], cwd=fixture, check=True)
        assert (subprocess.run(scope + [tree], cwd=fixture, capture_output=True).returncode == 0) == expected
    assert subprocess.run(scope + ["invalid-revision"], cwd=fixture, capture_output=True).returncode != 0

matrix = yaml_document(ROOT / ".github/workflows/pr-image-security.yml")["jobs"]["scan"]["strategy"]["matrix"]
validate_matrix(matrix)
for invalid in ({**matrix, "image": matrix["image"][1:]}, {**matrix, "image": matrix["image"] + ["other"]},
                {**matrix, "arch": ["amd64"]}, {**matrix, "arch": matrix["arch"] + ["other"]},
                {**matrix, "exclude": [{"image": "remote", "arch": "arm64"}]},
                {**matrix, "include": matrix["include"] + [{"image": "hercules", "arch": "amd64"}]}):
    try:
        validate_matrix(invalid)
    except AssertionError:
        continue
    raise AssertionError("Invalid matrix was accepted")
ci = yaml_document(ROOT / ".github/workflows/ci.yml")
validate = ci["jobs"]["validate"]
steps = validate["steps"]
assert validate["needs"] == "pr-image-security"
assert any('test "$SCAN_RESULT" = success' in step.get("run", "") for step in steps)
for name in ("Build RemoteClient for smoke test", "Build roBrowser frontend for smoke test", "Build wsProxy"):
    assert next(step for step in steps if step.get("name") == name)["if"] == "steps.scope.outputs.build == 'true'"
assert next(step for step in steps if step.get("name") == "Build rAthena on AMD64 (PR validation)")["if"] == "steps.scope.outputs.rathena == 'true'"
scope_run = next(step for step in steps if step.get("id") == "scope")["run"]
build_line = next(line for line in scope_run.splitlines() if "grep -Ev" in line and "grep -Eq" in line)
patterns = re.findall(r"grep -E[vq] '([^']+)'", build_line)
assert len(patterns) == 2
for paths, expected in ((["docs/gitops.md"], False), (["deploy/clusters/default/ragnarok-app.yaml"], False),
                        (["deploy/k8s/overlays/flux/kustomization.yaml"], False),
                        (["deploy/clusters/default/kustomization.yaml", "images/robrowser/Dockerfile"], True),
                        (["images/rathena/Dockerfile"], True), (["deploy/k8s/base/rathena.yaml"], True),
                        (["deploy/k8s/overlays/other/kustomization.yaml"], True)):
    filtered = subprocess.run(["grep", "-Ev", patterns[0]], input="\n".join(paths) + "\n", text=True, capture_output=True)
    assert filtered.returncode in (0, 1)
    matched = subprocess.run(["grep", "-Eq", patterns[1]], input=filtered.stdout, text=True)
    assert (matched.returncode == 0) == expected, paths
dependabot = yaml_document(ROOT / ".github/dependabot.yml")
assert dependabot["multi-ecosystem-groups"]["dependencies"]["schedule"] == {
    "interval": "weekly", "day": "monday", "time": "12:00", "timezone": "Europe/Berlin"}
updates = dependabot["updates"]
expected = [("github-actions", "/"), ("npm", "/images/robrowser"), ("npm", "/images/wsproxy")] + [
    ("docker", f"/images/{image}") for image in ("remote", "robrowser", "rathena", "wsproxy", "hercules")]
assert sorted((entry["package-ecosystem"], entry["directory"]) for entry in updates) == sorted(expected)
assert all(entry["patterns"] == ["*"] and entry["multi-ecosystem-group"] == "dependencies" for entry in updates)
assert all(entry["groups"] == {"security": {"applies-to": "security-updates", "patterns": ["*"]}}
           for entry in updates if entry["package-ecosystem"] in ("npm", "github-actions"))
updater = yaml_document(ROOT / ".github/workflows/dependency-update.yml")
assert updater[True] == {"workflow_dispatch": None, "schedule": [{"cron": "23 12 * * *"}]}
assert updater["concurrency"] == {"group": "upstream-dependency-update", "cancel-in-progress": False}
updater_steps = updater["jobs"]["update"]["steps"]
cycle_step = next(step for step in updater_steps if step.get("id") == "cycle")
update_step = next(step for step in updater_steps if step.get("id") == "update")
assert "scripts/py/check-fork-update-cycle.py" in cycle_step["run"] and update_step["if"] == "steps.cycle.outputs.ready == 'true'"
assert all(f"update_pin {name} " in update_step["run"] for name in ("ROBROWSER", "REMOTECLIENT", "RATHENA", "ROENGLISH"))
layout_step = next(step for step in updater_steps if step.get("name") == "Validate layouts at candidate revisions")
assert layout_step["if"] == "steps.update.outputs.changed == 'true'" and "scripts/sh/ci/check-upstream-layout.sh" in layout_step["run"]
pr_step = next(step for step in updater_steps if step.get("name") == "Create or update dependency update PR")
assert pr_step["if"] == "steps.update.outputs.changed == 'true'"
assert all(value in pr_step["run"] for value in ("scripts/py/check-fork-update-cycle.py", "branch='automation/upstream-dependency-update'", "gh pr create", "gh pr edit"))

publish = (ROOT / ".github/workflows/publish.yml").read_text()
assert "pushd deploy/k8s/overlays/flux" in publish
assert "git add deploy/k8s/overlays/flux/kustomization.yaml" in publish
assert "gh pr merge" not in (ROOT / ".github/workflows/dependency-update.yml").read_text()
assert not (ROOT / ".github/workflows/dependabot-automerge.yml").exists()
assert subprocess.run(["git", "check-ignore", "-q", "--no-index", "database/conf.d/local.cnf"], cwd=ROOT).returncode == 0
assert subprocess.run(["git", "check-ignore", "-q", "--no-index", "deploy/compose/conf.d/local.cnf"], cwd=ROOT).returncode == 0
assert "./conf.d:/etc/mariadb.conf.d:ro" in (ROOT / "deploy/compose/docker-compose-common.yml").read_text()
legacy = subprocess.run(["bash", str(ROOT / "scripts/sh/k8s/k8s-rathena.sh")], capture_output=True, text=True)
assert legacy.returncode != 0 and "disabled" in legacy.stderr

# 1. Ensure Dockerfiles and entrypoints do not regress to in-place sed/patch/heredoc config mutations.
for rel in (
    "images/remote/Dockerfile",
    "images/robrowser/Dockerfile",
    "images/rathena/Dockerfile",
    "images/wsproxy/Dockerfile",
):
    text = (ROOT / rel).read_text()
    assert not re.search(r"\bsed\s+-i\b", text), f"{rel} still contains sed -i"
    assert not re.search(r"\bpatch\b", text), f"{rel} still contains patch"
    assert ">>" not in text, f"{rel} still appends to files with >>"
    assert "<<" not in text, f"{rel} still uses inline heredocs"

rathena_entrypoint = (ROOT / "images/rathena/entrypoint.sh").read_text()
assert "<<" not in rathena_entrypoint, "images/rathena/entrypoint.sh still uses inline heredocs"
assert "envsubst" in rathena_entrypoint, "images/rathena/entrypoint.sh must use envsubst templates"

# 2. Verify rAthena compile-time and runtime templates with envsubst.
with tempfile.TemporaryDirectory(prefix="rathena-cfg-test-") as tmpdir:
    tmp = pathlib.Path(tmpdir)
    templates = ROOT / "images/rathena/templates"
    defines_out = tmp / "defines_pre.hpp"
    env = {
        **os.environ,
        "PACKET_OBFUSCATION_KEY1": "0x11223344",
        "PACKET_OBFUSCATION_KEY2": "0x55667788",
        "PACKET_OBFUSCATION_KEY3": "0x99AABBCC",
    }
    with defines_out.open("wb") as out_fp:
        subprocess.run(
            [
                "envsubst",
                "${PACKET_OBFUSCATION_KEY1} ${PACKET_OBFUSCATION_KEY2} ${PACKET_OBFUSCATION_KEY3}",
            ],
            stdin=(templates / "defines_pre.hpp.template").open("rb"),
            stdout=out_fp,
            env=env,
            check=True,
        )
    rendered_defines = defines_out.read_text()
    assert "#ifndef CONFIG_CUSTOM_DEFINES_PRE_HPP" in rendered_defines
    assert '#include "defines_pre_upstream.hpp"' in rendered_defines
    assert "#define PACKET_OBFUSCATION_KEY1 0x11223344" in rendered_defines
    assert "#define PACKET_OBFUSCATION_KEY2 0x55667788" in rendered_defines
    assert "#define PACKET_OBFUSCATION_KEY3 0x99AABBCC" in rendered_defines
    assert "${" not in rendered_defines
    (tmp / "defines_pre_upstream.hpp").write_text(
        "#define CONFIG_CUSTOM_DEFINES_PRE_HPP\n#define CUSTOM_SETTING 42\n"
        "#define PACKET_OBFUSCATION_KEY1 0x1\n"
    )
    preprocessed = subprocess.check_output(
        ["cc", "-E", "-dM", "-x", "c", str(defines_out)], text=True
    )
    assert "#define CUSTOM_SETTING 42" in preprocessed
    assert "#define PACKET_OBFUSCATION_KEY1 0x11223344" in preprocessed

    # Verify rAthena build-arg validator rejects invalid values and accepts valid ones.
    dockerfile = (ROOT / "images/rathena/Dockerfile").read_text()
    validator = dockerfile.split("RUN set -eu;", 1)[1].split("git clone", 1)[0]
    validator = "set -eu;" + validator.replace("\\\n", " ").rsplit("&&", 1)[0]
    valid_build_env = {
        **os.environ,
        "RATHENA_REF": "87d006378bf1b2cfba84781f9e9e3547be44ed46",
        "PACKETVER": "20211103",
        "SET_PRERENEWAL": "0",
        "PACKET_OBFUSCATION_KEY1": "0x6DED6DEE",
        "PACKET_OBFUSCATION_KEY2": "0x3DFD6AED",
        "PACKET_OBFUSCATION_KEY3": "0x0A3D5C0D",
    }
    subprocess.run(["sh", "-c", validator], env=valid_build_env, check=True)
    for value in ("", "2", "-1", "+1", " 1"):
        subprocess.run(["sh", "-c", validator], env={**valid_build_env, "SET_PRERENEWAL": value}, check=True)
    for bad_override in (
        {"RATHENA_REF": ""},
        {"PACKETVER": "2021-11-03"},
        {"PACKETVER": "20211103\n20211104"},
        {"SET_PRERENEWAL": "invalid"},
        {"PACKET_OBFUSCATION_KEY1": "6DED6DEE"},
        {"PACKET_OBFUSCATION_KEY2": "0x123456789"},
        {"PACKET_OBFUSCATION_KEY3": "0x1234; rm -rf /"},
        {"PACKET_OBFUSCATION_KEY1": "0x1234\n#define INJECTED 1"},
        {"PACKET_OBFUSCATION_KEY2": "0x1234\n0x5678"},
        {"PACKET_OBFUSCATION_KEY3": "0x1234\n"},
    ):
        res = subprocess.run(
            ["sh", "-c", validator],
            env={**valid_build_env, **bad_override},
            capture_output=True,
        )
        assert res.returncode != 0, f"Validator accepted invalid override: {bad_override}"

    # Verify rAthena entrypoint runtime config rendering preserves literal '$' in passwords.
    ragnarok_root = tmp / "ragnarok"
    (ragnarok_root / "conf" / "import").mkdir(parents=True)
    entrypoint_copy = tmp / "entrypoint.sh"
    entrypoint_text = rathena_entrypoint.replace(
        "/usr/local/share/rathena/templates", str(templates)
    ).replace("/opt/ragnarok", str(ragnarok_root))
    entrypoint_copy.write_text(entrypoint_text)
    entrypoint_copy.chmod(0o755)
    runtime_env = {
        **os.environ,
        "INIT_DB": "false",
        "MARIADB_HOST": "db.internal",
        "MARIADB_DATABASE": "ro_db",
        "MARIADB_USER": "ro_user",
        "MARIADB_PASSWORD": "p@ss$UNEXPANDED_SECRET",
        "LOGIN_SERVER_HOST": "login.internal",
        "CHAR_SERVER_HOST": "char.internal",
        "MAP_SERVER_HOST": "map.internal",
        "SET_INTERSRV_USER": "inter_u",
        "SET_INTERSRV_PASSWORD": "inter$UNEXPANDED_PASS",
        "SET_PINCODE_ENABLED": "yes",
        "SET_NEW_ACCOUNT": "no",
        "SET_MOTD": "Welcome to Ragnarok!",
        "UNEXPANDED_SECRET": "LEAKED",
        "UNEXPANDED_PASS": "LEAKED",
    }
    subprocess.run([str(entrypoint_copy), "true"], env=runtime_env, check=True)
    inter_conf = (ragnarok_root / "conf/import/inter_conf.txt").read_text()
    char_conf = (ragnarok_root / "conf/import/char_conf.txt").read_text()
    map_conf = (ragnarok_root / "conf/import/map_conf.txt").read_text()
    login_conf = (ragnarok_root / "conf/import/login_conf.txt").read_text()
    motd_txt = (ragnarok_root / "conf/motd.txt").read_text()
    assert "login_server_ip: db.internal\nlogin_server_db: ro_db\nlogin_server_id: ro_user\nlogin_server_pw: p@ss$UNEXPANDED_SECRET" in inter_conf
    assert "log_db_pw: p@ss$UNEXPANDED_SECRET" in inter_conf
    assert "LEAKED" not in inter_conf
    assert "userid: inter_u\npasswd: inter$UNEXPANDED_PASS\n\nlogin_ip: login.internal\nchar_ip: char.internal\n\npincode_enabled: yes\n" == char_conf
    assert "userid: inter_u\npasswd: inter$UNEXPANDED_PASS\n\nchar_ip: char.internal\nmap_ip: map.internal\n" == map_conf
    assert "new_account: no\n" == login_conf
    assert motd_txt == "Welcome to Ragnarok!"

    sql_hex = rathena_entrypoint.split("sql_hex() {", 1)[1].split("\n}", 1)[0]
    for value in ("quote'\\slash", "line\nbreak", "unicode-\u00e4"):
        encoded = subprocess.check_output(["sh", "-c", sql_hex, "sh", value], text=True)
        assert encoded == value.encode().hex()

print("PASS declarative Dockerfile configs, build-arg validation, and template rendering")
