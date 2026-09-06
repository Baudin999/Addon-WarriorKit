local ADDON, ns = ...

local UI = ns.UI
local C, M = UI.Color, UI.Metric

--------------------------------------------------------------------------
-- Windows, rails and tab strips
--
-- The chrome, and the two pieces of navigation that go in it. A window is a
-- titled, draggable, escape-closing rectangle with a content area and a footer.
-- A rail is a column of choices down the left. A tab strip is a row of choices
-- across the top of whatever the rail chose.
--
-- All three are here rather than in the options panel because none of them
-- knows what a setting is, and the next window this addon grows, an aura list,
-- a loot log, a profile browser, wants the same three and should not be
-- copying them out of a file called Panel.lua.
--
-- **A window is adopted onto the pixel grid.** It is a frame the addon owns
-- outright, anchored to UIParent, so unlike a nameplate it can be exact in both
-- size and position, and every number in UI.Metric is then a count of physical
-- pixels. The cost is the cost the enemy bars already pay: a window 540 pixels
-- wide is 540 pixels on a laptop and 540 on a 4K panel, which on the 4K panel
-- is small. Zoom is the answer there, and it comes from two places that
-- multiply: UI.ScreenZoom, a whole step the screen height picks on its own, and
-- UI.Size, the slider the player drags in the settings panel. A screen that
-- doubles everything and a player who halves it land back on the design size,
-- which is the arithmetic you want and the reason they are one number by the
-- time a window sees them.
--
-- **The size is deliberate and the window does not resize.** The old panel grew
-- to whatever its tallest page needed, which on this screen was 773 physical
-- pixels of a 1440 pixel monitor for a settings window, and then scaled itself
-- down when that overflowed, which shrank the text to buy room for settings
-- nobody was reading. This one is a fixed rectangle: a section that does not fit
-- scrolls. A drag handle to resize it would mean a saved size, a minimum, a
-- maximum, and a reflow of every section on every mouse move, to buy what the
-- scrollbar already gives.
--------------------------------------------------------------------------

-- Every window the library has made, in creation order. Nothing in the addon
-- reads it yet. It exists because a UI layer that means to own the screen has
-- to be able to answer "what is open", and because the harness drives the
-- options panel through it rather than through a hook cut into the panel for
-- the harness's benefit.
UI.Windows = {}

-- What the screen asks for, before the player has said anything. Whole steps
-- only: below a 1600 pixel tall screen the pixel metrics are already
-- comfortable, above 2000 they are half the size they should be, and a
-- fractional step chosen on the player's behalf would put every edge in the
-- window onto a half pixel to buy a size nobody asked for.
function UI.ScreenZoom()
	local height = UI.ScreenHeight()
	if height >= 2000 then
		return 2
	end
	return 1
end

-- What the boxes this layer draws itself are sized at.
--
-- There was one of these for the whole addon, called UI size, and every window
-- took it. Each screen carries its own number now and asks for it with a
-- getter, so what is left here is the two things the UI layer draws that belong
-- to no feature and so have nobody to ask: the confirm box in UI/Ask.lua and,
-- through its own setter, the hover box.
--
-- The number is held here rather than read out of ns.db, because this layer is
-- not allowed to know the name of a setting. Settings/Settings.lua reads the
-- saved value and pushes it in, the same way a widget takes a getter rather than a key.
--
-- The screen's step and the player's multiply. On a 4K panel the screen has
-- already doubled everything, so half size lands back on the design size and is
-- exact; on a 1080p panel the screen contributes 1 and half size is genuinely
-- half.
local chosen = 1

function UI.Size()
	return chosen
end

-- Every frame on the grid is re-zoomed by its own rescale listener, which is
-- the same path a monitor swap takes, so this only has to say that the ground
-- moved. Returns whether it did: an unchanged size relays out nothing.
function UI.SetSize(scale)
	scale = tonumber(scale) or 1
	if scale == chosen then
		return false
	end
	chosen = scale
	UI.Notify()
	return true
end

function UI.DialogZoom()
	return UI.ScreenZoom() * chosen
end

-- Whether one unit is a whole number of physical pixels at the zoom in force.
-- The window is exact only when the product is, which is why the screen's own
-- step is whole and why the panel says out loud which stops of the slider are
-- and which are not.
function UI.Exact(zoom)
	zoom = zoom or UI.DialogZoom()
	return math.abs(zoom - math.floor(zoom + 0.5)) < 1e-6
end

local Window = {}
Window.__index = Window

--------------------------------------------------------------------------
-- The dark behind a screen window
--
-- A screen window has no ground, so what it is written on is the game. Narcissus
-- dims the screen either side of its figure and it is the whole reason that page
-- reads as one thing rather than as text scattered over scenery. This is that,
-- for the half of the monitor a screen window takes: one wash, solid at the
-- outer edge and gone by the middle where the player's character is standing.
--
-- It stops at the window's own edge, which is what the two anchors below are
-- for. Half the monitor is the half the sheet was cut down to so the player
-- keeps the other half to fight in, and a shadow that crept past the frame
-- would be taking back the thing that cut was made to give.
--
-- **It never answers the pointer.** This is the one piece of chrome in the
-- addon that could cost the player the world behind it and do it silently. A
-- screen window turns the mouse off on its own frame precisely so a click on
-- the sheet reaches the mob behind it, and a wash laid over half the monitor on
-- a frame that took the mouse would be half a monitor you can no longer target,
-- loot or turn the camera in. It draws the same either way and hovers the same
-- either way, so nothing about looking at it says which one shipped. So it is a
-- texture on the window's own frame rather than a frame of its own: there is no
-- new surface for anyone to switch the mouse on later, and the pointer harness
-- presses a point on the sheet's half and reads back nothing.
--
-- **Faded rather than shown.** A rectangle of shadow over half the screen that
-- appears between one frame and the next on a key press is the one thing on
-- this page that reads as a bug rather than as an interface.
--------------------------------------------------------------------------

-- How long the world takes to go dark. Long enough to be a fade and short
-- enough that the sheet is readable by the time the eye has got to it.
local DARK_SECONDS = 0.2

-- The wash, and the one script that catches every way a screen window comes up.
--
-- OnShow rather than Window:Show, and that is the whole reason this is a script
-- at all. The character sheet is opened in a fight by a secure snippet, which
-- runs none of this file's Lua, so a fade hung off the method would be a fade
-- that never happened on the key most people open the sheet with.
--
-- Set rather than hooked, because a window is this library's frame and the
-- caller is the one chaining onto it. Character/Window.lua hooks its own paint
-- under this, the way Mail/Window.lua already hooks OnHide.
local function Darkness(window, frame, opts)
	window.darkOf = opts.dark or function() return false end
	window.dark = UI.Wash(frame, C.shadow, "RIGHT", "BACKGROUND")
	window.dark:SetAllPoints()
	window.dark:SetAlpha(0)
	window.dark:Hide()
	-- A tween on a texture rather than on a frame. The alpha channel is the only
	-- one armed and SetAlpha is the only call it makes, so what it drives has to
	-- answer that and nothing else.
	window.darkening = ns.Ck.Animations.New(window.dark)
	frame:SetScript("OnShow", function()
		window:Darken()
	end)
end

-- The bar across the top: the strip, the name on it and the close box. Its own
-- function because it is the whole of what a window that is not bare has and
-- none of what a bare one does, so the alternative is fifteen lines of one
-- window's chrome sitting inside the constructor both kinds run through.
-- The ground a window is drawn on, and the hairline round it. Beside TitleBar
-- for the reason TitleBar is beside the constructor: it is a piece of chrome
-- whose colour the caller decides, and the argument for the line is a paragraph
-- nobody reading how a window is assembled has to step through.
--
-- Returns the frame's pixel, which the title bar is placed in and which cannot
-- be asked for before the frame is on the grid.
local function Surface(window, frame, opts)
	-- Kept on the window rather than left local, because how opaque a window is
	-- is a property of that window. The panel wants to be read and takes the
	-- palette's own alpha; a chat window sits over the world all night and the
	-- player decides how much of the world comes through it.
	--
	-- A screen window has none. It is the size of the screen, so a ground on it
	-- is the game painted out, and what it draws is meant to be read against the
	-- world rather than against a panel.
	if not opts.screen then
		window.bg = ns.Fill(frame, "BACKGROUND", C.window[1], C.window[2], C.window[3], C.window[4])
		window.bg:SetAllPoints()
	else
		Darkness(window, frame, opts)
	end

	local px = ns.Pixel(frame)
	-- A hairline round the outside, unless the caller says no.
	--
	-- The line is there to say where a window ends, and that is worth having on
	-- a settings window: it is opaque, it lands over the game for a minute and
	-- the edge is what tells the panel from the world behind it. The chat window
	-- is the opposite case. It is eighty percent transparent and up all evening,
	-- so the line is not marking a boundary you needed marking, it is a bright
	-- rectangle drawn round the trees. Take it off and the window is what is
	-- written in it, which is what a chat window should be.
	if opts.edge ~= false and not opts.screen then
		window.edges = ns.Outline(frame, C.edge[1], C.edge[2], C.edge[3], 1)
		ns.EdgeSize(window.edges, px)
	end
	return px
end

local function TitleBar(window, px, title)
	local frame = window.frame
	local bar = ns.Fill(frame, "ARTWORK", C.chrome[1], C.chrome[2], C.chrome[3], 1)
	bar:SetPoint("TOPLEFT", px, -px)
	bar:SetPoint("TOPRIGHT", -px, -px)
	bar:SetHeight(M.title)

	window.title = UI.Label(frame, M.heading, C.heading, "LEFT", UI.FLAT)
	window.title:SetPoint("TOPLEFT", M.pad, -math.floor((M.title - M.heading) / 2) - px)
	window.title:SetText(title or "")

	-- The close box, and on a secure window it is a secure button.
	--
	-- A window with a protected frame inside it cannot be hidden by an addon in
	-- combat, and a cross that does nothing in a fight is worse than no cross.
	-- A snippet is allowed to do it, so the cross runs one: the frame reference
	-- is what the snippet is given, because a snippet may only touch what it has
	-- been handed. Nothing else on the window changes, and every other window in
	-- the addon takes the ordinary branch.
	if window.secure then
		window.close = UI.Button(frame, { label = "x", glyph = true,
			width = M.title - 8, height = M.title - 8,
			template = "SecureHandlerClickTemplate" })
		window.close:SetFrameRef("window", frame)
		window.close:SetAttribute("_onclick", [[
			self:GetFrameRef("window"):Hide()
		]])
	else
		window.close = UI.Button(frame, { label = "x", glyph = true,
			width = M.title - 8, height = M.title - 8,
			onClick = function() window:Hide() end })
	end
	window.close:SetPoint("TOPRIGHT", -4, -4)
end

-- The strip along the bottom and the hairline above it. Beside TitleBar for the
-- same reason TitleBar is its own function: it is a piece of chrome whose size
-- the caller decides, and eight lines of it inside the constructor is eight
-- lines nobody reading how a window is assembled needs to step through. Every
-- window has one, bare or not, because the chat window's way out lives in it.
local function Footer(window, frame, opts)
	window.footer = CreateFrame("Frame", nil, frame)
	window.footer:SetPoint("BOTTOMLEFT", M.pad, 0)
	window.footer:SetPoint("BOTTOMRIGHT", -M.pad, 0)
	window.footer:SetHeight(window.foot)
	-- The line over it is there to part the footer from the page above it, and
	-- a screen window has no page: it is a line the width of the monitor drawn
	-- across the world, which is the loudest piece of chrome it could carry.
	if opts.screen then
		return
	end
	window.footerRule = UI.Rule(frame, C.hairline)
	window.footerRule:SetPoint("BOTTOMLEFT", M.pad, window.foot)
	window.footerRule:SetPoint("BOTTOMRIGHT", -M.pad, window.foot)
end

-- The two ways out of a dropdown that is open over this window and a key field
-- that has the keyboard. Its own function beside TitleBar and Footer, because
-- both scripts are the same two calls for two different reasons and neither
-- reason is about how a window is assembled.
--
-- A listening key field has the keyboard and an open dropdown covers whatever is
-- under it, so a click anywhere else in the window has to be a way out of both.
-- Each of them eats its own click, so this never cancels the click that opened
-- it.
--
-- Escape closes the window through UISpecialFrames, which calls Hide on the
-- frame and knows nothing about either. So the cleanup hangs off the frame
-- rather than off the Hide method, and every route out goes through it.
local function Dismissals(frame)
	local function Clear()
		UI.StopCapture()
		UI.CloseDropdown()
	end
	frame:SetScript("OnMouseDown", Clear)
	frame:SetScript("OnHide", Clear)
end

-- Where the window sits among everything else on screen.
--
-- DIALOG unless the caller says otherwise. A settings window is something you
-- open over the game and close again, and DIALOG is where that belongs. A
-- window that is up while you play, which is what the chat window is, has to
-- sit under the tooltip and under anything the client puts over the world, so
-- it asks for a lower one.
--
-- One strata is one pile. Every window in the addon is in the same one, and
-- two frames at the same level in the same pile are sorted by their children:
-- the second window's title bar draws over the first window's body and under
-- the first window's buttons. Toplevel is the client's answer. A toplevel
-- frame is lifted above every sibling in its strata when it is clicked,
-- children and all, so a window is over or under another window entirely and
-- never threaded through it. Window:Show does the same lift, because the
-- window you just opened is the one you want on top and a click is not what
-- opened it.
--
-- A screen window is the floor of the pile and stays there. It is a backdrop
-- laid over half the monitor, so every window the player opens has to flow over
-- the top of it, and a toplevel frame lifted on a click would put the backdrop
-- over the bags the moment you clicked a gear square.
local function Pile(frame, opts)
	if opts.screen then
		frame:SetFrameStrata(opts.strata or "BACKGROUND")
		frame:SetToplevel(false)
		return
	end
	frame:SetFrameStrata(opts.strata or "DIALOG")
	frame:SetToplevel(true)
end

-- Where a window can be dragged to, and whether it can be dragged at all.
--
-- Dragged through UI/Placeable.lua, which owns placing for every frame in the
-- addon that can be moved, windows included. Its header says why that is one
-- file and not two. No name, because a window has a bar across its top to grab
-- it by and answers the mouse whether or not you are placing it. /wk lock does
-- not reach a window unless the window asks it to, which the chat window is the
-- only one to do. Locking a quest log would be locking a window rather than
-- placing the HUD.
--
-- A screen window is dragged by a strip along its top and by nothing else.
--
-- It had no drag at all while it was the whole monitor, which was right then: a
-- frame the size of the screen is already where it goes. It is half the screen
-- now, and half a screen is a thing a player has an opinion about, so the drag
-- is back. What it must not be is the frame: a placeable with no chrome covering
-- half the game is an invisible drag target the size of a wall, with the left
-- button and the camera's right drag gone out of all of it.
--
-- So the grip is the row across the top of the window, which is a title bar in
-- everything but the paint. It sits over the page rather than under it, and it
-- is the whole of that edge: the sheet used to draw its tabs in the strip and
-- lift them one level over it, so only the ends either side of the words were a
-- grab. There is one page now and nothing is drawn up there, so every pixel of
-- the top edge takes the drag.
--
-- It says so under the cursor rather than all the time. A panel with nothing
-- drawn on it cannot carry a permanent bar without becoming the dialog this
-- sheet stopped being, so the strip lights while you are on it and is not there
-- otherwise, which is the trade the gear rows already make with their rings.
--
-- Beside TitleBar and Footer for the reason both of those are: it is one piece
-- of what a window is, and the argument for the shape it has is a paragraph
-- nobody reading how a window is assembled has to step through.
local function Grip(window, frame)
	local grip = CreateFrame("Frame", nil, frame)
	grip:SetPoint("TOPLEFT")
	grip:SetPoint("TOPRIGHT")
	grip:SetHeight(M.title)
	grip:EnableMouse(true)

	local lit = ns.Fill(grip, "BACKGROUND",
		C.chrome[1], C.chrome[2], C.chrome[3], 0.7)
	lit:SetAllPoints()
	lit:Hide()
	grip:SetScript("OnEnter", function() lit:Show() end)
	grip:SetScript("OnLeave", function() lit:Hide() end)

	-- The one part of a screen window that answers the mouse at all, so it is
	-- also the only place a click can be the way out of an open dropdown. Every
	-- other window gets this on the frame, which a screen window's is not
	-- listening for.
	Dismissals(grip)

	window.grip = grip
	return grip
end

-- How much of the window is chrome, what draws it, and the page under it.
--
-- Beside Surface, TitleBar and Footer, and it calls the last two, because the
-- three numbers and the three frames are one decision: a window with no title
-- bar has no twenty four pixels of chrome and its page starts at the top edge,
-- and splitting that across the constructor made the reader hold the chrome
-- height in their head from where it is worked out to where it is used.
--
-- Both numbers rather than the two constants they used to be, because the chat
-- window wants neither of the defaults: no title bar at all, and a footer sized
-- for one line of text instead of for a row of buttons.
--
-- **A bare window has no title bar and no close box.** A title bar says which
-- window this is, which is worth twenty four pixels in a settings window you
-- opened on purpose and worth nothing in a window that is up all evening
-- drawing the thing it is named after. A window that asks for bare owes its
-- player some other way out, and the chat window's is a cross at the foot of
-- its own rail.
local function Chrome(window, frame, px, opts)
	window.chrome = (opts.bare or window.screen) and 0 or M.title
	window.foot = opts.footer or M.footer

	if not opts.bare and not window.screen then
		TitleBar(window, px, opts.title)
	end

	-- Everything between the title bar and the footer. Content parents to this,
	-- so nothing below has to know how tall the chrome is.
	window.content = CreateFrame("Frame", nil, frame)
	window.content:SetPoint("TOPLEFT", 0, -window.chrome)

	-- The grip over the page, said here rather than where the grip is made,
	-- because the content frame it is placed against does not exist yet at that
	-- point and the strata the window is filed in is set between the two.
	--
	-- Over, not under. Under was the first answer and it does not work: the
	-- bottom of a window's stack is under the page, under anything the page
	-- lifts above itself, and under every button on it, so a strip down there is
	-- a strip nothing ever reaches.
	--
	-- So the strip is above all of it, and nothing has to beat it. The character
	-- sheet used to draw a tab row in the strip and lift it one level over the
	-- grip, because a tab you cannot press is worse than a sheet you cannot drag.
	-- That sheet is one page now and the top edge is a handle end to end.
	if window.grip then
		window.grip:SetFrameLevel(window.content:GetFrameLevel() + 20)
	end

	Footer(window, frame, opts)
end

local function Drag(window, frame, opts)
	window.place = UI.Placeable(frame, {
		moved = opts.moved,
		lockable = opts.lockable == true,
		-- Which of the two drags this window gets. A secure one is dragged from
		-- a snippet, because moving a window that holds a protected frame is
		-- refused in combat the same way showing it is.
		secure = window.secure,
		-- A window with chrome is grabbed by its own chrome, so the frame is the
		-- grip. A screen window has none, and names the strip above instead.
		grip = window.screen and Grip(window, frame) or nil,
	})
end

-- opts.zoom is a number or a getter returning one, and a getter is what every
-- window in the addon passes. This layer is still not allowed to know the name
-- of a setting, so the window is handed a way to ask rather than a key to read,
-- the same way every widget in the kit is. A getter is also what lets the
-- window keep itself on the grid, which is KeepOnGrid below.
local function ZoomOf(opts)
	if type(opts.zoom) == "function" then
		return opts.zoom
	end
	return function()
		return tonumber(opts.zoom) or UI.DialogZoom()
	end
end

-- The grid moved: a monitor swap, combat letting go of a frame, or this
-- window's own zoom being dragged. Its own function for the reason TitleBar and
-- Footer are: it is one piece of what a window is, and the argument for the
-- shape it has is a paragraph nobody reading how a window is assembled has to
-- step through.
--
-- Ten windows carried these two lines in a listener of their own, which is
-- todo.md item 19 and was six windows worse than the item said. The library made
-- the frame; keeping it at the size it is meant to be drawn at is the library's
-- job and not something each caller re-derives.
--
-- What the caller gets is the rezoom as a function rather than a callback after
-- it, because two of the twelve do not want it run where it would fall by
-- default. The character sheet defers the whole thing in combat, since scaling
-- the frame its secure gear squares hang off is refused. Every window that lays
-- itself out in its own units has to do that after the units change and not
-- before, which is the same ordering by a different route. Left out, the rezoom
-- simply happens, which is the whole of what eight of the twelve wanted.
local function KeepOnGrid(window, opts)
	local function Apply()
		local want = window.zoomOf()
		window.zoom = want
		return UI.Rezoom(window.frame, want)
	end
	window.Rezoom = Apply
	UI.OnRescale(function()
		if opts.rescale then
			return opts.rescale(Apply)
		end
		return Apply()
	end)
end

function UI.Window(opts)
	local window = setmetatable({}, Window)

	window.zoomOf = ZoomOf(opts)
	local zoom = window.zoomOf()

	-- Whether this window has a protected frame somewhere inside it. One does:
	-- the character sheet, whose gear squares are secure buttons because using
	-- what is in a slot is protected. Everything an addon does to such a window
	-- in combat is refused by the client, so a secure window is shown, hidden
	-- and dragged from snippets instead: the key that opens it is bound to a
	-- secure button, the close cross is one, and the drag is a point handed to a
	-- snippet through the attribute template the frame is built with here.
	window.secure = opts.secure == true

	-- Whether this is a window on the screen or the screen itself.
	--
	-- One asks and one ever will: the character sheet. It is a page drawn on the
	-- world with the game still showing through it, so it has none of what makes
	-- a window a window. No ground, because a ground under half the monitor is
	-- that half of the game painted out. No line round the outside, because it is
	-- read as part of the scene rather than as a panel over it. No title bar,
	-- because there is nothing to name. And the floor of the pile, so everything
	-- the player opens over it flows over the top.
	--
	-- It is still dragged and it still remembers where you put it. Both came back
	-- when it stopped being the whole monitor and became half of one: a frame the
	-- size of the screen is already where it goes, half a screen is a corner the
	-- player has an opinion about. With no title bar to grab, Grip below hands it
	-- a strip along its top instead.
	--
	-- It does not eat the mouse either. Every other window in the addon does,
	-- because a click that lands on a panel should stop there; this one has no
	-- panel, so a click it swallowed would be a mob you could not target through
	-- a page you can see straight through. What is on it answers for itself: the
	-- gear squares take their own clicks and everything else on the page takes
	-- the hover and hands the buttons back to the world.
	window.screen = opts.screen == true

	-- The attribute template rather than the drag one, because the drag a secure
	-- window gets is not a drag the client runs: the restricted environment has
	-- no StartMoving in it, so UI/Placeable.lua writes the point it wants into an
	-- attribute and the snippet on this template is what places the frame.
	local frame = CreateFrame("Frame", opts.name, UIParent,
		window.secure and "SecureHandlerAttributeTemplate" or nil)
	window.frame = frame
	window.zoom = zoom
	UI.Adopt(frame, zoom)

	frame:SetPoint("CENTER")
	frame:EnableMouse(not window.screen)
	Drag(window, frame, opts)
	Pile(frame, opts)
	Dismissals(frame)
	frame:Hide()

	local px = Surface(window, frame, opts)

	Chrome(window, frame, px, opts)

	window:Resize(opts.width or 540, opts.height or 450)

	-- Escape closes it, the same as any Blizzard window. The name is what
	-- UISpecialFrames holds, so a window that wants the behaviour has to have one.
	--
	-- opts.escape = false opts out, and the chat window is why. Escape is the
	-- key that clears a targeting cursor and steps out of a text field, and a
	-- window you have up all evening must not be what it closes instead.
	if opts.name and opts.escape ~= false then
		tinsert(UISpecialFrames, opts.name)
	end

	KeepOnGrid(window, opts)

	UI.Windows[#UI.Windows + 1] = window
	return window
end

-- The margin a screen window keeps off the edge of the monitor.
--
-- Edge to edge is the wrong number twice. A line printed against the last pixel
-- of the panel is a line you read the top half of, and the game's own window is
-- not always the size of the monitor: a client running windowed under a
-- compositor can hang forty pixels off the bottom, and everything the addon
-- draws down there goes with it. Six percent is the same margin a photograph
-- gets and it is enough for both.
local SCREEN_MARGIN = 0.94

-- The most of the monitor a screen window may take.
--
-- It took all of it, and all of it was too much. A sheet the size of the screen
-- puts the name of your helmet a third of a monitor from the helmet, puts the
-- stats column against the last pixel of the panel where a windowed client can
-- carry it off the edge entirely, and leaves the player with no part of the
-- game left to click on. The page was right and the canvas was wrong.
--
-- Then it was half the monitor across at four by three, and that was the same
-- mistake with a smaller number. A share of the monitor is a size chosen by the
-- player's hardware, and the page's contents do not know what hardware they are
-- on: ten rows of gear are 396 pixels tall on every screen ever made, so half of
-- a 3440 wide panel at four by three gave that page 1290 pixels of height and
-- nine hundred of them stayed empty all evening.
--
-- So this is a ceiling now rather than a size. A screen window asks Resize for
-- the size its own contents want and gets that, or gets this if that would not
-- fit: half the monitor across, never taller than the monitor less its margin.
-- Half is still the most a panel can take and still leave a screen to play on,
-- and it now binds on the small screens it was written for instead of on all of
-- them.
local SCREEN_SHARE = 0.5

-- The whole monitor in this window's own units, which after adoption are
-- physical pixels over the zoom. Off the grid, on a client with no
-- SetIgnoreParentScale, the window is in UIParent's units and UIParent is what
-- to ask, which is the same fork Resize takes below and for the same reason.
function Window:Screen()
	local across, down
	if UI.Supported() then
		across, down = UI.ScreenWidth() / self.zoom, UI.ScreenHeight() / self.zoom
	else
		across, down = UIParent:GetWidth() or 0, UIParent:GetHeight() or 0
	end
	return math.floor(across), math.floor(down)
end

-- The largest box a screen window is allowed to be: half the monitor's width,
-- and the monitor's height less its margin. The two are independent now, which
-- they could not be while this was a shape as well as a size.
function Window:Panel()
	local across, down = self:Screen()
	return math.max(math.floor(across * SCREEN_SHARE), 1),
		math.max(math.floor(down * SCREEN_MARGIN), 1)
end

-- Where it sits, which is against the right hand edge with the same margin off
-- it. Its own function because it is re-run out of every resize: the offset is
-- in the window's units, so it is a different number after a zoom.
--
-- The right rather than the middle. The middle is where the player's character
-- is standing, and a sheet with a picture of that character laid over the
-- character is the one place on the screen it must not be.
local function Anchor(window)
	local across = window:Screen()
	window.frame:ClearAllPoints()
	window.frame:SetPoint("RIGHT", UIParent, "RIGHT",
		-math.floor(across * (1 - SCREEN_MARGIN) / 2), 0)
end

-- The requested size, clamped to what the screen can hold. Both numbers are in
-- the window's own units, which after adoption are physical pixels divided by
-- the zoom, so the screen has to be converted into them before they can be
-- compared.
function Window:Resize(width, height)
	-- A screen window is asked how big it wants to be and then told what it may
	-- have. Both numbers are in the window's own units, which are physical pixels
	-- over the zoom, so the zoom still decides how much of the monitor a page of a
	-- given size covers: turn it up and the sheet asks for the same number of
	-- units and each one is worth more pixels, which is larger type on a larger
	-- panel rather than more room for rows nobody added.
	--
	-- Every route into a resize goes through here, so this is also what keeps the
	-- panel in the right corner at the right size after a monitor swap or a drag
	-- of the zoom slider: the caller re-runs its own layout and asks again, and
	-- the point is re-set below off the same numbers.
	if self.screen then
		local most, tallest = self:Panel()
		width = math.min(width or most, most)
		height = math.min(height or tallest, tallest)
		-- Where it ships, and only until the player has said otherwise. This runs
		-- out of every resize, which is where a monitor swap and a drag of the
		-- zoom slider both land, so without the question a sheet would walk back
		-- to the right hand edge every time either of them moved.
		if not (self.place and self.place:Placed()) then
			Anchor(self)
		end
	else
		-- On the grid the window's units are pixels over the zoom, so the screen has
		-- to be converted into them. Off it, on a client with no
		-- SetIgnoreParentScale, the window is in UIParent's units and UIParent is
		-- what to ask. Getting this the wrong way round on the second client puts a
		-- window taller than the screen on it and nothing here would say so.
		local room = UI.Supported() and (UI.ScreenHeight() / self.zoom) or UIParent:GetHeight()
		local budget = math.floor((room or UI.ScreenHeight()) * 0.86)
		if height > budget then
			height = budget
		end
	end

	self.width, self.height = width, height
	self.frame:SetSize(width, height)
	self.content:SetSize(width, self:Body(height))
	return width, height
end

-- How tall the content area is in a window of this height: everything the
-- chrome does not take. Public because a caller that lays out inside the
-- content has to be able to ask, and because the two numbers it subtracts are
-- per window now rather than two constants anybody could read off the theme.
function Window:Body(height)
	return (height or self.height or 0) - self.chrome - self.foot
end

-- A search field in the title bar.
--
-- Chrome rather than a widget, because it belongs to the window and not to any
-- page in it: what it searches is everything the window holds, and a control
-- that lives on one page cannot say anything about the other forty four.
--
-- opts.onType is called on every keystroke with the whole field. Filtering as
-- you type rather than on enter, because a settings window is something you
-- rummage in: you type two letters, see whether it is there, and type two more.
--
-- It takes the keyboard when you click it and gives it back on escape, and
-- never at any other time. It used to be focused the moment the window opened,
-- on the argument that a field you have to click first is a field you forget is
-- there, and that argument cost more than it was worth: an edit box with the
-- keyboard takes every press before anything else on the page sees it, so the
-- first thing anybody did after opening the window was type into a search box
-- they had not asked for. Binding a key was the worst of it. The key you
-- pressed went into the search field and the capture read nothing.
function Window:Search(opts)
	local width = opts.width or 150
	local height = M.title - 8

	local box = UI.Box(self.frame, C.sunken, C.edge)
	box:SetSize(width, height)
	box:SetPoint("TOPRIGHT", self.close, "TOPLEFT", -M.rowGap, 0)

	local ghost = UI.Label(box, M.small, C.quiet, "LEFT", UI.FLAT)
	ghost:SetPoint("LEFT", 4, 0)
	ghost:SetText(opts.placeholder or "search")

	local edit = CreateFrame("EditBox", nil, box)
	edit:SetPoint("TOPLEFT", 4, 0)
	edit:SetPoint("BOTTOMRIGHT", -4, 0)
	edit:SetFontObject(UI.Font(M.small, UI.FLAT))
	edit:SetTextColor(C.text[1], C.text[2], C.text[3])
	edit:SetAutoFocus(false)
	edit:SetMaxLetters(40)

	edit:SetScript("OnTextChanged", function(field)
		ghost:SetShown(field:GetText() == "")
		opts.onType(field:GetText())
	end)
	-- Escape empties the field and gives the keyboard up in one press, so the
	-- page comes back and the window is listening again. The window still takes
	-- two presses to leave, because this one is spent on the search and the next
	-- reaches the window itself, which is what the two-stage version was for.
	edit:SetScript("OnEscapePressed", function(field)
		field:SetText("")
		UI.StopTyping()
		field:ClearFocus()
	end)
	edit:SetScript("OnEnterPressed", function(field)
		if opts.onEnter then
			opts.onEnter(field:GetText())
		end
	end)
	edit:SetScript("OnEditFocusGained", function(field)
		UI.CloseDropdown()
		UI.StopCapture()
		UI.Typing(field)
		UI.Tint(box.bg, C.selected)
	end)
	edit:SetScript("OnEditFocusLost", function()
		UI.StopTyping()
		UI.Tint(box.bg, C.sunken)
	end)

	-- The whole rectangle answers the click, not only the letters inside it.
	-- Four pixels of padding either side is four pixels of a field that looks
	-- like it should take the cursor and does not, and this is now the only way
	-- in.
	box:EnableMouse(true)
	box:SetScript("OnMouseDown", function()
		edit:SetFocus()
	end)

	self.search = edit
	return edit
end

function Window:SetTitle(text)
	-- A bare window has no title to set. Refused rather than raised, because the
	-- caller that asks is a page naming itself and a page in a window with no
	-- title bar is not a bug.
	if not self.title then
		return false
	end
	self.title:SetText(text)
	return true
end

-- How much of the world comes through the window, as a fraction of the
-- palette's own alpha rather than instead of it. A window at 1 is the window
-- the theme describes; below that it is the same colour, thinner.
-- A screen window has no ground to make more or less opaque, and asking one how
-- see-through it should be is a question with no answer rather than a mistake:
-- it is already the world with writing on it.
function Window:SetOpacity(fraction)
	if not self.bg then
		return
	end
	local alpha = (C.window[4] or 1) * math.max(0, math.min(fraction or 1, 1))
	self.bg:SetColorTexture(C.window[1], C.window[2], C.window[3], alpha)
end

-- The world behind a screen window, darkened or not, from wherever it stands.
--
-- Run out of the frame's own OnShow, so every route up fades from nothing: the
-- method, Escape's counterpart on the key, and the secure snippet that is the
-- only one of the three that works in a fight. Run again by whoever owns the
-- setting when the player turns it off, because a tick box that does nothing
-- until you shut the sheet and open it again is a tick box you press twice.
--
-- Off is instant and on is a fade, and that is not an oversight. On happens on
-- a key press with the player looking at the world it covers; off happens on a
-- settings page, where the shadow going away is the answer to the click that
-- was just made and there is nothing for it to read as.
function Window:Darken()
	local dark = self.dark
	if not dark then
		return false
	end
	local Animations = ns.Ck.Animations
	if not self.darkOf() then
		Animations.Stop(self.darkening)
		dark:SetAlpha(0)
		dark:Hide()
		return false
	end
	-- From nothing every time, rather than from wherever the last run left it.
	-- The sheet is shut by Escape and by a snippet as well as by Window:Hide,
	-- and a fade that resumed from the alpha it was at would come up solid on
	-- every route this file does not own.
	dark:SetAlpha(0)
	dark:Show()
	Animations.Arm(self.darkening, DARK_SECONDS, Animations.Ease.out)
	Animations.Alpha(self.darkening, 0, 1)
	Animations.Start(self.darkening)
	return true
end

-- Raised as well as shown, for the reason Pile gives. Not in combat for a
-- secure window: a raise is a frame level write, and the client refuses those
-- on a protected frame mid fight the same way it refuses the Show.
function Window:Show()
	if not (self.secure and InCombatLockdown()) then
		self.frame:Raise()
	end
	self.frame:Show()
end

function Window:Hide()
	UI.CloseDropdown()
	UI.StopCapture()
	self.frame:Hide()
end

function Window:IsShown()
	return self.frame:IsShown()
end

--------------------------------------------------------------------------
-- The rail
--
-- A column down the left edge that folds. Eight groups, and the one you are in
-- stands open with its sections listed under it, indented. Choosing a section
-- is one click on the thing you came for rather than a click on the rail and a
-- second one on a strip of tabs across the top of the page.
--
-- The strip was the thing this replaced and it had two faults a fold does not.
-- It could only show the sections of the group you were already on, so the
-- window never showed more than an eighth of itself at once. And a group with
-- eleven of them wrapped onto three lines of stubs, which took a fifth of the
-- page's height to say what a column says in a column.
--
-- One group is open at a time. Clicking a shut one opens it onto whichever
-- section you were last reading there; clicking the open one shuts it, and the
-- page stays up with the group's own row carrying the mark instead. So the rail
-- can be folded flat to eight lines without the window going blank.
--
-- It sits in a scroll view of its own, because open is taller than shut: eight
-- groups fit the rail with room over, and eight plus the eleven sections of
-- Fighting do not. Reveal keeps whatever is selected inside the viewport, so
-- opening a long group never scrolls the chosen row off the bottom.
--------------------------------------------------------------------------

local Rail = {}
Rail.__index = Rail

-- The fold mark. A chevron down when the group is open and a chevron right when
-- it is shut, drawn out of Media/Glyphs.ttf by UI.Glyph. The letters here are
-- the letters that face cuts the two chevrons onto, and they are also what you
-- see if the file does not load, which is the whole reason it is done this way.
local OPEN, SHUT = "v", ">"

-- The column the fold mark sits in, and the step a section hangs under its
-- group. One number for both, because the two have to agree: a chevron is
-- nearly a full em wide where the letter it replaced was a third of one, and
-- the first version of this put the mark and the group's own name in the same
-- four pixels.
local FOLD = M.rowGap + M.glyph + M.rowGap

local function PaintRail(button)
	local shade = button.selected and C.selected or (button.hovered and C.hover or C.rail)
	UI.Tint(button.bg, shade)
	button.mark:SetShown(button.selected and true or false)
	if button.dot then
		button.dot:SetShown(button.dot.lit and true or false)
	end
	if button.fold then
		button.fold:SetText(button.open and OPEN or SHUT)
	end

	-- Three shades rather than two. A section that is showing is the heading
	-- colour, an open group is the body colour because it is the heading of a
	-- list you are reading, and everything shut is dim.
	local color = C.dim
	if button.selected then
		color = C.heading
	elseif button.open then
		color = C.text
	end
	button.text:SetTextColor(color[1], color[2], color[3])
end

function UI.Rail(parent, opts)
	local rail = setmetatable({ groups = {}, onSelect = opts and opts.onSelect }, Rail)
	rail.frame = CreateFrame("Frame", nil, parent)
	local bg = ns.Fill(rail.frame, "BACKGROUND", C.rail[1], C.rail[2], C.rail[3], 1)
	bg:SetAllPoints()

	rail.view = UI.ScrollView(rail.frame)
	rail.view.frame:SetPoint("TOPLEFT", M.rowGap, -M.rowGap)
	rail.stack = UI.Stack(rail.view.canvas)
	return rail
end

-- The half of a row that is the same whichever kind it is. A row is built once
-- and kept: a frame cannot be destroyed on this client, so folding hides rows
-- and rebuilds the column's cell list rather than unmaking anything.
local function RailRow(rail, left)
	local button = CreateFrame("Button", nil, rail.stack.frame)
	button.bg = ns.Fill(button, "BACKGROUND", C.rail[1], C.rail[2], C.rail[3], 1)
	button.bg:SetAllPoints()
	button.mark = ns.Fill(button, "ARTWORK", C.accent[1], C.accent[2], C.accent[3], 1)
	button.mark:SetPoint("TOPLEFT")
	button.mark:SetPoint("BOTTOMLEFT")
	button.mark:SetWidth(2)

	button.text = UI.Label(button, M.font, C.dim, "LEFT", UI.FLAT)
	button.text:SetPoint("LEFT", left, 0)
	UI.Wrap(button.text, false)

	button:SetScript("OnEnter", function(this)
		this.hovered = true
		PaintRail(this)
	end)
	button:SetScript("OnLeave", function(this)
		this.hovered = nil
		PaintRail(this)
	end)
	return button
end

function Rail:Add(label)
	local at = #self.groups + 1
	local group = { at = at, children = {}, current = 1 }
	local button = RailRow(self, FOLD)

	-- The fold, in the margin the indent leaves free on the rows below it, so a
	-- group's own letters and its sections' letters do not start in the same
	-- column and the shape of the list is legible with the words unread.
	button.fold = UI.Glyph(button, M.glyph, C.quiet, "LEFT")
	button.fold:SetPoint("LEFT", M.rowGap, 0)
	UI.Wrap(button.fold, false)

	-- Whether anything filed under this group is drawing on your screen. Three
	-- pixels in the accent colour against the right edge, which is the one part
	-- of a rail row nothing else uses. It is the single question the window
	-- could never answer without opening forty five tabs.
	button.dot = ns.Fill(button, "OVERLAY", C.accent[1], C.accent[2], C.accent[3], 1)
	button.dot:SetSize(3, 3)
	button.dot:SetPoint("RIGHT", -M.rowGap, 0)
	button.dot:Hide()
	button.text:SetPoint("RIGHT", button.dot, "LEFT", -M.rowGap, 0)
	button.text:SetText(label)

	-- What the label has to fit in: the row less the fold on the left, the dot on
	-- the right and the air round both. Recorded rather than worked out again,
	-- because the gate that refuses a rail line too long to read has to measure
	-- against the same number the anchors above use.
	button.room = FOLD + 3 + M.rowGap * 2

	button:SetScript("OnClick", function()
		self:Toggle(at)
	end)

	group.button = button
	PaintRail(button)
	self.groups[at] = group
	return at
end

function Rail:AddChild(at, label)
	local group = self.groups[at]
	if not group then
		return nil
	end
	local index = #group.children + 1
	local button = RailRow(self, M.gutter)
	button.text:SetPoint("RIGHT", -M.rowGap, 0)
	button.text:SetText(label)
	button.room = M.gutter + M.rowGap
	button:SetScript("OnClick", function()
		self:Select(at, index)
	end)
	PaintRail(button)
	group.children[index] = button
	return index
end

-- The column, rebuilt from what is open. Cells are thrown away and re-added
-- rather than shown and hidden in place, because a hidden frame still holds its
-- cell's height and the fold would cost nothing at all.
function Rail:Layout()
	self.stack.cells = {}
	for _, group in ipairs(self.groups) do
		self.stack:Add(group.button, { height = M.railRow, gap = 1 })
		for _, child in ipairs(group.children) do
			child:SetShown(group.open and true or false)
			if group.open then
				self.stack:Add(child, { height = M.railRow, gap = 1, indent = FOLD })
			end
		end
	end
	-- Nothing has said how big the rail is until Resize runs, and the window
	-- chooses its first line before that. So the column is laid out and the
	-- viewport is told about it only once there is a viewport to tell.
	self.stack:SetWidth(self.view.width or 0)
	local extent = self.stack:Reflow()
	if self.view.height then
		self.view:Update(extent)
	end
end

function Rail:Paint()
	for at, group in ipairs(self.groups) do
		local holds = (at == self.selected)
		group.button.open = group.open
		group.button.selected = holds and not group.open
		PaintRail(group.button)
		for index, child in ipairs(group.children) do
			child.selected = holds and group.open and index == self.section
			PaintRail(child)
		end
	end
end

-- Keep a row inside the viewport. Opening the longest group puts its last
-- sections below the fold, and a selection you cannot see is a rail that has
-- stopped saying where you are.
function Rail:Reveal(button)
	if not self.view.height then
		return false
	end
	local top = 0
	for _, cell in ipairs(self.stack.cells) do
		if cell.frame == button then
			if top < self.view.offset then
				self.view:ScrollTo(top)
			elseif top + cell.height > self.view.offset + self.view.height then
				self.view:ScrollTo(top + cell.height - self.view.height)
			end
			return true
		end
		top = top + cell.height + cell.gap
	end
	return false
end

function Rail:Resize(width, height)
	self.frame:SetSize(width, height)
	self.view:Resize(width - M.rowGap * 2, height - M.rowGap * 2)
	self:Layout()
end

-- Whether this group holds something that is on. Returns whether it changed, so
-- a caller refreshing every group does not repaint the eight of them every time
-- anything anywhere in the window is clicked.
function Rail:SetDot(at, lit)
	local group = self.groups[at]
	if not group or (group.button.dot.lit and true or false) == (lit and true or false) then
		return false
	end
	group.button.dot.lit = lit and true or false
	PaintRail(group.button)
	return true
end

-- A section, named by its group and its place in it. The section is optional
-- and defaults to whichever one that group was last left on, which is what a
-- click on a folded group means.
function Rail:Select(at, index)
	local group = self.groups[at]
	if not group then
		return false
	end
	index = index or group.current or 1
	if not group.children[index] then
		return false
	end

	for _, other in ipairs(self.groups) do
		other.open = (other == group)
	end
	group.current = index
	self.selected, self.section = at, index

	self:Layout()
	self:Paint()
	-- Told first, revealed second. What the window does with the choice is lay
	-- itself out again, and that hands the rail its size, so a scroll worked out
	-- before it would be worked out against the last one.
	if self.onSelect then
		self.onSelect(at, index)
	end
	self:Reveal(group.children[index])
	return true
end

-- What a click on a group row does. Open it onto where you left it, or shut the
-- one that is already open and leave its page up.
function Rail:Toggle(at)
	local group = self.groups[at]
	if not group then
		return false
	end
	if not group.open then
		return self:Select(at, group.current)
	end
	group.open = false
	self:Layout()
	self:Paint()
	return true
end

--------------------------------------------------------------------------
-- The tab strip
--
-- A row of choices across the top of a window or a page, one per thing behind
-- it. The options window used to navigate with one and now folds its rail
-- instead; what is left are the two places a strip is the right shape: the chat
-- window's channels, and the list of loadouts inside one page of the panel.
-- Both are short, both are one word each, and neither is the top level of
-- anything.
--
-- Each tab is as wide as its own title, because a title is what a tab is for
-- and cutting it in half to make the row tidy loses the only information on it.
-- A row that runs out of width wraps onto the next one and the strip grows by a
-- whole tab, so eight of them is a taller strip rather than eight unreadable
-- stubs.
--
-- **A bare strip is the same row with its chrome taken off**: no fill behind a
-- tab, no line under the row, just the words and the accent bar under the one
-- you are on. It is for the character sheet, which is a backdrop the size of
-- the screen rather than a window, and where a strip of filled buttons over the
-- world is the one thing on the page that still looks like a dialog. What a tab
-- is stays exactly what it was: the colours already carry selected, hovered and
-- unread on their own, and the fill was never the thing saying which was which.
--------------------------------------------------------------------------

local TABPAD = 10

local Tabs = {}
Tabs.__index = Tabs

local function PaintTab(button)
	local fill = C.chrome
	local tone = C.dim
	if button.selected then
		fill, tone = C.selected, C.heading
	elseif button.hovered then
		fill, tone = C.hover, C.text
	elseif button.unread then
		-- A tab you are not on with something on it reads as the selected tab
		-- reads, minus the accent bar under it. Anything louder is a chat window
		-- that flashes at you all night; anything quieter is a tab you never
		-- notice, which is the whole reason the mark exists.
		tone = C.text
	end
	if button.bg then
		UI.Tint(button.bg, fill)
	end
	button.text:SetTextColor(tone[1], tone[2], tone[3])
	button.mark:SetShown(button.selected and true or false)
	button.dot:SetShown(button.unread and not button.selected)
end

function UI.TabStrip(parent, opts)
	local tabs = setmetatable({ buttons = {}, onSelect = opts and opts.onSelect }, Tabs)
	tabs.bare = opts and opts.bare and true or false
	tabs.frame = CreateFrame("Frame", nil, parent)
	if not tabs.bare then
		tabs.rule = UI.Rule(tabs.frame, C.hairline)
		tabs.rule:SetPoint("BOTTOMLEFT")
		tabs.rule:SetPoint("BOTTOMRIGHT")
	end
	return tabs
end

function Tabs:Add(label)
	local index = #self.buttons + 1
	local button = CreateFrame("Button", nil, self.frame)
	button:SetHeight(M.tab)
	if not self.bare then
		button.bg = ns.Fill(button, "BACKGROUND", C.chrome[1], C.chrome[2], C.chrome[3], 1)
		button.bg:SetAllPoints()
	end
	button.mark = ns.Fill(button, "ARTWORK", C.accent[1], C.accent[2], C.accent[3], 1)
	button.mark:SetPoint("BOTTOMLEFT")
	button.mark:SetPoint("BOTTOMRIGHT")
	button.mark:SetHeight(2)

	-- What says a tab has something on it. Two pixels in the accent colour in
	-- the top right corner of the tab, which is a corner nothing else uses.
	button.dot = ns.Fill(button, "OVERLAY", C.accent[1], C.accent[2], C.accent[3], 1)
	button.dot:SetSize(3, 3)
	button.dot:SetPoint("TOPRIGHT", -3, -3)
	button.dot:Hide()

	-- Flat inside a window, shadowed on a bare strip. A flat word is right on a
	-- filled button and unreadable on a bright afternoon, which is what a bare
	-- strip is drawn over.
	button.text = UI.Label(button, M.font, C.dim, "CENTER",
		self.bare and UI.SHADOW or UI.FLAT)
	button.text:SetPoint("CENTER")
	UI.Wrap(button.text, false)
	button.text:SetText(label)

	button:SetScript("OnClick", function()
		self:Select(index)
	end)
	button:SetScript("OnEnter", function(this)
		this.hovered = true
		PaintTab(this)
	end)
	button:SetScript("OnLeave", function(this)
		this.hovered = nil
		PaintTab(this)
	end)

	PaintTab(button)
	self.buttons[index] = button
	return index
end

-- Lays the row out and returns how tall the strip ended up, which is one tab
-- per line of them. The caller has to take that answer and give the rest of the
-- height to the content, because a strip that wrapped and was not asked would
-- draw over the first row of the page.
function Tabs:Resize(width)
	local x, y, lines = 0, 0, 1
	local shown = 0

	for index = 1, #self.buttons do
		local button = self.buttons[index]
		if button.hidden then
			button:Hide()
		else
			shown = shown + 1
			local text = button.text:GetStringWidth() or 0
			local size = UI.Round(self.frame, text + TABPAD * 2)
			if size > width then
				size = width
			end
			if x > 0 and x + size > width then
				x = 0
				y = y + M.tab
				lines = lines + 1
			end
			button:SetWidth(size)
			button:ClearAllPoints()
			button:SetPoint("TOPLEFT", self.frame, "TOPLEFT", x, -y)
			button:Show()
			x = x + size
		end
	end

	local height = lines * M.tab + M.hairline
	self.frame:SetSize(width, height)
	self.shown = shown
	return height
end

-- A tab can be renamed after it exists, because a page's first section is made
-- before the page's builder has said what it is called.
function Tabs:SetLabel(index, label)
	if self.buttons[index] then
		self.buttons[index].text:SetText(label)
	end
end

-- A tab that is not there yet.
--
-- The strip is built once, because a frame cannot be destroyed on this client
-- and rebuilding one would leak a button every time the strip changed. So a tab
-- whose contents do not exist is hidden rather than unmade, and Resize skips it
-- so the tabs after it close the gap. The chat window's people tab is the only
-- caller: it is not drawn until there is somebody on the list.
function Tabs:SetShown(index, shown)
	local button = self.buttons[index]
	if not button then
		return false
	end
	button.hidden = not shown
	return true
end

function Tabs:IsShown(index)
	local button = self.buttons[index]
	return button ~= nil and not button.hidden
end

-- Whether a tab has something on it you have not looked at. Selecting a tab
-- clears its own mark, because looking at it is what unread means.
function Tabs:SetUnread(index, unread)
	local button = self.buttons[index]
	if not button or (button.unread and true or false) == (unread and true or false) then
		return false
	end
	button.unread = unread and true or false
	PaintTab(button)
	return true
end

function Tabs:Select(index)
	if not self.buttons[index] then
		return false
	end
	self.selected = index
	for i = 1, #self.buttons do
		self.buttons[i].selected = (i == index)
		if i == index then
			self.buttons[i].unread = false
		end
		PaintTab(self.buttons[i])
	end
	if self.onSelect then
		self.onSelect(index)
	end
	return true
end


--------------------------------------------------------------------------
-- The list
--
-- A column of rows down the left of a window, where the rows change while the
-- window is open. That is the whole difference between this and the rail above
-- it, and it is why there are two of them rather than one with a flag.
--
-- The rail is the options window's: forty five sections that are known at load,
-- built once, folded and unfolded. The list is the chat window's: a room per
-- conversation, and the set of conversations changes every time you join a
-- party, leave a guild, or get a whisper from somebody you have never spoken to.
-- Folding is not the question there. What is drawn at all is.
--
-- So a caller hands over the rows it wants and gets them, and this file works
-- out which frames to reuse. A frame cannot be destroyed on this client, so
-- rows are pooled and the ones past the end are hidden rather than unmade,
-- which is the same trick the loadout tabs use and for the same reason.
--
-- A row is one of two things. A header is a dim word with no background and no
-- click, there to say what the rows under it are. An entry is a button with a
-- label, an accent mark down its left edge when it is the one you are reading,
-- and a count on the right when it holds something you have not read.
--
-- An entry may also carry three things a caller asks the whole column for, and
-- the quest log is what asked for all three. A glyph in front of the words,
-- which is a state the row is in rather than anything you can press. A note at
-- the right, which is a small number about the row that is not a count of
-- unread lines. And a strip of marks at the far right that you can press, one
-- per action the caller offers on every entry.
--
-- **The marks are drawn on every row rather than on the one under the cursor.**
-- Revealing them on hover is the tidier column and it is a trap: the cursor
-- moving from the row onto the mark leaves the row, the row repaints without
-- its marks, and the button the player was reaching for is gone before the
-- click lands. So they are always there, drawn quiet, and they brighten under
-- the cursor. What is quiet is legible and what is missing is not.
--
-- Rows are addressed by a string id rather than by position, because the
-- position of a whisper moves every time somebody else whispers you and the
-- selection has to survive that.
--------------------------------------------------------------------------

local List = {}
List.__index = List

-- How much of a room's icon you see. The same three steps the words used to be
-- drawn in: the room you are reading is whole, a room holding something you
-- have not read is nearly whole, and a quiet room is half there. A picture has
-- no colour to lend a state, so brightness is what carries it.
local FULL, WAITING, QUIET = 1, 0.9, 0.5

-- The column a row's glyph is drawn in, and one mark you can press at the right
-- of it. The glyph is the width the middle column of the quest window reserves
-- for the same mark, so the two read as one interface; the button is wider than
-- the glyph in it because it is a thing you aim at with a mouse.
local MARK, ACTION = 10, 16

local function PaintCount(button)
	local waiting = button.unread and button.unread > 0 and not button.selected
	if not waiting then
		button.badge:Hide()
		if button.badgeBg then
			button.badgeBg:Hide()
		end
		return false
	end
	button.badge:SetText(button.unread > 99 and "99+" or tostring(button.unread))
	button.badge:Show()
	if button.badgeBg then
		button.badgeBg:Show()
	end
	return true
end

-- The glyph, the note and the strip of marks, shown on an entry and never on a
-- header. Split out because both halves of PaintListRow want it and the header
-- half returns before it reaches the bottom of the function.
local function PaintExtras(button, entry)
	if button.glyph then
		button.glyph:SetShown(entry and button.glyph:GetText() ~= "")
	end
	if button.note then
		button.note:SetShown(entry and button.note:GetText() ~= "")
	end
	for index = 1, #(button.actions or {}) do
		local mark = button.actions[index]
		mark:SetShown(entry and mark.wanted ~= false)
	end
end

local function PaintListRow(button)
	if button.header then
		UI.Tint(button.bg, C.rail)
		button.text:SetTextColor(C.quiet[1], C.quiet[2], C.quiet[3])
		button.mark:Hide()
		button.badge:Hide()
		if button.badgeBg then
			button.badgeBg:Hide()
		end
		PaintExtras(button, false)
		if button.rule then
			button.rule:SetShown(button.icons and true or false)
		end
		return
	end

	local shade = button.selected and C.selected or (button.hovered and C.hover or C.rail)
	UI.Tint(button.bg, shade)
	button.mark:SetShown(button.selected and true or false)
	if button.rule then
		button.rule:Hide()
	end

	-- Three shades, the same three the rail uses. The room you are reading is
	-- the heading colour, a room with something in it is the body colour, and a
	-- quiet room is dim. The count on the right is what says how much; the
	-- colour is what you see without reading it.
	--
	-- A row may also carry a colour of its own, which overrides the middle of
	-- the three and never the selected one. The quest log is what asked: a
	-- quest's level colour is the difference between a fight you walk into and
	-- one you die in, and it is a fact about the row rather than about whether
	-- you have read it. Selected still wins, because which row you are on has
	-- to be legible before anything the row says is.
	local color = C.dim
	local light = QUIET
	if button.selected then
		color, light = C.heading, FULL
	elseif button.tint then
		color, light = button.tint, WAITING
	elseif button.unread and button.unread > 0 then
		color, light = C.text, WAITING
	end
	button.text:SetTextColor(color[1], color[2], color[3])
	if button.icon then
		button.icon:SetAlpha(button.hovered and FULL or light)
	end

	PaintExtras(button, true)
	PaintCount(button)
end

-- opts.onSelect is handed (id, which, mods): the row, the button it was pressed
-- with, and what was held down at the press. The last two are nil where the
-- selection moved without a click, so a caller reading a modifier checks the
-- button first. See List:Press, which is the only thing that fills them in.
--
-- opts.icons draws a picture per row instead of a word, which is what the chat
-- window's rail is: thirteen rooms down a column twenty six pixels wide, and
-- the name of each in its hover. A header is a hairline there rather than a
-- caption, because "Channels" does not fit in twenty six pixels and the air
-- between two runs of icons says the same thing.
--
-- opts.describe is handed a row and answers a tooltip subject, which is the only place
-- an icon rail can put a name. Without it the rail is a column of pictures
-- nobody can read.
--
-- opts.marks reserves a glyph column in front of the words on every entry, so
-- that the marks line up down one edge whether or not this row has one.
--
-- opts.actions is what a caller offers on every entry: an array of
-- { glyph, tip, onClick }, drawn as marks at the right edge in the order given
-- and handed the row's own id when pressed. An entry may carry `shown`, which
-- is handed the same id and decides whether this row gets that mark at all.
--
-- The column reserves the strip's width whether or not the cursor is on the
-- row, because a strip that appeared on hover would change how much room the
-- words have as you move down it.
function UI.List(parent, opts)
	local list = setmetatable({ pool = {}, rows = {}, onSelect = opts and opts.onSelect }, List)
	list.icons = opts and opts.icons and true or false
	-- How big the picture on an icon row is drawn, and the row and the column
	-- follow it. The theme's number until the caller says otherwise, which the
	-- chat window does from a setting: a fourteen pixel picture is the right
	-- size beside eleven point text and the wrong size for anybody who has
	-- moved the text to eighteen. See List:SetIconSize.
	list.iconSize = M.roomIcon
	list.describe = opts and opts.describe
	list.marks = opts and opts.marks and true or false
	list.actions = opts and opts.actions or nil
	-- opts.onBack is the way out of whatever this column is part of, called on a
	-- right click on any row. The dungeon log is what asked: its column is one
	-- dungeon's bosses and the gesture that leaves it for the shelf has to work
	-- over the column as much as over the map beside it.
	list.onBack = opts and opts.onBack or nil
	-- opts.onRight is a right click on one entry, handed that entry's id. The
	-- chat rail is what asked: a whisper room is closed by right clicking it,
	-- and a column of pictures twenty four pixels wide has no room for a mark
	-- beside each one. A list that offers both takes the row's own gesture
	-- first, and the way out only where there was no row under the cursor.
	list.onRight = opts and opts.onRight or nil
	-- Named if the caller asks, for the reason the aura rows and the meter are:
	-- a column that has laid itself out wrongly has to be measurable from a
	-- macro and from scripts/harness.lua, and the alternative is the file that
	-- owns it handing out a reference to its own tables.
	list.frame = CreateFrame("Frame", opts and opts.name, parent)
	list.bg = ns.Fill(list.frame, "BACKGROUND", C.rail[1], C.rail[2], C.rail[3], 1)
	list.bg:SetAllPoints()

	list.view = UI.ScrollView(list.frame, { overlay = list.icons })
	list.view.frame:SetPoint("TOPLEFT", M.rowGap, -M.rowGap)
	list.stack = UI.Stack(list.view.canvas)
	return list
end

-- One row's frame, made once and reused for whatever row lands on it next. It
-- carries every part either kind of row can want, because a header that became
-- an entry on the next refresh would otherwise need a frame of its own.
-- The picture on an icon row, and the count that sits in its corner.
--
-- The count is over the icon rather than beside it, because there is no beside
-- in a column this narrow, and it carries its own dark rectangle: an accent
-- coloured 3 on top of whatever art the room's icon happens to be is a number
-- you can lose against a bright corner.
local function IconRow(list, button)
	button.icon = UI.Icon(button, "ARTWORK")
	button.icon:SetSize(list.iconSize, list.iconSize)
	button.icon:SetPoint("CENTER")

	-- The chip the count stands on, opaque and a rectangle of its own.
	--
	-- Both of those were different and both were wrong. It was a 55% black
	-- pinned to the two corners of the string, which is a chip that darkens
	-- whatever is behind the number rather than replacing it, and takes its
	-- shape from a string that has not been measured yet. That was survivable
	-- while the row behind it was opaque; it stopped being survivable when the
	-- row learned to fade, because then the thing behind the number is the
	-- world. A count is the whole of the alert design in this window and it has
	-- to be legible at every stop of the opacity slider, so it gets a surface
	-- the slider does not reach.
	button.badgeBg = ns.Fill(button, "OVERLAY", C.sunken[1], C.sunken[2], C.sunken[3], 1)
	-- A size under the one a word row's count is drawn at, because this one is
	-- not beside the row's text but in the corner of a fourteen pixel picture,
	-- and a number as tall as three quarters of the icon is a badge with an
	-- icon behind it rather than the other way round.
	button.badge:SetFontObject(UI.Font(M.glyph, UI.FLAT))
	button.badge:ClearAllPoints()
	button.badge:SetPoint("BOTTOMRIGHT", button.icon, "BOTTOMRIGHT", 1, -1)
	button.badgeBg:SetPoint("LEFT", button.badge, "LEFT", -1, 0)
	button.badgeBg:SetPoint("RIGHT", button.badge, "RIGHT", 1, 0)
	button.badgeBg:SetHeight(M.glyph + 2)
	button.badgeBg:Hide()

	-- A header is a hairline across the column with air either side of it. It is
	-- drawn on the same pooled frame as a room, because a run that gains a
	-- header on the next refresh would otherwise need a frame of its own.
	button.rule = UI.Rule(button, C.hairline)
	button.rule:SetPoint("LEFT", M.rowGap, 0)
	button.rule:SetPoint("RIGHT", -M.rowGap, 0)
	button.rule:Hide()
	button.text:Hide()

	button.icons = true
	-- The hover scripts are the row's own, because they paint as well as
	-- describe. What ns.Tip.Hang would have done for free is the one thing left, and
	-- it is the thing a frame under the cursor all evening cannot do without:
	-- a right drag over the rail has to turn the camera rather than stop dead.
	--
	-- Unless the row answers the right button itself. A button passed through
	-- never reaches the frame's scripts, whatever RegisterForClicks said, so a
	-- rail that hands the camera its right button and closes a conversation on
	-- the same button does the first and never the second. That is how a
	-- right click on a whisper room turned the camera and left the room where
	-- it was. A column that took the gesture keeps the button, and the price
	-- is that a right drag begun on its rows does not turn the camera.
	if not (list.onBack or list.onRight) then
		UI.PassCamera(button)
	end
	return button
end

-- One mark at the right of a row: a glyph you can press, with no surface under
-- it and no edge round it.
--
-- Not UI.Button, and the difference is the point. A button is a control with a
-- filled rectangle and a hairline, which is right in a footer and wrong twenty
-- times down a column: twenty of them is a wall of small boxes over the words
-- they belong to. This is a letter that lights up, which is as much furniture
-- as a row of a list can afford.
local function RowMark(button, spec, outermost, right)
	local mark = CreateFrame("Button", nil, button)
	mark:SetSize(ACTION, ACTION)
	if outermost then
		mark:SetPoint("RIGHT", right, "RIGHT", -M.rowGap, 0)
	else
		mark:SetPoint("RIGHT", right, "LEFT", 0, 0)
	end

	mark.text = UI.Glyph(mark, M.glyph, C.quiet, "CENTER")
	mark.text:SetPoint("CENTER")
	mark.text:SetText(spec.glyph or "")

	mark:SetScript("OnEnter", function(self)
		self.text:SetTextColor(C.text[1], C.text[2], C.text[3])
		if spec.tip then
			ns.Tip.Settle(self, { kind = "note", title = spec.tip }, true, nil, ns.Tip.HOLD)
		end
	end)
	mark:SetScript("OnLeave", function(self)
		self.text:SetTextColor(C.quiet[1], C.quiet[2], C.quiet[3])
		if spec.tip then
			ns.Tip.Close()
		end
	end)
	mark:SetScript("OnClick", function(self)
		local row = self:GetParent()
		if row.id ~= nil and spec.onClick then
			spec.onClick(row.id)
		end
	end)
	return mark
end

-- The marks, right to left, and whatever the next thing along the row anchors
-- to. A list that offered none hands its rows straight back.
local function RowMarks(list, button)
	if not list.actions then
		return button, "RIGHT", -M.rowGap
	end
	-- Built from the right edge inwards so that the caller's first action is the
	-- leftmost mark. A list is written the way it is read.
	button.actions = {}
	local right = button
	for at = #list.actions, 1, -1 do
		right = RowMark(button, list.actions[at], at == #list.actions, right)
		button.actions[at] = right
	end
	return right, "LEFT", 0
end

-- One modifier, asked of the client rather than remembered. A key held is a
-- state the client already keeps and this widget has no event that would keep
-- it correctly: a modifier cached at the last press is the modifier of the last
-- press, and the row would answer a plain click as a shift click for as long as
-- nobody pressed shift again.
local function Down(ask)
	return type(ask) == "function" and ask() and true or false
end

-- What was held at the moment of the press. Read here rather than in the
-- caller's own handler, because by the time the caller runs the key may be up:
-- the press is the only moment the answer is the player's.
local function Held()
	return {
		shift = Down(IsShiftKeyDown),
		ctrl = Down(IsControlKeyDown),
		alt = Down(IsAltKeyDown),
	}
end

local function ListRow(list, index)
	local button = CreateFrame("Button", nil, list.stack.frame)
	button.bg = ns.Fill(button, "BACKGROUND", C.rail[1], C.rail[2], C.rail[3], 1)
	button.bg:SetAllPoints()
	button.mark = ns.Fill(button, "ARTWORK", C.accent[1], C.accent[2], C.accent[3], 1)
	button.mark:SetPoint("TOPLEFT")
	button.mark:SetPoint("BOTTOMLEFT")
	button.mark:SetWidth(2)

	-- Right to left down one chain: the marks you can press, then the note, then
	-- the unread count, then whatever room is left is the words. Chained rather
	-- than each given its own offset, because a region a row does not use is
	-- empty and an empty string is no pixels wide, so the ones that are there
	-- close up without anything having to know which.
	local right, edge, gap = RowMarks(list, button)

	button.note = UI.Label(button, M.small, C.accent, "RIGHT", UI.FLAT)
	button.note:SetPoint("RIGHT", right, edge, gap, 0)
	UI.Wrap(button.note, false)

	button.badge = UI.Label(button, M.small, C.accent, "RIGHT", UI.FLAT)
	button.badge:SetPoint("RIGHT", button.note, "LEFT", 0, 0)
	UI.Wrap(button.badge, false)

	-- The glyph column, on a list that asked for one. Reserved on every entry
	-- whether or not this row has a mark, so the ones that do line up.
	local left = M.gutter
	if list.marks then
		button.glyph = UI.Glyph(button, M.glyph, C.quiet, "LEFT")
		button.glyph:SetPoint("LEFT", M.rowGap, 0)
		button.glyph:SetWidth(MARK)
		UI.Wrap(button.glyph, false)
		left = M.rowGap + MARK + M.rowGap
	end

	button.text = UI.Label(button, M.font, C.dim, "LEFT", UI.FLAT)
	button.text:SetPoint("LEFT", left, 0)
	button.text:SetPoint("RIGHT", button.badge, "LEFT", -M.rowGap, 0)
	UI.Wrap(button.text, false)

	-- Both buttons where the caller offered a way back or a gesture on the
	-- row, because a gesture that works on the window and not on the column
	-- under the cursor is a gesture that works nowhere: a row is a button, a
	-- button with no right click registered eats the press, and nothing behind
	-- it is ever told.
	--
	-- The list stays here and does not register both on every row, which was
	-- the other way to give onSelect a button to report. A row that takes the
	-- right button keeps it, and the price is written above UI.PassCamera: a
	-- right drag begun over that column stops dead instead of turning the
	-- camera. The quest log's left column is two hundred pixels of the screen
	-- and that trade is not worth an argument nothing reads yet.
	--
	-- A modifier costs nothing here either way. RegisterForClicks names the
	-- button and the edge and says nothing about shift, so a shift left click
	-- arrives at OnClick as "LeftButton" on a row registered for the left
	-- button and on a row that registered nothing.
	if list.onBack or list.onRight then
		button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	end
	button:SetScript("OnClick", function(this, which)
		if which == "RightButton" then
			if list.onRight and this.id ~= nil then
				list.onRight(this.id)
			elseif list.onBack then
				list.onBack()
			end
			return
		end
		if this.id then
			-- Press rather than Select, and the difference is the whole of
			-- this gesture. See List:Press.
			list:Press(this.id, which, Held())
		end
	end)
	-- The hover paints as well as describes, so the two scripts are hung here
	-- and the tooltip is opened from inside them rather than through
	-- ns.Tip.Hang, which would take both.
	button:SetScript("OnEnter", function(this)
		this.hovered = true
		PaintListRow(this)
		if list.describe and this.id then
			ns.Tip.Open(this, list.describe(this))
		end
	end)
	button:SetScript("OnLeave", function(this)
		this.hovered = nil
		PaintListRow(this)
		if list.describe then
			ns.Tip.Close()
		end
	end)

	if list.icons then
		IconRow(list, button)
	end

	-- A row made after the column was faded takes the fraction with it. A pool
	-- fills as the column grows, so the alternative is a rail whose first ten
	-- rows are transparent and whose eleventh is black.
	UI.Fade(button.bg, list.opacity)

	list.pool[index] = button
	return button
end

-- One row, filled in from what the caller said is on it. Split out of Set
-- because a column of words and a column of icons fill a row in differently
-- and Set is the part that is the same for both.
function List:Row(index, row)
	local button = self.pool[index] or ListRow(self, index)
	button.header = row.header and true or false
	button.id = row.id
	button.unread = row.unread or 0
	button.tint = row.color
	button.selected = (row.id ~= nil and row.id == self.selected)

	if self.icons then
		button.icon:SetShown(not button.header)
		button.icon:SetTexture(row.icon or "")
		button.label = row.header or row.label or ""
	else
		button.text:SetText(row.header or row.label or "")
		button.text:SetFontObject(UI.Font(row.header and M.small or M.font,
			UI.FLAT))
	end

	-- The glyph keeps its own colour through everything PaintListRow does to
	-- the row, selection included. It is there to say what state the row is in,
	-- and the row it says least about must not be the one you are reading.
	if button.glyph then
		local tint = row.markColor or C.quiet
		button.glyph:SetText(row.mark or "")
		button.glyph:SetTextColor(tint[1], tint[2], tint[3])
	end
	if button.note then
		button.note:SetText(row.note or "")
	end

	-- Which of the marks this row gets. A mark that would do nothing on this
	-- row is not drawn on it: the quest log is what asked, because a client
	-- refuses to hand a quest to the party that nobody else could take, and a
	-- share arrow on such a row is a control that fails quietly when pressed.
	for at = 1, #(button.actions or {}) do
		local decide = self.actions[at].shown
		button.actions[at].wanted =
			decide == nil or (row.id ~= nil and decide(row.id) and true or false)
	end

	-- A header is a caption rather than a control, so it must not take the
	-- click meant for the room under it or light up on the way past.
	button:EnableMouse(not button.header)
	button:Show()
	PaintListRow(button)
	return button
end

-- How tall one row is. A header in an icon column is a hairline with air round
-- it rather than a word, so it takes a fraction of the height a word would.
function List:RowHeight(button)
	if not self.icons then
		return M.railRow
	end
	if button.header then
		return M.rowGap * 2 + 1
	end
	return self:IconRow()
end

-- One icon row's height, and the width a column of them wants. Both are the
-- theme's differences kept over whatever the picture is: four pixels of air
-- above and below it, five either side. The caller reads both back, because
-- the column's width is the caller's layout and the caller is what places
-- the rail, the log beside it and the line under both.
function List:IconRow()
	return self.iconSize + (M.roomRow - M.roomIcon)
end

function List:IconWidth()
	return self.iconSize + (M.rooms - M.roomIcon)
end

-- How big the picture on every row is drawn from now on, and how wide a column
-- of them wants to be.
--
-- The theme sets the picture at fourteen and the row and the column at four
-- and ten more than that, and those two differences are what is kept: a
-- twenty pixel picture sits in a twenty four pixel row down a thirty pixel
-- column, with the same air round it the theme gave the fourteen. The width
-- is answered rather than applied; see IconWidth above.
--
-- Rows already made are resized here; rows made later read the size off the
-- list. Nothing is relaid, because the caller resizes the column right after
-- and that is the one pass that lays the rows out again.
function List:SetIconSize(px)
	px = math.max(1, math.floor(tonumber(px) or M.roomIcon))
	if self.iconSize ~= px then
		self.iconSize = px
		for index = 1, #self.pool do
			local icon = self.pool[index].icon
			if icon then
				icon:SetSize(px, px)
			end
		end
	end
	return self:IconWidth()
end

-- The picture on the row with this id, for the harness. Handed out rather than
-- answered about, because what is being checked is how big a texture came
-- out, and a number this widget kept is a number this widget could keep
-- wrongly and still agree with itself.
function List:Icon(id)
	for index = 1, #self.pool do
		local button = self.pool[index]
		if button.id ~= nil and button.id == id then
			return button.icon
		end
	end
	return nil
end

-- A click on the row with this id, with either button, for the harness. It
-- runs the row's own OnClick, so what is asserted is the wiring from the row
-- to whatever the caller hung on that button and not the caller's closure on
-- its own.
function List:Click(id, which)
	for index = 1, #self.pool do
		local button = self.pool[index]
		if button.id ~= nil and button.id == id and button:IsShown() then
			-- Through the button's own press rather than its OnClick script,
			-- because the press is where the client decides whether the
			-- button reaches the script at all. Calling the script handed the
			-- chat rail a right click its rows were passing through to the
			-- camera, and certified a close that never happened in game.
			return button:Click(which or "LeftButton")
		end
	end
	return false
end

-- What the column holds now.
--
--   row.header  the word above a run of rooms, drawn dim and not clickable,
--               and a hairline with air round it in an icon column
--   row.id      what Select and the caller's onSelect name this row by
--   row.label   what it says, or what its hover says in an icon column
--   row.icon    the texture on it, in an icon column
--   row.unread  how many lines arrived here while you were somewhere else
--   row.color   the row's own colour, used when it is not the selected one
--   row.mark    a glyph in front of the words, on a list that asked for marks
--   row.markColor  what that glyph is drawn in, whatever the row's own colour
--   row.note    a small number at the right that is not a count of unread lines
--
-- The selection is kept by id across a refresh, so a whisper arriving while you
-- are reading the guild does not move you.
function List:Set(rows)
	self.rows = rows
	self.stack.cells = {}

	for index = 1, #rows do
		local button = self:Row(index, rows[index])

		-- Air above a header and none above anything else, which is what makes
		-- the runs read as runs. It is put on the row before rather than on the
		-- header itself, because a stack spaces rows by what sits under them,
		-- and the first header has no row before it to widen.
		local previous = self.stack.cells[#self.stack.cells]
		if button.header and previous then
			previous.gap = M.rowGap
		end
		self.stack:Add(button, { height = self:RowHeight(button), gap = 1 })
	end

	-- A row that is not drawn names nothing. The pool keeps every frame ever
	-- made, and a frame past the end of this refresh kept the id of whatever
	-- room it last drew: Mark found it, answered that the room was on the rail,
	-- and the window did not rebuild the column. In the game that was a
	-- conversation that had fallen off the end of the rail coming back invisible
	-- when the same person whispered again.
	for index = #rows + 1, #self.pool do
		self.pool[index].id = nil
		self.pool[index]:Hide()
	end

	self.stack:SetWidth(self.view.width or 0)
	local extent = self.stack:Reflow()
	if self.view.height then
		self.view:Update(extent)
	end
	return #rows
end

-- How wide one row in the column came out.
--
-- Public because a column whose rows are two pixels wide draws nothing, clicks
-- nowhere, and answers every other question correctly: the frame is the width
-- the theme says, the rows are the count the caller handed over, and the only
-- symptom is an empty strip. That is exactly what reserving a scrollbar column
-- inside a thirty pixel rail did.
function List:RowWidth()
	return self.stack.width or 0
end

-- How opaque the column is drawn, as a fraction of its own colours.
--
-- The chat window is what asks and its rail is what made this necessary. The
-- window's background takes an opacity setting and the rail did not, so a
-- window the player had made transparent was a black column with a pane of
-- glass beside it. Every surface in the column takes the fraction: the strip
-- behind the rows, each row's own shade, and the bar down the side of it.
--
-- The pictures, the counts and the accent mark against the selected room are
-- left alone. Those are what you read the column by, and a rail you can see
-- through is not the same request as a rail you cannot read.
function List:SetOpacity(fraction)
	self.opacity = fraction
	UI.Tint(UI.Fade(self.bg, fraction), C.rail)
	for index = 1, #self.pool do
		local button = self.pool[index]
		UI.Fade(button.bg, fraction)
		PaintListRow(button)
	end
	UI.FadeBar(self.view.bar, fraction)
	return true
end

function List:Resize(width, height)
	self.frame:SetSize(width, height)
	self.view:Resize(width - M.rowGap * 2, height - M.rowGap * 2)
	self:Set(self.rows)
end

-- Move the cursor to this id and repaint every row against it. Answers whether
-- it moved, which is what says a caller has to be told.
local function Cursor(list, id)
	if list.selected == id then
		return false
	end
	list.selected = id
	for index = 1, #list.pool do
		local button = list.pool[index]
		button.selected = (button.id ~= nil and button.id == id)
		PaintListRow(button)
	end
	return true
end

-- The row with this id, if it is drawn. Selecting one that is not there keeps
-- the id anyway, because the caller's own state is what decides which rooms
-- exist and this widget is not the place to argue with it.
--
-- Nothing is fired for a selection that is already where it is being put. That
-- refusal is what makes this safe to call from a paint: every window here hands
-- Select the id it is already showing on each repaint, and a callback fired
-- there would be a paint calling the thing that paints.
function List:Select(id)
	if not Cursor(self, id) then
		return false
	end
	if self.onSelect then
		self.onSelect(id)
	end
	return true
end

-- A click on the row with this id, which is not the same thing as putting the
-- selection on it, and the two are separate calls for one reason: a click on
-- the row you are already reading is still a click. Select refuses that move
-- and is right to, so a gesture hung on the selected row through Select alone
-- is a gesture that does nothing exactly where the player aimed it.
--
--   which  the button the row was pressed with, "LeftButton" today: the right
--          button belongs to onRight and onBack, which answer it before the
--          selection is ever reached, and a row on a list offering neither of
--          those never registered for it and never sees the press at all.
--   mods   { shift, ctrl, alt }, each a boolean, read off the client at the
--          moment of the press.
--
-- Both are nil when the selection was moved by code rather than by a hand, and
-- they arrive together or not at all. So `which` is the guard: a caller that
-- checks it before reading `mods` cannot mistake a repaint for a gesture, and
-- a pin that fires on a repaint is a pin the player did not ask for.
function List:Press(id, which, mods)
	Cursor(self, id)
	if self.onSelect then
		self.onSelect(id, which, mods)
	end
	return true
end

function List:Selected()
	return self.selected
end

-- Press one of the marks on the row with this id, and answer whether there was
-- one to press.
--
-- Public for the reason UI/Window.lua's own named frames are: a mark that is
-- drawn and wired to nothing is a control that fails silently, and the
-- alternative is a test reaching into this widget's pool and calling the
-- caller's own closure, which asserts the caller and not the column.
function List:Act(id, at)
	for index = 1, #self.pool do
		local button = self.pool[index]
		if button.id ~= nil and button.id == id and button.actions then
			-- Pressed rather than called. Click is the client's own, so the
			-- mark answers on the edge and the button it registered for and a
			-- mark wired to a click it never asked for stays silent here the way
			-- it would on screen. Reaching its OnClick by name answered for the
			-- handler and for nothing else.
			local mark = button.actions[at]
			if mark and mark:IsShown() then
				mark:Click("LeftButton")
				return true
			end
		end
	end
	return false
end

-- One row's count, without rebuilding the column.
--
-- This is the whole reason the count is not just another field of Set. A line
-- of chat changes exactly one number on one row, and rebuilding thirteen rows
-- to draw it would be thirteen SetText calls per message on a raid night.
-- Returns false when there is no such row, which is how the caller knows a
-- rebuild is the thing it actually wanted.
function List:Mark(id, unread)
	for index = 1, #self.pool do
		local button = self.pool[index]
		if button.id ~= nil and button.id == id then
			if button.unread ~= unread then
				button.unread = unread
				PaintListRow(button)
			end
			return true
		end
	end
	return false
end

-- Which way to step through the rooms from where you are, skipping the headers.
-- Tab in the chat window is what calls this, so it has to wrap and it has to
-- answer something on a column that is all headers and one room.
function List:Step(delta)
	local rows, at = self.rows, nil
	for index = 1, #rows do
		if rows[index].id ~= nil and rows[index].id == self.selected then
			at = index
		end
	end
	if not at then
		at = delta > 0 and #rows or 1
	end
	for offset = 1, #rows do
		local index = ((at - 1 + delta * offset) % #rows) + 1
		if rows[index].id ~= nil then
			return rows[index].id
		end
	end
	return nil
end
