-- Quests, Questie and the cursor
--
-- Everything the clutter window rests on. The quest fixtures are chosen so
-- there is exactly one item per branch the verdict can take, and the cursor is
-- modelled rather than stubbed away: the window picks an item up and asks the
-- client what it is really holding before destroying anything, and a stub that
-- always agreed would make that check pass without ever being tested.

local H = ...
local region, constant, ITEMS = H.region, H.constant, H.ITEMS
local CARRIED, carrying, itemLink = H.CARRIED, H.carrying, H.itemLink

local QUESTS = {
	[101] = { name = "Wanted: Hogger", completed = true },
	[102] = { name = "The Missing Diplomat", completed = false },
	[103] = { name = "A Rogue's Deal", completed = false },
	[104] = { name = "Ruins of Zul'Mamwe", completed = true },
}

-- What you are on right now. One quest, and the item that belongs to it must
-- never be offered.
local QUEST_LOG = { 102 }

-- Questie's item rows, one per branch:
--   3001 one completed quest                       clutter, certain
--   3002 a quest in your log                       kept
--   3003 starts a quest you have not done          kept, and this is the one
--        that matters most
--   3004 two completed quests                      clutter, certain
--   3005 a quest neither taken nor completed       clutter, uncertain
--   3006 starts a quest you have completed         clutter, certain
--   3007 absent from the database entirely         kept
local QUESTIE_ITEMS = {
	[3001] = { relatedQuests = { 101 } },
	[3002] = { relatedQuests = { 102 } },
	[3003] = { startQuest = 103 },
	[3004] = { relatedQuests = { 104, 101 } },
	[3005] = { relatedQuests = { 103 } },
	[3006] = { startQuest = 101 },
}

local questieModules = {
	QuestieDB = {
		QueryItemSingle = function(itemId, field)
			local row = QUESTIE_ITEMS[itemId]
			return row and row[field] or nil
		end,
		QueryQuestSingle = function(questId, field)
			local row = QUESTS[questId]
			return row and row[field] or nil
		end,
	},
}

-- ImportModule hands back a fresh empty table for a module it has never heard
-- of rather than nil, which is why "the module came back" proves nothing and
-- why Clutter.lua checks for the query functions instead. The stub does the
-- same thing, so that trap is reachable from a test.
_G.QuestieLoader = {
	ImportModule = function(_, name)
		questieModules[name] = questieModules[name] or {}
		return questieModules[name]
	end,
}

_G.GetNumQuestLogEntries = function() return #QUEST_LOG end
_G.GetQuestLogTitle = function(index)
	local questId = QUEST_LOG[index]
	if not questId then
		return nil
	end
	-- The quest id is the eighth value, which is where Questie reads it from.
	return QUESTS[questId].name, 60, nil, false, false, false, nil, questId
end
_G.IsQuestFlaggedCompleted = function(questId)
	local quest = QUESTS[questId]
	return quest ~= nil and quest.completed or false
end

local cursor
local destroyed = {}

_G.GetCursorInfo = function()
	if not cursor then
		return nil
	end
	return "item", cursor.id, cursor.link
end

_G.ClearCursor = function() cursor = nil end

-- Counted, because the window has two independent guards against destroying
-- the wrong item and the counter is the only way to tell which one fired. The
-- slot re-read happens before the cursor is touched at all, so a stale card
-- that still reaches a pickup means that first guard is gone even though the
-- second one caught it.
local pickups = 0

_G.PickupContainerItem = function(bag, slot)
	pickups = pickups + 1
	local held = carrying(bag, slot)
	if not held then
		cursor = nil
		return
	end
	cursor = { id = ITEMS[held].id, link = itemLink(held), bag = bag, slot = slot }
end

-- The end of the line, and the only call in the addon with no way back. It
-- takes whatever the cursor is holding, which is exactly why the window checks
-- what that is first.
_G.DeleteCursorItem = function()
	if not cursor then
		return
	end
	destroyed[#destroyed + 1] = cursor.link
	CARRIED[cursor.bag][cursor.slot] = false
	cursor = nil
end
_G.CursorHasItem = constant(false)
-- id and the empty-slot art, the two the gear slots read. The path is shaped
-- like the client's so a slot that draws it can be told from one that does not.
_G.GetInventorySlotInfo = function(name)
	return 16, "Interface\\PaperDoll\\UI-PaperDoll-Slot-" .. tostring(name)
end

-- One action slot, modelled rather than stubbed flat.
--
-- Buttons/Slot.lua walks a ladder over five of these calls and the whole value
-- of the ladder is its order, so every rung has to be reachable from a test.
-- A stub that answered "usable, in range, no cooldown" to everything would
-- leave four of the six statuses unreachable and the ordering untested, which
-- is the only part of that file that can be wrong.
--
-- Absent from the table means an empty slot, which is what the client says for
-- every slot on a fresh character and is why HasAction used to be constant
-- false here.
local slots = {}
_G.WarriorKitSlots = slots

_G.HasAction = function(slot) return slots[slot] ~= nil end
-- What kind of thing is in the slot and which one, which is how
-- Buttons/Reaction.lua tells an Overpower square from the other twenty-three.
-- A slot the test named no spell for answers nothing at all, which is what the
-- client says for a macro, an item or an empty slot, so the path that ignores
-- everything but a plain spell is reachable from a test rather than assumed.
_G.GetActionInfo = function(slot)
	local held = slots[slot]
	if not held or not held.spell then
		return nil
	end
	return "spell", held.spell
end
_G.GetActionTexture = function(slot)
	local held = slots[slot]
	return held and held.texture or nil
end
-- start, duration, enabled, in the order the loose global answers them.
_G.GetActionCooldown = function(slot)
	local held = slots[slot]
	if not held or not held.duration then
		return 0, 0, 1
	end
	return held.start or 0, held.duration, 1
end
-- usable, and whether the block is the power bar rather than anything else,
-- which is the pair Slot.State splits "cost" from "stance" on.
_G.IsUsableAction = function(slot)
	local held = slots[slot]
	if not held then
		return false, false
	end
	if held.usable == nil then
		return true, false
	end
	return held.usable, held.noPower or false
end
-- 1, 0 or nil, the same three IsSpellInRange answers. nil is the interesting
-- one: it is what a client that never answers gives back, and what an honest
-- client gives back when the action has no range at all.
_G.IsActionInRange = function(slot)
	local held = slots[slot]
	if not held then
		return nil
	end
	return held.range
end
_G.GetActionCount = function(slot)
	local held = slots[slot]
	return held and held.count or 0
end
-- Already what is running: the stance you are standing in, the auto attack
-- already swinging. Two calls rather than one because the client has two, and
-- Buttons/Slot.lua folds them into a single answer; a stub with only the first
-- would leave the fold untested.
_G.IsCurrentAction = function(slot)
	local held = slots[slot]
	return (held and held.current) and true or false
end
_G.IsAutoRepeatAction = function(slot)
	local held = slots[slot]
	return (held and held.repeating) and true or false
end
-- Worn or wielded, which is the green ring Blizzard draws and this addon draws
-- one pixel inside the status border.
_G.IsEquippedAction = function(slot)
	local held = slots[slot]
	return (held and held.equipped) and true or false
end

-- Picking an action slot up and putting it down.
--
-- Written onto the cursor declared above rather than onto one of their own.
-- GetCursorInfo closes over that upvalue, and Buttons/Layout.lua refuses to
-- write a slot while the cursor is full, so a second cursor here would leave
-- Layout believing both hands were empty while a spell was on its way from one
-- square to another. `id` and `link` are the two fields GetCursorInfo reports,
-- so the shape is theirs and only `action` is new.
--
-- Modelled and not stubbed flat because Buttons/Bars.lua's whole drop path is
-- unreachable otherwise: a pickup that never fills the cursor and a place that
-- never moves a slot both look exactly like a bar you cannot drop on.
_G.PickupAction = function(slot)
	local held = slots[slot]
	if not held then
		return
	end
	cursor = { id = slot, link = nil, action = held }
	slots[slot] = nil
end
_G.PlaceAction = function(slot)
	local carried = cursor and cursor.action
	local displaced = slots[slot]
	slots[slot] = carried
	cursor = displaced and { id = slot, link = nil, action = displaced } or nil
end

-- Blizzard's own action bars, as much of them as a clone can see.
--
-- Five bars of twelve named buttons, each carrying the .action field that says
-- which slot it drives, and a holder frame per multi-bar whose IsShown says
-- whether the bar is on at all. Modelled rather than left absent, because
-- Buttons/Bars.lua reads the slot off the button and the on/off off the holder,
-- and with neither present every discovery comes back empty, the clone reports
-- "nothing to clone", and the whole feature tests as passing.
--
-- Bar 1 sits on bonus bar page 1 at slot 73, which is what the live client
-- answered for a warrior and is the number docs/README.md records. Three of the
-- four multi-bars are on and one is off, because a clone that hardcoded "two
-- bars" and a clone that cloned everything the client has a name for would both
-- pass a fixture where every bar was on.
local BLIZZARD_BARS = {
	{ button = "ActionButton%d", base = 73, stands = "MainActionBar" },
	{ button = "MultiBarBottomLeftButton%d", base = 61, holder = "MultiBarBottomLeft", on = true },
	{ button = "MultiBarBottomRightButton%d", base = 49, holder = "MultiBarBottomRight", on = true },
	{ button = "MultiBarRightButton%d", base = 37, holder = "MultiBarRight", on = true },
	{ button = "MultiBarLeftButton%d", base = 25, holder = "MultiBarLeft", on = false },
}

-- The frame that swallowed every drop on bar 1, modelled because reading the
-- code could not find it and only Blizzard's own source could.
--
-- MainActionBar is declared `enableMouse="true"` on MEDIUM at frame level 50,
-- 454 by 35, anchored to the bottom of UIParent. Buttons/Blizzard.lua hides the
-- twelve buttons standing on it and a hidden frame takes no mouse, but this
-- frame is not hidden and must not be: the micro menu and the bag bar hang off
-- the same corner. Strip the art and it is an invisible mouse trap across the
-- bottom of the screen.
--
-- The four multi-bars are declared with no `enableMouse` at all, which is why
-- they are absent here and why exactly one bar was ever broken. Modelling only
-- the frame that takes the mouse is the point: a fixture where every Blizzard
-- bar frame took clicks would pass a fix that raised nothing.
-- Declared inside the block, because a name at file scope here is one of the
-- two hundred Lua 5.1 allows a chunk and this file's header says what happens
-- when they run out.
do
	local main = region("frame", _G.UIParent, "MainActionBar")
	main:SetFrameLevel(50)
	-- TOOLTIP, which is what `/wk actionbars trace` read off the live client
	-- and is the whole bug: it is the top strata there is, so a cloned bar
	-- standing at MEDIUM 120 loses every hit test on that corner of the screen
	-- no matter how high the level goes. Two fixes were written against a
	-- fixture that said MEDIUM here and both of them passed it.
	main:SetFrameStrata("TOOLTIP")
	main:EnableMouse(true)
end

-- region rather than child, on purpose: these are Blizzard's frames and must
-- not turn up in the anchor sweep that holds every frame on the addon's own
-- grid to a whole pixel.
for _, bar in ipairs(BLIZZARD_BARS) do
	if bar.holder then
		region("frame", _G.UIParent, bar.holder).shown = bar.on
	end
	-- Parented to the frame they stand on where the client parents them there,
	-- because Buttons/Blizzard.lua walks up from the button to find whatever is
	-- taking the mouse above it rather than naming a frame. A fixture that hung
	-- every button off UIParent would have nothing above it to find.
	local stands = bar.stands and _G[bar.stands] or _G.UIParent
	for index = 1, 12 do
		region("button", stands, bar.button:format(index)).action = bar.base + index - 1
	end
end

_G.GetMacroIndexByName, _G.GetMacroInfo = constant(0), constant(nil)
_G.GetNumMacros = function() return 0, 0 end

-- The state driver, modelled rather than accepted.
--
-- This is the one piece of Buttons/Bars.lua that cannot be read: bar 1 is
-- re-pointed at another twelve action slots by a snippet running inside the
-- restricted environment, because an attribute cannot be written from Lua in
-- combat and a stance change happens in combat. A no-op here would leave the
-- snippet's arithmetic, and which frames it walks, tested by nothing at all.
--
-- So the registration is recorded and the snippet is run as ordinary Lua with
-- the three locals the client puts in scope. What that proves is what the
-- snippet does. What it cannot prove is that the restricted environment accepts
-- it, which is why DrivePages probes for the template and CanPage reports which
-- path came up.
local drivers = {}

_G.RegisterStateDriver = function(frame, state, macro)
	drivers[#drivers + 1] = { frame = frame, state = state, macro = macro }
end
_G.UnregisterStateDriver = function(frame, state)
	for index = #drivers, 1, -1 do
		if drivers[index].frame == frame and drivers[index].state == state then
			table.remove(drivers, index)
		end
	end
end

-- Whether a driver was registered for that frame and state, and the macro
-- condition it was given, so a test can assert the conditions cover every
-- stance rather than only that a call was made.
_G.WarriorKitDriver = function(frame, state)
	for index = 1, #drivers do
		if drivers[index].frame == frame and drivers[index].state == state then
			return drivers[index].macro
		end
	end
	return nil
end

-- One state transition, as the client would deliver it.
_G.WarriorKitDriveState = function(frame, state, newstate)
	local body = frame:GetAttribute("_onstate-" .. state)
	if type(body) ~= "string" then
		return false
	end
	local run = assert(loadstring("local self, stateid, newstate = ...\n" .. body))
	run(frame, state, newstate)
	return true
end

-- The binding set, which is what a bar clone reads its keys off. Separate from
-- the override layer below on purpose: an override never writes into this, and
-- an addon that could not tell the two apart would report its own bindings back
-- to itself as the player's.
--
-- The keys are the ones Layout.BAR1 names in its comment, because those are the
-- keys this install actually has and a fixture nobody uses proves less.
local bindings = {}
_G.WarriorKitBindings = bindings

local BAR1_KEYS = { "E", "Q", "Z", "X", "C", "V", "F", "1", "2", "3", "4", "5" }
for index = 1, 12 do
	bindings[("ACTIONBUTTON%d"):format(index)] = { BAR1_KEYS[index] }
	bindings[("MULTIACTIONBAR1BUTTON%d"):format(index)] = { "SHIFT-" .. BAR1_KEYS[index] }
	bindings[("MULTIACTIONBAR2BUTTON%d"):format(index)] = { "CTRL-" .. BAR1_KEYS[index] }
end
-- One button with a secondary key as well, because the client allows two and
-- losing the second one silently is exactly the kind of thing that ships.
bindings.ACTIONBUTTON1 = { "E", "SHIFT-BUTTON3" }

_G.GetBindingKey = function(command)
	local held = bindings[command]
	if not held then
		return nil
	end
	return held[1], held[2]
end
-- The override layer, modelled rather than accepted. Every part that takes a
-- key reads GetBindingAction back afterwards rather than believing its own
-- SetOverrideBindingClick, because a client that takes the call and does
-- nothing with it leaves no other trace. A stub that answered "" to every
-- readback would make all three of them report a client that refused the key.
local overrides = {}
_G.ClearOverrideBindings = function(owner)
	for key, held in pairs(overrides) do
		if held.owner == owner then
			overrides[key] = nil
		end
	end
end
_G.SetOverrideBindingClick = function(owner, _, key, name, suffix)
	overrides[key] = { owner = owner, action = ("CLICK %s:%s"):format(name, suffix) }
	return true
end
_G.GetBindingAction = function(key, checkOverride)
	local held = checkOverride and overrides[key]
	return held and held.action or ""
end
_G.IsControlKeyDown, _G.IsShiftKeyDown, _G.IsAltKeyDown = constant(false), constant(false), constant(false)

-- Which stance you are standing in, and which bonus bar page the client has bar
-- 1 on because of it. Both are readable rather than constant, because
-- Layout.Bar1Bases derives the other two stance pages from the one it can see
-- and refuses outright when the offset says bar 1 is not paging at all. A
-- constant zero left that refusal as the only reachable answer.
--
-- Form 1 and offset 1 is a warrior standing in battle stance, which is what the
-- live client answered on Tusksfirst and is written down in docs/README.md.
local shapeshift = { form = 1, bonus = 1 }
_G.WarriorKitShapeshift = shapeshift
_G.GetShapeshiftForm = function() return shapeshift.form end
_G.GetBonusBarOffset = function() return shapeshift.bonus end
_G.UISpecialFrames, _G.SlashCmdList, _G.Enum = {}, {}, {}

H.destroyed, H.pickups, H.slots = destroyed, pickups, slots
