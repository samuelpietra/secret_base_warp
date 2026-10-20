#!/bin/sh
# Runs the offline tests; none needs a ROM, so the same run serves a
# gen1recomp install on macOS and CI on Linux.
#
#   lint         every global main.lua touches; a misspelt local shows here
#   engine       the engine modules, functions, warp kinds, hook and event the
#                mod relies on, on the real engine
#   integration  the mod's paths on stand-ins for the engine modules
#
# The engine is the newest update payload of the install this mod sits in
# (mods/secret_base_warp/tests -> three levels up), or else gen1recomp's
# release of ENGINE_VERSION.  LÖVE is the system's (CI installs it with apt),
# or else a copy of the install's app without its game.love, which would
# otherwise start the game instead of the test.  Exits non-zero on a failure.
set -eu

ENGINE_VERSION=0.3.85
TESTS=$(cd "$(dirname "$0")" && pwd)
MOD=$(dirname "$TESTS")
INSTALL=$(cd "$MOD/../.." && pwd)
WORK=${RUNNER_TEMP:-${TMPDIR:-/tmp}}/secret_base_warp-tests
mkdir -p "$WORK"

PAYLOAD=$(ls -t "$HOME/Library/Application Support/pokemon-love2d/updates/"gen1recomp-*.love 2>/dev/null | head -1 || true)
if [ -z "$PAYLOAD" ]; then
  PAYLOAD="$WORK/gen1recomp-$ENGINE_VERSION.love"
  [ -f "$PAYLOAD" ] || curl -fsSL -o "$PAYLOAD" \
    "https://github.com/bryanthaboi/gen1recomp/releases/download/v$ENGINE_VERSION/gen1recomp-$ENGINE_VERSION.love"
fi
# macOS empties old files under $TMPDIR, so the extracted engine is checked too
if [ ! -f "$WORK/engine/main.lua" ] || [ "$(cat "$WORK/engine.from" 2>/dev/null)" != "$PAYLOAD" ]; then
  rm -rf "$WORK/engine" && mkdir -p "$WORK/engine"
  unzip -q -o "$PAYLOAD" -d "$WORK/engine"
  echo "$PAYLOAD" > "$WORK/engine.from"
fi

LOVE=$(command -v love || true)
if [ -z "$LOVE" ]; then
  if [ ! -x "$WORK/love.app/Contents/MacOS/love" ]; then
    rm -rf "$WORK/love.app"
    cp -R "$INSTALL/gen1recomp.app" "$WORK/love.app"
    rm -f "$WORK/love.app/Contents/Resources/game.love"
  fi
  LOVE="$WORK/love.app/Contents/MacOS/love"
fi

export SBW_MOD="$MOD" SBW_ENGINE="$WORK/engine"
failed=0
for test in lint engine integration; do
  echo "== $test"
  "$LOVE" "$TESTS/$test" > "$WORK/$test.log" 2>&1 || true
  cat "$WORK/$test.log"
done
grep -qx "main.lua	ok" "$WORK/lint.log" || failed=1
grep -qx "ALL PASS" "$WORK/engine.log" || failed=1
grep -qx "ALL PASS" "$WORK/integration.log" || failed=1
exit "$failed"
