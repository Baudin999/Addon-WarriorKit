local ADDON, ns = ...

local Window = {}
ns.CharWindow = Window

local UI = ns.UI
local C, M = UI.Color, UI.Metric

--------------------------------------------------------------------------
-- The character window
--
-- Five tabs over one window: what you are wearing, what it adds up to, what you
-- are skilled at, who likes you, and the weapon sets you have put on keys.
--
-- **It replaces the client's sheet rather than sitting beside it.** The client
-- draws four of these five and draws them as four separate windows wearing one
-- frame, with a picture of your back taking the largest area of the first one
-- and the number everybody actually wants, how often you miss, on none of them.
-- Blizzard.lua puts that frame in the attic and takes the C key, behind the one
-- switch on the page where every other Blizzard frame this addon replaces is
-- switched.
--
-- **The fifth tab is the loadouts.** They were a section of the options window,
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
-- **Nothing here is on a ticker.** Your gear changes when the server says it
-- did, which is six events, and every one of them ends in a repaint of the tab
-- that happens to be up. A window nobody has open is not repainted at all.
--------------------------------------------------------------------------

local WIDTH, HEIGHT = 580, 480

-- The five, in the order they are drawn. `fill` is what the tab's pane is
-- handed on a repaint, and the two that have none are the two that are not
-- readouts: the gear page draws itself and the loadout page is a widget kit.
local TABS = {
	{ label = "gear" },
	{ label = "stats", fill = function() return ns.CharStats.Groups() end },
	{ label = "skills", fill = function() return ns.CharSkills.Groups() end },
	{ label = "reputation", fill = function() return ns.CharRep.Groups() end },
	{ label = "loadouts" },
}

local GEAR, STATS, SKILLS, REPUTATION, LOADOUTS = 1, 2, 3, 4, 5

local window, tabs, footer
local panes = {}
local showing = GEAR

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

local function Select(index)
	showing = index
	for slot = 1, #TABS do
		local pane = panes[slot]
		if slot == index then
			pane.frame:Show()
		else
			pane.frame:Hide()
		end
	end
	return Window.Paint()
end

local function Chrome()
	footer = UI.Label(window.footer, M.small, C.dim, "LEFT", UI.FLAT)
	UI.Wrap(footer, false)
	footer:SetPoint("LEFT")
end

function Window.Fit()
	if not window then
		return false
	end
	local width = window.width - M.pad * 2
	local body = window:Body() - M.pad * 2
	local under = body - (tabs:Resize(width) + M.gutter)

	for index = 1, #TABS do
		local pane = panes[index]
		pane.frame:SetSize(width, under)
		if pane.Resize then
			pane:Resize(width, under)
		else
			pane.view:Resize(width, under)
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
		title = "Character",
		width = WIDTH,
		height = HEIGHT,
	})

	tabs = UI.TabStrip(window.content, { onSelect = Select })
	tabs.frame:SetPoint("TOPLEFT", M.pad, -M.pad)

	panes[GEAR] = ns.Paperdoll.New(window.content)
	panes[STATS] = ns.CharReadout.New(window.content)
	panes[SKILLS] = ns.CharReadout.New(window.content)
	panes[REPUTATION] = ns.CharReadout.New(window.content)
	panes[LOADOUTS] = Loadouts(window.content)

	for index = 1, #TABS do
		tabs:Add(TABS[index].label)
		panes[index].frame:SetPoint("TOPLEFT", tabs.frame, "BOTTOMLEFT", 0, -M.gutter)
		panes[index].frame:Hide()
	end

	Chrome()
	Window.Fit()
	tabs:Select(showing)
	return window
end

--------------------------------------------------------------------------

-- The tab that is up, and the line along the bottom. Nothing else, because
-- every other pane is behind this one and cannot be measured while it is.
function Window.Paint()
	if not window then
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

-- Opened on a tab, which is what the C key needs: the client's own key carries
-- which of its pages it meant, and a key that always landed on the gear tab
-- would be a worse key than the one it replaced.
function Window.Show(tab)
	Window.Build()
	window:Show()
	if tab and TABS[tab] then
		tabs:Select(tab)
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
for index = 1, #WATCHED do
	pcall(events.RegisterEvent, events, WATCHED[index])
end
events:SetScript("OnEvent", function(_, event)
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
UI.OnRescale(function()
	if not window then
		return
	end
	UI.Rezoom(window.frame, UI.WindowZoom())
	window.zoom = UI.WindowZoom()
	Window.Fit()
	Window.Refresh()
end)
