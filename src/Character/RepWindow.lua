local ADDON, ns = ...

local Window = {}
ns.CharRepWindow = Window

local UI = ns.UI
local C, M = UI.Color, UI.Metric

--------------------------------------------------------------------------
-- Where the standings went
--
-- Reputation was a tab on the character sheet, and it was there because the
-- client keeps it on the window this addon takes away rather than because it
-- belongs beside your gear. Nothing on this list moves when you swap a ring.
-- When the sheet folded down to one page the standings could not follow the
-- skills into the stats column, because a faction is not a number about your
-- character, so they got a window instead and `/wk reputation` opens it.
--
-- Character/Reputation.lua did not change. It hands back a title and a list of
-- rows exactly as it did as a tab, this window hosts the same ns.CharReadout
-- pane the tab was, and the page draws the same.
--
-- **Built on the first open**, which is what every window in the addon does
-- except the sheet this one came off. The sheet cannot: its key press runs a
-- snippet, a snippet may only touch a frame it has been handed a reference to,
-- and neither can be made in a fight. Nothing here is secure, nothing here is
-- bound to a key, and a list of factions is not something anybody needs mid
-- pull, so a player who never types the word pays for none of it.
--------------------------------------------------------------------------

-- The width of a column of prose, and it is the one number the old tab kept
-- when the sheet became the screen. A faction with a bar beside it is read at a
-- column's width however much room there is: laid across an ultrawide it is a
-- line your eye loses on the way back. This is the content width of the window
-- the tab was drawn in before any of that changed.
local WIDTH = 836

-- Tall enough for a dozen rows and their headings without scrolling, which is
-- about what a character carries before Outland. Past that the pane's own view
-- scrolls, so this is where the window opens rather than a limit on the list.
local HEIGHT = 520

local window, pane, footer

--------------------------------------------------------------------------

-- The pane takes the whole of the page, inside the padding. There is one thing
-- in this window, so the layout is a subtraction rather than an arrangement.
function Window.Fit()
	if not window then
		return false
	end
	window:Resize(window.width, window.height)
	local width = window.width - M.pad * 2
	local under = window:Body() - M.pad * 2
	pane.frame:SetSize(width, under)
	pane:Resize(width, under)
	return true
end

local function Build()
	if window then
		return window
	end

	window = UI.Window({
		name = "WarriorKitReputation",
		title = "Reputation",
		width = WIDTH,
		height = HEIGHT,
		-- The character sheet's own zoom, and one setting for the two of them is
		-- the honest answer rather than a saving. This is the sheet's reputation
		-- page in a frame of its own: a player who wants their standings larger
		-- wants the page they came off larger too, and a second slider under a
		-- second label would be a second thing to keep in step.
		zoom = function() return ns.Zoom("characterZoom") end,
		-- The window goes back onto the grid and is then laid out again, in that
		-- order, because every number Fit uses is in the window's own units and
		-- those units are what just changed.
		rescale = function(apply)
			apply()
			Window.Fit()
			Window.Refresh()
		end,
	})
	ns.Remember(window)

	pane = ns.CharReadout.New(window.content)
	pane.frame:SetPoint("TOPLEFT", M.pad, -M.pad)

	footer = UI.Label(window.footer, M.small, C.dim, "LEFT", UI.FLAT)
	UI.Wrap(footer, false)
	footer:SetPoint("LEFT")

	-- Painted whenever the window comes up rather than whenever it is built, so
	-- the first open pays for the walk and every later one repays it.
	window.frame:SetScript("OnShow", function()
		Window.Paint()
	end)

	Window.Fit()
	return window
end

-- Every faction the client will list, and the line along the bottom.
--
-- Nothing at all while the window is shut. Reading the list expands the
-- client's own collapsed headers, which is a write to its state, and doing that
-- on a window nobody has open is a cost with no reader.
function Window.Paint()
	if not window or not window:IsShown() then
		return false
	end
	pane:Set(ns.CharRep.Groups())
	footer:SetText(ns.CharRep.Describe() .. ".")
	return true
end

function Window.Built()
	return window ~= nil
end

function Window.Shown()
	return window ~= nil and window:IsShown()
end

function Window.Show()
	Build()
	if not window:IsShown() then
		window:Show()
	else
		Window.Paint()
	end
	return true
end

function Window.Hide()
	if not window then
		return false
	end
	window:Hide()
	return true
end

function Window.Toggle()
	if Window.Shown() then
		return Window.Hide()
	end
	return Window.Show()
end

-- The pane, handed out rather than answered about, for the reason the sheet
-- hands its page over: what is worth checking is how many rows came out and how
-- tall one wrapped to, and neither is a boolean this file could compute without
-- computing it the same way twice.
function Window.Pane()
	return pane
end

-- Repainted only while it is up. UPDATE_FACTION fires on every quest turn-in
-- and every mob in a zone that has a faction, and walking the client's whole
-- list to update a window nobody has open is the waste this addon has a gate
-- for.
function Window.Refresh()
	if Window.Shown() then
		return Window.Paint()
	end
	return false
end

function Window.Describe()
	if not window then
		return "not built yet"
	end
	return Window.Shown() and "open" or "closed"
end

--------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("UPDATE_FACTION")
events:SetScript("OnEvent", function()
	Window.Refresh()
end)
