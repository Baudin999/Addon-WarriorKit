local ADDON, ns = ...

local Compare = {}
ns.Compare = Compare

--------------------------------------------------------------------------
-- What you are wearing, beside what you are pointing at
--
-- Hold shift over a piece of gear and the game puts the piece it would replace
-- next to it. That is fifteen years of muscle memory and it is how anybody
-- decides whether a drop is an upgrade: not by reading two numbers on one box,
-- but by reading two boxes side by side.
--
-- It stopped working the moment this addon started drawing its own tooltip, and
-- it stopped working everywhere at once. The client's comparison is not a
-- feature of items, it is a feature of the client's own box: that parchment
-- holds two more parchments called ShoppingTooltip1 and 2, it fills them from
-- its own OnUpdate while a modified click is held, and nothing about any of it
-- is reachable from a box somebody else drew. So a bag square, a quest reward,
-- a loot row, a dungeon drop and a link in chat all went quiet together, and
-- the only thing on screen saying so was the absence of a box nobody could
-- point at.
--
-- **This is that behaviour, rebuilt on the addon's own three files.** It is
-- twenty lines of decision and no drawing at all, which is the whole reward for
-- the shape UI/Tip.lua already had:
--
--   Core/Gear.lua      which worn slots an item would land in
--   Character/Worn.lua what is in one of those slots right now
--   UI/Tip.lua         a subject, built into a box
--   UI/Tooltip.lua     that box, drawn beside the one under the cursor
--
-- Nothing here knows what a tooltip looks like and nothing in UI/ knows what a
-- ring is. This file is the sentence that joins them, and it is registered
-- rather than called: UI/Tip.lua asks whoever handed it a comparer, and this is
-- the only part of the addon that has anything to say.
--
-- **Every hover gets it for free, and that is the point.** There is no list of
-- call sites here and there is no per-window switch, because every item hover
-- in the addon already goes through ns.Tip.Open with a link on it. The bags,
-- the merchant, the mail, the loot feed, the quest log's rewards, the dungeon
-- log's drops, the character sheet and a link somebody pasted in chat are one
-- code path and always were. What was missing was not a hook in each of them.
-- It was this file.
--
-- **Two ways to ask for it, and both are the client's own.** Shift held is the
-- one everybody knows. The other is the client's alwaysCompareItems, which is a
-- checkbox in Blizzard's own interface options and means "do it without the
-- key": a player who has ticked it has already said what they want and should
-- not have to say it again here.
--------------------------------------------------------------------------

-- Whether the addon offers this at all, pushed in by Settings/Settings.lua for
-- the reason the placement and the linger are: the part that draws is not
-- allowed to know the name of a setting, and neither is the part that decides
-- what to draw beside it.
--
-- On to start with, because it is the client's own behaviour and a player who
-- notices this setting at all is a player who has already noticed it working.
local enabled = true

function Compare.SetEnabled(on)
	local want = on and true or false
	if want == enabled then
		return false
	end
	enabled = want
	-- The box that is up follows the switch, because the control is in the
	-- settings window and the box demonstrating it is usually the hover you
	-- have on screen while you flip it.
	ns.Tip.Again()
	return true
end

function Compare.Enabled()
	return enabled
end

-- Whether a comparison is wanted this instant.
--
-- Asked rather than tracked. The key state is a fact the client already holds
-- and asking costs one call on a hover, where tracking it would cost a flag
-- this file has to keep in step with a key that can go down while the game is
-- in the background and come up while it is not.
--
-- The CVar is read through a guard because it is a name rather than a call: a
-- client that does not carry it answers nothing, and nothing has to read as
-- "shift only" rather than as an error.
local function Wanted()
	if type(IsShiftKeyDown) == "function" and IsShiftKeyDown() then
		return true
	end
	if type(GetCVarBool) ~= "function" then
		return false
	end
	local ok, always = pcall(GetCVarBool, "alwaysCompareItems")
	return (ok and always) and true or false
end

-- What to put beside a subject, as an array of subjects.
--
-- Nil for everything that is not an item you could put on, which is most
-- hovers in the addon: an action square, an aura, a feed's filter chip, a
-- creature in the world, a stack of cloth.
--
-- **A worn slot with nothing in it is left out rather than drawn empty.** An
-- empty finger is not a comparison, it is the absence of one, and a box saying
-- so would be a box you have to read to learn nothing. Blizzard's own does the
-- same and for the same reason.
--
-- **And so is the piece you are already wearing.** A link is the whole item
-- down to its enchant, so two identical strings are one object seen twice:
-- hovering your own weapon in a loadout list would otherwise put that weapon
-- next to itself.
local function For(subject)
	if not enabled or subject.kind ~= "item" or not subject.link then
		return nil
	end
	if not Wanted() then
		return nil
	end

	local slots = ns.Gear.Replaces(subject.link)
	if not slots then
		return nil
	end

	local worn
	for index = 1, #slots do
		local slot = slots[index]
		local link = ns.Worn.Link(slot)
		if link and link ~= subject.link then
			worn = worn or {}
			worn[#worn + 1] = { kind = "inventory", unit = "player", slot = slot }
		end
	end
	return worn
end

ns.Tip.SetCompare(For)

-- Shift, watched, so the box follows the key rather than the pointer.
--
-- This is the half that cannot be done at hover time. Everything above runs
-- when a tooltip opens, and the whole gesture is pressing a key while one is
-- already open and the mouse has not moved. There is no second OnEnter coming,
-- so the key has to ask for the box again itself.
--
-- MODIFIER_STATE_CHANGED rather than a ticker, which is the note
-- Buttons/Placing.lua already carries: the client knows when a key moves and an
-- OnUpdate asking ten times a second would be a ticker the addon then has to
-- defend forever. Registered always and answered only for shift, because the
-- event is one string comparison on a key almost nobody holds by accident.
--
-- ns.Tip.Again refuses on its own where no box is up, which is nearly every
-- press, so there is nothing to check here before asking.
local keys = CreateFrame("Frame")
keys:RegisterEvent("MODIFIER_STATE_CHANGED")
keys:SetScript("OnEvent", function(_, _, key)
	if type(key) == "string" and key:find("SHIFT") then
		ns.Tip.Again()
	end
end)

-- One sentence for the panel, in the terms every other reading there is written
-- in: what will happen the next time you hold the key, rather than what the
-- setting is called.
function Compare.Describe()
	if not enabled then
		return "off, so a hover says what the thing is and nothing about what you have on"
	end
	if type(IsShiftKeyDown) ~= "function" then
		return "on, and this client will not say whether shift is down"
	end
	return "hold shift over a piece of gear anywhere in the addon and what you are"
		.. " wearing opens beside it, two boxes for a ring and for a trinket"
end
