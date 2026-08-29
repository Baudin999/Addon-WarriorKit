local ADDON, ns = ...

ns.version = "1.9"

-- Core knows nothing about any feature. It holds the saved variables, the API
-- shims, the two drawing helpers every part uses, and the one registry every
-- feature signs into. Adding an eighth part to the addon must not require
-- editing this file.

--------------------------------------------------------------------------
-- The registry
--
-- Each part calls ns.Register once, from its Feature.lua, and
-- hands over everything Core or the panel could want from it. Nothing else in
-- the addon reaches across parts to find out what exists.
--
--   name          the word that heads its slash help and its status line
--   order         a whole number, unique across the addon: where this part's
--                 tabs sit inside whichever group they named, and where its
--                 line sits in /wk status
--   defaults      merged into ns.db, the account-wide saved variables
--   charDefaults  merged into ns.dbc, this character's saved variables
--   switch        { key, label, available } the one boolean that decides
--                 whether this part puts anything on your screen
--   words         slash words this part answers to, word = function(arg, raw)
--   help          lines printed by /wk help
--   status        function returning one line for /wk status
--   lock          function applying ns.db.locked to this part's frames
--   reset         function putting this part's frames back where they started
--   panel         function(ui) building this part's sections of the panel
--   showing       function(open) the options window opened or closed. For a
--                 part that draws something on the screen to say which of its
--                 rows the page is on, and has to stop when the page is gone
--
-- Every field except name is optional. A part with no frames has no lock.
--
-- order is whole and unique because it used to be neither. Two parts sat on 8
-- and a third on 7.6, so where they came out was whatever table.sort felt like
-- on the day, and the only way to find out was to open the window. A collision
-- is a login error now.
--
-- switch is the one boolean the panel draws itself, at the top of the part's
-- first page, and the rail reads to say which groups are doing something. It
-- exists because eleven parts each wrote their own check box for the same idea
-- and no two of them worded it the same way. available is optional and says the
-- part is not built on this character at all, which is Charge on a class whose
-- file named no openers. A part that answers no there opens no page and takes
-- no row on Start here: the switch is not greyed, it is not there.
--
-- Two scopes, because they are two different questions. A preference is yours
-- and belongs to the account. A record of what was in your action bars before
-- the loadout overwrote them belongs to the character whose bars they were,
-- and storing it account-wide is how one character's backup ends up written
-- over another character's bars.
--------------------------------------------------------------------------

ns.features = {}

local defaults = {
	locked = true,
}

local charDefaults = {}

-- Settings that shipped and were then dropped. A key no feature registers is
-- never read again, but saved variables are written back whole at every logout,
-- so it sits in the file forever looking like a setting. Named here with what
-- dropped them, cleared once at load, and asserted against below so a key
-- cannot be retired and registered at the same time.
local RETIRED = {
	-- 1.2: the aim reticle, replaced by softAuto driving SoftTargetEnemy off
	-- combat rather than drawing a box around what it resolved to.
	softIcon = true,
	softIconSize = true,

	-- 1.2: the breakdown ranked by damage, casts or hits off a chip on its
	-- window. The other two rankings were answers to a question that table does
	-- not ask, and a ranking by press count puts Battle Shout above Mortal
	-- Strike. It never shipped, but a reload while it existed wrote the key.
	breakdownSort = true,

	-- 1.2: markKeys was a boolean for one edit before the marking keys became
	-- one setting per mark in markBinds. It never shipped, but a reload while it
	-- existed wrote it, and ApplyDefaults keeps whatever it finds, so a boolean
	-- would still be sitting where a table is now indexed.
	markKeys = true,

	-- 1.2: the distance between the player and target blocks, back when the two
	-- were anchored a fixed distance apart. The target's facing edge is the
	-- player's reflected in the middle of the screen now, so the corridor is
	-- twice the player's distance from the centre and there is no number to
	-- choose. Retired rather than left to sit unread, because a setting nothing
	-- reads is a setting somebody will try to change.
	skinGap = true,

	-- 1.2: whether the chat window was left open, written by a cross at the
	-- foot of its rail. The cross is gone: it took the conversation off the
	-- screen in one press and wrote that down, so the window stayed gone across
	-- reloads and the way back was a slash word you had to know. The way to be
	-- rid of the window is the chat setting, and this key has to be wiped or a
	-- player who pressed the cross once would never see the window again.
	chatShown = true,

	-- 1.9: one switch for the client's own aura row, which meant a different
	-- thing depending on what the skin was doing. It is four switches now, one
	-- per thing you can see twice, and each says what it does on its own line.
	blizzAuras = true,
}

-- A key lives in exactly one scope. Checking both tables on every insert is
-- what stops a setting being account-wide in one release and per-character in
-- the next without anyone noticing.
local function Claim(into, source)
	for key, value in pairs(source or {}) do
		assert(defaults[key] == nil and charDefaults[key] == nil,
			("two features both define the setting %q"):format(key))
		assert(not RETIRED[key],
			("%q is in the retired list and would be wiped at every load"):format(key))
		into[key] = value
	end
end

local taken = {}

function ns.Register(feature)
	assert(type(feature) == "table" and type(feature.name) == "string",
		"a feature must register a table with a name")
	assert(type(feature.order) == "number" and feature.order == math.floor(feature.order),
		("%s registered the order %s, and an order is a whole number")
			:format(feature.name, tostring(feature.order)))
	assert(not taken[feature.order],
		("%s and %s both registered the order %d")
			:format(feature.name, tostring(taken[feature.order]), feature.order))
	taken[feature.order] = feature.name

	if feature.switch then
		assert(type(feature.switch.key) == "string" and type(feature.switch.label) == "string",
			("%s registered a switch with no key or no label"):format(feature.name))
		assert(type((feature.defaults or {})[feature.switch.key]) == "boolean",
			("%s says its switch is %q and no boolean of that name is in its defaults")
				:format(feature.name, feature.switch.key))
	end

	Claim(defaults, feature.defaults)
	Claim(charDefaults, feature.charDefaults)

	ns.features[#ns.features + 1] = feature
	table.sort(ns.features, function(a, b)
		return a.order < b.order
	end)
	return feature
end

-- Walks the registry so callers never name a feature. Used by lock, reset and
-- anything else that has to reach every part at once.
function ns.Each(hook, ...)
	for _, feature in ipairs(ns.features) do
		if feature[hook] then
			feature[hook](...)
		end
	end
end

-- Nameplate frames are restricted regions on this client. A positional
-- measurement on one raises rather than returning nil, and a ticker that does
-- it once a frame buys "too many errors, disable addons" in about a minute.
-- Size, scale, strata and level do answer, but every measurement of a frame
-- the addon does not own goes through here so a client that restricts more of
-- them degrades to a nil answer instead of a screenful of errors.
function ns.Measure(frame, method)
	if not frame or type(frame[method]) ~= "function" then
		return nil
	end
	local ok, value = pcall(frame[method], frame)
	if ok then
		return value
	end
	return nil
end

--------------------------------------------------------------------------
-- Hiding what the addon does not own
--
-- Blizzard's own update code turns its regions back on, so hiding one is not
-- enough: its Show method is replaced with Hide first, and put back on the way
-- out. Both halves refuse while a protected region is in lockdown and say so by
-- returning false, so the caller can finish the job at PLAYER_REGEN_ENABLED
-- rather than eating a lockdown error.
--
-- Lives here because three parts strip Blizzard regions, the enemy bars, the
-- artwork part and the frame skin, and none of them is allowed to reach into
-- another.
--------------------------------------------------------------------------

-- Whether a region refuses to be touched right now. Shared rather than local
-- because three parts ask it: the enemy bars strip nameplate regions, the
-- artwork part strips bar art, and the frame skin moves the regions of a
-- secure unit button, and all three queue the refusal for PLAYER_REGEN_ENABLED
-- rather than eating a lockdown error.
function ns.Blocked(region)
	return region and region.IsProtected and region:IsProtected() and InCombatLockdown()
end

function ns.Strip(region)
	if not region or region.wkStripped then
		return true
	end
	if ns.Blocked(region) then
		return false
	end
	region.wkStripped = true
	region.wkShow = region.Show
	region.Show = region.Hide
	region:Hide()
	return true
end

function ns.Unstrip(region)
	if not region or not region.wkStripped then
		return true
	end
	if ns.Blocked(region) then
		return false
	end
	region.Show = region.wkShow
	region.wkShow = nil
	region.wkStripped = nil
	region:Show()
	return true
end

function ns.Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff40c0f0WarriorKit|r: " .. msg)
end

--------------------------------------------------------------------------
-- Drawing
--
-- ns.Fill, ns.Pixel, ns.EdgeSize, ns.Outline and ns.Recolor live in UI/Draw.lua
-- and UI/Pixel.lua, which load between this file and Core/Panel.lua. They were
-- here until the pixel grid arrived and turned twenty lines into a layer with
-- its own scale arithmetic, resolution watcher and font cache. The names on ns
-- are unchanged, so nothing that draws had to move with them.
--------------------------------------------------------------------------

--------------------------------------------------------------------------
-- Which client this is
--
-- The addon ships one TOC per flavour and runs on both: 20506 is TBC
-- Anniversary, 11509 is Classic Era. Read the interface number rather than a
-- product string, because the number is what the TOC already declares and it
-- is what actually gates the API surface. Anything under 20000 is vanilla.
--------------------------------------------------------------------------

ns.interface = select(4, GetBuildInfo()) or 0
ns.vanilla = ns.interface > 0 and ns.interface < 20000

--------------------------------------------------------------------------
-- Which class this is
--
-- Not here. ns.Class in Class\Class.lua owns the question and the registry of
-- what each class brought with it, and Class\<name>.lua holds the facts. Core
-- knew it was a warrior addon for as long as this file answered that question,
-- which is exactly the coupling the registry above exists to refuse.
--------------------------------------------------------------------------

--------------------------------------------------------------------------
-- API shims
--
-- 2.5.6 still has the old globals, but the C_Spell namespace is what newer
-- builds keep. Resolve once here so the modules never care which one exists.
--------------------------------------------------------------------------

local C_Spell = _G.C_Spell

-- Vanilla has no threat API. Nothing in that client computes threat, which is
-- why every Classic threat meter parses the combat log instead. Resolved once
-- so a caller asks a question rather than calling a nil five times a second.
local UnitDetailedThreatSituation = _G.UnitDetailedThreatSituation

function ns.HasThreat()
	return type(UnitDetailedThreatSituation) == "function"
end

-- isTanking, status, scaled percent. Nil all the way down on a client without
-- the API, which is a different answer from "no threat on this mob" and the
-- caller has to tell them apart, so ask ns.HasThreat first.
function ns.Threat(source, unit)
	if type(UnitDetailedThreatSituation) ~= "function" then
		return nil
	end
	return UnitDetailedThreatSituation(source, unit)
end

--------------------------------------------------------------------------
-- Incoming heals
--
-- What every heal in flight on a unit adds up to. It is the number that says
-- whether a health bar is about to fill itself or whether the only thing
-- coming is your own cooldown, and it is the one thing a warrior frame cannot
-- work out by looking at health.
--
-- Both clients register UnitGetIncomingHeals and both fire
-- UNIT_HEAL_PREDICTION, so this is a client API rather than the combat log
-- estimate every Classic healing addon has to build for itself. Probed all the
-- same, because nothing installed here calls it and that is the bar the rest of
-- this section is held to.
--------------------------------------------------------------------------

local UnitGetIncomingHeals = _G.UnitGetIncomingHeals

function ns.HasHealPrediction()
	return type(UnitGetIncomingHeals) == "function"
end

-- Nil where the client has no prediction at all, 0 where it has it and nothing
-- is on the way. The caller has to tell those apart the way it does with
-- threat: one is a feature that cannot run, the other is a quiet moment.
function ns.IncomingHeals(unit)
	if type(UnitGetIncomingHeals) ~= "function" then
		return nil
	end
	local amount = UnitGetIncomingHeals(unit)
	return type(amount) == "number" and amount or 0
end

--------------------------------------------------------------------------
-- What a unit is casting
--
-- The one thing an enemy nameplate says that health and threat do not: there
-- is a window open right now, and Pummel or Shield Bash closes it. Replacing
-- the plate took that away, which is the whole reason this is here.
--
-- Two calls, because the client has two and a unit is doing at most one of
-- them. UnitCastingInfo counts up to a finish, UnitChannelInfo counts down from
-- a start, and this asks for a cast and falls back to a channel so every caller
-- gets one answer with a flag saying which it was.
--
-- Confirmed rather than remembered, on the bar every other shim in this file is
-- held to. Details is installed on the Era client and its framework used to
-- route both of these through LibClassicCasterino, which is the combat log
-- estimator every vanilla cast bar was built on because vanilla answered only
-- for you. That branch is switched off in `Libs/DF/externals.lua` under the
-- comment "disable this for now, as it appears to be working now through API
-- changes", and what it falls back to is UnitCastingInfo and UnitChannelInfo
-- called unguarded. So both clients answer for a unit that is not you. Probed
-- all the same, because nothing installed here proves it for 2.5.6 and a
-- feature that silently draws nothing is the failure this addon keeps hitting.
--
-- The returns are read positionally, which is the thing this file exists to do
-- once rather than in a feature. Both calls open with name, text, texture,
-- start, finish, isTradeSkill. After that they differ by one slot: a cast
-- carries a castID and a channel does not, so notInterruptible is the eighth
-- return of one and the seventh of the other. Neither slot is trusted to hold
-- it. What comes back is type checked, the way ns.Upkeep.EnchantShape counts
-- the stride between two weapon enchants rather than assuming it, and a client
-- that puts something else there is a client that does not say.
--------------------------------------------------------------------------

local UnitCastingInfo = _G.UnitCastingInfo
local UnitChannelInfo = _G.UnitChannelInfo

-- The cast half only, because that is the half a feature cannot do without.
-- The channel call is probed separately inside ns.CastingInfo: a client that
-- answered one and not the other would draw every cast and miss every channel,
-- which is most of the feature rather than none of it, and is not a reason to
-- report the whole thing absent.
function ns.HasCastInfo()
	return type(UnitCastingInfo) == "function"
end

-- nil until a cast has been read, false once one has been read and the client
-- left that slot empty, true once one has come back with the flag in it.
-- Reported and never inferred, the same as EnemyBars.CameraState: "this client
-- does not say" and "nothing has said yet" are two different answers and the
-- second one is not a claim.
local immuneKnown

function ns.CastImmuneKnown()
	return immuneKnown
end

-- The spell's name, when it started and when it ends in GetTime seconds,
-- whether it is a channel, and whether the client says it cannot be
-- interrupted. Nil for a unit doing neither, which is nearly every unit nearly
-- always, so the miss costs one call and one comparison.
--
-- The times come back in milliseconds on both calls and are divided here, for
-- the reason ns.SpellCastTime divides: a caller counting the client's
-- milliseconds against a GetTime in seconds draws a bar that is full from the
-- first frame and nothing about it looks wrong.
function ns.CastingInfo(unit)
	if type(UnitCastingInfo) ~= "function" then
		return nil
	end

	local channel = false
	local name, _, _, startMS, endMS, _, _, immune = UnitCastingInfo(unit)
	if not name and type(UnitChannelInfo) == "function" then
		channel = true
		name, _, _, startMS, endMS, _, immune = UnitChannelInfo(unit)
	end
	if not name or not startMS or not endMS then
		return nil
	end

	if type(immune) == "boolean" then
		immuneKnown = true
	else
		immune = nil
		if immuneKnown == nil then
			immuneKnown = false
		end
	end

	return name, startMS / 1000, endMS / 1000, channel, immune
end

--------------------------------------------------------------------------
-- Levels
--
-- What a mob is worth is a level question, and the client answers it in two
-- pieces: how far below you a mob can be and still pay XP, and whether it is
-- an elite. Resolved here with the other shims so the bars ask a question
-- rather than probe a global five times a second per mob.
--------------------------------------------------------------------------

local GetQuestGreenRange = _G.GetQuestGreenRange
local UnitClassification = _G.UnitClassification

-- How many levels below yours a mob can be and still pay XP. Questie calls
-- GetQuestGreenRange("player") unguarded on both clients, which is what proves
-- it is here, and the build that takes no argument ignores the one it is
-- handed. Nil rather than a guessed number when it is missing: a guess would
-- write "no XP" over a mob that still pays, and a wrong answer is worse than
-- none.
function ns.GreenRange()
	if type(GetQuestGreenRange) ~= "function" then
		return nil
	end
	local range = GetQuestGreenRange("player")
	return type(range) == "number" and range or nil
end

-- "worldboss", "rareelite", "elite", "rare", "normal" or "trivial", and nil on
-- a client without it. Nothing installed here calls UnitClassification, so it
-- is probed rather than trusted the way the confirmed APIs are. Losing it
-- costs the elite marker and leaves the level itself intact.
function ns.Classification(unit)
	if type(UnitClassification) ~= "function" then
		return nil
	end
	return UnitClassification(unit)
end

function ns.SpellName(spell)
	if C_Spell and C_Spell.GetSpellInfo then
		local info = C_Spell.GetSpellInfo(spell)
		return info and info.name
	end
	return (_G.GetSpellInfo(spell))
end

-- How long the client says that spell takes to cast, in seconds. Zero for an
-- instant, and zero where the client will not say, because every caller of
-- this branches the same way on a nil and the branch is worth writing once.
--
-- The client counts in milliseconds on both sides of the shim. It is the
-- fourth return of the old global and the castTime field of the new table, and
-- the fourth return is the reason this exists at all: a select(4) sitting in a
-- feature file is a positional read of an API the addon otherwise never reads
-- positionally.
function ns.SpellCastTime(spell)
	if C_Spell and C_Spell.GetSpellInfo then
		local info = C_Spell.GetSpellInfo(spell)
		return (info and info.castTime or 0) / 1000
	end
	local castTime = select(4, _G.GetSpellInfo(spell))
	return (castTime or 0) / 1000
end

function ns.SpellTexture(spell)
	if C_Spell and C_Spell.GetSpellTexture then
		return C_Spell.GetSpellTexture(spell)
	end
	return _G.GetSpellTexture(spell)
end

function ns.SpellCooldown(spell)
	if C_Spell and C_Spell.GetSpellCooldown then
		local info = C_Spell.GetSpellCooldown(spell)
		if not info then
			return 0, 0, true
		end
		return info.startTime, info.duration, info.isEnabled
	end
	local start, duration, enabled = _G.GetSpellCooldown(spell)
	return start or 0, duration or 0, enabled ~= 0
end

-- Returns usable, and whether the block is rage rather than anything else.
function ns.SpellUsable(spell)
	if C_Spell and C_Spell.IsSpellUsable then
		return C_Spell.IsSpellUsable(spell)
	end
	return _G.IsUsableSpell(spell)
end

-- One of your own buffs, by slot, as the name alone.
--
-- UnitAura is asked first and C_UnitAuras second, which is the opposite way
-- round from the spell shims above and is deliberate: the old call hands back a
-- string and the new one hands back a table it built to put the string in.
-- Every caller of this wants the string. Where only the new call exists the
-- table is made and dropped, which is the cost of that client.
--
-- Nil at the first empty slot, which is how both callers know to stop walking.
-- Buffs/Upkeep.lua asks what is missing and Cooldowns/Cooldowns.lua asks which
-- burst window is open, and both walk the same list for the same string.
function ns.BuffName(unit, index)
	if type(_G.UnitAura) == "function" then
		return (_G.UnitAura(unit, index, "HELPFUL"))
	end
	if C_UnitAuras and C_UnitAuras.GetBuffDataByIndex then
		local aura = C_UnitAuras.GetBuffDataByIndex(unit, index)
		return aura and aura.name
	end
	return nil
end

-- Returns 1 in range, 0 out of range, nil when the check does not apply.
function ns.SpellInRange(spell, unit)
	if C_Spell and C_Spell.IsSpellInRange then
		local inRange = C_Spell.IsSpellInRange(spell, unit)
		if inRange == nil then
			return nil
		end
		return inRange and 1 or 0
	end
	return _G.IsSpellInRange(spell, unit)
end

-- Whether a range answer definitely blocks. Takes what IsSpellInRange or
-- IsActionInRange handed back, which is 1, 0 or nil.
--
-- Only a definite 0 blocks. Both calls answer nil for a great many honest
-- reasons: the spell has no range, the unit cannot take it, the client has not
-- decided yet. Treating nil as out of range would pin every square in the
-- addon red, and treating it as in range silently would hide a client that
-- never answers at all, which is a real state on 2.5.6 and is worth knowing
-- once. So the nils are counted and the fortieth one says so, once, for the
-- session.
--
-- Shared rather than kept in whichever file needed it first. Charge/Charge.lua
-- had this counter and Buttons/Slot.lua needs the identical one, and two
-- copies means two thresholds and two chances to print the sentence twice.
local rangeAnswered, rangeSilent = false, 0
local RANGE_PATIENCE = 40

function ns.OutOfRange(answer)
	if answer == nil then
		rangeSilent = rangeSilent + 1
		if not rangeAnswered and rangeSilent == RANGE_PATIENCE then
			ns.Print("this client is not answering range checks, so out-of-range targets cannot be dimmed.")
		end
		return false
	end
	rangeAnswered = true
	return answer == 0
end

--------------------------------------------------------------------------
-- Items
--
-- Two clients, two container APIs. Era backported C_Container and 2.5.6 may or
-- may not carry it, so both are probed and a client with neither answers empty
-- rather than erroring: a picker with nothing in it is a worse UI, not a
-- broken addon.
--------------------------------------------------------------------------

local C_Container = _G.C_Container

-- Newer builds moved the item lookups into C_Item and kept the old globals
-- working. Resolved here beside C_Container so ns.ItemValue asks one question
-- rather than probing two namespaces per bag slot per tick.
local C_Item = _G.C_Item

function ns.ContainerSlots(bag)
	if C_Container and C_Container.GetContainerNumSlots then
		return C_Container.GetContainerNumSlots(bag) or 0
	end
	if type(_G.GetContainerNumSlots) == "function" then
		return _G.GetContainerNumSlots(bag) or 0
	end
	return 0
end

function ns.ContainerItemLink(bag, slot)
	if C_Container and C_Container.GetContainerItemLink then
		return C_Container.GetContainerItemLink(bag, slot)
	end
	if type(_G.GetContainerItemLink) == "function" then
		return _G.GetContainerItemLink(bag, slot)
	end
	return nil
end

-- How many are in a bag slot and whether the client has it locked, which is
-- what a sale in flight looks like from the outside. Multiple returns rather
-- than a table, because the vendor sweep asks this once per slot per tick and
-- a table per slot is garbage the collector walks in the middle of a frame.
--
-- C_Container answers one table with named fields and the old global answers
-- eleven values in a fixed order; both are read here so no caller has to know
-- which client it is on.
function ns.ContainerItem(bag, slot)
	if C_Container and C_Container.GetContainerItemInfo then
		local info = C_Container.GetContainerItemInfo(bag, slot)
		if not info then
			return nil
		end
		return info.stackCount, info.isLocked
	end
	if type(_G.GetContainerItemInfo) == "function" then
		local _, count, locked = _G.GetContainerItemInfo(bag, slot)
		return count, locked
	end
	return nil
end

-- Use what is in a bag slot. At a merchant that sells it; anywhere else it
-- eats, equips or opens the thing, which is why every caller has to prove the
-- merchant window is up before it calls this. False where the client has
-- neither API, so a caller can say so rather than believe a sale happened.
function ns.UseContainerItem(bag, slot)
	if C_Container and C_Container.UseContainerItem then
		C_Container.UseContainerItem(bag, slot)
		return true
	end
	if type(_G.UseContainerItem) == "function" then
		_G.UseContainerItem(bag, slot)
		return true
	end
	return false
end

-- Put what is in a bag slot on the cursor. The only caller is the clutter
-- window, which picks an item up so it can ask the cursor what it is really
-- holding before destroying it. False where the client has neither API, so the
-- caller stops rather than carrying on to a delete it cannot aim.
function ns.PickupContainerItem(bag, slot)
	if C_Container and C_Container.PickupContainerItem then
		C_Container.PickupContainerItem(bag, slot)
		return true
	end
	if type(_G.PickupContainerItem) == "function" then
		_G.PickupContainerItem(bag, slot)
		return true
	end
	return false
end

-- Name, icon, equip location and the link's own colour code, for an item link.
--
-- The name and the colour are read out of the link rather than asked for,
-- because the link is text the client already handed over and needs no cache
-- behind it. GetItemInfo answers nil for an item the client has not cached
-- yet, which for something sitting in your own bags is rare and not
-- impossible, so GetItemInfoInstant is preferred where it exists: it reads the
-- client's own item database and cannot miss.
--
-- Both lookups go through C_Item first, the same as ns.ItemValue and
-- ns.ItemKind below. This function did not, and that was the loot feed drawing
-- a question mark on every row: the newer client moved the item lookups into
-- C_Item and took the loose globals away, so the icon came back nil while the
-- quality colour and the quest ring, which are the two functions underneath
-- this one, went on working. A missing global here is not a client that cannot
-- answer, it is a client that was asked in the wrong place.
--
-- The fallback is on the icon rather than the equip location. Both callers
-- that read the location can do without it and no caller can do without the
-- picture, and an item with nowhere to equip it answers "" rather than nil,
-- which is a value that reads as an answer and stopped the second lookup ever
-- running for a stack of cloth.
function ns.ItemInfo(link)
	if type(link) ~= "string" then
		return nil
	end

	local name = link:match("%[(.-)%]")
	local color = link:match("|c(%x%x%x%x%x%x%x%x)")
	local equip, icon

	local instant = (C_Item and C_Item.GetItemInfoInstant) or _G.GetItemInfoInstant
	if type(instant) == "function" then
		local _, _, _, loc, texture = instant(link)
		equip, icon = loc, texture
	end

	local cached = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
	if not icon and type(cached) == "function" then
		local _, _, _, _, _, _, _, _, loc, texture = cached(link)
		equip = equip or loc
		icon = texture
	end

	return name, icon, equip, color
end

-- The name of an item's use effect, or nil for an item that has none.
--
-- This is what tells a trinket you press from a trinket you wear. The client
-- answers a spell name for the first and nothing at all for the second, which
-- is a better test than a cooldown reading: a passive trinket with a proc on it
-- carries a cooldown too, and a square for a cooldown you cannot spend is a
-- square that says press me about nothing.
function ns.ItemSpell(link)
	if type(link) ~= "string" then
		return nil
	end
	local lookup = (C_Item and C_Item.GetItemSpell) or _G.GetItemSpell
	if type(lookup) ~= "function" then
		return nil
	end
	return (lookup(link))
end

-- What a worn item's own cooldown reads, by inventory slot, in the three values
-- ns.SpellCooldown answers in. Zeroes where the client has no such call, which
-- reads as ready and is the honest answer: an addon that cannot ask has nothing
-- to say about a trinket's cooldown.
--
-- Probed rather than trusted, the same as UnitRace in Buffs/Racials.lua.
-- Nothing installed here calls it unguarded and a nil call on a ticker is what
-- gets the whole addon offered up for disabling.
function ns.InventoryCooldown(slot)
	local lookup = _G.GetInventoryItemCooldown
	if type(lookup) ~= "function" then
		return 0, 0, false
	end
	local start, duration, enabled = lookup("player", slot)
	return start or 0, duration or 0, enabled ~= 0
end

-- Quality and what a vendor pays, for an item link. Quality is the number the
-- client grades an item on, 0 being the grey a vendor exists to take off you.
--
-- Nil where the client has not cached the item yet, and a caller has to treat
-- that as "do not know" rather than as zero. Selling on a guessed quality is
-- how something that is not trash ends up at a vendor, so the vendor sweep
-- leaves an item it cannot grade alone and asks again on its next pass, by
-- which point the client has answered.
function ns.ItemValue(link)
	if type(link) ~= "string" then
		return nil
	end

	local lookup = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
	if type(lookup) ~= "function" then
		return nil
	end

	local _, _, quality, _, _, _, _, _, _, _, sellPrice = lookup(link)
	if type(quality) ~= "number" then
		return nil
	end
	return quality, sellPrice or 0
end

-- The item's id, and the class and subclass the client files it under. Class 12
-- is a quest item, which is the one the clutter scan turns on, and Baganator
-- categorises on the same number on this client.
--
-- GetItemInfoInstant rather than GetItemInfo, because this reads the client's
-- own item database and cannot miss the way a cache lookup can. That matters
-- here more than it does for a sell price: an item whose class came back nil
-- would be an item the scan silently never considered.
function ns.ItemKind(link)
	if type(link) ~= "string" then
		return nil
	end

	local lookup = (C_Item and C_Item.GetItemInfoInstant) or _G.GetItemInfoInstant
	if type(lookup) ~= "function" then
		return nil
	end

	local itemId, _, _, _, _, classId, subClassId = lookup(link)
	if type(itemId) ~= "number" then
		return nil
	end
	return itemId, classId, subClassId
end

--------------------------------------------------------------------------
-- Saved variables
--
-- ADDON_LOADED fires once every file in the TOC has run, so every feature has
-- already registered its defaults by the time this merges them.
--
-- Two tables. WarriorKitDB is the account's and reaches ns.db, WarriorKitCharDB
-- is this character's and reaches ns.dbc. Both are declared in the TOC and both
-- arrive at ADDON_LOADED, so no caller has to know which file its setting came
-- out of, only which name to read it from.
--------------------------------------------------------------------------

local function ApplyDefaults(db, from)
	for key, value in pairs(from) do
		if db[key] == nil then
			if type(value) == "table" then
				local copy = {}
				for i, v in pairs(value) do
					copy[i] = v
				end
				db[key] = copy
			else
				db[key] = value
			end
		end
	end
	return db
end

-- The registered default for one setting, so a reset does not repeat a literal
-- that already exists in a feature's defaults table. Anchor tables are the
-- exception: they are handed out by reference and dragging a frame mutates
-- them, so a reset must build a fresh one rather than reuse the default.
function ns.DefaultFor(key)
	if defaults[key] ~= nil then
		return defaults[key]
	end
	return charDefaults[key]
end

-- A character that carried the loadout backup from before the split has it in
-- the account file, where it does not belong and where the next character to
-- apply the loadout would have inherited it. Move it once, then leave the
-- account table alone.
local function Retire()
	for key in pairs(RETIRED) do
		WarriorKitDB[key] = nil
		WarriorKitCharDB[key] = nil
	end
end

local function Migrate()
	for key in pairs(charDefaults) do
		if WarriorKitDB[key] ~= nil then
			if WarriorKitCharDB[key] == nil then
				WarriorKitCharDB[key] = WarriorKitDB[key]
			end
			WarriorKitDB[key] = nil
		end
	end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, name)
	if name ~= ADDON then
		return
	end
	WarriorKitDB = WarriorKitDB or {}
	WarriorKitCharDB = WarriorKitCharDB or {}
	Retire()
	Migrate()
	ns.db = ApplyDefaults(WarriorKitDB, defaults)
	ns.dbc = ApplyDefaults(WarriorKitCharDB, charDefaults)
	self:UnregisterEvent("ADDON_LOADED")
end)
