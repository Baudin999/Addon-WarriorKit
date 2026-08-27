local ADDON, ns = ...

-- Where the addon sits in the client's own menu.
--
-- Everything in here answers one complaint: a slash command is a thing you have
-- to be told about. Escape is a thing everyone already presses. So the addon
-- puts one button in that menu, it says WarriorKit, and it opens the same panel
-- /wk opens. No setting guards it, because a checkbox that hides the way into
-- the settings is a checkbox nobody can find their way back to.
--
-- The awkward part is that the menu belongs to Blizzard and the two clients
-- this addon ships for do not build it the same way. Nothing below names a
-- Blizzard button, reads a localised string or assumes a count. It reads the
-- anchor chain the menu is already laid out with, hangs our button off the end
-- of it and grows the frame by exactly what it added. A client that lays the
-- menu out some other way gets no button and no error, and /wk still works.
--
-- Nothing here draws with the addon's own kit either. A button in Blizzard's
-- menu that does not look like Blizzard's buttons reads as damage, so ours is
-- a GameMenuButtonTemplate and takes its size from the button it displaces.

local Menu = {}
ns.GameMenu = Menu

local LABEL = "WarriorKit"
local BUTTON = "WarriorKitGameMenuButton"

-- The button, and why there is not one. Exactly one of the two is set.
local button, refusal

-- What the menu was tall before we grew it, and what we last set it to. The
-- pair is how re-attaching stays idempotent across a client that recomputes
-- the menu's height on every show and one that does not: if the height still
-- reads back as what we wrote, nothing has recomputed and the base stands.
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

-- The button at the foot of the menu's column, found by reading the chain
-- rather than by naming anything.
--
-- Blizzard hangs each button off the bottom of the one above it, so the foot is
-- the one nothing else hangs off. Two lists rather than one, and the difference
-- between them is the whole of why this works on a menu with a hidden button in
-- it: every button contributes what it hangs off, shown or not, so a hidden
-- button still accounts for the button above it. Only shown ones can be the
-- foot.
--
-- Our own button is walked with the rest. Left out, the button it displaced
-- would look like a second foot the moment we placed it, and the second attach
-- would refuse.
local function Foot(menu)
	local candidates, hangs = {}, {}

	for _, child in ipairs({ menu:GetChildren() }) do
		if ns.Measure(child, "GetObjectType") == "Button" then
			local _, relative = Anchor(child)
			if relative then
				hangs[relative] = true
				if ns.Measure(child, "IsShown") then
					candidates[#candidates + 1] = child
				end
			end
		end
	end

	local foot
	for _, entry in ipairs(candidates) do
		if not hangs[entry] then
			if foot then
				return nil, "this client's game menu is not one column of buttons"
			end
			foot = entry
		end
	end

	if not foot then
		return nil, "this client's game menu has no button to hang ours above"
	end
	return foot
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

	local foot, why = Foot(menu)
	if not foot then
		refusal = why
		return false
	end

	local point, relative, relativePoint, x, y = Anchor(foot)
	if not point then
		refusal = "this client's game menu will not say where its buttons are"
		return false
	end

	-- Our button takes the foot's anchor exactly and the foot takes the same
	-- anchor again off ours, so whatever gap the client leaves between two
	-- buttons is the gap above ours and below it. Nothing here invents a number.
	if relative ~= button then
		local width, height = ns.Measure(foot, "GetWidth"), ns.Measure(foot, "GetHeight")
		if width and height and width > 0 and height > 0 then
			button:SetSize(width, height)
		end
		button:ClearAllPoints()
		button:SetPoint(point, relative, relativePoint, x, y)
		foot:ClearAllPoints()
		foot:SetPoint(point, button, relativePoint, x, y)
	end

	Grow(menu, math.abs(y))
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
		refusal = "this client would not build a game menu button"
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
	if button then
		return "in the game menu, above the last button in it"
	end
	return "not built"
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

-- A part with no settings, no slash word and no page. It registers anyway, for
-- the one line it can put in /wk status: this is the only thing in the addon
-- whose success depends on how somebody else's frame is built, and the way to
-- ask whether it worked has to be something you can type.
ns.Register({
	name = "menu",
	order = 13.5,

	status = function()
		return Menu.Describe()
	end,
})
