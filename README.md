# WarriorKit

A warrior addon for TBC Anniversary (2.5.6) and Classic Era (1.15.9).

- **One Charge button.** It casts Charge, Intervene or Intercept depending on
  what you are looking at, and out of combat it aims by camera rather than by
  target.
- **Easy raid marking.** Bind your raid target icons to simple buttons.
- **One key that switches target and swings.** TAB cycles and stops there. Bind
  a key in `/wk` and it takes the next enemy and starts the attack on it.
- **Weapon loadouts, one key each.** A press puts you in a stance and puts that
  loadout's pair of weapons in your hands. Three come ready, one per stance, and
  you can add your own. Drag a weapon or a shield onto a hand on the paperdoll
  in `/wk`.
- **Threat-coloured enemy bars.** They replace the Blizzard nameplate and carry
  a tag saying what the kill is worth.
- **A damage meter and a threat meter, side by side.** One row per player: the
  spec icon, the name, the number, and a class-coloured bar as long as their
  share of the top row. Clicking the header swaps damage for healing. The threat
  side is the client's own percentage, where 100 means that player takes the
  mob, and beside it the seconds until they get there at the rate they are
  gaining. Nothing is drawn but the rows, so it sits on the screen rather than
  over it. There is no breakdown to open, because there is nothing behind a row.
- **A warrior bar loadout**, with a backup of whatever it replaced, plus an
  Edit Mode layout carried inside the addon.
- **Your own action bars, redrawn.** `/wk actionbars on` reads whichever bars
  you have up, stands one of ours up for each on the same action slots, moves
  your keys onto it, and hides Blizzard's behind it. Bar 1 still pages by
  stance. Every icon is drawn at the one size this client can draw sharp, and
  the border says whether a press would land. Your keybindings are read and
  never written, so `off` gives everything back with no reload.
- **Stripped bar art**, so the bars read as a row of icons. `/wk art on` puts
  the Blizzard art back.
- **Four chores done for you.** Corpses empty in one go instead of one slot at
  a time. Grey items sell themselves at every merchant. Damaged gear pays for
  its own repair at any merchant who mends, out of the guild bank where your
  rank allows it and out of your purse where it does not. Hold shift as you open
  a merchant to skip both. The camera pulls back four times the base distance
  instead of 1.9.
- **`/wk destroy` clears out finished quest items.** One card at a time, with
  the quest it came from written on it, and a destroy and a skip. It reads
  Questie's database to work out which quest, so it needs Questie installed.

`/wk` opens the settings panel. Everything in it has a slash command too.

The Charge button and the bar loadout are warrior only, and on any other class
they are not there at all: no button, no icon in the world, no key taken, and
your action targeting setting left exactly where you had it. Everything else on
this list works the same on a hunter as it does on a warrior.

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
