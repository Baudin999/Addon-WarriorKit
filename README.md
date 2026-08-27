![WarriorKit](art/warriorkit.jpg)

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
  share of the top row. Click the header for the breakdown of your own damage,
  right click it to swap damage for healing. The threat side is the client's own
  percentage, where 100 means that player takes the mob, and beside it the
  seconds until they get there at the rate they are gaining. Nothing is drawn but
  the rows, so it sits on the screen rather than over it. A row opens nothing,
  because there is nothing behind a row.
- **A swing timer, with the Slam press marked on it.** One bar per hand, filling
  towards the next swing off the combat log, and a green band on the main hand
  bar showing where to press Slam so the cast finishes exactly as the swing
  does. Press before the band and the Slam restart throws away the swing you had
  charged; press after it and the swing is pushed out to the end of the cast.
  The whole bar goes green while you are on the band. The cast time is the
  client's own, measured off your last Slam, and it follows your haste, so the
  band moves when Flurry lands. The bars are drawn for anybody holding a weapon;
  the band is a warrior's.
- **Your own cast bar.** One bar under the swing timer, the same width as it, in
  the same flat colours as everything else here. The spell on the left and the
  seconds left on the right, counted in tenths because that is what an interrupt
  is timed in, and a channel drains from the other end rather than filling. A
  cast that does not finish, because you were interrupted or walked out of range
  or the client refused the press, turns the bar red and holds it where it
  stopped for most of a second: an empty bar is what a cast that finished leaves
  behind, so a cast that died has to look like something else. Blizzard's own
  goes off the screen, and one tick box puts it back.
- **Party and raid frames that stop moving.** The same block your own frame
  wears, one per person you are grouped with: class colour on the health, the
  power under it, the name and the percent, and the role each one is playing
  said with Blizzard's own icon. The slot is decided by role and then by name,
  so the healer is in the same place in every group you are ever in, and it is
  worked out between fights and never during one. Left click targets, which is
  the point of the whole thing, because the Charge button casts Intervene at
  whoever you are looking at. Somebody out of range, dead, offline or running
  back drains to the empty colour and their block says which. A member the
  client will not name a power for gets no rail rather than an empty one. Where
  the addon guesses a role wrong, tell it: `/wk party role <name> healer` is
  kept for that character and beats everything the client thinks. Blizzard's
  party and raid frames go off the screen, and one tick box each puts them back.
- **A nag for what you forgot.** A row of squares over your character when
  something that should be up is not: a sharpening stone worn off either hand,
  Battle Shout lapsed, no food. It is not there at all when nothing is wrong, so
  seeing it is the whole message, and it is checked out of combat, which is when
  you can fix it. A shield is never nagged about. Hover a square and it tells you
  what is missing and what fixes it. Every entry has its own switch, per
  character, because a bank alt that will never own a sharpening stone does not
  need to be told about one forever, and one square you cannot silence teaches
  you to ignore the whole row. Add your flask and your elixirs
  by spell id, because these clients will not say that an aura came from one.
  In combat the row turns into the other question: the racial you own and have
  not pressed. Blood Fury on an orc and Berserking on a troll pulse in the middle
  of your screen until you spend them, because those are the two that are damage
  and the rest are cooldowns you spend when something happens.
- **A loot stream, and the combat log beside it.** Two columns of what just
  happened, newest at the top and older underneath, scrolled with the wheel. A
  loot row is the item's icon, its name in its own quality colour and how many
  dropped, with a stripe down the left in that same colour, so a pull reads as a
  ribbon before you read a word of it. A combat row is three columns off the
  combat log: what happened, who it was, and the number. The stripe says which
  way the blow went and a critical draws its number in gold with a mark after
  it, so the crit is not a hue you have to be able to see. Entering and leaving
  combat draw a band across the feed, which is what separates one pull from the
  one before it, and the band at the end says how long the fight took. Both
  feeds are the same widget, and adding a third is a file that captures
  something and a table of settings.

  Hover any row and you get the addon's own tooltip, not Blizzard's parchment.
  For an item that means the item's real text, stats and all, read out of the
  client and redrawn in this interface. Nothing in either feed is on a ticker:
  they change when something happens to you and when you scroll them, and never
  in between.
- **A breakdown of what this character actually does.** One row per ability,
  kept between sessions: how much of your damage it is, how often it lands, how
  often it crits, what it averages, and what stopped it when it did not land.
  The miss column names the outcome rather than pooling it, because a dodge and
  a parry mean different things and dodge is the one you can do something about.
  Shouts, stances and Charge are counted but not listed, since in a damage
  ranking they are a run of zeroes above the rows you came to read.

  It answers the questions a meter cannot, because a meter forgets the pull it
  was counting: whether Slam pays for the swing it costs, what share of your
  damage comes from Thunder Clap, whether that new axe changed anything. Rows
  can be read one level band at a time, since in this era the target's level
  drives crit and miss hard and a number pooled across grey trash and an elite
  is the average of two unrelated things.

  It opens in a window of its own, from a click on the meter header or from
  `/wk breakdown open`, and Escape closes it. `/wk breakdown` prints the top ten
  to chat instead.
- **A warrior bar loadout**, with a backup of whatever it replaced, plus an
  Edit Mode layout carried inside the addon.
- **Your own action bars, redrawn.** `/wk actionbars on` reads whichever bars
  you have up, stands one of ours up for each on the same action slots, moves
  your keys onto it, and hides Blizzard's behind it. Bar 1 still pages by
  stance. Every icon is drawn at the one size this client can draw sharp, and
  the border says whether a press would land. Your keybindings are read and
  never written, so `off` gives everything back with no reload.

  Then every bar is yours to shape. Fold its twelve into 1, 2, 3, 4, 6 or 12
  rows, so a bar is a row along the bottom or a column down the side. Pick the
  colour of the ground under the squares and how much of it you see, down to
  nothing, which leaves the icons standing on the world. Send a bar off the
  screen when a fight starts, or keep it off the screen until you hold shift,
  ctrl or alt, with its keys working the whole time either way. Unlock the bars
  and shift-drag one where you want it, or put its middle on the middle of the
  screen with a button, one axis at a time. Make the squares bigger or smaller,
  16 pixels to 54, and the panel says which sizes draw sharp. Every bar answers for itself, and one
  press puts the lot back to plain. While the settings window is open, whichever
  bar you have picked wears a blue rim on the screen, so you are never editing
  the one you thought was the other one.
- **Stripped bar art**, so the bars read as a row of icons. `/wk art on` puts
  the Blizzard art back.
- **A square minimap, as wide as you asked for.** The mask and the ring come
  off, the mousewheel zooms, and Blizzard's mail and tracking icons move to the
  corners. Every addon button on the edge of the map goes behind one square you
  press to open. Each is borrowed rather than taken: parent, position and the
  button's own anchoring are handed back the moment you turn it off.
- **A chat window, and one tab for the people you play with.** Name your wife,
  your kids or your guild officers in `/wk` and every line any of them says, in
  any channel, is copied to one tab of its own, together with the whispers you
  send them. The tab is not drawn until there is a name on the list. Beside it
  are two more: everything anyone said, and whispers on their own. Nothing else
  is in it. Loot, experience, system text and every addon's output stay in
  Blizzard's window, which is not hidden and not unregistered, because there is
  no safe way to tell those lines apart from the ones this window already drew.
  The conversation is taken out of Blizzard's frames through FrameXML's own
  message filter, so one tick box puts it back with no reload. Names are class
  coloured, a click on one answers it, item links still work, and nothing fades
  out after two minutes.
- **A voice channel joined when you log in.** Pick your party or raid channel,
  or any community or guild stream you are in, the same list the client's own
  Chat Channels window puts a voice button on. The addon activates it at login
  and asks again whenever it could have appeared, which for a party channel is
  when you group up and for a community one is when the first person joins. It only ever joins:
  nothing here leaves a channel, mutes anyone or moves a volume. Blizzard's
  voice chat has no channels you can name, so what there is to pick is short,
  and `/wk` says so.
- **A filter for the red text in the middle of the screen.** Tick the messages
  you do not need and they stop drawing. Nothing is hidden that you did not
  tick, the list is shared by every character on the account, and one press
  silences what a missed charge shouts at you.
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

The Charge button, the bar loadout and the Slam band are warrior only, and on
any other class they are not there at all: no button, no icon in the world, no
key taken, no band on the swing bar, and your action targeting setting left
exactly where you had it. Everything else on this list works the same on a
hunter as it does on a warrior, the swing bars included.

## Install

Unzip into `Interface/AddOns`, so that the folder is
`Interface/AddOns/WarriorKit` with `WarriorKit.toc` directly inside it.

## Repo layout

    src/        the addon, exactly what the client loads
    src/Media/  the art the addon ships, today one 64x64 icon
    docs/       the engineering notes, including the file map and API caveats
    scripts/    check.sh, bake-ui.sh, release.sh
    art/        the project art: the banner above, the avatar, the plaque

`art/` is for GitHub and the CurseForge project page and is not shipped, which
is what separates it from `src/Media/`. The client reads BLP and TGA, so a JPEG
in the addon folder would be dead weight.

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
