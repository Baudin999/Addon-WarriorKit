local ADDON, ns = ...

-- Where the addon sits in the client's own menu.
--
-- Everything in here answers one complaint: a slash command is a thing you have
-- to be told about. Escape is a thing everyone already presses. So the addon
-- puts one button in that menu, it says WarriorKit, and it opens the same panel
-- /wk opens. No setting guards it, because a checkbox that hides the way into
-- the settings is a checkbox nobody can find their way back to.
--
-- The button hangs off the bottom of the frame with a margin, and the frame
-- grows by exactly what that costs. That is the whole placement, and it is the
-- second attempt.
--
-- The first one read the menu's anchor chain, worked out which button was at
-- the foot of it, took that button's anchor and re-anchored the foot to ours.
-- It is a nicer picture and it does not survive contact. Blizzard rewrote this
-- frame on the modern clients and the rewrite lays every button out against the
-- frame itself, so there is no chain to read; the walk that coped with that
-- included our own button among the candidates, so once the client relaid its
-- column our button could come back as the foot and be anchored to itself. In
-- game that read as a button you saw on every other press of Escape.
--
-- None of that is worth a nicer picture. The frame's own bottom edge is a thing
-- every version of this menu has, it needs no walk, it cannot come back as our
-- own button, and Blizzard's buttons are never touched at all. Theirs are
-- placed by code we cannot see and re-placed whenever it likes, and a button of
-- ours that moved one of them would be undone on the next show and would take
-- one of Blizzard's with it.
--
-- The one thing still read off the menu is a button to copy a size from, and
-- that is cosmetic: a size we cannot measure leaves the template's own, which
-- is the right size by construction.

local Menu = {}
ns.GameMenu = Menu

local LABEL = "WarriorKit"
local BUTTON = "WarriorKitGameMenuButton"

-- The air under our button, and the same again above it. A number chosen rather
-- than measured, which is the point: the old file measured the gap between two
-- of Blizzard's buttons so ours would sit in their rhythm, and the rhythm is not
-- worth what reading it cost. Ours is the last thing in the menu and it is
-- allowed to look like it.
local MARGIN = 8

-- Above whatever the menu draws inside itself. Ours is a child of the menu and
-- the menu may hold a container with its own level, and a button behind the
-- frame it sits on is a button you cannot click. Ten is past anything one of
-- these frames stacks inside itself.
local LIFT = 10

-- How many regions `/wk menu` lists before it stops. A menu with more than this
-- in it is a menu somebody else has already filled, which is worth knowing and
-- is not worth thirty lines of chat.
local PROBE_LIST = 16

-- The button, and why there is not one. Exactly one of the two is set.
local button, refusal

-- What the menu was tall before we grew it, and what we last set it to. The
-- pair is how re-attaching stays idempotent across a client that recomputes the
-- menu's height on every show and one that does not: if the height still reads
-- back as what we wrote, nothing has recomputed and the base stands.
local base, grown

-- What the last attach found to copy a size from. Carried for `/wk status`,
-- because a button at the template's own size in a menu whose buttons are a
-- different size is a thing you can see and would want explained.
local copied

-- One anchor off a frame the addon does not own.
--
-- ns.Measure is the house call for this and takes no arguments and returns one
-- value, and an anchor is an index in and five values out. Same contract
-- though: a restricted frame raises rather than answering, and the answer to
-- that is nil, not a screenful of errors.
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

-- Any one of the menu's own buttons, for its size and nothing else.
--
-- One level down as well as the menu itself, because a menu that keeps its
-- column in a container of its own is a shape this has already met. One level
-- rather than the whole tree: the whole tree of somebody else's frame is a walk
-- with no bottom to it, and the prize here is a width.
local function Sibling(menu)
	for _, child in ipairs({ menu:GetChildren() }) do
		if child ~= button and ns.Measure(child, "GetObjectType") == "Button"
			and ns.Measure(child, "IsShown") then
			return child
		end
		for _, inner in ipairs({ child:GetChildren() }) do
			if inner ~= button and ns.Measure(inner, "GetObjectType") == "Button"
				and ns.Measure(inner, "IsShown") then
				return inner
			end
		end
	end
	return nil
end

local function Fit(menu)
	local twin = Sibling(menu)
	copied = twin and (ns.Measure(twin, "GetName") or "an unnamed button") or nil
	if not twin then
		return
	end
	local width, height = ns.Measure(twin, "GetWidth"), ns.Measure(twin, "GetHeight")
	if width and height and width > 0 and height > 0 then
		button:SetSize(width, height)
	end
end

-- Taller by one button and the air around it, and no taller on the second call.
local function Grow(menu)
	local height = ns.Measure(menu, "GetHeight")
	local own = ns.Measure(button, "GetHeight")
	if not height or not own or own <= 0 then
		return false
	end
	if not grown or math.abs(height - grown) > 0.01 then
		base = height
	end
	grown = base + own + MARGIN * 2
	menu:SetHeight(grown)
	return true
end

-- Put the button where it belongs, from whatever state the menu is in.
--
-- Run at login and again on every show, because a client that lays its own menu
-- out on show has put its own height back by the time it is next opened.
-- Everything it reads it reads fresh, so a run that changes nothing writes
-- nothing but the height it already had.
function Menu.Attach()
	local menu = _G.GameMenuFrame
	if not button or not menu then
		return false
	end

	Fit(menu)
	if not Grow(menu) then
		refusal = "this client's game menu will not say how tall it is"
		return false
	end

	button:SetFrameLevel((ns.Measure(menu, "GetFrameLevel") or 0) + LIFT)
	button:ClearAllPoints()
	button:SetPoint("BOTTOM", menu, "BOTTOM", 0, MARGIN)
	button:Show()

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
	return ("at the bottom of the game menu, %s"):format(
		copied and ("the size of " .. copied) or "at its template's own size")
end

-- What the client's menu is actually made of.
--
-- This is the only part of the addon whose success depends on the shape of
-- somebody else's frame, and the shape has changed under it once already. So
-- there is a way to look at it that is not reading this file and guessing. Same
-- job `/wk skin probe` does for the aura buttons and for the same reason.
local function Say(region, indent)
	local _, relative = Anchor(region)
	ns.Print(("%s%s %s%s, %s wide, hangs off %s"):format(
		indent,
		tostring(ns.Measure(region, "GetObjectType")):lower(),
		ns.Measure(region, "GetName") or "unnamed",
		ns.Measure(region, "IsShown") and "" or " (hidden)",
		tostring(ns.Measure(region, "GetWidth")),
		relative and (ns.Measure(relative, "GetName") or "an unnamed frame")
			or "nothing"))
end

function Menu.Probe()
	local menu = _G.GameMenuFrame
	if not menu then
		ns.Print("game menu: this client has no GameMenuFrame at all.")
		return
	end

	ns.Print(("game menu: %s tall, %s"):format(
		tostring(ns.Measure(menu, "GetHeight")), Menu.Describe()))
	ns.Print(("  our button %s, AddButton %s, Layout %s, HookScript %s"):format(
		button and "built" or "not built",
		type(menu.AddButton) == "function" and "yes" or "no",
		type(menu.Layout) == "function" and "yes" or "no",
		type(menu.HookScript) == "function" and "yes" or "no"))

	local children, lines = 0, 0
	for _, child in ipairs({ menu:GetChildren() }) do
		children = children + 1
		if lines < PROBE_LIST then
			lines = lines + 1
			Say(child, "  ")
		end
		for _, inner in ipairs({ child:GetChildren() }) do
			if lines < PROBE_LIST then
				lines = lines + 1
				Say(inner, "    ")
			end
		end
	end
	ns.Print(("  %d children of the menu, %d regions listed."):format(children, lines))
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
	order = 22,

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
