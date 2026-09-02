-- The client's own tooltip, as much of it as UI/Scan.lua reads
--
-- The stats on an item, the rank and the cost on an action slot, the sentence
-- under a debuff: all of it is computed inside the game and no API hands it
-- over. The addon reads it the only supported way, by pointing a hidden
-- GameTooltip at the thing and reading the font strings back, and until this
-- file existed the stub answered none of that. CreateFrame ignored the
-- template, the probe in UI/Scan.lua failed, and every tooltip in the addon
-- that draws the client's own words fell through to its title. The whole path
-- was untested and looked tested.
--
-- So a frame asked for with GameTooltipTemplate comes back doing the five
-- things the scanner leans on: it takes an owner, it clears, it takes a setter,
-- it counts its lines, and its lines are reachable as globals built from its
-- own name.
--
-- **What it says is a section's to decide.** H.tooltips is one table per kind,
-- keyed by whatever the setter is passed, and a section seeds the entry it is
-- about to hover. There is no default answer on purpose: a stub that invented a
-- line for every question would make "the client said nothing" unreachable, and
-- that is the state half the fallbacks in the addon exist for.
--
-- **And Blizzard's own tooltip, which is the other half.** A creature in the
-- world has no frame for the addon to answer for, so the client fills and shows
-- GameTooltip itself and the addon takes it back down. That means the stub has
-- to be able to put the client's box up the way the client does: showing it
-- with a unit in it, and showing it with anything else, because the whole of
-- the suppression is that it acts on the first and leaves the second alone.
--
-- What this cannot prove is that the game agrees. The line count, the order and
-- the colours are modelled from the contract, and a model that is wrong is a
-- test that passes and a client that does not.

local H = ...
local child = H.child

-- Keyed by what the setter is passed. A link for an item, a slot number for an
-- action, and unit plus index or slot for the other three, joined with a colon
-- because a table keyed on two values is two tables.
--
-- One entry is an array of lines and one line is `{ left, right, color }`,
-- where color is three numbers and is left out on every line whose colour does
-- not carry information.
local tooltips = { item = {}, bag = {}, action = {}, spell = {}, buff = {},
	debuff = {}, inventory = {}, unit = {} }
H.tooltips = tooltips

local function Pair(unit, at)
	return tostring(unit) .. ":" .. tostring(at)
end
H.tooltipKey = Pair

local function String(frame, side, index)
	local name = frame.name .. "Text" .. side .. index
	local found = _G[name]
	if not found then
		found = child("fontstring", frame, name)
	end
	return found
end

local function Fill(frame, lines)
	frame.lines = lines or {}
	for index = 1, #frame.lines do
		local line = frame.lines[index]
		local left = String(frame, "Left", index)
		left:SetText(line[1] or "")
		local color = line[3]
		left:SetTextColor(color and color[1] or 1, color and color[2] or 1,
			color and color[3] or 1)
		String(frame, "Right", index):SetText(line[2] or "")
	end
	return #frame.lines
end

local function Setter(kind, key)
	return function(self, a, b)
		local at = key and key(a, b) or a
		return Fill(self, tooltips[kind][at])
	end
end

local function Dress(frame)
	frame.lines = {}

	frame.SetOwner = function() return true end
	frame.Show = function(self) self.shown = true end
	frame.Hide = function(self) self.shown = false end

	frame.ClearLines = function(self)
		for index = 1, #self.lines do
			String(self, "Left", index):SetText("")
			String(self, "Right", index):SetText("")
		end
		self.lines = {}
	end
	frame.NumLines = function(self) return #self.lines end

	-- The client raises on a malformed link rather than answering nothing, which
	-- is why every setter in UI/Scan.lua goes through a pcall. A string with no
	-- |H...|h in it is what somebody typing an item name by hand produces, and
	-- it has to reach that pcall from here or the guard is untested.
	frame.SetHyperlink = function(self, link)
		if type(link) ~= "string" or not link:find("|H.-|h") then
			error("malformed link: " .. tostring(link), 0)
		end
		return Fill(self, tooltips.item[link])
	end

	-- Keyed by bag and slot. The same item as the link setter above answers
	-- about, asked from where it is lying, which is the only way the client
	-- will say "Soulbound" rather than "Binds when picked up". A section seeds
	-- the two entries separately on purpose: the whole claim is that the bags
	-- get the second text and a loot row gets the first.
	frame.SetBagItem = Setter("bag", Pair)
	frame.SetAction = Setter("action")
	-- Keyed by the spell id. The setter Wrath added and the older client has
	-- not, which is why the nag row asks with it and takes nil where it is
	-- absent; a section that wants the older answer deletes this one.
	frame.SetSpellByID = Setter("spell")
	frame.SetUnitBuff = Setter("buff", Pair)
	frame.SetUnitDebuff = Setter("debuff", Pair)
	frame.SetInventoryItem = Setter("inventory", Pair)
	-- Keyed by the unit token, like the action setter is keyed by the slot. The
	-- one setter in the list whose subject the addon did not draw: what comes
	-- back is the client's five lines about a creature, and a section seeds them
	-- the same way it seeds an item's.
	frame.SetUnit = Setter("unit")
end

local made = _G.CreateFrame
_G.CreateFrame = function(kind, name, parent, template)
	local frame = made(kind, name, parent, template)
	if template == "GameTooltipTemplate" then
		Dress(frame)
	end
	return frame
end

-- Blizzard's own tooltip, which is not the scanner's
--
-- The scanner above is a frame the addon made and never shows. This is the one
-- the client owns: shared with quest text, with a link somebody clicked in
-- chat, with the merchant window and with every other addon installed. The
-- world hover is the one place WarriorKit touches it, and what it does is take
-- it down again, so the two things the stub has to model are the two the
-- suppression reads. GetUnit says what the tooltip is about, and Show and Hide
-- have to be real, because the suppression hangs on OnShow and a swallowed one
-- would make the whole path look tested.
--
-- 02-text.lua stands the frame up as a plain region. This dresses it, and does
-- so here rather than there for the reason the CreateFrame wrapper above is
-- here: what the client's tooltip answers is this file's subject.
local theirs = _G.GameTooltip

-- Nil for a tooltip about anything that is not a unit, which is most of them
-- and is the case the suppression has to leave alone. The name is answered
-- beside it because the client answers a name first and UI/Scan.lua throws it
-- away, and a stub that answered one value could not prove it was reading the
-- second.
theirs.unit = nil
theirs.GetUnit = function(self)
	if not self.unit then
		return nil, nil
	end
	return _G.UnitName(self.unit), self.unit
end

-- The client putting its own tooltip up, which is the event the addon answers.
--
-- Hidden first, because a region only fires OnShow on the change and a section
-- driving two hovers in a row would get one hook call for two shows. `unit` is
-- the token it is about, and nil is the tooltip carrying anything else: an item
-- somebody linked, a quest reward, another addon's line.
function H.blizzardTooltip(unit)
	theirs:Hide()
	theirs.unit = unit
	theirs:Show()
	return theirs:IsShown()
end

-- Where the pointer is.
--
-- The client answers in physical pixels, which is UIParent's own units only at
-- a UI scale of 1, and this stub runs at 0.65. So a section writes where the
-- pointer is in units and this multiplies out, which is the way round that
-- leaves the division in UI/Tooltip.lua worth asserting: a stub answering units
-- would agree with a box that never divided at all.
local cursor = { x = 300, y = 500 }
H.cursor = cursor
_G.GetCursorPosition = function()
	local scale = _G.UIParent:GetEffectiveScale()
	return cursor.x * scale, cursor.y * scale
end
