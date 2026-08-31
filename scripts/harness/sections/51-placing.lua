-- What the lock reaches, and what it does not
--
-- Eighteen frames in this addon can be dragged. Twelve of them are the HUD, and
-- /wk lock is what stops you shoving the swing bars off the screen with a
-- misplaced click during a pull. Six are chrome windows, and locking one of
-- those would be locking a window rather than placing a piece of the HUD: you
-- opened the quest log on purpose and you will close it again in a minute.
--
-- That difference was a Lock(true) called once at build and never a second
-- time, which is a property of a frame written as a call nobody repeats.
-- UI.Placeable takes `lockable` now, and this is the gate on it, because a
-- declared property with nothing asserting it is a comment.
--
-- The failure it catches is quiet in both directions. A window that starts
-- obeying the lock is a quest log you cannot move while the HUD is locked,
-- which is how it will be for anybody who plays locked, which is everybody.
-- A HUD frame that stops obeying it is a swing bar that walks off the screen
-- on a stray drag and never says why.
--
-- Asserted through RegisterForDrag rather than through SetMovable. Both are
-- set, and the second stays true for the life of the frame: taking the drag
-- button away is how the addon actually takes a drag away, so it is the one
-- that answers the question.
--
-- Driven through ns.Each("lock"), which is what /wk lock and the panel's button
-- both call. Reaching into each part's own Lock would be testing twelve
-- functions rather than the one route a player can actually take.

local H = ...
local ns, check = H.ns, H.check

local HUD = {
	{ "WarriorKitSwing", "the swing bars" },
	{ "WarriorKitCooldowns", "the cooldown row" },
	{ "WarriorKitBuffs", "the buff nag" },
	{ "WarriorKitHoverSheet", "the mouseover sheet" },
	{ "WarriorKitMeter", "the meters" },
	{ "WarriorKitProgress", "the experience rails" },
	{ "WarriorKitPlayerCast", "your cast bar" },
	{ "WarriorKitGroup", "the party anchor" },
	{ "WarriorKitEnemyBarsAnchor", "the enemy bars anchor" },
	{ "WarriorKitCorral", "the minimap corral" },
	-- The one window that asks for the lock, because it is furniture rather
	-- than something you opened for a minute.
	{ "WarriorKitChat", "the chat window" },
	-- The marker a hover's box hangs off when the placement is the anchor. It
	-- draws nothing at all while the frames are locked, so the lock is the only
	-- thing that makes it visible or draggable, and a marker that ignored the
	-- lock would be an invisible frame swallowing the camera drag in the middle
	-- of the screen.
	{ "WarriorKitTooltipAnchor", "the tooltip marker" },
}

-- Built lazily, each by the thing that opens it, so the ones this run has not
-- opened are skipped rather than failed. Whichever are up are held to the rule.
local WINDOWS = {
	{ "WarriorKitOptions", "the settings panel" },
	{ "WarriorKitQuests", "the quest log" },
	{ "WarriorKitMail", "the mail window" },
	{ "WarriorKitBreakdown", "the meter breakdown" },
	{ "WarriorKitCharacter", "the character sheet" },
	{ "WarriorKitClutter", "the destroy window" },
	{ "WarriorKitAsk", "the confirmation window" },
}

local function draggable(name)
	local frame = _G[name]
	if not frame then
		return nil
	end
	return frame.dragButton ~= nil
end

local was = ns.db.locked

ns.db.locked = true
ns.Each("lock")

local hudHeld, hudSeen = 0, 0
for _, entry in ipairs(HUD) do
	local state = draggable(entry[1])
	if state ~= nil then
		hudSeen = hudSeen + 1
		if state == false then
			hudHeld = hudHeld + 1
		end
		check(state == false, entry[2] .. " can still be dragged with the frames locked")
	end
end
check(hudSeen >= 11, ("only %d of the 12 HUD frames were built"):format(hudSeen))

local free, windowsSeen = 0, 0
for _, entry in ipairs(WINDOWS) do
	local state = draggable(entry[1])
	if state ~= nil then
		windowsSeen = windowsSeen + 1
		if state then
			free = free + 1
		end
		check(state == true, entry[2] .. " stopped being movable when the frames were locked")
	end
end

-- And the other way round, because a frame that ignores the lock in both
-- directions passes the half above without being placeable at all.
ns.db.locked = false
ns.Each("lock")

local hudFree = 0
for _, entry in ipairs(HUD) do
	local state = draggable(entry[1])
	if state ~= nil then
		if state then
			hudFree = hudFree + 1
		end
		check(state == true, entry[2] .. " could not be dragged with the frames unlocked")
	end
end

ns.db.locked = was
ns.Each("lock")

print(("placing %d of %d HUD frames locked down and all %d back up, %d of %d windows movable throughout")
	:format(hudHeld, hudSeen, hudFree, free, windowsSeen))
