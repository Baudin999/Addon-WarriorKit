local ADDON, ns = ...

local Window = {}
ns.CharWindow = Window

local UI = ns.UI
local C, M = UI.Color, UI.Metric

--------------------------------------------------------------------------
-- The character window
--
-- Four tabs over one window: what you are wearing and what it adds up to, what
-- you are skilled at, who likes you, and the weapon sets you have put on keys.
--
-- **It replaces the client's sheet rather than sitting beside it.** The client
-- draws three of these four and draws them as three separate windows wearing one
-- frame, with a picture of your back taking the largest area of the first one
-- and the number everybody actually wants, how often you miss, on none of them.
-- Blizzard.lua puts that frame in the attic and takes the C key, behind the one
-- switch on the page where every other Blizzard frame this addon replaces is
-- switched.
--
-- **The stats are not a tab.** They were, and a tab was the wrong shape for
-- them: what a stat answers is what the piece you just put on did, and a number
-- you have to change page to read is a number you read once a week. So the
-- readout is a column down the right of the gear page, next to the squares that
-- move it. Character/Paperdoll.lua hosts it, Character/Readout.lua still draws
-- it, and this window is one tab narrower and one window wider for it.
--
-- **The last tab is the loadouts.** They were a section of the options window,
-- which is where you go to change how opaque the chat window is. A loadout is a
-- pair of weapons on a key, so it belongs where your weapons are. The page
-- itself did not change: Loadouts/Page.lua hands the same rows to the same
-- widget kit, and this window is the host instead of the options window. That
-- is the whole of what the kit's host contract was written for.
--
-- **One pane is painted at a time.** A font string on a hidden frame will not
-- say how tall it wraps to on this client, so a tab painted while another one
-- was up would lay its prose out one line high and keep that height when you
-- opened it. Selecting a tab shows it and then paints it, in that order.
--
-- **This window opens in a fight, and everything below that says `secure` or
-- `InCombatLockdown` is there for that one sentence.** The gear page carries
-- nineteen secure buttons because using what is in a slot is protected, a frame
-- built from a secure template is protected, and every protected thing an addon
-- does in combat is refused: showing this window, hiding it, moving it, sizing
-- it, taking its gear page down to put another tab up. Blizzard's own sheet does
-- all of that in a fight because Blizzard's code is allowed to.
--
-- An addon is allowed to borrow the permission one way, which is to have the
-- press run a snippet. So there are three answers here and no fourth. The key
-- is bound to a secure button whose snippet shows and hides the window, and the
-- cross on the title bar is the same button in the corner. The gear page is
-- never hidden, and the other three tabs are drawn over it. Everything that
-- would have to move a protected frame, the layout and the zoom, waits for
-- PLAYER_REGEN_ENABLED. The Lua way in still exists and still refuses in a
-- fight, and says which key does work.
--
-- **Nothing here is on a ticker.** Your gear changes when the server says it
-- did, which is six events, and every one of them ends in a repaint of the tab
-- that happens to be up. A window nobody has open is not repainted at all, and
-- neither is one nobody has opened yet: Window.Paint refuses while the window
-- is down and the window's own OnShow is what pays the first one.
--
-- **The frames are built at login and that is deliberate.** Every other window
-- in the addon waits for the first open. This one cannot: the key press runs a
-- snippet, a snippet may only touch a frame it has been handed a reference to,
-- and neither the window nor the reference can be made in a fight. A sheet
-- built on first press would be a C key that does nothing the first time it is
-- pressed in a pull. What login no longer pays for is the two paints and the
-- model, which is where nearly all of the cost was.
--------------------------------------------------------------------------

-- There are no two numbers here any more.
--
-- This was 860 by 520, arrived at by adding up a padding, two columns of rows,
-- the gap the figure stood in, a gutter and the narrowest column the stats
-- would draw into. Every one of those additions was an argument about how
-- little the page could be given and still work, and the page it produced was a
-- character standing in a box the size of a dialog with his gear listed round
-- the edges. The sheet this is drawn against is not a dialog. It is the screen,
-- with the figure standing in it and the gear read off the world either side.
--
-- So the size is the monitor and `screen` in UI/Window.lua is what makes it so.
-- The zoom is still the player's and still means what it always meant: turn it
-- up and the type and the discs get bigger while the sheet still covers the
-- screen, because the units it is laid out in shrink by the same factor.
-- Character/Paperdoll.lua takes whatever width comes out and gives the figure
-- everything the three columns of text do not want.
--
-- The other three tabs are the exception, and PAGE is how wide they get. They
-- are lists of prose on a ground of their own, and prose is read at a column's
-- width however much room there is: a weapon skill with its sentence under it
-- laid across an ultrawide is a line your eye loses on the way back. It is the
-- old window's content width, which is what those three were always drawn at
-- and the only number from it worth keeping.
local PAGE = 836

-- The four, in the order they are drawn. `fill` is what the tab's pane is
-- handed on a repaint, and the two that have none are the two that are not
-- readouts: the gear page draws itself, stats and all, and the loadout page is a
-- widget kit.
local TABS = {
	{ label = "gear" },
	{ label = "skills", fill = function() return ns.CharSkills.Groups() end },
	{ label = "reputation", fill = function() return ns.CharRep.Groups() end },
	{ label = "loadouts" },
}

local GEAR, SKILLS, REPUTATION, LOADOUTS = 1, 2, 3, 4

local window, tabs, footer, key
local panes = {}
local showing = GEAR
local pending = false

--------------------------------------------------------------------------
-- The loadout tab
--
-- A stack in a scroll view, a kit over the stack, and the page drawn into it.
-- Everything the options window does for a section, in eleven lines, which is
-- what makes the kit worth having rather than a settings window's private
-- helper.
--------------------------------------------------------------------------

local function Loadouts(parent)
	local pane = {}
	pane.frame = CreateFrame("Frame", nil, parent)
	pane.view = UI.ScrollView(pane.frame)
	pane.view.frame:SetPoint("TOPLEFT")
	pane.stack = UI.Stack(pane.view.canvas, 1)

	pane.host = {
		stack = pane.stack,
		-- A dropdown has to sit over the window rather than inside the pane it
		-- was opened from, or it is clipped by the viewport the moment the list
		-- is longer than the room under the control.
		Popup = function() return window and window.frame or UIParent end,
	}
	pane.host.Refresh = function()
		pane.kit.Refresh()
		pane.Reflow()
	end

	function pane.Reflow()
		if not pane.frame:IsShown() then
			return 0
		end
		pane.stack:SetWidth(pane.view.width or 1)
		local height = pane.stack:Reflow()
		pane.view:Update(height)
		return height
	end

	pane.kit = UI.Kit(pane.host)
	ns.LoadoutPage.Build(pane.kit)
	return pane
end

--------------------------------------------------------------------------

-- Which page is on top.
--
-- The gear pane is never hidden and the other three are drawn over it. That is
-- not a layout preference, it is what lets a tab be pressed in a fight: the gear
-- pane holds nineteen secure buttons, hiding a frame with a protected one inside
-- it is itself a protected act, and an addon may not do one of those in combat.
-- Three ordinary frames going up and down over it is ordinary Lua and holds in a
-- fight like anything else here.
--
-- The three that cover it are opaque and take the mouse, so nothing shows
-- through and no click falls past them onto a gear square. Build sets that up
-- once; this is only the switch.
local function Select(index)
	showing = index
	for slot = 1, #TABS do
		if slot ~= GEAR then
			panes[slot].frame:SetShown(slot == index)
		end
	end
	return Window.Paint()
end

local function Chrome()
	-- The rim rather than the flat face, because this line is printed along the
	-- bottom of the screen over whatever the player is standing on.
	footer = UI.Label(window.footer, M.small, C.dim, "LEFT", UI.SHADOW)
	UI.Wrap(footer, false)
	footer:SetPoint("LEFT")
end

-- Refused in a fight, and put right when it drops.
--
-- Sizing the gear pane sizes the frame nineteen secure buttons hang off, which
-- is the same protected act as showing it. Nothing here is urgent: a sheet laid
-- out for the old screen is a sheet with a wide margin until the fight ends,
-- and PLAYER_REGEN_ENABLED below runs the pass again.
--
-- The resize is what re-reads the monitor. A screen window is not asked how big
-- it wants to be, so this hands it the two numbers it will ignore and takes back
-- the ones it came out at, which is how a sheet built at one resolution still
-- covers the screen after a monitor swap or a drag of the zoom slider.
function Window.Fit()
	if not window then
		return false
	end
	if InCombatLockdown() then
		pending = true
		return false
	end
	window:Resize(window.width, window.height)
	local width = window.width - M.pad * 2
	local body = window:Body() - M.pad * 2
	local under = body - (tabs:Resize(width) + M.gutter)

	for index = 1, #TABS do
		local pane = panes[index]
		-- The gear page is the sheet and takes the whole of it. The other three
		-- are lists of prose on an opaque ground, and a list of prose is read at
		-- a column's width whatever the monitor is: given the screen they would
		-- be twenty skills laid across an ultrawide on a panel that has painted
		-- the game out from edge to edge.
		local room = index == GEAR and width or math.min(width, PAGE)
		pane.frame:SetSize(room, under)
		if pane.Resize then
			pane:Resize(room, under)
		else
			pane.view:Resize(room, under)
		end
	end
	return true
end

function Window.Build()
	if window then
		return window
	end

	window = UI.Window({
		name = "WarriorKitCharacter",
		-- The size of the monitor, fixed to it, with no title bar, no line round
		-- the outside, no ground and no saved point, at the floor of the frame
		-- pile so every window the player opens flows over the top of it.
		-- UI/Window.lua carries the whole of what that means; what it means here
		-- is that no width and no height are passed, because neither would be
		-- read.
		--
		-- No title bar is no close box, and a window without one owes the player
		-- another way out. This one has two, and both were here before the cross
		-- was: Escape, through UISpecialFrames, and the key that opened it, which
		-- is C unless the player has moved it and is a snippet either way, so it
		-- shuts the sheet in a fight as well as out of one.
		screen = true,
		zoom = function() return ns.Zoom("characterZoom") end,
		-- The grid moved: the screen changed size, combat let go of a frame, or
		-- this sheet's own zoom was dragged. The rezoom is handed over rather
		-- than run for us because this is one of the two windows that does not
		-- always want it where it would fall. The grid moving in the middle of a
		-- fight is a sheet that keeps the zoom it had until the fight ends:
		-- scaling the frame the secure gear squares hang off is refused, and Fit
		-- is refused for the same reason.
		rescale = function(apply)
			if InCombatLockdown() then
				pending = true
				return
			end
			apply()
			Window.Fit()
			Window.Refresh()
		end,
		-- The gear squares are secure buttons, so everything the client refuses
		-- an addon in combat it refuses this window: the close box runs a snippet
		-- instead of Lua, and the window is not dragged in a fight. UI/Window.lua
		-- holds both halves of that.
		secure = true,
	})
	-- No ns.Remember, because there is nothing to remember. A sheet the size of
	-- the screen is already where it goes and cannot be dragged off it, so the
	-- only thing a saved point could do is put it somewhere wrong. Whatever an
	-- older version wrote against this name is dropped rather than left to rot in
	-- the account file behind a reader that no longer exists.
	ns.db.windowSpots["WarriorKitCharacter"] = nil

	-- The words rather than a strip of buttons. This sheet is a backdrop with
	-- the game showing through it, and a row of filled tabs across the top is the
	-- one thing left on the page that would still read as a dialog.
	tabs = UI.TabStrip(window.content, { onSelect = Select, bare = true })
	tabs.frame:SetPoint("TOPLEFT", M.pad, -M.pad)

	panes[GEAR] = ns.Paperdoll.New(window.content)
	panes[SKILLS] = ns.CharReadout.New(window.content)
	panes[REPUTATION] = ns.CharReadout.New(window.content)
	panes[LOADOUTS] = Loadouts(window.content)

	for index = 1, #TABS do
		local pane = panes[index].frame
		tabs:Add(TABS[index].label)
		pane:SetPoint("TOPLEFT", tabs.frame, "BOTTOMLEFT", 0, -M.gutter)
		if index == GEAR then
			pane:Show()
		else
			-- Over the gear page, opaque, and it eats the mouse. See Select for
			-- why the page underneath is never taken down instead.
			--
			-- The cover stays now that the sheet itself has no ground, and it is
			-- the one place on the sheet where a panel is the right answer. These
			-- three pages are lists of prose: a weapon skill with its sentence
			-- under it, a faction with a bar. The gear page has a figure and a
			-- disc for every line and reads against grass; a paragraph does not.
			pane:SetFrameLevel(window.content:GetFrameLevel() + 10)
			pane:EnableMouse(true)
			local cover = ns.Fill(pane, "BACKGROUND",
				C.window[1], C.window[2], C.window[3], C.window[4])
			cover:SetAllPoints()
			pane:Hide()
		end
	end

	-- Painted whenever the window comes up, by whatever route. In a fight the
	-- route is the snippet on the key, which runs no Lua of ours at all, so this
	-- is the only place a paint can be hung and still happen.
	window.frame:SetScript("OnShow", function()
		Window.Paint()
	end)

	Chrome()
	Window.Fit()
	tabs:Select(showing)
	return window
end

--------------------------------------------------------------------------

-- The tab that is up, and the line along the bottom. Nothing else, because
-- every other pane is behind this one and cannot be measured while it is.
--
-- And nothing at all while the window is shut. This is nineteen slots, every
-- stat, every skill or every faction depending on the tab, and it ran twice at
-- login on a window nobody had opened: once out of the fit and once out of the
-- tab strip choosing its first tab. The window's own OnShow is what pays for it
-- now, so the sheet is painted when it comes up and not before.
function Window.Paint()
	if not window or not window:IsShown() then
		return false
	end
	local tab = TABS[showing]
	local pane = panes[showing]

	if tab.fill then
		pane:Set(tab.fill())
	elseif pane.Reflow then
		pane.host.Refresh()
	else
		pane:Paint()
	end

	footer:SetText(("%s. %s."):format(ns.Worn.Describe(), ns.CharStats.Describe()))
	return true
end

function Window.Built()
	return window ~= nil
end

function Window.Shown()
	return window ~= nil and window:IsShown()
end

--------------------------------------------------------------------------
-- The key
--
-- Blizzard's own sheet opens in a fight and so must this one. What stopped it
-- is the gear page: a frame built from a secure template is protected, showing
-- a window that has a protected frame inside it is itself protected, and an
-- addon may not do a protected thing in combat. Blizzard's code may. So may a
-- snippet, and a snippet is the sanctioned way an addon borrows the permission.
--
-- So the key does not call any of the Lua below. It is bound to this button,
-- the button carries the snippet, and the snippet shows or hides the window.
-- Everything the Lua side still wants, painting the page that came up, hangs
-- off the window's own OnShow, which fires whoever showed it.
--
-- Character/Blizzard.lua binds the key to it, because that file already owns
-- which key opens this window and hands the key back when the switch is off.
--------------------------------------------------------------------------

local KEY = "WarriorKitCharacterKey"

-- Built with the window and never before it: the snippet is handed the frame it
-- acts on, because a snippet may only touch what it has been given a reference
-- to. Named, because SetOverrideBindingClick takes the name of a button rather
-- than the button.
function Window.Key()
	if key then
		return key
	end
	if not Window.Build() then
		return nil
	end
	key = CreateFrame("Button", KEY, UIParent, "SecureHandlerClickTemplate")
	-- The down edge, which is the one a key bound with SetOverrideBindingClick
	-- is dispatched on with no useOnKeyDown attribute set. Hover/Cast.lua's
	-- header carries the proof off a live client, and every keyed button in this
	-- addon is registered the same way. Registering both edges here would run
	-- the snippet twice and the window would open and shut in one press.
	key:RegisterForClicks("AnyDown")
	key:SetFrameRef("window", window.frame)
	key:SetAttribute("_onclick", [[
		local sheet = self:GetFrameRef("window")
		if sheet:IsShown() then
			sheet:Hide()
		else
			sheet:Show()
		end
	]])
	return key
end

function Window.KeyName()
	return KEY
end

--------------------------------------------------------------------------

-- Opened on a tab, which is what the C key needs: the client's own key carries
-- which of its pages it meant, and a key that always landed on the gear tab
-- would be a worse key than the one it replaced.
--
-- In a fight this cannot open the window and says so. The key can, and a tab
-- change on a window that is already up is ordinary, so that half falls
-- through: pressing the skills key mid pull on an open sheet still works.
function Window.Show(tab)
	Window.Build()
	if InCombatLockdown() and not window:IsShown() then
		ns.Print(("the character sheet opens on %s in a fight."):format(ns.CharBlizzard.KeyText()))
		return false
	end
	-- Asked before it is called, because in a fight a window that is already up
	-- is a window this may not call Show on either: the client refuses the call
	-- rather than noticing it would have changed nothing.
	if not window:IsShown() then
		window:Show()
	end
	if tab and TABS[tab] then
		tabs:Select(tab)
	else
		Window.Paint()
	end
	return true
end

-- Refused in a fight for the reason Show is, and it names the two ways out that
-- do work, both of which are snippets: the key and the cross on the title bar.
function Window.Hide()
	if not window then
		return false
	end
	if InCombatLockdown() and window:IsShown() then
		ns.Print(("the character sheet closes on %s or on its own cross in a fight.")
			:format(ns.CharBlizzard.KeyText()))
		return false
	end
	window:Hide()
	return true
end

function Window.Toggle(tab)
	if Window.Shown() and (tab == nil or tab == showing) then
		return Window.Hide()
	end
	return Window.Show(tab)
end

function Window.Tab()
	return showing
end

-- One tab's pane, handed out rather than answered about.
--
-- What the harness checks here is the picture: how many squares the gear page
-- drew, which of them are showing a durability line, how tall a row came out
-- once its sentence wrapped. None of that is a boolean this file could compute
-- without computing it the same way twice, which is a test that agrees with
-- itself. Same reason ns.Attic.Frame hands the room over.
function Window.Pane(index)
	return panes[index]
end

-- Repainted only while it is up. Every event below fires whether or not
-- anybody is looking, and walking nineteen slots and sixty skills to update a
-- window nobody has open is the waste this addon has a gate for.
function Window.Refresh()
	if Window.Shown() then
		return Window.Paint()
	end
	return false
end

function Window.Describe()
	if not ns.db.character then
		return "off"
	end
	if not window then
		return "not built yet"
	end
	return Window.Shown() and ("open on " .. TABS[showing].label) or "closed"
end

--------------------------------------------------------------------------
-- Events
--
-- Every one is pcalled onto the frame, because the two clients this addon runs
-- on disagree about three of them and registering an event a client has never
-- heard of raises rather than being ignored. COMBAT_RATING_UPDATE is the one
-- that settles it: there are no combat ratings at all on the older client, and
-- a login error is what a plain register would cost there.
--------------------------------------------------------------------------

local WATCHED = {
	"UNIT_INVENTORY_CHANGED",
	"PLAYER_EQUIPMENT_CHANGED",
	"UPDATE_INVENTORY_DURABILITY",
	"UNIT_STATS",
	"UNIT_ATTACK_POWER",
	"UNIT_RESISTANCES",
	"COMBAT_RATING_UPDATE",
	"SKILL_LINES_CHANGED",
	"UPDATE_FACTION",
	"PLAYER_LEVEL_UP",
}

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
for index = 1, #WATCHED do
	pcall(events.RegisterEvent, events, WATCHED[index])
end
events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_REGEN_ENABLED" then
		-- Whatever the fight refused. One flag rather than a queue, because
		-- everything deferred here ends in the same two calls.
		if pending then
			pending = false
			Window.Fit()
		end
		Window.Refresh()
		return
	end
	if event == "PLAYER_LOGIN" then
		if ns.db.character then
			Window.Build()
		end
		-- Nothing here caged Blizzard's sheet or took the C key, and that is the
		-- difference between this part and the quest log. Character/Blizzard.lua
		-- is registered through ns.BlizzHide.Also, so the pass that runs at
		-- login, when a switch moves, when combat drops and once a second
		-- forever reaches it without this file naming it. The quest log's own
		-- hide is not on that list and has to be called.
		return
	end
	Window.Refresh()
end)

-- The grid moved: the screen changed size, or the player dragged the UI size
-- slider. The window goes back onto the grid at the new zoom and is then laid
-- out again, in that order, because every number Fit uses is in the window's
-- own units and those units are what just changed.
