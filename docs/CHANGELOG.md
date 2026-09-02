# Changelog

## Unreleased

### One filtered event registration, in Core with the other shims

`Core/Core.lua` opens by saying it is the client shim layer: about thirty
questions the two clients answer differently, each asked once. Filtered event
registration was not one of them. Six files tested
`type(events.RegisterUnitEvent) == "function"` themselves and wrote a
two-branch registration under it, and four of the six wrote the same comment
above that explaining why UNIT_AURA unfiltered is thousands of events a fight.

`ns.RegisterUnitEvent(frame, event, unit)` takes the frame, the event and the
unit, calls the filtered register where the client has one and the plain one
where it does not. The six branches are gone. Every caller still reads the unit
off the payload, because that is what a client without the filtered call
requires and it costs one comparison where the filter already ran.

`UnitFrames/PlayerCast.lua` keeps its `pcall`, on the outside now. None of its
seven `UNIT_SPELLCAST_*` names is proven on both clients and a register that
raises would take the other six down with it. The other five sites register
names both clients carry and stay strict, so a name typed wrong there is an
error at load rather than a handler that never fires.

### A row with a hint says so, with a `?` in the corner

Hints have been drawn in the addon's own tooltip on hover for a long time, which
costs the page no vertical space and is the right shape. Nothing said one was
there. A page full of hints looked like a page with none, and the only way to
find one was to sweep the cursor down the column.

There is a `?` in the right corner of any row that carries a hint now, dim until
you hover the row and in the accent colour while you do. The controls on that
row slide left to make room; a row with no hint reserves nothing. The sentence
still opens on hovering the row rather than on hitting a twelve pixel target,
because the row is what you were reading.

A hint can be a function now, for a sentence that is different every time it is
read. The zoom rows are the first: each one says which stop that screen is on
and whether the stop keeps a hairline sharp. That was a reading under every row,
which is twenty three rows of prose on a page whose whole point was to be
compact, and it is a hover on the row it belongs to instead. Both zoom lists
lost about a third of their height.

The panel's prose budget went from 25,500 to 27,000 to pay for the twenty three
sentences, which is the largest raise on that list. It is worth saying what the
budget does not measure: those sentences replaced twenty three readings that
were on the page permanently, so the prose you see went down while the number
counted went up. A hint is read one at a time, on the row you hovered. Telling
those apart is a change to what the budget means and it is not being made in the
commit that would benefit from it.

### Target of target is on the screen again

The skin took that frame over completely. It sizes it, anchors it under the
target block, hides the client's artwork on it, draws its own square over it and
paints the unit's colour and four numbers onto it five times a second. The one
thing it never did was put it up. Whether that frame appears was left with the
client, which decides it behind a console variable and three tests on your
target, inside a method no addon can see the result of. A frame the addon has
taken over that far cannot have its visibility owned somewhere else, and the
symptom was the block being built, measured and painted where nobody could see
it.

`Block.Reveal` answers it now, on the same pass that paints the block. The test
is the client's own with the console variable dropped: your target exists, your
target has a target, your target is not you, and your target is alive. Not one
of those four asks what the unit is, so it holds the same for a mob, a quest
giver and a player of either faction. Showing a secure unit button is protected,
so a change combat refuses waits for the pull to end like every other one the
skin makes, and the client's own show goes on working through a fight.

Nothing here fights the client. Its driver compares that frame's shown flag
against whether the unit exists and only acts when the two disagree, so a frame
this puts up is a frame it leaves alone. `/wk skin probe` says `on screen` or
`not drawn` against target of target, and the harness now stands that frame up
hidden the way the client's own template declares it, so a skin that never puts
it up fails instead of passing every assertion about the block drawn on it.

### Every screen carries its own zoom, in tenths

One number sized every window in the addon. Shrinking the map so it sat beside
the quest log shrank the quest log with it, which is not a compromise anybody
would have chosen if the two had ever been separable.

They are now. There are two pages under The screen, Zoom: windows and Zoom: on
screen, twenty three rows between them: the map, the quest log, the bags, the
mail, the merchant, the character sheet, the adventure guide, the breakdown, the
clutter window, the chat window, the options panel, the confirm box, the
tooltips, and every part of the HUD that was already sized on its own. Scale the
map down and the tooltips up in the same sitting and neither moves the other.

It is two pages rather than one because one did not fit. Twenty three rows with
a sentence under each ran to a thousand units of stack in a view that holds
three hundred and fifty, so the row you opened the page for was three screens
down, and a control you cannot reach is a control you do not have. The windows
and the things drawn over the world are the two halves anybody thinks in, each
fits without scrolling, and the harness asserts the height rather than trusting
it. The sentence under every row went with the split: it said whether that stop
kept a hairline sharp, twenty three times, and the reading at the foot of each
list answers that for every row at once.

The step is a tenth, from 0.5x to 3x. It was a quarter for windows and a whole
number for anything you read mid fight, and the argument for the whole number
was that a bar you glance at during a pull is worth keeping pixel exact. That
argument is about one stop being better than another and it was being made by
putting the other stops out of reach. Every row says, under itself, whether the
stop it is on keeps a hairline sharp or draws it soft, so the cost is quoted
rather than decided for you.

`/wk scale` lists every screen and what it is drawn at. `/wk scale map 0.8` sets
one. It is not called `zoom` because Comfort already answers that word and means
the camera, and not `size` because Charge answers that one and means the charge
button in pixels.

**What the page is made of.** A part declares its sizeable screens in its own
`ns.Register` call under `zooms`, giving a key, a label and what to run after
the number changes. `ns.Zooms()` walks the registry and the page draws a row per
entry, so it names no feature and cannot go stale: a part that adds a window
turns up, and one that stops drawing a screen takes its row away. Core keeps its
promise that an eighth part must not mean editing Core.

**What came out with it.** `UI.Window` takes `opts.zoom` as a getter now and
keeps its own frame on the grid. Ten windows carried the same two lines in a
listener of their own, which is todo.md item 19 and was six windows worse than
the item said when it was written: six new windows landed while it sat open and
every one of them copied the pair. Seven of those listeners are gone entirely.
The four with real work in them pass `opts.rescale`, which receives the rezoom
as a function rather than running before it, so the character sheet can still
defer the whole thing in combat and the three that lay themselves out in their
own units can still do it in the right order.

The chat window had worked all of this out first. It has had its own zoom, its
own key and its own range since it was written, on the argument that a window
you have up all evening is a different question from a panel you open for a
minute. It is one row on the page like everything else now, and the range it
kept privately is the range the whole addon runs on.

**On login.** A player who had dragged the old UI size slider has that number
written onto every window still sitting at its default, once, and `uiSize` is
dropped from the account file. A screen already sized on its own keeps what it
was given. The shipped default for a window is 1.3 rather than 1.25, because
1.25 is not on a tenth stop and a default the page cannot reach is a default the
reset cannot restore.

### One square on the cooldown page was dead to the mouse

Two defects, and both of them read the same way from the chair: one spell you
cannot drag while every other square works.

`UI.DropSquare` built its button as a child of the page and anchored it over the
square with `SetAllPoints`. An anchor is not a parent. Hiding the square left
the button shown, holding the rect the hidden square still had, taking every
click and every drag that landed on that patch of the page. The cooldown page
hides squares it is not using, so the first time you dragged one off the row it
left a live invisible button behind on the row, and whatever square that landed
on was dead. Nothing on screen could show it. The button is a child of the
square now, so the mouse follows the picture.

And `Landed` asked `GetMouseFocus` and only that. `Buttons/Trace.lua` had
already learned the hard way that this client answers "what is the cursor over"
under one of two names and neither can be assumed; its first live run printed
every gesture and never once named a frame. That probe is `ns.MouseFocus` in
Core now, asking both, with Trace and the page reading the one answer. Asked
under one name on a client that carries the other, a square whose contents will
not go on the cursor came off the row and landed nowhere, which is exactly what
a square you cannot drag looks like.

Right clicking a square under the row puts it back on the end of its line now,
which is the mirror of right clicking one on the row to take it off. That pair
is the one gesture that works whatever the client answers for the frame under
the cursor. Forgetting a spell you added yourself is `/wk cooldowns drop <id>`
and not a click: off the row and gone for good look identical the moment after
you press, and the one that cannot be undone by dragging does not get the easy
button.

### The cooldown row is arranged by dragging it

The page that decided what was on the row was a list of twenty-three rows with
five controls each: a tick box for whether the square was drawn, two buttons
that walked it one place along its line, a third that sent it to the other line,
and a cross for one you had added yourself. Every one of them described a
picture instead of being one, and the picture was on the other side of the
screen. Arranging six squares meant reading the row out as a list, editing the
list, and then looking up to see what you had done.

So the page draws the row. `Cooldowns/Panel.lua` lays out the two lines at the
sizes `Row.lua` draws them at, big squares along the top and small ones docked
under, with the squares that are off the row under a caption saying so. Drag a
spell out of your spellbook onto either line and it lands where you dropped it,
in front of the square you dropped it on. Drag one from a line to the other and
it changes size, which is the whole reading of the two lines. Drag one off and
it stops being counted and turns up under the row where you can drag it back.
Right click does the same in one press, for the hurry and for a client with no
`GetMouseFocus`.

Two calls carry all of it. `Cooldowns.Place` puts one key on one line at one
place along it and switches it back on, because a line and a place are one
gesture and a pair of calls that did them separately would draw the row twice
and leave it wrong in between. `Cooldowns.Put` is the same thing for a spell off
the cursor, and it looks the id up against every id every entry carries before
it adds anything: a spell the row already knows about moves rather than arriving
a second time to count the same cooldown down beside itself. `Cooldowns.Add`
follows that rule now too, so typing the id of something you had switched off
switches it back on instead of refusing on the grounds that it is already there.

A drag out goes one of two ways and the page picks between them once, at the
start, on whether the cursor took what was in the square. A spell rides the
cursor, which is how every icon in the game moves and is why one dragged off the
row can be dropped on an action bar. An equipped trinket cannot be picked up
without unequipping it, so nothing goes on the cursor, the square is remembered,
and the client is asked where the button came up. The two paths cannot both fire
for one drag, which is what saves this file from having to know what order the
client fires them in.

`ns.CarrySpell` is in Core with the other client shims. `PickupSpell` answers to
a name on one client and an id on the other, and `Buttons/Layout.lua` had the
only probe that tried both; the options page now asks the same question, and two
copies of a probe is two answers to it.

The picker that offered what your class knows is gone, because dragging out of
the spellbook offers all of it and offers it in the place you are looking. The
field that takes a spell id stays, for a rank you have not trained and for a
spell an item casts, which are the two things the book will not hand you. The
page lost 235 characters of prose on the way, and the budget in
`16-options-window.lua` came down with it.

### Buyback, which went off the screen with the client's window

The merchant window replaced the rack and not the tab beside it. Selling to the
wrong vendor is recoverable for an hour, and that is the argument three other
parts of this addon lean on: the grey sweep sells for you, the bag window's row
sells four things in one press, and `Comfort/Destroy.lua` will not destroy
anything a vendor would take because the vendor is the safer door. All of that
is true because a sale can be undone, and the only place in the game it can be
undone from was behind `MerchantFrame`, which spends the whole session parked
off the side of the screen so its cross cannot end the conversation by accident.
Parking it took buyback with it.

So the window has a tab strip across the top now. `Rack` is what he sells,
unchanged. `Buyback` is the last twelve things you sold, newest at the top, at
the price you were paid, and a click takes one back. The window grew by the
height of the strip rather than losing a row of stock: `HEIGHT` was always how
tall the rack is, and the strip is added on top of it once the strip has said
how tall it came out.

`Merchant/Buyback.lua` is `Stock.lua`'s shape for the other rack, and the two
differ in the two places the racks do. It is not in piles. Stock files a shop
under the bag window's class headings because you are looking for a kind of
thing; you open buyback for one reason, which is the thing you just sold, so the
order is the order you sold in and there are at most twelve. And the slots are a
range rather than a list: `GetNumBuybackItems` answers the highest slot in use
rather than how many things are in it, and a slot you have already taken
something out of answers no name at all, so the walk runs the range and skips
the holes. A window that read the count as a length would draw a blank row for
every gap, and nothing in the client says so out loud.

One pool of rows draws both. `Merchant/Rows.lua` used to name `ns.Stock` for the
four questions a row asks about an entry: is it in stock, how many are left, can
you pay for it, buy it. It takes whichever rack answers them as an argument now,
and the row records the one that painted it, so a press buys back the thing on
the line rather than the rack row that was drawn on the same button a moment
earlier. That last part is what the harness asserts: the rod cost a thousand to
take back and the rack row under it was the water at twenty five.

`/wk merchant sold` says what is on the rack, and the panel reads it live.

### The bag window at a merchant

Standing at a vendor with the bag window open, there was no way to sell
anything but by right-clicking each grey, no way to pay for the mending, and
nothing on the screen that said which of the things in front of you a merchant
would even take. The two chores had been in the addon since `Comfort/Vendor.lua`
and `Comfort/Repair.lua` shipped; the window you look at while you do them knew
nothing about either.

`Bags/Merchant.lua` is the row that answers all four. While a merchant session
is open the window grows one control row across the top: `sell 4 greys`, and
`repair 1g 20s`. Neither button does the work. The sale is `ns.Vendor.Run`, the
repair is `ns.Repair.Run`, both of them the parts that already own a ticker, the
refusals and a harness section, and a second sweep written into the bags to
avoid naming them would be a second set of rules about what a vendor takes.

The squares learned the other half. A grey a vendor will pay for wears a coin in
its top corner, which is the glyph the loot feed's money chip already draws. A
square holding something no merchant will buy goes dim and desaturated for as
long as you are standing there, and quest items are most of what that catches.
Both readings are the client's own sell price off the scan the window has
already done: `ns.ItemValue` hands back the grade and the price in one call, so
`entry.price` costs the scan nothing, and nought means a vendor refuses it while
nil means this client has not cached the item yet and is read as a refusal too.
That is the same rule the junk pile follows and for the same reason: a square
drawn as sellable on a guess is a square a merchant then refuses.

The row is drawn only when there is something on it. A merchant who does not
mend and a bag with no greys in it get no row at all, which is the rule the
piles below it already follow. With the automatic sale switched on it is usually
one button for a moment and then nothing, because the sweep has emptied the pile
it was counting.

**The session is the bag row's own flag.** `MERCHANT_SHOW` and `MERCHANT_CLOSED`
are the two edges of a merchant, three parts of the addon now hold both, and
there is no order between two frames on one event. A row reading
`Comfort/Repair.lua`'s flag would be right or a frame late depending on which
handler the client ran first. What it takes from that file instead is
`Repair.Quote`, which asks `CanMerchantRepair` and `GetRepairAllCost` rather
than a flag and is the same answer whoever asks it; `Repair.Cost` is that quote
behind the session gate, for every caller with no merchant reading of its own.

`Vendor.Run` is the sale as a press rather than as an event, and it ignores
`sellTrash` entirely. That setting decides whether opening a merchant starts a
sweep; a press is not a merchant opening, and the button is there for the player
who keeps the automatic sale off or held shift at this vendor.

The harness tells the three merchant parts apart by flicking two settings, one
at a time: selling off takes the sweep off `MERCHANT_SHOW`, the bag window off
takes the row off it, and the frame still listening after both is the repair.

### The fanfare stopped shipping its own song

`src/Media/BestAround.mp3` is five seconds of a record Joe Esposito made in
1984, and this repository is public. Length is not a defence and neither is the
fact that BestAround has been handing the same file out since 2007, so the file
is gone from git and out of the release zip. Nothing else about the fanfare
changed. The path, the event, the master channel, the throttle and both slash
words are as they were.

What is left is a part that names a file it does not carry. Put anything the
client can read at `Media/BestAround.mp3` and it plays. Install BestAround and
you already have the one everybody means. With nothing there, `PlaySoundFile`
refuses and `/wk` reports it, which is what the part already did on a client
with no sound at all.

Both gates learned the new rule rather than losing the old one. `check.sh`
exempts exactly one name from "a Lua file names this and it is not there", and
in exchange fails if that name is ever tracked again, because the machine that
plays the fanfare is also the machine a wide `git add` runs on. `release.sh`
puts the pair in `IGNORE` and drops them from the list the zip must contain, so
the copy that takes all of `src/` cannot carry them by accident. The licence
file went with the sound: it describes a file no clone has, and a licence for
nothing is a thing `check.sh` already fails.

### A dungeon log, three columns wide

Neither of these clients has an adventure guide, so the two questions everybody
asks before a run have never had an answer in the game: which dungeon am I for,
and does anything in it replace what I am wearing. `Dungeons/` is eight files
answering both. Every boss in the game down the left, grouped by dungeon and in
level order. The client's own map of the one you picked in the middle, with the
bosses marked on it. What the one you are reading drops on the right, in the
client's own grade colours with the client's own tooltip on each row. Shift-L
opens it.

**The data is generated, not remembered.** `Dungeons/Baked.lua` is forty
dungeons, two hundred and thirty seven bosses and eight hundred and fifty six
drops, and not one number in it was typed. `scripts/bake-dungeons.sh` reads
Questie's own npc and item databases, which Questie generates from the client,
and resolves a hand-written list of boss names into creature ids, levels and
drop tables. The hand-written half is the editorial half and nothing else: which
dungeons there are, and what order their bosses are fought in. A boss name in
that list Questie cannot place stops the bake and writes no file, so the two
halves check each other every time it runs.

That split is the whole design. An item id nobody generated is an id somebody
remembered, and an id remembered wrongly does not draw a blank. It resolves to a
real sword, with a real icon and a real tooltip, that this boss does not drop.

**So the client checks it again at draw time.** The book carries each drop as an
id and the name it had when the bake read it, and `Dungeons/Loot.lua` compares
that name to what the client says the id is. A row the client disagrees with is
dropped and counted, and the count is a reading in the settings window. A wrong
book shows fewer items, never the wrong ones.

**The map is drawn from tiles the client will not hand over.** Ask `C_Map` about
a dungeon on either of these clients and it answers nothing, for two different
reasons. The 1.15 one has no dungeon maps in its map tree: fifty four rows, a
world, six continents, the zones and three battlegrounds, and not one node of
the dungeon kind. The 2.5 one has a hundred and four of them, named and parented
correctly, and files art for not a single one, so `GetMapArtLayers` comes back
empty on every dungeon in the game. It ships no map group table either, so it
cannot say that the Deadmines and Ironclad Cove are two floors of one place.

Both of them ship the pictures all the same, twelve tiles to a floor under
`Interface\WorldMap`, and a texture is drawn by path whether or not anything in
the client's own tables still points at it. So `Dungeons/Sheets.lua` is the join
and it is generated like the book: `scripts/bake-dungeon-maps.sh` reads
Blizzard's own map tables, takes the floors and their names out of one, the
tiles out of another and the map ids out of the 2.5 client's own, and checks
every path against the listfile before it writes one. Thirty five places, seventy
eight floors. A path nobody checked is a blank rectangle waiting to happen: a
texture that does not resolve draws nothing and says nothing about it.

**Where a boss stands is learned, because nothing on this machine knows it.**
Questie files every creature inside an instance at the coordinate `{-1, -1}`,
which is its way of saying it does not know, and no call on either client will
answer either. So `Dungeons/Seen.lua` writes the position down the first time
you open that boss's loot window, from where you are standing, which is where
the corpse is because you walked to it. A dungeon you have never run draws its
map with no marks and a line underneath saying so. The alternative was a
coordinate somebody remembered, which is a wrong mark on the one screen you
opened to find out where something is.

The same event fills in the loot. Questie's Classic database carries every
creature's whole drop table, which is where the eight hundred Classic drops come
from; its Burning Crusade database carries only what its own quests need, which
is why the fifteen Outland dungeons come to about forty. Those fill in from your
own runs, one loot window at a time.

**The picture is the widget the other two maps are drawn on.** `UI/Chart.lua`
gained three things and every existing caller is unchanged by all three: a
square takes the caller's colour, a square takes the caller's size, and a point
carrying a `label` draws that number on the mark. The number is what joins the
mark to the row down the left, which is the whole of how the picture answers the
column.

`ns.CreatureId` moved into `Core/Core.lua`. The quest log's drop ledger and this
one both read a creature id off the same loot window, and the GUID format is a
client fact rather than a part's private knowledge.

### One bag window, with what you carry sorted into piles

Five bags open as five windows, in the order you happen to have them on your
belt, and finding the potion means reading a hundred squares. `Bags/` is five
files replacing that: one window, everything you are carrying grouped under a
heading, and how many slots are free along the bottom next to your gold.

**The piles are the client's own item classes and nothing here decides them.**
`GetItemInfoInstant` reads the client's item database rather than a cache, so it
cannot come back nil for something sitting in your own bags, which means the
piles are right on the first frame after a login and are in whatever language
the client is in. That is the whole of the categorisation: a table of sixteen
lines, an order, and no rules anybody has to write or maintain.

Two piles are not a class and both earn the exception. Junk is quality zero
whatever class it is, because what every grey has in common is that a vendor is
where it goes. Empty is the absence of an item, drawn as a pile at the bottom so
the free count is a thing you can point at rather than a number to take on
trust. An item the client has not graded yet stays in its class pile rather than
being called junk on a guess, and moves when `GET_ITEM_INFO_RECEIVED` arrives.

**Every square is the client's own bag button.** It inherits
`ContainerFrameItemButtonTemplate`, which is what Blizzard's bags and every bag
addon in the game are built on, so the click, the drag, the stack split, the
shift-link and the merchant sale are the client's code. None of that is worth
reimplementing: a right click on a bag slot means eat, equip, open, sell or
attach depending on which window is in front of you, and the rules for which are
inside the client. It also means Mail/Bags.lua keeps working with no change at
all, because that file takes over `ContainerFrameItemButton_OnClick` by name and
a square built on this template arrives there like any other.

The art is not the client's. The template's icon, count, quality border and
normal texture are stripped and the square is drawn again in the addon's
palette: a sunken ground, a hairline in the item's own grade colour, a crisp
twenty seven pixel icon and a flat count. The hover is the addon's own box, for
the reason every hover in this addon is: two designs on one screen is the defect
that box exists to stop.

**Nine calls, not one.** B is `ToggleBackpack`, the bag buttons on the bar are
`ToggleBag`, the binding for all of them is `ToggleAllBags`, and then there are
the six the client calls on your behalf, of which `OpenAllBags` is the one that
matters: it is what a merchant and a bank do. Take the toggle alone and the
first vendor you speak to puts five of Blizzard's bags on the screen beside this
window. All nine are replaced and all nine are handed back exactly when the
switch goes off.

This is the one part of the addon that will argue with another bag addon.
Baganator and Bagnon take the same nine names and whichever loads last holds
them. That is not a bug to work around, it is what replacing the bags means, and
the settings page says to run one or the other.

`/wk bags` opens it, `/wk bags columns 10` decides how wide, and
`/wk bags count` says how many slots you have and how many are free.

### A world map with a list of zones down the side of it

The client's world map navigates by clicking a continent and then the piece of
coastline you think is the place you meant. That is a fine way to learn a world
and a bad way to answer "show me Desolace", which is the question anybody who has
played for a week is actually asking. `Map/` is five files replacing it: every
zone in the game in a column down the left, the one you picked drawn beside it at
the size the client draws a zone, Questie's markers on top of it, and a line
along the bottom saying who that zone is for.

**The column is the point.** One group per continent, one row per zone,
alphabetical inside each, and the zone you are standing in is the one it opens
on. Alphabetical rather than by level is a real choice: a list sorted by level is
a better list to plan an evening with and a worse one to find a name in, and the
level is on the screen anyway, in the footer, which is the half you cannot get
any other way.

The zones come out of the client rather than out of a list written down.
`Map/Zones.lua` climbs `C_Map` from the map you are standing on to whatever has
continents under it and walks down from there, so the column is in your own
language and covers whatever the build has. `/wk map zones` says how many it
found.

**The level range is a table, and that is worth being honest about.** No call on
either of these clients answers what level a zone is for. The client knows a
zone's name, its art, its shape and its children, and has never known that
Westfall is where you go at ten. So the ranges are compiled in, keyed on the map
ids read off Questie's own generated tables, and a zone with no row draws a
footer that says so rather than a number somebody guessed. A city says it is a
city, because an empty line reads as a table that forgot one.

**The markers are Questie's, read off Questie's own frames.** Not off its
database. Questie has ten thousand lines deciding which quests you can pick up,
which are the wrong faction, the wrong level, already done, or in a chain you
have not started, and it spends that decision on a frame per marker. `Map/Pins.lua`
walks the frames. So the map shows exactly what Questie shows, in the same art
and the same colours, and a Questie category switched off is switched off here
too. Both of its registers are read, so the flight masters and the trainers
arrive with the quests.

**The wheel zooms, at the cursor.** The picture is the widget the quest log's map
already was. `Quests/Chart.lua` had said in its own first paragraph that nothing
in it knew what a quest was, so it is `UI/Chart.lua` now, with one thing added:
a point can be somebody else's icon instead of a coloured square.

Blizzard's map goes in the attic and M opens this one, under a switch that hands
both back in one tick. The cage is on the once-a-second pass rather than done
once at login, because `WorldMapFrame` is behind a load-on-demand addon on some
of these builds and a one-shot apply would leave the client's map on the screen
for the session.

### A character sheet of the addon's own, with the number the client has never drawn

The client's character window is five pages wearing one frame, and the largest
single area of the first of them is a picture of your back. `Character/` is nine
files replacing it: your gear with what it adds up to in a column beside it, your
skills, your standings and your loadouts, on four tabs the C key opens.

**Hit and miss is the reason it exists.** No client on either of these versions
has ever put your miss chance on the character sheet, because the client knows
your hit rating and not your hit chance, and the gap between those two is the
difference between a set of enchants that was worth buying and one that was not.
`Character/Stats.lua` computes it: how often a special, a white swing and a spell
go wide against a target of your own level and against the three above it, with
the hit off your gear taken off each. Each of those numbers is the hit you still
want, so nothing says it a second time.

The formula is four constants and it is checked against the three figures
everybody quotes. A character at the weapon skill their level allows misses
5.5% one level up, 6% two up and 9% three up, those three are not derivable from
each other, and the only shape that lands on all three is a tenth of a percent
for each of the first ten points of the target's defence over your weapon skill
and six tenths for every point after them. Section 52 of the harness closes the
stub's ten point shortfall, reads all three back, and opens it again, so a
formula that ignored weapon skill fails one half of that and a formula that got
the second slope wrong fails the other.

What it cannot see is talent hit, and the row says so rather than being quietly
low. The client rates hit that came off gear and has no call at all for the flat
percentage a talent grants.

**The gear page draws nineteen slots and four numbers.** The four are the ones
the client's own sheet has never had: what your gear averages, how worn it is,
how many slots are empty, and how often you miss. Every square carries the
durability of what is in it as a line along its bottom edge, green through amber
to red, because durability is the one fact about your gear that changes while you
play and the client keeps it behind a hover. Clicking is the client's own two
calls, the cursor swap FrameXML's own paperdoll button makes and the one that
takes a piece off, and both are refused in a fight with the reason printed rather
than failing silently.

**The skills page is bars rather than a list of numbers.** The client's skill tab
draws the same length bar for a weapon skill you have capped and a profession you
started this morning. Every row here carries how far along it is, and a weapon
skill under the cap for your level carries the sentence saying what the shortfall
costs you against a boss, which is the same number the hit page is computed from.
A weapon skill is told from a profession by what it caps at and whether it can be
abandoned, never by the header it sits under, because every header on that page
is a localised string.

**Reputation is here because hiding the client's window would otherwise delete
it.** Standings are drawn in three colours rather than the client's eight-shade
gradient: red for somebody who would attack you, grey for somebody with no
opinion, green for somebody who has one. What does not come across is the at-war
tick and the watched-bar picker, and untick the switch to get either.

**The loadout page moved.** It was a section of the options window, between the
chat opacity and the minimap shape, and it is the last tab here. A loadout is a
pair of weapons on a key, so it belongs on the page with your weapons on it.
Nothing about the page changed: `Loadouts/Page.lua` hands the same rows to the
same widget kit and this window is the host instead of the options window, which
is the whole of what the kit's host contract was written for. `Loadouts/Feature.lua`
has no `panel` any more.

**Blizzard's sheet goes in the attic and C opens this one.** The switch is
`hide Blizzard's character sheet`, on the Blizzard's own frames page with the
other nine, because there is one place in this addon where a frame of the
client's is switched off and a tenth switch somewhere else would be a tenth place
to look. `ToggleCharacter` is swapped for one that opens the matching tab, which
is the second global function swap in the addon after the quest log's. The two
pages this window does not draw, your pet's sheet and the honour tab, print a
line naming the switch rather than opening a tab that is not there.

The key swap cost one bug on the way in and the harness caught it. `TakeKey` built
its replacement function inside itself, the hide pass runs once a second forever,
and a closure per pass is three kilobytes per fifty ticks for the collector to
walk. The function is declared once at load now and the pass compares before it
writes.

`ns.ItemLevel` joins the item shims in Core. `Character/Readout.lua` is the
column of headed rows the stats, skills and reputation tabs are all drawn in, and
it repaints a pool rather than building rows, because this client cannot destroy
a frame and a page handed a different number of skills every refresh would leak
one per row per refresh.

### The tooltip stays long enough to read, goes where you put it, and stops lecturing

Six changes to the box every hover in the addon opens.

It no longer vanishes on the frame the pointer leaves. Leaving a thing starts a
countdown of a second, and the box holds until the countdown runs out. Every
hoverable thing in this addon is small and most of them sit in a column, so the
cursor crosses two on the way to the one you meant, and a box that opened and
shut twice on the way was a box you never finished reading. Hovering anything
else replaces it on the spot, whatever is left of the clock, and a hover with
nothing to say takes it down rather than leaving it there for another second
pointing at something it is not about. `/wk tips linger 0` puts it back to the
client's own behaviour, which is to go the instant you look away, and the slider
runs to ten seconds for anybody who wants longer.

The blue line at the bottom is gone, everywhere. `hint` was a fourth band in
`UI/Tip.lua` carrying one quiet sentence about what to press or which switch
silences the thing, it reached twenty five call sites, and by then it was
furniture: a footnote under every hover in the addon is not read, it is a line
of the fight you are covering, and on the world hover it sat over the screen for
the whole evening. The band is deleted rather than emptied, and `scripts/check.sh`
fails on a subject that carries one, because a field that is silently ignored is
a field somebody writes again and cannot tell is doing nothing. The sentences
that were worth keeping were already in the settings window, which is where the
settings are.

The box can hang off a marker you place yourself. There were two answers to
where a hover opens and now there are three: the corner the client keeps its own
tooltip in, beside the thing you hovered, or `anchor`, which is a marker you drag
with the frames unlocked the same way you place the swing bars. Which corner of
the box lands on the marker is read off which quarter of the screen the marker is
in, so the box always grows away from the nearest edge. The corner is a long way
from the fight on an ultrawide monitor and beside covers what you are reading;
this is the answer to both, and it costs one drag. The setting is `tipPlace` and
it retires `tipDock`.

How big it reads is a number. The body was the addon's body size, twelve pixels,
and it is a setting between eight and eighteen now, with the title tracking it
a pixel above so the pair stays a pair at every stop. The window zoom is not the
answer to this question: it scales the air as well as the text, and a tooltip
that grew its own padding to buy a readable sentence would cover twice as much
of the fight.

A creature you point at says what it is carrying that a quest of yours wants.
`Quests/Drops.lua` reads Questie's own tooltip registry, which is the only thing
on either client that knows a boar drops the hide, and draws the quest the item
feeds and the count the client is keeping: three of eight. Under it, where there
is one worth printing, is a drop chance, and that one is measured rather than
looked up, because no database on either client carries one. The addon counts
the corpses of that creature you open the loot window on and how many of them had
the item, and says nothing at all until there are ten of them: a fraction off two
kills is arithmetic pretending to be information. `/wk quests drops` says how
many creatures it has counted.

`UI.Placeable` picked up a twelfth HUD frame and `scripts/check.sh` a rule. The
marker is invisible and mouse blind while the frames are locked, which is the
only thing that keeps an empty frame in the middle of the screen from swallowing
the right button drag that turns the camera, and `51-placing.lua` holds it to
that with the other eleven.

### The quest log answers for the party, and abandoning asks first

Five changes, four of them in the left column, where a row used to be a mark, a
level and a name and is now a row you can act on.

A quest ready to hand in is marked with a tick. It was a `+`, which is the mark
for adding a thing rather than for having finished one, and it was a `+` because
the glyph face had no tick in it. It has one now, cut onto `V` by
`scripts/bake-glyphs.sh`, and the objective lines in the middle column take it
too: they said done with the same plus and saying it two ways would be worse
than saying it wrongly once. `V` is what a client that refuses the font draws
instead, which is the same bargain every other mark in the face makes.

The mark is a region of its own rather than two characters on the front of the
label, and it keeps its colour through the selection. `PaintListRow` throws a
row's own colour away for the row you are reading, so a log that said "finished"
in green alone said it least about the quest you had open.

Every quest row carries a share arrow and a cross. The arrow is drawn only on
the rows the client would hand over, because it refuses a quest nobody else
could take and an arrow on such a row is a control that fails silently when you
press it. The cross is on every row, because every quest can be abandoned.

The cross opens a question in the middle of the screen. The footer button used
to arm itself and abandon on the second press, with a line in the chat window
between the two, and both halves of that were wrong: the warning was in a window
you may not have been looking at, and the armed state was a button whose label
had changed by one word. `UI.Ask` is the replacement, one window shared by
anything that has to ask before it does something irreversible, and the footer
button goes through it as well.

A row says how many of the people you are playing with are on the same quest,
and its hover names them. Two things can answer that and neither always can, so
`Quests/Party.lua` asks both and merges on the name: the client's own
`IsUnitOnQuest`, which knows the party member running no addons and does not
exist on every build, and Questie's comms, which knows anyone running Questie
whatever their client will say. Nobody having it and nothing being able to say
both draw no number, because a `0` would be this addon claiming it asked and got
an answer. `/wk quests party` says which of the two is answering.

Clicking a quest in Questie's tracker opens this window on that quest.
`QuestieTracker.utils:ShowQuestLog` is the one function the tracker's click and
its right-click menu both go through, so `Quests/Tracker.lua` replaces it under
the same switch that takes the L key, keeps the original, and hands it back when
the switch goes off. A click on a quest you are not on falls through to Questie
rather than being swallowed.

The list column is thirty pixels wider and the window thirty wider with it, so
the middle column and the map come out the size they always were. That is what
the number and the two marks cost.

`UI.List` grew three things to pay for all this and every one of them is
general: a glyph column, a note at the right that is not an unread count, and a
strip of marks per entry with a `shown` that decides which rows get which. The
marks are drawn on every row rather than revealed on hover, because the cursor
moving from the row onto the mark leaves the row, and a strip that appeared on
hover would take the button away as you reached for it.

`scripts/check.sh` gained a rule while the two lists were open in front of it.
`UI.GLYPHS` and the `PICK` table in `scripts/bake-glyphs.sh` are compared as
text, so a letter added to the addon without rebaking the font, or baked and
never written down, fails the gate. A glyph string given a letter the face has
no mark on draws an empty rectangle and says nothing at all, at load, at lint or
in the harness, and that is exactly the failure this change could have shipped.

### The lock is a property of a frame now, not a call nobody repeats

`UI.Placeable` takes `lockable`. Eleven frames say nothing and take the default,
which is that `/wk lock` and the panel's button decide whether they can be
dragged. Five chrome windows pass `lockable = false` and are always movable,
because locking a quest log would be locking a window rather than placing a
piece of the HUD: you opened it on purpose and you will close it in a minute.

They were always movable. The difference is that it used to be a `Lock(true)`
called once at build and never again, so the only way to know a window ignored
the lock was to notice that nothing called it a second time. The chat window is
the one that asks for the lock, with `lockable = true`, because it is up all
evening in a corner you chose and it is furniture like the rest of the HUD.

A name and a rim are what a chromeless frame wears while you place it, so a
frame the lock never reaches has no state to wear them in. That combination
asserts at login rather than drawing a rim over the world all session.

`51-placing` in the harness is the gate. It drives `ns.Each("lock")`, which is
what the slash word and the panel button both call, and asserts that all eleven
HUD frames lose the drag and all five windows keep it, then that all eleven get
it back. Both halves matter: a frame that ignores the lock in both directions
passes the first on its own without being placeable at all. The client stub
records `RegisterForDrag` now, for the reason it already recorded `SetMovable`.

`UI.Window` gave up its footer to a `Footer` local beside `TitleBar`. The
constructor was at the hundred-line gate and `lockable` pushed it over, which is
the gate doing its job rather than a number to raise.

### One file owns dragging, and windows are one of its callers

Twelve frames in this addon can be unlocked and moved, and until now every one
of them wrote its own twenty lines to do it: `SetMovable`, `SetClampedToScreen`,
a drag that refuses while the frames are locked, a drag stop that reads the
point back and writes it into a setting, and a `Lock` that toggles
`RegisterForDrag`. Nine of them also drew a rim over the frame and a name above
it, because a frame with no chrome and nothing in it is a piece of empty screen
you have to find from memory. The clone scan found two of the copies matching
character for character, comments included: `Cooldowns/Row.lua` and
`Swing/Gauges.lua` carried the same note about a drag landing wherever the
cursor was, with one noun changed.

`src/UI/Placeable.lua` is the one of them now. A caller hands it a frame, a
function to take the finished anchor and, if the frame has no chrome, the name
to draw above it while you are placing it. It knows nothing about which setting
it writes, because `src/UI/` is not allowed to know the name of a setting, which
is the rule `UI.Size` and the tooltip's dock were already written to.

The split that let it reach twelve was chrome. `UI.Window` owned the background,
the hairline, the title bar and the close box, and it owned a broken half of the
placing too: it made every window movable and then had nowhere to put the
result. So the one window that has to remember its corner, the chat window,
overwrote the drag scripts `UI.Window` had just installed with a thirteenth copy
of them. Chrome was never the axis. Placing is one thing, chrome is another, and
`UI.Window` is a caller of `UI.Placeable` rather than a rival to it.

Two things came out with it. `ns.UI.Whole` is in `UI/Pixel.lua` beside
`ns.UI.Round`, where eight files had written their own copy of it, and the
header now says why the two are different functions with similar names. Round
takes a size from outside the grid and refuses to return zero, because a
hairline asked for and not drawn is a missing line. Whole takes a coordinate,
where zero is the left edge and a floor at one would be a bug. And the meters
were the one frame of the twelve that saved its offsets unrounded. Nothing said
so, because the other eleven agreed with each other rather than with a rule
written down anywhere. They round now, all of them, through the same line.

Three frames were re-anchoring their rim on every `Apply`, once per layout, for
no effect. The rim is anchored to the frame and follows it already.

Nothing became newly draggable and nothing stopped being draggable. The parts
whose own `Lock` has more to do than toggle a drag still do it: the experience
rails hand the mouse from the bars to the frame, the enemy bars show a header
only in list mode, and a feed lets go of its status strip so the corner you
reach for is the corner you can drag by.

Two drag sites are deliberately not on this. The charge button and the action
bar handles are dragged by a child handle that moves its parent, which is a
different shape from a frame you grab anywhere, and there are two of them rather
than twelve.

### You're the best around

Levelling plays five seconds of the Karate Kid chorus over the client's own
chime. The snippet is BestAround's, byte for byte: LittleJoey's addon from 2007,
fixed for 6.0 by Nephyrin, four files and one of them the song.
`src/Media/BestAround-LICENSE.txt` records where it came from and says plainly
that the recording is somebody else's and is not covered by this addon's
licence.

It goes out on the master channel rather than on the sound effects slider, so
somebody who plays with combat noise down still gets it. A turn-in that levels
you twice fires the event twice in the same frame, and the part throttles on the
clip's own length, so that plays once rather than over itself. `/wk ding` plays
it now, which is the only way anybody can decide whether they want it, and
`/wk ding off` ends it. Off unregisters the event rather than branching inside
the handler.

`check.sh` learned about sound. Media/ held three kinds of file and now holds
four: a sound is OGG or MP3 and carries a `<name>-LICENSE.txt` beside it the way
a font does, for a harder reason, because an audio file can be the whole of
somebody else's work rather than a glyph out of a set. A second rule catches the
other half of the same failure: every `Media\<file>` a Lua file names has to be
there. Neither of those failures says anything out loud in the game, which is
the whole reason both are gates.

### Enemy bars arrive sooner, arrive smoothly, and take a click along their whole length

Three things about the bars on mobs, and all three are the same complaint: the
bar is an instrument you read at pull range, and it was behaving like one that
only worked once the fight had started.

**Further out.** `bars distance` is `nameplateMaxDistance`, borrowed the way
`bars stack` borrows `nameplateMotion`, and it ships at 41. A bar is drawn on a
nameplate, so the range the bars work at is that CVar's and nothing else's, and
whatever the client was holding is handed back when the setting goes off. The
client clamps to a ceiling of its own without saying so, so the panel and
`/wk status` read the CVar back rather than repeating the number you asked for.

The range the setting offers is now the range the client will hold. It asks
once, by writing more than any client takes and reading back what stuck, and
puts the CVar back the way it found it. On the Anniversary client the answer is
41, and 41 is also where that client starts, so the old stepper walked up to 60
past a wall: the number moved, the bars did not, and the setting looked broken
because from its shipped figure onwards it was. Now the stepper stops at 41, a
saved setting above the ceiling is pulled down to it, and the readout says the
range is as far as this client goes.

**In and out rather than on and off.** A plate goes up and comes down in one
frame, and fifteen bars blinking on at a pull reads as a fault rather than as
mobs coming into range. A bar ramps in over 0.15s and out over 0.22s, the out
slower on purpose: arriving is information you want now, leaving is a bar you
have already read. The ramp multiplies the alpha that says which bar is yours
instead of replacing it, so a bar half arrived that is not your target is dim
and half arrived at once.

A bar on its way out comes off the plate first and holds its own place on the
screen, because the client hides a plate the moment its mob is gone and a child
of a hidden frame does not draw whatever its alpha says. The held position is
snapped to a whole pixel, since it came off a plate and a plate's origin is
wherever the mob was standing. `bars fade off` puts back the old behaviour
exactly.

**Clickable along the whole bar.** The frame the game hit-tests is the plate's
own, our bar is drawn over it and takes no mouse of its own, and the plate was
being sized to the bar's height. That is the wrong figure: the bar hangs off the
plate's centre by its gauge, and more of it is above that centre than below,
because the debuff row and the threat line are up there and only the cast
chamber is down. So the middle of a bar targeted and the ends did nothing. The
figure sent now is the smallest box centred where the plate is that holds the
whole bar, which costs a little spacing and buys a bar that targets anywhere.

The plate's size also came off `bars stack`, which was one switch over two jobs.
Spacing is what that setting is; the click is not, and it is applied whenever the
bars are drawn on plates.

### Every tooltip is one size

The box took its zoom from whatever you hovered. That was a deliberate rule and
it read well one box at a time. Across a session it read badly: the missing buff
row ships at 2x, because four squares over your character have to be legible
from across a fight, so a square on it opened a tooltip in text twice the size of
the one the action bar six pixels below opened. Same font, same palette, same
layout, two sizes.

A tooltip is not part of the widget you hovered. It is a paragraph about it, and
how big this addon's paragraphs are is what the UI size slider answers. So the
box is drawn at `UI.WindowZoom` now, the same as every window here, whichever
frame it opened on. The size of a HUD widget is about how far away you read it
from and nothing else.

`UI.ZoomOf` went with the rule. It walked up from a region to whichever ancestor
was on the pixel grid, it existed for this one caller, and a query nothing calls
is a thing the next reader has to work out the purpose of.

### A missing buff square says what the game says

Hover an action square and the box names the spell, its rank and its cast time,
because `UI/Scan.lua` points a hidden tooltip at the slot and reads the client's
own lines back. Hover a square on the missing buff row and the head was "food",
in the caption's voice, with a sentence of ours under it. Two boxes eight pixels
apart, written by two different hands.

The reason was real. There is no aura index for an aura that is not on you, so
there was nothing to point the scanner at. There is an id, though, and
`SetSpellByID` takes one, so `spell` is now a subject kind like `action` or
`debuff`. A racial square and a flask you added yourself read with it, and the
game's own description of the spell takes the head.

A bare hand has no id and does have a weapon, so those two squares read with the
worn slot, the same question the buff row's weapon enchant square already asks.
What the game says about the sword you are swinging is the right thing to put
above "nothing on the weapon you swing".

`SetSpellByID` landed in Wrath and the older client has no answer for it. That
path is not a fallback bolted on afterwards: `UI/Tooltip.lua` has always drawn
the caller's title where the client hands over nothing, so on 1.12 the head is
the caption's phrase, which is what it was yesterday.

### The experience bar is ours now

The last Blizzard frame on the screen. `Artwork/Artwork.lua` has stripped the
gryphons and the metal strip off the action bars since the first week and left
`MainMenuExpBar` alone on purpose, with a comment saying an experience bar is not
furniture. It is a reading, and it was the one reading still drawn in 2007 art
under a HUD that has none.

So `Progress/` draws it. Two rails along the bottom edge of the screen: how far
into the level you are, and under it the faction you are watching. The level and
the count on one, the faction and the standing on the other, in the same flat
colours as everything else here. `/wk hide xp` takes the client's own pair down
and ships on, the same as every other switch on that page.

A rail with nothing to say is not there. At the level cap the frame is the
reputation rail alone, with no faction watched it is the experience rail alone,
and with both true there is nothing on the screen. That is the missing buff row's
rule applied to a readout: a bar drawn empty is a claim about a character who has
run out of things to earn.

The rested pool is drawn rather than written. Between where you are and where the
bonus runs out the rail carries a second fill, in the blue this game has used for
it since it shipped, clamped at the end of the level because a week away is a
pool bigger than the level. It is the one number on the bar that changes what a
kill is worth, and it should not need a hover.

The twenty segment marks are the client's own bubbles, and they are still the
unit people count in. They come off under 160 pixels of width whatever the
setting says, where twenty of anything reads as hatching.

Hover either rail and the addon's own box says the rest: what is left of the
level, what the rested pool is worth, and what the session says the rest of the
level will cost you in minutes. That last one is arithmetic of ours, because
nothing in the game will tell you what you are earning an hour. The accumulator
runs whether or not the bars are drawn, and it handles the level landing between
two readings, where the client's number goes down rather than up and a plain
difference would report that you are earning backwards.

Nothing here is on a ticker. Experience moves when you kill something and
reputation moves when the client says it did, so the part draws on five events
and on nothing else, and none of its functions is in `check.sh`'s `HOT` list.

`/wk xp on|off`, `xp faction`, `xp bubbles`, `xp width`, `xp height`, `xp zoom`,
`xp reset`, and a page of its own under Readouts.

### A mob that pays nothing says so with its name

The XP scale was already on the bars, on the two characters of the level tag.
Two characters is the wrong size for a fact you act on. You decide whether a
kill is worth taking at pull range, across a screen with six plates on it, and
the addon was answering in a shade of grey on a number you have to squint at.

It is on the name now. A mob whose kill pays you nothing draws its name in the
same grey the level tag uses, so the two agree and the loud one carries it. Grey
beats the warm colour your current target wears. Which mob is yours is already
said by the plate being brighter than the rest, and a mob you picked up by
mistake is exactly the one that has to tell you.

The other half was missing outright. A mob somebody else tagged pays no XP and
no loot at any level, and this addon had never asked. It replaces the Blizzard
plate, and the Blizzard plate greying out was the only place that fact was ever
drawn. `UnitIsTapDenied` answers it, and a tapped mob now takes the bottom
colour whatever its level reads.

The target frame was worse. It drew the level in one flat shade for its whole
life while the plate beside it carried the full scale, so the one mob you had
actually chosen was the one the addon would not price. It wears the scale now,
and only on something you can attack. Your own frame and a friendly target keep
the plain number, because an even yellow on those claims a reward that is not
there.

### The tooltip docks in the corner

Every hover in the addon used to open its box next to the thing you hovered.
That is a fine rule for a label and a bad one here, because everything in this
addon you can hover sits over the middle of the screen: a loot row, a cooldown
square, a nag, a mob you are about to hit. The box landed on the row under the
one you were reading, and on a creature it followed the pointer into whatever
you were looking at.

So it goes where this game has always put a tooltip. The bottom right corner,
clear of the bags and of however many action bars are switched on, in the same
place the client's own box would have been.

The two clearances are the client's own and are read rather than written down.
It rewrites them whenever the bags open or a bar appears, so the addon's box
moves when the client's would have. A client that defines neither gets the bare
corner plus one bag bar. Both numbers land on the pixel grid on the way in: they
are measured in UIParent's units and this box is on the addon's own scale, and
an offset that is a fraction of a unit puts the border half on a pixel.

`/wk tips beside` is the way back, and there is a checkbox for it on the
settings page under Hovers. Beside is not a fallback. On a very wide monitor the
corner is a long way from what you are reading, and a label on the thing itself
is worth the cover it costs.

### The chat line is Blizzard's now, and `/logout` works

Typing `/logout` in this window used to do nothing, or take two presses, or come
back as a red line naming WarriorKit. The reason was one line of code: the
window made its own edit box.

`Logout()` is protected and the client refuses it from any call stack an addon
has been in. A field of ours puts a function of ours in that stack. The client
dispatches the key press into our OnEnterPressed, our handler calls the client's
parser, and the protected call at the end of it is dropped. Blizzard's field has
its OnEnterPressed set in XML, so the same press goes from the keyboard into
FrameXML with nothing of ours between it and the command.

The answer was to stop building a field. `Chat/Field.lua` borrows
`ChatFrame1EditBox`, hides the three border textures, fades the focus glow, sets
the log's own font on it and anchors it into the footer. The rectangle round it
is still ours and so is the sentence in it. The frame the characters go into is
the client's, and nothing in this addon ever calls SetScript on it.

Both chat keys went back to the client with it. The window used to bind enter
and slash onto buttons of its own so the line opened down here rather than
behind the hidden window, and that was the other half of the bug: a key bound to
a button of ours opens the line from a script of ours. Now `OPENCHAT` and
`OPENCHATSLASH` are FrameXML's own again and the room's slash is written into
the line off the client's activation instead.

What this deleted is most of `Chat/Compose.lua`: a secure button carrying the
typed line as macrotext, an override binding armed while you typed and handed
back afterwards, a list of thirty five slash words that might end in a protected
call, an alias table, a debug log and its slash word, and the combat retry that
existed because a binding cannot move in a fight. Around four hundred lines,
none of which did anything except work around the field.

This is Prat's arrangement. It has shipped for fifteen years without a `/logout`
bug, because it never had one to fix: the only two edit boxes in Prat are for
copying chat and for search, and the line you send from is always the client's.

### The quest log turns over and shows you a map

The middle column has a tab over it now. One side is the quest. The other is the
zone it sends you to, drawn at the width of the column, with a dot on every
place that quest has anything at.

This is the question a quest log has never answered on any client. The text says
eight Kobold Miners and the world does not label a Kobold Miner, so the answer
has always been a second addon, a second window, or a browser. Questie knows
where every one of them stands and spends that knowledge on icons scattered over
the world map, where finding this quest among your other nineteen is its own
job. The tab asks the same database the other way round: not what is in this
zone, but where is this quest.

Blue is what is left to do, green is who takes it back, and gold is you. Only
unfinished objectives are drawn, because the four camps you already emptied are
the half of the answer that makes the other half hard to see. Hovering a dot
gives you its name and its coordinates, which is what you can type into whatever
you already have open, and which is still true tomorrow in a way a distance is
not. A quest that sends you to two zones gets a strip of zone names under the
map, and the one it opens on is the one Questie says is nearest to where you are
standing.

The wheel zooms, and it zooms at the point under the cursor. A zone drawn at the
width of one column is three hundred pixels across a place that takes twenty
minutes to walk, which says which end of Westfall and not which side of the
road. Six times is the far end, where one of the client's tiles is drawn at
twice its own size and the art gives out. Zooming at the cursor is a pan and a
zoom in one notch, so there is nothing to drag, and nothing to drag means no
ticker running on a window that is open all evening. The box claims the empty
height under the map as it goes in, and never outruns the picture inside it.

The dot is nine pixels and it carries a wash of its own colour behind it. Five
was a three pixel core on a painting of hills, roads and rivers in every colour
a dot can be: the mark was there and nobody could find it, which for the one
thing the page exists to say is the same as not drawing it. The wash is what
does the finding, and where a camp puts four dots inside one step the washes run
together into one cloud, which is the honest picture. Not four things. One place
with things in it.

Two questions were being asked the wrong way round underneath. An objective
counted as done when its two counts matched, and Questie forces both to zero for
every speak to, explore and use step in the game, so those quests dropped their
whole selves off the map; `Completed` is the field that answers. And a quest's
spawn list is empty whenever Questie has not drawn that quest's icons yet, so
where a thing stands now goes to the database behind it rather than to what is
currently on the world map.

The picture is the client's own art, in its own twelve tiles, cropped. The last
column and the last row of a zone map are part tiles padded out to full size, so
drawing them whole puts two black seams through every map in the game.

None of it is required. Questie missing, Questie still compiling, a quest it has
no row for, or a zone this client has no picture of are four different ways to
have no map, and the line under it says which one you have rather than leaving
an empty rectangle to read as a broken addon.

### A quest log you can see all of

The client's log draws six of your quests through a slot. Twenty do not fit, so
the log you are carrying is something you scroll a strip to see an eighth of,
and clicking a quest pushes the list off the window to show you its text. Every
question you actually open the log to ask is about the whole log at once. What
can I hand in. What have I outlevelled. None of them can be asked of six lines.

So this one is three columns and the left one is the log, all of it, zone by
zone, and it does not move when you click something. A quest ready to hand in is
green, one that failed is red, and everything else is on the same experience
ladder the enemy bars colour a mob's level with, so what is worth doing now is
legible before you read a word of it.

The middle column puts the objectives first and the giver's story second, which
is the opposite of the client's order and the right one after the first read.
You have read the story. What you came back for is three of eight.

The right column is what the quest pays: the choices apart from the items you
get regardless, each with its own real tooltip, the coin, and the spell or the
title where there is one. Under that go two lines the client cannot answer and
Questie can, when Questie is installed: who takes the quest back, and how far
away the nearest thing you still have to kill is. Nothing here replaces Questie
or touches its map icons. It reads what Questie already knows and spends on a
tracker sorted by zone.

Blizzard's log goes in the attic and `L` opens this one. `/wk quests hide off`
puts both back the way they were, and `/wk quests off` turns the window off
entirely.

### A mail window that says who you are sending to

The client's has one recipient field and it looks the same whatever you type in
it. Your bank alt, a guildmate you have never spoken to and a name off the
auction house are the same eleven pixels of white text, and the only thing
between the second two and four hundred gold is that you read what you typed.

So the window has a band along the bottom in the colour of whoever it is going
to. Green is a character on your own account, blue is somebody on your friends
list or in one of your groups, red is a name the addon has never seen, and the
band says what is riding on the letter while it says so. It is always there
rather than appearing when something is wrong: a warning that appears is a
warning you have to notice appearing, and it moves everything under it when it
does. Red also arms the send, so value going to a name off your favourites list
takes two presses. `/wk mail warn off` drops the second press and keeps the
colour.

Favourites are a list rather than the colour, and the two are different
questions on purpose. A relation is what the client and the addon can work out
about a name; a favourite is a name you put on a list because you mail it. A
guild bank alt is a stranger by relation and belongs on the list; an alt the
addon met once is green and does not. The list is the column down the left of
the window and is what the warning is measured against.

Attachments are not capped at twelve. A mail carries twelve, and what the client
does with that is make twelve the number you have to think in: fill a form,
send, walk back to the bag, fill it again. The draft holds thirty six and
divides, the block of squares draws the line where the split falls, and the send
posts one mail at a time and waits for the server between each. Coin rides on
the first mail only, because splitting it three ways is three ways for half of
it to be sitting in a mailbox after the second one failed.

Right click a stack in your bags and it goes on the letter. That is what the
client's own window does and it is the only way anybody attaches twelve of
anything; dragging squares onto a block one at a time was the first version of
this and nobody would do it twice. The stack you point at is the stack that
goes, which a drop cannot promise: a cursor says what it is carrying and never
which slot it came out of, so twenty identical piles of ore mean the drop takes
the first free one and the click takes the seventh.

The click is taken over while the window is open and given back the moment it
closes, the same promise the parked window makes. Shift, ctrl and the left
button are never taken, so the client's stack split and everything else it does
still work. What the addon claims it never hands back: a stack already on the
mail says so and stops there, because falling through means the client eats the
ore. `/wk mail bags off` if you want none of it.

One name is hooked and it is `ContainerFrameItemButton_OnClick`, which every bag
button in the game reaches, Baganator's included, and which Auctionator hooks on
this same client to put a bag item on the auction form. It is replaced rather
than secure-hooked, because a hook runs after the client's own handler and the
whole job here is to stop it.

This turned up something the send was doing. It raised `SetSendMailShowing` and
left it up, which was harmless while nothing else clicked a bag slot. With that
flag up, a bag click the addon does not catch attaches to the client's own form,
and that form is parked off the side of the screen: the stack leaves your bags
and lands on a letter nobody can see. The flag goes back down when a run ends.

The subject writes itself. Coin titles the mail `money`, one item titles it
after that item, several title it after the first and a count, and a split send
numbers the parts and fits the number inside the client's sixty four characters.
A subject you type wins over all of it.

The inbox is the other tab: a row a message with the sender in the same three
colours, what is on it, how long is left, and a take-everything that counts down
rather than up, because taking a message renumbers the inbox and a sweep walking
upwards skips every other one while reporting that it took them all.

Three things this change is honest about. Blizzard's window is parked off the
side of the screen rather than hidden, because `MailFrame` going down is what
tells the server you have walked away from the mailbox; `ns.Strip` would have
closed it. There is no send timeout, because a timeout is an `OnUpdate` and an
`OnUpdate` is a ticker this addon would defend forever, so a stalled send waits
with a stop button under it. And the attach path is `UseContainerItem` with
`SetSendMailShowing` set, which is `Baganator/Transfers/AddToMail.lua`'s shape
on this exact client rather than one reasoned from the API list.

One thing the harness was swallowing came out with it, and it was making
existing code look tested. `Region:Show` and `Region:Hide` now run the frame's
own `OnShow` and `OnHide`, which is what the client does: `Core/Panel.lua` wraps
that pair to tell every part the options window opened, `Perf/Feature.lua` starts
and stops the memory walk with the tab that owns it, and the mail window closes
the mailbox from its frame's `OnHide` so that escape, the close box and the
client saying it shut all leave through one door. None of the three could run
before. It is guarded on the shown state really changing, because the client
does not raise either script for a call that changed nothing.

`Region:SetText` raising `OnTextChanged` is the same gap one layer over, and the
chat keys found it in the same week from the other end: a field that reports
what you typed is a field whose whole behaviour hangs off that script, and a
stub that dropped it made every one of them look like a box you could not type
in. That half is `45-chat-keys`' and the mail fields are driven through it.

`Feeds/Purse.lua`'s coin formatter is `ns.Coin` in Core now, and the thousands
separator beside it is `ns.Thousands`. Two parts needed the same answer, which
is the rule that moved `Core/Gear.lua` and `Core/Stance.lua` out of the parts
that invented them. It was called `Group` while it was private, and `ns.Group`
is the party and raid block's namespace: the collision was silent, made
`ns.Group` a function for the length of one file's load and a table afterwards,
and the only symptom was the gold-an-hour cell raising once a second.
### The harness clock is frozen, like the realm clock beside it

`03-player.lua` handed the addon `os.date` and every other time in the stub
client is fixed. `Minimap/Clock.lua`'s guard is that a second look inside the
same minute must not touch the font string, and `23-minimap.lua` asserts it by
calling `Update()` and expecting `false`. A run that crossed a minute boundary
between `Apply` and that call got `true`, which is the guard working, and the
section failed for the time of day. `date` now formats against one timestamp
built from a table, so the reading is the same in every timezone and on every
run.

### check.sh finds the classes instead of naming them

The harness loop listed WARRIOR, MAGE, SHAMAN, PRIEST and HUNTER as five words
with nothing tying them to `Class/*.lua`. A sixth class file got no run, and the
failure that hides is a login error rather than a wrong answer: the cap of eight
entries on the cooldown row and four on the upkeep row is an `assert` inside
`Cooldowns.All` and `Upkeep.Fixed`, and it fires on the client, at
`PLAYER_LOGIN`, as a Lua error. `Class/Mage.lua` already lists eight cooldowns,
so a ninth is all it takes, and nothing reaches that assert before the game does
unless the harness has been run as that class.

So the list is read off the files. `sed` pulls the token out of every
`ns.Class.Register("...")` call in `Class/`, which is the string the harness is
handed, rather than the file's name, which is only a convention. An empty result
fails the gate, because no class covered at all is the one outcome that would
otherwise look like a pass. HUNTER stays written out on the loop, since having
no file is the whole of what that shape proves.

### Casting on what the mouse is over

The addon's own Clique, under `Hover/`. Drag a spell onto the empty row at the
top of the page, press the key you want it on, and that key casts on whatever the
cursor is over, in the world, on a nameplate, on a party block or on a skinned
unit frame.

The page is a list of rows and one empty row on top of it. A row is a whole
binding, four columns wide: the spell, the key, who it lands on, and the cross
that takes it off. Every column writes straight through to the binding, so
changing your mind about one of the three decisions costs a click on the row.
The empty row is the same widget with a draft behind it rather than a saved
binding, which is why filling it in has no order you have to follow.

It was three stacked controls with a read-only list under them, which is the
shape a settings page falls into when each control is added on its own. It asked
for the three decisions in a fixed order in three places on the page, and once a
binding existed the only thing you could do to it was delete it and start over.
Every one of those is the same defect: the thing being edited is a row and the
page was not drawing rows.

`UI.DropSquare` and `UI.KeyBox` came out of the kit to make that possible. Both
were closures inside `UI.Kit`, reachable only through the labelled full-width row
built around them, and a page that lays out its own columns needs the piece
without the row. `ui.Custom` grew an `opts.label` at the same time, so a row a
page builds itself is in the search index like every other control. `kit.Slot` went with them: the
labelled row was the only thing that ever called it and the page that called
that draws its own rows now. `UI.Kit`'s own line count came down from 157 to
123, and the allow-list entry in `scripts/shape.lua` came down with it.

Every binding carries a filter and the filter is a macro conditional. An enemy
key is `[@mouseover,harm,nodead]`, a friendly key is `help,nodead`, and a key
that takes either is `exists,nodead`. `harm` and `help` are exclusive, so a heal
and an attack can sit on the same key with no chance of one firing where the
other was meant. A conditional also decides at the moment of the press, which is
what lets a binding survive a fight: attributes cannot be touched once lockdown
is up, and nothing here needs to be.

Twelve bindings share one `SecureActionButtonTemplate`, because a secure button
looks its action up under `<modifiers>type<click>` and the click name an override
binding passes through is the whole of what tells one binding from another. That
is `Marking/Keys.lua`'s mechanism with the button swapped for a secure one, which
is the one thing marking did not need and casting does.

The attributes are `*type1` and `*macrotext1`, and the `*` is what the first cut
of this was missing. The modifier prefix is read off the keyboard at the moment
of the press, so a key on ALT-BUTTON3 arrives asking for `alt-type1`, and every
key worth putting a mouseover spell on carries a modifier. `*` is the wildcard
the client falls back to when the modified name holds nothing. Under `type-1` the
attributes sat where nothing ever looks: the override bound, `GetBindingAction`
read it back correctly, `/wk hover show` printed the right macro, the page drew
the key as live, and not one press cast anything. Every reporting path this
feature has agreed the keys were up, because every one of them asks the binding
layer and none of them could ask the button what name it answers to.
`UnitFrames/Group.lua` has written `*type1` since the party frames shipped.
`44-hover.lua` now asserts the attribute name and not only its value.

Spells are stored by name, so `/cast` picks your best rank and a trainer visit
cannot leave a binding pointing at rank 3. Bindings are per character, because a
binding names a spell and a spell is something one character knows.

`Sheet.lua` draws the list over the world, one line per binding, key on the left
and the spell's own icon and name beside it, red for an enemy key and green for a
friend key. A mouseover binding is otherwise completely invisible, which is why
half of what anybody sets up in Clique gets forgotten. It is written on a change
and never on a ticker.

`ui.ItemSlot` became `ui.Slot` on the way through. It was a widget nothing
called, and what it needed to take a spell was one question moved out of the
widget layer and into the caller: `opts.take` is handed the whole of
`GetCursorInfo` and answers what the setter gets. `CursorHasItem` went with it,
because it answers for an item and never for a spell, so the drop highlight asks
the same question the drop does.

### The party list fills outward from the middle

The frame you drag is the middle of the block now, not its top left corner. A
fifth person moves every slot half a block away from the anchor instead of
pushing the bottom of the list further down the screen and leaving the top where
it was, and a group that breaks up closes back onto the same point.

The header already sizes itself to the block it has just arranged, buttons, gaps
and column spacing included, so centring it on the anchor is the whole of the
mechanism. There is no second copy of the header's column arithmetic to keep in
step.

The offset is rounded rather than written as `CENTER` anchored to `CENTER`. Half
of the block is not always a whole unit: four blocks with a three pixel gap
between them is a hundred and forty five, and a list placed on half of that puts
every edge inside it across two rows of pixels. Rounding gives up half a unit of
centring and keeps the grid.

`/wk party grow up|down` still picks which end the first slot is at, which is
what it now says on the page and in the line it prints.

`harness/client/09-group.lua` got two corrections while this was measured against
it, both from the shipped `SecureGroupHeaders.lua`. The first block of a column
is placed at the corner where the growth direction and the column direction meet
rather than at the growth direction alone, which the model had centring across a
header three columns wide; and a header with nobody to place takes one block's
width and a tenth of a pixel of height rather than a whole block of it.

### Hiding Blizzard's own frames, by the parent rather than by the method

`/logout` put the client's chat window back on the screen with `hide chat` on,
and the target carried two cast bars with `hide cast` on. Same bug both times,
and it was in the mechanism rather than in either switch.

Every hide replaced the frame's Lua `Show` with its `Hide` and then recorded that
it had. `SetShown` is resolved in C and never reads that field, so every FrameXML
path written that way walked straight past the hide: `FCF_` uses it on the chat
window, which a slash command run through the client's own edit box reaches, and
the cast bar mixin uses it on the target's bar, which every cast reaches. And
because each pass remembered what it had done, the first frame that got past it
stayed past it until the next reload. `UnitFrames/Blizzard.lua` already had a
hook on `CompactRaidFrameManager_UpdateShown` for exactly this, which is a patch
for the one frame somebody happened to notice.

`Core/Attic.lua` is the answer instead. One frame, created hidden, whose `Show`
and `SetShown` are both replaced with `Hide`, and every frame this addon replaces
is re-parented into it. Visibility on this client is a property of the parent
chain, so a frame in the attic is not drawn whatever anybody calls on the frame
itself. Show, SetShown, SetAlpha, a fade, an animation and a layout pass all
lose, and none of them had to be guessed in advance, which is the difference
between this and the four fixes before it.

The passes verify instead of remembering. Every one re-resolves every name, reads
what is on the screen rather than what the last pass did, and runs at login, when
a switch moves, when combat drops and once a second forever. `ns.Attic.Sweep`
walks everything the attic holds and puts back anything whose parent has drifted,
which is the one call a cage can lose to. So the guarantee is no longer "no path
we thought of can show it", it is "nothing the addon replaces stays on the screen
for longer than a second". The raid hook is deleted.

Each entry now carries a list of global names and a list of FrameXML parent keys,
because a client that spells a name differently is the failure a single global
cannot survive. The target's cast bar is taken down as `TargetFrameSpellBar` and
as `TargetFrame.spellbar`, and either one is enough.

`/wk hide probe` prints one line per name: whether this client has the frame,
whether the attic holds it, and whether it is on the screen anyway. Every bug
these switches have had looked identical from the outside, a switch that was on
with the frame still drawn, and settling which of the three it was took a guess
at FrameXML each time. It takes one command now.

Two things stay out of the attic on purpose. Art does, because a texture is a
region of the frame it was made on and re-parenting one moves it out of that
frame's draw order rather than off the screen, so nameplates, bar art and the
unit frame skin keep `ns.Strip`. Secure action buttons do, because the client's
bar controller calls methods on them from a stack that goes on to perform
protected actions, and `Buttons/Blizzard.lua` is unchanged.

`43-blizzard-hide.lua` asserts on `IsVisible` rather than on `IsShown` and fires
`SetShown` first, because a caged frame is allowed to have its own flag turned
back on and `IsShown` cannot see the difference. The fixture's raid manager and
cast bar both call `SetShown` now, which is the call the old hide lost to, so the
version this replaces fails the section. The pass costs 0.00 KB per 50 ticks and
is bracketed as `hide` on the performance tab.

### Five refusals read "a this character"

Todo item 13, the last thing the class split left behind.

`Class.Label()` is the addon's own word for what you are, and it is what a
refusal reads out. It answers the class file's label once the client has named a
class, the client's own name for a class no file has been written for, and a
phrase for the moment before the client will answer at all. That phrase was
"this character", and five of the sentences that read it put an indefinite
article straight in front of it: "no ability a this character owns opens on a
dodge or on a block", "the charge button is built on three openers and a this
character has none", and three more in `Buttons/Layout.lua`,
`Cooldowns/Cooldowns.lua` and `Cooldowns/Feature.lua`.

The fallback was wrong rather than the call sites. Two asserts and the panel's
rail entry take the same string bare and read correctly, so fixing it at the
call sites means rewriting five sentences around one word that is right in three
other places. It is now "character of unknown class", which is a noun phrase and
follows an article.

It is cosmetic and only reachable in the window before `UnitClass` answers,
which is why nothing caught it.

`21-which-class` gates the shape rather than the words. Whatever `Class.Label`
returns may not begin with a determiner, checked on the label as it stands on
every class shape and again on the fallback with `UnitClass` taken away. A class
file that labels itself "the shaman" fails the same check. The fallback half
runs on the shape with no class file of its own, because `Class.Token` holds the
first answer that was not nil and finds the file under it; `Class.Name` reads the
global on every call, so taking it away and putting it back is the whole of that
moment.

### A row for the cooldowns that decide fights

Todo item 7. Death Wish, Recklessness, Shield Wall, Last Stand and your
trinkets, drawn as a row of squares over your character with what is left of
each one on it. It is up for the whole fight, it stays up afterwards while
something is still recovering, and it is gone otherwise.

The bars already draw a swipe on every square and that is not the same thing. A
swipe answers "can I press this" about a square you are looking at, and the
cooldowns that decide a pull are the ones you are not looking at: on bar 2, on a
stance page you are not standing in, or off the bottom of the screen. Counting
three minutes in your head is what this replaces.

**It is a class part, not a warrior part.** The list is a seventh field in the
class registry, so `Class/Warrior.lua` names the four warrior cooldowns and no
file outside a class file names a spell. A mage brings eight, a shaman six, a
priest five, and a class nobody has written a file for brings none and still
gets its trinkets. Nothing was edited outside `Class/` to add any of them.

Three filters decide what is actually drawn, and each one drops a square on its
own. A spell this client cannot name is left out, which is most of what
separates Era from Burning Crusade in those files. A spell this character has
not learned is left out, which is how a talent nobody spent a point on and a
trainer nobody visited both come out right without the class file knowing about
specs. And one switch per entry, per character, drops whatever you do not want
to look at: a raiding main and a levelling alt on the same account disagree
about Shield Wall, and only you can settle that.

The trinkets are not a class fact and are decided by the client rather than by a
list. An item with a use effect answers `GetItemSpell` and a passive one answers
nothing, so the row carries the trinket you press and skips the one you merely
wear. That is a better test than a cooldown reading, because a passive trinket
with a proc on it has a cooldown too, and a square saying "ready" about a proc
is a square telling you to press something you cannot press.

Two things came out of this that are not the row.

`UI/Ability.lua` counts in minutes above a minute. A thirty minute Recklessness
drew "1798" on a 27 pixel square, which is four digits of false precision about
a number nobody reads to the second, and every action bar square had the same
defect. It rounds down, so 1m means a minute or more and the ladder has no gap
in it: 3m, 2m, 1m, then 59 and the seconds. Rounding up reads as the safer
choice and is not, because 119 seconds and 61 seconds both round to 2m and the
label would go from 2m straight to 59 without ever saying 1m.

`ns.BuffName` is in Core with the rest of the API shims, because the cooldown
row walks your own buffs for the same string `Buffs/Upkeep.lua` walks them for:
whether a burst window is still open is a question the client will not answer
from a cooldown, since the cooldown starts the moment you press the ability and
says nothing about the fifteen seconds you pressed it for.

The rail renumbered. The registry takes whole numbers only and the row belongs
next to the buff nag, so it took 10 and the nine parts below it moved down one.

### The skin is four files, one per subject

`UnitFrames/Skin.lua` was 1,988 lines holding three jobs that never spoke to
each other. Splitting it was todo item 11, and the reason was never the line
count: `8ad829f` deleted the file ceiling and put `scripts/shape.lua` in its
place, which measures a function's own lines, its depth and its branches, so
cutting a file in half moves nothing it reports. The reason is that a reader
looking for where a badge lands had to walk past a texture walk and a ticker to
find it.

`UnitFrames/Art.lua` is everything the skin does to a region Blizzard owns.
Record it before the first change reaches it, hide it, hand it back. Two of the
four rules in the old file's header are this file's, and they are the two about
the walk: textures go and frames stay, and walk the regions rather than naming
them. It knows nothing about a rectangle.

`UnitFrames/Block.lua` is the geometry. The square, the two rails pinned to the
grid, the four strings, the badges on the corners, and where the three blocks
hang off each other. The other two rules are this file's: fit the frame to the
block, and draw on the grid while measuring off it.

`UnitFrames/Paint.lua` is the tick. Given a block that already exists, read the
unit and write what changed.

`UnitFrames/Skin.lua` is what is left, and it is the part rather than any of the
three. Which frames this client has, whether each one is wanted, the order that
styles and unstyles them without losing half a skin to combat, and what the
slash commands and the panel are told.

Four files rather than the three the item named, because taking three subjects
out of a file leaves a fourth behind. The part was always in there. It was never
the thing anybody would have said the file was about.

The cut is a move and the numbers say so. `Place` came out at 195 lines of its
own, 2 deep and 16 branches, which is exactly what it measured going in, and so
did `Build` at 83, `StripArt` at 78, `Refresh` at 99 and `HealSlice` at 29.
Nothing was rewritten to fit through a door.

Four things did change, and each one is the seam rather than the code. `Link`,
`Perch` and `Landed` are handed the entry they hang off instead of looking it
up, because the entry list is the part's and a geometry file has no business
walking it. `Style` went from 62 lines to 39 and `Unstyle` from 32 to 19,
because both were doing the walk's bookkeeping inline and now ask for it in one
call each. `Skin.Probe` reads a recorded width through `Art.Was` rather than
reaching into a table two files away. And the ticker's own body is a named
`Tick` rather than an anonymous closure, so `check.sh`'s hot path scan can see
it, which it could not before.

`BADGES` and `BARS` stayed in `Art.lua`, and `Block.lua` reads both at load.
Which of Blizzard's regions the skin spares is the walk's question; which corner
each one lands on is the block's. Splitting that table down the seam between
them would be two lists free to disagree about how many badges there are.

The local `Blocked(entry)` wrapper is gone. It was one line around `ns.Blocked`,
which `Core/Core.lua` already documents, and keeping it would have meant writing
it in two files.

`scripts/shape.lua`'s allow-list points at `Block.Place` now, at the same 195,
and its `why` no longer says item 11 will split it. `check.sh`'s HOT list names
`Paint.Refresh`, `HealSlice` and `Skin.lua`'s `Tick`. Both TOCs load the three
new files before `Skin.lua`, `Art.lua` first because `Block.lua` reads its two
lists as it loads. `docs/README.md`'s file layout, its ticker table and its two
notes about where the skin flattens a bar and hides a texture all name the file
that does it now.

### The loadout seed could latch on a class the client had not named yet

`Loadouts.All` seeds one loadout per stance the first time it is read, records
that it has in `loadoutsSeeded`, and never seeds again. That flag is the one
answer in the addon that is kept across a session, and it was being written off
a count that cannot tell two states apart.

`Stance.Count` reads `forms` off your class file through `ns.Class.Of`. An
unresolved class has no file, so it counts zero forms exactly as a mage does. A
read taken before the client would say what you are therefore looked like a
class with no stances, latched the flag, and left a warrior with an empty
loadouts list for the life of that character. A reload does not undo it: the
flag is the record that the seed already ran.

Nothing reaches it today. `Loadouts.Apply` runs at `PLAYER_LOGIN`, where
`UnitClass` answers, and the panel is built later still. That is a fact about
the current call order rather than about the code, and it is the reason to guard
instead of to argue: what a wrong answer costs here is a saved variable the
player cannot clear from inside the addon.

So the seed asks for the token before it counts anything. A read with no token
is answered out of the list and records nothing.

`20-loadouts` takes the token away and reads the list, which is the state the
addon is in for the whole of `ADDON_LOADED`. It stubs `ns.Class.Token` rather
than `UnitClass`, because Token caches the first answer that is not nil and by
that point it has one, and because `Mine` and `Of` both go through it. Take the
guard out and the section fails on the latch.

### Class.Is is deleted, and the guard it carried is written down

`Class.Is(want)` answered true on an unresolved class, on the argument that a
wrong yes costs a moment of a button that will not cast and a wrong no costs a
warrior their charge button until they reload. The argument is right. The
function was not in the path. Nothing in `src` called it: `Charge.Available`,
`Reaction.Arm`, `Loadouts.All`, `Icon.lua` and `Marker.lua` all go through
`Class.Of`, which answers nil on an unresolved class, so every login decider
took the branch the function existed to prevent. Only the harness called it, and
it called it as a warrior, so it passed.

Deleting it puts the rule where it holds. The section comment in
`Class/Class.lua` now says what the guard is: ask at `PLAYER_LOGIN` or later,
never at file scope, and check for the nil anywhere the answer is written down.
There is one such place and it checks.

`docs/README.md` documented `ns.IsWarrior()` in three places, and it has been
gone since the class split. It sat in the API index, it taught the removed
unresolved-answers-yes rule in the gotchas, which would have misled the next
reader into believing a guard that is not there, and the Charge section said
that page is one sentence instead of four tabs when the part opens no page at
all. All three describe `ns.Class` instead, the gotcha carries the nil rule and
the one place it bites, and the file layout lists `Class/`, which it had never
mentioned. `Charge/Feature.lua` said its row on Start is drawn and refuses;
`BuildStart` leaves it out, and the comment now says so and why.

### /wk status errored on a class with no bar plan

`Layout.Describe` read the plan straight after being refused over it, and on a
character with none that is the length of a nil. The panel row calls it, the
status line calls it, and the status line calls it whether or not anything
refused, so a hunter typing `/wk status` in combat got a Lua error instead of a
line.

The refusals in `Buttons/Layout.lua` come in two kinds and the file had them in
the wrong order. Combat and a full cursor clear on their own. A missing
`PickupSpell` and an unwritten plan do not, and never will on that character.
`Describe` tells the two apart by comparing the sentence against
`Layout.BUSY_COMBAT` and `Layout.BUSY_CURSOR`, and carries on past either,
because reading what your bars would be filled from is an ordinary thing to do
mid fight. That test is only sound if every permanent refusal is reached before
the first transient one, and it was not. `CanApply` asked about combat before it
asked for the plan, so a plan-less character was refused in a sentence that
promised to clear, and `Describe` walked past it into the plan.

So `CanApply` asks for the plan first, and `CanWrite` probes the five compose
calls before it asks `CanCarry` about combat. Nothing else moved. The same
reordering fixes a quieter version of the same bug: a client without
`PickupSpell` used to report "you are in combat" for the length of every fight,
which reads as a client that will manage it in a minute and never will.

The harness calls `CanApply` and `Describe` under lockdown on every class it
runs as, and reads which of the two refusals came back rather than reading the
sentence itself. Put the old order back and the hunter run fails on that line
and then dies in `Describe`, which is the whole report.

### A priest, which is one fact and no page

The fifth class file, and the shortest. A priest fills in one of the six fields:
Fortitude and Inner Fire on the buff nag row, both silent when they lapse and
both gone after a death. No bar plan, because nobody here has levelled a priest,
and a plan written off a talent calculator would fill your bars with a guess and
take a backup you then have to put back.

That shape is the one the options rail had no run for. A class that registers a
file but opens no page of its own is dropped from the rail by `FillRail`, and
neither the mage nor the shaman reaches that branch: both carry a bar plan and a
plan opens a page. `check.sh` runs the harness as a priest now, so the rail is
gated on five shapes rather than four.

### The chat window gives its screen back

It shipped taking a third of the corner it sits in, and most of what it took was
not conversation. A hundred and four pixels of every line went to a column of
room names, twenty four more to a title bar naming a window you have had open
all evening, twenty eight under that to a heading and a note. The default
rectangle was 520 by 260 and the message inside it was 396 wide.

The column is one icon wide now. A room is a picture rather than a word, its
name and what the enter key would do in it are in the hover, and the count of
what arrived while you were reading somewhere else sits in the corner of the
icon rather than beside a name. `UI.List` takes `icons` and `describe` for it,
and a header in that mode is a hairline with air round it, because "Channels"
does not fit in thirty pixels and the air says the same thing.

The title bar is gone with it. `UI.Window` takes `bare`, which costs the bar,
the name and the close box, and a window that asks for it owes its player
another way out: the chat window's is a cross at the foot of its own rail. The
footer is a second number now rather than the one constant, because a strip
holding one line of text is not a strip holding a row of buttons.

The heading row and the note beside it are gone too, and what they said is in
the empty line you type on: **Party, enter types /p**, until there is a
character in the field, at which point the field says it better. That is the
same argument the slash in the field has always been. The window is 400 by 210
by default and the message in it is 358 wide, which is thirty five per cent less
window for a wider line.

A file that still holds exactly 520 by 260 is a file where nobody touched the
two steppers, and that pair was chosen for a window with fifty pixels of chrome
and a hundred pixel rail in it. It is moved to the new default once at login.
Any other pair is left alone, because a number somebody set is a number somebody
set.

### A font object carries a justification, and every line of chat was centred

`CreateFont` hands back an object justified centre, a frame given one takes both
the face and the justification, and `UI/Text.lua` had never said otherwise. It
went unseen for as long as it did because `UI.Label` justifies each font string
itself after it sets the object, so the object's own answer never reached the
screen.

Then the chat window put a `ScrollingMessageFrame` on one. That frame makes its
own font strings and no caller can reach them, so the only place to say how they
are justified is the frame, and `SetFontObject` overwrites that with the
object's. Every line anybody spoke came out centred, and the `SetJustifyH` three
lines above it in `UI/Log.lua` was doing nothing at all. Every object this addon
makes is justified left where it is made.

### A room made after the window was laid out drew nothing

A room's log is built on the first line that lands in it, which for Say is the
first thing you say all evening and for a whisper is somebody you have never
spoken to. `Relayout` placed the logs that existed when it ran and nothing
placed the ones made after it, so those came out anchored to nothing at no size.

Every symptom pointed somewhere else. The line went into the buffer, the count
went up against the room in the rail, `/wk status` counted it, and the room drew
an empty rectangle. You could see what you had just said in Conversation and not
in Say. `ChatWindow.Shape` reports a room's log size so the harness can state
the claim from outside the file, and `List:RowWidth` reports a row's width for
the same reason: a rail that is the right width with rows that are two pixels
wide answers every other question correctly and draws nothing.

That second one is not hypothetical. `UI.ScrollView` reserves sixteen pixels for
the scrollbar column, which is right at a hundred and eighty and absurd at
thirty, so the first icon rail had fourteen pixels of room for an eighteen pixel
icon. The view takes `overlay` now and floats the bar over the content on a
column that narrow.

### A font size is a pixel height, and two places had it in units

The loot feed's filter chips shipped drawing nothing. Every measurement in a
widget file is a design pixel multiplied by the zoom, so `16 * unit` is the
shape of nearly every line in `UI/`, and the chip's mark was written the same
way: `UI.Glyph(chip, CHIP_MARK * unit, ...)`. A font size is the one thing that
is not a unit measurement. Inside a frame `ns.UI.Adopt` has taken onto the grid
a font size already is a pixel height, so this asked `UI.GlyphFont` for 26.25,
`SetFont` refused the fraction, the readback in `UI/Text.lua` then failed its
fallback as well, `GetFont` came back nil, and every chip drew an empty square.

Nothing that measures a rectangle could see it. The geometry was right and only
the picture was missing, and the harness runs at one unit per pixel where the
fraction never appears at all. It took a screenshot.

So the fix is a gate rather than an edit. `check.sh` refuses a font size
multiplied by a unit anywhere in the addon, and the first run of it found the
same mistake a second time in `UnitFrames/PlayerCast.lua`, where the spell name
and the seconds left on your own cast bar are sized off the bar's height. That
one has been on main since the cast bar landed and would have drawn no text at
any UI scale that is not a whole number of pixels.

### A tooltip can open above the thing it describes

Beside is right for anything the width of a row. It is wrong for anything
smaller than the cursor: the pointer's hotspot is its top left corner and the
arrow hangs down and to the right, so a box pinned to the top right of a sixteen
pixel chip opens underneath the arrow that opened it and you read it round the
pointer.

`Tooltip.Show` takes a third argument for it and `Anchor` still picks a side the
same way, so a chip on a feed dragged to the right of the screen throws its box
left rather than off the edge. The chips are the only caller. `Tooltip.Frame` is
published so the harness can assert the box's bottom edge is above the chip's
top, which is the only way to state that claim from outside the file.

### The chat window is a rail of rooms, and the room is the channel

Three tabs became thirteen rooms. A room is one conversation: Conversation and
System at the top, then your groups, then Say, Party, Raid, Instance and Guild,
then a room per person whispering you, eight of them at once. Each has its own
log, its own scroll position and a count against its name for what arrived while
you were reading something else.

Three is what fits across the top of a window, and that number was deciding the
design. Everything anybody said went into one column because there was nowhere
else to put it, which is the sliding spill this part was supposed to be the
answer to. A rail down the left has room for thirteen, so a room can be one
conversation rather than one compromise.

The other half is the part worth arguing about. The old window had a button
beside the field that cycled six channels, and it had nothing to do with the tab
you were reading: you could be reading Whispers and typing into guild all
evening and nothing on the screen would have said so. The room is now the
channel. Selecting the party room is the same act as choosing to talk to your
party, and when you start typing the field already reads `/p ` with the cursor
after it.

The slash is in the field rather than on a label beside it. A label is the addon
telling you where the line will go; the slash is the line. You can see it, delete
it, or change the p to a g, and `/w Aria` typed inside the guild room whispers
Aria and leaves the guild room where it was. There is no second piece of state
holding which channel you are in, which is why there is nothing left that can
disagree with the rail. Tab steps to the next room and rewrites the slash.

Every channel prefix the addon knows is one `SendChatMessage`. Everything else
with a slash on the front still goes to `ChatEdit_SendText`, which is what
Blizzard's field calls, because keeping up with every command in the game is not
this file's job. `/raid` is raid and `/r` is reply, the way the client has it.

A room is a view and not a box. One line lands in every room it belongs in, so a
whisper from your wife is in Whispers under her name, in Family, and in
Conversation. A room is drawn while the channel behind it exists or while it
holds something unread, so a party line that arrived as you left the group is
still reachable and reading it is what makes the row go away.

### Groups, in place of one flat list of important people

The old list was one column of names and one tab for all of them, on the
argument that what you want to know is whether anybody you care about has
spoken. That holds until there are two kinds of person on it. A wife in party
chat and an officer asking about raid times are both on the list, and one of
them you answer now while the other you answer at some point this week.

Six groups, twenty people each, a room per group, and a person may be in two of
them with their line going to both. Everybody on an existing list is carried
into a group called People at the first login and the old key is dropped, so
nothing is retyped. The panel page is the loadouts page's shape twice over: a
strip of groups, a strip of who is in the one you picked, a field under each and
one button that adds everyone standing with you.

### Blizzard's chat window is hidden, and nothing it drew is lost

This is the change the old README said could not be made. Loot, experience,
faction, system text and every addon's output arrive at a chat frame's
`AddMessage` as finished strings with nothing on them saying where they came
from, so hiding that frame without more would delete all of it.

What makes it safe is that hiding forces the claim. The claim takes every
conversation event out of Blizzard's frames before FrameXML draws it, so what is
left arriving at `AddMessage` is exactly what this addon did not capture, and
forwarding it whole to a System room cannot double anything. That was never true
with the claim off, which is still the case and is why the claim cannot be turned
off while the window is hidden.

The switch is one line in `UnitFrames/Blizzard.lua`'s table, beside the other six
that say hide Blizzard's copy of a thing this addon draws, so there is one page
and one word for all of them. What is not a line is the mechanism, and that is
`Chat/Blizzard.lua`, registered through a new `Blizz.Also`. The rule that file
states is that the next thing to hide should be a row rather than a file, and it
holds for a frame that goes down when a boolean says so. It does not hold for a
window whose hiding deletes the game's own output unless the forward goes with
it.

Nothing is unregistered and nothing is destroyed. The frames go down through
`ns.Strip`, which puts a frame's own `Hide` where its `Show` was and so survives
the client showing it again, and only a frame that was on screen is taken, so
putting the window back does not turn on eight tabs nobody ever opened. They keep
their own scrollback, so one tick puts the window back with the evening still in
it. Closing this window puts Blizzard's back on the next call, which is
the coupling the claim already had and for the same reason: the first version of
the claim did not have it, and one press of a close box deleted every line of
conversation from the screen.

The enter key comes here while that window is hidden, through an override
binding that is dropped by one call and handed back the moment the window is
shown. It is not a setting of its own on purpose. The client's enter opens the
client's chat line, and with that window hidden the line it opens is invisible,
so the key has to move or typing is broken. Every slash command still works from
this field.

### UI.List, which is the rail for a column that changes

`UI.Rail` is the options window's: forty five sections known at load, built once,
folded and unfolded. The chat rail is the opposite problem. Which rooms exist
changes every time you join a party, leave a guild or get a whisper from
somebody new, and folding is not the question there. What is drawn at all is.

So a caller hands `UI.List` the rows it wants and the widget works out which
frames to reuse, pooling them because a frame cannot be destroyed on this client.
Rows are addressed by a string id rather than by position, because the position
of a whisper moves every time somebody else whispers you and the selection has to
survive that. `List:Mark` moves one row's count without rebuilding the column,
which is what keeps a raid night from costing thirteen `SetText` calls a message.
### The loot feed, made worth looking at

Five changes, and four of them are one argument: the loot feed was a column
dressed as a window, and a window is not what it is.

**The chrome is gone and it is a setting either way.** The word "Loot" sat over
a column whose rows are an item icon, an item name in the item's own quality
colour and a stack size, and a hairline rectangle sat round the whole thing.
Neither was carrying information. `Stream.Defaults` takes a third argument for
whether a stream ships with them, the loot feed says no and the combat feed says
yes, and both are `<prefix>Header` and `<prefix>Edge` for anybody who disagrees.
The combat feed keeps them because its rows are three columns of numbers and a
column of numbers with nothing named over it is one you have to work out.

What the header is worth is not the setting but the geometry. A strip that stops
being drawn without the rows moving up is a band of empty window, so
`Feed:Chrome` owns one number and Resize and Sync read it rather than each
deciding again.

**Filter chips instead of a quality floor.** Seven small squares over the rows:
five gems in the quality colours, then a break, then a quest bang and a stack of
coins. Each is on or off and the quality five say which they are by colour,
because the quality ramp is a thing every player in this game already reads.

The first cut of this drew each chip as a rectangle of flat quality colour and
nothing else, which is obvious in a screenshot and invisible in the geometry:
seven hard-edged colour swatches in a row is a colour picker, and it read as
something left on the screen by mistake. Nothing else in this addon that you
click is a bare colour. An ability square, an aura square and a button in the
panel are the same thing, a dark square with a hairline and a mark on it, and a
chip is now that at chip size. `bake-glyphs.sh` gained three codepoints for the
marks and the header went from 16 units to 20 to hold them, which is air the
heading wanted anyway.

The letters those glyphs are baked onto were a choice rather than an accident.
`*`, `!` and `$`: a client that refuses the font falls the whole string back to
Arial Narrow, and what comes back is still a mark rather than three empty
squares. `!` is the same mark in both faces.

The floor they replace worked at the door. An item under it never became a row
and no amount of changing your mind got it back, which is the wrong end to
filter at for a window whose whole job is answering "what did I just get". Now
everything that drops is recorded and the chips decide what is drawn, so turning
one back on brings its history with it. `lootFeedQuality` is gone and
`lootFeedShow` is a five bit mask in its place; the panel carries the same
switches, and the tally over the column reads "4/40" whenever a chip is hiding
something, because a feed showing four rows when forty things dropped otherwise
looks broken.

Filtering costs a walk of the ring rather than the one step an unfiltered feed
takes, so `UI/Feed.lua` walks it once per paint into a window it owns rather
than once per row, and caches the count. A feed with no filter is exactly the
file it was.

**A quest item gets a ring round its icon.** It is white, the same white as a
stack of linen, so the row that hands in your chain of five kills read exactly
like the row that hands you a bandage. `ns.ItemKind` already answered class 12
for Comfort/Clutter.lua and now answers it here. The quest chip is an override
rather than an eighth tier: on, a quest item is drawn whatever the white chip
says, which is the combination that makes the feed useful while questing.

**The hover says what the thing is worth.** Two numbers and they answer
different questions. The vendor price is the client's own and is per item, so a
stack gets a second line with the total on it, which is the number you actually
decide on and which no tooltip in the game gives you. An item a vendor will not
take says so in words rather than showing 0c, because nought copper and "not
cached yet" are the same number and different facts.

The auction price is not the client's at all. There is no API in this game for
what an item goes for, so `Feeds/Auction.lua` asks whichever scanner the player
has installed, in order, and takes the first answer: Auctionator on either of
its two interfaces, TradeSkillMaster, Auctioneer, RECrystallize. Nothing is
required and no TOC names one as a dependency. A player with none of them loses
one line of one tooltip and is told nothing about it. The line names the addon
that supplied the number, because a price with no source on it is one the player
cannot check, and that is also why the first scanner wins rather than an average
of two: two scanners disagreeing is a real thing, and averaging them is a number
nobody's addon holds.

**And the row is a size.** `<prefix>Icon` runs 16 to 40 and the row is the icon
plus two, so one stepper moves the picture, the line height and the height of
the whole frame. The floor is the text rather than the art: every string on a
row is outlined, `UI.OutlineFloor` puts an outlined glyph at 14 or above, and a
row shorter than 16 is one whose name does not fit however small the picture
gets. `UI.FeedIcons` takes the size as an argument now that it is a setting,
because the panel note it feeds was otherwise telling every player the same
thing whatever they had dragged the slider to.

`31-feeds.lua` stayed what a feed is and `40-loot-feed.lua` is what is only ever
true of loot, which is where the section went over the eight hundred line limit
rather than under an allow-list. The client stub gained one white item that is
not a quest item, because "the whites are off and the quest item is still drawn"
is not a claim you can make about a column with one row in it.

### Full flexibility on the cloned bars

The clone shipped with the shape of every bar in source and one tick box per bar.
That was the right default and too little of an answer: bar 1 was a row of twelve
because the plan said twelve columns, and there was no way to fold it, tint it,
take it off the screen in a fight or bring it up on a key.

`Buttons/Look.lua` holds five settings per bar and `ns.db.barLook` keys them by
the plan's bar key. Rows, the colour of the ground under the squares, that
colour's opacity, whether the bar goes down in combat, and which modifier holds
it up. Every one of them defaults to something that is not a setting, so a bar
nobody has touched carries no record at all and `actionbars plain` is a deletion
rather than a write. That is `Buttons/Which.lua`'s shape for the tick boxes and
it is what makes a fresh clone of the repo look like the machine it was written
on.

Six shapes, not twelve: 1, 2, 3, 4, 6 and 12 rows are the numbers that divide
twelve, and a last row with a gap on the end of it is a bar and a stump. The
panel's stepper counts in ones and walks between the six on the direction of
travel, because snapping to the nearest is a control that does nothing on every
second press. A typed number that is not a shape is refused rather than rounded.

How big a square is was a constant with an argument attached to it, and it is a
setting now with the argument intact. 27 and 54 are the only two drawn sizes
where one stored icon texel lands on one screen pixel, so the default is the
sharp one, the range is 16 to 54 to cover both, the step is one pixel so neither
can be stepped over, and the readout says "blended" at every other stop rather
than reporting a number and letting the art go soft unexplained.

Two buttons put one bar's middle on the middle of the screen, one axis at a time,
leaving the other axis where it was. Neither asks the screen how wide it is: an
anchor with its horizontal half taken off, held to UIParent at zero, is centred
by the client at every resolution, and the vertical half is kept, so a bar along
the bottom of the screen is still along the bottom of it. Refused in combat, with
nothing written when it is.

Eight named colours rather than three sliders. This is an addon for one person
who wants the same interface on every install, and a colour you dialled in lives
in one WTF folder. Two of the eight are the theme's own and the other six are
deliberately dark and flat, because the background is the ground under twelve
pieces of Blizzard icon art. The opacity is `ui.Opacity`, 0 to 100 in fives like
the other three in the addon, and at nothing the hairline goes with it.

The two that decide when a bar is on the screen cannot be done from Lua at all.
Everything inside a bar is a secure button, so the frame cannot be hidden once
the client is in lockdown, and a fight starting is the moment you want it gone.
Both are a visibility state driver instead: `[combat] hide; show`, or `[mod:shift]
show; hide` for a bar that is up only while a key is held. A key beats the combat
switch rather than being read alongside it, because a bar you hold a key for is
down unless you are holding the key, and `[mod:shift] show; [combat] hide; show`
is the other setting wearing this one's name. Keys go on working while a bar is
off the screen, which is the point of a bar you only look at sometimes.

`actionbars unlock` is the bars' own lock and it is shift-dragging: the handles
come up while shift is held, watched off `MODIFIER_STATE_CHANGED` rather than a
ticker, and no other frame in the addon is unlocked while you nudge one. It ships
locked, because a handle takes every click that lands on it and a shift-click
over a bar belongs to the handle while it is up.

The panel page is a tab strip and one set of controls rather than five bars times
six controls down a column, which is the shape the loadouts page and the people
page already have. Every setting has a slash word: `actionbars rows|colour|
background|combat|key <bar> <value>`, and `actionbars plain` drops the lot.

The bar the strip names wears an accent rim while the window is open, because a
tab that says "bottom left bar" names a bar you then have to find by counting and
the two on the right of the screen are a pair of identical columns. Two pixels of
the colour the selected tab is marked in, two pixels outside the bar so it does
not cover the hairline already there.

That needed a hook Core did not have. `showing`, on the registry, is the options
window opening and closing, fired off the window frame's own `OnShow` and
`OnHide` rather than out of `Options.Show` and `Options.Hide`, because Escape
closes the panel through `UISpecialFrames` and never comes past `Core/Panel.lua`.
A mark that outlived the window would be an accent rectangle round one bar for
the rest of the session with nothing on screen to say why.

`harness/sections/38-bar-look.lua` is 85 checks: the arithmetic of every shape,
a shape put back to the plan's being dropped rather than stored, the colour
reaching the texture, the hairline going with the background, the macro each pair
of switches registers, the driver count after three restyles, the driver being
handed back with the bar, the words parsing a bar name and refusing a value
without writing it, and the handles following shift. It is
a section of its own rather than two hundred more lines in `05-action-bars.lua`,
along the seam that file already had: that one is the clone, and nothing in this
one knows what an action slot is.

One thing the harness found rather than proved: `22-chores.lua` replaced
`IsShiftKeyDown` with a constant and left it replaced, so every section after it
had been running with shift welded off. It goes through the stub's own switch now.

### Party and raid frames

Todo item 6. Blocks for the people you are grouped with, in the addon's own
look, and Blizzard's party and raid frames off the screen behind them. The
Charge button casts Intervene at whoever you are looking at and there was no
fast way to look at a party member, which is the whole reason the item exists.

These are our frames rather than Blizzard's wearing our skin, and everything
else follows from that. `PartyMemberFrame1` is bound to `party1` in XML and
there is no supported way to point it at anyone else, so the moment the order is
decided by role the client's frames cannot draw it. `UnitFrames/Group.lua` is a
`SecureGroupHeaderTemplate`, its attributes and the slot order;
`UnitFrames/Member.lua` is one member's block, and it knows nothing about a
header or an order and reads no setting of its own.

The order is tanks, then healers, then damage, and by name inside a band. By
name is arbitrary as an ordering and it is the only one that is stable: the same
five people produce the same five slots in every group they are ever in
together. It is recomputed out of combat and nowhere else, which is what makes
fixed placing true rather than aspirational, and it reaches the header as
`sortMethod = "NAMELIST"`. `/wk party order group` swaps that for the raid's own
group numbers; a party is always by role.

`Unit/Role.lua` answers what somebody is playing out of four sources that
disagree: an answer you typed, `UnitGroupRolesAssigned`,
`GetPartyAssignment("MAINTANK")`, then the winning talent tree, then the class.
Only the last is not cached, because caching a guess is how a warrior stays in
the damage band for the rest of the night after the client finally said
Protection. `Meter/Spec.lua` moved to `Unit/Spec.lua` to be reachable from it and
grew one function, which answers the winning tree's index and points beside the
icon it already answered.

`/wk hide party` and `/wk hide raid` take the client's copies down and both ship
on. The raid needed more than a strip: `CompactRaidFrameManager` re-shows its
container through `SetShown`, which is resolved in C and never reads the Lua
`Show` that `ns.Strip` replaced, so that layout pass is hooked and
`BlizzHide.Apply` now looks at what is on the screen rather than at what it did
last time.

Ctrl-click marking had to be put back by hand. `Marking/Marking.lua` hooks frames
by name and the four party frames are on that list, so hiding them took marking
on a party member with them; `ns.Marking.Watch(frame)` is the one exposed
function and `UnitFrames/Feature.lua` calls it as each button is built.

`harness/client/09-group.lua` is a party, a raid and a model of the header
written from the contract, because the stub had no group tokens, no roles and no
templates at all. `harness/sections/39-party-raid.lua` drives the slot order
under three rosters and all four role sources, holds the class colour, the power
colour, the missing rail and the role icon's crop to the palette and to
Blizzard's own grid, proves the order does not move in combat, and measures the
tick at 0.00 KB per 50 ticks over four blocks.

### Your own cast bar

The last Blizzard frame this HUD had left alone. Every unit around you was drawn
by the addon and the one bar you time a press against was still Blizzard's, in
gold, under an interface that has none.

`UnitFrames/PlayerCast.lua` draws it: 180 by 16 at `CENTER, 0, -250`, which is
under the swing bars and the same width as them, so the charge icon, the swing
bars and this read as one column of things you are timing against rather than
three features that happen to be near each other. `/wk cast on|off`, `cast
width`, `cast height`, `cast zoom` and `cast reset`, plus a section of its own in
the panel. `/wk hide playercast` takes Blizzard's down and ships on, like the
four switches beside it.

It is a bar of its own rather than a chamber under the player block, and that is
the decision the file is about. The enemy row opens downward out of the bar it
belongs to, because a mob's cast is one more thing about that mob. Under the
player block is where your debuff row hangs, so a chamber there would push that
row down and pull it back up on every cast, which is the row moving every time
the fight gets interesting.

Four answers come out of `UnitFrames/Cast.lua` and none is written twice:
whether there is a cast worth drawing, how far along it is, what the seconds
read, and what an unlocked frame previews. Two of those were private to that
file and are public now; two were extracted out of its own tick and sweep on the
way. The enemy row and your bar therefore cannot drift apart on a channel
draining backwards or on a rounded number promising a tenth of a second it has
not got.

What is new is the cast that failed. Interrupted, moved out of, or refused, the
bar turns red and holds where it stopped for seven tenths of a second rather
than emptying, because an empty bar is exactly what a cast that finished leaves
behind. `UNIT_SPELLCAST_FAILED` also fires for a press the client refused before
anything started, so the hold does nothing where the bar was already down.

`harness/sections/37-player-cast.lua` holds the fill to the same three
statements the swing bar is held to at 60 and 144 fps, drives the interrupt and
its hold, and measures the sweep at 0.00 KB per 200 frames of casting.

### The performance tab had a row that could never fill

`Perf.Start("cast")` has been bracketing the enemy cast sweep since that row
shipped, and `Perf/Feature.lua` has been drawing a line for it, but `cast` was
never in `Perf/Perf.lua`'s `ORDER`. `Perf.Start` looks the key up in a table
built from that list and returns without doing anything when it finds nothing,
so the row read as unavailable for the whole life of the feature and nothing
said so. Both `cast` and the new `playercast` are in the list now.

### The purse and the tooltip drew their text the wrong way

The three numbers along the bottom of the loot feed looked worse than the rest
of the window. They were outlined at 12 pixels, and `UI/Text.lua` puts the floor
for an outline at 14 for a reason: a rim spends a pixel of every stroke, so
below the floor the hole in a 6 closes and the waist of an 8 fills in. On the
one line in the window that is nothing but digits, that is the whole line. The
strip is 20 tall now and its text is at the floor.

Dropping the rim instead would have been the obvious fix and it would have been
wrong. A feed looks like it is painted on a surface this addon owns, and it is
not one: the background is a slider the player drags, it goes to zero, and
`Feeds/Feature.lua` promises them in writing that the text reads all the way
down to nothing. Flat text there goes with the surface. So the strip keeps the
outline it had and gets the height to carry one.

Two more strings were under the floor and nobody had hovered them: the drag
captions on the swing bars and the buff row, both at 12 over the world.

The tooltip was a different fault with the same shape. Its body was 11, a number
the file wrote for itself, and 11 is `UI.Metric.small` - the size the panel keeps
for a hint under a control. Every line of a tooltip is the thing you opened it to
read, so a box whose prose was smaller than the panel under it had it backwards.
Title and body come off `UI.Metric` now, at 13 and 12.

### Every string in the addon says what is behind it, and the addon checks

`UI.Label` used to take an outline when the caller named no role, which is how
ten sites ended up outlined without anybody choosing it. There is no default
now: `UI/Text.lua` names all three roles, `UI.FLAT`, `UI.SHADOW` and
`UI.OUTLINE`, every caller passes one, and `check.sh` fails a call that does not.

A grep can only see that a role was named. Whether it is the right one is a fact
about what is behind the glyph, and that is not in the source at all, so
`harness/sections/36-font-roles.lua` asks the built addon instead. It walks every
string that has text in it, 881 of them, finds what each is standing on by
climbing its parents until it hits a surface, and fails on three things: an
outline under the floor, a string with nothing behind it that is not outlined,
and MONOCHROME.

Then it drags every background opacity to zero and walks them all again. That
second pass is the one worth having. Three surfaces in this addon are not
surfaces - the two feeds and the chat window - and a string on one of them is a
string over the world that looks like it is not.

What counts as a surface is the whole difficulty, and it is a question about
geometry rather than about art. Taking any texture with a file path throws the
rule away: a loot row carries the item's icon at its left edge, and that backs
the name sitting beside it, which is 26 rows excused a rule they were never
measured by. Demanding a texture pinned corner to corner throws away the aura
square's icon, which is cropped and single-anchored, and fails 168 strings that
are right. What settles it is measuring the texture against the frame it is in
rather than against the glyph: an icon that is most of its square is a surface,
and a sixteen pixel icon in a two hundred pixel row is a surface for nothing but
itself.

Three sites are allow-listed with the reason written next to them, and each is
excused one rule rather than all three. The chat window is the one place the
three roles do not settle it: its text size is a slider from 9 to 20 and its
background is a slider to 0, and at the bottom of both there is no role that
works. It stays flat until one of the two sliders gets a floor. The
timer over an aura square is the other: it sits above the art rather than on it,
so it has the world behind it and takes a shadow anyway, because at 8 to 14
pixels an outline closes the hole in a 6. `UI/Aura.lua` already argued that
trade where it is made; the allow-list is where it is now enforced.

### Five icons, cut onto the letters they replace

The chevron on a folded group was a lowercase `v`, the shut one was a `>`, the
close button was an `x` and both ends of every stepper were `+` and `-`. Those
are not icons, they are the letters that look most like icons, and at ten pixels
of Arial Narrow they read as a typo.

`Media/Glyphs.ttf` is five marks of Font Awesome Free Solid, subset by
`scripts/bake-glyphs.sh` out of the copy already on the machine that builds it.
It is 2,172 bytes.

The part worth writing down is where the five sit in the font. They are not on
Font Awesome's own codepoints, they are on `v`, `>`, `x`, `+` and `-`. So no
call site carries a codepoint escape, no call site knows it is drawing an icon,
and nothing anywhere checks whether the font loaded: a client that refuses the
file leaves the font object empty, `UI/Text.lua` puts Arial Narrow in its place
at the same size, and the window draws the letters it drew last week. The
fallback is what the code was already doing, so there is no second path through
any caller to get wrong.

`ns.UI.Glyph` is a string in that face and `ns.UI.Button` takes `glyph = true`.
A glyph is not an icon here: an icon is the game's own art for a spell and
`ns.UI.Icon` still means that. Marks draw at 10 pixels against the body's 12,
because a Font Awesome glyph fills its em box and a letter of Arial Narrow uses
about two thirds of one.

The font is under the SIL OFL, which reserves the name Font Awesome, so the
subset goes out as WarriorKit Glyphs with the licence beside it in `Media/`.
`check.sh` learned that Media holds three kinds of file: a texture is TGA or BLP
with both sides a power of two, a font is a TTF and is measured for nothing but
has to have its licence next to it, and a licence is allowed there only because
its font is. `release.sh` fails a zip missing either file, and the harness walks
every string in the window, asserts the five marks are in the glyph face and
everything else is not, and drives the branch where the client refuses the file.

### The /wk window is sorted by what you came to change

`Core/Menu.lua` put a WarriorKit button in the client's own Escape menu last
week, and that raised the stakes on what the button opens. Until then the only
way in was a slash command, so everyone who opened the window had already read
something about the addon. Now somebody who has never heard of it can press
Escape, see a name and click.

What they found was eighteen rail entries, each one a registered part with a
capital letter on it. Three sat below the fold of a 390 pixel view and nothing
on screen said so. Behind them were 44 tabs, 134 controls and 134 notes holding
40,268 characters, about fifteen pages of prose with switches embedded in it.

**A section names its own group.** `ui.Header(title)` is now
`ui.Section(title, group)`, and the panel declares eight groups: Start here,
Fighting, You, Them, Readouts, The screen, Chores, Under the hood. A group that
does not exist is a login error rather than a section quietly landing in a
default. Eight entries come to 184 pixels, so the rail fits a 390 pixel view
folded shut, which the eighteen never did.

That also lets one part's sections sit apart. `UnitFrames/Panel.lua` has three
and two of them are about your own frames while the third is about enemy
nameplates; they are in **You** and in **Them** now without a line of code
moving between files.

`order` no longer decides rail position, because the rail is not made of parts.
It decides where a part's sections sit inside a group, and `ns.Register`
refuses anything that is not a whole number or that another part already took.
`artwork` and `minimap` were both on 8 and their relative position was whatever
`table.sort` felt like.

**The rail folds.** The group you are in stands open with its sections listed
under it, indented, and choosing one is a single click on the thing you came
for. It replaced a strip of tabs across the top of the page, which had two
faults. The strip could only show the sections of the group you were already on,
so the window never showed more than an eighth of itself at once. And Fighting's
eleven wrapped onto three lines of stubs, which took a fifth of the page's
height to say what a column says in a column.

One group is open at a time. Clicking the open one shuts it and leaves its page
up, with the mark moved onto the group's own line, so the rail can be folded
flat to eight lines without the window going blank; clicking a shut one opens it
onto whichever of its sections you were last reading. The rail is 180 pixels
wide because a section title has to be readable in it, and the window is 608 so
that the page keeps the 400 pixels it had. Open is taller than the view when
Fighting is out, and the rail scrolls; whatever is selected is kept inside the
viewport. The title of the section you are on is drawn over the page, on the
hairline that used to be the underside of the tab strip.

**One switch per part, drawn by the panel.** A part declares
`switch = { key, label, apply }` and the panel draws the check box in the same
place on every part's first page. Eleven features had each written their own for
the same idea: `show the row`, `show the icon`, `Show the meters`, `Show the
swing bars`, `show enemy bars`, `draw the WarriorKit chat window`. The rail now
marks any group holding a part that is on, which is the one question the window
could never answer without opening forty five pages, and **Start here** is a
whole page of nothing but those switches and their ledes.

**Notes are gone and three capped calls replace them.** `ui.Lede` is one line
under a section title at most 160 characters, `ui.Hint` is at most 200 and draws
in the addon's own tooltip on hover, and `ui.Reading` is a live number in the
accent colour that never wraps. 44 ledes, 75 hints and 81 readings come to
14,375 characters against 40,268, and the harness fails past 16,000. The
reasoning the notes carried moved to `docs/README.md`, which is where explaining
the addon belongs and which can be read on a second monitor while the game runs.
Five parts had no notes there at all before this: the feeds, the chat window,
the minimap, the performance tab and the breakdown were documented only inside
the panel.

**A search field in the title bar, focused when the window opens.** Every
control records its label, its section and its group as it is built. Typing
filters and each result reads `group / section / label`; clicking one opens the
group, selects the section and marks the row. Emptying the field puts the page
back. It did not while the tab strip existed. The strip returned and the section
under it stayed hidden, so the window sat blank until you clicked a tab, and the
harness now clears a query and checks the page is there.

A query matches the label, the section title, the group name and the part's
slash words, so typing `skin` finds the frame controls that `/wk skin` drives.

**Four kit calls for the four knobs every part had reinvented.** `ui.Zoom` has
no range because there is one and it is 1 to 3; four files had declared
`LOW_ZOOM, HIGH_ZOOM = 1, 3` at the top of themselves. `ui.Opacity` has no range
for the same reason, and the meters' `bar opacity` is called `background` like
the other two. `ui.Size` keeps the caller's range, because a feed is 200 to 520
wide and a minimap is 120 to 300, and writes `px` after the number so four pages
can all say `width`. `ui.Count` is rows and bars, and `list bars` is called
`rows`. Charge's three icon steppers became `icon size` on the button and a
`size` and a `height` in a section called **The icon over the mob**.

Three controls were deleted: the zoom stepper on Buffs, Feeds and Meters. Those
three are read between fights, and the argument for a private zoom is that a
thing you read mid swing has to stay exact at a size you chose. That covers the
enemy bars and the swing timer and it does not cover a loot feed. Every setting
they wrote is still there and every slash word still takes it.

Nothing about the slash commands changed. Every word keeps working, `/wk` on its
own still opens the window, and the words are sitting inside people's macros.
Nothing on the game screen moved.

Section 16 of the harness grew the rules: every section names a group that
exists, no group holds two sections with one title, no title repeats its group's
name, every lede and hint is inside its cap, every reading fits one line, no
label is empty or ends in whitespace, all 147 labels are findable by typing them
in full, and every part with a boolean in its defaults declares a switch or is
allow-listed with a reason. The fold has its own: one group open at a time, one
line under it per section, every line short enough to be read whole in the
column it sits in, and the page still up when the group it belongs to is folded
shut over it. `check.sh` got the half a grep can settle, with each
rule naming the kit call to use instead.


### The client's own aura row has a switch of its own

`/wk auras off`, and the corner of the screen is empty: your buffs, your
debuffs and the temporary weapon enchant beside them. The panel carries the same
switch on the frame skin's aura tab, under the rows this addon draws.

It exists because the sweep that was already hiding those buttons could not be
relied on to. The skin hides them one name at a time, `BuffButton1` through
`BuffButton32` and the three enchant buttons, because a button the client builds
the first time you carry nine buffs has no other handle. A name this backport
spells some other way stops the sweep and hides nothing, which is what two
reported screenshots were: the client's row drawing over ours, in gold, saying
the same thing.

So the switch takes the other handle. It hides `BuffFrame` and
`TemporaryEnchantFrame`, two globals rather than fifty-one names, and every
button the client parents to them goes down whatever it is called. The two
mechanisms never argue over a region. The sweep holds buttons, the switch holds
their frames, `ns.Strip` marks what it holds, so turning either off gives back
only what that one took.

On by default, and on a default install you will not see it do anything: the
skin is drawing your auras under the block and the client's buttons are already
hidden. The switch is for the player running with `skin off` or with the player
frame left alone, whose buffs are the client's row and nothing else. That player
loses the last reading of the stone on their weapon when they switch it off,
because the missing-buff row only speaks once the stone has run out, and the
panel note says so rather than letting them find out in a raid. Right click to
cancel a buff goes with the row too.

`/wk status` says which of the two frames this client carries. Nothing hidden
and neither frame found is a client that names its aura frames something else,
which is a different failure from a switch that did nothing.

Section 14 asserts both frames down, the strip holding against the client
showing its own row again, and both frames back on the way out. The harness
client parents `BuffButton1` and `DebuffButton1` to `BuffFrame` and
`TempEnchant1` to `TemporaryEnchantFrame`, the way both clients do.

### The addon is in the game menu, and there is a spec for the window it opens

A slash command is a thing you have to be told about. Escape is a thing everyone
already presses. **There is one button in the client's own game menu now**, it
says WarriorKit, and it opens the panel `/wk` opens. No setting guards it,
because a check box that hides the way into the settings is a check box nobody
can find their way back to.

The menu belongs to Blizzard and the two clients this addon ships for do not
build it the same way, so `Core/Menu.lua` names no Blizzard button, reads no
localised string and assumes no count. It reads the anchor chain the menu is
already laid out with, hangs our button off the end of it and grows the frame by
exactly what it added. Our button takes the foot's anchor verbatim and the foot
takes the same anchor again off ours, so whatever gap the client leaves between
two buttons is the gap above ours and below it. A client that lays its menu out
some other way gets no button, no error, and a reason in `/wk status`.

The foot is the button nothing else hangs off. Every button in the column
contributes what it hangs off, shown or hidden, and only shown ones can be the
foot, because Blizzard hides buttons in that column and a walk that skipped one
would lose track of the button above it and find two feet where there is one.

The work is on the menu's `OnShow` rather than done once at login, because a
client that lays its own menu out on show will have dropped us out of the chain
by the time it is next opened. Everything the attach reads it reads fresh, and a
run that changes nothing writes nothing. A version that grew the frame on every
show would reach the top of the screen inside a session.

**`SPEC-menu.md` is the redesign of the window that button now leads to**, and
it starts by counting what is in there: eighteen entries in the rail, 44
sections behind them, 134 controls, and 134 notes holding 40,268 characters of
prose. One note per control, exactly. The spec asks for eight groups a player
can rank instead of eighteen module names, capped prose in three narrower kinds
with what is cut moving to the README, one declared switch per part so you can
see what the addon draws without opening 44 tabs, four kit calls for the four
knobs that were reinvented once per part, a search field, and a Start here page
of nothing but switches. Nothing in it changes a slash word.

### The aura square reads the way the client's own row does

Reported from the game with a screenshot of Blizzard's buff row above ours. Two
rows of icons, one over the other, saying the same kind of thing in two
different languages: theirs `14 m` in gold above the icon, ours `4m` in white
inside it, and the number inside the art was the one you could not read.

**The number moved off the art and into a strip over the square.** A number
written on an icon is a number over a picture somebody else chose. 27 on a pale
bandage and 27 on a dark bleed are two different readings, and the drop shadow
behind it only ever rescues one of them. Over the square it has the world
behind it, which is a worse background in theory and a better one in practice,
because nothing else is competing for those pixels.

That makes the widget taller than it is wide, so it is two frames now: the
square, which is the art and the hairline and the sweep, and the widget, which
is the square plus the strip. `Aura.Size` hands its caller back a width and a
height instead of one number, and both rows put what comes back into their
layout node. The strip is the timer's own type height and a pixel of air, taken
up to whole pixels so the art below it still starts on one. The mouse stays on
the art: `SetHitRectInsets` keeps the strip out of it, because a tooltip that
opens over blank sky above an icon is a tooltip nobody asked for.

**The colour is the client's rule now, and so is the format.** Gold while the
time is counted in minutes or hours, paper white once it is counted in seconds.
That is the same fact the unit already carries, which is why `Tint` takes the
unit rather than the seconds. The string is written out the way the client
writes it, with the space and the unit on every reading: `14 m`, `2 h`, `56 s`.

The amber-under-ten, red-under-five ladder this replaces was not wrong about
what is urgent. It was wrong about who decides. Half the auras on the screen
are drawn by the client in a row of its own, and two rows that disagree about
what a colour means are two rows you have to read separately.
`Color.text.duration` is the client's `NORMAL_FONT_COLOR` written down rather
than read, for the reason the class colours are written down: a global this
addon does not own can be absent on one client or moved by another addon. It is
not a token, because it stands over the world rather than on a fill the palette
caps.

Sections 6, 7 and 14 measure all of it. The bar's height is built from the
square the setting draws plus the strip over it rather than from the setting
alone, section 7 asserts the string and its colour at both ranges, and section
14 asserts the anchor, the strip in whole pixels and the hit rect at three
square sizes. The harness client records `SetTextColor` for that, since one
string in the addon says two things in two colours.

`LayoutWidget` on the enemy bars gave its tracked row up to `IconRow` on the way
through, and shape.lua's entry for it comes down from 203 lines to 185.

### The aura square sweeps, and says the time the way the client does

Reported from the game with a screenshot of Blizzard's buff row beside ours:
theirs reads `28 m`, ours read `1972`.

Both halves of that are fixed and they are one reading between them.

**The square sweeps.** A wedge over the art, drawn by the client's own Cooldown
frame, reversed so it fills as the aura runs out rather than emptying the way a
cooldown does. That is the difference worth having: a number is a thing you read
and a wedge is a thing you see, and a row of twelve squares is read at a glance
or not at all. The refreshed square is the bright one and the square about to
drop is the dark one.

The wedge needs a fraction, so both scans now carry the aura's duration beside
its expiry. A temporary weapon enchant has an expiry and no duration anywhere in
the client's API, so its square counts down in text and never sweeps. That is
the truth about what is known rather than a wedge drawn against a guess.

**The number is in the largest unit that still says something true.** Whole
seconds, at any range, is what put four digits across a sixteen pixel icon: a
half hour buff read `1972`, which is a precision nobody uses, over the art that
says which buff it is. It reads `28 m` now, and `2 h`, and seconds under a
minute, rounded up in every unit so a square never reads 0 while the aura is
still on the unit. The type is sized at under half the square rather than six
tenths, because the string is four characters wide now and was two.

The colour of that number, and the exact format of it, are the entry above:
this one landed an amber and red ladder of our own, and the client's own gold
and white replaced it before either shipped.

Measured in section 7, which now asserts the reading and its unit, the two
numbers handed to the sweep, and that the sweep is reversed. The harness client
records `SetReverse` for that, because an aura sweep and a cooldown sweep are
the same two numbers and opposite pictures.

`UpdateWidget` on the enemy bars gave up its tracked row to a function of its
own on the way through, and shape.lua's entry for it comes down from 142 lines
and 41 branches to 123 and 31.

### The aura square draws its art again

Reported from the game with a screenshot: the squares over the block show their
timer and nothing else. No icon, no hairline, at a size that had been working.

Two things could do that and both are fixed, because the screenshot cannot tell
them apart and either one on its own leaves the same empty square.

**Every region of the square has a size of its own now.** The art hung off two
opposite corners of the square and each hairline off two adjacent ones, so all
five were rectangles the client had to derive from a frame that had just been
resized under them. The square's edge is a setting, which makes it the one
widget in the addon that gets resized while the addon is up, and a region the
client declines to work a rectangle out for draws nothing and raises nothing.
The timer cannot fail that way, because a font string is as big as its text and
is anchored to a corner rather than sized by one, which is exactly why a number
was the only thing left on the screen. `ns.EdgeSize` takes an optional length
for this and nothing else passes it.

**An aura with no art falls back to its spell's own texture.** A client is
allowed to hand back an aura carrying no icon, and these rows are the only
reader in the addon that takes one off the aura rather than off a spell it
already holds: the enemy bars draw the list you asked them to watch and have
`ns.SpellTexture` for every entry in it. So the same picture is asked for from
the other end, at the cost of one call on the aura that has no art rather than
one on every aura.

Both are measured. Section 14 lays the rows out at 12, 20 and 28 and asserts the
art's inset and size, both hairlines, and that an aura answering no icon still
draws the spell's. Reverting either fix fails the run.

### `/wk skin probe` measures the aura square rather than repeating the setting

Reported from the game with a screenshot: the aura squares draw their timer and
nothing else. No art, no hairline, at a size that had been working.

The screenshot settles more than it looks like it does. The block is 68 pixels
tall, the two numbers over it sit 31.5 apart, which is a 28 pixel square and the
3 pixel gap, and they are right aligned on the block's top corner one gap up. So
the row is exactly where the row belongs and the layout is not what is wrong.
What is gone is everything that is a region of the square, because a font string
draws off its own anchor whatever the square does while the art and the hairline
take their size from the square's edges.

Every number the probe printed was a number that went in rather than one the
client used, which is why none of them said anything about this. Each row's line
now carries the width the square came out at, the width the art came out at,
whether the art was ever handed a texture, and how thick the hairline is, all
read back off the widget.

**The resize itself is measured now.** Section 14 lays the rows out at 12, 20 and
28 and asserts the square, both corners of the art's one pixel inset, the
hairline and that the square still holds its texture afterwards. It passes,
which is the point: it says the arithmetic in `Auras.Place` is not the fault and
narrows what is.

**The harness could not have caught an inset bug at all.** The client stub took
`SetPoint("TOPLEFT", x, y)`, which is how every inset in the addon is written,
and stored the two offsets in the fields `GetPoint` hands back as the relative
frame and the relative point. So the offset read back as zero and the relative
frame read back as a number, and anything asserting on an inset was asserting on
nothing. The stub models both shapes.

### The client's weapon enchant goes off the screen with the rest of its auras

Reported from the game: with the addon's own rows on, the client is still
drawing auras.

`TemporaryEnchantFrame` was the one thing the sweep deliberately spared, and
the reason expired in the change directly below this one. While nothing here
drew the enchant, the client's copy was the only reading of the stone on your
weapon and taking it down would have taken that reading with it. The row draws
both hands at its own head now, so what the corner held was a second copy of a
number the square already carried, sitting where you have to look away to read
it. `TempEnchant1` and up are swept like `BuffButton1` and up, and an aura this
addon draws is back to having exactly one place on the screen.

**It is a run of its own rather than the tail of the buff row's names.** The
sweep stops at the first name the client has not built, because the client
builds those buttons on demand and in order, and the two names do not fill
together: on a character carrying six buffs the walk stops at `BuffButton7` and
a single list of both would never reach an enchant. So each name the client
counts from 1 carries its own mark, and `/wk skin probe` adds them up.

### The weapon enchant leads your buff row, and the square can be bigger

Reported from the game with a screenshot: the squares are too small and the
sharpening stone is nowhere.

**The enchant was left to the client and the client's row is hidden.** That was
the wrong end of the trade. A temporary weapon enchant sits at no aura index at
all, so `GetWeaponEnchantInfo` is the only call that knows about it, and hiding
`BuffFrame` took the last reading of it off the screen. Both hands now lead your
buff row, read through `Buffs/Upkeep.lua` because that file already counts the
returns rather than picking one of the three shapes the call has had. The square
borrows the weapon's own art, the way Blizzard's enchant button does, and
hovering it opens the item's tooltip, because the enchant is a line on the item.
A client with no such call adds nothing and says nothing.

**The size ceiling was a constant that stopped being true.** `/wk skin aura`
ran to 32, which was the block's height when the rows were written. The block is
`/wk skin height` and runs to 72, so the ceiling follows it: the rule was always
that a square should not be taller than the frame it hangs off, and now the rule
is what is written down instead of the number it came to that day.

**The flag reached the table and not the row.** `enchants` was on the spec in
`ROWS` and `Auras.Build` copies named fields onto the row it builds, so the row
never saw it and drew nothing. The harness caught it on the first run, which is
the whole argument for asserting a feature rather than looking at it.

### The aura rows go on both sides of the block and run outward

Both rows sat under the block and chained, debuffs then buffs. Asked for from
the game: buffs over the block and debuffs under it, and every row running
outward from the middle of the screen rather than in from the portrait.

**Nothing chains any more, and that is the point.** Each row anchors to the
block itself, buffs on its top edge and debuffs on its bottom. A target picking
up a raid's worth of bleeds moved the buff row before and now moves nothing:
the two rows cannot push each other about because neither one is holding the
other up.

**Every row starts on the gauge end.** That is the edge facing the other block,
which is the opposite corner to the portrait, and it comes off `spec.mirror`
the way everything else about the mirroring does. So your rows run right to
left and the target's run left to right, and the four of them read outward from
the corridor the two blocks are already mirrored about. `reverse` and `justify`
on the `ns.UI.Flow` node both flipped for it.

**A row grows away from the block.** `lineOrder` was already in `ns.UI.Flow`,
put there for the enemy bars' debuff row, and it is what puts line one against
the block on the row above it: the frame is sized for a full list and fills
from its bottom edge up. Nothing new was needed in the layout engine.

**The row's height stops changing on the tick.** It is set once, to what a full
list comes to. No row hangs off another one now, so a height that tracked the
count buys nothing, and on the row above the block it would cost that row every
square it has: those are placed against the frame's bottom edge, and that edge
is the one an anchor on the block's top holds still. `Height` and the
per-row line count go with it.

**Target of target is cleared by dropping past it rather than by hanging off
it.** It is parked under the target block on the portrait corner and the debuff
row now runs from the other corner, so an anchor between them would inset the
row by the difference between the two widths. `Perch` still says the frame is
there. What is taken off it is its height, converted into the block's units
because it is drawn at a scale of its own, and the row keeps hanging from the
block's own corner with that much more drop. Read on a change of head, not on
the tick, so it costs one comparison against nil while the target holds still.

### Your own buffs and debuffs, under your own block

The aura rows were built for the target only, on the argument that Blizzard
does not hang your buffs off `PlayerFrame` at all. That was the wrong half of
the job once the target became the player mirrored, and it was reported the
plain way: "I do not see them anchored to the character." The two blocks are
one HUD. What is on you belongs beside what is on the target, not in the corner
of the screen you have to look away to read.

**The player is one entry in `ROWS` and nothing else moved.**
`UnitFrames/Auras.lua` was already a table keyed by frame, so the player's two
rows are the same rows off the same settings, drawn by the same code and hidden
the same way. `UnitFrames/Skin.lua` is untouched: it already called `Build`,
`Place`, `Style` and `Update` for every frame it skins, and the player simply
started having rows to draw. Both differences come off the spec the file
already had. The player block is not mirrored, so its rows start on the corner
the portrait is on and run right. And nothing is ever parked under it, so its
debuff row hangs on the block itself while the target's hangs under target of
target.

**Two things go off the screen with the client's row.** Cancelling one of your
own buffs is a protected call, so a square drawn here cannot offer right click
to cancel. Getting that back means a secure button per square, which is its own
piece of work and is not worth starting until somebody misses it. The temporary
weapon enchant is the other, and it is the reason `TemporaryEnchantFrame` is
deliberately left alone: it sits at no aura index, so nothing here can find it,
and hiding it would take the only reading of the sharpening stone on your
weapon off the screen. `Buffs/Nag.lua` says when it is missing and says nothing
about how long the one you have has left.

**Each row asks the client for its own ceiling by name.** `MAX_TARGET_DEBUFFS`
for the target and `BUFF_MAX_DISPLAY` for you, out of a `max` field on the spec
rather than out of a branch on the filter that only knew about the target.
`Auras.CountCeiling` reads across every frame instead of off the target's, so a
row given a longer ceiling than the others cannot end up with a setting that
refuses to reach it.

**One harness check was finding the portrait square by luck.** Section 10 walks
a unit frame's children for one pinned to the block, and the two aura rows are
pinned to the block as well. On the target that never showed, because the rows
hang off target of target instead. On the player it came back with the debuff
row and failed on the spot. It now skips the children that carry a name, which
is the real difference between them: every frame this addon has to be findable
from a macro is a named global, and the portrait square is not one.

### The target block is the player block mirrored, and the gap setting is gone

`/wk skin gap` is retired. There is no number between the two blocks any more,
because the distance across was never a preference and pretending it was is
what made the pair look wrong.

**A fixed distance apart is not a mirror.** The link anchored the target block
120 pixels off the player block's far edge, which put the line the two mirrored
about wherever Edit Mode had last left the player. In game that is left of
centre and low, so the pair sat off to one side facing each other. Reported
from the game, and the specification was wrong rather than the code that
implemented it.

**The target's facing edge is the player's reflected in the middle of the
screen.** Reflecting a point about the centre moves it 2 * (centre - point),
read in screen units because that is the only space two frames on different
scales share, then divided back into the frame's own units because that is what
an anchor offset counts in. The corridor between the blocks is now twice the
player's distance from the centre, so you widen it by dragging the player
outward and you close it by dragging the player in. Drag the player across the
centre and the pair crosses, which is what a mirror does and is worth knowing
before it surprises you.

**Dragging the target still means something, and it means one thing now.** The
drop sets the level, which is how far the target's top edge sits below the
player's. The sideways half is measured and thrown away, and the re-anchor puts
the frame back on the mirror line, because opposite the player is the only place
it can go. `Landed` reads two edges instead of four for it.

**A pass that cannot measure writes nothing.** `Mirrored` comes back empty on a
pass where the client has not resolved the player block's position yet, which
happens once at login. There is nothing to fall back to now that the fixed
distance is gone, and that is the better answer. The target stays on the point
it arrived with and the next pass asks again, instead of jumping to an invented
distance and then jumping a second time. `/wk status` says the rest follows on
the next pass rather than blaming combat for it.

Three harness assertions changed with the specification rather than being
adjusted to fit it. What they assert is the mirror stated as the thing you can
see: the midpoint of the two facing edges is the middle of the screen, at three
UI scales. The stub parks the player right of centre on purpose, so a pair
anchored a fixed distance apart fails all three. A fourth asserts `skinGap` is
still absent from the settings, because a distance that quietly became a number
again would pass every other check while the mirror only held for whatever value
it happened to hold. The key is in `RETIRED`, so a saved variable written before
this is cleared rather than left to be found.

### The target's aura rows are the addon's now

Blizzard drew the target's buffs and debuffs and the skin worked around where
they landed. It draws them itself instead, and the machinery that did the
working around is deleted.

**The row could not be moved, which is why it had to be replaced.** Every icon
in the client's row is a child of a secure unit button, so an addon may anchor
one out of combat only, and the client re-anchors the head of each row on every
aura the target gains or loses. Anything placed there is back inside the gauge
one refresh into the first pull.

What the skin did instead was move the edge the client measures from. It read
the lift off an icon the client had already placed, fitted the target frame to
the block plus that lift, and let the client's own arithmetic drop the icons
under the block. It worked, and it cost four things: a number that only settled
on the first target carrying an aura, a `UNIT_AURA` handler waiting for that
moment, a frame that was not the same rectangle as the block, and a mouse region
inset to pull clicks off the strip underneath. All four are gone. All three
frames are the block exactly.

**One square, two rows.** `UI/Aura.lua` is one aura drawn: the cropped icon, a
hairline round it, the seconds left along the bottom, the stack count in the
corner, and who cast it said by draining the art rather than by adding a colour.
It came out of `UnitFrames/EnemyBars.lua` rather than being written beside it,
so the debuff row on a nameplate and the row under the target block are the same
code and cannot drift apart. The bars lost 39 lines and draw the same picture,
with one difference: the stack count is inset by one screen pixel now instead of
one unit, so at `bars zoom 2` it stops sitting two pixels in while the border
beside it stays at one.

It is deliberately not `UI/Ability.lua`. That file's whole vocabulary is ten
reasons a press does or does not land, and it hangs the countdown off
`status == "cooldown"` because below the global there is nothing to count. An
aura has no cost, no range and no stance, its timer is the thing you actually
read, and the six textures a button needs for its pushed, equipped and armed
states are six per square nobody would ever see.

**Yours go first.** The client's order is the order the auras landed in, so on
anything with a raid on it your Rend is somewhere behind a screen of other
people's bleeds and a row capped at twelve loses it. Sorting would allocate on a
ticker; two passes over the same list do not, and the answer is the same.

**`ns.UI.Flow` never runs on the ticker.** Every square is placed once at layout
for the longest the row is allowed to be, the tick shows a prefix of them and
moves none, and the only thing that changes is the row's own height, which is
what tells the row below where to sit. The gap between rows is folded into each
row's height, so a target with no debuffs puts the buff row against the block
rather than one gap below where the debuffs would have been.

**Hiding the client's row is a sweep, not a walk.** Those buttons are built on
demand, so it cannot be done once when the skin goes on, and walking all
forty-eight names every tick to find that out would be silly. They are built in
order, so the only one that can have appeared since the last look is the one
after the last one hidden: one global lookup per row per tick once the row has
settled. `ns.Strip` refuses on a protected region in combat and says so, so a
button the client builds mid fight is retried and lands when combat drops.

**Target of target is parked on exactly the corner the rows hang from.** `Perch`
tells them it is there and the first row hangs under it rather than through it.
That happens on the ticker rather than at layout, because the client shows and
hides that frame with the unit and a target with nothing targeted would
otherwise leave a hole the size of it. Writing it there is allowed in combat
where re-anchoring target of target itself is not, for the one reason that
matters: that frame is ours.

**Your own buffs stay where they are.** Blizzard does not hang them off
`PlayerFrame` at all. They are `BuffFrame`, a top level Edit Mode system carrying
thirty-two buffs, sixteen debuffs, three temporary weapon enchants and right
click to cancel, and none of the payoff above is on that side. What this addon
has to say about your own buffs is the nag row's, which reads
`GetWeaponEnchantInfo` as well as your auras and so can see the sharpening stone
that appears at no aura index.

`/wk skin auras on|off`, `/wk skin aura 20`, `/wk skin debuffs 12`,
`/wk skin buffs 8`. Turning the rows off leaves the target with no row at all,
which is the honest answer rather than an oversight: the frame is the block, so
handing the client's row back would hang it in the gauge. `/wk skin off` gives
it back, because that is what gives the frame its size back.

**Two gates moved in the same change.** `UnitFrames/Feature.lua` hit the 800
line limit, and the page came out into `UnitFrames/Panel.lua` rather than a
fourth entry on the length allow-list; the seam was already there, since nothing
in the page decides anything and nothing left in `Feature.lua` draws. That also
paid off the entry item 8 had added at 879, so the allow-list is back to three.
`UnitFrames/EnemyBars.lua` ratcheted from 2050 to 2011 and `UnitFrames/Skin.lua`
from 2012 to 1934.

### A breakdown of what this character actually does

One row per ability, kept between sessions: how much of your damage it is, how
often it lands, how often it crits, what it averages, what its best hit was and
what stopped it when it did not land. It is the question the meters cannot
answer, because a meter totals the pull you are in and forgets it when the next
one starts. This never forgets and never reports a rate.

**Counters, not history.** Every question it exists to answer is a ratio over
counters. Crit chance is crits over landed hits, miss chance is the miss table
over attempts, and what share of your damage is Thunder Clap is a sum over rows.
None of them needs the event that produced it kept, and keeping the events is
the one thing this could not afford. An evening of solo play is tens of
thousands of combat log lines, and the client writes saved variables by
serialising the whole table to Lua source at logout. So the table grows with the
number of abilities you use and never with the number of swings you take.

**There is no flush, so there is nothing to flush.** An addon cannot ask the
client to write saved variables; they are written at logout, at a reload and on
quitting, and the only way to force one in between is `ReloadUI`, which is why
Titan puts a confirmation box in front of changing a profile. So this does not
accumulate into a private table and copy it across at `PLAYER_LOGOUT`. It counts
straight into the table the client serialises, and there is no logout hook that
can be forgotten.

**Crit damage is kept apart from total damage**, and that is what makes both
averages come back out. The average normal hit is the damage that was not a crit
over the hits that were not crits; the average crit is the other half. A single
blended average of a 500 and a 900 is 700, which describes no hit the character
has ever landed, and it cannot be taken apart afterwards. Four counters instead
of two, and the harness asserts both halves.

**A miss keeps its type.** The client names ten outcomes and the table holds the
ones that happened to you. A dodge says you were in front of it and a parry says
something about the target, and one pooled "missed" number teaches neither.

**Rates are banded by the target's level against yours.** In this era level
difference drives miss and dodge hard, and a lifetime crit rate pooled across
grey trash and an elite is an average of two unrelated fights. There are four
bands and the fourth is the honest one: the combat log carries no level, so it
is only ever learned from a unit token, which means the mob was your target or
had a nameplate up. Anything you hit without ever seeing lands in "level not
seen" rather than being quietly counted as your own level, which is the answer
that would flatter every rate in the table.

**Stored by spell id, added up by name.** A name is localised and collides: the
eight ranks of Heroic Strike are eight ids and one word. Reading by id would
give eight thin rows nobody wants and storing by name would throw away the
ability to look at one rank alone. The pane says the one thing that does not
survive the roll up, which is that a rate pools across ranks correctly and an
average hit does not.

**Only what swings at something is listed.** Battle Shout, Charge and every
stance are counted like everything else and kept out of the table, because in a
ranking by damage they can only ever be a run of zeroes above the rows you
opened it to read. They stay in the store, since an ability that does nothing
today is one damage event away from being worth a row. An ability that has only
ever been dodged does get listed: no damage across four dodges is not the same
fact as no damage because the thing does none.

There is one ranking and no control for it. It ranked by casts and by landed
hits as well for a while, off three chips on the window, and both of those
answer a question this table does not ask. Ranked by press count Battle Shout
sits above Mortal Strike, which reads as a bug rather than as a view.

**Only your own hits.** `Meter/Meter.lua` reads the same event and counts
everybody, deliberately, because it is answering what the group did to this
pull. Counting the group here would grow the table by every stranger you have
ever been in a party with, and that is the one filter keeping it bounded.

The table opens from the meter. It lived on a settings page first, on the
argument that a month of play summed up is read between sessions rather than
during a pull and does not need a frame to place. That argument was about where
the numbers are kept; it said nothing about how you get to them, and the way you
got to them was six clicks into a settings tree. The meter is what you are
looking at when the question occurs to you, so a left click on the meter header
opens the table and a right click still swaps the meter between damage and
healing. Escape or the cross closes it, and there is no frame at all until the
first open and no ticker behind it ever.

`/wk breakdown open` opens the same window and `/wk breakdown` prints the
ranking to chat. Throwing the record away takes two presses or `reset yes`,
because a mistyped word should not be able to delete a month of counting.

### Loot and the combat log, as feeds you can scroll

Two columns of what just happened, newest at the top and older underneath.
A loot row is the item's icon, its name in its own quality colour and how many
dropped. A combat row is three columns: what happened, who the other party was,
and the number. Down the left edge of each row is a stripe, so a pull reads as a
ribbon before you read a word of it: quality for loot, and for combat which way
the blow went, white out, red in, green healed and grey missed.

**A combat row has to say who, and for a while it did not.** The rule was to
draw the spell where there was one and the other party's name where there was
not, which put "Overpower 321" and "Plains Creeper 26" on the screen in the same
shape, neither of them saying who was on the other end. So the name column is
now always what happened, a spell or the client's own word for a swing, and the
dim middle column is always who, reading "on Plains Creeper" for something you
did and "from Plains Creeper" for something done to you. The number column is a
fixed width, so a run of hits reads as a column rather than as a ragged edge.

A critical draws its number in gold **and** puts a mark after it, `871!`. Gold
alone was the whole signal, on the one row in the feed that exists to be
noticed, and a signal carried by hue alone is one a colourblind player does not
get. The same argument runs one level up in the stripe, which is why the middle
column carries the preposition rather than leaving the direction to the colour.

**Entering and leaving combat draw a band across the feed.** Without them a feed
is one unbroken column and the only thing separating this pull from the last one
is a gap in timestamps a row does not carry. A marker is a band the width of the
row with a word on it: no icon, no middle column, nothing an event can look
like, because a marker that could be read as a hit for nothing is worse than no
marker at all. The band at the end of a fight says how long it lasted, which is
a fact nothing else in the addon reports: the meters total a fight and reset on
the next one, and neither of them ever says how long you were in it.

A pair of markers with nothing between them is left standing rather than
swallowed. That pair is information too. It says you were in combat and nothing
that happened in it cleared the floor, which is exactly what somebody who has
set that floor too high is looking for.

`Feed:Mark` is a capability of the widget rather than something the combat feed
fakes with an ordinary row, because "one set of events ends and another begins"
is a thing any feed wants, and a marker built out of an ordinary row is one an
ordinary row can be mistaken for.

Both feeds ship wider than they did, 260 for loot and 320 for the combat log,
and the combat feed shows twelve rows rather than ten. Three columns need the
width, and a pull produces rows an order of magnitude faster than a corpse does:
at ten rows a fight scrolled off the bottom before you had read the top of it.
The width slider now runs 200 to 520 rather than 140 to 420, because 140 units
is not a row, it is four things clipped to two glyphs each.

**One widget, two feeds, and that was the point.** `UI/Feed.lua` knows about a
column of entries and nothing else: not where it sits, not whether it is
switched on, not what an item or a swing is. `Feeds/Stream.lua` is the frame one
of them sits in and the seven settings behind it, found by prefix so both
streams read the same six. What is left in `Feeds/Loot.lua` and
`Feeds/Combat.lua` is only the capture. A third feed is a file and a table.

**The rows do not move.** There is one frame per visible row, built once,
anchored once, and never anchored again. Arrivals go into a ring and scrolling
is an offset into it, so ten rows repaint whether the feed holds ten entries or
four hundred, and a scroll costs the same as a drop. `UI/Log.lua` already
refused to build a chat window out of `UI/Stack.lua` for this reason and the
constant here is worse: a stack would remeasure four hundred entries every time
a mob died. It also means there is no clipping to arrange and no ScrollFrame to
probe, because the rows exactly fill the space.

The ring reuses its tables, and the harness states that by identity rather than
by measuring it: the four hundred and first drop has to land in the table the
first one used. Nothing in either feed is on a ticker. They change when
something happens to you and when you scroll them, and never in between, which
is why a row carries no clock and the time of day lives in the tooltip.

**An arrival must not scroll the feed under you.** Scrolled back into history,
a drop pushes the list down under the offset rather than under your eyes. That
is the defect that would make the scrollback useless and it cannot be seen in a
screenshot: a feed that jumped and one that did not are the same picture taken
at different moments. It is gated.

**The loot sentences are built, not typed.** The client hands over the same
localised format strings it used, so `LOOT_ITEM_SELF_MULTIPLE` becomes a pattern
and a German client is read by German rules without the addon knowing a word of
German. Order in that table is its whole correctness: "You receive loot: %s."
matches the counted sentence as well, because the link is followed by "x8" and
`(.+)` will happily swallow it, so every counted form is tried before its
uncounted twin. The harness carries both forms of each for exactly that, and
deliberately leaves two of the twelve out, because a client that carries some
and not others is a real state and `/wk status` has to say so rather than
quietly capturing two thirds of what drops.

The combat feed is about you and nothing else. The log names every creature in
range, including the other party fighting the pack next door, and a feed that
drew all of it would be the client's own combat log tab, which is the thing
nobody reads. It is not the meters either: they total a fight, this is a list of
moments, and the two share no state.

### The addon has its own tooltip now

Every hover in the addon went to `GameTooltip` until this release, which meant a
parchment scroll with a gold border rising out of an interface that has neither
anywhere else. `UI/Tooltip.lua` is the addon's own: the theme's palette, the
shared Arial Narrow, the pixel grid, one frame with a pool of lines refilled on
every open.

**It is the size of the thing it describes.** One frame serves every hover in
the addon, so it has one zoom and forty possible owners, and it took that zoom
from `UI.WindowZoom`, which is the settings window's. With the UI size slider
above 1 that meant hovering a feed row opened a box six hundred screen pixels
across to explain a row thirty pixels tall. It now asks the owner what zoom the
owner is drawn at, through the new `UI.ZoomOf`, and moves itself onto that. The
padding, the line gap, the rule spacing and the wrap width all came in with it:
a tooltip is a label that follows the cursor and is read in the half second
before you move on, and every unit of air in it is a unit of the game it is
covering.

**A caller hands over a table, not a run of calls.** `Tooltip.Show(owner, data)`
takes a title, a colour, an optional item link, and a list of lines: a plain
sentence, a label and its value pushed to opposite edges, a quiet blue hint that
names a switch, a spacer. The five imperative writers it published before are
locals now. Five ways to write a line is five things a caller can do in the
wrong order, and the one that actually mattered, whether a title had been
written yet, was bookkeeping every caller had to get right on its own. What a
hover says is a value the caller returns, which is also what let the feed guard
the reopen: with the cursor resting on a feed, a tooltip was being refilled once
per combat log event, and it is now refilled only when the entry under it moves.

An item's text is the client's and there is no API that hands it over as data,
so the supported way to read it is to point a tooltip of your own at the link
and read back the font strings it filled in. That is what a hovered loot row
does, and it is why the tooltip carries a scanner. Where the client refuses the
frame, or hands over nothing, the row falls back to its name and the facts the
feed knows, and `/wk feed` says which of the three happened rather than leaving
you to guess from a thin box.

`Buffs/Nag.lua` was the file that had invented this shape, three lines of a
title, what is wrong and the name of the switch that silences it, and it is now
the first caller rather than the only implementation. Its `PassCamera` came with
it and is `ns.UI.PassCamera`: a mouse enabled frame swallows every button that
lands on it, including the right drag that turns the camera, and everything in
this addon you can hover sits exactly where that drag starts. Written once for
four nag squares, it is the same trap at forty times the area on a feed, which
is what moved it into the library. Where the client has no
`SetPassThroughButtons` the price is real and both the panel and the feeds' own
setting say so out loud.

The blue instruction colour that was one of two literals in `Buffs/Nag.lua` is
`UI.Color.hint` now. Its detail line takes the theme's reading colour rather
than the near-identical grey it had, which is the point of having a palette.

### The enemy bars say when to Pummel again

`grep UNIT_SPELLCAST` returned nothing across the addon. The bars replace the
nameplate, so replacing it cost the one thing on a plate that says a cast is
running and there are two seconds left to stop it. Every enemy bar carries a
cast row now: the spell's name on the left, the seconds left on the right, a
fill that runs left to right for a cast and drains right to left for a channel.

Violet, and deliberately nothing else on the bar. The gauge above it carries
threat, which is the green through red scale, and the tag beside it carries the
XP scale, which is those same five colours meaning something else. A cast bar in
any of them would read as a third opinion about the mob's health. A cast the
client flags as uninterruptible draws in the idle slate instead: there is
nothing for you to do and the colour says so.

**The row is reserved and it draws nothing.** It is kept clear whether or not
the mob is casting. A row that appeared would shove the health bar upwards at
the exact moment the thing you are watching starts happening, and a bar that
moves when the fight gets interesting is a bar you have to find again. Empty, it
hides its box, so there is no fill, no edge and no backdrop and what is left is
air. The three pixel threat bar that used to sit above the gauge is the version
of this that got deleted for drawing its backdrop while nothing was pulling.

**The fill is drawn on every frame.** One `OnUpdate` now runs two bodies:
`EnemyBars.Sweep` on every frame, which advances the fills and nothing else, and
`EnemyBars.Update` behind the fifth of a second accumulator it always had. This
is the swing timer's argument and it took two repairs to learn there: a readout
a fifth of a second stale is one nobody can fault, and a moving edge drawn at
five hertz is a moving edge that steps. The harness holds the cast fill to the
same three statements the swing bar is held to, at 60 fps and at 144, and none
of them is a tolerance.

The accumulator subtracts the interval now instead of zeroing. Zeroing throws
away however far past the interval the frame landed, which turns a 5 Hz tick
into every fourth frame at 60 and every twelfth at 144, rates of 4.6 and 4.8.
That was the first of the two throttles on the swing bar, and it was the same
line.

**Nothing is kept between frames.** `ns.CastingInfo` is a live question with a
live answer, so the tick asks it once per bar and `UnitFrames/Cast.lua` draws
what came back. A model keyed by unit token would have to survive nameplate
tokens being recycled the moment a mob dies, and that is a class of stale bar
that cannot happen if there is no model.

The `UNIT_SPELLCAST_*` events are registered as well, and they buy exactly one
thing: the fifth of a second between a cast starting and the next tick, which on
a one and a half second window is an eighth of the reason to look. They are not
what the feature rests on. A client that never fires one of them for a nameplate
unit draws the same bar a fifth of a second later, which is the lesson the
debuff row paid for. `/wk status` says how many have ever reached a bar.

**Two calls, one answer, and a flag that is counted rather than assumed.**
`UnitCastingInfo` counts up and `UnitChannelInfo` counts down, and both open the
same six returns and then differ by one slot: a cast carries a castID and a
channel does not, so `notInterruptible` is the eighth return of one and the
seventh of the other. Neither slot is trusted. What comes back is type checked,
and `ns.CastImmuneKnown` reports what has been seen rather than what is assumed:
nil before the first cast is read, false once one has been read without the
flag, true once one has carried it.

That both calls answer for a unit that is not you is the one inference this rests
on, and it is a good one. Vanilla answered only for the player, which is why
every Classic cast bar was built on a combat log estimator. Details ships that
estimator and its framework used to route both calls through it on Era; the
branch is switched off in its own source under the comment "disable this for
now, as it appears to be working now through API changes". An addon deleting its
own workaround is a stronger proof than an addon calling the API.

**Unlocking previews it.** A mob that casts is not something you can arrange, so
"unlock the frames and look", which is how everything else in this addon gets
placed and sized, had nothing to look at: the row could not be judged until a
caster pulled you. Unlocked, every bar draws its own cast instead of asking the
client, five seconds around, a cast filling and then a channel draining, through
the same guarded writes the real thing uses. `Buffs/Nag.lua` had the same
problem with an equally empty row and this is its answer. You still need a bar
to look at, which means a hostile target or a nameplate up.

`replace` style now hides Blizzard's plate cast bar, which it deliberately did
not before. Two cast bars for one cast, in two places on the screen, is worse
than either alone. `bars cast off` takes our row away and gives Blizzard's back
in the same breath, so it is a real off switch rather than a way to stop seeing
casts.

`Swing/Slam.lua` reads the cast it measures through the same shim now. It had
its own positional read of `UnitCastingInfo`, which is exactly the thing Core
exists to do once.

### A region hidden by a setting was not always given back

Found on the way in, because the cast bar would have had the identical bug the
first time anyone typed `bars cast off`.

`PlateRegions` decided which of Blizzard's nameplate regions to hide by reading
the settings, and the restore walk called the same function. Hide the raid icon
with `bars marker` on, switch the setting off, and the walk that was meant to
give it back no longer had it on the list. The icon stayed hidden for the rest
of the session, nothing was written anywhere, and the only symptom was a mob
with no raid marker at all: not ours, because the setting is off, and not
Blizzard's, because we are still standing on it.

The strip list may shrink with a setting. The restore list may not. It is
`PlateRegions(plate, every)` now, restore passes `every`, and `ns.Unstrip` is a
no-op on a region that was never taken, so asking for all of them costs a table
lookup.

### Bar 1 takes a dropped spell, and this time the client said why

Two fixes went in for this and neither worked, because both were written by
reading the code. Bar 1 hovered, named what was on it, highlighted an empty
square and pushed under a click, and a spell dragged onto it would not leave the
cursor. Every other bar took the same spell.

So this release stopped guessing and asked. `/wk actionbars trace` prints what
the client says is under the cursor, whenever that changes, with the frame's
name, its strata, its level and the action slot it presses if it has one. It
answered in one line:

    trace: under the cursor: MainActionBar (TOOLTIP 50), holding spell 21/spell

`MainActionBar` is mouse enabled in **TOOLTIP**, which is the top strata there
is. The previous fix stood the cloned bars at frame level 120 to beat that
frame's level of 50, and a level cannot win an argument with a strata: our bar
sat at MEDIUM 122 and lost every hit test on that corner of the screen anyway.
The same trace never once named a bar 1 square while it named squares on the
other four, which is the same fact from the other side.

That frame cannot be hidden, because the micro menu and the bag bar hang off the
same corner, and it cannot be out-stacked, because nothing stacks above TOOLTIP
except tooltips. So the mouse comes off it. It has no click handler and no drag
handler; it exists to stop a press reaching the world, and the bar of ours
standing over it does that job now. `Buttons/Blizzard.lua` walks up from each
Blizzard button it hides, silences any ancestor that actually takes the mouse,
and hands every one of them back when the clone is turned off, which is the
same shape the button hiding already had. Frames declared with no `enableMouse`,
which is all four multi-bars, are never touched. `EnableMouse` is per frame and
never inherited, so the micro menu and the bag bar keep theirs.

**The trace stays.** It is off unless asked for, read only, and it prints three
things: the frame under the cursor as it changes, every drag gesture a square
gets with the cursor either side of it, and every click, through `PostClick`,
because a spell is dropped by clicking as often as by dragging. Its first live
run printed every gesture and never named a frame, because this client has no
`GetMouseFocus`; both that and the `GetMouseFoci` that replaced it are asked
for now, and the trace says which one answered as it switches on.

The drop path also stops being silent with the trace off. A drop that reaches a
square and moves nothing says which action slot it was aimed at, once per reason
per session, and a square pointing at no slot says that instead. The old latch
fired on the first refusal and swallowed every other reason for the rest of the
session, which was the same silence one layer down; it is keyed by the line now.

`scripts/harness.lua` carries `MainActionBar` in TOOLTIP with bar 1's twelve
buttons parented to it, and fails if the clone leaves it taking the mouse, if it
silences a holder that never took one, or if the off switch leaves anything
deaf. The old fixture said MEDIUM and both failed fixes passed it.

### A nag you cannot silence is a nag you learn to ignore

The report was one sentence: "I do not have a weapon enchant, and I know that's
bad, but I do not need a permanent nag for something I cannot fix." The row had
one master switch and no way to stop watching one thing, so a character with no
sharpening stones got the main hand square every time they left combat, forever.

That is worse than a wasted square. The row is one row. Once you have learned to
look past the stone you have learned to look past Battle Shout, the food and
Blood Fury sitting on your keyboard, and the whole feature is gone. One
unfixable entry costs you the other three.

So every entry has its own switch: `buffs weapon off`, `buffs offhand off`,
`buffs shout off`, `buffs food off`, and a tick box each under a new **What it
watches** heading on the panel. The words name the thing rather than the slot,
with one exception. `offhand` is a hand, because for that entry the hand is the
thing: the only rule on it is that a shield in that hand is never nagged about
and a weapon in it is.

**Off means off the list, not hidden.** A switched-off entry never reaches the
list `Upkeep.Rebuild` builds, so the tick never asks about it, the row never
draws it, and `Describe` never counts it. Drawing it at alpha zero would have
cost the same four calls a tick for a square nobody can use, and testing it on
the tick and dropping the answer is the same work with none of the answer. The
harness asserts the entry is absent from the walked list rather than that the
square is hidden, which is what makes both cheap versions fail rather than pass.

**Per character, and this is the one scope decision in the addon taken on
editorial grounds.** Everything else on the buffs page is a preference about the
row itself, and how big the row is is the same answer on every character you
own. Whether a bare weapon is worth a square is a fact about the character: a
raiding main carries a stack of stones and wants the square, a bank alt has
never bought one and never will. Account wide would have taken the raider's
answer and forced it on the alt, which is the complaint that produced the
setting, repeated one level up. It is `ns.dbc.buffWatch`, and absent means
watched, so a fresh character carries an empty table and an entry added in a
later release arrives switched on.

**What you switched off is visible.** `/wk status` and the panel both name it,
so the status reads `3 tracked, 1 missing; bare weapon switched off`. A nag you
turned off six weeks ago and can find no trace of is the same defect in a new
place: the row is quiet and you no longer know why.

**The captions say what is wrong instead of which hand.** `main hand` became
`bare weapon` and `off hand` became `bare off hand`. The old ones named the slot
and left you to work out what about it, which on a bare icon over your character
is no help at all. The racial half was already speaking correctly with `press
Blood Fury`.

**Hovering a square says the rest.** Two words of caption is the right length
for something you read at a glance mid-raid and it is not enough the first time
you see it. The tooltip carries what the caption could not: that a bare weapon
means no stone, no oil and no imbue on the weapon you swing; that a bare off
hand can only be a real weapon, because a shield is never nagged about; that
Battle Shout has lapsed and any rank counts; and for the racial, which racial it
is and how many seconds it has been sitting off cooldown. That last figure is
the row's own record. A spell that is ready reports a duration of zero and no
end time, so nothing in the client can answer it, and `Nag.Update` stamps the
moment the racial half came up.

The last line of every tooltip names the switch that silences that square.
Turning one off from the square you are tired of, rather than reading a settings
page to find which tick box it is, is most of what the switch is worth.

`Buttons/Square.lua` owns this shape for the action bars and the row follows it
rather than inventing a second way: `OnEnter` and `OnLeave`, anchored to the
square, refused outright when there is nothing to say. It is not shared code,
because every step in that file is about an action slot read off a secure
button's attribute and handed to the client to describe.

**One real cost, and it is worth naming rather than discovering.** A square
takes the mouse only while the row is locked and drawn, and this row sits above
the middle of the screen, which is where a right button drag to turn the camera
starts. A mouse enabled frame swallows every button that lands on it. The right
and middle buttons are handed back through `SetPassThroughButtons`, which
arrived in 1.14.4 and 10.0 and is probed rather than trusted, so on a client
without it a right drag begun exactly on one of these squares does not turn the
camera: at most four squares of 54 pixels, only while something is missing, and
only out of combat. It is in the untested list. Unlocked, the squares release
the mouse entirely, because unlocked the row is a thing you drag and a square on
top would eat the button first.

**The spells you add yourself have no switch, and remove is why.** The four that
ship cannot be taken off the row, so a switch is the only way to stop one. A
spell you added is one press from gone, and gone is the better answer: it hands
the slot back, and a flask you have stopped keeping up is not something you want
listed in a quiet state. A switch there would turn six slots into twelve states
with nothing on screen to tell them apart.

The assertions found one bug while they were being written.
`ns.dbc.buffWatch[key] = on and nil or false` is the short way to write the
setter and it is wrong in Lua: `and nil` is falsy, so the `or` takes over and
every call writes `false`. Switching an entry back on left it off. It is a
branch now, with the reason on the line.

### The swing bar still stepped, because there were two throttles on one edge

The last repair deleted a 20 Hz ticker with a broken accumulator, which was a
real bug and a real fix. The bar still stepped in game. The reason is that the
rounding to whole pixels was a second throttle sitting behind the first, and
finding the first is what hid it.

A fill snapped to a whole pixel can only change value as many times as the bar
has pixels. At the shipped 180 pixels across a 3.4 second swing that is 53 times
a second and no oftener, whatever rate the tick runs at. So the bar stood still
on 7 of the 60 frames a 60 Hz screen draws and on 91 of the 144 a fast one
draws, and every move it did make was a whole design unit, which is three screen
pixels at `swing zoom 3`. Deleting the ticker raised the drawn rate from 20 to
53 and changed nothing else.

`DrawHand` now writes the fill as a fraction of a pixel, on every frame, with no
comparison in front of it. The quantisation is gone and so is the guard it
doubled as. That is one line of arithmetic and five fewer lines of code.

**This is a second pixel rule, not an exception to the first.** The addon has a
hard rule that every edge lands on a whole pixel, enforced across 6,836 offsets,
and it exists so borders and art are sharp. It was written when every edge in
this addon was static and for that codebase it was the whole truth. A moving
fill wants the opposite thing: what the eye reads on a moving edge is velocity,
and velocity lives in where the edge sits between two pixels as much as in which
pixel it is on. Round it and you have destroyed the only thing being looked at
to buy a sharpness that cannot be seen on something in motion.

So there are two named rules now rather than one rule and a hole beside it. A
static edge lands on a whole pixel. A moving fill is not quantised. Both are
written out under the pixel grid in the README, both cover a category rather
than a file, and both are gated: the anchor sweep keeps walking every static
offset, and the swing section now asserts the positive form of the second rule,
that the fill really does land off a whole pixel on nearly every frame. Put a
round back around the fill and that fails. The Slam band and its mark move only
when your weapon speed does, a few times a fight, so they are static edges and
they stay on whole pixels.

**The old smoothness assertions were the wrong statements.** They said the fill
never jumps more than one pixel between two frames and that it visits all 180
positions, and both passed against a bar that visibly stepped, because a
quantised fill satisfies them exactly. No assertion in this repo can prove that
a bar looks smooth: smooth is a property of a screen and an eye and the harness
has neither. What it can prove is the property that leaves the client nothing to
be blamed for, so the fill is driven across a whole swing at 60 fps and again at
144, and three things have to hold on every frame with no tolerance allowed. The
drawn position equals elapsed over duration times the width, exactly. The value
changes on every frame, with no frame repeating the one before it. And every
step is the same size as every other, which is what constant velocity means.
Against the rounded code those read `the fill drew the same position twice on
309 of 489 frames` and `the widest step was 1.000000 px more than the narrowest`.

**What the unguarded write costs was measured, not assumed.** The swing tick
allocated 0.03 KB per fifty ticks rounded and guarded, and allocates 0.03 KB per
fifty ticks written every frame. The gate stays at 0.05. It is the addon's only
`-- unguarded:` exemption and the reason is on the line.

### The addon reads your own auras now, and says what you forgot

`grep UnitBuff` across `src/` used to find nothing. A sharpening stone that wore
off forty minutes ago costs more damage over a raid than any single rotational
mistake, and Battle Shout falling off says nothing at all.

`Buffs/` is a row of squares over your character, and it is not there when
nothing is wrong. That is the design decision. A row that is always up with the
missing ones lit is furniture, and you stop seeing furniture in about a week,
which is exactly long enough to convince yourself the addon is watching for you.
A row that exists only when something is wrong carries its whole message in
existing. The cost is a frame you cannot find to drag, so unlocking shows every
square it watches at three quarters alpha, which is the trade the meters already
make when they draw an outline round an empty pane.

**Two halves, taking turns rather than sharing one row.** Out of combat it is
what is missing: no stone on either hand, no Battle Shout, no food. In combat it
is the racial you own and have not pressed. They can never both be on screen,
which is why one row answers two questions.

That split is not a layout convenience. You fix a missing buff out of combat
because out of combat is when you can fix it, and shouting about a lapsed stone
mid pull is telling you about a thing you cannot do. Blood Fury is the opposite.
It is not a buff you keep up; it is two minutes of attack power sitting on a key,
and the only moment worth saying anything is the moment you are swinging at
something with it off cooldown.

**The weapon enchants are the reason the feature exists and are the only entry
that is not an aura.** A temporary enchant does not appear in an aura scan at any
index. `GetWeaponEnchantInfo` is the only thing in the client that knows, and
that call has had three shapes: six values at three per hand, eight once 6.0 put
the enchant's own id in after the charges, and twelve once Cataclysm added a
ranged hand. Nothing installed here settles which one 2.5.6 and 1.15.9 answer
with. So the stride is counted with `select("#", ...)` rather than read
positionally on a guess: at a guessed three against a client that answers eight,
the main hand's enchant id lands where the off hand's "has an enchant" belongs,
and a number is truthy, so the off hand would read as enchanted forever and never
say why. The harness drives both shapes and reads the off hand in both.

**A shield is never nagged about**, and that is the client's own
`OffhandHasWeapon` rather than a reading of the slot. A shield, a
held-in-off-hand item and an empty hand all answer no to it, and every one of the
three is a state a warrior is in on purpose.

**Auras are matched by name and scanned on an event, never on the tick.** Battle
Shout has eight ranks and the aura carries whichever one was shouted, so the ids
in the source exist only to ask this client what it calls the spell in the
language it is running in. `UNIT_AURA` fires for every buff you gain and every one
you lose, so the walk runs from the event and the tick reads a field. On a client
carrying `C_UnitAuras` that walk would also build a table per aura, which is
allocation on a ticker.

**Flasks and elixirs are a setting rather than a table.** These clients will not
say that an aura came from an elixir. There is no category on an aura and no call
that maps one back to the item, so the built-in version is about forty hand
written spell ids that cannot be checked from outside the game, go stale on the
next patch, and are wrong in a way nothing reports. `/wk buffs add <id>` takes six
of your own, the same shape the debuff row on the enemy bars already has.

**Only the racials that are damage are nagged about.** Blood Fury on an orc and
Berserking on a troll: both are throughput, both come back inside three minutes,
and forgetting one across a boss fight is free damage thrown away. Every other
racial a warrior can have is listed with the nag off so the status line and the
panel can name yours and say why it is quiet. Stoneform is spent when something
bleeds you and War Stomp when something needs stunning, and a row that shouted
about either every fight would teach you to ignore the row, which would cost you
Blood Fury as well.

The ids come from Wowhead's TBC Classic database and each was checked against the
cooldown its page states. Blood Fury has a second proof and it is the one that
matters: 20572 sits in this install's own Details saved variables as a buff with
uptime, recorded off a live 2.5.6 session. The race is `UnitRace`'s second
return, which is the token and is the same string in every locale, and it is read
every time rather than cached for the reason `ns.IsWarrior` reads the class every
time.

**The racial square breathes, and there is no sound.** Its alpha runs between a
floor and full over 1.6 seconds, which at the row's ten hertz is sixteen steps
and reads as a pulse rather than a strobe. It is on by default, because a nag you
can ignore is not what was asked for, and `/wk buffs pulse off` makes it a still
square. A sound would be a new kind of thing in this addon and is not worth it: a
chime in a raid competes with the sounds you are already listening for, it fires
whether or not you are looking at the screen, and a racial coming off cooldown is
worth noticing within a few seconds rather than immediately. The alpha is
quantised to twentieths so a tick that would draw the same value writes nothing.

Two states silence the missing-buff half and neither touches the racial half.
Dead, because nagging a corpse about its sharpening stone is noise, and that one
is not a setting. Resting, because an inn is where you have not put a stone on
yet on purpose and the row would be up through an hour at the auction house; that
one is `/wk buffs resting` for anyone who buffs in the bank.

**Not gated on warrior.** A lapsed stone costs a hunter's melee weapon exactly
what it costs a warrior's, and a troll rogue forgets Berserking the same way.
Battle Shout is the one entry that asks `ns.IsWarrior`, inside `Upkeep.Rebuild`,
and the hunter harness run asserts it is not on the list.

The long personal cooldowns are deliberately absent. Death Wish and Recklessness
are timed by hand on purpose and are their own piece of work.

### Overpower is a reaction, and the bars say so now

Overpower was drawn ready from the first pull to the last. It is pressable for
about five seconds after your target dodges you and not one moment else, which
makes it the one square on a warrior's bar whose whole point is that it is
usually dark. It was the brightest thing on the row.

The client is the reason and it is worth stating exactly, because nothing in the
code read wrong. `IsUsableAction` answers yes for Overpower in Battle Stance
whether or not anything has dodged you. It is not confused and it is not
answering about rage: the window lives on the server and the client is never
told, so there is no aura to scan, no cooldown to read, no event when it opens
and none when it shuts. Every rung of the ladder above that call was correct and
the square was still a lie.

The combat log is the only place the fact appears, so `Buttons/Reaction.lua`
reads it, the same event `Meter/Meter.lua` and `Swing/Swing.lua` already read and
the same way. A dodge of yours opens Overpower. A block, dodge or parry of yours
opens Revenge, which is the identical mechanism seen from the other end and is
in the same file for that reason: two copies of one five second clock is how the
two drift, and the drift would be silent because each would be right most of the
time. Pressing the ability shuts its own window, and leaving combat shuts both.

A block is read in two shapes, not one. A block that stops the whole hit arrives
as a miss; a block that stops part of it arrives as a landed hit carrying a
blocked amount, and on a tank that is the common one. A parser that took only
the tidy shape would leave Revenge dark through most of the fight it was open
in.

**The window is five seconds and that number is a decision.** Every
player-facing source says five, and both abilities carry a five second cooldown,
so a warrior pressing on every window presses on the cooldown. The MaNGOS and
TrinityCore server cores both hold `REACTIVE_TIMER_START` at four. Five wins
because the two errors do not cost the same: a second long says pressable when
it is not and costs a glance, a second short greys a free five rage attack that
is still sitting there and costs the attack. `/wk status` prints the seconds left
on each window so the figure can be checked against the live client, and the
README lists it under what has never been measured.

**A new reason, and no new colour.** `reaction` joins the vocabulary in
`UI/Ability.lua` and takes the look every unpressable square takes. A shut
window is not a state you can act on: you cannot walk out of it and you cannot
wait it out on purpose, so there is nothing for a colour to tell you to do. What
says the window opened is the square leaving that look, which on a bar is a jump
from drained grey to full colour and is the biggest change any square in the row
can make.

**The rung sits above the usable split**, which is the ladder's own rule that
what cannot be fixed at all comes first. That ordering also quiets the square
that used to shout for nothing: Overpower on a bar in Defensive Stance drew
orange "swap" all fight, telling you to swap into a stance where the press still
would not land. Now the orange turns up only while the window is open, where
swapping really does let you press it.

Stances needed no new code. Overpower is Battle Stance only and Revenge is
Defensive Stance only, and the client already refuses both in the wrong stance
in exactly the shape the ladder splits `cost` from `stance` on.

Warrior only, decided once at login, so on another class nothing is registered
and no combat log line is read. Only a plain spell is recognised, matched by
asking the client its own name for the two abilities and comparing that against
its name for whatever is in the slot: locale-proof, rank-proof, and two spell IDs
in the source rather than a rank list that goes stale at the next trainer visit.
An Overpower wrapped in a macro keeps the old behaviour, because the client will
not say what a `/cast` line resolves to.

### The swing bar jumped, and the Slam mark wandered

Both halves of the report were true and neither was arithmetic. Every assertion
the feature shipped with passed the whole time.

**The bar jumped because 20 Hz is an animation rate, not a refresh rate.** Every
other ticker in the addon updates a readout, where fifty milliseconds of staleness
is invisible. The swing bar is a moving edge. At the shipped width the fill
crosses 53 pixels a second, so a draw every fifty milliseconds moved it about
three pixels at a time, and three pixels is a step you can see. The accumulator
made it worse by resetting to zero instead of subtracting the interval, so on a
60 fps client it fired every fourth frame rather than every third and the real
rate was 15 Hz.

So the bar draws on every frame and there is no accumulator left to be wrong.
That costs nothing, because the pixel quantisation is the guard: the fill is a
whole number compared against the whole number already on the bar, so a frame
that would draw the same pixel writes nothing. Inside a swing that is 53 writes a
second, outside one it is none, and the churn measurement did not move.

The harness now drives a whole swing one 60 fps frame at a time and asserts that
the fill never jumps more than a pixel between two frames and that it visits all
180 positions. Against the shipped code those read `the fill jumped 3 pixels in
one frame` and `the fill took 69 positions across a 180 pixel swing`.

**The mark wandered because the cast time under it was re-measured on every
cast.** `UNIT_SPELLCAST_START` was read every time and the number it gave was
drawn straight away, so the mark moved a pixel or twenty depending on what the
server declared and on which cast the client happened to be describing. That is
the player's own words: it moved depending on when they clicked the spell.

Haste does not touch Slam's cast time on either of these clients. Warcraft
wiki's patch history dates that to Cataclysm 4.0.1, "Slam can now be cast while
moving, and haste now reduces the cast time". Before that patch the cast is 1.5
seconds less the talent and nothing else moves it, which makes it a constant per
character and makes a second reading of it worthless. So the first Slam of a
session is measured and every one after it is ignored, and a talent point is
what drops the held number. The reading is snapped to a twentieth of a second,
because every value the real cast can take is a multiple of a tenth and the
milliseconds under that are the server's rounding. A reading that snaps to zero
is refused, since zero is truthy in Lua and would have won over the estimate for
the session and then reported the character has no Slam. A reading longer than
the spell's own cast time is refused as some other cast.

What is still allowed to move the mark is your weapon speed, and it has to be:
the press is the moment with a cast time left to run, and a shorter swing spends
a bigger share of itself on the same cast, so Flurry walks the band back down
the bar rather than up it. That is asserted as the invariant rather than as a
percentage, at three weapon speeds and across a proc that lands mid swing.

`ns.Swing.Duration(hand)` is new and is what the band divides by now. It is the
swing being drawn rather than what `UnitAttackSpeed` says this instant. The two
are the same number today, and asking for the first is what stops the mark and
the fill from being two answers that agree by luck.

Three smaller repairs in the same files. `unit` was read once at login and used
by every layout pass after it, so on a client with no `SetIgnoreParentScale` a
monitor swap sized the bars off the old screen height. The band's guard compared
its two edges and not the line down the middle, so two windows a hair apart drew
the right band with a stale line in it. And a bar built before its layout ran
seeded its scale at one pixel, which draws a whole swing in two positions; it
now seeds at nothing and draws an empty bar until the layout gives it a width.

The performance tab's swing row said 20 Hz. It says "every frame" and costs the
row against 60 of them, which is the budget the rest of that tab already
measures against.

### A chat window, and a tab for the people you play with

The complaint was that the chat interface is fiddly and not worth reading, and
both halves of that are true for the same reason. Blizzard's window is one
column carrying two different things: people talking, and the game reporting
loot, experience, faction, reputation, skill-ups, errors and every addon's
output. The conversation is a few lines an hour and the reporting is a few lines
a second, so the half you would answer is the half that scrolls away.

So the addon draws the conversation and leaves the reporting where it is.

`Chat/Window.lua` is three tabs. People is anyone on your list, in any channel,
plus the whispers you send them. Chat is every person talking. Whispers is
whispers. That is the whole design, and the people tab is the reason the part
exists: a wife in party chat and a son whispering from two zones away land in
the same place, and neither of them goes past behind an argument about loot.

One tab for all of them, not a tab per person. A tab per person is a row of
stubs you have to read the labels of, and it splits one conversation between
three people into three windows. The question you actually have is whether
anybody you care about has said anything, and that is one question with one
answer. The tab is not drawn at all until there is a name on the list, which is
what makes it turn up on its own when you add the first one.

A name is what the list holds, matched with the realm suffix off and the case
flattened, so `Aria`, `aria` and `Aria-Firemaw` are one person. A GUID would be
exact and there is nothing to type into a settings panel to get one, and it is
per character, so a son who rerolls would be a stranger again. `/wk people
group` puts everyone you are grouped with on the list in one press, which is the
only reason filling it in is bearable: three names typed by hand, spelled right,
is the chore this addon exists to remove.

**Blizzard's window is not hidden and nothing of it is unregistered.** That is
the decision with the longest argument behind it. Hiding it and mirroring
`AddMessage` into a fourth tab is what a chat replacement usually does, and it
cannot be made correct here: the lines arriving at `AddMessage` include the ones
Blizzard's own handler just built from the events this addon already drew, and
there is no supported way to tell those from an addon's `print`. Every way of
guessing is a heuristic on formatted text. So the conversation is claimed and
nothing else is touched, Blizzard's window keeps everything this one does not
draw, and you shrink it into a corner yourself.

The claim is `ChatFrame_AddMessageEventFilter`, which is FrameXML's own
extension point for exactly this. One tick box puts the conversation back in
Blizzard's window on the next line, with no reload and no frame handed back,
which is the same contract the artwork strip and the minimap corral hold.

The capture is a registration of our own rather than a hook on Blizzard's
frames, and those are two mechanisms doing two jobs rather than one job twice.
Which messages a Blizzard chat frame receives is a per character setting the
player owns, so a guild tab switched off in the client's own chat settings is a
guild message this window would never see if it listened through that frame.

The numbered channels are a setting and it ships off. General and Trade are most
of the volume in a city and none of the conversation.

### A log widget, and why it is not built out of the stack

`UI/Log.lua` is the new piece of the widget library: a column of lines that
grows from the bottom, wraps, caps itself at five hundred and scrolls. Each tab
holds one.

It is not built out of `UI/Stack.lua` and `UI/Scroll.lua`, which is worth
writing down because everything else in the interface is. The stack asks every
row how tall it is and lays the column out again from the top, which is right
for a settings page and wrong here: a line arrives, the whole column reflows,
and in a raid that is several hundred measured font strings a second. Worse, a
font string on a hidden frame does not report its wrapped height on this client,
which is why the panel reflows a section only after showing it, and a chat tab
you are not looking at is hidden all evening.

So the log is the client's own `ScrollingMessageFrame`, which is a frame type
rather than a template, probed with `pcall` exactly as `UI/Scroll.lua` probes
the Slider and the ScrollFrame. What the client contributes is the buffer and
the wrap. The font is the addon's shared Arial Narrow, the bar beside it is
`UI.ScrollBar`, lifted out of the scroll view so both draw the same bar, and the
colours are the theme's.

Two things it does that Blizzard's does not. Nothing fades: a line stays until
it falls off the end of the buffer, because a window you are meant to read is
not a river you glance at. And the insert mode is written and read back, because
the two clients disagree about which spelling of that token they accept and a
refused write is silent, which would put the newest line at the top and say
nothing about it.

### A voice channel, joined when you log in

Pick your party or raid channel in `/wk`, or a community's where this client has
communities, and the addon activates it at login and again the moment the
channel appears, which for a party channel is when you group up.

The picker offers what the client's own Chat Channels window draws a voice
button on: your party or raid, and every stream of every community and guild you
are in. There is nothing else to offer. Blizzard's voice chat is not the one
from patch 2.2 with channels you could name; since it was rebuilt on the
Battle.net service it is attached to the groups you are already in, and the
panel says so rather than leaving you looking for the button that makes one.

The first version of this listed only the community streams the client already
had a voice channel for, on the argument that a text stream is not a voice
channel and offering one that is not there would be a lie. That emptied the
picker at exactly the moment it is used. A community voice channel does not
exist until somebody joins it, so at login, which is when you are choosing what
to join, there is nothing to list. It offers every stream now and asks for the
one you picked, which is what pressing the voice button in the client's own
window does.

The pick is saved as the club and the stream behind it, and the name it was
picked under is saved beside them. Communities load a few seconds after you
enter the world, and without the name the picker and the status line spell your
voice channel as a pair of numbers until they do.

**It only ever joins.** Nothing in it leaves a channel, mutes anyone, picks a
device or moves a volume. Those are the client's own settings, somebody pressed
something to get them where they are, and an addon undoing one while your hands
are full is not a feature.

A channelID is deliberately not what is saved: it is handed out per session, so
saving one would mean joining whatever happens to take that number tomorrow.

The request is rate limited and gives up after five tries. Everything that makes
this look again is an event, and those arrive in bursts: a roster change, a
channel appearing, the service signing in. A join request per event is an addon
hammering a Battle.net service, and a channel that never turns up is a channel
the player has to sort out in the client's own settings rather than one worth
asking for forever.

### The harness was skipping an event handler

Found while testing the above, and it had been true for every part that ever
registered `ADDON_LOADED`.

Several parts unregister that event from inside their own handler for it, which
is what the client asks you to do and what Core does first of all. The stub's
`fire` walked the list of registered frames with `ipairs` while
`UnregisterEvent` removed entries from that same list, so every unregister
shifted the frames after it down by one and the next one in line never got the
event. Which part got skipped depended on the order the TOC happened to load
them in.

The chat part is what caught it: it registers its events in that handler,
therefore registered none of them, and every line fired at it in the test landed
nowhere. In the game it would have worked, which is the worst shape a harness
bug can have. `fire` walks a copy now.

The same section is why `scripts/harness.lua` has one table where it had four
locals. That file is a single chunk sitting on Lua 5.1's two hundred local
limit, which turns out to be a real ceiling: the allocation gates are one
concept and are one table now, and the chat stubs bring one name between them.

### A swing timer, with the Slam press drawn on it

The addon talked about the swing everywhere and never drew it. `UI/Ability.lua`
brightens a square's border to say Heroic Strike is armed and goes off on the
next swing, and nothing on screen said when that swing was coming.

`Swing/` is two gauges under the character, one per hand, on the pixel grid.
The clock is the combat log: `SWING_DAMAGE` and `SWING_MISSED` with you as the
source, because a swing landing is the same instant the next one starts, and
`UnitAttackSpeed` is how long that instant lasts. A miss counts, since
`SWING_MISSED` is the server saying the swing happened and did nothing, and a
timer that only heard damage would stop dead against a mob you cannot hit.

Which hand swung is a flag in two different slots, twenty-one on a landed swing
and thirteen on a missed one. Reading one index for both gives an off hand bar
that never runs and a main hand bar that runs twice as fast, which reads as a
haste bug and is a parser bug, so the harness feeds both subevents.

Haste scales what is left of a swing rather than restarting it. Flurry landing
halfway through a 3.4 second swing leaves you halfway through a 2.4 second one.
That is one line of arithmetic and it is the single thing a warrior's swing
timer has to get right, so it is asserted rather than described.
`UNIT_ATTACK_SPEED` is not enough on its own, because it does not reliably
follow an aura on these clients, so the player's own `UNIT_AURA` is registered
too and every one of them ends in a comparison against the speed already held.
`UNIT_INVENTORY_CHANGED` is the third door into the same arithmetic and this
addon opens it itself, off a loadout key.

The band is the point of the whole thing. Slam has a cast time, it does not
interrupt the swing while it casts, and finishing it restarts the swing. Press
early and the restart throws away the charge you had; press late and the swing
is pushed out to the end of the cast. The one right press is where the cast ends
as the swing ends, at `(D - C) / D` of the bar, and that is drawn as a green
band two tenths of a second wide with a line down the middle of it. The whole
gauge flips green while the fill is inside, because four percent of a bar is not
enough to catch out of the corner of an eye and all of it is.

The cast time is the client's own. `UNIT_SPELLCAST_START` carries what the
server actually started, talents and haste folded in, so from the first Slam of
a session the band is drawn off a measurement. Until then it is the spell's cast
time out of the new `ns.SpellCastTime` less a tenth of a second per point of
Improved Slam, and the talent is found by name rather than by position, because
every "Improved X" talent carries the ability's own localised name inside it.
Whether this client already folds that talent into `GetSpellInfo` could not be
settled without logging in, and the measurement means it does not have to be.

A completed Slam restarts the main hand timer off `UNIT_SPELLCAST_SUCCEEDED`.
Nothing in the log says so: the next event you would see is the swing that lands
a full weapon speed later, and a timer built on the log alone draws the whole of
that swing wrong.

The bars are gated on holding a weapon and not on being a warrior, because a
swing timer is worth the same to anybody standing in melee. The band is Slam's
and is warrior only, and the hunter run of the harness asserts both halves.

The tick counts in whole pixels: the bar's scale is its own width, so the fill
is an integer compared against the integer already on it and between swings the
tick writes nothing at all. It measures 0.03 KB per fifty ticks against a gate
of 0.05. It shipped at 20 Hz and does not run at a rate any more; the section at
the top of this file says why.

`scripts/harness.lua` grew an attack speed, a talent tree, a cast in flight and
a weapon in each hand, and its combat log stub went from sixteen values to
twenty-one so the off hand flag exists to be read. The swing gate went into the
`CHURN` table with the others rather than taking a local of its own, for the
reason the chat work gives above: that chunk is at Lua 5.1's ceiling of two
hundred locals, and the swing gate is what it ran out on.

### Deep Wounds never lit up, because the talent is not the bleed

The debuff row above an enemy bar matches auras by name, and the picker offered
12162 for Deep Wounds. 12162 is the talent. It is a hidden passive on the
warrior, the client names it "Deep Wounds", and no mob has ever carried an aura
by that name. What lands is 12721, and the client spells that one "Deep Wound",
singular. One letter, no error in the log, and an arms warrior watching a square
that could not come on.

The shortlist now carries 12721. Anyone who already picked Deep Wounds keeps the
dead ID, because the default list is read once on a fresh account and never
again, so `EnemyBars.Repair` swaps it at login and `AddSpell` swaps it on the way
in. Type 12162 into the panel's id field and the addon tells you Deep Wound is on
the bar, which is the truth and is visibly not what you typed.

Charge and Intercept have the same shape and were already right: 7922 and 20253
are the applied stuns, not the abilities. The comments beside them say so now, so
the next person to tidy the list does not "fix" them into the ability IDs.

The panel note used to say to use rank 1's id since the match is by name. That is
true for a ranked spell and false for a proc, and it is the sentence that made
12162 look correct. It now says to use the ID of the aura that lands, and names
both halves of the Deep Wounds pair.

The harness stubs auras now instead of answering nil forever, which left the
half of `ScanDebuffs` that lights a square up unreachable. It puts a "Deep Wound"
bleed on a mob and asserts the slot goes to mine with the timer and the stack the
client reported, dims for another warrior's, and goes out when it falls off. Put
12162 back and it says the mob is bleeding and the slot reads "none".

### The addon has a face

`Media/Icon.tga` is the first art the addon ships: the sword emblem, 64 by 64,
cut round with an alpha edge. Both TOCs name it as `## IconTexture:`, which is
what the client draws beside WarriorKit in the addon list. It is the only place
this art goes. The panel is flat, pixel-exact and deliberately plain, and a
gold plaque inside it would be a sticker on a schematic.

Three rules in `check.sh` came with it, because a texture fails silently in
every direction. A path a TOC names has to resolve to a file in the addon; a
file in `Media/` has to be a `.tga` or a `.blp` and has to be named by
something; and both its sides have to be powers of two. A path that does not
resolve draws a green question mark and writes nothing to the log, and a
texture 60 pixels wide is simply not drawn. `IconTexture` also joined the list
of fields the two TOCs must agree on, and `release.sh` now fails if the icon is
missing from the zip.

### The bars say what you can afford, and what is already armed

Two things a square was not saying.

A spell you have no rage for was drawn in full colour with a blue hairline
round it. The hairline is correct and it is not enough on its own: it is one
pixel on a 27 pixel square, and "what can I press" is a question asked with the
eye moving rather than stopping. The bars carry no rage bar and no mana bar of
their own, so what you can afford is readable off the squares or it is not
readable anywhere. The `cost` look now drains the art the way the `no` look
does, in both palettes. The blue edge stays and says which of the two kinds of
no it is once the eye has landed.

Range deliberately does not get the same drain. Out of range is a fact about
one mob and it goes away when you take a step; out of rage is a fact about you
and it is the one that decides what to press. Two states that both grey out are
two states you have to read the border to tell apart, which is the border doing
the work the art should have done.

The other was a queued Heroic Strike, which is the one press in a warrior's
rotation whose entire answer is "it is armed and it goes off on the next
swing". `Slot.Active` had it right the whole time and `Ability.Draw` drew it as
22% additive gold over the icon, which is invisible on art that is already
bright. It now draws a gold ring on the edge of the art as well, which is the
half you can see across a screen, and keeps the tint underneath so the square
reads as lit rather than merely outlined. Blizzard draws a checked border for
the same fact.

The ring lands exactly where the green equipped ring lands and is built after
it, so on the one square that is both, armed wins. Two rings a pixel apart on a
27 pixel square is mush, so there is only room for one and it has to be picked:
being worn is still true a second from now and the green comes back the moment
the swing lands, where an armed press you did not see is a press you make
again.

`scripts/harness.lua` holds both. The drain on `cost` and its absence on
`range` are asserted against both palettes, and the ring is driven on and off
against a status that is not `ready`, so it cannot quietly become a tenth rung
of the ladder or take the border the status owns.

### A black edge round the map, and a clock on the end of it

The ring was doing one job worth keeping. It ended the picture. Take it off and
the world runs out to a rectangle with nothing round it, which reads as a hole
cut in the screen rather than as a map.

So the square gets the box the action bars are already built on: three pixels
of near black with a hairline on the outside of it, in the same two colours, so
the two read as pieces of one interface. It is drawn as four bands round the
map rather than as one rectangle behind it. A rectangle would have to sit under
the map to avoid covering the world, and where a child frame lands against its
parent's own drawing is the client's business rather than something an addon
gets to state. Four bands are outside the map's bounds and cover nothing
whatever the client decides.

Two more pieces of Blizzard's furniture come off with the ring. The sun and
moon said whether it was day in a game whose sky says the same thing. The
digital clock draws its numbers on a strip of the old stone minimap tile, so on
a stripped square it was the last of the round map anywhere on the screen,
hanging under the bottom edge looking like the one bit that survived. That
strip is what this change started as.

`Minimap/Clock.lua` puts the reading back as a tab off the middle of the bottom
of the black. It overlaps the bezel by exactly one pixel, so the tab's top edge
and the bezel's bottom edge land in the same row, and the seam between them is
painted out with one band of the fill colour inset a pixel at each end. The
outline then turns both corners and runs round the map and the clock as one
silhouette rather than as a box with a box stuck to it. That join is the whole
reason it is a file and not four lines in `Shape.lua`.

It says local time, where Blizzard's shipped saying the realm's. The realm's is
the time an addon needs and not the time a person does, and it is one hover
away with the date. The twelve hour toggle is read off the client's own CVar,
because a player who set it set it for a clock and this is the clock now; a
client with no such CVar reads as twenty four hours, which everybody can parse,
where the wrong guess in the other direction puts a pm on the wrong half of the
day. The tick looks once a second and writes twice an hour.

Blizzard's clock belongs to an addon loaded on demand, so at login there is
nothing for the strip to take. `Shape.lua` runs another apply on `ADDON_LOADED`
and that is the one that catches it. Login is still the first apply and nothing
before it counts, because an apply taken earlier would read the width off a
frame the client has not sized yet and remember that number as the one to hand
back when the square goes off.

### The auto repair never repaired

It gated on `MerchantFrame:IsShown()`, and `MERCHANT_SHOW` is the server
opening a merchant session rather than the client finishing the window.
`ShowUIPanel` defers when another panel holds the slot, and a client that loads
`MerchantFrame` on demand has no frame to ask at all. So the repair asked a
frame that was not up yet, `Repair.Run` answered "no merchant window is open",
and `OnEvent` swallows every refusal on purpose, because a refusal at a
merchant is nearly always "nothing is damaged". It failed at every vendor, in
silence, for four releases.

The sale next door never saw it, and that is the part worth writing down. The
sweep is a ticker: it asks the same question again a fifth of a second later,
by which time the window is up. Two parts on one event, one of them working,
and the difference was that the broken one asked once.

The gate is the session now. `MERCHANT_SHOW` sets a flag and `MERCHANT_CLOSED`
clears it, both stay registered whatever the setting says, and `autoRepair`
decides whether the handler repairs rather than whether the handler runs. That
second half fixes a smaller bug in the same line: with the setting off the
frame used to unregister, so `/wk repair` at a merchant told you there was no
merchant.

The harness grew a merchant that can be open with its window shut, which is the
only shape that catches this. It also had to stop telling the sweep's frame
from the repair's by which events they hold, because they hold the same two
now; it flicks `sellTrash` once instead and takes whichever frame leaves
`MERCHANT_SHOW`.

### A filter for the red text in the middle of the screen

A warrior generates more of it than anyone. Charge, Intercept and Intervene are
all positional, the charge button in this addon aims by camera and so misses on
purpose, and every miss costs a line of red text across the middle of the
screen. While it is up it hides the one message that would have been worth
reading.

`Comfort/Errors.lua` replaces `UIErrorsFrame.AddMessage` and drops what is on
your list. Two decisions shape it.

Nothing is muted that you did not tick. The list ships empty, and the panel
offers what has actually come past this session rather than a guess at what you
can live without. There is one preset, `/wk errors charge`, and it is a press
rather than a default.

The list is account-wide, and it is keyed by the name of the global holding the
message rather than by the message. `ERR_BADATTACKPOS`, not "You are too far
away!". A name survives a locale, survives a client rewording the string, and
means the same thing on the character you log into next, which is the whole
point of it being in `ns.db` rather than `ns.dbc`. Messages built from a format
string cannot key that way and fall back to their own text; none of them is the
spam this exists for.

The hook is installed once and never taken off. Turning the setting off makes
the wrapper pass everything through. Putting the old method back would write
over whatever addon hooked after this one, and a filter is not worth breaking
somebody else's.

### The minimap is square, and one button holds the rest

Two files, one part, and they are one decision. The round mask throws away the
corners of a map the client has already drawn and the ring spends about twenty
pixels of every edge on rivets, so `Minimap/Shape.lua` takes both off and sizes
the frame to `minimapSize`, 180 by default against the client's 140. The north
tag and the two zoom buttons go with the ring and the mousewheel takes over the
zoom, clamped at both ends because a client asked for a level it does not have
raises.

Blizzard's own icons were anchored to points on the arc and a square has no
arc, so the mail, the tracking, the battleground and the calendar are pulled to
the four corners. Each one's original anchor is recorded the first time it is
moved and handed back when the square goes off, which is the same contract
`Artwork.lua` has: off is a state, not a reload.

`Minimap/Corral.lua` is the other half. Every addon that wants to be reachable
puts a round icon on the edge of the map, and with eight installed the map is a
ring of icons with a map in the middle. The corral takes every named child of
the minimap that is not Blizzard's and not ours, parents it to a tray behind
one square, and replaces the button's own `SetPoint` with a no-op, because a
minimap button drags itself back to the arc whenever it feels like it. That is
`ns.Strip` replacing `Show` with `Hide`, on a different method and for the same
reason. Parent, anchor and the real `SetPoint` all come back on release, and
nothing else about the button is touched, so a press in the tray is the press
it always was.

No ticker. Addons load late, so the scan runs at login, on `ADDON_LOADED`
after login, and whenever you open the tray, and never on a clock.

The first test on a real client collected 555 buttons, and the shape of that
mistake is worth keeping. The minimap is not only where addons hang their
button; it is also where every addon that draws a pin on the map hangs the pin,
and Questie parents several hundred quest icons to it. The corral took the lot
and, because a taken button has its `SetPoint` replaced, left Questie unable to
move its own map.

Four tests now, and the last is the one that would have caught it alone. A
candidate has to be a Button, because a pin is often a Frame and a button
almost never is. It has to measure between 18 and 48, because LibDBIcon draws
at 31 and a pin is drawn at 12 to 16. It has to not be one of a family:
candidates are grouped by their name with the trailing digits taken off, and a
group of more than two is a pool rather than a button, because pins are pooled
and named by counter and a button has one name and no siblings. And there is a
ceiling of 24, which is not a filter but a refusal, reported in `/wk status`
and in the panel rather than swallowed.

`/wk minimap list` names what is held and how much was left as pins, because
the way this was found was a square on the minimap reading 555 with no way to
ask what it meant.

The harness grew a minimap: a cluster, a ring of art, four of Blizzard's
buttons anchored the way the client anchors them, three addon buttons of the
two shapes that actually turn up, and one unnamed child that must never be
collected because a nameless button could not be released. Most of what it
asserts is the reverse direction, because the forward one is the easy half of
both files.

### The cloned bars answer a press

The squares read the right slots, drew the right art and cast the right spells,
and they still did not feel like buttons. Five things were missing and four of
them are the same missing thing: nothing on a square changed in response to
anything you did with it.

The loudest was the global cooldown. `Buttons/Slot.lua` withheld the swipe below
1.5 seconds on the grounds that a bar sweeping on every press is a strobe. It
is, and that strobe was the only thing on screen answering a key press: a rage
dump has no cooldown to count, no colour to change and nothing to grey, so
pressing one moved no pixel at all. `Slot.State` now returns the cooldown's
numbers whether or not it returns the `cooldown` status, and `Ability.Draw`
takes the swipe off the numbers and the countdown off the status. The global
sweeps and gets no number; a real cooldown still gets both.

Then the three the client will draw for you if asked. A highlight on the
HIGHLIGHT layer, which the client shows and hides itself for any frame that
takes the mouse. A pushed tint, which the Button widget draws between mouse down
and mouse up. And a tooltip, which was on the list of things a square
deliberately was not and should not have been: drag is a way to lose a bar to a
misclick, and a tooltip is how you find out which rank of Rend the loadout put
in slot four.

The fifth is the active tint. `IsCurrentAction` and `IsAutoRepeatAction` fold
into `Slot.Active`, and a square that is already what is running gets an
additive gold wash over the art. On a warrior that is the stance you are
standing in, drawn on the bar at a glance, and the auto attack already swinging.
It is an argument to `Ability.Draw` rather than a tenth status, because the
active stance is also `ready` and the two must be able to be true at once. The
two calls are probed separately from the five in `NEEDED`: a client without them
loses a tint, not the bar.

And empty slots stopped being question marks. An empty slot has no art, so it
fell to the `no` look and came out as `INV_Misc_QuestionMark` at 55 percent, a
row of grey question marks where Blizzard's bar had holes. Both palettes grew an
`empty` look carrying `blank`, which says draw no art at all.

### You can drop a spell on a square, and a worn item says so

The two things the entry above listed as not done.

Dragging was refused on the grounds that `PickupAction` and `PlaceAction` on a
frame you can drop anything onto is a way to lose a bar to a misclick. The risk
is real and the conclusion did not follow. With Blizzard's buttons hidden
underneath, nothing could be dropped on a bar at all, so learning a spell meant
turning the whole clone off to place it and back on again. A misclick moves one
slot and hands back what it displaced. Nothing is destroyed, and the picture is
right on the next tick.

So a square takes `OnDragStart` and `OnReceiveDrag`, both refused in combat,
which is where `PickupAction` cannot be called anyway. They ask
`Layout.CanCarry`, which is new and is the smaller half of `Layout.CanWrite`.
That split was a bug found while wiring this up: `CanWrite` refuses while the
cursor is holding something, which is the state every drop happens in, so a drop
asking it would be told to put down the thing it was in the middle of putting
down. It also demanded all seven action calls, and moving one slot onto another
needs two. `CARRY` is those two, `COMPOSE` is the five a loadout needs on top,
and each is probed once.

Empty squares are drawn at full alpha now rather than faded. That looks
backwards and is not: with `blank` there is no art left to fade, so the alpha
only reached the black backing and the hairline, and fading those leaves a drop
target you cannot see. It is also why there is no grid. The client shows one on
`ACTIONBAR_SHOWGRID` because its bar has no background to see a hole against,
and this one is squares on a box.

The equipped ring is `IsEquippedAction` folded into `Slot.Equipped`, drawn as a
second green outline one pixel inside the status border rather than a recolour
of it. The outer edge already carries the status, and being worn is not a
status: a wielded weapon can be on cooldown and out of range at once, and all
three are worth saying. It sits on `OVERLAY` because `BORDER` is under the art,
and a ring on the art's own bounds would be covered by it.

`Buttons/Bars.lua` hit 832 lines doing this, over the 800 line gate. It took the
split rather than a fourth entry on the allow-list. `Buttons/Square.lua` is what
one square answers to the mouse: everything in it hangs a script on a button and
touches the cursor, and none of it knows what a bar is or which slot a square
points at.

### The meter bars have an opacity slider

`BAR_ALPHA = 0.15` was a constant in `Meter/Window.lua` and the note beside it
argued the number well: a bar is read against the bars next to it rather than
against the world behind it, so a tint ranks four players and a wash only hides
the floor. The argument holds and the number does not travel. 15 percent over a
dark crypt is what it was drawn for, and 15 percent over Tanaris at noon is
nothing at all, which is a thing the addon cannot see and a player can see in a
second.

So it is `meterBarAlpha`, whole percent, 0 to 100 in fives, still 15 by default.
The panel gets a slider under the pane width and `/wk meter alpha 60` reaches
the same stops, through `Command.Step` so a value off them is refused rather
than quietly rounded. At 0 there are no bars and the meter is columns of
outlined text over the world, which is one of the reasons the range starts
there rather than at something safe.

The one part worth writing down is the guard. A row writes its bar and its name
only when the player on it changes class, which is what keeps the tick free, and
the alpha is not the class: left alone, the slider would have looked broken to
anyone dragging it outside a fight and landed later on a class change that never
comes. `MeterWindow.Apply` clears the colour guard on every row, so a setting
change lands on the next tick. The harness asserts that, rather than asserting
the saved variable took the number, and the panel's slider census went from two
to three so the next one is a decision as well.

### The unit frames share one layer instead of two copies of it

`UnitFrames/EnemyBars.lua` and `UnitFrames/Skin.lua` draw the same things about
the same units, and each had grown its own copy of how. Neither copy was wrong.
Having two of them was, and they had already drifted:

- the class colour was a hex string in one file and an `{r, g, b}` table in the
  other, with a cache each;
- the level tag was interned in the skin and rebuilt on every tick in the bars,
  which is a `tostring` and a concat per mob to say a number that changes when
  the mob does;
- the reaction palette was declared in both, four of the nine colours being the
  same three literals typed out twice, which holds until somebody warms the
  green on one of them;
- the bars walked the whole party or raid on their own ticker to get the unit
  list their threat comparison needs, which is eighty unit queries five times a
  second in a forty man, while `Meter/Roster.lua` already held that list and
  rebuilt it on `GROUP_ROSTER_UPDATE`.

There is a `Unit/` layer now, between Core and UI, and both files read it.
`Unit/Color.lua` is every colour the addon puts on a unit, one palette with the
semantic maps on top of it, so a green that appears in two answers is the same
table in both. `Unit/Level.lua` is the tag and what the kill is worth, so the
bars got the skin's cache and the skin got the bars' colour. `Unit/Threat.lua`
is what the client's threat API says, for one mob or across a group.
`Unit/Roster.lua` is `Meter/Roster.lua` moved, because the bars wanted the same
answer it was already giving the meters.

`Unit/` draws nothing and signs into no registry. Two rules hold across it, and
both come from the callers rather than from taste. Nothing allocates, because
everything on that page is reachable from a ticker running against every mob on
the screen. And a colour is handed back by reference and never built at call
time, because the tickers guard their widget writes on colour identity, so the
same state has to answer the same table every time.

The enemy bars' allocation gate went from 0.25 to 0.05 KB per fifty ticks, and
what it measures is 0.00. The roster walk was the whole of what was left.

Nothing about what either frame looks like changed.

### A stack panel, so a widget's layout is a tree rather than a hundred SetPoints

`ns.UI.Flow` is what XAML calls a StackPanel and CSS calls a flex container:
rows, columns, gaps, padding, alignment, growth, wrapping and mirroring. Two
passes, the same two XAML has. Measure asks every node how big it wants to be,
bottom up; Arrange hands every node the rectangle it got, top down, and pins
each frame to the root's top left corner at the offset that came out.

`LayoutWidget` in `UnitFrames/EnemyBars.lua` was a hundred and eighty lines of
`SetPoint` with the failure mode every hand-written layout has: each anchor is
individually correct and the relationship between them lives only in whoever
wrote them. Moving the threat line up three pixels meant finding the four other
offsets measured off the same edge. It is a tree now, and the widget's own
height falls out of the measurement instead of being derived by hand from four
other numbers.

Three shapes were worth adding for what the bars actually needed. `lineOrder`
lets a wrapping row grow upwards, so the debuff line nearest the gauge is the
one that fills first and a partial line hangs off the top. `direction = "stack"`
is XAML's single-cell Grid, every child getting the whole rectangle and placing
itself in it, which is how the threat number and the debuff row share one strip
without either reserving room from the other. And `reverse` is the whole of
mirroring a layout, which is what the target frame is against the player frame.

It does not do content sizing and it will not. A node's size is a number the
caller knows before the layout runs, so the two strings inside a gauge, sized by
whatever the mob happens to be called, stay pinned to each other with plain
anchors. A layout that had to re-run on a name change would be a layout running
on the tick. `check.sh` is what holds that line: no function in `UI/Flow.lua` is
named in `HOT`, so the engine may allocate and everything that calls it may not.

`scripts/harness.lua` gates the engine on its own, nine shapes read back off the
offsets it wrote, before anything built out of it is touched. The debuff row
test stopped naming an anchor pair and measures where the square lands instead,
which also covers the gauge's own placement and did not before.

### The frame skin is laid out by the same engine, and mirroring is one flag

`Place` in `UnitFrames/Skin.lua` carried the block's whole geometry by hand, and
`spec.mirror` was three variables named `portraitEdge`, `gaugeEdge` and `pull`
whose signs were threaded through every offset in the function. The target frame
mirrors the player frame, so every one of those offsets had to carry which way
it was facing.

The box's interior is a Flow row of three cells now with `reverse = spec.mirror`
on it, and mirroring is that flag. Two details made it work. The pixel the box's
outline draws into is its own empty cell at the end of the row rather than
padding, because `reverse` reverses child order and not padding, so an inset
written as padding would have stayed on the same edge when mirrored. And the
divider is the square's inner column expressed as a nested reversed row, so it
turns with the square.

Three things `reverse` could not take, and all three for the same reason Flow
does not do content sizing. The block's own anchor on Blizzard's frame is placed
by its owner. The four badge regions belong to the client and stay hand pinned.
And the four font strings are as wide as whatever the unit is called, so they
are anchored rather than arranged. `pull` survives in that last block alone
instead of running through the whole function.

Nine anchors went out of the addon: the rails and the divider each used two
points and use one. The blocks measure what they measured, 202 by 34 with a 21
and 10 gauge and a one pixel hairline.

### One gauge, drawn one way

The addon drew a flat status bar in three places and had three implementations
of it. Two of them shared an exact pair of lines, the fill colour followed by
the spent track at a fifth of that colour on nine tenths alpha, typed out in
`EnemyBars.lua` and again in `Skin.lua`.

`UI/Gauge.lua` holds what is actually shared. `Gauge.New` builds a flat bar with
its track. `Gauge.Flatten` turns a bar the client made into a flat one and reads
back first, so a bar that is already flat costs a comparison rather than a
texture write. `Gauge.Underlay` puts a texture inside a bar and under its fill
by draw layer, which is where the note about the target frame drawing at 28
percent of its own colour now lives. `Gauge.Paint` is the pair, once.

`Meter/Window.lua` was looked at and deliberately left alone. Its rows wear the
same look and are a different widget: one texture whose width is that player's
share, with nothing behind it and no spent part to colour. Putting it through a
gauge would add a frame per row, raise an ordering question against the row's
icon and text that does not exist today, and hand a StatusBar's internal float
the rounding the meter does in whole pixels on purpose. Three implementations
were two implementations and a lookalike.

### check.sh caps how long a file may be

The addon gates allocation on tickers, TOC parity between the two flavours and
version drift between the TOCs and `ns.version`, and had nothing watching a file
reach nineteen hundred lines. Two had. That is the same class of debt: nothing
is wrong with any one line, the whole is past what fits in a head, and the next
change lands wherever there is room rather than where it belongs.

800 lines in general. Three files carry their own ceiling, set at what they
measure today, each with a one-line reason and the split it would take. The
ceiling fails in both directions: growing past it fails, and shrinking below it
fails until the number comes down in the same commit, which is what makes it a
ratchet rather than a licence to grow back.

### The harness was one file, and it had nearly stopped loading

Eleven thousand lines: a stub of the client, then thirty six sections of
assertions, in one chunk. Lua 5.1 gives one function two hundred locals, a chunk
is a function, and the count had reached a hundred and seventy one. What that
number buys at two hundred is not a failing test. It is `main function has more
than 200 local variables`, and the harness does not start.

Nothing measured it. The file carried a header asking whoever came next to scope
their section in a `do ... end`, which is a request rather than a gate, and
eleven of the thirty six sections had not. Ten of those eleven had left a name
behind that a later section was reading.

**It is a directory now.** `scripts/harness.lua` is still the command and still
runs the same assertions in the same order, against the same client, to the same
output. Under it, `harness/client/` is the stub, one file per part, loaded in the
order `client/init.lua` lists. `harness/sections/` is the questions, one file per
subject, in the order `harness/runner.lua` lists. Every file is its own chunk
with its own two hundred names. The worst declares fifty eight.

**What one section leaves for a later one is named at both ends.** Sections
depend on each other on purpose: a churn figure measured in one is compared in
another, the skin is fitted in one and taken off again three down. In the single
file that worked because the variable was still in scope, which is also how a
section could pick one up by accident. It goes through `H.carry` now, written
where it is handed over and read where it is used. The ten values the stub keeps
and a section writes, the purse and the repair bill and how tall the screen is,
live on one table that both sides name.

**Naming a section stops the run after it.**

    lua5.1 scripts/harness.lua src WARRIOR 12-debuff-square-size

Everything above that section still runs. Not the section alone: it reads what
the ones above it left behind, so a run of one on its own is a crash rather than
a smaller suite.

**`check.sh` measures the shape**, which is the part that was missing the whole
time. No harness file over 800 lines or 40 names at chunk level unless it carries
its own ceiling and a written reason, both ratcheting in each direction, and the
runner's section list has to match what is on disk.

## Unreleased

### The charge part now stays out of the way on another class

Charge, Intervene and Intercept are warrior abilities. On a hunter the part was
still built anyway: a secure button holding a key override, a ten-a-second
ticker behind an icon that could never light, a twenty-a-second nameplate scan
behind a marker for an ability that does not exist, and `SoftTargetEnemy`
rewritten on every combat transition to serve all of it. Four tabs of settings
in `/wk` wrote values nothing on that character read.

`ns.IsWarrior()` is the one answer now, in `Core/Core.lua`, and the loadout
reads the same one instead of asking the client itself. `Icon.lua` and
`Marker.lua` unregister their event frames at PLAYER_LOGIN rather than building
something and hiding it, because a hidden marker still pays for the scan.
`SoftTarget.Wanted` returns nil, which is the single place that decides whether
that CVar gets written, so the panel, the slash word and the combat transitions
all leave it alone together. The slash words say why, `/wk status` says why, and
the Charge page is one sentence instead of four tabs of dead controls.

The saved settings are untouched. They are account-wide and a warrior alt shares
them, so a class gate is a fact about this character rather than a preference
about the addon.

The class is read every time rather than cached. Class data is not reliable
while the files load, and a cache taken then would lock a warrior out of their
own charge button for the session. An unresolved class counts as a warrior for
the same reason: the two wrong answers do not cost the same.

`check.sh` runs the harness twice, and the second run comes up as a hunter.
Both halves are decided once at PLAYER_LOGIN, so the only way to assert that
nothing was built is to start as something else. That run asserts the button
and the marker are absent, the key was refused, the Charge page is one tab and
the CVar came out holding the value it went in with, and it re-runs every other
part of the addon on the way, which is how a part that quietly needed a warrior
would now fail here rather than in someone's game.

### The charge key did nothing while the frames were unlocked

`ApplySecure` cleared the button's `type` attribute whenever `ns.db.locked` was
false, so that a left-press meant for a drag could not also cast. It did stop
the drag casting. It also killed the bound key, because the key is an override
that clicks the same button, and a secure button with no type is a button with
no action. The symptom is a charge key that silently does nothing until you type
`/wk lock`, with no error and nothing in chat.

The two jobs are on two frames now. The button keeps `type = "macro"` the whole
time and never takes the mouse at all; a plain frame laid over it takes every
click while the frames are unlocked and does the dragging. The key works in both
states, a stray click while placing still cannot cast, and the tooltip moved
onto the handle with the drag.

### Blizzard's damage number sat across the level and the rage gauge

`StripArt` walks textures. The combat feedback number is a font string, so the
walk never saw it, and Blizzard draws it centred on a portrait sized for a frame
a hundred units tall. On a 34 pixel block it lands over the level text and half
the power gauge, and neither number can be read.

It goes with the name, the level and the two bar numbers, which is the list of
font strings this file already hides by name. It is the one entry on that list
with nothing drawn in its place: the art that used to hold it does not exist any
more, so there is nowhere correct to put it. The harness shows it and asserts it
stays hidden, because the client calls `Show` on it at every hit.

### Repairing

The other half of what a merchant is for. Grey items have sold themselves at
every merchant since 1.4 and the repair was still a click on an anvil.

`Comfort/Repair.lua` pays at any merchant the client says can mend, the moment
the window opens, behind the same shift key that skips the sale. Guild funds
first where your rank's withdraw allowance covers the bill, your own purse where
it does not, and nothing at all where neither can cover it: half a repair is not
something the client offers, and an emptied purse is worse than broken mail.
A guild that answers yes and then refuses falls through to your own gold rather
than walking away.

`/wk repair` with no argument repairs the merchant in front of you now and says
why not when it cannot. `/wk repair on|off` is the setting. `/wk status` carries
the worst piece you are wearing.

One call and no ticker, which is the whole reason it is a separate file from the
sale. `RepairAllItems` does every slot at once, so unlike a sweep there is
nothing to repeat. The two parts share the merchant window and share nothing
else.

The merchant calls are named in `.luacheckrc` on the usual standard: TitanRepair
and Leatrix Plus both call them unguarded on both clients, inside the feature
this one is. The guild bank trio is not, because Classic Era has no guild bank
and TitanRepair calling them there proves only that TitanRepair would break.
Those three go through `_G` and are pcalled, so a client without them loses
guild funding and keeps the repair.

### The numbers on a debuff square were outlined into blobs

The threat line and the targeted-by line went up to 14 for the same reason from
the other direction. Those two sit in the gap above the gauge, over whatever the
player is standing on, so the outline is not a choice there: with nothing behind
the glyph, flat is not softer, it is gone. That makes the floor a hard minimum
rather than a switch point, and 12 outlined was the one combination that is
wrong both ways at once, too small to carry a rim and unable to drop it. The
empty bar is two pixels taller as a result, and the harness derives that height
from `ns.UI.OutlineFloor` rather than carrying a literal, so the two move
together.

The name, the health number and the level tag are the same 12 and stay outlined.
They sit on an opaque fill, which makes the outline a contrast judgement rather
than a necessity, and a pale name on a pale gauge is a real argument for keeping
it. The gate encodes that distinction rather than flattening it: outlined text
over the world must reach the floor, text over a fill may be either.

An outline is a rim drawn round a glyph and it costs the same pixels whatever
the glyph is, so below about fourteen it has eaten the counters: the hole in a
6, the waist of an 8. UI/Theme.lua has said so since the panel was rebuilt, and
said it about panel text, which is why panel text is flat. The timer and the
stack count on a debuff square are over the icon's own opaque art for exactly
the same reason, and they were being drawn outlined at seven to twelve pixels.

Both go through `ns.UI.NumberFont` now, which keeps the outline while the glyph
is big enough to carry one and drops it when it is not. The harness sets every
icon size in the range and reads the size and flags back off the font object,
so it fails on the old values at every one of them.

Worth saying rather than hiding, because the harness prints it: every number on
a square comes out flat, at every setting. Both are capped by a design constant
under the floor, the timer by the bar's own text size and the count by
`COUNT_TEXT_SIZE`, so no icon setting can lift either to fourteen. That means a
56 pixel square still carries a 12 pixel timer, which is legible and small for
the room it has. Left alone for now; it is a look decision rather than a defect.

Found by the other half of this pair working on the meters, which had the same
bug in its own rows. A number can be arithmetically correct at every zoom and
still be the wrong number, and the layout is exactly as consistent as it would
be if it were right.

### two meters, and no window round them

A damage and healing readout and a threat readout, side by side in one
draggable frame. A row is a spec icon, a name, a number and a class-coloured bar
as long as that player's share of the top row. Clicking the damage header swaps
it to healing. There is no breakdown to open, because there is nothing behind a
row to open.

Nothing is drawn but the rows. No backdrop, no border, no title bar. Details
draws a window because it is a tool you go and use; this is two columns you read
out of the corner of one eye during a pull, and every pixel of chrome around
them is a pixel of the fight underneath.

**The threat pane differentiates.** The percentage is the client's own, where
100 means that player takes the mob, thresholds and talents already folded in.
What is new is the rate it is changing at and what that projects to: 82% and
falling is a rogue who stopped, 82% and climbing four points a second is a rogue
who takes the mob in four and a half seconds, and the header says which and
names them. Smoothed over half second samples, because threat arrives in lumps
the size of a Sinister Strike and two raw samples can differ by twenty points
either way. Nothing past a minute is projected.

On Classic Era the pane says `no api` and stays empty. Vanilla computes no
threat, so every Classic threat meter is a combat log simulation carrying a
table of coefficients, and that is a different addon.

**Spec icons on clients with no specs.** There is no `GetSpecialization` here.
A character is three talent trees with points in them, and the tree with the
most is the whole of what anyone means by a spec. Yours is read directly and
re-read on every point spent. Everybody else's is an inspect, inside about 28
yards and out of combat, one in flight and never the same person twice inside a
minute. Until one lands the row draws a class icon, so the icons sharpen over
the first minute in a group and never block anything while they do.

**One clock for every row.** Details gives each player their own activity
window, which flatters whoever stopped early. This divides everyone by the
segment, which is the only version where the rows add up to the total on the
header. Overheal is subtracted: a healer who lands 40k into a full health bar
has healed nothing.

**The group filter is the parsing.** The combat log carries the party next door,
both sides of the duel by the mailbox and every mob in the pack. A pet's damage
is its owner's, so a hunter does not read as half a hunter. What a member
summoned is theirs, taken from `SPELL_SUMMON`, because a totem is not a pet and
no unit token points at one. Everything else is nobody's.

**A new gate.** `METER_CHURN_KB`, measured with the clock running rather than
frozen. A meter with nothing moving allocates nothing at all, because every
write is guarded on a number rather than on the string it would make, and a gate
on that figure would be measuring the guards. With the seconds ticking over it
measures 0.16 KB per fifty ticks and the gate is 0.20.

Worth knowing which way round the guards pay. In a fight they save almost
nothing, 0.16 against 0.27, because the numbers move every tick and the string
gets built either way. What they buy is the meter sitting on screen between
pulls, which is most of a session, at nothing at all.

**The icon is 27 pixels because that is a size the client stores.** Every other
number in the layout follows it. A spell icon is kept at 64 texels, the crop
takes the five texel border off each edge, and the 54 that are left are exact
only where they halve onto whole pixels: 54 and 27, nothing between. So a row
icon draws 27 at zoom 1 off the half size copy and 54 at zoom 2 off the full
one, which is as sharp as a spell icon gets. The row is the icon with a pixel
above and below, 29, so the icon decides the height rather than the text. Six
rows and a header is 196 pixels tall, two panes and a gap is 408 wide.

**Every string on it is 14, because every string on it is outlined.** With no
background behind them the outline is the only thing between a number and a pale
floor, so unlike a timer on a debuff square this text cannot fall back to flat
when it shrinks: flat over the world is gone rather than soft. That makes the
outline floor a hard minimum here, and both sizes sit on it. The number lives in
`UI/Text.lua` and the harness reads it from there, so the meters and the bars
are held to one figure.

That is the second version of those numbers. The first drew a 12 pixel icon and
11 pixel row text, and the report from the client was two words: shrunken, and
not sharp. The pane headers were wrong too, at 12, and nobody reported those
because nobody reads a header twice. The harness fails now on an icon size the
client does not store, at either zoom that can be exact, and on any outlined
string under the floor.

**Five defects, four of them caught before any of this ran in a client.** The
group total was `0/0` before the first fight of a session, and the client's
`string.format` renders that nan as `-9223372036854775808`; that was the first
tick of every login. The threat header never wrote at all while the state was
quiet, because the guard's unchanged case was identical to the state the pane
starts in with nothing drawn. The same header then stuck on `no target` after a
target came back. An inspect the client never answered parked the queue on that
GUID for the rest of the session, because there is no failure event for one.
And the fifth is the sizing above, which no gate caught because there was no
gate until a person looked at the thing. Each has a test that fails without its
fix.

### bars zoom does something now

It never has. The setting shipped, the panel offered 1 to 3, the README called
it the answer to sizes being absolute on a high resolution monitor, and the bar
measured 180 by 62 screen pixels at zoom 1, 2 and 3 alike. Fonts included.

One line did it. Every design number in `LayoutWidget` was multiplied by
`ns.Pixel(widget)`, which on the grid is `1 / zoom`, and the scale the zoom put
on the frame multiplied it straight back. The two cancel exactly, which is why
nothing looked wrong: the bar was not the wrong size, it was the same size.

The fix is a second conversion with a name of its own. `ns.UI.Pixel` is one
screen pixel and is for hairlines and insets, which stay one pixel when the
design grows. `ns.UI.Unit` is one pixel of the design, which on the grid is one
unit whatever the zoom, because turning that unit into a 2x2 or 3x3 block of
screen pixels is the entire job of a zoom. Every size in the bars goes through
`Unit` now and every edge still goes through `Pixel`.

    zoom 1   bar 180 x  62 px, gauge 23, icon 20, hairline 1
    zoom 2   bar 360 x 122 px, gauge 44, icon 40, hairline 1
    zoom 3   bar 540 x 182 px, gauge 65, icon 60, hairline 1

At `bars zoom 2` a debuff square draws 38 screen pixels of art, which is about
what Blizzard's own buff buttons draw and roughly twice what this addon has been
drawing. If you have ever thought the bars looked small on a big monitor, that
is the setting, and it works now.

**The sharp icon size moves with the zoom.** The art is the square times the
zoom, less two pixels for the border, sampled from 54 texels. So one stored
texel lands on one pixel at `bars icon 29` when the zoom is 1, and at
`bars icon 28` when the zoom is 2, where it draws the full 54 texel copy one for
one and is the sharpest a spell icon gets. `EnemyBars.IconAdvice` works that out
rather than carrying a table, the panel and `bars icon` both read it, and the
harness checks the number it names against the texel arithmetic at each zoom.

**Two new gates.** The harness converts the bar to screen pixels and compares it
against what the design asked for at each whole zoom, which is the check that
was missing: every assertion in that file was written in the widget's own units,
and in those units the bar genuinely does change size at 2x. It is half as many
units on twice the scale, the same picture, and no measurement taken in units
can tell the two apart. The whole-pixel anchor sweep now runs at 1x, 2x and 3x
as well, because a number that was even before a multiply is not obliged to stay
even after one.

### The bars were half a pixel low, and the icons were never the size they said

Reported as "the bar does not feel crisp", which it was not, and the cause was
not the nameplate. Three anchor offsets in the enemy bars were fractions of a
pixel, and a frame whose own origin sits half a pixel off a boundary has every
edge, every glyph and every icon inside it drawn across two rows.

The one that mattered: `PLATE_BAR_HEIGHT / 2 + 1` is 11.5, it is the offset that
puts the widget where Blizzard's bar was, and replace is the style that ships.
Every bar this addon has ever drawn in its default configuration was half a
pixel low. The level tag's number was 2.5 pixels off centre, half the width of
the reaction stripe, on every bar as well. The threat line lands on a half pixel
at any odd debuff icon size. All three now round, and the comment explaining why
rounding is necessary was already sitting three lines above the worst of them.

An odd bar cannot be centred on a point and land on a boundary, so half a pixel
of centring is what this gives up. It is not visible. The smear was.

**The harness walks every anchor now.** Every frame the addon puts on the pixel
grid, every offset on it, and it fails on anything that is not a whole number of
physical pixels: 2843 offsets across 1779 regions. This class of bug is
invisible in review because the arithmetic that causes it looks like centring,
and it cannot be caught by reading one file, so it is caught by a number
instead.

**Debuff icons: 29, and nothing else.** The panel said 16 and 32 were the sizes
that draw sharp. Neither is, and the square has never been drawn at either. The
client keeps each texture at half the size of the one above and picks the pair
nearest what was asked for, so a draw is exact only where the sampled texels
halve down to the drawn pixels. `ns.UI.Icon` crops five texels a side to lose
the border baked into the art, leaving 54 rather than 64, and the square draws a
one pixel border with the art inset inside it, so a 20 pixel setting draws 18
pixels of icon. 54 halves to 27, plus the border is 29, and 13.5 is not a number
of pixels. Nothing else in the range lands.

The shipped 20 draws 18 from 54, which is 58 percent of the way between two
stored copies and about as blended as the range gets. The default has not moved,
because moving it rewrites a setting nobody touched, but the row is a slider
that steps by one instead of a stepper that stepped by two, so 29 is reachable
from the panel for the first time, and the note names it. `bars icon` says the
same thing. `EnemyBars.IconAdvice` is the one place that arithmetic lives and
the harness checks the size it names is genuinely exact rather than trusting the
note. 29 is the answer at `bars zoom 1`, which is the default and was the only
zoom that existed in practice when this was written. See the zoom entry above
for what the number becomes once the zoom does something.

The ceiling on `bars icon` is 56 now rather than 32. 54 texels survive the crop
and the border takes two pixels, so 56 is the largest square where a stored
texel still lands on a screen pixel; above it the client stretches 54 texels
over more pixels than it has and the art softens again. The old 32 was chosen
when the row was four fixed icons on a 180 pixel bar, and it put the whole top
half of the useful range out of reach: with `bars zoom` inert, this number was
the only way to get a big icon, and it stopped well short of one.

What this does not fix: a nameplate's own origin is wherever the mob is
standing, which is a moving fraction of a pixel no addon can read. The bar is
exact in geometry and in its offset from the plate now. Where the plate lands is
still the client's business.

### A settings tab, and a slider that says how big you want this

An eleventh part, `Settings`, one rail entry in `/wk` holding the preferences
that belong to no feature. There is one of them so far. `UI size` is a slider
from 0.5x to 3x in quarters, and it sizes the windows this addon draws: the
`/wk` panel and the Clutter window. `/wk uisize 1.5` does the same from a macro
and `/wk uisize` on its own prints where you are.

It multiplies the whole step the screen already picks rather than replacing it,
which is the arithmetic that makes the control mean what its name says. On a 4K
panel the addon has been drawing everything at 2x on its own; dragging to 0.5x
there lands back on the design size with every edge still exact. On a 1080p
panel 0.5x is genuinely half.

Eleven stops, and they do not all cost the same. A stop keeps the pixel grid
when the size times the screen's own step comes out whole, which on most
monitors means 1x, 2x and 3x. The other eight ask for a one pixel hairline at
1.25 or 1.75 pixels and get a blur. `bars zoom` refuses a fraction outright and
still does, because a bar over a mob's head is the addon deciding what you see
in the middle of a pull. A settings window is you deciding how you want to read
it, so the fraction is allowed here and the panel names the stops that stay
exact and tells you which one you are on. The slash word refuses anything off a
step rather than rounding it, so a macro and the slider reach the same values.

`kit.Slider` is new in the widget kit, built on the client's `Slider` frame type
the way the scrollbar is, with a pair of nudge buttons behind a probe for a
client that refuses the type. Both paths are in the harness now, which is how
the fallback turned out to be broken on the day it was written: `pcall` returns
the error message where the frame would be, and the fallback called `Hide` on a
string.

A drag updates the readout and commits nothing until the button comes up. The
client reads a slider's value off where the cursor sits against where the track
sits, so a setter that resizes the window the slider is in walks the track out
from under the cursor and the next frame reads a value off geometry that has
moved. Committing live made the thumb slam between 0.5x and 3x for as long as
the button was held. The harness holds the button, moves the thumb, asserts
nothing was saved, lets go and asserts the value landed.

### The debuff row on the enemy bars is yours

It tracked Sunder Armor, Demoralizing Shout, Thunder Clap and Rend, in that
order, because those are the four an editor once typed into a constant. Which
debuffs matter is a spec question and a fight question, so the list is a setting
now. `/wk` has a Debuffs tab under Enemy bars: a row per tracked spell with the
icon, the name and a button that takes it off, a picker holding every debuff a
warrior can apply on these clients, and a field that takes any spell ID at all.
`bars debuff add 12162` does the same from a macro, and `bars debuff` prints
what is on the bar.

Ten slots. Matching is still on the localised name, so rank 1 is enough, every
rank counts and another warrior's Sunder still shows up desaturated. Two IDs
that resolve to one name are refused, because they would be two identical
squares lighting up and going out together. An ID this client cannot name keeps
its place and draws nothing, so a spell added on the TBC character comes back
when you log into it rather than vanishing from an Era session.

`bars icon` sizes one square between 16 and 32 pixels. Those two are the sizes
the client actually holds a copy of, a 64 texel icon halved and halved again, so
they are the two that draw sharp and everything between them is a blend of two
copies. The panel says which of the two you are on rather than pretending the
stepper is flat. The timer and the stack count now scale with the square: a
fourteen pixel number on a sixteen pixel icon covered the art it was
annotating.

The row still ends flush with the right end of the gauge, which is what it was
always for. What it does when it no longer fits is new: it wraps upwards, one
right aligned row at a time, so ten 32 pixel icons on a 180 pixel bar become two
rows of five instead of four icons hanging off the left edge into the mob next
to it. The bar grows by exactly the rows it gained, and the nameplate driver is
told the new height, so two mobs standing together still get two bars that do
not cover each other. An empty list costs the row entirely and leaves the threat
line its own height.

`Command.Number` now refuses a fraction instead of taking it. Every caller is a
pixel count, a bar count or a zoom step, all three of which sit on the pixel
grid, and `bars zoom 1.5` used to be accepted and put every edge in the addon
onto a half pixel.

## 1.7

### Three chores the client makes you do by hand

A ninth part, `Comfort`, one rail entry in `/wk` with a tab per chore. All three
are on by default, because every one of them is something you would otherwise do
every few minutes and off is not a state anyone would choose to start in. The
implementations are Leatrix Plus's, which is loaded on both of these clients and
is what proves every API involved.

**Fast loot.** The client's auto loot opens the loot window and then takes one
slot per frame, which is where the pause over each corpse comes from.
`LOOT_READY` fires before any of that, so the corpse is emptied there and the
window never draws. It runs only when auto loot is what your click asked for, so
a shift-click to open the window still opens it, and it is throttled to 0.3
seconds because the event fires again as each slot clears.

Under master loot only the slots below the threshold are taken. `LootSlot` on a
slot at or above it does nothing if you are not the master looter and quietly
assigns it to yourself if you are, and an addon should not do that on your
behalf. Where the client names no loot method at all the corpse is still emptied
solo and the job is handed back to the client in a group.

**Selling trash.** Grey items go at every merchant, and holding shift as you open
one skips that visit. Only grey, and only what a vendor will pay something for.
An item the client has not cached yet is left alone rather than sold on a guess,
and asked about again a fifth of a second later.

The sweep is a ticker rather than a single pass, because a sale is not instant:
the slot locks, the server clears it, and only then does the item leave the bag.
It repeats until a pass finds nothing left, backstopped at 25 passes, and it
stops early on the two vendor refusals worth naming. What it made is the
difference in your purse across the sweep rather than the sell prices added up,
which is the number that is still right when a vendor refuses something halfway
down the list.

The safety is the point. `UseContainerItem` sells a bag slot while a merchant
window is up and *uses* it when one is not, so the same call that sells your
greys eats your food and equips your weapons anywhere else. Every path into it is
behind a check that the window is still open, and the harness models the
difference: its stub sells with the window up and destroys with it down, so a
sweep that forgets to look fails the run rather than passing it.

**Max camera zoom.** `cameraDistanceMaxZoomFactor` goes to 4.0 instead of the
1.9 the client ships. The CVar is read straight back after it is written, so a
client that clamps reports what it clamped to in `/wk status` and in the panel
rather than being taken at its word. Off hands the CVar back at the client's own
default. It is written at every entry to the world rather than once at login,
because the CVar is the client's and anything that puts it back would otherwise
leave the setting saying one thing and the camera doing another.

### /wk destroy, for quest items you are finished with

Quest items for quests you have completed sit in your bags forever. Most cannot
be sold, so the vendor sweep is no help and the only way out is to destroy them.
`/wk destroy` opens a small window that shows one at a time: the item, the quest
it came from, a destroy and a skip.

The client will tell you an item is a quest item and will not tell you which
quest. There is no API for it. So this reads Questie's item database, which
carries the quest an item starts and every quest that wants it, and without
Questie the window says so and offers nothing rather than listing every quest
item in your bags.

Three things are never offered. An item that starts a quest you have not
provably finished, because starters look exactly like orphans and destroying one
loses a chain you never knew existed. An item tied to a quest in your log. And
anything the database has never heard of. What is left is sorted with the certain
ones first, and an item whose quest is still out there to pick up says "destroy
anyway" on the button rather than "destroy".

Four guards stand between the press and the delete: the slot is re-read against
the card, the item is picked up and the cursor is asked what it is really
holding, `DeleteCursorItem` is probed and pcalled because nothing installed on
either client calls it, and a 0.4 second debounce stops a double click landing on
the card that replaced the one you meant. The queue is rebuilt on every press
rather than advanced, because bags move under an open window.

None of this can know about repeatable quests, which never flag as completed, or
about a chain dropping part three's item while you are on part one. That is why
it asks instead of acting, and the panel tab says so above the button.

### Gates

`Comfort/Vendor.lua` names both of its ticker functions in check.sh's `HOT`
list, so the sweep is held to the same no-unguarded-writes, no-allocation rule
as the other four tickers. The harness gained a merchant, a corpse, a quest log,
a model of Questie, a cursor and two more bags, and asserts the negative cases:
a sweep that loses its window moves nothing, master loot leaves the master
looter's slots alone, both settings unregister their events rather than branching
inside a handler the client still calls, a stale clutter card never reaches the
cursor, a cursor holding the wrong item is not deleted, a client with no delete
call refuses, and an empty Questie module is not taken for a working database.

Ten mutations were applied to check those assertions bite, and one did not. The
"slot moved under the card" test was being caught by the cursor check rather than
by the slot re-read it claimed to cover, so both guards passed with the first one
deleted. The harness counts pickups now, which separates them: a stale card that
reaches a pickup means the first guard is gone even though the second one held.

The rail order had two parts sharing `order = 8`, which left `table.sort` to
decide between them. Perf and EditMode now have their own.

### The target's gauge, and the row of icons in it

Two bugs on the target frame, both of them the fit from 1.6 meeting something
the client measures off the frame's rectangle.

**The colour.** The target's health bar drew at 28 percent of its own colour at
any health, which on a tan warrior is the grey-brown of a corpse. The spent
track was a texture on our rail, one frame level under Blizzard's bar, and 1.6
had already written that level explicitly after the same bug appeared once
before. Both clients took the write. The target frame did not keep it: its
rails came out level with its bars, a tie goes to whichever frame was built
later, which is ours, and a 20 percent track at nine tenths alpha over the fill
is 28 percent. The player frame, one line of the same code away, was correct.

So the order is no longer between two frames. The spent track and the heal
slice are regions of Blizzard's own bar now, on the two lowest BACKGROUND
sublevels, and the fill is on ARTWORK above both. Inside one frame the layer
decides and there is nothing for a client to disagree with. Nothing else moved:
the rails still carry the geometry, the bars are still pinned to them corner to
corner, and the heal slice is still pinned to the fill texture, one boundary
crossing further out because its width is now written in the bar's units.

**The aura row.** The client hangs the target's buffs and debuffs off the
frame's bottom left corner and lifts the first icon of each row by the height
of the art that hangs under the bars on a frame 100 units tall. Fitting the
frame to the block took that art away and the lift then put the icons inside
the gauge.

The icons are not moved, and that is the design rather than a shortcut. Every
one of them is a child of a secure unit button, so an addon may only anchor one
out of combat, and the client re-anchors the head of each row on every aura the
target gains or loses. A row placed by this addon would be back in the gauge on
the first refresh of the first pull and stay there until it ended.

What moves is the edge the client measures from. The target frame is fitted to
the block plus the lift, so its bottom edge sits one lift below the block and
the client's own arithmetic lands the row against the block's bottom. It holds
in combat because nothing has to be written in combat. The lift itself is
measured rather than assumed: both clients keep it in a local, but the anchor
the client wrote on the icon carries the number, so the first target with an
aura settles it and a `UNIT_AURA` on the target is what catches that moment.
Until then there is no tail and the frame is the block, and a client that hangs
its row below the frame rather than above it measures as no lift and gets no
tail either.

A tail is a strip of frame under the block and a strip of frame takes clicks,
so `SetHitRectInsets` pulls the mouse region back off it, the Edit Mode
selection is pinned to the block rather than to the frame, and target of target
parks under the block rather than under the frame. What you can click and what
you can drag are still the thing you can see. `/wk skin probe` prints the lift
and says so when it has not measured one yet, and the insets go back with the
frame's size when the skin comes off.

### Gates for both

The harness stub now records a texture's draw layer and sublevel, which it
dropped before, so the ordering that decides what the gauge looks like is
asserted rather than assumed: the track and the slice are regions of the bar,
and the three layers run track, slice, fill. The old assertion compared two
frame levels, which is exactly the number the addon asked for rather than the
one that reached the screen, and it passed while the target was drawing at 28
percent.

The stub also stands up the head of each aura row, anchored the way the client
anchors it, and models hit rect insets and `RegisterUnitEvent`. Four things are
asserted from that: the frame carries no tail before an aura has been seen, it
is the block plus the client's lift afterwards, the addon has not touched the
anchors on either row head, and the mouse region stops at the block. Both
halves were checked by breaking the code and watching them fail.


## 1.6

### A performance tab

`/wk` has a Performance page, and `/wk perf` prints the same thing to chat.

The four tickers time themselves with `debugprofilestop`, two clock reads
bracketing each tick body. Each one reports per tick, which is the spike you
feel, and per second, which is the share of a 60 fps frame it actually takes,
plus the worst single tick since the counters were cleared. A part can register
a gauge beside its timing, because 0.31 ms means one thing at two nameplates and
another at fifteen, and the enemy bars register their own count.

Memory is the expensive half and it runs on a fifth ticker that exists only
while the tab is on screen. `UpdateAddOnMemoryUsage` walks every addon the
client has loaded, so sampling it on a ticker that never stops would make the
file measuring the cost the most expensive thing in the addon. The tab's row
starts it on `OnShow` and stops it on `OnHide`.

Two limits are written into the tab itself rather than buried here. The client
attributes Lua allocation and nothing else, so frames and textures never appear
in the figure and it should be read as churn rather than size. And per addon CPU
needs the `scriptProfile` CVar plus a reload and slows the whole client;
TitanPerformance owns that setting in this install, so the tab reads the number
where someone else has turned it on and never turns it on itself.

The tab accounts for itself. Its own sampling cost is a row in it, measured the
same way as everything else.

The harness proves the measurement is free rather than claiming it. Its clock is
stubbed before the addon loads, so every allocation figure it already gates on
was taken with the brackets live, and the bars still measure 0.17 KB per fifty
ticks. It also asserts that the counters move, that switching timing off stops
them accumulating rather than merely zeroing them, and that the sampler runs
only between `Watch(true)` and `Watch(false)`.


Weapon loadouts, one key each.

A loadout is a name, a pair of weapons, an optional stance and a key. A press
puts you in the stance and puts that pair in your hands, off one hardware event,
out of one macro:

    /cast [nostance:2] Defensive Stance
    /equipslot 16 Bloodspiller
    /equipslot 17 Aegis of the Blood God

Three are made for you, one per stance, because stance dancing is what this
started as and a warrior wants those three whatever else they want. Nothing in
the code treats them as special. They are rows in the same list as anything you
add, they can be renamed, unbound from their stance and deleted, and a loadout
with no stance at all is a weapon set with a key on it. Ten is the cap, one
secure button each, and the seed runs once rather than every login, so deleting
Berserker does not bring it back.

Nothing in the part calls `EquipItemByName`. Equipping during a fight is
something ordinary Lua may not do, and an `/equipslot` line off a key press is
the path that is allowed to, so every loadout is a secure button carrying
`macrotext`, the shape `Targeting/Switch.lua` already had.

The macro is written out of combat and never on the press. Every decision a
press makes is a macro conditional, which is what lets a key work in a fight at
all. Changing a loadout mid fight is the one thing that waits, and it waits
until PLAYER_REGEN_ENABLED rather than being lost. Every button is rewritten on
every apply rather than the one that moved, because deleting a row shifts every
row under it onto a different button and a partial pass would leave a key bound
to somebody else's macro. Both are asserted.

The main hand line is written before the off hand line, and the order is the
feature. Going from a two hander to a one hander and a shield, the first line is
what frees the hand the second one needs. A two hander in the main hand takes the
off hand line out of the macro entirely, because an `/equipslot 17` under one
would take the two hander back off. A blank hand means leave it alone: there is
no `/equipslot` for an empty hand, so a loadout cannot strip a shield, and the
panel says so rather than leaving you to work it out.

Swaps fire in combat by default, swing timer reset and all, because that is most
of the point. `loadout combat off` puts a `nocombat` conditional on every equip
line and leaves the stance change alone.

The page is a paperdoll. Blizzard's own model of your character sits in the
addon's own box with a gear square per hand under it, wearing Blizzard's
empty-slot art and Blizzard's slot ring, which is the layout the client's own
character sheet uses. Under that is the loadout strip, one button per loadout
and a `+` at the end, in the place Blizzard puts its own tabs. You drag a weapon
or a shield onto a hand and right click a hand to clear it.

Four widgets are new in the UI layer and none of them knows what a setting is: a
gear square, the paperdoll built out of two of them, a pooled tab strip, and a
line of text you type. The loadout strip is a control rather than the window's
own tab strip on purpose. The window's strip is chrome, built once at login out
of the headers each feature writes, and it cannot grow; a loadout list changes
while the window is open. That is why no rebuild path had to be cut into
`Core/Panel.lua`, and why adding a loadout costs no frames after the first time.

A name typed by hand builds an `/equipslot` line that silently does nothing, so
the panel offers no text field for one. `Core/Gear.lua` is `Charge/Weapons.lua`
promoted to the shared layer: one hand was one part's private knowledge, two
hands is not. It offers what you are carrying and nothing else, and a saved name
that is not on this character keeps its slot and goes orange rather than being
dropped by a panel that cannot see into your bank. `Core/Stance.lua` is the same
move for the three stance spells and their localised names, which the charge
macro and the loadout macros both bake in and could otherwise disagree about.

The harness grew a client to test against. Secure attributes are stored rather
than swallowed, so a macro can be read back; the override binding layer is
modelled, so the readback every part does after taking a key is answering
something rather than reporting a refusal; and there are three items in the
stub's backpack, so the gear scan has something to find. Sixteen assertions on
the macros: the lines, their order, the two rules that drop a line, the combat
conditional, the refused second claim on one key, the delete that has to move
every binding under it, and the loadout changed in combat that has to land after
it.

What the harness cannot settle, and only a key press in game can: whether the
client runs two `/equipslot` lines off one press, and what it does when a two
hander comes off into a full bag. Nothing installed on either client calls
`/equipslot`, so there is nothing to read that would answer either.


### Incoming heals on the skinned frames

The health gauge on the player, target and target of target frames now shows
what is already in the air. A pale green slice runs from where the fill stops to
where the heals in flight will take that unit. `/wk skin heals off` drops it, and
there is a checkbox on the same page.

It is clamped to what the unit is missing. A 2,000 heal on a warrior who is down
300 draws 300, because a slice that runs past the end of the bar is lying about
both numbers. The slice is drawn on our rail, two frame levels under Blizzard's
health bar, which clamps it a second time and for free: when the heal lands, the
fill draws straight over the prediction.

Where it starts is Blizzard's answer rather than ours. The slice is pinned to
the health bar's own fill texture, so its inner edge is exactly where the bar
stops whichever end the client fills from, and it stands as tall as the bar
without this file knowing how tall the bar is. The width is ours and is a whole
number of pixels, like everything else the skin draws.

`UnitGetIncomingHeals` is a real API on both clients. Both binaries register it
and both fire `UNIT_HEAL_PREDICTION`, so there is no LibHealComm here and
nothing parses anyone else's casts. It is probed the way the threat API is:
`ns.HasHealPrediction` answers, a client without it draws nothing, and
`/wk status` says which of those two things is happening.

The gates moved with it. `HealSlice` is in `HOT`, so the scan holds every write
in it to a guard, and it guards on the span it last drew rather than on the heal,
which means a fight where nothing is healing costs three comparisons a tick and
no widget writes. The harness stubs the API and drives three states through the
tick: nothing on the way draws nothing, 1,800 of 9,000 draws 33 pixels of a 167
pixel gauge, and a heal far past what the unit is missing draws the 89 pixels it
is down and stops there.


### The skinned frames are the size Edit Mode thinks they are

The block the skin draws used to hang off Blizzard's portrait anchor inside a
frame five times its size. Everything that reads a unit frame's rectangle read
that one. Edit Mode selected it, snapped it against the other frames and saved
it, while the thing you can see sat somewhere inside it, and the empty three
quarters went on eating clicks. Lining the player frame up with anything was
guesswork.

So the block is anchored to the frame's own top corner now, the one the
portrait is on, and `PlayerFrame`, `TargetFrame` and `TargetFrameToT` are each
resized to the block over them. On this monitor the player frame goes from 232
by 100 of Blizzard's units to 165.74 by 27.90, which is the 202 by 34 pixels
the block already was. What Edit Mode drags is what is drawn, the hit region is
the block, and the target's aura row follows the frame in rather than hanging
where a 232 by 100 frame left it.

Three things carry the resize. The original size is recorded before the first
fit and `/wk skin off` writes it back without a reload. `SetSize` on a secure
unit button is a protected action, so it sits behind the same lockdown guard as
the rest of `Place` and finishes at `PLAYER_REGEN_ENABLED`. And target of
target is placed by this addon once the target frame is fitted, three pixels
under the target block on the edge the two share, because Blizzard's anchor for
it was written against a target frame 100 units tall and points at a corner
that has moved. It goes back to that anchor the moment either frame is
unskinned.

Edit Mode draws a selection frame over the system it is dragging. Where this
client puts one, the skin pins it to the frame and post-hooks that frame's own
`AnchorSelectionFrame`, so the next time Edit Mode re-anchors it, it is pinned
again. Both names are retail's and both are probed before they are touched. A
client with neither still gets the fit, which is what Edit Mode draws over by
default. `/wk skin probe` says which of the two this client is, and prints what
each frame measured before the fit.

Two clamps went with it. The gauge was clamped to what was left of the frame's
width and the square to the frame's height, both because the space around the
block was not empty. The frame is the block now, so the two settings are the
whole of the size and there is nothing left to clamp against.

The harness asserts the fit in screen space, which is the only space the block
and the unit frame share: one is on the pixel grid and the other is on the
client's scale, so a comparison of the raw numbers would pass on a fit that
never converted. Each frame covers exactly the piece of screen its block does,
target of target is parked under the target block, and turning the skin off
hands all three frames back the size they were built at and target of target
back its own anchor.


## 1.5

A drawing layer, `UI/`, and everything the addon draws rebuilt on it. Eight
files: a pixel grid, a drawing kit, and a widget library.

### The pixel grid

`ns.Pixel` computed one screen pixel as `1 / scale`, which is the right answer
only on a screen 768 pixels tall. On a 1440 tall screen at UI scale 0.65 it
asked for 1.88 pixels wherever it meant one, so every border in the addon was a
smear. Frames go through `UI.Adopt` now, which takes them off their parent's
scale and puts them at `768 / screenHeight`, where one unit is one physical
pixel and every size in a layout is a whole number written as a whole number.

Sizes are absolute pixels as a result. The same setting draws the same physical
size on any monitor, which is the point, and `bars zoom` is the lever for a
screen where that is too small. Zoom is a whole number because a fractional one
would put every edge back on a half pixel.

A resolution change re-scales every adopted frame. One the client refuses
because a protected frame is in lockdown is deferred to
`PLAYER_REGEN_ENABLED`.

### Enemy bars

- Icons are cropped on a texel boundary, `5/64` rather than `0.08`, and the
  client's own texture snapping is turned off on them, which is what was
  softening the art. Text moved to Arial Narrow, shared as one font object per
  size rather than a private copy per font string.
- **Which bar is yours.** Your target sits at full alpha and every other bar at
  0.55, and with nothing targeted they all go bright again. `SetIgnoreParentAlpha`
  throws away the client's own dimming, deliberately, because plate alpha also
  fades with distance and there is no plate at all in list mode. The only signal
  before this was the name text turning from white to cream.
- Bars no longer land on top of each other when two mobs stand together. That
  was never a drawing bug: Blizzard's driver spaces plates by how big it thinks
  a plate is, and it thinks a plate is Blizzard's nameplate. `bars stack` tells
  it the real figure and asks it to stack rather than overlap, and hands both
  client settings back when you turn it off.
- A bar on a plate is `bars width` pixels, the same figure the list uses. It was
  the width of the plate under it, and that was a loop with no fixed point: the
  bar measured the plate, the driver sized the plate to the bar, and the next
  bar measured a plate that had changed. Which way it ran depended on the scale
  the client puts on a nameplate against the scale it puts on UIParent.
- The list collector stopped allocating. It was building a table for the list,
  one per mob in it and two closures every fifth of a second. At two bars over
  fifty ticks, 51.76 KB before and 0.17 KB after.

### Player, target and target of target

- The three frames the skin creates per unit frame are adopted onto the grid.
  Blizzard's portrait, status bars and state icons are not and cannot be: they
  are regions of a secure unit button. Every number crossing that line is
  converted and snapped in the direction it is crossing.
- Both gauges are pinned corner to corner onto rails the addon owns rather than
  given a height, so a bar's four corners are whole pixels without the bar
  leaving Blizzard's scale.
- The power bar was 11.63 physical pixels tall and is 10. The two text baselines
  were at -14.41 and -34.63 and are at -11 and -28. The state icons were 22.79
  and 29.84 pixels square and are 18 and 24, both even so that centring one on a
  corner keeps its edges on pixel boundaries.
- The block's anchor offsets were read off Blizzard's portrait anchor and used
  unconverted, which put the block out by the ratio between the two scales.
- The portrait and all four state icons take the sampling fix, crop on a texel
  boundary at `10/64` instead of `0.15`. `/wk skin off` hands snapping back.
- The level tag was built and then compared, so the guard never saved the
  building: 18.75 KB per fifty ticks across three frames, down to 0.00. The bar
  fill and the portrait crop read back before writing: 300 texture writes and
  150 crop writes per fifty ticks, down to zero.
- `skin height` and `skin width` are counts of screen pixels now rather than UI
  units, so **the frames will visibly shrink on first reload**. The ranges
  widened to 18-72 and 90-360; height 42 and width 246 restore the old size.

### The options window, rebuilt on a widget library

`UI/` grew `Theme.lua`, `Stack.lua`, `Scroll.lua`, `Widgets.lua` and
`Window.lua`. `Core/Panel.lua` went from 884 lines to 354 and now owns only
which parts exist and where their sections go.

- **Tabs.** There was never a tab strip. What the old file called a tab was the
  rail button, so choosing a part could not reveal anything. Every `ui.Header` a
  feature writes is now a tab within that part's page, which is twelve tabs
  across seven parts and four on Charge alone.
- **Text no longer overflows.** Every row measures itself, and the stack sets a
  row's width before it asks its height. The old layout did those two the other
  way round, so the one row that measured measured against the previous pass.
- **The window is smaller and it stays put.** 544 by 452 physical pixels, fixed.
  It was 486 by 634 units, which at a 0.65 UI scale is 592 by 773 pixels of a
  1440 pixel screen, and it grew every time a note wrapped and then scaled itself
  down when that overflowed.
- **It scrolls**, with a bar that shows position and drags, and a wheel handler.
  The bar hides entirely when the content fits.
- **No new ticker.** The scrollbar is a `Slider` frame type rather than a thumb
  the addon follows with an `OnUpdate`.
- The seven `panel = function(ui)` builders were not touched. Every widget name
  takes the arguments it always took.

### Gates

`check.sh` bans allocation on ticker paths the way it already banned unguarded
writes, and it runs `scripts/harness.lua`, which loads the addon against a stub
of the client and drives it. The harness asserts the grid arithmetic, whole
pixel geometry on every frame the addon owns, the texel-boundary crops, the
plate footprint, the four target-alpha states, a resolution change that lands in
combat, and every row of every tab of every page of the options window. Three
allocation ratchets sit just above their measured figures.

Two of those gates found real defects on their first run: a 20 Hz nameplate scan
in `Charge.PlateFor` that could never succeed on either target client, and the
level tag being built before it was compared.

## 1.4

One key that takes the next enemy and swings at it, bound in `/wk` under
Targeting or with `/wk switch <key>`. TAB cycles targets and leaves the new mob
standing there, so switching mid-fight cost a second press. The key is a secure
button carrying `/targetenemy` and `/startattack`, held as an override binding,
so putting it on TAB leaves your saved bindings alone.

## 1.3

Moved the addon into a repo of its own, outside the game tree, with both
clients linked into `src/`.
