# WarriorKit

A personal warrior addon for WoW TBC Anniversary. Eight parts: ctrl-click raid
marking, one button that casts Charge, Intervene or Intercept depending on what
you are looking at, one key that takes the next enemy and swings at it, weapon
loadouts with a key each that swap your stance and both your hands, a warrior
loadout that fills the action bars, enemy bars that replace the
Blizzard nameplate, a strip of the Blizzard bar art, and one Edit Mode layout
carried inside the addon folder. Settings live in a panel
opened with `/wk`.

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

The addon is eight parts and a core. Each part is a folder, and Core knows the
name of none of them.

    Core/Core.lua        SavedVariables, API shims, the feature registry
    Core/Gear.lua        what the client will let into each hand, and the two
                         slot numbers those hands are
    Core/Stance.lua      the three stance spells, their names, and which one
                         you are standing in
    Core/Command.lua     slash dispatch, built from the registry
    Core/Panel.lua       the options window and the widget kit

    UI/Pixel.lua         the pixel grid: screen size, scale, snapping, rescale
    UI/Draw.lua          a filled rectangle, a hairline outline, a crisp icon
    UI/Text.lua          one shared font object per size, a label, wrapped height
    UI/Theme.lua         the palette and the pixel metrics, in one table each
    UI/Stack.lua         a column of rows, each one asked how tall it is
    UI/Scroll.lua        a viewport that clips, a canvas that moves, a bar
    UI/Widgets.lua       the widget kit a page is built out of
    UI/Window.lua        window chrome, the side rail and the tab strip

    Perf/Perf.lua        what each ticker costs and what the addon is holding
    Perf/Feature.lua

    Marking/Marking.lua      ctrl-click raid marking, keybinding entry points
    Marking/Keys.lua         the override binding behind each marking key
    Marking/Feature.lua

    Charge/Charge.lua        which ability, which unit, what state; shared colours
    Charge/Icon.lua          the HUD icon, which is also the secure button that casts
    Charge/Marker.lua        the icon in the world above the mob the button will hit
    Charge/SoftTarget.lua    action targeting, held on out of combat and off in it
    Charge/Feature.lua

    Targeting/Switch.lua     the secure button behind the switch key, and its binding
    Targeting/Feature.lua

    Loadouts/Loadouts.lua    ten secure buttons, one per loadout, each carrying
                             that loadout's cast and its pair of /equipslot lines
    Loadouts/Feature.lua     the paperdoll page and the loadout tab strip

    Buttons/Layout.lua       the warrior loadout, and the backup of what it replaced
    Buttons/Ranks.lua        moves bar slots up to the best rank you know
    Buttons/Feature.lua

    UnitFrames/Plates.lua    the client settings that decide where a plate goes
    UnitFrames/EnemyBars.lua enemy bars, nameplate replacement and list fallback
    UnitFrames/Skin.lua      the square skin on player, target and target of target
    UnitFrames/Feature.lua

    Artwork/Artwork.lua      strips the gryphons and the metal strip off the bars
    Artwork/Feature.lua

    EditMode/EditMode.lua    probes Edit Mode, captures a layout, imports the baked one
    EditMode/Saved.lua       generated, the baked layout, written by bake-ui.sh
    EditMode/Feature.lua

    Bindings.xml         keybindings, loaded automatically, not listed in the TOC
    WarriorKit.toc       load order, TBC Anniversary and the fallback for anything else
    WarriorKit_Vanilla.toc   the same list for Classic Era
    check.sh             syntax, TOC coverage and lint gate, exits non-zero on any finding
    bake-ui.sh           bakes a captured Edit Mode layout into EditMode/Saved.lua

`UI/` is not a part. It has no `Feature.lua`, signs into no registry, owns no
setting and knows the name of nothing above it. It is a layer, the way Core is:
everything that puts a frame on the screen draws through it, and it draws
through the client.

TOC order matters three times. `Core/Core.lua` must load first because it
creates the registry every other file signs into. `UI/` loads next, before
`Core/Panel.lua`, because the panel takes `ns.Fill` and `ns.Outline` into
file-scope locals as it loads. Within a part, behaviour loads before
`Feature.lua`, because `Feature.lua` is the only file in a part allowed to name
anything outside its own folder.

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
loadout overwrote them belongs to the character whose bars they were. Two parts use
`charDefaults`. `Charge` keeps `softPrior`, the value a character's
`SoftTargetEnemy` CVar had before the addon took it over, because that CVar is
character scoped itself. `Buttons` keeps `layoutBackup`, `layoutStamp` and
`layoutMacros`, and registers them there because holding them account-wide
could destroy a second character's bars: the first character
to apply the loadout owned the only backup, the second overwrote its bars
without taking one, and restoring on the second wrote the first one's bars into
its slots. A key that moves scope is migrated once at `ADDON_LOADED` and the
account copy is dropped.

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
    ns.SpellName / ns.SpellTexture / ns.SpellCooldown / ns.SpellUsable / ns.SpellInRange
    ns.ItemInfo(link)            name, icon, equip slot and the link's own colour
    ns.ContainerSlots(bag) / ns.ContainerItemLink(bag, slot)   bags, on either
                                        container API, and 0 or nil on neither
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
    ns.EnemyBars.WidgetFor(unit) the bar on that unit's plate, if there is one
    ns.EnemyBars.Describe()      what the grid resolved to and whether the client
                                 agreed to space plates by the size of a bar
    ns.FrameSkin.Apply()         put the three Blizzard unit frames where
                                 ns.db.skin says they should be
    ns.FrameSkin.Describe()      one line on what the skin did or did not find
    ns.Options.Refresh()         put the panel back in step with the database
    ns.Options.SelectTab(index)  show one part's page
    ns.Register(feature)         sign a part into the registry, from Feature.lua only
    ns.Each(hook, ...)           run one registry hook across every part
    ns.DefaultFor(key)           the registered default for a setting, for reset
    ns.Command.Toggle(arg)       "off" is off, anything else is on
    ns.Command.Number(v, lo, hi, what)  parse and range-check, or complain and return nil
    ns.Layout.CanWrite()         the action API is here, combat is not, cursor is empty
    ns.Layout.CanApply()         that, and you are a warrior
    ns.Layout.Apply / Restore    fill the action bars, or put back what was there
    ns.EditMode.CanApply / Capture / Apply / Saved / IndexOf
    ns.interface / ns.vanilla    the interface number, and whether this is 1.x
    ns.HasThreat() / ns.Threat(source, unit)   the threat API, or nil on vanilla
    ns.HasHealPrediction() / ns.IncomingHeals(unit)   what is already in the air
                                 for that unit, 0 when nothing is, nil when the
                                 client has no prediction at all
    ns.Strip(region) / ns.Unstrip(region)   hide a Blizzard region so its own code
                                            cannot show it again, or give it back
    ns.Blocked(region)           whether a region is protected and in lockdown,
                                 so the caller can queue the work for regen
    ns.Artwork.Apply()           re-run the bar art strip from ns.db.blizzArt

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

Three consequences worth knowing before changing anything under it:

- **Sizes are absolute now.** A 21 pixel bar is 21 pixels on a laptop and 21 on
  a 4K panel. That is the point and it is also the cost, which is what
  `bars zoom` is for. Zoom is a whole number because a fractional one puts every
  edge back on a half pixel.
- **A measurement from outside the grid means nothing until it is converted.**
  A nameplate is not on the grid and never will be. `ns.UI.Convert` takes a size
  from one frame's units into another's, and `ns.UI.Round` snaps what comes out.
  A width read off a plate and used directly is a bug that looks like a
  rendering artefact.
- **A bar on a nameplate cannot be snapped in position.** Its origin is wherever
  the mob is standing, which is a moving fraction of a pixel no addon can read.
  Its geometry is exact; where that geometry lands is the client's business.
  Bars in the list anchor to UIParent and are exact in both.

Icons are a separate fix in the same file. A flat colour is one texel stretched
over a rectangle and there is nothing to get wrong. A spell icon is a 64 texel
square resampled to whatever the layout asked for, and it needs two things: a
crop on a texel boundary, `5/64` and not `0.08`, and the client's own
`SetSnapToPixelGrid` turned off, because that pulls a texture's corners onto
whole pixels and stretches the two axes by different amounts. Both methods are
probed rather than called, and an icon that is merely soft beats a widget that
raises. `ns.UI.Icon` does all of it.

Text goes through `ns.UI.Font`, which hands out one shared font object per size
and flag pair. A font string given a font by `SetFont` carries its own copy; one
given a font object shares. The bars alone put eight strings on a widget and lay
out a widget per nameplate.

### The widget library

`UI/` was three files and a pixel grid. It is eight now, and the five new ones
are a widget library rather than a settings panel: the options window is the
first thing built on them and is not meant to be the last.

    ns.UI.Color / ns.UI.Metric     the palette and the measurements
    ns.UI.Box / ns.UI.Rule         a filled box with a hairline, and a hairline
    ns.UI.Stack(parent, width)     a column, :Add, :Space, :Reflow
    ns.UI.ScrollView(parent)       :Resize, :Update(extent), :ScrollTo
    ns.UI.Button(parent, opts)     a push button
    ns.UI.Kit(host)                the widget kit
    ns.UI.Window(opts)             chrome, adopted onto the grid
    ns.UI.Rail / ns.UI.TabStrip    the two levels of navigation
    ns.UI.Windows                  every window the library has made

**Every row is asked its height, never told.** A widget that carries text hands
its stack a measure function. Reflow sets the row's width first, asks second,
snaps the answer to a whole pixel and only then places the row under it. Doing
those two in the other order is the whole of the overflow bug that was in the
old panel: a note measured against the previous pass's width is a note drawn on
top of whatever follows it.

**A page has two levels.** The rail is the parts, and each `ui.Header` a feature
writes opens a tab within that part. Nothing in a `Feature.lua` changed for it:
`ui.Header` used to draw a rule and now opens a section, and the kit asks its
host where sections go. A host that answers nothing gets the rule back.

**The window is adopted, so it is exact.** Unlike a nameplate it is a frame the
addon owns and anchors to UIParent, so every number in `UI.Metric` is a count of
physical pixels and the window is 544 by 452 of them. It does not resize and it
does not grow: a section that does not fit scrolls. Zoom is a whole number
picked off the screen height, 1 below 2000 pixels tall and 2 above, for the same
reason `bars zoom` is a whole number.

**Three client questions, all probed.** Clipping is `SetClipsChildren` where it
answers, the `ScrollFrame` frame type where it does not, and nothing at all
where neither does. The bar is a `Slider` frame type with a thumb the addon
draws, chosen because following a dragged thumb by hand means an `OnUpdate` and
this addon does not add a ticker for a settings window. The wheel is
`EnableMouseWheel`. No Blizzard widget template is used anywhere in the layer.

### Where the client puts a nameplate

Bars piling up when two mobs stand together is not a drawing bug and no care in
the widget fixes it. Blizzard's driver decides where a plate goes, and it uses
two things `UnitFrames/Plates.lua` can reach: `nameplateMotion`, which on 0 lets
plates overlap freely and on 1 makes the driver push them apart, and the plate's
size, which the driver takes to be Blizzard's nameplate. Ours is twice the
height of that with a level tag hanging off the left edge.

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

Four `OnUpdate` tickers run at once and none of them ever stops. A fifth runs
only while you are looking at it.

    Charge/Marker.lua        20 Hz   it tracks the camera
    Charge/Icon.lua          10 Hz   the HUD icon and the macro
    UnitFrames/EnemyBars.lua  5 Hz   every bar on screen
    UnitFrames/Skin.lua       5 Hz   the three Blizzard unit frames
    Perf/Perf.lua             1 Hz   only while the performance tab is on screen

The fifth one is the exception that proves the rule rather than a loosening of
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

`check.sh` enforces this. `HOT` in that file lists every function that runs on
every tick, and a `:SetSomething(` call or a table constructor inside one fails
the build unless an `if`, `elseif` or `else` stands between it and the top of
the function. A
function only ever reached from behind a guard, `PlaceOnPlate` for one, is not
on the list: it already runs on a change rather than on a tick, and its job is
to do the writing. A `for` loop
is not a guard: it repeats the write, it does not decide it. Adding an
`OnUpdate` to a file that names no function in `HOT` also fails, so a new ticker
cannot arrive unchecked.

To exempt one line, put `-- unguarded: <reason>` on a write or
`-- allocates: <reason>` on an allocation. The reason is required and the gate
checks that it is there. Two exemptions stand today, both the same shape: a
memoisation guarded by an early return the scan cannot see.

What is deliberately not guarded: `Skin.lua` re-applies `Flatten` and the
portrait crop on every tick because Blizzard's own code puts the texture and the
crop back whenever it swaps the art underneath, and ours has to be the last
word. That is three frames at 5 Hz.

What is knowingly still expensive: `ThreatState` walks every group member for
every mob you are tanking, because the number it shows is the nearest
challenger and there is no cheaper way to find it. Solo that is two threat
queries per mob. In a forty man raid with fifteen plates it is about 2,900 a
second, and the only way to cut it is to show a different number.

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
finish at PLAYER_REGEN_ENABLED. The cast bar is left alone on purpose so
interrupts stay visible.

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
go through the frame itself. `UnitFrames/Skin.lua` hides their textures the way
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

**APIs that do exist here**, each confirmed by an installed addon calling it
unguarded rather than by memory:

    UnitDetailedThreatSituation   Details_TinyThreat
    UnitLevel                     Questie, OPie
    GetQuestGreenRange            Questie, as GetQuestGreenRange("player")
    UnitReaction                  Details, and it tests reaction <= 4 the same way
    C_UnitAuras.*                 Leatrix_Plus
    UnitAura                      Questie
    C_NamePlate.*                 used by this addon's own marking module
    GetActionInfo                 OPie
    EditModeManagerFrame          Titan, GetActiveLayoutInfo only

The spell and aura accessors are shimmed anyway, C_Spell first with the legacy
global as fallback for spells, legacy first for auras. If a future client drops
one side, only the shim changes.

## Traps already hit

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
- Class data is not reliably available while files load. Resolve
  `UnitClass("player")` at PLAYER_LOGIN, not at file scope.
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
- `RegisterForDrag(nil)` is an error, not a way to clear a drag registration.
  The no argument call is what clears it. Written as
  `RegisterForDrag(unlocked and "LeftButton" or nil)` it raised on every lock,
  which meant every login.
- Anything a ticker does at 20Hz has to be incapable of raising. Two of these
  in one session hit the client's error ceiling and got the whole addon
  offered up for disabling, which is a far worse failure than the feature
  simply not working.

## Feature notes

**Marking.** Skull is 8, cross is 7. Ctrl-clicking a unit that already carries
the icon clears it. `SetRaidTarget` silently does nothing without raid leader
or assistant, so the addon says so once every five seconds instead.

Three marks, one key each, set in the panel or with `/wk markkey`. The shipped
keys are `CTRL-BUTTON1` for skull, `CTRL-SHIFT-BUTTON1` for cross and
`ALT-BUTTON1` for moon: moon takes alt rather than a third ctrl combination
because `CTRL-ALT-BUTTON1` is a chord, and the point of these is that they beat
opening a menu. `Marking.MARKS` in `Marking.lua` is the list, read by `Keys.lua`
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

**Charge.** Three abilities, one button. Charge.lua holds the state,
ChargeIcon.lua draws the HUD icon and is the button that casts, ChargeMarker.lua
puts a copy of that icon in the world over the mob you are about to hit.

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
and drives it off combat: on when you are out of it, off when you are in it.

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

**Why the loadout strip is not the window's tab strip.** The window's strip is
chrome: `Core/Panel.lua` builds it once at PLAYER_LOGIN out of the headers each
feature writes, and it cannot grow. A loadout list is a setting that changes
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

**Options panel.** `/wk` with nothing after it opens it, Escape closes it, and
every row has a slash command behind it so nothing is only reachable by mouse.

One tab per part down the left, one page each, both built out of the same
registry walk, so a seventh part takes a seventh tab without `Panel.lua`
changing. It was one column of every setting in the addon before that. Six parts
made it 700 pixels tall and the window scaled itself down to fit the screen,
which bought room for settings you were not looking at by shrinking the text of
the one you were. Every page is sized to the tallest of them, so changing tabs
does not resize the window under the mouse.

A page is a list of rows laid out top down rather than a running cursor. The
cursor could not survive a note. A note is as tall as its text wraps, its text
changes while the panel is open, and a row whose height was fixed before its
text was written gets drawn over by the row under it. So notes measure
themselves on every refresh, and a note that gains a line pushes the rows under
it down and the window out. Out only: the window never shrinks back, because a
panel that breathes while you read it is worse than one that is too tall.

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
debuff icons packed right.

The edge around the gauge carries the threat colour, the same colour the fill
uses, so aggro is legible off a bar that is nearly empty. Your current target
turns its name pale gold instead, because the edge is spoken for.

**The mob tag** sits outside the box, off the left end of the gauge, and
answers two questions between them: what the kill is worth, and whether the mob
starts it.

The number is the level, coloured on the client's own XP scale:

    grey     more than GetQuestGreenRange below you, and it pays nothing
    green    below you and still inside that range
    yellow   two levels either side of you
    orange   three or four above
    red      five or more above, or a level the client will not name

    42   normal        42+   elite        42r   rare        42r+  rare elite
    ??   a boss, or a level this client will not name

The stripe closing the tag on the left is the reaction. `UnitReaction` under 4
is hostile and it comes for you inside its aggro radius, 4 is neutral and it
stands there until you hit it. Anything over 4 does not fight you at all and
cannot normally reach a bar, since a bar needs `UnitCanAttack`, so that case
draws the idle grey rather than a claim.

Hostile is deep red and quiet, neutral is bright amber. That is deliberate and
not a mistake about which one matters: nearly everything on the screen is
hostile, the bar already carries threat red on the fill and five-levels-up red
on the number, and a third bright red would say nothing new. The exception is
what you want to catch from across a room.

The stripe cannot tell you about aggro radius, which shrinks as a mob falls
behind your level until a hostile one walks past without noticing you. Read the
two halves of the tag together. Deep red against a grey number is a mob that
could come for you and will probably not bother.

`replace` style strips `LevelFrame` and `ClassificationFrame` off the Blizzard
plate, so before this the bar showed no level and no elite dragon at all. The
tag puts both back in one string.

The tag is one frame holding both, and one setting turns the pair on and off,
because they are one question: what is this thing and what does it do about me.
The number and the stripe are a tag rather than a second colour on the gauge on
purpose. The XP scale
and the threat scale are the same five colours meaning two different things,
and a green fill would have to mean "you hold it" and "it is worth little" at
once. So difficulty gets the tag, threat keeps the fill, the edge and the line
above, and neither has to be read through the other.

The tag used to sit inside the gauge, over the left end of the fill. The left
end is the part a mob still has at ten percent, so the tag covered exactly the
health worth looking at. It now sits outside the box, flush against its left
edge and the same height as it, so the two read as one strip with the box's own
hairline between them. There is no gap. The whole inside of the bar is the
name's again, left edge to health number.

It is pinned by its right edge rather than its left. It is as wide as its own
text, measured with `GetStringWidth` whenever the string changes, because `??`
and `42r+` are not the same width, and pinning the right edge means a wider tag
grows leftwards into empty screen instead of pushing the gauge. The raid marker
anchors outside the tag while the tag is on and back against the box when it is
off, so the two never want the same strip of screen.

Its plate is near black and the number carries the colour, because a filled chip
would sit against the gauge in a colour off the same five and the two would read
as one smear.

**What sits over the mob is the tag plus the box, not the box.** A tag hanging
off one side would otherwise throw the whole thing left of the plate's centre.
`PlaceOnPlate` shifts the widget right by half the tag width when it anchors it,
which puts the middle of the pair on the plate centre and carries the threat
line and the debuff row along rather than leaving them behind. It is not a
one-time calculation: the offset is half of a width that changes with the
string, so `UpdateWidget` calls `PlaceOnPlate` again on the same branch that
remeasures the tag, next to the `GetStringWidth` call that caused the move. Both
are guarded on the string, so a mob whose level is not changing pays nothing.

List mode gets no offset at all. There the widgets stack against the anchor's
left edge, and the right answer is boxes that line up under a ragged column of
tags, not boxes that shuffle sideways by mob level. `LayoutWidget` records
`widget.onPlate` for that check, and a widget going back to the pool drops its
`widget.plate` so a stale plate cannot be re-anchored to.

`GetQuestGreenRange` is what draws the grey line, and a client without it gets
green for everything below you instead. Grey is a claim that the kill is worth
zero, and that claim needs the number the shim could not get. `bars level off`
takes the whole tag away, stripe included.

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
gone: threat is the colour of the gauge and of the edge, and the number is still
written on the line above.

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
is moot and `CameraState()` says so. Off by default, because marking is a
headline feature and it is not a fix, it is a trade.

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

Tracked debuffs are Sunder Armor, Demoralizing Shout, Thunder Clap and Rend,
matched on localised name so all ranks count and another warrior's Sunder shows
up desaturated rather than missing. Add Hamstring (1715), Piercing Howl (12323)
or Mocking Blow (694) to `TRACKED_SPELLS`.

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
`StatusTrackingBarManager` are deliberately in neither list.

**Frame skin.** The player frame, the target frame and target of target,
wearing the enemy bars' look: flat fills, one pixel edges, a square portrait,
and the class colour on the gauge and on the edge around it. `/wk skin off`
puts every piece back without a reload. On by default, for the same reason the
bar art strip is.

Nothing is rebuilt. Building three frames from scratch would mean earning back
click targeting, the dropdown, target auras and the cast bar, and it would
fight the Edit Mode layout this addon already carries, so the skin restyles
Blizzard's frames in place instead.

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

**The anchor is measured, the size is a setting, and the size is now pixels.**
Only the client knows where the frame sits, so the block is placed on the
portrait's own first anchor. Only you know how tall you want it, so the height
and the width are `/wk skin height` and `/wk skin width`, and since the block
went on the pixel grid those two numbers are counts of screen pixels rather than
of UI units. On a 1440 tall screen at UI scale 0.65 one unit used to buy 1.22
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
boundary and each has a direction. `Pixels()` brings a measurement in: a frame
width read off `TargetFrame` is 232 of Blizzard's units, not 232 pixels, and
comparing it against a setting that counts pixels is what makes a clamp fire
when it should not. `ns.Pixel(frame)` takes a size out: a badge that should be
18 pixels is written on Blizzard's region as 18 times that.

The two gauges avoid the question entirely. Each bar is pinned corner to corner
onto a rail, an empty frame inside the box, rather than given a height. The
client resolves an anchor on the screen rather than in either frame's units, so
the bar's four corners are our whole pixels and nothing about the bar had to be
converted or rounded to get there.

What the grid cannot fix is where the block starts. It hangs off the portrait's
own anchor on a frame that is not on the grid, so the origin is a fraction of a
pixel no addon can read, exactly as a bar on a nameplate takes its origin from
wherever the mob is standing. The geometry is exact; the origin is Blizzard's.

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

**Three frame levels, and they are the whole z-order.** The box sits at the
unit frame's own level, because the portrait is a region of that frame and a
box one level up would cover it. The two status bars sit two levels up. Every
piece of text sits three levels up, on `entry.top`, because font strings
underneath a status bar is exactly what the first version shipped: the player's
name and level were drawn and then painted over by the health bar.

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

**The block never draws outside the frame it is skinning.** Blizzard's art can
overhang its own frame and ours must not, because the space around these
rectangles is not empty: the target's buffs and debuffs run along the bottom of
the target frame and target of target sits in the same strip. The gauge is
clamped to what is left of the frame's width once the portrait has taken its
square, and the square is clamped to the frame's height.

That clamp is a guard, not a guarantee, because target of target is parked on
the aura row by Blizzard itself and ours is opaque where theirs is mostly not.
So each of the three frames has its own switch under the part's switch,
`/wk skin tot off` being the one to reach for.

**`/wk skin probe` prints what the client answered.** Frame size, whether the
portrait resolved, the portrait's recorded height and first anchor, the health
bar's recorded width, and the name of every region hidden. Every number the
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

The tick runs at 5Hz, the same rate the enemy bars run at, and for the reason
the artwork part does not use events either: the event names carrying health
and power have been renamed twice between these two clients and a missed one is
a bar that lies.

**Re-applying is not the same as writing.** The tick still has to be the last
word on the bar fill and the portrait crop, because Blizzard's code puts both
back whenever it swaps the art underneath. It reads back first now. A colour
texture answers no file path, so a bar that is still flat costs one comparison,
and the moment `UI-StatusBar` comes back the path answers and the write happens.
The crop compares the left coordinate the same way. Across three frames that was
300 texture writes and 150 crop writes every fifty ticks, all of them writing
the value already there, and it is zero. Where a client has no `GetTexture` the
write stands unguarded, which is what this did before and is the safe half to be
wrong on.

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

## Commands

    /wk                          open the settings panel
    /wk panel | options | config the same thing
    /wk status                   one line per part
    /wk help                     the command list, gathered from the registry
    /wk lock | unlock            both frames
    /wk reset                    positions, size, width, offset
    /wk size 44                  charge icon, 16 to 128
    /wk mark on|off              marking, all paths
    /wk markkey skull CTRL-BUTTON1   one key per mark, or none to clear
    /wk markkey cross|moon <key>
    /wk targetmark on|off        the ctrl-targeting fallback
    /wk charge on|off
    /wk charge always|ready      always visible, or only when usable
    /wk charge marker on|off     the icon in the world
    /wk charge marker size 40    16 to 96
    /wk charge marker offset 0   nudge it up or down the plate, -60 to 60
    /wk charge soft on|off       action targeting driven off combat, or yours
    /wk charge weapon Bloodspiller   equipped into slot 16, "none" to drop the line
    /wk bind SHIFT-Q             take a key, override binding only
    /wk bind none                hand the key back
    /wk switch TAB               next enemy and swing at it, override binding only
    /wk switch none              hand that key back
    /wk bars on|off
    /wk bars mode auto|plates|list
    /wk bars style replace|attach
    /wk bars offset 0            nudge the bar on the plate, -60 to 60
    /wk bars marker on|off       ours, or hand the marker back to Blizzard
    /wk bars level on|off        the mob tag, XP colour and reaction stripe
    /wk bars max 8               list mode only, 1 to 15
    /wk bars width 180           a bar on a plate and in the list, 120 to 400
    /wk skin on|off              square class-coloured player and target frames
    /wk skin player|target|tot on|off   one frame at a time
    /wk skin height 34           18 to 56, the block's height
    /wk skin width 168           90 to 280, the gauge's width
    /wk skin heals on|off        the incoming heal slice on the health gauge
    /wk skin probe               what this client answered for each frame
    /wk buttons apply            fill the bars with the warrior loadout
    /wk buttons restore          put back exactly what was there before
    /wk buttons                  what it would do, and whether a backup is held
    /wk ranks                    how many bar slots are holding an older rank
    /wk ranks refresh            move them all up to your best rank
    /wk art on|off               Blizzard bar art, off by default
    /wk ui                       what is baked in, and whether Edit Mode answers
    /wk ui save                  capture the active Edit Mode layout
    /wk ui apply                 import the baked layout and make it active
    /wk ui auto on|off           import it on a client that does not have it

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

It does six things and exits non-zero on any finding. The bar is zero warnings
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
6. Runs `scripts/harness.lua`, which loads every file in TOC order against a
   stub of the client, puts two nameplates up, drives the enemy bars ticker and
   then asserts the things reading the source cannot settle: that the grid
   resolves to one unit per pixel on a screen that is not 768 tall, that a
   widget's geometry is a whole number of pixels once the client's fractional
   measurements have been through it, that the icon crop lands on a texel
   boundary, that the driver was told how much room a bar wants, and that fifty
   ticks stay under the allocation gate. Those gates are ratchets: each sits
   just above the current figure and the next improvement lowers it in the same
   commit. The bars' gate went in at 5.0 covering 4.10 and is 0.5 covering 0.17.

   It also stands up stubbed `PlayerFrame`, `TargetFrame` and `TargetFrameToT`,
   runs the skin against them, and asserts that the blocks the addon owns are on
   the grid and whole, that both gauges are pinned to their rails, that the
   anchor offset was converted and not used raw, that the badge widths are even,
   and that the tick writes neither a bar fill nor a crop it has already
   written.

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
7. Runs luacheck over the tree.

The harness is not a client. Every API in it answers what that file says it
answers, so a stub that returns the wrong thing is a test that passes and a
client that does not. It proves the code runs and the arithmetic lands; it
proves nothing about whether the game agrees.

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
- Whether the portrait's first anchor is a corner. The block is placed on that
  anchor whatever it is, so a portrait anchored by its centre puts the block's
  centre where the portrait's was and the square lands a little off. `side` and
  `bar` in `SPECS` are the only numbers to change if it does.
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
