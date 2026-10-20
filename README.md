# Secret Base Warp

A gen1recomp mod for Pokémon Emerald. Adds a **BASE** row to the Start menu
that takes you straight into your own Secret Base, and walks you back out to
where you left from.

The trip is a round trip. The mod runs the game's own entry script, so the
engine records your departure point in `session.dynamicWarp` exactly as it does
when you walk in through the door — leaving through the base door returns you
to the tile you called the menu from, facing down, the same as vanilla.

If you were riding a bike when you left, you are back on it when you return.

## Requirements

| | |
|---|---|
| Game | Pokémon Emerald |
| Engine | gen1recomp 0.3.0 or newer |
| Mod API | 2 |
| Permissions | `engine_internals` |

The mod reaches engine modules that are not on the Gen 3 mod facade list, so it
declares the `engine_internals` permission. The Mod Manager flags that with a
`!` badge reading *PATCHES ENGINE CODE*; it is expected, not a warning about
this mod in particular.

## Eligibility

The BASE row only appears when the warp would actually work, so selecting it
never does nothing. It is hidden when:

- You do not own a Secret Base yet.
- You are already inside a Secret Base. Entering one from another would
  overwrite `session.dynamicWarp`, the single slot holding the first base's way
  out, and strand you indoors.
- A script, cutscene or forced movement is running (`Field.isLocked`).
- A warp is already in flight (`Warp.isBusy`).
- You are aboard Mr. Briney's boat or the S.S. Tidal, which are scripted from
  start to finish.
- A Battle Frontier or Battle Tent challenge is in progress. Those facilities
  cut you off from the PC on purpose, and a Secret Base has one. Lobbies and
  the surrounding town stay usable, because the check is the running challenge
  and not the map.
- You are in a Trainer Hill run, for the same reason.
- You are inside the sealed rooms of the Elite Four: the four member rooms, the
  Champion's room, halls 1 to 5 and the Hall of Fame. Pokémon League 1F/2F and
  the Ever Grande Pokémon Center are deliberately allowed, since you can still
  walk out of those.

Everywhere else is fair game, including buildings, gyms and caves. The warp is
a round trip, so the question is never whether you may leave a map, only
whether the game is in the middle of something.

## Installing

gen1recomp loads mods from a `mods` folder. On a portable install — one with a
`portable.txt` next to the application — that folder sits beside the app:

```
gen1recomp/
├── portable.txt
├── gen1recomp.app
└── mods/
    └── secret_base_warp/
        ├── main.lua
        └── manifest.json
```

1. Copy the `secret_base_warp` folder into `mods/`, keeping the folder name.
2. Start gen1recomp and open the Mod Manager.
3. Enable **Secret Base Warp** and accept the `engine_internals` prompt.
4. Load an Emerald save.

The mod targets Emerald only and stays inert on other games.

## Using it

Open the Start menu. If you own a Secret Base and nothing listed under
[Eligibility](#eligibility) is in the way, a **BASE** row sits just above
**SAVE**.

Select it. You spin out with the teleport sound, arrive inside your base facing
away from the door, and walk out through that door whenever you are done.

## Contributing

### Commit messages

[Conventional Commits](https://www.conventionalcommits.org), with a scope when
it carries signal:

```
feat(menu): warp to the player's own Secret Base
fix(bike): remount the bike on the return trip
refactor(engine-access): collapse the repeated idioms
```

Types in use: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`.

### Versioning

[Semantic Versioning](https://semver.org), one release per commit, tagged
`vMAJOR.MINOR.PATCH`:

| Change | Bump |
|---|---|
| Incompatible change | major |
| Backward compatible functionality | minor |
| Backward compatible bug fix | patch |

**A local convention worth stating, because it departs from the spec:**
`refactor` and `docs` also bump the patch version here. SemVer versions
releases rather than commits, so a pure refactor normally waits for the next
release instead of earning a version of its own. In this repository every
commit is a build that gets installed and played, and two different `main.lua`
files must never both claim the same version — otherwise there is no way to
tell which build is running. In a library, let refactors ride along to the next
`fix` or `feat` instead.

Keep `manifest.json`'s `version` field in step with the tag.

### Packaging

`./package.sh` writes the install zip of the release `manifest.json` names to
`~/Desktop/secret_base_warp-v<version>.zip`: the files of its tag, in a
`secret_base_warp` folder, without the tests and tooling (`.gitattributes`
marks them `export-ignore`). It stops if that version has no tag yet.

### Tests

`tests/run.sh` runs the offline tests (see `tests/README.md`); run it before
every commit.

### Code

- English only, in comments as well as identifiers.
- Names carry the meaning. A comment earns its place when it records something
  that reading this file cannot reveal: engine behaviour, or a rule this mod
  imposes. A comment that restates the next line does not.
- Engine modules are reached through `engineModule` and queried through
  `callOrFalse`, so a renamed or missing module hides the row rather than
  breaking the Start menu. Two raw `pcall`s are deliberate and carry a comment
  saying why.
