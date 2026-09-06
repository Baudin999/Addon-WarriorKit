-- The standings window
--
-- Reputation was the character sheet's fourth tab and is a window of its own on
-- `/wk reputation`. Character/Reputation.lua did not change a line for the move,
-- so what this section is about is the host: that nothing exists until somebody
-- types the word, that what comes up draws the same list the tab did, and that a
-- window nobody has open is not walking the client's faction table.
--
-- **Built on the first open, which is the half that is easy to lose.** Every
-- window in the addon waits for its first open except the character sheet, and
-- the sheet is the file this one was cut out of. Copying its lifecycle would
-- have been the natural mistake: a window built at login, a faction walk paid
-- for by every player whether or not they ever type the word, and nothing
-- anywhere saying so. So the first three checks run before anything in this file
-- has asked for the window.
--
-- **The list is read through the pane rather than through the module.** What the
-- module answers is 52-gear-page.lua's shape of question; what is asserted here
-- is that the answer reached the screen, which is a different failure and the
-- one a host can cause on its own.
--
-- What this cannot prove: that a faction bar looks like anything. The fraction
-- is a width and the standing is a colour, and the stub answers about both
-- without drawing either.

local H = ...
local ns, check, fire = H.ns, H.check, H.fire

local Rep, Window = ns.CharRep, ns.CharRepWindow

local slash = _G.SlashCmdList.WARRIORKIT

local heard = {}
local chat = _G.DEFAULT_CHAT_FRAME.AddMessage
_G.DEFAULT_CHAT_FRAME.AddMessage = function(_, text)
	heard[#heard + 1] = tostring(text)
end

local function say(input)
	heard = {}
	slash(input)
end

local function said(what)
	for index = 1, #heard do
		if heard[index]:find(what, 1, true) then
			return true
		end
	end
	return false
end

local function Find(groups, title, label)
	for _, group in ipairs(groups) do
		if group.title == title then
			for _, row in ipairs(group.rows) do
				if row.label == label then
					return row
				end
			end
		end
	end
	return nil
end

----------------------------------------------------------------------
-- Nothing until it is asked for
----------------------------------------------------------------------

check(Window.Built() == false, "the standings window was built before anybody opened it")
check(_G.WarriorKitReputation == nil,
	"the standings window has a frame on the client and nobody has typed the word")
check(Window.Describe() == "not built yet",
	("a window nobody has opened describes itself as %q"):format(Window.Describe()))

-- And it is not on a key either. The sheet is built at login because its key
-- runs a snippet and a snippet may only touch a frame it was handed; nothing
-- here is secure, so a binding would be the one reason to build early and there
-- must not be one.
check(Window.Shown() == false, "a window that does not exist says it is open")

----------------------------------------------------------------------
-- The word
----------------------------------------------------------------------

say("reputation")
check(Window.Built() and Window.Shown(), "/wk reputation opened nothing")

local frame = _G.WarriorKitReputation
check(frame ~= nil, "the standings window opened without a frame on the client")
check(math.abs(ns.UI.Pixel(frame) - 1) < 1e-9,
	("the standings window is not on the grid: one pixel is %.4f units")
		:format(ns.UI.Pixel(frame)))
check(frame:GetHeight() * ns.Zoom("characterZoom") <= H.state.SCREEN_H,
	"the standings window is taller than the screen")

-- The sheet's own zoom rather than one of its own. One slider for the two of
-- them is the decision, so a second key appearing in the registry is a decision
-- reversed rather than a setting gained.
local window
for _, entry in ipairs(ns.UI.Windows) do
	if entry.frame == frame then
		window = entry
	end
end
check(window ~= nil, "the standings window is not in the addon's own list of windows")
check(window.zoom == ns.UI.ScreenZoom() * ns.Zoom("characterZoom"),
	("the standings window is at zoom %s and the sheet's is %s")
		:format(tostring(window.zoom), tostring(ns.Zoom("characterZoom"))))
check(ns.db.reputationZoom == nil,
	"the standings window grew a zoom setting of its own")

-- Typing it again shuts it, which is what every other window word in the addon
-- does and the only behaviour a player will try without reading anything.
say("reputation")
check(not Window.Shown(), "/wk reputation would not close the window it opened")
say("reputation")
check(Window.Shown(), "/wk reputation would not open it a second time")

-- And the reading, which is the sub-word. It prints rather than opening, so a
-- player who wants the number without the window has it.
say("reputation list")
check(said("factions"), "reputation list printed nothing about your standings")

----------------------------------------------------------------------
-- What it draws
--
-- The same list the tab drew, out of the same module, into the same pane class.
-- The fixture is one collapsed header with two factions under it, because
-- collapsed is the state the walk has to get past.
----------------------------------------------------------------------

do
	check(H.expandedFactions() == 1,
		"the collapsed faction header was not expanded, so nothing under it could be listed")

	local groups = Rep.Groups()
	check(#groups == 1 and #groups[1].rows == 2,
		("the standings list came back as %d groups"):format(#groups))

	local thrallmar = Find(groups, "Outland", "Thrallmar")
	check(thrallmar ~= nil and thrallmar.value:find("Honored", 1, true) ~= nil,
		("a standing the client names reads %s"):format(tostring(thrallmar and thrallmar.value)))
	check(thrallmar.fraction ~= nil and math.abs(thrallmar.fraction - 0.4) < 1e-6,
		("Thrallmar is 2400 of 6000 into Honored and the bar reads %.3f")
			:format(thrallmar.fraction or -1))

	local pane = Window.Pane()
	check(pane ~= nil and pane:Lines() > 0, "the standings window drew no lines at all")
	check(#pane.groups == #groups,
		("the pane holds %d groups and the module handed over %d")
			:format(#pane.groups, #groups))

	-- Not the compact column. This is a page of its own, so a row keeps its bar
	-- on the page and takes no hover: the sheet's column hides what it cannot fit
	-- because it is a column, and a window is not.
	local barred, hinted = 0, 0
	for index = 1, pane:Lines() do
		local line = pane.lines[index]
		if line:IsShown() then
			if line.track:IsShown() then
				barred = barred + 1
			end
			if line.hint then
				hinted = hinted + 1
			end
		end
	end
	check(barred == 2, ("%d of the two factions drew a bar"):format(barred))
	check(hinted == 0,
		"a row on the standings page kept something back for a hover, which is the column's bargain")

	-- A row with a bar is taller than a row without one, which is the whole of
	-- what the pane's own measurement pass is for. Drawn on a hidden frame it
	-- would come back at one line and stay there.
	local tallest = 0
	for index = 1, pane:Lines() do
		local line = pane.lines[index]
		if line:IsShown() then
			tallest = math.max(tallest, line:GetHeight())
		end
	end
	check(tallest > ns.UI.Metric.row,
		("the tallest row is %d px and a row with a bar under it is taller than %d")
			:format(tallest, ns.UI.Metric.row))
end

----------------------------------------------------------------------
-- The window is dragged and remembers where it went
----------------------------------------------------------------------

do
	local home = { frame:GetPoint() }
	ns.db.windowSpots.WarriorKitReputation = nil

	local took, dragging = H.mouse.DragTo(frame, frame, 120, -60, "LeftButton", 8, -8)
	check(took == frame, ("a drag on the standings window landed on %s")
		:format(took and (took:GetName() or took:GetObjectType()) or "nothing"))
	check(dragging, "the standings window is open and its title bar took no drag")

	local spot = ns.db.windowSpots.WarriorKitReputation
	check(spot ~= nil, "the standings window was dropped somewhere and wrote down nothing")

	frame:ClearAllPoints()
	frame:SetPoint(home[1], home[2] or _G.UIParent, home[3], home[4], home[5])
	ns.db.windowSpots.WarriorKitReputation = nil
end

----------------------------------------------------------------------
-- A window nobody has open is not repainted
--
-- UPDATE_FACTION fires on every turn-in and on most of what you kill, and
-- reading the list expands the client's own headers, which is a write to its
-- state. So the event has to reach a shut window and stop there.
----------------------------------------------------------------------

do
	check(Window.Shown(), "the window went down before the refresh was measured")
	check(Window.Refresh(), "an open standings window would not repaint")

	Window.Hide()
	check(not Window.Shown(), "the standings window would not close")
	check(Window.Refresh() == false, "a shut standings window repainted anyway")
	check(Window.Paint() == false, "a shut standings window painted on being asked directly")

	-- Through the client rather than by calling Refresh, because what is being
	-- checked is that the listener is on the event at all and that it asks the
	-- same question.
	fire("UPDATE_FACTION")
	check(not Window.Shown(), "an event opened a window nobody asked for")

	Window.Show()
	check(Window.Shown() and Window.Describe() == "open",
		("the window reopened and describes itself as %q"):format(Window.Describe()))
	fire("UPDATE_FACTION")
	check(Window.Pane():Lines() > 0, "the event emptied the page it was meant to refresh")
	Window.Hide()
end

_G.DEFAULT_CHAT_FRAME.AddMessage = chat

print(("standings %d factions on their own window; %s")
	:format(#Rep.Groups()[1].rows, Rep.Describe()))
