# Secret Base Warp — working notes for Claude

A gen1recomp mod for Pokémon Emerald: a **BASE** row in the Start menu that
takes the player into their own Secret Base through the game's own entry
script, so walking out the door returns them where they left from. The
README is the spec of what it does and when the row is hidden.

Answer in the language the person is writing in. Everything committed —
code, comments, README, commit messages — is in English.

## How this mod is built

- One file, `main.lua`. Every engine module it touches is listed in
  `ENGINE` and reached through `engineModule`; engine functions are queried
  through `callOrFalse`, so a renamed or missing one hides the row instead of
  breaking the Start menu. The two raw `pcall`s are deliberate and say why.
- The one change to an engine function is `overrideNextWarpKind`: it swaps
  `Warp.scripted` for a single warp and puts it back the moment that warp
  fires. Keep any new override that short-lived.
- The warp runs `SecretBase_EventScript_Enter`, which records the way out in
  `session.dynamicWarp`. Never enter a base from inside another: that slot
  holds the first base's exit.
- What the mod authors, stated so it stays deliberate: the row label "BASE",
  its place above SAVE, and `TELEPORT_SPEC`, Emerald's teleport sound on
  FireRed's spin.

## Vanilla first

The mod adds what the game lacks with the game's own pieces, so a player
cannot tell where the game ends and the mod begins.

- **No new pixels, sounds, music or fonts.** Graphics, text, sounds and rules
  come from the player's imported ROM or from the engine. A mod may ship data
  about the ROM's assets (which tiles, which pixels belong, which palette
  colours to swap), never the assets themselves.
- **Text comes from the ROM when the ROM has it.** Search the script cache
  (`RomText`) before writing a string; join the ROM's own words before
  authoring new ones. Authored text is the last resort, and it follows the
  game's style (capitals, `{PKMN}`, line lengths).
- **Behaviour copies the original.** A piece, screen or sound that exists in
  the game behaves as it does there: same script, same collision, same
  sound, same cursor rules. Departures are the maintainer's call, made
  explicitly, and recorded in the README.
- **Find the engine's own function first.** Before drawing, measuring or
  computing something, look for the engine module that already does it (the
  summary screen's badges, the list menu's arrows, the damage code's type
  chart) and call it.
- At a visual impasse — alignment, layout, which sprite or colour — render
  the options from the real ROM into an image and show it before building
  one.

## Scope

- Build what was asked. No option, setting, flag, fallback path or
  abstraction nobody asked for: a value the spec fixes is a constant.
- Something out of scope that seems useful is offered as a suggestion, not
  built.
- When reporting, audit additions against the request and say plainly which
  parts were not in it.

## Code

- Match the surrounding code: its names, comment density and idioms.
- Names say what a thing means in the game ("choosingCommand", "footprintTop"),
  not how it is computed.
- Comment only what reading the file cannot reveal: engine behaviour this
  relies on (cite the engine file or the pret source), or a rule this mod
  imposes and why. Never restate the next line.
- Reuse before adding: a second copy of a pattern becomes one helper; a
  table of data beats parallel branches.
- Leave no leftovers: unused locals, dead branches, debug prints, stale
  comments and helpers whose last caller went away are deleted in the same
  change.
- Engine access goes through the mod's own helpers and patterns (*How this
  mod is built*); a new kind of access follows them, or says in a comment
  why it cannot.

## Before saying it is done

There are no offline tests for this mod yet. Read the change against the
README's *Eligibility* list, then hand the build over for an in-game test,
naming the cases to try. Do not claim it works before that.

## Releasing

Commit only when the maintainer says so, usually after playing the build.

- [Conventional Commits](https://www.conventionalcommits.org): `feat`, `fix`,
  `refactor`, `docs`, `chore`, with a scope when it carries signal.
- One SemVer tag per commit, `vMAJOR.MINOR.PATCH`: every commit is a build
  that gets installed, so `refactor`, `docs` and `chore` bump the patch too
  (README, *Versioning*). `manifest.json`'s `version` moves with the tag, in
  the same commit.
- End every commit message with the co-author trailer:
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` (or the model in
  use).
- Update the README in the same commit when behaviour, requirements or
  layout change.
- `./package.sh` writes the install zip of the tagged release to
  `~/Desktop/secret_base_warp-v<version>.zip`, leaving out what
  `.gitattributes` marks `export-ignore` (the tooling).
