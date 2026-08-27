local ADDON, ns = ...

local People = {}
ns.People = People

--------------------------------------------------------------------------
-- The people who matter, in groups
--
-- A group is a name and a handful of people: Family, the officers, the four you
-- level with. Everything anybody in a group says, in any channel, is copied to
-- that group's own room in the chat window, and so is anything you whisper to
-- them.
--
-- **Why groups and not one list.** The first version of this was one flat list
-- of important people and one tab for all of them, on the argument that what
-- you want to know is whether anybody you care about has spoken. That argument
-- holds right up to the point where you have two kinds of people on it. A wife
-- in party chat and a guild officer asking about raid times are both on the
-- list and neither belongs in the same column as the other: one of them you
-- answer now, the other you answer at some point this week. A group is the
-- smallest thing that separates them, it is a thing the player already has in
-- their head, and it costs one row in a rail.
--
-- A person may be in more than one group and their line goes to all of them.
-- Rooms are views rather than boxes, which is the whole shape of the window:
-- nothing is filed away where you have to go and look for it.
--
-- **Names, not GUIDs.** A GUID is exact and it is also unavailable: the client
-- gives one on a chat event but there is nothing to type into a settings panel
-- to get one, and it is per character, so a son who rerolls is a stranger
-- again. A name is what you would type, it is what the client puts on the
-- message, and it is what a person keeps. The cost is that two characters with
-- the same name on different realms are the same person here, which on these
-- clients means somebody you meet cross-realm in a battleground.
--
-- **Account-wide.** Who matters to you is a fact about you, not about the
-- character you are standing in, and typing the same three names in on every
-- alt is exactly the kind of chore this addon exists to remove.
--
-- Names are matched normalised: realm suffix off, case flattened. The client
-- sends "Aria" in party and "Aria-Firemaw" from another realm, and both are the
-- same person.
--------------------------------------------------------------------------

-- The caps. Neither is a technical limit and both are shape.
--
-- Twenty in a group is the list of people you would notice if they spoke, and a
-- list of forty is a list you have stopped reading. Six groups is what fits in
-- the window's rail beside the channels and the whispers without the rail
-- becoming the thing you scroll.
People.MAX = 20
People.GROUPS = 6

-- Normalised name -> the groups holding it. Rebuilt whenever the list changes
-- rather than walked per message, because every line of chat in a raid asks
-- this question and the answer changes when you type in the panel.
local index = {}

-- Which group and which member the panel is showing. Module state rather than a
-- saved setting, because it is where you are in a window rather than something
-- you decided.
local shown, member = 1, 1

--------------------------------------------------------------------------

-- What two names have to agree on to be the same person: the realm suffix off,
-- the case flattened, the spaces trimmed. Returns nil for anything that is not
-- a name, so an empty field cannot match an empty sender.
function People.Key(name)
	if type(name) ~= "string" then
		return nil
	end
	local trimmed = name:gsub("^%s+", ""):gsub("%s+$", "")
	trimmed = trimmed:gsub("%-.*$", "")
	if trimmed == "" then
		return nil
	end
	return trimmed:lower()
end

local function Reindex()
	index = {}
	for _, group in ipairs(ns.db.groups) do
		for _, name in ipairs(group.members) do
			local key = People.Key(name)
			if key then
				local held = index[key]
				if not held then
					index[key] = { group }
				elseif held[#held] ~= group then
					held[#held + 1] = group
				end
			end
		end
	end
end

ns.People.Reindex = Reindex

--------------------------------------------------------------------------
-- Reading the list
--------------------------------------------------------------------------

function People.All()
	return ns.db.groups
end

function People.Count()
	return #ns.db.groups
end

function People.Get(position)
	return ns.db.groups[position]
end

-- Every group holding this name, or nil. This is the whole hot path of the
-- part: it runs once per line of chat and it is a table lookup on a string that
-- had to be built anyway.
function People.Match(sender)
	local key = People.Key(sender)
	if not key then
		return nil
	end
	return index[key]
end

function People.Total()
	local count = 0
	for _, group in ipairs(ns.db.groups) do
		count = count + #group.members
	end
	return count
end

--------------------------------------------------------------------------
-- Which one the panel is on
--------------------------------------------------------------------------

local function Clamp(value, count)
	if value > count then
		value = count
	end
	if value < 1 then
		value = 1
	end
	return value
end

function People.Shown()
	shown = Clamp(shown, People.Count())
	return shown
end

function People.Show(position)
	shown = position
	member = 1
	return People.Shown()
end

function People.Member()
	local group = People.Get(People.Shown())
	member = Clamp(member, group and #group.members or 0)
	return member
end

function People.ShowMember(position)
	member = position
	return People.Member()
end

--------------------------------------------------------------------------
-- Editing the groups
--
-- Every one of these returns a reason rather than printing one. A part's
-- behaviour file does not talk to the player: Feature.lua does, and the panel
-- shows the same string in a note.
--
-- A group carries a key of its own, handed out once and never reused. The room
-- in the window is named by that key rather than by the group's position, so
-- deleting the first group does not hand its unread lines to the second, and
-- renaming one keeps the scrollback you were reading.
--------------------------------------------------------------------------

function People.AddGroup(name)
	if People.Count() >= People.GROUPS then
		return nil, ("%d is as many groups as there is room for"):format(People.GROUPS)
	end

	ns.db.groupSeq = (ns.db.groupSeq or 0) + 1
	local list = ns.db.groups
	list[#list + 1] = { key = tostring(ns.db.groupSeq), name = name or "", members = {} }
	Reindex()
	shown, member = #list, 1
	return shown
end

function People.RemoveGroup(position)
	local list = ns.db.groups
	if not list[position] then
		return false
	end
	table.remove(list, position)
	Reindex()
	shown = Clamp(shown, #list)
	member = 1
	return true
end

function People.RenameGroup(position, name)
	local group = ns.db.groups[position]
	if not group then
		return false, "no group is selected"
	end
	group.name = name or ""
	return true
end

--------------------------------------------------------------------------
-- Editing who is in one
--------------------------------------------------------------------------

-- Whether this group already holds the name, which is the one thing an add has
-- to refuse. The same person in two groups is allowed and is the point; the
-- same person twice in one group is a row you would delete.
local function Holds(group, name)
	local key = People.Key(name)
	if not key or not index[key] then
		return false
	end
	for _, held in ipairs(index[key]) do
		if held == group then
			return true
		end
	end
	return false
end

function People.Add(position, name)
	local group = ns.db.groups[position]
	if not group then
		return nil, "no group is selected"
	end
	if #group.members >= People.MAX then
		return nil, ("%d is as many people as a group holds"):format(People.MAX)
	end

	-- A blank one is allowed and is what the + button makes: the row appears,
	-- the field under it takes the name, and the list is saved when it does. A
	-- blank entry matches nothing, because Key answers nil for it.
	name = name or ""
	if Holds(group, name) then
		return nil, name .. " is already in " .. People.Name(position)
	end

	group.members[#group.members + 1] = name
	Reindex()
	member = #group.members
	return member
end

function People.Remove(position, at)
	local group = ns.db.groups[position]
	if not group or not group.members[at] then
		return false
	end
	table.remove(group.members, at)
	Reindex()
	member = Clamp(member, #group.members)
	return true
end

function People.Rename(position, at, name)
	local group = ns.db.groups[position]
	if not group or not group.members[at] then
		return false, "nobody is selected"
	end
	if Holds(group, name) and People.Key(group.members[at]) ~= People.Key(name) then
		return false, name .. " is already in " .. People.Name(position)
	end
	group.members[at] = name or ""
	Reindex()
	return true
end

-- Everyone you are grouped with, into one group, in one press. This is the
-- reason the list is bearable to fill in at all: three names typed by hand,
-- spelled right, with the right accents, is a chore, and a family that plays
-- together is a family that is already in your party when you think of it.
--
-- Party and raid tokens rather than ns.Unit.Roster, because the roster is keyed
-- by GUID for the meters and what is wanted here is the plain name, and because
-- this runs on a button press rather than on a tick.
function People.AddParty(position)
	local group = ns.db.groups[position]
	if not group then
		return 0, 0
	end

	local added, skipped = 0, 0
	local size = GetNumGroupMembers and GetNumGroupMembers() or 0
	local prefix = (IsInRaid and IsInRaid()) and "raid" or "party"

	for slot = 1, math.max(size, 0) do
		local unit = prefix .. slot
		if UnitExists(unit) and not UnitIsUnit(unit, "player") then
			if People.Add(position, UnitName(unit)) then
				added = added + 1
			else
				skipped = skipped + 1
			end
		end
	end
	return added, skipped
end

--------------------------------------------------------------------------
-- Saying what is there
--------------------------------------------------------------------------

-- What a group is called on a rail row and in a sentence. A group with no name
-- yet is the row the + button just made, and it still has to be findable.
function People.Name(position)
	local group = ns.db.groups[position]
	if not group then
		return "no group"
	end
	return group.name ~= "" and group.name or ("group %d"):format(position)
end

-- The group a slash word named, matched the way a person's name is: case
-- flattened, because "family" is what somebody types for a group they called
-- "Family".
function People.Find(name)
	local wanted = People.Key(name)
	if not wanted then
		return nil
	end
	for position, group in ipairs(ns.db.groups) do
		if People.Key(group.name) == wanted then
			return position, group
		end
	end
	return nil
end

function People.Describe()
	local groups, total = People.Count(), People.Total()
	if groups == 0 then
		return "no groups"
	end
	if groups == 1 then
		return ("%s, %d in it"):format(People.Name(1), total)
	end
	return ("%d groups, %d people"):format(groups, total)
end

--------------------------------------------------------------------------
-- The list before groups existed
--
-- One flat list of names lived in ns.db.people and had one tab in the window.
-- Everybody on it goes into a group called People, which is what it was, and
-- the old key is dropped. Nothing is lost and nobody retypes three names they
-- typed once.
--------------------------------------------------------------------------

local function Carry()
	local old = ns.db.people
	ns.db.people = nil
	if type(old) ~= "table" or #old == 0 then
		return false
	end

	local position = People.AddGroup("People")
	if not position then
		return false
	end
	for _, entry in ipairs(old) do
		if type(entry) == "table" then
			People.Add(position, entry.name)
		end
	end
	return true
end

--------------------------------------------------------------------------

-- The index is built from the saved list, so it cannot be built until the saved
-- variables are here.
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, _, name)
	if name ~= ADDON then
		return
	end
	Carry()
	Reindex()
	self:UnregisterEvent("ADDON_LOADED")
end)
