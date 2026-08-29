-- A party, a raid, and the secure group header that draws one
--
-- The stub had no group at all: no party or raid tokens, no
-- UnitGroupRolesAssigned, no GetPartyAssignment, no UnitInRange and no
-- templates of any kind. UnitFrames/Group.lua is a header and an order, so all
-- of that has to exist before a single assertion about it can run.
--
-- Three parts, and the order they are in is the dependency order.
--
--   The roster. One record per member, written by a section and read by every
--   unit call below. Health, power, range and whether they are dead are per
--   member here, where the shipped client answers one constant for everybody,
--   because a fixture that gave every member the same reading could not tell a
--   block drawing its own member from a block drawing the first one four times.
--
--   The unit calls, layered over what 03-player.lua and 06-log.lua already
--   installed. A token this file knows about is answered from its record and
--   everything else falls through, so every section above this one sees exactly
--   what it saw before.
--
--   The header. SecureGroupHeaderTemplate is FrameXML's, so CreateFrame is
--   wrapped: a frame asked for with that template comes back doing the three
--   things the addon leans on. It holds attributes, it makes one child per
--   member and points each at a unit, and it runs the initialConfigFunction on
--   a child the first time it makes it.
--
-- What this cannot prove is that the game agrees. The real header's ordering,
-- its column arithmetic and its restricted environment are modelled from the
-- contract, and a model that is wrong is a test that passes and a client that
-- does not.

local H = ...
local guids, unitClass, unitName = H.guids, H.unitClass, H.unitName
local realPlayers, chat, unitAlias = H.realPlayers, H.chat, H.unitAlias
local child = H.child

-- token -> the member's record. Every field is optional except name and class:
--
--   name, class, guid   what the client answers about them
--   you                 this record is the player, whatever token it is under
--   subgroup            the raid group they are in, for `party order group`
--   health, healthMax   the gauge
--   power, powerMax     the rail, and a maximum of zero is a member with none
--   powerType           the number Color.power is keyed by
--   assigned            what UnitGroupRolesAssigned answers about them
--   maintank            what GetPartyAssignment("MAINTANK") answers
--   range, connected    false for a member you cannot reach or who has gone
--   dead, ghost         the two states that stop a reading being taken
local members = {}

-- The tokens the group is made of, in the order the client hands them over.
-- The player's second name is deliberately not in here: in a raid they are
-- reachable as raid1 and as player, and a list carrying both would place them
-- twice.
local tokens = {}
local byName = {}
local inRaid = false

local base = {
	health = _G.UnitHealth, healthMax = _G.UnitHealthMax,
	power = _G.UnitPower, powerMax = _G.UnitPowerMax,
	powerType = _G.UnitPowerType, dead = _G.UnitIsDeadOrGhost,
}

--------------------------------------------------------------------------
-- The roster
--------------------------------------------------------------------------

local function Install(token, entry)
	members[token] = entry
	guids[token] = entry.guid or ("Player-" .. token)
	unitName[token] = entry.name
	unitClass[token] = entry.class
	realPlayers[token] = true
	byName[entry.name] = token
end

local function Forget()
	for token in pairs(members) do
		guids[token], unitName[token], unitClass[token] = nil, nil, nil
		realPlayers[token] = nil
		unitAlias[token] = nil
	end
	wipe(members)
	wipe(byName)
	for index = #tokens, 1, -1 do
		tokens[index] = nil
	end
	inRaid = false
	chat.groupSize = 0
end

-- The group, as a section sets it. Tokens are party1 upward or raid1 upward
-- unless a record names its own, which is how the player takes the "player"
-- token in a party and a raid token in a raid.
local function Set(list, raid)
	Forget()
	inRaid = raid and true or false
	for index, entry in ipairs(list) do
		local token = entry.token or (inRaid and ("raid" .. index) or ("party" .. index))
		Install(token, entry)
		tokens[#tokens + 1] = token
		if entry.you and token ~= "player" then
			-- Reachable under both names, and UnitIsUnit has to agree, because
			-- Unit/Roster.lua walks the raid tokens and skips the one that is
			-- you by asking exactly that.
			members.player = entry
			guids.player, unitName.player = guids[token], entry.name
			unitClass.player, realPlayers.player = entry.class, true
			unitAlias[token] = { player = true }
			unitAlias.player = { [token] = true }
		end
	end
	chat.groupSize = #tokens
end

--------------------------------------------------------------------------
-- The unit calls
--------------------------------------------------------------------------

_G.IsInRaid = function() return inRaid end

_G.UnitHealth = function(unit)
	local entry = members[unit]
	return entry and (entry.health or 0) or base.health(unit)
end

_G.UnitHealthMax = function(unit)
	local entry = members[unit]
	return entry and (entry.healthMax or 0) or base.healthMax(unit)
end

_G.UnitPower = function(unit)
	local entry = members[unit]
	return entry and (entry.power or 0) or base.power(unit)
end

_G.UnitPowerMax = function(unit)
	local entry = members[unit]
	return entry and (entry.powerMax or 0) or base.powerMax(unit)
end

_G.UnitPowerType = function(unit)
	local entry = members[unit]
	return entry and (entry.powerType or 0) or base.powerType(unit)
end

-- Two returns, the way the client answers: whether they are in range, and
-- whether it was able to tell. A unit this file knows nothing about comes back
-- unchecked, which is the answer for anyone who is not in your group.
_G.UnitInRange = function(unit)
	local entry = members[unit]
	if not entry then
		return true, false
	end
	return entry.range ~= false, true
end

_G.UnitIsConnected = function(unit)
	local entry = members[unit]
	return not entry or entry.connected ~= false
end

_G.UnitIsGhost = function(unit)
	local entry = members[unit]
	return (entry and entry.ghost) and true or false
end

_G.UnitIsDeadOrGhost = function(unit)
	local entry = members[unit]
	if not entry then
		return base.dead(unit)
	end
	return (entry.dead or entry.ghost) and true or false
end

-- NONE for everybody who has not been given one, which is what Era answers all
-- day and is a different thing from the call being missing.
_G.UnitGroupRolesAssigned = function(unit)
	local entry = members[unit]
	return (entry and entry.assigned) or "NONE"
end

_G.GetPartyAssignment = function(what, unit)
	local entry = members[unit]
	return (what == "MAINTANK" and entry and entry.maintank) and true or false
end

--------------------------------------------------------------------------
-- The header
--------------------------------------------------------------------------

local OPPOSITE = { TOP = "BOTTOM", BOTTOM = "TOP", LEFT = "RIGHT", RIGHT = "LEFT" }

-- The corner the first block of a column sits in, which is the growth direction
-- and the column direction said as one word. The client writes it as two anchors
-- on the same button and this model keeps one per frame, so the pair is folded
-- into the corner they meet at. It reads the same for one column and it is only
-- a raid that tells them apart: with a single anchor at TOP a column would be
-- centred across a header three columns wide instead of starting at its left
-- edge.
local CORNER = {
	TOP = { LEFT = "TOPLEFT", RIGHT = "TOPRIGHT" },
	BOTTOM = { LEFT = "BOTTOMLEFT", RIGHT = "BOTTOMRIGHT" },
}

-- The initialConfigFunction, run the way the restricted environment runs it:
-- once per child, the first time the header makes it, with `self` bound to the
-- new button. A sandbox is not modelled, because what is being tested is that
-- the addon wrote a snippet that does the right thing, not that the client
-- refuses a snippet that does the wrong one.
local function Configure(header, button)
	local code = header:GetAttribute("initialConfigFunction")
	if not code then
		return
	end
	local chunk = loadstring("local self = ...\n" .. code)
	if chunk then
		chunk(button)
	end
end

-- Who the header would show, in the order it would show them.
local function Listed(header, into)
	if header:GetAttribute("sortMethod") == "NAMELIST" then
		for name in (header:GetAttribute("nameList") or ""):gmatch("[^,]+") do
			if byName[name] then
				into[#into + 1] = byName[name]
			end
		end
		return into
	end

	local rank, show = {}, header:GetAttribute("showPlayer")
	for index, token in ipairs(tokens) do
		rank[token] = index
		if show or not members[token].you then
			into[#into + 1] = token
		end
	end
	table.sort(into, function(a, b)
		local first, second = members[a].subgroup or 1, members[b].subgroup or 1
		if first ~= second then
			return first < second
		end
		return rank[a] < rank[b]
	end)
	return into
end

-- Every child placed, the way SecureGroupHeaders places them: the first of a
-- column against the header itself, and each one after it against the opposite
-- edge of the child above, at xOffset and yOffset.
local function Arrange(header, shown, per, wide, tall)
	local point = header:GetAttribute("point") or "TOP"
	local side = header:GetAttribute("columnAnchorPoint") or "LEFT"
	local spacing = header:GetAttribute("columnSpacing") or 0
	local corner = CORNER[point][side]
	local columns = 0

	for index = 1, #shown do
		local button = header.buttons[index]
		local column, row = math.floor((index - 1) / per), (index - 1) % per
		columns = math.max(columns, column + 1)
		button:ClearAllPoints()
		if row == 0 then
			button:SetPoint(corner, header, corner, column * (wide + spacing), 0)
		else
			button:SetPoint(point, header.buttons[index - 1], OPPOSITE[point],
				header:GetAttribute("xOffset") or 0, header:GetAttribute("yOffset") or 0)
		end
	end

	-- The header sized to the block it has just arranged, which is the half of
	-- the contract UnitFrames/Group.lua places the list by: the header is
	-- centred on the anchor and takes its own size from the buttons, so this
	-- arithmetic is what decides whether the list fills outward from the middle.
	--
	-- Nobody to place is a header the client gives one block's width and no
	-- height at all, out of minWidth and minHeight falling to the multipliers of
	-- a column that runs down the screen. Nothing is shown at that size, so what
	-- it buys is a model that does not quietly answer a whole block where the
	-- game answers a tenth of a pixel.
	local rows = math.min(#shown, per)
	local gap = math.abs(header:GetAttribute("yOffset") or 0)
	if rows > 0 then
		header:SetSize(columns * wide + (columns - 1) * spacing,
			rows * tall + (rows - 1) * gap)
	else
		header:SetSize(wide, 0.1)
	end
end

-- What the real header does on every attribute change, and what it refuses to
-- do in combat. The refusal is the half that matters here: the addon's whole
-- claim to a fixed slot order rests on nothing moving mid pull, and half of
-- that is this file's behaviour rather than the addon's.
local function Update(header)
	if _G.InCombatLockdown() then
		header.dirty = true
		return
	end
	header.dirty = false

	local shown = {}
	local key = inRaid and "showRaid" or "showParty"
	if next(members) and header:GetAttribute(key) then
		Listed(header, shown)
	end

	local per = header:GetAttribute("unitsPerColumn") or math.max(#shown, 1)
	local cap = per * (header:GetAttribute("maxColumns") or 1)
	while #shown > cap do
		shown[#shown] = nil
	end

	for index = 1, #shown do
		local button = header.buttons[index]
		if not button then
			button = child("button", header, nil)
			header.buttons[index] = button
			Configure(header, button)
		end
		button:SetAttribute("unit", shown[index])
		button:Show()
	end
	for index = #shown + 1, #header.buttons do
		header.buttons[index]:Hide()
	end

	Arrange(header, shown, per, header.buttons[1] and header.buttons[1]:GetWidth() or 1,
		header.buttons[1] and header.buttons[1]:GetHeight() or 1)
	header.shownUnits = shown
end

local function Header(header)
	header.buttons = {}
	header.shownUnits = {}
	local write = header.SetAttribute
	header.SetAttribute = function(self, name, value)
		write(self, name, value)
		Update(self)
	end
	header.wkUpdate = Update
end

local made = _G.CreateFrame
_G.CreateFrame = function(kind, name, parent, template)
	local frame = made(kind, name, parent)
	if template == "SecureGroupHeaderTemplate" then
		Header(frame)
	end
	return frame
end

H.group = { Set = Set, Forget = Forget, members = members, tokens = tokens,
	byName = byName, Update = Update }
