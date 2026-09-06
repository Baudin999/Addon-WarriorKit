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
local counted = H.counted

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
--   3008 a quest further down your log             kept, and ranked after 3002
--
-- Every row carries its name, because a row is a row: Core/QuestItems.lua
-- asks for the name to tell an item Questie has never heard of from one it
-- ties to no quest, and a fixture row with no name would read as absent.
local QUESTIE_ITEMS = {
	[3001] = { name = "Hogger's Claw", relatedQuests = { 101 } },
	[3002] = { name = "Diplomat's Ring", relatedQuests = { 102 } },
	[3003] = { name = "Sealed Letter", startQuest = 103 },
	[3004] = { name = "Zul'Mamwe Fetish", relatedQuests = { 104, 101 } },
	[3005] = { name = "Rogue's Token", relatedQuests = { 103 } },
	[3006] = { name = "Old Cipher", startQuest = 101 },
	-- 202 rather than a quest lower down, because 47-quest-log.lua abandons
	-- one and 52-character.lua another, and the brotherhood is the lowest
	-- row still in the log by the time the bag sections run.
	[3008] = { name = "Trapper's Rope", relatedQuests = { 202 } },
}

-- Questie's drop table, keyed item then npc, in percent.
--
-- v11 ships one and v6 did not, which is the whole reason the addon reads it
-- through a probe rather than a call: Quests/Drops.lua has to draw the same box
-- on an install where GetItemDroprate does not exist. One pair is modelled and
-- one deliberately is not, so both branches are reachable -- 3002 off npc 1234
-- has a looked-up rate, and every other pair falls through to the ledger the
-- addon counts for itself.
local DROP_RATES = {
	[3002] = { [1234] = 22 },
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
		-- The pair Questie answers: the percentage, and which of its three
		-- databases the number came from. A bare number here would let a
		-- reader that indexed it wrong pass.
		GetItemDroprate = function(itemId, npcId)
			local row = DROP_RATES[itemId]
			local rate = row and row[npcId]
			return rate and { rate, "wowhead" } or nil
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

-- Questie's other half: the declared-stable API it ships in Public/.
--
-- The loader above cannot reach any of it. `Questie.API` is a plain table on
-- the Questie global, written there by Modules/VersionCheck.lua at load and
-- filled in by the four files under Public/, so the two halves of that addon
-- are two globals here for the same reason they are two on a real client.
--
-- Not ready at load, which is the state this matters in. Questie flips isReady
-- at the end of its own third init stage, minutes after login on a cold
-- database, and every part of this addon that asks Questie something at
-- PLAYER_LOGIN is asking before there is an answer. A stub that came up ready
-- would make the queue below unreachable and the wait untested.
--
-- Both registers throw on a non-function, because Questie's own do. It is the
-- only way a caller finds out it passed the wrong thing, and a stub that took
-- anything would let a bad call through here and fail in somebody's game.
local questiePublic = { waiting = {}, updates = {} }

_G.Questie = {
	API = {
		isReady = false,
		Enums = {
			QuestUpdateTriggerReason = {
				QUEST_ACCEPTED = 1,
				QUEST_UPDATED = 2,
				QUEST_TURNED_IN = 3,
				QUEST_ABANDONED = 4,
			},
		},
		RegisterOnReady = function(callback)
			if type(callback) ~= "function" then
				error("RegisterOnReady: callback must be a function", 0)
			end
			if _G.Questie.API.isReady then
				callback()
				return
			end
			questiePublic.waiting[#questiePublic.waiting + 1] = callback
		end,
		RegisterForQuestUpdates = function(callback)
			if type(callback) ~= "function" then
				error("RegisterForQuestUpdates: callback must be a function", 0)
			end
			questiePublic.updates[#questiePublic.updates + 1] = callback
		end,
	},
}

-- The database finishing, and the queue emptied by it. Questie drains the list
-- rather than keeping it, so a callback registered before ready runs exactly
-- once and one registered after runs immediately, and both paths are here.
function questiePublic.Ready()
	local waiting = questiePublic.waiting
	_G.Questie.API.isReady = true
	questiePublic.waiting = {}
	for _, callback in ipairs(waiting) do
		callback()
	end
	return #waiting
end

-- One quest update, in the shape Questie propagates it: the quest, the
-- objective that moved or nil, and one of the four reasons.
function questiePublic.Update(questId, objectiveIndex, reason)
	for _, callback in ipairs(questiePublic.updates) do
		callback(questId, objectiveIndex, reason)
	end
	return #questiePublic.updates
end

-- How many are listening, which is the only way to tell a register that
-- happened from one that was refused.
function questiePublic.Listening()
	return #questiePublic.waiting, #questiePublic.updates
end

H.questie = questiePublic

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
	if cursor.merchant then
		-- What the client answers with a vendor's batch on the cursor: the
		-- word and the rack index, and nothing after them.
		return "merchant", cursor.merchant
	end
	if cursor.spell then
		-- The shape this client answers a spell in: the spellbook index and the
		-- book it came out of, and nothing in a fourth slot. Modelled that way
		-- deliberately, because Hover/Hover.lua tries a fourth-slot spell id
		-- first and a stub that carried one would leave the reading this client
		-- is on untested.
		return "spell", cursor.spell, cursor.book
	end
	return "item", cursor.id, cursor.link
end

-- A spell on the cursor, which is what dragging one out of the spellbook
-- leaves there. Written onto the cursor above rather than onto one of its own,
-- for the reason PickupAction writes onto it: everything that asks what the
-- hands are holding asks that one upvalue.
_G.WarriorKitCarrySpell = function(index, book)
	cursor = index and { spell = index, book = book or "spell" } or nil
end

_G.ClearCursor = function() cursor = nil end

-- Put anything at all in the hands, for a client file that models a pickup of
-- its own. 17-merchant.lua writes a vendor's batch through this rather than
-- onto a cursor of its own, for the reason PickupAction below writes onto this
-- one: one upvalue is what every question about the hands reads.
H.hold = function(held) cursor = held end

-- Counted, because the window has two independent guards against destroying
-- the wrong item and the counter is the only way to tell which one fired. The
-- slot re-read happens before the cursor is touched at all, so a stale card
-- that still reaches a pickup means that first guard is gone even though the
-- second one caught it.
local pickups = 0

-- The second of the two calls, which is a drop rather than a pickup.
--
-- A cursor already holding a stack of the same item is what turns this into the
-- move Bags/Stack.lua is built on, and the split is the client's: as much as
-- will fit goes across, the rest stays where it came from, and a slot the move
-- empties reads false afterwards the way a sold one does. Modelled rather than
-- waved through, because the whole claim of that sweep is the arithmetic of
-- what lands where, and a stub that merged the lot would let a sweep that
-- overfilled a stack pass.
local function drop(bag, slot, held)
	local from = cursor
	local room = (ITEMS[held].stack or 1) - counted(bag, slot)
	local moved = math.min(counted(from.bag, from.slot), room)
	local left = counted(from.bag, from.slot) - moved
	counted(bag, slot, counted(bag, slot) + moved)
	-- An emptied slot goes back to the default of one rather than staying at
	-- nought. Nothing holds a count for a slot with nothing in it, and a nought
	-- left behind is what the next thing to land there would be read as.
	counted(from.bag, from.slot, left > 0 and left or 1)
	if left == 0 then
		CARRIED[from.bag][from.slot] = false
	end
	cursor = nil
end

_G.PickupContainerItem = function(bag, slot)
	pickups = pickups + 1
	local held = carrying(bag, slot)
	if not held then
		cursor = nil
		return
	end
	-- `cursor.bag` is what says the hands are holding a bag slot rather than a
	-- spell, which is the other thing that can be on this cursor.
	if cursor and cursor.bag and cursor.id == ITEMS[held].id
		and (ITEMS[held].stack or 1) > 1 then
		drop(bag, slot, held)
		return
	end
	cursor = { id = ITEMS[held].id, link = itemLink(held), bag = bag, slot = slot }
end

-- Part of a stack onto the cursor, and the rest left in the slot.
--
-- The one call in the client the loot filter has to be exact about. What it
-- destroys is the count that arrived off a corpse and the stack it arrived
-- into is holding what the character was already carrying, so a split that
-- moved the wrong number would pass a filter that deleted somebody's cloth.
--
-- An amount at or over the whole stack is a pickup, which is what the client
-- does with it: there is no such thing as splitting a stack into nothing. The
-- cursor carries how many it is holding, and that is what tells the delete
-- below apart from a delete of a whole slot.
_G.SplitContainerItem = function(bag, slot, amount)
	local held = carrying(bag, slot)
	if not held then
		cursor = nil
		return
	end
	local have = counted(bag, slot)
	if amount >= have then
		_G.PickupContainerItem(bag, slot)
		return
	end
	counted(bag, slot, have - amount)
	cursor = { id = ITEMS[held].id, link = itemLink(held), bag = bag, slot = slot,
		amount = amount }
end

-- The drop on a bag rather than on a slot, which is what the two bag buttons
-- along the client's bar do with whatever the cursor holds.
--
-- Modelled as the client does it: the item goes to the first free slot of that
-- one bag, and a bag with no room leaves it on the cursor and says nothing,
-- which is what makes the addon's walk from bag to bag reachable. The answer
-- is whether the cursor had an item at all, because that is what the client's
-- own backpack button reads to decide between a drop and a toggle. Only a slot
-- picked out of a bag can be on this cursor, so that is all that can land.
local function stow(bag)
	if not cursor or not cursor.bag then
		return false
	end
	local held = CARRIED[bag]
	for slot = 1, held and #held or 0 do
		if held[slot] == false then
			held[slot] = CARRIED[cursor.bag][cursor.slot]
			counted(bag, slot, counted(cursor.bag, cursor.slot))
			counted(cursor.bag, cursor.slot, 1)
			CARRIED[cursor.bag][cursor.slot] = false
			cursor = nil
			return true
		end
	end
	return true
end
_G.PutItemInBackpack = function() return stow(0) end
-- The client's own arithmetic: bag one is the inventory slot after the
-- nineteen worn ones. The addon never reads the number, it hands it straight
-- back, so what is checked is that the two calls agree with each other.
_G.ContainerIDToInventoryID = function(bag) return 19 + bag end
_G.PutItemInBag = function(id) return stow(id - 19) end

-- The end of the line, and the only call in the addon with no way back. It
-- takes whatever the cursor is holding, which is exactly why the window checks
-- what that is first.
_G.DeleteCursorItem = function()
	if not cursor then
		return
	end
	destroyed[#destroyed + 1] = cursor.link
	-- A split stack takes only what the cursor is holding with it. The slot it
	-- came out of still holds the remainder and its count came down when the
	-- split was made, so emptying the slot here would destroy that remainder
	-- too, which is the whole of what the filter is written not to do.
	if not cursor.amount then
		CARRIED[cursor.bag][cursor.slot] = false
		counted(cursor.bag, cursor.slot, 1)
	end
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
	if not held then
		return nil
	end
	-- A macro answers "macro" and the index of the macro, which is where every
	-- reader in the addon used to stop. The index is not a spell id and asking
	-- the wrong call about it is the bug the second return exists to catch.
	if held.macro then
		return "macro", held.macro
	end
	-- An item answers "item" and its id, which is what a hearthstone dragged
	-- onto a bar is, and is the third kind Buttons/Slot.lua reads.
	if held.item then
		return "item", held.item
	end
	if not held.spell then
		return nil
	end
	return "spell", held.spell
end
-- What a macro's conditionals resolve to, which is the only way to ask a macro
-- square what a press would cast.
--
-- Modelled off a table the test writes rather than stubbed flat, because both
-- halves are reachable defects: a macro that resolves to nothing is a slot that
-- has to fall back to the action-level answer, and a macro that resolves to a
-- reactive is the hole the whole macro path was written to close.
--
-- Answers the name and not the id, which is one of the two shapes the live call
-- takes. The other shape is driven from the section by writing a number here.
local macroSpells = {}
_G.WarriorKitMacroSpells = macroSpells
_G.GetMacroSpell = function(index)
	return macroSpells[index]
end
_G.GetActionTexture = function(slot)
	local held = slots[slot]
	return held and held.texture or nil
end
-- Whether the slot is aimed at an enemy, which is the one thing about the
-- target the client will say without one selected. Off a field on the slot
-- and false unless a section writes it, so a totem and a heal stay ready and
-- only the square the section calls an attack can be greyed for having
-- nothing to hit.
-- Under C_ActionBar, the way the 2.5.6 client holds it, and with the second
-- argument the client's documentation marks not nilable, so a caller that
-- leaves it out fails here rather than on the first square of the live tick.
-- Slot.CanRead probes the namespace first, so this is the path the bar runs.
_G.C_ActionBar = _G.C_ActionBar or {}
_G.C_ActionBar.IsHarmfulAction = function(slot, useNeutral)
	if type(slot) ~= "number" or type(useNeutral) ~= "boolean" then
		error("Usage: C_ActionBar.IsHarmfulAction(actionID, useNeutral)", 2)
	end
	local held = slots[slot]
	return (held and held.harmful) and true or false
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
-- So the registration is recorded and the snippet is run, through the sandbox
-- in 21-restricted.lua rather than as ordinary Lua. It used to be ordinary Lua
-- and that was its own lie: a body running under _G reaches every method on the
-- frame, including the PascalCase no-op that answers any call at all, so a
-- snippet calling something the restricted environment does not carry passed
-- here and failed in the game. What the run proves is what the snippet does.
-- What it cannot prove is that the client's own parser accepts the body, which
-- is why DrivePages probes for the template and CanPage reports which path came
-- up.
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

-- How many drivers are registered for that frame and state. One, always: a
-- visibility driver registered twice on one frame is two answers to the same
-- question and the client keeps both, which is exactly the leak a re-apply
-- would cause and exactly the leak nothing on screen would show.
_G.WarriorKitDrivers = function(frame, state)
	local count = 0
	for index = 1, #drivers do
		if drivers[index].frame == frame and drivers[index].state == state then
			count = count + 1
		end
	end
	return count
end

-- One state transition, as the client would deliver it.
_G.WarriorKitDriveState = function(frame, state, newstate)
	return H.snippet.State(frame, state, newstate)
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

-- The client's two chat keys, under the names FrameXML gives them. The chat
-- window reads these back rather than assuming the defaults, so a stub that did
-- not carry them would let it fall through to a path no player is on.
bindings.OPENCHAT = { "ENTER", "NUMPADENTER" }
bindings.OPENCHATSLASH = { "/" }

-- The override layer, modelled rather than accepted. Every part that takes a
-- key reads GetBindingAction back afterwards rather than believing its own
-- SetOverrideBindingClick, because a client that takes the call and does
-- nothing with it leaves no other trace. A stub that answered "" to every
-- readback would make all three of them report a client that refused the key.
local overrides = {}

-- A key with an override on it carries the override, so it is no longer one of
-- the keys the command underneath is on. That is what the client answers and it
-- is why a part that wants to read its own keys back has to give them up first.
-- A stub that answered with the key anyway let the chat window arm a key it had
-- already taken, which in the game is an enter that opens a chat line instead
-- of running the line it was loaded with.
_G.GetBindingKey = function(command)
	local held = bindings[command]
	if not held then
		return nil
	end
	local free = {}
	for _, key in ipairs(held) do
		if not overrides[key] then
			free[#free + 1] = key
		end
	end
	return free[1], free[2]
end
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
-- Asked with checkOverride the layer answers first; asked without it, the set
-- underneath answers whatever override is on the key. That second reading is
-- how a part that has taken a key finds out what the key was pressing, and
-- a stub that answered "" there would make every such key press nothing.
_G.GetBindingAction = function(key, checkOverride)
	local held = checkOverride and overrides[key]
	if held then
		return held.action
	end
	for command, keys in pairs(bindings) do
		for _, bound in ipairs(keys) do
			if bound == key then
				return command
			end
		end
	end
	return ""
end

-- The client building its binding set again, which is what happens at Okay and
-- at Cancel in the Key Bindings panel, at a switch between the account's keys
-- and this character's, and once during login after PLAYER_LOGIN has run.
-- Every override goes with it.
--
-- Modelled rather than left out, because a stub that keeps an override forever
-- cannot see the failure this caused: every key the addon took was taken at
-- login and thrown away a moment later, so it was dead before it could be
-- pressed and rebinding by hand was the only thing that appeared to work.
_G.WarriorKitRebuildBindings = function()
	overrides = {}
	H.fire("UPDATE_BINDINGS")
end
_G.IsControlKeyDown, _G.IsAltKeyDown = constant(false), constant(false)

-- Shift, readable rather than constant, because the cloned bars carry a lock of
-- their own and the key is what unlocks it. A drag handle that only comes up
-- while shift is held cannot be tested against a false that never moves.
local shift = false
_G.IsShiftKeyDown = function() return shift end
_G.WarriorKitShift = function(down)
	shift = down and true or false
	return shift
end

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
