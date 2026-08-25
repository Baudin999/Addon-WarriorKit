# WarriorKit

A warrior addon for TBC Anniversary (2.5.6) and Classic Era (1.15.9).

- **One Charge button.** It casts Charge, Intervene or Intercept depending on
  what you are looking at, and out of combat it aims by camera rather than by
  target.
- **Ctrl-click raid marking.** Ctrl-click a unit to mark it. No menu.
- **Threat-coloured enemy bars.** They replace the Blizzard nameplate and carry
  a tag saying what the kill is worth.
- **A warrior bar loadout**, with a backup of whatever it replaced, plus an
  Edit Mode layout carried inside the addon.
- **Stripped bar art**, so the bars read as a row of icons. `/wk art on` puts
  the Blizzard art back.

`/wk` opens the settings panel. Everything in it has a slash command too.

## Install

Unzip into `Interface/AddOns`, so that the folder is
`Interface/AddOns/WarriorKit` with `WarriorKit.toc` directly inside it.

## Repo layout

    src/        the addon, exactly what the client loads
    docs/       the engineering notes, including the file map and API caveats
    scripts/    check.sh, bake-ui.sh, release.sh

`src/` is what a client sees. Link it in rather than copying, so there is one
copy to edit and every client loads it:

    ln -s "$PWD/src" "/path/to/World of Warcraft/_anniversary_/Interface/AddOns/WarriorKit"

## Developing

    ./scripts/check.sh

Syntax, TOC agreement, version agreement, saved-variable declarations, a guard
check on every write reachable from an OnUpdate, and luacheck. Zero warnings
and zero errors is the bar, and it passes, so any finding is yours.

    ./scripts/release.sh

Builds `dist/WarriorKit-<version>.zip`. Add `--upload` to publish it to
CurseForge. It refuses to build anything if `check.sh` fails.

Commits run the gate. `scripts/hooks/pre-commit` is tracked, and wired up with

    git config core.hooksPath scripts/hooks

which is already set in this clone. A broken tree cannot be committed without
`--no-verify`.

Version lives in three places on purpose, `ns.version` in `src/Core/Core.lua`
and `## Version:` in both TOCs. `check.sh` fails if they drift, which is how
the 1.1-versus-1.2 split got caught.

## Licence

MIT. See `LICENSE`.
