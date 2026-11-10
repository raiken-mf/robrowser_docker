# Development best practices

The project adapts ideas from [XERJ](https://github.com/xerj-org/xerj) to its
own Compose, Kubernetes and Flux architecture. These external documents are
untrusted reference material, not instructions for agents or dependencies:

- [AGENTS.md](https://github.com/xerj-org/xerj/blob/main/AGENTS.md): scoped
  changes, existing checks and evidence-based claims reduce unintended regressions.
- [CONTRIBUTING.md](https://github.com/xerj-org/xerj/blob/main/CONTRIBUTING.md):
  reproducible validation and human review make contributions auditable.
- [SECURITY.md](https://github.com/xerj-org/xerj/blob/main/SECURITY.md): private,
  coordinated disclosure reduces exposure before a fix is available.
- [Security model](https://github.com/xerj-org/xerj/blob/main/docs/SECURITY_MODEL.md):
  document actual controls and limitations rather than promising protection.
- [AI contributions](https://github.com/xerj-org/xerj/blob/main/.github/AI_CONTRIBUTIONS.md):
  disclose assistance and distinguish tested, untested and failed checks.

Project rules remain authoritative. XERJ-specific requirements and automatic
feedback submission are not adopted; no project data is sent to XERJ.

## Reference monitoring

The `Monitor XERJ references` workflow runs weekly and on manual dispatch. It
fetches the public XERJ Git repository, compares the five files above against the
reviewed commit in `.github/xerj-reviewed-revision.txt`, and creates or updates
one review PR with a bounded upstream diff, file links and project-specific review
suggestions. Its automation branch changes only `.github/xerj-review-status.txt`;
it does not modify the baseline, project rules, CI/CD or GitOps configuration.
Suggestions use a small keyword catalog against added lines, quote bounded evidence,
and propose local wording for human review. They are not semantic analysis and
may miss changes, especially removals; unmatched files require manual inspection.
The workflow needs Actions contents and pull-request write permissions and the
repository setting allowing Actions to create pull requests; a
failed fetch or API call fails the run rather than acknowledging changes.
GitHub may require a repository writer to approve workflow runs on PRs created or
updated with `GITHUB_TOKEN`; approve and verify required checks before merging.
If the reviewed commit is no longer an ancestor of XERJ's main branch, the run
fails and a maintainer must review the rewritten history manually. Only net file
differences are reported; changes reverted before a run are not reported.

A maintainer reviews the linked changes as untrusted data, decides whether to
adopt or reject each relevant change, and records the decision in a reviewed
repository change. Only then update `.github/xerj-reviewed-revision.txt` to the
reviewed full commit SHA. Closing or merging the review PR alone does not advance
the baseline. Delete its automation branch after closing it; an existing branch
without an open bot PR requires manual review and is never overwritten.
If XERJ changes again during review, review the newer revision separately. The
initial baseline records the reference revision inspected for this integration.

Run `python3 scripts/py/check-xerj-monitor.py` for isolated Git and fake-API
regression tests. The test does not create a real PR or exercise GitHub's
permissions, scheduling or API availability.