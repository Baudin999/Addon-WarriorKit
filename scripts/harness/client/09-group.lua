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

-- The raid roster row, which is the one place outside a header that answers
-- what group somebody is in. Three of its eleven return values are filled,
-- because three is what the addon reads and a fixture that invented the other
-- eight would be inventing answers nothing checks.
_G.GetRaidRosterInfo = function(index)
	local token = inRaid and tokens[index]
	local entry = token and members[token]
	if not entry then
		return nil
	end
	return entry.name, entry.rank or 0, entry.subgroup or 1
end

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

-- Which way columnSpacing pushes the block that opens a new column, which is
-- the direction columnAnchorPoint names. The client works these out of
-- getRelativePointAnchor and applies them to both axes; the fixture had them
-- written into the x argument, which is right for a grid whose columns run
-- across and silently wrong for one whose rows stack down.
local COLUMN_STEP = {
	LEFT = { 1, 0 }, RIGHT = { -1, 0 }, TOP = { 0, -1 }, BOTTOM = { 0, 1 },
}

-- Where the first block of a column goes, which is the one piece of this model
-- the client and the addon disagreed about for a whole release.
--
-- SecureGroupHeaders anchors block one at the header's own growth point, TOP to
-- TOP, so the first column is centred across the header rather than sitting at
-- its left edge, and every column after it is hung off the right of the column
-- before. A raid three columns wide therefore paints a block and a half further
-- right than the box the header sized itself to, and this file used to model the
-- tidier arrangement instead: one corner, TOPLEFT to TOPLEFT. That is the shape
-- of mistake the note at the top of this file warns about. It made a two column
-- list centred in the model and half a block right of the anchor in the game.

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

-- Every child placed, the way SecureGroupHeaders places them: block one against
-- the header's growth point, each one under it against the opposite edge of the
-- block above at xOffset and yOffset, and the block that opens a new column
-- against the far edge of the block that opened the last one.
local function Arrange(header, shown, per, wide, tall)
	local point = header:GetAttribute("point") or "TOP"
	local side = header:GetAttribute("columnAnchorPoint") or "LEFT"
	local spacing = header:GetAttribute("columnSpacing") or 0
	local columns = 0
	local start

	for index = 1, #shown do
		local button = header.buttons[index]
		local column, row = math.floor((index - 1) / per), (index - 1) % per
		columns = math.max(columns, column + 1)
		-- No clear before the write, because the client does not do one. A
		-- point replaces the point of the same name and sits beside a point of
		-- any other, so a list arranged down the screen and then across leaves
		-- every tile pinned by two corners and standing in a staircase. This
		-- file used to clear, which is the tidier arrangement and the one that
		-- made a party frame with a stale anchor pass every check in the suite.
		-- The clear the client does do is on the children it stops showing, and
		-- that is in Update below.
		if index == 1 then
			button:SetPoint(point, header, point, 0, 0)
			start = button
		elseif row == 0 then
			local step = COLUMN_STEP[side] or COLUMN_STEP.LEFT
			button:SetPoint(side, start, OPPOSITE[side],
				spacing * step[1], spacing * step[2])
			start = button
		else
			button:SetPoint(point, header.buttons[index - 1], OPPOSITE[point],
				header:GetAttribute("xOffset") or 0, header:GetAttribute("yOffset") or 0)
		end
	end

	-- The header sized to the block it has just arranged. UnitFrames/Group.lua
	-- reads none of this any more, and that is the point of keeping it right: the
	-- box the header gives itself is not the box the blocks fill once there is a
	-- second column, and a model that quietly made the two agree is what hid the
	-- offset in the first place.
	--
	-- Nobody to place is a header the client gives one block's width and no
	-- height at all, out of minWidth and minHeight falling to the multipliers of
	-- a column that runs down the screen. Nothing is shown at that size, so what
	-- it buys is a model that does not quietly answer a whole block where the
	-- game answers a tenth of a pixel.
	-- The header's own box, along the axis the members run and the axis the
	-- columns stack, which are not always x and y: a header whose point is LEFT
	-- runs its members across and stacks its columns down, and a fixture that
	-- wrote the run into the width would answer a rectangle the client never
	-- gives.
	local run = math.min(#shown, per)
	local down = (point == "TOP" or point == "BOTTOM")
	local gap = math.abs((down and header:GetAttribute("yOffset")
		or header:GetAttribute("xOffset")) or 0)
	if run > 0 then
		local along = run * (down and tall or wide) + (run - 1) * gap
		local stack = columns * (down and wide or tall) + (columns - 1) * spacing
		header:SetSize(down and stack or along, down and along or stack)
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
		-- The one clear the client does: a child it has stopped showing loses
		-- its anchors and its unit, so somebody who leaves and comes back is
		-- anchored from nothing rather than from what they had last time.
		header.buttons[index]:ClearAllPoints()
		header.buttons[index]:SetAttribute("unit", nil)
	end

	Arrange(header, shown, per, header.buttons[1] and header.buttons[1]:GetWidth() or 1,
		header.buttons[1] and header.buttons[1]:GetHeight() or 1)
	header.shownUnits = shown
end

-- The template as FrameXML declares it: hidden, and deaf while it is.
--
-- SecureGroupHeaderTemplate carries hidden="true", and both of the doors into
-- SecureGroupHeader_Update that an addon reaches, the attribute write and the
-- roster event, ask IsVisible first. OnShow is the third and is the one that
-- opens the other two. A fixture that updated a hidden header let the party
-- pass every assertion here and draw nothing in the game, which is exactly the
-- bug it was meant to catch, so the flag and the gate are both modelled.
local function Header(header)
	header.buttons = {}
	header.shownUnits = {}
	header.shown = false
	header.scripts.OnShow = Update
	local write = header.SetAttribute
	header.SetAttribute = function(self, name, value)
		write(self, name, value)
		if self:IsVisible() then
			Update(self)
		end
	end
	header.wkUpdate = Update
end

local made = _G.CreateFrame
_G.CreateFrame = function(kind, name, parent, template)
	-- The template goes through, not just past: the client underneath reads it
	-- to decide whether a button's click has a secure half, and a wrapper that
	-- swallowed it turned every secure button in the addon into a plain one.
	local frame = made(kind, name, parent, template)
	if template == "SecureGroupHeaderTemplate" then
		Header(frame)
	end
	return frame
end

H.group = { Set = Set, Forget = Forget, members = members, tokens = tokens,
	byName = byName, Update = Update }
