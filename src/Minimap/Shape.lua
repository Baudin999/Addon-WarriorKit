local ADDON, ns = ...

-- The minimap, square and as big as you asked for.
--
-- The round minimap is a mask and a ring of art, and neither carries any
-- information. The mask throws away the corners of a map the client has
-- already drawn, and the ring spends about twenty pixels of every edge on
-- rivets. Take both off and the same frame shows more world at the same size,
-- with an edge that lines up with every other edge in this addon.
--
-- Three rules shape the file, and they are the ones Artwork.lua works to as
-- well, because this is the same job on a different frame.
--
--   Everything is reversible in one call. The mask goes back, the art comes
--   back, the size goes back, and every button this file moved goes back to
--   the point it was found on. `off` is a state, not a reload.
--
--   Nothing is named that is not resolved through _G first. This client is TBC
--   art under a backported interface, and a texture the wiki names may not be
--   the one 2.5.6 has. A missing name is a skipped entry.
--
--   The map itself is never touched. Minimap:SetMaskTexture and
--   Minimap:SetSize are the whole of what happens to it. No hooks, no ticker,
--   nothing on the frame that draws the world.

local Shape = {}
ns.MinimapShape = Shape

-- The client's own mask, and the one every square-minimap addon writes in its
-- place. WHITE8X8 is a solid white texture that ships with the client, so a
-- mask made of it keeps every pixel of the square.
local ROUND_MASK = "Textures\\MinimapMask"
local SQUARE_MASK = "Interface\\Buttons\\WHITE8X8"

-- What the client draws it at, used only where the client will not say. Read
-- from the frame before anything here writes to it, which is what the first
-- Apply does.
local BLIZZARD_SIZE = 140

-- The ring, and the two controls that only make sense on a ring. The zoom
-- buttons sit on the arc and would hang off the corners of a square; the
-- mousewheel replaces them below, which is where every other client has put
-- zoom for fifteen years.
local ART = {
	"MinimapBorder",
	"MinimapBorderTop",
	"MinimapNorthTag",
	"MinimapZoomIn",
	"MinimapZoomOut",
	"MiniMapWorldMapButton",
}

-- Blizzard's own minimap buttons, which are not addon buttons and are not the
-- corral's business. They are anchored to points on the arc, so on a square
-- they end up floating outside it. Each is pulled to the corner named here.
--
-- Two spellings of the tracking button because the clients disagree, and both
-- are tried. A name this client does not have is skipped.
local CORNERS = {
	{ "MiniMapTracking", "TOPLEFT", 1, -1 },
	{ "MiniMapTrackingFrame", "TOPLEFT", 1, -1 },
	{ "MiniMapMailFrame", "TOPRIGHT", -1, -1 },
	{ "MiniMapBattlefieldFrame", "BOTTOMRIGHT", -1, 1 },
	{ "MiniMapMeetingStoneFrame", "BOTTOMRIGHT", -1, 1 },
	{ "GameTimeFrame", "BOTTOMLEFT", 1, 1 },
}

local border, applied
local original = {}   -- what each moved button was anchored to before this file moved it
local wheelWas = nil  -- the mousewheel handler the client had, if it had one
local wheelTaken = false

--------------------------------------------------------------------------
-- The frame
--------------------------------------------------------------------------

local function Map()
	local map = _G.Minimap
	if type(map) ~= "table" or type(map.SetSize) ~= "function" then
		return nil
	end
	return map
end

-- What the client draws it at, asked once and then remembered. Asked on the
-- first Apply rather than at load, because at load the frame may not have been
-- sized yet, and remembered because by the second Apply the number on the
-- frame is one this file wrote.
local blizzardSize

local function Original(map)
	if not blizzardSize then
		local width = ns.Measure(map, "GetWidth")
		blizzardSize = (type(width) == "number" and width > 0) and width or BLIZZARD_SIZE
	end
	return blizzardSize
end

--------------------------------------------------------------------------
-- Moving what the ring used to hold
--------------------------------------------------------------------------

local function Remember(name, button)
	if original[name] then
		return
	end
	local point, relativeTo, relativePoint, x, y = button:GetPoint()
	if not point then
		-- A button with no point of its own is one the client positions some
		-- other way. Recorded as false so it is never moved and never asked
		-- again, rather than as nil, which would look like "not seen yet".
		original[name] = false
		return
	end
	original[name] = { point, relativeTo, relativePoint, x, y }
end

local function Corner(map, square)
	for _, entry in ipairs(CORNERS) do
		local name, point, x, y = entry[1], entry[2], entry[3], entry[4]
		local button = _G[name]
		if type(button) == "table" and type(button.SetPoint) == "function" then
			Remember(name, button)
			local was = original[name]
			if was then
				button:ClearAllPoints()
				if square then
					button:SetPoint(point, map, point, x, y)
				else
					button:SetPoint(was[1], was[2], was[3], was[4], was[5])
				end
			end
		end
	end
end

--------------------------------------------------------------------------
-- Zoom
--
-- The two buttons are art on the arc and go with the rest of it, so the wheel
-- has to do their job. The handler the client had is kept and put back, on the
-- chance that a client or an addon had already claimed it.
--------------------------------------------------------------------------

local function Wheel(map, square)
	if square and not wheelTaken then
		wheelWas = map:GetScript("OnMouseWheel")
		wheelTaken = true
		map:EnableMouseWheel(true)
		map:SetScript("OnMouseWheel", function(self, delta)
			local levels = self.GetZoomLevels and self:GetZoomLevels() or 5
			local zoom = (self.GetZoom and self:GetZoom() or 0) + (delta > 0 and 1 or -1)
			if zoom < 0 then
				zoom = 0
			elseif zoom > levels - 1 then
				zoom = levels - 1
			end
			self:SetZoom(zoom)
		end)
	elseif not square and wheelTaken then
		map:SetScript("OnMouseWheel", wheelWas)
		map:EnableMouseWheel(wheelWas ~= nil)
		wheelWas, wheelTaken = nil, false
	end
end

--------------------------------------------------------------------------
-- The edge
--
-- One pixel, in the addon's own colour, drawn on a frame of ours rather than
-- on the minimap. Nothing here is a texture on somebody else's frame, so the
-- client's own update code has nothing to argue with.
--------------------------------------------------------------------------

local function Edge(map)
	if border then
		return border
	end
	border = CreateFrame("Frame", nil, map)
	border:SetPoint("TOPLEFT", map, "TOPLEFT", 0, 0)
	border:SetPoint("BOTTOMRIGHT", map, "BOTTOMRIGHT", 0, 0)
	border.edges = ns.Outline(border, ns.UI.Color.edge[1], ns.UI.Color.edge[2],
		ns.UI.Color.edge[3], 1)
	return border
end

--------------------------------------------------------------------------

function Shape.Apply()
	if not ns.db then
		return
	end
	local map = Map()
	if not map then
		return
	end

	-- Read before anything below writes to the frame, so the number that gets
	-- remembered as the client's own is the client's and not one of this
	-- file's from the last Apply.
	local was = Original(map)

	local square = ns.db.minimapSquare
	local size = square and ns.db.minimapSize or was

	map:SetSize(size, size)

	-- The cluster is what the rest of the interface anchors under. Left at the
	-- client's own size the buffs would sit on top of a bigger map, and the
	-- padding the client keeps around the frame is the difference between the
	-- two, so it is carried rather than guessed at.
	local cluster = _G.MinimapCluster
	if type(cluster) == "table" and type(cluster.SetSize) == "function" then
		local padding = 52 -- what TBC leaves round a 140 map for the ring and the zone text
		cluster:SetSize(size + padding, size + padding)
	end

	if type(map.SetMaskTexture) == "function" then
		map:SetMaskTexture(square and SQUARE_MASK or ROUND_MASK)
	end

	for _, name in ipairs(ART) do
		local region = _G[name]
		if region then
			if square then
				ns.Strip(region)
			else
				ns.Unstrip(region)
			end
		end
	end

	Corner(map, square)
	Wheel(map, square)
	Edge(map):SetShown(square)

	applied = square
end

-- Whether the square is actually on the frame, which is not the same as the
-- setting saying so. A client with no SetMaskTexture takes the size and keeps
-- its round mask, and the panel should say that rather than claim a square.
function Shape.Square()
	return applied == true
end

function Shape.Size()
	local map = Map()
	if not map then
		return nil
	end
	return ns.Measure(map, "GetWidth")
end

function Shape.Describe()
	local map = Map()
	if not map then
		return "not applied, this client has no Minimap frame to reshape"
	end
	if not ns.db.minimapSquare then
		return ("round and %d wide, the client's own"):format(Original(map))
	end
	local masked = type(map.SetMaskTexture) == "function"
	return ("%s and %d wide, the client's is %d"):format(
		masked and "square" or "still round, this client will not take a mask",
		ns.db.minimapSize, Original(map))
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
	Shape.Apply()
end)
