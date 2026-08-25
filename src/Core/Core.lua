local ADDON, ns = ...

ns.version = "1.3"

-- Core knows nothing about any feature. It holds the saved variables, the API
-- shims, the two drawing helpers every part uses, and the one registry every
-- feature signs into. Adding a seventh part to the addon must not require
-- editing this file.

--------------------------------------------------------------------------
-- The registry
--
-- Each of the six parts calls ns.Register once, from its Feature.lua, and
-- hands over everything Core or the panel could want from it. Nothing else in
-- the addon reaches across parts to find out what exists.
--
--   name          the word that heads its slash help and its status line
--   order         where it sits in the panel and in /wk status
--   defaults      merged into ns.db, the account-wide saved variables
--   charDefaults  merged into ns.dbc, this character's saved variables
--   words         slash words this part answers to, word = function(arg, raw)
--   help          lines printed by /wk help
--   status        function returning one line for /wk status
--   lock          function applying ns.db.locked to this part's frames
--   reset         function putting this part's frames back where they started
--   panel         function(ui) building this part's section of the panel
--
-- Every field except name is optional. A part with no frames has no lock.
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

	-- 1.2: markKeys was a boolean for one edit before the marking keys became
	-- one setting per mark in markBinds. It never shipped, but a reload while it
	-- existed wrote it, and ApplyDefaults keeps whatever it finds, so a boolean
	-- would still be sitting where a table is now indexed.
	markKeys = true,
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

function ns.Register(feature)
	assert(type(feature) == "table" and type(feature.name) == "string",
		"a feature must register a table with a name")

	Claim(defaults, feature.defaults)
	Claim(charDefaults, feature.charDefaults)

	ns.features[#ns.features + 1] = feature
	table.sort(ns.features, function(a, b)
		return (a.order or 99) < (b.order or 99)
	end)
	return feature
end

-- Walks the registry so callers never name a feature. Used by lock, reset and
-- anything else that has to reach all six parts at once.
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
-- A coloured rectangle and a one pixel outline, which between them draw every
-- surface the addon owns. They live here rather than in one part because the
-- panel and the enemy bars both need them, and neither is allowed to reach
-- into the other. SetBackdrop is deliberately not used: it needs a template
-- that may not be on this client, and this is twenty lines.
--------------------------------------------------------------------------

function ns.Fill(parent, layer, r, g, b, a)
	local texture = parent:CreateTexture(nil, layer or "BACKGROUND")
	texture:SetColorTexture(r, g, b, a or 1)
	return texture
end

-- One screen pixel, in the units the frame is drawn in. SetHeight(1) is not
-- one pixel: a nameplate carries a scale of its own, so the same edge lands as
-- one and a half pixels on a plate and rounds up along one side and down along
-- the other, which reads as a thick lopsided border. Ask for this wherever an
-- edge is meant to be hairline, and ask again after a reparent.
function ns.Pixel(frame)
	local scale = frame and frame.GetEffectiveScale and frame:GetEffectiveScale()
	if not scale or scale <= 0 then
		return 1
	end
	return 1 / scale
end

function ns.EdgeSize(edges, size)
	edges[1]:SetHeight(size)
	edges[2]:SetHeight(size)
	edges[3]:SetWidth(size)
	edges[4]:SetWidth(size)
end

-- Returns the four edges so a caller that recolours on state, the way a bar
-- takes the threat colour, or resizes them to a real pixel, does not have to
-- rebuild them.
function ns.Outline(frame, r, g, b, a)
	local edges = {}
	for i = 1, 4 do
		edges[i] = ns.Fill(frame, "BORDER", r, g, b, a)
	end
	edges[1]:SetPoint("TOPLEFT")
	edges[1]:SetPoint("TOPRIGHT")
	edges[2]:SetPoint("BOTTOMLEFT")
	edges[2]:SetPoint("BOTTOMRIGHT")
	edges[3]:SetPoint("TOPLEFT")
	edges[3]:SetPoint("BOTTOMLEFT")
	edges[4]:SetPoint("TOPRIGHT")
	edges[4]:SetPoint("BOTTOMRIGHT")
	ns.EdgeSize(edges, 1)
	return edges
end

function ns.Recolor(edges, color)
	for i = 1, #edges do
		edges[i]:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
	end
end

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

--------------------------------------------------------------------------
-- Items
--
-- Two clients, two container APIs. Era backported C_Container and 2.5.6 may or
-- may not carry it, so both are probed and a client with neither answers empty
-- rather than erroring: a picker with nothing in it is a worse UI, not a
-- broken addon.
--------------------------------------------------------------------------

local C_Container = _G.C_Container

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

-- Name, icon, equip location and the link's own colour code, for an item link.
--
-- The name and the colour are read out of the link rather than asked for,
-- because the link is text the client already handed over and needs no cache
-- behind it. GetItemInfo answers nil for an item the client has not cached
-- yet, which for something sitting in your own bags is rare and not
-- impossible, so GetItemInfoInstant is preferred where it exists: it reads the
-- client's own item database and cannot miss.
function ns.ItemInfo(link)
	if type(link) ~= "string" then
		return nil
	end

	local name = link:match("%[(.-)%]")
	local color = link:match("|c(%x%x%x%x%x%x%x%x)")
	local equip, icon

	if type(_G.GetItemInfoInstant) == "function" then
		local _, _, _, loc, texture = _G.GetItemInfoInstant(link)
		equip, icon = loc, texture
	end

	if not equip and type(_G.GetItemInfo) == "function" then
		local _, _, _, _, _, _, _, _, loc, texture = _G.GetItemInfo(link)
		equip = loc
		icon = icon or texture
	end

	return name, icon, equip, color
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
