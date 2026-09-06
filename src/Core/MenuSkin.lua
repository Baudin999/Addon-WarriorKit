local ADDON, ns = ...

local UI = ns.UI
local C, M = UI.Color, UI.Metric

local Skin = {}
ns.MenuSkin = Skin

-- The client's own menu, drawn in the addon's look.
--
-- Core/Menu.lua puts one button at the foot of the game menu, and that button
-- is the kit's: a flat grey rectangle, one physical pixel of edge, the addon's
-- own sans. Blizzard's nine above it are red glass on a parchment frame with
-- gold corners. Stack the two and ours reads as something that got stapled on,
-- which is exactly what the first screenshot of it showed.
--
-- Two ways out of that and only one of them is honest. Paint our button like
-- theirs, and the way into a window drawn in greys is a gold button, and the
-- addon has an opinion about 2007 art here that it holds nowhere else in the
-- interface. Or paint the menu. This file is the second.
--
-- It is the same job Artwork/Artwork.lua does to the action bars, on the same
-- two calls, and it keeps that file's rule: textures go, frames stay. Nothing
-- here hides a frame, because a frame in this menu is either a button that has
-- to keep working or a box the buttons hang off, and hiding either takes the
-- column with it. What goes is every texture and the heading, and what arrives
-- is the kit's own panel underneath and the kit's own paint on each button.
--
-- Nothing moves. Not one of Blizzard's buttons is anchored, resized or
-- relevelled, and the reason is the long one in Core/Menu.lua: this column is
-- laid out on every show, on the newer flavours by a layout pass that runs
-- after our hook, so a placement of ours is a placement that comes undone in
-- front of you. Paint survives that, and it survives it without a second
-- mechanism. A texture we hid stays hidden because ns.Strip leaves Hide where
-- Show used to be, and a font string we dressed stays dressed because the
-- client does not rewrite the font on a button it did not just create.
--
-- Nothing here calls anything of Blizzard's either. Every button in the menu
-- keeps its own OnClick, so Logout is still Blizzard's Logout, run from
-- Blizzard's code off Blizzard's button, and this addon is a coat of paint on
-- the path rather than a step in it. That is deliberate and it is the whole
-- reason this is a skin and not a replacement menu: a menu of our own would
-- have to make those calls itself, and the two that matter are the two an
-- addon is not allowed to make.
--
-- And it all goes back in one call, because the switch on the panel is a
-- switch and not a reload. Blizzard's regions come back through ns.Unstrip,
-- every string we dressed goes back into the font it was wearing when we found
-- it, and our own paint is hidden rather than destroyed: a texture cannot be
-- un-created, and the next switch on wants it anyway.

-- How far down the menu a button is looked for. One level, for the reason
-- Core/Menu.lua gives for its own walk: the whole tree of somebody else's
-- frame is a walk with no bottom, and every flavour of this menu either hangs
-- the column off the frame or hangs it off one box inside it.
local DEPTH = 1

-- The air a title bar needs above the first button before one is drawn at all.
-- One pixel of edge and one of daylight.
local CLEAR = 2

-- What the bar says on a client whose menu carries no heading of its own.
local UNTITLED = "Game menu"

-- The menu, and our own button in it. Our own is skipped by every walk here:
-- it is already the kit's, and painting it twice would strip the paint the
-- first pass put on.
local frame, own

-- What this file drew on the menu. One table, built on the first pass and
-- shown and hidden after that.
local paint

-- The heading read off the client's own menu, kept because the bar redraws it
-- and because the strip that hides it runs every pass.
local heading

-- What the last pass came to, for the status line and the panel's reading.
local stripped, dressed = 0, 0

-- Combat stopped part of the work, so Core/Menu.lua comes back at
-- PLAYER_REGEN_ENABLED for the rest.
local pending = false

--------------------------------------------------------------------------
-- Reading a frame the addon does not own
--------------------------------------------------------------------------

-- pcall guarded on the same terms ns.Measure is, and lifted from
-- Artwork/Artwork.lua, which asks the same question of the action bars: a
-- frame the addon did not build may refuse a call that looks harmless, and a
-- screenful of errors is worse than a piece of art that stayed visible.
local function Listed(target, method)
	if not target or type(target[method]) ~= "function" then
		return {}
	end
	local ok, list = pcall(function(subject)
		return { subject[method](subject) }
	end, target)
	if not ok or not list then
		return {}
	end
	return list
end

local function Regions(target)
	return Listed(target, "GetRegions")
end

local function Children(target)
	return Listed(target, "GetChildren")
end

-- Everything this file draws is marked, because it draws onto frames it then
-- walks again. Our fill on one of Blizzard's buttons is a texture of that
-- button, so the next pass would find our own paint among theirs and strip it.
local function Mine(region)
	region.wkOurs = true
	return region
end

local function Reveal(region, on)
	if on then
		region:Show()
	else
		region:Hide()
	end
end

--------------------------------------------------------------------------
-- One string of somebody else's
--------------------------------------------------------------------------

-- What a font string was wearing before we dressed it, so the switch can put
-- it back. A string on a font object needs the object; a string carrying its
-- own font needs the three values SetFont took. Both shapes turn up on this
-- menu, and which one a given client uses is not worth finding out when
-- keeping either costs the same.
local function Keep(text)
	if text.wkKept then
		return
	end
	text.wkKept = true
	text.wkFont = text:GetFontObject()
	if not text.wkFont then
		text.wkPath, text.wkSize, text.wkFlags = text:GetFont()
	end
	text.wkR, text.wkG, text.wkB, text.wkA = text:GetTextColor()
end

-- A button's label in the kit's face, and dimmed when the button is not
-- something you can press. Blizzard says that with its own disabled font,
-- which this has just taken off, so a client that greys Macros in combat would
-- otherwise draw it exactly like every button that still works.
local function Restyle(text, enabled)
	Keep(text)
	text:SetFontObject(UI.Font(M.font, UI.FLAT))
	local tone = enabled and C.text or C.quiet
	text:SetTextColor(tone[1], tone[2], tone[3])
end

local function Restore(text)
	if not text.wkKept then
		return
	end
	if text.wkFont then
		text:SetFontObject(text.wkFont)
	elseif text.wkPath then
		text:SetFont(text.wkPath, text.wkSize, text.wkFlags)
	end
	text:SetTextColor(text.wkR, text.wkG, text.wkB, text.wkA)
	text.wkKept = nil
end

--------------------------------------------------------------------------
-- One button of somebody else's
--------------------------------------------------------------------------

-- Hover, hooked rather than set, so whatever the client's own button already
-- did on the way in and out still happens. Both guard on the flag rather than
-- on the texture, because a hook cannot be taken off again: after the switch
-- goes off these still run, and what they must do then is nothing.
local function Lit(entry)
	if entry.wkOn then
		UI.Tint(entry.wkPaint, C.hover)
	end
end

local function Dim(entry)
	if entry.wkOn then
		UI.Tint(entry.wkPaint, C.control)
	end
end

local function Dress(entry)
	entry.wkPaint = Mine(ns.Fill(entry, "BACKGROUND",
		C.control[1], C.control[2], C.control[3], 1))
	entry.wkPaint:SetAllPoints()
	entry.wkEdges = ns.Outline(entry, C.edge[1], C.edge[2], C.edge[3], 1)
	for index = 1, 4 do
		Mine(entry.wkEdges[index])
	end
	ns.EdgeSize(entry.wkEdges, ns.Pixel(entry))
	entry:HookScript("OnEnter", Lit)
	entry:HookScript("OnLeave", Dim)
end

local function Paint(entry)
	local complete = true
	local enabled = ns.Measure(entry, "IsEnabled") ~= false
	-- A region of ours reads as nothing at all, because the fill and the four
	-- edges below are textures of this button and the next pass would find
	-- them among Blizzard's and strip the paint it had just put on.
	for _, region in ipairs(Regions(entry)) do
		local kind = not region.wkOurs and ns.Measure(region, "GetObjectType") or nil
		if kind == "Texture" then
			complete = ns.Strip(region) and complete
			stripped = stripped + 1
		elseif kind == "FontString" then
			Restyle(region, enabled)
		end
	end

	if not entry.wkPaint then
		Dress(entry)
	end
	entry.wkOn = true
	Reveal(entry.wkPaint, true)
	UI.Tint(entry.wkPaint, C.control)
	for index = 1, 4 do
		Reveal(entry.wkEdges[index], true)
	end
	dressed = dressed + 1
	return complete
end

local function Bare(entry)
	local complete = true
	for _, region in ipairs(Regions(entry)) do
		local kind = not region.wkOurs and ns.Measure(region, "GetObjectType") or nil
		if kind == "Texture" then
			complete = ns.Unstrip(region) and complete
		elseif kind == "FontString" then
			Restore(region)
		end
	end

	entry.wkOn = false
	if entry.wkPaint then
		Reveal(entry.wkPaint, false)
		for index = 1, 4 do
			Reveal(entry.wkEdges[index], false)
		end
	end
	return complete
end

--------------------------------------------------------------------------
-- The frame itself
--------------------------------------------------------------------------

-- One region of the menu's own chrome. A texture is Blizzard's art and goes. A
-- font string is the menu's heading and goes too, after its words have been
-- kept, because the bar below redraws that line in the kit's own face and two
-- headings in one place is worse than either.
local function Cover(region)
	local kind = ns.Measure(region, "GetObjectType")
	if region.wkOurs or (kind ~= "Texture" and kind ~= "FontString") then
		return true
	end
	if kind == "FontString" and not heading then
		heading = ns.Measure(region, "GetText")
	end
	if not ns.Strip(region) then
		return false
	end
	stripped = stripped + 1
	return true
end

local function Uncover(region)
	if region.wkOurs then
		return true
	end
	return ns.Unstrip(region)
end

-- The kit's panel, drawn on the menu's own regions rather than on a frame of
-- ours. A frame would need a level, and a level put below Blizzard's buttons
-- on one client is a level put over them on the next; a parent's own texture
-- is under every child frame it has by construction, on every client, with
-- nothing to work out.
local function Panel()
	if paint then
		return
	end
	local px = ns.Pixel(frame)
	paint = {}
	paint.bg = Mine(ns.Fill(frame, "BACKGROUND",
		C.window[1], C.window[2], C.window[3], C.window[4]))
	paint.bg:SetAllPoints()
	paint.edges = ns.Outline(frame, C.edge[1], C.edge[2], C.edge[3], 1)
	for index = 1, 4 do
		Mine(paint.edges[index])
	end
	ns.EdgeSize(paint.edges, px)

	paint.bar = Mine(ns.Fill(frame, "BORDER",
		C.chrome[1], C.chrome[2], C.chrome[3], 1))
	paint.bar:SetPoint("TOPLEFT", px, -px)
	paint.bar:SetPoint("TOPRIGHT", -px, -px)
	paint.bar:SetHeight(M.title)

	paint.title = Mine(UI.Label(frame, M.heading, C.heading, "LEFT", UI.FLAT))
	paint.title:SetPoint("TOPLEFT", M.pad, -math.floor((M.title - M.heading) / 2) - px)
end

-- Whether the top of the menu is empty enough to put a title bar in.
--
-- The bar is our chrome drawn over a frame we did not build, so the one thing
-- it must not do is land on a button. Every flavour of this menu has left room
-- above the first button for a heading of its own, and that is a habit rather
-- than a promise: the honest answer where the room is not there is no bar.
local function Room(buttons)
	local top = ns.Measure(frame, "GetTop")
	if not top then
		return false
	end
	for _, entry in ipairs(buttons) do
		local theirs = ns.Measure(entry, "GetTop")
		if theirs and top - theirs < M.title + CLEAR then
			return false
		end
	end
	return true
end

local function Headed(buttons)
	local room = Room(buttons)
	paint.title:SetText(heading or UNTITLED)
	Reveal(paint.bar, room)
	Reveal(paint.title, room)
	return room
end

local function Hidden()
	if not paint then
		return
	end
	Reveal(paint.bg, false)
	Reveal(paint.bar, false)
	Reveal(paint.title, false)
	for index = 1, 4 do
		Reveal(paint.edges[index], false)
	end
end

--------------------------------------------------------------------------
-- The pass
--------------------------------------------------------------------------

-- Every button in the menu, and every frame in it that is not one. Our own
-- button is in neither list: it is already the kit's, and a second coat would
-- strip the first.
local function Gather(target, depth, buttons, holders)
	for _, child in ipairs(Children(target)) do
		local kind = child ~= own and ns.Measure(child, "GetObjectType") or nil
		if kind == "Button" then
			buttons[#buttons + 1] = child
		elseif kind and depth > 0 then
			holders[#holders + 1] = child
			Gather(child, depth - 1, buttons, holders)
		elseif kind then
			holders[#holders + 1] = child
		end
	end
end

-- One pass over the whole menu: the frame's own regions, the regions of every
-- box inside it, and then every button. Two callers hand it opposite pairs,
-- which is the only difference between painting the menu and putting it back.
local function Walk(buttons, holders, onRegion, onButton)
	local complete = true
	for _, region in ipairs(Regions(frame)) do
		complete = onRegion(region) and complete
	end
	for _, holder in ipairs(holders) do
		for _, region in ipairs(Regions(holder)) do
			complete = onRegion(region) and complete
		end
	end
	for _, entry in ipairs(buttons) do
		complete = onButton(entry) and complete
	end
	return complete
end

-- The menu drawn our way, or put back the way the client draws it. Run at
-- login and again on every show, because that is when Core/Menu.lua places its
-- own button, and everything here is idempotent so a pass that changes nothing
-- writes nothing.
function Skin.Apply()
	if not frame or not ns.db then
		return true
	end

	local buttons, holders = {}, {}
	Gather(frame, DEPTH, buttons, holders)

	local complete
	if ns.db.menuSkin == false then
		stripped, dressed = 0, 0
		complete = Walk(buttons, holders, Uncover, Bare)
		Hidden()
	else
		Panel()
		stripped, dressed = 0, 0
		complete = Walk(buttons, holders, Cover, Paint)
		Reveal(paint.bg, true)
		for index = 1, 4 do
			Reveal(paint.edges[index], true)
		end
		Headed(buttons)
	end

	pending = not complete
	return complete
end

-- Which menu, and which button in it is ours. Called by Core/Menu.lua once its
-- button exists, because that file owns the button and this one owns the paint
-- and neither goes looking for the other's.
function Skin.Watch(menu, ours)
	frame, own = menu, ours
end

function Skin.Deferred()
	return pending
end

function Skin.Describe()
	if not frame then
		return "no game menu to paint"
	end
	if ns.db and ns.db.menuSkin == false then
		return "the client's own look"
	end
	if dressed == 0 then
		return "nothing painted yet"
	end
	if pending then
		return ("%d buttons and %d regions, the rest follows when combat drops")
			:format(dressed, stripped)
	end
	return ("%d buttons painted, %d of the client's regions off"):format(dressed, stripped)
end
