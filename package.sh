#!/bin/sh
# Writes the install zip of the release manifest.json names: the files of tag
# v<version>, in a folder named after the mod id, at ~/Desktop/<id>-v<version>.zip.
# Paths marked export-ignore in .gitattributes (tests, tooling) are left out.
set -eu

cd "$(dirname "$0")"
field() { sed -n "s/^  \"$1\": \"\(.*\)\",*$/\1/p" manifest.json; }
ID=$(field id)
VERSION=$(field version)
TAG="v$VERSION"

if ! git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  echo "manifest.json says $VERSION, but there is no tag $TAG: commit and tag the release first" >&2
  exit 1
fi
if [ "$(git rev-parse "$TAG^{commit}")" != "$(git rev-parse HEAD)" ]; then
  echo "note: HEAD is not $TAG; the zip holds $TAG" >&2
fi

OUT="$HOME/Desktop/$ID-$TAG.zip"
git archive --format=zip --prefix="$ID/" -o "$OUT" "$TAG"
echo "$OUT"
unzip -l "$OUT" | tail -1
