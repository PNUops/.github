#!/usr/bin/env bash
# Verification gate: shell lint + publication hygiene + profile asset integrity.
# Run it before every commit; CI runs the same script on push and pull request.
set -euo pipefail
cd "$(dirname "$0")/.."

# find's exit status is invisible through a process substitution, so a partial
# walk would shorten the list and still lint clean. Materialising it first lets
# set -e see the failure.
listing="$(mktemp)"
trap 'rm -f "$listing"' EXIT
find . -name '*.sh' -not -path './.git/*' -print0 > "$listing"
mapfile -d '' -t scripts < "$listing"
[ "${#scripts[@]}" -gt 0 ] || { echo "verify: no scripts found" >&2; exit 1; }
shellcheck "${scripts[@]}"

# Publication hygiene: no references to paths this repository does not contain,
# none to a private tree or a vault, no internal process tokens. This page is
# the organisation's front door, so it is the most-read text the project has and
# the one nobody re-reads before publishing.
# shellcheck source=scripts/hygiene.sh
. scripts/hygiene.sh   # cwd is the repo root (set above)
hygiene_selftest
hygiene_check public

# The profile page loads its images through absolute raw file URLs, because a
# relative path in a profile README resolves against the viewer's page rather
# than this repository. Nothing in a rendered page reports a URL that 404s: the
# image simply does not appear, and the person who renamed the file is not the
# person looking at the page. So the paths inside those URLs are checked against
# the tree, in both directions — a named file that is missing, and a committed
# asset that nothing names and that is therefore only taking up space.
asset_fail=0
referenced="$(mktemp)"
trap 'rm -f "$listing" "$referenced"' EXIT
git ls-files -z '*.md' \
  | xargs -0 grep -ohE 'profile/assets/[A-Za-z0-9._-]+' \
  | sort -u > "$referenced"
while IFS= read -r asset; do
  [ -n "$asset" ] || continue
  if [ ! -f "$asset" ]; then
    echo "verify: the profile page loads $asset, which is not in this repository" >&2
    asset_fail=1
  fi
done < "$referenced"
while IFS= read -r asset; do
  [ -n "$asset" ] || continue
  if ! grep -qxF "$asset" "$referenced"; then
    echo "verify: $asset is committed but no page references it" >&2
    asset_fail=1
  fi
done < <(git ls-files 'profile/assets/*')
[ "$asset_fail" -eq 0 ] || { echo "verify: profile asset check failed" >&2; exit 1; }

echo "org-profile verify OK (${#scripts[@]} scripts)"
