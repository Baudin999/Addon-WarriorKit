local ADDON, ns = ...

local Paperdoll = {}
ns.Paperdoll = Paperdoll

local UI = ns.UI
local C = UI.Color

--------------------------------------------------------------------------
-- The gear page
--
-- Nineteen slots in the arrangement the client uses, and between the two
-- columns the four numbers the client's own sheet has never drawn: what your
-- gear averages, how worn it is, how many slots are empty and how often you
-- miss. Those four are the whole reason this page is not simply the client's
-- with a different border.
--
-- **There is no character model in the middle and that is deliberate.** The
-- middle of the client's sheet is a picture of your back. It is the largest
-- single area of the window and it answers no question: what you are wearing is
-- already drawn in the two columns either side of it, at the size you can read
-- the names of. So the space goes to the numbers instead.
--
-- The loadout tab of this same window does draw one, through `kit.Paperdoll`,
-- and the two are not in disagreement. There the model is showing you the pair
-- of weapons you just put in its hands, which is the whole subject of that page
-- and is a thing no square can show. Here it would be a picture of what the
-- nineteen squares already say.
--
-- **A square carries the durability of what is in it.** One line along the
-- bottom edge, drawn only where the piece is worn at all, green through to red.
-- Durability is the one fact about your gear that changes while you play and
-- the one the client hides behind a hover, and a repair bill you can see coming
-- is a repair bill that never surprises you in a doorway.
--
-- **Clicking is the client's own two calls.** Left is the cursor swap that
-- FrameXML's paperdoll button makes, right is the one that takes a piece off or
-- fires it where it has a use. Both are refused in a fight by the client, so
-- both are refused here first, with the reason printed: a slot that silently
-- does nothing is the worst version of this page. Core/Worn.lua carries the
-- argument in full.
--------------------------------------------------------------------------

-- The client draws its slots at thirty-six and this draws them at thirty-six,
-- for the reason UI/Widgets.lua borrows the client's slot ring: a square you
-- drag a helmet into should be the size of the square the helmet came out of.
local SQUARE = 36
local INSET = 2
local WEAR = 2

-- How far apart two squares in a column sit, and the air between a column and
-- the middle.
local GAP = 4

local Pane = {}
Pane.__index = Pane

--------------------------------------------------------------------------
-- One slot
--------------------------------------------------------------------------

local function Subject(entry)
	local link = ns.Worn.Link(entry.slot)
	if link then
		return { kind = "inventory", unit = "player", slot = entry.slot }
	end
	return { kind = "note", title = entry.label,
		lines = { { "empty", color = C.dim } } }
end

local function Act(entry, which)
	local ok, why
	if which == "RightButton" then
		ok, why = ns.Worn.Use(entry.slot)
	else
		ok, why = ns.Worn.Swap(entry.slot)
	end
	if not ok and why then
		ns.Print(why)
	end
	return ok
end

local function Square(pane, entry)
	local box = UI.Box(pane.frame, C.sunken, C.edge)
	box:SetSize(SQUARE, SQUARE)

	box.icon = UI.Icon(box, "ARTWORK")
	box.icon:SetPoint("TOPLEFT", INSET, -INSET)
	box.icon:SetPoint("BOTTOMRIGHT", -INSET, INSET)

	-- The client's own silhouette for an empty slot, uncropped: it is already
	-- the shape it draws at, and cropping it the way an item icon is cropped
	-- eats its own border.
	box.empty = box:CreateTexture(nil, "ARTWORK")
	box.empty:SetPoint("TOPLEFT", INSET, -INSET)
	box.empty:SetPoint("BOTTOMRIGHT", -INSET, INSET)
	box.empty:SetVertexColor(1, 1, 1, 0.3)

	box.wear = ns.Fill(box, "OVERLAY", C.tick[1], C.tick[2], C.tick[3], 1)
	box.wear:SetPoint("BOTTOMLEFT", INSET, INSET)
	box.wear:SetHeight(WEAR)
	box.wear:Hide()

	local button = CreateFrame("Button", nil, pane.frame)
	button:SetAllPoints(box)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:SetScript("OnClick", function(_, which)
		UI.CloseDropdown()
		if Act(entry, which) then
			pane:Paint()
		end
	end)
	button:SetScript("OnReceiveDrag", function()
		if Act(entry, "LeftButton") then
			pane:Paint()
		end
	end)
	button:SetScript("OnEnter", function(self)
		UI.Tint(box.bg, C.control)
		ns.Tip.Open(self, Subject(entry))
	end)
	button:SetScript("OnLeave", function()
		UI.Tint(box.bg, C.sunken)
		ns.Tip.Close()
	end)
	UI.PassCamera(button)

	box.button = button
	box.entry = entry
	return box
end

-- What colour a durability line is at a given fraction. Three stops rather than
-- a gradient: green while it is fine, amber once a repair is worth planning,
-- red once a piece is about to stop working. A continuous blend between them
-- would be a colour nobody can read a number off.
local function WearTone(fraction)
	if fraction <= 0.2 then
		return C.loss
	end
	if fraction <= 0.5 then
		return C.heading
	end
	return C.tick
end

local function PaintSquare(box)
	local entry = box.entry
	local icon = ns.Worn.Icon(entry.slot)
	box.icon:SetTexture(icon)
	box.icon:SetShown(icon and true or false)

	local empty = (not icon) and ns.Worn.Art(entry) or nil
	box.empty:SetTexture(empty)
	box.empty:SetShown(empty and true or false)

	local link = icon and ns.Worn.Link(entry.slot) or nil
	local quality = link and ns.ItemValue(link) or nil
	ns.Recolor(box.edges, (quality and UI.Quality[quality]) or C.edge)

	local has, of = ns.Worn.Durability(entry.slot)
	if has then
		local fraction = has / of
		box.wear:SetWidth(math.max(UI.Round(box, (SQUARE - INSET * 2) * fraction), 1))
		UI.Tint(box.wear, WearTone(fraction))
		box.wear:Show()
	else
		box.wear:Hide()
	end
end

--------------------------------------------------------------------------
-- The middle
--------------------------------------------------------------------------

-- The four readings, as the one group the shared readout pane draws. It is the
-- same pane the stats, skills and reputation tabs use, handed one group instead
-- of seven, which is what stops this page inventing a fifth way to put a label
-- beside a number.
local function Summary()
	local rows = {}
	local level, empty = ns.Worn.Level()
	local wear, worst, fraction = ns.Worn.Wear()

	rows[#rows + 1] = { label = "level",
		value = ("%d %s"):format(UnitLevel("player") or 0, ns.Class.Label()) }

	if level then
		rows[#rows + 1] = { label = "item level", value = ("%.1f"):format(level) }
	end

	if wear then
		rows[#rows + 1] = {
			label = "durability",
			value = ("%d%%"):format(math.floor(wear * 100 + 0.5)),
			fraction = wear,
			tone = WearTone(wear),
			note = worst and ("Your %s is the worst of it, at %d%%.")
				:format(worst.label, math.floor((fraction or 0) * 100 + 0.5)) or nil,
		}
	end

	rows[#rows + 1] = { label = "empty slots", value = ("%d"):format(empty or 0),
		note = (empty or 0) > 0
			and "Shirt and tabard are not counted, and neither is an off hand your two hander already fills."
			or nil }

	rows[#rows + 1] = { label = "a special, three levels up",
		value = ("%.2f%%"):format(ns.CharStats.MeleeMiss(3)),
		note = "Before any hit off your gear. The stats tab takes that off and says what is left." }

	return { { title = UnitName("player") or "You", rows = rows } }
end

--------------------------------------------------------------------------

function Paperdoll.New(parent)
	local pane = setmetatable({ squares = {} }, Pane)
	pane.frame = CreateFrame("Frame", nil, parent)

	for _, entry in ipairs(ns.Worn.Slots()) do
		pane.squares[#pane.squares + 1] = Square(pane, entry)
	end

	pane.middle = ns.CharReadout.New(pane.frame)
	pane.middle.frame:SetPoint("TOPLEFT", SQUARE + GAP * 2, 0)
	return pane
end

-- Left column down the left, right column down the right, the three weapons in
-- a row along the bottom of the middle. Placed rather than stacked, because
-- this is one arrangement of a fixed number of squares and a layout engine
-- would be a layer between the numbers and the picture.
function Pane:Resize(width, height)
	self.frame:SetSize(width, height)
	local left, right, hands = 0, 0, 0

	for index = 1, #self.squares do
		local box = self.squares[index]
		box:ClearAllPoints()
		if box.entry.side == "left" then
			box:SetPoint("TOPLEFT", 0, -(left * (SQUARE + GAP)))
			left = left + 1
		elseif box.entry.side == "right" then
			box:SetPoint("TOPRIGHT", 0, -(right * (SQUARE + GAP)))
			right = right + 1
		else
			box:SetPoint("BOTTOMLEFT",
				SQUARE + GAP * 2 + hands * (SQUARE + GAP), 0)
			hands = hands + 1
		end
	end

	local column = math.max(left, right) * (SQUARE + GAP) - GAP
	self.middle:Resize(math.max(width - (SQUARE + GAP * 2) * 2, 1),
		math.max(math.min(column, height - SQUARE - GAP), 1))
	return self:Paint()
end

function Pane:Paint()
	for index = 1, #self.squares do
		PaintSquare(self.squares[index])
	end
	return self.middle:Set(Summary())
end

function Pane:Show()
	self.frame:Show()
	return self:Paint()
end

function Pane:Hide()
	self.frame:Hide()
end
