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
--
-- `unit` is a token: player, target, mouseover, nameplate3. It is the only kind
-- here whose subject is not something this addon drew, and the one where the
-- client's text is the whole answer rather than a supplement to it. What the
-- game writes for a unit is the name, the level and classification tag, the
-- faction, the guild and on a player the class: five lines the addon has no
-- other way to word, half of them localised, and all of them already right.
local KINDS = {
	item      = { method = "SetHyperlink",     args = 1 },
	action    = { method = "SetAction",        args = 1 },
	buff      = { method = "SetUnitBuff",      args = 2 },
	debuff    = { method = "SetUnitDebuff",    args = 2 },
	inventory = { method = "SetInventoryItem", args = 2 },
	unit      = { method = "SetUnit",          args = 1 },
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

--------------------------------------------------------------------------
-- Holding the client's own tooltip down
--
-- Every other hover in this addon is replaced by replacing the frame it lands
-- on. There is an OnEnter, the addon writes it, and Blizzard's tooltip is never
-- asked for. A creature in the world has no such frame: the cursor is over
-- WorldFrame, the client resolves `mouseover` and fills GameTooltip itself, and
-- there is nothing to overwrite. So the only way to have one box on screen
-- rather than two is to take the client's back down after it has gone up.
--
-- It is here because this is the file allowed to name GameTooltip, and that
-- rule is worth more than the convenience of putting the code beside the part
-- that asks for it. scripts/check.sh fails on the name anywhere else, comments
-- included.
--
-- **Narrow twice, and both narrowings are load bearing.** It is armed only
-- while the addon has a box of its own on screen, and it acts only on a tooltip
-- that answers a unit. GameTooltip is shared furniture: a quest reward, an item
-- somebody linked in chat, a bag slot, a merchant row and every other addon
-- installed all draw in it, and none of those is this addon's to take away.
--
-- What the two ways of being wrong cost is not the same, which is why the test
-- is the strict one rather than the thorough one.
--
--   too broad   a hover that is not a creature loses its tooltip whenever a mob
--               happens to be under the cursor as well. A linked item says
--               nothing, a quest reward says nothing, and nothing on screen
--               says why. That is a bug report nobody can reproduce.
--   too narrow  Blizzard's parchment stands beside the addon's box and the same
--               mob is described twice. Ugly for an evening, and nothing is
--               lost.
--
-- **The hook is never taken off.** HookScript chains under whatever the client
-- and every other addon already put there and there is no call to undo one, so
-- the flag below is what actually turns this on and off. Disarmed, the hook is
-- one comparison on a tooltip that was going to be shown anyway.
--------------------------------------------------------------------------

local suppressing = false
local hooked = false

-- Take it down if it is up and it is about a unit.
--
-- Called from the hook and again the moment suppression is armed, because the
-- client shows its tooltip and fires UPDATE_MOUSEOVER_UNIT in whichever order
-- it likes: the addon can hear about the mouseover after the parchment is
-- already on screen, and then no OnShow is coming.
local function Hush()
	if not suppressing then
		return
	end
	local theirs = GameTooltip
	if type(theirs) ~= "table" or type(theirs.GetUnit) ~= "function" then
		return
	end
	-- The name comes back first and is thrown away. A tooltip describing an
	-- item has a name too; only the second return says the subject is a unit.
	local _, unit = theirs:GetUnit()
	if unit == nil or type(theirs.Hide) ~= "function" then
		return
	end
	theirs:Hide()
end

-- Arm or disarm, and answer whether it is armed.
--
-- False on a client that will not take the hook at all, which is not the same
-- as being turned off: the caller is drawing its own box either way and has to
-- be able to tell the player they are about to see two.
function Scan.Suppress(on)
	suppressing = on and true or false
	if not suppressing then
		return false
	end

	if not hooked then
		if type(GameTooltip) ~= "table" or type(GameTooltip.HookScript) ~= "function"
			or not pcall(GameTooltip.HookScript, GameTooltip, "OnShow", Hush) then
			suppressing = false
			return false
		end
		hooked = true
	end

	Hush()
	return true
end

function Scan.Suppressing()
	return suppressing
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
