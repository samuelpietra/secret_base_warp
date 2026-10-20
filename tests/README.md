# Offline tests

The mod only acts in the game, and when an engine function it relies on is
renamed it hides the BASE row without a word. These tests catch both before a
build is installed and played. Run them all with:

```sh
tests/run.sh
```

None needs a ROM, so the same script runs on a gen1recomp install (macOS,
portable) and in CI on Linux. It uses the install's newest engine payload and
a copy of its app's LÖVE when it finds them; otherwise gen1recomp's release
of the oldest engine `manifest.json` accepts, downloaded, and the system's `love`.
It exits non-zero when a test fails.
Raise `ENGINE_VERSION` in `run.sh` together with `game_version` in the
manifest.

| Test | Checks | Expected |
|---|---|---|
| `lint` | Every global `main.lua` reads or writes. A misspelt local shows up as an unexpected global. | `main.lua ok`. |
| `engine` | On the real engine: every module in `main.lua`'s `ENGINE` and every function the mod calls; the two warp kinds `TELEPORT_SPEC` joins, and its fields among those the engine's kinds use; the Start menu still raising `ui.start_menu.items` and calling `onSelect`, and map entry emitting `map.entered` with its `mapId`; the row going in before SAVE through the real hook bus and `ModUI`; the real `Player` back on the bike through the real event bus. | `ALL PASS`. |
| `integration` | The mod's paths on stand-ins for the engine modules: every case of the README's *Eligibility*, the sealed Elite Four rooms and the rooms you can walk out of, a throwing engine query, the row's place; selecting it: the own base made current, the menu closed, the warp waiting for it to close, the entry script, facing up, the teleport kind registered once and its override gone after one warp; the fallback to `SB.enter` and the restore when nothing warps; the bike remembered, kept through the base, remounted on the way back, dropped when stale, never while surfing. | `ALL PASS`. |
