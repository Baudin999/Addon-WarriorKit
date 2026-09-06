-- Socketing.
--
-- The whole of the client's socketing conversation, which is a server session
-- rather than a call: it is opened on one item, it keeps two answers per hole
-- while it is up, and paying is a separate act that destroys what it replaces.
-- Modelled rather than waved through, because every claim the window makes is
-- about the difference between those two answers.
--
-- The helmet 13-character.lua wears is the piece with holes in it and this file
-- adds nothing to it: two holes, the first empty and the second holding the
-- Bold Living Ruby that fixture already put there, which is the shape
-- ns.ItemSockets was written against.
--
-- **The colour rule is the server's here.** Core/Sockets.lua carries the same
-- rule and uses it to decide which gems a window offers first; this one uses it
-- to answer `matches`, which is what says whether the socket bonus is paid. The
-- two are deliberately written out twice, because the addon must not compute
-- the second from the first: a section that put a red gem in a yellow hole and
-- read a bonus back would be reading the addon's own opinion.
--
-- **Blizzard's own frame is here too.** It arrives with a load-on-demand addon
-- of Blizzard's, so it is made hidden and the section fires the ADDON_LOADED
-- that would have built it. The addon parks it off the side of the screen, and
-- a frame with no size has no edges to read, which is 17-merchant.lua's note
-- about the merchant window and the same reason.

local H = ...
local region, ITEMS, itemLink = H.region, H.ITEMS, H.itemLink
local worn = H.worn

-- Four gems, one per hole colour that matters and one that fits two holes.
-- The subclass numbers are the client's, read off Questie's tbcItemDB.lua
-- rather than typed: Living Ruby is class 3 subclass 0, Dawnstone 2, Nightseye
-- 3 and Skyfire Diamond 6. Tigerseye is already in 04-hands.lua at subclass 7,
-- which is the vanilla jewel that goes in no hole at all, and it is left there
-- so this file does not have to add the one gem the window must leave out.
ITEMS["Bold Ornate Ruby"] = { id = 8001, classId = 3, subClassId = 0,
	quality = 3, price = 900, icon = "Interface\\Icons\\GemRed" }
ITEMS["Rigid Dawnstone"] = { id = 8002, classId = 3, subClassId = 2,
	quality = 3, price = 900, icon = "Interface\\Icons\\GemYellow" }
ITEMS["Shifting Nightseye"] = { id = 8003, classId = 3, subClassId = 3,
	quality = 3, price = 900, icon = "Interface\\Icons\\GemPurple" }
ITEMS["Relentless Earthstorm Diamond"] = { id = 8004, classId = 3, subClassId = 6,
	quality = 4, price = 4000, icon = "Interface\\Icons\\GemMeta" }

-- Which subclass goes in which hole. The server's copy of the rule.
local FITS = {
	Red = { [0] = true, [3] = true, [5] = true },
	Yellow = { [2] = true, [5] = true, [4] = true },
	Blue = { [1] = true, [3] = true, [4] = true },
	Meta = { [6] = true },
}

-- The holes in each thing you can be wearing, by inventory slot. One entry,
-- because one piece in this client has any: the helmet, whose second hole
-- already holds a gem in 13-character.lua and whose first is the empty one
-- ns.ItemSockets counts.
local HOLES = {
	[1] = {
		{ colour = "Red" },
		{ colour = "Red", gem = "Bold Living Ruby" },
	},
}

-- The session, or nil. `gem` is what is in the hole and `new` is what has been
-- put in front of it and not paid for, which is the split the whole window is
-- about.
local session = nil

local function matches(name, colour)
	local item = name and ITEMS[name]
	local row = FITS[colour]
	return (item and row and row[item.subClassId]) and true or false
end

local function holes()
	return session and HOLES[session.slot] or nil
end

_G.ItemSocketingFrame = region("frame")
_G.ItemSocketingFrame:SetSize(300, 340)
_G.ItemSocketingFrame:Hide()

_G.SocketInventoryItem = function(slot)
	if not HOLES[slot] then
		return
	end
	session = { slot = slot }
	for _, hole in ipairs(HOLES[slot]) do
		hole.new = nil
	end
	_G.ItemSocketingFrame:Show()
	H.fire("SOCKET_INFO_UPDATE")
end

-- The other way in, which nothing in the addon calls yet and the client still
-- has. It reaches the same session, which is the fact the window is built on.
_G.SocketContainerItem = function()
	return false
end

_G.CloseSocketInfo = function()
	if not session then
		return
	end
	local list = holes()
	for _, hole in ipairs(list) do
		hole.new = nil
	end
	session = nil
	_G.ItemSocketingFrame:Hide()
	H.fire("SOCKET_INFO_CLOSE")
end

_G.GetNumSockets = function()
	local list = holes()
	return list and #list or 0
end

_G.GetSocketTypes = function(index)
	local list = holes()
	local hole = list and list[index]
	return hole and hole.colour or nil
end

_G.GetSocketItemInfo = function()
	if not session then
		return nil
	end
	local name = (worn[session.slot] or ""):match("%[(.-)%]")
	local item = name and ITEMS[name]
	if not item then
		return nil
	end
	return name, item.icon, item.quality
end

local function reader(field)
	return function(index)
		local list = holes()
		local hole = list and list[index]
		local name = hole and hole[field]
		if not name then
			return nil
		end
		return name, ITEMS[name].icon, matches(name, hole.colour)
	end
end

local function linker(field)
	return function(index)
		local list = holes()
		local hole = list and list[index]
		return hole and hole[field] and itemLink(hole[field]) or nil
	end
end

_G.GetExistingSocketInfo, _G.GetExistingSocketLink = reader("gem"), linker("gem")
_G.GetNewSocketInfo, _G.GetNewSocketLink = reader("new"), linker("new")

-- The client's one gesture for a hole, and what it does depends on the cursor.
-- Holding a gem puts it in front of the hole and takes it off the cursor;
-- holding nothing hands back whatever was waiting there, onto the cursor, which
-- is where the addon's ClearCursor then puts it back in the bag.
_G.ClickSocketButton = function(index)
	local list = holes()
	local hole = list and list[index]
	if not hole then
		return
	end
	local kind, _, link = _G.GetCursorInfo()
	local name = kind == "item" and link and link:match("%[(.-)%]") or nil
	if name and ITEMS[name] and ITEMS[name].classId == 3 then
		hole.new = name
		_G.ClearCursor()
	elseif not kind and hole.new then
		H.hold({ id = ITEMS[hole.new].id, link = itemLink(hole.new) })
		hole.new = nil
	end
	H.fire("SOCKET_INFO_UPDATE")
end

_G.AcceptSockets = function()
	local list = holes()
	if not list then
		return
	end
	local spent = 0
	for _, hole in ipairs(list) do
		if hole.new then
			hole.gem = hole.new
			hole.new = nil
			spent = spent + 1
		end
	end
	if spent == 0 then
		H.fire("SOCKET_INFO_FAILURE")
		return
	end
	H.fire("SOCKET_INFO_SUCCESS")
	H.fire("SOCKET_INFO_UPDATE")
end

-- The two halves of "this would stop being tradeable", both false unless a
-- section says otherwise: nothing in this client is a group drop inside its two
-- hours, and modelling that clock would be modelling the server.
local bound = { tradeable = false, proposed = false }
_G.GetSocketItemBoundTradeable = function() return bound.tradeable end
_G.HasBoundGemProposed = function() return bound.proposed end

-- What a section drives the scene with.
H.sockets = {
	holes = HOLES,
	bound = bound,
	open = function() return session ~= nil end,
	-- Blizzard's load-on-demand addon arriving, which is what the addon's own
	-- watcher listens for and cannot be made to happen any other way here.
	arrive = function() H.fire("ADDON_LOADED", "Blizzard_ItemSocketingUI") end,
}
