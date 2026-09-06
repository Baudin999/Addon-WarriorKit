local ADDON, ns = ...

local Bars = {}
ns.AdHocBars = Bars

local UI = ns.UI
local Ability = ns.UI.Ability
local Flow = ns.UI.Flow
local C = ns.UI.Color

--------------------------------------------------------------------------
-- The bar on the screen, and the key that puts it there
--
-- Three protected things per bar, and a snippet stands between the player and
-- each of them, because every one is refused to an addon in a fight and a bar
-- of totems is pressed in one.
--
--   Showing it. A frame with a secure button inside it may not be shown or
--   hidden by an addon under lockdown. The key is bound to a button built on
--   SecureHandlerClickTemplate, and the button's own snippet is what shows or
--   hides the bar: the same shape Character/Window.lua uses for the C key on a
--   sheet with nineteen secure squares on it. The key is held rather than
--   pressed. The down edge shows the bar and the up edge puts it away, which is
--   how every ring addon on this client reads a key, and it is why the button
--   takes both edges instead of toggling on one.
--
--   Hiding it after a press. A press on a square casts the spell, and the bar
--   is meant to go away again the way an OPie ring does. The button's OnClick
--   is wrapped, and the snippet that runs after the cast hides the bar the
--   button sits on. WrapScript is what OPie does to every ring proxy on this
--   client, so it is proven here in the way Blizzard parity asks for.
--
--   Moving it. The restricted environment has no StartMoving, so a secure
--   frame is placed by a point handed to a snippet; UI/Placeable.lua owns that
--   drag and the character sheet is its first caller. A bar is its second, and
--   the drag is taken by a grip along the bar's left edge rather than by the
--   bar, because the bar is squares from edge to edge and a drag started on a
--   square is a drag of what the square holds.
--
-- Everything else about a square is UI/Ability.lua's and Buttons/Castable.lua's:
-- the picture, the swipe, the colour of the edge, the ladder that decides it.
-- Nothing here reads an action slot, because nothing here has one.
--
-- The frames are made on first use and never destroyed, because a secure frame
-- cannot be. A bar you delete keeps its frame and the next bar you add takes
-- it, so the pool never grows past the cap, and every attribute on it is
-- written again from the list on every Apply, which is what makes a deleted
-- bar's key land on the right frame.
--------------------------------------------------------------------------

local MAX = ns.AdHoc.MAX
local PER_BAR = ns.AdHoc.PER_BAR

-- The two the state driver argument in Buttons/Bars.lua already fixed:
-- two units between squares, and four round the lot rather than three, because
-- this bar carries a grip along one edge and a frame padded evenly on all four
-- is what stops that edge reading as a mistake.
local GAP, PAD = 2, 4

-- 27, the sharp size, for the reason Buttons/Look.lua gives at length: it is
-- the one drawn size where a stored texel lands on a pixel. The zoom is how you
-- make a bar bigger, and it scales the whole frame rather than resampling the
-- art inside it, which is why the default zoom in AdHoc/Feature.lua is not 1:
-- a bar you hold a key to read wants a square you can read at a glance, and
-- scaling the frame is the only way to get one that keeps the art sharp.
local SIZE = 27

-- The grip along the left edge, in units. Wide enough to land a cursor on and
-- no wider, because it is on the screen only while the bar is. It is painted
-- in the rail colour, a shade off the background, and only lifts to the edge
-- colour under the cursor: a solid chrome slab down the side of a row of icons
-- reads as a piece of the bar rather than a handle for it.
local GRIP = 5

-- 120, the same depth Buttons/Placing.lua stands the cloned bars at, and for
-- its reason: Blizzard's MainActionBar takes the mouse at level 50 across the
-- bottom of the screen, and a bar that lands under it loses every click.
local LEVEL = 120

-- Where a bar goes the first time it is shown. Below the middle of the screen,
-- because a bar you press a key for is one you are looking at, and the middle
-- is where your character stands.
local DEFAULT_POINT = { "CENTER", "UIParent", "CENTER", 0, -160 }

local entries = {}
local pending = false

local function FrameName(index)
	return ("WarriorKitAdHoc%d"):format(index)
end

local function KeyName(index)
	return ("WarriorKitAdHoc%dKey"):format(index)
end

local function ButtonName(index, at)
	return ("WarriorKitAdHoc%dButton%d"):format(index, at)
end

Bars.KeyName = KeyName
Bars.ButtonName = ButtonName

--------------------------------------------------------------------------
-- The snippets
--------------------------------------------------------------------------

-- What the key runs, on both edges of the press. The bar is handed over as a
-- frame reference because a snippet may only touch what it has been given.
--
-- `down` is the third argument the click handler is given, and it is what makes
-- this a hold rather than a toggle: a toggle on the down edge alone needs a
-- second press to put the bar away, and a bar of totems is opened in a fight
-- with a thumb that is already going somewhere else.
--
-- The nil arm is not dead code. Nothing installed on this box hands a snippet
-- that third argument, so it is the client's word and not a proven call, and a
-- client that hands over nothing would otherwise leave the key showing a bar
-- that never goes away. On that client the key is the toggle it used to be,
-- which is worse than a hold and better than a bar you cannot dismiss.
local HOLD = [[
	local bar = self:GetFrameRef("bar")
	if down == nil then
		if bar:IsShown() then bar:Hide() else bar:Show() end
	elseif down then
		bar:Show()
	else
		bar:Hide()
	end
]]

-- What runs after a press on a square, once the client has cast whatever the
-- square held. The bar decides whether it goes away, and says so in an
-- attribute because a snippet cannot read a saved variable.
local CLOSE = [[
	local bar = self:GetParent()
	if bar and bar:GetAttribute("wk-close") then
		bar:Hide()
	end
]]

--------------------------------------------------------------------------
-- Building one
--------------------------------------------------------------------------

-- The item cooldown call, resolved once. Two names across the clients this
-- runs on, and neither is proven by anything installed, so a client with
-- neither draws an item with no swipe rather than an error a tick.
local ItemCooldown = (C_Container and C_Container.GetItemCooldown) or _G.GetItemCooldown

-- What a square says to a hover. A note rather than the client's own spell
-- text, because the name is the whole of what you need to read off a bar you
-- designed yourself, and the sentence under it is the one thing a square on
-- this bar does that a square on any other does not.
local function Says(w)
	local record = w.record
	if not record then
		return { kind = "note", title = "an empty square",
			lines = { "Drag a spell, an item or a macro here." } }
	end
	local closes = ns.AdHoc.Closes(w.bar)
	return { kind = "note", title = record.name,
		lines = { closes and "A press uses it and puts the bar away."
			or "A press uses it. The bar stays up until you let the key go.",
			"Drop something else on it to replace it." } }
end

-- A drop on a square, off the bar itself. OnReceiveDrag and PostClick both,
-- for the reason Buttons/Square.lua registers both: a spell let go over a
-- square arrives as a drag, and one clicked onto it arrives as a click. Neither
-- is protected, which is why a secure button takes them in plain Lua.
local function Drop(w)
	if type(GetCursorInfo) ~= "function" then
		return
	end
	local kind, a, b, c = GetCursorInfo()
	if not kind then
		return
	end
	local record, why = ns.AdHoc.Carry(kind, a, b, c)
	if not record then
		if why then
			ns.Print(why)
		end
		return
	end
	local ok, refused = ns.AdHoc.Put(w.bar, w.at, record)
	if not ok then
		ns.Print(refused)
		return
	end
	ClearCursor()
end

local function Handle(w)
	ns.Tip.Hang(w, Says)
	w:SetScript("OnReceiveDrag", Drop)
	w:SetScript("PostClick", Drop)
end

local function Build(index)
	-- The attribute template rather than a plain frame, because the drag a
	-- secure frame gets is a point written into an attribute and a snippet on
	-- this template is what places it. UI/Placeable.lua says why.
	local frame = CreateFrame("Frame", FrameName(index), UIParent, "SecureHandlerAttributeTemplate")
	frame.bg = ns.Fill(frame, "BACKGROUND", C.window[1], C.window[2], C.window[3], C.window[4] or 1)
	frame.bg:SetAllPoints()
	frame.edges = ns.Outline(frame, C.hairline[1], C.hairline[2], C.hairline[3], C.hairline[4] or 1)
	ns.EdgeSize(frame.edges, ns.Pixel(frame))
	UI.Adopt(frame, ns.db.adhocZoom)
	frame:SetFrameStrata("MEDIUM")
	frame:SetFrameLevel(LEVEL)
	frame:Hide()

	local entry = { index = index, frame = frame, buttons = {}, count = 0 }
	entries[index] = entry

	-- The grip, which is the one part of the bar that answers a drag.
	local grip = ns.Fill(frame, "ARTWORK", C.rail[1], C.rail[2], C.rail[3], 1)
	local px = ns.Pixel(frame)
	grip:SetPoint("TOPLEFT", px, -px)
	grip:SetPoint("BOTTOMLEFT", px, px)
	grip:SetWidth(GRIP)
	entry.grip = grip
	local handle = CreateFrame("Frame", nil, frame)
	handle:SetAllPoints(grip)
	handle:SetFrameLevel(LEVEL + 2)
	handle:EnableMouse(true)
	-- Painted directly rather than through ns.Recolor, which takes the four
	-- textures of an outline. This is one texture.
	handle:SetScript("OnEnter", function()
		grip:SetColorTexture(C.edge[1], C.edge[2], C.edge[3], 1)
	end)
	handle:SetScript("OnLeave", function()
		grip:SetColorTexture(C.rail[1], C.rail[2], C.rail[3], 1)
	end)
	entry.handle = handle

	entry.place = UI.Placeable(frame, {
		secure = true,
		lockable = false,
		grip = handle,
		moved = function(anchor)
			local bar = ns.AdHoc.Get(index)
			if bar then
				bar.point = anchor
			end
		end,
	})

	for at = 1, PER_BAR do
		local w = Ability.New(frame, ButtonName(index, at), "SecureActionButtonTemplate", Ability.QUIET)
		w.bar, w.at = index, at
		-- The up edge, and the attribute agreeing with it, for the reason
		-- Buttons/Bars.lua writes both: a square you drop a spell onto must not
		-- cast on the press that starts the drag, and a button whose two edges
		-- disagree is a button that goes dark under the key and does nothing.
		w:RegisterForClicks("AnyUp")
		w:SetAttribute("useOnKeyDown", false)
		if type(frame.WrapScript) == "function" then
			frame:WrapScript(w, "OnClick", "", CLOSE)
			entry.closes = true
		end
		Handle(w)
		entry.buttons[at] = w
	end

	-- The key. Registered on both edges, because both are the point: the down
	-- edge puts the bar up and the up edge takes it away, and the snippet tells
	-- them apart by the argument the handler is given rather than by counting
	-- presses.
	local key = CreateFrame("Button", KeyName(index), UIParent, "SecureHandlerClickTemplate")
	key:RegisterForClicks("AnyDown", "AnyUp")
	key:SetFrameRef("bar", frame)
	key:SetAttribute("_onclick", HOLD)
	entry.key = key

	return entry
end

--------------------------------------------------------------------------
-- Applying the list
--------------------------------------------------------------------------

-- What a press on each square does. A spell by name, an item through /use for
-- the reason Hover/Hover.lua casts one that way, a macro by name. A square
-- past the end of the list is left with no type, so a stray press does nothing
-- rather than whatever the square held last.
local function Arm(entry, bar)
	local buttons = bar.buttons
	for at = 1, PER_BAR do
		local w = entry.buttons[at]
		local record = buttons[at]
		w.record = record
		w:SetAttribute("type", nil)
		w:SetAttribute("spell", nil)
		w:SetAttribute("macro", nil)
		w:SetAttribute("macrotext", nil)
		if record and record.kind == "spell" then
			w:SetAttribute("type", "spell")
			w:SetAttribute("spell", record.name)
		elseif record and record.kind == "item" then
			w:SetAttribute("type", "macro")
			w:SetAttribute("macrotext", "/use " .. record.name)
		elseif record and record.kind == "macro" then
			w:SetAttribute("type", "macro")
			w:SetAttribute("macro", record.name)
		end
	end
	-- One empty square on a bar with nothing on it, so a bar you just made and
	-- pressed the key for is a square saying drop something here rather than
	-- a sliver of background.
	entry.count = math.max(1, #buttons)
end

-- The squares in rows, and the frame sized round them with the grip on the
-- left. The rows are written out rather than left to Flow's wrap, for the
-- reason Buttons/Bars.lua writes its own: wrapping needs a width to wrap
-- against and a width here would be the same arithmetic stated twice.
local function Arrange(entry, bar)
	UI.Adopt(entry.frame, ns.db.adhocZoom)
	local columns = ns.AdHoc.Columns(entry.index)
	local rows = { direction = "column", gap = GAP, pad = { PAD + GRIP, PAD, PAD, PAD } }
	local row

	for at = 1, PER_BAR do
		local w = entry.buttons[at]
		if at <= entry.count then
			if (at - 1) % columns == 0 then
				row = { direction = "row", gap = GAP }
				rows[#rows + 1] = row
			end
			Ability.Size(w, SIZE)
			row[#row + 1] = { frame = w, width = SIZE, height = SIZE }
			w:Show()
		else
			w:Hide()
		end
	end

	Flow.Arrange(entry.frame, rows)
	entry.place:Place(bar.point or DEFAULT_POINT)
end

-- Everything protected in one function. Attributes, anchors and override
-- bindings are all refused under lockdown, so in combat this sets pending and
-- PLAYER_REGEN_ENABLED runs it for real.
--
-- Every frame is rewritten from the list every time rather than the one that
-- changed, because deleting a bar shifts every bar under it onto a different
-- frame and a partial pass would leave a key on the wrong one.
function Bars.Apply()
	if InCombatLockdown() then
		pending = true
		return false
	end
	pending = false

	local list = ns.AdHoc.All()
	local on = ns.db.adhoc
	for index = 1, MAX do
		local bar = on and list[index] or nil
		local entry = entries[index]
		if bar and not entry then
			entry = Build(index)
		end
		if entry then
			ClearOverrideBindings(entry.key)
			if bar then
				Arm(entry, bar)
				Arrange(entry, bar)
				entry.frame:SetAttribute("wk-close", ns.AdHoc.Closes(index))
				if bar.key ~= "" then
					SetOverrideBindingClick(entry.key, true, bar.key, KeyName(index), "LeftButton")
				end
			else
				entry.frame:Hide()
			end
		end
	end
	return true
end

-- Put every bar back where it started. The anchor is dropped rather than
-- written, because a bar with no anchor of its own sits at the default and a
-- saved variable that restates it is one that can drift from it.
function Bars.Reset()
	for _, bar in ipairs(ns.AdHoc.All()) do
		bar.point = nil
	end
	Bars.Apply()
end

--------------------------------------------------------------------------
-- The key
--------------------------------------------------------------------------

-- Reads the override layer back rather than reporting what this file meant to
-- set. A client that takes the call and does nothing with it leaves no other
-- trace. Nil means the question could not be asked.
local function Holds(index, key)
	if type(GetBindingAction) ~= "function" then
		return nil
	end
	local ok, action = pcall(GetBindingAction, key, true)
	if not ok or type(action) ~= "string" then
		return nil
	end
	return action == ("CLICK %s:LeftButton"):format(KeyName(index))
end

-- Returns the binding the key was carrying, "" when it carried none, or nil
-- plus a reason when the key cannot be taken. The displaced action is read
-- with our own override dropped, so it reports the real binding rather than
-- the click binding this file left there last time.
function Bars.Bind(index, key)
	local bar = ns.AdHoc.Get(index)
	if not bar then
		return nil, "no such bar."
	end
	if InCombatLockdown() then
		return nil, "keys cannot be rebound in combat."
	end

	key = key or ""
	if ns.AdHoc.BARE[key] then
		return nil, ("%s belongs to targeting and the camera. Hold a modifier."):format(key)
	end
	if key ~= "" then
		for other, each in ipairs(ns.AdHoc.All()) do
			if other ~= index and each.key == key then
				return nil, ("%s already opens %s."):format(key, each.name)
			end
		end
	end

	bar.key = ""
	Bars.Apply()

	local displaced = key ~= "" and GetBindingAction(key) or ""
	bar.key = key
	bar.displaced = displaced
	Bars.Apply()

	if key ~= "" and Holds(index, key) == false then
		return nil, ("this client would not take %s."):format(key)
	end
	return displaced
end

function Bars.Describe(index)
	local bar = ns.AdHoc.Get(index)
	if not bar then
		return "unknown"
	end
	if bar.key == "" then
		return "unbound"
	end
	if not ns.db.adhoc then
		return bar.key .. " (the bars are off, so the key is not held)"
	end
	if Holds(index, bar.key) == false then
		return bar.key .. " (the client did not take it)"
	end
	return bar.key
end

-- Whether that bar is on the screen right now, or nil for one not built.
function Bars.Visible(index)
	local entry = entries[index]
	if not entry then
		return nil
	end
	return entry.frame:IsShown() and true or false
end

-- Whether the client gave this bar the wrap that hides it after a press.
function Bars.CanClose(index)
	local entry = entries[index]
	return entry ~= nil and entry.closes == true
end

function Bars.Pending()
	return pending
end

-- The entry, for the harness. Nothing in the addon reads it.
function Bars.Entry(index)
	return entries[index]
end

--------------------------------------------------------------------------
-- The tick
--
-- Only the bars on the screen are drawn, and most of the time that is none of
-- them, so the pass is a walk over six entries and back. A bar that is up is
-- drawn ten times a second, the rate the cloned bars draw range and count at.
--------------------------------------------------------------------------

local function Draw(entry)
	for at = 1, entry.count do
		local w = entry.buttons[at]
		local record = w.record
		if not record then
			Ability.Draw(w, nil, "empty")
		elseif record.kind == "spell" then
			local status, start, duration = ns.Castable.State(record.name)
			Ability.Draw(w, record.icon, status, start, duration)
		elseif record.kind == "item" then
			local count = ns.ItemCount(record.name)
			local start, duration
			if record.id and ItemCooldown then
				start, duration = ItemCooldown(record.id)
			end
			Ability.Draw(w, record.icon, count > 0 and "ready" or "unknown", start, duration, count)
		else
			Ability.Draw(w, record.icon, "ready")
		end
	end
end

function Bars.Update()
	for index = 1, MAX do
		local entry = entries[index]
		if entry and entry.frame:IsShown() then
			Draw(entry)
		end
	end
end

UI.Ticker(UI.Forever, 0.1, "adhoc", Bars.Update)

--------------------------------------------------------------------------
-- Events
--
-- PLAYER_LOGIN rather than ADDON_LOADED, because the binding set the overrides
-- land on top of is not built until then. PLAYER_REGEN_ENABLED picks up
-- anything a fight refused.
--------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_REGEN_ENABLED" and not pending then
		return
	end
	Bars.Apply()
end)

-- And again every time the client rebuilds its binding set, which throws every
-- override away, including the one taken at PLAYER_LOGIN a moment earlier. See
-- ns.Rebind in Core/Core.lua.
ns.Rebind(Bars.Apply)

-- A resolution change moves every size at once, the same way it moves the
-- cooldown row.
UI.OnRescale(Bars.Apply)
