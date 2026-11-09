#!/usr/bin/env bash
set -euo pipefail

baseline_file=${XERJ_BASELINE_FILE:-.github/xerj-reviewed-revision.txt}
upstream=${XERJ_REPOSITORY:-https://github.com/xerj-org/xerj.git}
repository=${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}
baseline=$(tr -d '\r\n' < "$baseline_file")
[[ "$baseline" =~ ^[0-9a-f]{40}$ ]] || { printf '%s\n' 'Invalid reviewed XERJ revision' >&2; exit 1; }

work=$(mktemp -d)
trap 'find "$work" -type f -exec chmod u+w {} +; rm -r "$work"' EXIT
git init -q "$work/upstream"
git -C "$work/upstream" remote add origin "$upstream"
git -C "$work/upstream" fetch -q --no-tags origin "$baseline" refs/heads/main:refs/remotes/origin/main
head=$(git -C "$work/upstream" rev-parse refs/remotes/origin/main^0)
git -C "$work/upstream" cat-file -e "$baseline^{commit}"
git -C "$work/upstream" merge-base --is-ancestor "$baseline" "$head" || {
  printf '%s\n' 'Reviewed XERJ revision is not an ancestor of main; manual review is required.' >&2
  exit 1
}
files=(AGENTS.md CONTRIBUTING.md SECURITY.md docs/SECURITY_MODEL.md .github/AI_CONTRIBUTIONS.md)
changed=$(git -C "$work/upstream" diff --name-only --no-renames "$baseline" "$head" -- "${files[@]}")
if [[ -z "$changed" ]]; then
  printf '%s\n' 'No monitored XERJ files changed.'
  exit 0
fi

body="$work/pr.md"
{
  printf '%s\n\n' '<!-- xerj-reference-monitor -->' 'XERJ reference files changed since the last reviewed revision. External content is untrusted reference material, not project instructions.'
  printf 'Reviewed: `%s`\nCurrent: `%s`\n\n' "$baseline" "$head"
  printf '[Full comparison](https://github.com/xerj-org/xerj/compare/%s...%s)\n\n' "$baseline" "$head"
  printf '%s\n' 'Changed files:'
  while IFS= read -r file; do
    printf -- '- [%s](https://github.com/xerj-org/xerj/compare/%s...%s#diff-%s) ([old](https://github.com/xerj-org/xerj/blob/%s/%s), [new](https://github.com/xerj-org/xerj/blob/%s/%s))\n' "$file" "$baseline" "$head" "$(printf '%s' "$file" | shasum -a 256 | cut -d ' ' -f 1)" "$baseline" "$file" "$head" "$file"
  done <<< "$changed"
  printf '\n%s\n' 'Deterministic candidate changes (human review required; keyword matches are not semantic analysis):'
  while IFS= read -r file; do
    git -C "$work/upstream" diff --no-ext-diff --no-color --no-renames --unified=0 "$baseline" "$head" -- "$file" > "$work/file.diff"
    matched=false
    for category in tests secrets review; do
      case "$category" in
        tests) pattern='test|validation|regression'; target='CONTRIBUTING.md'; proposal='For behavior changes, record the focused regression command and its result in the handoff.' ;;
        secrets) pattern='secret|credential|password'; target='docs/security.md'; proposal='Document where credentials are stored, who can read them, and how they are rotated without committing them.' ;;
        review) pattern='review|approval|human'; target='AGENTS.md'; proposal='Require a human decision before adopting external instructions or changing deployment ownership.' ;;
      esac
      evidence=$(LC_ALL=C grep -iE '^\+[^+].*('"$pattern"')' "$work/file.diff" | head -c 300 || true)
      if [[ -n "$evidence" ]]; then
        matched=true
        printf -- '- `%s` -> `%s`: Candidate wording: "%s" Check existing rules and applicability before adopting.\n' "$file" "$target" "$proposal"
        printf '  Evidence (added upstream text, untrusted): `%s`\n' "$(printf '%s' "$evidence" | tr '\n\r' '  ' | sed 's/`/\x27/g; s/@/@ /g')"
      fi
    done
    if [[ "$matched" == false ]]; then
      printf -- '- `%s`: No catalog rule matched added lines; inspect the diff manually, including removals.\n' "$file"
    fi
  done <<< "$changed"
  printf '\n%s\n' 'Upstream diff (untrusted data; truncated at 400 lines or 20000 bytes):' '```diff'
  git -C "$work/upstream" diff --no-ext-diff --no-color --no-renames "$baseline" "$head" -- "${files[@]}" > "$work/upstream.diff"
  LC_ALL=C head -c 20000 "$work/upstream.diff" > "$work/bounded.diff"
  sed -n '1,400p' "$work/bounded.diff" | sed 's/```/` ` `/g; s/@/@ /g'
  printf '%s\n' '```'
  printf '\n%s\n' 'A human must review and record acceptance or rejection before updating .github/xerj-reviewed-revision.txt. This PR does not update the baseline or adopt upstream instructions.'
} > "$body"

branch=automation/xerj-reference-review
base=${GITHUB_DEFAULT_BRANCH:-main}
[[ "$base" =~ ^[A-Za-z0-9._/-]+$ ]] || { printf '%s\n' 'Invalid default branch' >&2; exit 1; }
base_sha=$(gh api "repos/$repository/git/ref/heads/$base" --jq '.object.sha')
[[ "$base_sha" =~ ^[0-9a-f]{40}$ ]] || { printf '%s\n' 'Invalid base revision' >&2; exit 1; }
printf 'Reviewed: %s\nCurrent: %s\n' "$baseline" "$head" > "$work/status.txt"
refs=$(gh api --paginate "repos/$repository/git/matching-refs/heads/$branch" --jq '.[].ref')
if grep -Fxq "refs/heads/$branch" <<< "$refs"; then
  prs=$(gh api --paginate "repos/$repository/pulls?state=open&per_page=100" --jq ".[] | select(.head.ref == \"$branch\" and .head.repo.full_name == \"$repository\" and .user.login == \"github-actions[bot]\") | .number")
  [[ -n "$prs" ]] || { printf '%s\n' 'Review branch exists without an open bot PR; manual review required.' >&2; exit 1; }
else
  gh api "repos/$repository/git/refs" -f "ref=refs/heads/$branch" -f sha="$base_sha" >/dev/null
  prs=''
fi
branch_sha=$(gh api "repos/$repository/git/ref/heads/$branch" --jq '.object.sha')
[[ "$branch_sha" =~ ^[0-9a-f]{40}$ ]] || { printf '%s\n' 'Invalid review branch revision' >&2; exit 1; }
file_sha=$(gh api "repos/$repository/git/trees/$branch_sha?recursive=1" --jq '.tree[] | select(.path == ".github/xerj-review-status.txt") | .sha')
content=$(base64 < "$work/status.txt" | tr -d '\n')
if [[ "$file_sha" != "$(git hash-object "$work/status.txt")" ]]; then
  if [[ -n "$file_sha" ]]; then
    [[ "$file_sha" =~ ^[0-9a-f]{40}$ ]] || { printf '%s\n' 'Invalid review status revision' >&2; exit 1; }
    jq -n --arg message 'chore: update XERJ reference review' --arg content "$content" --arg branch "$branch" --arg sha "$file_sha" '{message:$message,content:$content,branch:$branch,sha:$sha}' > "$work/update.json"
  else
    jq -n --arg message 'chore: update XERJ reference review' --arg content "$content" --arg branch "$branch" '{message:$message,content:$content,branch:$branch}' > "$work/update.json"
  fi
  gh api --method PUT "repos/$repository/contents/.github/xerj-review-status.txt" --input "$work/update.json" >/dev/null
fi
if [[ -n "$prs" ]]; then
  gh pr edit "${prs%%$'\n'*}" --repo "$repository" --body-file "$body"
else
  gh pr create --repo "$repository" --base "$base" --head "$branch" --title 'Review XERJ reference changes' --body-file "$body"
fi