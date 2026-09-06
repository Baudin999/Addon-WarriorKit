local ADDON, ns = ...

local Sockets = {}
ns.Sockets = Sockets

--------------------------------------------------------------------------
-- The socketing session, and the gems you are carrying
--
-- Putting a gem in a hole is not one call. It is a conversation with the
-- server, opened on one item, held while you try gems in it, and closed again,
-- and every step of it is a loose global on the client this addon is written
-- for. This file is that conversation, shimmed once, the same way ns.Questie
-- and the thirty container calls above are shimmed once: a part does not probe
-- the client for a call it means to make.
--
-- **The session is the client's and there is only one.** SocketInventoryItem
-- opens it on a slot you are wearing and SocketContainerItem on a slot in a
-- bag. Either one fires SOCKET_INFO_UPDATE, and from that moment the reads
-- below answer about that item and no other. Opening a second one closes the
-- first. Nothing here holds a copy of what the session says, because a copy is
-- a thing that can disagree with the server about what is in the hole.
--
-- **A gem you have clicked is not a gem you have socketed.** The client keeps
-- two answers per hole and the difference is the whole reason this is a window
-- rather than a click: Filled is what is in the item now, Waiting is what you
-- have put in front of it and not yet paid for. Apply is what pays, and it is
-- the point of no return, because the gem it replaces is destroyed.
--
-- **The colour rule is the expansion's and it is written down here.** A red
-- hole takes a red, a purple or an orange; a yellow takes a yellow, an orange
-- or a green; a blue takes a blue, a purple or a green; a meta hole takes a
-- meta and nothing else. The numbers those colours are are the client's own
-- item subclasses, and they were read out of Questie's TBC item database
-- rather than typed from memory: Living Ruby is 0, Star of Elune 1, Dawnstone
-- 2, Nightseye 3, Talasite 4, Noble Topaz 5, Skyfire Diamond 6.
--
-- The rule only decides what a window offers you first. Whether a gem actually
-- matched is the client's own answer, handed back by Filled and Waiting as
-- `matches`, so a table that went out of date could sort a list wrongly and
-- cannot make the addon claim a socket bonus that is not there.
--
-- **Nothing here exists on the older client.** Sockets arrived with the Burning
-- Crusade. On Classic Era every call below is missing, Available answers false,
-- and the part that draws the window never opens one.
--------------------------------------------------------------------------

-- The most holes anything in this expansion carries.
local MOST = 3

-- The backpack is 0 and neither client has a reagent bag, which is Core/Gear's
-- number and the same walk.
local LAST_BAG = 4

-- Class 3 is a gem, whatever colour it is. Baganator files on the same number
-- and ns.ItemKind above is what answers it.
local GEM_CLASS = 3

-- Which gem goes in which hole, keyed by the socket colour the client names
-- and holding the item subclasses that fit it. Subclass 7 is Simple, which is
-- every jewel from the expansion before this one, and it is on no list because
-- it fits nothing: a Tigerseye in your bags is a gem the client agrees is a gem
-- and is not a thing you can socket.
local FITS = {
	Red = { [0] = true, [3] = true, [5] = true },
	Yellow = { [2] = true, [5] = true, [4] = true },
	Blue = { [1] = true, [3] = true, [4] = true },
	Meta = { [6] = true },
}

-- Every subclass that fits something, which is what tells a socketing gem from
-- a vendor trash jewel without naming the colours twice.
local SOCKETABLE = {}
for _, colours in pairs(FITS) do
	for subclass in pairs(colours) do
		SOCKETABLE[subclass] = true
	end
end

--------------------------------------------------------------------------
-- Where the client keeps it
--------------------------------------------------------------------------

-- One call of the client's, from whichever of the two places this build put it.
--
-- The newer client moved the reads into C_ItemSocketInfo and left the loose
-- globals behind a CVar; 2.5.6 has the globals and no namespace at all. The two
-- calls that open a session were never moved and are only ever loose, so the
-- namespace lookup misses for them and the global answers, which is the same
-- fallback ns.ItemInfo makes for the same reason.
--
-- Looked up on every call rather than resolved once at load. The namespace is
-- built by an addon of Blizzard's own that loads when something first asks for
-- it, so a name resolved at login can be nil for the whole session on a client
-- where it exists.
local function Call(name)
	local box = _G.C_ItemSocketInfo
	if type(box) == "table" and type(box[name]) == "function" then
		return box[name]
	end
	if type(_G[name]) == "function" then
		return _G[name]
	end
	return nil
end

-- Whether this client can socket at all. Read before anything is drawn and
-- before the paperdoll's shift click does anything but what it always did.
function Sockets.Available()
	return Call("GetNumSockets") ~= nil and Call("SocketInventoryItem") ~= nil
end

--------------------------------------------------------------------------
-- Opening and closing it
--------------------------------------------------------------------------

-- Start a session on a slot you are wearing. The event is what the window
-- listens to, so this answers whether the client was asked rather than whether
-- anything came back.
function Sockets.Open(slot)
	local open = Call("SocketInventoryItem")
	if not open or type(slot) ~= "number" then
		return false
	end
	open(slot)
	return true
end

-- The same on a slot in a bag, which is the other half of what the client's own
-- shift click reaches. Nothing in this addon calls it yet; it is here because
-- the session does not care which of the two opened it, and a shim written
-- against only one of them is a shim that goes wrong the day a bag square
-- learns the gesture.
function Sockets.OpenBag(bag, slot)
	local open = Call("SocketContainerItem")
	if not open or type(bag) ~= "number" or type(slot) ~= "number" then
		return false
	end
	open(bag, slot)
	return true
end

-- End it. Every route out of the window comes through here, because a session
-- the player has walked away from is still open on the server.
function Sockets.Close()
	local shut = Call("CloseSocketInfo")
	if not shut then
		return false
	end
	shut()
	return true
end

--------------------------------------------------------------------------
-- Reading it
--------------------------------------------------------------------------

-- How many holes the item in the session has. Zero is both "nothing is open"
-- and "the thing that is open has no holes", and the window treats them the
-- same way, because there is nothing to draw either way.
function Sockets.Count()
	local count = Call("GetNumSockets")
	if not count then
		return 0
	end
	local held = count()
	return type(held) == "number" and held or 0
end

-- The piece being worked on: its name, its picture and its grade.
function Sockets.Piece()
	local read = Call("GetSocketItemInfo")
	if not read then
		return nil
	end
	return read()
end

-- What colour one hole is, as the client's own word: Red, Yellow, Blue or Meta.
-- Not localised, which is why the table above can be keyed on it.
--
-- The client answers an empty string for a hole with no colour, which is what
-- FrameXML's own socketing frame branches on before it draws a rim, and that is
-- nil here. A caller reading "" would key the fit table on it, get nothing, and
-- say the hole is a colour called nothing rather than saying it does not know.
function Sockets.Colour(index)
	local read = Call("GetSocketTypes")
	if not read or type(index) ~= "number" then
		return nil
	end
	local colour = read(index)
	if colour == nil or colour == "" then
		return nil
	end
	return colour
end

-- Both answers about one hole have the same three returns and differ only in
-- which pair of calls they make, so they are one function with the names passed
-- in.
local function Read(info, link, index)
	local read = Call(info)
	if not read or type(index) ~= "number" then
		return nil
	end
	local name, icon, matches = read(index)
	if not name then
		return nil
	end
	local text = Call(link)
	return name, icon, text and text(index) or nil, matches and true or false
end

-- The gem that is in the hole now. Nil for an empty one.
function Sockets.Filled(index)
	return Read("GetExistingSocketInfo", "GetExistingSocketLink", index)
end

-- The gem you have put in front of it and not yet paid for. Nil where you have
-- put nothing there this session.
function Sockets.Waiting(index)
	return Read("GetNewSocketInfo", "GetNewSocketLink", index)
end

--------------------------------------------------------------------------
-- Changing it
--------------------------------------------------------------------------

-- The client's one gesture for a hole, and it does two things depending on what
-- is on the cursor. With a gem held it puts that gem in front of the hole; with
-- nothing held it hands back whatever was waiting there.
--
-- Both halves end by clearing the cursor, and that is not tidying up. A gem
-- handed back lands on the cursor and stays there, so a player who took one out
-- and then clicked anything else would be dropping it wherever they clicked;
-- ClearCursor is what puts it back in the bag it came from. Narcissus makes the
-- same three calls in the same order on this client, which is the proof this
-- dance is the one the client expects.
local function Click(index)
	local click = Call("ClickSocketButton")
	if not click or type(index) ~= "number" then
		return false
	end
	click(index)
	local drop = Call("ClearCursor")
	if drop then
		drop()
	end
	return true
end

-- Put the gem in this bag slot in front of this hole.
--
-- Picking the slot up is the only way in. PickupItem on the item's own id looks
-- like the shorter route and does not work here, which is a thing Narcissus
-- found first and says so in a comment; the cursor has to be holding the stack
-- out of your bags.
function Sockets.Put(index, bag, slot)
	if not ns.PickupContainerItem(bag, slot) then
		return false
	end
	return Click(index)
end

-- Take back the gem waiting in this hole, leaving whatever was already
-- socketed alone. Nothing on the cursor is what makes it a take rather than a
-- put, so the window has to have finished its last click before this one.
function Sockets.Take(index)
	if not Sockets.Waiting(index) then
		return false
	end
	return Click(index)
end

-- Pay for it. Everything waiting goes in, everything it replaces is destroyed,
-- and the client answers with SOCKET_INFO_SUCCESS or SOCKET_INFO_FAILURE.
function Sockets.Apply()
	local accept = Call("AcceptSockets")
	if not accept then
		return false
	end
	accept()
	return true
end

-- Whether paying would cost you the right to give the item away.
--
-- An item somebody in your group helped you win is tradeable back to that group
-- for two hours, and a gem flagged soulbound ends that early. The client keeps
-- the two halves apart and both have to hold, so the window asks one question
-- and gets one answer.
function Sockets.Binds()
	local tradeable, proposed = Call("GetSocketItemBoundTradeable"), Call("HasBoundGemProposed")
	if not tradeable or not proposed then
		return false
	end
	return (tradeable() and proposed()) and true or false
end

--------------------------------------------------------------------------
-- What you are carrying
--------------------------------------------------------------------------

-- Whether a gem of this subclass goes in a hole of this colour.
--
-- A colour the table does not know answers false rather than true. A hole this
-- addon has never heard of is a hole nothing should be offered for, and the
-- client's own `matches` is still what says whether the gem you did put in
-- earned the bonus.
function Sockets.Fits(subclass, colour)
	local colours = FITS[colour]
	return (colours and subclass and colours[subclass]) and true or false
end

-- Every gem in your bags, in bag order.
--
-- Walked rather than cached. A gem leaves your bags the moment you socket it
-- and arrives the moment somebody cuts one for you, and eighty odd bag slots
-- read on the events that change either is cheaper than a table that can be
-- wrong about what you are holding.
--
-- What comes back is the slot, not the item: the window puts a gem in a hole by
-- picking that slot up, so the bag and the index are the part it cannot do
-- without and the link is what draws it.
function Sockets.Gems()
	local found = {}
	for bag = 0, LAST_BAG do
		for slot = 1, ns.ContainerSlots(bag) do
			local link = ns.ContainerItemLink(bag, slot)
			local _, class, subclass = ns.ItemKind(link)
			if class == GEM_CLASS and SOCKETABLE[subclass] then
				local name, icon = ns.ItemInfo(link)
				local quality = ns.ItemValue(link)
				found[#found + 1] = {
					bag = bag, slot = slot, link = link,
					name = name, icon = icon, quality = quality,
					colour = subclass,
				}
			end
		end
	end
	return found
end

-- The most holes anything carries, for a window that has to build its squares
-- before it knows what it is looking at.
function Sockets.Most()
	return MOST
end
