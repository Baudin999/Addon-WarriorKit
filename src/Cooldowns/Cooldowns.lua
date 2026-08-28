local ADDON, ns = ...

local Cooldowns = {}
ns.Cooldowns = Cooldowns

--------------------------------------------------------------------------
-- The long cooldowns
--
-- What this answers is one question the rest of the addon does not: how long
-- until the thing you win the fight with is back. The bars already draw a swipe
-- on every square, and a swipe on a square that is off the bottom of the screen
-- or on a page you are not standing in says nothing at all. Death Wish is three
-- minutes, Recklessness is thirty, Shield Wall is thirty, and a warrior counts
-- all three in their head because nothing on the screen counts them.
--
-- Two sources, and the split is the whole of this file.
--
-- Your class's list is facts and lives in Class\<yours>.lua, which is the rule
-- every other part follows. Nothing here names a spell, and a class that
-- registers no `cooldowns` field gets a row of trinkets or no row at all.
--
-- The trinkets are not a class fact and are the same two slots for everybody,
-- so they are here. Which trinket is worth a square is decided by the client:
-- an item with a use effect answers ns.ItemSpell with the name of it and a
-- passive one answers nothing, so the row carries the ones you press and skips
-- the ones you merely wear. That test is better than a cooldown reading,
-- because a passive trinket with a proc on it has a cooldown too and a square
-- saying "ready" about a proc is a square telling you to press something you
-- cannot press.
--
-- What is deliberately not here is a judgement about which cooldowns matter.
-- The class files list what is long and worth counting, IsSpellKnown drops
-- whatever this character has not learned or has not talented, and one switch
-- per entry drops whatever you personally do not want to look at. Three filters
-- and none of them is this file having an opinion about your spec.
--
-- Nothing in here draws. Row.lua is the row and Feature.lua is the settings,
-- which is the seam every part in this addon has.
--------------------------------------------------------------------------

-- Below this a cooldown is the global rather than the ability's own. The same
-- 1.5 Buttons\Slot.lua and Buffs\Racials.lua carry, and it is tested against
-- the whole duration rather than what is left of it: a three minute cooldown
-- with a second to run is still a cooldown, and a ready spell caught under the
-- global you just triggered is not.
local GCD = 1.5

-- How many entries one class may put on the row. Eight, which is one more than
-- any class file uses today and is a ceiling rather than a target: the row is
-- built once at login at the ceiling, because a frame cannot be destroyed on
-- these clients.
local MAX_CLASS = 8

-- How many of your own aura slots the client will answer for. Forty, the same
-- number every aura scan in the addon stops at.
local SLOTS = 40

local NONE = {}

--------------------------------------------------------------------------
-- The two trinkets
--
-- One entry each, built at load and filled in whenever the worn gear moves.
-- `slot` is what makes an entry a trinket: everything that reads state branches
-- on it once, because a worn item answers a different call from a spell and
-- nothing else about the two differs.
--
-- The keys are the words you type at them, so `/wk cooldowns trinket1 off`
-- silences the top one. Numbered rather than named after whatever is in the
-- slot today, because the switch is per character and outlives the trinket.
--------------------------------------------------------------------------

local TRINKETS = {
	{ key = "trinket1", slot = ns.Gear.TRINKET1 },
	{ key = "trinket2", slot = ns.Gear.TRINKET2 },
}

-- The whole list this character could draw, class first and trinkets last, held
-- once the client has answered for the class. Built the way Upkeep.Fixed builds
-- its own, and cached for the same reason: it cannot change after login.
local shipped

-- What is actually drawn, which is `shipped` with the switched off, the
-- unknown and the unnameable taken out. Rebuilt on an event, never on a tick.
local order = {}

-- How many times the list has been rebuilt, so the row can tell that what it
-- laid out is stale without comparing the list to itself. A count rather than a
-- length, because a rebuild can leave the list exactly as long as it was and
-- hold different entries: one spell trained and another switched off in the same
-- moment is two squares changing places and no number moving.
local epoch = 0

-- Aura name to entry, for the scan. A burst cooldown that is running is the
-- other half of the question this row answers, and the client will not say so:
-- the spell's cooldown starts the moment you press it and says nothing about
-- whether the fifteen seconds you pressed it for are still going.
local wanted = {}

--------------------------------------------------------------------------
-- Resolving one entry
--------------------------------------------------------------------------

-- The first of an entry's ids this client both names and this character knows,
-- with the name and the picture taken off it.
--
-- Two questions in one walk and they are not the same question. A client that
-- cannot name an id is a client that never shipped the spell, which is most of
-- what separates Era from Burning Crusade in the class files. A character that
-- does not know a spell it can name is a talent unspent or a trainer unvisited,
-- and that one changes during a session, which is why SPELLS_CHANGED rebuilds.
local function Resolve(entry)
	entry.id, entry.name, entry.texture = nil, nil, nil
	for index = 1, #(entry.spells or NONE) do
		local id = entry.spells[index]
		local name = ns.SpellName(id)
		if name and IsSpellKnown(id) then
			entry.id, entry.name = id, name
			entry.texture = ns.SpellTexture(id)
			return
		end
	end
end

--------------------------------------------------------------------------
-- The list
--------------------------------------------------------------------------

function Cooldowns.Ceiling()
	return MAX_CLASS + #TRINKETS
end

function Cooldowns.Count()
	return #order
end

function Cooldowns.Epoch()
	return epoch
end

function Cooldowns.Entry(index)
	return order[index]
end

-- What your class brought, plus the two trinket slots everybody has.
--
-- Nil until the client says what class this is, which is the rule Class.lua
-- states: an answer taken at file scope would be nil, and a nil written down
-- once would leave a warrior with no row for the session.
function Cooldowns.All()
	if shipped then
		return shipped
	end
	if not ns.Class.Token() then
		return NONE
	end

	local mine = ns.Class.Of("cooldowns") or NONE
	assert(#mine <= MAX_CLASS,
		("%s puts %d entries on the cooldown row and the cap is %d")
			:format(ns.Class.Label(), #mine, MAX_CLASS))

	shipped = {}
	for index = 1, #mine do
		shipped[index] = mine[index]
		-- Resolved here rather than only in Rebuild, because the options page is
		-- built at login off this list and labels its switches with the client's
		-- own name for each spell. A page built a moment before the first
		-- rebuild would carry the entry's key instead, and a label is a string
		-- the page keeps rather than a question it asks again.
		Resolve(shipped[index])
	end
	for index = 1, #TRINKETS do
		shipped[#shipped + 1] = TRINKETS[index]
	end
	return shipped
end

-- Which class claims a slash word this character has no entry for, or nil for a
-- word nobody claims, which is an ordinary typo. The same answer Upkeep gives
-- and for the same reason: `/wk cooldowns iceblock` on a warrior would
-- otherwise fall through to the bare on|off toggle, switch the whole row off
-- and report that it had done something else.
function Cooldowns.Elsewhere(word)
	for _, def in pairs(ns.Class.All()) do
		local list = def.cooldowns or NONE
		for index = 1, #list do
			if list[index].key == word then
				return def.label
			end
		end
	end
	return nil
end

function Cooldowns.ByWord(word)
	local list = Cooldowns.All()
	for index = 1, #list do
		if list[index].key == word then
			return list[index]
		end
	end
	return nil
end

--------------------------------------------------------------------------
-- What you have switched off
--
-- Per character, and the argument is the one Buffs\Feature.lua makes for its
-- own: whether Shield Wall is worth a square is a fact about the character and
-- not a preference about the row. A tank wants it. The same account's alt has
-- not learned it, which IsSpellKnown answers, and the same account's second
-- warrior has learned it and never presses it, which only you can answer.
--------------------------------------------------------------------------

function Cooldowns.Watched(key)
	return ns.dbc.cooldownWatch[key] ~= false
end

function Cooldowns.SetWatched(key, on)
	-- A branch rather than `on and nil or false`, which is shorter and wrong:
	-- `and nil` is falsy, the `or` takes over, and every call writes false.
	if on then
		ns.dbc.cooldownWatch[key] = nil
	else
		ns.dbc.cooldownWatch[key] = false
	end
	Cooldowns.Rebuild()
end

-- How many are switched off, and their names in one phrase, so a silenced entry
-- is visible somewhere. A square you turned off six weeks ago and cannot find
-- any trace of is the same defect as one you learned to ignore.
function Cooldowns.Silent()
	local list = Cooldowns.All()
	local count, names = 0, ""
	for index = 1, #list do
		local entry = list[index]
		if not Cooldowns.Watched(entry.key) then
			count = count + 1
			names = names .. (count > 1 and ", " or "") .. (entry.name or entry.key)
		end
	end
	return count, names
end

-- What is in the two trinket slots, and whether it is a thing you press.
--
-- Read whenever the worn gear moves and never on the tick. The name is the use
-- effect's rather than the item's, because that is what the tooltip on the
-- square has to say and it is the string the aura scan matches on: an item
-- called Bloodlust Brooch puts an aura on you under the name of its effect.
function Cooldowns.Refit()
	for index = 1, #TRINKETS do
		local entry = TRINKETS[index]
		local link = GetInventoryItemLink("player", entry.slot)
		local spell = ns.ItemSpell(link)
		local item, icon = ns.ItemInfo(link)
		entry.id = nil
		entry.name = spell
		entry.item = item
		entry.texture = spell and icon or nil
	end
end

-- What is in one trinket slot, in the panel's words. Three answers and the
-- middle one is the whole reason the slot can be empty on the row while
-- something is sitting in it: a trinket with no use effect is worn rather than
-- pressed, and nothing about wearing it is worth a square.
function Cooldowns.Worn(slot)
	for index = 1, #TRINKETS do
		local entry = TRINKETS[index]
		if entry.slot == slot then
			if not entry.item then
				return "empty"
			end
			if not entry.name then
				return entry.item .. ", worn rather than pressed"
			end
			return entry.item .. ", " .. entry.name
		end
	end
	return "empty"
end

-- Rebuild the drawn list out of what this character has, has learned and has
-- left switched on. On an event, never on a tick.
function Cooldowns.Rebuild()
	Cooldowns.Refit()

	for index = #order, 1, -1 do
		order[index] = nil
	end
	for name in pairs(wanted) do
		wanted[name] = nil
	end

	local list = Cooldowns.All()
	for index = 1, #list do
		local entry = list[index]
		if not entry.slot then
			Resolve(entry)
		end
		entry.present = false
		if entry.name and Cooldowns.Watched(entry.key) then
			order[#order + 1] = entry
			wanted[entry.name] = entry
		end
	end

	epoch = epoch + 1
	Cooldowns.Scan()
end

-- Which of the drawn entries are running right now, as auras on you. Called
-- from UNIT_AURA and never from the ticker, which is the rule Buffs\Upkeep.lua
-- states at length: forty slots ten times a second is four hundred lookups to
-- learn what one event already said.
function Cooldowns.Scan()
	for index = 1, #order do
		order[index].present = false
	end

	local index = 1
	while index <= SLOTS do
		local name = ns.BuffName("player", index)
		if not name then
			break
		end
		local entry = wanted[name]
		if entry then
			entry.present = true
		end
		index = index + 1
	end
end

--------------------------------------------------------------------------
-- What one square is doing
--
-- On the tick. Nothing below allocates.
--------------------------------------------------------------------------

-- The status, the swipe and whether the window it opens is still open, as four
-- values rather than a table, because a table here is one allocation per square
-- per tick to say what four values already say.
--
-- Four of the ten statuses are reachable. "empty" is a slot past the end of the
-- list, "unknown" is the client refusing to answer for something it otherwise
-- lists, "cooldown" is a real wait and "ready" is a press. Range and cost are
-- not asked: a cooldown row that greyed Death Wish out because you are ten rage
-- short would be answering a question the bar already answers, and the answer
-- moves twice a second.
function Cooldowns.State(index)
	local entry = order[index]
	if not entry then
		return "empty", 0, 0, false
	end

	local start, duration, enabled
	if entry.slot then
		start, duration, enabled = ns.InventoryCooldown(entry.slot)
	else
		start, duration, enabled = ns.SpellCooldown(entry.id)
	end

	if enabled == false then
		return "unknown", 0, 0, false
	end
	if duration and duration > GCD then
		return "cooldown", start, duration, entry.present
	end
	return "ready", start, duration, entry.present
end

-- Is anything on the row still recovering. What the row is up for out of
-- combat, and the reason it is not up the rest of the time.
--
-- On the tick.
function Cooldowns.Busy()
	for index = 1, #order do
		local status = Cooldowns.State(index)
		if status == "cooldown" then
			return true
		end
	end
	return false
end

--------------------------------------------------------------------------

-- Why there is no row, in this character's own words, or nil where there is
-- one. Said once here so the panel, the slash word and the status line give the
-- same reason rather than three sentences that have to be kept in step.
function Cooldowns.Refusal()
	if #order > 0 then
		return nil
	end
	local list = Cooldowns.All()
	if #list <= #TRINKETS and not ns.Class.Of("cooldowns") then
		return ("nothing is listed for a %s, so the row carries your trinkets and"
			.. " nothing else"):format(ns.Class.Label())
	end
	local silent = Cooldowns.Silent()
	if silent > 0 then
		return "everything this character has is switched off"
	end
	return "nothing on the list is learned yet, so there is nothing to count"
end

function Cooldowns.Describe()
	if not ns.db.cooldowns then
		return "off"
	end

	local refusal = Cooldowns.Refusal()
	if refusal then
		return refusal
	end

	local silent, names = Cooldowns.Silent()
	local tail = silent > 0 and ("; " .. names .. " switched off") or ""

	local waiting = 0
	for index = 1, #order do
		local status = Cooldowns.State(index)
		if status == "cooldown" then
			waiting = waiting + 1
		end
	end
	if waiting == 0 then
		return ("%d tracked, all ready"):format(#order) .. tail
	end
	return ("%d tracked, %d on cooldown"):format(#order, waiting) .. tail
end
