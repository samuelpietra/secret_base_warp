#!/bin/sh
# Every commit is a release: each commit in the range (git rev-list syntax,
# default HEAD) raises manifest.json's version over its parent's and carries
# the tag v<version>.
set -eu

version_at() { git show "$1:manifest.json" | sed -n 's/^  "version": "\(.*\)",$/\1/p'; }
newer() { # is $2 greater than $1
  [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)" = "$2" ]
}

failed=0
for commit in $(git rev-list --reverse "${1:-HEAD}"); do
  short=$(git log -1 --format='%h %s' "$commit")
  version=$(version_at "$commit")
  if git rev-parse -q --verify "$commit^" >/dev/null; then
    previous=$(version_at "$commit^")
    if ! newer "$previous" "$version"; then
      echo "::error::$short: version $version does not raise $previous"; failed=1
    fi
  fi
  if [ "$(git rev-parse -q --verify "refs/tags/v$version^{commit}" || true)" != "$commit" ]; then
    echo "::error::$short: tag v$version is missing or on another commit"; failed=1
  fi
  [ "$failed" -eq 0 ] && echo "ok $short: v$version"
done
exit "$failed"
