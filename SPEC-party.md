# SPEC: the party and raid units

Todo item 6. This is the design, not the build.

## What is being asked for

Blocks for the people you are grouped with, in the addon's own look, drawn by
the addon rather than by the client. Class colour on the health fill. The role
each one is playing, said with an icon. Rage or mana under the health. Blizzard's
own party and raid frames off the screen. A place in the list that is decided by
role rather than by who invited whom, so the healer is in the same slot in every
group you are ever in. Switches for all of it in the panel.

## The one decision everything else follows from

These are our frames, built from `SecureGroupHeaderTemplate`, not Blizzard's
frames wearing our skin.

`UnitFrames/Skin.lua` skins the player, target and target of target because
those three frames carry targeting, the dropdown and a cast bar, and a frame
drawn from scratch would have to earn all of that back. That argument does not
carry over. `PartyMemberFrame1` is bound to `party1` in XML and there is no
supported way to point it at anyone else, so the moment the order is decided by
role rather than by party index, the client's frames cannot draw it. The raid is
worse: `CompactRaidFrameContainer` runs its own layout pass and puts back
whatever an addon moves.

`SecureGroupHeaderTemplate` is the answer the client already ships for this. It
creates one secure unit button per member, calls `RegisterUnitWatch` on each,
and shows and hides them itself as the roster changes, including in combat.
Every attribute that decides the shape of the list is written out of combat and
the header does the rest. Both flavours have it: `SecureGroupHeaders.lua` is in
FrameXML on 2.5.6 and on Classic Era.

What this costs is that the header is a Blizzard template and the addon has
never leaned on one. `Charge/Icon.lua` and `Buttons/Bars.lua` already carry the
combat-deferred secure write pattern, so the shape is familiar even if the
template is not.

## Files

Three new ones, and one move.

`Unit/Role.lua` answers what role a unit is playing. It goes under `Unit/` for
the reason `Roster.lua` did: it is a question about a unit, the answer is wanted
per member per layout, and the meters will want the same answer the first time
somebody asks for a role column. Loads after `Roster.lua`.

`UnitFrames/Group.lua` is the header, its attributes, where the block of frames
sits, and the slot order. It knows nothing about how one member is drawn.

`UnitFrames/Member.lua` is one member's block: build it, lay it out, tick it. It
knows nothing about a header, an order or a setting other than the sizes handed
to it. This is the same seam `UnitFrames/Cast.lua` sits on.

The move is `Meter/Spec.lua` to `Unit/Spec.lua`. It already reads talent trees
for you and for anyone the client will let you inspect, which is the only source
of a real role on a client with no roles. It cannot stay under `Meter/`, because
`Unit/Role.lua` loads long before that folder and a part may not name a file
outside its own tree. The file itself changes in two ways: `ns.MeterSpec` becomes
`ns.Unit.Spec`, and it grows one function that answers the winning tree's index
and points next to the icon it already answers. `Meter/Window.lua` is the only
caller and takes a one word rename. The alternative is `Role.lua` resolving
`ns.MeterSpec` at call time the way the tickers resolve `ns.Perf.Start`, which
works and is a worse answer, because the dependency is real and would be hidden.

## Role, on a client that has none

Four sources, best answer first, cached per GUID.

An override the player typed wins over everything. `/wk party role <name>
tank|healer|dps` and a picker in the panel, kept per character, because
inspection fails in the exact case where you already know the answer.

`UnitGroupRolesAssigned(unit)` next, where the client has the function and
answers something other than `NONE`. On 2.5.6 that is the group finder's
assignment and it is right when it is set. On Era it is usually `NONE` and costs
one call.

`GetPartyAssignment("MAINTANK", unit)` next, which is the raid's own main tank
flag and is on both clients.

Then talents, through `Unit/Spec.lua`, mapped by a class and tree table. Three
trees per class and nine classes is twenty seven entries, of which only the ones
that are not damage need saying: warrior tree three, paladin trees one and two,
priest trees one and two, druid trees two and three, shaman trees one and three.
Everything else is damage.

The floor is the class. A priest with no talents read yet is a healer, a mage is
damage, a warrior is damage. That is a guess and it is the right guess, because
the alternative is a member with no slot until an inspect lands, and a frame
that arrives late is a frame that moves.

Which brings up the rule that makes "fixed placing" true rather than aspirational:
the order is recomputed only out of combat. An inspect that resolves mid pull is
recorded and changes nothing on the screen until the fight ends. The list settles
over the first minute you are in a group and then stops moving.

## The order

Tanks, then healers, then damage. Inside a band, by name. Not by party index, not
by the order the client hands the units over, and not by group number unless you
ask for it.

By name inside the band is the part worth defending. It is arbitrary as an
ordering and it is the only one that is stable: the same five people produce the
same five slots in every group they are ever in together, whoever formed it and
whoever zoned in first. Party index does not do that. Sorting by class does not
either, because a class can be two roles.

`/wk party order group` switches the raid to group number, which is what somebody
running a twenty five man with assignments per group actually wants. Party is
always by role.

Your own frame is not in the list by default. `Skin.lua` already draws you as a
block, and two of your own frames on one screen is the exact complaint that
`UnitFrames/Blizzard.lua` exists to answer. `/wk party self on` puts you in, at
your own role's slot.

## What one block draws

The same block the skin draws, at the same default size, because they are the
same instrument and a party frame that does not match the player frame reads as
a second addon.

- Health fill in `Color.Class`, which is already under the luminance ceiling, so
  the name on it reads at every state of the bar.
- Power under it at `HEALTH_SHARE`, in `Color.power[powerType]`, which is rage
  red, mana blue and energy yellow and is already keyed by the number
  `UnitPowerType` returns. A member with no power draws no rail rather than an
  empty one, which is `Unit.Power` answering a max of zero.
- Name, left, in `Color.paper`. Health percent, right.
- The role icon, on the portrait side, from `Interface\LFGFrame\UI-LFG-ICON-ROLES`
  at the standard quadrants. Blizzard's own art, because it is the art everyone
  in the group already recognises, and because the alternative costs a rerun of
  `bake-glyphs.sh` and three more codepoints in `Media/Glyphs.ttf`. If a flavour
  turns out not to carry the texture, the glyph font is the fallback and the
  harness is where that gets caught.
- Out of range, dead, offline and ghost all draw the same way: the fill goes to
  the track colour and the name says which. `UnitInRange` is on both clients.

Nothing is rebuilt per tick and nothing allocates on one. Every widget write is
guarded on the value already on the frame, which `check.sh` will enforce as soon
as the new tick functions are in `HOT`.

## Taking Blizzard's off

Two lines in `UnitFrames/Blizzard.lua`, which is the file that already holds one
switch per thing you can see twice.

`hideBlizzParty` takes `PartyMemberFrame1` through `4`. Four entries against one
key, the way `BuffFrame` and `TemporaryEnchantFrame` already share one.

`hideBlizzRaid` takes `CompactRaidFrameContainer` and `CompactRaidFrameManager`.
This one has a catch worth a hint under the switch: the manager re-shows the
container on its own layout pass, so the entry needs a hook on that pass as well
as the strip, or the frames come back the first time somebody joins. The strip
itself is `ns.Strip`, which already defers to `PLAYER_REGEN_ENABLED` when combat
refuses.

Both ship on, for the reason the other five ship on: the addon is drawing the
thing, and shipping with two copies on screen is shipping a bug.

## Clicking one

Left click targets. Right click opens the unit menu. Ctrl click marks.

Marking is the half that would go missing quietly. `Marking/Marking.lua` hooks
frames by name and `PartyMemberFrame1` through `4` are already on that list, so
hiding them takes ctrl click marking on a party member off the screen with them.
The fix is one exposed function, `ns.Marking.Watch(frame)`, called from
`UnitFrames/Feature.lua` as each button is built, because a behaviour file may
not name a file outside its own folder and `Feature.lua` is where that rule puts
it.

Targeting is the point of the whole item. `todo.md` says it plainly: the Charge
button casts Intervene at whoever you are looking at, and until now there was no
fast way to look at a party member.

## Settings

Defaults, in the shape `Feature.lua` already uses.

    party = true
    partySelf = false
    partyOrder = "role"        -- "role", or "group" for the raid
    partyRoleIcon = true
    partyWidth = 168           -- matches skinWidth
    partyHeight = 34           -- matches skinHeight
    partyGap = 4
    partyGrow = "down"
    partyRaidColumns = 8
    partyRaidPerColumn = 5
    partyZoom = 1
    partyRange = true
    partyPoint = { "LEFT", "UIParent", "LEFT", 40, 120 }
    partyRoles = {}            -- per character overrides, name -> role
    hideBlizzParty = true
    hideBlizzRaid = true

Party and raid share one header and one set of numbers, except the two that only
mean anything in a raid. A party of four at 168 pixels wide is the player block
repeated. Forty of those is not a screen, so the sizes are settings and the raid
is expected to run smaller.

The block is dragged when the frames are unlocked and saves its point, exactly
as `playerCastPoint` does, and it goes on the grid through `ns.UI.Adopt`.

## What the gates need

Both TOCs get the four files in the same place, or `check.sh` fails on the list
comparison before anything else runs.

Every tick function in `Group.lua`, `Member.lua` and `Role.lua` goes in `HOT`.

A new harness section, `38-party-raid`, and its name in `runner.lua`. This is the
part of the work that is easy to underestimate. The stub client has no group
tokens, no `UnitGroupRolesAssigned`, no `GetPartyAssignment` and no secure
header, so the harness needs a party and a raid to exist before a single
assertion can run. A fake header is about forty lines: hold the attributes, build
a child per unit, and let the section drive `Group.Rebuild()` directly. What the
section then asserts is the order under three rosters, the class colour and power
colour on a fill, the role icon's crop, that a member with no power draws no
rail, and that a tick allocates nothing.

The panel section obeys the rules `check.sh` greps for: `ui.Section(title,
group)`, `ui.Size` for pixels, `ui.Count` for counts, `ui.Zoom` for the zoom, and
a named font role on every string.

## Not in this item

Aggro. `Unit/Threat.lua` already answers who has it, and a border that says a
party member pulled is one setting and about fifteen lines. It is worth doing and
it is worth doing after the frames exist.

Buffs and debuffs on a party block. `UI/Aura.lua` is one square and every row in
the addon is made of it, so the row is cheap. Deciding which of a raid's auras is
worth a square is not, and that is a separate argument.

Pets, and party target frames. Neither is asked for.
