local ADDON, ns = ...

local Window = {}
ns.TalentWindow = Window

local UI = ns.UI
local C, M = UI.Color, UI.Metric
local Read, Board, Cost = ns.TalentRead, ns.TalentBoard, ns.TalentCost

--------------------------------------------------------------------------
-- The talent window
--
-- Three trees side by side, every talent in every one of them on the screen
-- at once, and nothing to scroll.
--
-- **That is the whole argument.** The client's own frame shows one tree at a
-- time behind three tabs, in a scroll view that on the wider trees hides the
-- last two tiers under the fold, so the question everybody opens it with,
-- "where are my forty one points", is answered by three tabs and a scroll bar.
-- This window is sized to the tallest tree this character has: seven tiers on
-- the older client, nine on the newer, read off the client rather than written
-- here, and every square of all three is in front of you the moment it opens.
--
-- **It replaces the client's window rather than sitting beside it.**
-- Blizzard.lua puts the client's frame in the attic and takes the N key,
-- behind the one switch on the page where every other Blizzard frame this
-- addon replaces is switched. Nothing on this window is secure, because
-- spending a point is not a protected act, so the key is the plain global the
-- client already routes it through and the window opens in a fight.
--
-- **Two specs are a strip across the top.** Where the client has dual
-- specialisation the window carries two tabs, the one you are standing in
-- marked, and a button that makes the other one live. Points go into the live
-- one only, which is the client's own rule, and the boards say so on a hover
-- rather than by refusing quietly. A client with one group draws no strip at
-- all: the boards start under the title and the window is that much shorter.
--
-- **The foot is the two numbers the client's frame does not put together.**
-- How many points are waiting, and what unlearning them all would cost, the
-- second off Talents/Cost.lua and worded as a quote where there is one and as
-- an estimate where there is not.
--
-- Nothing here is on a ticker. The window paints when it opens and when the
-- client says the talents moved, and a window nobody has open is not painted
-- at all.
--------------------------------------------------------------------------

-- The air between two boards, and the hairline down the middle of it.
local BETWEEN = 20

-- How tall the strip across the top is where there are two specs, and the
-- room under it before the boards start.
local STRIP = M.tab + M.gutter

local window, tabs, activate, foot
local boards = {}

-- Which group the boards are showing. The live one until a tab is pressed,
-- and back to the live one whenever the client says the live one changed.
local viewing = 1

-- The tallest tree drawn, so the window can be sized to it exactly.
local tiers = 1

--------------------------------------------------------------------------
-- Size
--
-- Worked out from what the boards drew rather than from a constant, because
-- the two clients disagree about how many tiers a tree has and a window sized
-- for the taller one on the shorter client is two tiers of nothing.
--------------------------------------------------------------------------

local function Width()
	return M.pad * 2 + Read.Tabs() * Board.Width() + (Read.Tabs() - 1) * BETWEEN
end

local function Height(count)
	local strip = (count > 1) and STRIP or 0
	return M.title + M.pad + strip + Board.Height(tiers) + M.pad + M.footer
end

-- Every board placed, the strip shown or not, and the window sized to fit.
function Window.Fit()
	if not window then
		return false
	end
	local count = Read.Groups()
	local strip = (count > 1) and STRIP or 0
	local width, height = Width(), Height(count)
	window:Resize(width, height)

	tabs.frame:SetShown(count > 1)
	activate:SetShown(count > 1 and viewing ~= select(2, Read.Groups()))
	if count > 1 then
		tabs:Resize(width - M.pad * 2 - activate:GetWidth() - M.gutter)
	end

	for index = 1, #boards do
		local board = boards[index]
		board.frame:ClearAllPoints()
		board.frame:SetPoint("TOPLEFT", window.content, "TOPLEFT",
			M.pad + (index - 1) * (Board.Width() + BETWEEN), -(M.pad + strip))
		if board.rule then
			board.rule:ClearAllPoints()
			board.rule:SetPoint("TOPLEFT", board.frame, "TOPRIGHT", math.floor(BETWEEN / 2), 0)
			board.rule:SetPoint("BOTTOMLEFT", board.frame, "BOTTOMRIGHT", math.floor(BETWEEN / 2), 0)
		end
	end
	return true
end

--------------------------------------------------------------------------
-- The strip
--------------------------------------------------------------------------

local function SpecLabel(group, active)
	local word
	if group == 1 then
		word = type(_G.TALENT_SPEC_PRIMARY) == "string" and _G.TALENT_SPEC_PRIMARY or "Primary"
	else
		word = type(_G.TALENT_SPEC_SECONDARY) == "string" and _G.TALENT_SPEC_SECONDARY or "Secondary"
	end
	if group == active then
		return word .. ", live"
	end
	return word
end

-- Whether the paint below is the one moving the strip, in which case the
-- strip's own callback must not paint again.
local quiet = false

local function Select(index)
	if quiet then
		return false
	end
	viewing = index
	return Window.Paint()
end

local function Activate()
	local count, active = Read.Groups()
	if count < 2 or viewing == active then
		return false
	end
	if InCombatLockdown() then
		ns.Print("the other spec cannot be made live in a fight.")
		return false
	end
	return Read.Activate(viewing)
end

--------------------------------------------------------------------------

function Window.Build()
	if window then
		return window
	end

	window = UI.Window({
		name = "WarriorKitTalents",
		title = "Talents",
		width = Width(),
		height = Height(1),
		zoom = function() return ns.Zoom("talentsZoom") end,
		rescale = function(apply)
			apply()
			Window.Fit()
			Window.Refresh()
		end,
	})
	ns.Remember(window)

	tabs = UI.TabStrip(window.content, { onSelect = Select })
	tabs.frame:SetPoint("TOPLEFT", M.pad, -M.pad)
	tabs:Add(SpecLabel(1, 1))
	tabs:Add(SpecLabel(2, 1))

	activate = UI.Button(window.content, { label = "Make this spec live", width = 130, height = M.tab,
		onClick = Activate })
	activate:SetPoint("TOPRIGHT", -M.pad, -M.pad)

	for index = 1, Read.Tabs() do
		local board = Board.New(window.content)
		if index < Read.Tabs() then
			board.rule = UI.Rule(window.content, C.hairline, true)
		end
		boards[index] = board
	end

	foot = UI.Label(window.footer, M.small, C.dim, "LEFT", UI.FLAT)
	UI.Wrap(foot, false)
	foot:SetPoint("LEFT")
	foot:SetPoint("RIGHT")

	window.frame:SetScript("OnShow", function()
		Window.Paint()
	end)

	viewing = select(2, Read.Groups())
	Window.Fit()
	return window
end

--------------------------------------------------------------------------
-- Painting
--------------------------------------------------------------------------

local function PointsLine(unspent)
	if unspent < 1 then
		return "No points to spend"
	end
	if unspent == 1 then
		return "1 point to spend"
	end
	return ("%d points to spend"):format(unspent)
end

-- Every board, the strip and the foot. The window is then fitted again,
-- because how tall the boards came out is only known once they are painted.
function Window.Paint()
	if not window then
		return false
	end
	local count, active = Read.Groups()
	if count < 2 or viewing < 1 or viewing > count then
		viewing = active
	end
	local live = viewing == active
	local unspent = Read.Unspent(viewing)

	tiers = 1
	for index = 1, #boards do
		local _, deep = boards[index]:Set(index, viewing, unspent, live)
		if deep > tiers then
			tiers = deep
		end
	end

	if count > 1 then
		tabs:SetLabel(1, SpecLabel(1, active))
		tabs:SetLabel(2, SpecLabel(2, active))
		if tabs.selected ~= viewing then
			quiet = true
			tabs:Select(viewing)
			quiet = false
		end
	end

	foot:SetText(("%s. %s."):format(PointsLine(unspent), Cost.Describe()))
	Window.Fit()
	return true
end

function Window.Built()
	return window ~= nil
end

function Window.Shown()
	return window ~= nil and window:IsShown()
end

function Window.Show()
	Window.Build()
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

-- The other group's boards, for the harness and the slash word. A group this
-- character does not have is refused rather than drawn empty.
function Window.View(group)
	local count = Read.Groups()
	if group < 1 or group > count then
		return false
	end
	viewing = group
	return Window.Paint()
end

function Window.Viewing()
	return viewing
end

function Window.Board(index)
	return boards[index]
end

function Window.Tiers()
	return tiers
end

-- Repainted only while it is up. Every event below fires whether or not
-- anybody is looking, and walking a hundred talents to update a window nobody
-- has open is the waste this addon has a gate for.
function Window.Refresh()
	if Window.Shown() then
		return Window.Paint()
	end
	return false
end

-- The three trees in a sentence, for the panel and the slash word.
function Window.Trees()
	local parts = {}
	for tab = 1, Read.Tabs() do
		local name, _, points = Read.Tree(tab)
		parts[#parts + 1] = ("%d %s"):format(points or 0, name or ("tree " .. tab))
	end
	return table.concat(parts, ", ")
end

function Window.Describe()
	if not ns.db.talents then
		return "off"
	end
	if not window then
		return "not built yet"
	end
	if not Window.Shown() then
		return "closed"
	end
	local count = Read.Groups()
	if count > 1 then
		return ("open on %s"):format(SpecLabel(viewing, select(2, Read.Groups())))
	end
	return "open"
end

--------------------------------------------------------------------------
-- Events
--
-- Every one is pcalled onto the frame, because the two clients this addon runs
-- on disagree about two of them and registering an event a client has never
-- heard of raises rather than being ignored.
--------------------------------------------------------------------------

local WATCHED = {
	"PLAYER_TALENT_UPDATE",
	"CHARACTER_POINTS_CHANGED",
	"ACTIVE_TALENT_GROUP_CHANGED",
	"PLAYER_LEVEL_UP",
}

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
for index = 1, #WATCHED do
	pcall(events.RegisterEvent, events, WATCHED[index])
end
events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		if ns.db.talents then
			Window.Build()
		end
		return
	end
	if event == "ACTIVE_TALENT_GROUP_CHANGED" then
		-- Back onto the live one. The tab you were reading was the one you
		-- asked to be made live, and it is now.
		viewing = select(2, Read.Groups())
	end
	Window.Refresh()
end)
