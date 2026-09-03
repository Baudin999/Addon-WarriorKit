# WarriorKit

A personal warrior addon for WoW TBC Anniversary. Twelve parts: ctrl-click raid
marking, one button that casts Charge, Intervene or Intercept depending on what
you are looking at, one key that takes the next enemy and swings at it, weapon
loadouts with a key each that swap your stance and both your hands, a warrior
loadout that fills the action bars, enemy bars that replace the
Blizzard nameplate and carry a cast bar of their own, a chat window with a room
per conversation in place of the client's own and a voice
channel joined at login, a strip of the Blizzard bar art, three chores the
client makes you do by hand, a swing timer with the Slam window marked on it,
a row over your character counting down the cooldowns that decide fights,
a loot stream and a combat log drawn as scrolling feeds, and one Edit Mode
layout carried inside the addon folder. Settings live in a panel opened with
`/wk`.

This file is written for whoever picks the addon up next, human or agent. The
first half is what it does, the second half is what the client will and will
not let you do, which is where most of the work went.

## Target clients

Two, from one copy of the source.

    product      wow_anniversary          wow_classic_era
    version      2.5.6.69110 (TBC)        1.15.9.69109 (vanilla)
    interface    20506                    11509
    toc          WarriorKit.toc           WarriorKit_Vanilla.toc

    install      <wow>/_anniversary_      <wow>/_classic_era_
    wow          /home/baudin/Games/battlenet/drive_c/Program Files (x86)/World of Warcraft

The Era install carries `Interface/AddOns/WarriorKit` as a symlink to the
Anniversary copy, so there is one set of files to edit and both clients load it.
Saved variables are not shared: those live in each install's own WTF, so the two
clients keep separate settings, which is what you want when one of them has no
Edit Mode and no threat API.

A client loads `Name_<Flavour>.toc` when one exists and falls back to
`Name.toc`. Era takes the Vanilla file, everything else takes the fallback. Both
list exactly the same Lua files, and `check.sh` fails if they ever drift, because
a file that loads on one client and silently does not on the other is the worst
kind of difference to chase.

The game runs under Wine through Lutris, but the addon is plain Lua on a normal
filesystem path. Edit the files in place, then `/reload` in game.

**What Classic Era does not have.** Handled in the code, by `ns.vanilla` and by
the probes that were already there, never by loading different files:

    threat API        absent. UnitDetailedThreatSituation does not exist in
                      vanilla, which is why every Classic threat meter parses
                      the combat log. ns.HasThreat answers, and the enemy bars
                      colour by who each mob is hitting instead. Said once in
                      chat at login and shown in /wk status.
    Edit Mode         absent. EditMode.CanApply says so and the panel greys out.
    Intervene         a TBC ability. MacroText already builds its lines only if
                      the spell name resolves, and Charge.Known is false, so the
                      combat half of the button is Intercept alone.
    C_UnitAuras       absent, the aura shim falls back to UnitAura.
    C_Spell           absent, the spell shim falls back to the globals.
    softenemy         almost certainly absent. Already probed and latched.
    loadout spells    Spell Reflection and Commanding Shout are TBC. The loadout
                      is written in localised spell names, so those slots come
                      back as "not yet learned, left empty" rather than as an
                      error.

## Files and load order

The addon is twenty-eight parts and a core. Each part is a folder, and Core knows the
name of none of them.

    Core/Core.lua        SavedVariables, API shims, the feature registry
    Core/Attic.lua       where a Blizzard frame goes when this addon draws it
                         instead: one frame, hidden at birth, that nothing can
                         show. A frame re-parented into it is not drawn whatever
                         the client calls on the frame itself

    Class/Class.lua      the class registry, and the question "which class is
                         this". Loads straight after Core and before every part,
                         because all of them read facts off it
    Class/Warrior.lua    the whole of what the addon knows about a warrior: the
                         forms, the charge abilities, the two a fight hands you,
                         Slam, Battle Shout, the four long cooldowns, and the
                         bar plan
    Class/Mage.lua       three of those seven
    Class/Shaman.lua     three of those seven
    Class/Priest.lua     two, and neither of them opens a page
                         Nothing outside a class file names one of its spells,
                         and a class with no file here is a supported class

    Core/Gear.lua        what the client will let into each hand, the two slot
                         numbers those hands are, and the two the trinkets are
    Core/Stance.lua      your class's own form list, read off the registry
                         above: their names, and which one you are standing in
    Core/Command.lua     slash dispatch, built from the registry
    Core/Panel.lua       the options window and the widget kit

    Unit/Unit.lua        health and power, as the integers that get drawn
    Unit/Color.lua       every colour the addon puts on a unit, in one palette
    Unit/Level.lua       the level tag, the elite suffix, what a kill is worth
    Unit/Roster.lua      who is in the group, whose pet is whose, and what a
                         GUID was called when it last was
    Unit/Spec.lua        which talent tree somebody took, out of your own trees
                         or out of an inspect, and the icon of it
    Unit/Role.lua        tank, healer or damage, out of four sources that
                         disagree, with the class as the floor
    Unit/Threat.lua      what the threat API says, for one mob or across a group

    UI/Pixel.lua         the pixel grid: screen size, scale, snapping, rescale
    UI/Draw.lua          a filled rectangle, a hairline outline, a crisp icon
    UI/Gauge.lua         a status bar with a flat fill and the spent part
                         of it behind, in the fill's own colour at a fifth
    UI/Text.lua          one shared font object per size, a label, a glyph,
                         wrapped height
    UI/Flow.lua          a stack panel: rows, columns, wrapping and alignment
    UI/Theme.lua         the palette and the pixel metrics, in one table each
    UI/Stack.lua         a column of rows, each one asked how tall it is
    UI/Scroll.lua        a viewport that clips, a canvas that moves, a bar
    UI/Log.lua           a column of lines that grows from the bottom, wraps,
                         caps itself and scrolls
    UI/Tooltip.lua       the addon's own tooltip, rendered from a table a caller
                         hands over, at the zoom of the frame it was opened on,
                         plus a scanner that reads an item's real text out of
                         the client so it can be redrawn in this chrome
    UI/Feed.lua          a column of entries, newest at the top, each an icon, a
                         name, an optional dim middle column, a number and a
                         coloured stripe, with markers that band the whole row;
                         a ring behind it and rows that repaint rather than move
    UI/Widgets.lua       the widget kit a page is built out of
    UI/Window.lua        window chrome, the folding side rail, the tab strip
                         and the list, which is the rail's twin for a column
                         whose rows change while the window is open

    Perf/Perf.lua        what each ticker costs and what the addon is holding
    Perf/Feature.lua

    Marking/Marking.lua      ctrl-click raid marking, keybinding entry points
    Marking/Keys.lua         the override binding behind each marking key
    Marking/Feature.lua

    Hover/Hover.lua          what a binding is, what the cursor is carrying, and
                             the macro one binding turns into
    Hover/Cast.lua           the one secure button every hover key presses
    Hover/Sheet.lua          the list of what you bound, drawn over the world
    Hover/Panel.lua          the page: a row per binding and an empty one on top
    Hover/Feature.lua

    Charge/Charge.lua        which ability, which unit, what state; shared colours
    Charge/Icon.lua          the HUD icon, which is also the secure button that casts
    Charge/Marker.lua        the icon in the world above the mob the button will hit
    Charge/SoftTarget.lua    action targeting, held on out of combat and off in
                             it, and never touched on another class
    Charge/Feature.lua

    Targeting/Switch.lua     the secure button behind the switch key, and its binding
    Targeting/Feature.lua

    Loadouts/Loadouts.lua    ten secure buttons, one per loadout, each carrying
                             that loadout's cast and its pair of /equipslot lines
    Loadouts/Page.lua        the paperdoll page and the loadout tab strip, drawn
                             into whichever widget kit is handed to it, which is
                             the character window's
    Loadouts/Feature.lua     the registration and the slash word, and no panel

    Buttons/Reaction.lua     whether the Overpower or Revenge window is open,
                             tracked off the combat log
    Buttons/Slot.lua         what one action slot is doing, as one of ten statuses
    Buttons/Layout.lua       the warrior loadout, and the backup of what it replaced
    Buttons/Ranks.lua        moves bar slots up to the best rank you know
    Buttons/Which.lua        which bars this client can have, and which of them
                             you want cloned
    Buttons/Look.lua         what one bar looks like and when it is up: the rows
                             the twelve fold into, the colour and opacity of the
                             ground under them, whether it goes down in combat
                             and which key holds it up
    Buttons/Bars.lua         a clone of every action bar you have, on the same
                             slots and the same keys, with Blizzard's hidden
    Buttons/Placing.lua      where each cloned bar sits, and the handle you drag
                             it by
    Buttons/Feature.lua

    UnitFrames/Plates.lua    the client settings that decide where a plate goes
    UnitFrames/Cast.lua      the cast row one enemy bar carries: what the mob is
                             casting, how long is left of it, and whether the
                             client says you can stop it, plus the four answers
                             about a cast that both bars in the addon share
    UnitFrames/PlayerCast.lua your own cast bar, on a frame you drag, under the
                             swing timer. The same four answers, drawn in a
                             rectangle of its own, plus the cast that failed
    UnitFrames/EnemyBars.lua enemy bars, nameplate replacement and list fallback
    UnitFrames/Auras.lua     your own and the target's buff and debuff rows,
                             and hiding the client's, which cannot be moved
    UnitFrames/Art.lua       what the skin does to a region Blizzard owns:
                             record it, hide it, hand it back
    UnitFrames/Block.lua     the square itself: portrait, two gauges, four
                             strings, and where the three blocks hang off
                             each other
    UnitFrames/Paint.lua     one pass over one block: the colours off the unit,
                             the four numbers and the incoming heal
    UnitFrames/Skin.lua      the part: which frames this client has, whether
                             each is wanted, and styling them in an order that
                             survives combat
    UnitFrames/Member.lua    one party or raid member's block: build, lay out, tick
    UnitFrames/Group.lua     the secure group header, its attributes, and the
                             slot order every member falls into
    UnitFrames/Panel.lua     the part's page in the options window
    UnitFrames/Feature.lua

    Meter/Meter.lua          damage and healing per player, out of the combat log
    Meter/Threat.lua         each member's threat on your target, and how fast it
                             is climbing
    Meter/Window.lua         the two panes, their rows, and the tick that paints them
    Meter/Feature.lua        the tab, the slash words and the settings

    Swing/Swing.lua          when the next swing lands, in each hand, out of
                             the combat log and UnitAttackSpeed
    Swing/Slam.lua           what Slam costs to cast and where on the swing the
                             press that costs no swing sits
    Swing/Gauges.lua         a gauge per hand, the band on the main hand one,
                             and the tick that paints them
    Swing/Feature.lua

    Buffs/Upkeep.lua         what should be up and is not: your own auras, and
                             the temporary enchant on each hand
    Buffs/Racials.lua        which racial this character owns, whether it is off
                             cooldown, and whether it is one worth nagging about
    Buffs/Nag.lua            the row of squares, the tick that paints it, and
                             the click that opens the row's page
    Buffs/Panel.lua          the row drawn again on the options page as its two
                             lines, with what is off it underneath, to drag
    Buffs/Feature.lua

    Cooldowns/Cooldowns.lua  what is on the long-cooldown row: your class's own
                             list, filtered by what this character has learned
                             and left switched on, plus whichever trinket you
                             are wearing has something to press
    Cooldowns/Row.lua        the row of squares, when it is on the screen, and
                             the tick that paints it
    Cooldowns/Feature.lua

    Feeds/Stream.lua         one feed put on the screen: its frame, its anchor,
                             its drag and the seven settings behind it, found by
                             prefix so both streams read the same six
    Feeds/Loot.lua           what dropped, out of the client's own loot
                             sentences turned into patterns rather than typed
    Feeds/Combat.lua         what landed on you or that you landed, out of the
                             combat log, and only where one end of it is yours,
                             with a band across the feed at each end of a fight
    Feeds/Feature.lua

    Breakdown/Breakdown.lua  one counter row per ability, kept between sessions:
                             what landed, what crit, what stopped it, banded by
                             the target's level against yours
    Breakdown/Window.lua     that table drawn into the settings panel, and the
                             same ranking printed by the slash word
    Breakdown/Feature.lua

    Artwork/Artwork.lua      strips the gryphons and the metal strip off the bars
    Artwork/Feature.lua

    Progress/Progress.lua    every call this part makes to the client: how far
                             into the level you are, the rested pool, the watched
                             faction folded out of either shape the client
                             answers it in, and the session's own experience
                             clock, which no API answers
    Progress/Rails.lua       the two bars along the bottom of the screen, the
                             rested pool drawn beyond the fill, the twenty
                             segment marks, and a hover on each rail
    Progress/Feature.lua

    Minimap/Shape.lua        squares the minimap, resizes it, moves Blizzard's own
                             icons to the corners, puts the wheel on the zoom
    Minimap/Corral.lua       borrows the other addons' minimap buttons into one tray
    Minimap/Feature.lua

    Chat/People.lua          the groups and who is in them, matched on the name
                             with the realm and the case taken off
    Chat/Rooms.lua           which conversations exist right now, where a line
                             goes and what is unread in each
    Chat/History.lua         the whispers and the party chat, kept across a
                             logout and thrown away after a day
    Chat/Compose.lua         the slash a room fills the line in with, and the
                             send that reads it back
    Chat/Field.lua           the client's own chat line, stripped of its art and
                             anchored into our footer, because a field of ours
                             is a field `/logout` cannot run from
    Chat/Feed.lua            every chat event turned into one coloured line
    Chat/Blizzard.lua        the client's own chat window off the screen, and
                             everything it would have drawn forwarded here
    Chat/Voice.lua           the voice channel pick, and the join it asks for
    Chat/Window.lua          the window: the room rail, a log each, and the
                             rectangle the client's line sits in
    Chat/Feature.lua

    Comfort/Loot.lua         empties a corpse on LOOT_READY, before the window draws
    Comfort/Vendor.lua       sells grey items while a merchant window is up
    Comfort/Repair.lua       pays the merchant to mend, guild funds first
    Comfort/Camera.lua       how far cameraDistanceMaxZoomFactor lets you pull back
    Comfort/Thanks.lua       whispers a stranger who buffs you, and nobody you are grouped with
    Comfort/Errors.lua       the muted-message list, and the method that stands in
                             front of UIErrorsFrame
    Comfort/Clutter.lua      which quest items are finished with, and why
    Comfort/Destroy.lua      the one-card-at-a-time window that acts on that
    Comfort/Feature.lua

    Mail/Who.lua             which of three a recipient is, and the favourites
                             list the warning is measured against
    Mail/Draft.lua           the letter you are writing, how many mails it
                             divides into, and what each one is titled
    Mail/Send.lua            the conversation with the server: fill the form,
                             post, wait, fill it again
    Mail/Inbox.lua           what is waiting, and the sweep that counts down
    Mail/Blizzard.lua        the client's own mail frame parked off screen, still
                             shown, because hiding it closes the mailbox
    Mail/Window.lua          the window: the favourites column, the attachment
                             block, the band along the bottom, the inbox list
    Mail/Feature.lua

    Character/Worn.lua       the nineteen slots, what is in each, how worn it is,
                             and the two calls that put a piece on or take it off
    Character/Stats.lua      every number the client will answer for, and the one
                             it will not: how often you miss
    Character/Skills.lua     the skill lines, folded under the client's own
                             headers, with the shortfall on a weapon skill priced
    Character/Reputation.lua the faction lines, in three colours rather than eight
    Character/Readout.lua    a column of headed rows, repainted from a pool. The
                             skills tab, the reputation tab and the stats column
                             on the gear page are all this, the last of them
                             compact: a line a row, the sentence in the hover
    Character/Paperdoll.lua  the gear page: nineteen squares, the four numbers
                             the client's own sheet has never drawn, and the
                             stats down the right of them
    Character/Window.lua     four tabs over one window, one painted at a time
    Character/Blizzard.lua   the client's own sheet in the attic, and the C key
                             redirected to the matching tab
    Character/Feature.lua

    Bags/Bags.lua            the five bags you carry, walked, and what is in
                             them sorted into piles on the item class the client
                             already files each one under. Draws nothing
    Bags/Stack.lua           the half stacks, put together. Two partial stacks
                             of one item, one dropped on the other until each
                             item is down to a single partial. Draws nothing
    Bags/Grid.lua            the pool of squares. Each one is built on the
                             client's own bag button, so the click, the drag and
                             the stack split are the client's code, and each is
                             parented to a holder frame carrying its bag number,
                             which is the only thing that handler has to go on
    Bags/Window.lua          the window, the free count along the bottom and
                             the stack button between it and your purse
    Bags/Blizzard.lua        the nine calls the client opens and shuts a bag
                             through, taken, so B opens this one
    Bags/Feature.lua

    Dungeons/Book.lua        the book: which dungeons, which bosses, what each
                             one drops, and the ledger of what you have seen.
                             Loads before Baked.lua, which only assigns into it
    Dungeons/Baked.lua       generated, the dungeons and their drops, written by
                             bake-dungeons.sh out of Questie's own databases
    Dungeons/Sheets.lua      generated, the picture of every dungeon and the
                             floors it is cut into, written by
                             bake-dungeon-maps.sh out of Blizzard's map tables
    Dungeons/Places.lua      which floors a dungeon has, what each is called and
                             which tiles draw it. Neither client will answer any
                             of that, which is why it is baked
    Dungeons/Loot.lua        a baked item id turned into what the client says
                             about it, and any row the client disagrees with
                             dropped rather than drawn
    Dungeons/Seen.lua        where a boss stands and what came off it, learned
                             off the loot window, because no database on either
                             client holds a coordinate inside an instance
    Dungeons/Window.lua      the three columns: bosses, the map, the drops
    Dungeons/Key.lua         Shift-L, held as an override on a plain button
    Dungeons/Feature.lua

    EditMode/EditMode.lua    probes Edit Mode, captures a layout, imports the baked one
    EditMode/Saved.lua       generated, the baked layout, written by bake-ui.sh
    EditMode/Feature.lua

    Settings/Settings.lua    how big the addon's own windows are drawn
    Settings/Feature.lua

    Bindings.xml         keybindings, loaded automatically, not listed in the TOC
    WarriorKit.toc       load order, TBC Anniversary and the fallback for anything else
    WarriorKit_Vanilla.toc   the same list for Classic Era
    check.sh             syntax, TOC coverage and lint gate, exits non-zero on any finding
    bake-ui.sh           bakes a captured Edit Mode layout into EditMode/Saved.lua
    bake-dungeons.sh     bakes the dungeon book out of Questie's databases into
                         Dungeons/Baked.lua
    bake-dungeon-maps.sh bakes the dungeon pictures out of Blizzard's own map
                         tables into Dungeons/Sheets.lua

Neither `UI/` nor `Unit/` is a part. Neither has a `Feature.lua`, neither signs
into a registry, neither owns a setting and neither knows the name of anything
above it. They are layers, the way Core is.

`UI/` is how the addon draws. Everything that puts a frame on the screen goes
through it, and it goes through the client.

`Unit/` is what the addon knows about a mob or a group member. It draws nothing.
It exists because the enemy bars and the frame skin had each grown their own
copy of the same four answers and the copies had drifted: the class colour was a
hex string in one file and a table in the other, the level tag was cached in one
and rebuilt per tick in the other, and the reaction palette was declared twice
with the same literals. Both files read one copy now, so they cannot disagree
about what a mob is, and the threat meter reads the same roster the bars do.

Two rules hold everywhere under `Unit/`, and both come from the callers rather
than from taste. Nothing allocates, because everything on that page is reachable
from a ticker running against every mob on the screen. And a colour is handed
back by reference and never built at call time, because the tickers guard their
widget writes on colour identity, so the same state has to answer the same
table every time.

TOC order matters four times. `Core/Core.lua` must load first because it creates
the registry every other file signs into. `Unit/` loads next, because it draws
nothing and needs nothing but Core, and inside it Color loads before Level and
Roster before Threat. `UI/` loads after that and before `Core/Panel.lua`, because
the panel takes `ns.Fill` and `ns.Outline` into file-scope locals as it loads.
Within a part, behaviour loads before `Feature.lua`, because `Feature.lua` is the
only file in a part allowed to name anything outside its own folder.

The Charge files split by job, not by feature. `Charge.lua` decides which
ability, which unit and what state, and all three displays read that one answer.
Anything that would let the icon, the marker and the button disagree belongs in
`Charge.lua`.

There is one deliberate seam between parts: `Charge/Marker.lua` reads
`ns.EnemyBars.WidgetFor` so the world icon sits above the enemy bar rather than
under it. Two things drawing on one nameplate have to agree about z-order, and
one of them has to ask.

## The feature registry

Each part calls `ns.Register` once, from its `Feature.lua`, and hands Core
everything Core or the panel could want:

    name          the word that heads its slash help and its status line
    order         where it sits in the panel and in /wk status
    defaults      merged into ns.db, the account-wide saved variables
    charDefaults  merged into ns.dbc, this character's saved variables
    words         slash words this part answers to, word = function(arg, raw)
    help          lines printed by /wk help
    status        function returning one line for /wk status
    lock          function applying ns.db.locked to this part's frames
    reset         function putting this part's frames back where they started
    panel         function(ui) building this part's section of the panel

Every field except `name` is optional. Marking has no frames you can drag, so it
registers no `lock` and no `reset`.

**Two default tables, because there are two questions.** A preference is yours
and belongs to the account. A record of what was in your action bars before the
loadout overwrote them belongs to the character whose bars they were. Four parts
use `charDefaults`. `Charge` keeps `softPrior`, the value a character's
`SoftTargetEnemy` CVar had before the addon took it over, because that CVar is
character scoped itself. `Buttons` keeps `layoutBackup`, `layoutStamp` and
`layoutMacros`, and registers them there because holding them account-wide
could destroy a second character's bars: the first character
to apply the loadout owned the only backup, the second overwrote its bars
without taking one, and restoring on the second wrote the first one's bars into
its slots. `Loadouts` keeps the loadouts themselves, because a set of weapon
swaps is a fact about the character wearing the weapons. `Buffs` keeps
`buffWatch`, the entries on the nag row this character still watches,
`buffLine`, which line each one you moved stands on, and `buffExtra`, the
spells you put on the row yourself. The first of those was the only scope
decision in the addon taken on editorial grounds rather than on a technical
one, and the other two followed it the day a spell could be dragged onto the
row: a shield one shaman drags on is not a fact about the same account's
warrior. See the buff nag notes.

A key that moves scope is migrated once at `ADDON_LOADED` and the account copy
is dropped.

This is what keeps the parts apart. Before the registry, `Core.lua` held a
`DEFAULTS` table naming every setting in the addon and a slash handler with a
branch per feature, and `Options.lua` built every section. All three had to be
edited to add anything. Now none of them do, and three collisions that used to
be silent are load-time assertions: two features defining the same setting, in
either scope; two features claiming the same slash word; and a feature claiming
a slash word Core answers itself.

That third one is not hypothetical. `Core/Command.lua` answered `ui` before it
ever consulted the registry, the interface part registered `ui` anyway, and
every `/wk ui` command opened the settings panel instead of reaching Edit Mode.
The capture and bake workflow was dead for a release and nothing said so. The
reserved words are one table now, `RESERVED`, and `BuildWords` asserts against
it. `BuildWords` also runs at `PLAYER_LOGIN` rather than on the first slash
command, so all three assertions really are load-time rather than waiting for
someone to type something.

## The word table

`words` takes `function(arg, raw)`, and for a part with one word that does one
thing that is what it gets. A part with a dozen words wrote a chain of ifs, and
a chain of ifs over settings is the same four steps repeated: parse the value,
write `ns.db.<key>`, call the module's `Apply`, print a sentence.
`ns.Command.Word` walks a table of those instead and hands back the handler.

    local SwingWord = ns.Command.Word({
        name = "swing",
        apply = function() Gauges.Apply() end,
        show = function()
            return "swing timer " .. Gauges.Describe() .. "."
        end,

        { "width", number = { 80, 400 }, key = "swingWidth",
          say = function(width)
            return ("the swing bars are %d pixels wide."):format(width)
          end },

        ns.Command.Zoom("swingZoom", "the swing bars draw at %dx."),

        otherwise = { toggle = true, key = "swing",
          say = function(on)
            return "swing timer " .. (on and "on" or "off") .. "."
          end },
    })

An entry names the word first and then one of four kinds. `number` and `step`
take the range, `toggle` reads "off" as off, and `choice` takes the words it
will accept and refuses anything else by naming the set. The range may be a
function returning it, which is how a word whose ends the owning file computes
avoids carrying a second copy of them: `skin aura` asks
`FrameAuras.SizeRange()` at the command.

`say` receives what was written and returns the sentence, or up to three of
them. `key` is where it goes, `set` is for the write that is not a plain
`ns.db[key]`, and `apply` overrides the table's own, with `apply = false` for a
word that redraws nothing. The refusal message reads `name .. " " .. word`, so
`swing width` names itself the way it was typed.

A word that is not a setting carries `run` and stays a function. `buffs add`
takes a spell id, `cast reset` moves a frame, `bars debuff` dispatches again:
none of them is four steps and none of them gains anything from pretending.
`otherwise` is the bare on|off every one of these ends in, or a function where
the part has more lists to look an unknown word up in first, which is what the
cooldown row and the buff nag do with a word their class put on the row.

The gate this replaced was a real one. Two functions sat on the allow-list in
`scripts/shape.lua` as "a slash dispatcher, one branch per word", and three more
had been split in half by their own comment's admission that the branch count
was the only reason. That kind is gone from the list now.

## Conventions

Every file starts `local ADDON, ns = ...` and hangs its module table off `ns`.
A part's behaviour files never call `ns.Print` for settings, never read the
registry, and never touch another part. Anything that crosses a folder boundary
goes through `Feature.lua` or through the shared surface below:

    ns.db           account SavedVariables, ready at ADDON_LOADED
    ns.dbc          this character's SavedVariables, ready at the same moment
    ns.Print(msg)   prefixed chat output
    ns.Fill / ns.Outline / ns.Recolor   a coloured rectangle, a hairline edge,
                                        and a recolour of an edge already drawn
    ns.Pixel(frame) / ns.EdgeSize(edges, size)   one screen pixel in that
                                        frame's units, and an edge resized to it
    ns.UI.Adopt(frame, zoom)     put a frame on the pixel grid, so one unit
                                 inside it is one physical pixel
    ns.UI.Rezoom(frame, zoom)    change that frame's whole-number zoom
    ns.UI.Pixel(frame)           what ns.Pixel forwards to
    ns.UI.Round(frame, size)     a measurement snapped to a whole pixel
    ns.UI.Convert(size, from, to)   a size measured in one frame's units,
                                 expressed in another's
    ns.UI.Scale() / ns.UI.ScreenHeight() / ns.UI.Supported() / ns.UI.Describe()
    ns.UI.OnRescale(fn)          run when the resolution or the UI scale moves
    ns.UI.Icon(parent, layer)    a spell icon cropped on a texel boundary with
                                 the client's own snapping turned off
    ns.UI.Crisp(texture)         that sampling fix, on a texture you made
    ns.UI.Font(size, flags) / ns.UI.Label(...) / ns.UI.FontName()
    ns.UI.FLAT / ns.UI.SHADOW / ns.UI.NumberFont(size) / ns.UI.OutlineFloor()
                                 the three text roles, and the smallest glyph
                                 an outline can go round. See Text.
    ns.Unit.Color.paper          the one colour text is drawn in over a fill
    ns.Unit.Color.Luma / .Contrast   relative luminance, and the ratio between
                                 two colours. See Contrast.
    ns.UI.Wrap / ns.UI.TextHeight   a string folded to a width, and how tall
                                 it came out
    ns.UI.Flush()                every adopted frame combat refused to re-scale
    ns.UI.Color / ns.UI.Metric   the palette and the pixel measurements
    ns.UI.Box / ns.UI.Rule       a filled box with a hairline, and a hairline
    ns.UI.Stack(parent, width)   a column of rows, each asked its own height
    ns.UI.ScrollView(parent)     a viewport that clips and a bar that moves it
    ns.UI.Button / ns.UI.Kit(host)   a push button, and the widget kit a page
                                 is built out of
    ns.UI.Window(opts) / ns.UI.Rail / ns.UI.TabStrip / ns.UI.Windows
    ns.UI.ScrollBar(parent, onValue)   the bar on its own, for something
                                 that scrolls in units the view cannot count
    ns.UI.Log(parent, opts)      a column of lines that grows from the
                                 bottom, or nil and why this client has none
    ns.UI.Tooltip.Show(owner, data)   the addon's own tooltip, at owner's
                                 zoom, from a table of a title, a colour, an
                                 optional item link and a list of lines:
                                 { "text" }, { "label", "value" },
                                 { hint = "..." }, { blank = true }. Nothing to
                                 say draws nothing. Docked in the corner the
                                 client keeps its own tooltip in, or beside
                                 owner where the setting says beside
    ns.UI.Tooltip.SetDocked(on) / Docked()   which of those two, pushed in by
                                 Settings/Settings.lua off the saved value
    ns.UI.Tooltip.Close() / Lines() / Text(i) / Owner() / Zoom() / IsShown()
    ns.UI.Tip(owner, describe)   hang that on a frame, where describe(owner)
                                 answers the table or nothing
    ns.UI.PassCamera(owner)      hand the right and middle buttons back to the
                                 camera on a mouse enabled frame
    ns.UI.Feed(parent, opts)     a column of entries with a ring behind it;
                                 :Entry() / :Push() to add one, :Mark(kind,
                                 label, trailing, band) for a break in it
    ns.Perf.Start(key) / ns.Perf.Stop(key)   bracket a tick body
    ns.Perf.Slot(key)            average ms, worst ms, and how many ticks
    ns.Perf.Memory()             KB held and KB per second being allocated
    ns.Perf.Gauge(label, read)   a count shown beside a timing, from a Feature
    ns.Perf.Watch(on) / Watching() / Sample() / Reset() / Ready() / ClientCPU()
    ns.Perf.OnSample             set by whoever is displaying the numbers
    ns.EnemyBars.Count()         how many bars are drawn right now
    ns.Plates.SetFootprint(w, h)  how much room one bar wants, in UIParent units
    ns.Plates.Measure(plate)     what a plate was before the addon touched it
    ns.Plates.Apply / Restore / Flush / Stacking / Describe / Warn
    ns.HasCastInfo()             whether this client will say what a unit that
                                 is not you is casting
    ns.CastingInfo(unit)         that spell's name, when it started and when it
                                 ends in GetTime seconds, whether it is a
                                 channel, and whether the client says it cannot
                                 be interrupted. Nil for a unit doing neither
    ns.CastImmuneKnown()         whether a cast has come back carrying that last
                                 flag yet: nil before the first one is read,
                                 false once one has been read without it
    ns.SpellName / ns.SpellTexture / ns.SpellCooldown / ns.SpellUsable / ns.SpellInRange
    ns.SpellCastTime(spell)      how long the client says that spell takes to
                                 cast, in seconds, and 0 for an instant or for a
                                 client that will not say
    ns.ItemInfo(link)            name, icon, equip slot and the link's own colour
    ns.ContainerSlots(bag) / ns.ContainerItemLink(bag, slot)   bags, on either
                                        container API, and 0 or nil on neither
    ns.ContainerItem(bag, slot)  how many are in that slot and whether the
                                 client has it locked, as two returns rather
                                 than a table, because the vendor sweep asks
                                 once per slot per tick
    ns.UseContainerItem(bag, slot)   sell it if a merchant window is up, use it
                                 if one is not, so every caller has to prove the
                                 window first; false where the client has
                                 neither API
    ns.ItemValue(link)           quality and what a vendor pays, and nil where
                                 the client has not cached the item, which is
                                 "do not know" rather than "worth nothing"
    ns.ItemKind(link)            the item's id and the class and subclass the
                                 client files it under, read from the client's
                                 own database rather than the cache
    ns.ItemStack(link)           how many of it one bag slot holds, 1 for
                                 everything that does not stack, and nil where
                                 the client has not cached it, which the
                                 stacking sweep treats as "ask again"
    ns.PickupContainerItem(bag, slot)   put a bag slot on the cursor, so the
                                 caller can ask the client what it is really
                                 holding, or call it twice to drop one stack on
                                 another; false where neither API is here
    ns.Questie(name, ...)        one of Questie's modules, asked for by the
                                 name of the module and the names of the calls
                                 you are about to make, and nil for a module
                                 missing any of them. The only place
                                 QuestieLoader is named. See Asking Questie
    ns.Charge.Pick()             ability key, the unit it takes, that unit's nameplate
    ns.Charge.SoftUnit()         the softenemy token when it resolves, whatever is under it
    ns.Charge.State(key, unit)   a status string, plus cooldown times
    ns.Charge.Look(status)       border colour, greyed or not, alpha
    ns.Charge.NameEpoch()        a number that moves when a cached spell name might
                                 have, so the macro guard can compare one value
    ns.ChargeIcon.CanRelease()   whether the state driver path came up
    ns.Switch.Bind(key)          take a key for the switch button, or "" to hand
                                 it back; returns what that key was bound to
    ns.Switch.Describe()         the switch key, or "unbound", or the key plus
                                 what the readback said when it did not take
    ns.Gear.MAINHAND / ns.Gear.OFFHAND   16 and 17, the two numbers an
                                 /equipslot line counts in
    ns.Gear.List(slot, current, empty)   picker rows: an empty row, then
                                 everything that could go in that slot, then
                                 the saved name when it is in neither
    ns.Gear.Find(slot, name)     the carried item's row, or nil
    ns.Gear.Held(slot, name)     whether the client could equip it right now
    ns.Gear.Accepts(slot, link)  the name to save for an item link, or nil and
                                 the reason that hand will not take it
    ns.Gear.Art(slot)            the client's own empty-slot art for that hand
    ns.Stance.Name(index)        that stance's name in this client's language
    ns.Stance.Current()          the stance you are in, or nil when the client
                                 will not say
    ns.Stance.Epoch()            a number that moves when a stance name might
    ns.Loadouts.All() / Get(i) / Count()   the list, one row, its length
    ns.Loadouts.Add(name) / Remove(i) / Rename(i, name)
    ns.Loadouts.Shown() / Show(i)   which one the panel is on
    ns.Loadouts.SetStance(i, n)  the stance it casts, or nil for none
    ns.Loadouts.SetItem(i, slot, link)   save a dropped item into one hand, or
                                 nil and the reason it does not go there
    ns.Loadouts.Bind(i, key)     take a key for one loadout, or "" to hand it
                                 back; returns what that key was bound to
    ns.Loadouts.Macro(i)         the macro that loadout's button is carrying
    ns.Loadouts.TwoHanded(i)     whether its main hand fills both hands, or nil
                                 when the item is not on this character
    ns.Loadouts.ButtonName(i)    the secure button that loadout is bound to
    ns.SoftTarget.Apply()        put the CVar where combat says it should be
    ns.SoftTarget.Restore()      hand the CVar back at the value it had before
    ns.SoftTarget.Describe()     "auto, on out of combat" and the other two
    ns.Swing.Speed(hand) / Armed / Remaining / Fraction   how long a swing is,
                                 whether one is running, how much of it is left
                                 and how much of it is spent, per hand
    ns.Swing.Duration(hand)      how long the swing being drawn is, which is
                                 what Fraction divides by. Anything marking up
                                 that bar asks this rather than Speed
    ns.Swing.Start(hand) / Stop(hand) / Retime()   a swing landed, a swing is
                                 not coming, and the speed moved under one
    ns.Swing.Ready() / HasMainhand() / HasOffhand()   whether the client will
                                 say, and what is in each hand
    ns.Slam.Window()             where the press that costs no swing sits, as
                                 three shares of the main hand swing: open,
                                 close and the exact press between them
    ns.Slam.Cast() / Measured() / Estimate() / Rank() / Known() / Longer()
                                 the cast time being drawn, the one the client
                                 measured, the one worked out from the talent,
                                 the points in it, whether this character has
                                 Slam, and whether the cast outruns the swing
    ns.Slam.Open()               whether pressing Slam right now is the press
    ns.Upkeep.OUT / IN / BOTH    the two lines, checked between fights and
                                 during one, and the saved word for an entry
                                 that stands on both
    ns.Upkeep.Count() / Entry(i) / Missing(i) / Ceiling()   how many buffs are
                                 watched, one of them, whether it is missing
                                 right now, and how many squares the row must
                                 be built to hold
    ns.Upkeep.Lines(entry) / On(entry, line)   which lines an entry stands on,
                                 as the saved word, and whether it stands on
                                 one of them, off the flags Rebuild wrote
    ns.Upkeep.Split() / OnLine(line, at)   how many stand on each line, and the
                                 at-th one on a line
    ns.Upkeep.ShelfCount() / Shelved(i)   what is switched off and drawn under
                                 the row on the page so it can be put back
    ns.Upkeep.Enchants()         both hands at once: enchanted or not, and the
                                 seconds left on each, or nil where this client
                                 has no GetWeaponEnchantInfo
    ns.Upkeep.EnchantShape()     3 or 4, the stride between the two hands in
                                 that call's returns, counted rather than guessed
    ns.Upkeep.Bare(hand) / Left(hand)   whether that hand takes a stone and has
                                 none, and how long what is on it has to run
    ns.Upkeep.Scan() / Rebuild() / Refit()   re-read your auras, rebuild the
                                 list, re-read the art each hand draws
    ns.Upkeep.Fixed() / ByWord(w)   the entries that ship, the racial among
                                 them, plus your class's, read only, and the
                                 one a slash word names
    ns.Upkeep.Owner(id) / Place(key, line, only) / Leave(key, line) / Put(id, line)
                                 which entry answers for a spell; one entry onto
                                 one line, leaving the other as it was unless
                                 `only`; off one line, and off the row from its
                                 last; and a spell dropped on a line whether or
                                 not the row has heard of it
    ns.Upkeep.Watched(key) / SetWatched(key, on)   whether this character still
                                 watches that entry, and switching it
    ns.Upkeep.Silent()           how many entries you switched off, and their
                                 captions in one phrase
    ns.Upkeep.Add(id) / Remove(id) / Extra() / MaxExtra() / Describe()
    ns.Racials.Spell() / Name() / Texture()   the racial this character owns
    ns.Racials.Worth() / Ready() / Idle() / Describe()   whether it is one worth
                                 shouting about, whether it is off cooldown, both
                                 at once, and one line for the status
    ns.BuffNag.Apply / Lock / Reset / Update / Describe
    ns.BuffNag.Mode() / Shown() / Caption() / Icon(slot) / Metrics()   which
                                 line is on screen, how many squares, what the
                                 caption under them says, one square for the
                                 harness, and the square and gap for the page
    ns.BuffPanel.Rows(ui) / Tray(ui) / Square(i) / Shelved(i)   the two lines
                                 and the tray on the options page, and one
                                 square of each for the harness
    ns.Options.Open(title)       the window, shown on the section with that
                                 title; what a thing on screen calls to explain
                                 itself
    ns.SpellIdOnCursor(a, b, c)  which spell is on the cursor, as an id, off
                                 the three values GetCursorInfo hands back
    ns.SwingGauges.Apply / Lock / Reset / Show / Update / Describe
    ns.SwingGauges.Bar(hand) / Applicable()   one hand's gauge, and whether
                                 there is a swing worth drawing at all
    ns.Cast.Build(widget) / Fit / Clear   the cast row one enemy bar carries:
                                 make it, size it to a widget and answer the
                                 node its layout puts under the gauge, and
                                 forget what was last drawn on it
    ns.Cast.Update(widget, unit) / Sweep(widget, now)   what the client says,
                                 read on the bars' tick, and the moving fill,
                                 drawn on every frame
    ns.Cast.Describe()           one line on whether the row is on, whether this
                                 client answers for another unit at all, and
                                 whether it has ever flagged one you cannot stop
    ns.EnemyBars.Sweep()         the cast fills, every frame, and nothing else
    ns.EnemyBars.WidgetFor(unit) the bar on that unit's plate, if there is one
    ns.EnemyBars.Describe()      what the grid resolved to and whether the client
                                 agreed to space plates by the size of a bar
    ns.FrameSkin.Apply()         put the three Blizzard unit frames where
                                 ns.db.skin says they should be
    ns.FrameSkin.Describe()      one line on what the skin did or did not find
    ns.FrameAuras.Build/Place/Update/Style/Unstyle(entry)
                                 the aura rows under a block, built and placed
                                 by UnitFrames/Block.lua and styled by
                                 UnitFrames/Skin.lua, in that order
    ns.FrameAuras.Under(entry, frame)
                                 what now sits between a block and its first
                                 row, which Perch is the only thing that knows
    ns.FrameAuras.Describe() / Probe(entry) / SizeRange()
    ns.Group.Apply()             everything a setting can move about the party
                                 and raid list: where it sits, its zoom, its
                                 attributes and every block under it
    ns.Group.Rebuild()           the slot order recomputed and every block laid
                                 out under it. What the roster events reach, and
                                 the one entry a harness drives
    ns.Group.Update()            every block read off the client and redrawn,
                                 once a second and after anything that moves the
                                 roster. The five times a second pass beside it
                                 draws only the blocks an event marked
    ns.Group.Order()             the slot order as the header was last told it.
                                 Empty while `party order group` is running,
                                 because the header is deciding it then
    ns.Group.OnMember(callback)  what to do to each new button the header makes.
                                 It exists for ctrl-click marking, which a
                                 behaviour file may not reach across for
    ns.Group.Header() / Members() / Count() / Deferred() / Describe()
    ns.Group.SizeRange() / GapRange() / ColumnRange() / Lock() / Reset() / Fits()
    ns.GroupMember.Build(button) / Place(button, look) / Update(button)
                                 one member's block, built, laid out and ticked.
                                 `look` is the whole of what that file knows
                                 about the settings
    ns.GroupMember.Ranged(button)
                                 whether that member is close enough to help,
                                 which is the one reading on a tile no event
                                 carries and the only thing the fast pass asks
                                 the client about every tile
    ns.GroupMember.Rails(button) whether the block still wants the power rail it
                                 was laid out with, which is a relayout rather
                                 than a write
    ns.Unit.Role.Of(unit)        tank, healer or damage, out of four sources
                                 that disagree, cached per GUID where the answer
                                 is settled and never where it is a guess
    ns.Unit.Role.Band(role) / Art(role)
                                 where a role sorts, and the sheet and crop
                                 Blizzard draws it with
    ns.Unit.Role.Set(name, role) / Override(name) / Forget() / Overrides()
    ns.Unit.Role.Describe()      which of the four sources this client carries
    ns.Unit.Spec.Icon(guid, class) / Tree(guid)
                                 the picture of the winning talent tree, and its
                                 index and points. Was ns.MeterSpec
    ns.Marking.Watch(frame)      hook ctrl-click marking onto a frame this addon
                                 made after login, which is every party block
    ns.BlizzHide.Apply()         every frame in UnitFrames/Blizzard.lua put
                                 where its switch says. Not part of the skin: it
                                 answers with every Blizzard unit frame left
                                 alone
    ns.PlayerCast.Apply()        your own cast bar laid out where the settings
                                 say, and locked or unlocked with them
    ns.PlayerCast.Update(now) / Sweep(now)
                                 what the client says, five times a second, and
                                 the fill, on every frame
    ns.PlayerCast.Fail(word)     a cast that stopped without finishing, held red
                                 for seven tenths of a second
    ns.PlayerCast.Bar() / SizeRange() / Describe() / Reset()
    ns.BlizzHide.Switches() / Find(word)
                                 the seven switches in panel order, and the one a
                                 `/wk hide` word names. The panel and the slash
                                 word both walk this rather than writing the
                                 list out again
    ns.BlizzHide.Found() / Describe()
                                 how many of the frames those switches name this
                                 client carries, and what is currently hidden
    ns.BlizzHide.Probe()         one line per name: whether this client has the
                                 frame, whether the attic holds it, and whether
                                 it is on the screen anyway. `/wk hide probe`
    ns.FrameSkin.Landed()        Edit Mode dropped a linked frame: read the gap
                                 and the level back off where it came to rest
    ns.FrameSkin.LinkRange()     gap low, gap high, level low, level high, so the
                                 command, the panel and a drag clamp to one set
    ns.FrameSkin.DescribeLink()  one line on where the target block is hanging,
                                 or which frame it is waiting on
    ns.Options.Refresh()         put the panel back in step with the database
    ns.Options.SelectTab(index)  show one part's page
    ns.Register(feature)         sign a part into the registry, from Feature.lua only
    ns.Each(hook, ...)           run one registry hook across every part
    ns.DefaultFor(key)           the registered default for a setting, for reset
    ns.Command.Toggle(arg)       "off" is off, anything else is on
    ns.Command.Number(v, lo, hi, what)  parse and range-check, or complain and return nil
    ns.Command.Step(v, lo, hi, step, what)  the same on a coarser ruler
    ns.Command.Word(table)       a word table, walked; returns the handler that
                                 `words` registers
    ns.Command.Zoom(key, said)   the zoom entry, whose range is ns.UI's and whose
                                 only argument is the sentence
    ns.Slot.State(slot)          what one action slot is doing: a status out of
                                 UI/Ability.lua's ten, plus the cooldown times
    ns.Slot.Texture / Count / CanRead / Describe
    ns.Reaction.Of(slot)         which reactive ability that slot holds, or nil
    ns.Reaction.Open(key)        whether that window is open right now
    ns.Reaction.Remaining(key) / Name(key) / Watching() / Describe()
    ns.Bars.Apply()              stand the cloned bars up, or take them down and
                                 give Blizzard's back; false when combat deferred it
    ns.Bars.CanPage()            whether a state driver came up, so bar 1 pages
                                 in combat rather than only out of it
    ns.Bars.All()                the bars it built, read only
    ns.Bars.Count() / Hidden() / Keys()   squares drawn, Blizzard buttons
                                 hidden, and keys the override layer took
    ns.Bars.Short(key)           a binding shortened to fit a 27 pixel square
    ns.Bars.Restyle()            lay every standing bar out again to what
                                 ns.BarLook says; false when combat deferred it
    ns.Bars.Describe()           one line for /wk status and the panel
    ns.WhichBars.PLAN            every bar this client can have, in draw order
    ns.WhichBars.Wanted(def) / Want(key, value) / Follow() / Decided()
                                 which of them we clone: the saved answer, or
                                 your own interface options where there is none
    ns.BarLook.Rows(def) / Columns(def)   the shape one bar is drawn in, the
                                 plan's own columns where nothing is saved
    ns.BarLook.SetRows(def, n) / StepRows(def, n)   one of the six shapes twelve
                                 makes, set outright or walked up and down
    ns.BarLook.Size(def) / SetSize(def, px) / SizeRange()
                                 one square's edge, and the range the panel and
                                 the slash word both clamp to
    ns.BarLook.Sharp(px)         whether a stored icon texel lands on a screen
                                 pixel at that size, which is true of two of them
    ns.BarLook.Color(def) / Tint(def) / SetColor(def, key)
    ns.BarLook.Alpha(def) / SetAlpha(def, percent)
    ns.BarLook.Paint(entry)      the ground under one bar's squares, painted
    ns.BarLook.Combat(def) / Key(def) / SetCombat / SetKey
                                 when the bar is on the screen
    ns.BarLook.Visibility(def)   the macro the client evaluates for it, or nil
    ns.BarLook.Watch(entry) / Unwatch(entry) / CanDrive()
                                 hand one bar's visibility to the client, take it
                                 back, and whether this client can do it at all
    ns.BarLook.Shape(def) / Hours(def) / Summary(order)   the two readings on the
                                 panel's page, and one line across every bar
    ns.BarLook.Marking(open) / Marked() / Mark(order)
                                 the accent rim on whichever bar the panel's
                                 page is showing, up with that window and off
                                 again with it
    ns.BarLook.Find(word) / Plain() / Decided()
    ns.BarPlace.Centre(entry, axis)   one axis of one bar's anchor put on the
                                 middle of the screen, the other axis untouched
    ns.BarPlace.Loose()          whether a bar can be dragged right now: every
                                 frame unlocked, or the bars loose and shift held
    ns.Bars.Standing(def)        whether that bar is up, which is not the same
                                 question as whether it is wanted
    ns.Bars.Centre(def, axis)    that, refused in combat, on the bar it names
    ns.Layout.SlotOf(name)       which action slot one of Blizzard's buttons drives
    ns.Layout.CanWrite()         the action API is here, combat is not, cursor is empty
    ns.Layout.CanApply()         that, and you are a warrior
    ns.Layout.Apply / Restore    fill the action bars, or put back what was there
    ns.People.All() / Count() / Get(i) / Name(i) / Find(name)
    ns.People.AddGroup(name) / RemoveGroup(i) / RenameGroup(i, name)
    ns.People.Add(i, name) / Remove(i, at) / Rename(i, at, name)
    ns.People.AddParty(i)        everyone you are grouped with, in one press
    ns.People.Key(name)          what two names have to agree on to be the same
                                 person: the realm off, the case flattened
    ns.People.Match(sender)      every group holding that name, or nil
    ns.People.Total() / Describe()
    ns.Rooms.Route(room, who, whisper)  which rooms one line belongs in
    ns.Rooms.List()              the rail, headers and rooms, in order
    ns.Rooms.Target(id)          the channel a line typed in that room goes to,
                                 and who it is addressed to when it is a whisper
    ns.Rooms.Whisper(name) / WhisperId(name) / Recent() / Exists(id) / Title(id)
    ns.Rooms.Mark(id) / Read(id) / Unread(id) / Waiting() / Describe()
    ns.Compose.Prefix(kind, target)  the slash the field starts with
    ns.Compose.Note(kind, target)    the same thing in a sentence
    ns.Compose.Parse(text, kind, target)  channel, recipient and body, or nil
                                 when the line belongs to the client's parser
    ns.Compose.Send(text, kind, target)
    ns.ChatFeed.Apply()          register or unregister the chat events, and
                                 claim or hand back Blizzard's frames
    ns.ChatFeed.Attach(onLine)   set the sink, and get what arrived before it
    ns.ChatFeed.System(text, r, g, b)  a line Blizzard's window would have drawn
    ns.ChatFeed.Installed() / Claimed() / Describe()
    ns.ChatBlizzard.Apply()      the client's chat window off the screen, or back
    ns.ChatBlizzard.Wanted() / Hiding() / Count() / Describe()
    ns.ChatWindow.Ensure() / Show() / Hide() / Toggle() / Focus() / Shown()
    ns.ChatWindow.Apply() / Lock() / Reset() / Built() / Keys()
    ns.ChatWindow.Send(text)     a line to wherever the room and the text
                                 between them say
    ns.ChatWindow.Go(id) / Step(delta) / Room() / Channel() / Reply(name)
    ns.ChatWindow.Fill() / Line() / Rooms() / Count(id) / Held() / Describe()
    ns.Voice.Supported() / Ready()   whether there is a voice service, and
                                 whether it has signed in yet
    ns.Voice.Options() / Label(value) / Set(value)
    ns.Voice.Apply(force)        join or activate what the setting names
    ns.Voice.Active() / Describe()
    ns.EditMode.CanApply / Capture / Apply / Saved / IndexOf
    ns.interface / ns.vanilla    the interface number, and whether this is 1.x
    ns.Class.Register(token, def)     one call per Class\<yours>.lua, at load
    ns.Class.Token() / Name() / Label()   what the client says you are, its own
                                 localised word for it, and the addon's word for
                                 a refusal to read out. All three are nil, or a
                                 stand-in, until the client will say
    ns.Class.Mine() / Of(field)  your class's table, and one field off it. Nil
                                 is the gate: a part that wants a fact gets nil
                                 and does not build
    ns.Class.All()               every class file that signed in, read only
    ns.Class.Spell(name) / Macro(name)   the two cells a bar plan is built of
    ns.HasThreat() / ns.Threat(source, unit)   the threat API, or nil on vanilla
    ns.HasHealPrediction() / ns.IncomingHeals(unit)   what is already in the air
                                 for that unit, 0 when nothing is, nil when the
                                 client has no prediction at all
    ns.Strip(region) / ns.Unstrip(region)   put a Blizzard region's own Hide where
                                            its Show was, or give it back. For a
                                            texture. It does nothing about
                                            SetShown, which is why frames go to
                                            the attic instead
    ns.Attic.Vanish(frame) / ns.Attic.Return(frame)
                                 a whole frame of Blizzard's off the screen, by
                                 re-parenting it into a frame that is hidden and
                                 cannot be shown, and back where it was found
    ns.Attic.Sweep()             everything the attic holds, checked against
                                 where it actually is, and put back if it moved
    ns.Attic.Held(frame) / Count() / Frame() / Available() / Cageable(frame)
    ns.Blocked(region)           whether a region is protected and in lockdown,
                                 so the caller can queue the work for regen
    ns.Artwork.Apply()           re-run the bar art strip from ns.db.blizzArt
    ns.Loot.Apply() / ns.Loot.Describe()   put the addon on or off the loot
                                 path, and one line on which it is
    ns.Vendor.Apply() / ns.Vendor.Stop() / ns.Vendor.Running() / Describe()
                                 the same for the merchant, plus a way to end a
                                 sale in flight and a way to ask if one is
    ns.Camera.Apply() / ns.Camera.Current() / ns.Camera.Describe()
                                 write the zoom CVar, read back what the client
                                 actually kept, and say so
    ns.Clutter.Scan()            every quest item in your bags that is finished
                                 with, each with the reason, plus a word saying
                                 why the list is empty when it is not "clean"
    ns.Clutter.Certain(entry) / Ready() / Describe()   whether that entry is a
                                 straightforward yes, whether Questie is
                                 answering at all, and one line on which
    ns.Destroy.Show() / Hide() / Toggle() / Describe()
                                 the clutter window, and one line for /wk status
    ns.Destroy.Take() / ns.Destroy.Skip()   the two buttons, which is the only
                                 route to a delete in the whole addon

Anything that changes a setting outside the panel ends by calling
`ns.Options.Refresh()`. The slash handler already does.

Each module exposes the same three-ish entry points so the slash handler can
drive them without knowing anything: `ApplyLayout()`, `ApplyLock()`, `Update()`,
and `Rebuild()` for EnemyBars. All of them must tolerate being called before
PLAYER_LOGIN, so each starts with a nil guard on its frame.

Adding a setting means adding a key to the `defaults` table in that part's
`Feature.lua`, or to `charDefaults` when the setting describes one character
rather than the account. Core merges every part's defaults and backfills missing keys on
load, so existing saved variables pick it up without a migration step. Two parts
defining the same key is an assertion at load, not a last-writer-wins surprise.

### Asking Questie

Questie is another addon and half a dozen files here read something out of it:
where a quest sends you, what a creature is wanted for, which quest an item in
your bags belongs to, what Questie has drawn on the map, and whose quest log a
party member has broadcast. All of it comes through `QuestieLoader:ImportModule`,
and that call has a trap in it. A name it has never heard of gets a fresh empty
table back rather than nil, so a client with no Questie at all answers every
question with a table and the module coming back proves nothing.

The honest test is whether the call you meant to make is on the module, so
`ns.Questie` takes the names of the calls:

    local db = ns.Questie("QuestieDB", "QueryItemSingle", "QueryQuestSingle")
    if not db then
        return nil
    end

Nil there means Questie is not installed, is a version without those calls, or
has not finished compiling its database. All three are the same answer to the
caller: ask the client instead, or say out loud that this cannot be answered.

Function names only. A data field like `currentQuestlog` or `questIdFrames` is
filled in after login rather than at load, so refusing the module over one would
report a missing Questie for a quest log that is merely not built yet. A caller
reading a field checks that field itself, at the read.

Nothing is cached. The database compiles minutes after login and an answer taken
before that would be wrong for the rest of the session, which is the reason
`EditMode.CanApply` is not cached either.

Five files had written this probe out by hand, four of them character for
character, and `Quests/Where.lua` handed its copy back out as `Where.Module` so
`Quests/Drops.lua` could borrow it. `scripts/check.sh` fails on `QuestieLoader`
or `ImportModule` anywhere outside `Core/Core.lua`, comments included, which is
the layering rule the addon already believed in: outside Core, a file does not
probe for a call it means to make.

### The pixel grid

The client draws the interface in a virtual space 768 units tall whatever the
monitor is. A frame of height H at effective scale S covers `H * S *
physicalHeight / 768` physical pixels, so one pixel is `768 / (S *
physicalHeight)` units.

`ns.Pixel` returned `1 / S`, which is that formula with the screen height
assumed to be 768. On a 1440 tall screen at UI scale 0.65 the true figure is
0.82 units and the old one was 1.54, so every hairline in the addon was being
asked for at nearly two pixels and landing as a smear along one edge of a box
and a line along the other. That was the whole of "nothing looks crisp".

Correcting the arithmetic is not enough, because a correct fractional number of
units still lands wherever the frame's origin happens to sit. So the addon does
not work in fractions. `UI.Adopt` calls `SetIgnoreParentScale(true)` and sets
the frame's scale to `768 / physicalHeight`, and inside that frame one unit is
one physical pixel. Every size in `EnemyBars.lua` is a whole number of pixels
written as a whole number, `ns.Pixel` on such a frame returns exactly 1, and
nothing rounds on a ticker.

**There are two pixel rules, not one, and they want opposite things.**

1. **A static edge lands on a whole pixel.** A border, an icon crop, a band, a
   mark, a block of art, anything that holds still while you look at it. Drawn
   across two rows of pixels it reads as blurry, and blurry is what this whole
   section exists to stop. Gated by the anchor sweep at the end of
   `scripts/harness.lua`, which walks every offset on the grid at 1x, 2x and 3x.
2. **A moving fill is not quantised.** A swing bar and an enemy cast bar, which
   are the two things in this addon that draw motion.
   What the eye reads on a moving edge is its velocity, and
   velocity lives in where the edge sits between two pixels as much as in which
   pixel it is on. Rounding it throws away the only thing being looked at, to
   buy a sharpness nobody can see on something in motion. Rounding is also a
   throttle: a 180 pixel fill crossing a 3.4 second swing can only change value
   53 times a second once it is rounded, however often the tick runs, so it
   stands still on 91 of the 144 frames a fast screen draws. Gated in
   `scripts/harness/sections/27-swing-visible.lua`, which asserts that the fill
   lands off a whole pixel on nearly every frame, and again in the cast section,
   which drives a cast across two frame rates and asserts that no frame repeats
   the position of the one before it.

Rule 1 was written when every edge in the addon was static, and for that
codebase it was the whole truth. The swing bar was the first moving edge and it
was quantised because the rule said to, which is how a rule that was right for
every case it had met produced a bar that visibly stepped. See "one pixel rule
was two" under traps already hit.

Which rule an edge falls under is not a judgement call: it is whether the edge
moves under a moving clock. The Slam band and its mark move, but they move when
your weapon speed does, which is a few times a fight, so they are static edges
and they land on whole pixels.

Three consequences worth knowing before changing anything under it:

- **Sizes are absolute now.** A 21 pixel bar is 21 pixels on a laptop and 21 on
  a 4K panel. That is the point and it is also the cost, which is what
  the zoom page is for. Every screen the addon draws carries its own number,
  from 0.5x to 3x in tenths, so you can shrink the map and grow the hover box in
  the same sitting. Three of those stops keep the grid on a screen that
  contributes 1 and the rest let you off it on purpose, because a soft hairline
  is a price you are allowed to choose. The page prints, per screen, which of
  the two states that screen is in.
- **`ns.UI.Pixel` and `ns.UI.Unit` are not the same question, and mixing them up
  makes a zoom setting inert.** `Pixel` answers "how many units is one screen
  pixel", which on the grid is `1 / zoom`. `Unit` answers "how many units is one
  pixel of the design", which on the grid is 1 whatever the zoom, because the
  zoom is what turns that unit into a 1x1, 2x2 or 3x3 block. A layout that runs
  its own design numbers through `Pixel` has divided itself by the zoom, and the
  scale multiplies it straight back. Use `Pixel` for a hairline or an inset,
  which is one screen pixel and stays one when the design grows. Use `Unit` for
  every number that is a size.
- **A measurement from outside the grid means nothing until it is converted.**
  A nameplate is not on the grid and never will be. `ns.UI.Convert` takes a size
  from one frame's units into another's, and `ns.UI.Round` snaps what comes out.
  A width read off a plate and used directly is a bug that looks like a
  rendering artefact.
- **A bar on a nameplate cannot be snapped in position.** Its origin is wherever
  the mob is standing, which is a moving fraction of a pixel no addon can read.
  Its geometry is exact; where that geometry lands is the client's business.
  Bars in the list anchor to UIParent and are exact in both.
- **An anchor offset is a number a person typed, and half of an odd number is
  half a pixel.** The grid makes sizes exact and does nothing at all about
  position. A frame whose own origin sits half a pixel off a boundary has every
  edge, glyph and icon inside it rasterised across two rows, and the arithmetic
  that produces it looks like centring, because it is. Three of these were live
  at once in the enemy bars, including one on the widget itself in the default
  style, which meant every bar the addon had ever drawn was half a pixel low.
  The harness now walks every frame on the grid and fails on any offset that is
  not a whole number of pixels.

Icons are a separate fix in the same file. A flat colour is one texel stretched
over a rectangle and there is nothing to get wrong. A spell icon is a 64 texel
square resampled to whatever the layout asked for, and it needs two things: a
crop on a texel boundary, `5/64` and not `0.08`, and the client's own
`SetSnapToPixelGrid` turned off, because that pulls a texture's corners onto
whole pixels and stretches the two axes by different amounts. Both methods are
probed rather than called, and an icon that is merely soft beats a widget that
raises. `ns.UI.Icon` does all of it.

### Text

Every string in the addon goes through `ns.UI.Font`, which hands out one shared
font object per size and flag pair. A font string given a font by `SetFont`
carries its own copy of it; one given a font object shares. The bars alone put
eight strings on a widget and lay out a widget per nameplate, so that is a
couple of hundred private font instances against six shared ones, and a font
size change is six writes rather than one per string.

The typeface is `Fonts\ARIALN.TTF` and it is not a setting. Friz Quadrata is the
client's default and it is a serif cut for a 2004 headline, not for a ten pixel
number over a moving nameplate. Every client since the first ships Arial Narrow,
so it costs no asset in the addon folder and no dependency.

**The second face is five marks, and they are cut onto letters.**
`Media/Glyphs.ttf` is a subset of Font Awesome Free Solid: the two chevrons on a
group that folds, the close cross, and the two ends of a stepper.
`scripts/bake-glyphs.sh` builds it from the system copy and it comes to about
two kilobytes.

What makes it worth doing this way is where those five glyphs sit in the font.
They are not on their own codepoints, they are on `v`, `>`, `x`, `+` and `-`,
the letters this window drew before the font existed. So no call site carries a
codepoint escape, nothing checks whether the font loaded, and a client that
refuses the file gets Arial Narrow at the same size and draws the letters again.
The fallback is the thing the code was already doing.

`ns.UI.Glyph(parent, size, colour, justify)` is a string in that face and
`ns.UI.Button` takes `glyph = true` for a button whose label is a mark rather
than a word. A glyph is not an icon: an icon is the game's own art for a spell,
which `UI/Draw.lua` crops and `ns.UI.Icon` hands out. Marks are drawn two pixels
under the body size, because a Font Awesome glyph fills its em box while a
letter of Arial Narrow uses about two thirds of one.

The font is under the SIL OFL and the licence travels beside it in `Media/`.
`check.sh` fails a font in there with no `<name>-LICENSE.txt` next to it, and
`release.sh` fails a zip that is missing either file.

**Three roles, and every string is exactly one of them.** This is the whole font
policy. Pick the role from what is behind the glyph, never from how it looks.

    flat       over a surface this addon painted and knows the colour of.
               Panel prose, and every string on a bar. Nothing round the
               glyph, because Unit/Color.lua guarantees the contrast.
               ns.UI.FLAT.
    shadowed   over art the addon did not paint and cannot predict, which is
               a spell icon under a stack count. A one pixel drop shadow,
               which holds the glyph off a bright icon and spends none of the
               glyph's own pixels. ns.UI.SHADOW, or ns.UI.NumberFont. An
               aura's time left takes this role over the world as well, since
               it is drawn below the outline floor and has no other option.
    outlined   over the world. The only place with no known colour behind it,
               so a shadow has nothing to be darker than. The default.

An outline and a shadow do the same job, which is to keep a pale glyph off what
is behind it, and they pay for it differently. The outline spends the glyph's
own pixels; the shadow spends the pixel below and to the right. That is why the
outline is last resort and not first: over anything with a known colour the
shadow is strictly better, and over a surface the palette caps neither is needed.

`ns.UI.SHADOW` is not a client flag and never reaches `SetFont`. It rides inside
the flags string so that it threads through `ns.UI.Label` and every other site
that already passes flags along, instead of adding a parameter to all of them.

**`ns.UI.OutlineFloor` is a minimum size, not a switch.** An outline costs a
pixel on every stroke whatever the glyph is, so below fourteen it has eaten the
counters: the hole in a 6, the waist of an 8, and a 3 and an 8 stop being
different shapes. Only text over the world is outlined now, and that text has no
fallback to switch to, because flat over the world is not softer, it is gone. So
a string that must be outlined must also be at least fourteen pixels tall.

**MONOCHROME is not in the addon and this is why.** It was tried as the default
for everything at or under sixteen pixels, on the theory that turning the
rasteriser off would stop an anti-aliased rim bleeding into an anti-aliased
stem. It does, and it also breaks the stems. An unhinted humanist face at eleven
to fourteen pixels has stems that do not land on pixel boundaries, and rounding
each one independently on and off makes them different weights, so whole words
come out uneven. It looked sharp on a 14 pixel numeral over a bar and it looked
like damage on a tooltip and on a meter row, which is most of the text this
addon draws. The report was that all the text had gone fuzzy, and it had. The
harness asserts that no string carries the flag, because the next person to
reach for it will reach for it in `UI/Text.lua` and not in this paragraph.

**Sharpness is geometry first and contrast second, and there is no third.** The
grid puts every glyph on a whole number of physical pixels, which is as far as
geometry goes. Everything after that is the section below.

### Contrast

A colour this addon fills a bar with is a background, and something is written
on top of it. That is a different job from the one Blizzard's class colours were
chosen for, which is a name **in** the colour against a black chat window, and
the two want opposite things. Six of the nine classes are too light to be a
background for anything. One of them is white.

The palette was carrying the consequence in silence. White on the warrior tan is
2.4:1. On the threat amber it is 1.6:1, on the threat green 2.4:1, on the orange
2.3:1. Two colours in the whole set were over 4:1, nothing anywhere said so, and
the report that came back was that the frames were not sharp. They were not
soft. They had no edge to be sharp at.

So `Unit/Color.lua` carries a rule rather than a pile of hand-picked pairs.

    Color.paper            the one colour text is drawn in over a fill
    Color.TEXT_RATIO       4.5, for a name and a number, which are read
    Color.TOKEN_RATIO      3.0, for a level tag and a stack count, which are
                           recognised
    Color.Luma(c)          sRGB relative luminance, the WCAG definition
    Color.Contrast(a, b)   how far apart two colours are, 1 to 21
    Color.fills / .tokens  every colour in each role, so a gate can walk them
    Color.Describe()       the whole table, and `/wk colors` prints it

**Every fill is taken under a luminance ceiling, and the ceiling is solved, not
typed.** It is the value at which `Color.paper` clears `TEXT_RATIO`, which is one
rearrangement of the contrast formula, and writing the answer down instead is how
a threshold and its consequence drift apart. One text colour then works on every
fill, at every state of the bar: the spent end is the fill through `Color.Dim`,
which is darker still.

**The shaping scales the linear components by one factor.** That is the only
operation that takes brightness off without turning the hue, which is why the
warrior still reads as tan and the threat green still reads as green. A colour
halved in sRGB is not half as bright, and a scale that pretends it is turns a
hue as it dims it. Warrior goes `0.78 0.61 0.43` to `0.55 0.43 0.30`.

**Tokens run the other way**, with a floor rather than a ceiling, and a hue that
cannot reach it is blended toward white until it does. Three rather than four and
a half is a judgement and not a rounding: these are two digits and a percent sign
in a HUD, not a paragraph, and holding a five colour scale apart is half of what
they are for.

**The pass runs once at load and writes in place**, so a colour keeps the table
identity the tickers guard on, and it is deduped, because the roles share tables
on purpose. `HUE.slate` is the idle threat state, the idle reaction and a locked
cast at once, and darkening it three times would land it at a fraction of what
the ceiling asked for. That is the one bug this pass can have.

**Not shaped:** `Color.frame` and the hues under it. An edge is a pixel of chrome
round a box with nothing ever drawn on top of it, so a ceiling meant for
backgrounds would do nothing but stop the one state that departs from departing.

**Classes carry two colours, and confusing them is the bug the whole section
exists to prevent.** `tint` is the identity and goes in a chat line, where the
colour is the text. `fill` is the bar, where the colour is the background.
`Color.Class` hands back the fill and `Color.ClassHex` hands back the tint. The
nine are written down in `Unit/Color.lua` rather than read from
`RAID_CLASS_COLORS`, because a fill has to be shaped before it can carry text,
shaping reads the number, and a global this addon does not own can be absent on
one of the two clients or moved by another addon that got there first. A class
off the end of the table still arrives through that global and is shaped on the
way in.

**Where to put a new colour.** A fill goes in one of the role tables and the
shaping pass takes it. A short coloured string on a fill goes in `Color.xp` or
`Color.text` and the floor takes it. Prose over a fill is `Color.paper` and
nothing else. The harness fails on anything that misses its threshold, so the
answer to "is this readable" is never a judgement made at the call site.

**One place the rule gives a bad answer, and it is not hidden.** The XP scale
collapsed at the top: `hard` is `1.00 0.76 0.52` and `deadly` is `1.00 0.74
0.73`, differing only in blue. A red that dark cannot be read off a dark fill, so
raising it to the floor walks it toward white and it lands on salmon. The rule is
telling the truth. A red level tag on a coloured bar cannot be both red and
readable, and the fix is a dark chip behind the tag, which is a layout change and
not a palette one.

### The widget library

`UI/` was three files and a pixel grid. It is nine now, and the six new ones
are a widget library rather than a settings panel: the options window is the
first thing built on them and is not meant to be the last.

    ns.UI.Color / ns.UI.Metric     the palette and the measurements
    ns.UI.Box / ns.UI.Rule         a filled box with a hairline, and a hairline
    ns.UI.Stack(parent, width)     a column, :Add, :Space, :Reflow
    ns.UI.Flow.Arrange(root, tree) rows, columns, wrapping and alignment
    ns.UI.Flow.Lines(node)         where a wrapping row breaks
    ns.UI.ScrollView(parent)       :Resize, :Update(extent), :ScrollTo
    ns.UI.Button(parent, opts)     a push button
    ns.UI.Pixel(frame)             one screen pixel, in that frame's units
    ns.UI.Unit(frame)              one design pixel, in that frame's units
    ns.UI.Size / ns.UI.SetSize     what the player dragged the size slider to
    ns.UI.ScreenZoom / WindowZoom  the screen's whole step, and it times the size
    ns.UI.Kit(host)                the widget kit
    ns.UI.ZOOM_LOW / ZOOM_HIGH     the one zoom range, 1 to 3
    ns.UI.ALPHA_LOW / HIGH / STEP  the one opacity range, 0 to 100 in fives
    ns.UI.Window(opts)             chrome, adopted onto the grid
    ns.UI.Rail / ns.UI.TabStrip    the two levels of navigation
    ns.UI.Windows                  every window the library has made

**Every row is asked its height, never told.** A widget that carries text hands
its stack a measure function. Reflow sets the row's width first, asks second,
snaps the answer to a whole pixel and only then places the row under it. Doing
those two in the other order is the whole of the overflow bug that was in the
old panel: a row measured against the previous pass's width is a row drawn on
top of whatever follows it.

**A page has two levels and the kit names both.** `ui.Section(title, group)`
says which of the window's nine groups the rows after it belong in, and the
title becomes one line under that group when the rail folds it open. The kit asks its host where sections
go; a host that answers nothing gets a heading rule in the same column instead,
which is what this call was before the window had a rail.

**Prose is three capped calls, and controls register themselves.** `ui.Lede` is
one 160 character line under a section title, `ui.Hint` is a 200 character
sentence drawn in the tooltip on hover, and `ui.Reading` is a live value on the
right of its own row that never wraps. Every control also records its label into
the host's index as it is built, which is what the search field walks and what
the harness counts labels out of.

**Two pieces live outside the kit, because a page sometimes lays out its own
row.** `ns.UI.DropSquare` is the square you drop a spell or an item onto and
`ns.UI.KeyBox` is the box you press a key into. Both were closures inside
`UI.Kit`, reachable only through the labelled full width row built around them,
and the mouseover casting page needs four of them side by side on a row it draws
itself. Each takes an `opts.after` to put its page back in step, which is what
the kit passes its own refresh in. `ui.Custom` takes an `opts.label` for the same
reason: a row a page builds itself belongs in the search index like any other
control.

**Four calls carry the ranges that are genuinely one range.** `ui.Zoom` takes
neither a label nor a range, `ui.Opacity` takes no range, `ui.Size` keeps the
caller's range and writes `px` after the number, and `ui.Count` is whole numbers
one at a time. `ns.UI.ZOOM_LOW`, `ns.UI.ZOOM_HIGH` and the three `ALPHA_`
numbers are public for the slash words that take the same value, so a range is
written once in the addon rather than once per part.

**The window is adopted, so it is exact.** Unlike a nameplate it is a frame the
addon owns and anchors to UIParent, so every number in `UI.Metric` is a count of
physical pixels and the window is 544 by 452 of them. It does not resize itself
to its content and it does not grow: a section that does not fit scrolls.

**Zoom comes from two numbers that multiply.** `UI.ScreenZoom` is a whole step
read off the screen height, 1 below 2000 pixels tall and 2 above. The other is
the number the player set for that one screen, 0.5 to 3 in tenths, held in the
account file under the key the part registered. `ns.Zoom(key)` is the product,
and it is what a window is adopted at. A 4K screen that has already doubled
everything and a player who halves it land back on the design size with the grid
intact.

There was one number for every window, called `uiSize`, and it was wrong for the
reason the chat window worked out first: shrinking a map to sit beside a quest
log shrank the quest log with it. A part declares each sizeable screen in its
`ns.Register` call under `zooms`, and the zoom page draws a row per entry
without naming a single feature. A player who had dragged the old slider has
that number written onto every window key still at its default, once, and
`uiSize` is dropped.

`UI.Window` takes `opts.zoom` as a getter and keeps its own frame on the grid:
it registers one `OnRescale` listener that asks the getter and re-zooms. A
caller with layout to redo passes `opts.rescale`, which receives the rezoom as a
function so it can defer it, as the character sheet does in combat, or run it
before its own `Fit`. Adding a window means passing a getter and nothing else.
Ten windows each carried the rezoom in a listener of their own before this.

**Three client questions, all probed.** Clipping is `SetClipsChildren` where it
answers, the `ScrollFrame` frame type where it does not, and nothing at all
where neither does. The bar is a `Slider` frame type with a thumb the addon
draws, chosen because following a dragged thumb by hand means an `OnUpdate` and
this addon does not add a ticker for a settings window. The wheel is
`EnableMouseWheel`. No Blizzard widget template is used anywhere in the layer.

### Layout, in the sense a stack panel means it

`ns.UI.Stack` lays a settings page out: a column of rows, each asked its own
height. `ns.UI.Flow` is the other kind, the one a HUD widget wants, and it is
what XAML calls a StackPanel and CSS calls a flex container. You describe what
goes where and it works out the offsets.

    Flow.Arrange(widget, {
        direction = "column", gap = 4, align = "stretch",
        { frame = widget.targetedBy, height = 15, align = "center" },
        { direction = "stack",
            { frame = widget.threatText, alignX = "start", alignY = "end" },
            { direction = "row", wrap = true, justify = "end",
              lineOrder = "up", ... },
        },
        { frame = widget.box, height = 23 },
    })

Two passes, the same two XAML has. Measure asks every node how big it wants to
be, bottom up. Arrange hands every node the rectangle it got, top down, and pins
each frame to the root's top left corner at the offset that came out.

**Pinned to one corner, not chained.** A chain of anchors can only align the run
it starts, which is why the debuff row on an enemy bar used to be anchored square
by square to the gauge's corner with the row width subtracted by hand.

**A stack is XAML's single-cell Grid.** Every child gets the whole rectangle and
places itself in it with `alignX` and `alignY`. It is how the threat line and the
debuff row share one strip of screen: in a row each would reserve space from the
other and the icons would wrap early.

**`reverse` is the whole of mirroring.** The run starts at the far edge and walks
in. Nothing else about a mirrored layout differs.

**Both unit frame files are laid out by it.** The enemy bar is a column with a
wrapping row in it. The skinned block is a mirrored row, and `reverse = spec.mirror`
is the whole of the mirroring: the target frame is the player frame with that
flag set. What Flow will not place is the block's own anchor on Blizzard's frame,
the badge regions the client owns, and the four font strings sized by whatever
the unit is called.

**It does not do content sizing, and it will not.** A node's size is a number the
caller knows before the layout runs. The two strings inside an enemy bar's gauge
are sized by whatever the mob happens to be called, so they stay pinned to each
other with plain anchors. A layout that had to re-run when a name changed would
be a layout running on the tick, and `check.sh` is what keeps that boundary: no
function in `UI/Flow.lua` is reached by `scripts/hot.lua`'s walk, so it may
allocate and the files that call it may not.

`scripts/harness.lua` gates the engine on its own, before anything built out of
it: nine shapes, each read back off the offsets Flow wrote. A layout bug inside
the enemy bars shows up as one failing assertion about a debuff square and takes
an hour to trace back to the arithmetic. The same bug there names itself.

### Where the client puts a nameplate

Bars piling up when two mobs stand together is not a drawing bug and no care in
the widget fixes it. Blizzard's driver decides where a plate goes, and it uses
two things `UnitFrames/Plates.lua` can reach: `nameplateMotion`, which on 0 lets
plates overlap freely and on 1 makes the driver push them apart, and the plate's
size, which the driver takes to be Blizzard's nameplate. Ours is twice the
height of that, and taller again while a mob is casting.

`SetNamePlateEnemySize` tells it the real figure, sent in UIParent's units
because that is what the driver counts in. Where that call is missing,
`nameplateOverlapV` multiplies the height the driver uses instead. Both are
behind one setting, `bars stack`, and both are the player's, borrowed: the prior
value is saved on first touch and put back when the setting goes off, the same
discipline `Charge/SoftTarget.lua` applies to `SoftTargetEnemy`.

Sizing the plate moves the click target with it. A taller plate takes the mouse
over more of the screen, which is more room to click a mob and more of a camera
drag swallowed, and that trade is why this is a setting rather than something
the part does quietly.

### What the addon costs

`GetAddOnMemoryUsage` answers one number for the whole addon, and one number for
the whole addon is close to useless: "WarriorKit, 341 KB" names nothing you can
switch off. What is worth measuring is the four tickers, because each one maps
to a setting on the page next to the one reporting it.

So the tickers time themselves. `debugprofilestop` is a millisecond clock with a
fractional part, two calls bracket a tick body outside the functions `HOT`
names, and forty ticks a second across the whole addon makes that free by any
measure that matters. The tab reports what the measuring costs anyway, because a
performance tab that will not account for itself is asking to be believed rather
than read. Each figure is given twice: per tick, which is the spike you feel,
and per second, which is the share of the frame budget it actually takes.
Neither one alone answers "is this expensive".

Two things the client cannot tell you, both written into the tab and not only
here. It attributes Lua allocation to an addon and nothing else, so frames and
textures live on the C side and never appear in the figure, and for a UI addon
those are most of the real footprint: read it as churn rather than as size. And
the allocation rate counts rises only, because Lua's collector runs whenever it
likes and a fall in the resident number is that happening rather than anything
the addon handed back.

Per addon CPU through `GetAddOnCPUUsage` needs the `scriptProfile` CVar and a
reload, and it slows the whole client while it is on. TitanPerformance owns that
setting in this install. `Perf.ClientCPU` reads the number where someone else has
already turned it on and never turns it on itself.

This is the field instrument and the harness is the gate. The harness measures
allocation against a stub, deterministically, and fails the build on a
regression. The tab measures the thing a stub cannot, which is real frame time
at fifteen plates in a real raid. Numbers the tab surfaces are candidates to
become new ratchets.

### Ticker discipline

Every tick in the addon is one call, `ns.UI.Ticker(frame, interval, name, fn)`
in `UI/Ticker.lua`. Before it, twelve files wrote out the same accumulator by
hand and one of the twelve got it wrong. It is one line each now, and the list
below is the whole of what runs.

    Swing/Gauges.lua         every frame  two gauges and the Slam band
    UnitFrames/EnemyBars.lua every frame  the cast fill on every bar on screen
    UnitFrames/PlayerCast.lua every frame your own cast fill, moving
    UI/Tooltip.lua           every frame  the linger before a box goes
    Comfort/Thanks.lua       every frame  only while a whisper is waiting
    Charge/Marker.lua           20 Hz     it tracks the camera
    Charge/Icon.lua             10 Hz     the HUD icon and the macro
    Buttons/Bars.lua            10 Hz     every square on every cloned bar
    Buffs/Nag.lua               10 Hz     the missing buff row, and its pulse
    Cooldowns/Row.lua           10 Hz     the long-cooldown row and its countdowns
    UI/Chart.lua                10 Hz     the arrow on an open map
    World/World.lua             10 Hz     whether you are still looking at it
    UnitFrames/PlayerCast.lua    5 Hz     what you are casting, asked again
    UnitFrames/Skin.lua          5 Hz     the marked blocks, and target of target
    UnitFrames/Group.lua         5 Hz     the range on every tile, and the marked
    Meter/Window.lua             5 Hz     the two panes of numbers
    Buttons/Trace.lua            5 Hz     only while /wk bars trace is on
    Comfort/Vendor.lua           5 Hz     only during a sale, and it stops itself
    UnitFrames/EnemyBars.lua     1 Hz     everything else on every bar on screen
    UnitFrames/Skin.lua          1 Hz     all three blocks read from the top
    UnitFrames/Group.lua         1 Hz     every tile read from the top
    Feeds/Stream.lua             1 Hz     the strip under a feed
    Minimap/Clock.lua            1 Hz     the reading on the minimap square
    UnitFrames/Blizzard.lua      1 Hz     every Blizzard frame the switches hide
    Perf/Perf.lua                1 Hz     only while the performance tab is on screen

Three of those hold their ticker and stop it: the sale when it runs out of
trash, the whisper queue when it empties, and the sampler when you leave the
performance tab. Four more hang off a frame that hides, so they stop with the
window they are drawn in. A frame whose tickers have all stopped gives its
`OnUpdate` back, so a part nobody is looking at costs the client nothing rather
than a call and a comparison every frame forever.

Four parts carry two tickers, at two rates and under two `Perf` slots each: the
enemy bars, your own cast bar, the skinned unit frames and the party tiles. The
first two were one handler with a throttle written inside it, which meant a
fifth-of-a-second poll and a per-frame fill were reported as one number. The
other two are the same split the bars already took: a fast pass over what the
client said moved, and a slower reading of everything for what no event carries.
A row's hertz in `Perf/Feature.lua` is what turns a per-tick figure into a share
of a second, so it moves with the interval or the tab lies.

The accumulator subtracts the interval rather than zeroing it. Zeroing throws
away however far past the interval the frame landed and turns 5 Hz into every
fourth frame at 60 and every twelfth at 144, which are 4.6 and 4.8. That was the
first of the two bugs behind the stepping swing bar, and nine of the twelve
hand-written copies had it. A frame longer than the whole interval drops the
debt instead of catching up, so a stall does not run the body twice.

Two handlers are still a raw `SetScript`, and neither is a tick. `UI/Placeable`
follows a dragged frame while the button is down, and Core hands a rebind one
frame to run in. Both name a function, which is all the scan below needs.

The buff row is ten rather than five for one reason and it is not the readout.
What it says changes when an aura lands, which is an event, and the row would be
correct at one hertz. Ten is the rate the pulse on the racial square needs: 1.6
seconds a cycle at ten hertz is sixteen alpha steps, which reads as a breath. At
five it reads as a blink.

The cooldown row is ten for a different reason, and it is the readout. Under ten
seconds a square counts in tenths, so the number on it moves ten times a second
and a five hertz tick would draw every second one of those. Above ten seconds
nothing on the row changes faster than once a second and the tick costs one
comparison per square, because UI/Ability.lua builds the string only when the
number behind it has moved.

Nothing in either tick walks your auras. UNIT_AURA fires for every buff you gain
and every one you lose, so the scan runs from the event and the tick reads a
field. The two weapon enchants are the exception and are read live, because a
stone running out fires nothing at all, and that costs two numbers out of one
call rather than a walk of forty slots.

Two rows have no rate, and they are the two things in the addon that draw
motion. Every other ticker refreshes a readout, and a readout refreshed twenty
times a second is never more than fifty milliseconds stale, which nobody can
see. A swing bar and a cast bar are not readouts, they are moving edges, and a
moving edge is an animation. An animation is drawn on the frame the screen is
drawn on or it is drawn in steps.

The enemy bars are on that list twice, and that is the arrangement rather than a
duplicate. Two tickers hang off one frame: `EnemyBars.Sweep` every frame, which
advances the cast fills and nothing else, and `EnemyBars.Update` at one second,
which reads everything a bar says that is not moving. They were one handler
with a hand-written accumulator inside it, and the accumulator is now `UI.Ticker`
for every part of the addon at once.

The skinned frames and the party tiles are on it twice for the other reason. The
fast pass draws only what an event marked, and each has exactly one thing left
on it that no event carries: whether target of target belongs on the screen, and
whether a party member is close enough to help. Both are asked every pass for
every unit and both are one call. The reading behind them draws everything and
is what covers an incoming heal, a name, a level and a client that says nothing
about a `targettarget` token.

The report back was that the timer "jumps chunks", and it took two repairs
because there were two throttles on that one edge. The first was the 20 Hz
ticker, which at the shipped width moves the fill about three pixels at a time.
The second was the rounding: a fill snapped to a whole pixel can only change
value 53 times a second across a 3.4 second swing, whatever rate the tick runs
at, so it stood still on 91 of the 144 frames a fast screen draws and each move
was a whole design unit, which is three screen pixels at `swing zoom 3`.
Deleting the ticker raised the drawn rate from 20 to 53 and left the rounding in
place, which is why the bar still stepped. See the two pixel rules under the
pixel grid.

So the fill is now written as a fraction, on every frame, with nothing in front
of it. It is the one write in the addon that is not guarded, and the exemption
is on the line rather than in an allow-list. What it costs was measured rather
than argued: the swing tick allocated 0.03 KB per fifty ticks rounded and
guarded, and allocates 0.03 KB per fifty ticks unguarded. Every other rate in
the table stands, because none of those parts draws motion.

The last one is the exception that proves the rule rather than a loosening of
it. `UpdateAddOnMemoryUsage` walks every addon the client has loaded, which
would make the file that measures the cost the most expensive thing in the
addon. So it is started by the tab's `OnShow` and stopped by its `OnHide`, and
nothing samples memory when nobody is reading it.

The rule on those paths is that nothing writes to a frame without comparing
against the value already there. `SetText` costs a string measure and a
relayout whether or not the text changed. `SetScale` dirties the layout of a
frame and every region inside it. A guard costs one comparison.

This was the defect that made the addon feel sluggish. `UpdateWidget` guarded
the cheap comparisons and left the expensive writes open: 26 widget writes per
mob per tick, which at fifteen nameplates is about two thousand pointless font
string and texture updates every second. The `before`/`after` measurement, taken
by driving the module under a stubbed API, was 468 writes across nine idle ticks
against two mobs, and 0 after.

The same rule covers work that produces a value, not only work that writes one.
`ChargeIcon.SyncMacro` compared the macro string it had just built, so the guard
never saved the building: a table, a dozen formatted lines and a concat, thirty
times a second. It now compares the three inputs instead, the unit, the weapon
setting and `ns.Charge.NameEpoch()`.

The same rule now covers allocation, which is the same defect one step further
out. A table constructor or an anonymous function on a ticker is garbage the
collector has to walk later, and the collector runs in the middle of a frame.
The list collector was building a table for the list, one per mob in it and two
closures every fifth of a second, about eighty objects a second to answer a
question whose answer rarely changed. Measured under the harness at two bars and
fifty ticks, that was 51.76 KB before and 4.10 KB after. The plate path was
already clean and measures 0.17 KB. An allocation behind an `if` is a cache
being filled once and is fine; one the tick reaches every time is not.

`check.sh` enforces this. `HOT` is every function a frame handler can reach, and
a `:SetSomething(` call or a table constructor inside one fails the build unless
an `if`, `elseif` or `else` stands between it and the top of the function. A
`for` loop is not a guard: it repeats the write, it does not decide it.

`HOT` used to be two hundred lines typed at the top of `check.sh`, and a typed
transitive closure fails one way and says nothing while it does: a hot function
grows a new callee, nobody adds it, and the scan quietly comes off that code.
`scripts/hot.lua` computes the list now, walking out from every ticker and every
`OnUpdate`. It resolves a module call by matching `Local.Fn` to its definition,
reads `ns.Alias = Local` out of each file first because the two spellings rarely
agree, and takes a bare name as a same-file local, which is what Lua scoping says
it can be. Calls are read at the function's own depth: a builder that defines
twenty click handlers inside itself is not putting all twenty on a tick path.
The list comes back at 335 functions where the typed one had 200.

Two edges the text cannot carry are declared where they are, with a reason the
script requires. `-- hot:` above a definition seeds it as a root, for a function
called back through a table field. `-- cold:` stops the walk, for a function a
tick reaches that does not run every time: a builder, a layout pass, or a body
whose caller compares first. `check.sh` counts both against ceilings of 2 and 8,
and `scripts/ratchet.lua` refuses the commit that raises either.

A closure written in place at a `SetScript("OnUpdate", ...)` or as a ticker body
fails, which is what makes all of the above possible. A handler with no name is a
root the walk cannot name and a body the scan cannot find, so the tick would run
with nothing above it and nothing would say so.

To exempt one line, put `-- unguarded: <reason>` on a write or
`-- allocates: <reason>` on an allocation. The reason is required and the gate
checks that it is there. Fifteen exemptions stand today. Seven are `allocates:`
and all seven are the same shape, a memoisation guarded by an early return the
scan cannot see. Four `unguarded:` are the moving edges, the writes here that are
meant to run on every frame whatever they are about to draw. The last four are
the early-return shape again on the write side, where the line above compares the
value and returns when it already matches.

What is deliberately not guarded: `Paint.lua` re-applies `Flatten` and the
portrait crop on every tick because Blizzard's own code puts the texture and the
crop back whenever it swaps the art underneath, and ours has to be the last
word. That is three frames at 5 Hz.

What is knowingly still expensive: `ThreatState` walks every group member for
every mob you are tanking, because the number it shows is the nearest
challenger and there is no cheaper way to find it. Solo that is one threat
query per mob, down from two. In a forty man raid with fifteen plates it is
about 600 per reading, and a reading is once a second plus whatever
`UNIT_THREAT_LIST_UPDATE` asks for, where it used to be five times a second
regardless. The only way to cut it further is to show a different number.

## What the client will not let you do

These are the constraints that shaped the code. Verified against this install,
not assumed.

**3D world clicks are invisible to addons, but a modified mouse button is not
a click.** There is no way to see a click on a mob in the world, nor which
button did it. Clique ships in this install and advertises 3D-world
click-casting, and its source contains zero references to `WorldFrame`, which
settles that half.

What it does instead is the part worth copying. Its whole 3D-world feature is
the `hovercast` binding set, and `core/attributes.lua` builds it out of one
line, `self:SetBindingClick(true, key, clickableButton, suffix)`, pointed at a
`SecureActionButtonTemplate` created in `core/core.lua` carrying
`unit="mouseover"`. Clique never asks what you clicked. It asks what you are
hovering, and the game answers that for a mob in the world exactly as it does
for a nameplate.

So the binding system sees `CTRL-BUTTON1` before the world does, and by the time
the binding runs `mouseover` has already resolved. `Marking/Keys.lua` claims one
override binding per mark onto an ordinary button, and the click name it passes
through is the mark's id, so the OnClick handler is one lookup however many
marks the list grows to. Casting is protected and `SetRaidTarget` is not, so
none of Clique's secure header machinery is needed here.

The keys are settings, one per mark in `ns.db.markBinds`, so `Keys.lua` names no
key and no icon. It refuses a bare `BUTTON1` or `BUTTON2` for Clique's reason,
and refuses a key another mark already owns, because two marks on one key is the
one mistake the panel cannot show you afterwards: the second binding wins and
the first mark just stops working.

Clique also proves the key binds at all on this client: its global branch skips
`BUTTON1` and `BUTTON2` by exact string match, because an unmodified mouse
button binding would eat plain targeting, and takes every modified one.

The right button is never claimed in the world. A binding on it swallows the
camera drag, which is the trade `bars camera` and `bars clickthrough` exist to
manage on a plate.
Nameplates and unit frames are ordinary UI frames and take their own clicks
before the binding system does, so ctrl-right-click still marks a cross there,
through the OnMouseDown hook.

PLAYER_TARGET_CHANGED with ctrl held survives as a fallback for a client that
refuses the override, and only runs while the keys are not held. Holding both
at once is what made ctrl-tab mark whatever it landed on.

**A keybinding press reports itself as LeftButton.** `GetMouseButtonClicked()`
cannot separate a keybind from a left click, so the keybindings are two
separate bindings rather than one modifier-aware one.

**Never hide `plate.UnitFrame`.** That frame is what the game hit-tests for
nameplate clicks. Hiding it kills targeting and ctrl-click marking. To replace
the nameplate look, strip its visible regions instead: swap each region's
`Show` method for `Hide` so Blizzard's update code cannot put them back, then
hide it. That is `ns.Strip` in Core, and `ns.Unstrip` reverses it. Both refuse
while a protected region is in lockdown and return false, so the caller can
finish at PLAYER_REGEN_ENABLED.

**`ns.Strip` is for a texture, and only a texture.** It replaces the Lua `Show`
field, and `SetShown` is resolved in C and never reads that field. Every
FrameXML path written as `frame:SetShown(true)` walks straight past a strip, and
two shipped bugs were exactly that: `FCF_` uses it on the chat window, so
`/logout` put the client's chat back on the screen, and the cast bar mixin uses
it on the target's bar, so the target carried two cast bars with the switch on.

So a whole frame of Blizzard's goes to `Core/Attic.lua` instead. The attic is one
frame, created hidden, whose `Show` and `SetShown` are both replaced with `Hide`,
and every frame this addon replaces is re-parented into it. Visibility on this
client is a property of the parent chain, so a frame in the attic is not drawn
whatever anybody calls on the frame itself: Show, SetShown, SetAlpha, a fade, an
animation and a layout pass all lose, and none of them has to be predicted in
advance. `ns.Attic.Vanish` applies both handles, the cage and the strip, and
`ns.Attic.Return` gives the frame back to the parent it was found on.

The one call that undoes a cage is somebody else's `SetParent`, and nothing in
the client is known to make one on these frames. That claim is checked rather
than believed: `ns.Attic.Sweep` walks everything the attic holds, once a second,
off the clock in `UnitFrames/Blizzard.lua`, and puts back anything whose parent
has drifted. The same pass re-resolves every name, which is what catches a frame
the client had not built yet, including the temporary chat window a whisper
opens. So the guarantee is not "no path we thought of can show it". It is
"nothing the addon replaces stays on the screen for longer than a second".

Two things deliberately stay out of the attic. Art does: a texture or a font
string is a region of the frame it was made on, and re-parenting one moves it out
of that frame's draw order rather than off the screen, so nameplates, bar art and
the unit frame skin keep `ns.Strip`. Secure action buttons do too, for the reason
`Buttons/Blizzard.lua` gives in its own header: the client's bar controller calls
methods on them from a stack that goes on to perform protected actions, and an
addon's frame in that chain is a taint. Those are hidden with `statehidden` and
`Hide` and nothing else.

`/wk hide probe` reports one line per name: whether this client has the frame,
whether the attic holds it, and whether it is on the screen anyway. Every bug
these switches have had looked identical from the outside, a switch that was on
with the frame still drawn, and telling a name this client spells differently
from a frame the client put back used to take a guess at FrameXML.

The cast bar used to be left alone on purpose, so interrupts stayed visible, and
that was right for as long as nothing here drew one. `replace` style hides it
now, and only while `bars cast` is on: two cast bars for one cast, in two places
on the screen, is worse than either of them alone. Switch ours off and
Blizzard's is what says when to Pummel again.

**A nameplate cannot be measured.** Plate frames are restricted regions here.
`plate:GetCenter()` raises `Action[FrameMeasurement] failed because[Can't
measure restricted regions]` rather than returning nil, so there is no guarding
it with a nil check. The restriction is deliberate: reading where a plate sits
on screen would let an addon derive a unit's world position. Size, scale,
strata and level do answer, and `EnemyBars` reads plate width without
complaint, but every measurement of a frame the addon does not own now goes
through `ns.Measure`, which pcalls and returns nil, so a client that restricts
more of them degrades instead of spamming.

This cost 1883 errors in one session and earned "too many addon errors" before
it was found. A ticker that raises once a frame reaches the client's limit in
about a minute.

**The client will not say what /targetenemy is about to pick.** There is no API
for it, so the addon does not ask. It uses soft targeting instead, which is a
different and better thing: the client works out which mob your camera is aimed
at and hands it over as the `softenemy` unit token, needing no measurement.

**A secure button cannot be rewritten, shown, hidden or moved in combat.** The
Charge button is a SecureActionButtonTemplate, so every one of those calls is
protected. Three consequences, all load-bearing:

- Visibility runs on `SetAlpha`, which is not protected. Nothing calls Show or
  Hide on the button after the one Show at login.
- `ApplySecure` collects everything that is protected in one function. In
  combat it sets `securePending` and returns false, and PLAYER_REGEN_ENABLED
  runs it for real.
- The macro's target line carries `nocombat`. The unit token in there goes
  stale the moment combat starts, and without that guard a stale token would
  pull your target off the mob you are tanking.

**Protected frames in combat.** Anything touching a Blizzard region goes
through `Blocked(region)`, which checks `IsProtected() and InCombatLockdown()`.
Blocked work is queued in `pending` and flushed on PLAYER_REGEN_ENABLED. I
expect nameplate regions to be unprotected, so this path should never fire, but
it costs nothing and prevents error spam if that assumption is wrong.

**Never hide a unit frame either, and for the same reason.** `PlayerFrame`,
`TargetFrame` and `TargetFrameToT` are secure unit buttons: the click that
targets, the right-click dropdown and every ctrl-click mark that lands on one
go through the frame itself. `UnitFrames/Art.lua` hides their textures the way
the enemy bars hide a nameplate's, one region at a time through `ns.Strip`, and
never touches the frame.

Anchoring and resizing a protected region is what combat forbids, and every
region the skin moves is a child of one of those buttons. So `Style` refuses
outright while `ns.Blocked` says lockdown, rather than doing the unprotected
two-thirds and leaving a frame half skinned, and PLAYER_REGEN_ENABLED runs it
for real.

**An addon may not put a weapon in your hand during a fight.** Not with
`EquipItemByName`, not with `PickupInventoryItem`. The one path that works is an
`/equipslot` line inside a macro run off a hardware key press, which is why both
the charge button and the three stance buttons are secure buttons carrying
`macrotext` rather than Lua calling a function. `/equipslot` takes an item name,
so an item this character is not carrying builds a line that does nothing and
says nothing, and `Core/Gear.lua` exists to make that name unpickable rather
than merely unlikely.

Two things about it are still unproven here and only a key press in game can
settle them: whether the client runs two `/equipslot` lines off one press, and
what it does when a two hander comes off into a full bag. No addon in either
install calls `/equipslot`, so there is nothing to read that would answer
either. The macro itself is asserted by `scripts/harness.lua` down to the
character; what the server does with it is not.

**The 255 character macro limit is the macro editor's, not this one's.** The
charge button already carries about 430 characters of `macrotext` and works. A
three line stance macro is around 75.

**Nothing installed here writes to an action bar.** `PlaceAction`,
`PickupSpell`, `PickupMacro`, `CreateMacro` and the rest of that set are the
only APIs the addon uses that no installed addon confirms. Details references
every one of them, but only inside `luaserver.lua`, which is a language-server
stub rather than running code, so it proves nothing. `Layout.CanApply` probes
for each by name before anything is written, and the panel greys the button out
and says which one is missing. Every write is also guarded by `GetCursorInfo`,
so a pickup that came up empty can never reach `PlaceAction` and drop whatever
was on the cursor last into a slot.

`PickupAction`, `PlaceAction`, `PickupSpell`, `PickupMacro`, `ClearCursor`,
`GetCursorInfo` and `GetActionInfo` are each present as exact strings in
`WowClassic.exe` on this install, which is weaker evidence than an addon calling
one and stronger than nothing. The probes stay: a name in the binary is not a
name bound into the Lua environment, and the probes cost one comparison.

**APIs that do exist here**, each confirmed by an installed addon calling it
unguarded rather than by memory:

    UnitDetailedThreatSituation   Details_TinyThreat
    UnitLevel                     Questie, OPie
    GetQuestGreenRange            Questie, as GetQuestGreenRange("player")
    UnitReaction                  Details, and it tests reaction <= 4 the same way
    C_UnitAuras.*                 Leatrix_Plus
    UnitAura                      Questie
    C_NamePlate.*                 used by this addon's own marking module
    UnitCastingInfo               Details, for a unit that is not you
    UnitChannelInfo               Details, the same
    GetActionInfo                 OPie
    EditModeManagerFrame          Titan, GetActiveLayoutInfo only

The spell and aura accessors are shimmed anyway, C_Spell first with the legacy
global as fallback for spells, legacy first for auras. If a future client drops
one side, only the shim changes.

The two cast calls are worth the long version, because vanilla answered them
only for you and every Classic cast bar was built on a combat log estimate
instead. Details ships that estimator, LibClassicCasterino, and its framework
used to route both calls through it on Era. That branch is switched off in
`Libs/DF/externals.lua` under the comment "disable this for now, as it appears
to be working now through API changes", and what it falls back to is
`UnitCastingInfo` and `UnitChannelInfo` unguarded. An addon deleting its own
workaround is a stronger proof than an addon calling the API, because somebody
went and checked.

## Traps already hit

One line each. A bug that survived a shipped fix gets a full write-up in
`docs/POSTMORTEMS.md` instead.

- A word Core answers itself is a word no feature can have. The dispatch in
  `Core/Command.lua` returned before the registry was consulted, so the
  interface part's `ui` lost silently and every `/wk ui` opened the panel. One
  `RESERVED` table now, asserted in `BuildWords`, which runs at login.
- Saved variables have two scopes and the wrong one is not an error, it is a
  bug you find on your second character. Anything describing one character's
  bars, macros or bindings goes in `charDefaults`.
- `OnUpdate` must live on a frame that is never hidden. Hanging the ticker on
  the icon frame stops the ticker the moment the icon hides, and it never comes
  back. Both modules drive their ticker from their always-shown event frame.
- Re-anchoring a region without `ClearAllPoints()` first stacks anchor points
  rather than replacing them.
- Marking dedupes by GUID and icon for half a second. Two paths can still fire
  for one physical click, and without the dedupe the second one toggles the mark
  straight back off. The icon has to be part of the key: keyed on the GUID
  alone it also swallowed a deliberate second click, so marking a mob skull and
  changing your mind to cross inside half a second did nothing.
- Class data is not reliably available while files load. Ask `ns.Class` at
  PLAYER_LOGIN or later, never at file scope, and never cache the answer of your
  own: a cache taken while the files load would lock a warrior out of the charge
  button for the whole session. `Class.Token` caches the first answer that is
  not nil and asks again every time until it gets one, which is that rule in one
  place.
- A nil out of `ns.Class` does not mean no, it means the client has not said
  yet, and the two are indistinguishable at the call site. That costs nothing
  where the answer is only used to decide what to draw this frame, because the
  next frame asks again. It costs a character where the answer is written down.
  `Loadouts.All` is the only place in the addon that keeps one: it seeds a
  loadout per stance, records that it has, and never seeds again, and an
  unresolved class counts zero stances exactly as a mage does. So it asks for
  the token first and records nothing without one. Anything else that latches a
  decision off a class fact has to do the same.
- MONOCHROME is not a sharpness setting, it is a font choice. It gives a purpose
  built pixel font hard clean edges and it gives an unhinted humanist face like
  Arial Narrow broken ones, because at eleven to fourteen pixels the stems do not
  land on boundaries and rounding each independently makes them different
  weights. Shipped as the default under sixteen pixels for exactly one commit.
  The harness asserts the flag is absent.
- A font size is in units and a pixel count is not, and rounding in the wrong one
  undoes the conversion. `Skin.lua` had `math.floor(big * px + 0.5)` where `big`
  was already a whole count of physical pixels and `px` was what one costs in
  units, so the product was exact and the floor broke it. Invisible on the grid,
  where `px` is 1, and a fractional glyph height on a client with no
  `SetIgnoreParentScale`.
- White text is not readable because it is white. It was on every bar in the
  addon at between 1.6:1 and 2.4:1, and the symptom reported was "not sharp"
  rather than "low contrast", which sent the first fix at the rasteriser instead
  of at the palette. Ask `Color.Contrast` before believing a rendering theory.
- Our widgets call `EnableMouse(false)` so they never swallow a click meant for
  the nameplate underneath.
- A mouse enabled frame swallows every mouse button that lands on it, whatever
  `RegisterForClicks` says, including the right button drag that turns the
  camera. The charge icon sits near the middle of the screen, which is exactly
  where that drag starts, so it takes the mouse only while unlocked, the same
  as the enemy bars anchor. Neither documented way of pressing it, the bound
  key or `/click`, needs the mouse. This was invisible until the
  `RegisterForDrag` bug below was fixed, because that error aborted
  `ApplySecure` before it ever set the `type` attribute, so the button was
  mouse enabled and inert. Fixing one bug is what exposed the other.
- A frame that covers another one takes its mouse whether or not anything is
  drawn on it. `MainActionBar` is declared `enableMouse="true"` at frame level
  50 across the bottom of UIParent; the four multi-bars are declared with no
  `enableMouse` at all. Hiding Blizzard's twelve buttons does not hide the frame
  they stand on, and stripping its art does not stop it taking clicks, so a
  cloned bar standing over bar 1 at the default level 1 drew perfectly, cast off
  its keys, and swallowed every drop. Anything laid over Blizzard's furniture has
  to say what level it stands at. `Buttons/Placing.lua` uses 120 and the harness
  models the frame at 50.
- A frame level cannot win an argument with a frame strata. `MainActionBar` on
  this client is mouse enabled in TOOLTIP, the top strata there is, so a cloned
  bar at MEDIUM 122 lost every hit test on the bottom of the screen to a frame
  at level 50. Two fixes were written against the level before `/wk actionbars
  trace` printed the strata. When a frame is taking a click that is not yours,
  read both numbers, and read them off the client rather than off Blizzard's
  XML: this one is declared MEDIUM and is not running at MEDIUM.
- Where a frame cannot be hidden and cannot be out-stacked, take its mouse off.
  `Buttons/Blizzard.lua` walks up from each button it hides and calls
  `EnableMouse(false)` on any ancestor that takes the mouse, and hands every one
  of them back with the off switch. `EnableMouse` is per frame and never
  inherited, so the micro menu and the bag bar hanging off the same corner keep
  theirs. A frame with no click handler and no drag handler that swallows every
  press is furniture, not interface.
- That level was a real bug and was not the bar 1 bug. Bar 1 still took no drop
  after it, while hovering, naming what was on it and pushing under a click. A
  frame that answers `OnEnter` is the frame the client hit tested the cursor
  against, so if a square hovers, the drop is reaching it and the depth of what
  is underneath cannot be the reason it failed. Two fixes went in on a reading
  of the code before that was worked out. `/wk actionbars trace` exists so the
  third one is chosen on what the client says: it prints the frame under the
  cursor as it changes, and every gesture a square gets, with the slot and the
  cursor either side of it. A drop that never prints was never sent to us; a
  drop that prints and leaves the cursor loaded is the client refusing the slot.
- This client has no `GetMouseFocus`. The trace was written around it, printed
  every gesture on its first live run and never named a single frame, which
  reads as a cursor touching nothing rather than as a missing call. `Trace.Focus`
  asks for `GetMouseFocus` and then for the `GetMouseFoci` that replaced it, and
  says which one answered as the switch goes on. A diagnostic that can go silent
  for two different reasons is not a diagnostic.
- What is actually different about bar 1: it is the only bar the client
  re-points by stance, so its squares press the bonus bar slots 73 to 108 while
  every other bar presses 25 to 72, and it is the only bar whose `action`
  attribute is written by a secure snippet as well as from Lua. It is also the
  only bar standing on Blizzard's main menu bar. Everything else about it is the
  code the four working bars run.
- `RegisterForDrag(nil)` is an error, not a way to clear a drag registration.
  The no argument call is what clears it. Written as
  `RegisterForDrag(unlocked and "LeftButton" or nil)` it raised on every lock,
  which meant every login.
- The spell that applies an aura and the aura it applies are two spells with
  two names. The debuff row matched on the name and the picker offered 12162,
  the Deep Wounds talent, which the client happily names "Deep Wounds". What
  lands on the mob is 12721, and the client calls it "Deep Wound". One letter,
  no error in the log, and a square that stayed dark through every fight for
  the life of the setting. Track the ID of the aura, never the ID of the talent
  or the charge that grants it. Charge and Intercept have the same shape and
  were already right: the applied stuns are 7922 and 20253, and both are named
  "... Stun". A `REPLACED` table in `EnemyBars.lua` swaps a saved 12162 for
  12721 at login and inside `AddSpell`, because a saved list keeps whatever was
  in it and the panel takes a bare number.
- A list built from a setting in both directions gives back less than it took.
  `PlateRegions` decided which of Blizzard's nameplate regions to hide by
  reading the settings, and the restore walk used the same function. Hide the
  raid icon with `bars marker` on, switch the setting off, and the walk that was
  meant to give it back no longer had it on the list: the icon stayed hidden for
  the rest of the session, nothing said anything, and the only symptom was a
  mob with no marker at all on either bar. The strip list may shrink with a
  setting; the restore list may not. `PlateRegions(plate, every)` is that, and
  `ns.Unstrip` is a no-op on a region that was never taken, so asking for all of
  them costs a table lookup. Found while adding the cast bar to the same walk,
  which would have had the identical bug on its first `bars cast off`.
- A guard on the value is not a guard on the frame. The cast row wrote the
  spell's name behind a comparison against the name already on it, and showed
  the row on the same branch. A mob that casts Shadow Bolt, is interrupted, and
  casts Shadow Bolt again has not changed the string, so the second cast wrote
  nothing and the row stayed hidden: the bar you most needed was the one that
  never came. What the row is drawing and whether the row is drawn are two
  questions and they take two guards.
- Anything a ticker does at 20Hz has to be incapable of raising. Two of these
  in one session hit the client's error ceiling and got the whole addon
  offered up for disabling, which is a far worse failure than the feature
  simply not working.
- An API that answers yes when the truth is no is worse than one that refuses
  to answer, because nothing in the code looks wrong. `IsUsableAction` says
  Overpower is usable in Battle Stance whether or not anything has dodged you.
  It is not confused and it is not lying about rage: the window lives on the
  server and the client is never told, so there is no aura to scan, no cooldown
  to read and no event to catch. The cloned bars drew the one square whose whole
  point is that it is usually not pressable as ready from the first pull to the
  last, and every rung of the ladder above it was correct. The fix is
  `Buttons/Reaction.lua`, which watches the combat log because the combat log is
  the only place the fact appears. Before trusting a client answer about a
  reactive ability, work out whether the server ever sent the client the
  question.
- **One pixel rule was two.** "Every edge lands on a whole pixel" was written
  when every edge in this addon was a border, a crop or a block of art, and for
  that codebase it was the whole truth: it is enforced across 6,836 offsets and
  it has caught real bugs. The swing bar was the first edge that moves under a
  moving clock, and it was rounded to a pixel because the rule said to, which is
  what made it step. A moving edge wants the opposite thing, because the eye
  reads velocity off it rather than sharpness, and rounding also caps how often
  the edge can change position: 53 times a second at the shipped width,
  whatever the frame rate. The bar was repaired once for the ticker rate alone
  and still stepped, because the rounding was the second throttle and nobody had
  looked at it. The rule was not wrong, it was under-specified, so it is now two
  named rules with a gate each. See the pixel grid above. When a rule holds for
  every case a codebase has and then meets a new kind of case, the question to
  ask is whether it was ever one rule.

## Feature notes

**Marking.** Skull is 8, cross is 7. Ctrl-clicking a unit that already carries
the icon clears it. `SetRaidTarget` silently does nothing without raid leader
or assistant, so the addon says so once every five seconds instead.

Three marks, one key each, set in the panel or with `/wk markkey`. The shipped
keys are `F5` for skull, `F4` for cross and `F3` for moon: function keys rather
than modified clicks, because a modified click on a nameplate competes with the
camera and with click targeting, and the point of these is that they beat opening
a menu. They run downward in the order the marks matter. `Marking.MARKS` in `Marking.lua` is the list, read by `Keys.lua`
for the bindings and by `Feature.lua` for the key fields, so a fourth mark is one
entry there and one `Bindings.xml` block.

A key marks whatever is under the cursor, out in the world, on a nameplate and on
a unit frame, all through the same rule. Shift is read on the left button in the
OnMouseDown hook now too. It used to mean cross in the world and skull on a
plate, on the same mob for the same keys, because `Marking.OnClick` branched on
the button and never looked at it.

Three ways in, and they differ in one place only. The override bindings in
`Keys.lua` mark what you hover and nothing else, because a ctrl-click that lands
on terrain has no subject. The Key Bindings entries fall back to your target
when you hover nothing, on purpose, because a key pressed with the cursor
nowhere still has an obvious subject. The OnMouseDown hook on plates and unit
frames gets its unit from `mouseover` the same as the rest.

Clearing every key hands the mouse back and puts the ctrl-targeting fallback in
charge. `/wk status` names each mark and its key, and appends `unproven` when
`GetBindingAction` has not confirmed the override.

**Mouseover casting.** The addon's own Clique, in five files under `Hover/`.
Drag a spell onto the empty row at the top of the page, press the key you want it
on, and that key casts it on whatever the cursor is over.

The page is that list and nothing else. One row per binding, four columns wide:
the spell, the key, who it lands on, and the cross that takes it off. Every
column writes straight through, so changing your mind about one of the three
decisions costs one click on the row rather than a delete and a rebuild. The
empty row at the top is the same widget with a draft behind it instead of a saved
binding, which is why filling it in has no order you have to follow.

The mechanism is `Marking/Keys.lua`'s with one thing added. An override binding
claims the key, the click name it passes through is the binding's index, and the
button on the other end is a `SecureActionButtonTemplate` rather than a plain
one, because casting is protected and marking is not. A secure button looks its
action up under `<modifiers>type<click>`, so twelve bindings share one button and
the click name is the whole of what tells them apart.

The attributes are written as `*type-wk1` and `*macrotext-wk1`, and both halves
of the name shipped wrong once. The `*` is the modifier prefix. It is read off
the keyboard at the moment of the press, so a key on ALT-BUTTON3 arrives asking
for `alt-type...`, every key worth putting a mouseover spell on carries a
modifier, and `*` is the wildcard the client falls back to when the modified name
holds nothing. The dash is the click name: the client answers only the five real
mouse buttons with a bare number, and every other click name gets a dash in
front, so a click called `wk1` looks for `-wk1`. Written as `type-1` and then as
`*type1` the attributes were under a name nothing ever asks for, the override
bound, `GetBindingAction` read it back correctly, `/wk hover show` printed the
right macro, and not one key cast anything. `UnitFrames/Group.lua` writes its
click actions with the wildcard and always did.

The filter is a macro conditional and not a unit attribute, because there is no
attribute that means "only when it is an enemy". An enemy key carries
`/cast [@mouseover,harm,nodead] Rend`, a friendly key carries `help,nodead`, and
a key that lands on either carries `exists,nodead`. Two consequences follow. A
conditional decides at the moment of the press, so a binding survives a fight
without being rewritten, which matters because attributes cannot be touched once
lockdown is up. And a conditional that does not match casts nothing and says
nothing, so one key can carry a heal and another an attack with no chance of
either firing on the wrong thing.

The spell is stored by name rather than by id, which is what `/cast Thunder Clap`
needs to pick your best rank. `Buttons/Ranks.lua` exists to keep a plain spell on
an action bar up to date after a trainer visit; a binding made here never goes
stale in the first place.

Reading the cursor is the one part written from the documentation. This client
answers a dragged spell with a spellbook index and the book it came out of, and
newer builds put a spell id in a fourth slot. `Hover.Carry` tries the fourth
slot, then `GetSpellBookItemName`, then the first value as an id, and takes the
first that names a spell. A wrong reading costs nothing, because the name and the
icon are in the slot before the key is pressed.

Bindings are per character, in `ns.dbc.hoverBinds`. A binding names a spell and a
spell is something one character knows, so a druid's Rejuvenation key written
account-wide would be a key that casts nothing on the warrior next door while the
list on screen went on advertising it.

The list on screen is `Sheet.lua` and it is the only visible part of the feature.
A mouseover binding has no icon, no cooldown swipe and no keybind text anywhere,
which is why Clique users forget half of what they set up. One line per binding,
the key on the left, the spell's own icon and name beside it, red for an enemy
key, green for a friend key and grey for either. It is drawn on a change and
never on a ticker, because what is bound changes when you bind something.

A key that is also on a bar keeps the bar. The macro's second line is a
`/click` on the square the key was pressing, under the filter's negation, so a
heal on a square and the same key on this list is one key that heals the party
member under the cursor and heals you with nothing there. `Buttons/Bars.lua`
answers which square from the binding set under the override, stops binding a
key this list holds and keeps drawing it, and Blizzard's own button answers when
the clone is off. That second line is why the button carries macro text and not
`unit = "mouseover"` with a spell attribute: a secure button whose unit does not
exist drops the press before it reads anything else, so no key with a unit on it
can fall through to anything. A key on no bar gets one line, and a press with
nothing under the cursor does nothing: a key that quietly hits your target when
you meant to hover something is worse than a key that does nothing, and the list
on screen has no way to draw the difference.

**Charge.** Three abilities, one button. Charge.lua holds the state,
ChargeIcon.lua draws the HUD icon and is the button that casts, ChargeMarker.lua
puts a copy of that icon in the world over the mob you are about to hit.

None of it is built on another class. Charge, Intervene and Intercept are
warrior abilities, so on a hunter the whole part is cost with nothing on the
other side of it: a secure frame holding a key override, a ten-a-second ticker
on the icon, a twenty-a-second nameplate scan on the marker, and a client CVar
written on every combat transition. `Icon.lua` and `Marker.lua` ask
`ns.Charge.Available()` at PLAYER_LOGIN and unregister their event frames
outright rather than building something and hiding it, because a hidden marker
is still paying for the scan. That call reads `charge` off your class file, so
the question is which abilities you were given rather than which class you are.
`SoftTarget.Wanted` asks the same question, so the CVar is never written either;
that gate is on `Wanted` and not on the event frame, because `Apply` is also
called straight from the panel and the slash word and one authority is what
stops those three paths disagreeing. `/wk charge`, `/wk size` and `/wk bind` say
why instead of writing a setting nothing reads, and the Charge part opens no
page at all, so it takes no row on Start and no entry in the rail.

The saved settings are left alone. They are account-wide, a warrior alt shares
them, and a class gate is a fact about this character rather than a preference
about the addon.

    out of combat            Charge     Battle Stance      the mob you are looking at
    in combat, friendly hover Intervene Defensive Stance   that party member
    in combat, hostile hover  Intercept Berserker Stance   that mob

In combat with nothing under the cursor the icon shows Intervene greyed out,
since that is the one a tank reaches for.

Cooldown, usability and range are queried by localised spell name so the highest
known rank answers. The GCD is filtered out by ignoring durations at or under
1.5s. TBC Charge needs Battle Stance and no combat, and `IsUsableSpell` covers
the stance but not the combat rule, so combat is checked separately. Wrong
stance is its own colour rather than a blocker, because the macro swaps stance
for you and the state clears itself on the next press.

`Charge.State` returns a status, in this order: cooldown, then the wrong side of
the combat rule, then a unit the ability cannot take, then stance, then rage,
then range. Stance comes from `GetShapeshiftForm` when the client offers it and
from `IsUsableSpell` when it does not, and `IsUsableSpell` is the only thing
that knows about rage. Range only blocks on a definite 0 from `IsSpellInRange`.
A client that answers nil gets a one-time chat notice instead of every target
pinned at out-of-range.

`Charge.Look` turns that status into what you see, and there are three looks
rather than one per status, because the question the icon answers has three
honest answers:

    go    green, full colour       a press lands Charge on that mob
    swap  orange, full colour      the press spends itself on the stance swap
    no    grey, desaturated, 60%   nothing lands

Out of range and on cooldown are both `no`. The reason differs, the answer does
not, and eight shades saying one of three things is how the old icon managed to
be both colourful and unreadable. Cooldown still carries the sweep and the
seconds, so the two are told apart by the timer rather than by the hue. Both
icons read this one function, so the HUD and the world can never disagree about
what green means.

**Picking the mob.** Out of combat the mob you are aiming at wins, because
aiming by looking is the whole point of the marker. `softenemy` first, then the
target you chose on purpose even if it is a friendly one that will make the
charge fail, then the mob under the cursor, then nothing and the press falls
through to `/targetenemy` in the macro. Soft targeting resolves to your own
target while you hold one, so that order only bites when the two differ, which
is exactly when the camera is the answer you wanted. In combat the cursor is the
only thing available, because attributes cannot be rewritten under lockdown.

This used to score every attackable nameplate by how far it sat from the middle
of the screen, so turning the camera walked the marker along a row of mobs.
Plate positions are unreadable here, so that had to go, and for a while this
file claimed nothing could replace it. That was wrong. Soft targeting is the
game's own answer to the same question, computed from the real selection cone
rather than a heuristic, and it costs one unit token lookup instead of a scan.

**Is soft targeting here?** Not settled. `SoftTargetEnemy` is definitely a live
CVar on this client, `SET SoftTargetEnemy "3"` persists to a character's
`config-cache.wtf`, and the game's own options call it action targeting. But no
installed addon reads the `softenemy` token, and the wiki marks the token as
Dragonflight, which is inference from a patch note rather than a statement about
Classic. So `SoftEnemy()` probes: the first time the token answers, it is
supported. Until then the pick falls through to the cursor. Both paths are
correct, so a client without it loses camera aiming rather than breaking.

`Charge.SoftTargetState()` reports `on` once the token has answered, `off` when
the CVar is switched off, and `unproven` while neither has happened. The marker
says so in chat once, but only for `off`, because that is the only one you can
do anything about.

**Charge button.** `WarriorKitChargeButton` is the HUD icon and the caster both.
The addon rewrites its `macrotext` whenever the predicted mob changes, from the
marker's ticker so the two never disagree by a frame:

    #showtooltip
    /target [nocombat,@softenemy,harm,nodead]
    /targetenemy [noexists][dead]
    /cast [nocombat,nostance:1] Battle Stance
    /cast [nocombat] Charge
    /cast [combat,@mouseover,help,nodead,nostance:2] Defensive Stance
    /cast [combat,@mouseover,help,nodead] Intervene
    /cast [combat,@mouseover,harm,nodead,nostance:3] Berserker Stance
    /cast [combat,@mouseover,harm,nodead] Intercept
    /equipslot [nocombat] 16 Bloodspiller
    /startattack

Only the target on line two is a decision the addon made. Line three is a
backstop under it rather than an alternative to it: whether `@softenemy`
resolves inside a macro conditional is unproven here, and if it silently does
not, `/targetenemy` is what stops a press with nothing targeted from doing
nothing at all. When line two worked, the target exists and is alive, so line
three is a no-op. Everything in combat has to be a macro conditional, because
attributes cannot be rewritten once lockdown is up. `help` and `harm` are exclusive, so exactly one of those two
pairs can fire on a press.

Each pair spends a press on the stance swap when you are in the wrong one, the
same as any stance-dance macro: the swap is sent to the server and the `/cast`
below it runs before the answer arrives. A tank sitting in Defensive Stance
pays that for Charge and Intercept, never for Intervene. The icon turns orange
when a press will go on the stance rather than the ability, so it is visible
rather than surprising.

`nocombat` on the weapon swap is there so a press mid-fight cannot reset your
swing timer. The line comes from `chargeWeapon` and disappears when that is
empty. The Charge tab sets it from a picker listing your main hand and every
one hander, main hander and two hander in your bags, and nothing else: a name
typed by hand builds an `/equipslot` line that silently does nothing, and
nothing on screen used to say so. A saved name that is not in your bags is kept
rather than dropped, and the row under it says in orange that the swap will not
fire, which is what you want to read when the weapon is in the bank.
`Core/Gear.lua` owns that list and owns both slot numbers. It was
`Charge/Weapons.lua` and knew about one hand, because one part needed one
weapon; the stance keys need two, so it moved to the shared layer rather than
being reached across a folder boundary. Unlocking the icon clears the `type` attribute so dragging it cannot
cast.

Two ways to press it. `/wk bind X` takes the key with an override binding, or
put `/click WarriorKitChargeButton` in an ordinary macro and drag that to an
action bar.

**The key never touches your saved bindings.** `SetBindingClick` would, and the
next `SaveBindings` (the Key Bindings panel calls it when you click Okay) would
make the overwrite permanent. So `ChargeIcon.Bind` uses an override binding,
which layers on top of the binding set and leaves what is saved alone.

The key is held the whole time by default, because the in-combat half casts
Intervene and Intercept. `chargeKeyRelease` hands it back during combat instead,
for anyone who would rather keep their own binding there. Releasing at
PLAYER_REGEN_DISABLED is too late, lockdown is already up when the event fires,
so that option needs `WarriorKitChargeBinder`, a SecureHandlerStateTemplate
driven by `RegisterStateDriver` on `[combat]` whose snippet sets and clears the
binding from inside the restricted environment.

Nothing installed here proves `RegisterStateDriver` and that template exist on
2.5.6, so `BuildBinder` probes with a `pcall` and a failed probe drops back to a
plain `SetOverrideBindingClick` held the whole time. `ChargeIcon.CanRelease()`
reports which path came up, and the panel greys the checkbox out and says so
when the driver is missing. `BIND_SNIPPET` is shared by the state handler and by
the out-of-combat `Execute` path so the two cannot drift.

`ChargeIcon.Bind` drops the override before reading `GetBindingAction`, so the
displaced binding it reports is the real one rather than our own click binding.
It is kept in `chargeKeyDisplaced` so the panel can keep showing it.

**Charge marker.** The same icon, parented to the predicted mob's nameplate, out
of combat only. In combat the button switches to Intervene and Intercept, both
aimed with the cursor, so a world icon has nothing to add and the HUD icon
carries that state instead. It cancels the plate's scale so the size in the settings is the
size on screen, ignores the plate's alpha so distance fading cannot dim it, and
sits above the enemy bar when there is one on that plate. It draws the three
looks above: full colour with a green edge when Charge would land right now,
grey when it would not, orange while the press would go on the stance swap.

Nameplates are the only frames an addon can put in the world, so the marker
needs enemy nameplates on. With them off it says so once and stays hidden.

**When aiming is reported broken.** One function decides, `Charge.Pick`, and
three things read it: the world marker, the `/target` line in `Icon.lua`'s
`MacroText`, and the HUD icon. If they ever disagree, something stopped reading
`Pick`, and that single-answer rule is the design. Tell the three failures apart
before changing anything, because they have nothing in common:

    no marker anywhere         Pick returns nil, or nameplates are off
    marker on the wrong mob    Pick chooses badly
    marker right, press wrong  the macro's /target line disagrees with Pick

The first was usually not the addon. Soft targeting is a character scoped CVar,
so a character that never touched it ran the default, which is off, and with it
off `Pick` has no camera answer and falls back to target then cursor. That is
what the section below now takes care of, so if the marker is missing out of
combat, check `/wk status` first: `action targeting auto, on out of combat`
with `token unproven` means the CVar is set and the token is what is not
answering.

**Action targeting.** `Charge/SoftTarget.lua` owns the `SoftTargetEnemy` CVar
and drives it off combat: on when you are out of it, off when you are in it. On
another class it owns nothing and writes nothing, because the setting exists to
serve a button that is not built there.

That is the same line the rest of the Charge part already draws. Charge is an
out of combat ability, the world marker detaches at PLAYER_REGEN_DISABLED, and
the macro's target line carries `nocombat`. Soft targeting is what makes
`softenemy` resolve, `softenemy` is how the marker aims by camera, and once
combat is up `Charge.Pick` reads the cursor instead, so the token buys nothing
in the fight and a client re-aiming at whatever you glance at costs you
something. So the setting follows the ability.

The CVar is character scoped, so the value it had before the addon took it is
remembered per character in `softPrior`, and turning the setting off with
`/wk charge soft off` puts that value back rather than leaving the CVar wherever
the last combat transition happened to drop it. A setting that quietly edits
your client config and does not put it back is not a setting, it is a side
effect.

Both `GetCVar` and `SetCVar` calls are pcalled. Nothing in this install proves
`SetCVar` takes this name on 2.5.6, and a CVar the client marks protected
refuses while lockdown is up. A refused write sets `pending`, says so once, and
is retried at PLAYER_REGEN_ENABLED. The worst case is action targeting staying
on through a fight, which is where it was before this existed.

A transition that would write the value already there writes nothing, so
standing in a city out of combat is not a stream of CVar writes.

Every write is read back. A `SetCVar` that raises is caught by the pcall, but a
client that accepts the call and ignores the name leaves no trace at all, and
`Apply` would otherwise believe it. `Describe` reports what `GetCVar` says
rather than what this file meant to set, because a status line that echoes its
own intent cannot witness anything, and until someone opens `config-cache.wtf`
it is the only witness there is. A CVar sitting somewhere other than where the
addon put it reads as `auto, but the client is holding it on`.

While the addon owns the CVar the marker's own "action targeting is off"
warning stays quiet, because off out of combat then means a write the client
refused, which `SoftTarget` has already said, and telling you to set a CVar the
addon is driving is advice that fights itself.

`/wk status` reports the two halves separately, because they are two questions:
`action targeting auto, on out of combat` is what the CVar is doing, and
`token on | off | unproven` is whether `softenemy` resolves on this client at
all.

**Switching target.** One key, one macro, two lines: `/targetenemy` and
`/startattack [harm,nodead]`. TAB is already the first line. The second is the
whole reason this part exists, because cycling picks the next mob and leaves it
standing there untouched, so switching mid-fight otherwise costs a second press
that is easy to forget while something is hitting you.

`Targeting/Switch.lua` builds `WarriorKitSwitchButton`, a
`SecureActionButtonTemplate` with no size and no anchor, the shape
`Marking/Keys.lua` uses for its own button. Starting an attack is protected, so
the two commands have to run as a macro off a hardware key press rather than as
two Lua calls. That is also why the key is not a `Bindings.xml` entry: a binding
listed there runs ordinary Lua, and ordinary Lua may not start an attack.

The macro is a constant, which is the one way this button is simpler than the
charge button. That one rewrites its macro out of combat because it resolves a
unit token in Lua. This one resolves nothing, so the macro is written once at
load and combat can refuse only a rebind. `harm` and `nodead` are on the attack
line because the cycle can land on nothing when there is nothing in range, and a
bare `/startattack` then answers back in chat for a press that did nothing.
They do not belong on the target line. A bare `[harm,nodead]` tests the target
you already have rather than the one the cycle is about to pick, so on
`/targetenemy` it would decide whether the cycle runs at all, and the press
right after your mob dies would do nothing. Nothing filters what
`TargetNearestEnemy` picks: it takes a reverse flag and hands out no candidate
list.

The key is an override binding, the same as the charge key and the marking keys,
so putting it on TAB leaves TAB alone in the binding set and clearing it hands
TAB straight back. `Switch.Describe` reads `GetBindingAction` back rather than
reporting what it meant to set, so `/wk status` can say the client did not take
the key.

**Loadouts.** A loadout is a name, a pair of weapons, an optional stance and a
key. One press puts you in the stance and puts that pair in your hands.

Three are made for you, one per stance, because that is what this started as and
a warrior wants those three whatever else they want. Nothing in the code treats
them as special: they are rows in the same list as anything you add, they can be
renamed, unbound from their stance and deleted, and a loadout with no stance is a
weapon set with a key on it. Ten is the cap, one secure button each. The seed
runs once and is recorded in `loadoutsSeeded`, so deleting Berserker does not
bring it back at the next login.

Each button carries a macro of at most three lines:

    /cast [nostance:2] Defensive Stance
    /equipslot 16 Bloodspiller
    /equipslot 17 Aegis of the Blood God

Nothing here calls `EquipItemByName`, and nothing here needs to. Putting a weapon
in your hand during a fight is something ordinary Lua may not do, and an
`/equipslot` line run off a hardware key press is the path that is allowed to,
which is the same argument that makes `Targeting/Switch.lua` a secure button
rather than two function calls. `nostance` on the cast means a press while you
are already standing there spends itself on the weapons.

**The macro is written out of combat and never on the press.** Every decision a
press makes is a macro conditional, which is what lets a key work in a fight at
all. `Loadouts.Apply` is the only writer, its callers are a settings change and
two events, and there is no `OnClick` on any of the ten buttons.

**The order of the two equip lines is load bearing.** Going from a two hander to
a one hander and a shield, the main hand line is what frees the hand the off hand
line needs. The other way round the client clears the off hand itself and the
loadout has nothing in that slot to say. Main hand first, always.

**A loadout cannot say "take that off".** There is no `/equipslot` for an empty
hand, so a blank slot means leave whatever is there alone rather than strip it.
The panel says so under the slot rather than leaving you to work out why nothing
came off.

**A two hander drops the off hand line.** Both hands are already spoken for, so
an `/equipslot 17` under a two hander would either be refused or take the two
hander back off. The line is left out of the macro and the panel greys that slot
and says why. Only when the client can be asked: a weapon in the bank has no
equip type to read, and guessing at one would silently drop a line you set on
purpose.

**A swap mid fight resets your swing timer.** That is the price of dancing and it
is usually worth paying, so `loadoutSwapCombat` is on by default. Off, every
equip line takes a `nocombat` conditional and a key pressed in a fight changes
stance and leaves your hands alone. The charge button makes the opposite choice
for the opposite reason: its swap is a convenience on the pull, so its line
carries `nocombat` always.

**Changing a loadout in combat lands when the fight ends.** A secure button's
attributes cannot be written under lockdown, so `Loadouts.Apply` sets `pending`
and returns false, and PLAYER_REGEN_ENABLED runs it for real. This is the
`ApplySecure` shape from `Charge/Icon.lua` and the harness asserts both halves,
because a part that only did the first would lose the change silently.

**Every button is rewritten on every apply, not the one that moved.** Deleting a
row shifts every row under it onto a different secure button. A partial pass
would leave a key bound to the button the deleted row was on, quietly doing
somebody else's job, which is what the delete assertion in the harness exists to
catch.

The keys are override bindings, the same as the charge key, the marking keys and
the switch key, so your saved bindings are untouched and clearing a key hands it
straight back. Two loadouts cannot claim one key: the second claim is refused
with a reason and the first keeps the key. Or put
`/click WarriorKitLoadout1Button` in an ordinary macro and drag that to a bar.

**The page is a paperdoll.** `kit.Paperdoll` draws Blizzard's own `PlayerModel`
of your character in the addon's own box, with a gear square per hand under it
wearing Blizzard's empty-slot art and Blizzard's slot ring, which is the layout
the client's own character sheet uses. Under that is `kit.Tabs`, one button per
loadout and a `+` at the end, which is the strip Blizzard puts under its
paperdoll. A weapon set is something you look at rather than a pair of names in
a list.

`PlayerModel` is a frame type rather than a template, so it costs nothing to
exist on 2.5.6, and `SetUnit` is probed anyway. A client that will not draw a
model leaves an empty box and the slots underneath still work. `SetUnit` is
called once and again on show, never on a refresh, because it reloads the model
and a refresh is every click anywhere in the window.

**The page is a tab of the character window, not a section of the options
window.** It was the second, between the chat opacity and the minimap shape, and
a loadout is a pair of weapons on a key, so it belongs on the page with your
weapons on it. The page itself did not change when it moved: `Loadouts/Page.lua`
takes a widget kit and calls the same nine functions every other page in the
addon calls, and the character window is a host in the sense `UI.Kit` means, so
the whole of the move is which frame the rows land on. `Loadouts/Feature.lua`
carries no `panel` any more, which means turning the character sheet off leaves
loadouts to `/wk loadout`, and the switch says so.

**Why the loadout strip is not the window's tab strip.** The options window's
strip is chrome: `Core/Panel.lua` builds it once at PLAYER_LOGIN out of the
headers each feature writes, and it cannot grow. A loadout list is a setting that changes
while the window is open, so it is a control instead, pooled inside one row.
That is the whole reason no rebuild path had to be cut into the panel, and the
reason adding a loadout costs no frames after the first time.

**Where the weapons come from.** The panel does not offer a text field for them.
You drag a weapon or a shield out of your bags onto a hand and right click a hand
to clear it. A name typed by hand builds an `/equipslot` line that silently does
nothing, which is the failure `Core/Gear.lua` exists to make impossible: it
offers what you are carrying and nothing else, and a saved name that is not on
this character keeps its slot and goes orange rather than being dropped by a
panel that cannot see into your bank.

**Character sheet.** Nine files under `Character/`, replacing the client's own
window: gear with the stats beside it, skills, reputation and loadouts, on four
tabs the C key opens. The stats had a tab of their own and lost it: what a stat
answers is what the piece you just put on did, so the readout is a column down
the right of the squares that move it. It is drawn compact, which is a mode of
`Character/Readout.lua` rather than a second widget: a row is one line, and the
sentence that would have wrapped under it is in the hover with the value, so
thirty-odd numbers fit beside a portrait and the reasoning is a point away.

**Missing is the reason it exists.** Every other number on this page is a
lookup. How often you miss is not, on either of these clients, because the
client knows your hit rating and not your hit chance, and no character sheet the
game has ever shipped has drawn one. `Character/Stats.lua` computes it against a
target of your own level and against the three above it, for a special, for a
white swing and for a spell, and subtracts the hit your gear rated. Each of
those three is the hit still wanted as well, which is why no row says it twice:
a special that misses six percent of the time is a special six percent of hit
would land every time.

Four constants, and they are checked against the three published figures rather
than against themselves:

    miss = 5% + min(gap, 10) * 0.1% + max(gap - 10, 0) * 0.6%
    gap  = target defence - your weapon skill
    a white swing adds 19% while both hands hold a weapon

A character at the weapon skill their level allows misses 5.5% one level up, 6%
two up and 9% three up. Those three are not derivable from each other and the
shape above is the only one that lands on all of them. Section 52 of the harness
closes the stub's ten point shortfall, reads all three back and opens it again,
so a formula that ignored weapon skill fails one half and a formula with the
second slope wrong fails the other. Spells are a table rather than a curve, 4, 5,
6 and 17 percent, because the step from two levels up to three is eleven points
and no line through the first three goes near it; writing that as a formula
would be inventing a mechanism to explain a number that was chosen.

**Talent hit is not in it, and the row says so.** `GetCombatRatingBonus` reports
what your gear rated. There is no call at all for the flat percentage a talent
grants, so a warrior with points in the one that gives hit is a percent better
than this page says. Saying that is the difference between a computed number
that helps and one that costs somebody a set of enchants.

**A row the client will not answer is absent, not "unknown".** Two clients load
this addon and the older one has no combat ratings, no expertise and no
resilience. `Whole` and `Percent` both return nil for nil, `Row` drops a nil
value, and a group whose rows all dropped is not drawn. The two places where the
absence is itself the answer say so in a sentence: with no ratings the hit row
reads "this client does not rate hit" and nothing is subtracted from the miss
rows.

**The spell group hangs on spell power, not on whether its calls answered.** The
client answers a spell crit chance and a mana regen for a warrior in plate, both
off intellect nobody chose to have. Rows of nought are how a page teaches you to
stop reading it.

**The gear page is nineteen squares and four numbers.** The four are item level,
durability, empty slots and the miss chance, and none of them is on the client's
own sheet. There is no character model in the middle, which is the largest area
of the client's version: what you are wearing is already drawn in the two columns
either side at the size you can read the names of. The loadout tab does draw one,
and the two differ for a reason: there the model is showing you the pair of
weapons you just put in its hands, which is the whole subject of that page.

Every square carries the durability of what is in it as a line along its bottom
edge, green over 50%, amber to 20%, red under it. Three stops rather than a
gradient, because a continuous blend is a colour nobody can read a number off.
Durability is the one fact about your gear that changes while you play and the
client keeps it behind a hover.

**Clicking is the client's own two calls.** Left is `PickupInventoryItem`, which
swaps whatever is on the cursor into the slot and picks up what was there; it is
what FrameXML's own paperdoll button calls, so it is the call the client is
written to accept from a hardware click. Right is `UseInventoryItem`, which takes
the piece off or fires it where the item has a use, which is what the client does
on its own sheet. Both are refused in a fight by the client, silently, so
`Worn.Free` refuses first and the reason is printed. A slot that does nothing
when you click it is the worst version of this page.

**Skills are bars, and a weapon skill under the cap is priced.** The client's own
skill tab draws the same length bar for a capped weapon skill and a profession
started this morning. A weapon skill is told from a profession by what it caps at
and whether it can be abandoned, never by the header it sits under, because every
header on that page is a localised string and matching on one is how an addon
works in English and lists nothing in German. The two tests together are wrong
only for a character at exactly level fifteen with a profession at its first cap,
which draws one extra sentence and nothing else.

Reading the skill list expands the client's headers, once, and reading the
reputation list expands its own. There is no way to enumerate what is under a
collapsed header. That is a write to the client's state and the only thing that
reads it back is the frame this part puts in the attic.

**Reputation is here because hiding the client's window would otherwise delete
it.** Standings are drawn in three of the palette's own colours rather than the
client's eight-shade gradient: red for somebody who would attack you, grey for
somebody with no opinion, green for somebody who has one. A gradient between
orange and blue says something only if you have memorised the order. The at-war
tick and the watched-bar picker are not carried, because both are writes to a
live server state off a frame this addon owns and neither is what anybody opens a
reputation list to find out.

**One pane is painted at a time.** A font string on a hidden frame will not say
how tall it wraps to on this client, so a tab painted while another was up would
lay its prose out one line high and keep that height when you opened it.
Selecting a tab shows it and then paints it, in that order, and `Pane:Paint`
returns zero while hidden.

**`Character/Readout.lua` repaints a pool.** Stats, skills and reputation are the
same picture, a heading with rows under it, each row a name, a value, sometimes a
sentence and sometimes a bar. This client cannot destroy a frame, so a pane that
built its rows when it was handed a list would leak one per row per refresh, and
a reputation list is sixty rows. There is one frame per line the pane has ever
needed and a repaint shows the regions this line uses. It is not `UI/Stack.lua`
for one reason: a stack's cells are added once, this list is a different length
every time, and giving the stack a way to forget its cells is a method that
exists for one caller and would then have to be right for the options window too.

**Blizzard's sheet goes in the attic and C opens this one.** `CharacterFrame` is
not a live server session the way `MailFrame` is: every call this addon makes
about your gear, your skills and your standings works with the frame nowhere near
the screen, so it takes the cage rather than being parked. Its five pages go with
it because all five are its children.

The switch is `hide Blizzard's character sheet`, and it is on the Blizzard's own
frames page with the other nine rather than on this part's page. There is one
place in this addon where a frame of the client's is switched off, and a tenth
switch somewhere else would be a tenth place to look. `Character/Blizzard.lua`
registers through `BlizzHide.Also`, which is the second part to do it after the
chat window, and both had to: the chat window because hiding it without
forwarding what it draws deletes every addon's output, this one because the C key
has to open ours once the client's is gone.

`ToggleCharacter` is swapped for one that opens the matching tab, which is the
second global function swap in the addon after `ToggleQuestLog`. The original is
kept and handed back exactly, and `GiveKey` only hands back what this file took.
The two pages this window does not draw, your pet's sheet and the honour tab,
print a line naming the switch rather than opening a tab that is not there.

**The swap cost one bug and the harness caught it.** `TakeKey` built its
replacement function inside itself. The hide pass runs once a second forever, so
that is a closure a second for the collector to walk: 3.12 KB per fifty ticks
against a gate of 0.05. The function is declared once at load now and the pass
compares before it writes. This is the third time a per-pass allocation has been
caught by that gate rather than by review.

**Buttons.** Fills the action bars with a warrior loadout and can put back
exactly what was there before. Two jobs it deliberately does not do:

*Keybindings.* Nothing in `Layout.lua` calls `SetBinding` or `SaveBindings`. The
keys for bar 1 and the shift layer are already in the binding set, so the
loadout only has to write the slots those keys point at. That keeps the rule
above about never touching a saved binding intact, and it means applying the
loadout on one character cannot disturb another.

*Frame positions.* Where the bars sit is Edit Mode's job. Layout in this part
means what is in the slots, not where the bar is.

*Anyone who is not a warrior.* Every spell in `BAR1` and `BAR2` is a warrior
spell, so `Layout.CanApply` refuses outside the class and the panel greys the
button out. `Ranks` goes through `Layout.CanWrite` instead, which is the same
check without the class rule, because moving whatever spell is in a slot up to
your best rank is the same job in every class.

*Spell ranks.* `Ranks.lua` is the other half of the same argument and is
independent of the loadout: it walks all 120 action slots, not only the ones the
plan owns. A plain spell in a slot holds one rank, so training the next one
leaves the bar casting the old one until you drag the new rank out of the
spellbook. The usual fix is to wrap the ability in a macro, because `/cast
Thunder Clap` with no rank named always casts the best one. That spends a macro
slot per ability per character, and 18 is all you get. Rewriting the slot spends
nothing and leaves a real spell there, which keeps the native cooldown swipe,
the range and rage colouring and the tooltip that a `macrotext` button has to
rebuild by hand.

Only slots reading `spell` from `GetActionInfo` are touched. A macro is yours
and its text is yours. Items, companions and equipment sets are skipped for the
same reason.

The best rank comes off the spellbook rather than out of the rank line under the
icon, which is localised and whose number is not always where you would expect.
Ranks of one spell sit in ascending order inside a tab, so the last entry
wearing a name is the best one you have. `FUTURESPELL` entries are the greyed
ranks the trainer has not sold you yet and are skipped, because placing one
would put a spell on the bar you cannot cast, which is a worse bug than the
stale rank.

The stale list is cached and dropped on `LEARNED_SPELL_IN_TAB`,
`SPELLS_CHANGED` and `ACTIONBAR_SLOT_CHANGED`, because the panel asks for the
count on every refresh. `Apply` reads each slot again before writing it, since
the cached list can be a click old and a slot that moved underneath must not be
overwritten.

*The reaction window.* Overpower and Revenge are the two squares on a warrior's
bar you do not press, you are handed. Overpower opens when your target dodges
you; Revenge opens when you block, dodge or parry. The client will not say so.
`IsUsableAction` answers yes for Overpower in Battle Stance for the whole of
every fight, so the square that is pressable for five seconds an encounter was
drawn ready for all of it.

`Buttons/Reaction.lua` tracks both off `COMBAT_LOG_EVENT_UNFILTERED`, which is
the only place the fact appears, and `Slot.State` asks it one question. One file
for both because they are one idea seen from two ends: the trigger differs by
which side of the swing you are on and the clock after it is identical. Five
subevents are read. A dodge of yours off `SWING_MISSED` or `SPELL_MISSED` opens
Overpower. A block, dodge or parry of yours off the same two opens Revenge, and
so does a blocked amount on `SWING_DAMAGE` or `SPELL_DAMAGE`, because a block
that stops only part of a hit arrives as a landed hit and that is the common
case on a tank. `SPELL_CAST_SUCCESS` shuts the window you just spent, and
leaving combat shuts both.

The window is five seconds and that number is the one thing here that is not
read off the client. It is listed under what has never been measured, with the
argument, at the bottom of this file.

The rung sits above the usable split rather than below it, which is the ladder's
own rule: what cannot be fixed at all comes first, and a shut window is not
something you can do anything about while a wrong stance is. That ordering also
fixes the square that used to shout for nothing. Overpower on a bar in Defensive
Stance drew orange "swap" from the first pull to the last, which is a colour
telling you to swap into a stance where the press still would not land. Now the
orange appears only while the window is open, where swapping really does let you
press it.

Stances needed no new code. Overpower is Battle Stance only and Revenge is
Defensive Stance only, and `IsUsableAction` already refuses both in the wrong
stance with a `notEnoughPower` of false, which is exactly the pair the ladder
splits `cost` from `stance` on.

Only a plain spell is recognised, matched by asking the client its own name for
Overpower and Revenge at rank 1 and comparing that against its name for whatever
is in the slot. Both sides are the client's string, so it holds in every locale
and at every rank, and the file carries two spell IDs rather than a rank list
that goes stale at the next trainer visit. An Overpower wrapped in a macro is
not recognised and keeps the old behaviour, which is the same limit `Ranks.lua`
takes for the same reason: the client will not say what a `/cast` line resolves
to.

Warrior only, decided once at `PLAYER_LOGIN`. On another class nothing
registers, so no square is gated on a window that could not open and no combat
log line is read to find that out.

The design lives in `Layout.BAR1`, `Layout.BAR2` and `Layout.MACROS`, three
declarative tables. Changing the loadout is editing data. `BAR1` is twelve rows
of `{ role, battle, defensive, berserker }`, because warriors get bar 1 paged by
stance for free and the point of the loadout is that the same finger does the
same job in all three: slot 3 is always the builder, slot 7 always the
interrupt, slot 4 always the window that just opened.

*Which slot.* The addon does not carry a table of page numbers. It reads
`ActionButton1.action`, which already holds the answer for whichever stance you
are standing in, and derives the other two pages from the 12 slot stride. If
`GetBonusBarOffset` says bar 1 is not paging, it fills one page with the
Defensive set and says so rather than writing to slots nothing displays.

*The backup.* Per character, in `WarriorKitCharDB`, because it describes one
character's bars. Held account-wide it was a way to lose them: the first
character to apply owned the only backup, the second overwrote its bars without
taking one, and restoring on the second wrote the first one's bars into its
slots. Taken once, before the first write, covering exactly the slots the
plan touches and no others. Stored by stable identity: spell and item by ID,
macro by name, because a macro index shifts the moment a macro is created.
Everything that can refuse refuses before the snapshot is taken, so the addon
can never believe a loadout was applied that was not. The one weakness is that
saved variables only reach disk at logout, so the backup does not survive a
crash until the next `/reload`, which is why applying says so.

*Macros.* Five, prefixed `WK `, created per character. Restore deletes exactly
the ones it created, by name, and leaves anything you renamed alone. Applying
checks for free macro slots before it starts.

**Our own bars.** This is on out of the box. It reads whichever action bars you
have up, stands one of ours up for each of them on the same action slots, moves
your keys onto it with an override binding and hides Blizzard's twelve behind it;
`/wk actionbars off` hands them back without a reload. Nothing in it invents a
slot space, a key or a bar: `Buttons/Which.lua` holds the plan of the five bars
this client can have and answers which of them you want, and the shipping answer
is read off your own interface options, so the feature gives you back the
interface you already had, in the places the plan puts it. The plan is three
bars stacked along the bottom of the screen and two single columns of twelve
against the right edge.

What is negotiable at runtime is what one bar looks like and when it is up. Five
settings per bar, in `Buttons/Look.lua`, keyed by the plan's bar key, and every
one of them defaults to something that is not a setting: the plan's own columns,
the window colour every other surface in the addon is painted in, and no for both
visibility answers. A bar nobody has touched therefore has no record at all,
`ns.db.barLook` is empty on a fresh install, and `actionbars plain` is a deletion
rather than a write. That is `Which.lua`'s shape for the tick boxes and the
argument is the same one: the shipping state travels with a clone of the repo,
and a saved variable that merely restates it is one that can drift from it.

*Rows.* Six shapes and not twelve, because 1, 2, 3, 4, 6 and 12 are the numbers
that divide twelve and a last row with a gap on the end of it is a bar and a
stump. One row is the bar every client ships. Twelve is a column down the side of
the screen. The stepper in the panel counts in ones and walks between the six on
the direction of travel: up takes the next shape above the one you are standing
in, down takes the next below. Snapping to the nearest instead is a control that
does nothing on every second press, because +1 from four lands on five and five
is nearer four than six. A typed number that is not a shape is refused rather
than rounded, which is `ns.Command.Number`'s rule everywhere else in the addon.

*How big a square is.* It was a constant with an argument attached to it, 27,
because `UI.IconSizes` answers 54 and 27 on this client and those are the only
two drawn sizes where one stored icon texel lands on one screen pixel. It is a
setting now and the argument still holds, so both facts sit together rather than
one winning: the default is the sharp one, the range is 16 to 54 so it covers
both, the step is one pixel so neither can be stepped over, and
`ns.BarLook.Sharp` is what the readout uses to say "blended" at every other stop.
A bar you want out of the way at the edge of the screen is worth more small than
it is worth sharp; a bar you press all night is the other way round.

The size lands through `Arrange`, which is also the one function a row count
change runs, because `UI.Ability.Size` re-places every region on a square and
that is the whole of what a resize is. The gap between two squares and the pad
round the twelve stay at two pixels and three: they are what makes a bar look
like one thing rather than twelve, and nothing is answered by asking for them.

*The middle of the screen.* Two buttons, one per axis, and each leaves the other
axis exactly where it was. Centring both at once is a button nobody wants,
because a bar in the middle of the screen is a bar over your character.

Neither asks the screen how wide it is. An anchor with its horizontal half taken
off, held to `UIParent` at zero, is centred by the client at every resolution and
stays centred when the resolution changes, and no number this addon worked out
can say that. The other half is kept, so `BOTTOM, y = 8` becomes `BOTTOM, x = 0,
y = 8` and a bar along the bottom of the screen is still along the bottom of it.
A bar held to the side has no half left to keep, so `RIGHT` becomes `CENTER`,
which is the same sentence for a bar that was already at the middle height.

Refused in combat, and nothing is written when it is, so a refusal leaves the bar
where it was rather than saving a position it never took.

*Colour and opacity.* Eight named colours rather than three sliders, for the
reason the geometry in `Which.lua` is source code: this is an addon for one
person who wants the same interface on every install, and a colour you dialled in
lives in one WTF folder. Two of the eight are the theme's own, so a bar left alone
matches every other surface the addon paints; the other six are deliberately dark
and flat, because this is the ground under twelve pieces of Blizzard icon art and
anything with saturation in it fights the art rather than holding it. The opacity
is the one control the addon already had three of, so it is `ui.Opacity` and runs
0 to 100 in fives like the others. At nothing the hairline goes with the
background, which is `Feeds/Stream.lua`'s rule: a rectangle of hairline round
nothing is a window frame with no window in it.

*When a bar is on the screen.* Two settings, and neither can be done from Lua at
all. Everything inside a bar is a secure button, so the frame cannot be shown or
hidden while the client is in lockdown, and combat starting is exactly the moment
you want it to go. So both are a visibility state driver: the addon hands the
client a macro and the client evaluates it inside the restricted environment and
does the hiding on its own account. `[combat] hide; show` for a bar that goes
down in a fight, `[mod:shift] show; hide` for one that is up only while a key is
held. Same machinery as the page driver in `Bars.lua` and the charge key's
binder, probed the same way, and `ns.BarLook.CanDrive` reports whether this
client has it. A bar's keys go on working while it is off the screen, which is
the point of a bar you only look at sometimes.

A key beats the combat switch rather than being read alongside it, and that is a
decision rather than a shortcut. A bar you hold a key for is down unless you are
holding the key, in a fight or out of one, so there is nothing left for a combat
rule to decide. `[mod:shift] show; [combat] hide; show` would mean a bar that is
up all the time except in combat, which is the other setting wearing this one's
name.

The driver is registered on the bar's frame and always through `Unwatch` first,
because a driver registered twice on one frame is two answers to the same
question and the client keeps both. Handing a bar back drops it: left on, the
client would go on deciding when to show a bar this addon had already given up.

*The bars' own lock.* `ns.db.barsLocked` ships off. On means a bar moves only
while `/wk unlock` has every frame in the addon loose. Off means holding shift
puts a drag handle over each bar for as long as you hold it, watched through
`MODIFIER_STATE_CHANGED` rather than through a ticker asking `IsShiftKeyDown` ten
times a second. The cost is stated rather than hidden: a handle is a frame laid
over the whole bar and it takes every click that lands on it, so while shift is
down a shift-click on a square goes to the handle instead of to the square. That
is why it is a setting, and it ships off because a bar is moved where you can
see what it lands next to rather than after an unlock.

*The panel page.* One page, Bars under Action bars, with the switch for the
whole clone at its top and one tab strip and one set of controls under that,
rather than five bars times seven controls down a page, which is thirty five
rows to find one in. The strip picks a bar and every control answers for
whichever is in front, the tick that clones it included, which is the shape the
loadouts page and the people page already have. Which tab is in front is not a
saved setting, the same as `ns.People.Shown`. It was two pages in two groups for
a while, one holding a tick per bar and the other holding everything else about
a bar, and the second was the one you wanted every time you opened the first.

*And the bar it names wears a rim while the window is open.* A strip that says
"bottom left bar" names a bar you then have to find by counting, and the two on
the right of the screen are a pair of identical columns. The rim is two physical
pixels of the accent colour, which is what the selected tab is marked in, two
pixels outside the bar rather than on its own edge: drawn on the edge it covers
the hairline already there and reads as the colour setting having moved.

It goes up and down with the window, which is what the `showing` registry hook
is for. Core had no way to tell a part that the options window had opened, and
this is the first thing that needed one. It fires off the window frame's own
`OnShow` and `OnHide` rather than out of `Options.Show` and `Options.Hide`,
because Escape closes the panel through `UISpecialFrames`, which calls `Hide` on
the frame and never comes past `Core/Panel.lua`. A mark that outlived the window
would be an accent rectangle round one bar for the rest of the session with
nothing on the screen to say why.

**Options panel.** `/wk` with nothing after it opens it, Escape closes it, and
every row has a slash command behind it so nothing is only reachable by mouse.

Nine groups down the left, declared in `Core/Panel.lua` and owned by no
feature, each folding open to one line per section: On and off, Fighting,
Action bars, Frames, Windows, Feeds and meters, Chores, The screen, Under the
hood, and one more named after your class under Fighting. A feature calls
`ui.Section(title, group)` and its rows land on that line. Naming a group that
does not exist is a login error rather than a section quietly landing in a
default.

Every name is a thing on the screen or a job you came to do. The first cut had
You, Them and Readouts, and Chores holding the bag window, the mail window, the
quest log and the merchant, because sorting a bag is a chore. Nobody looking for
the bag window thinks that; they think "windows", so that is the group. The
frames are under Frames, the bars under Action bars, and the page of switches
is called what it is for.

It was one rail entry per registered part before that: eighteen module names,
three of them below the fold of a 390 pixel view with nothing on screen saying
so, and a new player asked to guess that the camera distance was under Comfort,
Blizzard's action bar art under Artwork, the Edit Mode layout under Interface
and the window's own size under Settings. Three of those four were junk drawers
with different names. A part is a folder of code; a group is what somebody was
thinking about when they opened the window, and those are not the same axis.
Eight entries come to 184 pixels, so the rail fits for the first time.

Letting a section choose its own group also lets one part's sections sit apart.
`Comfort/Feature.lua` sells your greys and pulls the camera back, and those are
under **Chores** and **The screen** without a line of code moving between files.

`order` on a part no longer decides where it sits in the rail, because the rail
is not made of parts. It decides where that part's tabs sit inside whichever
group they named, and `ns.Register` refuses anything that is not a whole number
or that another part has already taken. `artwork` and `minimap` were both on 8
and their relative position was whatever `table.sort` felt like on the day.

A page is a list of rows laid out top down rather than a running cursor. The
cursor could not survive a row that wraps. A lede is as tall as its text wraps
and its width is not known until it has been placed, and a row whose height was
fixed before its text was written gets drawn over by the row under it. So a row
that carries prose measures itself, the stack sets its width before it asks, and
the answer is what the row is set to.

**One switch per part, drawn by the panel.** A part declares
`switch = { key, label, apply, page, says }` and the panel draws the check box
at the top of the page named under `page`, or of the first page the part opens
when it names none. `says` is the one sentence the switch needs and it hangs on
the row the way any hint does. Eleven features each wrote their own for the
same idea and no two worded it the same way: `show the row`, `show the icon`,
`Show the meters`, `Show the swing bars`, `show enemy bars` and `draw the
WarriorKit chat window`. The wording stops being each author's choice, which is
most of why those six were six different shapes.

`page` exists because "the first page a part opens" put the enemy bars switch at
the top of the player frames page, which was the section the file happened to
write first. A switch is the row somebody opens the window for, and it has to be
on the page whose title they clicked to find it. `says` exists because seven
window parts drew a second check box on the same key as their switch, under
different words, for no reason but to have a row to hang a sentence on. The
harness refuses a page carrying two controls with one label and a switch on a
page other than the one its part named.

A part that turns a row on and a page that says where the row sits are the same
page. The bars, the missing-buff row and the cooldown row each had two, and a
person turning a bar off and a person moving it are the same person on the same
evening.

The rail marks any group holding a part that is on. That is the one question the
window could never answer without opening forty five tabs, and it is what
**On and off** is a whole page of: every switch in one column, each under the
lede of the page it belongs to, and no numbers at all. It was called Start here,
which said where to begin and not what was on it.

Seven parts declare no switch and the harness holds the list of them with a
reason each. Targeting's only setting is a key binding and a key nobody bound is
already off. A loadout is a row in a list. Feeds has two feeds with a collect
and a show each, and one switch would name whichever came first and lie about
the other. Artwork's boolean turns Blizzard's art on rather than the part's own
drawing, so a lit rail dot would mean the opposite of what it means everywhere
else. Comfort is six unrelated chores. Interface imports a layout once at
login. Settings is one slider.

**Prose is three capped calls and the caps are the point.** There were 134
notes holding 40,268 characters, one per control, about fifteen pages of writing
with switches embedded in it. They did three different jobs and the window drew
all three the same way, so the one sentence a control needed was buried in four
paragraphs about why the pixel grid prefers whole stops.

`ui.Lede(text)` is one line under a section title, at most 160 characters,
present tense, saying what the section changes on screen. One per section, and a
second is a login error. `ui.Hint(text)` is at most 200 characters and is drawn
in the addon's own tooltip on hover, so the column gets its vertical space back
and the sentence is one hover away. `ui.Reading(label, fn)` is a live number or
a short state in the accent colour on the right of its own row; it is not capped
by character count, but it never wraps and the harness measures that.

**A row with a hint carries a `?` in its right corner.** Costing no vertical
space was the half that worked; the half that did not was that nothing said a
hint was there, so a page full of them looked like a page with none and the only
way to find one was to sweep the cursor down the column. The mark is twelve
pixels, dim until the row is hovered, and the controls on that row slide left to
make room for it: `Paired` hands every builder a `right` frame to anchor to
rather than the row itself, and a row with no hint reserves nothing. The
sentence still opens on hovering the row rather than on hitting the mark,
because the row is what you were reading.

`text` may be a function returning the sentence, for one that is different every
time it is read. The zoom rows are why: each says which stop that screen is on
and whether the stop keeps a hairline sharp, which was a reading under every row
until the mark existed to hang it on. A live hint is capped where it is read,
since there is nothing to measure at the call site.

44 ledes, 75 hints and 81 readings come to 14,375 characters against 40,268, and
the harness fails past 16,000. What the caps pushed out is in this file, under
the part it belongs to.

**Search, in the title bar, focused when the window opens.** Every control
records its label, its section and its group into an index as it is built.
Typing filters and the result is a list of rows reading `group / section /
label`; clicking one selects the group, selects the tab and marks the row. They
are links rather than the live controls, because a control is built into one
section's stack and cannot be in two at once, and a link is the honest answer
anyway: it teaches you where the thing lives, so the second time you go straight
there.

A query is matched against the label, the section title, the group name, the
part's name and every slash word it answers to. That last one is what makes
typing `skin` find the frame controls, because `/wk skin` is what drives them
and it is the word somebody who already knows the addon reaches for.

The index pays for itself twice. The harness types all 147 labels in full and
fails if any one of them comes back with nothing, which is what stops a control
being added to a page and left out; and it is where the label rules are checked,
on the string the feature produced rather than on the source, because
`"collect " .. entry.collects` only reads correctly once the feed's name is
glued on.

**Four kit calls for the four knobs every part had reinvented.** `ui.Zoom` takes
no label and no range, because there is one range and it is 1 to 3; four files
declared `LOW_ZOOM, HIGH_ZOOM = 1, 3` at the top of themselves. `ui.Opacity`
takes no range for the same reason, 0 to 100 in fives, and the meters control is
renamed from `bar opacity` to `background` so all three match. `ui.Size` keeps
the range with the caller, because a feed is 200 to 520 wide and a minimap is
120 to 300 and those differ for real reasons, and writes `px` after the number
so four pages can all say `width`. `ui.Count` is rows and bars, and the enemy
bars' `list bars` is called `rows` like everywhere else.

Three controls were deleted with them: the zoom stepper on Buffs, Feeds and
Meters. Those three are read between fights, and the argument for a private zoom
is that a thing you read mid swing has to stay exact at a size you chose. That
covers the enemy bars and the swing timer and it does not cover a loot feed.

A picker row opens one popup shared by every picker, with a pool of rows inside
it, and asks for its list at the moment it opens rather than holding one. That
is what makes it safe to point at your bags.

It is built out of `CreateFrame` and coloured textures rather than Blizzard
widget templates. `UICheckButtonTemplate` and `OptionsSliderTemplate` are both
present in this install, but each template is one more thing that has to keep
existing, and the panel needs no more than a rectangle, an outline and a font
object. Sliders are steppers for the same reason, and because a stepper lands on
the number you meant.

Every row registers a refresh function, so one `Options.Refresh()` after any
change puts the whole panel back in step with the database whether the change
came from a click or from a slash command.

The key field swallows the keyboard while it listens, through
`SetPropagateKeyboardInput` behind a method-exists check. Without that method
the key you press also fires whatever it is currently bound to, once. Modifiers
come off `IsShiftKeyDown` and friends rather than off the key event, because a
modifier press arrives as its own key and has to be ignored. Middle mouse and
the two side buttons bind as well; left and right click cancel.

**Enemy bars.** Drawn out of flat coloured rectangles and one pixel edges, the
same two helpers the options panel uses. No gradient, no gloss, no art file:
`UI-StatusBar` is the 2007 glass texture and a bar wearing it reads like it, and
a bar built from `SetColorTexture` has no asset that can go missing either. One
box holds one gauge and the gauge is pinned to all four of its corners, so the
fill covers the whole inside however the numbers round. The spent part keeps the
hue at a fifth of the brightness so a mob at ten percent still reads as yours,
and the row above the gauge is split rather than stacked, threat text left and
debuff icons packed right. The icon row wraps upwards when it stops fitting, so
a long list on a narrow bar becomes two rows rather than icons hanging off the
left edge.

The edge around the gauge carries reaction, not threat. It used to carry threat
at full saturation on all four sides, which put a saturated red ring on nearly
every bar on the screen to say what the fill under it already said. The palette
had been arguing against that since it was written: `Color.edgeDim` is 0.60 with
a note saying an edge at full strength "shouted louder than anything inside it",
and the skinned unit frames dim theirs while these bars never did.

What pays for losing the edge is the track. The spent part of a gauge keeps
three tenths of the threat hue rather than a fifth, so a mob at ten percent
reads as yours across the bar's whole width instead of round its rim. The ring
was never what made aggro legible on a nearly empty bar; the track was, and at a
fifth it was too dim to do the job alone.

Your current target turns its name pale gold and everything else dims to 0.55
alpha, because the edge is spoken for.

**The level** sits inside the gauge, left of the name, coloured on the client's
own XP scale:

    grey     more than GetQuestGreenRange below you, and it pays nothing
    green    below you and still inside that range
    yellow   two levels either side of you
    orange   three or four above
    red      five or more above, or a level the client will not name

    42   normal        42+   elite        42r   rare        42r+  rare elite
    ??   a boss, or a level this client will not name

`replace` style strips `LevelFrame` and `ClassificationFrame` off the Blizzard
plate, so before this the bar showed no level and no elite dragon at all. The
string puts both back.

**Reaction is the frame, and it is a departure channel.** `UnitReaction` under 4
is hostile and draws iron `#3D404A`, which reads as chrome and disappears. 4 is
neutral and draws amber `#F2BF26` around the whole box, which is unmissable
across a room and is exactly what "do not cleave this one" needs to be. Anything
over 4 does not fight you at all and cannot reach a bar, since both halves of
the collector require `UnitCanAttack`, so friendly draws the quiet frame rather
than a colour no caller can reach.

**A player of the other faction needs the flag as well.** Attackable is the
client's word and it is nearly the whole rule for which plate gets a bar. The
exception is the other faction: on a PvP realm a Horde player standing in
Durotar is attackable and unflagged, and a bar on them is a bar on somebody who
has not started anything. So a player of the other faction gets a bar while
`UnitIsPVP` or `UnitIsPVPFreeForAll` says so and not otherwise, and
`UNIT_FACTION` puts the bar up the moment they flag, because a plate that
arrived unflagged has no bar for the tick to look at. A player of your own
faction is left to `UnitCanAttack`: a duel flags nobody, and the bar on your
duel partner is the point of the duel.

That is the second thing the revamp moved and the reasoning is worth keeping.
Reaction used to be a five pixel stripe closing a level chip on its far left,
which put a permanent five pixels at the outermost edge of the widget, in the
loudest position on the bar, to carry one bit. Because every bar is on something
attackable, that bit was hostile on nearly every bar on the screen. A channel
that is loud in the common case is noise. Drawing nothing for the common case
and everything for the exception costs no pixels and says more.

The frame is outside the `bars level` branch on purpose. Turning the mob level
off turns off what a kill is worth, which is a preference. It must not turn off
whether a mob will start a fight, which is not.

**The level moved inside the gauge, and the chip is what was wrong, not the
position.** The original argument for hanging it outside was that inside the
gauge it covered the left end of the fill, which is the end a mob still has at
ten percent. That is true of a chip and false of a glyph: the chip drew an
opaque plate over the fill, and a font string does not. The mob's name has sat
in that exact strip since the first bar and has never covered anything.

The second argument was that the XP scale and the threat scale are the same five
colours meaning two different things, so a green fill cannot mean "you hold it"
and "it is worth little" at once. That is an argument about two *fills*
competing. A 14 pixel numeral over a flat fill reads as a label, the way the
name beside it does.

That numeral has since cost more than it was meant to. It is the one string on
the widget the **Contrast** rule cannot serve well, because the XP scale runs to
red at the deadly end and a red token cannot be read off a capped fill. The chip
is what would fix it, and taking it away is what made it a problem.

What the chip cost was the shape of the whole widget. Reading leftward from the
box there was a raid marker, a three pixel gap, a tag about 27 pixels wide, then
the bar, while the targeted-by line above was `barsWidth + 60` and centred. Four
distinct vertical alignments inside one 79 pixel object, and a ragged staircase
for a silhouette. Nothing else in the addon does that: the options window, the
meter rows and the nag row all share one left edge. The assembly has one left
edge now, and the raid marker is the only thing outside it.

It also made the footprint handed to the nameplate driver wider than the bar,
which is the complication the head of `Plates.lua` documents, and it forced
`PlaceOnPlate` to shift the widget right by half the tag on every remeasure,
because `??` and `42r+` are not the same width. Both are gone. `LayoutWidget`
sends the driver `barsWidth` and `PlaceOnPlate` applies no horizontal offset at
all.

`GetQuestGreenRange` is what draws the grey line, and a client without it gets
green for everything below you instead. Grey is a claim that the kill is worth
zero, and that claim needs the number the shim could not get. `bars level off`
takes the string away and leaves the frame.

A one pixel edge is not `SetHeight(1)`. A nameplate carries a scale of its own,
so a one unit edge on a plate landed at about one and a half pixels and rounded
up along the bottom and down along the top, which read as a thick lopsided
border. `ns.Pixel(frame)` divides by the frame's effective scale and
`ns.EdgeSize` applies the result, and `LayoutWidget` recomputes both every time
a widget is laid out, because the plate and the list version of the same widget
do not share a scale.

There was a second three pixel bar above the health bar showing the threat
number as a gauge. Solo, and any time nothing was pulling, it sat empty and left
a dark stripe along the top of the box that read as an unfinished fill. It is
gone: threat is the fill and the track, and the number is still written on the
line above.

**One type size on the bar, and it is the outline floor.** `PLATE_TEXT` was 12
while the threat number and the targeted-by line above it were raised to 14 to
clear that floor, so the mob's name was drawn smaller than the list of who else
was on it. Worse, the name, the health number and the level were all drawn at 12
with an outline, and `UI/Text.lua` states in its own words that an outline below
14 closes up a glyph's counters until a 3 and an 8 stop being different shapes.
That is what "the bar looks coarse" actually was. Not blurry: mush. Everything
on the bar is Arial Narrow 14 now, and the cast chamber's text is 10. Two sizes
on the widget instead of four.

Neither carries an outline any more. Both sit on a fill the palette caps, so
they are flat and bare, and the only two strings on the widget that keep a rim
are the threat line and the targeted-by line, which hang in the gap above the
gauge over whatever the player is standing on. See **Text** and **Contrast**.

The health number is given the width of `"100%"` at layout and kept there. Arial
Narrow is proportional, so `"9%"` and `"100%"` are different widths, and the
name's right boundary is pinned to this string's left edge. Without a reserved
column the name re-measured and re-clipped every time the percent changed, so
the mob's name walked left and right as it died, once per bar per tick.

Text is inset five pixels from the gauge's ends rather than four. Four next to a
one pixel hairline reads as three, which is what made the name look like it was
leaning on the frame.

`PLATE_BAR_HEIGHT` is 22 rather than 21, and that is a pixel-crispness fix
rather than a size preference. `replace` is the default style and it centres the
gauge on the mob, so the offset is half the bar height. Half of 21 is half a
pixel, and a widget whose origin is half a pixel off a boundary has every edge,
every glyph and every icon inside it drawn across two rows. `PlaceOnPlate` used
to round that away and give up half a pixel of centring in exchange. An even bar
gives up nothing and there is nothing left to round.

**A plate is a hole in the camera, and the hole is not ours.** The widget calls
`EnableMouse(false)` on itself and none of its children ever take the mouse, so
what swallows a button over a bar is `plate.UnitFrame` underneath it: a mouse
enabled secure button, which is exactly how a click on a plate targets and where
ctrl-click marking gets its unit.

This section used to say 2.5.6 had no `SetMouseClickEnabled` and no way to keep
one button while handing back another. Both halves were wrong, and they were
inference rather than a probe. `SetPassThroughButtons` is here: Details calls it
unguarded in `functions/slash.lua`, which `Details_TBC.toc` loads at Interface
20506, for its own click-through options. `SetMouseClickEnabled` is here too,
called unguarded in `OPie/UI/Widgets.lua`, whose TOC lists 20506. Questie
replaces `SetPassThroughButtons` with a no-op on its world map pin under the
comment "hack to avoid in-combat error", which is what says it is protected.

So a plate can keep the mouse and hand one button back. `bars camera` is that
setting and it defaults to `right`.

    right   the default. Right button reaches the world, so the camera turns
            over a bar. Left still targets and ctrl-left still marks. The cost
            is Blizzard's right-click-to-interact and ctrl-right-click cross
            marking on a plate.
    left    camera orbit over a bar, at the price of click targeting, since the
            click that targets is a left click on the frame and a button that
            passes through never reaches the frame at all.
    both    click-through by another name. Prefer `bars clickthrough`.
    off     the plate keeps every button. What every version before this did.

`bars clickthrough on` is still there and still calls `EnableMouse(false)` on the
button, which gives the whole plate back to the world. With it on, `bars camera`
is moot and `CameraState()` says so. It ships on: the camera turning wherever the
cursor happens to be is worth more all evening than click targeting on a plate
is, and marking has the keys in `markBinds` and the target fallback either way.
It is a trade rather than a fix, which is why it stayed a setting.

`PlateMouse` tracks the mouse state and the pass-through state separately. A
plate arrives mouse enabled, so the `EnableMouse` call is never made in the
default configuration and one shared guard would have skipped the pass-through
along with it. Both halves are idempotent, both refuse under lockdown, and both
finish through the same `pending` flush on PLAYER_REGEN_ENABLED.

`EnemyBars.CameraState()` reports which path is live and never infers it:
`unproven` until a call has been made, `unavailable` on a client without the
method, `moot` when clickthrough already took the plate, and otherwise the
setting.

**The hit box is Blizzard's and cannot be resized, so it is drawn instead.** The
widget in `replace` mode is around fifty pixels tall counting the debuff row and
the threat line, and `plate.UnitFrame` is its own size underneath. When those two
rectangles do not line up, part of a bar takes the mouse and part of it does not,
with nothing on screen saying where the boundary is. That reads as the addon
being flaky.

Two things about it. `PlaceOnPlate` anchors the widget to `plate.UnitFrame`
rather than to the plate, so the bar sits on the frame that actually takes the
mouse by construction instead of by a constant that happened to line up; where
the two are coincident, which is the usual shape, it places identically. And
each widget carries a `hitbox` frame outlined in red that is shown only while the
frames are unlocked and only when there is a hit box to draw, so the boundary can
be checked by eye in two seconds rather than inferred from behaviour.

Untried avenue: `CameraOrSelectOrMoveStart` and `CameraOrSelectOrMoveStop` are
public, and a right button `OnMouseDown` on the plate could hand the drag back to
the camera by hand. It needs a script on a secure nameplate button, which taints
it. `SetPassThroughButtons` does the same job with no taint, so this stays
unattempted.

`barsMode` defaults to `auto`, which reads
`nameplateShowEnemies` and runs the attached version when nameplates are on and
the stacked panel when they are off, switching live on CVAR_UPDATE. One widget
factory serves both, only the anchor differs.

While you hold a mob your own threat is a permanent 100 percent, which is
useless, so the bar shows the nearest challenger and their name instead,
scanned across the roster. Colour follows that number: green clear, yellow past
70, orange past 90, red whenever the mob is on someone else, grey with no
threat data.

**The cast bar.** `grep UNIT_SPELLCAST` returned nothing across this addon
until this row existed, and the bars replace the nameplate, so replacing it cost
the one thing on a plate that says when to press Pummel or Shield Bash. The
spell's name sits on the left, the seconds left on the right, and a fill runs
left to right for a cast and drains right to left for a channel.

Violet, and deliberately nothing else on the bar. The gauge above it carries
threat, which is the green through red scale, and the level beside the name
carries the XP scale, which is those same five colours meaning something else. A
cast bar in any of them would read as a third opinion about the mob's health.
The one exception is a cast the client flags as uninterruptible, which is drawn
in the idle slate: there is nothing for you to do and the colour says so.

**It is the second chamber of the health bar's box, not a box under it.** One
outline goes round both, with a one pixel opaque seam between them and no gap.

It began as a separate box with its own backdrop, its own four sided violet
outline and four pixels of clearance. That is two independently framed
rectangles near each other, with nothing but proximity claiming they are about
the same mob. A seam reads as a division inside one object; a gap reads as two
objects. The chamber also has no edge of its own, because the box's outline
belongs to reaction, and turning it violet for the length of a cast would say
the mob had gone neutral.

**The chamber takes no room while nothing is casting.** The row used to be
reserved whether or not the mob ever cast, so seventeen pixels of nothing hung
under every bar on the screen, permanently. With the fifteen pixel targeted-by
line that is empty whenever you are solo, up to 32 of the widget's 79 pixels
were nothing at all, most of the time.

The goal that reserve bought was right and is kept: a row that appears must not
shove the health bar upward at the exact moment the thing you are watching
starts happening, because a bar that moves when the fight gets interesting is a
bar you have to find again. Reserving was one way to reach it and it was the
expensive way. The widget hangs by its **top** edge now, so the chamber opens
downward out of the box's bottom and every pixel above it, the health gauge
included, stays exactly where it was. The bar is 64 pixels idle and 76 casting,
against 79 always.

`Cast.Fit` therefore returns a height and not a Flow node. Flow measures once at
layout, and a chamber that comes and goes five times a fight is a state, not a
measurement, so `LayoutWidget` stores the box's idle and open heights and `Cast`
switches between them with one `SetHeight`. The health gauge carries the height
Flow gave it and is pinned to the widget's top left, so growing the box around
it moves nothing. The harness asserts exactly that: it opens the chamber and
checks the gauge's height and anchor offset are unchanged.

`Plates.SetFootprint` is handed the **casting** height unconditionally. The
widget really does grow, and a driver told the idle figure would space plates so
that a chamber opened into the bar underneath. Spacing for the taller of two
states is correct in both; spacing for the shorter is correct in neither.

**The fill is drawn on every frame and the rest is not.** One `OnUpdate` runs
`EnemyBars.Sweep`, which advances the fills and nothing else, drains the
widgets the unit events have marked, and runs the arrival ramps.
`EnemyBars.Update` sits behind a one second accumulator on the same frame and
reads every bar off the client from the top. The argument is the swing bar's
and the note at the head of `Swing/Gauges.lua` is the long version: a readout
that is late by the time between two events is one nobody can fault, and a
moving edge drawn at five hertz is a moving edge that steps.

**The per-frame pass stops.** `Cast.lua` keeps the set of open chambers,
`EnemyBars` keeps the ramps and the marked widgets, and a frame that finds all
three empty gives the `OnUpdate` back. `Cast.OnWake` is how the cast row starts
it again without knowing what a plate or a pool is; `StartFade` and the unit
event handler start it directly. Before this the sweep walked every bar every
frame and asked each chamber whether it was shown, which at fifteen plates and
sixty frames is about a thousand client calls a second to learn that nobody is
casting.

**Nothing is kept between frames.** `ns.CastingInfo` is a live question with a
live answer, so the tick asks it once per bar and `Cast.lua` draws what came
back. A model keyed by unit token would have to survive nameplate tokens being
recycled the moment a mob dies, which is a whole class of stale bar that cannot
happen if there is no model. The `UNIT_SPELLCAST_*` events are registered too,
and they are worth exactly one thing: the second between a cast starting and the
next reading, which on a one and a half second window is the whole of the reason
to look. They are not what the feature rests on. A client that never fires one
of them for a nameplate unit draws the same bar a second later, which is the
lesson the debuff row paid for.

They are registered only while the row is on, the client answers, and the bars
are on plates. Registered they wake the bars' frame on every cast every unit the
client tracks starts, and in a raid that is a great many for the eight of them
that land on a mob with a bar. In list mode the tick does the whole job: a list
widget is found by position rather than by unit, so the lookup would be a walk
of every bar for every cast in the zone.

**Two calls, one answer.** `UnitCastingInfo` counts up and `UnitChannelInfo`
counts down, and a unit is doing at most one of them. `ns.CastingInfo` asks for
a cast, falls back to a channel, and hands back one shape with a flag saying
which it was. Both open name, text, texture, start, finish, isTradeSkill, and
then differ by one slot: a cast carries a castID and a channel does not, so
`notInterruptible` is the eighth return of one and the seventh of the other.
Neither slot is trusted to hold it. What comes back is type checked, and
`ns.CastImmuneKnown` reports what has actually been seen: nil before any cast
has been read, false once one has been read without the flag, true once one has
carried it. "This client does not say" and "nothing has said yet" are different
answers and only one of them is a claim.

**The seconds are floored, not rounded.** Rounded, a row with 2.96 left says
3.0, which is the one number in the addon somebody is timing a press against
promising a tenth of a second it does not have. They are also drawn out of a
table of strings built once per tenth ever shown: at fifteen plates in a raid, a
plain format call is a hundred and fifty throwaway strings a second to draw
about thirty distinct numbers, and the churn gate in the cast section of
`scripts/harness.lua` measured 0.93 KB per two hundred frames before it and
0.00 after.

**Unlocking previews it, because a caster is not something you can arrange.**
The row is empty almost all of the time, so "unlock the frames and look", which
is how every other piece of this addon gets placed and sized, had nothing to
look at. Unlocked, every bar on screen draws its own cast instead of asking the
client: five seconds around, the first half a cast filling left to right and the
second a channel draining right to left, so one unlock answers both questions.
It goes through `Show`, the same guarded writes the real thing goes through,
rather than a second copy of the drawing that could drift from it.

It is named "cast" and "channel" rather than after a spell. A row reading
"Shadow Bolt" over a boar that is not casting is a preview lying about the thing
it is previewing.

You still need a bar to look at, which means a hostile target in list mode or a
nameplate up in plate mode. Locking again drops the preview at once, including
the case that matters: locked while the mob really is casting, the flag has to
go or the sweep rolls that cast over into another preview when it ends and the
row never goes out again.

`bars cast off` takes the row away and gives Blizzard's own plate cast bar back
in the same breath, which is what makes it a real off switch rather than a way
to stop seeing casts.

**Your own cast bar.** `UnitFrames/PlayerCast.lua`, and the last Blizzard frame
on the screen this HUD had left alone. Every unit around you was being drawn by
this addon and the one bar you time a press against was still a 2007 gold frame,
which is a mismatch you can see from across the room.

It is a bar of its own with a point you drag, not a chamber under the player
block, and that is the whole design decision in the file. The enemy row opens
downward out of the bar it belongs to, because a mob's cast is one more thing
about that mob. Yours is not. Under the player block is where your debuff row
hangs, and a chamber opening there would push that row down and pull it back up
on every cast, which is the row moving every time the fight gets interesting.
So this is furniture, placed the way the swing bars and the meters are placed.

It ships at 180 by 16 at `CENTER, 0, -250`, under the charge icon at -190. The
width used to be tied to the swing bars, on the argument that two bars of
different lengths stacked on each other read as two features that happen to be
near each other. The swing bars ship off now and sit above the character at -157
when they are on, so there is nothing under this one to match and the number is
its own.

**Four answers come out of `UnitFrames/Cast.lua` and none of them is written
twice.** That file already knew whether there is a cast worth drawing
(`Cast.Live`), how far along it is (`Cast.Fraction`), what the seconds read
(`Cast.Seconds`, off a table of about thirty strings built once ever) and what
an unlocked frame previews (`Cast.Preview`). Two of the four were private and
are public now, and two were extracted out of `Cast.Update` and `Cast.Sweep` on
the way. So the enemy row and your own bar cannot disagree about a channel
draining backwards, about a cast that has run out still being answered for by
the client, or about a rounded number promising a tenth of a second it has not
got. Neither of them decides any of it.

**What the file does own is the cast that failed.** Interrupted, moved out of,
or refused, your cast stops and the bar turns red and holds where it stopped for
seven tenths of a second rather than emptying. That is the one state a mob's
cast bar has no use for and it is not a nicety: an empty bar is exactly what a
cast that finished leaves behind, so a cast that died has to look like something
else or the bar has answered the wrong question. On a warrior it is Slam, which
is the one cast in the rotation and the one `Swing/Slam.lua` exists to time.

`UNIT_SPELLCAST_FAILED` is also what the client says when a press was refused
before anything started, so the hold does nothing where the bar was already
down. A red bar for a spell you never began is the addon inventing a cast in
order to report the failure of it.

**Events and a poll, and the poll is the belt.** Seven `UNIT_SPELLCAST_*` names
put a cast up at once and two more say why one stopped. None of them is proven
on both of these clients, so every registration goes through `pcall` and every
one is filtered to the player where `RegisterUnitEvent` exists, with the token
tested again in the handler where it does not. Behind them the client is asked
five times a second regardless. A name this client has never heard of therefore
costs a bar up to a fifth of a second late, and not a bar that never comes up.

**Blizzard's own goes down through the same five switches as everything else.**
`hide playercast` in `UnitFrames/Blizzard.lua`, which names `CastingBarFrame` and
`PlayerCastingBarFrame` because 2.5.6 and the clients this Edit Mode was
backported from call it different things. It is a plain boolean like the other
four and it does not read the setting above it, which means both off is the one
combination that leaves you with no cast bar at all. That is said in the hint
under the switch, in what `/wk cast off` prints, and in the panel's readout,
because a switch whose effect you cannot predict from its label is not a switch.

**The debuff row is a setting, not a constant.** It ships tracking Sunder Armor,
Demoralizing Shout, Thunder Clap and Rend, and `ns.db.barsSpells` is what it
actually draws: an array of spell IDs in the order they appear, up to ten of
them. The panel has a tab for it and `bars debuff add|remove` does the same job
from a macro. Which debuffs matter is a spec question, and hard-coding four of
them answered it for an arms warrior who wants Deep Wounds and a protection one
who wants the room back.

Matching is on the localised name rather than the ID, which is why rank 1 is
enough: every rank of Sunder resolves to the same string, and another warrior's
Sunder shows up desaturated rather than missing. It is also why two IDs that
resolve to one name are refused. They would be two identical squares lighting up
and going out together.

It is also why the ID has to be the aura's and not the applying spell's. A proc
and a stun bolted onto a charge are two spells each, and the one Wowhead finds
first is the talent. `SUGGESTED` carries 12721 for Deep Wounds and not 12162,
and `REPLACED` swaps the old ID out of a saved list at login and out of anything
typed into the panel. There is no way to ask either client whether an ID names a
hidden passive, so nothing warns about the general case. Naming the cases we
know is honest; guessing at the rest would put a wrong warning next to a working
square.

`EnemyBars.AddSpell` and `EnemyBars.RemoveSpell` are the only writes to that
list. Both re-resolve the names and textures and then relayout, because a caller
that forgot either half would leave a row of blank squares behind. An ID this
client cannot name is kept on the list and drawn as nothing, since an account
plays both flavours and a spell Era has never heard of should come back on the
character it was added on. The panel and `/wk status` name the ones that are in
that state rather than leaving the row silently short.

`bars icon` sizes one square, 16 to 32 pixels, and **29 is the only size in that
range that draws sharp.** That is not the answer anyone expects, and the two
reasons for it sit in different files.

The client keeps each texture at half the size of the one above it and picks the
pair nearest the size asked for, so a draw is exact only where the texels being
sampled halve down to the pixels being drawn. For an uncropped 64 texel icon
that would be 64, 32 and 16, which is what this file used to claim. But
`ns.UI.Icon` crops five texels off each edge to lose the border baked into the
art, so 54 texels are sampled, and the square draws a one pixel border with the
art inset inside it, so a 20 pixel setting draws 18 pixels of icon. 54 halves to
27, 27 plus the border is 29, and 13.5 is not a number of pixels. Nothing else
in the range lands.

The shipped 20 draws 18 pixels from 54 texels, which is 58 percent of the way
between two stored copies. That is close to the worst place in the range to
stand, because a blend weighted near half and half is neither picture. The
default has not moved, since moving it rewrites a setting nobody touched, but
the panel now names 29 and the stepper steps by one instead of two. It stepped
by two before, so the one size worth having was not reachable from the panel at
all.

`EnemyBars.IconAdvice` is where that arithmetic lives and the panel, the slash
word and the harness all read it, so changing the crop in `UI/Draw.lua` moves
the advice rather than leaving a stale number in a note.

The timer and the stack count are sized off the square rather than off the bar,
because a fourteen pixel number on a sixteen pixel icon covers the art it is
annotating.

The timer stands over the square rather than on it, in a strip as tall as its
own type plus a pixel, and the widget the row lays out is the square plus that
strip. The client's own buff row reads that way and this one now matches it:
gold while the time is counted in minutes, paper white once it is counted in
seconds, `14 m` and `56 s` with the space the client puts there. It keeps the
shadowed font over the world, which is the one exception to the three roles
above, because these numbers run from eight pixels to fourteen and an outline
at eight has closed the hole in a 6.

**Bar art.** Strips the 2007 furniture off the action bars at PLAYER_LOGIN: the
two gryphons, the riveted metal strip behind bar 1, the page arrows and the page
number. It is on the moment the addon loads, because that is the look the
loadout in `warrior-loadout.md` was designed around, and `/wk art on` puts every
piece back without a reload.

Two decisions are worth knowing before editing `ART_HOLDERS` or `ART_REGIONS`.

Textures go, frames stay. Bar 1, the micro menu and the bag bar are all anchored
to `MainMenuBarArtFrame` in both of the saved Edit Mode layouts in
`WTF/Account/FLAMINGO999/edit-mode-cache-account.txt`, so hiding that frame
would take them with it. `EachTexture` walks its regions and strips the textures
one by one, leaving the frame where the anchors expect it.

Names are a fallback, not the method. This client is a hybrid, TBC-era art under
a backported Edit Mode, so a texture global the wiki names may not be the one
2.5.6 has. Walking `GetRegions` cannot go stale, and every name in either list
is resolved through `_G`, so an absent one is a skipped entry rather than an
error. `/wk status` reports how many regions the last sweep touched, and zero is
the answer that matters: it means this client calls the art something else, not
that the art was already gone.

The experience bar is not artwork. `MainMenuExpBar` and
`StatusTrackingBarManager` are deliberately in neither list. `Progress/` draws
both of those bars now and `/wk hide xp` is what takes the client's own down, so
stripping their textures here would be two parts arguing over one frame.

**The experience and reputation rails.** `Progress/Rails.lua`, along the bottom
edge of the screen. Two bars: how far into the level you are, and under it the
faction you are watching. `Progress/Progress.lua` is every call the part makes to
the client and draws nothing, which is the same seam `Quests/Client.lua` draws
and is drawn here for the same reason: these are the calls the two clients
disagree about.

A rail with nothing to say is not there. At the level cap the frame is the
reputation rail alone, with no faction watched it is the experience rail alone,
and with both true there is no frame on the screen at all. That is the buff nag's
rule applied to a readout, and it is worth more here than a tidy rectangle,
because a bar drawn empty is a claim about a character who has run out of things
to earn. The three states that mean no experience are one answer to the drawing
layer: the cap, `IsXPUserDisabled` on a character who switched it off, and a
client that will not say.

Nothing here runs on a ticker. Experience moves when you kill something and
reputation moves when the client says it did, so the part draws on five events
and on nothing else, and no function in it is on `check.sh`'s tick paths. That is
also why the writes are unguarded: a guard buys one comparison against a write
that happens on every frame, and these happen a few times a minute.

The rested pool is drawn rather than written. The section of the rail between
where you are and where the bonus runs out is a second fill in the blue this game
has used for it since it shipped, clamped at the end of the level, because a week
away is a pool bigger than the level and drawn unclamped it hangs off the end of
the rail. It is the one number on the bar that changes what a kill is worth.

The twenty segment marks are the client's own bubbles, and they are still the
unit people count in. They come off under 160 pixels of width whatever the
setting says, which is eight design pixels a segment, because twenty of anything
narrower reads as hatching. That floor is inside the widths the rail is allowed
to be, so it is a state the slider can reach rather than a number nothing can get
under.

The watched faction comes back in two shapes and both are asked for.
`C_Reputation.GetWatchedFactionData` answers a table with its own field names on
the newer builds and `GetWatchedFactionInfo` answers five values on the older
ones, and this addon ships for a backported client where it is genuinely either.
Both are folded to the same five numbers, and they are band relative: the client
says 8400 out of a band running 6000 to 12000, and 8400 of 12000 would draw a
rail most of the way along a standing you have barely started. The eight
standings fold onto the three colours in `Color.reaction`, because a standing is
what a faction thinks of you and that is already the palette for exactly that
question.

The session clock is this addon's arithmetic and not the client's. Nothing in the
game will tell you what you are earning an hour, so the accumulator watches every
experience change since login and divides, and it runs whether or not the bars
are drawn, because a rate that started counting when you opened the settings
window is a rate about the settings window. The level up is the case worth
knowing: the number goes down rather than up, and what you earned is the rest of
the old level plus what carried into the new one, so the cost of the old level is
kept from the previous reading. Read as a plain difference it is a large negative,
and the symptom is an hourly rate saying you are going backwards.

**Frame skin.** The player frame, the target frame and target of target,
wearing the enemy bars' look: flat fills, one pixel edges, a square portrait,
and the class colour on the gauge and on the edge around it. `/wk skin off`
puts every piece back without a reload. On by default, for the same reason the
bar art strip is.

Almost nothing is rebuilt. Building three frames from scratch would mean
earning back click targeting, the dropdown and the cast bar, and it would fight
the Edit Mode layout this addon already carries, so the skin restyles
Blizzard's frames in place instead. The target's aura row is the one thing the
addon does draw itself, and the next section is why it had no choice.

Non-destructive is a mechanism here, not a claim. `Snapshot` reads a region's
anchors, size, frame level, draw layer, font, justification, texture
coordinates and status bar texture once, before the first change reaches it,
and `Revert` puts all of it back. Two details in there are bugs already paid
for: a font string answers the size of whatever text is currently in it, which
was never set and must never be set back, and `GetPoint` answers a nil
`relativeTo` for a region anchored to its own parent, which `SetPoint` reads as
`UIParent` and would fling across the screen.

The colour is held rather than repainted. Blizzard recolours a health bar on
every unit change, so `SetStatusBarColor` is swapped for a no-op and the
original kept beside it as `wkSetStatusBarColor`, which is what `ns.Strip` does
to `Show`. `Paint` calls the original. Nothing in that is a protected action.

**Incoming heals are a slice of the gauge, and they are clamped.** A pale green
slice runs from where the health fill stops to where the heals already in the
air will take that unit. `/wk skin heals off` drops it. Two decisions carry it.

It is clamped to what the unit is missing, so a 2,000 heal on a warrior who is
down 300 draws 300. An unclamped slice runs past the end of the bar and lies
about both numbers.

It is pinned to Blizzard's own fill texture rather than measured along the rail.
The fill's inner edge is exactly where the bar stops, whichever end the client
fills from and whatever the scale between us comes to, so the slice starts on
the fill rather than a pixel off it and stands as tall as the bar without this
file knowing how tall that is. Its width is ours, in whole pixels, like every
other number in `Place`. The slice is a texture on our rail, two frame levels
below the health bar, and that ordering does the clamp a second favour: the
moment a heal lands, Blizzard's fill draws straight over the slice that
predicted it.

`UnitGetIncomingHeals` is a client API on both flavours, not a combat log
estimate. Both binaries register it and both fire `UNIT_HEAL_PREDICTION`, which
is why there is no LibHealComm here and no scan of anyone else's casts. It is
still probed rather than trusted, so a client that drops it draws nothing and
says so in `/wk status`.

**The frame is fitted to the block, and the size is a setting in pixels.**
The block used to hang off the portrait's own anchor inside a frame five times
its size, and everything that reads a unit frame's rectangle read that one:
Edit Mode selected it, snapped it against the other frames and saved it, while
the thing you could see sat somewhere inside it, and the empty three quarters
went on eating clicks. So the block is anchored to the frame's own top corner
now, the one the portrait is on, and `PlayerFrame`, `TargetFrame` and
`TargetFrameToT` are each resized to the block over them. What Edit Mode drags
is what is drawn and the hit region is the block.

**The aura rows are ours, and the client's are hidden.** This is the one place
the addon walks away from a Blizzard frame instead of restyling it, and the
reason is that the row cannot be moved. Every icon in the target's is a child of
a secure unit button, so an addon may anchor one out of combat only, and the
client re-anchors the head of each row on every aura the target gains or loses.
Anything placed there is back inside the gauge one refresh into the first pull.

The skin used to answer that by moving the edge the client measures from. It
read the lift off an icon the client had already placed, fitted the target frame
to the block plus that lift, and let the client's own arithmetic drop the icons
under the block. It worked. It cost a measured number that only settled on the
first target carrying an aura, a `UNIT_AURA` handler waiting for that moment, a
frame that was not the same rectangle as the block, and a mouse region inset to
pull clicks off the strip underneath. All four are gone and all three frames are
the block exactly.

What draws instead is `UnitFrames/Auras.lua`: `C_UnitAuras` with the `UnitAura`
fallback every other aura reader here uses, our own squares out of `UI/Aura.lua`,
laid out by `ns.UI.Flow`. Debuffs under the block and buffs over it, each
wrapping away from the block so a row that fills moves nothing that was already
on the screen, and every row starting on the block's gauge end and running
outward from it. Which is to say the four rows are two reflections: yours run
right to left and the target's run left to right, across the same corridor the
two blocks are mirrored about. `lineOrder` on the `ns.UI.Flow` node is what
keeps line one against the block on the row above it, where the frame is sized
for a full list and fills from the bottom edge up.
`/wk skin auras off` leaves both frames with no row at all, which is the honest
answer rather than an oversight: each frame is its block, so handing the
client's row back would hang it in the gauge. Only `/wk skin off` gives it back,
because that is what gives the frame its size back.

`/wk skin aura` sizes the square, and its ceiling is the block's own height
rather than a constant. Above that a square is taller than the frame it hangs
off, which was 34 pixels when these rows were written and is `/wk skin height`
now, running to 72. The floor is 12, where the stack count stops being
readable.

**The player has the same two rows, and that was the second answer.** The first
build drew them on the target only, on the argument that Blizzard does not hang
your buffs off `PlayerFrame` at all: they are `BuffFrame`, a system of its own
in the top corner of the screen, and `Buffs/Nag.lua` already had something to
say about your own buffs. That was wrong once the target became the player
mirrored. The two blocks are one HUD, and what is on you belongs beside what is
on the target rather than in a corner you have to look away to read. `ROWS` in
`UnitFrames/Auras.lua` is keyed by frame for exactly this: the player is one
entry in it, the rows are the same rows, the settings are the same settings, and
nothing else in the file knows the difference.

One thing stays with the client's row and goes off the screen with it.
Cancelling one of your own buffs is a protected call, so a square drawn here
cannot offer right click to cancel; the client's row could, and it is hidden.

The temporary weapon enchant is the other half of that and it does come back.
It sits at no aura index at all, so no walk over `C_UnitAuras` finds it and
`GetWeaponEnchantInfo` is the only call in the client that knows about it. Both
hands lead your buff row, read through `Buffs/Upkeep.lua` rather than out of the
call, because that file already counts the returns instead of picking one of the
three shapes that call has had. A client answering none of them adds nothing to
the row. The square borrows the weapon's own art, which is what Blizzard's
enchant button does, and hovering it opens the item's tooltip rather than an
aura's, because the enchant is a line on the item.

`TemporaryEnchantFrame` goes down with the rest, and it was spared for one
release. While nothing here drew the enchant, the client's copy was the only
reading of the stone on your weapon and hiding it would have taken that reading
off the screen; the moment the row drew one, sparing the client's copy stopped
being a reading and became a second one, in the corner, saying the same number
under a square that already said it. An aura this addon draws gets one place on
the screen, and that rule does not have an exception for the one aura that has
no index.

Your own auras go first, and it is the one opinion in the file. The client's
order is the order the auras landed in, so on anything with a raid on it a row
capped at twelve loses your Rend behind a screen of other people's bleeds.
Sorting would allocate on a ticker; two passes over the same list do not, and
the answer is the same. What you cast is drawn in colour and everything else is
drained, which is the same three states the enemy bars' debuff row uses, because
it is the same square: `UI/Aura.lua` is one file and both rows are made of it.

`ns.UI.Flow` never runs on the ticker. Every square is placed once at layout for
the longest the row is allowed to be, and the tick shows a prefix of them and
moves none. The row's own height is set once as well, to what a full list comes
to, and nothing on a tick writes it: no row hangs off another one, so a height
that tracked the count would buy nothing. On the row above the block it would
cost that row every square it has, because those are placed against the frame's
bottom edge and that edge is the one the anchor holds still.

Hiding the client's rows is a sweep rather than a walk. Those buttons are built
on demand, so it cannot be done once when the skin goes on, and walking all
ninety-six names every tick to find that out would be silly. They are built in
order, so the only one that can have appeared since the last look is the one
after the last one hidden: one global lookup per run per tick once the run has
settled. `ns.Strip` refuses on a protected region in combat and says so by
returning false, so a button the client builds mid fight is retried and lands
the moment combat drops. Whether these buttons are protected at all on this
backport is in the untested list below.

That sweep is one handle and it is not enough on its own. A button this
backport spells some other way is one the sweep never reaches, and the sweep
stops at the first name that is not a frame, so a single renamed button leaves
the whole run above it on the screen. That is not theoretical: it is what put a
Blizzard debuff over a row already drawing the same debuff, on a client that had
moved your debuffs out of `BuffFrame` into a `DebuffFrame` of their own.

So `UnitFrames/Blizzard.lua` takes the other handle, and holds every switch of
this shape in one table. A frame goes down by name, and every button inside it
goes with its parent whatever it is called. `BuffFrame` is the awkward one: it
holds both of your rows on 2.5.6, so it may only go down when both switches are
on, and whichever switch is on alone is served by the sweep, which works a
button at a time and can tell a buff from a debuff. `DebuffFrame` is the newer
clients splitting that frame in two, and a name a client does not carry costs
one lookup against nil. The target's rows name no frame at all, because every
icon in them is a child of `TargetFrame` and hiding `TargetFrame` is hiding the
target.

The two never argue over a region: the sweep holds buttons, this holds frames,
the attic marks what it holds, so turning either off gives back only what that
one took. All four switches ship on, because an addon that draws your buffs
under your portrait and leaves the client's in the corner has not replaced
anything, it has added to it.

Both handles were rewritten once and the reason is worth reading before the next
switch is added, because the first version was correct and still failed in game.
It hid each frame once, at login, by replacing `Show`, and then remembered that
it had. Both halves were wrong: replacing `Show` does nothing about `SetShown`,
so the client put frames back by a route the hide never covered, and because the
file remembered, the first frame that got past it stayed past it for the session.
The raid manager had a hook of its own for exactly this, which is a patch for the
one frame somebody noticed rather than an answer for the call.

Neither half survives. Frames go to the attic, which no call on the frame can
undo, and the pass verifies instead of remembering: it re-resolves every name,
reads what is on the screen, and runs at login, when a switch moves, when combat
drops and once a second forever. Each entry carries a list of names and a list of
FrameXML parent keys, because a name a client spells differently is the failure
mode a single global cannot survive: the target's cast bar is looked for as
`TargetFrameSpellBar` and as `TargetFrame.spellbar`, and either one takes it
down. There is exactly one key in that list and that is a rule: a key is read
straight off a frame this addon does not own, so a guessed one hides something
nobody asked to hide, which is worse than the failure the list exists to fix.
`spellbar` is the only one written from FrameXML source. The next one goes in
after `/wk hide probe` has printed ON SCREEN against a name. The raid hook is
gone.

A run is one name the client counts from 1, and a row can stand in for more
than one of them: your buff row replaces `BuffButton` and `TempEnchant` both.
Each run carries its own mark, because the two do not fill together. A sweep
walking them as one list would stop at the first `BuffButton` the client has not
built yet, which on a character carrying six buffs is `BuffButton7`, and would
never reach an enchant at all.

Target of target is parked under the target block on the corner the portrait is
on, and the debuff row runs from the other corner, so the two cannot be chained
by an anchor: the row would land inset by the difference between the two widths.
`Perch` tells the rows that frame is there, and what is taken off it is its
height, which is the only thing about it the row cares about. The row goes on
hanging from the block's own corner with that much more drop. Nothing is ever
parked under the player block, so over there the same comparison is against nil
for the life of the session. It is on the ticker rather than at layout because
the client shows and hides that frame with the unit, and a target with nothing
targeted would otherwise leave a hole the size of it. Writing it there is
allowed in combat where re-anchoring target of target itself is not, for the one
reason that matters here: that frame is ours.

A resize is not a free change, so three things carry it. The original size is
recorded before the first fit and `/wk skin off` writes it back, without a
reload, like every other change the skin makes. `SetSize` on a secure unit
button is a protected action, so it sits behind the same lockdown guard as the
rest of `Place` and finishes at `PLAYER_REGEN_ENABLED`. And target of target is
placed by this addon once the target frame is fitted: Blizzard's anchor for it
was written against a target frame 100 units tall, so the moment that frame is
34 pixels tall instead, the anchor points at a corner that has moved. It is
parked three pixels under the target block, on the edge the two share, and it
goes back to Blizzard's anchor the moment either frame is unskinned.

**Whether target of target is on the screen is the skin's answer too.** It is
the one of the three that goes up and down on its own, and for a long time it
was the one thing about that frame the addon left with the client: the block was
built, measured, anchored and painted on a frame nobody could see. Blizzard
decides it behind the `showTargetOfTarget` console variable and three tests on
your target, inside a mixin method whose result no addon can read. A frame the
skin has taken over that far cannot have its visibility owned somewhere else, so
`Block.Reveal` asks it on the same pass that paints the block.

The test is Blizzard's own with the console variable dropped, and its four terms
are the whole of when a target's target means anything: your target exists, your
target has a target, your target is not you, and your target is alive. None of
them asks what the unit is, which is why it holds the same for a mob, an NPC and
a player of either faction. It reads the frame's own flag and writes only on a
disagreement, which is the rule the hide switch states for the frames it takes
down: verify every pass, do not remember.

Nothing in it fights the client. Blizzard's driver compares that frame's shown
flag against `UnitExists` on the same unit and acts only when those two
disagree, so a frame this puts up is one it leaves alone, and a frame it takes
down on its own is one this agrees with. Showing a secure unit button is
protected, so a change combat refuses waits for `PLAYER_REGEN_ENABLED` like
every other write here; the client's own show and hide are secure and go on
working through a pull, which is what covers a frame that first has to go up
mid fight. Nothing puts the flag back at `/wk skin off`, and that is deliberate:
the client's driver reads the frame's own flag, so its first pass after the skin
comes off finds whatever state it was left in and corrects it.

**The three frames are one chain, and Edit Mode is left one job.** The player
block is wherever Edit Mode put it. The target block hangs off the player block
and target of target hangs off the target block, so what you place is one HUD
rather than three frames free to drift apart. `/wk skin link off` puts the
target frame back on its own point without a reload.

That division is the only one available rather than a compromise. Edit Mode
stores an absolute point per system and writes it back, and has no notion of
one system anchored to another, so anything relational is this addon's by
definition and the only real question is how much absolute positioning stays
with Edit Mode. One anchor is the right amount. Dragging, snapping, switching
layouts and storing them per character all go on working, and none of it is
written here.

The mirroring already in the blocks is what makes the pair symmetric. The
player's gauge ends on its right edge and the target's on its left, because
`spec.mirror` is false on one and true on the other, so anchoring the two gauge
ends together faces the gauges across the gap and turns both portraits outward.
`Link` reads that off the mirror flag rather than naming a corner, so a frame
that stopped being mirrored would take its side of the link with it.

The distance across is not a setting. `Mirrored` reflects the player's facing
edge in the middle of the screen, which puts the target's facing edge 2 *
(centre - edge) away from it, and both terms are read in screen units because
that is the only space two frames on different scales share. The first version
of this anchored the two blocks a fixed 120 pixels apart, which put the line
they mirrored about wherever Edit Mode had last left the player. In game that
is left of centre and low, and two frames facing each other off to one side is
not a mirror. The specification was wrong, not the code under it.

So the corridor is twice the player's distance from the centre, and you widen
it by dragging the player outward. Drag the player across the centre and the
pair crosses, which is what a mirror does and is worth knowing before it
surprises you.

`/wk skin level 0` is the one number left: how far the target's top edge drops
below the player's, in screen pixels on the same ruler as `/wk skin height`,
snapped. Where the pair lands on the screen is still a fraction of a pixel
nobody can read, because the player frame's origin is Blizzard's. That is the
boundary the pixel grid already draws round the block, unchanged.

Four things carry it, and the first is that a drag still means something. A
linked frame that swallows your drag is a bug report, so nothing here refuses
one. What is hooked is the drop: `Landed` measures the two top edges in screen
units, divides by what one screen pixel costs there, snaps, clamps to the range
the slash command takes, stores the level and writes the anchor again. The
sideways half of your drop is thrown away and the re-anchor puts the frame back
on the mirror line, because opposite the player is the only place it can go.

Second, the anchor is written again on every relayout rather than only when the
switch moves, because three things change the numbers without changing the
state. The player moving, the level setting, and a resolution change that moves
what one pixel costs in the frame's own units. Edit Mode writes its own saved
point back over ours when a layout is applied, so the events that say it did
are what re-apply the link. That last part is now true of target of target as
well, and it was a bug: its three pixels were converted once and left, so a
monitor swapped mid session left it on the old grid's offset until something
else happened to move it.

Third, off restores. The frame's own points are recorded before the first link,
in the same `frameShot` the fit records its size in, and `Replant` hands them
back. Three callers share that one function now, target of target coming off
its perch, the target coming off the player block, and the whole skin coming
off, because a restore that differed between the three would be a frame that
lands somewhere new depending on which switch you flipped.

Fourth, the link needs both frames skinned. Unskinned, `TargetFrame` is 232 by
100 and an edge measured off it is the edge of a rectangle three quarters of
which is empty, so the link waits and `/wk status` names the half that is
missing rather than drawing something wrong. `Mirrored` can also come back with
nothing, on a pass where the client has not resolved the player block's
position yet. There is nothing to fall back to and that is deliberate. The
target stays on the point it already has and the next pass asks again, rather
than jumping to an invented distance and then jumping a second time.

Target of target keeps `TOT_GAP` and gets no number of its own, which is a
decision rather than an omission. It is stacked under the target and reads as
one piece with it, and three pixels is the hairline that stops two adjacent
outlines reading as one thick edge. There is no other value anyone would type.

Edit Mode also draws a selection frame over the system it is dragging. Where
this client puts one, the skin pins it to the block, and it post-hooks that
frame's own `AnchorSelectionFrame` so a re-anchor when the user next opens Edit
Mode gets pinned again. Both halves are probed by name and neither exists on a
client without Edit Mode, where the fit alone is the whole of the answer. The
hook is the one piece of this part that cannot be taken off again, so it does
nothing at all while the skin is off.

Only you know how tall you want the block, so the height and the width are
`/wk skin height` and `/wk skin width`, and since the block went on the pixel
grid those two numbers are counts of screen pixels rather than of UI units. On a 1440 tall screen at UI scale 0.65 one unit used to buy 1.22
pixels, so the same setting draws a smaller square than it did and the ranges
reach further up to compensate: 18 to 72 and 90 to 360. Sizing it off Blizzard's
own portrait, which is what the first version did, gave a square as tall as the
portrait: it crowded the text and it dropped target of target onto the target's
aura row. Target of target takes a fixed fraction of both settings, because it
is a glance rather than a frame you read.

**What can go on the grid and what cannot.** The three frames this file creates
per unit frame, `slot`, `box` and `top`, are adopted: one unit inside them is
one physical pixel and every size in `Place` is a whole number. The portrait,
the two status bars and the four state icons are not, and never will be. They
are regions of a secure unit button, and rescaling one is a protected action
and a change the skin could not honestly hand back. So two numbers cross that
boundary, both of them outbound, because nothing read off the client decides a
size any more. `ns.Pixel(frame)` takes a length out: a badge that should be 18
pixels is written on Blizzard's region as 18 times that. `Fit()` takes the
whole block out: 202 by 34 pixels is written on `PlayerFrame` as 165.74 by
27.90 of its units on this monitor, which is the one number here whose
exactness is the client's business rather than ours.

The two gauges avoid the question entirely. Each bar is pinned corner to corner
onto a rail, an empty frame inside the box, rather than given a height. The
client resolves an anchor on the screen rather than in either frame's units, so
the bar's four corners are our whole pixels and nothing about the bar had to be
converted or rounded to get there.

What the grid cannot fix is where the block starts. It sits on the corner of a
frame that is not on the grid and that Edit Mode positions in its own units, so
the origin is a fraction of a pixel no addon can read, exactly as a bar on a
nameplate takes its origin from wherever the mob is standing. The geometry is
exact; the origin is Blizzard's. What the fit buys is that the rectangle you
line that origin up with in Edit Mode is now the rectangle you can see.

Numbers, on this monitor, before and after: the power bar was 9.54 units tall,
which is 11.63 pixels, and is 10; the two text baselines sat at -14.41 and
-34.63 pixels and sit at -11 and -28; the rest, combat and raid marker icons
were 22.79 pixels square and are 18; the PvP icon was 29.84 and is 24, and both
are even so that centring one on a corner does not put all four of its edges on
a half pixel.

**Sampled art gets the same two fixes a spell icon gets.** A flat colour is one
texel stretched over a rectangle. A portrait render and the four state icons
are not, so each takes `ns.UI.Crisp`: the client's own `SetSnapToPixelGrid`
off, because it pulls corners onto whole pixels and stretches the two axes by
different amounts, and the bias at zero. The portrait crop moved from `0.15`,
which cuts 9.6 texels of a 64 texel image and forces the sampler to interpolate
across the whole picture to find the edge, to `10/64`. That second number is
also exact in binary, which is what lets the tick compare what it reads back
against what it wrote. There is no getter for either half of the snapping fix,
so `Revert` puts back the client default rather than what was there.

**Text is four shared font objects, not twelve private ones.** Every string went
through `SetFont`, which gives a font string its own copy of the font, at a size
in UI units that came out as 17.06 and 8.53 physical pixels. They go through
`ns.UI.Font` now, at a whole pixel size taken off the bar height, sharing one
object per size with everything else the addon draws.

**Everything is anchored off the portrait's square**, `entry.slot`, which owns
no textures and exists only to be that square. The block cannot be anchored by
a corner of its own: the anchor read off the client names the portrait's
corner, and the portrait is on the left of the player frame and the right of
the target frame, so the same anchor has to grow the block in opposite
directions. `portraitEdge`, `gaugeEdge` and `pull` are the whole of the
mirroring, and nothing else in `Place` knows which way round it is.

**One box, one divider.** It was two outlined boxes pushed together, and two
edges meeting down the middle is what made the border read as furniture rather
than as a frame. The square and the gauge share one outline now with a single
hairline between them, which is what the enemy bars do with the mob tag for the
same reason. The edge takes the fill's colour at 60% brightness: at full
strength a hostile target ringed the whole block in saturated red and the
border shouted louder than anything inside it.

**Three frame levels, and one thing they are no longer allowed to decide.**
The box sits at the unit frame's own level, because the portrait is a region of
that frame and a box one level up would cover it. The two status bars sit two
levels up. Every piece of text sits three levels up, on `entry.top`, because
font strings underneath a status bar is exactly what the first version shipped:
the player's name and level were drawn and then painted over by the health bar.

What no longer rides on those levels is the gauge itself. The spent track used
to be a texture on the rail, one level under Blizzard's bar, and the target
frame came back from the client with its rails level with its bars anyway. A
tie goes to whichever frame was built later, which is ours, so a 20 percent
track at nine tenths alpha covered the fill and a target at full health drew at
28 percent of its own colour. The player frame, one line of the same code away,
was correct, and every level this addon could read back was the number it had
asked for rather than the one on the screen.

So the spent track and the heal slice are regions of Blizzard's own bar now, on
the two lowest `BACKGROUND` sublevels, with the fill on `ARTWORK` above them.
Inside one frame the draw layer decides and there is nothing for a client to
disagree with. The rails still carry the geometry and the bars are still pinned
to them corner to corner; what changed is that the two textures moved across
the boundary, so the heal slice's width is now written in the bar's units like
every other number that lands on something of Blizzard's.

**The text is ours, not Blizzard's.** Their name and level font strings are
hidden along with the status bar numbers, and this file draws its own pair.
Two problems went with them. A font string is Blizzard's and sits at Blizzard's
frame level, which is the z-order problem above, and restoring a font a region
never explicitly had is guesswork. Hiding is reversible in one call and drawing
is fully ours. Health takes 70% of the gauge and power the rest, less three
hairlines; the name and percentage sit in the health bar, the level and the
power number in the power bar. Font sizes come off the bar heights, because the
same code draws a 34 unit player frame and a 21 unit target of target.

**Blizzard's fill texture is turned flat, not replaced.** `SetStatusBarTexture`
with a new texture left the original parented to the bar and still drawing, so
the rage bar kept the soft rounded ends of `UI-StatusBar` underneath a flat
colour that was doing nothing. `SetColorTexture` on the texture the bar already
owns has nothing left over to draw, and `Revert` puts the file path back on
that same texture.

That was half of it. The rage bar still read as rounded afterwards, because
`WalkFrames` recurses into children whose object type is exactly `Frame`, which
is the test that keeps aura buttons and the cast bar out of the walk, and a
status bar is a `StatusBar`. Anything decorative parented to a bar sat in that
gap. The two bars are walked explicitly now, with each one's own fill in the
keep set so the walk does not hide the gauge itself.

`Flatten` also runs from the tick rather than once at style time, and re-fetches
the texture rather than caching it. Blizzard's code puts a texture back on these
bars the same way it puts a crop back on the portrait, so ours has to be the
last word, and a client that swapped the texture object out from under the bar
would leave a cached one pointing at nothing.

**Naming the frame that holds the art got half the job.** The first version
walked the unit frame's own regions and the regions of one named child,
`PlayerFrameTextureFrame` and `TargetFrameTextureFrame`. On the live client the
target's ring went and the player's stayed, because the player's ring lives on
something this file had not guessed. Children are discovered now: `WalkFrames`
goes two levels down and walks the regions of every child whose object type is
exactly `Frame`. An aura icon is a `Button` and the cast bar is a `StatusBar`,
so that one test leaves both alone while reaching a texture frame whatever it
is called.

The skip set is what stops that walk running away. Target of target is a child
of the target frame and has its own portrait to keep, so every entry's frame,
plate and gauge is skipped and every entry's portrait and marker is kept,
across all three rather than per frame.

**The block is the frame, so there is nothing left to clamp.** The gauge used
to be clamped to what was left of the frame's width once the portrait had taken
its square, and the square to the frame's height, because the space around the
block was not empty: the client's aura row ran along the bottom of the target
frame and target of target sat in the same strip. The row is hidden and drawn
here now, and target of target is anchored by this addon, so nothing is left to
clamp against. The two settings are the whole of the size.

Target of target is still the frame to turn off first. It is a glance rather
than something you read, it takes a fixed fraction of both settings, and ours
is opaque where Blizzard's is mostly not. Each of the three frames has its own
switch under the part's switch, `/wk skin tot off` being the one to reach for,
and turning it off puts the aura rows straight against the block.

**`/wk skin probe` prints what the client answered.** Frame size, whether the
portrait resolved, its recorded height, the health bar's recorded width, what
the frame measured before the fit, whether this client put an Edit Mode
selection on it, and the name of every region hidden. Every number the
layout is built from comes out of that one command, so a block landing in the
wrong place is one line of output rather than another round of inference.

**What goes with the art, and what comes back.** The walk hides every texture
on the frame, because all of them are positioned against art that is no longer
there and left alone they would float in empty screen. What survives is the
portrait and the four state icons in `BADGES`: the raid target icon, the combat
icon, the resting icon and the PvP icon. Each is re-anchored to a corner of the
portrait's square, centred on it so it half overhangs the block, and then left
alone. Whether you are resting, fighting or flagged is Blizzard's question and
their own code already answers it, so nothing here shows or hides one.

They are matched on the end of a region's name rather than on the whole of it.
Naming them outright would mean three names per icon across two clients and a
hybrid between them, and the suffix is the half that has never moved:
`AttackIcon$` catches the combat icon under any prefix. A pattern that matches
nothing costs one missing icon, and `/wk skin probe` prints the name of every
region hidden, so an icon called something unexpected here names itself in that
list and is one line in `BADGES` away from coming back.

Rest and combat share the square's top outer corner on purpose, because
Blizzard shows one or the other and never both. PvP takes the bottom outer
corner, at a larger scale, because that texture carries a wide transparent
margin and renders visibly smaller than the box it is given. The combat glow,
the leader icon and the master looter icon are deliberately not in the table,
and a line each is all they would take.

The cast bar, the target's buffs and debuffs and the group indicator are
separate frames rather than regions of these three, so the walk never reaches
them and they are untouched.

Power colour is keyed by the number `UnitPowerType` returns rather than by the
token beside it, because the number is the half that has never been renamed.
`PowerBarColor` would answer the same question and is a global nothing
installed here calls unguarded, so the five colours are constants in the file.

The fast pass runs at 5Hz and draws only the blocks an event marked. It used to
draw all three whatever had happened, for the reason the artwork part does not
use events either: the event names carrying health and power have been renamed
between these two clients and a missed one is a bar that lies. That was a fair
worry and it is answered rather than believed now. `UNIT_AURA`, `UNIT_HEALTH`,
`UNIT_POWER_UPDATE` and `UNIT_CONNECTION` are what `Blizzard_UnitFrame` on the
`classic_anniversary` branch registers for these same units, so a frame drawing
what the client's own frame draws listens to what the client's own frame listens
to. `PLAYER_TARGET_CHANGED` marks all three, because no per-unit event says the
creature under a token changed. The reading at 1Hz behind them is what covers
the rest, and target of target above all: that token has no event stream on this
client and Blizzard drives its own copy of the frame off a timer for it.

**Re-applying is not the same as writing.** The pass still has to be the last
word on the bar fill and the portrait crop, because Blizzard's code puts both
back whenever it swaps the art underneath. Neither is written blind. The two
bars are hooked on `SetStatusBarTexture`, which is the only call that can swap a
status bar's fill, so the flatten happens when the client asks for it and the
four readbacks per frame per pass are gone; where `hooksecurefunc` will not
install, the readback stays and the pass reads both bars as it always did. The
portrait cannot be hooked, because `SetPortraitTexture` is handed the texture and
writes it from the C side, so the crop compares its left coordinate. Across
three frames that was 300 texture writes and 150 crop writes every fifty ticks,
all of them writing the value already there. Where a client has no `GetTexture`
the write stands unguarded, which is what this did before and is the safe half
to be wrong on.

The level tag was the other one. `Refresh` built the string with a `tostring`
and a concat and then compared it, so the guard never saved the building: three
frames five times a second to say a number that changes when the unit does.
`LevelTag` interns one string per level and classification pair. Measured under
the harness at fifty ticks across all three frames, that was 18.75 KB before and
0.00 after.

`/wk status` reports how many regions the last apply hid, and zero with the
skin on is the answer that matters: it means the walk found no textures on
these frames, which says this client builds them out of something else rather
than that they were already bare.

**Party and raid frames.** `UnitFrames/Group.lua` and `UnitFrames/Member.lua`.
Blocks for the people you are grouped with, in the addon's own look, and
Blizzard's party and raid frames off the screen behind them. The Charge button
casts Intervene at whoever you are looking at and there was no fast way to look
at a party member, which is the whole reason this exists.

**These are our frames, not Blizzard's wearing our skin, and everything else
follows from that.** `UnitFrames/Skin.lua` skins the player, target and target of
target because those three carry targeting, the dropdown and a cast bar, and a
frame drawn from scratch would have to earn all of that back. That argument does
not carry over. `PartyMemberFrame1` is bound to `party1` in XML and there is no
supported way to point it at anyone else, so the moment the order is decided by
role rather than by party index the client's frames cannot draw it. The raid is
worse: `CompactRaidFrameContainer` runs its own layout pass and puts back
whatever an addon moves.

`SecureGroupHeaderTemplate` is the answer the client already ships and both
flavours carry it. It makes one secure unit button per member, shows and hides
them itself as the roster changes, and takes every decision about the shape of
the list as an attribute written out of combat.

**Three things follow from the header being secure and they are most of the
file.** Every attribute write is refused in lockdown and retried at
`PLAYER_REGEN_ENABLED`, which is the pattern `Charge/Icon.lua` already carries. A
button the header has just made cannot be laid out until combat drops, because
it is protected, and that costs nothing in practice: the header defers its own
update in lockdown too, so there is no new button waiting. And the size of one
button has to be written from inside the header's own restricted environment,
because the header reads it while placing the column. That is
`initialConfigFunction`, it is the only snippet in the addon, and it sets a size
and two attributes and nothing else, so it needs nothing off the restricted
whitelist that is in any doubt.

**The order is a role band and then a name, and it is recomputed out of combat
and nowhere else.** Tanks, then healers, then damage, and by name inside a band.
By name is arbitrary as an ordering and it is the only one that is stable: the
same five people produce the same five slots in every group they are ever in
together, whoever formed it and whoever zoned in first. Party index does not do
that, and sorting by class does not either, because a class can be two roles.

The out-of-combat rule is what makes fixed placing true rather than
aspirational. An inspect that resolves mid pull is recorded by `Unit/Role.lua`
and changes nothing on the screen until the fight ends. The list settles over
the first minute you are in a group and then stops moving.

The header takes it as `sortMethod = "NAMELIST"` with the names in order, which
is the one sorting the template offers that an addon can decide for itself.
`/wk party order group` swaps that for `groupBy = "GROUP"`, which is what
somebody running twenty five with assignments per group wants; a party is always
by role, because every group number in a party is 1 and grouping by it is the
order the client handed the units over.

**The list fills outward from the middle.** The frame you drag is the middle of
the block, not its top left corner. The header sizes itself to the block it has
just arranged, gaps and column spacing included, so centring it on the anchor is
the whole of the effect: a fifth person moves every slot half a block away from
the anchor rather than pushing the bottom of the list further down the screen and
leaving the top where it was. `/wk party grow up|down` still picks which end the
first slot is at.

That centring is written as a rounded offset rather than as `CENTER` anchored to
`CENTER`. Half of the block is not always a whole unit: four blocks with a three
pixel gap between them is a hundred and forty five, and a list placed on half of
that rasterises every edge inside it across two rows of pixels. Rounding gives up
half a unit of centring and keeps the grid, which is the same trade `OnDragStop`
makes on the drag itself.

It is recomputed after every layout, which is out of combat and nowhere else,
because what is being halved is the size the header gave itself while arranging
the block.

**Four sources answer what role somebody is playing, and the last is a guess.**
`Unit/Role.lua`, cached per GUID, best answer first: an override you typed, then
`UnitGroupRolesAssigned` where the client has it and says something other than
`NONE`, then `GetPartyAssignment("MAINTANK")`, then the winning talent tree
through `Unit/Spec.lua`, then the class.

Only the guess is not cached. A settled answer is settled for the session; a
class floor has to be asked again, or a warrior stays in the damage band for the
rest of the night after the client finally said Protection.

The floor is worth defending. A member with no slot until an inspect lands is a
frame that arrives late, and a frame that arrives late is a frame that moves. A
priest with no talents read yet is a healer and everyone else is damage, which is
the most common answer for every remaining class and is the band with the most
room in it.

The override is per character and by name rather than by GUID, because the point
of it is that you type it for the people you play with and it is still right next
week. A GUID would be right and unreadable. `/wk party role <name>
tank|healer|dps|none`, or the picker on the page, which walks one name round the
three bands and then off again.

**One block is the block the skin draws, at the same default numbers.** They are
the same instrument and a party frame that does not match the player frame reads
as a second addon. Class colour on the health fill, which is already under the
palette's luminance ceiling so the name on it reads at every state of the bar.
Power under it in `Color.power[powerType]`, keyed by the number `UnitPowerType`
returns rather than the token beside it. Name left, health percent right. The
role icon on the portrait side, in Blizzard's own art, because it is the art
everyone in the group already recognises.

A member with no power draws no rail rather than an empty one, which is
`ns.Unit.Power` answering a maximum of zero, and the health bar takes back both
the rail and the hairline that was between them, or that block would carry a
pixel of backdrop along its bottom edge that no other block has.

Out of range, dead, offline and a ghost all draw the same way: the fill goes to
the track colour and the name says which. Out of range is in that list on
purpose. A member you cannot reach and a member who is not there are the same
fact as far as the next thing you were going to press is concerned, and the slot
is what says who it is, which is the whole point of a fixed order.

Three of the four arrive as events. A tile registers `UNIT_HEALTH`,
`UNIT_POWER_UPDATE` and `UNIT_CONNECTION` against whatever token the header has
its button pointed at, marks itself when one lands, and the pass draws the tiles
that are marked. The registration moves with the token, because a tile still
listening for the person who used to stand in that slot is a tile marked by
somebody else's health. The fourth is out of range, and it is the whole of what
the pass still asks the client for every tile: a distance has no event and
Blizzard's own frames poll `UnitInRange` too.

**`UnitFrames/Member.lua` reads no setting at all.** What one block is drawn from
arrives as one table at layout time: the two sizes, the role, and the two
switches. One table reused rather than one per member, because a raid relayout is
forty of them. It is the same seam `UnitFrames/Cast.lua` sits on and it is what
lets `Group.lua` be about attributes and slots and nothing else.

**Ctrl-click marking had to be put back by hand.** `Marking/Marking.lua` hooks
frames by name and `PartyMemberFrame1` through `4` are on that list, so hiding
Blizzard's party frames takes marking on a party member off the screen with them.
The blocks that replace them are made by a header at whatever moment somebody
joins, so there is no name to add and no login at which to look for one.
`ns.Marking.Watch(frame)` is the one exposed function, called from
`UnitFrames/Feature.lua` as each button is built, because a behaviour file may
not name a file outside its own folder.

**The raid manager puts its own container back and a strip cannot stop it.**
`ns.Strip` replaces a frame's `Show` with its `Hide`, which survives a `Show` and
does nothing at all about a `SetShown`, because that one is resolved in C and
never reads the Lua field. `CompactRaidFrameManager` re-shows the container on
every layout pass. So `hide raid` hooks that pass as well as stripping the frame,
and `BlizzHide.Apply` now looks at what is on the screen rather than at what it
did last time: `ns.Strip` answers true for a frame it has already taken down,
which is right for every other switch there and is exactly wrong for this one.

**Meters.** Two panes in one frame: damage or healing on the left, threat on the right. No
window around either, no backdrop, no title bar and nothing to open. A row is a
spec icon, a name, a number and a class-coloured bar as long as that player's
share of the top row, and the bars are the only surface the part draws at all.

That is a deliberate difference from Details rather than a simplification of it.
Details draws a window because it is a tool you go and use: you open segments,
you click a row to break it down by spell, you compare pulls. None of that is
what a warrior wants mid-fight. What a warrior wants is two columns readable out
of the corner of one eye, and every pixel of chrome around them is a pixel of
the fight underneath.

**What a segment is.** It opens when combat starts and closes when combat drops,
and the numbers stay up after it closes until the next one opens. It opens on
the combat log as well as on `PLAYER_REGEN_DISABLED`, because in a group the
pull is often somebody else's: a meter that starts its clock when *you* are hit
reads the puller as having done their first four seconds of damage in no time.
`Fighting` is the guard on that, and it asks about the source as well as about
you. Without it a bleed ticking twice after the mob is down would open a fresh
segment and replace the fight you were still reading.

**One clock, not one per player.** Every row is divided by the segment's own
elapsed time. Details gives each player their own activity window, which
flatters whoever stopped early and is the right answer to "how hard did they hit
while they were hitting". This answers "what did they contribute to this fight",
which is the question a five second pull actually has, and it is the only
version where the rows add up to the total on the header. Rows that do not add
up are rows that get argued about.

**Effective healing only.** Overheal is subtracted. A healer who lands 40k into
a full health bar has healed nothing.

**The group filter is the whole of the parsing risk.** The combat log carries
every fight in range: the party next door, both sides of the duel by the
mailbox, every mob in the pack. `Roster.Owner` is the filter and it answers
three things at once. A pet's damage is its owner's, which is why a hunter does
not read as half a hunter. Anything a member summoned is theirs, taken from
`SPELL_SUMMON`, because a totem is not a pet and no unit token ever points at
one. And a GUID that is neither is nobody's, which is how the party next door
stays off the pane.

`Roster` also remembers name and class for every GUID that has ever been in the
group, and never forgets. The combat log carries neither, and somebody who
leaves mid-fight keeps their row until the segment ends.

**Spec icons, on clients that have no specs.** `Unit/Spec.lua`, which was
`Meter/Spec.lua` until the party frames wanted the same answer for a different
reason. There is no
`GetSpecialization` here and no spec id on a unit. A TBC character is three
talent trees with points in them, and which tree has the most is the whole of
what anyone means by a spec. Details resolves its own player that way and shows
a class icon for everyone else; this goes one step further, because the tree
icon is a better row and the client will hand it over if asked properly.

    yourself      GetTalentTabInfo, any time, free. Re-read on every point spent.
    anyone else   NotifyInspect, then GetTalentTabInfo with the inspect flag once
                  INSPECT_READY names them. Inside about 28 yards, out of combat,
                  one in flight, and never the same person twice inside a minute.
    neither       the class icon, which is always right and always available.

So a row is drawn from the first swing that lands, with whatever is known then,
and the icons sharpen from class to spec over the first minute in a group
without ever blocking anything.

Two traps in that. `GetTalentTabInfo` has two signatures across these clients,
one leading with a numeric tab id and one with the tree's name; they are told
apart on the type of the first return rather than on how far down the tail a nil
appears, which is what the Details framework does and which breaks on the older
shape's trailing boolean. And there is no event for an inspect the client
decided not to answer. The target walks out of range, or zones, or the client
simply drops it, and `INSPECT_READY` never comes. `TIMEOUT` is what stands
between one dropped request and a queue parked on that GUID for the rest of the
session.

**The threat pane does the half the client will not.** The client already
computes the hard part: `UnitDetailedThreatSituation`'s third return is threat
scaled against the amount needed to take the mob off whoever is holding it, so
100 means that player pulls, with the melee and ranged thresholds and every
talent that moves either already folded in. Nothing here recomputes any of that.

What it adds is the derivative. A percentage says where someone is; the rate of
change says where they are going, and where they are going is the reason to
watch threat at all. 82% and falling is a rogue who stopped. 82% and climbing
four points a second is a rogue who takes the mob in four and a half seconds.

The rate is smoothed because the raw one is unusable: threat arrives in lumps
the size of a Sinister Strike, and the denominator is a tank whose own total
steps up every swing, so two consecutive samples can differ by twenty points in
either direction. The reference sample moves on its own half second clock and
four tenths of each delta goes into an exponential average. Projections past a
minute are dropped: "they overtake you eventually" is not information.

On Classic Era there is no threat API at all, so the pane says so and stays
empty. Vanilla computes no threat, which is why every Classic threat meter is a
combat log simulation carrying a table of every spell's coefficient. That is a
different addon, and a made up number here would be worse than an honest blank.

**Every number in the layout follows the icon, and the icon is 27.** Not a size
anyone picked for looking right. The client stores a spell icon at 64 texels,
the crop in `UI/Draw.lua` takes the five texel border off each edge, and 54 are
left to sample. A draw is exact only where those 54 halve onto whole pixels,
which is 54 and 27 and nothing between. `ns.UI.IconSizes` is where that list
comes from and `MeterWindow.IconAdvice` reads it rather than carrying a copy.
At zoom 1 a row icon draws 27 off the half size copy and at zoom 2 it draws 54
off the full one, which is the sharpest a spell icon gets. Zoom 3 draws 81 and
is blended, and the panel says so.

The row is then the icon with a pixel above and below it, 29, so the icon
decides the height rather than the text. Six rows and a header is 196 pixels and
two panes and their gap is 408.

**How faint the bars are is a slider, and it starts at 15.** A bar is the only
surface the meter draws, and the top row's is the full width of its pane every
tick by definition, so whatever the alpha is, the player in first place is a
rectangle of class colour lying across that part of the screen for the whole
fight. It shipped at 0.32, which is a wash rather than a tint, and sat at 0.15
after that, which is right for the floor it was drawn over: a bar is read
against the bars beside it and not against the world behind it, and at 0.15 the
world comes through. What 0.15 cannot do is hold over a bright one. The tint
that ranks four players in a crypt is nothing at all in Tanaris at noon, and no
number this addon picks is right on both, so `meterBarAlpha` is whole percent,
0 to 100 in fives. At 0 there are no bars and the meter is columns of outlined
text over the world.

The part that made it more than a number is the guard. A row writes its bar and
its name only when the player on it changes class, which is what turns thirty
writes a second into none, and the alpha is not the class: left behind that
guard, a dragged slider would wait for somebody in the group to change class,
which is never. `MeterWindow.Apply` clears the guard on every row instead, and
the harness asserts the drag lands on the next tick rather than asserting the
saved variable took the number.

**And every string is 14, because every string is outlined.** They have to be:
the meter has no background, and the outline is the only thing between a number
and a pale floor behind it. That is the difference between this and a timer on a
debuff square, which sits on art and can trade the rim for a shadow.
`ns.UI.NumberFont` makes that trade at every size and is deliberately not used
here, because a shadow needs a known colour to be darker than and the world is
not one.

What that leaves is a hard minimum rather than a preference. An outline costs a
pixel on every stroke, and below `ns.UI.OutlineFloor` a 3 and an 8 stop being
different shapes. Both sizes here sit at the floor, and the harness reads the
floor out of `UI/Text.lua` rather than carrying its own copy, so one number
governs the meters and the bars together.

`UI/Theme.lua` states the same fact from the other direction, which is why panel
text is flat: over an opaque window an outline only thickens a glyph until it
closes itself up. Same fact, opposite conclusion, because one of them sits over
the world and the other does not.

All three of those shipped wrong first, a 12 pixel icon and 11 pixel row text,
and the report was two words: shrunken, and not sharp. The third was the pane
headers at 12, which nobody reported because nobody reads a header twice; they
were the same defect one line above the rows and the gate is what found them.
The harness now fails if a row icon draws a size the client does not store, at
either zoom that can be exact, and fails on any outlined string under the
floor.

**The mouse, and what the header costs.** The frame takes the mouse only while
it is unlocked, the same rule the charge button follows: a mouse enabled frame
swallows every button that lands on it, including the right button drag that
turns the camera. The one exception is the damage pane's header, which is the
DPS/HPS toggle and takes the mouse always, because a control you cannot click
while the frame is locked is not a control. The price is exact and worth
stating: a camera drag begun on that one strip, fourteen pixels tall, will not
turn the camera. Nothing else on the meter has that problem.

**Five defects the harness caught, four of them before any of this ran in a
client.**

    a nan in the header    Before the first fight of a session nothing has been
                           recorded and the clock reads zero, so the group total
                           was 0/0. The nan survives math.floor and the client's
                           string.format renders it -9223372036854775808. That
                           was the first tick of every login.
    a header never written A guard on "has the projection changed" whose
                           unchanged case, no eta and nobody converging, is
                           identical to the state the pane starts in with nothing
                           drawn yet. The threat header stayed empty until
                           somebody first pulled ahead. A guard whose "nothing
                           changed" matches "nothing has happened yet" skips the
                           first write, every time.
    a header stuck         The two early exits, no API and no target, left behind
                           what they had last shown, so a target that came back
                           to the same quiet state found the guard satisfied and
                           the header went on reading "no target" over a full
                           list of rows.
    a parked queue         An inspect the client never answered, above.
    soft and shrunken      The fifth, and the one the harness did not catch,
                           because there was no gate for it until a person
                           looked at the thing. The icon and the font, above.

Each has a test that fails without its fix.

**Swing timer.** Two gauges under the character, one per hand, and a green band
on the main hand one marking the press that costs no swing. The bars are worth
the same to anybody standing in melee and are gated on holding a weapon rather
than on being a warrior. The band is Slam's and is warrior only.

**The combat log is the clock.** There is no event for a swing starting, no
timer to read and nothing on the player that moves with one. What there is is
`SWING_DAMAGE` and `SWING_MISSED` with you as the source, and a swing landing is
the same instant the next one starts, so those two events are the clock and
`UnitAttackSpeed` is the length of a tick. A miss counts: `SWING_MISSED` is the
server saying the swing happened and did nothing, and a timer that only listened
for damage would stop dead against a mob you cannot hit.

Two consequences. A fight opens with the bar empty and it fills from your first
white hit, which is correct rather than a gap: before that swing there is no
swing in progress to draw. And the timer is only ever as right as the last event
it saw, so a swing the client did not log is a bar that runs to the end and
sits there.

**Which hand swung is a flag in two different places.** It is the twenty-first
value of `SWING_DAMAGE` and the second value of `SWING_MISSED`. Reading one slot
for both gives an off hand bar that never runs and a main hand bar that runs at
twice the speed, which looks like a haste bug and is a parser bug. Both indices
are read by number and the harness drives both subevents.

**Haste scales what is left, it does not restart it.** Flurry landing halfway
through a 3.4 second swing leaves you halfway through a 2.4 second swing, so
`Swing.Retime` multiplies the remaining time by the ratio of the two speeds. A
timer that kept the elapsed instead would jump backwards every time Flurry
landed, which is most swings in most fights. `UNIT_ATTACK_SPEED` is registered
and is not enough on its own: the event does not reliably follow an aura on
these clients, so `UNIT_AURA` on the player is registered too and every one of
them ends in a comparison against the speed already held.

`UNIT_INVENTORY_CHANGED` is the third door into the same arithmetic, and this
addon opens it itself: a loadout key swaps both hands mid fight.

**The Slam window is the point of the feature.** Slam has a cast time, it does
not interrupt the swing while it casts, and finishing it restarts the swing.
Press early and the restart throws away the charge you had. Press late and the
swing is pushed out to the end of the cast. The one right press is where the
cast ends as the swing ends, which is the moment the swing has exactly a cast
time left to run. A swing of `D` seconds drawn as a bar puts that press at
`(D - C) / D` of the way along, and the band is that plus and minus a tenth of a
second, because a key press lands within about a tenth of where you aimed and a
mark with no width is one you can only hit by luck.

The band and the mark are drawn in whole pixels, which is what makes pressing on
a mark mean anything: a band at 70.4 percent of a 180 pixel bar and a mark at
70.6 percent of it are the same pixel and the eye cannot tell which side of the
line it is on. They move only when your weapon speed does, which is a few times
a fight, so they are static edges under the first pixel rule.

The fill is not drawn in whole pixels, and that is the second pixel rule rather
than an exception to the first. The bar is asked which side of the drawn band
its fill is on, in the band's own units, so the colour flips the instant the
edge reaches the green you are aiming at rather than a pixel either side of it.
The whole gauge goes green while the fill is inside the band, because four
percent of a bar is not enough to catch out of the corner of an eye and all of
it is.

**Exactly one thing is allowed to move the mark, and it is your weapon speed.**
That is the repair the feature needed after it shipped: the report back was that
the mark "moves around depending on when I click the spell", and it did, because
the cast time under it was re-measured on every cast.

`D` is the swing being drawn, out of `ns.Swing.Duration`, rather than what
`UnitAttackSpeed` says right now. Those are the same number today and asking for
the first is what keeps the mark and the fill two readings of one thing rather
than two answers that agree by luck.

`C` is a constant per character. Haste does not touch Slam's cast time on either
of these clients: Warcraft wiki's patch history dates that to Cataclysm 4.0.1,
2010-10-12, "Slam can now be cast while moving, and haste now reduces the cast
time". Before that patch it is 1.5 seconds less the talent and nothing else. So
a second reading of it carries no information, and every difference a second
reading could carry is noise the mark would move for.

The mark does still move when the swing speed does, and it has to: the press is
the moment with a cast time left to run, and a shorter swing spends a bigger
share of itself on the same cast. Flurry landing walks the band back down the
bar, not up it. The harness asserts that as the invariant rather than as a
percentage, at three weapon speeds and across a proc that lands mid swing,
because the percentage is the number that moves.

**The cast time is measured once and then held.** `UNIT_SPELLCAST_START` carries
what the server actually started, as a start and an end in milliseconds, with
the talent already in it. The first Slam of a session replaces the estimate.
Every Slam after it is ignored.

The reading is snapped to a twentieth of a second, because every value the real
cast can take is a multiple of a tenth and the milliseconds under that are the
server's own rounding. It is refused if it snaps to zero, since zero is truthy
in Lua and a held zero would win over the estimate and then report that this
character has no Slam. It is refused if it is longer than the spell's own cast
time, because that reading is some other cast. What drops the held number is
`CHARACTER_POINTS_CHANGED`, which is the one event that means the answer really
changed.

Until the first cast it is the spell's own cast time out of `ns.SpellCastTime`,
less 0.1 seconds per point of Improved Slam. The talent is found by name rather
than by position, because a talent's tab and index are not stable and its name
is: every "Improved X" talent in this game carries the ability's own localised
name inside it, in every locale Blizzard ships, so the talent whose name
contains the localised name of Slam and is not Slam is Improved Slam.

The 0.1 is a seed and is not trusted. Warcraft wiki's rank table gives 0.1 per
point over five points for Classic and for Burning Crusade and dates the two
point, 0.5 per point version to patch 3.0.2, one expansion past both of these
clients. Wowhead's TBC entry for spell 12330 reads -1000 milliseconds, which
does not agree. Nothing in the API settles it, the measurement replaces it on
the first cast, and the panel says "estimated" until it has.

**Slam restarts the swing and nothing in the log says so.** The next log event
you would see is the swing that lands a full weapon speed later, so a timer
built on the log alone draws the whole of that swing wrong.
`UNIT_SPELLCAST_SUCCEEDED` for your own Slam restarts the main hand timer, and
the spell is matched by name across every shape that event arrives in.

**The bar is drawn every frame and nothing else in the addon is.** See ticker
discipline above for why, and for why that costs nothing.

**It took two repairs and the first one was not wrong.** The fill shipped on a
50 ms ticker whose accumulator reset to zero instead of subtracting the
interval, which made the real rate 15 Hz and the real step three and a half
pixels. That was a genuine bug and fixing it left the bar still stepping,
because the rounding to whole pixels was a second throttle behind the first: a
rounded fill changes value 53 times a second at the shipped width whatever the
tick does. Two throttles on one edge, and finding the first is what hid the
second. When a fix that was demonstrably correct does not change the symptom,
look for a second cause of the same symptom before doubting the fix.

**No test in this repo can prove the bar looks smooth.** Smooth is a property of
a screen and an eye, and the harness has neither. What it can prove is the thing
that leaves the client nothing to be blamed for: on every frame it is given, the
addon hands the widget the exact position the elapsed time puts the edge at, the
value changes on every frame, and every step is the same size as every other.
That is asserted at 60 fps and at 144. The last mile is a person looking at it.

**What could not be verified without the client.** That `SWING_DAMAGE` really
carries the off hand flag in slot 21 on 2.5.6 and 1.15.9, that
`UNIT_SPELLCAST_START` fires for Slam at all, and that the server scales a swing
in flight rather than restarting it when haste changes. All three are asserted
against the stub, which proves the arithmetic and proves nothing about the game.

**Buff nag.** A row of squares over your character, and only when something is
wrong. Nothing missing means nothing drawn.

That is the design decision and it was a real choice. A row that is always up
with the missing ones lit is furniture, and you stop seeing furniture in about a
week, which is exactly long enough to convince yourself the addon is watching for
you. A row that exists only when something is wrong carries its whole message in
existing. The cost is a frame you cannot find to drag, so unlocking draws every
square it watches at three quarters alpha, which is the trade the meters already
make when they draw an outline round an empty pane.

**Two halves, taking turns rather than sharing.** Out of combat the row is what
is missing: no stone on either hand, no Battle Shout, no food. In combat it is
the racial you own and have not pressed. They can never both be on screen, which
is why one row is enough for two questions.

**Every entry has its own switch, and that is not a comfort feature.** A person
who owns no sharpening stones was shown the main hand square every time they
left combat, forever, about a thing they already knew and could not fix. What
happens next is that they stop reading the row, and the row is one row, so
ignoring the stone means ignoring Battle Shout and the food and Blood Fury with
it. One unfixable square costs you the whole feature.

So `buffs weapon off`, `buffs offhand off`, `buffs shout off` and `buffs food
off`, with a tick box each on the panel. Switched off means off the list
`Upkeep.Rebuild` builds, which is the only definition worth having: the tick
never asks about that entry, the row never draws it, and `Describe` never counts
it. Drawing it at alpha zero would have cost the same four calls a tick for a
square nobody can use, and testing it on the tick and throwing the answer away
is the same work with none of the answer. The harness asserts the entry is
absent from the walked list rather than asserting the square is hidden, which is
what makes the cheap wrong version fail.

The switch names the thing rather than the slot, with one exception. `weapon`,
`shout` and `food` are things. `offhand` is a hand, because for that entry the
hand is the thing: the whole rule on it is that a shield in that hand is never
nagged about and a weapon in it is.

**The switch is per character and every other buff setting is not.** How big the
row is and whether it breathes are the same answer on every character you own,
so they are `ns.db`. Whether a bare weapon is worth a square is a fact about the
character: a raiding main carries a stack of stones and wants the square, a bank
alt has never bought one and never will. Account wide would have taken the one
answer that is right for the raider and forced it on the alt, which is the exact
complaint that produced this setting, one level up. It is `ns.dbc.buffWatch`, and
absent means watched, so a fresh character carries an empty table and an entry
added in a later release arrives switched on rather than silently missing.

**A silenced entry is visible somewhere.** `/wk status` and the panel both name
what you switched off, because a nag you turned off six weeks ago and can find
no trace of is the same defect one room over: the row is quiet and you no longer
know why. The status reads `3 tracked, 1 missing; bare weapon switched off`.

**The captions name what is wrong, not which hand.** They read `bare weapon` and
`bare off hand`. They used to read `main hand` and `off hand`, which names the
slot and leaves you to work out what about it, and on a bare icon over your
character that is no help at all. The racial half already spoke the right way
with `press Blood Fury`.

**Hovering a square says the rest.** The caption has to fit four squares' worth
of words on one line, so it is two words and the tooltip carries what those two
words could not: that a bare weapon means no stone, no oil and no imbue on the
weapon you swing, that a bare off hand can only ever be a real weapon because a
shield is never nagged about, that Battle Shout has lapsed and any rank counts,
and for the racial, which racial it is and how many seconds it has been sitting
off cooldown. That elapsed figure is the row's own record: a spell that is ready
reports a duration of zero and no end time, so nothing in the client can answer
it, and `Nag.Update` stamps the moment the racial half came up.

The last line of every tooltip names the switch that silences that square. Being
able to turn one off from the square you are tired of, rather than reading a
settings page to find which tick box it is, is most of the value of having the
switch at all.

`Buttons/Square.lua` owns this shape for the action bars and the row follows it:
`OnEnter` and `OnLeave`, anchored to the square, and refused outright when there
is nothing to say. It is not shared code. Every step in that file is about an
action slot read off a secure button's attribute and handed to the client to
describe, and none of it has anything to do with a sharpening stone.

**A square takes the mouse only while the row is locked and drawn**, and there
is a real cost to say out loud. The row sits above the middle of the screen,
which is where a right button drag to turn the camera starts, and a mouse
enabled frame swallows every button that lands on it. So the right and middle
buttons are handed back through `SetPassThroughButtons`, which arrived in 1.14.4
and 10.0 and is probed rather than trusted. On a client without it, a right drag
begun exactly on one of these squares does not turn the camera. That is at most
four squares of 54 pixels, only while something is missing, and only out of
combat. Unlocked the squares release the mouse entirely, because unlocked the
row is a thing you drag and a square on top would eat the button first.

**The spells you add yourself have no switch, and remove is why.** The four that
ship cannot be taken off the row, so a switch is the only way to stop one. A
spell you added is one you can remove in a press, and remove is the better
answer: it hands the slot back, and a flask you have stopped keeping up is not
something you want listed in a quiet state, it is something you want gone. A
switch there would turn six slots into twelve states with nothing on screen to
tell them apart.

The split is not a layout convenience. A missing buff is something you fix out of
combat, because out of combat is when you can fix it, and shouting about a lapsed
stone mid pull is telling you about a thing you cannot do. Blood Fury is the
opposite: it is not a buff you keep up, it is two minutes of attack power sitting
on a key, and the only moment worth saying anything is the moment you are
swinging at something with it off cooldown.

**The weapon enchants are the reason the feature exists** and they are the only
entry that is not an aura. A temporary enchant does not appear in an aura scan at
any index; `GetWeaponEnchantInfo` is the only thing in the client that knows.
That call has had three shapes: six values at three per hand, eight once 6.0 put
the enchant's own id in after the charges, and twelve once Cataclysm added a
ranged hand. Nothing installed here settles which one 2.5.6 and 1.15.9 answer
with, so the stride is counted with `select("#", ...)` rather than read
positionally on a guess. Guessing three against a client that answers eight puts
the main hand's enchant id where the off hand's "has an enchant" belongs, and a
number is truthy: the off hand would read as enchanted forever, silently. The
harness drives both shapes.

**A shield is never nagged about**, and that is the client's own
`OffhandHasWeapon` rather than a reading of the slot. A shield, a
held-in-off-hand item and an empty hand all answer no to it, and all three are
states a warrior is in on purpose.

**Auras are matched by name and scanned on an event.** Battle Shout has eight
ranks and the aura on you carries whichever one was shouted, so the ids in the
source exist only to ask this client what it calls the spell in the language it
is running in. The scan runs from `UNIT_AURA`, which fires for every buff you
gain and every one you lose, so nothing walks forty slots on the tick. On a
client carrying `C_UnitAuras` that walk would also build a table per aura, which
is allocation on a ticker.

Battle Shout is the one entry gated on class, inside `Upkeep.Rebuild`. The part
itself is not: a lapsed stone costs a hunter's melee weapon exactly what it costs
a warrior's, and a troll rogue forgets Berserking the same way.

**Flasks and elixirs are a setting, not a table.** These clients will not say
that an aura came from an elixir. There is no category on an aura and no call
that maps one back to the item, so the only built-in version is about forty hand
written spell ids that cannot be verified from outside the game, go stale on the
next patch, and are wrong in a way nothing reports. `/wk buffs add <id>` takes
six of your own, the same shape the debuff row on the enemy bars already has.

**Only the racials that are damage are nagged about.** Blood Fury on an orc and
Berserking on a troll: both are throughput, both come back inside three minutes,
and forgetting one across a boss fight is free damage thrown away. Every other
racial a warrior can have is listed with the nag off, so `/wk status` and the
panel can name yours and say why it is quiet. Stoneform is spent when something
bleeds you and War Stomp when something needs stunning, and a row that shouted
about either every fight would teach you to ignore the row, which would cost you
Blood Fury as well.

The ids are Wowhead's TBC Classic database, each checked against the cooldown its
page states: Blood Fury 20572 at two minutes, Berserking 26297 at three, War
Stomp 20549, Will of the Forsaken 7744, Stoneform 20594, Escape Artist 20589,
Perception 20600, Shadowmeld 20580, Gift of the Naaru 28880. Blood Fury has a
second proof and it is the one that matters: 20572 appears as a buff with uptime
in this install's own Details saved variables, recorded off a live 2.5.6 session.
The race is read from `UnitRace`'s second return, which is the token and is the
same string in every locale.

**How loud, and why there is no sound.** The racial square breathes: its alpha
runs between a floor and full over 1.6 seconds, which at ten hertz is sixteen
steps and reads as a pulse rather than a strobe. It is on by default, because a
nag you can ignore is not the thing that was asked for. There is no sound and
there will not be. A chime in a raid competes with the sounds you are already
listening for, it fires whether or not you are looking at the screen, and a
racial coming off cooldown is worth noticing within a few seconds rather than
immediately. The alpha is quantised to twentieths so a tick that would draw the
same value writes nothing.

Two states silence the missing-buff half and neither touches the racial half.
Dead, because nagging a corpse about its sharpening stone is noise, and that one
is not a setting. Resting, because an inn or a capital is where you have not put
a stone on yet on purpose and the row would be up through an hour at the auction
house; that one is `buffs resting` for anyone who buffs in the bank.

**What could not be verified without the client.** Which shape
`GetWeaponEnchantInfo` answers in, whether `IsResting` and `UnitIsDeadOrGhost`
are on both flavours, and whether 19705 is spelled exactly "Well Fed" in every
locale. All three are in the untested list below.

**Breakdown.** One row per ability, counted out of the combat log and kept
between sessions: how much of your damage it is, how often it lands, how often
it crits, and what stopped it when it did not. It is not the meters. They total
the pull you are in and forget it; this is the month.

Only your own hits are counted, and that is what keeps the record small.
Counting the group would grow the table by every stranger you have ever been in
a party with.

**The fourth band is the honest one.** Rows can be filtered to one band of
target level against yours. The combat log does not carry a target's level, so a
mob you never targeted and never saw a nameplate for lands in `level not seen`
rather than being quietly counted as your own level. Picking one band is worth
doing before you believe a crit or a miss rate: in this era the target's level
drives both of them hard, and a number pooled across grey trash and an elite is
the average of two unrelated things.

**The table is a window, not a page.** A left click on the meter's header opens
it, which is where you are looking when the question occurs to you. A right
click on that header swaps the meter between damage and healing. Escape or the
cross closes the table.

Only abilities that have swung at something are listed. A shout, a stance and
Charge are counted like everything else and kept out of a table ranked by
damage, because there they can only ever be a run of zeroes above the rows you
opened it to read. An ability that has only ever been dodged does get its row:
no damage across four dodges is not the same fact as no damage because the thing
does none.

Ranks are added up under one name. A rate pools across ranks correctly, because
it is per attempt either way. An average hit does not: for an ability you have
used at several ranks it is a blend of the rank you outgrew and the one you use
now.

**Feeds.** Two columns of the same shape, one fed by loot and one by the combat
log. A loot row is the item's icon, its name in its own quality colour and how
many there were, with a stripe down the left in that colour, so a run of drops
reads as a ribbon before you read a word of it. A quest item carries a ring
round its icon, because a quest item is white and so is a stack of linen. A
combat row reads what happened, then who it was, then the number. The stripe says which way it went,
white out, red in, green healed and grey missed, and a critical draws its number
in gold with a mark after it, so the crit is not a hue you have to be able to
see. Entering and leaving combat draw a band across the feed, which is what
separates one pull from the one before it, and the closing band says how long
the fight took.

**Two switches per feed, and they are not the same question.** Collect is
whether anything is recorded. Show is whether the column is drawn. Hidden and
still collecting is close to free, because drawing the column is the expensive
half, and showing it again brings back everything that happened while it was
away. Off, the loot feed reads no loot message at all, and the combat feed turns
an event away on one table lookup, which in a raid is the difference between a
few hundred lookups a second and a few hundred rows a second.

The loot feed ships on, against the right edge of the screen. The combat feed
ships off, both switches: it is the one thing in the addon that reads every
combat log event in the zone, and the meters and the breakdown already answer
"how did that fight go" off the same log without a row per swing. `feed combat
on` for the pull you want to read back.

**The loot feed ships bare and filters with chips.** No word over the column and
no line round the frame: the rows say what they are by the colour of the name on
them and the chrome was carrying nothing. Both are settings, `feed loot header`
and `feed loot edge`, and the combat feed keeps both because its rows are three
columns of numbers.

Over the rows are seven small squares of the addon's own furniture, each with a
mark on it: five gems in the quality colours and then, past a break, a quest bang
and a stack of coins. An off chip keeps its square and dims its mark, so the
strip holds its rhythm however many are off. They filter
what is drawn rather than what is kept: everything that drops is recorded either
way, so turning a chip back on brings its history with it. The tally on the right
of the strip reads "4/40" whenever a chip is hiding something, because a column
of four rows on an evening that dropped forty things otherwise looks broken.

Quest is an override rather than an eighth quality. On, a quest item is drawn
whatever the white chip says, which is the combination worth having while
questing: the whites off and the five wolf livers still on screen.

Every quality ships lit, grey vendor trash included, because this addon sells
that trash for you at the next merchant and the feed is the only place you will
ever see what it was. The group's drops are off by default: everyone else's loot
is what makes the client's own chat unreadable in a raid, and a feed that
reproduced it would have replaced one unreadable column with a prettier one.

**Hovering a loot row says what the thing is worth, twice.** The vendor price is
the client's own and is per item, so a stack gets a second line with the total on
it, which is the number you actually decide on and which no tooltip in the game
gives you. An item a vendor will not take says so in words, because nought copper
and "not cached yet" are the same number and different facts.

What an item goes for at auction is not a number this client holds at all.
`Feeds/Auction.lua` asks whichever scanner the player has installed, in order,
and takes the first answer: Auctionator on either of its interfaces,
TradeSkillMaster, Auctioneer, RECrystallize. None is required, no TOC names one,
and a player with none of them loses one line of one tooltip and is told nothing
about it. The line names the addon that supplied the number, because a price with
no source on it is one you cannot check.

**A row is a size.** `feed <which> icon` runs 16 to 40 and the row is the icon
plus two, so one stepper moves the picture, the line height and the height of the
whole feed. The floor is the text rather than the art: every string on a row is
outlined and an outlined glyph needs 14 pixels, so a row shorter than 16 is one
whose name does not fit however small the picture gets. 27 is the only size in
the range that draws one stored texel per screen pixel, and the panel says so
when you move off it.

**The combat floor is a setting because there is no right number.** At zero this
is every tick of every bleed on every mob in the pack, which in a fury pull
scrolls faster than it can be read. The right floor at level 20 and the right
floor in a raid differ by an order of magnitude. Misses and dodges earn a row
with no number on it: four dodges in a row is the reason your rotation stalled
and nothing else on the screen says so.

At zero background the feed is rows of outlined text over the world, the way the
meters are drawn, and the edge goes with the background whether or not its own
switch is on: a hairline rectangle round bare world is a window frame with no
window in it. The scrollbar goes too,
in everything but the thumb, which is the only thing left saying there is more
above and below what you can see.

Rows answering the mouse buys the tooltip and the wheel at the price a mouse
enabled frame always costs: it swallows every button that lands on it. The right
and middle buttons are handed back where the client has
`SetPassThroughButtons`, and where it does not, a right drag begun on the feed
will not turn the camera.

**Chat.** A column of rooms down the left of a window of the addon's own, and
the room you pick filling the rest. A room is one conversation: your party, your
guild, the family, each person whispering you. Every line keeps its channel
colour, names are class coloured, and a click on a name answers it.

The column is one icon wide and the window has no title bar. Both are the same
argument: thirteen room names cost a hundred pixels of every line anybody said
to label rooms you know by sight, and a bar across the top says which window
this is to somebody who has had it open all evening. The name of a room, what
the enter key would do in it and how much is waiting are in its hover, and the
room you are in is written into the empty line you type on.

**The room you are reading is the channel you are typing into.** That is the
whole design and everything else follows from it. Select the party room, start
typing, and the line already reads `/p ` with the cursor after it. Select the
guild room and it reads `/g `. A conversation with one person reads `/w Aria `.
Tab steps to the next room and rewrites the slash.

The slash is in the field rather than on a label beside it, and the difference
matters. A label is the addon telling you where the line will go. The slash is
the line, so you can see it, delete it, or change the p to a g, and everything
you already know about typing in this game still works: `/w Aria` from inside
the guild room whispers Aria and leaves the guild room where it was. There is no
second piece of state anywhere saying which channel you are in. The window this
replaced had one, in a button beside the field that cycled six channels, and it
could disagree with the tab you were reading all evening without saying so.

Every channel prefix the addon knows is sent with one `SendChatMessage`.
Everything else with a slash on the front, from `/dance` to another addon's
command, goes to `ChatEdit_SendText`, which is what Blizzard's own field calls.
`/raid` is raid and `/r` is reply, the way the client has it: getting that the
wrong way round sends a whisper meant for one person to forty.

**A room is a view, not a box.** One line lands in every room it belongs in, so
a whisper from your wife is in Whispers under her name, in Family, and in
Conversation. Nothing is filed away somewhere you have to remember to go and
look. A room is drawn while the channel behind it exists, or while it holds
something you have not read, which is what keeps a party line that arrived as
you left the group reachable instead of deleting the row it was on.

What marks a room is a count in the corner of its icon in the accent colour, and
the icon itself brightening. Selecting it clears the count. There is no flashing,
no toast, and no sound unless somebody in one of your groups spoke.

**Groups are the people who matter, in named sets.** Family, the officers, the
four you level with. The first version of this was one flat list of important
people and one tab for all of them, which holds up until you have two kinds of
person on it: a wife in party chat and an officer asking about raid times are
both important and neither belongs in the same column as the other. People are
matched on the name alone, case ignored and realm ignored, so one row covers
somebody whether they are standing beside you or whispering from another realm.
A person may be in two groups and their line goes to both. The groups are shared
by every character on the account, because who matters to you is not a fact
about the character you happen to be standing in.

**Blizzard's chat window is hidden, and everything it would have drawn is
forwarded here.** That is the default. The switch is on the **Blizzard's own
frames** page with the other six, because it answers the same question they do,
and `/wk hide chat` is the word for it. Loot,
experience, faction, system text, the combat log and every addon's output,
including this one's, arrive at a chat frame's `AddMessage` as finished strings
with nothing to say where they came from, so they go to the System room whole.

There is no doubling, and the reason is exact rather than lucky: hiding forces
the claim, the claim takes every conversation event out of Blizzard's frames
before FrameXML draws it, and what is left arriving at `AddMessage` is precisely
what this addon did not capture. That is what the README used to say could not be
done. It could not be done with the claim off, which is still true and is why the
claim cannot be turned off while the window is hidden.

Nothing is unregistered and nothing is destroyed. The frames go down through
`ns.Strip`, which puts a frame's own `Hide` where its `Show` was and so survives
the client showing it again, and only a frame that was on screen is taken, so
putting the window back does not turn on eight tabs nobody ever opened. They keep
their own scrollback, so turning the setting off puts the window back with the
evening still in it. Closing this window puts Blizzard's back on the
next call, because a game with neither has no chat at all.

**The enter key comes here while that window is hidden**, through an override
binding that is dropped by one call, and goes back the moment the window is
shown again. That coupling is deliberate rather than a setting of its own: the
client's enter opens the client's chat line, and with that window hidden the
line it opens is invisible. Every slash command still works from this field,
because the ones the addon does not know are handed to the client's parser.
There is also a key under WarriorKit in the client's own key bindings, for
somebody who keeps Blizzard's window and wants this one on a key of their own.

The numbered channels are on by default and have no room of their own: they land
in Conversation with everything else. General, Trade and anything else you have
joined are most of the volume in a city and none of the conversation, but they
are also where a group is found on these servers, and a window that cannot show
them is a window you still have to look away from. One tick puts the noise back
in Blizzard's frame. The sound for one of your people speaking is the client's
own whisper sound and only plays while you are not already reading one of your
groups: a sound for a line you are watching arrive is a sound you turn off, and
then there is none for the one you miss.

There is no drag handle on the corner. A window that resizes on the mouse means
a reflow of every wrapped line on every mouse move, and two steppers say the
same thing exactly. Drag the window itself while frames are unlocked.

**Voice only ever joins.** The pick is everything the client's own Chat Channels
window draws a voice button on: your party or raid, and every stream of every
community and guild you are in. There are no voice channels of your own to name,
because Blizzard's voice chat is attached to the groups you are already in. A
channel does not have to exist to be picked: a party channel is made when you
group up and a community one when the first person joins it, so the addon asks
for the one you named again at every login, at every roster change and whenever
the voice service comes back, and stops asking after five refusals. Nothing here
leaves a channel, mutes anyone, picks a device or moves a volume. Those are the
client's own settings and you pressed something to get them where they are.

The pick ships with a club ID in it, which is the author's own guild stream. A
client that is not a member of that club finds no such channel and joins
nothing, so on anybody else's account it behaves exactly like "none" with one
lookup in front of it, and the picker is one row away.

**Minimap.** The mask, the ring, the north tag and the two zoom buttons come
off, the map is squared and resized, and the mousewheel zooms instead.
Everything goes back in one call, so off is a state rather than a reload.

The round mask throws away the corners of a map the client has already drawn,
and the ring round it spends about twenty pixels of every edge on rivets.
Blizzard's own mail, tracking and battleground icons are moved to the corners of
the square, because they were anchored to points on the arc and a square has no
arc to hang them on.

**The ring was the only thing ending the picture**, which is why the black edge,
the hairline and the clock all wait for the square. The square gets the same
edge the action bars are built on, and the clock hangs off the bottom of it in
the middle with the realm's time on its tooltip. The sun and moon and Blizzard's
own clock come off with the ring: the sun says whether it is day in a game whose
sky says the same thing, and the clock draws its numbers on a strip of the old
stone minimap tile, which on a stripped square is the last piece of Blizzard's
map left on the screen.

**Every addon that wants to be reachable puts a round icon on the minimap
edge.** With eight installed the map is a ring of icons with a map in the
middle. The corral collects them behind one square you press to open a tray.
Each button is borrowed rather than taken: its parent, its position and its own
`SetPoint` are handed back the moment the corral goes off, and nothing about the
button itself is changed, so it does in the tray exactly what it did on the
ring.

Blizzard's own icons are left alone. The mail, the tracking and the calendar are
read at a glance without being pressed, and squaring the map has already put
them on the corners.

The scan runs at login, whenever an addon finishes loading, and whenever you
open the tray. Nothing polls, so an addon that puts its button up on a timer of
its own is found the next time you open the tray rather than the second it
appears.

**A pin is not a button.** The minimap is also where every addon that draws on
the map hangs its pins, and those are left where they are. They arrive in pools
with generated names, which is what tells them apart from a button. The corral
also refuses to hold more than it can lay out, and `/wk minimap list` says what
it took, what it left as pins and what it refused, because nothing should be
taken quietly.

**Interface.** One Edit Mode layout, carried inside the addon folder. This
client has Edit Mode: the backported retail manager, with the layouts written to
`WTF/Account/<account>/edit-mode-cache-account.txt`. That file is per install,
which is the whole problem. A second computer gets a fresh WTF and none of your
frame positions.

Saved variables do not solve it either, because they live in WTF too. The only
thing that travels with an addon is the addon folder, so the layout has to end
up as a file in it. An addon cannot write files, so the capture goes out through
saved variables and comes back in through a shell script:

    in game     /wk ui save            reads the active layout into ns.db.uiLayout
                /reload                the game writes saved variables on unload
    in a shell  ./bake-ui.sh           rewrites EditMode/Saved.lua from that

`bake-ui.sh` reads the saved variables file as Lua in an empty environment
rather than with a regex, and re-serializes with sorted keys, so re-baking an
unchanged layout produces a byte identical file and a real change is a readable
diff. It runs `check.sh` on the way out.

On a client that has no layout by that name, `AutoApply` imports it at
PLAYER_ENTERING_WORLD and makes it active, once. A layout already present is the
user's and is left alone, because swapping the UI at every login is not
automatic, it is a fight. `uiAuto` turns the import off; `/wk ui apply` does it
by hand.

`EditModeManagerFrame` is confirmed here only through `GetActiveLayoutInfo`,
which is the one method Titan calls. `GetLayouts`, `SelectLayout`, `ImportLayout`
and `SaveLayouts` are retail method names that this backport is assumed to carry.
`EditMode.CanApply` probes all five by name and every call goes through `Call`,
which pcalls, so a client missing any of them greys the buttons out and says
which one rather than erroring. Unlike the Buttons probe this one is not cached,
because `Blizzard_EditMode` can be load on demand and an answer taken at login
would go stale.

**Comfort.** Three chores the client makes you do by hand, lifted from Leatrix
Plus, which is loaded on both of these clients and is where every API here is
proved. They share a part because the alternative is three rail entries carrying
one tick box each; the panel's second level does the rest, so it is one rail
entry with a tab per chore.

**Thanking a stranger is the fourth chore and the only one that talks to
another person.** Somebody walks past, buffs you and keeps going, and the two
letters back do not get typed because by the time your hands are free the name
has scrolled away. `Comfort/Thanks.lua` reads `SPELL_AURA_APPLIED` off the
combat log, which is the only place the client names the caster at the moment
the aura lands: `UnitAura` names one too, but as a unit token, and a stranger
who buffed you in passing has no token a second later. Four filters stand
between a log line and a whisper. The aura landed on you, it is a buff rather
than a debuff, the caster's GUID is under `Player-` so it is not a pet or a
totem or a mob, and `Unit/Roster.lua` does not know them, because in a party or
a raid the buffs are the arrangement rather than a kindness. The same name is
thanked once every ten minutes, so a re-buff sends nothing. Off unregisters the
frame rather than branching inside the handler, which matters more here than it
does on the loot path: this is the busiest event in the game.

**Fast loot is a race the client loses on purpose.** Its auto loot opens the
window, then takes one slot per frame with a pause between each, and the window
is drawn through all of it. `LOOT_READY` fires once the server has said what is
on the corpse and before any of that starts, so taking every slot there empties
it without the window appearing. The throttle is 0.3 seconds, because
`LOOT_READY` fires again as each slot clears and a second pass over slots the
first one already took is at best wasted work.

It only runs when auto loot is what the click asked for, which is
`GetCVarBool("autoLootDefault") ~= IsModifiedClick("AUTOLOOTTOGGLE")`: the
setting, inverted by the modifier that exists to invert it. A shift-click to
open the window still opens the window.

**Master loot is the one case where fast looting is theft.** Every slot at or
above the threshold belongs to the master looter to assign. `LootSlot` on one of
those does nothing if you are not the master looter and quietly assigns it to
yourself if you are, which is a way to ninja your own raid without meaning to.
So under master loot only the slots below the threshold are taken.

Which loot method this is comes from `C_PartyInfo.GetLootMethod`, an enum where
2 is master looter, or from the old `GetLootMethod` global, which answers the
string `"master"`. Neither is proved on both clients, so both are probed and
neither answering is a third state: solo the corpse is still emptied, because
there is nobody to take a slot from, and in a group it falls back to the
client's own auto loot, which is slower and correct.

**The vendor part can destroy what you own, and that is the whole design.**
`ns.UseContainerItem` sells a bag slot while a merchant window is up and *uses*
it when one is not. It eats the food, equips the weapon, opens the box. So the
sweep asks `MerchantFrame:IsShown()` before it touches anything and stops the
moment the answer is no, and `MERCHANT_CLOSED` stays registered even with the
setting off, because turning selling off mid-sale still has to end the sale.

**Only grey, and only what a vendor pays for.** Quality comes from
`ns.ItemValue`, which is `GetItemInfo` and answers nil for an item the client has
not cached yet. Nil is treated as "do not know" and the item is left alone, then
asked about again a fifth of a second later. Selling on a guessed quality is how
something that is not trash ends up at a vendor, and there is no undo.

**A sale is not instant, so the sweep is a ticker rather than a pass.**
`UseContainerItem` locks the slot, the server clears it, and only then does the
item leave the bag, so one pass cannot see the result of its own work. It repeats
at 0.2 seconds until a pass finds nothing left, which is also what catches a sale
the server dropped. The backstop is 25 passes, five seconds, which is longer
than any real bagful and short enough that a vendor who silently refuses
everything does not leave a ticker running behind the window.

Two refusals are listened for by name, `ERR_VENDOR_DOESNT_BUY` and
`ERR_TOO_MUCH_GOLD` on `UI_ERROR_MESSAGE`, because both mean every remaining sale
fails the same way. Both constants are reached through `_G`: a client missing one
would compare a message against nil and stop a sale that was fine.

**What it made is measured, not predicted.** Adding up sell prices says what the
bags were worth. The difference in your purse across the sweep says what the
vendor actually paid, which is the number still right when a vendor refuses an
item halfway down the list. Holding shift as you open a merchant skips the whole
thing for that visit, the same key that already means "let me do this myself"
everywhere else at a vendor.

**Repair pays the guild first, and only as far as your rank goes.** Every
damaged piece at once, the moment the window opens, on any merchant the client
says can mend. Guild funds come first and only as far as your rank's own
withdraw allowance reaches; past that, or with no guild bank on this client, it
comes out of your purse. A purse that cannot cover the whole bill is left alone
rather than half spent, because a half repaired set is worse than an unrepaired
one you knew about. Holding shift as you open a merchant skips the repair for
that one visit, the same as it skips the sale.

The durability reading is the client's, and some clients do not quote it. The
merchant's own price is what the repair is decided on either way, so a client
that answers nothing about wear still repairs correctly and simply says nothing
about how worn you are.

**Error filtering stands in front of `UIErrorsFrame` and drops what you have
ticked.** Nothing is hidden that you have not ticked, and the sound and the
flash are untouched, so a refusal you did not mute still reads exactly as it
did. The list is shared by every character on the account, and it is kept and
consulted again the moment filtering goes back on.

There is one preset and it is the one the charge button costs you: what a
positional ability shouts when it misses, which is too far away, facing the
wrong way, out of range and not in front of you. Everything else you mute by
ticking it after it has come past, which is why the list fills as you play. A
client with no `UIErrorsFrame` to stand in front of filters nothing whatever the
list says, and your ticks are still saved for a client that has one.

**Max zoom is one CVar and a readback.** `cameraDistanceMaxZoomFactor` ships at
1.9 and Leatrix has been writing 4.0 into it on both of these clients for years,
which is what says the ceiling here is 4 rather than the 2.6 a retail client
clamps to. It is believed only as far as `Camera.Current`, which reads the CVar
back: a client that quietly clamps is reported as clamping rather than as having
taken the number, and that readback is what the panel note and the status line
print.

Off hands the CVar back at `GetCVarDefault`, probed by name because nothing
installed here calls it, and at 1.9 where the client will not say. The CVar is
the client's and survives a logout, so it is written at every
`PLAYER_ENTERING_WORLD` rather than once at login: anything that put it back
would otherwise leave the setting saying one thing and the camera doing another.

**Clutter.** Quest items for quests you have finished sit in your bags forever.
Most of them cannot be sold, so the vendor sweep is no help and the only way out
is to destroy them, which is why this is a window you open rather than anything
that runs on its own.

**The client will not tell you which quest an item belongs to.** There is no API
for it. It will tell you an item is a quest item, `GetItemInfoInstant`'s sixth
value is 12 and Baganator files its own Quest category on the same number here,
and that is the end of what the client knows. So `Clutter.lua` asks Questie,
which is loaded on both of these clients and whose item database carries
`startQuest` and `relatedQuests` per item. Without Questie the window says so and
offers nothing, because "every quest item in your bags" is not the question.

It asks through `ns.Questie`, naming `QueryItemSingle` and `QueryQuestSingle`,
because those two are what turn an item id into a quest id and a quest id into a
name. Neither of them present is the same answer as no Questie. See Asking
Questie for why the module coming back proves nothing on its own and why the
answer is not cached.

**Three ways an item is kept, and the first one is the one that matters.** An
item that starts a quest you have not provably finished is never offered.
Starters look exactly like orphans sitting in your bags and destroying one is how
a chain you never knew existed is lost. "Not provably finished" includes the case
where the client will not say whether you finished it: `Completed` answers true,
false or nil, and only true is good enough. An item tied to a quest in your log
is kept, and an item the database has never heard of is kept.

What is left gets one of two verdicts. `spent` means every quest it belongs to is
behind you, and `open` means one of them is still out there to pick up. The queue
puts spent first so the window never opens on the hard question, and the button
reads "destroy anyway" rather than "destroy" on an open one.

**The queue is rebuilt on every press, never advanced.** Bags move under an open
window: something loots, the vendor sweep sells, a stack splits and every slot
after it shifts by one. A window holding index 4 of a list it took thirty seconds
ago is a window pointing at whatever is in that slot now. Skips are remembered by
item link rather than by slot, for the same reason, and they are cleared every
time the window opens.

**Four guards stand between a press and a delete**, and the harness proves each
one by breaking it:

- the slot is re-read and compared against the link on the card, so a stale card
  never reaches the cursor at all;
- the item is picked up and the cursor is asked what it is actually holding,
  which is the client contradicting the bag scan and getting to win;
- `DeleteCursorItem` is probed and pcalled, because nothing installed on either
  client calls it. Questie hooks it, which proves the global exists and is not
  the same as proving the call is ours to make;
- a 0.4 second debounce, because the card is replaced the instant the first
  press lands and without it a double click falls on an item nobody looked at.

The first two overlap on purpose. The cursor check catches everything the slot
re-read catches, so the harness counts pickups rather than deletes to tell them
apart: a stale card that still reaches a pickup means the first guard is gone
even though the second one held.

**What this cannot know.** Repeatable quests never flag as completed, so their
turn-in items read as finished with forever. A chain can drop part three's item
while you are on part one, and Questie's database is expansion scoped, so the
Anniversary client reads the TBC rows and Era reads the Classic ones. All three
are reasons the window asks rather than acts, and the panel tab says so above the
button that opens it.

**No reset hook.** The registry's `reset` means "put this part's frames back
where they started" and this part has no frames. Registering one would make
`/wk reset`, which is what you type when a window has wandered off screen,
quietly turn selling back on for someone who had deliberately turned it off.

### Zoom

Every size in this addon is a count of physical pixels, decided once and true on
every monitor. That is the right default and it answers the wrong question for
one setting, which is how big a screen should look to the person reading it. A
544 pixel panel is comfortable on a 1080p monitor and a postage stamp on a 27
inch 4K one, and no measurement the addon can take separates the two, because
the difference is how far your eyes are from the glass.

So this is a preference and not a calculation. One rail entry, one row per
screen, one key per row in the account file. Each multiplies the whole step
`UI.ScreenZoom` already picks, so a 4K screen at 0.5x lands back on the design
size with every edge exact. Windows ship at 1.3, which is a stop that does not
keep the grid; the paragraph below is what that buys and what it costs, and 1x
is three steps down for anyone who wants the exact one back.

The page is built off `ns.Zooms()`, which walks the registry, so the list of
screens is the list of parts that draw one and cannot go stale. `Settings/` owns
three of the rows itself: the options panel, the hover box and the confirm box,
which are the screens no feature has a claim on.

**Back to the shipped answers.** `ApplyDefaults` fills in a setting that is
missing and leaves one that is present alone. That is the right rule for a
setting arriving in an update and the wrong one for a release that moves a
default: an account file with a number already written against every key never
sees a new one, so the player who has run the addon longest is the only one who
never gets the layout it ships with. Deleting the saved variables file was the
answer before this, and it takes the gold ledger and your groups with it.

`/wk defaults` reports how many settings are off the shipped answer and writes
nothing. `/wk defaults yes` writes them all back and reloads. The Settings page
draws the same thing as a button that arms on the first press and does it on
the second, and drops the arm when the window is shut.

It reloads because there is no hook that says "read your settings again". A
part reads them once, when it is built, so the honest way to apply two dozen
parts' worth at once is to build them again. Inventing an apply hook per part
would be two dozen functions with one caller between them, and the eight stale
anchors that `ns.DefaultCopy` replaced are what that kind of duplication looks
like a year later.

Fifteen keys are stepped over, named with a reason each in `Core/Core.lua`'s
`KEPT`. Every one of them is a record rather than a preference: the gold
ledger, your groups, the three lists you curated, what three nameplate CVars
held before the addon arrived, what the charge and switch keys displaced, the
Edit Mode staging area, and the note the chat window leaves when it fails to
build. There is no right default for "how much gold was that alt carrying", and
writing one would delete the answer rather than restore it. The list is checked
against the registry at login, so a key cannot be kept out of the reset and
then quietly dropped from the addon.

**Quarters, and what they cost.** The stops are 0.5 through 3, eleven of them. A
stop keeps the pixel grid when the size times the screen's own step comes out
whole, so on most screens that is 1x, 2x and 3x, and on one tall enough that the
addon already zooms 2x it is every half step. The rest do not: at 1.25x on a
1080p screen a one pixel hairline is asked for at 1.25 pixels and the renderer
lays down something soft, which is the exact defect `bars zoom` refuses to
allow.
Allowing it here is a deliberate split rather than an oversight. A bar over a
mob's head is the addon deciding what you see in a fight and is worth keeping
exact; a settings window is you deciding how you want to read it. The panel
prints which stop you are on and what it costs, and `Settings.Describe` is the
one function that sentence comes from, so the panel cannot claim a grid it does
not have.

**A drag shows and does not commit.** The client works a slider's value out from
where the cursor sits against where the track sits, every frame. The size setter
resizes the window the slider is in, the window is centred, so growing it walks
the track sideways by a good fraction of its own width and the next frame reads
a value off geometry that has already moved. The two then feed each other and
the thumb slams between the ends of the range for as long as the button is down.
`kit.Slider` therefore updates its readout on every step of a drag and calls the
setter once, on the way up. A click on the track and a keyboard nudge are not
drags and commit straight away. The harness holds the button, moves the thumb,
asserts nothing was saved, lets go and asserts the value landed.

**What it covers.** The windows this addon draws, which today are the `/wk`
panel and the Clutter window. Not the enemy bars, which have `bars zoom` in
whole steps, and not the skinned unit frames or the charge button, which are
sized in pixels where they sit and have their own settings for it.

**The fallback is a real branch and it is tested.** Nothing installed on 2.5.6
proves the `Slider` frame type takes a thumb texture from a stranger, so
`kit.Slider` probes it the way `UI/Scroll.lua` probes the scrollbar and falls
back to a pair of nudge buttons. That branch was wrong when it was written:
`pcall` hands back the error message where the frame would be, and the fallback
called `Hide` on a string. The harness now builds the row a second time with
`CreateFrame` refusing `Slider` and clicks both buttons, because a branch
nothing ever runs is a branch that is wrong.

**Console.** A box on the Under the hood page that runs a few lines of Lua
inside the game and shows what they printed, and one button per probe. A probe
is a question written into `Console/Console.lua` under a name: the calls, each
printed with its name beside it, so the answer reads as a table rather than a
row of numbers. The first is `xp`, every reading `Progress/Progress.lua` takes
before it decides whether there is an experience bar to draw, next to the two
the client's own bar asks instead on the builds that have them.

It exists because a macro is typed. On a machine where the clipboard does not
reach the game window, six calls with their names beside them are six chances
to mistype one, and the answer to "what does this client say here" is worth
having exact. `/wk console xp` prints the same lines to chat, and `/wk console
run <lua>` takes one line raw. The chunk runs as the client's own globals, the
way a macro does, and `print` is borrowed for the length of the chunk and put
back whether it ran, raised or never parsed.

**Performance.** What the addon costs, measured rather than claimed: how much
Lua it is holding, how fast that is growing, and how long each ticker takes.

**Read the memory figure as churn, not as size.** The client attributes Lua
allocation to an addon and nothing else. Frames and textures live on the C side
and never appear in that number, and for a UI addon they are most of the real
footprint. A fall in the figure is the collector running, which is why the rate
counts rises only.

The memory walk is the expensive half and it runs only while the tab is on
screen. The row that owns the sampler is a child of the section, so the client
shows it when the tab is chosen and hides it when the window closes or another
tab is, which is exactly the window in which walking every addon's memory is
worth doing.

**Timing is two clock reads per tick**, about forty a second across the whole
addon, and what that costs is one of the lines it measures. A client with no
`debugprofilestop` has no clock to time with and leaves those figures empty; the
memory half still works.

Per addon CPU through the client's own profiler needs the `scriptProfile` CVar
and a reload, and it slows the whole client while it is on. Nothing here turns
it on. If something else already has, the tab says what the profiler puts this
addon at, and the per tick timings above it are the addon's own clock either
way.

Gauges are what the timings are timings of. A part registers one with
`ns.Perf.Gauge(label, fn)` and it draws under **What is on screen**: a
millisecond figure means nothing without the count of things it was spent on,
and a row with nothing on it costs one comparison.

**Mail.** A mail window of the addon's own, opened by the mailbox rather than by
you. Sending is a column of favourites down the left, the recipient and the coin
beside it, the attachments beside that, and the subject and the letter under
both. Receiving is a list of what is waiting, one row a message.

**The band along the bottom is what the part is for.** Everything else in the
window is furniture the client also has. The band is one line in the colour of
whoever you are sending to: green for a character on your own account, blue for
somebody on your friends list or in one of your groups, red for a name the addon
has never seen, and it says what is riding on the letter while it says so.

It is one element rather than a warning that appears when something is wrong. A
warning that appears is a warning you have to notice appearing, and it moves
everything under it when it does. This is always there and always says who, so
there is no state in which the window is not telling you.

Red also arms the send. The button turns with the band, reads `send anyway`, and
takes a second press; anything you change in between disarms it, because the
thing you changed is the thing the warning was about. `/wk mail warn off` drops
the second press and keeps the colour.

**Favourites are a different axis from the colour and that is deliberate.** A
relation is what the client and the addon can work out about a name. A favourite
is a name you put on a list because you mail it. A guild bank alt you mail every
week is a stranger by relation and belongs on the list; an alt the addon met
once is green and does not. The warning is measured against the list, because the
list is the half you curated. The list ships with the author's bank alt on it,
which on anybody else's account is one name in the picker that never matches
anybody and comes off with `/wk mail unfav`.

**More than twelve attachments.** A mail carries twelve and there is no arguing
with that. What the client then does is make twelve the number you have to think
in: fill a form, send, walk back to the bag, fill it again. `Mail/Draft.lua`
holds up to thirty six and divides, `Mail/Send.lua` sends one at a time and waits
for the server between each, and the block of squares draws the line where the
split falls so you can see it before you press. Coin rides on the first mail
only: splitting it three ways would be three ways for half of it to be sitting in
a mailbox after the second one failed.

**The subject writes itself.** Sending gold titles the mail `money` and sending
one thing titles it after that thing, because that is what you would have typed
and because an inbox of mails called nothing is an inbox you open one at a time.
A subject you type wins over both. A split send numbers the parts and fits the
number inside the client's sixty four characters rather than letting the server
cut it off mid-word.

**How an item gets onto the form.** `UseContainerItem`, with the send pane
flagged as showing by `SetSendMailShowing`. That is the same call that sells a
grey at a merchant and eats a bread roll anywhere else, and the flag is what
decides which; it is the shape `Baganator/Transfers/AddToMail.lua` uses on this
exact client. The pick-up-and-click route is the other way and is worse here: it
puts an item on the cursor, so a failure halfway leaves you holding a stack of
ore in the middle of a window, and it needs the attachment slot chosen by hand.

Every slot is resolved twice, once when you drop and once at send, against the
link recorded at the drop. The bags move while a window is open: something loots,
a stack splits, the vendor sweep sells and every slot after it shifts by one. An
item that has genuinely gone is counted and reported rather than replaced by
whatever is in that slot now.

**There is no send timeout and that is deliberate.** A stalled send waits, the
window says which mail of how many it is waiting on, and there is a stop button
under it. The alternative is an `OnUpdate`, and an `OnUpdate` is a ticker this
addon would then have to defend forever, for a case that is a server not
answering. `MAIL_FAILED` and the mailbox closing both end a run on their own, and
a refusal stops the rest: a mail the server would not take has left its
attachments on the form, and posting the next one on top of them would send
somebody else's items to this recipient.

**Taking counts down.** `AutoLootMailItem` takes the coin and every attachment
off one message, and a message with nothing left on it and no text is then
deleted by the server, which renumbers the inbox. Walking upwards from one skips
every other message while reporting that it took them all; walking down from the
end cannot, because deleting message seven moves nothing below seven. A message
whose load does not go down, which is what a bag filling part way through one
looks like, is stepped past and counted rather than asked again forever.

**Blizzard's window is parked, not hidden, and it is the one frame that skips
`Core/Attic.lua`.** `MailFrame` ceasing to be drawn is what tells the server you
have walked away from the mailbox: TitanPost secure-hooks `MailFrame_Hide` for
exactly that signal, and the client's own `MAIL_SHOW` handler calls `CloseMail`
when `ShowUIPanel` could not find room for the frame.

Both of the addon's own mechanisms would therefore close it. `ns.Strip` calls
`Hide` as its first act. The attic re-parents a frame into a hidden room, which
is the stronger guarantee everywhere else and the wrong one here for the same
reason: visibility is a property of the parent chain, a frame whose parent is
hidden stops being visible, and that is what `MailFrame`'s own handler reacts to.

So the frame stays shown and stays parented to `UIParent`, parked off the side of
the screen at no opacity, and re-parked on its own `OnShow` because the client
lays its panels out again whenever a panel opens. The cost against the attic is
real and is why parking is not the default anywhere else: a client that
repositions the frame between two re-parks puts it back on the screen, where the
attic could not. That failure is visible rather than silent, and
`/wk mail hide off` is the way out of it.

**Who a name is comes from three lists and `Mail/Who.lua` owns one of them.** The
friends list is the client's and is read there, because it is an API rather than
another part of this addon. The other two arrive through `Who.Also` and
`Who.AlsoAlt`, which `Mail/Feature.lua` fills in with `Chat/People.lua`'s groups
and `Feeds/Purse.lua`'s ledger. A part may not name a file outside its own
folder, and both of those are one; copying either list would be a second list to
keep in step.

The guild is deliberately not one of the three. A guild of five hundred is a list
of people you are in a channel with, not a list of people you know, and a colour
that says friend for every one of them says nothing at all.

Names are matched with the realm suffix off and the case flattened, which is what
`Chat/People.lua` does. The cost is the same one: two characters of the same name
on different realms read as the same person.

## Commands

    /wk                          open the settings panel
    /wk panel | options | config the same thing
    /wk status                   one line per part
    /wk help                     the command list, gathered from the registry
    /wk lock | unlock            both frames
    /wk reset                    positions, size, width, offset
    /wk defaults                 what is not the answer the addon ships with
    /wk defaults yes             put all of it back, and reload
    /wk size 52                  charge icon, 16 to 128
    /wk mark on|off              marking, all paths
    /wk markkey skull F5         one key per mark, or none to clear
    /wk markkey cross|moon <key>
    /wk targetmark on|off        the ctrl-targeting fallback
    /wk hover on|off             a key casts on whatever the mouse is over
    /wk hover show               every key and the macro it presses
    /wk hover remove SHIFT-BUTTON3   take one key off
    /wk hover clear              take them all off
    /wk hover list on|off        the list drawn over the world
    /wk hover target on|off      fall back to your target when hovering nothing
    /wk charge on|off
    /wk charge always|ready      always visible, or only when usable
    /wk charge marker on|off     the icon in the world
    /wk charge marker size 30    16 to 96
    /wk charge marker offset 10  nudge it up or down the plate, -60 to 60
    /wk charge soft on|off       action targeting driven off combat, or yours
    /wk charge weapon Bloodspiller   equipped into slot 16, "none" to drop the line
    /wk bind SHIFT-Q             take a key, override binding only
    /wk bind none                hand the key back
    /wk switch TAB               next enemy and swing at it, override binding only
    /wk switch none              hand that key back
    /wk actionbars on|off        our own bars over Blizzard's, same slots, same keys
    /wk actionbars match         back to cloning whichever bars you have on
    /wk actionbars where         the plan lines for wherever you dragged them
    /wk actionbars reset         drop every dragged position
    /wk actionbars lock|unlock   whether shift and a drag moves a bar
    /wk actionbars rows bar1 3   1, 2, 3, 4, 6 or 12 rows of the twelve
    /wk actionbars square bar1 32        one square's edge, 16 to 54, sharp at
                                 27 and 54
    /wk actionbars centre bar1 across|down   its middle on the middle of the
                                 screen, one axis at a time
    /wk actionbars colour bar1 blue      window, black, slate, steel, blue,
                                 green, red or purple
    /wk actionbars background bar1 40    that colour's opacity, 0 to 100 in fives
    /wk actionbars combat bar1 on        the bar goes down when a fight starts
    /wk actionbars key bar1 shift        up only while that key is held
    /wk actionbars plain         every bar back to the plan's own shape
    /wk actionbars trace         what the mouse is really touching, for a drop
                                 that goes nowhere
    /wk bars on|off
    /wk bars mode auto|plates|list
    /wk bars style replace|attach
    /wk bars offset 0            nudge the bar on the plate, -60 to 60
    /wk bars marker on|off       ours, or hand the marker back to Blizzard
    /wk bars level on|off        the mob level inside the bar, coloured by XP
    /wk bars max 8               list mode only, 1 to 15
    /wk bars width 220           a bar on a plate and in the list, 120 to 400
    /wk bars debuff              what the icon row tracks, in order
    /wk bars debuff add 12721    a spell id, up to ten of them
    /wk bars debuff remove 772   by the same id
    /wk bars debuff reset        back to the five it ships with
    /wk bars icon 27             one debuff square's edge, 16 to 32, sharp at 29
    /wk meter on|off             the two meters
    /wk meter dps|hps            what the left pane counts
    /wk meter threat on|off      the right pane
    /wk meter rows 6             3 to 10, per pane
    /wk meter width 260          one pane, 120 to 400
    /wk meter alpha 100          the background behind the bars, 0 to 100 in fives
    /wk meter zoom 1             1 to 3
    /wk swing on|off             the main hand and off hand swing bars, off
    /wk swing width 330          80 to 400, one bar
    /wk swing height 14          4 to 32, one bar
    /wk swing zoom 2             1 to 3
    /wk buffs                    what is missing, and what your racial is doing
    /wk buffs on|off             the row of squares over your character
    /wk buffs weapon on|off      the stone on the weapon you swing
    /wk buffs offhand on|off     the stone on the weapon in your off hand
    /wk buffs shout on|off       Battle Shout lapsing
    /wk buffs food on|off        not being Well Fed
    /wk buffs racial on|off      the racial you own and have not pressed
    /wk buffs pulse on|off       whether the racial square breathes
    /wk buffs resting on|off     nag in inns and cities too, off by default
    /wk buffs zoom 2             1 to 3, and 2 is what it ships at
    /wk buffs list               the flask and elixirs you added
    /wk buffs add 17038          a spell id, up to six of your own
    /wk buffs remove 17038       by the same id
    /wk skin on|off              square class-coloured player and target frames
    /wk skin player|target|tot on|off   one frame at a time
    /wk skin height 68           18 to 72, the block's height
    /wk skin width 198           90 to 360, the gauge's width
    /wk skin link on|off         mirror the target block off the player block
    /wk skin level 0             -100 to 100, the target's drop from the player
    /wk skin heals on|off        the incoming heal slice on the health gauge
    /wk skin auras on|off        the buff and debuff rows on both blocks, every
                                 aura the client reports, wrapped away from
                                 the block
    /wk skin aura 28             12 to 32, the size of one aura square
    /wk skin probe               what this client answered for each frame
    /wk party on|off             blocks for the people you are grouped with
    /wk party self on|off        whether your own block is in the list
    /wk party order role|group   role bands, or the raid's own group numbers
    /wk party role <name> tank|healer|dps|none   an answer you type
    /wk party icons on|off       the role icon on each block
    /wk party range on|off       drain a member you cannot reach
    /wk party width 168          90 to 360, the gauge's width
    /wk party height 34          18 to 72, the block's height
    /wk party gap 4              0 to 20, between two blocks
    /wk party grow up|down       which end of the middle the first slot is at
    /wk party columns 8          1 to 8, the raid only
    /wk party percolumn 5        1 to 40, the raid only
    /wk party zoom 1             1 to 3
    /wk party reset              the list back on its own corner of the screen
    /wk hide                     the ten switches, and what each is doing
    /wk hide buffs on|off        Blizzard's buffs, in the corner of the screen
    /wk hide debuffs on|off      Blizzard's debuffs, beside them
    /wk hide target on|off       Blizzard's icons on the target frame
    /wk hide cast on|off         Blizzard's cast bar for your target
    /wk hide playercast on|off   Blizzard's cast bar for you
    /wk hide chat on|off         Blizzard's chat window, forwarded into ours
    /wk hide party on|off        Blizzard's four party frames
    /wk hide raid on|off         Blizzard's raid container and its manager
    /wk hide xp on|off           Blizzard's experience and reputation bars
    /wk hide character on|off    Blizzard's character sheet, and the C key with it
    /wk buttons apply            fill the bars with the warrior loadout
    /wk buttons restore          put back exactly what was there before
    /wk buttons                  what it would do, and whether a backup is held
    /wk ranks                    how many bar slots are holding an older rank
    /wk ranks refresh            move them all up to your best rank
    /wk art on|off               Blizzard bar art, off by default
    /wk xp on|off                the experience and reputation rails
    /wk xp faction on|off        the reputation rail under the experience one
    /wk xp bubbles on|off        the twenty segment marks
    /wk xp width 460             120 to 900
    /wk xp height 14             6 to 32
    /wk xp zoom 2                1 to 3
    /wk xp reset                 back along the bottom of the screen
    /wk loot on|off              empty a corpse in one go
    /wk sell on|off              grey items at every merchant, shift to skip one
    /wk repair                   pay the merchant in front of you now
    /wk repair on|off            every merchant who mends, shift to skip one
    /wk zoom on|off              how far the camera pulls back
    /wk errors on|off            filter the red text through your muted list
    /wk errors list              what is muted, and what has come past this session
    /wk errors clear             unmute everything
    /wk errors charge            mute what a missed positional ability shouts
    /wk minimap on|off           square rather than round
    /wk minimap size 180         120 to 300, how wide the map is drawn
    /wk minimap buttons on|off   collect the addon buttons behind one square
    /wk minimap scan             look for buttons that appeared since login
    /wk minimap list             what the corral holds, and what it left as pins
    /wk map                      open the world map
    /wk map on|off               the addon's world map instead of the client's
    /wk map hide on|off          Blizzard's map in the attic, and M opens this one
    /wk map zones                how many zones the client names, and how many have a level
    /wk map markers              whether Questie is answering for the markers
    /wk map turnins [name]       where the question mark went for a finished quest
    /wk map group                whether the client will say where your group is
    /wk map places               every kind of place Questie can draw, and which are on
    /wk map places Innkeeper on  one of them switched, in Questie and on both maps
    /wk destroy                  the clutter window, one quest item at a time
    /wk ui                       what is baked in, and whether Edit Mode answers
    /wk ui save                  capture the active Edit Mode layout
    /wk ui apply                 import the baked layout and make it active
    /wk ui auto on|off           import it on a client that does not have it
    /wk scale                    every screen, what it is drawn at and what it costs
    /wk scale map 0.8            one screen, 0.5 to 3 in tenths, refused off a step
    /wk mail                     the mail window, at a mailbox
    /wk mail on|off              the addon's window instead of the client's
    /wk mail hide on|off         move Blizzard's own mail frame out of the way
    /wk mail fav Aria            put a name on the quick list down the left
    /wk mail unfav Aria          take it off again
    /wk mail favs                the list, and who each of them is
    /wk mail warn on|off         whether value to a name off the list asks twice
    /wk bags                     the bag window
    /wk bags on|off              one window with your bags in piles
    /wk bags hide on|off         take the client's nine bag calls, so B opens this
    /wk bags columns 10          how many squares across, 6 to 16
    /wk bags count               how many slots you have and how many are free
    /wk dungeons                 the dungeon log
    /wk dungeons on|off          the window and the key that opens it
    /wk dungeons key SHIFT-L     which key opens it, override binding only
    /wk dungeons key none        hand that key back
    /wk dungeons book            how many dungeons, bosses and drops it holds
    /wk dungeons maps            whether this client has a map for each dungeon
    /wk dungeons seen            what your own runs have added to it
    /wk dungeons forget          throw the boss positions and learned drops away
    /wk character                the character sheet
    /wk character on|off         the addon's sheet instead of the client's
    /wk character hide on|off    Blizzard's own in the attic, and the C key
    /wk character gear           what you are wearing and how worn it is
    /wk character stats          your hit, and what you still miss with it
    /wk character skills         which weapon skills are behind the cap
    /wk loadout                  every loadout, its key and the pair it draws
    /wk loadout 2 SHIFT-2        the key for that loadout, or none to clear
    /wk loadout add Sword        a new one
    /wk loadout combat on|off    whether the weapon swap fires mid fight
    /wk console                  the console page, under Under the hood
    /wk console xp               a probe: the experience readings, in chat
    /wk console rail             a probe: the experience rail's frame, and what is over it
    /wk console run <lua>        one line of Lua, and what it printed, in chat

**The key field takes mouse buttons.** `ui.KeyField` maps left and right onto
`BUTTON1` and `BUTTON2` so a modified click can be captured, which is the whole
point of the marking keys. An unmodified click still cancels the capture,
because clicking away from a field you opened by accident has to stay possible
and a bare `BUTTON1` binding would be refused anyway.

Keybindings live under Key Bindings > WarriorKit and mark whatever you hover,
falling back to your target when you hover nothing. The two mouse buttons
`Keys.lua` claims are override bindings and never appear in that panel, the same
as the charge key. Charge is bound separately with
`/wk bind`, because a secure action needs a click binding rather than a
Bindings.xml entry. It will not appear in the Key Bindings panel, which is the
point: it is an override, not an entry in the set the panel saves.

## Verifying a change

Nothing here can run the game's API. What it can do is run the addon against a
stub of the API, which is a weaker claim and a much better one than syntax
alone. Everything runs from one script:

    ./check.sh

It does seven things and exits non-zero on any finding. The bar is zero warnings
and zero errors.

1. Loads every `.lua` under the addon through lua5.1. It walks the tree with
   `find` rather than a glob, because a glob stopped covering the files the
   moment they moved into folders.
2. Checks the TOC both ways: every file it lists exists, and every Lua file in
   the tree is listed. A file nothing loads is not gated by anything, and a file
   left behind by a refactor still reads like live code. The match is
   line-exact, so `Core.lua` does not satisfy `Core\Core.lua`.
3. Checks that every TOC agrees with every other TOC on `## Version`, `## Title`
   and `## Notes`, and that the version they agree on is the one `ns.version`
   declares in `Core/Core.lua`. Interface is deliberately not compared, because
   differing is the whole point of having two files. These drifted once already,
   the TOCs saying 1.1 while Core said 1.2, and nothing anywhere could tell.
4. Checks that every saved variable table a TOC declares is one some Lua file
   actually touches. An undeclared table is not saved at all, and the symptom is
   settings that vanish on logout rather than an error.
5. Bans writes and allocation on ticker paths, described under Ticker
   discipline above.
6. Caps how long a file may be. 800 lines in general, and four files carry
   their own ceiling set at what they measure today, each with a one-line reason
   and the split it would take. The ceiling fails in both directions: a file that
   grows past it fails, and a file that shrinks below it fails until the number
   comes down with it, which is what makes it a ratchet rather than a licence.
   The addon had gates on allocation, on TOC parity and on version drift, and
   nothing at all watching a file reach nineteen hundred lines.
7. Runs `scripts/harness.lua`, which loads every file in TOC order against a
   stub of the client, puts two nameplates up, drives the enemy bars ticker and
   then asserts the things reading the source cannot settle: that the grid
   resolves to one unit per pixel on a screen that is not 768 tall, that a
   widget's geometry is a whole number of pixels once the client's fractional
   measurements have been through it, that the icon crop lands on a texel
   boundary, that the driver was told how much room a bar wants, and that fifty
   ticks stay under the allocation gate. Those gates are ratchets: each sits
   just above the current figure and the next improvement lowers it in the same
   commit. The bars' gate went in at 5.0 covering 4.10, then 0.5, then 0.25, and
   is 0.05 now that the tick no longer rebuilds the raid to find out who is in
   it. It also gates `ns.UI.Flow` on its own, nine layout shapes read back off
   the offsets the engine wrote, before anything built out of it is touched.

   It also stands up stubbed `PlayerFrame`, `TargetFrame` and `TargetFrameToT`,
   runs the skin against them, and asserts that the blocks the addon owns are on
   the grid and whole, that both gauges are pinned to their rails, that the
   badge widths are even, and that the tick writes neither a bar fill nor a crop
   it has already written. It asserts the fit in screen space, which is the only
   space the block and the unit frame share: each frame covers exactly the piece
   of screen its block does, target of target is parked under the target block,
   and turning the skin off hands every frame back the size the stub built it
   and target of target back its own anchor.

   The chain is measured between the blocks rather than inside one, because a
   distance between two frames on two different scales is the thing the link
   can get wrong. What is asserted is the mirror stated as the thing you can
   see: the midpoint of the two facing edges is the middle of the screen, at UI
   scale 0.65, 1 and 0.5. The stub parks the player right of centre on purpose,
   so a pair anchored a fixed distance apart fails all three. Target of target
   is three pixels under the target block at the same three scales, which is the
   sweep that caught its offset being converted once and left on the old grid.
   Level 0 puts both block tops on one Y and level 24 puts the target 24 pixels
   below, because zero on its own is also what a link that dropped the vertical
   offset would produce. A drag is stood up the way Edit Mode drops one, on an
   absolute point of its own rather than on our anchor, so the level has to come
   back out of two measured edges: dropped 77 across and 33 down, `/wk skin
   level` reads 33 and the 77 is undone by the re-anchor putting the frame back
   on the mirror line. One check asserts `skinGap` is still absent from the
   settings, so the distance across cannot quietly become a number again.
   Turning the link off hands the target frame back the exact point the stub
   gave it, and turning it on inside lockdown writes nothing at all and finishes
   at `PLAYER_REGEN_ENABLED`.

   For that last pair the stub had to grow two things it had done without.
   `PlayerFrame` and `TargetFrame` now carry a point each, deliberately not on
   one line, because a restore has nothing to prove against a frame that never
   had an anchor and "both tops on one Y" is free if they started that way. And
   `GetLeft`, `GetRight`, `GetTop` and `GetBottom` resolve through the chain of
   anchors a frame was given rather than answering nil. What that models is one
   anchor per frame, which is what this addon writes; a frame sized by two
   opposing anchors is outside it, and the origin is the top left of `UIParent`
   rather than the bottom left of the screen, so it answers differences
   faithfully and absolutes on an offset.

   Two things the skin got wrong on the live client are gated there now. The
   stub records a texture's draw layer, which it used to drop, so the order that
   decides what a gauge looks like is asserted rather than assumed: the spent
   track and the heal slice are regions of Blizzard's bar and the layers run
   track, slice, fill. The old assertion compared two frame levels and passed
   while the target drew at 28 percent of its colour, because a level read back
   is the number the addon asked for and not the one the client used. And the
   stub stands up the head of each aura row, anchored the way the client anchors
   it, so the tail on the target frame is asserted from both sides: no tail
   before an aura has been seen, the block plus the client's lift after one, the
   row's own anchors untouched, and the mouse region stopping at the block.

   It opens the options window and walks it: every rail entry, every tab under
   it, every row on every tab. It asserts that the window is on the grid and
   sized in whole pixels, that no row is fractional, that no row is shorter than
   the wrapped text inside it, that exactly one section of a page is visible at
   a time, and that a section past the viewport turns the scrollbar on and one
   that fits turns it off with no stub left behind. The text engine it measures
   against is a model, not the client's: 0.42 em per glyph and a line box of the
   font size plus two. It has the one property the layout depends on, which is
   that a longer string in a narrower box is more lines, and it proves nothing
   about where the game breaks a line.

   Two behaviours are asserted rather than described. Which bar is yours, in all
   four states, including the one that gets lost in a refactor: with nothing
   targeted every bar is bright. And a resolution change that lands in combat,
   where a protected block holds its scale and takes the new one at
   `PLAYER_REGEN_ENABLED` while an unadopted frame moves straight away.

   The swing timer is driven through a fight rather than measured standing
   still. A stranger's swing is refused, your own starts the clock, a dodge
   restarts it the way a hit does, and the off hand flag is fed in from both
   the subevent that carries it in slot 21 and the one that carries it in slot
   13, so a parser reading one index for both fails here. Flurry lands at the
   halfway mark and the assertion is that 1.7 seconds of a 3.4 second swing
   becomes 1.2 seconds of a 2.4 second one rather than a bar that jumps
   backwards. The Slam band is asserted as pixels: a 1.5 second cast less five
   points of Improved Slam against a 3.4 second swing puts the press at 70
   percent of a 180 pixel bar, the band is two tenths of a second wide either
   side of it, and the gauge flips colour on the tick the fill reaches it and
   back on the tick it leaves. Then a completed Slam restarts the swing, a
   cast from 5000 to 6200 milliseconds replaces the estimate with 1.2 seconds,
   and the band moves with it.

   The buff nag is driven through a character who is missing things. A bare
   main hand is noticed and a sharpened one is not, a shield in the off hand is
   never nagged about and a weapon in it is, Battle Shout falling off turns its
   entry on and a hunter is never told to keep it up, and a fully buffed
   character is shown no row at all. `GetWeaponEnchantInfo` is stubbed in both
   its shapes, six returns and eight, and the off hand is read in both: on the
   eight value shape the main hand's enchant id sits exactly where the six value
   shape puts "the off hand has an enchant", so a stride read wrongly fails here
   rather than reporting an enchanted off hand forever on somebody's client. The
   racial half asserts that an orc gets Blood Fury and a troll gets Berserking,
   that a dwarf's Stoneform is never nagged about, that off cooldown in combat
   draws the square and pressing it takes the square away, that a global sweep
   does not count as having pressed it, that the square pulses and stops pulsing
   with the setting, and that fifty ticks with the clock moving stay under the
   allocation gate.

   The per-entry switches are driven with both hands bare, because the failure
   worth catching is not that the switch works, it is that it works on one
   entry. Switching the main hand off has to silence the main hand and leave the
   off hand drawing. A switched-off entry has to be absent from the list the
   tick walks, which is the assertion that fails against the two cheap wrong
   versions: a square hidden on the tick, and an entry tested on the tick with
   the answer thrown away. It has to be absent from the counts as well, so the
   status line cannot report squares nobody can see. It has to land in
   `WarriorKitCharDB` and not in `WarriorKitDB`, and it has to survive a
   modelled reload, where the saved table is handed back as a fresh copy and the
   entry is still off. Fifty ticks with an entry switched off are held to the
   same allocation gate as the racial half, because rebuilding the watched list
   once a tick is the obvious way to write the filter and would show up here
   rather than as a stutter somebody reports six weeks later.

   The tooltips are asserted by reading back what `UI/Tooltip.lua` drew, which
   is where they go now rather than into the stub's `GameTooltip`. Hovering a
   square
   has to name that square, carry the sentence the caption had no room for, and
   name the switch that silences it. The racial's has to name the racial and say
   how many seconds it has been off cooldown. A square takes the mouse while the
   row is locked and drawn, a hidden square does not, and unlocking hands the
   mouse back so the row can still be dragged.

   The reaction windows are driven through the same stubbed log. A slot holding
   Overpower reads `reaction` with nothing having dodged you, `ready` the moment
   a dodge arrives, and `reaction` again once five seconds have passed. A
   stranger's dodged swing does not open it, a parry does not open it, pressing
   the ability shuts it, and combat ending shuts both. Revenge is driven off a
   full block, a partial block on `SWING_DAMAGE` and a partial block on
   `SPELL_DAMAGE`, which are three different slots for the same fact, so a
   parser reading one index for all of them fails here. Where the rungs meet is
   asserted too: a real cooldown outranks a shut window and a shut window
   outranks the wrong stance, and an open window hands the wrong stance back so
   the square can say to swap. On the hunter run nothing is registered, a dodge
   opens nothing, and an Overpower square reads `ready`.

   All of that passed while the feature was unusable in game, so a second
   section asserts the two things a person actually sees. No assertion here can
   prove that a bar looks smooth, because smooth is a property of a screen and
   an eye and the stub has neither. What is asserted instead is the property
   that leaves the client nothing to be blamed for. The fill is driven across a
   whole swing one frame at a time, at 60 fps and again at 144, and three things
   have to hold on every frame with no tolerance allowed: the drawn position
   equals elapsed over duration times the width exactly, the value changes on
   every frame with no frame repeating the one before it, and every step is the
   same size as every other, which is what constant velocity means. A fourth
   assertion is the positive form of the second pixel rule, that the fill really
   does land between pixels, so that reintroducing a round is a failure rather
   than a silence. Then five Slams are
   cast in a row, each declaring a different length, and the press mark has to
   stay on the same pixel through all of them, through an aura event that moved
   no speed, and through readings that are refused for being longer than the
   spell or for rounding away to nothing. What is allowed to move it is asserted
   as the invariant it comes from: at 3.4, 2.4 and 1.6 second swings, and across
   a proc that lands mid swing, the moment the fill reaches the mark is the
   moment the swing has exactly a cast time left to run.
8. Holds the harness to the shape it was split into. No file over 800 lines
   or 40 names at chunk level unless it carries its own ceiling and a reason,
   both ratcheting in each direction, and the runner's section list has to
   match what is on disk. This one is here because the harness was a single
   file of eleven thousand lines that had reached a hundred and seventy one
   chunk locals against Lua 5.1's ceiling of two hundred, and the only thing
   watching that number was a comment asking the next author to be careful.
   The worst file declares fifty eight now.
9. Runs luacheck over the tree.

`scripts/harness.lua` is the command. The harness itself is the directory
beside it. `harness/client/` is the stub of the client, one file per part,
loaded in the order `client/init.lua` lists. `harness/sections/` is the
questions, one file per subject, in the run order `harness/runner.lua` lists.
That order is load bearing: sections leave state behind on purpose, and
anything one hands to a later one goes through `H.carry` and is named at both
ends. Naming a section stops the run after it, with everything above it still
running, which is the smallest run that can answer for that section:

    lua5.1 scripts/harness.lua src WARRIOR 12-debuff-square-size

The harness runs twice, and the second run comes up as a hunter:

    lua5.1 scripts/harness.lua src HUNTER

Two parts of the addon are warrior only, and both decide it once at
`PLAYER_LOGIN`, so a decision that has already been taken cannot be reached by
flipping the class afterwards. The second run is the only way to assert that
the charge button and the world marker were never built, that the key was
refused rather than accepted and dropped, that the Charge page is one sentence
instead of four tabs of dead controls, and that `SoftTargetEnemy` came out of
the run holding the value it went in with. Every check in that section is
written against the class the run is, so it gates both directions: the warrior
run proves the same things were built.

Every other part is asserted again on that run, which is the point. A part
that quietly needed a warrior fails in `check.sh` rather than in someone's
game. The skin's colour checks are the only ones that had to learn about it,
because the player's health bar carries the player's class colour.

The harness is not a client. Every API in it answers what that file says it
answers, so a stub that returns the wrong thing is a test that passes and a
client that does not. It proves the code runs and the arithmetic lands; it
proves nothing about whether the game agrees.

The harness is one Lua chunk, and Lua 5.1 gives one function two hundred
locals. That is a real ceiling: pass it and the file does not load, with
`main function has more than 200 local variables` and no tests run at all. Two
features merged in the same week each freed a single name by folding gates into
a table, and the merge of the two hit the ceiling anyway. Late sections are
wrapped in `do ... end` now, which hands every name in a section back at its
`end`. Wrap a new section the same way unless something after it reads a name
that section declares.

Add any new global you touch to `read_globals` in `.luacheckrc` rather than
silencing the warning, and if you ever need an `ignore` entry, write the reason
above it the way the `211/ADDON` entry does.

luacheck came from luarocks rather than pacman, so it lives in the user tree:

    luarocks install --local --lua-version 5.1 luacheck

## Confirmed on the live client

Answered by running it on Tusksfirst, 2.5.6.69110, and reading `/wk status`.
Each of these was a guess in the list below until then.

- **Bar 1 pages by stance for a warrior.** `Layout.Bar1Bases` read
  `ActionButton1.action` as 73, which is bonus bar page 1, and derived 85 and 97
  from the twelve slot stride. `/wk status` says "three stance pages from slot
  73". The whole shape of `Layout.BAR1` rested on this.
- **Edit Mode carries all five methods.** `EditMode.CanApply` probes
  `GetActiveLayoutInfo`, `GetLayouts`, `SelectLayout`, `ImportLayout` and
  `SaveLayouts` by name and answered true, so the interface status line printed
  its full form. Titan only ever proved the first one.
- **The bar art names are real.** `/wk status` says "stripped 9 regions". Zero
  was the answer that would have meant this client calls the art something else.
- **`GetCVar` answers for `SoftTargetEnemy`.** `softPrior` recorded a value read
  off the live client, and the charge status line reports what the CVar says.
- **Nothing raises.** Six parts running, `Logs/General.log` empty across the
  session.

Still open from that run: `token unproven`, so `softenemy` has not resolved yet.
Aiming at a mob out of combat with no target selected is the whole test.

## Untested against the live client

Everything below was written from the API contract and has never executed:

- **Whether one frame can carry every tick that never stops.** `UI/Ticker.lua`
  builds a frame of its own and the eighteen parts that used to keep one each
  hang off it. That frame has no parent and is never hidden, which is what all
  eighteen were, so the game should call it the way it called them. The harness
  cannot answer this one: its stub parents every frame to UIParent, so nothing
  in it is parentless. A mistake looks like the whole addon standing still from
  the moment you log in, with the bars, the enemy bars, the cast bar and the
  swing gauges all frozen together and the windows still opening. What would
  settle it: log in and watch a swing bar fill, or `/wk perf`, where every slot
  counts the ticks it has had.
- **Whether the first press of `/wk` is a noticeable pause.** The settings
  window is no longer built at login: the first thing that opens it makes the
  whole of it, which is about a thousand frames, eighteen hundred textures and
  one reading of every row on the page it lands on. Login is that much quicker
  and the cost moved rather than went away. A mistake looks like a hitch of a
  frame or two on the first `/wk` of a session, worst mid-pull, and nothing at
  all on every press after it. What would settle it: `/wk perf`, then `/wk`
  from a standstill and again during a fight.
- **Whether a row on a page you are not looking at can go stale.** A row is put
  back in step when its page comes up and at no other time, so a setting
  changed by a slash word while the window sits on another page is read when
  you click over to that page. A mistake looks like a number in the window
  disagreeing with what `/wk status` says, and correcting itself the moment you
  leave the page and come back. What would settle it: open the window on one
  page, change something with a slash word, then click to the page that shows
  it.

- **Whether `hooksecurefunc` takes on a Blizzard frame's `SetParent`.** It is
  what replaced the once-a-second parent check: `Core/Attic.lua` hooks the call
  on every frame it cages, and the walk that used to catch a foreign re-parent
  now runs every five seconds behind it. The hook is probed and pcalled, so a
  client that refuses it loses nothing but the speed. A mistake looks like one
  of Blizzard's frames back on the screen for up to five seconds after something
  moved it, where it used to be one. What would settle it: `/wk hide probe` with
  the switches on, which says ON SCREEN against any name a switch asked to hide.
- **Whether `SPELL_UPDATE_COOLDOWN` and `SPELL_UPDATE_USABLE` fire on 2.5.6.**
  The wiki lists both for this build and no addon on this machine registers
  either, so they are read off the contract. `Charge/Charge.lua` marks its
  answer stale on them, and the charge icon and the world marker only ask the
  client again once something has. A mistake looks like the charge square
  keeping its colour through a cooldown ending or through a rage bar filling,
  and clearing the moment you change target. What would settle it: charge
  something, then watch the square while the cooldown runs out.
- **Whether the charge marker still tracks range while you run.** Range is the
  one thing the client announces nothing about, so it is polled on the tick
  while the last answer was ready or out of range, and every other status waits
  for an event. A mistake looks like the marker staying red after you close the
  distance, or staying green while you back away.
- **Whether the addon comes off COMBAT_LOG_EVENT_UNFILTERED with every reader
  switched off.** The harness proves the subscriber list empties and that the
  stub holds no registration, but the stub is the addon's own model of
  RegisterEvent and UnregisterEvent rather than the client's. A mistake looks
  like a meter that counts nothing after its switch has been off and on again,
  or a swing bar that never arms, both of which are the event never coming
  back. What would settle it: turn the meters, the breakdown and the swing bars
  off, pull something, then turn the meters back on and pull again and read the
  meter.
- **Whether the seven events the action squares now repaint on cover
  everything they used to poll for.** The squares are drawn on
  `ACTIONBAR_UPDATE_COOLDOWN`, `ACTIONBAR_UPDATE_STATE`,
  `ACTIONBAR_UPDATE_USABLE`, `ACTIONBAR_SLOT_CHANGED`, `SPELL_UPDATE_USABLE`,
  `UPDATE_SHAPESHIFT_FORM` and `PLAYER_TARGET_CHANGED`, read off Blizzard's own
  ActionButton, and only range, the stack and a running countdown are still
  read on the tick. Two of the seven are events this client's own button has
  stopped registering in favour of a per-slot subscription, so a build that has
  also stopped sending them would leave a square stuck: an Overpower that stays
  grey after the rage arrives, or a stance swap that does not recolour bar 1.
  What would settle it: stand still with a target, gain rage from nothing but
  auto attack, and watch whether a square you cannot afford lights the moment
  you can.
- **Whether `UNIT_HEALTH` is what a warrior's Execute square comes in on.**
  `Buttons/Requires.lua` reads the target's health off that event now rather
  than off the bar's tick, and raises the squares' bit only when the answer
  crosses the fifth. A mistake looks like an Execute that stays grey below 20%
  until something else redraws the bar. What would settle it: pull anything and
  watch the square at the moment the health bar crosses a fifth.
- **Whether every ticker still runs at the rate it asks for.** `ns.UI.Ticker`
  replaced twelve hand-written accumulators, and nine of the twelve zeroed
  theirs where the shared one subtracts the interval. Those nine were running
  slightly slow and now run at the rate they name, which is a change to the
  buff row, the cooldown row, the party blocks, the skinned frames, the meter,
  the action squares, the charge icon, the charge marker and the Blizzard
  hider. Nothing on screen should look different; what would show a mistake is
  a row that has stopped moving, or the performance tab reporting a tick count
  well off the interval beside it. What would settle it: `/wk perf` with a
  target up, and read the ticks per second against each rate.
- **Whether the client fires UNIT_HEALTH, UNIT_AURA, UNIT_THREAT_LIST_UPDATE
  and UNIT_TARGET for a `nameplateN` token.** The enemy bars register all four
  against the plate's own unit when a bar attaches and redraw that bar on the
  next frame when one arrives. Nothing installed here proves any of the four
  reaches a nameplate token, and the same doubt is already written down for the
  cast events on the same frames. A client that fires none of them draws every
  bar off the reading that runs once a second instead, so a mistake looks like
  health, debuff squares and the threat number all stepping once a second while
  the cast fill under them stays smooth. What would settle it: pull one mob,
  watch its health bar, and see whether it slides or steps.
- **Whether Core hears UNIT_AURA before the buff row and the cooldown row do.**
  Both rows read your own buffs off one walk in `Core/Core.lua` now, and that
  walk runs again on the first ask after the event marks it stale. Core's frame
  registers the event first because Core is the first file in both TOCs, and the
  client is taken at its word that a frame which asked first is handed the event
  first. A mistake looks like one of the two rows being one aura event behind:
  a sharpening stone square that clears when the next buff lands rather than
  when the stone goes on, or a cooldown square that keeps its running border for
  one aura longer than the buff was up. What would settle it: shout, and watch
  the Battle Shout square clear on the shout rather than on the next thing that
  buffs you.
- **Whether UPDATE_MOUSEOVER_UNIT fires again for a creature you are already
  pointing at.** The world hover turns away a second event about the creature
  its box is already open on, because rebuilding is a scan of Blizzard's
  tooltip, every band laid out again and the suppression armed on top of the box
  it is already holding. A mistake looks like the box freezing over a mob that
  is moving: the threat line stuck at what it read when the box opened, and the
  box left where the pointer was rather than where it is. What would settle it:
  hover something that is running at you and watch the threat percentage.
- **Whether the client fires UNIT_HEALTH, UNIT_POWER_UPDATE and UNIT_CONNECTION
  for the `targettarget` and `partyN` tokens.** The names are Blizzard's own,
  taken off the frames in `Blizzard_UnitFrame` that draw the same units, but
  Blizzard registers them for `target` and `party1` rather than for a derived
  token, and its own comment beside the compact raid frame says there is no good
  way to hear about a target's target. The skinned frames and the party tiles
  register all three against their own unit and redraw on the next pass when one
  arrives; a token the client stays quiet about falls back to the reading that
  runs once a second. A mistake looks like target of target, or a party member's
  health, stepping once a second while the target frame beside it moves five
  times a second. What would settle it: stand next to somebody losing health,
  watch their tile and your target frame together.
- **Whether `hooksecurefunc` takes on a unit frame's `SetStatusBarTexture`.** It
  is what replaced reading both of Blizzard's bars back on every pass to find
  out whether the client had put its own artwork over the flat colour. The hook
  is probed and pcalled, and where it will not install the readback stays. A
  mistake looks like the health or power bar on one of the three frames wearing
  Blizzard's rounded UI-StatusBar art under the flat colour, most likely just
  after a target change. What would settle it: change target a few times and
  look at the ends of the gauge for the soft rounded cap.
- **Whether splitting your own cast bar into two tickers still draws it.**
  `UnitFrames/PlayerCast.lua` ran one handler that polled the client at 5 Hz and
  moved the fill on every frame. It is two tickers now, timed separately as
  `playercast` and `castsweep`. A mistake here looks like a cast bar that
  appears and then does not move, or one that moves and never appears.

- **Whether either client has map art for a dungeon.** The whole middle column
  turns on it. `Dungeons/Places.lua` walks C_Map for nodes of the dungeon kind
  and binds each to a name in the book, and both halves of that are unproven:
  the walk may come back empty on a build whose map tree has no dungeon nodes,
  and a build that has them may name them differently from the book. The two
  failures look identical on the screen, which is why the reading separates
  them. What would settle it: `/wk dungeons maps`, which prints how many dungeon
  maps this client named and how many of the book's forty found one. Nothing
  raises either way; a dungeon with no map draws its bosses and its drops and a
  line saying the client has no picture for the place.
- **Whether `C_Map.GetMapGroupID` and `GetMapGroupMembersInfo` answer on these
  builds.** They are what cut a dungeon into floors, so the strip under the map
  is built out of them. Both are probed and pcalled and a client that answers
  neither gets one floor per dungeon, which for most of the forty is the truth
  anyway. The symptom of a wrong answer is a Deadmines with no way to reach
  Ironclad Cove.
- **Whether the client will say where you are standing inside an instance.**
  Every mark on a dungeon map is a reading taken off `C_Map.GetPlayerMapPosition`
  at the moment you open a boss's loot window. Instances are the one place that
  call has historically answered nothing, and if it answers nothing here the
  window is a dungeon map with no marks on it for the life of the install. What
  would settle it: run any dungeon, loot the first boss, and `/wk dungeons seen`.
  It reports bosses placed and drops learned separately, so a client that
  records the drops and no position says so in the first number.
- **Whether `C_Item.RequestLoadItemDataByID` exists on 2.5.6.** It is what warms
  an item the client has never cached, which on the first open of a dungeon is
  most of the right hand column. Probed, and a client without it draws every row
  from the book's own name in the quiet colour and fills them in as the client
  loads the items for any other reason. Slower, not wrong.

- **Whether `ContainerFrameItemButtonTemplate` takes on these builds and behaves
  once it has.** Every square in the bag window inherits it, which is what makes
  the click, the drag, the stack split and the merchant sale the client's own
  code rather than a reimplementation of five different meanings of a right
  click. Baganator builds its classic squares on the same template on this
  install, so it is there; what is unproven is that a button of it works parented
  to a frame this addon made rather than to a container frame the client built.
  What would settle it: `/wk bags`, then right click a grey at a merchant. A
  template this client refuses is caught and reported rather than raised, and
  `/wk status` says so in the words "this client refused the bag button
  template". The same is true one layer down of `ContainerFrame_UpdateCooldown`,
  which is the only call that draws the swirl over a potion you just drank: it is
  probed and pcalled, and one refusal takes it off for the session, so the
  failure is a square with no swirl rather than an error per slot per bag
  update.
- **Whether stripping the template's own regions leaves the square drawable.**
  The icon, the count, the quality border, the quest texture and the normal
  texture are all put down with `ns.Strip` and the square is drawn again in this
  addon's palette. Which of those five a build carries differs across clients, so
  each is probed by name and a missing one is skipped. The failure that would not
  raise is the opposite: a region this file does not know the name of, still
  drawn, leaving Blizzard's gold border around a flat square. Looking at the
  window is the whole test.
- **Whether taking all nine bag calls is enough to keep the client's bags off the
  screen.** `Bags/Blizzard.lua` replaces `ToggleBackpack`, `ToggleAllBags`,
  `ToggleBag`, `OpenAllBags`, `OpenBackpack`, `OpenBag`, `CloseAllBags`,
  `CloseBackpack` and `CloseBag`, on the argument that the client never shows a
  container frame except through one of them. If a build has a tenth, the symptom
  is Blizzard's bags appearing beside this window at a merchant or a bank.
  `/wk bags count` and `/wk status` both report how many of the nine this client
  carries; nine of nine and a bag still opening is the tenth call.
- **Whether the once-a-second re-take fights another bag addon.** Baganator and
  Bagnon take the same nine names. Whichever addon writes them last holds them,
  and this one writes them every second, so it wins and their hook is dropped
  from the chain. That is the intended behaviour and it is also the reason the
  panel says to run one or the other. What is unproven is that nothing worse than
  that happens with both installed.
- **Whether `C_Item.GetItemClassInfo` answers on these builds.** The pile headers
  are the client's own word for each item class where it will say one, so the
  window reads in the language the client is in. A build with no such call draws
  the English fallbacks and nothing else changes. `/wk bags count` does not report
  this; the headers themselves are the test.
- **Whether `C_Map.GetMapChildrenInfo` walks the whole world on these builds.**
  The world map's zone column is a walk over the client's own map tree rather
  than a list written down, climbed from the map you are standing on to whatever
  has continents under it. Both clients draw their own world map through the
  modern map canvas, and Questie calls `WorldMapFrame:SetMapID` unguarded on
  this install, so the tree is there; what is unproven is that asking for every
  descendant of one kind answers on 2.5.6 the way it does on the build this was
  written against. What would settle it: `/wk map zones`, which prints how many
  zones over how many continents. Zero of either is the failure, and it draws an
  empty column and a line saying so rather than raising.
- **Whether the level ranges are keyed on the map ids these clients use.**
  `Map/Zones.lua` carries the one table in the addon the client cannot answer
  for, because no call on either build has ever said what level a zone is for.
  The ids are read off Questie's generated `areaIdToUiMapId` rather than typed,
  and `/wk map zones` prints how many of the zones the client offered have a row
  in it. Every zone but the battlegrounds and the instances should have one; a
  count far short of that means the ids are the wrong set, and the symptom is a
  footer that says no level range is known rather than a wrong number.
- **Whether Questie's icon frames read the way this addon reads them.** The
  markers on the map are Questie's own frames, walked out of
  `QuestieMap.questIdFrames` and `QuestieMap.manualFrames` and filtered on
  `UiMapID`, `miniMapIcon` and Questie's own `hidden` flag. Every field is read
  off the installed copy of Questie 11.37.1 and type checked at the call site, so
  a Questie whose internals moved draws fewer markers rather than raising. What
  is unproven is the count: `/wk map markers` says how many Questie is holding,
  and a map with none on it where that number is large is the failure.
- **Whether a tick on the Places page makes Questie draw.** The page is built
  out of `QuestieMenu.buildTownsfolkMenu`, `buildVendorMenu` and
  `buildProfessionMenu`, the three lists Questie's own dropdown is built from,
  and a tick calls the `func` on the entry, which is what a click in that
  dropdown calls. Read off the installed 11.37.1 and pcalled, so a Questie whose
  menu moved shows a page with one line on it saying so. What is unproven is
  the round trip: tick Innkeeper, open the map on a town, and the innkeeper is
  on it; open Questie's own dropdown and Innkeeper is ticked there too. A kind
  of NPC is spawned by Questie over a few ticks, so a map that is already open
  when the box is ticked shows it on its next repaint rather than on the click.
  `/wk map places` prints what Questie says it has on.
- **Whether `C_DeathInfo.GetCorpseMapPosition` answers on these builds.** Your
  corpse is on the map because that call says where it is, asked against the map
  being drawn so the skull lands on the continent picture as well as on the zone
  one. It is the call Blizzard's own corpse pin makes on this client, in
  `Blizzard_SharedMapDataProviders`, and it is probed and pcalled here like every
  other reach into the client. Two failures, and they look alike from the sofa: a
  build that answers nothing draws no skull, and one that answers a zeroed vector
  where it means "no corpse" would draw one in the top left corner of every zone,
  which is why the corner is refused. What would settle it: die, release, open
  the map.
- **Whether the skull comes out of `Interface\Minimap\POIIcons` at that cell.**
  The art and the crop are read off Blizzard's own `CorpsePinTemplate` for this
  client, which draws the last eighth of the sheet's top row at twenty four
  pixels scaled to eight tenths. A wrong cell is a different icon at nineteen
  pixels and a lost crop is the whole sheet squeezed into a grey smudge, so both
  failures are a mark in the right place that does not read as a skull.
- **Whether the drag pans the picture rather than the window.** A drag on the
  board pushes the map under its box while the zoom has left the picture bigger
  than the box, and is handed up to the window otherwise, so which of the two
  happens is decided by the zoom and nothing else. The tick that follows the
  cursor runs only while the button is down. What would settle it: open the map,
  zoom in, drag. The failures are a window that walks off the screen when you try
  to read the far side of a zone, and a map at rest that has stopped being a
  place you can drag the window from.
- **Whether caging `WorldMapFrame` costs Questie anything.** Questie hands its
  icons to HereBeDragons to place on the client's map, and a map that is never
  shown is a map those pins are never placed on. The frames themselves are made
  when your log changes and unmade when a quest is done, neither of which has
  anything to do with a map being on screen, which is why the markers survive
  the cage. What would settle it: pick a quest up with `map hide` on, open this
  window, and check the marker is there. `/wk map hide off` puts the client's map
  back and hands the M key over in one word.

- **Whether the miss numbers on the character sheet are the game's.** The
  formula reproduces the three figures everybody quotes, 5.5%, 6% and 9% at one,
  two and three levels up, and the harness holds it to all three. What the
  harness cannot answer is whether those three are right for these builds, and
  whether the client's weapon skill, defence and rating calls feed it what this
  addon thinks they do. What would settle it: stand at a target dummy three
  levels up with a known amount of hit rating, swing a few hundred times with the
  combat log on, and compare the miss count against the row. Nothing about this
  page is destructive if it is wrong; it is a number that would be quietly out by
  a percent or two.
- **Whether `GetCombatRatingBonus` is the whole of your gear hit on 2.5.6.** The
  page says out loud that talent hit is not in it. What it assumes is that
  everything else is, and an enchant or a set bonus that granted hit chance
  rather than hit rating would be missing from the row with nothing saying so.
- **Whether the nineteen slot numbers and `GetInventorySlotInfo` key names match
  these builds.** A wrong number draws an empty square in a slot you are wearing
  something in, and a wrong key name draws a square with no silhouette in it.
  Both are visible at a glance and neither is destructive. `/wk character gear`
  prints the item level, the durability and how many slots came back empty, and
  an empty count that is too high is the symptom.
- **Whether `PickupInventoryItem` and `UseInventoryItem` behave from this
  window.** Both are what FrameXML's own paperdoll button calls, both are refused
  in combat before they are reached, and neither has run from a frame this addon
  owns. The failure worth watching for is a click that picks an item up and
  leaves it on the cursor with nowhere obvious to put it back.
- **Whether `CharacterFrame` and its five pages go into the attic cleanly.** The
  harness cages a stub. What a live client may do that the stub does not is call
  a method on a caged page from its own `OnUpdate`, which is exactly what the
  target's cast bar did and what `mute` exists for. `/wk hide probe` names every
  frame and says whether it is on screen anyway, and `/wk character hide off`
  hands the whole thing back.
- **Whether the pet sheet and the honour tab are reachable any other way.** With
  the switch on, `ToggleCharacter` sends both to a printed line. If some other
  path on these clients opens either of them directly, it opens a caged frame and
  draws nothing at all.
- Whether `IsUnitOnQuest` exists on these builds and takes its arguments in the
  order this addon passes them, which is a row of your own quest log and then a
  unit token. `Quests/Party.lua` treats a missing or raising call as "cannot
  say" and falls back to what Questie's comms has heard, so the failure is a
  smaller number rather than an error. What it cannot catch is a call that
  exists, takes its arguments the other way round and answers false to
  everything: that reads as nobody in the group being on any quest, which looks
  exactly like a party with nothing in common. What would settle it: stand in a
  party on a shared quest, open the log, and check the number on the row against
  who is actually on it. `/wk quests party` says which of the two sources is
  answering.
- Whether the tick and the share arrow drew. Both are new letters in
  `Media/Glyphs.ttf`, cut onto `V` and `s` by `scripts/bake-glyphs.sh`, and the
  subset's cmap is rewritten to exactly the letters it bakes. A letter with no
  mark on it draws an empty rectangle and says nothing at all, at load, at lint
  or in the harness. `scripts/check.sh` compares the alphabet in `UI.GLYPHS`
  against the bake script and 47-quest-log checks the marks the window draws are
  in that alphabet, which is as far as anything short of the client can go. What
  would settle it: open the log and look at a quest you can hand in.
- Whether replacing `QuestieTracker.utils:ShowQuestLog` holds on the Questie
  that is installed. The function was read off Questie 6.3.11 for TBC, where the
  tracker's click handler and the "Show in Quest Log" line of its right-click
  menu both call it, so one swap covers both. A Questie that moved or renamed it
  leaves the swap unmade and every click going where it went before, which is
  Blizzard's log in the attic. What would settle it: click a quest in the
  tracker. The Quests section of `/wk` says whether the swap took.

- Whether the tooltip marker picks the right corner on a real screen. The
  addon reads which quarter of `UIParent` the marker sits in and hangs the box
  off the matching corner of itself, so it grows away from the nearest edge.
  The harness stub measures y downward from the top of the screen and the client
  measures it upward from the bottom, which is why `Marked` compares against
  `UIParent`'s own centre through `UI.Convert` rather than against half its
  height: that reading is the same in both conventions, and only the stub has
  ever run it. If it is wrong, a marker near the bottom of the screen grows the
  box down off the edge and the clamp drags it back over the marker. What would
  settle it: `/wk tips anchor`, `/wk unlock`, drag the marker into each of the
  four corners in turn and hover something.
- Whether `GetLootSourceInfo` exists on 2.5.6 and 1.15 and answers a creature
  GUID for a slot. It is the whole of the measured drop chance in
  `Quests/Drops.lua`: without it no corpse is ever counted, the ledger stays
  empty and a hover shows the quest and the count with no fraction under them,
  which is the same box a player with no history gets and is silent. The failure
  worth watching for is the opposite one, a call that answers a GUID this addon
  cannot parse, which is also silent and also shows nothing. What would settle
  it: kill and loot a dozen of something that carries a quest item, then hover
  another one. `/wk quests drops` says how many creatures have been counted, and
  zero after a dozen kills is the answer that means the call is not landing.
- Whether the installed Questie keys its tooltip registry the way this addon
  reads it. `Quests/Drops.lua` walks `QuestieTooltips.lookupByKey["m_<npc id>"]`
  and reads `questId`, `objective.Type`, `objective.Id`, `objective.Collected`
  and `objective.Needed` off the entries, all of it read and none of it written,
  and the shape was taken off Questie 6.3.11 for TBC. A Questie that renamed any
  of them draws no drop lines at all rather than wrong ones, because every field
  is checked before it is used. What would settle it: hover a mob that carries a
  quest item for a quest in your log.
- Whether all eighteen placeable frames still drag in the game after
  `UI/Placeable.lua` took the block over from the twelve copies that used to
  write it. The harness proves the property that broke silently before, which is
  which frames the lock reaches: twelve HUD frames lose the drag with `/wk lock`
  and get it back, six chrome windows keep it throughout. What no stub can
  prove is that `StartMoving` on a frame the client considers protected still
  behaves, and the party anchor is the one that would show it, because its
  blocks come off a secure group header and it is the only one that refuses to
  move in combat. What would settle it: `/wk unlock`, drag each frame, `/reload`
  and check every one came back where you left it, then pull something and try
  to drag the party blocks mid fight, which should refuse rather than error.
- Whether rounding the two anchors that were not rounded before moves anything
  visibly. The meters saved their offsets unrounded and now do not, and the
  chat window saves through the shared path, so both land on a whole pixel on
  the first drag after this. A frame that was sitting on a fraction moves by up
  to half a pixel once, which is the point, and then stays put.

- Whether a secure action button answers a suffixed click delivered by an
  override binding on 2.5.6. This is the whole of mouseover casting.
  `Marking/Keys.lua` proves the binding half on an ordinary button and its click
  name arrives as the mark's id, and Clique does the same thing onto a secure
  button, which is the closest thing to a proof there is here. What is not
  proven by anything installed is `type-<click>` and `macrotext-<click>` being
  read ahead of the bare pair on this build. If they are not, every hover key
  presses a button with no bare `type` set and nothing happens at all, which is
  silent. What would settle it: bind a spell, press the key over a mob, and read
  `/wk hover show`, which prints the macro off the button itself rather than the
  one the addon meant to write.
- What shape `GetCursorInfo` answers a dragged spell in on these clients.
  `Hover.Carry` tries three readings and takes the first that names a spell, so
  a client that answers any of them is covered, and one that answers none leaves
  the slot empty with a line in chat. The failure worth watching for is the
  third reading being reached on a client whose first value is a spellbook index
  rather than a spell id: that names the wrong spell, and the only thing between
  it and a wrong binding is that the name is in the slot before you press a key.
- Whether `[@mouseover,harm,nodead]` resolves inside a macro run off a click
  binding rather than off a real macro. The charge button already ships
  `[combat,@mouseover,help,nodead]` in its macro text and is the same shape, so
  the two stand or fall together.

- Whether the cooldown ids in the four class files name what this addon thinks
  they name. The warrior's four are the ones somebody here plays and are the
  least in doubt: 12292 Death Wish, 1719 Recklessness, 871 Shield Wall, 12975
  Last Stand. The other nineteen were read off Wowhead and nobody here has the
  character to check them on. The failure mode is quiet and small in both
  directions: an id this client cannot name and an id this character has not
  learned both leave no square, so a wrong number costs one square rather than
  drawing the wrong picture. What would settle it: `/wk cooldowns list` on each
  character, which prints every entry with the name this client gave it, or
  "not learned on this character" where it gave none.
- Whether Ice Block answers to 45438 on both flavours. It is the one entry
  written with two ids for one spell, 45438 and 27619, because the number has
  moved between builds and the list takes whichever this client knows. If both
  miss, a mage sees no Ice Block square and the rest of the row is unaffected.
- Whether GetItemSpell is on both clients and answers for a trinket you are
  wearing. It is what tells a trinket you press from a trinket you wear, it is
  probed through C_Item first and the loose global second, and a client with
  neither leaves both trinket squares off the row and nothing else. What would
  settle it: wear a trinket with a use effect and read `/wk cooldowns list`,
  which names the effect rather than the item.
- Whether GetInventoryItemCooldown answers for slots 13 and 14 on these
  clients. Same probe, same failure: a missing call reads as ready forever,
  which is a square that never counts down rather than an error.
- Whether the cooldown row reads at a glance at the size it ships. It draws at
  1x where the buff nag draws at 2x, and the argument for the difference is that
  this row is up for the whole fight and carries a number per square, so double
  sized squares over your character would be in the way rather than in view.
  Against that, the thing you are doing when you look at it is glancing away
  from a mob mid-pull. `/wk cooldowns zoom 2` is one command and settles it.
- Whether the priest's three upkeep ids name what this addon thinks they name.
  1243 is Power Word: Fortitude rank 1, 21562 is Prayer of Fortitude and 588 is
  Inner Fire, all matched by the name the client spells them, and the Fortitude
  square is cleared by either of its two. The one that is a guess is whether
  Prayer of Fortitude lands as its own aura name on 2.5.6 or as the single
  version's; if it lands as the single version's, 21562 resolves to a name
  already in the table and nothing is worse than it was. Nobody here plays a
  priest, so this is the one entry on the buff row written without a character
  to look at. What would settle it: buff a priest with each of the three and
  read the row.
- Which of the frame names under `/wk hide` this client actually carries.
  The mechanism is settled: a frame in the attic cannot be drawn, and
  `43-blizzard-hide.lua` proves it against the exact call that beat the last
  version. What is not settled is the naming. Every entry is probed, so a name
  these clients spell differently costs that frame and nothing else, and each of
  the two cast bars carries a FrameXML parent key as a second way in. What would
  settle it: `/wk hide probe`, which prints one line per name saying whether this
  client has the frame, whether the attic holds it, and whether it is on the
  screen anyway. Any line reading ON SCREEN is a name to add, not a mechanism to
  argue with.
- Whether `hooksecurefunc` on `DEFAULT_CHAT_FRAME.AddMessage` catches everything
  Blizzard's window would have drawn. Loot, experience and every addon's output
  should reach the System room and nothing should reach it twice. The doubling
  is the half that is argued rather than measured: it depends on the claim
  taking each conversation event out of FrameXML before `AddMessage` sees it.
  What would prove it: hide the window, loot something, and check the System
  room has the loot line and the Conversation room does not.
- Whether taking the enter key with an override binding is a good trade in
  practice. It is what the client does with `OPENCHAT` and it is dropped by one
  call, but a static popup that wanted the same key while the chat window was
  open would lose it. What would prove it: hide Blizzard's window, press enter,
  type, and then take a dialog that offers an accept button.
- Whether any of the four auction scanners answers on these clients. Each is
  probed by name and pcalled, so a scanner whose API has moved costs the auction
  line and nothing else, and a player with none of them was never going to get
  one. What would settle it: install one, scan, hover a loot row, and read the
  panel's "what an item goes for" line, which names whichever answered or says
  none did. Auctionator's modern interface is the one this file is least sure
  of on a classic realm, because `Auctionator.API.v1` is a retail-era shape and
  the classic build may only carry `Atr_GetAuctionBuyout`. Both are in the list
  and the second is tried after the first.
- Whether the seven filter chips fit the strip at every width the loot feed
  goes to. Seven squares of eleven units plus their gaps is about a hundred and
  ten, the strip is the feed's full width, and the narrowest a feed goes is two
  hundred, so the arithmetic says yes at every stop. What it does not say is
  whether eleven units reads as a square you can hit with a mouse at UI scale
  0.53, which is a thing you look at.
- Whether a row's icon at 16 pixels is still an icon. The floor is set by the
  text rather than the art and the art is the client's own 54 texel crop being
  resampled down, so a small row is legible by construction and recognisable by
  hope.

- The whole mail part. Every mail API it calls is probed by name and pcalled,
  and two of them are proved by an installed addon rather than by a run: the
  attach path is `Baganator/Transfers/AddToMail.lua`'s, which sets
  `SetSendMailShowing(true)` and then calls `UseContainerItem` on a bag slot, and
  `GetInboxHeaderInfo`'s return order is Syndicator's and Auctionator's. Proving
  a call exists is not proving the sequence around it is right, and five things
  ride on that sequence.

  Whether an attach really lands synchronously, which is what the fill loop
  assumes when it asks `GetSendMailItem` for the next free slot after every
  `UseContainerItem`. Baganator's own loop advances the same way, which is the
  argument; a client that answered a frame later would fill slot one twelve
  times. What would settle it: attach four things and watch the block, which
  draws what it thinks is on the form.

  Whether `MAIL_SEND_SUCCESS` arrives once per mail and after the form is
  empty. The state machine posts the next mail from inside that handler, so an
  event that arrived before the client cleared the slots would put mail two's
  items on top of mail one's. What would settle it: attach twenty stacks of
  anything and send. The footer counts the mails as they go and `/wk status`
  says what the last send did.

  Whether parking `MailFrame` off the side of the screen holds. It stays shown,
  so the mailbox stays open, and it is re-parked on its own `OnShow`, which is
  where the UIPanel layout would otherwise put it back. The failure mode is
  visible rather than silent: Blizzard's window turns up in the middle of the
  screen with ours over it, and `/wk mail hide off` is the way out. What would
  settle it: open a mailbox, then open and close the character sheet, which is
  what makes the client lay its panels out again.

  Whether the inbox sweep gets all of them. It counts down because taking
  renumbers, and the harness models that renumbering, but the model is written
  from the contract like everything else here. What would settle it: five
  messages with attachments, press take everything, and count what is left.

  And whether the three colours read as three colours on a dark window at UI
  scale 0.53. The contrast gate in `check.sh` measures each against the surface
  it is drawn on; it says nothing about whether green and blue are far enough
  apart to be told at a glance, which is a thing you look at.

- The whole party and raid header. `SecureGroupHeaderTemplate` is FrameXML's and
  `harness/client/09-group.lua` is a model of it written from the contract, so
  every assertion about a slot is an assertion against that model. Four things
  ride on it and none has run in the game. Whether the template exists under that
  name on 2.5.6 and on Era, which fails loudly: `CreateFrame` is pcalled and
  `/wk status` says the client has none rather than drawing nothing and saying
  nothing. Whether `sortMethod = "NAMELIST"` really places one button per name in
  the order given, which is the whole of the role ordering. Whether
  `initialConfigFunction` accepts `SetWidth`, `SetHeight` and `SetAttribute` in
  the restricted environment, which is the only snippet in the addon. And whether
  re-writing the `point` attribute makes the header arrange again, which is what
  puts a resized block back in the column it belongs in. What would settle all
  four: join a party, read `/wk status`, and change `party height` with the list
  on screen.
- Whether `UnitGroupRolesAssigned` and `GetPartyAssignment` are on these two
  clients. Both are probed by name and a missing one costs that source rather
  than raising, so the failure mode is a list ordered by talents and the class
  floor alone. `/wk party role` prints which of the four sources answered.
- Whether `Interface\LFGFrame\UI-LFG-ICON-ROLES` is on both flavours and is cut
  as a 256 square of 75 pixel cells. A path that does not resolve draws as a
  green question mark and writes nothing to the log, so this is the one thing
  here with no failure mode that announces itself. SPEC-party.md's answer if it
  turns out missing is three more codepoints in `Media/Glyphs.ttf` and a rerun of
  `bake-glyphs.sh`, which is not worth spending until somebody looks at a block
  and sees a question mark.
- Whether `CompactRaidFrameManager_UpdateShown` is what these clients call the
  raid manager's layout pass, and whether that pass is the one that re-shows the
  container. The hook is probed and pcalled, and where the name is wrong the
  symptom is loud: Blizzard's raid frames come back the first time somebody
  joins. `/wk hide` reports how many of the frames it names this client carries.
- Whether a block at 202 by 34 is the right size for a raid. The party is the
  player block repeated and that is the point; forty of them is not a screen, so
  the sizes are settings and a raid is expected to run smaller. Which numbers
  read at raid size is a thing you look at rather than measure.
- Whether the shaman's first talent tree is Elemental Combat on both flavours.
  `Unit/Role.lua` files it as damage, against SPEC-party.md, which listed shaman
  trees one and three as the ones that are not damage. Tree three is Restoration
  and is a healer; tree one is Elemental and is a caster, so following the spec
  there would have sorted every Elemental shaman into the healer band. A client
  that orders the tabs differently would put the mistake back, and `/wk party
  role` beside the icon on the block is what would show it.

- Whether the client's own aura buttons are protected on this backport, and
  therefore whether hiding one is refused in combat. `UnitFrames/Auras.lua`
  does not assume either way: it calls `ns.Strip`, which asks
  `IsProtected` and `InCombatLockdown` and returns false rather than raising, and
  the sweep retries on the next tick. If they are protected, the cost is one
  Blizzard icon visible under the block for the rest of a fight, and only the
  first time a target ever carries that many auras in a session, because the
  client builds those buttons on demand and in order. If they are not, it is
  hidden within a fifth of a second and nobody sees it. What would prove it: get
  a target to nine or more debuffs for the first time in a session while in
  combat, and watch whether one of Blizzard's icons appears below the block.
- Whether the nine `UNIT_SPELLCAST_*` names your own cast bar watches fire on
  these clients, and whether `CastingBarFrame` is what they call Blizzard's own.
  The events fail soft by design: every registration is a `pcall` and the poll
  behind them asks `UnitCastingInfo("player")` five times a second regardless, so
  a name that never arrives costs a fifth of a second and the failed-cast hold,
  which is the only thing on that bar an event is the sole source of. A missing
  frame name is louder, because `hide playercast` would then hide nothing and
  leave two cast bars on the screen; the panel says how many of the six names
  this client carries rather than claiming a row is hidden. What would prove
  both: cast anything, watch the bar fill, then walk out of range mid cast and
  see whether it goes red.
- Whether a 16 pixel bar at 180 wide is the right size for a spell name and the
  seconds beside it. The arithmetic is exact and asserted, but whether it reads
  at a glance during a pull is a thing you look at.
- Whether `BuffFrame`, `TemporaryEnchantFrame`, `DebuffFrame` and
  `TargetFrameSpellBar` are what these clients call those four frames. Each
  `/wk hide` switch takes a global down rather than the buttons inside it, which
  is the point of it: a button named something the sweep never guessed still
  goes down with its parent. A client that renamed the frames as well hides
  nothing, and the panel says so by reporting how many of the four were found
  rather than reporting a row that is hidden.
- Whether the four rows are the right shape at the size the blocks actually end
  up. Everything about the wrap, the mirroring and the row heights is asserted
  in `harness/sections/14-aura-row.lua`, and the arithmetic is exact, but
  whether a row that has folded onto two lines under a block reads well is a
  thing you look at rather than measure. Eight and eight is what a 266 pixel
  block holds in one line at 28 pixels a square, which is why those are the
  numbers it ships at. The player's pair is the one to look at first: you carry
  more buffs than a target does.
- Whether right click to cancel a buff is worth getting back. It goes off the
  screen with `BuffFrame`, because cancelling one is a protected call and a
  square drawn by this addon cannot make it. Getting it back means a secure
  button per square on the player's buff row, which is a real piece of work and
  is not worth starting until somebody misses the feature.

- The whole enemy cast row. `UnitCastingInfo` and `UnitChannelInfo` answering
  for a unit that is not you is inferred from Details deleting its own
  LibClassicCasterino workaround on Era, which is a strong proof and is still an
  inference. Three things follow it and none has run in the game: whether the
  `UNIT_SPELLCAST_*` events fire for a `nameplateN` token, which of the eighth
  and seventh returns really carries `notInterruptible` on 2.5.6 and 1.15.9, and
  whether `plate.UnitFrame.castBar` is what these clients call the region the
  strip walk now hides. The first two fail soft by design: the reading behind
  the events re-reads every bar once a second whatever the events do, and a slot
  that holds something other than a boolean is read as "this client does not
  say" and every cast draws as one you can stop. The third does not fail soft: a
  region
  the strip walk cannot find is Blizzard's cast bar still drawn under ours, and
  it announces itself. `/wk status` reports the other two, so one login answers
  them: whether a cast event has ever reached a bar, and what the client put in
  the uninterruptible slot.

- Whether 2.5.6 and 1.15.9 spell 12721 exactly "Deep Wound" in every locale.
  Wowhead's TBC database says "Deep Wound" for 12721 and "Deep Wounds" for the
  12162 talent, and the scan compares the aura's name against
  `ns.SpellName(12721)`, so both sides come off the same client and a localised
  name matches itself. A client that shipped the bleed under another ID is the
  only way this stays dark, and `/wk bars debuff` would then name a debuff the
  mob does not have.
- Whether `SWING_DAMAGE` carries the off hand flag in the twenty-first value on
  2.5.6 and 1.15.9, and `SWING_MISSED` in the second. Nothing installed here
  parses a swing. Both indices are read by number and the harness feeds both,
  so the parser is asserted against the contract this file states; a client that
  put the flag somewhere else would give an off hand bar that never runs.
- Which shape `GetWeaponEnchantInfo` answers in on 2.5.6 and 1.15.9. The
  documented history is six returns at three per hand, eight from 6.0 once the
  enchant's own id went in after the charges, and twelve from Cataclysm once a
  ranged hand existed. The one unguarded call in this install is inside a Details
  library written for a much later client and reads the eight value shape, and
  the language server stub beside it contradicts itself twice. `Buffs/Upkeep.lua`
  counts the returns instead of picking one, and the harness drives both, so a
  client answering twelve is covered by the same branch that covers eight. A
  client that answered some fourth shape would leave the off hand unread.
- Whether `OffhandHasWeapon`, `IsResting` and `UnitIsDeadOrGhost` are on both
  flavours. Nothing installed here calls any of the three, so all three are
  probed by name and a missing one costs the check it feeds rather than raising:
  no off hand entry, and a row that nags in an inn or over a corpse.
- Whether 19705 is spelled exactly "Well Fed" in every locale, and whether every
  food in these clients applies an aura by that name. Wowhead's TBC database
  names 19705 "Well Fed" and the comparison is this client's own string for that
  id against the aura's own string, so both sides come off the same client and a
  localised name matches itself. A client that shipped a second food aura under
  another name would leave that entry lit while you were fed.
- Whether `SetPassThroughButtons` is on 2.5.6 and 1.15.9. It arrived in 1.14.4
  and 10.0 and nothing installed on this machine calls it, so `Buffs/Nag.lua`
  probes for the name and pcalls it. Where it is missing, a right button drag
  begun on one of the nag squares does not turn the camera: at most four squares
  of 54 pixels, only while something is missing, and only out of combat. Settle
  it by putting the mouse on a square with something missing and right dragging.
- Whether the nine racial ids are what these two clients cast. Each is Wowhead's
  TBC Classic entry for that slug, cross-checked against the cooldown the page
  states. Blood Fury is the exception and is confirmed: 20572 is in this
  install's Details saved variables as a buff with uptime, recorded off a live
  2.5.6 session. The other eight are read through `ns.SpellName`, so an id this
  client does not know drops that entry rather than drawing a blank square.
- Whether `UNIT_SPELLCAST_START` fires for Slam and `UnitCastingInfo` answers a
  start and an end for it. That measurement is what replaces the estimated cast
  time, so a client that never fires it leaves the band drawn from the spell's
  own cast time less 0.1 seconds per point of Improved Slam, which is the state
  the first Slam of every session is drawn in anyway.

  What is no longer on this list is whether that start and end are stable from
  one cast to the next. Only the first reading is taken, so a client that varies
  it cannot move the mark, and the answer stopped mattering.
- Whether the swing bar looks smooth. This is not a client question, it is a
  screen and an eye question, and no test in this repo can answer it. What is
  asserted is that on every frame the addon is given it hands the widget the
  exact position the elapsed time puts the edge at, that the value changes on
  every frame at 60 fps and at 144, and that every step is the same size as
  every other. That leaves the client nothing to be blamed for and it is not the
  same claim. The bar has now been repaired twice against assertions that passed
  both times, so the only thing that closes this is somebody watching it fill.
- Whether the server scales a swing already in flight when haste lands, rather
  than restarting it. `Swing.Retime` assumes it scales, which is what every
  swing timer written for these clients assumes and what Flurry visibly does.
  Getting it wrong costs a bar that is out by the difference for one swing after
  every proc.
- Whether this client folds Improved Slam into `GetSpellInfo`, and whether the
  talent is 0.1 seconds a point on 2.5.6 or 0.2. Warcraft wiki's rank table says
  0.1 for both Classic and Burning Crusade; Wowhead's TBC entry for spell 12330
  says -1000 milliseconds, which would be 0.2. Either way the estimate is out by
  at most half a second and only until the first Slam of the session is cast,
  and the measurement corrects it from then on. This is the one place in the
  feature where being wrong was designed to be temporary.

  What is settled, and did not need the client: haste does not reduce Slam's
  cast time on either of these versions. Warcraft wiki's patch history dates
  that to Cataclysm 4.0.1. The mark is built on the cast being a constant per
  character, and that is where the constant comes from.
- Whether `RegisterStateDriver` and `SecureHandlerStateTemplate` re-point bar 1
  at another twelve action slots in combat on 2.5.6. `Charge/Icon.lua` already
  builds a handler and registers a driver on the same client, so the machinery is
  reached; what neither file proves is that the restricted environment runs the
  snippet `Buttons/Bars.lua` gives it. `scripts/harness.lua` runs that snippet as
  ordinary Lua and asserts every square lands on the right slot for all three
  stance pages, which settles the arithmetic and nothing else. `DrivePages`
  probes for the template and the global before either is used, and
  `ns.Bars.CanPage` reports which path is live, so a client with neither pages
  bar 1 out of combat and says so in `/wk status`.
- Whether a visibility state driver hides one of these bars on 2.5.6. It is the
  same unknown as the page driver above and it is reached through the same two
  calls, so a client that runs one runs the other; what is untested is the
  condition rather than the machinery. `scripts/harness/sections/38-bar-look.lua`
  asserts the macro that is registered, which settles that `[mod:shift] show;
  hide` is what the client is handed and nothing about what the client does with
  it. `ns.BarLook.CanDrive` is probed before either call, so a client with
  neither leaves every bar up and the panel's own reading says so. To settle it:
  set a bar to go down in combat, pull something, and watch it.
- Whether `GetBindingKey` answers a secondary key on this client. Nothing
  installed calls it. It is probed by name and pcalled, and both returns are put
  on the override layer and read straight back with `GetBindingAction`, so a key
  the call did not take is reported rather than believed.
- Whether `statehidden` is enough to keep one of Blizzard's action buttons down
  on 2.5.6. `Buttons/Blizzard.lua` sets it and calls `Hide`, and re-hides on the
  events the client repaints its bars on, so a client that ignores the flag
  costs a few extra `Hide` calls rather than a bar that comes back.

  What it deliberately does *not* do is go through `ns.Strip`, which swaps a
  region's `Show` for its `Hide`. That is right for a texture and wrong for a
  secure action button: the client's own bar controller calls `Show` on these
  from code that goes on to take protected actions, and an addon function
  running inside that stack taints it. The symptom is a press failing mid-fight
  with "Interface action failed because of an AddOn" and nothing tying it to
  this addon. `UnitFrames/Skin.lua` reads like a precedent for stripping and is
  the opposite of one: it strips regions of `PlayerFrame` and `TargetFrame` and
  says in its own header that the frame itself is never hidden, because it is a
  secure unit button. The harness asserts that no button of theirs carries a
  method or a field this addon wrote.
- Whether a key bound to one of our bar buttons wants the same click edge a
  mouse click does. The squares register `AnyUp`, which is what this client's own
  `ActionButton_OnLoad` registers, and the override bindings send `LeftButton`
  through the same button. Registering `AnyDown` instead is what made the first
  build draw perfectly and do nothing when clicked, and the harness now fails on
  a square that answers no up edge.

- Whether `LOOT_READY` fires before the loot window draws on 2.5.6. Leatrix
  Plus hangs its own faster looting on that event and is loaded on both clients,
  so the event is here; that taking every slot on it beats the window to the
  screen is the part taken on trust. The failure it degrades to is the window
  appearing and then closing itself, which is what the client does anyway.
- Whether `C_PartyInfo.GetLootMethod` is on either client. `Comfort/Loot.lua`
  probes it, falls back to the `GetLootMethod` global, and treats neither
  answering as "do not know": solo it still empties the corpse, grouped it hands
  the job back to the client rather than guessing there is no master looter.
- Whether `GetContainerItemInfo` answers a table on 2.5.6 or eleven loose
  values. Both are read in `ns.ContainerItem`, the same way `ns.ContainerSlots`
  already reads both container APIs.
- Whether `CanGuildBankRepair`, `GetGuildBankMoney` and `GetGuildBankWithdrawMoney`
  are on the Era client. TitanRepair calls all three unguarded on both, but Era
  has no guild bank at all, so what that proves is that TitanRepair would break
  and not that the call is there. `Comfort/Repair.lua` reaches all three through
  `_G` and pcalls them, so a client without them loses guild funding and still
  repairs out of your own purse. The merchant half is not in this list:
  `CanMerchantRepair`, `GetRepairAllCost`, `RepairAllItems` and
  `GetInventoryItemDurability` are called unguarded by both TitanRepair and
  Leatrix Plus on both clients, inside their own auto-repair feature, which is
  the same feature and so the same proof.
- Whether `GetGuildBankWithdrawMoney` really answers `-1` for a rank with no
  limit on this client rather than a large number. Read as an amount, `-1` is
  the smallest allowance there is and every repair falls through to your own
  gold, which is the safe direction to be wrong in. The harness models both.
- Whether `ERR_VENDOR_DOESNT_BUY` and `ERR_TOO_MUCH_GOLD` are the constants this
  client raises, and whether `UI_ERROR_MESSAGE` hands the message first or
  second. Both positions are compared and both constants are reached through
  `_G`, so a client that names them something else costs the early stop and
  leaves the 25 pass backstop doing the work.
- Whether `Minimap:SetMaskTexture` is on 2.5.6 and 1.15.9. Leatrix Plus writes
  a square mask on both, which is what puts it here rather than in the list of
  things nothing proves; it is still type-checked before it is called, and a
  client without it takes the size and keeps its round mask. `Shape.Describe`
  says which of the two happened rather than claiming a square either way.
- Whether every name in `Minimap/Shape.lua`'s `ART` and `CORNERS` lists exists.
  None of them is asserted. Both lists are walked through `_G`, a missing name
  is a skipped entry, and `MiniMapTracking` is spelled twice because the two
  clients disagree about which one they have.
- Whether the four tests in `Corral.lua` tell a minimap button from a map pin on
  every install. They are a Button rather than a Frame, a size between 18 and
  48, not one of a name family of more than two, and a ceiling of 24. The
  family rule is the load-bearing one and it turns on pins being pooled and
  named by counter, which is how every pin pool this author has read is built
  and is not a thing any client guarantees. An addon button that arrives with a
  counter on its name and two siblings would be left on the map, which is the
  safe direction to be wrong in; `/wk minimap list` says what was left and why.
- Whether another addon's minimap button minds being reparented. `Corral.lua`
  changes a button's parent, clears its points and replaces its `SetPoint` with
  a no-op, which is what every button bag has done since the first one, and all
  three are undone on release. What it does not do is touch the button's
  scripts, textures or size, so a press in the tray is the press it always was.
  A button that positions itself through something other than `SetPoint` would
  wander out of the tray, and nothing here can stop that.
- Whether `UIErrorsFrame` is the frame both clients draw errors on, and whether
  replacing its `AddMessage` is enough to stop one. Leatrix Plus filters the
  same frame the same way on both. The method is replaced once and never put
  back: an addon that hooked after this one would lose its hook to the
  restore, and a filter is not worth breaking somebody else's.
- Whether `cameraDistanceMaxZoomFactor` really accepts 4.0 on 2.5.6. Leatrix
  writes it on the Era client here. `Camera.Current` reads the CVar straight back
  after writing it, so a client that clamps says what it clamped to in `/wk
  status` rather than being believed.
- Whether `DeleteCursorItem` actually deletes when an addon calls it here, and
  whether the client raises its own confirmation over the top. Questie hooks the
  global, which proves it exists, and nothing installed calls it. It is probed
  and pcalled, so a client that refuses costs the window and leaves the item.
- Whether `GetCursorInfo` answers the item id as its second value on 2.5.6. The
  destroy path compares that id against the one the bag scan read and refuses on
  a mismatch, so a client that answers something else refuses every delete rather
  than aiming one wrongly. That is the right way round to be wrong.
- Whether Questie's `QueryItemSingle` is stable to call from another addon.
  Questie's own tooltip handler calls it exactly this way, but it is another
  addon's internal surface rather than an API, so every call is pcalled and the
  window degrades to offering nothing.
- Whether `GetCVarDefault` is on either client. Nothing installed here calls it,
  so it is probed and 1.9 is the documented default it falls back to. Getting
  this wrong costs nothing while the setting is on and parks the CVar on 1.9
  instead of the client's own number when it goes off.

- Whether the combat log puts the amount in the twelfth value for a swing and
  the fifteenth for everything with a spell in front of it, on these two
  clients. `CombatLogGetCurrentEventInfo` itself is not in doubt, Details calls
  it unguarded on both, but the whole of `Meter/Meter.lua`'s parsing is
  positional and the positions are read from the contract rather than from a
  client. A wrong slot reads as every number being zero or absurd, which is
  loud rather than subtle, and the harness models the sixteen values in order so
  a slot that moves in the addon is caught even though a slot that moves in the
  client is not.
- Whether `GetTalentTabInfo` leads with a numeric tab id or with the tree's name
  on each of these clients. Both shapes are read and told apart on the type of
  the first return. Getting it wrong costs the spec icon and falls back to the
  class icon.
- Whether `INSPECT_READY` fires here and carries the inspected GUID. Details
  calls `NotifyInspect` and `ClearInspectPlayer` on both, which proves the
  request half. The answer half is taken from the contract, and a client that
  never answers costs one request per member per minute and leaves every row on
  its class icon, because of the timeout.
- Whether index 1 is the inspect range for `CheckInteractDistance` here. Wrong
  either way it is a range test that is too strict or too loose, and the cost is
  an inspect that would have worked being skipped, or one going out that the
  server refuses.
- Whether `CLASS_ICON_TCOORDS` carries every class on Era. Read through `_G` and
  indexed by the class token, so a class it does not carry draws the question
  mark rather than raising.
- Whether `UnitDetailedThreatSituation`'s third return really is scaled to the
  pull threshold on the Anniversary client rather than to the tank's raw total.
  Both are percentages and both look plausible on a pane; if it is the raw
  ratio, the percentages are right relative to each other and the projection
  fires slightly late for a ranged attacker. `Details_TinyThreat` reads the same
  return the same way on the same clients.

- Whether `GetPhysicalScreenSize` is on 2.5.6. Nothing installed here calls it.
  `UI/Pixel.lua` probes it by name and falls back to parsing
  `gxWindowedResolution`, then to assuming 768, which is the one screen height
  where the new arithmetic and the old agree and nothing moves.
- Whether `SetIgnoreParentScale` is on 2.5.6. Probed on the first adoption. Where
  it is missing the grid does not happen, sizes stay correct because every
  constant is multiplied by `ns.Pixel`, and edges are still one pixel wide, they
  just land wherever the frame does. `/wk status` says which.
- Whether `SetSnapToPixelGrid` and `SetTexelSnappingBias` are on 2.5.6. Both
  probed per texture. Absent, icons are as soft as they were.
- Whether `C_NamePlate.SetNamePlateEnemySize` is on 2.5.6. Probed by name, and
  `nameplateOverlapV` is the fallback. `/wk status` reports which of the two is
  doing the work.
- Whether `SetCVar` takes `nameplateMotion` and `nameplateOverlapV` here. Both
  pcalled, both retried at PLAYER_REGEN_ENABLED, and `Plates.Warn` says so once
  in chat if the client is still not stacking.
- Whether `Fonts\\ARIALN.TTF` is present on both clients. `UI.Font` reads the
  font back after setting it and falls back to the client default.
- Whether a frame the addon creates as a child of `PlayerFrame` accepts
  `SetIgnoreParentScale`, and whether it counts as protected. `Style` and
  `Relayout` are both behind the lockdown guard, so every call the skin makes is
  out of combat. `UI.Refresh` is the path that is not, because a monitor swapped
  or a window resized mid pull reaches every adopted frame with `SetScale`. It
  asks `ns.Blocked` per frame now and defers the refused ones to
  `PLAYER_REGEN_ENABLED`, so the exposure is a block that keeps the old scale
  until combat drops rather than an error.
- Whether `10/64` is the right crop for a unit portrait on 2.5.6. Blizzard hides
  that dead space under the ring rather than cropping it, so there is no value
  to copy. Too small shows the render's empty border, too large cuts the chin,
  and the only reason to prefer 10 over 9 or 11 is that it is a texel boundary.
- Whether `Texture:GetTexture` answers nil for a texture set with
  `SetColorTexture` here. If it answers something the flatten guard never holds
  and the tick writes every time, which is what it did before. If it answers nil
  while the bar really does carry a file path, the rage bar keeps its rounded
  ends. The first is the failure this degrades to.
- Whether `Texture:GetTexCoord` answers back exactly what `SetTexCoord` wrote. If
  the client stores it lossily the crop is re-applied every tick, which is the
  old behaviour rather than a fault.
- Whether pinning a Blizzard status bar to a frame on a different scale with
  `SetAllPoints` resolves on the screen rather than in the bar's own units. The
  whole rail arrangement rests on it, and if it does not both gauges will be
  wrong by the ratio between the two scales, which is very visible.
- Whether `SetClipsChildren` is on 2.5.6. The harness answers every method probe,
  so it only ever exercises the clipping path: the `ScrollFrame` fallback and the
  no-clipping fallback have never run. `/wk` drawing content over its own footer
  is the symptom of the third.
- Whether the `Slider` frame type accepts a `Texture` object in
  `SetThumbTexture` here, and whether `SetObeyStepOnDrag` exists. The dress-up is
  pcalled; a refusal costs the bar and leaves the wheel. Without the second, the
  canvas lands on a fractional pixel while the thumb is held and snaps back on
  release.
- Whether `GetStringHeight` answers on a font string inside a hidden window. The
  panel only measures the section it has just shown, which should make it moot,
  but a client that refuses on a shown frame inside a hidden window would lay
  every note out one line tall until the first refresh after `Show`.
- Where the game actually breaks a line. The harness models 0.42 em per glyph. If
  Arial Narrow is wider than that in practice, notes wrap to more lines than
  modelled, which is safe because rows measure at runtime, but the harness's
  section heights are model numbers rather than measurements.

- Whether `/equipslot` takes macro conditionals. It goes through SecureCmdList,
  which gets `SecureCmdOptionParse` applied before the handler runs, so
  `[nocombat]` should work. If the weapon stops swapping on the pull, that is
  why, and dropping the conditional is the fix.
- Whether `/startattack` takes macro conditionals here. It goes through
  SecureCmdList the same as `/equipslot`, so `[harm,nodead]` should be parsed
  before the handler runs. If the switch key cycles and never swings, that is
  why, and dropping the conditional is the fix.
- Whether `SecureHandlerStateTemplate` and `RegisterStateDriver` exist here. The
  probe in `BuildBinder` handles it either way, but if they are missing the
  "hand the key back in combat" option is gone rather than broken.
- Whether the Options panel's `SetPropagateKeyboardInput` exists. Behind a
  method check, so the fallback is one stray keypress while capturing.
- Which container API each client carries. `C_Container` and the loose
  `GetContainerNumSlots` globals are both probed in `Core.lua` and a client with
  neither answers empty, so the worst case is a weapon picker offering nothing
  but "no weapon swap". `/wk charge weapon <name>` still sets it if that
  happens.
- Whether `GetItemInfoInstant` exists on 2.5.6. `ns.ItemInfo` falls back to
  `GetItemInfo`, which can answer nil for an uncached item, so the symptom would
  be a weapon missing from the picker until something else caches it.
- Whether `FontString:SetWordWrap` exists. Behind a method check on the three
  font strings pinned on both sides, and without it a long weapon name wraps
  onto the note under it instead of being clipped.
- Whether `FontString:GetStringHeight` answers on a hidden page. If it returns
  zero the notes lay out one line tall until the panel is shown, and the first
  refresh after `Options.Show` corrects them.
- Whether `UnitClassification` exists here. Nothing installed calls it, so
  `ns.Classification` probes for it, and a client without it draws the level
  with no elite marker rather than erroring. Every elite reading as normal is
  the symptom.
- Whether an action slot on 2.5.6 goes stale at all when you train a rank. If
  the client already moves the button itself, `Buttons/Ranks.lua` finds nothing
  stale every time and the whole part is dead weight rather than wrong. One
  trainer visit answers it: train a rank, touch nothing, look at the button.
- Whether `GetActionInfo` returns a rank-specific spell ID here. If it answers
  with a rank-agnostic ID instead, every slot compares equal to the spellbook's
  best and nothing is ever reported stale. Same symptom as the line above and
  the same test does not separate them, so check `/wk ranks` against a bar you
  know is out of date.
- Whether `GetSpellBookItemInfo` returns the spell ID in its second slot on this
  client rather than an override ID. The blast radius is small either way: a
  slot is only written when the spellbook entry's name already matches the name
  in the slot, so the worst case is the wrong rank of the right ability, never a
  different ability. Worth knowing anyway, because `buttons restore` does not
  cover it. `Ranks` writes slots the loadout never touched and keeps no backup
  of its own.
- Whether `IsSpellInRange` answers for nameplate units. If it returns nil the
  addon says so in chat once, and every target stays colour-coded as ready.
- Whether `RegisterForClicks("AnyDown")` fires once and not twice for a key sent
  by an override binding. Two casts per press would show up as a wasted Charge.
- Whether the `[combat]` state driver hands the key back fast enough to be
  useful on the pull. The charge itself puts you in combat, so the key flips to
  its normal binding roughly when the charge lands.
- Whether `self:SetBindingClick` inside the snippet takes a frame handle for its
  third argument on 2.5.6. If it wants a name, swap `button` for the literal
  string `"WarriorKitChargeButton"` in `BIND_SNIPPET`. That is the whole fix.
- `unitFrame.healthBar` and friends in `PlateRegions`. If the Blizzard bar is
  still visible under ours, a field name is wrong. That function is the only
  place to fix it.
- Whether the plate offset lines up without a nudge.
- Whether `partypet1` style units resolve for the targeting list in a five man.
- Whether `SetIgnoreParentAlpha` exists in 2.5.6, it is called behind a
  method-exists check.
- Whether the protected-region fallback ever triggers.
- Whether `SetOverrideBindingClick` takes a mouse button name on 2.5.6.
  Clique binds modified mouse buttons on this client through the same call, so
  this is the best supported of the unknowns here, but Clique routes through a
  secure header and `Keys.lua` does not, and nothing proves the plain call
  behaves the same. It is pcalled and read back with `GetBindingAction`, so a
  refusal drops to the ctrl-targeting fallback and says so once. `/wk status`
  reports `ctrl-click on` only when the readback agreed.
- Whether a button with no size and no anchor still receives a click delivered
  by an override binding. Clique's equivalent button is shaped the same way,
  which is why this one is not hidden and not mouse disabled.
- Whether `ALT-BUTTON1` is free on this client. Alt-click is self-cast on unit
  frames in some builds, and the moon key is the one shipped default most likely
  to collide with something. It is a setting, so the fix is to change it.
- Whether the override survives a UI reload without being reapplied. It is set
  at PLAYER_LOGIN, which fires on every reload, so it should not matter.
- Whether the `softenemy` unit token resolves on 2.5.6. This is the one worth
  answering first. `SoftTarget` now turns the CVar on for you out of combat, so
  the test is only this: drop your target, aim at a mob, and see whether the
  world marker lands on it. `/wk status` latches `token on` the moment the token
  answers once, and stays `unproven` until it does. The addon works either way,
  so this decides whether aiming follows your camera or only your target and
  cursor.
- Whether `SetCVar` accepts `SoftTargetEnemy` on 2.5.6, and whether the client
  lets it change while lockdown is up. Both calls are pcalled and a refusal
  defers to PLAYER_REGEN_ENABLED, so the failure mode is action targeting
  staying on through a fight rather than an error. If `/wk status` says
  `auto, off for this fight` while the game is plainly still re-aiming you, the
  in-combat write is what is being refused.
- Whether `[@softenemy]` resolves inside a macro conditional, which is a
  separate question from the Lua token and can fail on its own. The symptom is
  a marker on the right mob and a press that charges the wrong one. The
  `/targetenemy` backstop under that line covers the empty-target half of it.
- Whether `PlaceAction` and the rest of the action-writing set exist at all.
  `Layout.CanApply` probes for them, so a client without them greys the button
  out rather than erroring, but nothing here proves which way it goes.
- Which shape `PickupSpell` takes on 2.5.6. `CursorSpell` tries the name first
  and then the spell ID, and reports the slot as skipped if neither puts
  anything on the cursor.
- Everything about Classic Era. Nothing on that install confirms a single API
  the way Titan and Details confirm them on Anniversary, because that client has
  no addons in it yet. The Era claims here are read off the interface number and
  off what vanilla is known not to have, and every one of them is behind a probe
  or a type check, so the failure mode is a missing feature rather than an
  error. First run on Era, watch `Logs/General.log` and check `/wk status`.
- Whether Era nameplates are restricted regions the same way Anniversary's are.
  `ns.Measure` pcalls either way, so the answer only decides whether the plate
  width is read or defaulted to 130.
- Whether `ImportLayout` wants the layout table, the layout type and the name in
  that order, and whether it takes an account layout type from `Enum`. Both come
  from retail. If the import is refused, `EditMode.Apply` is the only place to
  fix it.
- Whether a layout table that came out of `GetActiveLayoutInfo` is accepted back
  by `ImportLayout` unchanged. Round trip through `bake-ui.sh` is verified to be
  lossless as a table, which is a different claim from the client accepting it.
- Whether the character macro cap is really 18. `MACRO_CAP` refusing early is
  the only cost of being wrong.
- Whether `GetMacroInfo` returns the name first on this client. The backup
  stores macros by name, so a wrong return order would restore the wrong macro.
- Whether replacing `Show` on `ActionBarUpButton` and `ActionBarDownButton`
  taints anything. They are ordinary buttons rather than secure ones, and the
  swap happens at login well outside combat, but this is the one entry in
  `ART_REGIONS` that touches a frame the player can click.
- Whether Blizzard re-creates any of the art after login. The `Show` swap covers
  a re-show, but not a texture that did not exist when the sweep ran.
- Whether the four parent keys the skin resolves its pieces through, `portrait`,
  `name`, `healthbar` and `manabar`, are on these frames here.
  `UnitFrame_Initialize` has set all four since vanilla and a key cannot be
  renamed by a client that renamed the global, which is why they are tried
  before the names, but nothing installed here reads one. Each falls back to the
  Classic global, and a piece that resolves to neither leaves that frame
  unskinned and says so in `/wk status` rather than erroring.
- Whether anything on this client writes a size back onto `PlayerFrame`,
  `TargetFrame` or `TargetFrameToT` after the fit. `Place` re-fits on every
  target change, every world entry and every resolution change, so a frame that
  is written once would come back on the next of those, but one written every
  frame would fight the skin and show as a block that does not match its own
  outline.
- Whether this client's Edit Mode calls its selection frame `Selection` and
  anchors it through `AnchorSelectionFrame`. Both names are retail's and both
  are probed before they are touched. If neither is there, the fit still makes
  the frame's own rectangle the block, which is what Edit Mode draws over by
  default; if the client insets its selection by the size of the art this part
  has already hidden, the pin is what corrects it. `/wk skin probe` says which
  of the two this client is.
- How this client's Edit Mode says a system has been dropped. `HookDrag` wants
  the moment a drag ends, so that where the target landed becomes the level.
  Retail carries `OnDragStop` as a method on the system frame itself and wires
  it as that frame's own drag script, so the method is post-hooked where it is a
  function on the frame and the script is hooked where it is not. Nothing
  installed on this machine touches either. A client that carries neither loses
  only the drag: the level stays whatever `/wk skin level` was last set to, and
  the link is still written. Settle it by opening Edit Mode, dragging the target
  well up or down, closing Edit Mode and reading `/wk status`, which prints the
  drop it stored.
- Whether a frame anchored to another frame can still be dragged in this Edit
  Mode at all. `StartMoving` clears a frame's points and follows the mouse, so
  an anchor of ours is no more of an obstacle than Edit Mode's own, and that is
  the contract rather than an observation. A client that refused would show as a
  target frame that will not move once the link is on, and `/wk skin link off`
  is the way out of that without a reload.
- Whether `EDIT_MODE_LAYOUTS_UPDATED` is a real event on this backport. It is
  retail's name for a layout being applied, which is the moment Edit Mode writes
  its own saved point back over the link's anchor. Registering an event a client
  does not have raises, so the registration goes through `pcall` and a client
  without it loses nothing this addon needs:
  `PLAYER_ENTERING_WORLD`, `PLAYER_TARGET_CHANGED` and the `Blizzard_EditMode`
  load all reach `Relayout` already. A layout switch that leaves the target
  frame parked at Edit Mode's own point until the next target change is what a
  missing event looks like.
- Whether this client names its aura buttons `TargetFrameBuff1`,
  `TargetFrameDebuff1`, `BuffButton1`, `DebuffButton1` and `TempEnchant1`. All
  five are the Classic names and none is called by anything installed here. A
  name that is not a frame stops that run's sweep at slot one and hides nothing,
  so the client's icons stay where they are, on top of ours in the player's case
  and inside the gauge in the target's. `/wk skin probe` prints how many of each
  row it has hidden, and the buff row's number counts both of its runs, so a
  full list plus a sharpening stone settles all five in one look.
- Where the target's cast bar lands. `Target_Spellbar_AdjustPosition` anchors it
  under the last aura row where there are auras, which now follows the block in,
  and against the frame where there are none. The second case has not been
  watched. Nothing here moves that bar.
- Whether `0.15` is the right crop for a unit portrait on 2.5.6. Blizzard hides
  that dead space under the ring rather than cropping it, so there is no value
  to copy. Too small shows the render's empty border, too large cuts the chin.
- Whether replacing `SetStatusBarColor` on a child of a secure unit button
  taints anything. Colouring a status bar is not a protected action and the swap
  happens outside combat, but this is the skin's equivalent of the
  `ActionBarUpButton` entry above: a method swapped on a frame the player clicks.
- Whether `AttackIcon$`, `RestIcon$` and `PVPIcon$` match anything on these
  frames here. The four `BADGES` patterns are written from the Classic region
  names, nothing installed here reads one, and a pattern that matches nothing
  is a state icon that stays hidden rather than an error. `/wk skin probe`
  lists every region the walk removed, so a miss names itself.
- Whether the server actually sends heal prediction for a TBC-era heal. The
  Lua function and the event are both in both client binaries, which is what
  says the API is there, but only a healer casting on you proves the data
  behind it arrives. If it never does, `UnitGetIncomingHeals` answers 0 forever
  and the slice simply never draws.
- Whether Blizzard re-anchors any of these regions after the skin has run.
  PLAYER_TARGET_CHANGED and PLAYER_ENTERING_WORLD re-place the block, and the
  portrait's crop is re-applied every tick, but a re-anchor on some other event
  would show as a piece drifting out of the square.
- How long the Overpower and Revenge windows really are. Five seconds is what
  every player-facing source says: the Vanilla wiki calls Overpower "only usable
  if your target dodges, for a short amount of time (5 second period)", the
  Classic guides agree, and both abilities carry a five second cooldown, so a
  warrior pressing on every window presses on the cooldown. The MaNGOS and
  TrinityCore server cores both hold `REACTIVE_TIMER_START` at 4000
  milliseconds, which is where four seconds comes from when somebody quotes it.
  `Buttons/Reaction.lua` uses five, because running a second long costs a glance
  at a square that says pressable when it is not, and running a second short
  greys a free five rage attack that is still sitting there. Settling it needs
  the live client: get something to dodge you, watch the seconds in `/wk status`
  and see when the client starts refusing the press.
- Whether `SPELL_CAST_SUCCESS` is what these clients send when Overpower or
  Revenge lands. It is the subevent the window is shut on. If a client sends
  something else, the square stays lit for the rest of the five seconds after
  the one press it had, which is a smaller version of the bug the file exists to
  fix rather than a new one.
- Whether a blocked amount really sits in slot 16 of `SWING_DAMAGE` and slot 19
  of `SPELL_DAMAGE` on 2.5.6 and 1.15.9. Both are read positionally, the way
  every other combat log read in this addon is. Reading the wrong slot opens the
  Revenge window on every hit you take, which looks like a window that never
  shuts rather than like a parser fault.

- Whether these clients carry `GetXPExhaustion`, `IsXPUserDisabled`,
  `GetMaxPlayerLevel` and `MAX_PLAYER_LEVEL`, and which of the two watched
  faction calls each of them answers. Every one of them is probed and pcalled at
  its call site, so a client missing one loses that answer rather than raising: a
  missing `GetXPExhaustion` is a rail with no rested pool drawn on it, a missing
  `IsXPUserDisabled` means an experience-off character keeps a rail nobody
  wanted, and a client answering neither faction call leaves the reputation rail
  off forever. The cap is settled by `UnitXPMax` answering zero even where both
  level calls are missing, which is what every client this addon has been read
  against does. What would settle it: `/wk xp` on a character partway through a
  level, which prints the reading and says which of them answered.
- Whether `MainMenuExpBar`, `ReputationWatchBar`, `MainMenuBarMaxLevelBar`,
  `StatusTrackingBarManager` and `ExhaustionTick` are what these two clients call
  those frames. The five are written from the two FrameXML generations this
  backport straddles and nothing installed here calls any of them. A name this
  client does not carry is a skipped lookup rather than an error, and the symptom
  of getting all five wrong is two experience bars on the screen rather than one.
  `/wk hide probe` prints one line per name and says which are on screen, which
  settles it in one look.
- Whether the reputation band the client answers is the standing's own band or
  the whole scale. `Progress.Faction` folds both calls to a band relative pair by
  subtracting the low end, which is right for the five value shape as documented
  and for the table shape's `currentReactionThreshold`. A client that already
  answers band relative numbers would have the low end taken off twice, and the
  symptom is a rail that reads nearly empty at a standing you are most of the way
  through. What would settle it: watch a faction you are partway into and compare
  the rail against the client's own reputation pane.
- **Whether `IsVisible` answers false for a chat room inside a closed window.**
  A room's log writes its scrollbar only while somebody can see it, and that
  reading is what decides. The harness proves the eleven rooms you are not
  reading go quiet, because their own frames are hidden; what it cannot prove is
  the window shut over the room you are, which turns on the parent walk rather
  than on the frame's own flag. A client that answered true there costs the
  writes back and nothing else. One that answered false for a room on screen is
  a scrollbar beside the room you are reading that never moves again. What would
  settle it: open the chat window, sit in the party room through a pull, and drag
  the bar.
- **Whether four hundred restored lines come back with a working scrollbar.**
  The replay of what was said before a reload now writes each room's bar once, at
  the end of that room's lines, rather than per line. The harness has never run
  it with a record in it, because the run's own login starts with an empty one. A
  mistake looks like a chat window that opens after a reload with the last
  session's lines in it and a thumb that is the wrong size or missing. What would
  settle it: talk in a party, `/reload`, and open the window.
