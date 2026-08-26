local ADDON, ns = ...

local People = {}
ns.People = People

--------------------------------------------------------------------------
-- The people who matter
--
-- A short list of names. Anything any of them says, in any channel, is copied
-- to one tab of its own, so a wife in party chat and a son whispering from two
-- zones away land in the same place and neither of them scrolls past behind a
-- guild argument about loot.
--
-- One tab for all of them, not a tab per person. A tab per person is a row of
-- stubs you have to read the labels of, and it splits a conversation between
-- three people into three windows; what you actually want to know is whether
-- anyone you care about has said anything, and that is one question with one
-- answer.
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
-- The list is matched against normalised names: the realm suffix off, the case
-- flattened. The client sends "Aria" in party and "Aria-Firemaw" from another
-- realm, and both are the same person.
--------------------------------------------------------------------------

-- The cap. Not a technical limit, a shape one: this is the list of people you
-- would notice if they spoke, and a list of forty is a list you have stopped
-- reading. It also bounds the panel, which draws a row per person.
People.MAX = 20

-- Normalised name -> the entry it came from. Rebuilt whenever the list changes
-- rather than walked per message, because every line of chat in a raid asks
-- this question and the answer changes when you type in the panel.
local index = {}

-- Which one the panel is showing. Module state rather than a saved setting,
-- because it is where you are in a window rather than something you decided.
local shown = 1

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
	for _, entry in ipairs(ns.db.people) do
		local key = People.Key(entry.name)
		if key then
			index[key] = entry
		end
	end
end

ns.People.Reindex = Reindex

function People.All()
	return ns.db.people
end

function People.Count()
	return #ns.db.people
end

function People.Get(position)
	return ns.db.people[position]
end

function People.Shown()
	local count = People.Count()
	if shown > count then
		shown = count
	end
	if shown < 1 then
		shown = 1
	end
	return shown
end

function People.Show(position)
	shown = position
	return People.Shown()
end

--------------------------------------------------------------------------
-- Editing the list
--
-- Every one of these returns a reason rather than printing one. A part's
-- behaviour file does not talk to the player: Feature.lua does, and the panel
-- shows the same string in a note.
--------------------------------------------------------------------------

function People.Add(name)
	if People.Count() >= People.MAX then
		return nil, ("%d is as many people as the list holds"):format(People.MAX)
	end

	-- A blank one is allowed and is what the + button makes: the row appears,
	-- the field under it takes the name, and the list is saved when it does. A
	-- blank entry matches nothing, because Key answers nil for it.
	name = name or ""
	local key = People.Key(name)
	if key and index[key] then
		return nil, name .. " is already on the list"
	end

	local list = ns.db.people
	list[#list + 1] = { name = name }
	Reindex()
	shown = #list
	return shown
end

function People.Remove(position)
	local list = ns.db.people
	if not list[position] then
		return false
	end
	table.remove(list, position)
	Reindex()
	if shown > #list then
		shown = #list
	end
	return true
end

function People.Rename(position, name)
	local entry = ns.db.people[position]
	if not entry then
		return false, "nobody is selected"
	end

	local key = People.Key(name)
	if key and index[key] and index[key] ~= entry then
		return false, name .. " is already on the list"
	end

	entry.name = name or ""
	Reindex()
	return true
end

-- Everyone you are grouped with, in one press. This is the reason the list is
-- bearable to fill in at all: three names typed by hand, spelled right, with
-- the right accents, is a chore, and a family that plays together is a family
-- that is already in your party when you think of it.
--
-- Party and raid tokens rather than ns.Unit.Roster, because the roster is
-- keyed by GUID for the meters and what is wanted here is the plain name, and
-- because this runs on a button press rather than on a tick.
function People.AddGroup()
	local added, skipped = 0, 0
	local size = GetNumGroupMembers and GetNumGroupMembers() or 0
	local raid = IsInRaid and IsInRaid()
	local prefix = raid and "raid" or "party"

	for slot = 1, math.max(size, 0) do
		local unit = prefix .. slot
		if UnitExists(unit) and not UnitIsUnit(unit, "player") then
			local name = UnitName(unit)
			local key = People.Key(name)
			if key and not index[key] then
				if People.Add(name) then
					added = added + 1
				else
					skipped = skipped + 1
				end
			else
				skipped = skipped + 1
			end
		end
	end
	return added, skipped
end

--------------------------------------------------------------------------
-- Asking about one
--------------------------------------------------------------------------

-- The entry for a sender, or nil. This is the whole hot path of the part: it
-- runs once per line of chat and it is a table lookup on a string that had to
-- be built anyway.
function People.Match(sender)
	local key = People.Key(sender)
	if not key then
		return nil
	end
	return index[key]
end

function People.Describe()
	local count = People.Count()
	if count == 0 then
		return "nobody on the list"
	end
	if count == 1 then
		local entry = ns.db.people[1]
		local name = entry.name ~= "" and entry.name or "one unnamed row"
		return name
	end
	return ("%d people"):format(count)
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
	Reindex()
	self:UnregisterEvent("ADDON_LOADED")
end)
