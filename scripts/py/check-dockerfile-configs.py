#!/usr/bin/env python3
"""Verify declarative Dockerfile configs, templates, and build-arg validation."""
import os
import pathlib
import re
import shutil
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]

subprocess.run(["ruby", str(ROOT / "scripts/sh/ci/check-pr-image-matrix.rb")], check=True)
publish = (ROOT / ".github/workflows/publish.yml").read_text()
assert "for overlay in deploy/k8s/overlays/flux deploy/overlays/flux; do" in publish
assert "git add deploy/k8s/overlays/flux/kustomization.yaml deploy/overlays/flux/kustomization.yaml" in publish
assert "gh pr merge" not in (ROOT / ".github/workflows/dependency-update.yml").read_text()
assert not (ROOT / ".github/workflows/dependabot-automerge.yml").exists()
assert subprocess.run(["git", "check-ignore", "-q", "--no-index", "database/conf.d/local.cnf"], cwd=ROOT).returncode == 0
assert "../../database/conf.d:/etc/mariadb.conf.d:ro" in (ROOT / "deploy/compose/docker-compose-common.yml").read_text()
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
