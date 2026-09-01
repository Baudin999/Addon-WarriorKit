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
-- The order is tanks, then healers, then damage, and by name inside a band. By
-- name is arbitrary as an ordering and it is the only one that is stable: the
-- same five people produce the same five slots in every group they are ever in
-- together, whoever formed it and whoever zoned in first. Party index does not
-- do that, and sorting by class does not either, because a class can be two
-- roles.
--
-- It is recomputed out of combat and nowhere else, which is what makes fixed
-- placing true rather than aspirational. An inspect that resolves mid pull is
-- recorded by Unit/Role.lua and changes nothing on the screen until the fight
-- ends.
--------------------------------------------------------------------------

local Member = ns.GroupMember
local Role = ns.Unit.Role
local Roster = ns.Unit.Roster

local FRAME_NAME = "WarriorKitGroup"
local HEADER_NAME = "WarriorKitGroupHeader"

-- The rate every readout in this addon runs at.
local POLL = 0.2

-- What the block is allowed to be, shared with the panel and the slash word so
-- all three clamp to the same numbers. The two sizes are the skin's own range,
-- because a party block and the player block are the same instrument.
local WIDTH_LOW, WIDTH_HIGH = 90, 360
local HEIGHT_LOW, HEIGHT_HIGH = 18, 72
local GAP_LOW, GAP_HIGH = 0, 20
local COLUMNS_LOW, COLUMNS_HIGH = 1, 8
local PER_COLUMN_LOW, PER_COLUMN_HIGH = 1, 40

-- The raid's own groups, in order, for `party order group`. A string because
-- that is what the header takes, and written out rather than built, because it
-- is eight characters and a loop that produced them would be a loop to read.
local GROUPS = "1,2,3,4,5,6,7,8"

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

local anchor, header, place
local built, missing = false, false
local pending = false

-- Every button the header has made, in the order it made them, and the set of
-- the ones already built out. The list is what the tick walks; the set is what
-- stops a button being built twice.
local members, adopted = {}, {}

-- What to do with a button the first time it is seen, registered from
-- UnitFrames/Feature.lua. It exists for ctrl-click marking: Marking/Marking.lua
-- hooks frames by name and PartyMemberFrame1 through 4 are on that list, so
-- hiding them takes marking on a party member off the screen with them. A
-- behaviour file may not name a file outside its own folder, and Feature.lua is
-- where that rule puts the call.
local watchers = {}

-- The slot order, and the band each name sorts into. Module tables rather than
-- locals built per pass, because the comparator has to read the bands and a
-- comparator written at the call site is a closure per rebuild.
local names, bands = {}, {}

-- What one block is drawn from, filled once per pass and handed to every member
-- with only the role changed between them. UnitFrames/Member.lua reads no
-- setting of its own and this table is the whole of what it is told; one table
-- reused rather than one per member, because a raid relayout is forty of them.
local look = { width = 0, height = 0, role = nil, icons = true, range = true }

local UnitName = UnitName
local UnitIsUnit = UnitIsUnit

--------------------------------------------------------------------------
-- The order
--------------------------------------------------------------------------

local function ByBand(a, b)
	if bands[a] ~= bands[b] then
		return bands[a] < bands[b]
	end
	return a < b
end

-- Who is in the list and in what order. Off ns.Unit.Roster rather than off the
-- party tokens, because that file already keeps the group by event and the
-- enemy bars were walking the raid on a ticker to get the same answer.
--
-- Your own name is in it only if you asked for it. Skin.lua already draws you
-- as a block, and two of your own frames on one screen is the exact complaint
-- UnitFrames/Blizzard.lua exists to answer.
local function Order()
	wipe(bands)
	for index = #names, 1, -1 do
		names[index] = nil
	end

	local units = Roster.Units()
	for index = 1, #units do
		local unit = units[index]
		local name = UnitName(unit)
		if name and (ns.db.partySelf or not UnitIsUnit(unit, "player")) then
			names[#names + 1] = name
			bands[name] = Role.Band(Role.Of(unit))
		end
	end
	table.sort(names, ByBand)
	return names
end

-- The slot order as the header was last told it. For the panel, for a macro and
-- for the harness, which drives Group.Rebuild and then reads this.
function Group.Order()
	return names
end

--------------------------------------------------------------------------
-- The attributes
--------------------------------------------------------------------------

-- Which of the two orderings the header is running, given the group you are in.
-- Party is always by role: the group number of a party is 1 for everyone in it,
-- so grouping by it is a list in the order the client hands the units over,
-- which is the thing the whole item exists to stop.
local function ByGroupNumber()
	return ns.db.partyOrder == "group" and IsInRaid() and true or false
end

local function Sorting()
	if ByGroupNumber() then
		-- The order is dropped as well as unused. It is handed out by
		-- Group.Order and the panel prints it, and a role order left lying about
		-- while the header is running group numbers is a readout that says the
		-- opposite of what is on the screen.
		for index = #names, 1, -1 do
			names[index] = nil
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
	header:SetAttribute("nameList", table.concat(Order(), ","))
end

-- Every attribute that decides the shape of the list, written in one pass.
-- False where combat refused, which the retry at PLAYER_REGEN_ENABLED picks up.
local function Secure()
	if InCombatLockdown() then
		return false
	end

	local wide, tall = ns.db.partyWidth, ns.db.partyHeight
	local gap = ns.db.partyGap
	local down = ns.db.partyGrow ~= "up"

	header:SetAttribute("template", "SecureUnitButtonTemplate")
	header:SetAttribute("initialConfigFunction", CONFIG:format(tall + wide, tall))

	-- One switch, said twice, because the header asks separately about a party
	-- and a raid. Solo is never on: a list of one is the player block the skin
	-- already draws.
	header:SetAttribute("showRaid", ns.db.party)
	header:SetAttribute("showParty", ns.db.party)
	header:SetAttribute("showSolo", false)
	header:SetAttribute("showPlayer", ns.db.partySelf)

	header:SetAttribute("point", down and "TOP" or "BOTTOM")
	header:SetAttribute("xOffset", 0)
	header:SetAttribute("yOffset", down and -gap or gap)
	header:SetAttribute("columnAnchorPoint", "LEFT")
	header:SetAttribute("columnSpacing", gap)
	header:SetAttribute("maxColumns", ns.db.partyRaidColumns)
	header:SetAttribute("unitsPerColumn", ns.db.partyRaidPerColumn)

	Sorting()
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
local function Take(button)
	adopted[button] = true
	members[#members + 1] = button
	button:RegisterForClicks("AnyUp")
	Member.Build(button)
	for index = 1, #watchers do
		watchers[index](button)
	end
end

-- Every child of the header, built out and laid out. False where combat refused
-- one of them.
--
-- A table per pass, which is allowed here: this runs on a roster change, on a
-- setting change and on nothing else. Every child of the header is a member
-- button, because the drag handle and the label are children of the anchor
-- rather than of the header.
local function Adopt()
	look.width, look.height = ns.db.partyWidth, ns.db.partyHeight
	look.icons, look.range = ns.db.partyRoleIcon, ns.db.partyRange

	local complete = true
	for _, button in ipairs({ header:GetChildren() }) do
		if not adopted[button] then
			Take(button)
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
local function Nudge()
	header:SetAttribute("point", ns.db.partyGrow ~= "up" and "TOP" or "BOTTOM")
end

--------------------------------------------------------------------------
-- Where the block sits
--------------------------------------------------------------------------

-- The anchor is one block's rectangle at the middle of the list, which is the
-- point the list grows out of in both directions. Unlocked it draws a rim and
-- carries its own name, so a list that is empty because you are not in a group
-- is still something you can find and drag.
local function Place()
	local point = ns.db.partyPoint
	anchor:ClearAllPoints()
	anchor:SetPoint(point[1], UIParent, point[3], point[4], point[5])
	ns.UI.Rezoom(anchor, ns.db.partyZoom)

	local unit = ns.UI.Unit(anchor)
	anchor:SetSize((ns.db.partyHeight + ns.db.partyWidth) * unit,
		ns.db.partyHeight * unit)
end

local Whole = ns.UI.Whole

-- How many blocks the header is about to show.
--
-- Off the roster rather than off the buttons, and that is the whole of the fix
-- for a list that sat with its anchor over the first slot instead of its
-- middle. Group.Count answers what is on the screen at this instant, which is
-- the wrong question at the moment the layout is decided: the header updates
-- itself off the same GROUP_ROSTER_UPDATE this file does, so the pass that
-- centres the list runs before the buttons for the people who are in it exist.
-- At login, in a party, that count is zero, the list is centred as a list of
-- nothing, and it stays that way until somebody joins or leaves and a second
-- pass happens to run late enough to see them.
--
-- Capped at the cap the header itself applies, because a raid past
-- maxColumns * unitsPerColumn is a header that shows the first of it and drops
-- the rest, and the list to centre is the one that gets drawn.
local function Expected()
	if not ns.db.party then
		return 0
	end
	-- Solo is never shown: showSolo is false, and a roster of one is you.
	local units = Roster.Units()
	if #units < 2 then
		return 0
	end
	local shown = ns.db.partySelf and #units or #units - 1
	return math.min(shown, ns.db.partyRaidColumns * ns.db.partyRaidPerColumn)
end

-- How many columns wide and how many rows deep a list of that many blocks is
-- arranged, and how far it reaches in each direction. The header's own
-- arithmetic, done here: a party of five at five to a column is one column of
-- five, and the same five at one to a column is five columns of one.
local function Extent(shown)
	local per = math.max(ns.db.partyRaidPerColumn, 1)
	local columns, rows = 1, shown
	if shown > per then
		columns, rows = math.min(math.ceil(shown / per), ns.db.partyRaidColumns), per
	end
	rows = math.max(rows, 1)

	local gap = ns.db.partyGap
	local block = ns.db.partyHeight + ns.db.partyWidth
	return columns, rows,
		columns * block + (columns - 1) * gap,
		rows * ns.db.partyHeight + (rows - 1) * gap
end

-- The header placed so the blocks under it fill outward from the anchor, which
-- is the whole of what makes the list grow from its middle.
--
-- Measured out of the settings rather than off the header, and anchored by the
-- edge the header grows from rather than by a corner. Both of those are the same
-- fact about SecureGroupHeaders: the first block of the first column is anchored
-- at the header's own growth point, TOP to TOP, so it is centred across the
-- header however wide the header says it is, and every further column is hung
-- off the right of that one. A second column therefore lands outside the box the
-- header sized itself to, and centring that box put a two column list half a
-- block right of where it belonged. Anchoring TOP to TOP instead ties the one
-- thing the client will not move, the top middle of the first block, to a point
-- this file works out for itself.
--
-- Rounded, because half of a block plus a gap is not always a whole unit. Four
-- blocks with a three unit gap between them is a hundred and forty five, and a
-- list placed on half of that rasterises every edge inside it across two rows of
-- pixels, which is the blur OnDragStop already rounds away for the same reason.
--
-- In combat this is never reached at all, because Rebuild has already returned
-- by then on a Secure that was refused.
local function Centre()
	local _, _, wide, tall = Extent(Expected())

	local down = ns.db.partyGrow ~= "up"
	local edge = down and "TOP" or "BOTTOM"
	local across = Whole((anchor:GetWidth() - wide) / 2)
	local away = Whole((tall - anchor:GetHeight()) / 2)

	header:ClearAllPoints()
	header:SetPoint(edge, anchor, edge, across, down and away or -away)
end

--------------------------------------------------------------------------
-- The group headings
--
-- One label over each column, which is the whole difference between a raid you
-- can find somebody in and forty rectangles. It says which raid group that
-- column starts with, and it is only drawn where the columns are groups, which
-- is a raid ordered by group number and nothing else. In role order a column is
-- five people who happen to have followed each other down the list.
--
-- The number is worked out rather than assumed. A header fills a column every
-- unitsPerColumn members whatever the groups are doing, so a raid with a group
-- of four in it packs the next group's first member into the column above, and
-- a label that counted columns instead of people would name the wrong group
-- from there down. Counting who is actually in each group and asking which one
-- the first member of the column falls into is right in both cases.
--------------------------------------------------------------------------

local MAX_GROUPS = 8

-- How far over the top of the list the headings sit.
local HEADING_GAP = 3

local headings = {}

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

local function Heading(index)
	local label = headings[index]
	if not label then
		label = ns.UI.Label(anchor, ns.UI.OutlineFloor(), ns.UI.Color.heading,
			"CENTER", ns.UI.OUTLINE)
		headings[index] = label
	end
	return label
end

-- A label over each column, or none at all.
--
-- `rows` is how many members fill a column of the real list, which is what
-- turns a column into the group its first member is in. Nothing there means a
-- raid the preview made up, and a made up raid is full, so the column is the
-- group and there is no roster to count.
local function Headings(columns, wide, tall, rows)
	local block, gap = ns.db.partyHeight + ns.db.partyWidth, ns.db.partyGap
	for index = 1, math.max(#headings, columns) do
		local group = index <= columns
			and (rows and GroupAt((index - 1) * rows + 1) or index)
		local label = (group or headings[index]) and Heading(index)
		if not group then
			if label then
				label:Hide()
			end
		else
			label:SetText("Group " .. group)
			label:ClearAllPoints()
			label:SetPoint("BOTTOM", anchor, "CENTER",
				Whole(block / 2 - wide / 2 + (index - 1) * (block + gap)),
				Whole(tall / 2 + HEADING_GAP))
			label:Show()
		end
	end
end

-- The headings over the real list, which is the raid ordered by group and
-- nothing else. Called after Centre, because both are placed off the same
-- rectangle and Centre is what works out how big it is.
local function Label()
	if not ByGroupNumber() or not CountGroups() then
		Headings(0, 0, 0)
		return
	end
	local columns, rows, wide, tall = Extent(Expected())
	Headings(columns, wide, tall, rows)
end

--------------------------------------------------------------------------
-- The preview
--
-- A list with nobody in it is what you are placing every time you place it: the
-- party is empty out of a group and the raid is empty except on the two nights
-- a week it is not. So unlocked and out of a group, the frames stand people who
-- are not there in the slots real ones would take, four seconds as a party and
-- four as a full raid, and then round again.
--
-- Two shapes rather than one because they are two different rectangles. A party
-- is one column at the size you read health off, a raid is that column repeated
-- across the screen, and the answer to "will this fit here" is different for
-- each. UnitFrames/PlayerCast.lua previews a cast and then a channel for the
-- same reason and on the same clock.
--
-- Ordinary frames rather than anything the header made. A secure header shows
-- one button per member and there is no member, so a preview built out of its
-- buttons is a preview of nothing. They are built the first time somebody
-- unlocks and kept after that, because unlocking is not a thing done on a tick
-- and a player who unlocks once will do it again.
--------------------------------------------------------------------------

-- Five people who are not there: a tank, a healer and three damage, in the
-- order the bands put them. So the preview shows the slot rule as well as the
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

-- The most a raid holds, whatever the column settings multiply out to.
local RAID = 40

-- How long each of the two shapes holds, and how far under the list its caption
-- sits.
local HOLD = 4
local CAPTION_GAP = 3

-- What a preview block is drawn from. The same table Member.Place reads for a
-- real member, with the two fields that say there is no unit behind this one.
local ghost = { width = 0, height = 0, role = nil, icons = true, range = true,
	preview = true, rails = true }

local frames, caption = {}, nil
local phase, phaseAt = "party", 0

-- Where slot `index` of an arrangement `rows` deep sits, as an offset from the
-- middle of the anchor.
--
-- The plain way round, which Centre cannot use and this can. The whole
-- arrangement is centred on the anchor, and Centre reaches that through the one
-- point on a secure header the client will not move; nothing here is secure, so
-- the list is `wide` by `tall` about the anchor's middle, a column fills before
-- the next one starts, and `grow` says which end of a column slot one is at.
local function Sit(frame, index, rows, wide, tall)
	local block = ns.db.partyHeight + ns.db.partyWidth
	local height, gap = ns.db.partyHeight, ns.db.partyGap
	local column, row = math.floor((index - 1) / rows), (index - 1) % rows

	local x = block / 2 - wide / 2 + column * (block + gap)
	local y = tall / 2 - height / 2 - row * (height + gap)
	frame:ClearAllPoints()
	frame:SetPoint("CENTER", anchor, "CENTER", Whole(x),
		Whole(ns.db.partyGrow == "up" and -y or y))
end

-- Under the anchor's own level rather than over it, all of it. What is on the
-- anchor is the rim you drag by and the name above it, and a preview block that
-- covered either would be a preview of the frame with the handle taken off.
local function Under(steps)
	return math.max(anchor:GetFrameLevel() - steps, 0)
end

-- One more block than there were, built the first time a shape needs it. Forty
-- of them is a raid at the cap and it is built once in a session, by somebody
-- who has unlocked the frames and is looking at them.
local function Made(wanted)
	if not caption then
		caption = ns.UI.Label(anchor, ns.UI.OutlineFloor(), ns.UI.Color.quiet,
			"CENTER", ns.UI.OUTLINE)
	end
	for index = #frames + 1, wanted do
		local frame = CreateFrame("Frame", nil, anchor)
		frame:EnableMouse(false)
		frame:SetFrameLevel(Under(1))
		Member.Build(frame)
		frames[index] = frame
	end
end

-- How many blocks this shape stands, and what its caption says.
local function Shape()
	if phase == "raid" then
		local held = math.min(ns.db.partyRaidColumns * ns.db.partyRaidPerColumn, RAID)
		local columns, rows = Extent(held)
		return held, ("a raid of %d, %d by %d"):format(held, columns, rows)
	end
	-- As many as a real party would show, which is four unless your own block
	-- is in the list.
	local held = ns.db.partySelf and #PREVIEW or #PREVIEW - 1
	return held, ("a party of %d"):format(held)
end

local function Show()
	local shown, said = Shape()
	local columns, rows, wide, tall = Extent(shown)
	Made(shown)

	ghost.width, ghost.height = ns.db.partyWidth, ns.db.partyHeight
	ghost.icons, ghost.range = ns.db.partyRoleIcon, ns.db.partyRange

	for index = 1, #frames do
		local frame = frames[index]
		if index > shown then
			frame:Hide()
		else
			-- The five over and over, so the fortieth block is drawn from a
			-- class and a power type like the first one.
			local member = PREVIEW[(index - 1) % #PREVIEW + 1]
			ghost.role = member.role
			Member.Place(frame, ghost)
			Member.Preview(frame, member)
			Sit(frame, index, rows, wide, tall)
			frame:Show()
		end
	end

	-- A made up raid is a full one, so its columns are its groups. Only in
	-- group order, for the reason the real headings are: in role order a column
	-- is not a group.
	if phase == "raid" and ns.db.partyOrder == "group" then
		Headings(columns, wide, tall)
	else
		Headings(0, 0, 0)
	end

	caption:SetText(said)
	caption:ClearAllPoints()
	caption:SetPoint("TOP", anchor, "CENTER", 0, Whole(-tall / 2 - CAPTION_GAP))
	caption:Show()
end

-- Whether the preview is what is on the screen. Unlocked, drawing at all, and
-- nobody to draw: in a group the real blocks are the preview, and two lists of
-- five on one anchor is the complaint the whole part exists to answer.
local function Previewing()
	return not ns.db.locked and ns.db.party and Expected() == 0
end

local function Preview()
	if Previewing() then
		if phaseAt == 0 then
			phaseAt = GetTime()
		end
		Show()
		return
	end
	-- Whatever the headings were saying, they are the real list's now.
	Label()
	if not caption then
		return -- never unlocked out of a group, so there is nothing built to hide
	end
	for index = 1, #frames do
		frames[index]:Hide()
	end
	caption:Hide()
	phase, phaseAt = "party", 0
end

-- The two shapes, four seconds each. Off the ticker that is already running,
-- and it does nothing at all while the frames are locked, which is every moment
-- but the one this is for.
local function Turn(now)
	if not Previewing() then
		return
	end
	if now - phaseAt < HOLD then
		return
	end
	phaseAt = now
	phase = phase == "party" and "raid" or "party"
	Show()
end

local function Build()
	anchor = CreateFrame("Frame", FRAME_NAME, UIParent)
	ns.UI.Adopt(anchor, ns.db.partyZoom)
	place = ns.UI.Placeable(anchor, {
		name = "WarriorKit party",
		-- The one of the twelve that refuses in combat. The blocks hanging off
		-- this anchor come off a secure group header, and moving the frame they
		-- are parented to in a lockdown is what the client raises on.
		combat = false,
		moved = function(point)
			ns.db.partyPoint = point
			Group.Apply()
		end,
	})

	-- The one call in the addon that names a Blizzard template. A client that
	-- does not carry it refuses the frame rather than raising, and everything
	-- below then answers that the part is not on this client, which is a
	-- different thing from a part that drew nothing.
	local ok, made = pcall(CreateFrame, "Frame", HEADER_NAME, anchor,
		"SecureGroupHeaderTemplate")
	if not ok or type(made) ~= "table" then
		missing = true
		-- Nothing else here ever runs, so the handle you would drag an empty
		-- list by goes off the screen with the list.
		anchor:Hide()
		return false
	end
	header = made
	-- Somewhere to be before the first layout. Centre moves it, on this pass and
	-- on every one after it.
	header:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, 0)
	built = true
	return true
end

--------------------------------------------------------------------------
-- Public
--------------------------------------------------------------------------

-- The order recomputed and every button laid out under it. This is the entry
-- the roster events reach and the one a harness drives.
function Group.Rebuild()
	if not built or not ns.db then
		return
	end
	if not Secure() then
		pending = true
		return
	end
	if not Adopt() then
		pending = true
	end
	Nudge()
	Centre()
	-- The roster is half of what decides whether there is a preview at all, and
	-- all of what the headings count, so both are done again here and not only
	-- when the lock moves. A group forming while the frames are unlocked is
	-- otherwise five made up members standing in front of the five real ones who
	-- just turned up.
	Preview()
	-- Painted here rather than left to the next tick, for the reason
	-- Skin.Apply paints at the end of its own pass: up to a fifth of a second
	-- of a block with no name and a white gauge on it is exactly long enough to
	-- read as a bug, and somebody joining the group is when it would happen.
	Group.Update()
end

-- Everything a setting can move. Called at login, whenever a number in the
-- panel changes and whenever the grid moves under the frame. Never from the
-- tick.
function Group.Apply()
	if not built or not ns.db then
		return
	end
	pending = false
	Place()
	Group.Rebuild()
	Group.Lock()
end

-- Locked is the normal state. Unlocked the anchor takes the mouse, draws its
-- rim and, out of a group, fills itself with a party that is not there and the
-- rectangle a raid would take, the same as your cast bar and for the same
-- reason: what you are placing is empty almost every time you place it.
function Group.Lock()
	if not built then
		return
	end
	place:Lock(not ns.db.locked)
	Preview()
end

function Group.Reset()
	ns.db.partyPoint = ns.DefaultCopy("partyPoint")
	Group.Apply()
end

-- Every member redrawn. Nothing here allocates and every write inside
-- Member.Update is guarded on the value already on the frame, which is what
-- check.sh's HOT list holds both files to.
function Group.Update()
	if not built or not ns.db or not ns.db.party then
		return
	end
	for index = 1, #members do
		local button = members[index]
		if button:IsShown() then
			Member.Update(button)
		end
	end
end

-- Whether every block still has the rails it was laid out with. A druid leaving
-- cat form gains a mana bar, and growing one is a relayout rather than a write,
-- so it is asked on the event that says the power type moved and acted on out
-- of combat like everything else here.
function Group.Fits()
	for index = 1, #members do
		if not Member.Rails(members[index]) then
			return false
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

-- The header itself and the buttons under it, for a macro and for the harness.
-- Handed out for the reason SwingGauges.Bar and PlayerCast.Bar are: what was
-- drawn has to be measurable, and the alternative is this file handing over its
-- own state table.
function Group.Header()
	return header
end

function Group.Members()
	return members
end

-- The made up blocks the preview stands in the slots, which shape it is
-- standing, and the headings over the columns. Empty until the frames have been
-- unlocked out of a group once, which is the whole condition it exists under.
function Group.Previewed()
	return frames, phase, headings
end

function Group.Count()
	local shown = 0
	for index = 1, #members do
		if members[index]:IsShown() then
			shown = shown + 1
		end
	end
	return shown
end

function Group.Deferred()
	return pending
end

-- What the block is allowed to be. One source for the panel's sliders and the
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

-- One line for /wk status and for the panel. It says which of the two orderings
-- is live rather than which is set, because `party order group` does nothing at
-- all in a party and that is worth reading before you go looking for the bug.
function Group.Describe()
	if missing then
		return "|cffd08040this client has no SecureGroupHeaderTemplate|r, so no party frames were built"
	end
	if not ns.db.party then
		return "off, and Blizzard's own party and raid frames are where the hide switches leave them"
	end
	if Previewing() then
		return ("on, %d by %d pixels, and previewing itself because the frames are"
			.. " unlocked: a party of %d, then a raid of %d, %d seconds each, both"
			.. " where the real ones go"):format(
			ns.db.partyHeight + ns.db.partyWidth, ns.db.partyHeight,
			ns.db.partySelf and #PREVIEW or #PREVIEW - 1,
			math.min(ns.db.partyRaidColumns * ns.db.partyRaidPerColumn, RAID), HOLD)
	end
	local order = ByGroupNumber() and "by raid group"
		or "tanks, then healers, then damage, by name inside each band"
	local line = ("on, %d by %d pixels, %d in the list, %s"):format(
		ns.db.partyHeight + ns.db.partyWidth, ns.db.partyHeight, Group.Count(), order)
	if not ns.db.partySelf then
		line = line .. ", you are not in it"
	end
	if pending then
		line = line .. (InCombatLockdown()
			and ", the rest follows when combat drops" or ", the rest follows on the next pass")
	end
	return line
end

--------------------------------------------------------------------------
-- The tick and the events
--
-- The ticker lives on the event frame, which is never hidden. On the anchor it
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
		-- Outside the perf bracket and outside Group.Update, which is the
		-- function the allocation gate measures. This one is two comparisons
		-- while the frames are locked, which is every moment but the one
		-- somebody is placing them, and it lays a list out on the fifth pass
		-- through the second it is not.
		Turn(GetTime())
	end
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
		if Build() then
			Group.Apply()
			events:SetScript("OnUpdate", OnUpdate)
		end
		return
	end
	if not built then
		return
	end
	if event == "UNIT_DISPLAYPOWER" then
		if not Group.Fits() then
			Group.Rebuild()
		end
		return
	end
	if event == "PLAYER_REGEN_ENABLED" and not pending then
		return
	end
	pending = false
	Group.Rebuild()
end)

-- A resolution change moves every size in this file at once, and it moves the
-- header's own arithmetic with them, because the gap between two blocks is
-- written on the header as a number of the anchor's units.
ns.UI.OnRescale(function()
	Group.Apply()
end)
