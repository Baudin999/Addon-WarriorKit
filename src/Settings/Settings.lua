local ADDON, ns = ...

local Settings = {}
ns.Settings = Settings

local UI = ns.UI

--------------------------------------------------------------------------
-- The settings that belong to no feature
--
-- Two of them: how big the addon's own windows are, and where a hover's box
-- opens. Both are questions about the whole addon rather than about any part
-- of it, which is why neither lives in a feature folder. The first is most of
-- this file and is described below; the second is further down, next to the
-- three calls it needs.
--
-- How big the addon's own windows are
--
-- Every other size in this addon is a count of physical pixels, decided once by
-- whoever drew the thing and true on every monitor. That is the right default
-- and it is the wrong answer for one question, which is how big a window should
-- look to the person reading it. A 544 pixel panel is comfortable on a 1080p
-- monitor at arm's length and postage stamp sized on a 27 inch 4K one, and no
-- measurement the addon can take tells the two apart, because the difference is
-- the distance from the screen to your eyes.
--
-- So this is a preference and not a calculation. UI/Window.lua already picks a
-- whole step off the screen height, which handles the 4K case badly but not
-- wrongly; this multiplies that step by whatever the player dragged the slider
-- to. The two compose: on a screen that has already doubled everything, half
-- size lands back on the design size and every edge is exact again.
--
-- **Quarters, and the grid.** The stops are 0.5 through 3 in quarters, eleven of
-- them. A stop keeps the grid when the size times the screen's own step comes
-- out whole, because one unit is then a whole number of pixels and a hairline is
-- a hairline. On a screen that contributes 1 those are 1x, 2x and 3x; on one
-- that contributes 2 every half step is exact, which is the composition doing
-- what it was meant to. The rest are soft: at 1.25x on a 1080p screen a one
-- pixel edge is asked for at 1.25 pixels and the renderer lays down a blur.
--
-- That is the same cost `bars zoom` refuses to let anyone pay, and the split is
-- deliberate rather than an oversight. A bar over a mob's head is the addon
-- deciding what you see mid-pull. A settings window is you deciding how you want
-- to read it, and a soft hairline on it is a price you are allowed to choose.
-- Settings.Describe is the one sentence that says which stop you are on and what
-- it costs, and Settings.Grid names the stops that stay exact on this screen.
--
-- **What it covers.** The windows this addon draws: the `/wk` panel and the
-- Clutter window. Not the enemy bars, which have their own whole-step zoom
-- under Unit frames, and not the skinned unit frames or the charge button,
-- which are sized in pixels where they sit. Those are things you read in a
-- fight and they are worth keeping exact.
--------------------------------------------------------------------------

Settings.LOW = 0.5
Settings.HIGH = 3
Settings.STEP = 0.25

-- Clamped into range and onto a stop. Everything that can set the size goes
-- through here, so a saved variable edited by hand, a macro and the slider all
-- land on the same set of values.
function Settings.Snap(scale)
	scale = tonumber(scale) or 1
	if scale < Settings.LOW then
		scale = Settings.LOW
	elseif scale > Settings.HIGH then
		scale = Settings.HIGH
	end
	local steps = math.floor((scale - Settings.LOW) / Settings.STEP + 0.5)
	return Settings.LOW + steps * Settings.STEP
end

-- "1x", "1.25x", "2.5x". Two decimal places with the dead zeros taken off,
-- rather than a lookup table of eleven strings that has to be kept in step with
-- three constants.
function Settings.Label(scale)
	local text = ("%.2f"):format(tonumber(scale) or 1)
	text = (text:gsub("0+$", ""))
	text = (text:gsub("%.$", ""))
	return text .. "x"
end

-- Push the saved value into the UI layer, which relays out every open window.
-- Called at ADDON_LOADED so the panel is built at the right size rather than
-- built at the design size and resized a moment later.
function Settings.Apply()
	UI.Tooltip.SetDocked(Settings.Docked())
	return UI.SetSize(Settings.Snap(ns.db.uiSize))
end

function Settings.Set(scale)
	ns.db.uiSize = Settings.Snap(scale)
	Settings.Apply()
	return ns.db.uiSize
end

--------------------------------------------------------------------------
-- Where a hover's box opens
--
-- The other setting that belongs to no feature. Every hover in the addon opens
-- the same box, so where that box goes is one answer for the whole addon and
-- not the loot feed's business or the action bar's.
--
-- Docked is the corner the client keeps its own tooltip in, and it is the
-- default: a box beside the row under the cursor covers the next row, and
-- everything in this addon you can hover sits over the middle of the screen.
-- Beside is the other answer and it is not a fallback. On a very wide monitor
-- the corner is a long way from what you are reading, and a label on the thing
-- itself is worth the cover it costs.
--
-- The value is pushed into UI/Tooltip.lua rather than read out of here, the
-- same way the size is: that layer is not allowed to know the name of a
-- setting.
--------------------------------------------------------------------------

function Settings.Docked()
	return ns.db.tipDock ~= false
end

function Settings.SetDocked(on)
	ns.db.tipDock = on and true or false
	UI.Tooltip.SetDocked(ns.db.tipDock)
	return ns.db.tipDock
end

-- One sentence saying where the next box will open and what that costs, in the
-- terms Settings.Describe uses for the grid: a control that hides its own cost
-- is a control you cannot make a decision with.
function Settings.DescribeDock()
	if Settings.Docked() then
		return "in the bottom right corner, where the client keeps its own,"
			.. " so nothing you hover is covered and nothing is beside it either"
	end
	return "beside whatever you hovered, and on the cursor out in the world,"
		.. " so it is next to the thing it describes and over what is behind it"
end

-- The stops that keep the grid on this screen, as a phrase a note can drop into
-- a sentence. A stop is exact when the screen's own step times the size is
-- whole, so the answer depends on the monitor and cannot be a constant: at
-- screen zoom 1 it is the three whole sizes, at 2 it is every half step.
function Settings.Grid()
	local screen = UI.ScreenZoom()
	local names = {}
	local stop = Settings.LOW
	while stop <= Settings.HIGH + 1e-6 do
		if UI.Exact(screen * stop) then
			names[#names + 1] = Settings.Label(stop)
		end
		stop = stop + Settings.STEP
	end
	if #names == 0 then
		return "no stop on this screen"
	end
	if #names == 1 then
		return names[1]
	end
	return table.concat(names, ", ", 1, #names - 1) .. " and " .. names[#names]
end

-- What a window measures on this screen right now, in physical pixels. The panel
-- is the one worth quoting because it is the one you are looking at while you
-- drag the slider, and it is UI.Windows[1] because Core/Panel.lua builds at
-- PLAYER_LOGIN and everything else in the addon builds its window on first use.
function Settings.Pixels()
	local window = UI.Windows[1]
	if not window then
		return nil
	end
	local zoom = window.zoom or 1
	return window.width * zoom, window.height * zoom
end

-- One sentence saying what the size is doing, and it does not flatter the
-- setting. A stop that costs the grid says so, in the same terms UI.Describe
-- uses for the grid itself, because a control that hides its own cost is a
-- control you cannot make a decision with.
function Settings.Describe()
	local size = Settings.Snap(ns.db.uiSize)
	local zoom = UI.WindowZoom()
	local screen = UI.ScreenZoom()

	local edges
	if not UI.Supported() then
		edges = "this client has no SetIgnoreParentScale, so windows sit on the UI"
			.. " scale and the size is applied to whatever that leaves them at"
	elseif zoom == 1 then
		edges = "one unit is one pixel, so every edge is exact"
	elseif UI.Exact(zoom) then
		edges = ("one unit is a %dx%d block of pixels, so every edge is exact"):format(zoom, zoom)
	else
		edges = ("one unit is %.2f pixels, so a hairline draws soft"):format(zoom)
	end

	local width, height = Settings.Pixels()
	local measured = width and (", panel %d x %d px"):format(width, height) or ""

	if screen == 1 then
		return ("%s%s, %s"):format(Settings.Label(size), measured, edges)
	end
	return ("%s on a %d pixel screen the addon already zooms %dx%s, %s")
		:format(Settings.Label(size), UI.ScreenHeight(), screen, measured, edges)
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, name)
	if name ~= ADDON then
		return
	end
	-- Core's own ADDON_LOADED handler registered first and so ran first, which
	-- is what makes ns.db readable here. Nothing else in the addon depends on
	-- that ordering, so it is stated rather than assumed.
	Settings.Apply()
	self:UnregisterEvent("ADDON_LOADED")
end)
