local ADDON, ns = ...

local Upkeep = {}
ns.Upkeep = Upkeep

--------------------------------------------------------------------------
-- What should be up and is not
--
-- Nothing in this addon read your own auras before this file. That is a real
-- hole rather than a missing convenience: a sharpening stone that wore off
-- forty minutes ago costs more damage over a raid than any single rotational
-- mistake, and Battle Shout falling off says nothing at all.
--
-- Two sources, because the client answers two different questions and only one
-- of them is an aura.
--
--   A weapon's temporary enchant is not a buff on you. It does not appear in an
--   aura scan at any index, and GetWeaponEnchantInfo is the only thing in the
--   client that knows about it.
--
--   Everything else is a buff on you and is found by walking your own auras.
--
-- Matching is on the name, never on the id, which is the rule the debuff row on
-- the enemy bars already follows. Battle Shout has eight ranks and the aura on
-- you carries the id of whichever rank was shouted, so an id comparison would
-- go dark the moment you trained the next one. The ids below exist only to ask
-- this client what it calls the spell in the language it is running in, which
-- is what makes the comparison locale independent.
--
-- The aura scan is event driven and never runs from the ticker. UNIT_AURA fires
-- for every aura you gain and every aura you lose, so a walk of forty slots ten
-- times a second would be four hundred lookups to learn what one event already
-- said. It is worse than that on a client carrying C_UnitAuras, where each slot
-- hands back a freshly built table: that is allocation on a ticker, which is
-- the thing scripts/harness.lua gates and check.sh bans.
--
-- The weapon enchants are the exception and are read on the tick, because a
-- stone that runs out fires nothing. Two values out of one call, no table and
-- no string, which is what makes that affordable.
--------------------------------------------------------------------------

local MAIN, OFF = ns.Gear.MAINHAND, ns.Gear.OFFHAND

-- Probed rather than trusted, and resolved to a local at load the way
-- Swing/Swing.lua resolves UnitAttackSpeed. Nothing installed on this machine
-- calls OffhandHasWeapon at all, and the only unguarded GetWeaponEnchantInfo
-- here is inside a Details library written for a much later client. A missing
-- one costs the weapon half of this feature; a missing one called anyway costs
-- an error ten times a second, which is the failure that gets a whole addon
-- offered up for disabling.
local GetWeaponEnchantInfo = _G.GetWeaponEnchantInfo
local OffhandHasWeapon = _G.OffhandHasWeapon

-- How many of your own aura slots the client will answer for. Forty is the
-- number every aura scan in the game uses and the number the enemy bars' own
-- debuff walk stops at.
local SLOTS = 40

-- How many spells of your own you may add on top of the list below. Six,
-- because the list this covers in practice is a flask and one or two elixirs,
-- and a nag row long enough to need scrolling is a nag row nobody reads.
local MAX_EXTRA = 6

-- How many entries a class may add. Four, which is more than any class file
-- written so far uses, and it is a cap rather than a count because Nag.lua
-- builds the row's squares once at login off Upkeep.Ceiling. A ceiling that
-- moved with the class would have to be right before the client will say what
-- you are, and it is not: that is the trap Class/Class.lua exists to keep out
-- of every file. Built to the cap, shown to the length.
local MAX_CLASS = 4

-- Handed back in place of a class list that is not there, so no caller builds a
-- table to iterate nothing.
local NONE = {}

--------------------------------------------------------------------------
-- The two lines
--
-- Every entry stands on one line or on both, and the lines are the whole of
-- when it is asked about. The out line is checked between fights, because a
-- stone and a plate of food are things you put on before the pull and cannot
-- put on during it. The in line is checked during a fight, because a shield
-- that spent its last charge on the third mob and a racial sitting off
-- cooldown are things you fix mid swing or not at all. A shield is both: it
-- should be up before the pull and it is the one that goes down during it.
--
-- So the lines are disjoint sets and an entry is a member of each on its own.
-- Dropping a square on a line puts it there and leaves the other line alone;
-- dragging it off a line takes it off that line only, and off the last line
-- it is switched off, which is where the shelf under the row comes from. The
-- saved word is `out`, `in` or `both`, and absent means what shipped.
--
-- Strings rather than booleans, for the reason Cooldowns.lua gives for its own
-- pair: every reader compares one of them, and a misspelling is then a square
-- on the wrong line rather than a nil error.
--------------------------------------------------------------------------

local OUT, IN, BOTH = "out", "in", "both"
Upkeep.OUT, Upkeep.IN, Upkeep.BOTH = OUT, IN, BOTH

--------------------------------------------------------------------------
-- The three that ship, and whatever your class adds
--
-- Each is here because it is silent when it lapses and expensive while it is
-- lapsed. Nothing that announces itself belongs on this list.
--
-- Two of them are hands rather than auras, and they are the reason this file
-- exists at all. The third is the cheapest buff in the game to keep up and the
-- one most often forgotten after a wipe.
--
-- Nothing on this list is a class ability, and that is the rule. A lapsed
-- sharpening stone costs a hunter's weapon exactly what it costs a warrior's.
-- What your class wants kept up is written in Class/<yours>.lua as `upkeep`,
-- in the same shape as an entry here, and Upkeep.Fixed hands the two back as
-- one list.
--
-- Five fields carry the words, and they are five because they are read in five
-- places that cannot share one string.
--
--   fixed    the caption under the square. It has to fit three others on one
--            line over your character, so it is two or three words and it names
--            what is wrong rather than where. "main hand" named the slot and
--            left you to work out what about it, which on a bare icon is no
--            help at all. "bare weapon" is the voice the racial half already
--            speaks in with "press Blood Fury": it says the thing you would fix.
--   word     what you type. `/wk buffs weapon off`.
--   switch   the panel's tick box, which is a sentence rather than a label
--            because every other tick box on that page is one.
--   hint     the tooltip, which is where the detail the caption cannot hold
--            goes: what the square is about and what fixes it.
--
-- An entry names one aura with `spell` or a set of them with `spells`, and a
-- set means any one of them counts. That is what a mage's armour is: four
-- spells, one of which should always be up, and nagging about the particular
-- one they are not running would be nagging about a choice.
--
-- The slash words name the thing rather than the slot, with one deliberate
-- exception. `weapon`, `shout` and `food` are the things. `offhand` is the hand,
-- because for that entry the hand is the thing: the whole rule on it is that a
-- shield in that hand is never nagged about and a weapon in it is, so the hand
-- is what you are switching off rather than an address for something else.
--------------------------------------------------------------------------

local FIXED = {
	-- The main hand, which is the sharpening stone, the oil or the shaman's
	-- imbue. Nagged only while there is a weapon in the slot, because an empty
	-- hand is a state you are in on purpose and briefly.
	{
		key = "mainhand", hand = MAIN, line = OUT,
		fixed = "bare weapon",
		word = "weapon",
		switch = "tell me about a bare weapon",
		hint = "Nothing on the weapon you swing. A sharpening stone, a weightstone,"
			.. " an oil or a shaman's imbue all count, and the cheapest of them is"
			.. " still the cheapest damage in the game.",
	},

	-- The off hand, and the one entry in this file with a rule about what it
	-- must not do. A shield takes no stone, a held-in-off-hand item takes no
	-- stone, and an empty off hand is most warriors most of the time. All three
	-- answer false to OffhandHasWeapon, which is the client's own question of
	-- "is there a weapon in that hand", so the test is that call and not
	-- whether the slot has something in it.
	{
		key = "offhand", hand = OFF, line = OUT,
		fixed = "bare off hand",
		word = "offhand",
		switch = "tell me about a bare off hand",
		hint = "Nothing on the weapon in your off hand. A shield takes no stone and"
			.. " is never nagged about, so this square only ever means a real"
			.. " weapon in that hand with nothing on it.",
	},

	-- Food. Every food buff in the game lands as one aura called Well Fed, and
	-- 19705 is the id this file asks the client to spell that phrase for. It is
	-- Nightfin Soup's buff on Wowhead's TBC database, named exactly "Well Fed",
	-- and which food granted it does not matter: the name is the thing being
	-- compared and every food shares it.
	{
		key = "food", spell = 19705, line = OUT,
		fixed = "food",
		word = "food",
		switch = "tell me when I am not fed",
		hint = "You are not Well Fed. Every food buff in the game lands as that one"
			.. " aura, so any of them clears this square.",
	},

	-- The racial, which is the one entry on this list that is not an aura and
	-- the one that ships on the in line. Racials.lua says which spell it is and
	-- whether it is worth a square; this entry is what puts it on the row beside
	-- the others so it can be switched, dragged off and dragged back the same
	-- way. It is missing while it is off cooldown in a fight, which is the only
	-- moment pressing it is worth saying, and it cannot be moved to the out
	-- line: a cooldown that is ready between fights is ready all afternoon.
	{
		key = "racial", racial = true, line = IN,
		word = "racial",
		switch = "nag me about my racial",
	},
}

--------------------------------------------------------------------------
-- What is not on that list, and will not be
--
-- Flasks and elixirs, which are the obvious fifth entry and are deliberately a
-- setting instead.
--
-- These clients will not tell you that an aura came from an elixir. There is no
-- category on an aura, no flag, and no call that maps one back to the item that
-- applied it. The only way to ship a built-in flask check is a hand written
-- table of every flask and battle and guardian elixir id in the expansion,
-- which is about forty numbers that cannot be verified from outside the game,
-- go stale on the next content patch, and are wrong in a way nothing reports.
--
-- So the list is yours. `/wk buffs add <spell id>` puts an aura on the row and
-- the panel says where to find the id, exactly the way the debuff row on the
-- enemy bars takes one. Six slots, and the same rule as everywhere else in this
-- addon: use the id of the aura that lands on you, not of the item.
--------------------------------------------------------------------------

-- The live list, rebuilt at login and whenever the extra list moves. Never
-- rebuilt from a tick.
local order = {}

-- This client's name for an aura, to the entry that wants it. One lookup per
-- aura slot per scan instead of a walk of the list per slot.
local wanted = {}

-- The extra entries, one table per spell you added and held rather than
-- rebuilt, so a rebuild hands the row the same table it was drawing. Keyed by
-- the spell rather than by the place on the list, because the key is what the
-- line and the switch are saved under and a place moves when the one before it
-- is removed.
local extras = {}

local function MineKey(spellID)
	return "spell" .. spellID
end

local function MineEntry(spellID)
	local key = MineKey(spellID)
	local entry = extras[key]
	if not entry then
		entry = { key = key, spell = spellID, mine = true, line = OUT }
		extras[key] = entry
	end
	return entry
end

-- What is off the row on purpose: the entries this character could draw and
-- has switched off. Built in the same walk as `order`, because the page draws
-- both and a square you took off the row that is nowhere on the page is a
-- square you cannot put back.
local shelf = {}

-- How many entries the row must be built to hold. A frame cannot be destroyed
-- on this client, only hidden, so Nag.lua builds this many squares once and
-- shows as many of them as the list is long.
function Upkeep.Ceiling()
	return #FIXED + MAX_CLASS + MAX_EXTRA
end

function Upkeep.Count()
	return #order
end

function Upkeep.Entry(index)
	return order[index]
end

function Upkeep.ShelfCount()
	return #shelf
end

function Upkeep.Shelved(index)
	return shelf[index]
end

-- Which lines an entry stands on, as the saved word: the ones you put it on,
-- or the one it shipped on. The racial answers the in line whatever was saved,
-- because a saved word for it can only be a file edited by hand.
function Upkeep.Lines(entry)
	if entry.racial then
		return IN
	end
	local moved = ns.dbc.buffLine[entry.key]
	if moved == OUT or moved == IN or moved == BOTH then
		return moved
	end
	return entry.line or OUT
end

-- Whether a drawn entry stands on one line. On the tick, off the two flags
-- Rebuild wrote onto it.
function Upkeep.On(entry, line)
	return entry.lines[line] == true
end

-- How many drawn entries each line carries. An entry on both counts twice,
-- because the page draws it twice.
function Upkeep.Split()
	local out, fight = 0, 0
	for index = 1, #order do
		local lines = order[index].lines
		out = out + (lines[OUT] and 1 or 0)
		fight = fight + (lines[IN] and 1 or 0)
	end
	return out, fight
end

-- The at-th drawn entry on one line, or nil past the end of it. What the page
-- reads a square off.
function Upkeep.OnLine(line, at)
	local seen = 0
	for index = 1, #order do
		if order[index].lines[line] then
			seen = seen + 1
			if seen == at then
				return order[index]
			end
		end
	end
	return nil
end

-- What ships, plus whatever your class added, as one list. Read only, so
-- Feature.lua builds a tick box and a slash word per entry off this instead of
-- naming any of them twice.
--
-- Built once the client will say what you are and held after that. Not held
-- before: a list taken while the class was still unresolved would be missing
-- your class's entries for the rest of the session, and nothing on screen would
-- say why. Until then the shipped three are handed back on their own, which is
-- correct for every character and short for one.
local shipped

function Upkeep.Fixed()
	if shipped then
		return shipped
	end
	if not ns.Class.Token() then
		return FIXED
	end

	local mine = ns.Class.Of("upkeep") or NONE
	assert(#mine <= MAX_CLASS,
		("%s puts %d entries on the upkeep row and the cap is %d")
			:format(ns.Class.Label(), #mine, MAX_CLASS))

	shipped = {}
	for index = 1, #FIXED do
		shipped[index] = FIXED[index]
	end
	for index = 1, #mine do
		shipped[#shipped + 1] = mine[index]
	end
	return shipped
end

-- Which class claims a slash word this character has no entry for, or nil for a
-- word nobody claims, which is an ordinary typo. Named rather than left to fall
-- through to the bare on|off toggle, because `/wk buffs shout` on a mage would
-- otherwise switch the whole row off and report that it had done something else.
function Upkeep.Elsewhere(word)
	for _, def in pairs(ns.Class.All()) do
		local list = def.upkeep or NONE
		for index = 1, #list do
			if list[index].word == word then
				return def.label
			end
		end
	end
	return nil
end

function Upkeep.ByWord(word)
	local list = Upkeep.Fixed()
	for index = 1, #list do
		if list[index].word == word then
			return list[index]
		end
	end
	return nil
end

--------------------------------------------------------------------------
-- What you have switched off
--
-- One entry at a time, and the whole of it is Rebuild's filter below. A
-- switched-off entry is not on `order`, which means the tick never asks about
-- it, Nag.lua never draws it, and Describe never counts it. That is what "off"
-- has to mean: an entry drawn at alpha zero is still four calls a tick and
-- still a square of screen nobody can use, and an entry checked and thrown away
-- is the same work with none of the answer.
--
-- Absent means watched. The saved table carries only what you switched off and
-- carries it as false, so a fresh character has an empty table, and an entry
-- added in a later release is watched rather than silently missing because
-- nobody's saved variables knew its name.
--------------------------------------------------------------------------

function Upkeep.Watched(key)
	return ns.dbc.buffWatch[key] ~= false
end

function Upkeep.SetWatched(key, on)
	-- Written as a branch and not as `on and nil or false`, which is the shorter
	-- line and is wrong: `and nil` is falsy, so the `or` takes over and every
	-- call writes false. Switching an entry back on would leave it off.
	if on then
		ns.dbc.buffWatch[key] = nil
	else
		ns.dbc.buffWatch[key] = false
	end
	Upkeep.Rebuild()
end

-- How many are switched off, and their captions in one phrase.
--
-- This exists so a silenced entry is visible somewhere. A nag you turned off
-- six weeks ago and cannot find any trace of is the same defect as a nag you
-- learned to ignore, moved one room over: the row is quiet and you no longer
-- know why. `/wk status` and the panel both say this.
function Upkeep.Silent()
	local count, names = 0, ""
	local list = Upkeep.Fixed()
	for index = 1, #list do
		local entry = list[index]
		if not Upkeep.Watched(entry.key) then
			count = count + 1
			names = names .. (count > 1 and ", " or "") .. (entry.fixed or entry.word)
		end
	end
	return count, names
end

--------------------------------------------------------------------------
-- The weapon enchants
--
-- GetWeaponEnchantInfo has had three shapes. The oldest answers six values,
-- three per hand: whether there is an enchant, how many milliseconds are left,
-- and how many charges. 6.0 put the enchant's own id after the charges, which
-- makes it eight. Cataclysm added a ranged hand, which makes it twelve.
--
-- Nothing on this machine settles which of the three 2.5.6 and 1.15.9 answer
-- with. The one unguarded call in this install is inside a Details library
-- written against a much later client and reads the eight value shape, and the
-- language server stub beside it disagrees with itself twice.
--
-- So it is counted rather than assumed. select("#", f()) is the exact number of
-- values the client returned, whatever they are, and the only thing this file
-- needs from it is the stride between the two hands: three on the old shape and
-- four on either newer one.
--
-- Reading it positionally on a guess is the failure worth avoiding. At stride
-- three against a client that answers eight, the off hand's "has an enchant"
-- would be read out of the main hand's enchant id, which is a number, which is
-- truthy, which is a nag that never fires and never says why.
--
-- Counted on every read rather than once. A client does not change its mind
-- about an API mid-session, so a cache would be correct; what a cache also is
-- is a client answer this file has written down, and the whole point of the
-- count is not to have written a client answer down. It costs one extra call to
-- a function that reads two numbers off the player, four times a tenth of a
-- second, which is not a cost.
--------------------------------------------------------------------------

function Upkeep.EnchantShape()
	if type(GetWeaponEnchantInfo) ~= "function" then
		return nil
	end
	if select("#", GetWeaponEnchantInfo()) >= 8 then
		return 4
	end
	return 3
end

-- Both hands out of one call: whether each is enchanted and how many seconds
-- each has left. Nil when this client has no such call at all, which is "do not
-- know" and not "nothing is enchanted", so nothing is nagged about.
--
-- On the tick. No table, no string, no concatenation.
function Upkeep.Enchants()
	local step = Upkeep.EnchantShape()
	if not step then
		return nil
	end
	if step == 4 then
		local mine, mineLeft, _, _, other, otherLeft = GetWeaponEnchantInfo()
		return mine and true or false, (mineLeft or 0) / 1000,
			other and true or false, (otherLeft or 0) / 1000
	end
	local mine, mineLeft, _, other, otherLeft = GetWeaponEnchantInfo()
	return mine and true or false, (mineLeft or 0) / 1000,
		other and true or false, (otherLeft or 0) / 1000
end

-- Whether that hand is holding something a stone goes on and has nothing on it.
--
-- The off hand asks the client rather than the inventory slot, which is the
-- whole of the shield rule. A shield, a held-in-off-hand item and an empty hand
-- all answer false to OffhandHasWeapon and none of the three is ever nagged
-- about. Where the client has no such call the off hand is left alone entirely,
-- because guessing off the slot would nag every tank in the addon about the
-- shield they are meant to be holding.
function Upkeep.Bare(hand)
	local mine, _, other = Upkeep.Enchants()
	if mine == nil then
		return false
	end
	if hand == OFF then
		if type(OffhandHasWeapon) ~= "function" then
			return false
		end
		if not OffhandHasWeapon() then
			return false
		end
		return not other
	end
	if not GetInventoryItemLink("player", MAIN) then
		return false
	end
	return not mine
end

-- How long that hand's enchant has to run, in seconds, or nil when there is
-- nothing on it. For the status line and the panel, never for the row: the row
-- says missing or nothing at all.
function Upkeep.Left(hand)
	local mine, mineLeft, other, otherLeft = Upkeep.Enchants()
	if mine == nil then
		return nil
	end
	if hand == OFF then
		return other and otherLeft or nil
	end
	return mine and mineLeft or nil
end

--------------------------------------------------------------------------
-- The list
--------------------------------------------------------------------------

-- One aura slot's name. ns.BuffName is the shim, in Core with the rest of them
-- since the cooldown row started walking the same list for the same string.
local function AuraName(index)
	return ns.BuffName("player", index)
end

-- One spell id into the lookup, under whatever this client calls it. The first
-- one that resolves gives the entry its name and its picture. `watch` is
-- whether the scan should match the name onto this entry: a shelved entry gets
-- its name and its picture for the page and no place in the lookup, because a
-- present aura on a square nobody can see is a missing square nobody can see.
local function TrackName(entry, id, watch)
	local name = ns.SpellName(id)
	if not name then
		return
	end
	if watch then
		wanted[name] = entry
	end
	if not entry.name then
		entry.name = name
		entry.texture = ns.SpellTexture(id)
	end
end

-- Every aura one entry is watching. A set means any one of them counts: a mage
-- in Molten Armor is not missing Ice Armor and an enhancement shaman running
-- Water Shield is not missing Lightning Shield, so all of the names point at the
-- one entry and the scan cannot tell which of them arrived.
--
-- The racial is not an aura and resolves off Racials.lua instead: the spell,
-- the name and the picture, read again on every rebuild because the client can
-- take a moment after login to answer for a race.
--
-- Named rather than written inside Rebuild, where the set inside the entry walk
-- was five levels deep and the shape gate stops at four. The gate was right:
-- what the inner loop does is a different job from rebuilding the list.
local function Track(entry, watch)
	entry.name, entry.texture = nil, nil
	if entry.racial then
		entry.spell = ns.Racials.Spell()
		entry.name = ns.Racials.Name()
		entry.texture = ns.Racials.Texture()
		return
	end
	if entry.spells then
		for at = 1, #entry.spells do
			TrackName(entry, entry.spells[at], watch)
		end
	elseif entry.spell then
		TrackName(entry, entry.spell, watch)
	end
end

-- Which of the tracked auras are on you. Called from an event, never a tick.
function Upkeep.Scan()
	for index = 1, #order do
		order[index].present = false
	end

	local index = 1
	while index <= SLOTS do
		local name = AuraName(index)
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

-- The art each hand's square draws, which is the weapon you are holding. That
-- says what the nag is about better than a picture of a stone would: the square
-- is your own axe with a red edge round it, and the axe you swapped to is the
-- one that has nothing on it.
--
-- Re-read whenever the worn gear moves, and never on the tick.
function Upkeep.Refit()
	for index = 1, #order do
		local entry = order[index]
		if entry.hand then
			local _, icon = ns.ItemInfo(GetInventoryItemLink("player", entry.hand))
			entry.texture = icon or ns.Gear.Art(entry.hand)
		end
	end
end

-- Whether one entry goes on the row at all, whichever line and whatever you
-- switched. The racial is the only one with a condition: a race with no racial
-- listed, or one that is situational rather than damage, has no square to draw
-- and no square to put back, the way a trinket slot with nothing pressable in
-- it has none on the cooldown row.
local function Drawable(entry)
	if entry.racial then
		return ns.Racials.Worth() and entry.name ~= nil
	end
	return true
end

-- Rebuild the live list from what ships, what your class added and whatever you
-- have put on it yourself.
function Upkeep.Rebuild()
	for index = #order, 1, -1 do
		order[index] = nil
	end
	for index = #shelf, 1, -1 do
		shelf[index] = nil
	end
	for name in pairs(wanted) do
		wanted[name] = nil
	end

	local list = Upkeep.Fixed()
	local all, count = {}, 0
	for index = 1, #list do
		count = count + 1
		all[count] = list[index]
	end
	local own = ns.dbc.buffExtra
	for index = 1, math.min(#own, MAX_EXTRA) do
		count = count + 1
		all[count] = MineEntry(own[index])
	end

	for index = 1, count do
		local entry = all[index]
		local watched = Upkeep.Watched(entry.key)
		local word = Upkeep.Lines(entry)
		entry.present = false
		-- One table per entry, made the first time and written after that, so
		-- a rebuild hands the row the same entry it was drawing and the tick
		-- reads two flags off it.
		entry.lines = entry.lines or {}
		entry.lines[OUT] = word == OUT or word == BOTH
		entry.lines[IN] = word == IN or word == BOTH
		Track(entry, watched)
		-- A shipped entry says what it is in the caption's own words; one you
		-- added says whatever this client calls it, because "flask" is not a
		-- word the client would use and the spell's name is.
		entry.label = entry.fixed or entry.name
			or (entry.spell and ("spell " .. entry.spell)) or "?"
		if Drawable(entry) then
			if watched then
				order[#order + 1] = entry
			else
				shelf[#shelf + 1] = entry
			end
		end
	end

	Upkeep.Refit()
	Upkeep.Scan()
end

-- Is the index'th entry missing right now. On the tick, so it reads a field for
-- an aura and makes one call for a hand.
--
-- An entry this client cannot name is never missing. That is the same answer
-- the debuff row gives an id it does not know: the slot keeps its place in case
-- you log in on the flavour that does know it, and nothing is drawn meanwhile.
function Upkeep.Missing(index)
	local entry = order[index]
	if not entry then
		return false
	end
	if entry.racial then
		return ns.Racials.Idle()
	end
	if entry.hand then
		return Upkeep.Bare(entry.hand)
	end
	if not entry.name then
		return false
	end
	return not entry.present
end

--------------------------------------------------------------------------
-- The list you keep
--------------------------------------------------------------------------

function Upkeep.Extra()
	return ns.dbc.buffExtra
end

function Upkeep.MaxExtra()
	return MAX_EXTRA
end

function Upkeep.MineKey(spellID)
	return MineKey(spellID)
end

function Upkeep.Add(spell)
	local id = tonumber(spell)
	if not id or id <= 0 then
		return false, "that is not a spell id."
	end
	local list = ns.dbc.buffExtra
	for index = 1, #list do
		if list[index] == id then
			return false, (ns.SpellName(id) or ("spell " .. id)) .. " is already on the row."
		end
	end
	if #list >= MAX_EXTRA then
		return false, ("the row holds %d of your own and it is full."):format(MAX_EXTRA)
	end
	list[#list + 1] = id
	Upkeep.Rebuild()
	return true, ns.SpellName(id) or ("spell " .. id .. ", which this client cannot name")
end

function Upkeep.Remove(spell)
	local id = tonumber(spell)
	local list = ns.dbc.buffExtra
	for index = 1, #list do
		if list[index] == id then
			table.remove(list, index)
			ns.dbc.buffLine[MineKey(id)] = nil
			ns.dbc.buffWatch[MineKey(id)] = nil
			Upkeep.Rebuild()
			return true
		end
	end
	return false
end

--------------------------------------------------------------------------
-- Putting a square on a line, and taking it off one
--
-- What the page does when you drag one, and what `buffs line <word>` does
-- with the same fact typed. Every entry the row could draw is a candidate,
-- whichever lines it is on and whether it is switched off, because dragging a
-- square onto a line means "watch this, here" and there is nothing else the
-- gesture could mean.
--------------------------------------------------------------------------

-- The entry one key names, on the shipped list or among your own.
local function ByKey(key)
	local list = Upkeep.Fixed()
	for index = 1, #list do
		if list[index].key == key then
			return list[index]
		end
	end
	return extras[key]
end

-- The saved word for a pair of flags, and nil where the pair is what shipped.
local function Save(entry, out, fight)
	local word = (out and fight and BOTH) or (fight and IN) or OUT
	if word == (entry.line or OUT) then
		ns.dbc.buffLine[entry.key] = nil
	else
		ns.dbc.buffLine[entry.key] = word
	end
end

-- Which entry already answers for a spell, or nil for one nothing on the row
-- has heard of. Every id an entry carries and the name as well, so a shield
-- dragged out of the spellbook at rank three lands on the shield square the
-- class file wrote at rank one rather than beside it.
function Upkeep.Owner(spellID)
	local name = ns.SpellName(spellID)
	local list = Upkeep.Fixed()
	for index = 1, #list do
		local entry = list[index]
		if entry.spell == spellID or (name and entry.name == name) then
			return entry
		end
		for at = 1, #(entry.spells or NONE) do
			if entry.spells[at] == spellID then
				return entry
			end
		end
	end
	return extras[MineKey(spellID)]
end

-- One entry onto one line, or onto both, or with no line named back onto the
-- lines it shipped on. The other line is left as it was, because a drop on a
-- line says nothing about the other one, unless `only` says the word names
-- where the square ends up rather than a line to add: that is what `buffs line
-- shield in` means, and what a spell just added off the spellbook means, which
-- has a shipped line it was never on. An entry that was switched off comes
-- back on the line it was dropped on and that line alone, which is what
-- dragging it up out of the shelf means.
--
-- Returns whether anything moved, and the sentence to print where it refused.
function Upkeep.Place(key, line, only)
	local entry = ByKey(key)
	if not entry then
		return false, "nothing on the row answers to " .. tostring(key) .. "."
	end
	if line ~= nil and line ~= OUT and line ~= IN and line ~= BOTH then
		return false, "a square goes on the in line, the out line or both."
	end
	if entry.racial and (line == OUT or line == BOTH) then
		return false, "your racial is a cooldown, and a cooldown that is ready"
			.. " between fights is ready all afternoon. It stays on the in line."
	end

	if line == nil then
		ns.dbc.buffLine[key] = nil
	else
		local was = (Upkeep.Watched(key) and not only) and Upkeep.Lines(entry) or nil
		local out = line == OUT or line == BOTH or was == OUT or was == BOTH
		local fight = line == IN or line == BOTH or was == IN or was == BOTH
		Save(entry, out, fight)
	end
	ns.dbc.buffWatch[key] = nil
	Upkeep.Rebuild()
	return true
end

-- One entry off one line. Off its last line it is switched off, and the saved
-- word is dropped with it so that putting it back from the shelf puts it back
-- where it shipped.
function Upkeep.Leave(key, line)
	local entry = ByKey(key)
	if not entry or not Upkeep.Watched(key) then
		return false
	end
	local was = Upkeep.Lines(entry)
	local out = (was == OUT or was == BOTH) and line ~= OUT
	local fight = (was == IN or was == BOTH) and line ~= IN
	if not out and not fight then
		ns.dbc.buffLine[key] = nil
		Upkeep.SetWatched(key, false)
		return true
	end
	Save(entry, out, fight)
	Upkeep.Rebuild()
	return true
end

-- A spell dropped on a line: off your spellbook, off the other line, or off
-- the squares under the row. Matched against the whole row before anything is
-- added, so dragging a square the row already knows about moves it rather than
-- arriving twice.
function Upkeep.Put(spellID, line)
	spellID = tonumber(spellID)
	if not spellID then
		return false, "that is not a spell this row can watch."
	end
	local owner = Upkeep.Owner(spellID)
	if owner then
		return Upkeep.Place(owner.key, line)
	end
	local ok, message = Upkeep.Add(spellID)
	if not ok then
		return false, message
	end
	return Upkeep.Place(MineKey(spellID), line, true)
end

-- One line for the status and the panel. Names what is missing right now, which
-- is the only thing anybody types this to find out, and then names what you
-- switched off, which is the thing you would otherwise have no way of learning.
--
-- The counts are of the watched list alone. A switched-off entry is not tracked
-- and is not missing, because a status line that said "4 tracked, 2 missing"
-- about two squares you cannot see would have moved the nag off the screen and
-- into the text rather than turned it off.
function Upkeep.Describe()
	local silent, names = Upkeep.Silent()
	local tail = silent > 0 and ("; " .. names .. " switched off") or ""

	if #order == 0 then
		return "nothing tracked" .. tail
	end
	local missing = 0
	for index = 1, #order do
		if Upkeep.Missing(index) then
			missing = missing + 1
		end
	end
	if missing == 0 then
		return ("%d tracked, all up"):format(#order) .. tail
	end
	return ("%d tracked, %d missing"):format(#order, missing) .. tail
end
