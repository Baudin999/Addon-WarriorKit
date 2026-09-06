-- The order everything happens in.
--
-- Stand the client up, load the addon over it in TOC order, put Blizzard's own
-- frames in front of it, fire the three login events, then run every section
-- under ./sections against the result.
--
-- The section list at the foot of this file is the run order and it is load
-- bearing. Sections leave state behind on purpose: a measurement taken in one
-- is compared in a later one, the skin is fitted in one and taken off again
-- three down, and 27-swing-visible ends by putting the client back the way the
-- sections after it expect it. Reordering that list is a change to what is
-- being tested. Everything one section hands to a later one goes through
-- H.carry and is named at both ends.

local ROOT, PLAYER_CLASS, load, only, PLAYER_SPEC = ...

local H = load("client/init.lua")(PLAYER_CLASS, load)
local ns = {}
H.ns, H.carry = ns, {}

local order = {}
for line in io.lines(ROOT .. "/WarriorKit.toc") do
	line = line:gsub("\r", ""):gsub("\\", "/")
	if line:match("^[A-Za-z].*%.lua$") then
		order[#order + 1] = line
	end
end
for _, path in ipairs(order) do
	H.loading.file = path
	assert(loadfile(ROOT .. "/" .. path))("WarriorKit", ns)
	H.loading.file = "runtime"
end
H.order = order

-- Over a copy of the list, not the list.
--
-- Several parts unregister ADDON_LOADED from inside their own handler for it,
-- which is what the client asks you to do and is what Core does first of all.
-- Removing an entry from the list this is walking shifts every frame after it
-- down by one, so ipairs skipped whichever frame was next, and the part that
-- got skipped depended on the order the TOC happened to load them in. The chat
-- part registered its events in that handler and did not get one, which is a
-- feature that would have worked in the game and failed here.
local events = H.events
local function fire(event, ...)
	-- What the client's unit watch does before any Lua hears about it: a
	-- secure frame watching a unit is shown or hidden as the unit comes and
	-- goes. Modelled in 03-player.lua and run here on the two events that say
	-- a unit changed, so a section that changes a target and fires the event
	-- sees the frame move the way the game moves it.
	if H.unitWatch and (event == "PLAYER_TARGET_CHANGED" or event == "UNIT_TARGET") then
		H.unitWatch()
	end
	local list = events[event]
	if not list then
		return
	end
	local watching = {}
	for index = 1, #list do
		watching[index] = list[index]
	end
	for _, f in ipairs(watching) do
		if f.scripts.OnEvent then
			f.scripts.OnEvent(f, event, ...)
		end
	end
end
H.fire = fire

load("client/08-blizzard.lua")(H)

_G.WarriorKitDB, _G.WarriorKitCharDB = {}, {}
fire("ADDON_LOADED", "WarriorKit")

--------------------------------------------------------------------------
-- Coming up as one spec
--
-- Before login, because the spec decides what is built and Class/Spec.lua
-- latches the first answer that is not nil. Named on the command line and read
-- back off the registry rather than written out here, so a class file that adds
-- a fourth spec is covered the moment check.sh reads the file.
--
-- Both readings the resolver uses are driven, because a spec is named by
-- whichever answers first and the two do not agree on their own. The signature
-- spells of every other spec are made unknown, so no spec but the wanted one
-- can be signed for; the wanted spec's tree is given every point, so the
-- fallback lands on it for the specs that carry no signature at all. A warrior
-- with Death Wish is fury whatever his trees say, and priest holy has nothing
-- to be signed for and is answered by its tree alone.
--
-- The run is refused rather than allowed to drift. A spec the addon then reads
-- differently is a broken resolver reported as a hundred wrong measurements.
--------------------------------------------------------------------------
if PLAYER_SPEC then
	local def = ns.Class.All()[PLAYER_CLASS]
	assert(def and def.specs, PLAYER_CLASS .. " registered no specs")

	local wanted
	for _, spec in ipairs(def.specs) do
		if spec.key == PLAYER_SPEC then
			wanted = spec
		else
			for _, id in ipairs(spec.signature or {}) do
				H.own.unknown[id] = true
			end
		end
	end
	assert(wanted, ("%s has no spec called %s"):format(PLAYER_CLASS, PLAYER_SPEC))

	for index, tree in ipairs(H.talentTrees.player) do
		tree.points = (index == wanted.tree) and 41 or 0
	end
	ns.Unit.Spec.Forget()
end

-- The whole run is at the design size, whatever size the addon ships at.
--
-- Everything the addon draws in a window is a design number multiplied by the
-- pixel of the frame it is in, and the sections below assert on those numbers:
-- a row is a whole number of pixels tall, a hairline is one pixel, an anchor
-- offset is not half of one. At a stop that is not a whole number none of that
-- is true, and Settings/Settings.lua is explicit that it is not meant to be: a
-- screen is allowed to go soft, that is the price a tenth charges, and
-- Settings.Grid names the stops that pay it.
--
-- So the size is set before the first window is built rather than moved
-- afterwards, because a window carries the pixel it was built at in the anchors
-- of its own chrome. Section 17 is where the stops themselves are walked.
--
-- Every screen, off the registry rather than by name. There was one number for
-- all of them and one call here; each screen carries its own now, and a walk is
-- what keeps this line covering a part that registers a screen tomorrow.
for _, zoom in ipairs(ns.Zooms()) do
	ns.db[zoom.key] = 1
	if zoom.apply then
		zoom.apply()
	end
end
ns.UI.Notify()

fire("PLAYER_LOGIN")
fire("PLAYER_ENTERING_WORLD")

if PLAYER_SPEC then
	assert(ns.Class.Spec.Token() == PLAYER_SPEC,
		("the run asked for %s and the addon reads %s")
			:format(PLAYER_SPEC, tostring(ns.Class.Spec.Token())))
end

-- What login built, read here because this is the only moment that can see it.
--
-- Most of the addon's construction waits for the first open now, and every
-- section below opens something: a count taken inside one of them is a count of
-- what that section did. Four readings, each the cheapest honest probe for one
-- thing that used to happen at login and no longer does, and the sections that
-- care read them out of H.login rather than taking them again.
H.login = {
	frames = #H.frames,
	models = H.models.loaded,
	book = H.spellbook.reads,
	durability = H.gear.durability,
}

print(("login  %d frames, %d spell book entries read, %d gear slots read, %d models loaded")
	:format(H.login.frames, H.login.book, H.login.durability, H.login.models))

-- The tooltip's linger, run out.
--
-- Leaving a hoverable thing starts a countdown rather than taking the box down,
-- because a box that vanishes on the frame you cross a row is a box you cannot
-- read. Every section that used to assert "the tooltip is gone after OnLeave"
-- has to run that countdown down first, and it goes through one helper rather
-- than a Sweep call per section so that what a section is saying stays "the
-- pointer left and the box went" rather than a number of seconds.
--
-- The whole of the range, so no section carries a number that has to change
-- when the shipped linger does.
function H.tipSettle()
	local _, longest = ns.UI.Tooltip.LingerRange()
	ns.UI.Tooltip.Sweep(longest + 1)
	return ns.UI.Tooltip.IsShown()
end

-- The hand, held still on a piece of chrome until its box opens. A tab, a chip
-- or a hint waits ns.Tip.HOLD for the pointer to stop, and a section that
-- hovers one and reads the box has to let that wait run out. The whole hold
-- and a frame more, so no section carries the number.
function H.tipHold()
	ns.Tip.Settling(ns.Tip.HOLD + 0.1)
	return ns.UI.Tooltip.IsShown()
end

-- One part's tick, by the ns.Perf slot it is timed under.
--
-- Every ticker that never stops hangs off ns.UI.Forever now, because the client
-- makes a Lua call per frame for every frame carrying an OnUpdate and there
-- were eighteen of them. A section used to reach its own part's tick by walking
-- H.frames for a frame from that file with a script on it and calling that
-- script; those frames carry no script any more, and the one they share carries
-- every part of the addon, so driving it would run twenty parts where a section
-- means to run one.
--
-- What comes back is the tick itself and a section beats it: tick:Beat(delta)
-- is one frame of the client, exactly what calling the frame's OnUpdate was.
-- This does not hand back a function that drives it, and that is deliberate. A
-- churn measurement runs its tick two hundred times between two readings of
-- collectgarbage("count") with the collector stopped, and one more Lua call
-- between the loop and the tick deepens the stack enough that Lua grows it
-- again after every collect: six tenths of a kilobyte, attributed to whichever
-- part is being measured. Beat the tick from the loop itself.
function H.tick(name)
	local tick = ns.UI.Ticking(name)
	assert(tick, ("no ticker called %s is running"):format(name))
	return tick
end

local failures = 0
function H.check(ok, message)
	if not ok then
		failures = failures + 1
		print("  FAIL " .. message)
	end
end

local SECTIONS = {
	-- First, and it is the only section that can answer for login: every one
	-- below it opens something. It reads H.login and asserts nothing else.
	"00-login",
	"01-unit-layer",
	"02-layout-engine",
	"03-gauge",
	"04-ability-square",
	"04-aimed-square",
	"05-action-bars",
	-- Straight after it, and it reads the bars that section left standing: what
	-- a pass of their ticker costs, which is a different question from whether
	-- the squares are right.
	"05-bars-tick",
	"06-debuff-row",
	"07-tracked-debuff",
	"08-bars-zoom",
	"09-cast-row",
	"10-unit-frame-skin",
	"11-skin-rails",
	"12-debuff-square-size",
	"13-incoming-heal",
	"14-aura-row",
	"15-skin-fit",
	"16-options-window",
	"17-zoom-page",
	"18-which-bar",
	"19-resolution-change",
	"21-which-class",
	"22-chores",
	"23-minimap",
	"24-clutter-window",
	-- Above the three sections that read the combat log, because what it asks
	-- about is the reader in front of all of them.
	"24-combat-log",
	"25-meters",
	"26-swing-timer",
	"27-swing-visible",
	"28-cost",
	"29-social",
	"30-buff-nag",
	-- The row's page, which reads the state the row left: an orc with both hands
	-- bare, in a fight.
	"30-buff-page",
	"31-feeds",
	-- Straight under it, and it is UI/Feed.lua's rule rather than either feed's:
	-- a note the column cannot hold whole is not drawn at all. A file of its own
	-- because 31-feeds.lua is at the line ceiling every section shares. It turns
	-- the combat feed on and off the way that section does and puts both feeds'
	-- widths back, so what it hands on is the scene it was given.
	"31-feed-note",
	"32-breakdown",
	"33-anchors",
	"34-game-menu",
	"35-purse",
	"36-font-roles",
	"37-player-cast",
	"38-bar-look",
	"39-party-raid",
	-- Under it, because it stands a party of its own up and puts the roster back
	-- the way that section left it: empty.
	"39-party-told",
	"40-loot-feed",
	"41-voice",
	"42-cooldown-row",
	"43-blizzard-hide",
	"44-hover",
	"45-chat-keys",
	"46-mail",
	"47-quest-log",
	-- Straight under it, because it reads what that section leaves: the window
	-- on screen, the log three quests short of what it started with, and the
	-- footer button driven once per quest. It puts five rows into the log and
	-- takes them out again, and it ends with nothing pinned.
	"47-quest-pin",
	-- Under it, and it leaves Questie ready for good. Everything above this
	-- line runs against a Questie whose database has not finished compiling,
	-- which is the state a login is in and the one worth testing the addon in;
	-- nothing below reads the flag.
	"47-questie-api",
	-- Last, and it registers a source of its own that stays registered. A
	-- section after this one would be reading tooltips with the harness's own
	-- line hooked into them.
	-- Which key presses the thing under the cursor, on an item's box and on a
	-- square's. Before 48-tooltips, which is the last section that may read a
	-- tooltip without the harness's own line in it.
	"48-key-line",
	"48-tooltips",
	-- Straight after it and for the same reason it is late: this registers a
	-- source of its own that stays registered too. Its line answers only a note
	-- carrying a `stamped` field and nothing below writes one, and its stamp
	-- answers the same number for every other note, so what the sections under
	-- here inherit is a tick that arms on a note hover and rebuilds nothing.
	"48-tooltip-fresh",
	"49-world-hover",
	-- After 48-tooltips, which is fine and is worth saying why: what that
	-- section leaves registered is a source that answers only a subject
	-- carrying its own probe field, and nothing here carries one.
	"50-experience-rails",
	-- It moves the addon's lock and puts it back, so it wants everything above
	-- it built and nothing above it disturbed. Second to last for that reason.
	"51-placing",
	-- It takes Blizzard's character sheet out of the attic and puts it back, and
	-- it moves the weapon skill the whole miss calculation is built on. Both are
	-- scene changes, so it goes under everything that reads either: the hide
	-- section three dozen lines above, and the placing walk directly over it,
	-- which counts this window among the six it holds to the lock.
	-- Before it, and that is the whole of why it is a file of its own rather
	-- than a block in it. The first thing it asserts is that the standings
	-- window does not exist, and 52-character reaches that window through the
	-- client's own reputation page name a hundred lines in.
	"52-standings",
	"52-character",
	-- Straight after it, and it was a block in the middle of it. The numbers on
	-- the stats column are arithmetic against three published figures rather than
	-- a reading of the window, and nothing that file does after the block ran
	-- moves one of them: it puts the weapon skill, the off hand and the ratings
	-- back where it found them, and so does this. A file of its own because it is
	-- a second subject and because 52-character.lua was over its own line ceiling
	-- carrying both.
	"52-stats-page",
	-- Straight after it, and it opens the sheet itself. What the gear page draws
	-- is a bigger subject than the rest of that window and it grew past the line
	-- ceiling the section was already exempted from, so it is a file: the split
	-- gave 52-character's exemption back rather than raising it.
	"52-gear-page",
	-- After both of them, and it is the window rather than the page: the wash
	-- UI/Window.lua lays over a screen window's own half of the monitor. It was
	-- a block at the foot of the gear page and took that file over the line
	-- ceiling, which is what noticed that it was in the wrong one.
	--
	-- Under 52-character rather than over it, because that section's first
	-- assertion is that nothing has opened the sheet yet and this one opens it.
	-- It shuts it again, and it puts the setting it turns off back, so what the
	-- reset below inherits is the scene the addon ships with.
	"52-screen-dark",
	-- Straight after the wash, because it is the same question about the same
	-- window from the other side: the wash owns the world behind the sheet and
	-- this owns the addon's own rectangles in front of it. It opens the sheet the
	-- way that section does and shuts it again, and it puts its own setting back,
	-- so the reset below still inherits the scene the addon ships with.
	"52-screen-hush",
	-- Under those, and it opens the same sheet again. What it reads is the one
	-- thing on a gear square that moves while nobody touches it: the arc a slot
	-- you press draws while its cooldown runs. It puts a trinket on cooldown,
	-- runs the wait down, takes the trinket off and puts it back, so the scene
	-- it hands on is the one it was given. A file of its own because
	-- 52-gear-page.lua is at its own line ceiling and this is a subject rather
	-- than a block: two halves, two masks and a tick that has to stop.
	--
	-- Over the enchant section rather than under it, because this one reads the
	-- character client/13-character.lua dressed and that one is the section that
	-- redresses him.
	"52-trinket-sweep",
	-- Last of the sheet's sections, because it dresses the character in
	-- enchanted pieces and puts a stone on a hand. Every assertion above reads
	-- a character wearing what client/13-character.lua put on, so a scene that
	-- changes what is in four slots goes below all of them and puts it back.
	"52-gear-enchant",
	-- Last, and it has to be: it puts every setting in the account file back
	-- to what the addon ships with, twice over, which is the one thing in the
	-- suite that would pull the scene out from under every section above it.
	"53-shipped-defaults",
	-- Under the reset, which is not the exception to the line above it that it
	-- looks like. What that section pulls out from under everything is the
	-- settings, and the two this one needs are the two the addon ships with, so
	-- a scene freshly reset to them is exactly the scene it wants. It reads
	-- nothing any earlier section left behind and it is the last word on where
	-- you are standing, which it moves into a zone the map tree holds.
	"54-world-map",
	-- Last, and it is the only section in the suite that puts a free slot in
	-- the bags. Every other one is written against a character carrying a full
	-- set, because a hole in a bag moves the numbers the vendor sweep and the
	-- clutter queue count, so the empty bag goes in here and comes out again at
	-- the foot of the file.
	"55-bags",
	-- Last. It walks the map tree again for dungeons, puts you inside one, and
	-- opens a loot window over a boss corpse, which is the one loot window in
	-- the suite that says which corpse a slot came out of. It takes that away
	-- again and puts you back where 54-world-map.lua left you standing.
	"56-dungeon-log",
	-- Last. It is the only section that stands you in front of a vendor with
	-- the full rack up, and it parks the client's own merchant window and takes
	-- it back again. It ends with the purse it found and no merchant open.
	"57-merchant",
	"58-spec",
	"59-chat-history",
	-- Straight after it, because it reads the rail that section wiped clean
	-- and closes conversations of its own making. What it asks is the four
	-- things the window grew after the history did: a picture size, a way to
	-- close a conversation, a box to copy a room out of, and a room for what
	-- the addon says.
	"59-chat-rooms",

	-- Last, and not about a feature. It drives one word of each kind the
	-- slash runner parses and reads the setting back, which is a question
	-- about ns.Command.Word rather than about any of the parts above.
	"60-slash-words",

	-- Last, and after 55-bags.lua for the reason every section in that pair
	-- runs in order: it changes what is in the trash bag under a running
	-- session and puts it back. It also stands up GetZoneText, which no client
	-- stub provides, and takes it down again.
	"61-bag-session",

	-- Last, and after 55-bags.lua and 61-bag-session.lua both, because it puts
	-- that scene back to draw the bag window one more time. It is the only
	-- section that seeds the client's binding line, and it leaves the seed
	-- behind: nothing after it reads a tooltip off a bag slot.
	"62-bag-lanes",

	-- Last, and after 54-world-map.lua, whose window it opens again and whose
	-- fixtures it reads. It is the only section that makes Questie draw
	-- something rather than reading what Questie drew, and it puts every
	-- place it switched back the way it found it.
	"63-map-places",
	"64-console",
	"65-bag-piles",
	"66-bag-drop",
	"67-talents",
	"68-spellbook",

	-- Last, and it is the only section that stands a corpse up other than the
	-- four slots 22-chores.lua counts. It swaps one in with a slot per rule the
	-- loot filter has, drives every rule over it, and puts those four back at
	-- the foot of the file. It also installs a stand-in for Comfort/Reagents.lua
	-- for two passes and takes it away again, because what the filter has to do
	-- when that part is missing is half of what it promises.
	"69-loot-filter",
	-- Last, and it is the only section that opens a profession window. It
	-- reads what no section above it has touched, a list that is empty until
	-- this one fills it, and it ends by emptying it again and shutting both
	-- windows, so nothing after it would find a scene it did not expect.
	"70-reagents",
	-- The only section that takes every bag off the character and hands back
	-- its own. What it measures is where one looted item landed and how much
	-- of the stack it landed in came out again, and a bag of the fixtures' own
	-- holding a second stack of the same cloth would answer that question for
	-- it. The character's bags go back at the foot of the file.
	"71-leftovers",
	-- The charge button's pick, by stance and by what is trained. It moves
	-- combat, the stance, the cursor and the book, and puts all four back.
	"72-charge-stance",
	-- What a square answers past its own cooldown: the ladder the cooldown
	-- row and the racial read through Buttons/Castable.lua, and which of the
	-- three Berserkings a troll gets. Moves the clock, the target, the race
	-- and what is affordable, and puts all four back.
	"73-castable",
	"74-bag-hold",
	-- Last, and after 55-bags.lua and 46-mail.lua both: it opens the mail
	-- window over a built bag window and right clicks the squares. The bag
	-- window is built once and 55-bags.lua asserts on that first build, which
	-- is why this cannot sit in the mail section where it was.
	"75-mail-bags",
	-- The bars you made yourself. It adds bars, takes keys and puts a spell
	-- on the cursor, and it deletes every bar and clears the cursor at the
	-- foot of the file, so nothing after it finds a key held or a scene it
	-- did not expect.
	"76-adhoc",
	-- Last, because it stubs four client calls and a CVar to arrange each of
	-- the four answers a dip can have, and puts all five back at the foot of
	-- the file. It also counts 250 events into the census and fires 300
	-- combat log lines, which is the loudest thing any section does and
	-- belongs nowhere near a section reading a frame.
	"77-frame-trace",
	-- After the frame trace rather than before it, which is the one place a
	-- section that reads frames can sit next to that one: it puts every call it
	-- stubbed back at the foot of its own file, and the row below is built at
	-- login and reads nothing it touched. It fills every totem slot and empties
	-- them again, so nothing after it would find a scene it did not expect.
	"78-standing-row",
	-- Last, and it has to be. It drains everything the loot sections left
	-- floating and then runs the animation tick out to nothing, which is a
	-- state no section above it expects to find and none below it would
	-- survive.
	"79-floating-messages",
	-- After it, which is the one place a section that drives an animation can
	-- sit beside that one. 79 runs the tween tick out to nothing and asserts it
	-- gave its OnUpdate back; this drives a different library on a different
	-- ticker, and it clears everything in the air at the head of the file
	-- because three sections above it fire combat log lines that this part has
	-- been reading since login.
	"80-floating-numbers",
	-- Under both of them, and it has to be. It drives a tween library on the
	-- gear page, and the sheet's other five sections all run above
	-- 79-floating-messages, which asserts that a dozen looted drops are still
	-- in the air and unticked: a beat of the animation tick from up there would
	-- expire them and read as that section's failure. Here the list is empty
	-- when it starts and empty when it hands over.
	"81-gear-arrival",
	-- Last, because it reads the state four sections above it left. It wants a
	-- quest in the log, a profession window that has been walked and a corpse in
	-- front of you at the same time, and 47, 69 and 70 are what put those three
	-- there. It hands every one of them back at the foot of the file the way they
	-- were handed over, so it can go on being last when the next one arrives.
	"82-need",
	-- Last, because it walks you round the map tree: it stands you in four
	-- zones and three dungeons, takes IsInInstance off the client and puts
	-- Questie away twice, and ends by asking what a client that will not say
	-- which map you are on answers. It puts every one of those back at the foot
	-- of the file, including where you were standing when it started.
	"83-quest-here",
	-- Straight after 83-quest-here, because it reads what that section leaves:
	-- the map you are standing on and the instance flag over it, both put back
	-- at the foot of that file. It drives one ticker by hand rather than through
	-- the frame, takes Questie away twice and breaks four of its names one at a
	-- time, and hands every one of them back before it prints.
	"84-quest-near",
	-- Last, because it takes Questie away three ways and reaches into that
	-- addon's own saved settings to do it. Everything above this line reads
	-- Questie; this is the one section that writes to it. It puts the global,
	-- the setting and both switches back at the foot of the file.
	"84-questie-tracker",
}

-- Naming a section runs every section up to and including it, rather than that
-- one on its own. A section reads what the ones above it left behind, so one
-- run in isolation is not a smaller version of the suite, it is a crash. The
-- prefix is the smallest run that can honestly answer for the section named.
local stop
if only then
	for index, section in ipairs(SECTIONS) do
		if section == only then
			stop = index
		end
	end
	if not stop then
		io.stderr:write(("harness: no section called %s\n"):format(only))
		os.exit(2)
	end
end

for index, section in ipairs(SECTIONS) do
	load("sections/" .. section .. ".lua")(H)
	if index == stop then
		break
	end
end

return failures
