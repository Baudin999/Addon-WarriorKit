local ADDON, ns = ...

local Breakdown = {}
ns.Breakdown = Breakdown

--------------------------------------------------------------------------
-- What this character actually does
--
-- One row per ability, kept for as long as you keep it: how often it landed,
-- how often it crit, how often it was dodged, how much it did. It is the
-- question Details answers with a fight timeline and forty panes, asked the
-- other way round: not what happened in that pull, but what this character has
-- been doing for the last month.
--
-- **Counters, not history.** Every question this exists to answer is a ratio
-- over counters. Crit chance is crits over landed hits. Miss chance is the miss
-- table over attempts. What share of your damage is Thunder Clap is a sum over
-- rows. None of them needs the event that produced them kept, and keeping the
-- events is the one thing this could not afford: an evening of solo play is
-- tens of thousands of combat log lines, and the client writes saved variables
-- by serialising the whole table to Lua source at logout.
--
-- So the table grows with the number of abilities you use and never with the
-- number of swings you take. Forty spells across four level bands is well under
-- a hundred kilobytes of text, against megabytes for the history nobody asked
-- for.
--
-- **There is no flush, so there is nothing to flush.** The client writes saved
-- variables at logout, at a reload and on quitting, and an addon cannot ask for
-- a write in between; the only way to force one is ReloadUI, which is why Titan
-- puts a confirmation box in front of changing a profile. This file therefore
-- does not accumulate into a private table and copy it over at PLAYER_LOGOUT.
-- It counts directly into ns.dbc, which is the table the client serialises, so
-- there is no moment where the record exists only in memory and no logout hook
-- that can be forgotten. A crash costs the session either way.
--
-- **You, and not the group.** Meter/Meter.lua reads the same event and counts
-- everybody, deliberately, because it is answering what the group did to this
-- pull. This counts only what your own GUID did, and that is the one filter
-- that keeps the table bounded: counting the group would grow it by every
-- stranger you have ever been in a party with.
--
-- Nothing here is on a ticker. A counter moves when the log says so.
--------------------------------------------------------------------------

-- The key a white swing is filed under. Zero, because it is not a spell and has
-- no id, and because a numeric key sits beside the real ones without the table
-- needing two kinds of key in it.
local MELEE = 0

--------------------------------------------------------------------------
-- The level bands
--
-- A crit rate pooled across grey trash and a boss is the average of two
-- unrelated numbers. In this era the target's level drives miss and dodge hard,
-- and miss and dodge are half of what this table is for, so every counter is
-- filed under the band the target was in.
--
-- Four bands and not three, and the fourth is the honest one. The combat log
-- does not carry the target's level: you only ever learn it from a unit token,
-- which means the mob was your target or had a nameplate up. Anything you hit
-- without ever seeing lands in UNKNOWN rather than being quietly folded into
-- "same level", which is the answer that would silently flatter every rate in
-- the table.
--------------------------------------------------------------------------

local UNDER, NEAR, HIGH, UNKNOWN = 1, 2, 3, 4
local BANDS = { UNDER, NEAR, HIGH, UNKNOWN }

-- Read by the panel and by the slash word, so the wording is written once.
local BAND_WORDS = {
	[UNDER] = "at or under you",
	[NEAR] = "one or two over",
	[HIGH] = "three or more over",
	[UNKNOWN] = "level not seen",
}

function Breakdown.Bands()
	return BANDS
end

function Breakdown.BandWord(band)
	return BAND_WORDS[band] or "?"
end

-- Which band the pane is reading, as Rank wants it: a band, or nil for all four
-- added together.
--
-- Stored as a number with zero meaning all, rather than as nil, because
-- Core/Core.lua's ApplyDefaults only fills a key that is nil and a setting
-- whose default is nil is a setting that is re-defaulted at every login.
function Breakdown.Band()
	local band = ns.db and ns.db.breakdownBand or 0
	return (band > 0) and band or nil
end

--------------------------------------------------------------------------
-- Where the numbers sit in the log
--
-- The client hands over twenty-one values and the meaning of the twelfth
-- onwards depends on the subevent. Buttons/Reaction.lua and Feeds/Combat.lua
-- both write this down already and both agree; this is the third reader and it
-- reads the same slots. A swing puts its amount at twelve, a spell puts its id,
-- name and school there and its amount at fifteen, and overkill is always the
-- slot after the amount.
--------------------------------------------------------------------------

local DAMAGE = {
	SWING_DAMAGE          = { amount = 12, crit = 18 },
	SPELL_DAMAGE          = { amount = 15, spell = 12, crit = 21 },
	SPELL_PERIODIC_DAMAGE = { amount = 15, spell = 12, crit = 21 },
	RANGE_DAMAGE          = { amount = 15, spell = 12, crit = 21 },
	DAMAGE_SHIELD         = { amount = 15, spell = 12, crit = 21 },
}

-- Where the miss type sits. A swing carries it at twelve because it has no
-- spell in front of it; everything else carries the spell first and the type at
-- fifteen.
local MISSED = {
	SWING_MISSED = 12,
	SPELL_MISSED = 15,
	RANGE_MISSED = 15,
}

--------------------------------------------------------------------------
-- The store
--
-- Kept per character, in WarriorKitCharDB, because it is a record of what this
-- warrior did and an account-wide one would average a level 70 over an alt that
-- has never left the starting zone. Core/Core.lua draws that distinction for
-- the loadout backup and it is the same distinction.
--
-- Registered as three flat keys rather than one nested table on purpose.
-- ApplyDefaults copies a default one level deep, so a nested table inside a
-- default would be handed out by reference and every character would share the
-- one table. Flat keys each get their own copy.
--------------------------------------------------------------------------

-- The most abilities this will ever file. A character uses a few dozen in its
-- life and this is an order of magnitude above that, so it is not a limit
-- anybody will meet by playing. It is here because an unbounded table in a
-- saved variable is a file that grows forever, and the one way this design
-- could become unbounded is a client that reports spell ids this file has never
-- seen. Refusals are counted and said out loud rather than dropped in silence.
local MAX_SPELLS = 400

local refused = 0
local myLevel = 0

-- What a white swing is called, in this client's own language. Auto Attack is
-- spell 6603 on both of these clients and is where Feeds/Combat.lua takes its
-- swing icon from, so the word and the picture come from the same place.
-- Resolved once and floored on a word rather than left nil, because a nil here
-- would file every swing you have ever made under "Spell 0".
local AUTO_ATTACK = 6603
local meleeName

local function MeleeName()
	if not meleeName then
		meleeName = ns.SpellName(AUTO_ATTACK) or "Melee"
	end
	return meleeName
end

-- guid -> level, for the mobs the client will currently answer for.
--
-- Bounded by construction rather than by pruning: an entry arrives when a
-- nameplate appears or you take a target, and leaves when that plate does or
-- when you take a different target. That is at most the plates on screen plus
-- one, a few dozen, and it never grows across an evening the way a cache keyed
-- by every mob you have ever hit would.
--
-- The target half had no such leaving. Every target you ever took wrote a level
-- in, only a plate going away took one out, and a mob targeted out of range of
-- any plate stayed in the table for the session: an evening of tab targeting is
-- thousands of entries nothing reads again. So the plates are a set of their
-- own, and a target that has no plate is dropped as soon as you look elsewhere.
local levels = {}
local plates = {}

-- The guid the target path last wrote a level for, so the next target change
-- knows what to drop.
local targeted

local function Store()
	return ns.dbc and ns.dbc.breakdownSpells
end

function Breakdown.Since()
	return (ns.dbc and ns.dbc.breakdownSince) or 0
end

-- Everything counted so far, thrown away. The timestamp goes with it, because a
-- lifetime number that started before you changed weapon answers a different
-- question from one that started after, and without a fresh start there is no
-- way to ask the new one.
function Breakdown.Reset()
	if not ns.dbc then
		return false
	end
	ns.dbc.breakdownSpells = {}
	ns.dbc.breakdownSince = time()
	refused = 0
	return true
end

function Breakdown.Count()
	local store = Store()
	if not store then
		return 0
	end
	local held = 0
	for _ in pairs(store) do
		held = held + 1
	end
	return held
end

function Breakdown.Refused()
	return refused
end

--------------------------------------------------------------------------
-- Counting
--------------------------------------------------------------------------

-- Which band the thing you just hit was in. UNKNOWN wherever the client has not
-- said, which includes every mob you never targeted and never saw a plate for.
--
-- A level of minus one is the client saying "much higher than you", which is
-- what it answers for a skull, and that is HIGH rather than unknown: it is a
-- real answer and a definite one.
local function Band(guid)
	local level = levels[guid]
	if not level or myLevel <= 0 then
		return UNKNOWN
	end
	if level < 0 then
		return HIGH
	end
	local over = level - myLevel
	if over <= 0 then
		return UNDER
	end
	if over <= 2 then
		return NEAR
	end
	return HIGH
end

-- The record for one ability, made on the first event that names it.
--
-- This allocates, and it is the one place in the file that does. It runs once
-- per ability per character rather than once per event, so the steady state
-- after your first fight of the session is table writes and nothing else.
local function Spell(key, name)
	local store = Store()
	if not store then
		return nil
	end
	if key == MELEE then
		name = MeleeName()
	end

	local record = store[key]
	if record then
		-- A rank learned after the record was made, or a client that had not
		-- cached the name when the first event arrived. The name is only ever a
		-- fallback for an id the client will no longer resolve, so it is worth
		-- correcting and not worth guarding beyond this.
		if name and record.name ~= name then
			record.name = name
		end
		return record
	end

	if Breakdown.Count() >= MAX_SPELLS then
		refused = refused + 1
		return nil
	end

	record = { name = name, casts = 0, at = {} }
	store[key] = record
	return record
end

local function Slot(record, band)
	local slot = record.at[band]
	if not slot then
		slot = { landed = 0, crits = 0, damage = 0, wasted = 0, crit = 0, max = 0, miss = {} }
		record.at[band] = slot
	end
	return slot
end

-- One landed hit.
--
-- Effective damage and the wasted part are kept apart, which is the convention
-- Meter/Meter.lua argues for and this file has to match or the two readouts
-- cannot be compared. The raw number is damage plus wasted and is still there.
--
-- Crit damage is kept apart from the total for the same reason, and it is what
-- makes both averages derivable from four numbers: the average normal hit is
-- the damage that was not a crit over the hits that were not crits, and the
-- average crit is the other half. A single blended average answers neither
-- question and cannot be taken apart afterwards.
local function Landed(record, band, amount, wasted, crit)
	local slot = Slot(record, band)
	slot.landed = slot.landed + 1
	slot.damage = slot.damage + amount
	if wasted > 0 then
		slot.wasted = slot.wasted + wasted
	end
	if crit then
		slot.crits = slot.crits + 1
		slot.crit = slot.crit + amount
	end
	-- The one figure that is not derivable from the others, so it is the one
	-- figure stored twice.
	if amount > slot.max then
		slot.max = amount
	end
end

-- One attempt that did not land, filed under what stopped it.
--
-- The type matters and is not folded into a single "missed" counter. A dodge
-- says something about where you were standing and a parry says something about
-- what you were hitting, and a warrior reading one pooled number learns
-- neither. The client names ten of these and the table only ever holds the ones
-- that actually happened to you.
local function Missed(record, band, kind)
	local slot = Slot(record, band)
	slot.miss[kind] = (slot.miss[kind] or 0) + 1
end

-- The twenty one values the client hands over and your own GUID after them,
-- which is what ns.CombatLog adds to the list. Read positionally, because the
-- positions are the whole contract, and the blanks are the values this file has
-- no use for.
function Breakdown.OnLog(_, subevent, _, sourceGUID, _, _, _, destGUID, _, _, _,
	a12, a13, _, a15, a16, _, a18, _, _, a21, me)
	-- The switch is account wide and the record is this character's. Turning
	-- counting off is a preference about the addon; what your warrior has done
	-- is a fact about your warrior, and Core/Core.lua draws that line for the
	-- loadout backup for the same reason.
	if not ns.db or not ns.db.breakdown or not ns.dbc then
		return false
	end

	if not me or sourceGUID ~= me then
		return false
	end

	-- What you pressed, which is not the same question as what landed. An
	-- ability that produced no damage event at all is invisible in every other
	-- counter here, and "did that cast pay for itself" is partly a question
	-- about how often you pressed it.
	if subevent == "SPELL_CAST_SUCCESS" then
		local record = Spell(a12, a13)
		if record then
			record.casts = record.casts + 1
		end
		return true
	end

	local missAt = MISSED[subevent]
	if missAt then
		local kind = (missAt == 12) and a12 or a15
		if type(kind) ~= "string" then
			return false
		end
		local record = Spell(missAt == 12 and MELEE or a12, missAt == 12 and nil or a13)
		if record then
			Missed(record, Band(destGUID), kind)
		end
		return true
	end

	local shape = DAMAGE[subevent]
	if not shape then
		return false
	end

	local amount = (shape.amount == 12) and a12 or a15
	if type(amount) ~= "number" or amount <= 0 then
		return false
	end

	-- Always the slot after the amount, on every shape in the table above,
	-- which is why the table only carries the one index. The client sends minus
	-- one on every hit that killed nothing, so the sign is tested and not just
	-- the type: subtracting a minus one would report more damage than was done.
	local wasted = (shape.amount == 12) and a13 or a16
	if type(wasted) ~= "number" or wasted < 0 then
		wasted = 0
	end
	if wasted > 0 then
		amount = amount - wasted
		if amount < 0 then
			amount = 0
		end
	end

	local crit = (shape.crit == 18) and a18 or a21
	local record = Spell(shape.spell and a12 or MELEE, shape.spell and a13 or nil)
	if record then
		Landed(record, Band(destGUID), amount, wasted, crit and true or false)
	end
	return true
end

--------------------------------------------------------------------------
-- Reading it back
--
-- Rolled up by name rather than handed over by id.
--
-- The store keys on spell id because that is what the log carries and it is
-- unambiguous. A name is localised and collides: the eight ranks of Heroic
-- Strike are eight ids and one word. Reading by id would give eight thin rows
-- nobody wants, and storing by name would throw away the ability to ever look
-- at one rank on its own. So it is stored by id and added up by name here,
-- which costs nothing and keeps both readings available.
--
-- One thing that does not survive the roll up cleanly, and the panel says so: a
-- rate pools across ranks correctly, because it is per attempt either way, and
-- an average hit does not. The average for a multi rank ability is a weighted
-- blend of ranks you outgrew and the one you use now.
--------------------------------------------------------------------------

-- Filled and sorted in place, so opening the pane does not build a table per
-- ability every time it refreshes.
local ranked = {}
local byName = {}

local function Blank(row)
	row.casts, row.landed, row.crits = 0, 0, 0
	row.damage, row.wasted, row.crit, row.max, row.misses = 0, 0, 0, 0, 0
	for kind in pairs(row.miss) do
		row.miss[kind] = nil
	end
end

-- A fresh row is blanked on the way out rather than built with its fields
-- written twice. Every field Fold adds to has to exist as a number before the
-- first add, and a row made mid walk has not been through the blanking pass at
-- the top of Rank, which is the one path that skipped it.
local function Row(name)
	local row = byName[name]
	if row then
		return row
	end
	row = { name = name, miss = {} }
	byName[name] = row
	Blank(row)
	return row
end

local function Fold(row, slot)
	row.landed = row.landed + slot.landed
	row.crits = row.crits + slot.crits
	row.damage = row.damage + slot.damage
	row.wasted = row.wasted + slot.wasted
	row.crit = row.crit + slot.crit
	if slot.max > row.max then
		row.max = slot.max
	end
	for kind, count in pairs(slot.miss) do
		row.miss[kind] = (row.miss[kind] or 0) + count
		row.misses = row.misses + count
	end
end

-- Damage, always, and the name to break a tie so that two rows that have done
-- the same amount do not swap places every time the pane refreshes.
--
-- It ranked by casts and by landed hits too for a while, off a field name held
-- in an upvalue. Both were answers to a question this table does not ask. What
-- it is for is where your damage goes, and a ranking by press count puts Battle
-- Shout above Mortal Strike and reads like a bug.
local function Bigger(a, b)
	if a.damage == b.damage then
		return a.name < b.name
	end
	return a.damage > b.damage
end

-- Every ability that has swung at something, biggest damage first.
--
-- band is nil for all four bands added together, or one of them on its own.
--
-- A row has to have attempted damage to be in the ranking: it landed a hit, or
-- something stopped one. A cast on its own is not enough, which is what keeps
-- Battle Shout, Charge and every stance out of a table ranked by damage, where
-- they can only ever be a run of zeroes under the abilities you came to read.
-- They are still counted and still in the store, because an ability that does
-- nothing today is one damage event away from being worth a row, and the store
-- is what decides that rather than a list of spell ids typed here.
--
-- Attempts and not damage, so an ability that has only ever been dodged keeps
-- its row. Zero damage across four dodges is not the same fact as zero damage
-- because the thing does no damage, and it is the more useful of the two.
function Breakdown.Rank(band)
	local store = Store()
	for _, row in pairs(byName) do
		Blank(row)
		row.live = false
	end
	for index = #ranked, 1, -1 do
		ranked[index] = nil
	end
	if not store then
		return ranked, 0
	end

	for key, record in pairs(store) do
		local name = record.name or ("Spell " .. tostring(key))
		local row = Row(name)
		if not row.live then
			row.live = true
			row.key = key
		end
		row.casts = row.casts + (record.casts or 0)
		for slotBand, slot in pairs(record.at) do
			if not band or slotBand == band then
				Fold(row, slot)
			end
		end
	end

	local total = 0
	for _, row in pairs(byName) do
		if row.live and (row.landed > 0 or row.misses > 0) then
			ranked[#ranked + 1] = row
			total = total + row.damage
		end
	end

	table.sort(ranked, Bigger)
	return ranked, total
end

--------------------------------------------------------------------------
-- The derived figures
--
-- Every one of these is a division the pane would otherwise do inline, and
-- every one of them has a denominator that can be zero on a row that has been
-- pressed once and missed. They are here so that the zero is handled in one
-- place rather than in six.
--------------------------------------------------------------------------

-- What fraction of the attempts landed as a critical. Crits are a subset of
-- landed hits, not a separate outcome, so the denominator is every hit that
-- landed and not every attempt.
function Breakdown.CritRate(row)
	if not row or row.landed <= 0 then
		return nil
	end
	return row.crits / row.landed
end

-- What fraction of the attempts did not land at all. An attempt is a hit that
-- landed or one that was stopped, and a cast that produced neither is not an
-- attempt, which is why casts are not in this denominator.
function Breakdown.MissRate(row)
	if not row then
		return nil
	end
	local attempts = row.landed + row.misses
	if attempts <= 0 then
		return nil
	end
	return row.misses / attempts
end

function Breakdown.Attempts(row)
	return row and (row.landed + row.misses) or 0
end

-- The average hit that was not a critical, and the average one that was. Two
-- functions because they are two different numbers and a blend of them is a
-- number that describes no hit you have ever landed.
function Breakdown.AverageHit(row)
	if not row then
		return nil
	end
	local normal = row.landed - row.crits
	if normal <= 0 then
		return nil
	end
	return (row.damage - row.crit) / normal
end

function Breakdown.AverageCrit(row)
	if not row or row.crits <= 0 then
		return nil
	end
	return row.crit / row.crits
end

-- How often one outcome stopped this ability, as a fraction of every attempt.
-- The reason the miss table is kept by type rather than summed: a warrior wants
-- to see dodge on its own, because dodge is about facing and is the one of
-- these you can do something about.
function Breakdown.MissRateOf(row, kind)
	if not row then
		return nil
	end
	local count = row.miss[kind]
	if not count then
		return nil
	end
	local attempts = row.landed + row.misses
	if attempts <= 0 then
		return nil
	end
	return count / attempts
end

--------------------------------------------------------------------------

-- Whether this client will say what happened at all. Both targets carry the
-- call, so this is expected to be true on both; it is asked rather than assumed
-- for the reason every other probe in this addon is asked, and a client without
-- it has to say so in the panel rather than showing an empty table with no
-- explanation on it.
function Breakdown.Ready()
	return ns.CombatLog.Ready()
end

function Breakdown.Describe()
	if not ns.db or not ns.db.breakdown then
		return "off, nothing is being counted"
	end
	if not Breakdown.Ready() then
		return "this client has no combat log API, so nothing can be counted"
	end

	local held = Breakdown.Count()
	if held == 0 then
		return "on, nothing counted yet"
	end

	local line = ("%d abilities since %s"):format(held,
		date("%d %b", Breakdown.Since()))
	if refused > 0 then
		line = line .. (", and %d were refused at the %d ability limit")
			:format(refused, MAX_SPELLS)
	end
	return line
end

function Breakdown.MeleeKey()
	return MELEE
end

-- On the log while the switch is on and off it entirely while it is not.
--
-- This file registered the event at load whatever the setting said, so a player
-- who had turned counting off still paid an unpack of every combat log line in
-- the zone for a record nothing was writing to.
function Breakdown.Apply()
	if ns.db and ns.db.breakdown then
		ns.CombatLog.Subscribe(Breakdown.OnLog)
	else
		ns.CombatLog.Unsubscribe(Breakdown.OnLog)
	end
end

--------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_LEVEL_UP")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
-- Guarded the way Marking/Marking.lua guards it. A client with no nameplate
-- API answers no levels at all, and everything lands in the band that says so.
if C_NamePlate then
	events:RegisterEvent("NAME_PLATE_UNIT_ADDED")
	events:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
end

events:SetScript("OnEvent", function(_, event, unit)
	if event == "NAME_PLATE_UNIT_ADDED" then
		local guid = UnitGUID(unit)
		if guid then
			plates[guid] = true
			levels[guid] = UnitLevel(unit)
		end
		return
	end

	if event == "NAME_PLATE_UNIT_REMOVED" then
		local guid = UnitGUID(unit)
		-- Kept while it is still your target, because a plate going away and a
		-- mob you are still fighting are not the same thing: the plate is gone
		-- the moment it leaves the screen and the target is not.
		if guid then
			plates[guid] = nil
			if guid ~= UnitGUID("target") then
				levels[guid] = nil
			end
		end
		return
	end

	if event == "PLAYER_TARGET_CHANGED" then
		local guid = UnitGUID("target")
		-- The one you were looking at, dropped unless a plate is holding it up.
		-- Anything a plate wrote is the plate's to take away.
		if targeted and targeted ~= guid and not plates[targeted] then
			levels[targeted] = nil
		end
		targeted = guid
		if guid then
			levels[guid] = UnitLevel("target")
		end
		return
	end

	Breakdown.Apply()
	myLevel = UnitLevel("player") or 0
	-- Stamped on the first login that has the saved table rather than at the
	-- first counted hit, so "since" means when the record started and not when
	-- you first swung at something.
	if ns.dbc and (ns.dbc.breakdownSince or 0) == 0 then
		ns.dbc.breakdownSince = time()
	end
end)
