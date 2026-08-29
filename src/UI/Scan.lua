local ADDON, ns = ...

local UI = ns.UI

--------------------------------------------------------------------------
-- The client's own tooltip text, read out as data
--
-- An item's stats, an action slot's rank and cost, a debuff's description: all
-- of it is computed inside the game and there is no API that hands any of it
-- over. The one supported way to read it is to point a tooltip of your own at
-- the thing, let the client fill it in, and read the font strings back. That is
-- what this file does, and it is the only file in the addon that names
-- GameTooltip.
--
-- **That is the whole reason it exists.** Before this, six files each held their
-- own version of the same conversation with the client, and each one drew its
-- answer in Blizzard's parchment while everything beside it drew in the addon's
-- chrome. A hovered action square raised a gold-bordered scroll; the cooldown
-- square eight pixels below it raised a flat black box. Reading the text out as
-- data is what lets both be drawn the same way.
--
-- **A kind, not a method.** A caller asks for `action` or `debuff` and never
-- names a client function, because which function answers a question is exactly
-- the thing that differs between the two clients this addon ships for. A kind
-- this client has no setter for answers nil, and the caller draws whatever it
-- knew on its own.
--
-- **Nothing here is cached.** A scan happens when a tooltip opens, which is a
-- moment, and an item's text can change between two of those moments: a
-- requirement you now meet, a charge you have spent, a cooldown running. A
-- cache would buy a stale tooltip in exchange for nothing anybody can measure.
--------------------------------------------------------------------------

local Scan = {}
UI.Scan = Scan

-- The scanner's name is load bearing. A GameTooltip's lines are reachable only
-- as globals built from the frame's own name, so a nameless one has text on it
-- that nothing can read.
local NAME = "WarriorKitTooltipScan"

-- What each kind asks the client, and how many arguments it passes.
--
-- The count is here rather than left to varargs so a caller that passes the
-- wrong number is refused rather than handed to the client, where the failure
-- is a Lua error inside a C function with no useful traceback. It costs one
-- comparison per hover.
--
-- `item` is a hyperlink, which is the shape everything in this addon carries an
-- item as: a loot row, a mail attachment and a chat link are all one string.
-- `inventory` is a worn slot number and is here for one caller, the weapon
-- enchant square on the buff row, because a temporary enchant answers to the
-- hand it is on rather than to an aura index.
local KINDS = {
	item      = { method = "SetHyperlink",     args = 1 },
	action    = { method = "SetAction",        args = 1 },
	buff      = { method = "SetUnitBuff",      args = 2 },
	debuff    = { method = "SetUnitDebuff",    args = 2 },
	inventory = { method = "SetInventoryItem", args = 2 },
}

local tip
local built

-- Three states and all three are different. nil is that nothing has been
-- scanned, false is that the frame was made and answered nothing, true is that
-- it worked. Kept apart because "this client refused the frame" and "this item
-- has no text" have different fixes, and a probe that merged them would tell
-- the player the first when it meant the second.
local answered

-- Built once and remembered, because a client either carries
-- GameTooltipTemplate or it does not and the answer cannot change inside a
-- session. The alternative is a pcall on a CreateFrame on every hover.
local function Frame()
	if built ~= nil then
		return tip
	end

	built = false
	local made, frame = pcall(CreateFrame, "GameTooltip", NAME, UIParent, "GameTooltipTemplate")
	if made and frame and type(frame.NumLines) == "function" then
		-- ANCHOR_NONE and never shown. This frame exists to be written to and
		-- read back, and one that anchored itself to the cursor would flash a
		-- second tooltip on every hover.
		if type(frame.SetOwner) == "function" then
			frame:SetOwner(UIParent, "ANCHOR_NONE")
		end
		tip, built = frame, true
	end
	return tip
end

-- One side of one line, as text and three colour components.
--
-- Nil for a line that is not there or came back empty, which is every right
-- hand side on most lines. The colour travels with the text rather than being
-- normalised away, because on an item that colour is information: the name is
-- the quality, the red line is the requirement you do not meet, the green is
-- the enchant.
local function Side(index, side)
	local string = _G[NAME .. "Text" .. side .. index]
	if not string or type(string.GetText) ~= "function" then
		return nil
	end
	local body = string:GetText()
	if not body or body == "" then
		return nil
	end
	if type(string.GetTextColor) ~= "function" then
		return body
	end
	local r, g, b = string:GetTextColor()
	return body, r, g, b
end

-- Whether this client will answer at all, for a caller deciding what to draw
-- before it asks. A caller that simply asks and takes nil is doing the right
-- thing and does not need this.
function Scan.Ready(kind)
	local entry = KINDS[kind]
	if not entry then
		return false
	end
	local frame = Frame()
	return frame ~= nil and type(frame[entry.method]) == "function"
end

-- Ask the client, and hand back whether it took the question.
local function Ask(frame, entry, a, b)
	if type(frame.ClearLines) == "function" then
		frame:ClearLines()
	end
	-- A link somebody built by hand raises here rather than coming back empty,
	-- the same as it does in the chat log's hyperlink handler, so every setter
	-- goes through a pcall whatever it is.
	if entry.args == 2 then
		return pcall(frame[entry.method], frame, a, b)
	end
	return pcall(frame[entry.method], frame, a)
end

-- The client's text for one thing, as an array of lines.
--
-- Each line is `{ left, lr, lg, lb, right, rr, rg, rb }`, which is the shape
-- UI/Tooltip.lua draws a line from, so nothing between here and the screen has
-- to reshape it. Nil rather than an empty table where there is no answer: an
-- empty array is a thing with no text, a nil is a question this client will not
-- take, and the caller falls back differently for each.
function Scan.Read(kind, a, b)
	local entry = KINDS[kind]
	if not entry then
		return nil
	end
	local frame = Frame()
	if not frame or type(frame[entry.method]) ~= "function" then
		return nil
	end
	if a == nil or (entry.args == 2 and b == nil) then
		return nil
	end
	if not Ask(frame, entry, a, b) then
		return nil
	end

	local total = frame:NumLines() or 0
	if total < 1 then
		answered = false
		return nil
	end
	answered = true

	local lines = {}
	for index = 1, total do
		local left, lr, lg, lb = Side(index, "Left")
		local right, rr, rg, rb = Side(index, "Right")
		if left or right then
			lines[#lines + 1] = { left, lr, lg, lb, right, rr, rg, rb }
		end
	end
	return lines
end

function Scan.Describe()
	if built == false then
		return "this client refused a tooltip of its own, so nothing computed inside the game can be read"
	end
	if answered == nil then
		return "nothing has been hovered yet"
	end
	if not answered then
		return "this client hands over no text, so a hover shows the name and nothing more"
	end
	return "reading the client's own text and drawing it in the addon's chrome"
end
