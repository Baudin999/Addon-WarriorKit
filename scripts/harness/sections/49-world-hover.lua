-- The hover no frame in the addon owns
--
-- Every other section that touches a tooltip goes through the thing that opened
-- one: a feed row, a nag square, an action square, all of them frames this addon
-- drew and hung an OnEnter on. A creature in the 3D world is none of those. The
-- cursor is over WorldFrame, the client resolves the mouseover token, fills
-- GameTooltip and shows it, and there is no script in that sequence for an addon
-- to write. So this part is built the other way round and every claim in it is a
-- claim the sections above cannot make.
--
--   The unit kind. UI/Scan.lua points its hidden tooltip at a unit token and
--   reads back the name, the level tag and what the thing is. Those five lines
--   are localised and computed inside the game, and the addon has no other way
--   to word any of them.
--
--   The box with no owner. Everything else takes its position and its zoom from
--   the frame it opened on. This one has neither, so it follows the pointer,
--   picks its side the way a frame's tooltip picks one, and reads the cursor in
--   physical pixels through a UI scale that is not 1.
--
--   The suppression, which is the half with the sharp edge. GameTooltip is
--   shared with quest text, with a link somebody clicked in chat and with every
--   other addon installed, so it is held down only while ours is up and only
--   when it is about a unit. Both halves of that are asserted here, because
--   getting the second wrong is a linked item that silently says nothing.
--
--   The hook, from the other end. Meter/Standing.lua registers one line against
--   the unit kind and never learns that this part exists. That is the whole
--   claim ns.Tip.Source is for and it cannot be made from inside the part that
--   opens the box.

local H = ...
local ns, check, fire = H.ns, H.check, H.fire
local guids, unitName = H.guids, H.unitName
local state, tooltips, cursor = H.state, H.tooltips, H.cursor
local CHURN = H.CHURN

do
	local World, Box = ns.World, ns.UI.Tooltip
	local MOB = "Creature-0-0-0-0-1234-0000ab77"

	-- A hover, which is looking away and back rather than one event.
	--
	-- The addon turns away a second UPDATE_MOUSEOVER_UNIT about the creature its
	-- box is already open on, because the client fires that event again for a mob
	-- that moved and rebuilding the whole box is a unit scan, every band laid out
	-- and the suppression armed on top of the box it is already holding down.
	-- Every claim below is about a box that was built, so the section clears the
	-- token first, which is what the pointer leaving does. The refusal itself is
	-- asserted on its own further down, with the raw event.
	local raw = fire
	local function hover(event, ...)
		if event ~= "UPDATE_MOUSEOVER_UNIT" or not guids.mouseover then
			return raw(event, ...)
		end
		local was = guids.mouseover
		guids.mouseover = nil
		raw(event)
		guids.mouseover = was
		return raw(event)
	end
	fire = hover

	-- Every line of the box, left side only. Read off what was drawn rather
	-- than off Tip.Build, because the order things landed in on screen is the
	-- thing being asserted.
	local function drawn()
		local lines = {}
		for index = 1, Box.Lines() do
			lines[index] = Box.Text(index) or ""
		end
		return lines
	end

	-- One edge of the box in physical pixels, which is the unit
	-- GetCursorPosition answers in and the only unit the two can be compared in.
	-- The box is drawn inside a frame on the addon's own grid and the pointer is
	-- read off a screen at a UI scale of 0.65, so a comparison that skipped
	-- either scale would pass against a box anchored to the wrong number.
	local function edge(method)
		local frame = Box.Frame()
		return ns.Measure(frame, method) * frame:GetEffectiveScale()
	end

	-- The pointer in those same pixels. The client answers a y measured up from
	-- the bottom of the screen and every edge above is read from the top left
	-- corner, which is the one conversion in this file and is the same one
	-- UI/Tooltip.lua makes when it anchors the box to UIParent's bottom.
	local function pointer()
		local x, y = _G.GetCursorPosition()
		return x, y - _G.UIParent:GetHeight() * _G.UIParent:GetEffectiveScale()
	end

	-- The client's own words about a mob: the name, the level and rank tag, and
	-- what kind of thing it is. Three lines rather than five because what is
	-- asserted is that they arrive in order and land in the head band, and a
	-- faction and a guild would prove the same thing twice.
	tooltips.unit.mouseover = {
		{ "Snarlmouth" },
		{ "Level 62 Elite", "Beast" },
		{ "Silverpine Forest" },
	}
	unitName.mouseover = "Snarlmouth"

	------------------------------------------------------------------
	-- The scanner will answer about a unit
	------------------------------------------------------------------

	check(ns.UI.Scan.Ready("unit"),
		"the scanner will not take a unit, so a creature can only ever be described by its token")

	local read = ns.UI.Scan.Read("unit", "mouseover")
	check(type(read) == "table" and #read == 3,
		("the client's three lines about a mob came back as %s"):format(tostring(read and #read)))
	check(read[1][1] == "Snarlmouth",
		"the first line is not the name: " .. tostring(read[1][1]))
	check(read[2][5] == "Beast",
		"the right hand side of a scanned unit line was dropped: " .. tostring(read[2][5]))

	------------------------------------------------------------------
	-- Nothing under the cursor, nothing on screen
	--
	-- The event fires with the token already cleared as well as with one
	-- resolved, and a part that opened on both would put a box up about
	-- whatever the last mob was.
	------------------------------------------------------------------

	guids.mouseover = nil
	fire("UPDATE_MOUSEOVER_UNIT")
	check(not H.tipSettle(), "a mouseover event with no unit behind it opened a box anyway")
	check(not ns.UI.Scan.Suppressing(),
		"Blizzard's tooltip is being held down with nothing of ours on screen")

	------------------------------------------------------------------
	-- The hover itself
	------------------------------------------------------------------

	-- On somebody else, which is the answer that needs no roster: the mob is on
	-- the wrong person and how far behind you are does not change that.
	state.threatReader = function(source)
		if source ~= "player" then
			return nil
		end
		return false, 2, 62
	end

	guids.mouseover = MOB
	cursor.x, cursor.y = 300, 500
	fire("UPDATE_MOUSEOVER_UNIT")

	check(Box.IsShown(), "a mouseover resolved and the addon put nothing up")
	check(Box.Owner() == Box.CURSOR,
		"the box was anchored to an owner, and a creature in the world is not a frame")

	local said = drawn()
	check(said[1] == "Snarlmouth",
		"the client's own first line is not the title: " .. tostring(said[1]))
	check(said[3] == "Silverpine Forest",
		"the client's third line is missing: " .. tostring(said[3]))

	------------------------------------------------------------------
	-- The hook, from the other end
	--
	-- Meter/Standing.lua registered one line against the unit kind at load and
	-- knows nothing about this part. Its line lands in the extra band, after
	-- everything the client said, and it is the last thing in the box: a hover
	-- that tracks your pointer carries no standing footnote about its own
	-- switch.
	------------------------------------------------------------------

	check(said[4] == "Threat",
		"nothing the addon knows about a mob reached its tooltip: " .. table.concat(said, " / "))
	local _, standing = Box.Text(4)
	check(standing == "theirs, you are at 62%",
		"the threat line does not say where you stand: " .. tostring(standing))
	check(#said == 4, ("the box drew %d lines rather than four: %s")
		:format(#said, table.concat(said, " / ")))

	------------------------------------------------------------------
	-- Blizzard's own box, held down
	--
	-- Narrow twice: only while ours is up, and only for a tooltip that answers
	-- a unit. The second is the one worth the assertion. GameTooltip carries a
	-- quest reward, a link somebody clicked in chat and every other addon's
	-- lines, and a suppression that took those too would be a linked item that
	-- says nothing with no error anywhere to say why.
	------------------------------------------------------------------

	check(ns.UI.Scan.Suppressing(),
		"our box is up and the client's is not being held down, so the mob is described twice")
	check(H.blizzardTooltip("mouseover") == false,
		"the client raised its own tooltip on the mob and the addon left it standing")
	check(H.blizzardTooltip(nil) == true,
		"a tooltip that is not about a unit was taken down as well, which is every linked item in the game")

	------------------------------------------------------------------
	-- Where the box lands
	--
	-- Beside the pointer and clear of the arrow, which hangs down and to the
	-- right of the hotspot. The side is picked the way a frame's tooltip picks
	-- one, so a mob on the right of the screen throws its box left rather than
	-- into the clamp.
	--
	-- All of which is what the box does undocked, and undocked is not the
	-- default, so the switch is thrown for the length of this claim and handed
	-- back at the end of it. The docked corner is asserted in 48-tooltips.lua
	-- where the setting lives; what is proven here is the answer a creature
	-- gets when the player has asked for a box beside the cursor, which is the
	-- one anchor in the file that no frame can reach.
	------------------------------------------------------------------

	local wasPlace = Box.Place()
	Box.SetPlace(Box.BESIDE)

	-- The stub stands UIParent up with no size at all, so the middle of the
	-- screen is zero and every tooltip in every section above this one has been
	-- thrown to the same side without anybody noticing. This is the one section
	-- where which side the box picks is the subject, so it gives the screen a
	-- size for the length of that claim and hands it straight back. A size left
	-- behind would move the mirror line 15-skin-fit measures its blocks against.
	local screen = _G.UIParent
	screen:SetSize(2560, 1440)
	cursor.x, cursor.y = 300, 500
	fire("UPDATE_MOUSEOVER_UNIT")

	local px, py = pointer()
	check(edge("GetLeft") > px and edge("GetLeft") - px < 64,
		"the box did not open just to the right of the pointer on the left of the screen")
	check(edge("GetTop") < py and py - edge("GetTop") < 64,
		"the box did not open just under the arrow that opened it")

	local near = edge("GetLeft")
	cursor.x = cursor.x + 60
	fire("UPDATE_MOUSEOVER_UNIT")
	check(edge("GetLeft") > near, "the box did not follow the pointer")

	cursor.x = 2400
	fire("UPDATE_MOUSEOVER_UNIT")
	px = pointer()
	check(edge("GetRight") < px,
		"a mob on the right of the screen threw its box further right, into the clamp")

	screen:SetSize(0, 0)
	Box.SetPlace(wasPlace)
	cursor.x = 300
	fire("UPDATE_MOUSEOVER_UNIT")

	------------------------------------------------------------------
	-- Nothing to say about a friend
	--
	-- The threat source's own guard, not this part's. A line reading "not
	-- swinging at anybody" under every innkeeper in the game is what makes a
	-- player turn the whole hover off.
	------------------------------------------------------------------

	_G.WarriorKitFriendlyUnits.mouseover = true
	fire("UPDATE_MOUSEOVER_UNIT")
	said = drawn()
	check(said[4] ~= "Threat",
		"a quest giver was told where you stand on it: " .. table.concat(said, " / "))
	_G.WarriorKitFriendlyUnits.mouseover = nil

	------------------------------------------------------------------
	-- The other answers the threat line has
	--
	-- Two returns of nil percent for opposite reasons, which is the trap the
	-- line is written round: you are holding the mob and nobody is near you,
	-- and the mob has never heard of you.
	--
	-- The fourth answer is a client with no threat API at all, and it cannot be
	-- reached from here. Core/Core.lua resolves UnitDetailedThreatSituation into
	-- a file-scope local as it loads, so a test that took the global away
	-- afterwards would take nothing away, and there is no way to be a Classic
	-- Era client half way through a run. The threat pane's own Era fallback in
	-- Meter/Threat.lua is untested for exactly the same reason and in exactly
	-- the same place, which is worth saying out loud rather than leaving to be
	-- discovered: what Swinging words is proven by nothing here.
	------------------------------------------------------------------

	state.threatReader = function(source)
		if source ~= "player" then
			return nil
		end
		return true, 3, 100
	end
	fire("UPDATE_MOUSEOVER_UNIT")
	local _, holding = Box.Text(4)
	check(holding == "yours, and nobody is close",
		"holding a mob with nobody behind you reads as: " .. tostring(holding))

	state.threatReader = function() return nil end
	fire("UPDATE_MOUSEOVER_UNIT")
	local _, idle = Box.Text(4)
	check(idle == "nothing on it yet",
		"a mob that has never heard of you reads as: " .. tostring(idle))

	------------------------------------------------------------------
	-- The same creature twice
	--
	-- The client fires this event again for a mob that moved, and the box for
	-- that mob is already on screen. Building it again is a scan of Blizzard's
	-- tooltip, every band laid out a second time and the suppression armed on
	-- top of the box it is already holding down, to draw what is drawn. So the
	-- second event about one creature is turned away, and the pointer leaving is
	-- what makes the next one a hover.
	------------------------------------------------------------------

	state.threatReader = function(source)
		if source ~= "player" then
			return nil
		end
		return true, 3, 100
	end
	raw("UPDATE_MOUSEOVER_UNIT")
	local _, held = Box.Text(4)
	check(held == idle,
		"a second event about the creature already on screen built the box again")

	fire("UPDATE_MOUSEOVER_UNIT")
	local _, back = Box.Text(4)
	check(back == "yours, and nobody is close",
		"looking away and back did not build the box again: " .. tostring(back))

	state.threatReader = function() return nil end
	fire("UPDATE_MOUSEOVER_UNIT")

	------------------------------------------------------------------
	-- The box, taken over by something that owns a frame
	--
	-- The addon has one tooltip and every hover in it draws in that one frame,
	-- so a bag square or a feed row crossed while a creature is under the
	-- pointer takes the box and gives it back to nobody. This part cannot hear
	-- that happen: there is no event for it, the token has not moved, and the
	-- refusal above is written against what this file last did rather than
	-- against what is on screen.
	--
	-- What that cost is the state asserted here. The box believed to be up was
	-- somebody else's, the next event about the creature was turned away as a
	-- repeat, and the suppression stayed armed: a mob under the pointer with
	-- Blizzard's box held down and none of ours in its place. Three claims, and
	-- the middle one is the defect.
	--
	--   The suppression comes off, because it is armed only in exchange for a
	--   box of ours being on screen.
	--   The creature's next event builds the box again rather than refusing.
	--   And nothing here takes down the box that took this one over. It belongs
	--   to whatever the pointer actually moved onto, and closing it would be
	--   this part answering for a hover it knows nothing about.
	------------------------------------------------------------------

	local elsewhere = _G.CreateFrame("Frame", nil, _G.UIParent)
	elsewhere:SetSize(30, 30)
	elsewhere:SetPoint("CENTER", _G.UIParent, "CENTER", 0, 0)

	check(ns.UI.Scan.Suppressing(), "the run reached the takeover with nothing of ours up")

	ns.Tip.Open(elsewhere, { kind = "note", title = "A row somewhere else" })
	check(Box.Owner() == elsewhere, "the hover that took the box over did not get it")

	-- The creature stops existing while the pointer is on that row, which is
	-- the close this part makes with a box on screen that is not its own.
	guids.mouseover = nil
	raw("UPDATE_MOUSEOVER_UNIT")
	check(Box.IsShown() and Box.Owner() == elsewhere,
		"the world hover closed a box belonging to whatever the pointer moved onto")
	check(not ns.UI.Scan.Suppressing(),
		"Blizzard's tooltip is still held down with a box that is not ours on screen")

	-- And the sweep reaches the same state without the creature going anywhere,
	-- which is the ordinary way round: the mob is still there, the pointer is on
	-- a row over it, and the tick is the only thing that can notice.
	guids.mouseover = MOB
	fire("UPDATE_MOUSEOVER_UNIT")
	check(Box.Owner() == Box.CURSOR, "the creature's box did not come back after the row")

	ns.Tip.Open(elsewhere, { kind = "note", title = "A row somewhere else" })
	ns.World.Sweep()
	check(not ns.UI.Scan.Suppressing(),
		"a sweep that found somebody else's box left Blizzard's held down")
	check(Box.IsShown() and Box.Owner() == elsewhere,
		"the sweep took down the box that had taken this one over")

	-- The pointer goes back to the creature. The token never moved, so what
	-- arrives is the same event about the same guid that used to be turned away
	-- as a repeat.
	ns.Tip.Close(true)
	raw("UPDATE_MOUSEOVER_UNIT")
	check(Box.IsShown(), "the creature under the pointer got no box back")
	check(Box.Owner() == Box.CURSOR,
		"the box that came back is not the world hover's")
	check(Box.Text(1) == "Snarlmouth",
		"the box that came back says " .. tostring(Box.Text(1)))
	check(ns.UI.Scan.Suppressing(),
		"our box is up again and Blizzard's is not being held down")

	------------------------------------------------------------------
	-- What the mob is wanted for
	--
	-- The one thing a creature hover can say that the client cannot: this boar
	-- drops the hide, that hide is for the quest in your log, and you have three
	-- of the eight. Only Questie knows the first of those, so the whole band is
	-- read off Questie's own tooltip registry, keyed `m_<npc id>` against the
	-- objective the creature feeds.
	--
	-- The drop rate has two sources and both are asserted, because they answer
	-- on different creatures and shipping only one of them is what the file did.
	-- Questie v11's own drop table is printed where it has a row, on the first
	-- hover and with nothing looted. The ledger under it is the addon's own,
	-- counted off the corpses you opened, and it says nothing at all until there
	-- are enough of them to be worth saying -- a fraction printed off two
	-- corpses is arithmetic pretending to be information.
	------------------------------------------------------------------

	local loader = _G.QuestieLoader
	local tips = loader:ImportModule("QuestieTooltips")
	local player = loader:ImportModule("QuestiePlayer")
	local wasLookup, wasLog = tips.lookupByKey, player.currentQuestlog

	-- 102 is "The Missing Diplomat", which client/05-quests.lua puts in the log
	-- and in Questie's database. The objective is Questie's shape: a type, the
	-- item id, the description it draws, and the two counts the client filled
	-- in.
	local hide = { Index = 1, Type = "item", Id = 3002,
		Description = "Bristleback Hide", Collected = 3, Needed = 8 }
	tips.lookupByKey = { ["m_1234"] = { ["102 1"] = { questId = 102, objective = hide } } }
	player.currentQuestlog = { [102] = {} }

	guids.mouseover = MOB
	fire("UPDATE_MOUSEOVER_UNIT")
	said = drawn()
	local named, counted = false, nil
	for index = 1, #said do
		if said[index] == "The Missing Diplomat" then
			named = true
		end
		if said[index] == "Bristleback Hide" then
			local _, value = Box.Text(index)
			counted = value
		end
	end
	check(named, "the box does not name the quest the mob feeds: " .. table.concat(said, " / "))
	check(counted == "3/8",
		"the box does not say how many you already have: " .. tostring(counted))

	-- Questie's own rate, on the first hover with nothing looted. This is the
	-- half that did not exist when the file was written: v6 shipped no drop
	-- table at all, so the only number the box could ever carry was one the
	-- player spent ten corpses earning.
	local listed = nil
	for index = 1, #said do
		if said[index] == "dropped by" then
			local _, value = Box.Text(index)
			listed = value
		end
	end
	check(listed == "22%",
		"Questie's own drop rate did not reach the box: " .. tostring(listed))

	-- And the ledger is still silent, because nothing has been looted. The two
	-- are separate lines and this is what says so: a box carrying the database
	-- rate must not be a box that has also invented a measured one.
	local Drops = ns.QuestDrops
	check(Drops.Chance(1234, 3002) == nil,
		"a drop chance was printed before a single corpse had been opened")

	-- Twelve corpses, four of them carrying it. Recorded through the same call
	-- the loot window drives, so what is asserted is the ledger the game fills
	-- rather than a number written into it by hand.
	for at = 1, 12 do
		Drops.Record(1234, at <= 4 and { [3002] = true } or {})
	end
	local rate, corpses = Drops.Chance(1234, 3002)
	check(rate ~= nil and corpses == 12,
		("twelve corpses answered %s over %s"):format(tostring(rate), tostring(corpses)))

	fire("UPDATE_MOUSEOVER_UNIT")
	said = drawn()
	local chance = nil
	for index = 1, #said do
		if said[index] == "your kills" then
			local _, value = Box.Text(index)
			chance = value
		end
	end
	check(chance == "33% of 12",
		"your own kills did not reach the box beside Questie's rate: " .. tostring(chance))

	-- Both lines, at once. The interesting case for anybody standing over the
	-- boars is the one where the two disagree -- 22 scraped against 33 of your
	-- own -- and merging them into an average would throw that away.
	local both = false
	for index = 1, #said do
		if said[index] == "dropped by" then
			local _, value = Box.Text(index)
			both = value == "22%"
		end
	end
	check(both, "Questie's rate stopped being printed once the ledger had an answer")

	-- With no row in Questie's drop table, the ledger takes the line back. This
	-- is every creature on a v6 install and a good few on v11, and it is the
	-- shape the box had before the database was read at all.
	--
	-- Ten more corpses onto the same creature, five of them carrying it: five of
	-- twenty two, because the twelve above were corpses of this boar too and a
	-- ledger that started counting again per item would report every drop as if
	-- it were the only thing the mob ever had on it.
	local other = { Index = 1, Type = "item", Id = 3005,
		Description = "Rogue's Note", Collected = 0, Needed = 4 }
	tips.lookupByKey = { ["m_1234"] = { ["102 1"] = { questId = 102, objective = other } } }
	for at = 1, 10 do
		Drops.Record(1234, at <= 5 and { [3005] = true } or {})
	end
	fire("UPDATE_MOUSEOVER_UNIT")
	said = drawn()
	local measured = nil
	for index = 1, #said do
		if said[index] == "dropped by" then
			local _, value = Box.Text(index)
			measured = value
		end
	end
	check(measured == "23% of 22 looted",
		"with no row in Questie's table the ledger did not take the line: " .. tostring(measured))

	------------------------------------------------------------------
	-- A creature you have to kill, which is the commonest quest there is
	--
	-- Questie registers `m_<npc id>` off the spawn list of every objective a
	-- creature feeds, whatever kind it is, and the file read `item` and dropped
	-- the other four. So a mob eight of which stood between you and the end of
	-- the quest said nothing at all, which is the defect this section is here
	-- for: nothing was broken, one comparison was too narrow, and the symptom
	-- was a hover that worked on some mobs and not others.
	------------------------------------------------------------------

	local slay = { Index = 1, Type = "monster", Id = 1234,
		Description = "Bristleback Quilboar", FullDescription = "Bristleback Quilboar slain",
		Collected = 3, Needed = 8 }
	tips.lookupByKey = { ["m_1234"] = { ["102 1"] = { questId = 102, objective = slay } } }
	Drops.Forget()

	fire("UPDATE_MOUSEOVER_UNIT")
	said = drawn()
	local killed = nil
	for index = 1, #said do
		if said[index] == "Bristleback Quilboar slain" then
			local _, value = Box.Text(index)
			killed = value
		end
	end
	check(killed == "3/8",
		"a mob you have to kill eight of says nothing: " .. table.concat(said, " / "))

	-- FullDescription over Description, which is Questie's own order and matters
	-- most here: a kill objective's Description is the creature's name, and the
	-- name is already the first line of the box.
	for index = 1, #said do
		check(said[index] ~= "Bristleback Quilboar",
			"the box repeats the mob's name instead of what the quest asked for")
	end

	-- No drop rate under a kill. The creature drops itself every time and a line
	-- saying so is furniture.
	for index = 1, #said do
		check(said[index] ~= "dropped by",
			"a creature you have to kill was given a drop chance")
	end

	------------------------------------------------------------------
	-- The same fact in the four characters a nameplate has room for
	--
	-- The badge UnitFrames/EnemyBars.lua draws off the bar's right edge. It is
	-- cached per creature, because it is asked once per plate five times a
	-- second and the walk behind it is over another addon's hash table, so what
	-- is asserted is both the answer and that the cache lets go of it.
	------------------------------------------------------------------

	check(Drops.Badge(1234) == "3/8",
		"the plate badge does not carry the count: " .. tostring(Drops.Badge(1234)))
	check(Drops.Badge(4321) == nil,
		"a creature no quest wants was given a plate badge")

	-- The count moves and the badge moves with it, but only once the log has
	-- said so. A cache nothing invalidates is a plate stuck on 3/8 for the rest
	-- of the evening.
	slay.Collected = 7
	check(Drops.Badge(1234) == "3/8",
		"the badge re-walked Questie's registry without the log having moved")
	Drops.Forget()
	check(Drops.Badge(1234) == "7/8",
		"the badge did not move after the log did: " .. tostring(Drops.Badge(1234)))

	-- An objective with no count of its own is a mark and nothing else, which is
	-- what an event or a thing you cast on a mob looks like.
	tips.lookupByKey = { ["m_1234"] = { ["102 1"] = { questId = 102,
		objective = { Index = 1, Type = "event", Description = "Reach the camp" } } } }
	Drops.Forget()
	check(Drops.Badge(1234) == "!",
		"an objective with no count did not fall back to the mark: " .. tostring(Drops.Badge(1234)))

	-- A quest you have handed in leaves its key registered in Questie until
	-- something walks it, so the log is asked as well as the registry. Without
	-- that the mob goes on offering a quest you finished a zone ago.
	player.currentQuestlog = {}
	fire("UPDATE_MOUSEOVER_UNIT")
	said = drawn()
	for index = 1, #said do
		check(said[index] ~= "The Missing Diplomat",
			"a quest that is no longer in your log is still on the mob's box")
	end

	tips.lookupByKey, player.currentQuestlog = wasLookup, wasLog
	ns.db.questDrops = {}
	Drops.Forget()

	------------------------------------------------------------------
	-- Looking away
	--
	-- UPDATE_MOUSEOVER_UNIT says when a hover begins and nothing reliable about
	-- when one ends, so the box carries a ticker that runs only while it is on
	-- screen. Everything it took has to come back: the box, and Blizzard's own
	-- tooltip with it.
	------------------------------------------------------------------

	fire("UPDATE_MOUSEOVER_UNIT")
	check(Box.IsShown(), "the scene is not set up: nothing is on screen to look away from")

	guids.mouseover = nil
	World.Sweep(1)
	check(not H.tipSettle(), "the box stayed up after the pointer left the mob")
	check(not ns.UI.Scan.Suppressing(),
		"the client's tooltip is still held down with nothing of ours on screen")
	check(H.blizzardTooltip("mouseover") == true,
		"Blizzard's own tooltip is still being taken down after the addon let go")

	------------------------------------------------------------------
	-- Turned off
	--
	-- Including the box already on screen. A hover left standing when the
	-- setting goes off would sit there describing a mob you are no longer
	-- asking about.
	------------------------------------------------------------------

	guids.mouseover = MOB
	fire("UPDATE_MOUSEOVER_UNIT")
	check(Box.IsShown(), "the scene is not set up: nothing is on screen to turn off")

	World.Set(false)
	check(not Box.IsShown(), "turning the world hover off left the box it had already opened")
	fire("UPDATE_MOUSEOVER_UNIT")
	check(not Box.IsShown(), "the world hover is off and a mouseover still opened a box")
	check(H.blizzardTooltip("mouseover") == true,
		"the world hover is off and the addon is still holding Blizzard's tooltip down")
	check(World.Describe():find("off", 1, true) ~= nil,
		"the part does not report that it is off: " .. World.Describe())

	World.Set(true)
	check(World.Describe() == "on, in the addon's own box",
		"the part does not report that it is working: " .. World.Describe())

	------------------------------------------------------------------
	-- A client that hands over nothing about a unit
	--
	-- The name still stands, the way it does on an item link the client refuses.
	-- A box carrying a threat reading over an unnamed thing is worse than a box
	-- carrying a name, and this is the branch that decides which one a player on
	-- a client with no SetUnit gets.
	------------------------------------------------------------------

	tooltips.unit.mouseover = nil
	state.threatReader = function(source)
		if source ~= "player" then
			return nil
		end
		return false, 2, 62
	end
	fire("UPDATE_MOUSEOVER_UNIT")
	check(Box.Text(1) == "Snarlmouth",
		"a client with no text about a unit did not fall back to the name: "
			.. tostring(Box.Text(1)))
	local _, still = Box.Text(2)
	check(still == "theirs, you are at 62%",
		"the addon's own line went with the client's: " .. tostring(still))

	tooltips.unit.mouseover = {
		{ "Snarlmouth" },
		{ "Level 62 Elite", "Beast" },
		{ "Silverpine Forest" },
	}

	------------------------------------------------------------------
	-- What the ticker costs
	--
	-- It runs only while the box is on screen, which is the fix, and it still
	-- has to cost nothing while it is: the question it asks is asked ten times a
	-- second for as long as you are pointing at anything, and the collector runs
	-- in the middle of a frame.
	------------------------------------------------------------------

	guids.mouseover = MOB
	fire("UPDATE_MOUSEOVER_UNIT")
	for _ = 1, 5 do
		World.Sweep(0.1)
	end
	collectgarbage("collect")
	collectgarbage("stop")
	local before = collectgarbage("count")
	for _ = 1, 50 do
		World.Sweep(0.1)
	end
	local churned = collectgarbage("count") - before
	collectgarbage("restart")
	check(churned < CHURN.world,
		("the world hover churned %.2f KB over 50 ticks, gate is %.2f")
			:format(churned, CHURN.world))
	check(Box.IsShown(), "fifty ticks over a mob that never moved took the box down")

	guids.mouseover = nil
	unitName.mouseover = nil
	tooltips.unit.mouseover = nil
	state.threatReader = nil
	cursor.x, cursor.y = 300, 500
	World.Close()
	H.blizzardTooltip(nil)

	print(("world  %s, %s; the client's own held down for a unit and nothing else; %.2f KB per 50 ticks, gate is %.2f")
		:format(World.Describe(),
			Box.Place(),
			churned, CHURN.world))
	print(("world  a creature's quest drops: %s"):format(ns.QuestDrops.Describe()))
end
