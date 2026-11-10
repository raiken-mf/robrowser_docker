#!/usr/bin/env python3
"""Exercise publishing with isolated GitHub, registry and workflow fixtures."""
import copy
import importlib.util
import json
import pathlib
import subprocess
import threading
import unittest
from unittest.mock import patch

import yaml

ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCE = ROOT / "scripts/py/publish-images.py"
BASE, FIRST, SECOND, THIRD = (str(number) * 40 for number in range(1, 5))
IMAGES = ("remote", "robrowser", "rathena", "wsproxy")
PATH = "deploy/k8s/overlays/flux/kustomization.yaml"


def record(image, source):
    return {"image": image, "source": source, "digest": "sha256:" + source[:1] * 64,
            "run": "10", "attempt": "1"}


class Fixture:
    def __init__(self):
        self.files = {"main": {PATH: self.overlay({image: BASE for image in IMAGES})}}
        self.prs = []
        self.registry = {}
        self.approved = {}
        self.writes = []
        self.fail = ""
        self.conflict = False
        self.lock = threading.Lock()
        for image in IMAGES:
            self.registry[f"ghcr.io/owner/{image}:sha-{BASE}"] = record(image, BASE)
            self.registry[f"ghcr.io/owner/{image}:stable"] = record(image, BASE)

    @staticmethod
    def overlay(pins):
        return yaml.safe_dump({"images": [{"name": f"ghcr.io/owner/{image}", "newTag": f"sha-{source}"}
                                           for image, source in pins.items()]})

    @staticmethod
    def ancestor(older, newer):
        return older in (BASE, FIRST, SECOND, THIRD) and newer in (BASE, FIRST, SECOND, THIRD) and older <= newer

    def main(self):
        return THIRD

    def read(self, branch, path):
        text = self.files.get(branch, {}).get(path)
        return (text, text) if text is not None else (None, None)

    def branch(self, branch):
        self.files.setdefault(branch, copy.deepcopy(self.files["main"]))

    def write(self, branch, path, text, previous, message):
        if self.fail == "journal" and path != PATH:
            raise RuntimeError("Injected journal failure")
        if self.fail == "update" and path == PATH:
            raise RuntimeError("Injected PR update interruption")
        if self.conflict and path == PATH:
            self.conflict = False
            self.files[branch]["human.txt"] = "preserved"
            raise publishing.Conflict("Injected compare-and-swap conflict")
        if self.read(branch, path)[1] != previous:
            raise publishing.Conflict("Changed file")
        self.files[branch][path] = text
        self.writes.append((branch, path))

    def pulls(self):
        return copy.deepcopy(self.prs)

    def pull(self, branch):
        if self.fail == "pr":
            raise RuntimeError("Injected PR creation failure")
        if not any(pull["branch"] == branch for pull in self.prs):
            self.prs.append({"branch": branch, "number": len(self.prs) + 1})

    def approval(self, image, source):
        return self.approved[(image, source)]

    def inspect(self, ref):
        return self.registry.get(ref)

    def promote(self, ref, approved):
        self.registry[ref] = copy.deepcopy(approved)
        if self.fail == "published":
            raise RuntimeError("Injected interruption after registry mutation")

    def pins(self):
        self.assert_one_pr()
        return {entry["name"].split("/")[-1]: entry["newTag"].removeprefix("sha-")
                for entry in yaml.safe_load(self.files[self.prs[0]["branch"]][PATH])["images"]}

    def assert_one_pr(self):
        assert len(self.prs) == 1, f"Expected one GitOps PR, found {len(self.prs)}"

    def run(self, source, images):
        records = [record(image, source) for image in images]
        for approved in records:
            self.approved[(approved["image"], source)] = approved
            self.registry[f"ghcr.io/owner/{approved['image']}:candidate-10-1"] = approved
        publishing.Publisher(self, self, self.ancestor, "owner", source, "10", "1").run(records)


class PublishingTests(unittest.TestCase):
    def test_executable_checkout_is_validated_source(self):
        workflow = yaml.safe_load((ROOT / ".github/workflows/publish.yml").read_text())
        checkout = workflow["jobs"]["promote-and-update-gitops"]["steps"][0]
        self.assertEqual(checkout["with"]["ref"], "${{ github.sha }}")

    def test_publication_only_uses_validated_main_push_context(self):
        ci = yaml.safe_load((ROOT / ".github/workflows/ci.yml").read_text())
        self.assertEqual(set(ci[True]), {"push", "pull_request"})
        self.assertEqual(ci[True]["push"]["branches"], ["main"])
        for filename in ("security.yml", "publish.yml"):
            workflow = yaml.safe_load((ROOT / ".github/workflows" / filename).read_text())
            self.assertEqual(workflow[True], {"workflow_call": None})
        security = ci["jobs"]["security"]
        publish = ci["jobs"]["publish"]
        self.assertEqual(security["uses"], "./.github/workflows/security.yml")
        self.assertEqual(publish["uses"], "./.github/workflows/publish.yml")
        self.assertEqual(security["needs"], "validate")
        self.assertEqual(publish["needs"], ["validate", "security"])
        self.assertEqual(security["if"], "always() && github.event_name == 'push' && github.ref == 'refs/heads/main' && needs.validate.result == 'success'")
        self.assertEqual(publish["if"], "always() && github.event_name == 'push' && github.ref == 'refs/heads/main' && needs.validate.result == 'success' && needs.security.result == 'success'")
        workflow = yaml.safe_load((ROOT / ".github/workflows/publish.yml").read_text())
        download = next(step for step in workflow["jobs"]["promote-and-update-gitops"]["steps"]
                        if step.get("name") == "Retrieve only security-approved release records")
        self.assertEqual(download["with"], {"pattern": "ready-*", "path": "ready", "merge-multiple": True})

    def test_default_branch_sha_cannot_promote_other_workflow_sha(self):
        fixture = Fixture()
        default_branch_sha, checked_workflow_sha = THIRD, FIRST
        approved = record("remote", checked_workflow_sha)
        fixture.registry["ghcr.io/owner/remote:candidate-10-1"] = approved
        before = copy.deepcopy(fixture.registry)
        with self.assertRaisesRegex(RuntimeError, "does not belong to this run"):
            publishing.Publisher(fixture, fixture, fixture.ancestor, "owner",
                                 default_branch_sha, "10", "1").run([approved])
        self.assertEqual(fixture.registry, before)
        self.assertFalse(fixture.writes)
        self.assertFalse(fixture.prs)
        fixture.run(checked_workflow_sha, ["remote"])
        self.assertEqual(fixture.pins()["remote"], checked_workflow_sha)

    def test_partial_releases(self):
        fixture = Fixture()
        fixture.run(FIRST, ["remote", "robrowser", "rathena"])
        fixture.run(SECOND, ["wsproxy"])
        self.assertEqual(fixture.pins(), {"remote": FIRST, "robrowser": FIRST, "rathena": FIRST, "wsproxy": SECOND})

    def test_parallel_publishers(self):
        workflow = yaml.safe_load((ROOT / ".github/workflows/publish.yml").read_text())
        self.assertEqual(workflow["jobs"]["promote-and-update-gitops"]["concurrency"],
                         {"group": "promote-main", "cancel-in-progress": False, "queue": "max"})
        ci = yaml.safe_load((ROOT / ".github/workflows/ci.yml").read_text())
        self.assertEqual(ci["concurrency"]["queue"], "max")
        fixture = Fixture()
        errors = []
        def scheduled(source):
            with fixture.lock:
                try:
                    fixture.run(source, ["wsproxy"])
                except Exception as error:
                    errors.append(error)
        threads = [threading.Thread(target=scheduled, args=(source,)) for source in (SECOND, FIRST)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join()
        self.assertFalse(errors, errors)
        self.assertEqual(fixture.pins()["wsproxy"], SECOND)
        self.assertEqual(fixture.registry["ghcr.io/owner/wsproxy:stable"]["source"], SECOND)

    def test_repeated_release(self):
        fixture = Fixture()
        fixture.run(FIRST, ["wsproxy"])
        writes = len(fixture.writes)
        fixture.run(FIRST, ["wsproxy"])
        fixture.assert_one_pr()
        self.assertEqual(len(fixture.writes), writes)

    def test_interrupted_publication(self):
        fixture = Fixture()
        fixture.fail = "published"
        with self.assertRaises(RuntimeError):
            fixture.run(FIRST, ["remote"])
        fixture.fail = ""
        fixture.run(SECOND, ["wsproxy"])
        self.assertEqual(fixture.pins()["remote"], FIRST)

    def test_newer_open_pr(self):
        fixture = Fixture()
        fixture.run(SECOND, ["wsproxy"])
        fixture.run(FIRST, ["wsproxy", "remote"])
        self.assertEqual(fixture.pins()["wsproxy"], SECOND)
        self.assertEqual(fixture.registry["ghcr.io/owner/wsproxy:stable"]["source"], SECOND)

    def test_interrupted_pr_update(self):
        for failure in ("update", "pr"):
            with self.subTest(failure=failure):
                fixture = Fixture()
                fixture.fail = failure
                with self.assertRaises(RuntimeError):
                    fixture.run(FIRST, ["remote"])
                fixture.fail = ""
                fixture.run(SECOND, ["wsproxy"])
                self.assertEqual(fixture.pins()["remote"], FIRST)

    def test_compare_and_swap_preserves_human_edits(self):
        fixture = Fixture()
        fixture.conflict = True
        fixture.run(FIRST, ["remote"])
        self.assertEqual(fixture.pins()["remote"], FIRST)
        self.assertEqual(fixture.files[fixture.prs[0]["branch"]]["human.txt"], "preserved")

    def test_failed_journal_prevents_publication(self):
        fixture = Fixture()
        before = copy.deepcopy(fixture.registry)
        fixture.fail = "journal"
        with self.assertRaises(RuntimeError):
            fixture.run(FIRST, ["remote"])
        self.assertEqual(fixture.registry["ghcr.io/owner/remote:stable"], before["ghcr.io/owner/remote:stable"])
        self.assertNotIn(f"ghcr.io/owner/remote:sha-{FIRST}", fixture.registry)

    def test_same_source_different_digest_keeps_immutable_tag(self):
        fixture = Fixture()
        fixture.run(FIRST, ["remote"])
        original = fixture.registry[f"ghcr.io/owner/remote:sha-{FIRST}"]["digest"]
        approved = {**record("remote", FIRST), "digest": "sha256:" + "a" * 64}
        fixture.registry["ghcr.io/owner/remote:candidate-11-1"] = approved
        publishing.Publisher(fixture, fixture, fixture.ancestor, "owner", FIRST, "11", "1").run(
            [{**approved, "run": "11"}])
        self.assertEqual(fixture.registry[f"ghcr.io/owner/remote:sha-{FIRST}"]["digest"], original)

    def test_newer_main_pin_is_not_reverted(self):
        fixture = Fixture()
        fixture.run(FIRST, ["remote"])
        fixture.files["main"][PATH] = fixture.overlay({image: SECOND for image in IMAGES})
        fixture.run(SECOND, ["wsproxy"])
        self.assertEqual(fixture.pins(), {image: SECOND for image in IMAGES})

    def test_existing_legacy_pr_is_reused(self):
        fixture = Fixture()
        legacy = "gitops/image-bump-" + FIRST
        fixture.prs = [{"branch": legacy, "number": 115}]
        fixture.files[legacy] = {PATH: fixture.overlay({image: FIRST if image == "remote" else BASE for image in IMAGES})}
        approved = record("remote", FIRST)
        fixture.approved[("remote", FIRST)] = approved
        fixture.registry[f"ghcr.io/owner/remote:sha-{FIRST}"] = approved
        fixture.run(SECOND, ["wsproxy"])
        self.assertEqual(fixture.pins()["remote"], FIRST)
        self.assertEqual(fixture.prs[0]["number"], 115)

    def test_competing_legacy_prs_fail_closed(self):
        fixture = Fixture()
        fixture.prs = [{"branch": "gitops/image-bump-old", "number": 1},
                       {"branch": "gitops/image-bump-new", "number": 2}]
        with self.assertRaises(RuntimeError):
            fixture.run(FIRST, ["remote"])
        self.assertNotIn(f"ghcr.io/owner/remote:sha-{FIRST}", fixture.registry)

    def test_legacy_published_without_pr_requires_security_proof(self):
        fixture = Fixture()
        approved = record("remote", FIRST)
        fixture.approved[("remote", FIRST)] = approved
        fixture.registry[f"ghcr.io/owner/remote:sha-{FIRST}"] = approved
        fixture.registry["ghcr.io/owner/remote:stable"] = approved
        fixture.run(SECOND, ["wsproxy"])
        self.assertEqual(fixture.pins()["remote"], FIRST)

    def test_unproven_legacy_publication_fails_closed(self):
        fixture = Fixture()
        fixture.registry["ghcr.io/owner/remote:stable"] = record("remote", FIRST)
        with self.assertRaises((RuntimeError, KeyError)):
            fixture.run(SECOND, ["wsproxy"])
        self.assertNotIn(f"ghcr.io/owner/wsproxy:sha-{SECOND}", fixture.registry)

    def test_digest_mismatch_does_not_update_gitops(self):
        fixture = Fixture()
        fixture.run(FIRST, ["remote"])
        fixture.registry[f"ghcr.io/owner/remote:sha-{FIRST}"]["digest"] = "sha256:" + "f" * 64
        before = fixture.pins()
        with self.assertRaises(RuntimeError):
            fixture.run(SECOND, ["wsproxy"])
        self.assertEqual(fixture.pins(), before)

    def test_recovery_without_current_records(self):
        fixture = Fixture()
        fixture.fail = "published"
        with self.assertRaises(RuntimeError):
            fixture.run(FIRST, ["remote"])
        fixture.fail = ""
        fixture.run(SECOND, [])
        self.assertEqual(fixture.pins()["remote"], FIRST)

    def test_http_adapter_compare_and_swap_and_permissions(self):
        github = publishing.GitHub("owner/repo")
        success = subprocess.CompletedProcess([], 0, '{}', '')
        with patch.object(publishing.subprocess, "run", return_value=success) as invoked:
            github.write("gitops/image-bump", PATH, "fixture", "old-blob", "fixture")
            payload = json.loads(invoked.call_args.kwargs["input"])
            self.assertEqual(payload["sha"], "old-blob")
            self.assertEqual(payload["branch"], "gitops/image-bump")
            self.assertIn("PUT", invoked.call_args.args[0])
        for code, exception in ((409, publishing.Conflict), (403, RuntimeError)):
            failure = subprocess.CompletedProcess([], 1, '', f'HTTP {code}')
            with patch.object(publishing.subprocess, "run", return_value=failure):
                with self.assertRaises(exception):
                    github.write("gitops/image-bump", PATH, "fixture", "old-blob", "fixture")

    def test_registry_adapter_exact_digest(self):
        registry = publishing.Registry()
        approved = record("remote", FIRST)
        with patch.object(publishing, "command", return_value="") as invoked:
            registry.promote(f"ghcr.io/owner/remote:sha-{FIRST}", approved)
            arguments = invoked.call_args.args[0]
            self.assertIn("--prefer-index=false", arguments)
            self.assertEqual(arguments[-1], "ghcr.io/owner/remote@" + approved["digest"])

    def test_unproven_pin_added_during_update_fails_closed(self):
        fixture = Fixture()
        fixture.run(FIRST, ["remote"])
        original_write = fixture.write
        def concurrent_write(branch, path, text, previous, message):
            if path == PATH:
                original_write(branch, path, fixture.overlay({image: SECOND if image == "rathena" else FIRST
                                                              for image in IMAGES}), previous, message)
                raise publishing.Conflict("Injected unproven concurrent pin")
            return original_write(branch, path, text, previous, message)
        fixture.write = concurrent_write
        with self.assertRaises((RuntimeError, KeyError)):
            fixture.run(SECOND, ["wsproxy"])


if __name__ == "__main__":
    specification = importlib.util.spec_from_file_location("publishing", SOURCE)
    publishing = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(publishing)
    unittest.main()