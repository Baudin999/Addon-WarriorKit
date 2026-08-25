-- The addon, loaded and driven under a stub of the client.
--
-- Nothing here is a client. It is enough of one to load every file in TOC
-- order, put nameplates up, run the enemy bars ticker and then ask four
-- questions no amount of reading the source will answer:
--
--   does the pixel grid resolve to one unit per pixel on a screen that is not
--   768 tall, which is every screen;
--   is a widget's geometry a whole number of pixels once the client's own
--   fractional measurements have been through it;
--   is a bar still the width the client's plate was after six mobs and a
--   setting change, or is it sizing itself off its own last answer;
--   and does a tick allocate.
--
-- The last is the one worth having automated. Allocation on a ticker is
-- invisible in review, invisible in game until a raid, and a one line change
-- reintroduces it. check.sh already bans the shapes that cause it inside the
-- functions HOT names; this measures the result and fails on a number.
--
-- What it does not prove: that the game agrees. Every API here answers what
-- this file says it answers. A stub that returns the wrong thing is a test
-- that passes and a client that does not.
--
--     lua5.1 scripts/harness.lua src

local SCREEN_H = 1440 -- a height that is not 768, which is the whole point
local UI_SCALE = 0.65

-- The bars' steady state, in KB per fifty ticks with two bars up, covering the
-- plate path and the list path both.
--
-- A ratchet, not a ceiling. It was 51.76 before the list collector stopped
-- allocating and 4.10 after, so the gate went in at 5.0. It measures 0.17 now,
-- so the gate is 0.5. Anything that improves this lowers the number in the same
-- commit, because a threshold parked at the worst case the codebase ever had is
-- a licence to go back there.
local LIST_CHURN_KB = 0.5

-- The skin's tick, in KB per fifty ticks across all three unit frames. Same
-- kind of ratchet. It was 18.75 while the level tag was built and then compared
-- on every tick, which is a tostring and a concat per frame to say a number
-- that changes when the unit does, and 0.00 once the tags were interned. Set at
-- the smallest figure that is not a claim the measurement can never move.
local SKIN_CHURN_KB = 0.5

--------------------------------------------------------------------------
-- The stub
--------------------------------------------------------------------------

local frames, events = {}, {}
local currentFile = "?"

local Region = {}
Region.__index = Region

-- Any PascalCase key is a method the client would have. Anything else is data
-- and has to answer nil, or code probing a frame for a region by name finds a
-- function where it expected a texture.
setmetatable(Region, { __index = function(_, key)
	if key:match("^%u") then
		return function() end
	end
	return nil
end })

-- The object type is data the addon branches on rather than a method it calls
-- for effect, so it cannot fall through to the no-op above. Both walks in
-- Skin.lua turn on it: a texture is hidden, a frame is recursed into, and
-- everything else, which is a status bar or an aura button, is left alone.
local TYPES = {
	frame = "Frame", texture = "Texture", fontstring = "FontString",
	statusbar = "StatusBar", button = "Button", font = "Font",
}

local function region(kind, parent, name)
	local self = setmetatable({
		kind = kind, parent = parent, name = name, scripts = {}, shown = true,
		width = 0, height = 0, scale = 1, ignoreScale = false, frameLevel = 0,
		regions = {}, children = {}, colorWrites = 0,
	}, Region)
	if name then
		_G[name] = self
	end
	return self
end

-- A frame's own textures and font strings answer GetRegions; its child frames
-- answer GetChildren. Both walks in Skin.lua need the two kept apart, because
-- one is what gets hidden and the other is what gets recursed into.
local function child(kind, parent, name)
	local self = region(kind, parent, name)
	if kind == "texture" or kind == "fontstring" then
		parent.regions[#parent.regions + 1] = self
	else
		parent.children[#parent.children + 1] = self
	end
	return self
end

function Region:GetObjectType() return TYPES[self.kind] or "Frame" end
function Region:GetRegions() return unpack(self.regions) end
function Region:GetChildren() return unpack(self.children) end
function Region:GetName() return self.name end

function Region:CreateTexture(name) return child("texture", self, name) end
function Region:CreateFontString() return child("fontstring", self) end
function Region:SetScript(name, fn) self.scripts[name] = fn end
function Region:GetScript(name) return self.scripts[name] end
function Region:SetSize(w, h) self.width, self.height = w, h end
function Region:SetWidth(w) self.width = w end
function Region:SetHeight(h) self.height = h end
function Region:GetWidth() return self.width end
function Region:GetHeight() return self.height end
--------------------------------------------------------------------------
-- A model of the text engine
--
-- Not the client's. It has one property the client's has and that is the only
-- one the layout depends on: a longer string in a narrower box is more lines,
-- and a row measured against it has to grow. Arial Narrow runs about 0.42 em
-- per glyph at panel sizes and a line box is the font size plus two, which is
-- close enough that a note wrapping to four lines here wraps to three or five
-- there and the row is tall enough either way.
--
-- Colour escapes are stripped before counting, because |cffd08040 is ten
-- characters of nothing and the notes are full of them.
--
-- What this cannot prove: that the game agrees on where a line breaks, that
-- GetStringHeight answers at all on a hidden font string, or that SetWordWrap
-- is on 2.5.6. All three are probed or floored in the code rather than trusted.
--------------------------------------------------------------------------

local ADVANCE, LEADING = 0.42, 2

local function plain(s)
	s = tostring(s or "")
	return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

function Region:SetText(s) self.text = s end
function Region:GetText() return self.text end
function Region:SetSpacing(v) self.spacing = v end
function Region:SetWordWrap(v) self.wordWrap = v and true or false end
function Region:SetJustifyH(v) self.justify = v end
function Region:FontSize()
	return self.fontSize or (self.fontObject and self.fontObject.fontSize) or 12
end
function Region:StringLines()
	local text = plain(self.text)
	if text == "" then
		return 0
	end
	if self.wordWrap == false or not self.width or self.width <= 0 then
		return 1
	end
	local wide = #text * ADVANCE * self:FontSize()
	return math.max(1, math.ceil(wide / self.width))
end
function Region:GetStringHeight()
	local lines = self:StringLines()
	if lines == 0 then
		return 0
	end
	return lines * (self:FontSize() + LEADING) + (lines - 1) * (self.spacing or 0)
end
-- 17.3 is what an unset string answers, deliberately fractional, because the
-- level tag on an enemy bar is sized off this and the whole point of that
-- assertion is that a fraction from outside the grid comes back whole.
function Region:GetStringWidth()
	local text = plain(self.text)
	if text == "" then
		return 17.3
	end
	return #text * ADVANCE * self:FontSize()
end
function Region:SetScale(s) self.scale = s end
function Region:GetScale() return self.scale end
function Region:SetIgnoreParentScale(v) self.ignoreScale = v end
function Region:GetEffectiveScale()
	if self.ignoreScale then
		return self.scale
	end
	return self.scale * (self.parent and self.parent:GetEffectiveScale() or 1)
end
function Region:SetParent(p) self.parent = p end
function Region:GetParent() return self.parent end
function Region:SetFrameLevel(l) self.frameLevel = l end
function Region:GetFrameLevel() return self.frameLevel end
function Region:GetFrameStrata() return "MEDIUM" end
function Region:SetTexCoord(a, b, c, d) self.texcoord = { a, b, c, d } end
-- Eight values, the way the client answers, and the first of them is the left
-- crop, which is what the skin's tick reads back before it writes.
function Region:GetTexCoord()
	local c = self.texcoord
	if not c then
		return nil
	end
	return c[1], c[3], c[1], c[4], c[2], c[3], c[2], c[4]
end
function Region:SetTexture(path) self.texture = path end
function Region:GetTexture() return self.texture end
function Region:SetColorTexture(r, g, b, a)
	-- A colour texture answers no file path, which is the readback Skin.lua's
	-- Flatten guards on. Counted rather than recorded, so the tick can be
	-- asserted to have stopped writing without the count itself allocating.
	self.texture = nil
	self.r, self.g, self.b, self.a = r, g, b, a
	self.colorWrites = self.colorWrites + 1
end
function Region:SetStatusBarTexture(t)
	if type(t) == "table" then
		self.fill = t
	else
		self.fill = self.fill or region("texture", self)
		self.fill.texture = t
	end
end
function Region:GetStatusBarTexture() return self.fill end
function Region:GetStatusBarColor() return 1, 1, 1, 1 end
function Region:SetSnapToPixelGrid(v) self.snapped = v end
function Region:SetTexelSnappingBias(v) self.bias = v end
function Region:SetFontObject(o) self.fontObject = o end
function Region:GetFont() return self.fontPath, self.fontSize, self.fontFlags end
function Region:SetFont(path, size, flags)
	self.fontPath, self.fontSize, self.fontFlags = path, size, flags
	return true
end
-- Real anchors, because the skin reads Blizzard's back out of its own snapshot
-- and places the whole block on the first of them. With GetNumPoints answering
-- nothing the snapshot recorded nothing, the block fell to its fallback anchor,
-- and the one conversion in the file that matters was never exercised.
function Region:SetPoint(point, relative, relativePoint, x, y)
	self.points = self.points or {}
	self.points[#self.points + 1] = { point, relative, relativePoint, x or 0, y or 0 }
end
function Region:ClearAllPoints() self.points = nil end
function Region:GetNumPoints() return self.points and #self.points or 0 end
function Region:GetPoint(index)
	local pt = self.points and self.points[index or 1]
	if not pt then
		return "CENTER", nil, "CENTER", 0, 0
	end
	return pt[1], pt[2], pt[3], pt[4], pt[5]
end
function Region:SetAllPoints(other)
	self.allPoints = other or self.parent
	self.points = { { "TOPLEFT", self.allPoints, "TOPLEFT", 0, 0 },
		{ "BOTTOMRIGHT", self.allPoints, "BOTTOMRIGHT", 0, 0 } }
end
-- Stored rather than swallowed by the metatable, because a secure button's
-- macro is written as an attribute and reading it back is the only way to
-- assert what a key press would actually send.
function Region:SetAttribute(key, value)
	self.attributes = self.attributes or {}
	self.attributes[key] = value
end
function Region:GetAttribute(key)
	return self.attributes and self.attributes[key]
end
function Region:IsProtected() return false end
function Region:SetShown(v) self.shown = v and true or false end
-- Recorded rather than swallowed by the metatable above, because which bar is
-- yours is said in alpha, and a no-op here is an assertion that reads back nil
-- and passes on nothing.
function Region:SetAlpha(v) self.alpha = v end
function Region:GetAlpha() return self.alpha or 1 end
function Region:IsShown() return self.shown end
-- Real, rather than the metatable's no-op, because the panel hides every
-- section but one and a stub that answers shown to all of them would let a
-- layout that puts seven pages on top of each other pass.
function Region:Show() self.shown = true end
function Region:Hide() self.shown = false end
function Region:RegisterEvent(e)
	events[e] = events[e] or {}
	events[e][#events[e] + 1] = self
end

_G.UIParent = region("frame")
_G.UIParent.scale = UI_SCALE
_G.UIParent.ignoreScale = true
_G.WorldFrame = region("frame")
_G.GameTooltip = region("frame")

function _G.CreateFrame(kind, name, parent)
	local f = child(kind, parent or _G.UIParent, name)
	f.origin = currentFile
	frames[#frames + 1] = f
	return f
end

function _G.CreateFont() return region("font") end

_G.GameFontNormal = region("font")
_G.GameFontNormal.fontPath = "Fonts\\FRIZQT__.TTF"
_G.GameFontNormalSmall, _G.GameFontHighlightSmall = _G.GameFontNormal, _G.GameFontNormal
_G.DEFAULT_CHAT_FRAME = { AddMessage = function() end }

function _G.GetPhysicalScreenSize() return 3440, SCREEN_H end

-- A clock that advances a fixed amount per read, so a bracketed tick measures
-- the same figure every run and an assertion on it means something. The real
-- one is a wall clock and would make every number here a coin toss.
local TICK_MS = 0.05
local clock = 0
function _G.debugprofilestop()
	clock = clock + TICK_MS
	return clock
end
function _G.GetFramerate() return 97.5 end

-- Memory that only ever rises, which is what an addon between collections does.
local heap = 300
function _G.UpdateAddOnMemoryUsage() heap = heap + 2 end
function _G.GetAddOnMemoryUsage(name)
	return (name == "WarriorKit") and heap or 0
end

local cvars = { nameplateShowEnemies = "1", nameplateMotion = "0",
	nameplateOverlapV = "1.10", SoftTargetEnemy = "0" }
function _G.GetCVar(k) return cvars[k] end
function _G.SetCVar(k, v) cvars[k] = tostring(v) return true end
function _G.GetCVarBool(k) return cvars[k] == "1" end

local plates, sized = {}, nil
local PLATE_W, PLATE_H = 110, 45 -- what this stub client's own plate measures
_G.C_NamePlate = {
	GetNamePlates = function()
		local out = {}
		for i, p in ipairs(plates) do out[i] = p end
		return out
	end,
	GetNamePlateForUnit = function(unit)
		for _, p in ipairs(plates) do
			if p.namePlateUnitToken == unit then return p end
		end
	end,
	-- The client resizes every enemy plate it has when told, and that is not a
	-- detail: the bars read a plate's width to size themselves, so a stub that
	-- only records the call cannot see a bar sizing itself off its own last
	-- answer. Plates put up later start at the size in force, the same way.
	SetNamePlateEnemySize = function(w, h)
		sized = { w, h }
		for _, p in ipairs(plates) do
			p:SetSize(w, h)
		end
	end,
}

local guids = {}
local function constant(v) return function() return v end end
_G.UnitExists = function(u) return guids[u] ~= nil end
_G.UnitGUID = function(u) return guids[u] end
_G.UnitIsUnit = function(a, b) return a == b end
_G.UnitClass = function() return "Warrior", "WARRIOR" end
_G.UnitDetailedThreatSituation = function() return true, 3, 100, 0, 1200 end
_G.UnitIsDead, _G.UnitCanAttack = constant(false), constant(true)
_G.UnitName, _G.UnitHealth, _G.UnitHealthMax = constant("Target Dummy"), constant(4200), constant(9000)
_G.UnitLevel, _G.UnitReaction = constant(62), constant(2)
-- True for exactly one unit, so the skin's player frame takes the class colour
-- through ClassTint and the other two fall to the reaction colour. Both halves
-- of Tint run, and the per class cache gets filled once and read after that.
_G.UnitIsPlayer = function(unit) return unit == "player" end
_G.UnitAffectingCombat, _G.UnitAura = constant(false), constant(nil)
_G.UnitPowerType, _G.UnitPower, _G.UnitPowerMax = constant(1), constant(40), constant(100)
_G.UnitPlayerOrPetInParty, _G.UnitPlayerOrPetInRaid = constant(false), constant(false)
_G.UnitIsGroupLeader, _G.UnitIsGroupAssistant = constant(true), constant(false)
_G.GetNumGroupMembers, _G.IsInRaid = constant(0), constant(false)
_G.GetRaidTargetIndex, _G.SetRaidTarget = constant(nil), function() end
_G.SetRaidTargetIconTexture = function() end
_G.GetTime, _G.GetQuestGreenRange, _G.InCombatLockdown = constant(100), constant(8), constant(false)
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
_G.tinsert, _G.date = table.insert, os.date
_G.GetBuildInfo = function() return "2.5.6", "69110", "2025-01-01", 20506 end
_G.RAID_CLASS_COLORS = { WARRIOR = { r = 0.78, g = 0.61, b = 0.43 } }
_G.GetSpellInfo = function(id) return "Spell" .. id, nil, "Interface\\Icons\\A" .. id end
_G.GetSpellTexture = function(id) return "Interface\\Icons\\A" .. id end
_G.GetSpellCooldown = function() return 0, 0 end
_G.IsUsableSpell, _G.IsSpellInRange, _G.IsSpellKnown = constant(true), constant(1), constant(true)
_G.GetNumSpellTabs = constant(0)
-- Three items in the backpack and empty hands. Enough for the gear scan to
-- have something to offer, and chosen so all three rules it enforces are
-- reachable: a main hander, a shield, and a two hander that must keep the
-- off hand line out of a loadout's macro.
local ITEMS = {
	["Bloodspiller"]    = { equip = "INVTYPE_WEAPONMAINHAND", icon = "Interface\\Icons\\Sword" },
	["Aegis"]           = { equip = "INVTYPE_SHIELD", icon = "Interface\\Icons\\Shield" },
	["Arcanite Reaper"] = { equip = "INVTYPE_2HWEAPON", icon = "Interface\\Icons\\Axe" },
}
local BAG = { "Bloodspiller", "Aegis", "Arcanite Reaper" }

local function itemLink(name)
	return ("|cffff8000|Hitem:1::::::::60:::::|h[%s]|h|r"):format(name)
end
_G.WarriorKitItemLink = itemLink

_G.GetInventoryItemLink, _G.GetItemInfo = constant(nil), constant(nil)
-- The fourth and fifth returns are the two ns.ItemInfo reads, the equip
-- location and the icon.
_G.GetItemInfoInstant = function(link)
	local name = type(link) == "string" and link:match("%\[(.-)%\]")
	local item = name and ITEMS[name]
	if not item then
		return nil
	end
	return 1, name, nil, item.equip, item.icon
end
_G.GetContainerNumSlots = function(bag) return bag == 0 and #BAG or 0 end
_G.GetContainerItemLink = function(bag, slot)
	return bag == 0 and BAG[slot] and itemLink(BAG[slot]) or nil
end
_G.GetCursorInfo, _G.ClearCursor = constant(nil), function() end
_G.CursorHasItem = constant(false)
-- id and the empty-slot art, the two the gear slots read. The path is shaped
-- like the client's so a slot that draws it can be told from one that does not.
_G.GetInventorySlotInfo = function(name)
	return 16, "Interface\\PaperDoll\\UI-PaperDoll-Slot-" .. tostring(name)
end
_G.HasAction, _G.GetActionInfo, _G.GetBonusBarOffset = constant(false), constant(nil), constant(0)
_G.GetMacroIndexByName, _G.GetMacroInfo = constant(0), constant(nil)
_G.GetNumMacros = function() return 0, 0 end
_G.RegisterStateDriver = function() end
-- The override layer, modelled rather than accepted. Every part that takes a
-- key reads GetBindingAction back afterwards rather than believing its own
-- SetOverrideBindingClick, because a client that takes the call and does
-- nothing with it leaves no other trace. A stub that answered "" to every
-- readback would make all three of them report a client that refused the key.
local overrides = {}
_G.ClearOverrideBindings = function(owner)
	for key, held in pairs(overrides) do
		if held.owner == owner then
			overrides[key] = nil
		end
	end
end
_G.SetOverrideBindingClick = function(owner, _, key, name, suffix)
	overrides[key] = { owner = owner, action = ("CLICK %s:%s"):format(name, suffix) }
	return true
end
_G.GetBindingAction = function(key, checkOverride)
	local held = checkOverride and overrides[key]
	return held and held.action or ""
end
_G.IsControlKeyDown, _G.IsShiftKeyDown, _G.IsAltKeyDown = constant(false), constant(false), constant(false)
_G.GetShapeshiftForm = constant(1)
_G.UISpecialFrames, _G.SlashCmdList, _G.Enum = {}, {}, {}

--------------------------------------------------------------------------
-- Load and drive
--------------------------------------------------------------------------

local ROOT = arg[1] or "src"
local ns = {}

local order = {}
for line in io.lines(ROOT .. "/WarriorKit.toc") do
	line = line:gsub("\r", ""):gsub("\\", "/")
	if line:match("^[A-Za-z].*%.lua$") then
		order[#order + 1] = line
	end
end
for _, path in ipairs(order) do
	currentFile = path
	assert(loadfile(ROOT .. "/" .. path))("WarriorKit", ns)
	currentFile = "runtime"
end

local function fire(event, ...)
	for _, f in ipairs(events[event] or {}) do
		if f.scripts.OnEvent then
			f.scripts.OnEvent(f, event, ...)
		end
	end
end

-- The three Blizzard unit frames, shaped the way 2.5.6 shapes them: a portrait
-- and two status bars hung off the frame under the four parent keys the skin
-- resolves through, the ring and the state icons on a texture frame one level
-- down, and target of target parented to the target frame, which is the nesting
-- the skin's skip set exists for. Standing them up before PLAYER_LOGIN because
-- that is when Skin.lua resolves and styles them.
local PORTRAIT_X, PORTRAIT_Y = 7, -11

local function unitFrame(name, w, h, parent, badges)
	local frame = child("frame", parent or _G.UIParent, name)
	frame:SetSize(w, h)
	frame:CreateTexture(name .. "Background")
	frame.portrait = frame:CreateTexture(name .. "Portrait")
	frame.portrait:SetTexture("Interface\\CharacterFrame\\TempPortrait")
	-- Anchored the way Blizzard anchors a portrait, in the frame's own units,
	-- which is the number the skin has to convert before it can hang the block
	-- on it. Deliberately not a whole pixel at this scale.
	frame.portrait:SetPoint("TOPLEFT", frame, "TOPLEFT", PORTRAIT_X, PORTRAIT_Y)
	frame.portrait:SetSize(60, 60)

	for _, key in ipairs({ "healthbar", "manabar" }) do
		local bar = child("statusbar", frame, name .. (key == "healthbar" and "HealthBar" or "ManaBar"))
		bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
		bar:SetSize(119, 12)
		bar.TextString = bar:CreateFontString()
		frame[key] = bar
	end

	local art = child("frame", frame, name .. "TextureFrame")
	art:CreateTexture(name .. "Ring")
	art:CreateTexture(name .. "Flash")
	frame.name = art:CreateFontString()
	for _, badge in ipairs(badges or {}) do
		art:CreateTexture(badge)
	end
	return frame
end

local playerFrame = unitFrame("PlayerFrame", 232, 100, nil,
	{ "PlayerRestIcon", "PlayerAttackIcon", "PlayerPVPIcon" })
child("fontstring", playerFrame, "PlayerLevelText")
local targetFrame = unitFrame("TargetFrame", 232, 100, nil,
	{ "TargetFrameRaidTargetIcon", "TargetFramePVPIcon" })
child("fontstring", targetFrame, "TargetLevelText")
unitFrame("TargetFrameToT", 120, 50, targetFrame, {})

_G.WarriorKitDB, _G.WarriorKitCharDB = {}, {}
fire("ADDON_LOADED", "WarriorKit")
fire("PLAYER_LOGIN")
fire("PLAYER_ENTERING_WORLD")

local failures = 0
local function check(ok, message)
	if not ok then
		failures = failures + 1
		print("  FAIL " .. message)
	end
end

-- A mob and the plate the client puts up for it, carrying a scale of its own
-- the way a real plate does, so a widget that inherited it would be measurably
-- wrong. The size is whatever the client has in force, which is this stub's own
-- figure until the addon has asked for another.
local function Pull(index)
	local unit = "nameplate" .. index
	local plate = region("frame", _G.UIParent)
	plate.namePlateUnitToken = unit
	plate.scale = 1.1
	plate:SetSize(sized and sized[1] or PLATE_W, sized and sized[2] or PLATE_H)
	plate.UnitFrame = region("frame", plate)
	plate.UnitFrame:SetSize(plate:GetWidth(), plate:GetHeight())
	-- The child regions a TBC nameplate actually carries. They have to exist
	-- rather than fall through to the metatable above: several are PascalCase,
	-- and a stub that answers a method there hands the strip a function where
	-- it expected a texture.
	for _, child in ipairs({ "healthBar", "name", "LevelFrame", "ClassificationFrame",
		"selectionHighlight", "aggroHighlight", "RaidTargetFrame" }) do
		plate.UnitFrame[child] = region("frame", plate.UnitFrame)
	end
	plates[#plates + 1] = plate
	guids[unit] = ("Creature-0-0-0-0-1234-0000000%d"):format(index)
	fire("NAME_PLATE_UNIT_ADDED", unit)
	return ns.EnemyBars.WidgetFor(unit)
end

for i = 1, 2 do
	Pull(i)
end

local anchor = _G.WarriorKitEnemyBarsAnchor
local widget = ns.EnemyBars.WidgetFor("nameplate1")
check(anchor ~= nil, "no anchor came up")
check(widget ~= nil, "no widget attached to nameplate1")

-- The grid.
check(math.abs(ns.UI.Scale() - 768 / SCREEN_H) < 1e-9,
	("perfect scale is %.6f, expected %.6f"):format(ns.UI.Scale(), 768 / SCREEN_H))
for name, frame in pairs({ anchor = anchor, widget = widget }) do
	local px = ns.UI.Pixel(frame)
	check(math.abs(px - 1) < 1e-9, ("%s is not on the grid: one pixel is %.4f units"):format(name, px))
end

-- Whole pixels where the grid can reach. The tag is the one size derived from
-- a measurement the client made, so it is the one that can come back fractional.
for _, pair in ipairs({ { "widget", widget }, { "box", widget.box }, { "tag", widget.level },
	{ "icon", widget.icons[1] } }) do
	for _, axis in ipairs({ "GetWidth", "GetHeight" }) do
		local size = pair[2][axis](pair[2])
		check(math.abs(size - math.floor(size + 0.5)) < 1e-9,
			("%s %s is %.4f, not a whole pixel"):format(pair[1], axis, size))
	end
end

-- A bar on a plate is `bars width` pixels, every bar, and it stays there.
--
-- It used to be as wide as the plate under it, and it then told the driver to
-- size plates by a footprint a tag wider than itself, so the next bar measured
-- off a plate came back changed: wider every round where a plate is scaled
-- above UIParent, which is this stub and was the harness case, narrower every
-- round on the client this was reported from. Either way no fixed point and no
-- setting that chose one. The five lines below are the whole of the contract:
-- the setting decides, six mobs do not move it, and a setting change does not
-- either.
local function BarWidth(unit)
	local bar = ns.EnemyBars.WidgetFor(unit)
	return bar and bar:GetWidth() or -1
end

local wanted = ns.db.barsWidth * ns.UI.Pixel(widget)
check(BarWidth("nameplate1") == wanted,
	("a bar on a plate is %.0f px, the setting says %.0f"):format(BarWidth("nameplate1"), wanted))
for i = 3, 6 do
	Pull(i)
	check(BarWidth("nameplate" .. i) == wanted,
		("mob %d got a bar %.0f px wide, the setting says %.0f"):format(
			i, BarWidth("nameplate" .. i), wanted))
end
ns.EnemyBars.Rebuild() -- what every setting in the panel does
check(BarWidth("nameplate1") == wanted,
	("a setting change took the bar to %.0f px, the setting says %.0f"):format(
		BarWidth("nameplate1"), wanted))

-- And the setting reaches a bar that is already on a plate, which is the half
-- of it that has no second chance: a widget on a plate is laid out when it
-- attaches, and these attached before the number changed.
ns.db.barsWidth = 240
ns.EnemyBars.ApplyLayout()
check(BarWidth("nameplate1") == 240 * ns.UI.Pixel(widget),
	("bars width 240 left the bar on a plate at %.0f px"):format(BarWidth("nameplate1")))
ns.db.barsWidth = 180
ns.EnemyBars.ApplyLayout()

-- Back down to the two the churn figure below is quoted at. The gate is a
-- number of KB per fifty ticks with two bars up, so the mobs pulled to prove
-- the width holds have to leave again or the ratchet is measuring a different
-- scene than the one it was set on.
for i = #plates, 3, -1 do
	fire("NAME_PLATE_UNIT_REMOVED", plates[i].namePlateUnitToken)
	guids[plates[i].namePlateUnitToken] = nil
	plates[i] = nil
end

-- The edges are one pixel, which was the whole complaint.
check(widget.box.edges[1].height == ns.UI.Pixel(widget),
	("hairline is %.4f units, expected %.4f"):format(widget.box.edges[1].height, ns.UI.Pixel(widget)))

-- The icon crop lands on texel boundaries and the client's snapping is off.
local art = widget.icons[1].texture
check(art.texcoord and math.abs(art.texcoord[1] * 64 - 5) < 1e-9,
	"icon crop is not on a texel boundary")
check(art.snapped == false and art.bias == 0, "icon texture is still being snapped")

-- The driver has been told how much room a bar wants.
check(cvars.nameplateMotion == "1", "nameplates were not asked to stack")
check(sized ~= nil, "the plate size was never set")

-- Allocation. Every ticker but the bars' is somebody else's measurement.
local barTicker
for _, f in ipairs(frames) do
	if f.scripts.OnUpdate and f.origin:match("EnemyBars") then
		barTicker = f
	end
end
check(barTicker ~= nil, "the enemy bars registered no ticker")

local function churn(n)
	collectgarbage("collect")
	collectgarbage("stop")
	local before = collectgarbage("count")
	for _ = 1, n do
		barTicker.scripts.OnUpdate(barTicker, 0.05)
	end
	local after = collectgarbage("count")
	collectgarbage("restart")
	return after - before
end

-- Cold first, because the first pass interns every label the bars will ever
-- show and that is a one time cost, not a per tick one.
churn(200)
local plateChurn = churn(200)

ns.db.barsMode = "list"
ns.EnemyBars.Rebuild()
churn(200)
local listChurn = churn(200)

--------------------------------------------------------------------------
-- The skin on the three Blizzard unit frames
--
-- The same questions as the bars, against a part that cannot put its subject
-- on the grid. The portrait, the two bars and the state icons are regions of a
-- secure unit button, so what is asserted here is the boundary: whole pixels on
-- the frames the addon made, a sampling fix on the art it borrowed, sizes that
-- crossed the scale on the way out, and a tick that neither allocates nor
-- writes what is already there.
--
-- The block's own origin is deliberately not asserted. It hangs off Blizzard's
-- portrait anchor on a frame that is not on the grid, so where it lands is a
-- fraction the client owns, exactly as a bar on a nameplate is.
--------------------------------------------------------------------------

-- Units for the three frames, added now rather than at login so the enemy bar
-- figures above are measured against two mobs and not three.
guids.player, guids.target, guids.targettarget = "Player-1", "Creature-9", "Creature-8"
-- Apply rather than a tick, because that is what a target change does and it
-- is the path that has to leave a frame fully painted: a fifth of a second of
-- a white gauge reads as a bug.
ns.FrameSkin.Apply()

local blocks = {
	{ "player", _G.WarriorKitSkinPlayer, _G.PlayerFrame },
	{ "target", _G.WarriorKitSkinTarget, _G.TargetFrame },
	{ "tot", _G.WarriorKitSkinToT, _G.TargetFrameToT },
}

-- entry.top is the only frame the skin pins to the whole of the box, which is
-- how it is found without this file reaching into the module's own tables.
local function textFrame(box)
	for _, f in ipairs(box.parent.children) do
		if f.allPoints == box then
			return f
		end
	end
end

check(ns.FrameSkin.Hidden() > 0, "the skin walked all three frames and hid nothing")

for _, block in ipairs(blocks) do
	local key, box, frame = block[1], block[2], block[3]
	if not box then
		check(false, key .. ": no block was built over " .. tostring(frame and frame.name))
	else
		-- On the grid, which is the whole of what the addon can put there.
		check(box.ignoreScale == true, key .. ": the block is still on the unit frame's scale")
		local px = ns.UI.Pixel(box)
		check(math.abs(px - 1) < 1e-9,
			("%s: block is not on the grid, one pixel is %.4f units"):format(key, px))
		for _, axis in ipairs({ "GetWidth", "GetHeight" }) do
			local size = box[axis](box)
			check(size > 0 and math.abs(size - math.floor(size + 0.5)) < 1e-9,
				("%s: block %s is %.4f, not a whole pixel"):format(key, axis, size))
		end

		-- The block hangs off the portrait's own anchor, and the offset in
		-- that anchor was written by the client in the client's units. Two
		-- things are asserted about what came out: it is a whole pixel, and it
		-- is not the number that went in. The second is the one with teeth,
		-- because Blizzard writes whole units and a whole unit is a whole
		-- number in either space, so a conversion quietly dropped would still
		-- pass the first test and put the block a fifth of its width out.
		local slot = box.points and box.points[1] and box.points[1][2]
		check(slot ~= nil, key .. ": the block is not hung on the portrait's square")
		local offset = slot and slot.points and slot.points[1]
		check(offset ~= nil, key .. ": the square was never anchored")
		for _, axis in ipairs({ { "x", 4, PORTRAIT_X }, { "y", 5, PORTRAIT_Y } }) do
			local value = offset and offset[axis[2]] or 0
			check(math.abs(value - math.floor(value + 0.5)) < 1e-9,
				("%s: the anchor's %s offset is %.4f, not a whole pixel")
					:format(key, axis[1], value))
			check(value ~= axis[3],
				("%s: the anchor's %s offset is still Blizzard's %d, unconverted")
					:format(key, axis[1], axis[3]))
		end

		-- The two rails are the only frames the block parents, and Blizzard's
		-- bars are pinned to them corner to corner rather than sized.
		local healthRail, powerRail = box.children[1], box.children[2]
		check(healthRail and powerRail, key .. ": the gauge rails were never built")
		for name, rail in pairs({ health = healthRail, power = powerRail }) do
			local height = rail and rail:GetHeight() or 0
			check(height >= 1 and math.abs(height - math.floor(height + 0.5)) < 1e-9,
				("%s: the %s rail is %.4f pixels tall, not a whole one"):format(key, name, height))
		end
		check(frame.healthbar.allPoints == healthRail,
			key .. ": the health bar is not pinned to its rail")
		check(frame.manabar.allPoints == powerRail,
			key .. ": the power bar is not pinned to its rail")

		-- Sampled art. The crop is on a texel boundary and the client's own
		-- snapping is off, the same two fixes a spell icon takes.
		local portrait = frame.portrait
		check(portrait.texcoord and math.abs(portrait.texcoord[1] * 64 - 10) < 1e-9,
			key .. ": the portrait crop is not on a texel boundary")
		check(portrait.snapped == false and portrait.bias == 0,
			key .. ": the portrait is still being snapped by the client")

		-- Sizes written onto a region of the unit frame cross the scale on the
		-- way out, and land on an even count so a badge centred on a corner
		-- does not put all four of its edges on a half pixel.
		local theirs = ns.UI.Pixel(frame)
		for _, badge in ipairs(frame.children[3].regions) do
			if badge.width > 0 then
				-- Rounded before the parity test, not after: the size was
				-- written as a count of pixels times the scale between us and
				-- reading it back divides that out again, which lands a hair
				-- off a whole number and never on one.
				local pixels = badge.width / theirs
				local whole = math.floor(pixels + 0.5)
				check(math.abs(pixels - whole) < 1e-6 and whole % 2 == 0,
					("%s: badge %s is %.4f pixels wide, not an even whole number")
						:format(key, tostring(badge.name), pixels))
			end
		end

		-- Shared font objects, not a font per string.
		local top = textFrame(box)
		check(top ~= nil, key .. ": no text frame over the block")
		for _, text in ipairs(top and top.regions or {}) do
			check(text.fontObject ~= nil and text.fontPath == nil,
				key .. ": a font string carries its own font instead of a shared object")
		end
	end
end

local skinTicker
for _, f in ipairs(frames) do
	if f.scripts.OnUpdate and f.origin:match("Skin") then
		skinTicker = f
	end
end
check(skinTicker ~= nil, "the skin registered no ticker")

local function skinChurn(n)
	collectgarbage("collect")
	collectgarbage("stop")
	local before = collectgarbage("count")
	for _ = 1, n do
		skinTicker.scripts.OnUpdate(skinTicker, 0.05)
	end
	local after = collectgarbage("count")
	collectgarbage("restart")
	return after - before
end

-- Cold first, the same as the bars: the first pass fills the class colour
-- cache and interns one level tag per frame, and neither is a per tick cost.
skinChurn(200)
local writesBefore = _G.PlayerFrame.healthbar.fill.colorWrites
local blockChurn = skinChurn(200)
local flattenWrites = _G.PlayerFrame.healthbar.fill.colorWrites - writesBefore

print(("grid   %s"):format(ns.UI.Describe()))
print(("bar    %.0f x %.0f px, box %.0f, tag %.0f, icon %.0f, hairline %.0f")
	:format(widget:GetWidth(), widget:GetHeight(), widget.box:GetHeight(),
		widget.level:GetWidth(), widget.icons[1]:GetWidth(), widget.box.edges[1].height))
print(("plates %s"):format(ns.Plates.Describe()))
local playerBox = _G.WarriorKitSkinPlayer
print(("skin   %s; player block %.0f x %.0f px, gauge %.0f and %.0f, hairline %.0f")
	:format(ns.FrameSkin.Describe(), playerBox:GetWidth(), playerBox:GetHeight(),
		playerBox.children[1]:GetHeight(), playerBox.children[2]:GetHeight(),
		playerBox.edges[1].height))
print(("churn  %.2f KB per 50 plate ticks, %.2f KB per 50 list ticks, two bars, gate is %.2f")
	:format(plateChurn, listChurn, LIST_CHURN_KB))
print(("skin   %.2f KB per 50 ticks across three frames, gate is %.2f; %d bar flattens in 50 ticks")
	:format(blockChurn, SKIN_CHURN_KB, flattenWrites))

check(listChurn <= LIST_CHURN_KB,
	("the list collector allocates %.2f KB per 50 ticks, over the %.2f gate")
		:format(listChurn, LIST_CHURN_KB))
check(plateChurn <= LIST_CHURN_KB,
	("the plate path allocates %.2f KB per 50 ticks, over the %.2f gate")
		:format(plateChurn, LIST_CHURN_KB))
check(blockChurn <= SKIN_CHURN_KB,
	("the skin allocates %.2f KB per 50 ticks, over the %.2f gate")
		:format(blockChurn, SKIN_CHURN_KB))
-- The bars and the portrait are the two things this file re-applies on every
-- tick because Blizzard's code puts them back. Re-applying is not the same as
-- writing: nothing has touched either one here, so the readback should hold and
-- the count should be flat.
check(flattenWrites == 0,
	("the skin flattened one bar %d times in 50 idle ticks, and nothing had unflattened it")
		:format(flattenWrites))

--------------------------------------------------------------------------
-- The options window
--
-- Opened, then walked: every entry in the rail, every tab under every entry,
-- and every row on every tab. Four things are asserted that reading the source
-- cannot settle, and all four are the complaints that caused the rewrite.
--
-- The window is on the grid and sized in whole pixels, so a hairline is a
-- hairline and a row is not half a pixel tall.
--
-- No row is fractional and no row is shorter than the text inside it. That is
-- the overflow bug, and the only way to see it is to set the real strings the
-- features write, wrap them to the real width the layout hands out, and compare.
--
-- A note that wraps produces a row that grew. A page whose rows come to more
-- than the viewport turns the scrollbar on, and one whose rows do not turns it
-- off, with no stub of a bar left behind.
--------------------------------------------------------------------------

local window = ns.UI.Windows[1]
check(window ~= nil, "no window was built")

local function whole(value)
	return math.abs(value - math.floor(value + 0.5)) < 1e-6
end

if window then
	ns.Options.Show()

	check(math.abs(ns.UI.Pixel(window.frame) - 1) < 1e-9,
		("the window is not on the grid: one pixel is %.4f units"):format(ns.UI.Pixel(window.frame)))
	check(whole(window.width) and whole(window.height),
		("the window is %.2f x %.2f, not a whole number of pixels"):format(window.width, window.height))
	check(window.height * window.zoom <= SCREEN_H,
		("the window is %.0f pixels tall on a %d pixel screen"):format(window.height * window.zoom, SCREEN_H))
	check(window.view.mechanism ~= "none",
		"neither SetClipsChildren nor the ScrollFrame type came up, so nothing clips")

	local rows, tabs, wrapped, tallest, shortest = 0, 0, 0, 0, math.huge
	for index = 1, #window.parts do
		local part = window.parts[index]
		check(window.rail:Select(index), ("rail entry %d refused to select"):format(index))
		check(#part.sections >= 1, ("%s has no section"):format(part.name))
		check(part.tabs.frame:IsShown(),
			("%s is selected in the rail and its tab strip is hidden"):format(part.name))
		check(whole(part.tabs.frame:GetHeight()),
			("%s has a tab strip %.2f pixels tall"):format(part.name, part.tabs.frame:GetHeight()))
		tabs = tabs + #part.sections

		for section = 1, #part.sections do
			ns.Options.SelectSection(section)
			local stack = part.sections[section].stack
			local where = ("%s / %s"):format(part.name, part.sections[section].title)

			check(stack.frame:IsShown(), where .. " did not show when its tab was chosen")
			for other = 1, #part.sections do
				if other ~= section then
					check(not part.sections[other].stack.frame:IsShown(),
						where .. " is showing while another section of the same page is too")
				end
			end

			for _, cell in ipairs(stack.cells) do
				rows = rows + 1
				check(whole(cell.height),
					("%s: a row is %.3f pixels tall, not a whole pixel"):format(where, cell.height))
				if cell.frame then
					check(cell.frame:GetWidth() + cell.indent <= stack.width + 1e-6,
						("%s: a row is %.1f wide inside a %.1f column"):format(where,
							cell.frame:GetWidth() + cell.indent, stack.width))
					-- Every string on the row, measured at the width the layout
					-- gave it. A row shorter than its own text is text drawn over
					-- whatever comes next, which is the whole complaint.
					for _, text in ipairs(cell.frame.regions) do
						if text.kind == "fontstring" and plain(text.text) ~= "" then
							local lines = text:StringLines()
							if lines > 1 then
								wrapped = wrapped + 1
							end
							check(cell.height + 1e-6 >= text:GetStringHeight(),
								("%s: a %d line string is %.1f tall in a %.1f row")
									:format(where, lines, text:GetStringHeight(), cell.height))
						end
					end
				end
			end

			-- The stack's own answer rather than the sum of the rows, because the
			-- air between them is height the viewport has to find too.
			if stack.height > tallest then
				tallest = stack.height
			end
			if stack.height < shortest then
				shortest = stack.height
			end

			-- Scrolling, both ways round. A section past the viewport has a bar
			-- that is showing and has somewhere to go; one that fits has none and
			-- is pinned at the top.
			local view = window.view
			if view.extent > view.height then
				check(view.scrollable, where .. " is taller than the viewport and does not scroll")
				check(view.bar == nil or view.bar:IsShown(),
					where .. " scrolls and shows no bar")
				view:ScrollTo(1e6)
				check(view.offset == view.extent - view.height,
					("%s: scrolling to the end landed at %.1f, not %.1f")
						:format(where, view.offset, view.extent - view.height))
				view:ScrollTo(0)
			else
				check(not view.scrollable, where .. " fits the viewport and still thinks it scrolls")
				check(view.bar == nil or not view.bar:IsShown(),
					where .. " fits the viewport and left a stub of a scrollbar behind")
				check(view.offset == 0, where .. " fits the viewport and is scrolled off the top")
			end
		end
	end

	check(wrapped > 0, "not one string in the whole panel wrapped, so nothing was measured")
	check(tallest > window.view.height,
		("the tallest section is %.0f pixels in a %.0f viewport, so scrolling was never exercised")
			:format(tallest, window.view.height))
	check(shortest <= window.view.height,
		("every section overflows, so the bar was never asked to hide"))

	print(("panel  %.0f x %.0f px at zoom %d, %d parts, %d tabs, %d rows, %d wrapped strings")
		:format(window.width, window.height, window.zoom, #window.parts, tabs, rows, wrapped))
	print(("panel  viewport %.0f x %.0f, tallest section %.0f, clipping by %s")
		:format(window.view.width, window.view.height, tallest, window.view.mechanism))

	ns.Options.Hide()
end

--------------------------------------------------------------------------
-- Which bar is yours
--
-- Four states and not two. The third is the one that gets lost in a refactor:
-- with nothing targeted every bar is bright, because dimming the whole screen
-- to say "none of these" is noise and it is the moment you most want to read
-- threat off a mob that is not yours yet.
--------------------------------------------------------------------------

do
	-- Everything above this point has been driving the panel and the skin, so
	-- the bars are put back where this section needs them rather than assumed.
	-- UnitIsUnit compares tokens in the stub, which is enough for every other
	-- caller and not enough here: "nameplate1" and "target" are two tokens for
	-- one mob and that is the whole question being asked.
	local realIsUnit = _G.UnitIsUnit
	_G.UnitIsUnit = function(x, y)
		if x == y then
			return true
		end
		return guids[x] ~= nil and guids[x] == guids[y]
	end

	ns.db.bars = true
	ns.db.barsMode = "plates"
	guids.target = nil
	ns.EnemyBars.Rebuild()
	for i = 1, 2 do
		fire("NAME_PLATE_UNIT_ADDED", "nameplate" .. i)
	end
	check(ns.EnemyBars.WidgetFor("nameplate1") ~= nil,
		"no bar attached, so the alpha states below would pass on nothing")

	local function Alpha(unit)
		local bar = ns.EnemyBars.WidgetFor(unit)
		return bar and bar:GetAlpha() or -1
	end
	local function Tick()
		for _ = 1, 4 do
			barTicker.scripts.OnUpdate(barTicker, 0.05)
		end
	end

	Tick()
	check(Alpha("nameplate1") == 1 and Alpha("nameplate2") == 1,
		"with nothing targeted both bars should be bright")

	guids.target = guids.nameplate1
	Tick()
	check(Alpha("nameplate1") == 1, "the targeted bar should be at full alpha")
	check(Alpha("nameplate1") > Alpha("nameplate2"),
		("the targeted bar is %.2f against %.2f on the other")
			:format(Alpha("nameplate1"), Alpha("nameplate2")))

	guids.target = guids.nameplate2
	Tick()
	check(Alpha("nameplate2") > Alpha("nameplate1"),
		"switching target should move the bright bar with it")

	guids.target = nil
	Tick()
	check(Alpha("nameplate1") == 1 and Alpha("nameplate2") == 1,
		"dropping target should bring every bar back to full")

	guids.target = guids.nameplate1
	Tick()
	print(("alpha  yours %.2f, theirs %.2f, and every bar %.2f with nothing targeted")
		:format(Alpha("nameplate1"), Alpha("nameplate2"), 1))

	_G.UnitIsUnit = realIsUnit
	guids.target = nil
end

--------------------------------------------------------------------------
-- A resolution change that lands in combat
--
-- The grid re-scales every frame on it, and the unit frame skin puts blocks on
-- it that are children of secure unit buttons. SetScale on a protected frame in
-- lockdown raises, and a monitor swapped or a window resized mid pull is how
-- that arrives. Refused frames wait for PLAYER_REGEN_ENABLED.
--------------------------------------------------------------------------

do
	local box = _G.WarriorKitSkinPlayer
	check(box ~= nil, "the skin's player block is not a named frame, so this cannot be tested")
	if box then
		local blocked, inCombat = {}, false
		local realLockdown, realProtected = _G.InCombatLockdown, Region.IsProtected
		_G.InCombatLockdown = function() return inCombat end
		function Region:IsProtected() return blocked[self] == true end

		local before = box:GetScale()
		blocked[box], inCombat = true, true
		SCREEN_H = 2160
		_G.GetPhysicalScreenSize = function() return 3840, SCREEN_H end
		fire("DISPLAY_SIZE_CHANGED")

		local wanted = 768 / SCREEN_H
		check(box:GetScale() == before,
			("a protected block was re-scaled in combat, %.4f"):format(box:GetScale()))
		check(math.abs(ns.UI.Scale() - wanted) < 1e-9,
			"the grid did not pick up the new screen height")
		check(math.abs(_G.WarriorKitEnemyBarsAnchor:GetScale() - wanted) < 1e-9,
			"an unprotected frame was deferred along with the protected one")

		inCombat = false
		fire("PLAYER_REGEN_ENABLED")
		check(math.abs(box:GetScale() - wanted) < 1e-9,
			("the block never caught up after combat, %.4f"):format(box:GetScale()))
		print(("lockdown a protected block held %.4f in combat and took %.4f after it")
			:format(before, box:GetScale()))

		_G.InCombatLockdown, Region.IsProtected = realLockdown, realProtected
		SCREEN_H = 1440
		_G.GetPhysicalScreenSize = function() return 3440, SCREEN_H end
		fire("DISPLAY_SIZE_CHANGED")
	end
end

--------------------------------------------------------------------------
-- Loadouts
--
-- The macro is the whole feature. Everything else in this part is a panel row
-- or an override binding, and what a key press actually sends is one string on
-- one attribute, so that string is what is asserted: the lines, their order,
-- the two rules that drop a line, the fight that defers the lot, and the
-- delete that has to move every binding under it onto a different button.
--
-- What this cannot prove: that the client runs two /equipslot lines off one
-- press, or what it does with a full bag when a two hander comes off. Nothing
-- installed on either client calls /equipslot, so those two answers are a key
-- press in game and nothing else.
--------------------------------------------------------------------------

local BATTLE, DEFENSIVE, BERSERKER = 1, 2, 3

local function LoadoutMacro(index)
	return _G[ns.Loadouts.ButtonName(index)]:GetAttribute("macrotext") or ""
end

local link = _G.WarriorKitItemLink

-- Three seeded, one per stance, and seeded once rather than on every login.
check(ns.Loadouts.Count() == 3,
	("the three stance loadouts were not seeded, %d rows"):format(ns.Loadouts.Count()))
check(ns.Loadouts.Get(DEFENSIVE).stance == 2, "the second seeded loadout is not Defensive Stance")

ns.Loadouts.SetItem(DEFENSIVE, ns.Gear.MAINHAND, link("Bloodspiller"))
ns.Loadouts.SetItem(DEFENSIVE, ns.Gear.OFFHAND, link("Aegis"))

-- Main hand before off hand, because going from a two hander to a one hander
-- and a shield the first line is what frees the hand the second one needs.
check(LoadoutMacro(DEFENSIVE) == table.concat({
	"/cast [nostance:2] " .. ns.Stance.Name(2),
	"/equipslot 16 Bloodspiller",
	"/equipslot 17 Aegis",
}, "\n"), "the defensive macro is not the three lines in order:\n" .. LoadoutMacro(DEFENSIVE))

-- A shield is not a main hand and a two hander is not an off hand. Both are
-- refused with a reason rather than saved and left to fail as a macro line.
check(ns.Loadouts.SetItem(BATTLE, ns.Gear.MAINHAND, link("Aegis")) == nil,
	"a shield was accepted into the main hand")
check(ns.Loadouts.SetItem(BATTLE, ns.Gear.OFFHAND, link("Arcanite Reaper")) == nil,
	"a two hander was accepted into the off hand")

-- A two hander in the main hand takes the off hand line out, whatever is saved
-- in that slot, because both hands are already spoken for.
ns.Loadouts.SetItem(BATTLE, ns.Gear.OFFHAND, link("Aegis"))
ns.Loadouts.SetItem(BATTLE, ns.Gear.MAINHAND, link("Arcanite Reaper"))
check(not LoadoutMacro(BATTLE):find("equipslot 17", 1, true),
	"a two hander left the off hand line in the macro:\n" .. LoadoutMacro(BATTLE))

-- The combat rule is a conditional on the equip lines and nothing else. The
-- stance still swaps mid fight; only the hands wait.
ns.dbc.loadoutSwapCombat = false
ns.Loadouts.Apply()
check(LoadoutMacro(DEFENSIVE) == table.concat({
	"/cast [nostance:2] " .. ns.Stance.Name(2),
	"/equipslot [nocombat] 16 Bloodspiller",
	"/equipslot [nocombat] 17 Aegis",
}, "\n"), "the combat rule did not reach both equip lines:\n" .. LoadoutMacro(DEFENSIVE))
ns.dbc.loadoutSwapCombat = true
ns.Loadouts.Apply()

-- A loadout with no stance is weapons and a key and nothing else, which is the
-- shape every custom one starts in.
local custom = ns.Loadouts.Add("Sword and board")
check(custom == 4, ("a fourth loadout did not land at 4, got %s"):format(tostring(custom)))
ns.Loadouts.SetItem(custom, ns.Gear.MAINHAND, link("Bloodspiller"))
check(LoadoutMacro(custom) == "/equipslot 16 Bloodspiller",
	"a loadout with no stance still cast one:\n" .. LoadoutMacro(custom))

-- One key cannot be two loadouts. The second claim is refused, and refused
-- without taking the key off the first, because two on one key is the mistake
-- the panel cannot show you afterwards.
check(ns.Loadouts.Bind(BATTLE, "SHIFT-1") ~= nil, "the client would not take SHIFT-1")
check(ns.Loadouts.Bind(DEFENSIVE, "SHIFT-1") == nil,
	"two loadouts were allowed to claim SHIFT-1")
check(ns.Loadouts.Describe(BATTLE) == "SHIFT-1",
	"a refused claim moved the key off the loadout that already held it")

-- Deleting a row shifts every row under it onto a different secure button, so
-- every binding is rebuilt from the list rather than only the one that moved.
-- Without that, SHIFT-2 would still be pointing at the macro Berserker used to
-- carry and would quietly do somebody else's job.
ns.Loadouts.Bind(custom, "SHIFT-2")
check(ns.Loadouts.Remove(BERSERKER), "the third loadout would not delete")
check(ns.Loadouts.Count() == 3, "the list is the wrong length after a delete")
check(ns.Loadouts.Get(3).name == "Sword and board", "the custom loadout did not shift down")
check(LoadoutMacro(3):find("Bloodspiller", 1, true) ~= nil,
	"the shifted loadout's macro did not follow it:\n" .. LoadoutMacro(3))
check(_G.GetBindingAction("SHIFT-2", true) == ("CLICK %s:LeftButton"):format(ns.Loadouts.ButtonName(3)),
	"a delete left a key bound to the button the deleted row was on")
check(LoadoutMacro(4) == "", "the button the list no longer reaches still carries a macro")

-- An attribute cannot be written under lockdown, so a loadout changed in a
-- fight is held and written when the fight ends. Both halves are asserted,
-- because a part that only did the first would silently lose the change.
do
	local realLockdown = _G.InCombatLockdown
	_G.InCombatLockdown = function() return true end
	ns.Loadouts.SetItem(DEFENSIVE, ns.Gear.MAINHAND, link("Arcanite Reaper"))
	check(not LoadoutMacro(DEFENSIVE):find("Arcanite", 1, true),
		"a secure macro was rewritten in combat")
	_G.InCombatLockdown = realLockdown
	fire("PLAYER_REGEN_ENABLED")
	check(LoadoutMacro(DEFENSIVE):find("Arcanite", 1, true) ~= nil,
		"the loadout changed in combat never landed after it:\n" .. LoadoutMacro(DEFENSIVE))
end

print(("loadout %d of %d rows, %d secure buttons, defensive sends %d characters")
	:format(ns.Loadouts.Count(), ns.Loadouts.MAX, ns.Loadouts.MAX, #LoadoutMacro(DEFENSIVE)))

--------------------------------------------------------------------------
-- What the addon costs
--
-- The measurement has to be free or it is not a measurement. Every churn figure
-- above was taken with the brackets live, because the clock is stubbed before
-- the addon loads, so those numbers already carry the instrumentation. This
-- section proves the rest: that the counters actually move, that switching
-- timing off stops them, and that the expensive half only runs while the tab
-- is on screen.
--------------------------------------------------------------------------

do
	ns.db.perf = true
	ns.Perf.Reset()
	check(ns.Perf.Ready(), "the harness clock is not reaching Perf")

	for _ = 1, 40 do
		barTicker.scripts.OnUpdate(barTicker, 0.05)
	end
	local average, peak, ticks = ns.Perf.Slot("bars")
	check(ticks == 10, ("the bars ticker ran 10 times and Perf counted %s"):format(tostring(ticks)))
	check(average and average > 0, "the bars ticker was timed at nothing")
	check(peak and peak >= average, "the worst tick is faster than the average one")

	-- Off has to mean off, not zero. A counter that keeps climbing with the
	-- setting off is a cost the setting claims to have removed.
	ns.db.perf = false
	ns.Perf.Reset()
	for _ = 1, 40 do
		barTicker.scripts.OnUpdate(barTicker, 0.05)
	end
	check(ns.Perf.Slot("bars") == nil, "timing kept accumulating with the setting off")
	ns.db.perf = true

	-- The memory walk runs on its own ticker and only while watched.
	check(not ns.Perf.Watching(), "the sampler was already running with no tab on screen")
	ns.Perf.Watch(true)
	check(ns.Perf.Watching(), "the sampler did not start")
	local held = ns.Perf.Memory()
	check(held > 0, "the sampler read no memory")
	ns.Perf.Watch(false)
	check(not ns.Perf.Watching(), "the sampler did not stop when the tab went away")

	-- And the gauge a part registered, which is what makes a millisecond figure
	-- readable: 0.31 ms means one thing at two bars and another at fifteen.
	local order, gauges = ns.Perf.Gauges()
	check(#order > 0, "no part registered a gauge, so the timings have no denominator")
	check(gauges[order[1]] ~= nil, "a gauge was ordered but never given a reader")

	print(("perf   bars %.3f ms per tick over %d ticks, %.0f KB held, %d gauge%s")
		:format(average or 0, ticks or 0, held, #order, #order == 1 and "" or "s"))
end

if failures > 0 then
	print(("harness: %d failed"):format(failures))
	os.exit(1)
end
print("harness: ok")
