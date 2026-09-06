# The CurseForge project page

This file is the text of the Description tab on the CurseForge project, id
1675955. The API that `scripts/deploy.sh` uploads through can send a file and a
changelog and nothing else, so the description is pasted by hand. Edit it here
first, then paste, so the page and the repo do not drift.

Everything below the line is the page.

---

## This is an alpha. Read this before you install it.

WarriorKit replaces most of the WoW interface. It is early, it is being worked
on daily, and it has not been through a wide test. Install it if you want to
help find what is broken. Do not install it the hour before a raid.

What alpha means here, concretely:

- Frames move and change shape between versions, and a layout you arranged by
  hand may not survive an update.
- Your settings live in SavedVariables and are read back by name. A setting
  that gets renamed comes back as its default rather than as what you set.
- The client hides Lua errors unless you turn them on. If a part of the addon
  is simply missing, run `/console scriptErrors 1` and reload before you report
  it, so the report has the error in it.
- It replaces Blizzard frames rather than hiding them. Turning a part off puts
  the Blizzard version back, and every part can be turned off in `/wk`.

## Bugs and requests go on GitHub

https://github.com/Baudin999/Addon-WarriorKit/issues

Open an issue there rather than a comment here. Comments on this page are not
tracked and get lost between file uploads; an issue stays open until the thing
is fixed. Useful reports say which client you are on (TBC Anniversary 2.5.6 or
Classic Era 1.15.9), your class, and what you did just before it happened. The
Lua error text is worth more than everything else put together.

## What it is

A full UI replacement for TBC Anniversary (2.5.6) and Classic Era (1.15.9).
The parts most people notice first:

- **One Charge button** that casts Charge, Intervene or Intercept depending on
  the stance you are in and what you are looking at.
- **A character sheet with four tabs** on the C key: gear with its totals,
  skills, standings and weapon loadouts. It works out your actual miss chance
  against a boss and against your own level, which no client on either version
  has ever put on the sheet.
- **A socketing window** that lists every gem in your bags against the holes in
  the piece you shift-clicked, and says by name what applying costs you before
  you spend it. TBC only.
- **A dungeon log** on Shift-L, where neither client has an adventure guide:
  two hundred and thirty seven bosses across forty dungeons, the dungeon map
  cut into floors with a mark per boss, and the drop list per boss.
- **Weapon loadouts on one key each**, stance and both hands in a single press.
- **Raid target icons on plain keybinds.**

The warrior-only parts are the Charge button, the bar loadout and the Slam
band. On any other class they are not built at all: no button, no key taken,
nothing hidden. The rest works the same on every class.

## Install

Unzip into `Interface/AddOns` so that the folder is
`Interface/AddOns/WarriorKit` with `WarriorKit.toc` directly inside it.

[Questie](https://www.curseforge.com/wow/addons/questie) is optional and worth
having. It adds the turn-in pin on the map, drop rates under quest items, and a
party member's progress on a shared quest. Nothing here needs it, and every
part that would ask says so in the panel when Questie is not answering.

## Licence

MIT. Source, issues and the full readme:
https://github.com/Baudin999/Addon-WarriorKit
