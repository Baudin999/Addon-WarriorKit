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
--     lua5.1 scripts/harness.lua src HUNTER
--
-- The second argument is the class this run is. It defaults to WARRIOR, which
-- is every run this file has ever done. Two parts of the addon are warrior
-- only, and both decide it once at PLAYER_LOGIN: the charge button and the
-- world marker are not built at all on another class, and the action targeting
-- CVar is never written. A decision taken at login cannot be reached by
-- flipping the class afterwards, so the only way to test it is to come up as
-- something else, and check.sh does both runs.

local SCREEN_H = 1440 -- a height that is not 768, which is the whole point
local UI_SCALE = 0.65

-- Read here rather than beside ROOT below, because the UnitClass stub is
-- installed long before that line runs.
local PLAYER_CLASS = arg[2] or "WARRIOR"
local WARRIOR = PLAYER_CLASS == "WARRIOR"

-- The bars' steady state, in KB per fifty ticks with two bars up, covering the
-- plate path and the list path both.
--
-- A ratchet, not a ceiling. It was 51.76 before the list collector stopped
-- allocating and 4.10 after, so the gate went in at 5.0. Then it measured 0.17
-- and the gate came to 0.5, then 0.09 and the gate came to 0.25. It measures
-- 0.00 now and the gate is 0.05.
--
-- What took it to zero is named and is not a scene change this time. The tick
-- was rebuilding the party or raid on every pass to get the unit list its
-- threat comparison walks, which is a table write and a token concat per
-- member, five times a second, for an answer that changes when somebody joins.
-- ns.Unit.Roster already held that list and rebuilds it on GROUP_ROSTER_UPDATE,
-- so the walk is gone and what is left on the tick allocates nothing at all.
--
-- The gate is 0.05 rather than 0.00 because a gate of zero is a claim the
-- measurement can never move, and this one is a sampled figure.
local LIST_CHURN_KB = 0.05

-- The skin's tick, in KB per fifty ticks across all three unit frames. Same
-- kind of ratchet. It was 18.75 while the level tag was built and then compared
-- on every tick, which is a tostring and a concat per frame to say a number
-- that changes when the unit does, and 0.00 once the tags were interned. Set at
-- the smallest figure that is not a claim the measurement can never move.
local SKIN_CHURN_KB = 0.5

-- The meters' tick, in KB per fifty ticks, with a party of three, both panes up
-- and the clock running. Same kind of ratchet as the two above, measured on a
-- harder scene.
--
-- Those two are quoted with nothing moving, and a meter with nothing moving
-- allocates nothing at all: every write in Meter/Window.lua is guarded on a
-- number rather than on the string it would make, so a frozen meter measures
-- 0.00 here. A gate on that figure would be measuring the guards.
--
-- So the clock moves inside the loop. The seconds tick over, the rates fall
-- between them, and the strings that draw both have to be built. That is a
-- meter's real steady state and it cannot be zero. It measures 0.16 and the
-- gate is 0.20.
--
-- Which is not an argument that the guards are wasted. In a fight they save
-- very little, because the numbers move every tick and the string gets built
-- either way. What they buy is the other case entirely: a meter sitting on
-- screen between pulls, which is most of a session, costs nothing at all.
local METER_CHURN_KB = 0.2

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
		-- The slider and status bar fields, present on every region so the
		-- writes below never grow the table. A status bar's value is set on the
		-- enemy bars ticker and the churn gate measures that tick.
		value = 0, valueMin = nil, valueMax = nil, valueStep = nil,
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

-- The draw layer is data here, not a no-op, because the gauge is drawn as
-- three textures inside one of Blizzard's bars and which of them is on top is
-- decided by layer and sublevel alone. That ordering used to be decided by
-- frame level between two frames, the client did not keep the order this file
-- wrote, and the target's gauge came out at 28 percent of its own colour. A
-- stub that dropped the layer could not tell the fixed version from the broken
-- one.
function Region:CreateTexture(name, layer, _, sublevel)
	local texture = child("texture", self, name)
	texture.layer, texture.sublevel = layer or "ARTWORK", sublevel or 0
	return texture
end
function Region:SetDrawLayer(layer, sublevel)
	self.layer, self.sublevel = layer, sublevel or 0
end
function Region:GetDrawLayer() return self.layer, self.sublevel end
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
-- The mouse region, real rather than the metatable's no-op, because the skin
-- pulls it back off the strip of frame the client's aura row hangs in and a
-- stub that dropped the call would pass a target frame taking clicks in empty
-- space under the block.
function Region:SetHitRectInsets(l, r, t, b)
	self.insets = { l, r, t, b } -- a stub, and this runs on a relayout rather than a tick
end
function Region:GetHitRectInsets()
	local insets = self.insets
	if not insets then
		return 0, 0, 0, 0
	end
	return insets[1], insets[2], insets[3], insets[4]
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
		-- On ARTWORK, which is where every client builds a status bar's own
		-- fill and what the two textures the skin puts under it are measured
		-- against.
		self.fill = self.fill or region("texture", self)
		self.fill.layer, self.fill.sublevel = "ARTWORK", 0
		self.fill.texture = t
	end
end
function Region:GetStatusBarTexture() return self.fill end
-- Recorded rather than dropped. This was a no-op falling through to the
-- PascalCase catch-all, and GetStatusBarColor answered a constant white, which
-- between them meant nothing here could see a colour the skin painted. A bug
-- that drew every gauge at a third of its brightness passed this file.
function Region:SetStatusBarColor(r, g, b, a)
	self.barR, self.barG, self.barB, self.barA = r, g, b, a or 1
	self.barWrites = (self.barWrites or 0) + 1
end
function Region:GetStatusBarColor()
	if self.barR then
		return self.barR, self.barG, self.barB, self.barA
	end
	return 1, 1, 1, 1
end
function Region:SetSnapToPixelGrid(v) self.snapped = v end
function Region:SetTexelSnappingBias(v) self.bias = v end
function Region:SetFontObject(o) self.fontObject = o end

-- A font string given a font object answers that object's font, which is what
-- the client does and is the only way to read back a size the addon never set
-- directly. Every string in this addon takes a shared font object rather than
-- its own copy, on purpose, so without this fall-through nothing here could
-- assert what size anything is drawn at.
function Region:GetFont()
	if self.fontPath then
		return self.fontPath, self.fontSize, self.fontFlags
	end
	local object = self.fontObject
	if object then
		return object.fontPath, object.fontSize, object.fontFlags
	end
	return nil
end
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
function Region:ClearAllPoints() self.points, self.allPoints = nil, nil end
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

-- A slider that behaves like one.
--
-- Real, rather than the metatable's no-op, because two things in the addon are
-- built on the client's Slider type and both of them are the client tracking a
-- drag on the addon's behalf: the scrollbar in UI/Scroll.lua and the UI size row
-- in UI/Widgets.lua. A no-op here would let a slider that never reports a value,
-- never snaps to its step and never clamps to its range pass every assertion in
-- this file, which is the whole widget.
--
-- The step is applied on the way in, which is what SetObeyStepOnDrag buys on the
-- real client: the setting can only ever hold a value the panel can also show.
-- OnValueChanged fires on every write, including the addon's own, because that
-- is what the client does and it is exactly what the latches in both callers
-- exist to survive.
function Region:SetMinMaxValues(low, high)
	self.valueMin, self.valueMax = low, high
end
function Region:GetMinMaxValues() return self.valueMin, self.valueMax end
function Region:SetValueStep(step) self.valueStep = step end
function Region:GetValueStep() return self.valueStep end

function Region:SetValue(value)
	value = tonumber(value) or 0
	local low, high = self.valueMin, self.valueMax
	if low and self.valueStep and self.valueStep > 0 then
		value = low + math.floor((value - low) / self.valueStep + 0.5) * self.valueStep
	end
	if low and value < low then
		value = low
	end
	if high and value > high then
		value = high
	end
	self.value = value
	local handler = self.scripts.OnValueChanged
	if handler then
		handler(self, value)
	end
end

function Region:GetValue() return self.value end
-- Real, rather than the metatable's no-op, because the panel hides every
-- section but one and a stub that answers shown to all of them would let a
-- layout that puts seven pages on top of each other pass.
function Region:Show() self.shown = true end
function Region:Hide() self.shown = false end
function Region:RegisterEvent(e)
	events[e] = events[e] or {}
	events[e][#events[e] + 1] = self
end

-- The filtered form, which the skin uses for UNIT_AURA so a raid's worth of
-- other units never reaches its handler. Modelled as the plain registration it
-- is: the filter is the client's business and every fire() here names its unit
-- anyway, so what this proves is that the addon took the filtered path at all.
function Region:RegisterUnitEvent(e)
	self:RegisterEvent(e)
end

-- Real, rather than the metatable's no-op. Two parts turn an event off when
-- their setting goes off, and that the addon leaves the path entirely is the
-- assertion; a no-op here would pass a feature that only ever branches inside
-- a handler the client is still calling.
function Region:UnregisterEvent(e)
	local list = events[e]
	if not list then
		return
	end
	for index = #list, 1, -1 do
		if list[index] == self then
			table.remove(list, index)
		end
	end
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
-- Table driven rather than a plain equality, for the same reason the threat
-- reader below is: several files resolve UnitIsUnit into a file-scope local as
-- they load, so a test that swapped the global afterwards would swap nothing.
-- The alias table is empty in the shipped scene, where two tokens are the same
-- unit or they are not.
local unitAlias = {}
_G.UnitIsUnit = function(a, b)
	if a == b then
		return true
	end
	local aliases = unitAlias[a]
	return aliases ~= nil and aliases[b] == true
end
-- Class and name are per unit where a test has said so and the shipped answer
-- everywhere else. Every module that reads them localises the global at load,
-- so a test cannot swap the function afterwards; it writes to these tables
-- instead, which is why they are here rather than in the section that uses them.
local unitClass, unitName = {}, {}
_G.UnitClass = function(unit)
	local class = unitClass[unit]
	if class then
		return class, class
	end
	return PLAYER_CLASS:sub(1, 1) .. PLAYER_CLASS:sub(2):lower(), PLAYER_CLASS
end

-- Threat, with a hook for the same reason. Core/Core.lua resolves
-- UnitDetailedThreatSituation once at load and calls the local from then on, so
-- the meters' section installs a reader here rather than replacing the global,
-- which would do nothing at all.
local threatReader
_G.UnitDetailedThreatSituation = function(source, unit)
	if threatReader then
		return threatReader(source, unit)
	end
	return true, 3, 100, 0, 1200
end

_G.UnitIsDead, _G.UnitCanAttack = constant(false), constant(true)
_G.UnitName = function(unit) return unitName[unit] or "Target Dummy" end
_G.UnitHealth, _G.UnitHealthMax = constant(4200), constant(9000)
-- Heal prediction, which both clients register and both back with an event.
-- Written as a variable rather than a constant because the skin has to be
-- driven through three states to be worth testing: nothing on the way, a heal
-- that fits inside what is missing, and one that does not.
local incomingHeals = 0
_G.UnitGetIncomingHeals = function() return incomingHeals end
_G.UnitLevel, _G.UnitReaction = constant(62), constant(2)
-- True for exactly one unit, so the skin's player frame takes the class colour
-- through ClassTint and the other two fall to the reaction colour. Both halves
-- of Tint run, and the per class cache gets filled once and read after that.
local realPlayers = { player = true }
_G.UnitIsPlayer = function(unit) return realPlayers[unit] == true end
-- Who is swinging. Table driven because the meters open a segment on the first
-- damage anyone in the group does, and the whole point of that rule is the pull
-- somebody else made while you are still walking in.
local inCombat = {}
_G.UnitAffectingCombat = function(unit) return inCombat[unit] == true end
_G.UnitAura = constant(nil)
_G.UnitPowerType, _G.UnitPower, _G.UnitPowerMax = constant(1), constant(40), constant(100)
_G.UnitPlayerOrPetInParty, _G.UnitPlayerOrPetInRaid = constant(false), constant(false)
_G.UnitIsGroupLeader, _G.UnitIsGroupAssistant = constant(true), constant(false)
_G.GetNumGroupMembers, _G.IsInRaid = constant(0), constant(false)
_G.GetRaidTargetIndex, _G.SetRaidTarget = constant(nil), function() end
_G.SetRaidTargetIconTexture = function() end
-- The wall clock, which the tests move rather than wait out. It starts where
-- the old constant sat, so everything written against a fixed 100 still sees
-- one, and the loot throttle can be stepped past a tenth of a second at a time.
local wall = 100
local function advance(seconds)
	wall = wall + seconds
end
_G.GetTime = function() return wall end
_G.GetQuestGreenRange, _G.InCombatLockdown = constant(8), constant(false)
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
_G.tinsert, _G.date = table.insert, os.date
_G.GetBuildInfo = function() return "2.5.6", "69110", "2025-01-01", 20506 end
_G.RAID_CLASS_COLORS = {
	WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
	HUNTER = { r = 0.67, g = 0.83, b = 0.45 },
	PRIEST = { r = 1.00, g = 1.00, b = 1.00 },
}
-- Every id names a spell except the block above 900000, which names none. The
-- debuff list has a path for an id this client does not know and a stub that
-- answered every number would leave that path unreachable.
_G.GetSpellInfo = function(id)
	if type(id) == "number" and id >= 900000 then
		return nil
	end
	return "Spell" .. id, nil, "Interface\\Icons\\A" .. id
end
_G.GetSpellTexture = function(id) return "Interface\\Icons\\A" .. id end
_G.GetSpellCooldown = function() return 0, 0 end
_G.IsUsableSpell, _G.IsSpellInRange, _G.IsSpellKnown = constant(true), constant(1), constant(true)
_G.GetNumSpellTabs = constant(0)
-- Three items in the backpack and empty hands. Enough for the gear scan to
-- have something to offer, and chosen so all three rules it enforces are
-- reachable: a main hander, a shield, and a two hander that must keep the
-- off hand line out of a loadout's macro.
-- Every item carries its own id and the class the client files it under, both
-- of which the addon reads. The id matters more than it looks: the clutter
-- window asks the cursor which item it picked up and compares ids, so a stub
-- that gave every item the same one would make that check pass by accident.
-- Class 12 is a quest item and is the only class the clutter scan considers.
local ITEMS = {
	["Bloodspiller"]    = { id = 1001, classId = 2, equip = "INVTYPE_WEAPONMAINHAND", icon = "Interface\\Icons\\Sword", quality = 3, price = 4200 },
	["Aegis"]           = { id = 1002, classId = 4, equip = "INVTYPE_SHIELD", icon = "Interface\\Icons\\Shield", quality = 3, price = 3800 },
	["Arcanite Reaper"] = { id = 1003, classId = 2, equip = "INVTYPE_2HWEAPON", icon = "Interface\\Icons\\Axe", quality = 4, price = 9100 },
	-- What the second bag holds, which is what a vendor is for. Two greys a
	-- vendor pays for, one grey it will not, and a green. None of the four
	-- carries an equip location, so the gear scan still sees the three weapons
	-- in the first bag and nothing else.
	["Chipped Boar Tusk"] = { id = 2001, classId = 7, quality = 0, price = 47 },
	["Tattered Cloth"]    = { id = 2002, classId = 7, quality = 0, price = 12 },
	["Broken Twig"]       = { id = 2003, classId = 7, quality = 0, price = 0 },
	["Emerald Pigment"]   = { id = 2004, classId = 7, quality = 2, price = 1900 },
	-- The third bag, one item per branch the clutter verdict can take. Which of
	-- them is clutter and which is not is decided by the quest fixtures below,
	-- not here.
	["Hogger's Claw"]     = { id = 3001, classId = 12, quality = 1, price = 0 },
	["Diplomat's Ring"]   = { id = 3002, classId = 12, quality = 1, price = 0 },
	["Sealed Letter"]     = { id = 3003, classId = 12, quality = 1, price = 0 },
	["Zul'Mamwe Fetish"]  = { id = 3004, classId = 12, quality = 1, price = 0 },
	["Rogue's Token"]     = { id = 3005, classId = 12, quality = 1, price = 0 },
	["Old Cipher"]        = { id = 3006, classId = 12, quality = 1, price = 0 },
	["Unknown Trinket"]   = { id = 3007, classId = 12, quality = 1, price = 0 },
}

local BAG = { "Bloodspiller", "Aegis", "Arcanite Reaper" }
local JUNK = { "Chipped Boar Tusk", "Tattered Cloth", "Broken Twig", "Emerald Pigment" }
local QUESTBAG = {
	"Hogger's Claw", "Diplomat's Ring", "Sealed Letter", "Zul'Mamwe Fetish",
	"Rogue's Token", "Old Cipher", "Unknown Trinket",
}

-- Bag 0 is the gear the loadouts pick from, bag 1 is the trash, bag 2 is the
-- quest items. Kept apart so a sale never moves what the paperdoll tests are
-- counting and a destroy never moves what the vendor tests are counting.
local CARRIED = { [0] = BAG, [1] = JUNK, [2] = QUESTBAG }

local function reset(bag, ...)
	local held = { ... }
	for index = 1, #held do
		bag[index] = held[index]
	end
end

local function refill()
	reset(JUNK, "Chipped Boar Tusk", "Tattered Cloth", "Broken Twig", "Emerald Pigment")
end

local function refillQuests()
	reset(QUESTBAG, "Hogger's Claw", "Diplomat's Ring", "Sealed Letter",
		"Zul'Mamwe Fetish", "Rogue's Token", "Old Cipher", "Unknown Trinket")
end

-- A sold slot is left as false rather than removed, because the client does
-- not renumber a bag when something leaves it and neither may this.
local function carrying(bag, slot)
	local held = CARRIED[bag] and CARRIED[bag][slot]
	return held or nil
end

local function itemLink(name)
	return ("|cffff8000|Hitem:1::::::::60:::::|h[%s]|h|r"):format(name)
end
_G.WarriorKitItemLink = itemLink

_G.GetInventoryItemLink = constant(nil)
-- Quality is the third value and the sell price the eleventh, which is the
-- order ns.ItemValue reads them in. Answering nil for a name this stub does not
-- carry is the client's "not cached yet", and the vendor sweep has to treat
-- that as a reason to leave the item alone.
_G.GetItemInfo = function(link)
	local name = type(link) == "string" and link:match("%\[(.-)%\]")
	local item = name and ITEMS[name]
	if not item then
		return nil
	end
	return name, link, item.quality, 60, 60, nil, nil, 1, item.equip, item.icon, item.price
end
-- The fourth and fifth returns are the two ns.ItemInfo reads, the equip
-- location and the icon.
_G.GetItemInfoInstant = function(link)
	local name = type(link) == "string" and link:match("%\[(.-)%\]")
	local item = name and ITEMS[name]
	if not item then
		return nil
	end
	return item.id, name, nil, item.equip, item.icon, item.classId
end
_G.GetContainerNumSlots = function(bag) return CARRIED[bag] and #CARRIED[bag] or 0 end
_G.GetContainerItemLink = function(bag, slot)
	local held = carrying(bag, slot)
	return held and itemLink(held) or nil
end
-- Texture, count, locked, quality, in the order the loose global answers them.
-- Nothing is ever locked here: a locked slot is a sale the server has not
-- finished, and modelling that would be modelling latency rather than the
-- addon.
_G.GetContainerItemInfo = function(bag, slot)
	local held = carrying(bag, slot)
	if not held then
		return nil
	end
	return ITEMS[held].icon, 1, false, ITEMS[held].quality
end

-- The call the whole vendor part is built around, and the reason it checks the
-- merchant window before every sweep. With the window up the item is sold and
-- the money arrives. With it down the same call *uses* the item, which here
-- means it is gone and nothing was paid for it. A stub that sold either way
-- would pass the one bug in this part worth catching.
local purse = 0
local misused = 0
_G.UseContainerItem = function(bag, slot)
	local held = carrying(bag, slot)
	if not held then
		return
	end
	CARRIED[bag][slot] = false
	if _G.MerchantFrame:IsShown() then
		purse = purse + ITEMS[held].price
	else
		misused = misused + 1
	end
end

_G.GetMoney = function() return purse end
_G.GetCoinText = function(amount) return ("%dc"):format(amount) end
_G.MerchantFrame = region("frame")
_G.MerchantFrame:Hide()

-- The repair side of the same window. Modelled as a bill that has to be paid
-- by somebody: the two repair calls move money out of a named purse and only
-- then clear the damage, so a repair the addon reports as done and never paid
-- for fails here rather than in Ironforge.
--
-- GUILD.allowed is what CanGuildBankRepair answers, GUILD.limit is the rank's
-- withdraw ceiling with -1 meaning none, and GUILD.held is what is actually in
-- the bank. All three are separate because the addon has to get the order of
-- them right and a single "can the guild pay" flag would let it get it wrong.
local repairBill = 0
local repairsMerchant = true
local paidBy = nil
local GUILD = { allowed = false, limit = 0, held = 0, spent = 0 }

_G.CanMerchantRepair = function() return repairsMerchant end
_G.GetRepairAllCost = function() return repairBill end

_G.RepairAllItems = function(onGuild)
	if repairBill <= 0 then
		return
	end
	if onGuild then
		-- The client refuses rather than billing you personally, which is the
		-- behaviour the addon's fall-through exists for.
		if not GUILD.allowed then
			return
		end
		local ceiling = GUILD.limit == -1 and GUILD.held or GUILD.limit
		if ceiling < repairBill or GUILD.held < repairBill then
			return
		end
		GUILD.held = GUILD.held - repairBill
		GUILD.spent = GUILD.spent + repairBill
		paidBy = "guild"
	else
		if purse < repairBill then
			return
		end
		purse = purse - repairBill
		paidBy = "you"
	end
	repairBill = 0
end

_G.CanGuildBankRepair = function() return GUILD.allowed end
_G.GetGuildBankMoney = function() return GUILD.held end
_G.GetGuildBankWithdrawMoney = function() return GUILD.limit end

-- Eighteen slots, of which the ones that wear are given a pair. A ring answers
-- nothing, which is what the scan has to skip rather than count as a piece at
-- zero percent.
local DURABILITY = {
	[1] = { 40, 100 },
	[5] = { 95, 100 },
	[16] = { 12, 100 },
}
_G.GetInventoryItemDurability = function(slot)
	local pair = DURABILITY[slot]
	if not pair then
		return nil
	end
	return pair[1], pair[2]
end

-- A corpse, with a quality on each slot so a master loot threshold has
-- something to sort by: two under a threshold of 2 and two at or above it.
local CORPSE = { 0, 1, 3, 2 }
local looted = {}
local lootMethod = "group"

_G.GetNumLootItems = function() return #CORPSE end
_G.GetLootSlotInfo = function(slot)
	return "Interface\\Icons\\Coin", "Something", 1, nil, CORPSE[slot]
end
_G.LootSlot = function(slot) looted[slot] = true end
_G.GetLootThreshold = constant(2)
_G.GetLootMethod = function() return lootMethod end
-- No C_PartyInfo here on purpose, so Comfort/Loot.lua resolves through the
-- loose global and the fallback half of that probe is the half being tested.
_G.IsModifiedClick = constant(false)

--------------------------------------------------------------------------
-- Quests, Questie and the cursor
--
-- Everything the clutter window rests on. The quest fixtures are chosen so
-- there is exactly one item per branch the verdict can take, and the cursor is
-- modelled rather than stubbed away: the window picks an item up and asks the
-- client what it is really holding before destroying anything, and a stub that
-- always agreed would make that check pass without ever being tested.
--------------------------------------------------------------------------

local QUESTS = {
	[101] = { name = "Wanted: Hogger", completed = true },
	[102] = { name = "The Missing Diplomat", completed = false },
	[103] = { name = "A Rogue's Deal", completed = false },
	[104] = { name = "Ruins of Zul'Mamwe", completed = true },
}

-- What you are on right now. One quest, and the item that belongs to it must
-- never be offered.
local QUEST_LOG = { 102 }

-- Questie's item rows, one per branch:
--   3001 one completed quest                       clutter, certain
--   3002 a quest in your log                       kept
--   3003 starts a quest you have not done          kept, and this is the one
--        that matters most
--   3004 two completed quests                      clutter, certain
--   3005 a quest neither taken nor completed       clutter, uncertain
--   3006 starts a quest you have completed         clutter, certain
--   3007 absent from the database entirely         kept
local QUESTIE_ITEMS = {
	[3001] = { relatedQuests = { 101 } },
	[3002] = { relatedQuests = { 102 } },
	[3003] = { startQuest = 103 },
	[3004] = { relatedQuests = { 104, 101 } },
	[3005] = { relatedQuests = { 103 } },
	[3006] = { startQuest = 101 },
}

local questieModules = {
	QuestieDB = {
		QueryItemSingle = function(itemId, field)
			local row = QUESTIE_ITEMS[itemId]
			return row and row[field] or nil
		end,
		QueryQuestSingle = function(questId, field)
			local row = QUESTS[questId]
			return row and row[field] or nil
		end,
	},
}

-- ImportModule hands back a fresh empty table for a module it has never heard
-- of rather than nil, which is why "the module came back" proves nothing and
-- why Clutter.lua checks for the query functions instead. The stub does the
-- same thing, so that trap is reachable from a test.
_G.QuestieLoader = {
	ImportModule = function(_, name)
		questieModules[name] = questieModules[name] or {}
		return questieModules[name]
	end,
}

_G.GetNumQuestLogEntries = function() return #QUEST_LOG end
_G.GetQuestLogTitle = function(index)
	local questId = QUEST_LOG[index]
	if not questId then
		return nil
	end
	-- The quest id is the eighth value, which is where Questie reads it from.
	return QUESTS[questId].name, 60, nil, false, false, false, nil, questId
end
_G.IsQuestFlaggedCompleted = function(questId)
	local quest = QUESTS[questId]
	return quest ~= nil and quest.completed or false
end

local cursor
local destroyed = {}

_G.GetCursorInfo = function()
	if not cursor then
		return nil
	end
	return "item", cursor.id, cursor.link
end

_G.ClearCursor = function() cursor = nil end

-- Counted, because the window has two independent guards against destroying
-- the wrong item and the counter is the only way to tell which one fired. The
-- slot re-read happens before the cursor is touched at all, so a stale card
-- that still reaches a pickup means that first guard is gone even though the
-- second one caught it.
local pickups = 0

_G.PickupContainerItem = function(bag, slot)
	pickups = pickups + 1
	local held = carrying(bag, slot)
	if not held then
		cursor = nil
		return
	end
	cursor = { id = ITEMS[held].id, link = itemLink(held), bag = bag, slot = slot }
end

-- The end of the line, and the only call in the addon with no way back. It
-- takes whatever the cursor is holding, which is exactly why the window checks
-- what that is first.
_G.DeleteCursorItem = function()
	if not cursor then
		return
	end
	destroyed[#destroyed + 1] = cursor.link
	CARRIED[cursor.bag][cursor.slot] = false
	cursor = nil
end
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
-- The combat log, the talent trees and the inspect handshake
--
-- Everything the meters are built on. All four are read through a local the
-- module took at load, so all four are declared here, before the addon runs,
-- and a test moves the data under them rather than replacing the function.
--
-- The log is modelled as the sixteen values the client hands over, because the
-- addon reads five of them out of fixed positions and the positions are the
-- whole contract: a stub that answered a named table would let a parser that
-- reads the wrong slot pass.
--------------------------------------------------------------------------

local logArgs = {}
_G.CombatLogGetCurrentEventInfo = function()
	return unpack(logArgs, 1, 16)
end

-- Three trees per character, points and an icon each. Two shapes, because
-- GetTalentTabInfo has two signatures across these clients: one leads with a
-- numeric tab id and one leads with the tree's name, and the addon tells them
-- apart on the type of the first value. Both are reachable from a test.
local talentShape = "modern"
local talentTrees = {
	player = {
		{ name = "Arms", icon = "Interface\\Icons\\Ability_Warrior_SavageBlow", points = 31 },
		{ name = "Fury", icon = "Interface\\Icons\\Ability_Warrior_InnerRage", points = 20 },
		{ name = "Protection", icon = "Interface\\Icons\\Ability_Warrior_DefensiveStance", points = 0 },
	},
	inspect = {
		{ name = "Beast Mastery", icon = "Interface\\Icons\\Ability_Hunter_BeastTaming", points = 11 },
		{ name = "Marksmanship", icon = "Interface\\Icons\\Ability_Marksmanship", points = 40 },
		{ name = "Survival", icon = "Interface\\Icons\\Ability_Hunter_SwiftStrike", points = 0 },
	},
}

_G.GetNumTalentTabs = function() return 3 end
_G.GetTalentTabInfo = function(index, inspect)
	local trees = inspect and talentTrees.inspect or talentTrees.player
	local tree = trees[index]
	if not tree then
		return nil
	end
	if talentShape == "old" then
		return tree.name, tree.icon, tree.points
	end
	return index, tree.name, "", tree.icon, tree.points, tree.name
end

local inspecting
_G.NotifyInspect = function(unit) inspecting = unit end
_G.ClearInspectPlayer = function() inspecting = nil end
_G.CheckInteractDistance = constant(true)
_G.UnitIsConnected = constant(true)

-- The sheet every class icon is cut out of. Only the three classes the meters'
-- section puts in a group, because a coordinate this file invented for a class
-- nothing draws would be a fixture proving nothing.
_G.CLASS_ICON_TCOORDS = {
	WARRIOR = { 0, 0.25, 0, 0.25 },
	HUNTER = { 0, 0.25, 0.25, 0.5 },
	PRIEST = { 0.5, 0.75, 0, 0.25 },
}

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
-- The combat feedback number, which is a font string and so is invisible to a
-- walk over textures. Blizzard draws it centred on a portrait twice the size
-- of the block, so left alone it lands across the level and the power gauge.
child("fontstring", playerFrame, "PlayerHitIndicator")
local targetFrame = unitFrame("TargetFrame", 232, 100, nil,
	{ "TargetFrameRaidTargetIcon", "TargetFramePVPIcon" })
child("fontstring", targetFrame, "TargetLevelText")
child("fontstring", targetFrame, "TargetFrameHitIndicator")
local totFrame = unitFrame("TargetFrameToT", 120, 50, targetFrame, {})
-- Anchored the way the client anchors it: against a target frame 100 units
-- tall. That offset is the whole reason the skin has to place this frame
-- itself once the target frame is the height of the block instead.
totFrame:SetPoint("TOPLEFT", targetFrame, "TOPLEFT", -35, -70)

-- The head of each of the target's two aura rows, anchored the way the client
-- anchors them: to the frame's bottom left corner, lifted by the height of the
-- art that hangs under the bars on a frame 100 units tall. Everything after
-- the head hangs off the head, so these two are the whole of the row's
-- position, and the lift is the number the skin has to measure and cannot
-- read, because the client keeps it in a local.
--
-- Standing them up unanchored first and anchoring them below, the way the
-- client does: the buttons exist from the moment the frame does and are
-- re-anchored on every aura the target gains or loses.
local AURA_LIFT = 32
local auraHeads = {}
for _, name in ipairs({ "TargetFrameBuff1", "TargetFrameDebuff1" }) do
	auraHeads[#auraHeads + 1] = child("button", targetFrame, name)
end

local function anchorAuras()
	for _, head in ipairs(auraHeads) do
		head:ClearAllPoints()
		head:SetPoint("TOPLEFT", targetFrame, "BOTTOMLEFT", 5, AURA_LIFT)
	end
end

-- What each unit frame was built as, taken before PLAYER_LOGIN and so before
-- the skin has fitted any of them. The fit is only reversible if these are the
-- numbers that come back.
local BUILT = {}
for _, frame in ipairs({ playerFrame, targetFrame, totFrame }) do
	BUILT[frame.name] = { frame:GetWidth(), frame:GetHeight(),
		frame.points and frame.points[1] }
end

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

--------------------------------------------------------------------------
-- The shared unit layer
--
-- ns.Unit, on its own. Two things it promises are not visible in a screenshot
-- and are what everything above it is built on.
--
-- The first is that a colour is a reference. Every ticker in the addon guards
-- its widget writes by comparing what it is about to draw against what it drew
-- last, and for a colour that comparison is table identity, so the same state
-- has to answer the same table every time. A version of this layer that built
-- its answers would look right on screen and would write the gauge, the track,
-- the edge and the threat line five times a second forever.
--
-- The second is who a walk covers. The threat comparison asks who is closest to
-- taking a mob off you, so it has to skip you: counting the player makes every
-- mob you are holding look like it is about to be lost.
--------------------------------------------------------------------------

do
	local Unit = ns.Unit
	local Color, Level, Threat = Unit.Color, Unit.Level, Unit.Threat

	-- A colour is the same table twice, or the guards above it are dead.
	check(Color.Class("WARRIOR") == Color.Class("WARRIOR"),
		"the class colour is a fresh table on every call")
	check(Color.ClassHex("WARRIOR"):match("^ff%x%x%x%x%x%x$") ~= nil,
		("the class escape is %q, expected ffRRGGBB"):format(Color.ClassHex("WARRIOR")))
	check(Color.Class("NOTACLASS") == nil,
		"a class the client will not colour came back with a colour anyway")
	check(Color.ClassHex(nil) == "ffffffff",
		"a nameless class did not fall back to white")

	-- A green that answers two questions is the same green, which is the whole
	-- reason the palette is one table and not two.
	check(Color.threat.safe == Color.reaction.friendly,
		"safe and friendly are two different greens again")
	check(Color.threat.off == Color.reaction.hostile,
		"off you and hostile are two different reds again")

	-- The stub's mobs are reaction 2, which is hostile, and the player is a
	-- warrior. Identity rather than value, for the reason above.
	check(Color.Reaction("nameplate1") == Color.reaction.hostile,
		"a reaction 2 mob is not coloured hostile")
	check(Color.Aggro("nameplate1") == Color.aggro.comes,
		"a hostile mob is not marked as one that comes for you")
	-- Whatever class this run came up as, since check.sh does two.
	local playerClass = select(2, _G.UnitClass("player"))
	check(Color.OfUnit("player") == Color.Class(playerClass),
		("the player's own frame is not wearing the %s colour"):format(tostring(playerClass)))
	check(Color.OfUnit("nameplate1") == Color.reaction.hostile,
		"a mob with no class did not fall back to its reaction")

	-- Dimming writes into one scratch table rather than allocating.
	local dim = Color.Dim(Color.reaction.hostile, 0.5)
	check(dim == Color.Dim(Color.reaction.friendly, 0.5),
		"dimming allocates a table instead of reusing its scratch")
	check(math.abs(dim[1] - Color.reaction.friendly[1] * 0.5) < 1e-9,
		"the scratch does not carry the colour it was last handed")

	-- Everything in the stub is level 62, player included, so every mob is an
	-- even fight and none of them is an elite.
	local tag, worth = Level.Of("nameplate1")
	check(tag == "62", ("the level tag is %q, expected \"62\""):format(tag))
	check(worth == Color.xp.even,
		"a mob at your own level is not on the even colour")

	check(Unit.TargetToken("raid17") == "raid17target",
		("the target token is %q, expected \"raid17target\""):format(Unit.TargetToken("raid17")))

	-- 4200 of 9000, floored to the integer that gets drawn rather than kept as
	-- the ratio, because the integer is what the guards compare.
	local health, maxHealth, percent = Unit.Health("nameplate1")
	check(health == 4200 and maxHealth == 9000 and percent == 46,
		("health reads %d of %d at %d%%, expected 4200 of 9000 at 46%%")
			:format(health, maxHealth, percent))

	-- Nobody but you in the group, so there is nobody to lose a mob to. A walk
	-- that counted the player would answer 100 here and every bar you were
	-- holding would draw as about to be lost.
	check(ns.Unit.Roster.Size() < 2, "the harness starts in a group of more than one")
	check(Threat.Top("nameplate1") == nil,
		"the threat walk counted the player as their own challenger")

	-- The vanilla road. That client has no threat API at all and the colour
	-- comes from who the mob is actually swinging at, which is the honest half
	-- of the question it can answer. Called directly, because the API is
	-- resolved into a local at load and cannot be taken away afterwards.
	local shade, victim, mine = Threat.Swinging("nameplate1")
	check(shade == Color.threat.idle and victim == nil and mine == false,
		"a mob swinging at nobody is not drawn idle")

	guids["nameplate1target"] = "Player-0-00000042"
	shade, victim, mine = Threat.Swinging("nameplate1")
	check(shade == Color.threat.off and victim == "nameplate1target" and mine == false,
		"a mob on somebody else is not drawn as off you")

	unitAlias["nameplate1target"] = { player = true }
	shade, victim, mine = Threat.Swinging("nameplate1")
	check(shade == Color.threat.safe and mine == true,
		"a mob swinging at you is not drawn as yours")
	unitAlias["nameplate1target"] = nil
	guids["nameplate1target"] = nil

	print("unit   palette shared, colours by reference, threat walk skips you, vanilla fallback")
end

--------------------------------------------------------------------------
-- The layout engine
--
-- ns.UI.Flow, on its own, before anything that is built out of it. Every
-- number below is a rectangle the engine worked out, read back off the offsets
-- it wrote, because that is the whole of what it promises: hand it a tree and
-- every frame in it lands where the tree says.
--
-- Worth gating separately from the widgets. A layout bug inside the enemy bars
-- shows up as one failing assertion about a debuff square and takes an hour to
-- trace back to the arithmetic; the same bug here names itself.
--------------------------------------------------------------------------

do
	local function Cell()
		return region("frame", _G.UIParent)
	end

	local root = Cell()
	ns.UI.Adopt(root)
	local px = ns.UI.Pixel(root)
	local Flow = ns.UI.Flow

	-- Where a frame ended up, in root units, from the offset Flow wrote on it.
	local function At(frame)
		local _, _, _, x, y = frame:GetPoint()
		return (x or 0) / px, -(y or 0) / px
	end

	local function near(got, want, what)
		check(math.abs(got - want) < 1e-9,
			("flow: %s is %.2f, expected %.2f"):format(what, got, want))
	end

	-- A column, stretched across, which is the shape of every stacked readout
	-- in the addon.
	do
		local a, b, c = Cell(), Cell(), Cell()
		Flow.Arrange(root, {
			direction = "column", gap = 2 * px, align = "stretch", width = 100 * px,
			{ frame = a, height = 10 * px },
			{ frame = b, height = 20 * px },
			{ frame = c, height = 5 * px },
		})
		near(root:GetHeight() / px, 39, "the column's height")
		near(select(2, At(a)), 0, "the first row's top")
		near(a:GetWidth() / px, 100, "a stretched row's width")
		near(select(2, At(b)), 12, "the second row's top")
		near(select(2, At(c)), 34, "the third row's top")
	end

	-- One child growing into what the others left, which is how a label takes
	-- the room beside a fixed control.
	do
		local a, b = Cell(), Cell()
		Flow.Arrange(root, {
			direction = "row", gap = 4 * px, width = 100 * px, height = 20 * px,
			{ frame = a, width = 10 * px, grow = 1 },
			{ frame = b, width = 30 * px },
		})
		near(a:GetWidth() / px, 66, "the growing child took the slack")
		near(At(b), 70, "the fixed child sits after it")
	end

	-- Packed to the far end, and run backwards, which is what mirroring a
	-- layout is and nothing else.
	do
		local a, b = Cell(), Cell()
		Flow.Arrange(root, {
			direction = "row", gap = 4 * px, width = 100 * px, height = 20 * px,
			justify = "end",
			{ frame = a, width = 10 * px },
			{ frame = b, width = 20 * px },
		})
		near(At(a), 66, "justify end: the first child")
		near(At(b), 80, "justify end: the last child ends flush")

		local c, d = Cell(), Cell()
		Flow.Arrange(root, {
			direction = "row", gap = 4 * px, width = 100 * px, height = 20 * px,
			reverse = true,
			{ frame = c, width = 10 * px },
			{ frame = d, width = 20 * px },
		})
		near(At(d), 0, "reversed: the last child leads")
		near(At(c), 24, "reversed: the first child follows")
	end

	-- Centred across the axis its container runs along.
	do
		local a = Cell()
		Flow.Arrange(root, {
			direction = "row", width = 100 * px, height = 20 * px,
			{ frame = a, width = 10 * px, height = 6 * px, align = "center" },
		})
		near(select(2, At(a)), 7, "a centred child's top")
	end

	-- The wrapping row, right aligned, growing upwards, which is the debuff row
	-- on an enemy bar. Five 20 wide squares with a 4 gap in a 70 wide row: three
	-- fit on the line nearest the gauge and two wrap above it.
	do
		local squares = {}
		local icons = { direction = "row", wrap = true, justify = "end",
			lineOrder = "up", gap = 4 * px, width = 70 * px, alignY = "end" }
		for index = 1, 5 do
			squares[index] = Cell()
			icons[index] = { frame = squares[index], width = 20 * px, height = 20 * px }
		end

		local lines = Flow.Lines(icons)
		check(#lines == 2, ("flow: the row broke into %d lines, expected 2"):format(#lines))
		near(lines[1].main / px, 68, "the first line's width")

		-- The line nearest the gauge is full and the tail hangs above it, so a
		-- text node beside it is sized against the first line and not the row.
		local text = Cell()
		Flow.Arrange(root, {
			direction = "stack", width = 70 * px,
			{ frame = text, width = 70 * px - lines[1].main, height = 20 * px,
				alignX = "start", alignY = "end" },
			icons,
		})
		near(root:GetHeight() / px, 44, "the stack is as tall as its tallest child")
		near(select(2, At(text)), 24, "the text sits on the line nearest the gauge")
		near(select(2, At(squares[1])), 24, "and so does the first square")
		near(At(squares[1]), 2, "the full line is packed right")
		near(At(squares[3]) + 20, 70, "the last square on it ends flush")
		near(select(2, At(squares[4])), 0, "the wrapped line is above")
		near(At(squares[4]) + 20 + 4 + 20, 70, "and is packed right too")
	end

	-- A node that is not drawn takes no room, which is what every setting that
	-- hides one row of a widget relies on.
	do
		local a, b, c = Cell(), Cell(), Cell()
		Flow.Arrange(root, {
			direction = "column", gap = 2 * px, width = 50 * px,
			{ frame = a, height = 10 * px },
			{ frame = b, height = 20 * px, skip = true },
			{ frame = c, height = 10 * px },
		})
		near(root:GetHeight() / px, 22, "the height ignores the skipped node")
		near(select(2, At(c)), 12, "the row after it moved up")
	end

	print("flow   column, row, grow, justify, reverse, align, wrap up, stack, skip")
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

-- The gauge fills the inside of the box, which is the box less one hairline on
-- each edge. Asserted because it was briefly one pixel tall: the gauge carries
-- no height of its own and takes whatever the box has left, and a layout node
-- that is not told to grow measures zero and gets zero.
do
	local px = ns.UI.Pixel(widget)
	check(math.abs(widget.health:GetHeight() - (widget.box:GetHeight() - 2 * px)) < 1e-9,
		("the gauge is %.0f px tall inside a %.0f px box, expected %.0f")
			:format(widget.health:GetHeight(), widget.box:GetHeight(),
				widget.box:GetHeight() - 2 * px))
	check(math.abs(widget.health:GetWidth() - (widget.box:GetWidth() - 2 * px)) < 1e-9,
		("the gauge is %.0f px wide inside a %.0f px box, expected %.0f")
			:format(widget.health:GetWidth(), widget.box:GetWidth(),
				widget.box:GetWidth() - 2 * px))
end

-- The edges are one pixel, which was the whole complaint.
check(widget.box.edges[1].height == ns.UI.Pixel(widget),
	("hairline is %.4f units, expected %.4f"):format(widget.box.edges[1].height, ns.UI.Pixel(widget)))

-- The icon crop lands on texel boundaries and the client's snapping is off.
local art = widget.icons[1].texture
check(art.texcoord and math.abs(art.texcoord[1] * 64 - 5) < 1e-9,
	"icon crop is not on a texel boundary")
check(art.snapped == false and art.bias == 0, "icon texture is still being snapped")

--------------------------------------------------------------------------
-- The debuff row
--
-- Which debuffs it shows and how big they are are both settings, so what is
-- asserted here is the shape the settings have to keep producing: the row is
-- as long as the list, it ends flush with the right end of the gauge however
-- long that is, and when it no longer fits it wraps upwards rather than hanging
-- icons off the left edge of the bar.
--
-- Offsets rather than resolved rectangles. This stub records what a frame was
-- anchored to and does no layout, which is the honest thing to assert against:
-- the offset is the addon's half of the contract and the arithmetic on it is
-- the client's.
--
-- Measured against the gauge rather than read off one anchor pair. Every square
-- used to hang off the gauge's own top right corner and this asserted that pair
-- by name; ns.UI.Flow pins everything in a widget to the widget's top left
-- instead, so which pair it used is the layout engine's business and the only
-- thing worth asserting is where the square lands. That is what this measures,
-- and it covers the gauge's own placement too, which naming the anchor did not.
--------------------------------------------------------------------------

-- The offset a frame was pinned at, checked to be pinned the way Flow pins
-- everything inside a widget.
local function Corner(frame, bar, what)
	local point, relative, relativePoint, x, y = frame:GetPoint()
	check(point == "TOPLEFT" and relative == bar and relativePoint == "TOPLEFT",
		("%s is anchored %s to %s, not TOPLEFT to the widget's TOPLEFT")
			:format(what, tostring(point), tostring(relativePoint)))
	return x or 0, y or 0
end

-- Where every square sits relative to the right end of the gauge, grouped by
-- the line it is on. Returns the lines, the one nearest the gauge first, each
-- one a list of the offsets of the squares' left edges.
local function IconRows(bar)
	local rows, order = {}, {}
	local boxX = Corner(bar.box, bar, "the gauge")
	local edge = boxX + bar.box:GetWidth()
	for index = 1, #ns.EnemyBars.Spells() do
		local holder = bar.icons[index]
		local x, y = Corner(holder, bar, ("debuff %d"):format(index))
		check(holder:IsShown(), ("debuff %d is on the list and hidden"):format(index))
		if not rows[y] then
			rows[y] = {}
			order[#order + 1] = y
		end
		local row = rows[y]
		row[#row + 1] = x - edge
	end
	for index = #ns.EnemyBars.Spells() + 1, #bar.icons do
		check(not bar.icons[index]:IsShown(),
			("debuff slot %d is off the list and still shown"):format(index))
	end
	table.sort(order)
	local out = {}
	for _, y in ipairs(order) do
		out[#out + 1] = rows[y]
	end
	return out
end

-- The whole of the alignment contract: the last square in every row ends on the
-- gauge's right edge, and the squares in a row are one gap apart.
local function CheckPacked(what)
	local bar = ns.EnemyBars.WidgetFor("nameplate1")
	local px = ns.UI.Pixel(bar)
	local size, gap = ns.db.barsIconSize * px, 4 * px
	local rows = IconRows(bar)
	for index, row in ipairs(rows) do
		table.sort(row)
		local right = row[#row] + size
		check(math.abs(right) < 1e-9,
			("%s: row %d ends %.0f px from the gauge's right edge, not on it"):format(what, index, right))
		for column = 2, #row do
			check(math.abs(row[column] - row[column - 1] - (size + gap)) < 1e-9,
				("%s: row %d has a %.0f px step between squares, expected %.0f")
					:format(what, index, row[column] - row[column - 1], size + gap))
		end
	end
	-- The gauge, the strip the icon rows take, and the line above the lot.
	local wanted = (21 + 2) + #rows * (size + gap) + 15 * px
	check(math.abs(bar:GetHeight() - wanted) < 1e-9,
		("%s: the bar is %.0f px tall over %d icon row(s), expected %.0f")
			:format(what, bar:GetHeight(), #rows, wanted))
	return rows
end

check(#ns.EnemyBars.Spells() == 4, "the bar does not ship tracking four debuffs")
CheckPacked("as it ships")

-- One more, and the row is one longer and still ends where it did.
check((ns.EnemyBars.AddSpell(12162)), "Deep Wounds would not go on the list")
check(#ns.EnemyBars.Spells() == 5, "adding a debuff did not lengthen the list")
local packed = CheckPacked("with a fifth")
check(#packed == 1 and #packed[1] == 5,
	("five 20 px squares on a 180 px bar should be one row of five, got %d row(s)"):format(#packed))

-- The same id twice would be two squares lighting up together, and an id this
-- client cannot name would be a blank square.
check(not (ns.EnemyBars.AddSpell(12162)), "the same debuff went on the list twice")
check(not (ns.EnemyBars.AddSpell(900001)), "an id this client cannot name went on the list")
check(not (ns.EnemyBars.AddSpell("rend")), "a word went on the list as a spell id")
check(#ns.EnemyBars.Spells() == 5, "a refused add changed the list anyway")

-- Off again, and the row is back where it started.
check((ns.EnemyBars.RemoveSpell(12162)), "Deep Wounds would not come off the list")
check(#ns.EnemyBars.Spells() == 4, "removing a debuff did not shorten the list")
CheckPacked("after a remove")

-- The size reaches the squares, and a longer list on a wider square wraps
-- upwards rather than running off the left end of the bar.
ns.db.barsIconSize = 32
ns.EnemyBars.ApplyLayout()
ns.EnemyBars.Rebuild()
check(ns.EnemyBars.WidgetFor("nameplate1").icons[1]:GetWidth()
		== 32 * ns.UI.Pixel(ns.EnemyBars.WidgetFor("nameplate1")),
	"bars icon 32 did not reach the squares")
CheckPacked("at 32 px")

for _, spellID in ipairs({ 1715, 12323, 355, 694, 1161, 676 }) do
	check((ns.EnemyBars.AddSpell(spellID)), ("%d would not go on the list"):format(spellID))
end
check(#ns.EnemyBars.Spells() == 10, "the list did not reach ten")
check(not (ns.EnemyBars.AddSpell(5246)), "an eleventh debuff went on a list capped at ten")
local wrapped = CheckPacked("ten at 32 px on a 180 px bar")
-- 180 holds five 32 px squares with 4 px between them, so ten is two rows.
check(#wrapped == 2 and #wrapped[1] == 5 and #wrapped[2] == 5,
	("ten squares should wrap to two rows of five, got %d row(s)"):format(#wrapped))

-- Emptying the list leaves the threat line its own height and nothing else.
for index = #ns.EnemyBars.Spells(), 1, -1 do
	ns.EnemyBars.RemoveSpell(ns.EnemyBars.Spells()[index])
end
check(#ns.EnemyBars.Spells() == 0, "the list would not empty")
do
	local bare = ns.EnemyBars.WidgetFor("nameplate1")
	local px, unit = ns.UI.Pixel(bare), ns.UI.Unit(bare)
	-- Built from the design rather than from one number, so the zoom and the
	-- outline floor both reach it. The gauge is 21 with a hairline each side,
	-- the strip above it is the threat line's own height, and 15 is the room the
	-- name over the plate takes. The strip is the floor rather than the bar's
	-- text size because that line sits over the world and cannot go flat, which
	-- is the whole reason it is 14 and not 12.
	local strip = math.max(12, ns.UI.OutlineFloor())
	local wanted = 21 * unit + 2 * px + (4 + strip + 15) * unit
	check(math.abs(bare:GetHeight() - wanted) < 1e-9,
		("with nothing tracked the bar is %.0f px tall, expected %.0f"):format(bare:GetHeight(), wanted))
	check(not bare.icons[1]:IsShown(), "an empty list still shows a square")
end

-- Back to the shipped scene, because the churn figure below is quoted against
-- four debuffs at twenty pixels and a ratchet measured on another list is a
-- ratchet measuring something else.
ns.db.barsIconSize = 20
ns.EnemyBars.ResetSpells()
check(#ns.EnemyBars.Spells() == 4, "the reset did not put the four back")
CheckPacked("after a reset")
widget = ns.EnemyBars.WidgetFor("nameplate1")

--------------------------------------------------------------------------
-- bars zoom actually scales the bar
--
-- It did not, for the whole life of the setting. Every design number in
-- LayoutWidget was multiplied by ns.Pixel(widget), which on the grid is 1/zoom,
-- and the scale the zoom put on the frame multiplied it straight back. The bar
-- measured 180 by 62 screen pixels at zoom 1, 2 and 3 alike, fonts included.
--
-- Nothing caught it because every assertion in this file was written in the
-- widget's own units, and in those units the bar really does change: it is half
-- as many units at 2x on twice the scale, which is the same picture. The only
-- way to see it is to convert to screen pixels and compare against what the
-- design asked for, which is what this does.
--
-- The hairline is deliberately not scaled. An edge is one screen pixel at every
-- zoom, the rule UI/Window.lua already follows for every rule in the options
-- window, so the box is the gauge plus two pixels rather than the gauge times
-- the zoom.
--------------------------------------------------------------------------

do
	local shipped = ns.db.barsZoom
	local function screen(frame, units)
		return units / ns.UI.Pixel(frame)
	end
	local function at(zoom)
		ns.db.barsZoom = zoom
		ns.EnemyBars.ApplyLayout()
		ns.EnemyBars.Rebuild()
	end

	local widthAtOne
	for _, zoom in ipairs{1, 2, 3} do
		at(zoom)

		local wide = screen(widget, widget:GetWidth())
		local gauge = screen(widget, widget.box:GetHeight())
		local icon = screen(widget, widget.icons[1]:GetWidth())
		local hair = screen(widget, widget.box.edges[1].height)
		if zoom == 1 then
			widthAtOne = wide
		end

		check(math.abs(wide - ns.db.barsWidth * zoom) < 1e-6,
			("at %dx the bar is %.1f screen pixels wide, the design asked for %d")
				:format(zoom, wide, ns.db.barsWidth * zoom))
		check(math.abs(gauge - (21 * zoom + 2)) < 1e-6,
			("at %dx the gauge box is %.1f screen pixels, expected %d")
				:format(zoom, gauge, 21 * zoom + 2))
		check(math.abs(icon - ns.db.barsIconSize * zoom) < 1e-6,
			("at %dx a debuff square is %.1f screen pixels, the design asked for %d")
				:format(zoom, icon, ns.db.barsIconSize * zoom))
		check(math.abs(hair - 1) < 1e-6,
			("at %dx the hairline is %.2f screen pixels, not one"):format(zoom, hair))

		for _, measure in ipairs{wide, gauge, icon} do
			check(math.abs(measure - math.floor(measure + 0.5)) < 1e-6,
				("at %dx something came out %.3f screen pixels"):format(zoom, measure))
		end

		-- The assertion the old code would have failed, stated on its own so the
		-- failure reads as "the zoom does nothing" rather than as a size being
		-- off by a bit.
		if zoom == 3 then
			check(math.abs(wide - widthAtOne) > 1e-6,
				("the bar is %.1f screen pixels wide at both 1x and 3x, so the zoom does nothing")
					:format(wide))
		end
	end

	at(3)
	print(("zoom   bar %.0f px wide at 1x and %.0f at 3x, icon %.0f px, hairline stays 1 px")
		:format(widthAtOne, screen(widget, widget:GetWidth()),
			screen(widget, widget.icons[1]:GetWidth())))
	at(shipped)
end

-- Rebuilt several times by the section above, so the reference the checks below
-- use is taken again rather than assumed to have survived.
widget = ns.EnemyBars.WidgetFor("nameplate1")
check(widget ~= nil, "no bar on nameplate1 after the zoom sweep")

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

-- The palette, restated rather than reached for. Skin.lua keeps these local and
-- that is right; a gate that imported the number it is checking would pass on
-- the day somebody changed it by accident. UnitIsPlayer above is true for the
-- player alone, so the player wears their own class colour and the other two
-- fall to the hostile one on a reaction of 2.
--
-- Two class colours, because this file runs twice and comes up as a different
-- class the second time. Both are the stub's own figures written out again, so
-- the check is still that the skin carried the client's colour through rather
-- than that two tables agree with each other.
local TRACK, EDGE_DIM = 0.20, 0.60
local CLASS_TINT = {
	WARRIOR = { 0.78, 0.61, 0.43 },
	HUNTER = { 0.67, 0.83, 0.45 },
}
local TINT = {
	player = CLASS_TINT[PLAYER_CLASS],
	target = { 0.88, 0.25, 0.28 },
	tot = { 0.88, 0.25, 0.28 },
}
assert(TINT.player, PLAYER_CLASS .. " has no colour in the stub's palette")

-- The two textures the skin draws inside each of Blizzard's bars, found the
-- way everything else here is found: by what they are, not by reaching into
-- the module's tables. The track fills its bar, so it is the one with
-- SetAllPoints on it; the slice is pinned to the fill texture instead, which
-- is what makes it start exactly where the bar stops.
local function barTexture(bar, filling)
	for _, region in ipairs(bar.regions) do
		if region.kind == "texture" and (region.allPoints ~= nil) == filling then
			return region
		end
	end
end

local function skinTrack(bar) return barTexture(bar, true) end
local function skinSlice(bar) return barTexture(bar, false) end

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

		-- The fit, which is the whole of what makes Edit Mode's rectangle the
		-- one on the screen. The block sits on the frame's own corner, the
		-- portrait's square sits on the block, and the frame covers exactly
		-- the piece of screen the block does.
		--
		-- The last is the one with teeth, and it is asserted in screen space
		-- rather than in either frame's units because that is the only space
		-- the two share: the block is on the pixel grid and the unit frame is
		-- on the client's scale, so a fit that never converted would pass a
		-- comparison of the raw numbers and be out by the ratio between them.
		-- A fit dropped altogether leaves the frame at the 232 by 100 the stub
		-- built and fails by a mile.
		local corner = key == "target" and "TOPRIGHT" or "TOPLEFT"
		local anchor = box.points and box.points[1]
		check(anchor and anchor[2] == frame and anchor[1] == corner
			and anchor[3] == corner and anchor[4] == 0 and anchor[5] == 0,
			key .. ": the block is not pinned to the frame's own " .. corner)

		-- The square is the one frame the block parents nothing to and pins
		-- nothing over: the two rails are children of the box and the text
		-- frame covers the whole of it.
		local slot
		for _, f in ipairs(frame.children) do
			if not f.allPoints and f.points and f.points[1] and f.points[1][2] == box then
				slot = f
			end
		end
		check(slot ~= nil, key .. ": the portrait's square is not hung on the block")
		local square = slot and slot.points[1]
		check(square and square[1] == corner and square[3] == corner
			and square[4] == 0 and square[5] == 0,
			key .. ": the square is not on the block's " .. corner)
		check(slot and slot:GetWidth() == slot:GetHeight() and slot:GetHeight() == box:GetHeight(),
			key .. ": the portrait's square is not the block's height squared")

		for _, axis in ipairs({ { "width", "GetWidth" }, { "height", "GetHeight" } }) do
			local ours = box[axis[2]](box) * box:GetEffectiveScale()
			local theirs = frame[axis[2]](frame) * frame:GetEffectiveScale()
			check(math.abs(ours - theirs) < 1e-6,
				("%s: the block is %.2f of screen %s and the frame Edit Mode drags is %.2f")
					:format(key, ours, axis[1], theirs))
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

		-- Stacking order, and the whole reason it is asserted this way.
		--
		-- The spent track used to be a texture on the rail, one frame under
		-- Blizzard's bar, and this file checked the two levels. Both clients
		-- took the writes and one of them did not keep them: the target frame
		-- came out with its rails level with its bars, the tie went to
		-- whichever was built later, which is ours, and the track drew over
		-- the fill at nine tenths alpha. A target at full health read at 28
		-- percent of its own colour. The player frame, one line of the same
		-- code away, was correct, and every level this file compared was the
		-- number the addon had asked for rather than the one on the screen.
		--
		-- So the order is no longer between two frames. The track and the heal
		-- slice are regions of Blizzard's own bar and sit under its fill by
		-- draw layer, which is settled inside one frame and cannot be a
		-- disagreement. What is asserted is that: same frame, and the layers
		-- in the order track, slice, fill.
		local LAYERS = { BACKGROUND = 1, BORDER = 2, ARTWORK = 3, OVERLAY = 4 }
		local function depth(texture)
			if not texture or not LAYERS[texture.layer] then
				return nil
			end
			return LAYERS[texture.layer] * 16 + (texture.sublevel or 0)
		end
		for name, bar in pairs({ health = frame.healthbar, power = frame.manabar }) do
			local track = skinTrack(bar)
			check(track ~= nil and track.parent == bar,
				("%s: the spent part of the %s gauge is not a region of the bar it"
					.. " belongs to, so what draws on top is two frame levels arguing")
					:format(key, name))
			local under, over = depth(track), depth(bar.fill)
			check(under and over and under < over,
				("%s: the %s track is on %s and the fill on %s, so the track draws"
					.. " over the fill"):format(key, name, tostring(track and track.layer),
						tostring(bar.fill and bar.fill.layer)))
		end
		local slice = skinSlice(frame.healthbar)
		check(slice and slice.parent == frame.healthbar,
			key .. ": the heal slice is not a region of the health bar")
		check(depth(skinTrack(frame.healthbar)) < depth(slice)
			and depth(slice) < depth(frame.healthbar.fill),
			key .. ": the heal slice is not between the spent track and the fill")

		-- What the block is actually painted. The fill is the unit's colour at
		-- full brightness, the spent part of each gauge is that colour at a
		-- fifth, and the five hairlines are it at three fifths. All three are
		-- read back, because a gauge is only as good as the colour that reaches
		-- it and every one of these numbers used to be invisible here.
		local tint = TINT[key]
		local function near(a, b) return a and math.abs(a - b) < 1e-6 end
		local function paints(region, r, g, b, a)
			return region and near(region.r, r) and near(region.g, g)
				and near(region.b, b) and near(region.a, a)
		end
		check(paints(frame.healthbar, tint[1], tint[2], tint[3], 1)
			or (near(frame.healthbar.barR, tint[1]) and near(frame.healthbar.barG, tint[2])
				and near(frame.healthbar.barB, tint[3]) and near(frame.healthbar.barA, 1)),
			("%s: the health bar is painted %s,%s,%s and not the unit's %.2f,%.2f,%.2f")
				:format(key, tostring(frame.healthbar.barR), tostring(frame.healthbar.barG),
					tostring(frame.healthbar.barB), tint[1], tint[2], tint[3]))
		check(paints(skinTrack(frame.healthbar), tint[1] * TRACK, tint[2] * TRACK,
			tint[3] * TRACK, 0.9), key .. ": the spent part of the health gauge is not "
				.. "the unit's colour at a fifth")
		local dimmed = 0
		for _, region in ipairs(box.regions) do
			if paints(region, tint[1] * EDGE_DIM, tint[2] * EDGE_DIM, tint[3] * EDGE_DIM, 1) then
				dimmed = dimmed + 1
			end
		end
		check(dimmed == 5, ("%s: %d of the block's five hairlines carry the unit's "
			.. "colour at three fifths, not all of them"):format(key, dimmed))

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

--------------------------------------------------------------------------
-- How big a debuff square can be before the client blends two copies
--
-- The file used to say 16 and 32 were the sharp sizes. Nobody could have caught
-- that by reading, because the two things that make it false are in different
-- files: UI/Draw.lua crops five texels off each edge of the art, leaving 54 of
-- 64, and EnemyBars.lua insets the art one pixel inside the square's border, so
-- the drawn size is two less than the number in the panel. 54 halves to 27, so
-- the only setting in the range that puts one stored texel on one pixel is 29,
-- and the stepper stepped by two and could not reach it.
--
-- Checked against the arithmetic rather than against a list, so a change to the
-- crop moves the answer here as well as in the panel.
--------------------------------------------------------------------------

do
	local low, high = ns.EnemyBars.IconRange()
	local texels = ns.UI.IconTexels()
	check(texels == 54, ("the crop leaves %s texels, not 54"):format(tostring(texels)))

	-- Once per zoom, because the drawn size is the setting times the zoom less
	-- the border, so which setting is exact moves when the zoom does. At 1x it is
	-- 29 drawing 27 off the half size copy. At 2x it is 28 drawing 54 off the
	-- full size copy, which is the sharpest a spell icon can be drawn.
	local sharpAt = {}
	for _, zoom in ipairs{1, 2, 3} do
		local exact = {}
		for size = low, high do
			local drawn, isExact = ns.EnemyBars.IconAdvice(size, zoom)
			check(drawn == size * zoom - 2,
				("at %dx a %d square draws %d pixels of art, not %d")
					:format(zoom, size, drawn, size * zoom - 2))

			-- The truth, worked out here from the texel count rather than taken
			-- from the function under test.
			--
			-- Non-negative steps only. A whole number of halvings down from 54
			-- texels is a stored copy landing one texel to a pixel. A whole
			-- number the other way is the client stretching 54 texels over 108
			-- pixels, which is clean magnification and is not the same claim, so
			-- it does not count as exact and the panel must not offer it as one.
			local steps = math.log(texels / drawn) / math.log(2)
			local shouldBeExact = steps > -1e-9
				and math.abs(steps - math.floor(steps + 0.5)) < 1e-9
			check(isExact == shouldBeExact,
				("at %dx, %d draws %d pixels from %d texels, %.3f copies down, and IconAdvice says %s")
					:format(zoom, size, drawn, texels, steps, isExact and "exact" or "blended"))

			if isExact then
				exact[#exact + 1] = size
			end
		end
		sharpAt[zoom] = exact
	end

	local function listed(zoom)
		return table.concat(sharpAt[zoom], ", ")
	end

	-- Two at 1x now that the ceiling reaches the second one: 29 draws 27 off the
	-- half size copy, 56 draws the full 54 and is the sharpest a spell icon gets.
	-- At 2x the zoom has already doubled the square, so 28 is the same 54 pixels
	-- and nothing else in the range lands.
	check(listed(1) == "29, 56", ("1x is sharp at %s, expected 29, 56"):format(listed(1)))
	check(listed(2) == "28", ("2x is sharp at %s, expected 28"):format(listed(2)))
	check(ns.EnemyBars.IconAdvice(56, 1) == 54,
		"56 at 1x does not draw the full 54 texel copy one for one")
	check(ns.EnemyBars.IconAdvice(28, 2) == 54,
		"28 at 2x does not draw the full 54 texel copy one for one")

	-- The advice points at the nearer of the two, not simply the largest.
	local _, _, near20 = ns.EnemyBars.IconAdvice(20, 1)
	local _, _, near50 = ns.EnemyBars.IconAdvice(50, 1)
	check(near20 == 29, ("at 20 the panel points at %s, not 29"):format(tostring(near20)))
	check(near50 == 56, ("at 50 the panel points at %s, not 56"):format(tostring(near50)))

	check(ns.EnemyBars.DescribeIcon(20, 1):find("29", 1, true) ~= nil,
		"the note at 20 does not name the size that is sharp: " .. ns.EnemyBars.DescribeIcon(20, 1))
	check(ns.EnemyBars.DescribeIcon(29, 1):find("one stored texel per pixel", 1, true) ~= nil,
		"the note at 29 does not say it is exact: " .. ns.EnemyBars.DescribeIcon(29, 1))

	local advertised = sharpAt[1][1]

	-- The sharp size is odd, and half of an odd icon is where the threat line
	-- used to land. Laid out at it here so the anchor check at the end of this
	-- file sees the odd case as well as the even one it gets from the default.
	local shipped = ns.db.barsIconSize
	ns.db.barsIconSize = advertised
	ns.EnemyBars.ApplyLayout()
	ns.EnemyBars.Rebuild()
	local _, _, _, _, threatY = widget.threatText:GetPoint()
	check(math.abs(threatY - math.floor(threatY + 0.5)) < 1e-6,
		("an odd icon put the threat line at %.3f pixels"):format(threatY))

	-- Every number on a debuff square, at every size the square can be set to.
	--
	-- An outline is a rim drawn round the glyph, so it costs the same number of
	-- pixels whatever the glyph is, and below about fourteen it has eaten the
	-- counters: the hole in a 6, the waist of an 8. The bars drew these outlined
	-- at seven to twelve pixels, which is where a stack count stops being a
	-- digit. Read back off the font object rather than off the constant, because
	-- the size a string ends up at is the smaller of the design size and a
	-- fraction of the icon, and it is the second one that produced the bad
	-- values.
	local floor = ns.UI.OutlineFloor()
	local outlined, flat = 0, 0
	for size = low, high do
		ns.db.barsIconSize = size
		ns.EnemyBars.ApplyLayout()
		ns.EnemyBars.Rebuild()
		local holder = widget.icons[1]
		for _, part in ipairs{ { "timer", holder.timer }, { "count", holder.count } } do
			local _, drawnAt, flags = part[2]:GetFont()
			check(drawnAt ~= nil,
				("the %s on a %d square reports no font"):format(part[1], size))
			if drawnAt then
				check(drawnAt >= floor or flags == "",
					("at icon %d the %s is %d pixels and still outlined, under the %d floor")
						:format(size, part[1], drawnAt, floor))
				if flags == "" then
					flat = flat + 1
				else
					outlined = outlined + 1
				end
			end
		end
	end
	-- Every one of them comes out flat, and that is the honest result rather than
	-- a branch that never ran. Both numbers are capped by a design constant
	-- below the floor, the timer by the bar's own text size and the count by
	-- COUNT_TEXT_SIZE, so no icon setting can lift either to fourteen. Worth
	-- knowing rather than hiding: it means a 56 pixel square still carries a 12
	-- pixel timer, which is legible but small for the room it has.
	check(outlined == 0,
		("%d numbers on a debuff square are outlined, and the caps should make that impossible")
			:format(outlined))

	-- So the branch itself is checked where it lives, rather than through a call
	-- site that can only ever reach one side of it.
	local _, small, smallFlags = ns.UI.NumberFont(floor - 1):GetFont()
	local _, big, bigFlags = ns.UI.NumberFont(floor):GetFont()
	check(small == floor - 1 and smallFlags == "",
		("NumberFont at %d came back %s with flags %q"):format(floor - 1,
			tostring(small), tostring(smallFlags)))
	check(big == floor and bigFlags == "OUTLINE",
		("NumberFont at %d came back %s with flags %q"):format(floor,
			tostring(big), tostring(bigFlags)))

	-- And the other side of the same rule, across every string the bar draws.
	--
	-- An outline is not optional over the world: with nothing behind the glyph,
	-- flat is not softer, it is gone. So outlined text has to be at or above the
	-- floor, because there is no degradation to fall back on. Text over an opaque
	-- fill may be either, and which one is a contrast judgement the layout is
	-- allowed to make.
	--
	-- The two that sit in the gap above the gauge were 12 and outlined, which is
	-- the one combination that is wrong both ways at once: too small to carry a
	-- rim and unable to drop it. The three over the fill are the same size and
	-- are not listed here, because an opaque backing makes the outline a choice.
	local OVER_THE_WORLD = {
		{ "threat line", function(w) return w.threatText end },
		{ "targeted by", function(w) return w.targetedBy end },
	}
	for _, entry in ipairs(OVER_THE_WORLD) do
		local _, drawnAt, flags = entry[2](widget):GetFont()
		check(flags ~= "", ("the %s went flat, and it has no background to be flat over")
			:format(entry[1]))
		check(drawnAt and drawnAt >= floor,
			("the %s is %s pixels over the world, under the %d floor, and cannot drop its outline")
				:format(entry[1], tostring(drawnAt), floor))
	end

	print(("fonts  %d numbers on a square, all flat; %d strings over the world, all outlined at %d px or more")
		:format(flat, #OVER_THE_WORLD, floor))

	print(("icons  %d texels sampled, range %d to %d; sharp at %s square at 1x, %s at 2x")
		:format(texels, low, high, listed(1), listed(2)))

	ns.db.barsIconSize = shipped
	ns.EnemyBars.ApplyLayout()
	ns.EnemyBars.Rebuild()
end

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
-- The incoming heal on the health gauge
--
-- Three states, because the arithmetic is only worth testing at its edges:
-- nothing on the way draws nothing, a heal that fits inside what is missing
-- draws its own share of the gauge, and a heal that does not fit draws what is
-- missing and not one pixel further.
--
-- The rail is measured off the block that landed rather than off the setting
-- that asked for it, which is the same rule the rest of this section works
-- under: a test written against skinWidth would be asserting the request and
-- not the answer.
--------------------------------------------------------------------------

local healSlice = skinSlice(_G.PlayerFrame.healthbar)
check(healSlice ~= nil, "the skin drew no incoming heal slice on the health bar")

local sliceAnchor = healSlice and healSlice.points and healSlice.points[1]
check(sliceAnchor ~= nil and sliceAnchor[2] == _G.PlayerFrame.healthbar.fill,
	"the heal slice is not pinned to the health bar's own fill texture, so it starts"
	.. " wherever the two scales happen to agree rather than where the bar stops")

-- A whole refresh interval per call, because the ticker only does the work
-- every fifth of a second and a heal set between two of those is a heal the
-- frame has not been told about yet.
local function healTick(amount)
	incomingHeals = amount
	skinTicker.scripts.OnUpdate(skinTicker, 0.25)
	if not healSlice.shown then
		return 0
	end
	-- Back into pixels, because the slice is a region of Blizzard's health bar
	-- and its width is written in that bar's units. That is the boundary this
	-- part is built on and the reason the number is asserted here at all: the
	-- span is worked out in whole pixels of the gauge and multiplied by one
	-- pixel in the bar's units on the way out, so dividing by the same figure
	-- is what the client will have drawn.
	return healSlice:GetWidth() / ns.UI.Pixel(_G.PlayerFrame.healthbar)
end

-- The gauge is the block less the portrait's square and the one pixel it is
-- inset by on its outer edge. Whole pixels, because the player block is on the
-- grid and that was asserted above.
local railPixels = playerBox:GetWidth() - playerBox:GetHeight() - 1
local MISSING = 9000 - 4200

check(healTick(0) == 0, "a unit with no heal on the way still draws a slice")

local fits = math.floor(1800 / 9000 * railPixels + 0.5)
local drawn = healTick(1800)
check(math.abs(drawn - fits) < 1e-9,
	("a 1800 heal on a 9000 unit drew %.2f px of a %d px gauge, expected %d")
		:format(drawn, railPixels, fits))
check(math.abs(drawn - math.floor(drawn + 0.5)) < 1e-9,
	"the heal slice is a fraction of a pixel wide")

local capped = math.floor(MISSING / 9000 * railPixels + 0.5)
local over = healTick(999999)
check(math.abs(over - capped) < 1e-9,
	("a heal far past what the unit is missing drew %.2f px, expected the %d px it is down")
		:format(over, capped))
check(capped < railPixels,
	"the clamp let an overheal cover the whole gauge, which says the unit is at full")

check(healTick(0) == 0, "the slice stayed up after the heal it predicted landed")

print(("heals  gauge %d px, 1800 of 9000 draws %d px, an overheal clamps to %d px")
	:format(railPixels, fits, capped))

--------------------------------------------------------------------------
-- The aura row
--
-- The client hangs the target's buffs and debuffs off the frame's bottom left
-- corner, lifted by the height of the art that used to hang under the bars.
-- Fitting the frame to the block took that art away and the same lift then put
-- the row inside the gauge, which is where a screenshot found it.
--
-- The row is not moved by the addon and this asserts that it is not. Every
-- icon in it is a child of a secure unit button, so it can only be anchored
-- out of combat, and the client re-anchors the head of each row on every aura
-- the target gains or loses: a row placed by the addon would be back inside
-- the gauge on the first refresh of the first fight. What the addon moves is
-- the edge the client measures from, which it may do whenever it is allowed
-- to and which then holds for the rest of the session.
--
-- So the three numbers here are the whole contract. The heads keep the anchor
-- the client wrote, the frame is the block plus that lift, and the mouse
-- region is pulled back off the strip so the block is still all you can click.
--------------------------------------------------------------------------

local targetBox = _G.WarriorKitSkinTarget

local function screenHeight(frame)
	return frame:GetHeight() * frame:GetEffectiveScale()
end

-- Before any aura exists there is nothing to measure and the frame is the
-- block exactly, which is what the fit assertions above have already checked.
check(math.abs(screenHeight(targetFrame) - screenHeight(targetBox)) < 1e-6,
	"the target frame carries a tail before the client has placed a single aura")

anchorAuras()
fire("UNIT_AURA", "target")

local lift = AURA_LIFT * targetFrame:GetEffectiveScale()
check(math.abs(screenHeight(targetFrame) - (screenHeight(targetBox) + lift)) < 1e-6,
	("the target frame is %.2f of screen and the block plus the client's %d unit"
		.. " lift is %.2f, so the aura row does not land under the block")
		:format(screenHeight(targetFrame), AURA_LIFT, screenHeight(targetBox) + lift))

for _, head in ipairs(auraHeads) do
	local point = head.points and head.points[1]
	check(point ~= nil and point[2] == targetFrame and point[5] == AURA_LIFT,
		head.name .. " was re-anchored by the addon, which is a write the client"
		.. " undoes on the next aura and combat refuses outright")
end

local _, _, _, bottom = targetFrame:GetHitRectInsets()
check(math.abs((bottom or 0) - AURA_LIFT) < 1e-6,
	("the target frame takes clicks %s units below the block, where the aura row"
		.. " hangs and there is nothing to click"):format(tostring(bottom)))

local _, _, _, playerBottom = playerFrame:GetHitRectInsets()
check((playerBottom or 0) == 0,
	"the player frame had its mouse region inset, and it has no aura row to make"
	.. " room for")

print(("auras  the client lifts the row %d units, the target frame is the block"
	.. " plus that and takes no clicks in it"):format(AURA_LIFT))

--------------------------------------------------------------------------
-- The fit, off and back on
--
-- The skin resizes three frames it does not own and re-anchors one of them,
-- and that is the change in this part that has to be reversible without a
-- reload: everything else it does to a unit frame is a texture hidden or a
-- region moved, and the frame's own rectangle is what Edit Mode saves against.
--
-- Turned off, every frame is the size the stub built and target of target is
-- back on the anchor the stub wrote. Turned back on, all three fit again,
-- which is what catches a restore that handed back the fitted size as though
-- it were the original.
--------------------------------------------------------------------------

local function screenSize(frame)
	return frame:GetWidth() * frame:GetEffectiveScale(),
		frame:GetHeight() * frame:GetEffectiveScale()
end

-- Under the target's block and not under the target's frame. Those two have
-- the same bottom edge on every frame but this one, where the frame carries
-- the strip the client's aura row hangs in, and hanging target of target off
-- the frame would leave a row of icons' worth of gap above it.
local perch = totFrame.points and totFrame.points[1]
check(perch ~= nil and perch[2] == _G.WarriorKitSkinTarget and perch[1] == "TOPRIGHT"
	and perch[3] == "BOTTOMRIGHT" and perch[5] < 0,
	"target of target is not parked under the target block, so it is still"
	.. " anchored against a target frame that is no longer that size")

local fitted = {}
for _, block in ipairs(blocks) do
	fitted[block[1]] = { screenSize(block[3]) }
end

ns.db.skin = false
ns.FrameSkin.Apply()

for _, block in ipairs(blocks) do
	local key, frame = block[1], block[3]
	local built = BUILT[frame.name]
	check(frame:GetWidth() == built[1] and frame:GetHeight() == built[2],
		("%s: the skin came off and left the frame %.0fx%.0f, not the %.0fx%.0f it found")
			:format(key, frame:GetWidth(), frame:GetHeight(), built[1], built[2]))
end

-- And the mouse region with it. A frame handed back its size while still
-- refusing clicks along its bottom edge is a frame the user cannot use and
-- cannot see why.
local _, _, _, offInset = targetFrame:GetHitRectInsets()
check((offInset or 0) == 0,
	("the skin came off and left the target frame refusing clicks %s units above"
		.. " its own bottom edge"):format(tostring(offInset)))

local back = totFrame.points and totFrame.points[1]
local was = BUILT[totFrame.name][3]
check(back ~= nil and back[1] == was[1] and back[2] == was[2] and back[3] == was[3]
	and back[4] == was[4] and back[5] == was[5],
	"target of target did not get its own anchor back when the skin came off")

ns.db.skin = true
ns.FrameSkin.Apply()

-- The combat feedback number, which is the one Blizzard piece on these frames
-- that a walk over textures cannot reach. It is a font string, it is drawn at
-- Blizzard's size and centred on a portrait that no longer exists at that size,
-- and left alone it lands across the level and the power gauge. Asserted on
-- both frames, and asserted through Show, because Blizzard's own combat handler
-- calls Show on it at every hit and a plain Hide would last until the next one.
for _, name in ipairs({ "PlayerHitIndicator", "TargetFrameHitIndicator" }) do
	local text = _G[name]
	check(text ~= nil, ("the harness has no %s to hide"):format(name))
	text:Show()
	check(not text:IsShown(),
		("%s came back the moment the client showed it, so the damage number"
			.. " still lands across the level"):format(name))
end

for _, block in ipairs(blocks) do
	local key, frame = block[1], block[3]
	local wide, tall = screenSize(frame)
	check(math.abs(wide - fitted[key][1]) < 1e-6 and math.abs(tall - fitted[key][2]) < 1e-6,
		("%s: the second fit came out %.2f x %.2f of screen, the first %.2f x %.2f")
			:format(key, wide, tall, fitted[key][1], fitted[key][2]))
end

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
-- The UI size slider
--
-- The one control in the addon that resizes the thing you are looking at while
-- you hold it, which is also the one that can put a window off the bottom of the
-- screen if the clamp in Window:Resize is ever lost. So it is driven here the
-- way a player drives it: through the client's own Slider, at every stop, with
-- the geometry measured after each one.
--
-- Three questions, and none of them is answerable by reading the source.
--
-- Does the window survive the top of the range. At 3x the panel wants 452 units
-- of a screen that has 480 of them left after the zoom, so the clamp has to fire
-- and the result still has to be a whole number of units and still has to fit.
--
-- Do the design metrics stay whole. Zoom multiplies the scale, not the numbers,
-- so every row must still be an integer count of units at 1.25x. A row that came
-- back fractional would mean the size had leaked into the layout, which is the
-- bug this arithmetic exists to avoid.
--
-- Does the addon tell the truth about the cost. A quarter stop puts a hairline
-- on a fraction of a pixel and the panel says so; a whole stop does not and the
-- panel says that instead. Both sentences are read off UI.Exact, so asserting on
-- them is asserting the panel cannot claim a grid it does not have.
--------------------------------------------------------------------------

if window then
	ns.Options.Show()

	local Settings = ns.Settings
	local screen = ns.UI.ScreenZoom()

	check(ns.db.uiSize == 1, ("the size starts at %s, not 1"):format(tostring(ns.db.uiSize)))
	check(window.zoom == screen,
		("the panel opened at zoom %s on a screen that asks for %d")
			:format(tostring(window.zoom), screen))

	-- The row the player actually drags, found the way the panel finds anything:
	-- through the parts recorded on the window. Nothing reaches into the feature
	-- for it.
	-- Named, not "the last slider on any page". The debuff icon row is a slider
	-- now too, and picking whichever came last would silently test the wrong
	-- control the next time a part gains one.
	local size
	for _, part in ipairs(window.parts) do
		if part.name == "Settings" then
			for _, widget in ipairs(part.kit.widgets) do
				if widget.slider then
					size = widget.slider
				end
			end
		end
	end
	check(size ~= nil, "no UI size slider was built, so the client refused the Slider type")

	local sliders = 0
	for _, part in ipairs(window.parts) do
		for _, widget in ipairs(part.kit.widgets) do
			if widget.slider then
				sliders = sliders + 1
			end
		end
	end
	check(sliders == 2, ("%d sliders in the panel, expected the UI size and the debuff icon")
		:format(sliders))

	if size then
		local low, high = size:GetMinMaxValues()
		check(low == Settings.LOW and high == Settings.HIGH,
			("the slider runs %s to %s, the setting runs %s to %s")
				:format(tostring(low), tostring(high),
					tostring(Settings.LOW), tostring(Settings.HIGH)))
		check(size:GetValueStep() == Settings.STEP,
			("the slider steps by %s, the setting steps by %s")
				:format(tostring(size:GetValueStep()), tostring(Settings.STEP)))

		local stops, widest, tallest = 0, 0, 0
		local stop = Settings.LOW
		while stop <= Settings.HIGH + 1e-6 do
			stops = stops + 1
			size:SetValue(stop)

			local where = Settings.Label(stop)
			check(ns.db.uiSize == stop,
				("%s on the slider saved %s"):format(where, tostring(ns.db.uiSize)))
			check(window.zoom == screen * stop,
				("%s left the window at zoom %s, not %s")
					:format(where, tostring(window.zoom), tostring(screen * stop)))
			check(whole(window.width) and whole(window.height),
				("%s left the window %.2f x %.2f, not a whole number of units")
					:format(where, window.width, window.height))
			check(window.height * window.zoom <= SCREEN_H,
				("%s put %.0f pixels of window on a %d pixel screen")
					:format(where, window.height * window.zoom, SCREEN_H))

			-- The zoom multiplies the scale and must not reach the layout, so
			-- every row on the section showing is still whole units.
			local part = window.parts[1]
			for _, cell in ipairs(part.sections[part.current or 1].stack.cells) do
				check(whole(cell.height),
					("%s made a row %.3f units tall"):format(where, cell.height))
			end

			local said = Settings.Describe()
			if ns.UI.Exact(screen * stop) then
				check(said:find("exact", 1, true) ~= nil,
					("%s is on the grid and the panel does not say so: %s"):format(where, said))
			else
				check(said:find("soft", 1, true) ~= nil,
					("%s is off the grid and the panel does not say so: %s"):format(where, said))
			end
			check(said:find(where, 1, true) ~= nil,
				("%s is set and the panel reads %s"):format(where, said))

			local wide, tall = Settings.Pixels()
			if wide > widest then
				widest, tallest = wide, tall
			end
			stop = stop + Settings.STEP
		end

		check(stops == 11, ("%d stops between %s and %s, not 11")
			:format(stops, tostring(Settings.LOW), tostring(Settings.HIGH)))

		-- Which stops stay on the grid is a property of the monitor, not a
		-- constant, so the note that names them is generated and asserted rather
		-- than typed. This screen contributes a whole step of 1, so the exact
		-- stops are the three whole sizes and nothing else.
		local grid = Settings.Grid()
		local named = 0
		local at = Settings.LOW
		while at <= Settings.HIGH + 1e-6 do
			local listed = grid:find(Settings.Label(at), 1, true) ~= nil
			check(listed == ns.UI.Exact(screen * at),
				("%s is %s the grid and the note %s it: %s"):format(Settings.Label(at),
					ns.UI.Exact(screen * at) and "on" or "off",
					listed and "names" or "leaves out", grid))
			if listed then
				named = named + 1
			end
			at = at + Settings.STEP
		end
		check(named == 3, ("%d stops are exact at screen zoom %d, not 3"):format(named, screen))

		-- A drag, which is the case the widget is shaped around. The setting has
		-- to sit still while the button is down, because the window this slider
		-- is sitting in is the window the setting resizes, and a track that
		-- moves out from under the cursor mid-drag makes the client read the
		-- next value off geometry that has already changed.
		Settings.Set(1)
		size:GetScript("OnMouseDown")(size)
		size:SetValue(2.75)
		check(ns.db.uiSize == 1,
			("a held drag committed %s before the button came up"):format(tostring(ns.db.uiSize)))
		check(window.zoom == screen,
			("a held drag resized the window to zoom %s under the cursor")
				:format(tostring(window.zoom)))
		size:GetScript("OnMouseUp")(size)
		check(ns.db.uiSize == 2.75,
			("letting go saved %s, not the 2.75 the thumb was on"):format(tostring(ns.db.uiSize)))
		check(window.zoom == screen * 2.75,
			("letting go left the window at zoom %s"):format(tostring(window.zoom)))

		-- Shut with the button still down, by escape or by a reload. The drag
		-- never ends and the value would otherwise be dropped.
		Settings.Set(1)
		size:GetScript("OnMouseDown")(size)
		size:SetValue(1.75)
		size:GetScript("OnHide")(size)
		check(ns.db.uiSize == 1.75,
			("a drag interrupted by the window closing saved %s"):format(tostring(ns.db.uiSize)))

		-- Past the end. The client clamps its own slider and Settings.Snap
		-- clamps everything that never went through one, which is what a saved
		-- variable edited by hand meets.
		size:SetValue(Settings.HIGH + 5)
		check(ns.db.uiSize == Settings.HIGH,
			("dragging past the end saved %s"):format(tostring(ns.db.uiSize)))
		check(Settings.Snap(99) == Settings.HIGH and Settings.Snap(-1) == Settings.LOW,
			"Snap let a value outside the range through")
		check(Settings.Snap(1.3) == 1.25,
			("Snap put 1.3 on %s"):format(tostring(Settings.Snap(1.3))))

		-- The macro path refuses what the slider cannot reach, rather than
		-- rounding it into something that nearly works.
		check(ns.Command.Step("1.3", Settings.LOW, Settings.HIGH, Settings.STEP, "UI size") == nil,
			"the slash word rounded an off-step value instead of refusing it")
		check(ns.Command.Step("2.25", Settings.LOW, Settings.HIGH, Settings.STEP, "UI size") == 2.25,
			"the slash word refused a value that is on a step")

		-- Every window on the grid, not only the one this section measures. The
		-- Clutter window is built on first use and inherits the size then.
		Settings.Set(2)
		for index = 1, #ns.UI.Windows do
			check(ns.UI.Windows[index].zoom == screen * 2,
				("window %d stayed at zoom %s while the size went to 2x")
					:format(index, tostring(ns.UI.Windows[index].zoom)))
		end

		Settings.Set(1)
		check(window.zoom == screen and window.height == 452,
			("back at 1x the window is %.0f units tall at zoom %s")
				:format(window.height, tostring(window.zoom)))

		-- The same row on a client that refuses the Slider frame type.
		--
		-- Nothing installed on 2.5.6 proves that type takes a thumb texture from
		-- a stranger, so UI/Widgets.lua probes it and falls back to a pair of
		-- nudge buttons, and a branch nothing ever runs is a branch that is
		-- wrong. This one was: pcall hands back the error message where the
		-- frame would be, and the fallback called Hide on a string.
		--
		-- Built as a kit of its own on a stack of its own, rather than by
		-- rebuilding the panel, because the panel is what every check above has
		-- been driving and it is not put back afterwards.
		local realCreate = _G.CreateFrame
		_G.CreateFrame = function(kind, ...)
			if kind == "Slider" then
				error("this client has no Slider frame type")
			end
			return realCreate(kind, ...)
		end

		local held, row = 1, nil
		local ok, err = pcall(function()
			local host = { stack = ns.UI.Stack(window.frame, 300) }
			local kit = ns.UI.Kit(host)
			row = kit.Slider("UI size", Settings.LOW, Settings.HIGH, Settings.STEP,
				function() return held end,
				function(value) held = value end,
				Settings.Label)
			host.stack:Reflow()
		end)
		_G.CreateFrame = realCreate

		check(ok, "the size row raised on a client with no Slider: " .. tostring(err))
		if ok and row then
			check(row.slider == nil, "the row kept a slider on a client that refused the type")

			local down, up
			for _, kid in ipairs(row.children) do
				local label = kid.text and kid.text.text
				if kid:GetScript("OnClick") then
					if label == "-" then
						down = kid
					elseif label == "+" then
						up = kid
					end
				end
			end
			check(down ~= nil and up ~= nil, "the fallback row has no nudge buttons")

			if down and up then
				down:GetScript("OnClick")(down)
				check(held == 1 - Settings.STEP,
					("the fallback minus button moved the value to %s"):format(tostring(held)))
				up:GetScript("OnClick")(up)
				up:GetScript("OnClick")(up)
				check(held == 1 + Settings.STEP,
					("the fallback plus button moved the value to %s"):format(tostring(held)))
				for _ = 1, 20 do
					down:GetScript("OnClick")(down)
				end
				check(held == Settings.LOW,
					("the fallback buttons ran past the low end to %s"):format(tostring(held)))
			end
		end

		print(("size   %d stops, %s to %s, biggest panel %.0f x %.0f px on a %d pixel screen")
			:format(stops, Settings.Label(Settings.LOW), Settings.Label(Settings.HIGH),
				widest, tallest, SCREEN_H))
		print(("size   exact at %s on this screen, soft on the rest"):format(Settings.Grid()))
		print("size   " .. Settings.Describe())
	end

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
-- Which class this is
--
-- Ten of the twelve parts do not care. Two do: the charge button casts three
-- warrior abilities, and the loadout fills the bars with warrior spells. On
-- anyone else neither can do anything, so neither should be running, and the
-- charge part in particular has to be absent rather than merely quiet. A
-- hidden button is still a secure frame holding a key override, and a hidden
-- marker is still a nameplate scan twenty times a second.
--
-- Both halves are decided once, at PLAYER_LOGIN, which is why this file takes
-- a class on the command line instead of flipping one here. Every check below
-- is written against WARRIOR rather than against a fixed answer, so the same
-- section is a gate on both runs: the warrior run proves the parts are built
-- and the other run proves they are not.
--
-- The CVar is the one worth stating plainly. Action targeting exists to serve
-- the charge button, so on another class the addon must leave the client's own
-- setting exactly as it found it, and "the addon does nothing" is only ever
-- provable by reading the thing it would have written.
--------------------------------------------------------------------------

do
	check(ns.IsWarrior() == WARRIOR,
		("the addon thinks a %s is%s a warrior"):format(PLAYER_CLASS, WARRIOR and " not" or ""))

	check((_G.WarriorKitChargeButton ~= nil) == WARRIOR,
		("the charge button %s built on a %s"):format(WARRIOR and "was not" or "was", PLAYER_CLASS))
	check((_G.WarriorKitChargeMarker ~= nil) == WARRIOR,
		("the world marker %s built on a %s"):format(WARRIOR and "was not" or "was", PLAYER_CLASS))
	check(ns.Charge.Known("charge") == WARRIOR,
		("a %s %s Charge"):format(PLAYER_CLASS, WARRIOR and "does not know" or "knows"))

	-- Put the client's own value back under the addon and let it decide again.
	-- A warrior is out of combat here, so the setting says on; anyone else has
	-- to come out of this with the same "0" they went in with.
	cvars.SoftTargetEnemy = "0"
	fire("PLAYER_ENTERING_WORLD")
	check(cvars.SoftTargetEnemy == (WARRIOR and "3" or "0"),
		("action targeting came out at %s on a %s"):format(cvars.SoftTargetEnemy, PLAYER_CLASS))

	-- The key. Refused rather than accepted and dropped, because a binding the
	-- panel shows and nothing presses is worse than being told why.
	local held = ns.db.chargeKey
	local displaced, why = ns.ChargeIcon.Bind("F")
	check((displaced ~= nil) == WARRIOR,
		("binding the charge key on a %s came back %s"):format(PLAYER_CLASS, tostring(displaced or why)))
	ns.ChargeIcon.Bind(held)

	-- The loadout's own class gate is not reached from here: this stub has no
	-- PickupSpell, so Layout.CanWrite refuses before the class is asked, and a
	-- check on the message would be a check on the missing stub. It reads the
	-- same ns.IsWarrior as everything above.

	-- The page in the options window. Four tabs of controls on a warrior, one
	-- page saying why on anyone else, rather than check boxes that write a
	-- setting nothing on this character reads.
	local page
	for _, part in ipairs(window.parts) do
		if part.name == "Charge" then
			page = part
		end
	end
	check(page ~= nil, "the options window has no Charge page")
	check(page and #page.sections == (WARRIOR and 4 or 1),
		("the Charge page has %s tabs on a %s"):format(page and #page.sections or "no",
			PLAYER_CLASS))

	local status
	for _, feature in ipairs(ns.features) do
		if feature.name == "charge" then
			status = feature.status()
		end
	end
	check(status ~= nil, "the charge part reports no status line")
	check(WARRIOR or (status and status:find("not a warrior", 1, true) ~= nil),
		("the charge status line on a %s does not say why: %s"):format(PLAYER_CLASS, tostring(status)))

	print(("class   %s: charge button %s, world marker %s, action targeting %s, Charge page %d tab%s")
		:format(PLAYER_CLASS,
			_G.WarriorKitChargeButton and "built" or "not built",
			_G.WarriorKitChargeMarker and "built" or "not built",
			cvars.SoftTargetEnemy == "0" and "left alone" or ("driven to " .. cvars.SoftTargetEnemy),
			page and #page.sections or 0, (page and #page.sections == 1) and "" or "s"))
end

--------------------------------------------------------------------------
-- The three chores
--
-- Two of these are conveniences and one of them can destroy what you own. The
-- container call the vendor part is built on sells a grey while a merchant
-- window is up and eats, equips or opens the same item when one is not, so the
-- assertions that carry the weight here are the negative ones: that a sweep
-- which loses its window moves nothing, that a green is still in the bag on the
-- last pass, and that the money that arrived is the money those two greys were
-- worth and not a copper more.
--------------------------------------------------------------------------

do
	local function lootedCount()
		local count = 0
		for _ in pairs(looted) do
			count = count + 1
		end
		return count
	end

	local function clearCorpse()
		for slot in pairs(looted) do
			looted[slot] = nil
		end
	end

	local function junkLeft()
		local count = 0
		for index = 1, #JUNK do
			if JUNK[index] then
				count = count + 1
			end
		end
		return count
	end

	_G.SetCVar("autoLootDefault", 1)

	----------------------------------------------------------------------
	-- Looting
	----------------------------------------------------------------------

	-- Solo, group loot, auto loot on: the whole corpse in one pass.
	clearCorpse()
	advance(1)
	fire("LOOT_READY")
	check(lootedCount() == 4, ("fast loot took %d of 4 slots"):format(lootedCount()))

	-- LOOT_READY fires again as each slot clears, and a second pass over slots
	-- the first one already took is at best wasted work.
	clearCorpse()
	fire("LOOT_READY")
	check(lootedCount() == 0, "the loot throttle let a second burst straight through")

	clearCorpse()
	advance(1)
	fire("LOOT_READY")
	check(lootedCount() == 4, "the loot throttle never released")

	-- Master loot, threshold 2. Slots 1 and 2 are under it and are taken; slots
	-- 3 and 4 are the master looter's to assign, and taking one of those on
	-- someone's behalf is the failure this guard exists for.
	clearCorpse()
	advance(1)
	lootMethod = "master"
	fire("LOOT_READY")
	check(looted[1] and looted[2], "master loot skipped a slot under the threshold")
	check(not looted[3] and not looted[4],
		"master loot took a slot the master looter has to hand out")
	lootMethod = "group"

	-- Off is unregistered, not a branch inside a handler the client still calls.
	clearCorpse()
	advance(1)
	ns.db.fastLoot = false
	ns.Loot.Apply()
	check(#(events["LOOT_READY"] or {}) == 0,
		"fast loot off left the addon sitting on the loot path")
	fire("LOOT_READY")
	check(lootedCount() == 0, "fast loot off still emptied the corpse")
	ns.db.fastLoot = true
	ns.Loot.Apply()

	----------------------------------------------------------------------
	-- The vendor
	----------------------------------------------------------------------

	-- Two parts sit on the merchant now, the sweep and the repair, so the
	-- sweep's frame is found by the thing only it has rather than by its place
	-- in the list: a sale is the one of the two that has to be stopped when the
	-- window shuts, so it is the one that also holds MERCHANT_CLOSED.
	local function listening(frame, event)
		for _, f in ipairs(events[event] or {}) do
			if f == frame then
				return true
			end
		end
		return false
	end

	local vendorFrame, repairFrame = nil, nil
	for _, f in ipairs(events["MERCHANT_SHOW"] or {}) do
		if listening(f, "MERCHANT_CLOSED") then
			vendorFrame = f
		else
			repairFrame = f
		end
	end
	check(vendorFrame ~= nil, "nothing registered MERCHANT_SHOW and MERCHANT_CLOSED")
	check(repairFrame ~= nil, "nothing registered MERCHANT_SHOW for the repair")

	local function sweep()
		local ticks = 0
		while ns.Vendor.Running() and ticks < 60 do
			vendorFrame.scripts.OnUpdate(vendorFrame, 0.2)
			ticks = ticks + 1
		end
		return ticks
	end

	-- The one that matters. A sale that starts and then loses its window has to
	-- touch nothing at all, because with the window shut every sale is a use.
	refill()
	_G.MerchantFrame:Show()
	fire("MERCHANT_SHOW")
	_G.MerchantFrame:Hide()
	sweep()
	check(junkLeft() == 4, "the sweep emptied the bag with the merchant window shut")
	check(misused == 0, "something in the bags was used rather than sold")

	-- And the sale itself. Two greys a vendor pays for go, the grey it will not
	-- pay for stays, and so does the green.
	refill()
	local before = _G.GetMoney()
	_G.MerchantFrame:Show()
	fire("MERCHANT_SHOW")
	check(ns.Vendor.Running(), "the merchant opened and no sweep started")

	local ticks = sweep()
	local sale = _G.GetMoney() - before
	check(not ns.Vendor.Running(), "the sweep never stopped on its own")
	check(sale == 47 + 12, ("the vendor paid %d for two greys worth 59"):format(sale))
	check(junkLeft() == 2,
		("%d left in the bag; the worthless grey and the green make 2"):format(junkLeft()))
	check(misused == 0, "the sale used something instead of selling it")

	-- Shift is the override, the same key that already means "let me do this
	-- myself" everywhere else at a merchant.
	refill()
	_G.MerchantFrame:Show()
	_G.IsShiftKeyDown = constant(true)
	fire("MERCHANT_SHOW")
	check(not ns.Vendor.Running(), "shift did not hold the sale off")
	_G.IsShiftKeyDown = constant(false)

	ns.db.sellTrash = false
	ns.Vendor.Apply()
	check(not listening(vendorFrame, "MERCHANT_SHOW"),
		"selling off left the addon sitting on the merchant")
	ns.db.sellTrash = true
	ns.Vendor.Apply()
	_G.MerchantFrame:Hide()

	----------------------------------------------------------------------
	-- The repair
	--
	-- One call and no ticker, so what is asserted is not that it finished but
	-- that the right purse paid. Every branch below ends with somebody out of
	-- pocket by exactly the bill, or with the bill still standing.
	----------------------------------------------------------------------

	local function damage(amount)
		repairBill = amount
		paidBy = nil
	end

	-- Nothing damaged is not a refusal, and it must not print as one.
	purse = 500
	damage(0)
	_G.MerchantFrame:Show()
	fire("MERCHANT_SHOW")
	check(ns.Repair.Run() == 0, "an undamaged warrior was not reported as undamaged")

	-- Your own money, which is the ordinary case: no guild bank in reach.
	GUILD.allowed = false
	damage(120)
	purse = 500
	fire("MERCHANT_SHOW")
	check(repairBill == 0, "opening a merchant left the gear damaged")
	check(purse == 380, ("the repair cost 120 and the purse moved by %d"):format(500 - purse))
	check(paidBy == "you", "the repair was not billed to the player")

	-- A purse that cannot cover it is left alone. Half a repair is not a thing
	-- the client offers and a purse emptied to nothing is worse than broken mail.
	damage(400)
	purse = 100
	fire("MERCHANT_SHOW")
	check(repairBill == 400, "a repair went through on a purse that could not cover it")
	check(purse == 100, "money left a purse that could not cover the repair")

	-- Guild funds first where the guild allows it, and the purse untouched.
	GUILD.allowed, GUILD.limit, GUILD.held, GUILD.spent = true, 1000, 1000, 0
	damage(400)
	purse = 100
	fire("MERCHANT_SHOW")
	check(repairBill == 0, "the guild bank was in reach and the gear stayed damaged")
	check(GUILD.spent == 400, ("the guild paid %d of a 400 bill"):format(GUILD.spent))
	check(purse == 100, "the guild paid and the purse moved as well")

	-- An unlimited rank answers -1, which is a sentinel and not an amount. Read
	-- as an amount it is the smallest allowance there is and every repair falls
	-- through to your own gold.
	GUILD.allowed, GUILD.limit, GUILD.held, GUILD.spent = true, -1, 1000, 0
	damage(400)
	purse = 1000
	fire("MERCHANT_SHOW")
	check(GUILD.spent == 400, "an unlimited withdraw allowance was read as no allowance")
	check(purse == 1000, "an unlimited rank still paid out of the player's purse")

	-- A rank allowed to withdraw less than the bill falls back to your gold
	-- rather than trying the guild and walking away.
	GUILD.allowed, GUILD.limit, GUILD.held, GUILD.spent = true, 50, 1000, 0
	damage(400)
	purse = 1000
	fire("MERCHANT_SHOW")
	check(GUILD.spent == 0, "the guild paid past the rank's withdraw limit")
	check(purse == 600, ("the purse should have covered the 400; it moved %d"):format(1000 - purse))
	check(repairBill == 0, "a rank under the limit left the gear damaged")

	-- And a guild that says yes and then refuses. The addon has to notice the
	-- bill is still standing and pay it itself.
	GUILD.allowed, GUILD.limit, GUILD.held, GUILD.spent = true, 1000, 0, 0
	damage(400)
	purse = 1000
	fire("MERCHANT_SHOW")
	check(repairBill == 0, "the guild refused and nothing paid the bill")
	check(purse == 600, "the guild refused and the fall-through never happened")
	GUILD.allowed = false

	-- A merchant who does not mend is a refusal with a reason, not a repair.
	repairsMerchant = false
	damage(400)
	purse = 1000
	fire("MERCHANT_SHOW")
	check(repairBill == 400, "a merchant who does not repair repaired anyway")
	check(select(2, ns.Repair.Run()) == "this merchant does not repair",
		"the refusal did not say why")
	repairsMerchant = true

	-- Shift holds it off, the same key that holds the sale off.
	damage(400)
	purse = 1000
	_G.IsShiftKeyDown = constant(true)
	fire("MERCHANT_SHOW")
	check(repairBill == 400, "shift did not hold the repair off")
	_G.IsShiftKeyDown = constant(false)

	-- Off is unregistered, not a branch inside a handler the client still calls.
	ns.db.autoRepair = false
	ns.Repair.Apply()
	check(not listening(repairFrame, "MERCHANT_SHOW"),
		"repair off left the addon sitting on the merchant")
	fire("MERCHANT_SHOW")
	check(repairBill == 400, "repair off still paid the merchant")
	ns.db.autoRepair = true
	ns.Repair.Apply()

	-- The worst piece, not the first one and not an average. A ring answers
	-- nothing and must not count as a piece at zero.
	damage(0)
	local worst, counted = ns.Repair.Durability()
	check(counted == 3, ("%d slots answered durability, three wear"):format(counted))
	check(worst ~= nil and math.floor(worst + 0.5) == 12,
		"the worst piece is at 12%% and the scan did not say so")

	_G.MerchantFrame:Hide()

	----------------------------------------------------------------------
	-- The camera
	----------------------------------------------------------------------

	ns.db.maxZoom = true
	ns.Camera.Apply()
	check(ns.Camera.Current() == 4, "max zoom never reached the CVar")

	-- Off hands the CVar back at whatever this client calls its default. With no
	-- GetCVarDefault, which is the client the fallback exists for, that is the
	-- documented 1.9.
	ns.db.maxZoom = false
	ns.Camera.Apply()
	check(ns.Camera.Current() == 1.9, "turning max zoom off did not hand the CVar back")

	-- And where the client does state a default, that is the number used.
	_G.GetCVarDefault = function() return "2.4" end
	ns.Camera.Apply()
	check(ns.Camera.Current() == 2.4, "the client's own default was ignored")
	_G.GetCVarDefault = nil

	ns.db.maxZoom = true
	ns.Camera.Apply()

	print(("chores corpse of %d in one pass, vendor paid %s over %d passes for 2 of 4 slots, repair %s, camera %s")
		:format(#CORPSE, _G.GetCoinText(sale), ticks, ns.Repair.Describe(),
			ns.Camera.Describe()))
end

--------------------------------------------------------------------------
-- The clutter window
--
-- The only thing in the addon with nothing behind it. A grey sold to a vendor
-- is in the buyback tab; an item destroyed here is gone. So most of what is
-- asserted below is the window refusing: a slot that moved under the card, a
-- cursor holding the wrong thing, a client with no delete call, a second click
-- landing on the card that replaced the one you meant. Each of those is a way
-- to destroy the wrong item, and each one has to end with nothing destroyed.
--------------------------------------------------------------------------

do
	local function byName(list)
		local out = {}
		for index = 1, #list do
			out[list[index].name] = list[index]
		end
		return out
	end

	----------------------------------------------------------------------
	-- The verdict
	----------------------------------------------------------------------

	refillQuests()
	local found = ns.Clutter.Scan()
	local seen = byName(found)

	check(#found == 4,
		("the scan offered %d of 7 quest items; 4 of them are finished with"):format(#found))
	check(seen["Diplomat's Ring"] == nil, "an item wanted by a quest in your log was offered")
	check(seen["Sealed Letter"] == nil, "an item that starts a quest you have not done was offered")
	check(seen["Unknown Trinket"] == nil, "an item the database has never heard of was offered")
	check(seen["Hogger's Claw"] ~= nil and ns.Clutter.Certain(seen["Hogger's Claw"]),
		"an item whose only quest is behind you was not offered as certain")
	check(seen["Zul'Mamwe Fetish"] ~= nil and ns.Clutter.Certain(seen["Zul'Mamwe Fetish"]),
		"an item whose two quests are both behind you was not offered as certain")
	check(seen["Old Cipher"] ~= nil and ns.Clutter.Certain(seen["Old Cipher"]),
		"a starter for a quest you have already completed was not offered")
	check(seen["Rogue's Token"] ~= nil and not ns.Clutter.Certain(seen["Rogue's Token"]),
		"an item for a quest still out there was not flagged as the uncertain one")

	-- Certain first, so the window never opens on the hard question.
	check(ns.Clutter.Certain(found[1]), "the queue did not put a certain item first")
	check(not ns.Clutter.Certain(found[#found]), "the queue did not put the uncertain one last")

	-- And the card names the quest, which is the whole reason the window exists
	-- rather than a list of item names.
	check(seen["Hogger's Claw"].reason:find("Wanted: Hogger", 1, true) ~= nil,
		"the card does not name the quest the item came from")
	check(seen["Rogue's Token"].reason:find("A Rogue's Deal", 1, true) ~= nil,
		"the uncertain card does not name the quest that still wants the item")

	----------------------------------------------------------------------
	-- Cycling
	----------------------------------------------------------------------

	ns.Destroy.Show()

	local clutter
	for _, held in ipairs(ns.UI.Windows) do
		if held.frame and held.frame:GetName() == "WarriorKitClutter" then
			clutter = held
		end
	end
	check(clutter ~= nil, "the clutter window was never built")

	local card = clutter.card
	check(card.count:GetText() == "1 of 4",
		("the counter opened on %q rather than 1 of 4"):format(tostring(card.count:GetText())))

	local before = #destroyed
	card.skip.scripts.OnClick()
	check(#destroyed == before, "skip destroyed something")
	check(card.count:GetText() == "2 of 4",
		("skip left the counter on %q"):format(tostring(card.count:GetText())))

	advance(1)
	card.destroy.scripts.OnClick()
	check(#destroyed == before + 1, "the destroy button destroyed nothing")
	check(destroyed[#destroyed]:find("Old Cipher", 1, true) ~= nil,
		"destroy took an item other than the one on the card")

	-- Two clicks in the same instant is one destroy. The window replaces the
	-- card the moment the first lands, so without the debounce the second falls
	-- on an item nobody looked at.
	local held = #destroyed
	card.destroy.scripts.OnClick()
	check(#destroyed == held, "a second click in the same instant destroyed another item")

	----------------------------------------------------------------------
	-- Every way it has to refuse
	----------------------------------------------------------------------

	-- The slot moved under the card. Something looted, the vendor sweep sold,
	-- a stack split and everything after it shifted by one.
	refillQuests()
	ns.Destroy.Show()
	QUESTBAG[1] = "Unknown Trinket"
	held = #destroyed
	local touched = pickups
	advance(1)
	card.destroy.scripts.OnClick()
	check(#destroyed == held, "the window destroyed whatever had replaced the item on the card")
	check(QUESTBAG[1] == "Unknown Trinket", "the replacement item was destroyed")
	-- And it never reached the cursor. The cursor check would have caught this
	-- too, so counting pickups is the only way to say the slot re-read in front
	-- of it is still there.
	check(pickups == touched, "a stale card still put an item on the cursor")

	-- The cursor came up holding something else, which is the client
	-- contradicting the bag scan. It is a second opinion and it gets to win.
	refillQuests()
	ns.Destroy.Show()
	local realPickup = _G.PickupContainerItem
	_G.PickupContainerItem = function() realPickup(2, 7) end
	held = #destroyed
	advance(1)
	card.destroy.scripts.OnClick()
	check(#destroyed == held, "a cursor holding the wrong item was deleted anyway")
	check(_G.GetCursorInfo() == nil, "the cursor was left holding an item")
	_G.PickupContainerItem = realPickup

	-- A client with no DeleteCursorItem. Nothing installed on either client
	-- calls it, Questie only hooks it, so this is the client the probe exists
	-- for and it has to refuse rather than raise.
	refillQuests()
	ns.Destroy.Show()
	local realDelete = _G.DeleteCursorItem
	_G.DeleteCursorItem = nil
	held = #destroyed
	advance(1)
	card.destroy.scripts.OnClick()
	check(#destroyed == held, "something was destroyed on a client with no delete call")
	check(_G.GetCursorInfo() == nil, "the cursor was left holding an item")
	_G.DeleteCursorItem = realDelete

	----------------------------------------------------------------------
	-- Without Questie
	----------------------------------------------------------------------

	local realLoader = _G.QuestieLoader
	_G.QuestieLoader = nil
	local none, why = ns.Clutter.Scan()
	check(#none == 0 and why == "questie", "a missing Questie did not stop the scan")
	check(not ns.Clutter.Ready(), "a missing Questie still reported a working database")

	-- The trap. ImportModule answers a fresh empty table for a module it does
	-- not carry, so the module coming back is no proof of anything.
	_G.QuestieLoader = { ImportModule = function() return {} end }
	check(not ns.Clutter.Ready(), "an empty Questie module was taken for a working database")
	_G.QuestieLoader = realLoader

	ns.Destroy.Hide()
	refillQuests()

	print(("clutter %d of %d quest items finished with, %d destroyed and %d refusals held")
		:format(#found, #QUESTBAG, #destroyed, 3))
end

--------------------------------------------------------------------------
-- The meters
--
-- Four questions, and only the first of them is about drawing.
--
-- Does the frame come up on the grid, in the size the settings ask for, and
-- does changing a setting reshape it without building a second copy of it. A
-- frame cannot be destroyed on this client, so a pane rebuilt per setting
-- change is a leak that never shows up in game and never stops growing.
--
-- Does the combat log parser read the right slot. The client hands over
-- sixteen values in a fixed order and the amount is in a different one for a
-- swing than for a spell, so the whole of that half is positional and a stub
-- that answered a named table would prove nothing about it.
--
-- Does the group filter hold. The log carries every fight in range: the other
-- party's pull, both sides of the duel by the mailbox, and every mob in the
-- pack. A pet's damage has to land on its owner and a stranger's has to land
-- nowhere, and those two are the same test from opposite ends.
--
-- And does a segment start and stop when a fight does, rather than when a
-- bleed ticks. The tail of the last pull opening a new segment would replace
-- the numbers you are still reading with two ticks of damage, which is the
-- kind of defect nobody reports because it looks like the meter resetting for
-- some reason of its own.
--------------------------------------------------------------------------

do
	local meterTicker
	for _, f in ipairs(frames) do
		if f.scripts.OnUpdate and f.origin:match("Meter/Window") then
			meterTicker = f
		end
	end
	check(meterTicker ~= nil, "the meters registered no ticker")

	-- Before anything in this file has ever been in a fight. Nothing has been
	-- recorded and no segment has ever opened, so the clock reads zero, and
	-- dividing a total of nothing by it is a nan that reaches the pane as
	-- -9223372036854775808. This is the first tick of every session and it ran
	-- that way until Meter.lua stopped dividing by Meter.Elapsed directly.
	check(ns.Meter.Idle(), "something was recorded before the first fight")
	check(ns.Meter.Elapsed() == 0,
		("the clock reads %s before the first fight"):format(tostring(ns.Meter.Elapsed())))
	check(ns.Meter.Total("dps") == 0,
		("the group total reads %s before the first fight"):format(tostring(ns.Meter.Total("dps"))))
	meterTicker.scripts.OnUpdate(meterTicker, 0.25)

	local frame = _G.WarriorKitMeter
	check(frame ~= nil, "no meter frame came up")
	local damagePane = ns.MeterWindow.Pane("damage")
	local threatPane = ns.MeterWindow.Pane("threat")
	check(damagePane ~= nil and threatPane ~= nil, "the meters built fewer than two panes")

	----------------------------------------------------------------------
	-- The shape
	----------------------------------------------------------------------

	check(math.abs(ns.UI.Pixel(frame) - 1) < 1e-9,
		("the meters are not on the grid: one pixel is %.4f units"):format(ns.UI.Pixel(frame)))

	-- The gap between the two panes, which is the only number in the frame's
	-- width that is not a setting.
	local PANE_GAP = 8
	check(damagePane:GetWidth() == ns.db.meterWidth,
		("a pane is %.0f px, the setting says %d"):format(damagePane:GetWidth(), ns.db.meterWidth))
	check(frame:GetWidth() == ns.db.meterWidth * 2 + PANE_GAP,
		("the frame is %.0f px, two panes and a gap is %d")
			:format(frame:GetWidth(), ns.db.meterWidth * 2 + PANE_GAP))

	-- A header, a hairline and one row per setting, with the gap only between
	-- rows and not hanging off the bottom. A row is the icon plus a pixel above
	-- and below it, which is what makes the icon rather than the text decide
	-- how tall the meter is.
	local HEADER, RULE, ROW, ROW_GAP = 16, 1, 29, 1
	local wanted = HEADER + RULE + ns.db.meterRows * (ROW + ROW_GAP) - ROW_GAP
	check(frame:GetHeight() == wanted,
		("the frame is %.0f px tall, a header and %d rows is %d")
			:format(frame:GetHeight(), ns.db.meterRows, wanted))

	-- A row icon lands one stored texel on one pixel, at the two zooms that can.
	--
	-- This is the gate for the defect that reached the user: the icon drew 12
	-- screen pixels of art out of a 54 texel source, the renderer blended the 27
	-- copy with the 13.5 copy, and every icon on the meter came out soft. The
	-- sizes that are exact are not a matter of taste, they are 54 and 27 and
	-- nothing between, and ns.UI.IconSizes is where they come from, so this
	-- moves on its own if the crop in UI/Draw.lua ever changes.
	for _, zoom in ipairs({ 1, 2 }) do
		local drawn, exact = ns.MeterWindow.IconAdvice(zoom)
		check(exact, ("a row icon draws %d screen pixels at %dx, which is not a size the client stores")
			:format(drawn, zoom))
	end

	-- Every string on the meter is big enough to survive its own outline.
	--
	-- All of them are outlined and all of them have to be: the meter has no
	-- background, so flat text over a pale floor is not softer, it is gone. That
	-- rules out the fallback ns.UI.NumberFont takes for a number on a debuff
	-- square, and leaves a hard minimum instead. The floor is read from
	-- UI/Text.lua rather than written here, so one number governs both parts.
	--
	-- The headers were the ones this caught. The rows went to 14 off the report
	-- from the client; the headers stayed at 12 and were the same defect sitting
	-- one line above it, unnoticed because nobody reads a header twice.
	local floor = ns.UI.OutlineFloor()
	for _, entry in ipairs({
		{ "a row's number", damagePane.rows[1].value },
		{ "a row's name", damagePane.rows[1].name },
		{ "the left header", damagePane.left },
		{ "the right header", damagePane.right },
		{ "the threat header", threatPane.left },
	}) do
		local _, size, flags = entry[2]:GetFont()
		check(size and (size >= floor or flags == ""),
			("%s is outlined at %s pixels and the floor is %d")
				:format(entry[1], tostring(size), floor))
	end

	-- Every setting that reshapes it reuses the frames it already made.
	local built = #frames
	ns.db.meterRows = 4
	ns.MeterWindow.Apply()
	check(#frames == built, ("changing the row count built %d new frames"):format(#frames - built))
	check(damagePane.visible == 4, "the pane did not take the new row count")
	check(not damagePane.rows[5]:IsShown(), "a row past the setting was left on screen")
	check(ns.MeterWindow.Pane("damage") == damagePane, "the pane was replaced rather than resized")

	ns.db.meterThreat = false
	ns.MeterWindow.Apply()
	check(frame:GetWidth() == ns.db.meterWidth,
		"the frame kept the threat pane's width after the pane was turned off")
	check(not threatPane:IsShown(), "the threat pane was turned off and stayed on screen")

	ns.db.meterThreat = true
	ns.db.meterRows = 6
	ns.MeterWindow.Apply()
	check(#frames == built, "turning the threat pane off and on again built new frames")

	----------------------------------------------------------------------
	-- The group
	----------------------------------------------------------------------

	local BAUDIN = "Player-0-00000001"
	local SNEAKY = "Player-0-00000002"
	local PET = "Pet-0-00000002"
	local FROST = "Player-0-00000003"
	local STRANGER = "Player-0-00000099"
	local TOTEM = "Creature-0-0000-000-totem"

	guids.player, unitClass.player, unitName.player = BAUDIN, "WARRIOR", "Baudin"
	guids.party1, unitClass.party1, unitName.party1 = SNEAKY, "HUNTER", "Sneakyman"
	guids.partypet1 = PET
	guids.party2, unitClass.party2, unitName.party2 = FROST, "PRIEST", "Frostbite"
	realPlayers.party1, realPlayers.party2 = true, true
	fire("GROUP_ROSTER_UPDATE")

	check(ns.Unit.Roster.Size() == 3,
		("the group has %d members in it, expected 3"):format(ns.Unit.Roster.Size()))
	check(ns.Unit.Roster.Owner(PET) == SNEAKY, "a pet's damage does not land on its owner")
	check(ns.Unit.Roster.Owner(BAUDIN) == BAUDIN, "your own damage does not land on you")
	check(ns.Unit.Roster.Owner(STRANGER) == nil, "somebody else's fight is inside the group filter")
	local who, class = ns.Unit.Roster.Who(SNEAKY)
	check(who == "Sneakyman" and class == "HUNTER",
		("the roster has %s the %s"):format(tostring(who), tostring(class)))

	----------------------------------------------------------------------
	-- The log
	--
	-- Sixteen values in the order the client hands them over. The amount is at
	-- 12 for a swing and at 15 for everything with a spell in front of it, and
	-- reading the wrong one is the whole failure mode this models.
	--
	-- `wasted` is the slot after the amount, which is 13 on a swing and 16 on
	-- everything else. The client puts three different things there and they
	-- are all the same thing: overkill on a damage event, overheal on a heal.
	-- One parameter rather than three, because a stub that gave each of them
	-- its own argument would let a parser that reads a swing's overkill out of
	-- slot 16 pass.
	----------------------------------------------------------------------

	local function log(subevent, source, dest, swing, amount, wasted)
		for index = 1, 16 do
			logArgs[index] = nil
		end
		logArgs[1] = GetTime()
		logArgs[2] = subevent
		logArgs[4] = source
		logArgs[8] = dest
		logArgs[12] = swing
		logArgs[15] = amount
		if swing then
			logArgs[13] = wasted
		else
			logArgs[16] = wasted
		end
		fire("COMBAT_LOG_EVENT_UNFILTERED")
	end

	inCombat.player = true
	fire("PLAYER_REGEN_DISABLED")
	check(ns.Meter.Running(), "combat started and no segment opened")

	log("SWING_DAMAGE", BAUDIN, nil, 1000)
	log("SPELL_DAMAGE", SNEAKY, nil, nil, 500)
	log("SPELL_DAMAGE", PET, nil, nil, 300)
	log("SPELL_DAMAGE", STRANGER, nil, nil, 9999)
	log("SPELL_HEAL", FROST, nil, nil, 400, 150)
	advance(10)

	local ranked = ns.Meter.Rank("dps")
	check(#ranked == 2, ("%d rows did damage, expected 2"):format(#ranked))
	check(ranked[1].guid == BAUDIN and ns.Meter.Amount(ranked[1], "dps") == 1000,
		("the top row is %s on %d"):format(tostring(ns.Unit.Roster.Who(ranked[1].guid)),
			ns.Meter.Amount(ranked[1], "dps")))
	check(ranked[2].guid == SNEAKY and ns.Meter.Amount(ranked[2], "dps") == 800,
		("the hunter and their pet came to %d, expected 800")
			:format(ns.Meter.Amount(ranked[2], "dps")))
	check(ns.Meter.Rate(ranked[1], "dps") == 100,
		("1000 damage over ten seconds reads as %.1f"):format(ns.Meter.Rate(ranked[1], "dps")))
	check(ns.Meter.Total("dps") == 180,
		("the group total is %.1f, and 1800 over ten seconds is 180"):format(ns.Meter.Total("dps")))

	local healed = ns.Meter.Rank("hps")
	check(#healed == 1 and healed[1].guid == FROST, "the healer is not the only row with healing on it")
	check(ns.Meter.Amount(healed[1], "hps") == 250,
		("400 healed into 150 of overheal counted as %d, expected 250")
			:format(ns.Meter.Amount(healed[1], "hps")))

	----------------------------------------------------------------------
	-- The ends of a fight
	----------------------------------------------------------------------

	inCombat.player = false
	fire("PLAYER_REGEN_ENABLED")
	check(not ns.Meter.Running(), "combat dropped and the segment stayed open")

	local frozen = ns.Meter.Elapsed()
	advance(5)
	check(ns.Meter.Elapsed() == frozen,
		("the clock ran on to %ds after the fight ended at %ds"):format(ns.Meter.Elapsed(), frozen))

	-- A bleed ticking on a mob that is already down. Nobody is in combat, so
	-- this is not a fight and must not be treated as the start of one.
	log("SPELL_PERIODIC_DAMAGE", BAUDIN, nil, nil, 77)
	check(not ns.Meter.Running(), "a tick after the fight opened a new segment")
	check(ns.Meter.Amount(ns.Meter.Rank("dps")[1], "dps") == 1000,
		"the tail of the last fight was written over the fight itself")

	-- Somebody else's pull. They are in combat and you are not yet, which is
	-- the case the whole rule exists for.
	inCombat.party1 = true
	log("SPELL_DAMAGE", SNEAKY, nil, nil, 250)
	check(ns.Meter.Running(), "somebody else's pull did not open a segment")
	local opened = ns.Meter.Rank("dps")
	check(#opened == 1 and opened[1].guid == SNEAKY,
		("the new segment came up with %d rows from the old one"):format(#opened - 1))

	-- A totem is not a pet and no unit token ever points at one, so the summon
	-- in the log is the only place the client says whose it is.
	log("SPELL_SUMMON", FROST, TOTEM)
	log("SPELL_DAMAGE", TOTEM, nil, nil, 120)
	local summoned = nil
	for _, slot in ipairs(ns.Meter.Rank("dps")) do
		if slot.guid == FROST then
			summoned = slot
		end
	end
	check(summoned ~= nil and ns.Meter.Amount(summoned, "dps") == 120,
		"what a member summoned did not land on the member")

	-- And one heal in this segment, so the toggle below has something to swap
	-- to. Nobody has healed since the pull opened it, and a pane that is empty
	-- because the fight was quiet proves nothing about the pane.
	log("SPELL_HEAL", FROST, nil, nil, 600, 100)

	----------------------------------------------------------------------
	-- Overkill
	--
	-- The last hit of a fight is reported at what it swung for, not at what
	-- the mob had left, and the difference is handed over beside it. Counting
	-- the swing is counting health the mob did not have, and on a five second
	-- pull it is most of the chart.
	--
	-- Three hits, because there are three ways to get this wrong: read a
	-- swing's overkill out of the spell slot, read a spell's out of the swing
	-- slot, or subtract the minus one the client sends on every hit that
	-- killed nothing and hand back more damage than was dealt.
	--
	-- Small numbers on purpose. This lands in the segment the pane assertions
	-- further down are drawn from, and those expect the hunter on top, so what
	-- is checked here has to stay under their 250.
	----------------------------------------------------------------------

	log("SWING_DAMAGE", BAUDIN, nil, 5000, nil, 4900)
	log("SPELL_DAMAGE", BAUDIN, nil, nil, 2000, 1900)
	log("SPELL_DAMAGE", BAUDIN, nil, nil, 40, -1)

	local killer = nil
	for _, slot in ipairs(ns.Meter.Rank("dps")) do
		if slot.guid == BAUDIN then
			killer = slot
		end
	end
	check(killer ~= nil and ns.Meter.Amount(killer, "dps") == 240,
		("7,040 swung with 6,800 of it overkill counted as %s, expected 240")
			:format(killer and tostring(ns.Meter.Amount(killer, "dps")) or "no row at all"))
	check(ns.Meter.Amount(ns.Meter.Rank("dps")[1], "dps") == 250,
		("the hunter is on %d and the overkill went somewhere it should not have")
			:format(ns.Meter.Amount(ns.Meter.Rank("dps")[1], "dps")))

	----------------------------------------------------------------------
	-- A totem that was already down when the fight started
	--
	-- The summon is the only place the client says whose a totem is, and it
	-- happens before the pull, because that is when totems get dropped. A
	-- segment opens by rebuilding the roster, so a roster rebuild that forgot
	-- what it had been told by the log dropped the totem's whole fight.
	----------------------------------------------------------------------

	inCombat.player, inCombat.party1 = false, false
	fire("PLAYER_REGEN_ENABLED")

	local PRE = "Creature-0-0000-000-searing"
	log("SPELL_SUMMON", FROST, PRE)
	fire("GROUP_ROSTER_UPDATE") -- somebody zones in between pulls
	check(ns.Unit.Roster.Owner(PRE) == FROST,
		"a roster change forgot whose totem it is")

	inCombat.player = true
	fire("PLAYER_REGEN_DISABLED")
	log("SPELL_DAMAGE", PRE, nil, nil, 640)
	local burning = ns.Meter.Rank("dps")
	check(#burning == 1 and burning[1].guid == FROST
			and ns.Meter.Amount(burning[1], "dps") == 640,
		"a totem dropped before the pull did not put its damage on anyone")

	-- And it stops being ours when its owner is not. The totem is still
	-- burning; it is somebody else's fight now.
	realPlayers.party2, guids.party2 = nil, nil
	fire("GROUP_ROSTER_UPDATE")
	check(ns.Unit.Roster.Owner(PRE) == nil,
		"a totem kept counting after its owner left the group")
	realPlayers.party2, guids.party2 = true, FROST
	fire("GROUP_ROSTER_UPDATE")

	-- Put the segment the pane assertions below are drawn from back the way
	-- they expect to find it: the hunter on top, the priest healing.
	inCombat.player, inCombat.party1 = false, false
	fire("PLAYER_REGEN_ENABLED")
	inCombat.player = true
	fire("PLAYER_REGEN_DISABLED")
	log("SPELL_DAMAGE", SNEAKY, nil, nil, 250)
	log("SPELL_SUMMON", FROST, TOTEM)
	log("SPELL_DAMAGE", TOTEM, nil, nil, 120)
	log("SPELL_HEAL", FROST, nil, nil, 600, 100)

	----------------------------------------------------------------------
	-- Spec icons
	----------------------------------------------------------------------

	ns.MeterSpec.Refresh()
	check(ns.MeterSpec.Known(BAUDIN), "your own spec did not resolve out of your talent trees")
	local icon = ns.MeterSpec.Icon(BAUDIN, "WARRIOR")
	check(icon:find("SavageBlow", 1, true) ~= nil,
		("the spec icon is %q, and 31 points are in Arms"):format(icon))

	-- The other signature. One build leads with a numeric tab id and one leads
	-- with the tree's name, and the addon tells them apart on the type of the
	-- first value rather than on how far down the tail a nil turns up.
	talentShape = "old"
	ns.MeterSpec.Forget()
	ns.MeterSpec.Refresh()
	check(ns.MeterSpec.Known(BAUDIN), "the older GetTalentTabInfo signature was not read")
	talentShape = "modern"

	-- Nobody has committed to anything yet, so there is no spec to draw and the
	-- class icon stands in.
	local spent = talentTrees.player[2].points
	talentTrees.player[1].points, talentTrees.player[2].points = 2, 1
	ns.MeterSpec.Forget()
	ns.MeterSpec.Refresh()
	check(not ns.MeterSpec.Known(BAUDIN), "three points in a tree were taken for a spec")
	local sheet, left = ns.MeterSpec.Icon(BAUDIN, "WARRIOR")
	check(sheet:find("CharacterCreate", 1, true) ~= nil and left == 0,
		("the fallback drew %q rather than the class sheet"):format(sheet))
	talentTrees.player[1].points, talentTrees.player[2].points = 31, spent

	-- And somebody else's, which is an inspect and an answer rather than a read.
	ns.MeterSpec.Forget()
	ns.MeterSpec.Refresh()
	check(ns.MeterSpec.Request(SNEAKY), "no inspect went out for a party member in range")
	check(inspecting == "party1",
		("the inspect went to %s"):format(tostring(inspecting)))
	fire("INSPECT_READY", SNEAKY)
	check(ns.MeterSpec.Known(SNEAKY), "the inspect was answered and no spec came back")
	local hunter = ns.MeterSpec.Icon(SNEAKY, "HUNTER")
	check(hunter:find("Marksmanship", 1, true) ~= nil,
		("the inspected spec icon is %q, and 40 points are in Marksmanship"):format(hunter))
	check(inspecting == nil, "the inspect was never handed back")

	-- An inspect the client never answers. There is no event for one, so the
	-- only thing standing between a dropped request and a queue parked forever
	-- is the expiry. Asked for, never answered, and then the next member has to
	-- get a request of their own.
	ns.MeterSpec.Forget()
	inspecting = nil
	advance(10)
	check(ns.MeterSpec.Request(SNEAKY), "the first inspect did not go out")
	check(inspecting == "party1", "the first inspect went to the wrong unit")
	inspecting = nil
	advance(10)
	check(ns.MeterSpec.Request(FROST), "a dropped inspect parked the queue for good")
	check(inspecting == "party2",
		("the second inspect went to %s"):format(tostring(inspecting)))
	fire("INSPECT_READY", FROST)
	check(ns.MeterSpec.Known(FROST), "the second inspect was answered and nothing came back")

	----------------------------------------------------------------------
	-- Threat
	--
	-- The percentage is the client's. What is asserted here is the half that is
	-- not: that the rate of change is measured across a real interval and that
	-- the projection off it lands where the arithmetic says.
	----------------------------------------------------------------------

	local threatPct = { player = 100, party1 = 50, party2 = 10 }
	threatReader = function(source)
		local pct = threatPct[source]
		if not pct then
			return nil
		end
		return pct >= 100, 3, pct, pct, pct * 100
	end

	guids.target = "Creature-0-0000-000-boss"
	check(ns.MeterThreat.Ready(), "the threat probe says this client has no api")
	check(ns.MeterThreat.Watching(), "there is a mob targeted and nothing to measure against")

	ns.MeterThreat.Update() -- plants the reference, measures nothing
	local planted = ns.MeterThreat.Rank()
	check(#planted == 3, ("%d members have threat on it, expected 3"):format(#planted))
	check(planted[1].guid == BAUDIN and planted[1].tanking,
		"the member holding the mob is not top of the list")
	check(ns.MeterThreat.Soonest() == nil,
		"a projection came out of the very first sample, which has nothing to compare against")

	advance(1)
	threatPct.party1 = 70
	ns.MeterThreat.Update()

	local soonest, when = ns.MeterThreat.Soonest()
	check(soonest ~= nil and soonest.guid == SNEAKY,
		"the member climbing towards the pull was not the one picked out")
	-- Twenty points in a second, four tenths of it into the average, so eight
	-- points a second against the thirty that are left.
	check(when and math.abs(when - 3.75) < 0.01,
		("the projection says %s seconds, the arithmetic says 3.75"):format(tostring(when)))
	check(ns.MeterThreat.Tanking().guid == BAUDIN, "the wrong member is holding the mob")

	-- Falling threat is not a projection. Somebody who stopped is not on their
	-- way to taking anything.
	advance(1)
	threatPct.party1 = 40
	ns.MeterThreat.Update()
	advance(1)
	threatPct.party1 = 20
	ns.MeterThreat.Update()
	check(ns.MeterThreat.Soonest() == nil, "a member whose threat is falling was projected to pull")

	----------------------------------------------------------------------
	-- What ends up on the rows
	----------------------------------------------------------------------

	threatPct.party1 = 82
	ns.db.meterMode = "dps"
	meterTicker.scripts.OnUpdate(meterTicker, 0.25)

	check(damagePane.rows[1]:IsShown(), "the meter ticked and drew no rows")
	check(damagePane.rows[1].name:GetText() == "Sneakyman",
		("the top damage row says %q"):format(tostring(damagePane.rows[1].name:GetText())))
	check(threatPane.rows[1].value:GetText() == "100%",
		("the top threat row says %q"):format(tostring(threatPane.rows[1].value:GetText())))
	check(damagePane.left:GetText() == "DPS", "the damage header is not labelled")

	-- The bar behind the top row fills the pane and everything under it is
	-- shorter, which is the whole of what a bar says.
	local top = damagePane.rows[1].bar:GetWidth()
	check(top == ns.db.meterWidth,
		("the top bar is %.0f px across a %d px pane"):format(top, ns.db.meterWidth))

	-- One click on the header is the whole of the toggle.
	check(damagePane.button ~= nil, "the damage header is not clickable")
	damagePane.button.scripts.OnClick()
	check(ns.db.meterMode == "hps", "clicking the header did not swap to healing")
	meterTicker.scripts.OnUpdate(meterTicker, 0.25)
	check(damagePane.left:GetText() == "HPS", "the pane swapped and the header did not")
	check(damagePane.rows[1].name:GetText() == "Frostbite",
		("the healing pane is topped by %q"):format(tostring(damagePane.rows[1].name:GetText())))
	-- And the two who did damage and no healing are off the pane rather than
	-- sitting on it at zero.
	check(not damagePane.rows[2]:IsShown(),
		"a member who healed nothing kept their row when the pane swapped to healing")
	damagePane.button.scripts.OnClick()

	-- The projection reaching the header, name and all. Soonest is asserted on
	-- its own above; this is the other half, that what it works out gets drawn.
	advance(1)
	threatPct.party1 = 90
	ns.MeterThreat.Update()
	meterTicker.scripts.OnUpdate(meterTicker, 0.25)
	check(threatPane.right:GetText():find("Sneakyman", 1, true) ~= nil,
		("the header does not name the member converging on you: %q")
			:format(tostring(threatPane.right:GetText())))

	-- And back to quiet, which is the state the two exits below are about.
	advance(1)
	threatPct.party1 = 30
	ns.MeterThreat.Update()

	-- Losing the mob and getting it back. Both of the header's early exits leave
	-- by a different door from the one that draws a projection, so both have to
	-- forget what they last showed on the way out. While they did not, a target
	-- that came back to the same quiet state found the projection guard already
	-- satisfied and the header went on reading "no target" over a full list of
	-- rows underneath it.
	meterTicker.scripts.OnUpdate(meterTicker, 0.25)
	check(threatPane.right:GetText() == "held",
		("the threat header says %q with the mob held and nobody climbing")
			:format(tostring(threatPane.right:GetText())))

	guids.target = nil
	meterTicker.scripts.OnUpdate(meterTicker, 0.25)
	check(threatPane.right:GetText() == "no target",
		("the target went away and the header says %q")
			:format(tostring(threatPane.right:GetText())))

	guids.target = "Creature-0-0000-000-boss"
	meterTicker.scripts.OnUpdate(meterTicker, 0.25)
	check(threatPane.right:GetText() ~= "no target",
		"the target came back and the header was still reading no target")

	----------------------------------------------------------------------
	-- Allocation
	----------------------------------------------------------------------

	-- The clock moves inside the loop, which is the difference between this and
	-- the two churn gates above. A meter with the fight frozen allocates
	-- literally nothing, because every write in the file is guarded on a number
	-- and none of the numbers moved; measuring that would be measuring the
	-- guards and calling it the steady state. A fight is seconds ticking over
	-- and a DPS figure falling between them, so that is what is measured.
	local function meterChurn(n)
		collectgarbage("collect")
		collectgarbage("stop")
		local before = collectgarbage("count")
		for _ = 1, n do
			advance(0.05)
			meterTicker.scripts.OnUpdate(meterTicker, 0.05)
		end
		local after = collectgarbage("count")
		collectgarbage("restart")
		return (after - before) / (n / 50)
	end

	meterChurn(200)
	local meterKb = meterChurn(200)
	check(meterKb <= METER_CHURN_KB,
		("the meters allocate %.2f KB per 50 ticks, the gate is %.2f"):format(meterKb, METER_CHURN_KB))

	print(("meters %d rows, %.0f x %.0f px, %d damage and %d threat, %.2f KB per 50 ticks, gate is %.2f")
		:format(ns.db.meterRows, frame:GetWidth(), frame:GetHeight(),
			#ns.Meter.Rank("dps"), #ns.MeterThreat.Rank(), meterKb, METER_CHURN_KB))

	----------------------------------------------------------------------
	-- Put the client back the way the sections after this one expect it.
	----------------------------------------------------------------------

	threatReader = nil
	guids.player, guids.party1, guids.partypet1, guids.party2, guids.target = nil, nil, nil, nil, nil
	unitClass.player, unitClass.party1, unitClass.party2 = nil, nil, nil
	unitName.player, unitName.party1, unitName.party2 = nil, nil, nil
	realPlayers.party1, realPlayers.party2 = nil, nil
	inCombat.player, inCombat.party1 = nil, nil
	fire("GROUP_ROSTER_UPDATE")
end

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

--------------------------------------------------------------------------
-- Every anchor on the grid, in whole pixels
--
-- The grid makes one unit one physical pixel inside an adopted frame. That buys
-- exact sizes, and it buys nothing at all about position: an anchor offset is a
-- number a person typed, and half of an odd number is half a pixel. A frame
-- whose own origin sits half a pixel off a boundary has every edge, every glyph
-- and every icon inside it rasterised across two rows of pixels. It is not
-- subtle and it is invisible in review, because the arithmetic that produces it
-- looks like centring, which is what it is.
--
-- Three of them were live when this check was written, all in the enemy bars,
-- and all three had the reason for rounding written in a comment a few lines
-- above the line that did not round.
--
--   PLATE_BAR_HEIGHT / 2 + 1   11.5 pixels, on the widget itself, in the style
--                              that ships as the default. Every bar the addon
--                              had ever drawn was half a pixel low.
--   STRIPE_WIDTH * px / 2      2.5 pixels, on the level tag's number.
--   lineHeight / 2             half a pixel on the threat line at any odd
--                              debuff icon size.
--
-- Scope is every frame the addon put on the grid and everything under it, found
-- by walking up for the SetIgnoreParentScale that UI.Adopt calls. A frame that
-- is not on the grid is not held to this: the charge button rides UIParent's
-- scale, and Blizzard's own frames are Blizzard's business. UIParent itself is
-- skipped, because the stub sets the flag on it to model the client.
--------------------------------------------------------------------------

do
	local offenders, checked, adopted = 0, 0, 0
	local note = "at 1x"

	local function onGrid(frame)
		local node = frame
		while node and node ~= _G.UIParent do
			if node.ignoreScale then
				return true
			end
			node = node.parent
		end
		return false
	end

	local function whole(value)
		return math.abs(value - math.floor(value + 0.5)) < 1e-6
	end

	local seen = {}
	local walk
	function walk(region)
		if seen[region] then
			return
		end
		seen[region] = true

		-- A frame's own offsets are in its own units. A texture or a font string
		-- carries no scale and is measured in the frame holding it.
		local host = region
		if region.kind == "texture" or region.kind == "fontstring" then
			host = region.parent
		end

		if host and region.points and onGrid(host) then
			adopted = adopted + 1
			local px = ns.UI.Pixel(host)
			for _, point in ipairs(region.points) do
				checked = checked + 1
				local x, y = (point[4] or 0) / px, (point[5] or 0) / px
				if not whole(x) or not whole(y) then
					offenders = offenders + 1
					check(false, ("%s: a %s anchored %s to %s sits at %.3f, %.3f pixels")
						:format(note, region.kind, tostring(point[1]), tostring(point[3]), x, y))
				end
			end
		end

		for _, kid in ipairs(region.regions) do
			walk(kid)
		end
		for _, kid in ipairs(region.children) do
			walk(kid)
		end
	end

	local function sweep(where)
		checked, adopted, offenders = 0, 0, 0
		seen = {}
		note = where
		walk(_G.UIParent)
		check(adopted > 0, where .. ": nothing on the grid carried an anchor")
		return checked, adopted, offenders
	end

	local one, regions, bad = sweep("at 1x")

	-- And again at each whole zoom, because zoom scales every design number and
	-- a size that was even at 1x is not obliged to stay whole once it has been
	-- through a multiply. This is the sweep that would catch the bars going half
	-- a pixel out at 2x, which nothing else here looks at.
	local shipped = ns.db.barsZoom
	for _, zoom in ipairs{2, 3} do
		ns.db.barsZoom = zoom
		ns.EnemyBars.ApplyLayout()
		ns.EnemyBars.Rebuild()
		local _, _, off = sweep(("at %dx"):format(zoom))
		bad = bad + off
	end
	ns.db.barsZoom = shipped
	ns.EnemyBars.ApplyLayout()
	ns.EnemyBars.Rebuild()
	sweep("back at 1x")

	print(("anchors %d offsets across %d regions on the grid, at 1x, 2x and 3x, %d off a whole pixel")
		:format(one, regions, bad))
end

if failures > 0 then
	print(("harness: %d failed"):format(failures))
	os.exit(1)
end
print("harness: ok")
