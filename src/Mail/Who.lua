local ADDON, ns = ...

local Who = {}
ns.MailWho = Who

--------------------------------------------------------------------------
-- Who you are about to mail
--
-- One question with three answers, and the whole mail window is coloured by
-- it: a character on your own account, somebody you know, and everybody else.
--
-- **Why this exists at all.** The client's mail window has one recipient field
-- and it looks the same whatever you type in it. Your bank alt, a guild member
-- you have never spoken to and a name off the auction house are the same eleven
-- pixels of white text, and the only thing standing between the second two and
-- four hundred gold is that you read what you typed. That is not a safety net,
-- it is a habit, and a habit fails at eleven at night.
--
-- So a name is resolved to one of three relations before anything is drawn, and
-- the answer is a colour rather than a sentence. Green is yours. Blue is
-- somebody you know. Red is a stranger, which is not an error and is not a
-- refusal: it is the one case where sending gold or a stack of anything asks you
-- twice, and Mail/Draft.lua is where that rule lives.
--
-- **Favourites are a different axis and are on purpose.** A relation is what the
-- client and the addon can work out about a name; a favourite is a name you put
-- on a list because you mail it. Most favourites will be green or blue and that
-- is fine, but the two are not the same question: a guild bank alt you mail
-- weekly is a stranger by relation and belongs on the list, and an alt you have
-- not touched since the addon met it is green and does not. The list is what the
-- rail down the left of the window draws and what the warning is measured
-- against.
--
-- **Where the answers come from.** The friends list is the client's own and is
-- read here, because it is an API rather than another part of this addon.
-- Everything else arrives through Who.Also and Who.AlsoAlt, which Mail/Feature
-- fills in: the addon's own groups of people who matter, and the purse ledger,
-- which is the only list of your own characters that exists. A part may not name
-- a file outside its own folder, and both of those are one, so the tests are
-- registered rather than called.
--
-- The guild is deliberately not one of them. A guild of five hundred is a list
-- of people you are in a channel with, not a list of people you know, and a
-- colour that says "friend" for every one of them says nothing at all.
--
-- Names are matched normalised: realm suffix off, case flattened, spaces
-- trimmed, which is what Chat/People.lua does and for the same reasons. The cost
-- is the same one: two characters of the same name on different realms read as
-- the same person.
--------------------------------------------------------------------------

Who.ALT, Who.FRIEND, Who.STRANGER = "alt", "friend", "stranger"

-- The most names the rail holds. Not a technical limit and not arbitrary: a
-- quick-pick list is one you take a name off by looking, and past a couple of
-- dozen you are reading rather than looking, at which point the field beside it
-- is faster than the list.
Who.MAX = 24

-- Extra tests, registered by Mail/Feature.lua rather than called from here.
-- Each is handed a normalised key and answers true or false.
local friendTests, altTests = {}, {}

-- The client's own friends list, normalised, rebuilt on FRIENDLIST_UPDATE
-- rather than walked per question. A recipient field answers this on every
-- keystroke and the answer changes about once an evening.
local friends = {}

--------------------------------------------------------------------------

-- What two names have to agree on to be the same person. Nil for anything that
-- is not a name, so an empty field cannot match an empty sender.
function Who.Key(name)
	if type(name) ~= "string" then
		return nil
	end
	local trimmed = name:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%-.*$", "")
	if trimmed == "" then
		return nil
	end
	return trimmed:lower()
end

-- Register another test. Both take a normalised key.
function Who.Also(test)
	friendTests[#friendTests + 1] = test
	return #friendTests
end

function Who.AlsoAlt(test)
	altTests[#altTests + 1] = test
	return #altTests
end

--------------------------------------------------------------------------
-- The friends list
--
-- Two clients and two spellings. C_FriendList is the newer home and the loose
-- globals are the older one, so both are probed and a client with neither loses
-- the blue rather than raising: an unknown friend reads as a stranger, which is
-- the safe way round to be wrong.
--------------------------------------------------------------------------

local function EachFriend(visit)
	local list = _G.C_FriendList
	if list and list.GetNumFriends and list.GetFriendInfoByIndex then
		for index = 1, list.GetNumFriends() or 0 do
			local info = list.GetFriendInfoByIndex(index)
			visit(info and info.name)
		end
		return true
	end

	if type(_G.GetNumFriends) == "function" and type(_G.GetFriendInfo) == "function" then
		for index = 1, _G.GetNumFriends() or 0 do
			visit((_G.GetFriendInfo(index)))
		end
		return true
	end
	return false
end

local function Note(name)
	local key = Who.Key(name)
	if key then
		friends[key] = true
	end
end

function Who.Rescan()
	wipe(friends)
	return EachFriend(Note)
end

function Who.FriendCount()
	local count = 0
	for _ in pairs(friends) do
		count = count + 1
	end
	return count
end

--------------------------------------------------------------------------
-- The three answers
--------------------------------------------------------------------------

local function Any(tests, key)
	for index = 1, #tests do
		if tests[index](key) then
			return true
		end
	end
	return false
end

-- Which of the three a name is. Your own character counts as an alt, because
-- mailing yourself is the ordinary way to move something between bags and the
-- bank and there is nothing to warn about.
function Who.Of(name)
	local key = Who.Key(name)
	if not key then
		return Who.STRANGER
	end
	if key == Who.Key(UnitName("player")) or Any(altTests, key) then
		return Who.ALT
	end
	if friends[key] or Any(friendTests, key) then
		return Who.FRIEND
	end
	return Who.STRANGER
end

function Who.Color(relation)
	local C = ns.UI.Color
	if relation == Who.ALT then
		return C.alt
	end
	if relation == Who.FRIEND then
		return C.friend
	end
	return C.stranger
end

-- One line under the recipient field, saying in words what the colour says in
-- colour. Both, because a colour is not readable to everyone and because the
-- sentence is what a screenshot of a mistake will carry.
function Who.Say(name)
	if not Who.Key(name) then
		return "nobody yet"
	end
	local relation = Who.Of(name)
	local starred = Who.Favourite(name) and ", a favourite" or ""
	if relation == Who.ALT then
		return "one of yours" .. starred
	end
	if relation == Who.FRIEND then
		return "somebody you know" .. starred
	end
	if starred ~= "" then
		return "not on your friends list, and a favourite"
	end
	return "a name this addon has never seen"
end

--------------------------------------------------------------------------
-- The favourites
--
-- An ordered list of names, account-wide, because who you mail is a fact about
-- you rather than about the character you are standing in. Names as typed, so
-- the rail draws "Aria" rather than "aria", and matched normalised, so it finds
-- her whichever way you type it.
--------------------------------------------------------------------------

function Who.Favourites()
	return ns.db.mailFavourites
end

function Who.Count()
	return #ns.db.mailFavourites
end

function Who.At(position)
	return ns.db.mailFavourites[position]
end

function Who.Find(name)
	local key = Who.Key(name)
	if not key then
		return nil
	end
	for position, held in ipairs(ns.db.mailFavourites) do
		if Who.Key(held) == key then
			return position
		end
	end
	return nil
end

function Who.Favourite(name)
	return Who.Find(name) ~= nil
end

-- Every one of these answers a reason rather than printing one, which is the
-- house shape: a behaviour file does not talk to the player, Feature.lua does,
-- and the window shows the same string in its own furniture.
function Who.Add(name)
	if not Who.Key(name) then
		return nil, "a favourite needs a name"
	end
	if Who.Favourite(name) then
		return nil, name .. " is already a favourite"
	end
	local list = ns.db.mailFavourites
	if #list >= Who.MAX then
		return nil, ("%d is as many favourites as the rail holds"):format(Who.MAX)
	end
	list[#list + 1] = name
	return #list
end

function Who.Remove(name)
	local at = Who.Find(name)
	if not at then
		return false, (name or "that") .. " is not a favourite"
	end
	table.remove(ns.db.mailFavourites, at)
	return true
end

function Who.Describe()
	local count = Who.Count()
	if count == 0 then
		return "no favourites yet"
	end
	return ("%d favourites, %d friends known"):format(count, Who.FriendCount())
end

--------------------------------------------------------------------------

-- The friends list is not there at load and is not there at PLAYER_LOGIN
-- either: the server sends it when it is ready and says so with this event,
-- which arrives again every time somebody on it comes or goes. Rescanning on
-- each is a walk over a list of twenty on an event that fires a handful of
-- times an hour, which is cheaper than caching anything cleverer.
local events = CreateFrame("Frame")
events:RegisterEvent("FRIENDLIST_UPDATE")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" and type(_G.ShowFriends) == "function" then
		-- The older client will not send the list until it is asked. Probed and
		-- pcalled like everything else this addon is not sure of, and a client
		-- that refuses loses the blue on names it would have known.
		pcall(_G.ShowFriends)
	end
	Who.Rescan()
end)
