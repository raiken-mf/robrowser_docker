#!/usr/bin/env python3
"""Promote approved images and reconcile one GitOps proposal under the CI lock."""
import base64
import json
import os
import pathlib
import re
import subprocess
import tempfile

import yaml

IMAGES = ("remote", "robrowser", "rathena", "wsproxy")
OVERLAY = "deploy/k8s/overlays/flux/kustomization.yaml"
JOURNAL_BRANCH = "automation/image-release-state"
JOURNAL = "image-releases.json"
PR_BRANCH = "gitops/image-bump"


class Conflict(RuntimeError):
    pass


def command(arguments, **options):
    result = subprocess.run(arguments, capture_output=True, text=True, **options)
    if result.returncode:
        raise RuntimeError(f"Command failed: {arguments[0]} {arguments[1]}")
    return result.stdout.strip()


def ancestor(older, newer):
    result = subprocess.run(["git", "merge-base", "--is-ancestor", older, newer], capture_output=True)
    if result.returncode not in (0, 1):
        raise RuntimeError("Missing source ancestry; refusing publication")
    return result.returncode == 0


def validate(approved):
    if set(approved) != {"image", "digest", "source", "run", "attempt"}:
        raise RuntimeError("Invalid release record fields")
    if approved["image"] not in IMAGES or not re.fullmatch(r"sha256:[0-9a-f]{64}", approved["digest"]):
        raise RuntimeError("Invalid release image or digest")
    if not re.fullmatch(r"[0-9a-f]{40}", approved["source"]):
        raise RuntimeError("Invalid release source")
    if not all(re.fullmatch(r"[1-9][0-9]*", approved[field]) for field in ("run", "attempt")):
        raise RuntimeError("Invalid release run")


class GitHub:
    def __init__(self, repository):
        if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository):
            raise RuntimeError("Invalid repository")
        self.repository = repository
        self.endpoint = f"repos/{repository}"

    def api(self, endpoint, payload=None, missing=False):
        arguments = ["gh", "api", self.endpoint + endpoint]
        if payload is not None:
            arguments += ["--method", "POST", "--input", "-"]
        result = subprocess.run(arguments, input=json.dumps(payload) if payload is not None else None,
                                capture_output=True, text=True)
        if result.returncode:
            if missing and "HTTP 404" in result.stderr:
                return None
            if "HTTP 409" in result.stderr or "HTTP 422" in result.stderr:
                raise Conflict("GitHub compare-and-swap conflict")
            raise RuntimeError("GitHub API failed; no permission bypass attempted")
        return json.loads(result.stdout) if result.stdout.strip() else None

    def pages(self, endpoint):
        result = command(["gh", "api", "--paginate", "--slurp", self.endpoint + endpoint])
        return json.loads(result)

    def main(self):
        return self.api("/git/ref/heads/main")["object"]["sha"]

    def branch(self, branch):
        if self.api("/git/ref/heads/" + branch, missing=True) is None:
            try:
                self.api("/git/refs", {"ref": "refs/heads/" + branch, "sha": self.main()})
            except Conflict:
                if self.api("/git/ref/heads/" + branch, missing=True) is None:
                    raise

    def read(self, branch, path):
        result = self.api(f"/contents/{path}?ref={branch}", missing=True)
        if result is None:
            return None, None
        return base64.b64decode(result["content"], validate=False).decode(), result["sha"]

    def write(self, branch, path, text, previous, message):
        payload = {"branch": branch, "message": message,
                   "content": base64.b64encode(text.encode()).decode()}
        if previous:
            payload["sha"] = previous
        result = subprocess.run(["gh", "api", "--method", "PUT", self.endpoint + "/contents/" + path,
                                 "--input", "-"], input=json.dumps(payload), capture_output=True, text=True)
        if result.returncode:
            if "HTTP 409" in result.stderr or "HTTP 422" in result.stderr:
                raise Conflict("GitHub file changed; retry reconciliation")
            raise RuntimeError("GitHub write failed; release journal retained for retry")

    def pulls(self):
        pulls = []
        for page in self.pages("/pulls?state=open&base=main&per_page=100"):
            for pull in page:
                branch = pull["head"]["ref"]
                if branch == PR_BRANCH or branch.startswith(PR_BRANCH + "-"):
                    if pull["head"]["repo"]["full_name"] != self.repository or pull["user"]["login"] != "github-actions[bot]":
                        raise RuntimeError("Unexpected GitOps PR owner; human review required")
                    pulls.append({"branch": branch, "number": pull["number"]})
        return pulls

    def pull(self, branch):
        pulls = self.pulls()
        if len(pulls) > 1 or any(pull["branch"] != branch for pull in pulls):
            raise RuntimeError("Competing legacy GitOps PRs require human consolidation")
        if not pulls:
            self.api("/pulls", {"base": "main", "head": branch, "draft": True,
                               "title": "chore(gitops): update security-approved images",
                               "body": "Consolidated exact-digest image releases. Review the release journal on "
                                       "automation/image-release-state and run required checks on this head. "
                                       "Human approval and merge remain mandatory."})

    def approval(self, image, source):
        for page in self.pages(f"/actions/workflows/ci.yml/runs?head_sha={source}&event=push&per_page=100"):
            for run in page["workflow_runs"]:
                if run["head_branch"] != "main" or run["head_sha"] != source:
                    continue
                jobs = [job for jobs_page in self.pages(f"/actions/runs/{run['id']}/jobs?filter=latest&per_page=100")
                        for job in jobs_page["jobs"]]
                security = [job for job in jobs if job["name"].startswith("security / build-and-scan (")]
                if len(security) != 4 or any(job["conclusion"] != "success" for job in security):
                    continue
                with tempfile.TemporaryDirectory(prefix="release-proof-") as directory:
                    result = subprocess.run(["gh", "run", "download", str(run["id"]), "--repo", self.repository,
                                             "--name", "ready-" + image, "--dir", directory], capture_output=True)
                    if result.returncode:
                        continue
                    values = (pathlib.Path(directory) / (image + ".txt")).read_text().splitlines()
                if len(values) != 3 or values[0] != image or values[2] != source:
                    raise RuntimeError("Historical security record mismatch")
                approved = {"image": image, "digest": values[1], "source": source,
                            "run": str(run["id"]), "attempt": str(run["run_attempt"])}
                validate(approved)
                return approved
        raise RuntimeError("No retained successful security evidence for pending GitOps tag")


class Registry:
    def inspect(self, ref):
        result = subprocess.run(["docker", "buildx", "imagetools", "inspect", ref,
                                 "--format", "{{json .Manifest}}"], capture_output=True, text=True)
        if result.returncode:
            if "not found" in result.stderr.lower() or "manifest unknown" in result.stderr.lower():
                return None
            raise RuntimeError("Registry inspection failed; refusing mutation")
        digest = json.loads(result.stdout)["digest"]
        raw = json.loads(command(["docker", "buildx", "imagetools", "inspect", "--raw", ref]))
        return {"digest": digest, "source": raw.get("annotations", {}).get("org.opencontainers.image.revision", "")}

    def promote(self, ref, approved):
        repository = ref.rsplit(":", 1)[0]
        command(["docker", "buildx", "imagetools", "create", "--prefer-index=false",
                 "-t", ref, repository + "@" + approved["digest"]])


class Publisher:
    def __init__(self, github, registry, is_ancestor, owner, source, run, attempt):
        self.github, self.registry, self.ancestor = github, registry, is_ancestor
        if not re.fullmatch(r"[a-z0-9][a-z0-9-]*", owner.lower()):
            raise RuntimeError("Invalid registry owner")
        self.owner, self.source, self.run_id, self.attempt = owner.lower(), source, run, attempt

    def ref(self, image):
        return f"ghcr.io/{self.owner}/{image}"

    def newer(self, older, newer):
        if older == newer:
            return False
        if self.ancestor(older, newer):
            return True
        if self.ancestor(newer, older):
            return False
        raise RuntimeError("Divergent release sources; human reconciliation required")

    def pins(self, text):
        document = yaml.safe_load(text)
        pins = {}
        for entry in document["images"]:
            for image in IMAGES:
                if entry["name"] == self.ref(image):
                    tag = entry.get("newTag", "")
                    if image in pins or not re.fullmatch(r"sha-[0-9a-f]{40}", tag) or "digest" in entry:
                        raise RuntimeError("Expected one source-SHA GitOps pin per image")
                    pins[image] = tag[4:]
        if set(pins) != set(IMAGES):
            raise RuntimeError("Missing GitOps image pins")
        return document, pins

    def verify(self, ref, approved):
        actual = self.registry.inspect(ref)
        if actual is None or any(actual[field] != approved[field] for field in ("digest", "source")):
            raise RuntimeError("Registry digest/source differs from security approval")

    def run(self, incoming):
        main = self.github.main()
        if not self.ancestor(self.source, main):
            raise RuntimeError("Release source is not on main ancestry")
        pulls = self.github.pulls()
        if len(pulls) > 1:
            raise RuntimeError("Consolidate existing legacy GitOps PRs before publishing")
        branch = pulls[0]["branch"] if pulls else PR_BRANCH
        main_text, unused = self.github.read("main", OVERLAY)
        unused, adopted = self.pins(main_text)
        pending_text, unused = self.github.read(branch, OVERLAY) if pulls else (main_text, None)
        unused, pending = self.pins(pending_text)
        for approved in incoming:
            validate(approved)
            if approved["source"] != self.source or approved["run"] != self.run_id or approved["attempt"] != self.attempt:
                raise RuntimeError("Current security record does not belong to this run")
            self.verify(self.ref(approved["image"]) + f":candidate-{self.run_id}-{self.attempt}", approved)
        if len({approved["image"] for approved in incoming}) != len(incoming):
            raise RuntimeError("Duplicate current release records")
        self.github.branch(JOURNAL_BRANCH)
        for retry in range(5):
            text, previous = self.github.read(JOURNAL_BRANCH, JOURNAL)
            journal = json.loads(text) if text else {}
            for key, approved in journal.items():
                validate(approved)
                if key != approved["image"] + ":" + approved["source"] or not self.ancestor(approved["source"], main):
                    raise RuntimeError("Invalid release journal ancestry")
            additions = list(incoming)
            for image in IMAGES:
                stable = self.registry.inspect(self.ref(image) + ":stable")
                if stable is not None and self.newer(adopted[image], stable["source"]):
                    key = image + ":" + stable["source"]
                    if key not in journal:
                        approved = self.github.approval(image, stable["source"])
                        validate(approved)
                        self.verify(self.ref(image) + ":stable", approved)
                        self.verify(self.ref(image) + ":sha-" + stable["source"], approved)
                        additions.append(approved)
            for image, source in pending.items():
                if self.newer(adopted[image], source) and image + ":" + source not in journal:
                    approved = self.github.approval(image, source)
                    validate(approved)
                    self.verify(self.ref(image) + ":sha-" + source, approved)
                    additions.append(approved)
            for approved in additions:
                if not self.ancestor(approved["source"], main):
                    raise RuntimeError("Recovered release source is not on main")
                key = approved["image"] + ":" + approved["source"]
                journal.setdefault(key, approved)
            updated = json.dumps(journal, sort_keys=True, indent=2) + "\n"
            try:
                if updated != text:
                    self.github.write(JOURNAL_BRANCH, JOURNAL, updated, previous,
                                      "chore(ci): journal security-approved releases")
                break
            except Conflict:
                if retry == 4:
                    raise
        selected = {}
        for approved in journal.values():
            image = approved["image"]
            if image not in selected or self.newer(selected[image]["source"], approved["source"]):
                selected[image] = approved
        for image, approved in selected.items():
            if self.newer(approved["source"], adopted[image]):
                continue
            ref = self.ref(image)
            target = ref + ":sha-" + approved["source"]
            if self.registry.inspect(target) is None:
                self.registry.promote(target, approved)
            self.verify(target, approved)
            stable = self.registry.inspect(ref + ":stable")
            if stable is None or self.newer(stable["source"], approved["source"]):
                self.registry.promote(ref + ":stable", approved)
                self.verify(ref + ":stable", approved)
            elif stable["source"] == approved["source"]:
                self.verify(ref + ":stable", approved)
        self.github.branch(branch)
        for retry in range(5):
            text, previous = self.github.read(branch, OVERLAY)
            document, pins = self.pins(text)
            fresh_main, unused = self.github.read("main", OVERLAY)
            unused, current = self.pins(fresh_main)
            changes = {}
            for image in IMAGES:
                if self.newer(pins[image], current[image]):
                    changes[image] = current[image]
            for image, approved in selected.items():
                source = approved["source"]
                if self.newer(changes.get(image, pins[image]), source) and not self.newer(source, current[image]):
                    changes[image] = source
                elif self.newer(source, pins[image]):
                    key = image + ":" + pins[image]
                    proof = journal.get(key) or self.github.approval(image, pins[image])
                    self.verify(self.ref(image) + ":sha-" + pins[image], proof)
            for entry in document["images"]:
                for image, source in changes.items():
                    if entry["name"] == self.ref(image):
                        entry["newTag"] = "sha-" + source
            for image in IMAGES:
                source = changes.get(image, pins[image])
                if self.newer(current[image], source):
                    if not self.ancestor(source, main):
                        raise RuntimeError("Proposed GitOps source is not on main")
                    proof = journal.get(image + ":" + source) or self.github.approval(image, source)
                    validate(proof)
                    self.verify(self.ref(image) + ":sha-" + source, proof)
            try:
                if changes:
                    self.github.write(branch, OVERLAY, yaml.safe_dump(document, sort_keys=False), previous,
                                      "chore(gitops): consolidate security-approved image pins")
                break
            except Conflict:
                if retry == 4:
                    raise
        text, unused = self.github.read(branch, OVERLAY)
        unused, final_pins = self.pins(text)
        if final_pins != current:
            self.github.pull(branch)


def main():
    records = []
    for path in sorted(pathlib.Path("ready").glob("*.txt")):
        values = path.read_text().splitlines()
        if len(values) != 3:
            raise RuntimeError("Expected exact three-line security record")
        records.append({"image": values[0], "digest": values[1], "source": values[2],
                        "run": os.environ["GITHUB_RUN_ID"], "attempt": os.environ["GITHUB_RUN_ATTEMPT"]})
    Publisher(GitHub(os.environ["GITHUB_REPOSITORY"]), Registry(), ancestor,
              os.environ["OWNER"], os.environ["GITHUB_SHA"], os.environ["GITHUB_RUN_ID"],
              os.environ["GITHUB_RUN_ATTEMPT"]).run(records)
    print("Security-approved releases reconciled; human review remains required.")


if __name__ == "__main__":
    main()