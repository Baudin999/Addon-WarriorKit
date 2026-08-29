# Todo

Each piece is built by one agent in its own worktree under `.worktrees/`,
on a branch named `worktree-<name>`, and merged into main when
`./scripts/check.sh` comes back at zero. The worktrees stay after the merge.

## Landed

A title and the commit that finished it. Where an item took several commits the
hash is the last of them. What was wrong and what fixed it is in
`docs/CHANGELOG.md` and `docs/README.md`, what is still unconfirmed in game is
in the README's untested list, and the full text of each item is this file at
`e7ef4ca` for 1 to 6, 8, 11 and 12, and at `ca59a77` for 7, 9 and 13.

1. Weapon swing timer. `8be9a43`
2. Deep Wounds missing from the enemy bar debuffs. `05e40ec`
3. Overpower drawn as ready when it is not. `dbbcd69`
4. Missing buff nag, including racials. `042df6c`
5. Enemy cast bar. `89a3e45`
6. Party and raid frames, ours off a secure group header. `e3de603`
7. Cooldown row for the long cooldowns, out of the class registry. `2245a01`
8. The target block linked to the player block, reflected about the middle of
   the screen rather than pinned a fixed distance off it. `2a999b5`
9. Our own buff and debuff rows on the skinned frames. `1871fa6`
11. Split `Skin.lua`, which had three subjects and came apart into four.
    `a5624de`
12. The chat window, reimagined as a rail of rooms. `1c4de0e`
13. What the class split left behind, down to the `Class.Label()` fallback.
    `fc6c0e5`
14. check.sh derives its class shapes from `Class/*.lua` rather than naming
    them. `371d82d`

Item 10, the Slam mark carried out of item 1, was dropped rather than
finished. Nothing tracks it now. Its text is in this file at `d05546c`.

## Open

Items 15 to 22 came out of an architecture review on 2026-08-29. Every one is a
duplication or a rule the addon already believes in and does not enforce. None
is a bug: the addon draws the right thing today. They are the shapes that make
the next change cost more than it should, ordered so the one that drags the most
out with it goes first.

15. A placeable HUD frame, named at last.

    Eleven parts of this addon put a rectangle on the world that you can unlock
    and drag, and none of them share a line of it. Seven write the same block by
    hand: `SetMovable`, `SetClampedToScreen`, an `OnDragStart` that checks
    `ns.db.locked`, an `OnDragStop` that rounds the point and writes
    `ns.db.<x>Point`, a `grab` box over the whole frame, a `title` label at
    `ns.UI.OutlineFloor()`, and a `Lock()` that toggles `RegisterForDrag` and
    shows or hides both. `src/Buffs/Nag.lua:632`, `src/Cooldowns/Row.lua:340`,
    `src/Hover/Sheet.lua:202`, `src/Meter/Window.lua:616`,
    `src/Progress/Rails.lua:234`, `src/Swing/Gauges.lua:390` and
    `src/UnitFrames/PlayerCast.lua:317`. A clone scan matches them character for
    character, comments included: `Cooldowns/Row.lua:351` and
    `Swing/Gauges.lua:401` carry the same note about a drag landing wherever the
    cursor was, with one noun changed.

    This is the GameTooltip story in `scripts/check.sh:457` happening a second
    time. Nothing is wrong at any one site, which is exactly why it reached
    seven.

    `UI.Window` exists for chrome windows. Nothing exists for this. The shape
    wanted is one call, something like
    `ns.UI.Placeable(frame, { key = "swingPoint", title = "WarriorKit swing",
    onMoved = Gauges.Apply })`, returning the lock and reset the feature
    registers. Three things come out with it. The seven `Lock()` bodies become
    one. The seven copies of
    `local function Whole(value) return math.floor(value + 0.5) end`
    (`UnitFrames/Group.lua:316`, `UnitFrames/PlayerCast.lua:124`,
    `Buttons/Placing.lua:157`, `Buffs/Nag.lua:160`, `Hover/Sheet.lua:40`,
    `Cooldowns/Row.lua:76`, `Progress/Rails.lua:100`) become `ns.UI.Whole`
    beside `ns.UI.Round`, which is a different function and is why nobody
    reused it. And the five `Reset` bodies that re-type their default
    coordinate rather than asking for it (`Nag.Reset`, `Row.Reset`,
    `Sheet.Reset`, `MeterWindow.Reset`, `Group.Reset`) stop being a second copy
    of a number that already sits in a `defaults` table. All five pairs agree
    today and nothing checks that they keep agreeing; `SwingGauges.Reset`,
    `Rails.Reset` and `PlayerCast.Reset` already call `ns.DefaultFor` and are
    the ones written right.

16. `ns.RegisterUnitEvent` in Core, where the other thirty shims live.

    `src/Core/Core.lua` is the client shim layer and says so. It holds
    `ns.HasThreat`, `ns.HasCastInfo`, `ns.ContainerSlots` and about thirty more,
    each one a question the two clients answer differently, asked once. And then
    six files ask `type(events.RegisterUnitEvent) == "function"` inline and
    write their own two-branch registration underneath:
    `src/UnitFrames/PlayerCast.lua:548`, `src/Buffs/Nag.lua:620`,
    `src/Swing/Swing.lua:304`, `src/Swing/Gauges.lua:379`,
    `src/Cooldowns/Row.lua:328`, `src/Swing/Slam.lua:356`.

    One function in Core taking a frame, an event and a unit, falling back to
    the plain register where the client has no filtered one, deletes all six.
    This is the cheapest item in the list.

17. The slash dispatchers, off a table rather than a chain of ifs.

    `Command.Number` abstracts the parsing and stops there. Its 34 callers then
    each hand-write the same four steps: write `ns.db.<key>`, call the module's
    `Apply`, `ns.Print` a sentence, `return`. `src/Swing/Feature.lua:44`,
    `src/Cooldowns/Feature.lua:35` and `src/Progress/Feature.lua:44` are three
    identical zoom handlers differing in the db key, the apply call and one
    noun.

    What it costs is on the shape report. `SkinWord` is 119 lines and 37
    branches, `BarsWord` 97 and 37, `BuffWord` 97, and two of them hold entries
    in the `scripts/shape.lua` allow-list reading "a slash dispatcher, one
    branch per word". A declarative table of
    `{ word, key, low, high, apply, say }` handed to a shared runner retires
    both entries instead of raising a number, which is the direction that list
    is meant to move.

18. One ticker, and a HOT list derived from it.

    Twelve files write the same throttle: accumulate the delta, compare it to an
    interval, zero it, call, and in four of them wrap the call in `Perf.Start`
    and `Perf.Stop`. `src/Charge/Marker.lua:201`, `src/Meter/Window.lua:647`,
    `src/Perf/Perf.lua:247`, `src/Feeds/Stream.lua:290`, and the rest behind
    named `OnUpdate` locals.

    A `ns.UI.Ticker(interval, name, fn)` collapses them, and that is the smaller
    half. The larger half is `HOT` in `scripts/check.sh:208`: about ninety-five
    function names, written out by hand, which is a transitive closure a person
    is maintaining. `check.sh:481` checks that a file with an `OnUpdate` names
    something in HOT, which is a good first cut and does not catch the failure
    that matters. A hot function that grows a new callee nobody added to the
    list takes the guard scan quietly off that code. Registering every ticker
    through one call is what makes the closure derivable instead of typed.

19. `UI.Window` re-zooms its own frame.

    Four windows carry the same pair of lines,
    `UI.Rezoom(window.frame, UI.WindowZoom())` followed by
    `window.zoom = UI.WindowZoom()`, inside their own `UI.OnRescale` listener:
    `src/Breakdown/Window.lua`, `src/Quests/Window.lua`, `src/Chat/Window.lua`,
    `src/Mail/Window.lua`. `UI.Window` made the frame. It should keep the frame
    on the grid, and the four callers should register nothing. What is left in
    each listener afterwards is the part that is genuinely the caller's: Quests
    re-fits and refreshes, Chat relays out, the other two have nothing to do.

20. `EachTexture` into Core, beside `ns.Strip`.

    `src/Artwork/Artwork.lua:59` and `src/UnitFrames/Art.lua:248` are the same
    pcall-guarded walk over a frame's texture regions, differing only in Art's
    `keep` set. Artwork's copy opens with "pcall guarded for the same reason
    `ns.Measure` is", which is the author noticing where it belongs and not
    moving it. It goes next to `ns.Strip`, `ns.Unstrip` and `ns.Blocked`, which
    are the three calls it exists to feed.

21. Two layering rules, gated rather than commented.

    `src/UI/Window.lua:62` and `src/UI/Tooltip.lua:147` both say the UI layer is
    not allowed to know the name of a setting, and both are keeping their word:
    `ns.db` appears nowhere under `src/UI/` except in those two comments. That
    is a one-line grep in `check.sh` and it passes today, which is the best
    possible moment to write it, because a rule added while it is already
    satisfied costs nothing and a rule added after it breaks costs a refactor.

    The second is item 16's rule once item 16 has landed: outside
    `src/Core/`, no file probes the client for a call it means to make. Both
    belong with the GameTooltip rule, which is the same idea already written
    down and already enforced.

22. `Core/Menu.lua` registers a feature from inside Core.

    `src/Core/Core.lua:8` promises that Core knows nothing about any feature and
    that an eighth part must not mean editing this file. Twenty-five parts keep
    that promise by registering from `<Folder>/Feature.lua`. `Core/Menu.lua:275`
    is the one that does not. It is a small file and a real feature, with a
    slash word and a status line, and it wants a folder like everything else.
    Worth doing last, when the four items above have already proved the
    registry does not need Core's help.

## Deliberately not on this list

The architecture review turned up two more repeats and both are right as they
stand. `src/Progress/Progress.lua:70` and `src/Quests/Client.lua:43` hold the
same four-line probed call, and the comment above the first one argues that
each is written against its own returns and that a prober in Core would be a
call every part reaches through rather than a seam each part draws. That
argument holds. `src/UI/Feed.lua`, `src/UI/Log.lua` and `src/UI/Stack.lua` each
open by saying why they are not one of the others, and each of those three
arguments holds too.
