#!/usr/bin/env bash
# Refuses to publish unless the checkout is exactly the tagged release on main.
# Publishing from a feature branch once shipped the next version under the
# previous one's name, and a stale py/dist/ uploaded two versions at once.
#
# Usage: scripts/publish_check.sh npm|py (run through make publish-npm / publish-py)
set -euo pipefail

registry="${1:-}"
case "$registry" in
  npm) tag_prefix="ts" ;;
  py) tag_prefix="py" ;;
  *) echo "usage: $0 npm|py" >&2; exit 2 ;;
esac

fail() { echo "✗ publish check: $*" >&2; exit 1; }

cd "$(git rev-parse --show-toplevel)"

branch="$(git rev-parse --abbrev-ref HEAD)"
[ "$branch" = "main" ] || fail "on branch '$branch'; publish only from main (git checkout main && git pull)"

[ -z "$(git status --porcelain)" ] || fail "working tree has uncommitted changes"

git fetch -q origin main --tags
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || fail "main is not at origin/main; run git pull"

ts_version="$(node -p "require('./ts/package.json').version")"
lock_version="$(node -p "require('./ts/package-lock.json').version")"
py_version="$(sed -n 's/^version = "\(.*\)"$/\1/p' py/pyproject.toml)"
[ -n "$py_version" ] || fail "could not read the version from py/pyproject.toml"
[ "$ts_version" = "$lock_version" ] || fail "ts/package.json is $ts_version but ts/package-lock.json is $lock_version"
[ "$ts_version" = "$py_version" ] || fail "ts/package.json is $ts_version but py/pyproject.toml is $py_version"
version="$ts_version"

tag="$tag_prefix/v$version"
[ -n "$(git tag --points-at HEAD --list "$tag")" ] || fail "HEAD is not tagged $tag; tag the merge commit first"
# The peeled ref (^{}) is the commit an annotated tag points at.
remote_sha="$(git ls-remote origin "refs/tags/$tag^{}" | cut -f1)"
[ -n "$remote_sha" ] || fail "tag $tag is not pushed to origin"
[ "$remote_sha" = "$(git rev-parse HEAD)" ] || fail "tag $tag on origin points at $remote_sha, not HEAD"

case "$registry" in
  npm)
    # npm exits non-zero with E404 for a version that does not exist yet.
    err="$(mktemp)"
    trap 'rm -f "$err"' EXIT
    if out="$(npm view "@jdg-keyforge/protocol@$version" version 2>"$err")"; then
      [ -z "$out" ] || fail "@jdg-keyforge/protocol@$version is already on npm"
    else
      grep -q E404 "$err" || fail "could not query npm: $(cat "$err")"
    fi
    ;;
  py)
    status="$(curl -sS -o /dev/null -w '%{http_code}' "https://pypi.org/pypi/jdg-keyforge-protocol/$version/json")" \
      || fail "could not reach PyPI"
    case "$status" in
      404) ;;
      200) fail "jdg-keyforge-protocol $version is already on PyPI" ;;
      *) fail "could not query PyPI (HTTP $status)" ;;
    esac
    ;;
esac

echo "✓ publish check: $registry $version from main at $(git rev-parse --short HEAD) ($tag)"
