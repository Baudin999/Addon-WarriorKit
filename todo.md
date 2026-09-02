# Todo

Each piece is built by one agent in its own worktree under `.worktrees/`,
on a branch named `worktree-<name>`, and merged into main when
`./scripts/check.sh` comes back at zero. The worktrees stay after the merge.

## Landed

A title and the commit that finished it. Where an item took several commits the
hash is the last of them. What was wrong and what fixed it is in
`docs/CHANGELOG.md` and `docs/README.md`, what is still unconfirmed in game is
in the README's untested list, and the full text of each item is this file at
`e7ef4ca` for 1 to 6, 8, 11 and 12, at `ca59a77` for 7, 9 and 13, at
`44c79ef` for 15, at `a7772af` for 16, at `c37c149` for 19, at `b5d2277` for
17, at `30a42cb` for 28 and at `2210d8f` for 18. Items 14, 23 and 31 were never
written longer than they are here.

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
15. A placeable HUD frame, named at last. `80528bc`
16. `ns.RegisterUnitEvent` in Core, where the other thirty shims live.
    `3df1df1`
17. The slash dispatchers, off a table rather than a chain of ifs. `abddb67`
19. `UI.Window` re-zooms its own frame, and every screen sizes on its own.
    `da4a01a`
23. A ceiling only moves down, in `scripts/ratchet.lua`. `271f8e6`
28. One Questie probe, in Core, and a gate that keeps it one. `07c4401`
18. One ticker, and a HOT list walked rather than typed. `903350d`
31. The four tick-path exemptions, all four allow-listed by name. `395e38a`

Item 10, the Slam mark carried out of item 1, was dropped rather than
finished. Nothing tracks it now. Its text is in this file at `d05546c`.

Items 23 and 31 were never in the Open list. Both came out of reading this file
against the code on 2026-09-02, and their numbers are where they were worked
rather than where a review found them.

Item 31 is item 18's gate read back. Item 18 counted its two markers exactly and
let scripts/ratchet.lua refuse a raise, which left no legal way to add a ninth
`cold:` in any number of commits: the raise fails the ratchet, and lowering the
number first fails the equality. Meanwhile the per-line `-- unguarded:` and
`-- allocates:` exemptions the same scan honours were uncounted, fifteen of them.
The strict door was shut and the unmeasured one was open, which is where the
next exemption would have gone. All four are path-keyed allow-lists now, one
entry per marked function, counted per file and cross-checked against what src/
carries, so an addition is a new key and reviewable and a raise still fails.

## Open

Items 16 to 22 came out of an architecture review on 2026-08-29. Items 16, 17,
18 and 19 landed on 2026-09-02 and are above, with 23. Item 18 had undercounted
the hand-written closure: it said about ninety-five function names and there
were two hundred by the time it was worked, which is the same lesson item 15
taught in the other direction. Read an item against the code before working it. Every one is a duplication
or a rule the addon already believes in and does not enforce. None is a bug: the
addon draws the right thing today. They are the shapes that make the next change
cost more than it should, ordered so the one that drags the most out with it
goes first. Item 15 undercounted its own sites by five and asked for a fix
`0312cf3` had already made.

20. `EachTexture` into Core, beside `ns.Strip`.

    `src/Artwork/Artwork.lua:59` and `src/UnitFrames/Art.lua:248` are the same
    pcall-guarded walk over a frame's texture regions, differing only in Art's
    `keep` set. Artwork's copy opens with "pcall guarded for the same reason
    `ns.Measure` is", which is the author noticing where it belongs and not
    moving it. It goes next to `ns.Strip`, `ns.Unstrip` and `ns.Blocked`, which
    are the three calls it exists to feed.

21. One layering rule, gated rather than commented.

    Item 16 has landed, so the rule it leaves behind can be gated. Outside
    `src/Core/`, no file probes the client for a call it means to make. It
    belongs with the GameTooltip rule and with the `src/UI/` rule item 15
    wrote, which are the same idea already written down and already enforced.

    Item 28 gated the Questie half on 2026-09-02: `QuestieLoader` and
    `ImportModule` outside `Core/Core.lua` fail `check.sh`. The client half is
    the work that is left, and it is not one grep. `_G.` reads 286 times outside
    `src/Core/` and most of them are a frame looked up by name rather than a
    call probed for, so the rule has to name the shape it refuses, which is
    `type(_G.Something) == "function"` on a call the file then makes. Count
    those first: a gate with 286 violations is a warning wearing a gate's
    clothes.

    The other rule this item asked for is one of those two now.

    Item 18 added a third of the same kind on 2026-09-02: a frame handler names
    a function and never opens a closure in place. It is the same shape as the
    two above, a rule the addon already believed in, and it is worth reading
    before this one is written because it shows what the client half costs. That
    gate was one grep and it worked because the shape it refuses is exact.

22. `Core/Menu.lua` registers a feature from inside Core.

    `src/Core/Core.lua:8` promises that Core knows nothing about any feature and
    that an eighth part must not mean editing this file. Twenty-five parts keep
    that promise by registering from `<Folder>/Feature.lua`. `Core/Menu.lua:275`
    is the one that does not. It is a small file and a real feature, with a
    slash word and a status line, and it wants a folder like everything else.
    Worth doing last, when the three items above have already proved the
    registry does not need Core's help.

Items 24 to 30 came out of a second architecture review on 2026-09-02, run
against three measurements rather than a reading: LCOM over shared module state,
a token clone detector across every pair of files, and fan-in and fan-out on
`ns`. Item 28 landed the same day and is above. Two of the three came back quiet
and that is worth writing down. `ns.db` is not the god object it looks like: 215
keys read, and only four read from outside the folder whose `defaults` declares
them, of which `locked` is Core's and meant to be. File-level LCOM4 is 1 almost
everywhere, so the folders hold together. What the measurements did find is one
file that is three modules and five mechanisms each written out between two and
nine times, and they are below in that order.

24. `UnitFrames/EnemyBars.lua` is three modules in one file.

    2,450 lines, 72 top-level functions, 25 mutable module locals, and 26
    distinct `ns.*` names, which is the largest fan-out in the addon. Its own
    section headers name five subjects, at `:269`, `:578`, `:774`, `:1482` and
    `:1734`, and two of the five touch none of the other three's state.

    The tracked spell list at `:269` is 17 functions over `trackedNames`,
    `trackedIcons` and `unresolved`, and nothing else. It is a saved list with
    Add, Remove, Reset, Repair and Resolve on it, no frame anywhere in it, and
    it is sitting inside a nameplate widget.

    The Blizzard plate handling at `:1482` is 8 functions over `stripped`,
    `pending` and `passThrough`, and it shares exactly one name, `stripped`,
    with the modes block under it. It is the ninth `Blizzard.lua`, filed under a
    different name and inside the file it hides plates for.

    Worth measuring the way it was found, because a file-level LCOM4 reads this
    file as cohesive: the call graph glues the three together even though the
    state does not. On state alone it is five components.

25. Nine `*/Blizzard.lua` files, one contract, written down nowhere.

    2,292 lines. Seven of the nine define the same three public calls, `Wanted`,
    `Apply` and `Describe`, over the same two private ones, `Frame` and
    `Remember`. Two mechanisms sit under that: park the frame off the screen at
    no alpha, or put it in the attic and take its key.

    `src/Mail/Blizzard.lua:65-160` and `src/Merchant/Blizzard.lua:68-198` are
    the same 90 lines of park. Run both through `diff` with the words `mail` and
    `merchant` substituted out and what is left is Merchant's drift check and
    two spellings of the same early return. `src/Map/Blizzard.lua:55-190` and
    `src/Quests/Blizzard.lua:60-165` are the same cage and key swap, and the
    only real difference is that Map opens the dungeon window when you are
    standing in one.

    The consequence is already on disk. Five of the seven end with
    `ns.BlizzHide.Also(Blizz.Apply)`; Mail and Quests do not, and are driven
    instead by seven hand-written `Apply()` calls across their `Feature.lua`
    and `Window.lua`. Nothing says whether that is deliberate, and the only way
    to find out is to open seven files side by side.

26. Taking a key off the client, written nine times.

    `SetOverrideBindingClick` onto a secure button, `ClearOverrideBindings`
    before it, a `Holds(key)` that reads the override layer back through
    `GetBindingAction` rather than trusting the set, and a record of the binding
    that got displaced. That is four calls with a subtle contract, and it is
    written out in `src/Targeting/Switch.lua:74`, `src/Charge/Icon.lua:275`,
    `src/Hover/Cast.lua:194`, `src/Dungeons/Key.lua:57`,
    `src/Marking/Keys.lua:74`, `src/Buttons/Bars.lua:371`,
    `src/Loadouts/Loadouts.lua:278` and `src/Character/Blizzard.lua:167`.
    `src/Dungeons/Key.lua:60-90` and `src/Targeting/Switch.lua:74-104` are the
    same 30 lines down to the comment above `Holds`.

    `ns.Rebind` at `src/Core/Core.lua:1459` already centralises the half that
    hurt: the re-take after `UPDATE_BINDINGS`, with the frame's delay and the
    latch that collapses the storm. Six files register with it. Two do not.
    `src/Buttons/Bars.lua:813` answers the event itself and Core's own comment
    at `:1434` allows for that. `src/Character/Blizzard.lua:200` is the one
    worth looking at: a second frame, a second `UPDATE_BINDINGS` registration,
    and a `dirty` flag picked up on `BlizzHide`'s tick, which is Core's
    mechanism rebuilt beside Core's mechanism.

    So the shared piece is the take, not the re-take. `ns.TakeKey(button, key,
    name)` returning the displaced binding, with `ns.Rebind` called from inside
    it, retires eight copies and makes the registration impossible to forget.

27. A window has no lifecycle, so twelve files invented one.

    `UI.Window` hands back an object with `Show`, `Hide` and `IsShown` on it at
    `src/UI/Window.lua:493-504`. Twelve files call `UI.Window(` and every one of
    them wraps that object in its own `Show`, `Hide`, `Shown` and `Toggle` over
    a file-local named `window`.

    Four spellings of one boolean came out of it. `window ~= nil and
    window:IsShown()` in Map, Quests, Dungeons and Character. `(window and
    window:IsShown()) and true or false` in Bags and Merchant. `built and
    window:IsShown() and true or false` in Chat. And
    `src/Mail/Window.lua:1097`, which reaches past the object into
    `window.frame:IsShown()`, which is the one that will break when the object
    grows a wrapper.

    The names went too. `src/Breakdown/Window.lua` carries `Open`, `Close`,
    `IsShown`, `Shown` and `Toggle`, which is five names for two states in one
    file. `src/Dungeons/Window.lua:847-864` and `src/Map/Window.lua:406-423`,
    which are `Hide`, `Shown` and `Toggle`, are identical line for line.

    The fix is on the object, not in Core: `Toggle`, a `Shown` that is the one
    spelling, and an optional `onShow` for the parts that paint on the way up.

29. The spell row on the options page, twice.

    `src/Buffs/Feature.lua:119-156` and `src/UnitFrames/Panel.lua:31-68` are the
    same 38 lines: a `Spell()` closure over a slot index, an icon, a remove
    button, a label pinned between them, and a measure function returning zero
    height for an empty slot. The comments differ in wording and agree in
    argument. Two lists, one row, and it wants to be `ui.SpellRow` in
    `UI/Widgets.lua` beside the other controls the panel builds.

30. `Bags/Grid.lua` and `Merchant/Grid.lua` are one grid.

    The same functions in the same order: `Subject`, `Enter`, `Leave`, `Build`,
    `Paint`, `Place`, `Trim`, then `Attach`, `Paint`, the pool, `Headers` and
    `Describe` public. The pile walk at the bottom of each is the same walk.

    Weaker than it was, and it is worth saying why rather than deleting it. The
    merchant's unit is a card now: a square with the item's name, the price and
    what is left of the supply beside it, laid out in columns worked out from the
    window's width. The bag window's unit is a bare square in a column count you
    set. So the shared thing left is the pile walk and the pool, and the parts
    that differ have grown. Ranked last of the seven, and the way to find out is
    still to write the shared grid and see what will not fit through it.


Items 32 to 45 came out of a performance review on 2026-09-02, read from source
against a five-man pull with fifteen plates up. The numbers are client calls per
second at steady state, counted from the code rather than measured on the live
client, and the Perf tab is where to check them before and after. One of them
is a bug. The rest are polls that should be events, formats that run before the
compare that would have skipped them, and windows built at login for a session
that never opens them. Ordered by what they cost, with the one that grows all
session first. The full review with every citation is off-tree

The architecture question the review raised is answered in item 36 and item 33
together. The client is already the event stream. What the addon lacks is not
a bus of its own on top of it but two things narrower than that: one shared
reader in front of each raw source whose read is the cost, and a dirty bit per
widget so that events mark and a tick draws. A general addon-wide stream would
re-broadcast client events through one more dispatch that every handler pays
for, and it would not have found a single item below.

32. The action ticker is armed again on every loading screen.

    `src/Buttons/Bars.lua:893-898` arms
    `ns.UI.Ticker(events, 0.1, "action", Bars.Update)` inside the branch that
    runs on PLAYER_LOGIN and on PLAYER_ENTERING_WORLD, and
    `src/UI/Ticker.lua:121-143` appends a tick on every call with no dedupe by
    name. After login and the first world entry there are two action tickers.
    Every instance door, hearth and zone load adds one. Three loading screens
    in, Bars.Update runs four times per 100 ms. It is the only ticker in the
    addon armed outside a login-only branch.

    Keep the returned tick in a local and arm only when it is nil. Then make
    UI.Ticker assert that no running tick on the same frame carries the same
    name, so the next one fails at the call rather than in the frame budget.

33. `Bars.Update` polls every square, twelve to sixteen calls each, ten times a
    second.

    `src/Buttons/Bars.lua:697-708` and `src/Buttons/Slot.lua:365` onward. Per
    square per tick: GetAttribute, HasAction, GetActionTexture,
    GetActionCooldown, GetActionInfo and GetMacroSpell on a macro,
    IsHarmfulAction, GetTime, IsUsableAction, UnitExists, IsActionInRange,
    then GetActionTexture a second time through `Slot.Texture`, GetActionCount,
    IsCurrentAction, IsAutoRepeatAction and IsEquippedAction. At 24 squares
    that is about 3,200 calls a second, and the header at `:686` says five bars
    is sixty squares, which is about 8,000. Item 32 multiplies it.

    Blizzard's own ActionButton on this client repaints from
    ACTIONBAR_UPDATE_COOLDOWN, ACTIONBAR_UPDATE_STATE,
    ACTIONBAR_UPDATE_USABLE, ACTIONBAR_SLOT_CHANGED, SPELL_UPDATE_USABLE,
    UPDATE_SHAPESHIFT_FORM and PLAYER_TARGET_CHANGED, and keeps a 0.1 s
    OnUpdate for range and the count text only. Do the same: a dirty bit per
    square set from those events, Draw only the dirty squares, and the tick
    shrinks to one IsActionInRange per harmful square while a target exists.
    The Reaction and Requires rungs raise the bit from their own events. The
    cheap first step that needs no restructuring: return the texture from
    `Slot.State` and drop the second GetActionTexture.

34. `EnemyBars.Update` formats a threat string per plate per tick, then compares
    it.

    `src/UnitFrames/EnemyBars.lua:697-722` builds `("%d%% %s"):format(...)` or
    `("%d%%"):format(...)` in `ThreatState`, and only then does `UpdateWidget`
    at `:1422` compare it to what is shown. Every engaged plate allocates one
    string per 0.2 s tick, about 75 a second in a pull, and `Record` at `:651`
    concatenates a targeter label on top. The guard scan does not count a
    format as an allocation, which is why this is on disk.

    The rest of the tick is about thirty client calls per plate, roughly
    2,400 a second at fifteen: `Unit/Threat.lua:98` calls
    UnitDetailedThreatSituation and then `ns.Threat` again to re-read what the
    first call returned and discarded; `Unit/Level.lua:119` asks UnitLevel
    twice, UnitClassification and UnitIsTapDenied for a mob whose level does
    not move; `ScanDebuffs` at `:731` walks UnitAura to the first nil.

    In order of payoff: compare percent and challenger as numbers and format
    on change; drop the duplicate `ns.Threat` call; cache the level tag and
    classification per GUID, keeping UnitIsTapDenied live; register
    UNIT_AURA, UNIT_HEALTH, UNIT_THREAT_LIST_UPDATE and UNIT_TARGET for the
    plate token on attach, set a dirty bit, and demote the 5 Hz pass to a 1 Hz
    verify.

35. `EnemyBars.Sweep` visits every plate every frame to find no casts.

    `src/UnitFrames/EnemyBars.lua:2278-2296`, driven at interval 0 from
    `:2333`. It calls GetTime, then walks `pairs(attached)` and asks each
    widget's cast box IsShown through `src/UnitFrames/Cast.lua:429`. Fifteen
    plates at 60 fps is about a thousand client calls a second, twice that in
    C entries counting the iterator, to learn that nobody is casting.

    Keep a set of widgets whose cast box is up, added where `Cast` shows the
    box at `Cast.lua:372` and removed in `Cast.Clear` at `:180`. Sweep walks
    that set, and the ticker stops when the set and `fading` are both empty
    and starts again from Show and from `StartFade` at `:1852`. Steady state
    becomes zero. Same shape, smaller: the "castsweep" tick in
    `src/UnitFrames/PlayerCast.lua:473` calls GetTime before asking whether
    the bar is shown at `:269`. Swap the order.

36. Six files each unpack the combat log, three of them for features that are
    off.

    `src/Meter/Meter.lua:180`, `src/Breakdown/Breakdown.lua:352`,
    `src/Swing/Swing.lua:266`, `src/Feeds/Combat.lua:359`,
    `src/Buttons/Reaction.lua:246` and `src/Comfort/Thanks.lua:145` each call
    CombatLogGetCurrentEventInfo on every COMBAT_LOG_EVENT_UNFILTERED line,
    pulling 15 to 21 return values. At 60 lines a second in a pull that is 360
    handler entries and about 7,000 value copies before any filter runs.
    Meter at `:289`, Swing at `:289` and Breakdown at `:667` register at load
    whatever their switch says. Only Thanks at `:202-206` unregisters when
    off, and it is the model.

    Two smaller costs on the same path. `Feeds/Combat.lua:366` calls
    UnitGUID("player") on every line that passes the shape filter, which is
    nearly all of them, before rejecting at `:371`; the other five cache the
    GUID at login. `Meter.lua:175` and `Swing.lua:260` call
    `type(CombatLogGetCurrentEventInfo)` per event for an answer fixed at
    load; `Combat.lua:252-255` resolves it once and is the pattern.

    The code is already shaped for a shared reader: all six read positional
    arguments, none mutates them, five reject on a GUID. One
    `ns.CombatLog.Subscribe(fn)` in Core, one unpack per line handed to a
    plain array of subscribers, each feature subscribing from its `Apply` when
    its switch is on, and the client event unregistered when the array is
    empty. On a night with meter, breakdown and swing off, that is nothing
    instead of three unpacks a line.

37. The Options window is built at login and every getter on it runs twice.

    `src/Core/Panel.lua:868-872` runs `Build()` at PLAYER_LOGIN. Build at
    `:590-716` creates the window and calls all 29 panel builders, and
    `src/UI/Widgets.lua:1061-1067` runs each widget's refresh the moment it is
    built, then `Options.Refresh()` at `:714` runs them all again. Roughly a
    thousand frames, 1,800 textures, a thousand font strings and a thousand
    closures for a window most sessions never open. What the getters reach is
    worse than the frames:

    `src/Comfort/Feature.lua:457` reads `Destroy.Describe`, which runs
    `Clutter.Scan` over every bag slot with item info, value and Questie
    queries, twice, against a cold item cache. `src/Buttons/Feature.lua:655`
    forces `Ranks.Scan`, a full spellbook walk and 120 slot reads.
    `src/Map/Feature.lua:118-139` builds a check per Questie place and each
    refresh rebuilds Questie's three menus, so N rows cost N+2 rebuilds.
    `src/Dungeons/Feature.lua:160-167` runs `Book.Count`, which allocates about
    500 tables to produce a number, and `Places.Count`, 78 GetMapInfo calls.
    `src/Character/Feature.lua:118-122` walks worn items, durability, every
    skill and every faction. All of it again on every one of the 49
    `Options.Refresh()` call sites, on every click, on every page.

    Build the window on first Show, build a feature's sections on first rail
    selection, and make `kit.Refresh` at `Widgets.lua:1070` skip a widget
    that is not visible. About half of all deferrable login work is this one
    item.

38. Skin and party frames poll what UNIT_AURA and UNIT_HEALTH would tell them.

    `src/UnitFrames/Skin.lua:492-508` through `src/UnitFrames/Paint.lua:132`
    and `src/UnitFrames/Auras.lua:293`: about 110 client calls per 0.2 s tick
    across player, target and target-of-target, 550 a second, of which the
    two-pass aura scan is about 45 and the texture readbacks that defend
    against Blizzard rewriting the bar are five per entry.
    `src/UnitFrames/Group.lua:979-986` through `src/UnitFrames/Member.lua:420`:
    about 16 per member, 320 a second in a five-man and 3,200 in a raid.

    Blizzard's own TargetFrame runs on UNIT_AURA for "target" on this client,
    so the worry in Skin's header about unproven events does not apply here. A
    dirty bit per unit from UNIT_AURA, UNIT_HEALTH, UNIT_POWER_UPDATE,
    UNIT_CONNECTION and PLAYER_TARGET_CHANGED leaves the tick with one
    UnitInRange per member, which has no event and which Blizzard polls at
    0.25 s too. Hook SetStatusBarTexture on the bar to retire the readbacks.
    While in Auras.lua: `AuraAt` at `:207-231` prefers C_UnitAuras, which
    returns a fresh table per call, so the "no allocation" note at `:241` only
    holds on the UnitAura fallback. Read the Perf tab on the live client before
    believing either comment.

39. Charge asks `State` twice a frame, at 20 Hz and at 10 Hz.

    `src/Charge/Marker.lua:119-125` and `src/Charge/Icon.lua:336-406` both
    call `Charge.State` at `src/Charge/Charge.lua:305`. `Charge.Pick` at
    `:265` is memoised per frame; State is not. A plated mob out of combat
    costs about 28 calls per marker tick and 12 per icon tick, 560 plus 120 a
    second. `Charge.Known` at `:114` walks IsSpellKnown over the rank list on
    every tick, twice, for an answer that changes at a trainer.

    Cache Known on SPELLS_CHANGED, memoise State per frame the way Pick is,
    and run State, Draw and AttachTo only when Pick's key, unit and plate
    triple changes or a cooldown, usable, stance or target event fires. The
    20 Hz stays for softenemy alone, which has no event.

40. `Blizz.Apply` re-asks every caged frame where it is, once a second.

    `src/UnitFrames/Blizzard.lua:336-425` resolves 19 globals and for each
    present frame calls GetObjectType, GetParent and IsShown through
    `src/Core/Attic.lua:143-219`. `Attic.Sweep` then calls GetParent on every
    frame the room holds, around a hundred once chat, character, talents,
    spellbook, map and merchant have caged theirs, and the seven `Blizz.Also`
    registrants re-vanish their own. About 400 calls in one frame every
    second, all answering a question whose answer changed zero times.

    The file names its two failure modes: a frame built late and a foreign
    SetParent. ADDON_LOADED covers the first.
    `hooksecurefunc(frame, "SetParent", ...)` and `"Show"` on each caged frame
    at Take time covers the second exactly. With those the verify pass drops
    to 5 or 10 seconds without weakening the promise in the header.

41. Feeds and chat pay a full repaint per line.

    `src/Feeds/Combat.lua:297-330`: every hit you deal or take runs `Add`,
    which allocates two or three strings, calls GetSpellTexture uncached at
    `:330`, and pushes into `Feed:Paint` at `src/UI/Feed.lua:1266`, which
    repaints all thirteen visible rows and runs `Sync` at `:1349-1372`, four
    scrollbar writes with no compare. Mark dirty in Push, paint once per frame
    from the strip's existing ticker, and cache SpellTexture by id in Core the
    way `SpellNameHeld` caches names.

    `Feed.lua:1335-1341` reopens the tooltip when the entry under a parked
    cursor changed, which with the mouse resting on row one of a live feed is
    a full `Tip.Build`, `Scan.Read` and `Tooltip.Layout` on every arrival.
    Throttle the reopen to 0.2 s.

    `src/UI/Log.lua:302-307` calls `Sync` on every chat line in every room the
    line routes to through `src/Chat/Window.lua:359-386`, hidden rooms
    included, and `Restore` at `:419-431` replays up to 400 lines each with its
    own Sync. Skip Sync on a hidden log and mark it stale for Show; compare the
    range before writing.

42. Closed windows and pools built at ceiling on login.

    `src/Character/Window.lua:270-271` paints the sheet twice on a hidden
    window and `src/Character/Paperdoll.lua:436` loads a PlayerModel into it,
    about 200 client calls. `src/Spellbook/Window.lua:376` walks every spell
    at login and `:689` again on every SPELLS_CHANGED with the window closed,
    and `Ranks.Scan` walks the same spellbook separately. `src/UnitFrames/
    Auras.lua:665-670` builds 96 aura squares to the ceilings at `:150-165`
    before the player has a target, about 290 frames with 96 Cooldown
    templates, and `src/UnitFrames/Skin.lua:559` runs the full `Block.Place` on
    every target change. `src/UI/Feed.lua:376-384` builds all 24 rows and 400
    ring tables per feed whatever the rows setting, and
    `src/Feeds/Stream.lua:343-394` builds both feeds with no check on the on
    switch. `src/Meter/Window.lua:595-621` builds 20 rows and arms its ticker
    with the meter off. `src/Swing/Gauges.lua:361-392` is built and ticking at
    interval 0 with the feature off. `src/Cooldowns/Row.lua:407-438` builds 23
    squares for a row that shows eight to ten.

    `src/Breakdown/Window.lua:500-503` builds on first open and is the
    pattern. What has to exist at login is the bars, the three skin blocks, the
    two group headers, the enemy bar anchor, the charge binder, the rims and
    the bindings. By frame count that leaves 80 to 85 percent of login
    construction as first-open work.

43. Thirteen OnUpdate handlers on frames that never hide.

    `src/UI/Ticker.lua:57-90` installs `Drive` per frame, and thirteen
    permanent tickers each hang off a private events frame. The client
    dispatches thirteen Lua entries per frame before any interval check runs,
    about 780 a second. One never-hidden driver frame shared by the permanent
    tickers makes that one. Under everything above, and last of the tick
    items for that reason.

44. Smaller costs worth fixing when the file is open.

    `src/Swing/Gauges.lua:233` is exempt as unguarded and writes zero onto a
    bar already at zero every frame between swings. Guard the write when the
    fraction is zero and shownValue is already zero.
    `src/Buffs/Nag.lua:483-511` calls UnitRace three times per tick through
    `Racials.Mine`, probes GetWeaponEnchantInfo's arity every tick, and asks
    `Racials.Idle` twice; capture the race at login and the tick drops from
    16 calls to two. `src/Cooldowns/Row.lua:265-282` reads every cooldown
    twice per tick out of combat, once in Busy and once in Paint.
    `src/Buffs/Upkeep.lua:606` and `src/Cooldowns/Cooldowns.lua:853` both walk
    UnitAura on the same UNIT_AURA event; one scan handing the set to both
    halves it. `src/Dungeons/Book.lua:92-101` scans 237 bosses linearly three
    or four times per paint and once per loot slot; a byId hash in `Book.All`
    is fifteen lines. `src/Breakdown/Breakdown.lua:176` `levels[guid]` leaks on
    the target path, written on every PLAYER_TARGET_CHANGED and removed only on
    NAME_PLATE_UNIT_REMOVED. `src/Bags/Window.lua:391` runs a full Refresh on
    every BAG_UPDATE, which fires once per bag per change; coalesce to one per
    frame. `src/World/World.lua:175` builds a tooltip on every
    UPDATE_MOUSEOVER_UNIT; early-out on the same GUID as last time.
    `src/UI/Text.lua:170` builds the font cache key by concat on every
    `UI.Font` call, on the keystroke path and on every tooltip line; key it as
    `fonts[flags][size]`. `src/Perf/Perf.lua:59` lists 14 slots and ten
    registered ticker names are missing from it: trace, vendor, thanks, chart,
    tip, world, bagstack, sampler, stream and clock, so two every-frame
    tickers are invisible on the tab.

45. The gate reaches the tick paths and not the event paths.

    `scripts/hot.lua` walks out from tickers and OnUpdate roots. A combat-log
    handler at 60 lines a second is hotter than any 5 Hz tick and is outside
    the walk, because event handlers are closures the root finder cannot
    name. The cheap way in is the marker the file already has. Seeding twelve
    functions with `-- hot:` (the four `OnLog`, `Swing.Retime`,
    `CombatFeed.OnLog`, `Upkeep.Scan`, `Cooldowns.Scan`, `Feed.Handle`, and
    EnemyBars `Attach` and `Release`) grows the closure from 355 to 439
    functions and the existing scan reports thirteen violations: four real
    per-event allocations at `Breakdown.lua:275`, `Chat/History.lua:143`,
    `Chat/Rooms.lua:339` and `EnemyBars.lua:1735`, seven writes in Attach and
    Release that want `-- cold:`, and two first-use paths at `UI/Ticker.lua:133`
    and `UI/Pixel.lua:97` that want a per-line reason. Do not seed wider:
    eighteen roots reached 937 functions because `Window.Refresh` resolves to
    all eight `Window.lua` files at once, which is the list-not-a-gate failure
    hot.lua's own header warns about.

    Two more rules that would have caught items 32 and 34. `UI.Ticker` refuses
    a running tick of the same name on the same frame. And the allocation scan
    counts `:format(` and `..` as allocations on a hot path, which it does not
    today; `ThreatState` formatting before its caller compares is exactly the
    shape the scan exists to catch.


## Deliberately not on this list

The architecture review turned up two more repeats and both are right as they
stand. `src/Progress/Progress.lua:70` and `src/Quests/Client.lua:43` hold the
same four-line probed call, and the comment above the first one argues that
each is written against its own returns and that a prober in Core would be a
call every part reaches through rather than a seam each part draws. That
argument holds. `src/UI/Feed.lua`, `src/UI/Log.lua` and `src/UI/Stack.lua` each
open by saying why they are not one of the others, and each of those three
arguments holds too.

This review adds three more that measured badly and read fine. `src/Class/*.lua`
files repeat each other because each is a registry of one class's spells, and
the repeats are the table shape rather than the data. `UI.Quality` in
`src/UI/Theme.lua:100` and `Color.power` in `src/Unit/Color.lua:355` are two
palettes that happen to be the same size. And ten parts open a placeable HUD
frame with the same four calls, `CreateFrame`, `ns.UI.Adopt`, `ns.UI.Unit` and
`ns.UI.Placeable`, which is four lines with no logic in them and is what a
constructor already looks like.

The performance review adds two more that were looked at and left alone.
Stripping comments from the shipped files: all 230 compile in 26 ms in stock
Lua 5.1 with the comments in, so the 45 percent of lines that are comment or
blank cost under 10 ms a login and a build step would buy nothing. And the saved
variables: chat history, quest drops, dungeon drops, breakdown spells and
loadouts are all capped, most at 400, and nothing logs a growing feed or combat
sample, so there is no serialise-on-logout cost to chase.
