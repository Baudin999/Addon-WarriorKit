local ADDON, ns = ...

-- Where the addon sits in the client's own menu.
--
-- Everything in here answers one complaint: a slash command is a thing you have
-- to be told about. Escape is a thing everyone already presses. So the addon
-- puts one button in that menu, it says WarriorKit, and it opens the same panel
-- /wk opens. No setting guards it, because a checkbox that hides the way into
-- the settings is a checkbox nobody can find their way back to.
--
-- The awkward part is that the menu belongs to Blizzard and there is more than
-- one of it. The menu this addon was written against is a column of buttons
-- each hung off the bottom of the one above it. Blizzard has since rewritten
-- that frame on the modern clients, and the rewrite lays every button out
-- against the frame itself, so there is no chain to read. Nothing below names a
-- Blizzard button, reads a localised string or assumes a count, and it handles
-- both shapes:
--
--   a chain      our button takes the last button's anchor and the last button
--                takes the same anchor again off ours, so whatever gap the
--                client leaves between two buttons is the gap around ours
--   a layout     Blizzard's buttons are left exactly where they are and ours
--                hangs under the lowest of them, at the gap that column is
--                already using
--
-- A client that does neither gets no button and no error, and `/wk menu` says
-- what it found. Both cases end the same way: the frame grows by exactly one
-- button and the gap above it.
--
-- Nothing here draws with the addon's own kit. A button in Blizzard's menu that
-- does not look like Blizzard's buttons reads as damage, so ours is a
-- GameMenuButtonTemplate and takes its size from the button it sits under.

local Menu = {}
ns.GameMenu = Menu

local LABEL = "WarriorKit"
local BUTTON = "WarriorKitGameMenuButton"

-- What a column leaves between two buttons when there is only one button in it
-- and nothing to measure. One pixel is what every version of this menu has
-- used, and it is only ever reached on a menu with a single button in it.
local LONE_GAP = 1

-- How many buttons `/wk menu` lists before it stops. A menu with more than this
-- in it is a menu somebody else has already filled, which is worth knowing and
-- is not worth thirty lines of chat.
local PROBE_LIST = 16

-- The button, why there is not one, and which of the two shapes above it found.
local button, refusal, shape

-- What the menu was tall before we grew it, and what we last set it to. The
-- pair is how re-attaching stays idempotent across a client that recomputes the
-- menu's height on every show and one that does not: if the height still reads
-- back as what we wrote, nothing has recomputed and the base stands.
local base, grown

-- One anchor off a frame the addon does not own.
--
-- ns.Measure is the house call for this and takes no arguments and returns one
-- value, and an anchor is an index in and five values out. Same contract
-- though: a restricted frame raises rather than answering, and the answer to
-- that is nil and a refusal, not a screenful of errors.
local function Anchor(frame)
	if not frame or type(frame.GetPoint) ~= "function" then
		return nil
	end
	local ok, point, relative, relativePoint, x, y = pcall(frame.GetPoint, frame, 1)
	if not ok then
		return nil
	end
	return point, relative, relativePoint, x or 0, y or 0
end

-- Every button in the menu, in the three lists the two walks below need.
--
-- `hangs` is fed by every button, shown or hidden, and that is the whole of why
-- the chain walk survives a menu with a hidden button in it: the button below a
-- hidden one still hangs off it, so a walk that only looked at shown buttons
-- would lose track of the button above and find two ends where there is one.
--
-- `all` carries our own button and `others` does not. The chain walk needs ours
-- in, because the button it displaced would look like a second end the moment
-- we placed it. The lowest walk needs ours out, because an unplaced button sits
-- at the origin and a placed one is already the lowest thing there.
local function Survey(menu)
	local all, others, hangs = {}, {}, {}

	for _, child in ipairs({ menu:GetChildren() }) do
		if ns.Measure(child, "GetObjectType") == "Button" then
			local _, relative = Anchor(child)
			if relative then
				hangs[relative] = true
			end
			if ns.Measure(child, "IsShown") then
				if relative then
					all[#all + 1] = child
				end
				if child ~= button then
					others[#others + 1] = child
				end
			end
		end
	end

	return all, others, hangs
end

-- The foot of a chain: the one button nothing else hangs off. Two of them means
-- this is not a chain, which is the answer on a menu laid out against its own
-- frame, and the caller falls through to the walk below.
local function ChainFoot(all, hangs)
	local foot
	for _, entry in ipairs(all) do
		if not hangs[entry] then
			if foot then
				return nil
			end
			foot = entry
		end
	end
	return foot
end

-- The lowest button on the screen, and the gap between it and the one above it.
--
-- Read off the screen rather than off the anchors, because this is the walk for
-- a menu whose anchors say nothing useful about order. Both clients put the
-- origin at a different corner and it does not matter: the foot is the smallest
-- bottom edge either way, because every reading here is a difference between
-- two of them.
local function LowestFoot(others)
	local foot, low, above
	for _, entry in ipairs(others) do
		local bottom = ns.Measure(entry, "GetBottom")
		if bottom and (not low or bottom < low) then
			foot, low = entry, bottom
		end
	end
	if not foot then
		return nil
	end

	for _, entry in ipairs(others) do
		local bottom = ns.Measure(entry, "GetBottom")
		if entry ~= foot and bottom and bottom > low and (not above or bottom < above) then
			above = bottom
		end
	end

	local height = ns.Measure(foot, "GetHeight") or 0
	local gap = above and (above - (low + height)) or LONE_GAP
	if gap < 0 then
		gap = LONE_GAP
	end
	return foot, gap
end

-- Take the foot's size, whatever the shape. A button drawn at a size nobody
-- chose is the one part of this that is visible from across the room.
local function Fit(foot)
	local width, height = ns.Measure(foot, "GetWidth"), ns.Measure(foot, "GetHeight")
	if width and height and width > 0 and height > 0 then
		button:SetSize(width, height)
	end
end

-- The chain: our button takes the foot's anchor exactly and the foot takes the
-- same anchor again off ours, so whatever gap the client leaves between two
-- buttons is the gap above ours and below it. Nothing here invents a number.
local function Insert(foot)
	local point, relative, relativePoint, x, y = Anchor(foot)
	if not point then
		return nil
	end
	if relative ~= button then
		Fit(foot)
		button:ClearAllPoints()
		button:SetPoint(point, relative, relativePoint, x, y)
		foot:ClearAllPoints()
		foot:SetPoint(point, button, relativePoint, x, y)
	end
	return math.abs(y)
end

-- The layout: Blizzard's buttons are not touched at all. Theirs are placed by
-- code we cannot see and re-placed whenever it feels like it, and a button of
-- ours that re-anchored one of them would be undone on the next show and would
-- take one of Blizzard's with it.
local function Append(foot, gap)
	local _, relative = Anchor(button)
	if relative ~= foot then
		Fit(foot)
		button:ClearAllPoints()
		button:SetPoint("TOP", foot, "BOTTOM", 0, -gap)
	end
end

-- Taller by one button and the gap above it, and no taller on the second call.
local function Grow(menu, gap)
	local height = ns.Measure(menu, "GetHeight")
	local own = ns.Measure(button, "GetHeight")
	if not height or not own or own <= 0 then
		return
	end
	if not grown or math.abs(height - grown) > 0.01 then
		base = height
	end
	grown = base + own + gap
	menu:SetHeight(grown)
end

-- Put the button where it belongs, from whatever state the menu is in.
--
-- Run at login and again on every show, because a client that lays its own menu
-- out on show will have dropped us out of the chain by the time it is next
-- opened. Everything it reads it reads fresh, so a run that changes nothing
-- writes nothing.
function Menu.Attach()
	local menu = _G.GameMenuFrame
	if not button or not menu then
		return false
	end

	local all, others, hangs = Survey(menu)
	local gap
	local foot = ChainFoot(all, hangs)

	if foot then
		gap, shape = Insert(foot), "chain"
	else
		local lowest, measured = LowestFoot(others)
		if not lowest then
			refusal = "this client's game menu has no button to sit under"
			return false
		end
		Append(lowest, measured)
		gap, shape = measured, "layout"
	end

	if not gap then
		refusal = "this client's game menu will not say where its buttons are"
		return false
	end

	Grow(menu, gap)
	refusal = nil
	return true
end

local function Build()
	local menu = _G.GameMenuFrame
	if not menu then
		refusal = "this client has no game menu to add to"
		return
	end

	-- pcall, because a template that is not on this client is an error at the
	-- call rather than a nil coming back, and the cost of that error is the rest
	-- of this file not running.
	local ok, made = pcall(CreateFrame, "Button", BUTTON, menu, "GameMenuButtonTemplate")
	if not ok or not made then
		refusal = "this client has no GameMenuButtonTemplate to build a button from"
		return
	end

	button = made
	button:SetText(LABEL)
	button:SetScript("OnClick", function()
		-- Closed the way Escape closes it, so the client takes it off its own
		-- panel stack. Hide alone leaves the stack believing it is still up.
		if type(HideUIPanel) == "function" then
			HideUIPanel(menu)
		else
			menu:Hide()
		end
		ns.Options.Show()
	end)
end

function Menu.Describe()
	if refusal then
		return refusal
	end
	if not button then
		return "not built"
	end
	if shape == "layout" then
		return "in the game menu, under the last button in it"
	end
	if shape == "chain" then
		return "in the game menu, above the last button in it"
	end
	return "built, and not placed yet"
end

-- What the client's menu is actually made of.
--
-- This is the only part of the addon whose success depends on the shape of
-- somebody else's frame, and the shape has changed once already. So there is a
-- way to look at it that is not reading this file and guessing. Same job
-- `/wk skin probe` does for the aura buttons and for the same reason.
function Menu.Probe()
	local menu = _G.GameMenuFrame
	if not menu then
		ns.Print("game menu: this client has no GameMenuFrame at all.")
		return
	end

	ns.Print(("game menu: %s tall, %s"):format(
		tostring(ns.Measure(menu, "GetHeight")), Menu.Describe()))
	ns.Print(("  our button %s, AddButton %s, Layout %s"):format(
		button and "built" or "not built",
		type(menu.AddButton) == "function" and "yes" or "no",
		type(menu.Layout) == "function" and "yes" or "no"))

	local count = 0
	for _, child in ipairs({ menu:GetChildren() }) do
		if ns.Measure(child, "GetObjectType") == "Button" then
			count = count + 1
			if count <= PROBE_LIST then
				local _, relative = Anchor(child)
				ns.Print(("  %s%s, %s wide, hangs off %s"):format(
					ns.Measure(child, "GetName") or "unnamed",
					ns.Measure(child, "IsShown") and "" or " (hidden)",
					tostring(ns.Measure(child, "GetWidth")),
					relative and (ns.Measure(relative, "GetName") or "an unnamed frame")
						or "nothing"))
			end
		end
	end
	ns.Print(("  %d buttons, %d listed."):format(count, math.min(count, PROBE_LIST)))
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
	Build()
	if not button then
		return
	end
	Menu.Attach()
	local menu = _G.GameMenuFrame
	if type(menu.HookScript) == "function" then
		menu:HookScript("OnShow", Menu.Attach)
	end
end)

-- A part with no settings and no page, and one word. It registers for the line
-- it puts in /wk status and for the probe above: this is the only thing in the
-- addon whose success depends on how somebody else's frame is built, and the
-- way to ask what happened has to be something you can type.
ns.Register({
	name = "menu",
	order = 13.5,

	words = {
		menu = function()
			Menu.Probe()
		end,
	},

	help = {
		"menu, what the client's own menu is made of and where our button went",
	},

	status = function()
		return Menu.Describe()
	end,
})
