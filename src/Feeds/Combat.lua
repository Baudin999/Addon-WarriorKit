local ADDON, ns = ...

local CombatFeed = {}
ns.CombatFeed = CombatFeed


--------------------------------------------------------------------------
-- What just happened to you
--
-- The same column as the loot stream, fed by the combat log instead: one row
-- per thing that landed, newest at the top, with the icon of whatever did it,
-- the name of the spell or of whoever swung, and the number.
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

-- Auto Attack, for the icon on a swing. Asked of the client rather than typed,
-- because an icon path this file invented would be a green question mark on a
-- client that files it elsewhere. Resolved once at login and floored on the
-- client's own unknown icon.
local UNKNOWN = "Interface\\Icons\\INV_Misc_QuestionMark"
local AUTO_ATTACK = 6603
local swingIcon = UNKNOWN

local seen, ignored = 0, 0

--------------------------------------------------------------------------

local function Fill(entry, tip)
	tip.Title(entry.name or "?", entry.color)

	if entry.subevent then
		tip.Pair("Event", entry.subevent)
	end
	if entry.source then
		tip.Pair("From", entry.source)
	end
	if entry.dest then
		tip.Pair("To", entry.dest)
	end
	if entry.value then
		tip.Pair(entry.healed and "Healed" or "Damage", tostring(entry.value),
			nil, entry.crit and CRIT or nil)
	end
	if entry.crit then
		tip.Line("A critical.", CRIT)
	end
	if entry.wasted and entry.wasted > 0 then
		tip.Pair(entry.healed and "Overheal" or "Overkill", tostring(entry.wasted), nil, MISS)
	end

	tip.Blank()
	tip.Hint("Scroll the feed for what happened before this. /wk feed combat for the rest.")
end

local stream = ns.Stream.New({
	prefix = "combatFeed",
	name = "WarriorKitCombatFeed",
	title = "Combat",
	empty = "quiet",
	onTooltip = Fill,
})

function CombatFeed.Stream()
	return stream
end

-- Bottom left, opposite the loot stream, which is the other half of the same
-- corner of the screen and is where the client's own combat text already goes.
function CombatFeed.Defaults()
	local defaults = ns.Stream.Defaults("combatFeed",
		{ "BOTTOMLEFT", "UIParent", "BOTTOMLEFT", 20, 180 })

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

local CombatLogGetCurrentEventInfo = _G.CombatLogGetCurrentEventInfo

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

-- The name a row carries. A spell has one and it is what you want to read; a
-- swing does not, and the informative thing about a swing is who threw it.
local function Caption(spellName, outgoing, source, dest)
	if spellName and spellName ~= "" then
		return spellName
	end
	return (outgoing and dest or source) or "?"
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
	entry.icon = (spellId and ns.SpellTexture(spellId)) or swingIcon or UNKNOWN
	entry.name = Caption(spellName, outgoing, source, dest)
	entry.amount = miss or (amount and tostring(amount)) or ""
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

function CombatFeed.OnLog()
	if not ns.db.combatFeed or type(CombatLogGetCurrentEventInfo) ~= "function" then
		return false
	end

	local _, subevent, _, sourceGUID, sourceName, _, _, destGUID, destName,
		_, _, a12, a13, _, a15, a16, _, a18, _, _, a21 = CombatLogGetCurrentEventInfo()

	local shape = SHAPES[subevent]
	if not shape then
		return false
	end

	local me = UnitGUID("player")
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

-- Whether this client will say what happened at all. Vanilla and TBC both
-- carry the call, so this is expected to be true on both targets; it is asked
-- rather than assumed for the reason every other shim in this addon is asked,
-- and a client without it has to say so in the panel rather than draw an empty
-- column with no explanation in it.
function CombatFeed.Ready()
	return type(CombatLogGetCurrentEventInfo) == "function"
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

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		swingIcon = ns.SpellTexture(AUTO_ATTACK) or UNKNOWN
		return
	end
	CombatFeed.OnLog()
end)
