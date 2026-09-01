local ADDON, ns = ...

local Group = {}
ns.Group = Group

--------------------------------------------------------------------------
-- The party and the raid
--
-- Our own frames, built from SecureGroupHeaderTemplate, rather than Blizzard's
-- frames wearing our skin.
--
-- UnitFrames/Skin.lua skins the player, target and target of target because
-- those three carry targeting, the dropdown and a cast bar, and a frame drawn
-- from scratch would have to earn all of that back. That argument does not
-- carry over. PartyMemberFrame1 is bound to party1 in XML and there is no
-- supported way to point it at anyone else, so the moment the order is decided
-- by role rather than by party index, the client's frames cannot draw it. The
-- raid is worse: CompactRaidFrameContainer runs its own layout pass and puts
-- back whatever an addon moves.
--
-- SecureGroupHeaderTemplate is the answer the client already ships. It makes
-- one secure unit button per member, watches each one, and shows and hides them
-- itself as the roster changes. Every attribute that decides the shape of the
-- list is written out of combat and the header does the rest.
--
-- Two lists, not one
--
-- A party and a raid are two things you place, size and read differently, and
-- this file shipped once with one header serving both. That was wrong in the
-- way that costs an afternoon: one place on the screen, one block size, one set
-- of columns and one handle, so a party wide enough to read health off was a
-- raid that ran past the edge of the monitor, and there was no way to put the
-- two of them in different places because there was only ever one of them.
--
-- So everything below takes a list as its first argument, and there are two:
-- the party, four or five blocks in a line, and the raid, a grid of columns
-- with the group number over each one. Each has its own header, its own place
-- on the screen, its own sizes and its own preview. The header attributes are
-- what keep them out of each other's way: the party shows in a party and never
-- in a raid, the raid shows in a raid and never in a party, so at most one of
-- them is ever drawing.
--
-- Three things follow from the header being secure, and they are most of this
-- file:
--
--   Every attribute write is refused in combat and retried at
--   PLAYER_REGEN_ENABLED, which is the pattern Charge/Icon.lua and
--   Buttons/Bars.lua already carry.
--
--   A button the header has just made cannot be laid out until combat drops,
--   because it is protected. That costs nothing in practice: the header defers
--   its own update in lockdown too, so there is no new button to lay out until
--   the fight ends either.
--
--   The size of one button has to be written from inside the header's own
--   restricted environment, because the header reads it while placing the
--   column. That is initialConfigFunction, and it is the only snippet in this
--   file. It sets a size and two attributes and nothing else, so it needs
--   nothing from the restricted whitelist that is in any doubt.
--
-- The party's order is tanks, then healers, then damage, and by name inside a
-- band. By name is arbitrary as an ordering and it is the only one that is
-- stable: the same five people produce the same five slots in every group they
-- are ever in together, whoever formed it and whoever zoned in first. Party
-- index does not do that, and sorting by class does not either, because a class
-- can be two roles. The raid runs the same bands or the raid's own group
-- numbers, which is what somebody with assignments per group wants.
--
-- It is recomputed out of combat and nowhere else, which is what makes fixed
-- placing true rather than aspirational. An inspect that resolves mid pull is
-- recorded by Unit/Role.lua and changes nothing on the screen until the fight
-- ends.
--------------------------------------------------------------------------

local Member = ns.GroupMember
local Role = ns.Unit.Role
local Roster = ns.Unit.Roster

-- The rate every readout in this addon runs at.
local POLL = 0.2

-- What a block is allowed to be, shared with the panel and the slash words so
-- all three clamp to the same numbers. The floor is under the skin's, because a
-- raid cell is not a player block: forty of those is a monitor.
local WIDTH_LOW, WIDTH_HIGH = 60, 360
local HEIGHT_LOW, HEIGHT_HIGH = 14, 72
local GAP_LOW, GAP_HIGH = 0, 20
local COLUMNS_LOW, COLUMNS_HIGH = 1, 8
local PER_COLUMN_LOW, PER_COLUMN_HIGH = 1, 40

-- The raid's own groups, in order, for a raid ordered by group. A string
-- because that is what the header takes, and written out rather than built,
-- because it is eight characters and a loop that produced them would be a loop
-- to read.
local GROUPS = "1,2,3,4,5,6,7,8"
local MAX_GROUPS = 8

-- The most a raid holds, whatever the column settings multiply out to.
local RAID = 40

-- The most a party holds, which is not a setting for the reason the raid's
-- columns are one: five people cannot fill a grid.
local PARTY_SLOTS = 5

-- What the header runs on each button it makes, inside its own restricted
-- environment. Three calls, all of them on the plainest part of the whitelist.
--
-- The size has to be here rather than written afterwards from Lua: the header
-- reads a child's width and height while it is placing the column, so a button
-- sized one frame later is a column that overlapped for one frame. Everything
-- else about the button is done out of combat by Adopt below, which is the
-- half that can call into this addon at all.
local CONFIG = [[
	self:SetWidth(%d)
	self:SetHeight(%d)
	self:SetAttribute("*type1", "target")
	self:SetAttribute("*type2", "togglemenu")
]]

--------------------------------------------------------------------------
-- The two lists
--
-- Everything that differs between them is here: which settings they read, what
-- their frames are called, and which of the client's two group shapes they are
-- for. Nothing below this asks which list it has except where the answer is the
-- whole point, and those places say so.
--
-- The settings are named rather than prefixed, because a prefix is a rule you
-- have to remember and a table is one the file enforces. `mine` is whether your
-- own block is in the list: off in a party, where Skin.lua already draws you,
-- and on in a raid, where a grid missing exactly one person is a grid you have
-- to count along.
--------------------------------------------------------------------------

local PARTY = {
	name = "party",
	title = "WarriorKit party",
	frameName = "WarriorKitParty",
	headerName = "WarriorKitPartyHeader",
	raid = false,
	keys = {
		on = "party", point = "partyMiddle", width = "partyWidth",
		height = "partyHeight", gap = "partyGap", grow = "partyGrow",
		zoom = "partyZoom", icons = "partyRoleIcon", range = "partyRange",
		mine = "partySelf",
	},
	members = {}, adopted = {}, ghosts = {}, headings = {},
	names = {}, bands = {},
}

local RAID_LIST = {
	name = "raid",
	title = "WarriorKit raid",
	frameName = "WarriorKitRaid",
	headerName = "WarriorKitRaidHeader",
	raid = true,
	keys = {
		on = "raid", point = "raidMiddle", width = "raidWidth",
		height = "raidHeight", gap = "raidGap", grow = "raidGrow",
		zoom = "raidZoom", icons = "raidRoleIcon", range = "raidRange",
		mine = "raidSelf", columns = "raidColumns", per = "raidPerColumn",
		order = "raidOrder", headings = "raidHeadings",
	},
	members = {}, adopted = {}, ghosts = {}, headings = {},
	names = {}, bands = {},
}

local lists = { PARTY, RAID_LIST }

-- One setting of one list. Every read in this file goes through it, so a list
-- cannot reach into the other one's numbers by accident.
local function S(list, key)
	return ns.db[list.keys[key]]
end

local function Which(name)
	return name == "raid" and RAID_LIST or PARTY
end

-- What to do with a button the first time it is seen, registered from
-- UnitFrames/Feature.lua. It exists for ctrl-click marking: Marking/Marking.lua
-- hooks frames by name and PartyMemberFrame1 through 4 are on that list, so
-- hiding them takes marking on a party member off the screen with them. A
-- behaviour file may not name a file outside its own folder, and Feature.lua is
-- where that rule puts the call.
local watchers = {}

-- Which list's bands the comparator is reading. A module local rather than an
-- argument, because table.sort takes two values and nothing else, and a
-- comparator written at the call site to close over the list would be a closure
-- per rebuild.
local sorting

-- What one block is drawn from, filled once per pass and handed to every member
-- with only the role changed between them. UnitFrames/Member.lua reads no
-- setting of its own and this table is the whole of what it is told; one table
-- reused rather than one per member, because a raid relayout is forty of them.
local look = { width = 0, height = 0, role = nil, icons = true, range = true }

local Whole = ns.UI.Whole
local UnitName = UnitName
local UnitIsUnit = UnitIsUnit

--------------------------------------------------------------------------
-- The order
--------------------------------------------------------------------------

local function ByBand(a, b)
	if sorting[a] ~= sorting[b] then
		return sorting[a] < sorting[b]
	end
	return a < b
end

-- Who is in the list and in what order. Off ns.Unit.Roster rather than off the
-- party tokens, because that file already keeps the group by event and the
-- enemy bars were walking the raid on a ticker to get the same answer.
local function Order(list)
	local names, bands = list.names, list.bands
	wipe(bands)
	for index = #names, 1, -1 do
		names[index] = nil
	end
	sorting = bands

	local units = Roster.Units()
	for index = 1, #units do
		local unit = units[index]
		local name = UnitName(unit)
		if name and (S(list, "mine") or not UnitIsUnit(unit, "player")) then
			names[#names + 1] = name
			bands[name] = Role.Band(Role.Of(unit))
		end
	end
	table.sort(names, ByBand)
	return names
end

-- The slot order as that list's header was last told it. For the panel, for a
-- macro and for the harness, which drives Group.Rebuild and then reads this.
--
-- One per list rather than one shared, which is not a nicety: a raid ordered by
-- group has no name list and empties its own, and while the two shared a table
-- that emptied the party's order on every pass through a rebuild the raid was
-- not even drawing for.
function Group.Order(which)
	return Which(which).names
end

--------------------------------------------------------------------------
-- The attributes
--------------------------------------------------------------------------

-- Whether this list is running the raid's own group numbers. Only the raid can:
-- the group number of a party is 1 for everyone in it, so grouping by it is a
-- list in the order the client hands the units over, which is the thing the
-- whole part exists to stop.
local function ByGroupNumber(list)
	return list.raid and S(list, "order") == "group" and true or false
end

-- Whether the list runs across the screen rather than down it. A party is four
-- or five blocks and reads either way round; a raid is a grid, and its columns
-- are already the way across.
local function Across(list)
	local grow = S(list, "grow")
	return not list.raid and (grow == "right" or grow == "left")
end

local function Sorting(list)
	local header = list.header
	if ByGroupNumber(list) then
		-- The order is dropped as well as unused. It is handed out by
		-- Group.Order and the panel prints it, and a role order left lying about
		-- while the header is running group numbers is a readout that says the
		-- opposite of what is on the screen.
		for index = #list.names, 1, -1 do
			list.names[index] = nil
		end
		header:SetAttribute("nameList", nil)
		header:SetAttribute("groupBy", "GROUP")
		header:SetAttribute("groupingOrder", GROUPS)
		header:SetAttribute("sortMethod", "INDEX")
		return
	end
	header:SetAttribute("groupBy", nil)
	header:SetAttribute("groupingOrder", nil)
	header:SetAttribute("sortMethod", "NAMELIST")
	header:SetAttribute("nameList", table.concat(Order(list), ","))
end

-- Which growth point the header hangs its first block off, which is the edge
-- the whole list is anchored by below.
local function Edge(list)
	local grow = S(list, "grow")
	if Across(list) then
		return grow == "left" and "RIGHT" or "LEFT"
	end
	return grow == "up" and "BOTTOM" or "TOP"
end

-- Every attribute that decides the shape of one list, written in one pass.
-- False where combat refused, which the retry at PLAYER_REGEN_ENABLED picks up.
local function Secure(list)
	if InCombatLockdown() then
		return false
	end

	local header = list.header
	local wide, tall = S(list, "width"), S(list, "height")
	local gap, on = S(list, "gap"), S(list, "on")
	local across, grow = Across(list), S(list, "grow")

	header:SetAttribute("template", "SecureUnitButtonTemplate")
	header:SetAttribute("initialConfigFunction", CONFIG:format(tall + wide, tall))

	-- The whole of what keeps two lists off one screen. Solo is never on: a
	-- list of one is the player block the skin already draws.
	header:SetAttribute("showParty", on and not list.raid)
	header:SetAttribute("showRaid", on and list.raid)
	header:SetAttribute("showSolo", false)
	header:SetAttribute("showPlayer", S(list, "mine"))

	header:SetAttribute("point", Edge(list))
	header:SetAttribute("xOffset", across and (grow == "left" and -gap or gap) or 0)
	header:SetAttribute("yOffset", across and 0 or (grow == "up" and gap or -gap))
	header:SetAttribute("columnAnchorPoint", "LEFT")
	header:SetAttribute("columnSpacing", gap)
	-- A party's columns are not a setting: five people cannot fill a grid, and a
	-- party that wrapped would be a party whose slots moved when the fifth
	-- person joined.
	header:SetAttribute("maxColumns", list.raid and S(list, "columns") or 1)
	header:SetAttribute("unitsPerColumn", list.raid and S(list, "per") or PARTY_SLOTS)

	Sorting(list)
	return true
end

--------------------------------------------------------------------------
-- The buttons
--------------------------------------------------------------------------

-- One button, taken over the first time it is seen.
--
-- RegisterForClicks is out here rather than in the snippet because it is the
-- one call of the four that is not obviously on the restricted whitelist, and
-- it does not have to be in there: a button the header made in combat has
-- nothing to lay out until combat drops anyway.
local function Take(list, button)
	list.adopted[button] = true
	list.members[#list.members + 1] = button
	button:RegisterForClicks("AnyUp")
	Member.Build(button)
	for index = 1, #watchers do
		watchers[index](button)
	end
end

-- Every child of a header, built out and laid out. False where combat refused
-- one of them.
--
-- A table per pass, which is allowed here: this runs on a roster change, on a
-- setting change and on nothing else. Every child of the header is a member
-- button, because the drag handle and the label are children of the anchor
-- rather than of the header.
local function Adopt(list)
	look.width, look.height = S(list, "width"), S(list, "height")
	look.icons, look.range = S(list, "icons"), S(list, "range")

	local complete = true
	for _, button in ipairs({ list.header:GetChildren() }) do
		if not list.adopted[button] then
			Take(list, button)
		end
		if ns.Blocked(button) then
			complete = false
		else
			look.role = Role.Of(button:GetAttribute("unit"))
			Member.Place(button, look)
		end
	end
	return complete
end

-- The header laid out again, after the buttons have been given their sizes.
--
-- A header places a column by reading each child's width and height, and a
-- button that existed before a size setting moved is still carrying the size
-- the snippet gave it when the header made it. Adopt writes the new one, which
-- is one pass after the arrangement that used the old one.
--
-- Any attribute write makes the header arrange again, whether or not the value
-- changed, so this writes the one it has just written. There is no relayout to
-- ask a header for, and this is what the shape of that template leaves.
local function Nudge(list)
	list.header:SetAttribute("point", Edge(list))
end

--------------------------------------------------------------------------
-- How big the list is
--------------------------------------------------------------------------

-- How many blocks a header is about to show.
--
-- Off the roster rather than off the buttons on the screen. A count of what is
-- drawn is the wrong question at the moment the layout is decided: the header
-- updates itself off the same GROUP_ROSTER_UPDATE this file does, so the pass
-- that places the list runs before the buttons for the people in it exist. At
-- login, in a party, that count is zero and the list is laid out as a list of
-- nothing.
--
-- Nothing at all for the list that is not the group you are in, which is what
-- the header's own two switches are already saying and what keeps an empty
-- raid grid from reserving a rectangle over your party.
--
-- Capped where the header caps itself, because a raid past
-- maxColumns * unitsPerColumn is a header that shows the first of it and drops
-- the rest, and the list to place is the one that gets drawn.
local function Expected(list)
	if not S(list, "on") or list.raid ~= (IsInRaid() and true or false) then
		return 0
	end
	-- Solo is never shown: showSolo is false, and a roster of one is you.
	local units = Roster.Units()
	if #units < 2 then
		return 0
	end
	local shown = S(list, "mine") and #units or #units - 1
	if not list.raid then
		return math.min(shown, PARTY_SLOTS)
	end
	return math.min(shown, S(list, "columns") * S(list, "per"))
end

-- How many blocks the preview stands, which is a full one of whatever this list
-- is for.
local function Full(list)
	if list.raid then
		return math.min(S(list, "columns") * S(list, "per"), RAID)
	end
	return S(list, "mine") and PARTY_SLOTS or PARTY_SLOTS - 1
end

-- How many columns wide and how many rows deep a list of that many blocks is
-- arranged, and how far it reaches each way. The header's own arithmetic, done
-- here: a party across the screen is one block deep and as long as it is, a
-- party down it is the other way about, and a raid is the grid its two numbers
-- describe.
local function Extent(list, shown)
	shown = math.max(shown, 1)
	local columns, rows = 1, shown
	if Across(list) then
		columns, rows = shown, 1
	elseif list.raid then
		local per = math.max(S(list, "per"), 1)
		if shown > per then
			columns, rows = math.min(math.ceil(shown / per), S(list, "columns")), per
		end
	end

	local gap = S(list, "gap")
	local block = S(list, "height") + S(list, "width")
	return columns, rows,
		columns * block + (columns - 1) * gap,
		rows * S(list, "height") + (rows - 1) * gap
end

--------------------------------------------------------------------------
-- The group headings
--
-- One label over each column of a raid, which is the difference between a grid
-- you can find somebody in and forty rectangles. Only where the columns are
-- groups, which is a raid ordered by group number: in role order a column is
-- five people who happened to follow each other down the list.
--
-- The number is worked out rather than counted off. A header breaks a column
-- every unitsPerColumn members whatever the groups are doing, so a raid with a
-- group of four in it packs the next group's first member into the column
-- above, and a label that counted columns would name the wrong group from there
-- down. Counting who is actually in each group and asking which one the first
-- member of a column falls into is right in both cases.
--------------------------------------------------------------------------

-- How far over the top of the list the headings sit.
local HEADING_GAP = 3

-- How many people are in each raid group. One pass per layout rather than one
-- per column, and false where this client has no roster call, which takes the
-- headings off rather than guessing at them.
local counts = {}

local function CountGroups()
	for group = 1, MAX_GROUPS do
		counts[group] = 0
	end
	if type(_G.GetRaidRosterInfo) ~= "function" then
		return false
	end
	for index = 1, (GetNumGroupMembers() or 0) do
		local _, _, subgroup = _G.GetRaidRosterInfo(index)
		if subgroup and counts[subgroup] then
			counts[subgroup] = counts[subgroup] + 1
		end
	end
	return true
end

-- The raid group the slot-th member of the list belongs to, counting through
-- the groups in the order the header lays them out.
local function GroupAt(slot)
	local seen = 0
	for group = 1, MAX_GROUPS do
		seen = seen + counts[group]
		if slot <= seen then
			return group
		end
	end
	return nil
end

local function Heading(list, index)
	local label = list.headings[index]
	if not label then
		label = ns.UI.Label(list.anchor, ns.UI.OutlineFloor(), ns.UI.Color.heading,
			"CENTER", ns.UI.OUTLINE)
		list.headings[index] = label
	end
	return label
end

-- A label over each column, or none at all.
--
-- `rows` is how many members fill a column of the real list, which is what
-- turns a column into the group its first member is in. Nothing there means a
-- raid the preview made up, and a made up raid is full, so the column is the
-- group and there is no roster to count.
local function Headings(list, columns, rows)
	local block, gap = S(list, "height") + S(list, "width"), S(list, "gap")
	for index = 1, math.max(#list.headings, columns) do
		local group = index <= columns
			and (rows and GroupAt((index - 1) * rows + 1) or index)
		local label = (group or list.headings[index]) and Heading(list, index)
		if not group then
			if label then
				label:Hide()
			end
		else
			label:SetText("Group " .. group)
			label:ClearAllPoints()
			label:SetPoint("BOTTOM", list.anchor, "TOPLEFT",
				Whole(block / 2 + (index - 1) * (block + gap)), HEADING_GAP)
			label:Show()
		end
	end
end

-- The headings over the real list, which is a raid ordered by group and nothing
-- else.
local function Label(list)
	local shown = Expected(list)
	if shown == 0 or not S(list, "headings") or not ByGroupNumber(list)
		or not CountGroups() then
		Headings(list, 0)
		return
	end
	local columns, rows = Extent(list, shown)
	Headings(list, columns, rows)
end

--------------------------------------------------------------------------
-- Where the list sits
--
-- The frame you drag is the list's own rectangle, all of it. That is the other
-- half of the fix for one header serving two lists: the handle used to be a
-- single block somewhere inside whatever was drawn, so moving a raid meant
-- finding a hidden square in the middle of a grid first. Unlocked, the whole
-- list takes the mouse.
--
-- It is anchored by its middle, whatever corner a drag ends on, and that is
-- what makes a list fill outward from where you put it: two people and twenty
-- five are centred on the same pixel, and nobody joining moves anybody who was
-- already on the screen.
--------------------------------------------------------------------------

-- The header hung off the list's own growth edge.
--
-- The one offset here is the header's own quirk: the first block of the first
-- column is anchored at the header's growth point, so a list of several columns
-- has to be pushed left by half of everything past the first column, or the
-- grid hangs off the right of the rectangle it was measured for. A list that
-- runs across the screen is one column laid sideways and needs none of it.
local function Hang(list, wide)
	local edge = Edge(list)
	local block = S(list, "height") + S(list, "width")
	list.header:ClearAllPoints()
	list.header:SetPoint(edge, list.anchor, edge,
		Across(list) and 0 or Whole((block - wide) / 2), 0)
end

-- Whether the preview is what this list is showing. Unlocked, drawing at all,
-- and nobody in it: in a group the real blocks are the preview.
local function Previewing(list)
	return not ns.db.locked and S(list, "on") and Expected(list) == 0
end

-- Everything about where the list is, in one pass: how big the rectangle is,
-- where it sits, and where the header hangs inside it.
--
-- Stored by its middle and anchored by its corner, which is not a contradiction
-- and is the only way to have both halves. The middle is what the setting means,
-- because a list that grew off a corner would shove everybody along the moment
-- somebody joined. The corner is what gets written, because a rectangle of odd
-- width centred on a whole pixel has its left edge on half of one, and every
-- block, hairline and glyph inside it is then rasterised across two rows. The
-- corner is worked out from the middle here and rounded once.
local function Lay(list)
	local shown = Previewing(list) and Full(list) or Expected(list)
	local _, _, wide, tall = Extent(list, shown)

	local point = S(list, "point")
	list.anchor:ClearAllPoints()
	list.anchor:SetPoint("TOPLEFT", UIParent, "CENTER",
		Whole(point[4] - wide / 2), Whole(point[5] + tall / 2))
	ns.UI.Rezoom(list.anchor, S(list, "zoom"))
	list.anchor:SetSize(wide, tall)
	Hang(list, wide)
end

-- Where the list's middle is, in the units the setting is written in. Measured
-- off the frame rather than read back out of the anchor it was given, because a
-- drag leaves the frame on whichever corner the client felt like and the answer
-- has to be the same one Lay will put back.
local function Middle(list)
	local x, y = list.anchor:GetCenter()
	local px, py = UIParent:GetCenter()
	if not x or not px then
		return nil
	end
	return Whole(x - ns.UI.Convert(px, UIParent, list.anchor)),
		Whole(y - ns.UI.Convert(py, UIParent, list.anchor))
end

--------------------------------------------------------------------------
-- The preview
--
-- A list with nobody in it is what you are placing every time you place it: the
-- party is empty out of a group and the raid is empty except on the nights it
-- is not. So unlocked, each list with nobody to draw stands people who are not
-- there in the slots real ones would take, in its own place and at its own
-- size. Both at once, because they are two frames and where you want each of
-- them is a question about the other. That is the answer
-- UnitFrames/PlayerCast.lua gives for a cast bar and it is the same reason:
-- what you are placing is invisible almost every time you place it.
--
-- Ordinary frames rather than anything the header made. A secure header shows
-- one button per member and there is no member, so a preview built out of its
-- buttons is a preview of nothing. They are built the first time somebody
-- unlocks and kept after that, because unlocking is not a thing done on a tick
-- and a player who unlocks once will do it again.
--------------------------------------------------------------------------

-- Five people who are not there: a tank, a healer and three damage, in the
-- order the bands put them. So a preview shows the slot rule as well as the
-- size and the place, and a raid is these five over and over, because forty
-- names invented here is forty names to read past.
local PREVIEW = {
	{ name = "Ironhide", class = "WARRIOR", role = Role.TANK,
		health = 96, power = 45, powerType = 1 },
	{ name = "Lightwell", class = "PRIEST", role = Role.HEALER,
		health = 100, power = 72, powerType = 0 },
	{ name = "Bramblefoot", class = "DRUID", role = Role.DPS,
		health = 61, power = 38, powerType = 0 },
	{ name = "Emberkin", class = "MAGE", role = Role.DPS,
		health = 78, power = 54, powerType = 0 },
	{ name = "Sneaky", class = "ROGUE", role = Role.DPS,
		health = 100, power = 90, powerType = 3 },
}

-- What a preview block is drawn from. The same table Member.Place reads for a
-- real member, with the two fields that say there is no unit behind this one.
local ghost = { width = 0, height = 0, role = nil, icons = true, range = true,
	preview = true, rails = true }

-- Where slot `index` sits inside the rectangle, which is the list's own frame.
-- Off its top left corner rather than its middle, because the rectangle is the
-- list exactly and the first slot is its first corner.
local function Sit(list, frame, index, down)
	local block = S(list, "height") + S(list, "width")
	local height, gap = S(list, "height"), S(list, "gap")
	local column, row = math.floor((index - 1) / down), (index - 1) % down
	if Across(list) then
		column, row = row, column
	end

	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", list.anchor, "TOPLEFT",
		Whole(column * (block + gap)), Whole(-row * (height + gap)))
end

-- Under the anchor's own level rather than over it, all of it. What is on the
-- anchor is the rim you drag by and the name above it, and a preview block that
-- covered either would be a preview of the frame with the handle taken off.
local function Under(list, steps)
	return math.max(list.anchor:GetFrameLevel() - steps, 0)
end

-- One more block than there were, built the first time a list needs it. Forty
-- of them is a raid at the cap, built once in a session, by somebody who has
-- unlocked the frames and is looking at them.
local function Made(list, wanted)
	for index = #list.ghosts + 1, wanted do
		local frame = CreateFrame("Frame", nil, list.anchor)
		frame:EnableMouse(false)
		frame:SetFrameLevel(Under(list, 1))
		Member.Build(frame)
		list.ghosts[index] = frame
	end
end

local function Show(list)
	local shown = Full(list)
	local columns, rows = Extent(list, shown)
	Made(list, shown)

	ghost.width, ghost.height = S(list, "width"), S(list, "height")
	ghost.icons, ghost.range = S(list, "icons"), S(list, "range")

	for index = 1, #list.ghosts do
		local frame = list.ghosts[index]
		if index > shown then
			frame:Hide()
		else
			-- The five over and over, so the fortieth block is drawn from a
			-- class and a power type like the first one.
			local member = PREVIEW[(index - 1) % #PREVIEW + 1]
			ghost.role = member.role
			Member.Place(frame, ghost)
			Member.Preview(frame, member)
			Sit(list, frame, index, Across(list) and columns or rows)
			frame:Show()
		end
	end

	-- A made up raid is a full one, so its columns are its groups and there is
	-- no roster to count them off.
	Headings(list, ByGroupNumber(list) and S(list, "headings") and columns or 0)
end

local function Preview(list)
	if Previewing(list) then
		Show(list)
		return
	end
	-- Whatever the headings were saying, they are the real list's now.
	Label(list)
	for index = 1, #list.ghosts do
		list.ghosts[index]:Hide()
	end
end

--------------------------------------------------------------------------
-- Building one
--------------------------------------------------------------------------

local function Build(list)
	list.anchor = CreateFrame("Frame", list.frameName, UIParent)
	ns.UI.Adopt(list.anchor, S(list, "zoom"))
	list.place = ns.UI.Placeable(list.anchor, {
		name = list.title,
		-- The one of the twelve that refuses in combat. The blocks hanging off
		-- this anchor come off a secure group header, and moving the frame they
		-- are parented to in a lockdown is what the client raises on.
		combat = false,
		-- The corner the drag ended on is thrown away and the middle is written
		-- instead, because the middle is what the list grows out of and what
		-- Lay puts back. Placeable hands over a point either way; this list is
		-- the one part of the addon that cannot store it as it arrives.
		moved = function()
			local x, y = Middle(list)
			if x then
				ns.db[list.keys.point] = { "CENTER", "UIParent", "CENTER", x, y }
			end
			Group.Apply()
		end,
	})

	-- The one call in the addon that names a Blizzard template. A client that
	-- does not carry it refuses the frame rather than raising, and everything
	-- below then answers that the part is not on this client, which is a
	-- different thing from a part that drew nothing.
	local ok, made = pcall(CreateFrame, "Frame", list.headerName, list.anchor,
		"SecureGroupHeaderTemplate")
	if not ok or type(made) ~= "table" then
		list.missing = true
		-- Nothing else here ever runs, so the handle you would drag an empty
		-- list by goes off the screen with the list.
		list.anchor:Hide()
		return false
	end
	list.header = made
	-- Somewhere to be before the first layout. Hang moves it, on this pass and
	-- on every one after it.
	list.header:SetPoint("TOPLEFT", list.anchor, "TOPLEFT", 0, 0)
	list.built = true
	return true
end

--------------------------------------------------------------------------
-- Public
--
-- Both lists, every time. Which of them has anybody in it is the header's
-- business, and it decides that off the group you are in.
--------------------------------------------------------------------------

local function RebuildOne(list)
	if not list.built then
		return
	end
	if not Secure(list) then
		list.pending = true
		return
	end
	if not Adopt(list) then
		list.pending = true
	end
	Nudge(list)
	Lay(list)
	-- The roster is half of what decides whether there is a preview at all, and
	-- all of what the headings count, so both are asked again here and not only
	-- when the lock moves. A group forming while the frames are unlocked is
	-- otherwise made up members standing in front of the real ones who just
	-- turned up.
	Preview(list)
end

-- The order recomputed and every button laid out under it. This is the entry
-- the roster events reach and the one a harness drives.
function Group.Rebuild()
	if not ns.db then
		return
	end
	for index = 1, #lists do
		RebuildOne(lists[index])
	end
	-- Painted here rather than left to the next tick, for the reason Skin.Apply
	-- paints at the end of its own pass: up to a fifth of a second of a block
	-- with no name and a white gauge on it is exactly long enough to read as a
	-- bug, and somebody joining the group is when it would happen.
	Group.Update()
end

-- Everything a setting can move. Called at login, whenever a number in the
-- panel changes and whenever the grid moves under the frames. Never from the
-- tick.
function Group.Apply()
	if not ns.db then
		return
	end
	for index = 1, #lists do
		lists[index].pending = false
	end
	Group.Rebuild()
	Group.Lock()
end

-- Locked is the normal state. Unlocked a list takes the mouse over its whole
-- rectangle, draws its rim and its name, and, with nobody in it, fills itself
-- with people who are not there: something to aim at and something to grab.
function Group.Lock()
	for index = 1, #lists do
		local list = lists[index]
		if list.built then
			list.place:Lock(not ns.db.locked)
			Lay(list)
			Preview(list)
		end
	end
end

function Group.Reset(which)
	local list = Which(which)
	ns.db[list.keys.point] = ns.DefaultCopy(list.keys.point)
	Group.Apply()
end

-- Every member redrawn. Nothing here allocates and every write inside
-- Member.Update is guarded on the value already on the frame, which is what
-- check.sh's HOT list holds both files to.
function Group.Update()
	if not ns.db then
		return
	end
	for index = 1, #lists do
		local members = lists[index].members
		for slot = 1, #members do
			local button = members[slot]
			if button:IsShown() then
				Member.Update(button)
			end
		end
	end
end

-- Whether every block still has the rails it was laid out with. A druid leaving
-- cat form gains a mana bar, and growing one is a relayout rather than a write,
-- so it is asked on the event that says the power type moved and acted on out
-- of combat like everything else here.
function Group.Fits()
	for index = 1, #lists do
		local members = lists[index].members
		for slot = 1, #members do
			if not Member.Rails(members[slot]) then
				return false
			end
		end
	end
	return true
end

-- Called once at load from UnitFrames/Feature.lua with what to do to each new
-- button. Kept as a list rather than one callback, because a second caller here
-- is a line and a second callback field is a decision about precedence.
function Group.OnMember(callback)
	watchers[#watchers + 1] = callback
end

-- One list's own parts, for a macro and for the harness. Handed out for the
-- reason SwingGauges.Bar and PlayerCast.Bar are: what was drawn has to be
-- measurable, and the alternative is this file answering nine questions about
-- itself one at a time.
-- Which setting one list reads for one of its own numbers, so the slash words
-- and the panel write the party's width and not the raid's without either of
-- them keeping a second copy of the map.
function Group.Key(which, name)
	return Which(which).keys[name]
end

function Group.Header(which)
	return Which(which).header
end

function Group.Members(which)
	return Which(which).members
end

function Group.Anchor(which)
	return Which(which).anchor
end

-- The made up blocks a list stands in its slots, and the headings over them.
-- Empty until the frames have been unlocked with nobody in that list, which is
-- the whole condition the preview exists under.
function Group.Previewed(which)
	local list = Which(which)
	return list.ghosts, list.headings
end

function Group.Count(which)
	local members = Which(which).members
	local shown = 0
	for index = 1, #members do
		if members[index]:IsShown() then
			shown = shown + 1
		end
	end
	return shown
end

function Group.Deferred(which)
	return Which(which).pending
end

-- What a block is allowed to be. One source for the panel's sliders and the
-- clamp the slash words go through, because two copies of a range is two
-- chances for one of them to accept a number the other would refuse.
function Group.SizeRange()
	return WIDTH_LOW, WIDTH_HIGH, HEIGHT_LOW, HEIGHT_HIGH
end

function Group.GapRange()
	return GAP_LOW, GAP_HIGH
end

function Group.ColumnRange()
	return COLUMNS_LOW, COLUMNS_HIGH, PER_COLUMN_LOW, PER_COLUMN_HIGH
end

--------------------------------------------------------------------------

-- One line per list for /wk status and for the panel. It says what is live
-- rather than what is set, because a raid ordered by group is doing nothing of
-- the kind while you are standing in a party.
function Group.Describe(which)
	local list = Which(which)
	if list.missing then
		return "|cffd08040this client has no SecureGroupHeaderTemplate|r, so no blocks were built"
	end
	if not S(list, "on") then
		return "off, and Blizzard's own frames are where the hide switches leave them"
	end

	local size = ("%d by %d pixels"):format(S(list, "height") + S(list, "width"),
		S(list, "height"))
	if Previewing(list) then
		return ("on, %s, and previewing itself because the frames are unlocked:"
			.. " %d blocks where the real ones go"):format(size, Full(list))
	end

	local order = ByGroupNumber(list) and "by raid group, a column each"
		or "tanks, then healers, then damage, by name inside each band"
	local line = ("on, %s, %d in the list, %s"):format(size, Group.Count(which), order)
	if not S(list, "mine") then
		line = line .. ", you are not in it"
	end
	if list.pending then
		line = line .. (InCombatLockdown()
			and ", the rest follows when combat drops" or ", the rest follows on the next pass")
	end
	return line
end

--------------------------------------------------------------------------
-- The tick and the events
--
-- The ticker lives on the event frame, which is never hidden. On an anchor it
-- would stop the moment a group broke up and never come back, which is the trap
-- Charge/Icon.lua and Swing/Gauges.lua both carry a note about.
--------------------------------------------------------------------------

local elapsed = 0

local function OnUpdate(_, delta)
	elapsed = elapsed + delta
	if elapsed >= POLL then
		elapsed = 0
		ns.Perf.Start("party")
		Group.Update()
		ns.Perf.Stop("party")
	end
end

local function Deferring()
	for index = 1, #lists do
		if lists[index].pending then
			return true
		end
	end
	return false
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("UNIT_DISPLAYPOWER")
-- The raid leader moving a main tank flag, which is one of the four sources
-- Unit/Role.lua reads and the only one that moves without the roster moving.
-- Through pcall, because the name is not proven on both of these clients and a
-- client that refuses it loses nothing: GROUP_ROSTER_UPDATE reaches this too.
pcall(events.RegisterEvent, events, "PLAYER_ROLES_ASSIGNED")

events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		local any = false
		for index = 1, #lists do
			any = Build(lists[index]) or any
		end
		if any then
			Group.Apply()
			events:SetScript("OnUpdate", OnUpdate)
		end
		return
	end
	if event == "UNIT_DISPLAYPOWER" then
		if not Group.Fits() then
			Group.Rebuild()
		end
		return
	end
	if event == "PLAYER_REGEN_ENABLED" and not Deferring() then
		return
	end
	for index = 1, #lists do
		lists[index].pending = false
	end
	Group.Rebuild()
end)

-- A resolution change moves every size in this file at once, and it moves each
-- header's own arithmetic with them, because the gap between two blocks is
-- written on the header as a number of the anchor's units.
ns.UI.OnRescale(function()
	Group.Apply()
end)
