#!/usr/bin/env python3
"""Gate fork pin updates on the weekly Dependabot cycle."""
import datetime
import json
import os
import re
import subprocess
from zoneinfo import ZoneInfo

BRANCH = "automation/upstream-dependency-update"
BERLIN = ZoneInfo("Europe/Berlin")


def cycle_start(now):
    local = now.astimezone(BERLIN)
    monday = local.date() - datetime.timedelta(days=local.weekday())
    start = datetime.datetime.combine(monday, datetime.time(12), BERLIN)
    if now < start:
        start -= datetime.timedelta(days=7)
    return start


def timestamp(value):
    return datetime.datetime.fromisoformat(value.replace("Z", "+00:00"))


def decision(pulls, now):
    start = cycle_start(now)
    if now < start + datetime.timedelta(hours=24):
        return "waiting for the 24-hour Dependabot window"
    marker = f"<!-- fork-pin-cycle:{start.date()} -->"
    for pull in pulls:
        if pull["base"]["ref"] != "main":
            continue
        branch = pull["head"]["ref"]
        state = pull["state"]
        if pull["user"]["login"] == "dependabot[bot]" and state == "open":
            if "security" not in [label["name"].lower() for label in pull["labels"]]:
                return "waiting for open Dependabot version updates"
        closed = pull["closed_at"]
        if branch == BRANCH and (timestamp(pull["created_at"]) >= start or
                                 (state == "closed" and closed and timestamp(closed) >= start) or
                                 marker in (pull["body"] or "")):
            return "a fork pin PR already exists for this cycle"
    return None


def main():
    repository = os.environ["GITHUB_REPOSITORY"]
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository):
        raise ValueError("Invalid repository name")
    result = subprocess.run(
        ["gh", "api", "--paginate", "--slurp", f"repos/{repository}/pulls?state=all&base=main&per_page=100"],
        check=True, capture_output=True, text=True,
    )
    pages = json.loads(result.stdout)
    if not isinstance(pages, list) or not pages or not all(isinstance(page, list) for page in pages):
        raise ValueError("Invalid pull request response")
    pulls = [pull for page in pages for pull in page]
    now = datetime.datetime.now(datetime.timezone.utc)
    reason = decision(pulls, now)
    open_pins = [pull for pull in pulls if pull["base"]["ref"] == "main" and
                 pull["head"]["ref"] == BRANCH and pull["state"] == "open"]
    if len(open_pins) > 1:
        raise ValueError("Multiple open fork pin PRs")
    number = open_pins[0]["number"] if open_pins else ""
    if open_pins and (type(number) is not int or number <= 0):
        raise ValueError("Invalid fork pin PR number")
    with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as output:
        output.write(f"ready={str(reason is None).lower()}\ncycle={cycle_start(now).date()}\npr_number={number}\n")
    print(reason or "Dependency cycle is ready for a fork pin PR")


if __name__ == "__main__":
    main()