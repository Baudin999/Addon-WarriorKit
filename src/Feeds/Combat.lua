local ADDON, ns = ...

local CombatFeed = {}
ns.CombatFeed = CombatFeed

local C = ns.UI.Color

--------------------------------------------------------------------------
-- What just happened to you
--
-- The same column as the loot stream, fed by the combat log instead: one row
-- per thing that landed, newest at the top, with the icon of whatever did it,
-- what it was, who the other party was, and the number.
--
-- **A row has to answer three questions and it used to answer one.** The rule
-- was: draw the spell's name where there is one and the other party's name
-- where there is not. That reads "Overpower 321" and "Plains Creeper 26" as the
-- same shape, and neither one says who was on the other end of it. So the name
-- column is always what happened, a spell or the client's own word for a swing,
-- and the dim middle column is always who, with "on" for something you did and
-- "from" for something done to you. The direction is in the stripe as well, in
-- colour, but colour on its own is a thing a colourblind player does not have.
--
-- **A critical carries a mark, not just a colour.** The number reads 871! and
-- draws in gold. Gold alone was the whole signal and it was the same mistake
-- one level down: the moment the feed exists to show you cannot be the one
-- carried by hue alone.
--
-- **It is about you and nothing else.** The log names every creature in range,
-- including the other party fighting the pack next door, and a feed that drew
-- all of it would be the client's own combat log tab, which is the thing nobody
-- reads. So a row is made only where you or your pet is one of the two ends of
-- the event. Meter/Meter.lua answers the other question, what the whole group
-- did over a fight, and the two share no state on purpose: one is a running
-- total and one is a list of moments.
--
-- **The positions are the contract.** CombatLogGetCurrentEventInfo hands over
-- twenty-one values in a fixed order and the meaning of the twelfth onwards
-- depends on the subevent. A swing puts its amount at twelve; a spell puts its
-- id, name and school there and its amount at fifteen. That is read here once,
-- in a table, rather than at each site, and it is the reason this file is
-- separate from the one that draws the rows.
--
-- **Nothing is on a ticker.** A row arrives when the log says so.
--
-- **Collecting and being on screen are two settings.** `combatFeed` is whether
-- this file does anything at all, and it decides whether this file is
-- subscribed to ns.CombatLog, so a feed that is off costs nothing at all per
-- combat log event: the addon is not on the event. `combatFeedShown` only
-- decides whether you can see the column, and a feed hidden with that one keeps
-- filling: what you get when you bring it back is the last four hundred things
-- that happened rather than a blank. That matters because the two are nowhere
-- near the same price. Reaching the end of this file and pushing a row costs
-- roughly thirty times what turning an event away at the top costs, and nearly
-- all of that thirty is UI/Feed.lua repainting the column. Feeds/Stream.lua
-- puts the hidden feed's widget to sleep for exactly that reason.
--------------------------------------------------------------------------

-- Where the amount and the crit flag sit for each shape of event.
--
--   amount   the slot the number is in
--   spell    the slot the spell id is in, and nil for a swing, which has none
--   crit     the slot the critical flag is in
--   heal     whether the number is healing rather than damage
--   miss     the slot the miss type is in, for the shapes that carry one
--
-- A table lookup rather than a chain of comparisons, because in a raid this is
-- the first line of a handler the client calls a few hundred times a second.
local SHAPES = {
	SWING_DAMAGE          = { amount = 12, crit = 18 },
	SPELL_DAMAGE          = { amount = 15, spell = 12, crit = 21 },
	SPELL_PERIODIC_DAMAGE = { amount = 15, spell = 12, crit = 21 },
	RANGE_DAMAGE          = { amount = 15, spell = 12, crit = 21 },
	DAMAGE_SHIELD         = { amount = 15, spell = 12, crit = 21 },
	SPELL_HEAL            = { amount = 15, spell = 12, crit = 18, heal = true },
	SPELL_PERIODIC_HEAL   = { amount = 15, spell = 12, crit = 18, heal = true },
	SWING_MISSED          = { miss = 12 },
	SPELL_MISSED          = { miss = 15, spell = 12 },
	RANGE_MISSED          = { miss = 15, spell = 12 },
}

-- The four colours a row can be, and they are the whole readout at a glance.
-- Held as tables this file owns for the reason Feeds/Loot.lua holds its quality
-- palette: every guard in UI/Feed.lua compares a colour by identity.
local OUT = { 0.87, 0.87, 0.91 }
local IN = { 0.94, 0.42, 0.35 }
local HEAL = { 0.34, 0.80, 0.44 }
local MISS = { 0.50, 0.50, 0.55 }

-- A crit is the one thing on a row that is worth a colour of its own. It is the
-- moment the feed exists to show you, and it is a property of the number rather
-- than of the direction, so it lands on the number and leaves the stripe saying
-- which way the blow went.
local CRIT = { 1.00, 0.82, 0.20 }

-- The two bands, which are the only thing on a marker row that says which one
-- it is at a glance. Dark rather than saturated: a marker is a rule drawn
-- across the feed, and one as loud as an entry would be competing with the
-- entries it exists to separate.
local PULL = { 0.32, 0.13, 0.13, 1 }
local LULL = { 0.13, 0.15, 0.21, 1 }

-- Auto Attack, for the icon and the word on a swing. Both asked of the client
-- rather than typed: an icon path this file invented would be a green question
-- mark on a client that files it elsewhere, and a typed "Melee" would be an
-- English word in the middle of a German feed. Resolved once at login and
-- floored on the client's own unknown icon and on a word of last resort.
local UNKNOWN = "Interface\\Icons\\INV_Misc_QuestionMark"
local AUTO_ATTACK = 6603
local swingIcon = UNKNOWN
local swingWord = "melee"

local seen, ignored = 0, 0

--------------------------------------------------------------------------

local function Marker(entry)
	local lines = {
		{ (entry.mark == "in")
			and "A fight started here. Everything above this line is the same pull."
			or "A fight ended here. Everything below this line was the pull before." },
		{ "At", ns.Stream.Clock(entry.at) },
	}
	if entry.amount and entry.amount ~= "" then
		lines[#lines + 1] = { "Lasted", entry.amount }
	end
	return {
		kind = "note",
		title = entry.name,
		color = (entry.mark == "in") and IN or C.dim,
		lines = lines,
	}
end

local function Fill(entry)
	if entry.mark then
		return Marker(entry)
	end

	local lines = {}
	if entry.subevent then
		lines[#lines + 1] = { "Event", entry.subevent }
	end
	if entry.source then
		lines[#lines + 1] = { "From", entry.source }
	end
	if entry.dest then
		lines[#lines + 1] = { "To", entry.dest }
	end
	if entry.value then
		lines[#lines + 1] = { entry.healed and "Healed" or "Damage",
			tostring(entry.value), tone = entry.crit and CRIT or nil }
	end
	if entry.crit then
		lines[#lines + 1] = { "A critical.", color = CRIT }
	end
	if entry.wasted and entry.wasted > 0 then
		lines[#lines + 1] = { entry.healed and "Overheal" or "Overkill",
			tostring(entry.wasted), tone = MISS }
	end

	return {
		kind = "note",
		title = entry.name or "?",
		color = entry.color,
		lines = lines,
	}
end

local stream = ns.Stream.New({
	prefix = "combatFeed",
	name = "WarriorKitCombatFeed",
	title = "Combat",
	empty = "quiet",
	-- Room for a mob's name and the preposition in front of it, which is about
	-- what "from Plains Creeper" measures. The feed gives it half of what is
	-- left after the number column at most, so a feed dragged down to the
	-- narrowest the panel allows gets less of it rather than losing the name.
	note = 96,
	onTooltip = Fill,
})

function CombatFeed.Stream()
	return stream
end

-- Bottom left, opposite the loot stream, which is the other half of the same
-- corner of the screen and is where the client's own combat text already goes.
function CombatFeed.Defaults()
	-- Keeps the word over it and the line round it, which is the third
	-- argument and the one thing this feed and the loot feed answer
	-- differently. A loot row says what it is by the colour of the name on it;
	-- a combat row is three columns of numbers, and a column of numbers with
	-- nothing named over it is a column you have to work out.
	local defaults = ns.Stream.Defaults("combatFeed",
		{ "LEFT", "UIParent", "LEFT", 423, 56 }, true)

	-- Taller than the loot feed, because a pull produces rows an order of
	-- magnitude faster than a corpse does: at ten rows a fight scrolls off the
	-- bottom before you have read the top of it. The same width as the loot
	-- feed, so the two columns are one instrument rather than two.
	defaults.combatFeedWidth = 280
	defaults.combatFeedRows = 13

	-- combatFeed and combatFeedShown both come from Stream.Defaults above and
	-- both start true, and both are turned off here. The first is the one this
	-- file reads: off means no row is ever built and no marker is ever drawn,
	-- which is the whole combat log left alone. The second only takes the
	-- column off the screen.
	--
	-- Off because of what it costs rather than what it is worth. This is the
	-- part of the addon with something to say about every line in the zone, and
	-- the meter and the breakdown already answer "how did that fight go" from
	-- the same log without a row per swing. `/wk feed combat on` for the pull
	-- you actually want to read back.
	defaults.combatFeed = false
	defaults.combatFeedShown = false

	-- What you do, and what is done to you. Both on, because either alone is
	-- half a conversation, and separate because they answer different questions
	-- and a tank wants the second one on its own.
	defaults.combatFeedOut = true
	defaults.combatFeedIn = true

	-- A miss is a row with no number on it and it is worth a row: four dodges
	-- in a row is the reason your rotation stalled and nothing else on screen
	-- says so.
	defaults.combatFeedMisses = true

	-- The smallest hit that gets a row.
	--
	-- Zero is every tick of every bleed on every mob you are fighting, which in
	-- a fury pull is a feed that scrolls faster than it can be read. This is the
	-- one number that decides whether the feature is useful or is noise, and it
	-- is deliberately a setting rather than a constant, because the right floor
	-- at level 20 and the right floor in a raid differ by an order of magnitude.
	defaults.combatFeedFloor = 0
	return defaults
end

--------------------------------------------------------------------------
-- One event
--------------------------------------------------------------------------

-- Whether a GUID is you or something of yours. Roster.Owner answers the owner
-- for a pet and nil for anything that is not one of the group's, so one call
-- covers a hunter's pet, a warlock's imp and a totem without this file knowing
-- what any of those are.
-- Both halves are checked before the comparison, and the second one is not
-- defensive tidying. Roster.Owner answers nil for anything that is not one of
-- the group's, so a moment where the client will not say who you are, which is
-- a loading screen and the first frames after one, would compare nil against
-- nil and make every creature in range yours. The symptom is a feed that draws
-- the whole zone, and it is a comparison that looks correct.
local function Mine(guid, me)
	if not guid or not me then
		return false
	end
	return ns.Unit.Roster.Owner(guid) == me
end

-- What happened, which is the spell where there is one and the client's own
-- word for a swing where there is not. Always what rather than sometimes who,
-- because a column that means two different things depending on the row is a
-- column you have to decode before you can read it.
local function Caption(spellName)
	if spellName and spellName ~= "" then
		return spellName
	end
	return swingWord
end

-- Who the other party was, and which way it went.
--
-- One short string built per row. That is an allocation on the path the combat
-- log drives and it is worth it: the alternative is a fourth region on every
-- row of every feed to hold a preposition, and this file already builds a
-- string for the number. A row is a thing that happened to you rather than a
-- tick, and there are not four hundred of them a second.
local function Note(outgoing, source, dest)
	local other = outgoing and dest or source
	if not other or other == "" then
		return ""
	end
	return (outgoing and "on %s" or "from %s"):format(other)
end

-- The number, with a crit said in a glyph as well as in gold.
local function Amount(amount, crit)
	if not amount then
		return ""
	end
	if crit then
		return amount .. "!"
	end
	return tostring(amount)
end

local function Add(subevent, shape, outgoing, source, dest, spellId, spellName,
	amount, wasted, crit, miss)

	-- Which way the blow went, as the one colour that carries the whole row: the
	-- stripe down its left edge, the name, and the number where the hit was not
	-- a critical. A miss is grey whichever direction it went in, because a swing
	-- that did not land is the same non-event either way round.
	local color
	if miss then
		color = MISS
	elseif shape.heal then
		color = HEAL
	elseif outgoing then
		color = OUT
	else
		color = IN
	end

	local entry = stream:Feed():Entry()
	-- Held rather than asked. The icon for a spell id was decided when the
	-- client shipped and this line runs on every hit in the zone that is yours.
	entry.icon = (spellId and ns.SpellTextureHeld(spellId)) or swingIcon or UNKNOWN
	entry.name = Caption(spellName)
	entry.note = Note(outgoing, source, dest)
	entry.amount = miss or Amount(amount, crit)
	entry.color = color
	entry.stripe = color
	entry.tone = crit and CRIT or color

	-- Everything past this point is read by the tooltip alone, which is what a
	-- feed is for: the row says what happened and the hover says the rest.
	entry.subevent = subevent
	entry.source = source
	entry.dest = dest
	entry.value = amount
	entry.wasted = wasted
	entry.crit = crit
	entry.healed = shape.heal

	stream:Feed():Push()
	seen = seen + 1
	return true
end

-- The twenty one values the client hands over, in the client's own order, and
-- your own GUID after them, which is what ns.CombatLog adds to the list.
--
-- The GUID is the first thing read, and it used to be the last. This file
-- called UnitGUID("player") once per line that got past the shape filter, which
-- in a pull is nearly every line, to reject on the answer three lines later.
-- Handed over now, and the rejection is where it belongs: no player means
-- nothing in the log is yours and there is nothing here to work out.
-- hot: handed to ns.CombatLog.Subscribe when the combat feed is switched on and
-- called back out of the reader list on every combat log line, which is an
-- edge scripts/hot.lua cannot see.
function CombatFeed.OnLog(_, subevent, _, sourceGUID, sourceName, _, _, destGUID,
	destName, _, _, a12, a13, _, a15, a16, _, a18, _, _, a21, me)
	if not me or not ns.db.combatFeed then
		return false
	end

	local shape = SHAPES[subevent]
	if not shape then
		return false
	end

	local outgoing = Mine(sourceGUID, me)
	local incoming = Mine(destGUID, me)
	-- Neither end is yours, which is nearly every event in a raid, so the miss
	-- costs one table lookup and two comparisons.
	if not outgoing and not incoming then
		return false
	end
	-- Your own bleed ticking on a mob is outgoing; a shield of yours healing you
	-- is both. Outgoing wins, because a row that said a heal was done to you by
	-- you would be reading the same fact twice.
	if outgoing and not ns.db.combatFeedOut then
		return false
	end
	if incoming and not outgoing and not ns.db.combatFeedIn then
		return false
	end

	local spellId = shape.spell and a12 or nil
	local spellName = shape.spell and a13 or nil

	if shape.miss then
		if not ns.db.combatFeedMisses then
			return false
		end
		local miss = shape.miss == 12 and a12 or a15
		if type(miss) ~= "string" then
			return false
		end
		return Add(subevent, shape, outgoing, sourceName, destName,
			spellId, spellName, nil, nil, nil, miss:lower())
	end

	local amount = (shape.amount == 12) and a12 or a15
	if type(amount) ~= "number" or amount < ns.db.combatFeedFloor or amount <= 0 then
		ignored = ignored + 1
		return false
	end

	-- Overkill and overheal are always the slot after the amount, on every
	-- shape in the table above, which is why SHAPES carries the one index.
	local wasted = (shape.amount == 12) and a13 or a16
	if type(wasted) ~= "number" or wasted < 0 then
		wasted = nil
	end

	local crit = (shape.crit == 18) and a18 or a21
	return Add(subevent, shape, outgoing, sourceName, destName,
		spellId, spellName, amount, wasted, crit and true or nil, nil)
end

--------------------------------------------------------------------------
-- Where one fight ends and the next begins
--
-- Without these the feed is one unbroken column and the only thing separating
-- the pack you are fighting from the one before it is a gap in the timestamps
-- you cannot see, because a row carries no clock. A marker is the line down the
-- middle of that: everything above it is this pull.
--
-- Both ends get one, and a pair with nothing between them is left standing
-- rather than swallowed. That pair is information too. It says you were in
-- combat and nothing that happened in it cleared the floor, which is the exact
-- state somebody who has set the floor too high is looking for.
--
-- How long it lasted goes on the end marker because that is the one fact about
-- a fight nothing else in the addon reports. The meters total a fight and reset
-- on the next one; neither of them ever says how long you were in it.
--------------------------------------------------------------------------

local pulled

local function Pull()
	pulled = GetTime()
	if not ns.db.combatFeed then
		return false
	end
	stream:Feed():Mark("in", "in combat", "", PULL)
	return true
end

local function Lull()
	-- Nothing to measure against where the addon came up mid fight, and a
	-- duration counted from login would be a made up number on a real row.
	local held = pulled and ("%.1fs"):format(GetTime() - pulled) or ""
	pulled = nil
	if not ns.db.combatFeed then
		return false
	end
	stream:Feed():Mark("out", "out of combat", held, LULL)
	return true
end

--------------------------------------------------------------------------

-- Whether this client will say what happened at all. Vanilla and TBC both
-- carry the call, so this is expected to be true on both targets; it is asked
-- rather than assumed for the reason every other shim in this addon is asked,
-- and a client without it has to say so in the panel rather than draw an empty
-- column with no explanation in it.
function CombatFeed.Ready()
	return ns.CombatLog.Ready()
end

function CombatFeed.Describe()
	if not ns.db.combatFeed then
		return "off"
	end
	if not CombatFeed.Ready() then
		return "this client has no combat log API, so the feed stays empty"
	end

	local line = stream:Describe()
	if not ns.db.combatFeedOut then
		line = line .. ", what you do is off"
	end
	if not ns.db.combatFeedIn then
		line = line .. ", what hits you is off"
	end
	if ns.db.combatFeedFloor > 0 then
		line = line .. (", nothing under %d"):format(ns.db.combatFeedFloor)
	end
	return line
end

-- What has reached the feed and what the floor turned away, for the panel and
-- for scripts/harness.lua.
function CombatFeed.Counts()
	return seen, ignored
end

-- What the markers are called from, so scripts/harness.lua can drive the two
-- ends of a fight without inventing an event the client does not send.
function CombatFeed.OnCombat(entering)
	if entering then
		return Pull()
	end
	return Lull()
end

-- On the log while the feed is collecting and off it entirely while it is not.
--
-- The feed ships off, because it is the one part of the addon that has
-- something to say about every line in the zone, and it registered the event at
-- load anyway. Off now means the client does not call into this addon for the
-- combat log at all, which is what the panel's hint has always claimed.
function CombatFeed.Apply()
	if ns.db and ns.db.combatFeed then
		ns.CombatLog.Subscribe(CombatFeed.OnLog)
	else
		ns.CombatLog.Unsubscribe(CombatFeed.OnLog)
	end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_REGEN_DISABLED" then
		Pull()
		return
	end
	if event == "PLAYER_REGEN_ENABLED" then
		Lull()
		return
	end
	swingIcon = ns.SpellTexture(AUTO_ATTACK) or UNKNOWN
	swingWord = ns.SpellName(AUTO_ATTACK) or swingWord
	CombatFeed.Apply()
end)
