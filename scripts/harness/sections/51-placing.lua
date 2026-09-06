-- What the lock reaches, and what it does not
--
-- Twenty three frames in this addon can be dragged. Fifteen of them are the HUD, and
-- /wk lock is what stops you shoving the swing bars off the screen with a
-- misplaced click during a pull. Eight are chrome windows, and locking one of
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
	{ "WarriorKitPlayerFrame", "the player frame" },
	{ "WarriorKitTargetFrame", "the target frame" },
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
	-- Built only for a class whose file wrote slots down, which is why the loop
	-- below skips a frame that is not there rather than failing on it: on a
	-- warrior run there is no row and there is nothing to lock.
	{ "WarriorKitStanding", "the row of what you have out" },
}

-- Built lazily, each by the thing that opens it, so the ones this run has not
-- opened are skipped rather than failed. Whichever are up are held to the rule.
local WINDOWS = {
	{ "WarriorKitOptions", "the settings panel" },
	{ "WarriorKitQuests", "the quest log" },
	{ "WarriorKitMap", "the world map" },
	{ "WarriorKitMail", "the mail window" },
	{ "WarriorKitBreakdown", "the meter breakdown" },
	{ "WarriorKitClutter", "the destroy window" },
	{ "WarriorKitAsk", "the confirmation window" },
	{ "WarriorKitCharacter", "the character sheet" },
}

-- What the client delivers the drag to, which is not always the frame being
-- moved. A window with chrome is grabbed by its own chrome. The character sheet
-- has none and names a strip across its top instead, so the scripts are on the
-- strip and the frame is what they move. Asked of UI.Windows rather than
-- guessed at, because a sheet that quietly stopped naming a grip and let the
-- whole frame take the drag would pass every check below by accident.
local function grip(frame)
	for _, entry in ipairs(ns.UI.Windows) do
		if entry.frame == frame then
			return entry.grip or frame
		end
	end
	return frame
end

local function draggable(name)
	local frame = _G[name]
	if not frame then
		return nil
	end
	return grip(frame).dragButton ~= nil
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
-- Thirteen rather than fifteen, because two of the fifteen are class-gated and
-- a run as a class without them is a run where they are correctly absent.
check(hudSeen >= 13, ("only %d of the 15 HUD frames were built"):format(hudSeen))

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

----------------------------------------------------------------------
-- And where you left it
--
-- Seven of those eight windows write down where they were dropped and open
-- there again next session. All seven opened in the middle of the screen every
-- session before this, however many times you had moved them, because
-- UI.Placeable has always had the drag and there was nowhere to put the answer.
-- ns.Remember is both halves of it now, and this is the gate on it.
--
-- The failure is as quiet as the lock's. A window that stops writing its spot
-- down looks exactly like a window you have not moved yet, and the way you find
-- out is tomorrow evening, one window at a time.
--
-- The drop is fired at the frame rather than acted out with a cursor. What
-- moves a plain frame is the client, and what the addon does at the end of a
-- drag is read the point back off it, so a stub that moved the frame itself
-- would be checking its own arithmetic. The sheet is grabbed first because a
-- secure drag has no client behind it and its drop reads the grab.
--
-- Every frame goes back where it was and every key is wiped afterwards. The
-- sections below this one open these windows and measure them.
----------------------------------------------------------------------

local KEEPS = {
	{ "WarriorKitOptions", "the settings panel" },
	{ "WarriorKitQuests", "the quest log" },
	{ "WarriorKitMap", "the world map" },
	{ "WarriorKitMail", "the mail window" },
	{ "WarriorKitBreakdown", "the meter breakdown" },
	{ "WarriorKitClutter", "the destroy window" },
	{ "WarriorKitCharacter", "the character sheet" },
}

local function drop(frame, x, y)
	local by = grip(frame)
	by.scripts.OnDragStart(by)
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", _G.UIParent, "TOPLEFT", x, y)
	by.scripts.OnDragStop(by)
end

local function replace(frame, anchor)
	frame:ClearAllPoints()
	frame:SetPoint(anchor[1], anchor[2] or _G.UIParent, anchor[3], anchor[4], anchor[5])
end

local kept = 0
for index, entry in ipairs(KEEPS) do
	local frame = _G[entry[1]]
	if frame then
		local home = { frame:GetPoint() }
		local x, y = 100 + index, -(40 + index)
		ns.db.windowSpots[entry[1]] = nil
		drop(frame, x, y)
		local spot = ns.db.windowSpots[entry[1]]
		check(spot ~= nil, entry[2] .. " was dropped somewhere and wrote down nothing")
		if spot then
			kept = kept + 1
			check(spot[1] == "TOPLEFT" and spot[4] == x and spot[5] == y,
				("%s wrote down %s at %s, %s and was dropped at TOPLEFT %d, %d"):format(
					entry[2], tostring(spot[1]), tostring(spot[4]), tostring(spot[5]), x, y))
		end
		replace(frame, home)
		ns.db.windowSpots[entry[1]] = nil
	end
end
check(kept == #KEEPS,
	("%d of the %d windows that remember where you left them did"):format(kept, #KEEPS))

-- The two that are deliberately out. The chat window keeps its corner in a
-- setting of its own, because that one has a reset button pointing at it and a
-- default that says which corner a conversation belongs in; a window in both
-- places would be a window whose two answers can disagree. The question box
-- keeps none at all: it opens over whatever asked the question.
local chatWas, chat = ns.db.chatPoint, _G.WarriorKitChat
if chat then
	drop(chat, 8, -8)
	check(ns.db.windowSpots.WarriorKitChat == nil,
		"the chat window wrote its corner into the shared list as well as its own setting")
	check(ns.db.chatPoint[4] == 8,
		"the chat window stopped writing its own corner down")
	ns.db.chatPoint = chatWas
	replace(chat, chatWas)
end

local ask = _G.WarriorKitAsk
if ask then
	local home = { ask:GetPoint() }
	drop(ask, 60, -60)
	check(ns.db.windowSpots.WarriorKitAsk == nil,
		"the question box remembered where it was dragged, and it opens over what asked")
	replace(ask, home)
end

-- The other half of it: a spot in the saved file is where the window opens.
-- Asserted on a frame of this section's own, because the seven above are put
-- back where the run found them and a restore is only visible on a frame
-- nothing else is measuring.
local spare = _G.CreateFrame("Frame", "WarriorKitSpotProbe", _G.UIParent)
local probe = { frame = spare, place = ns.UI.Placeable(spare, { lockable = false }) }
ns.db.windowSpots.WarriorKitSpotProbe = { "TOPRIGHT", "UIParent", "TOPRIGHT", -30, -70 }
ns.Remember(probe)
local at = { spare:GetPoint() }
check(at[1] == "TOPRIGHT" and at[3] == "TOPRIGHT" and at[4] == -30 and at[5] == -70,
	("a saved spot opened the window at %s %s, %s rather than TOPRIGHT at -30, -70")
		:format(tostring(at[1]), tostring(at[4]), tostring(at[5])))

-- The one window that has no drag and no spot at all. The character sheet is
-- the size of the monitor and fixed to it, so there is nothing to grab, nothing
-- to save and nothing a saved point could do but put it somewhere wrong. Both
-- halves are asserted, because a frame with a drag button and no writer looks
-- exactly like a frame nobody has moved yet.
local sheet = _G.WarriorKitCharacter
if sheet then
	check(sheet.dragButton == nil,
		"the character sheet has a drag on it and it is the size of the screen")
	check(ns.db.windowSpots.WarriorKitCharacter == nil,
		"the character sheet wrote down a spot, and it cannot be anywhere but the screen")
end

-- A saved variables file is edited by hand, carried between machines and
-- written by whatever the addon was two releases ago. What a corrupt anchor
-- must be is a window in the middle of the screen, not a Lua error at login on
-- the window that would have shown it.
ns.db.windowSpots.WarriorKitSpotProbe = { "TOPLEFT" }
ns.Remember(probe)
check(({ spare:GetPoint() })[1] == "TOPRIGHT",
	"an anchor with nothing in it was handed to SetPoint")
ns.db.windowSpots.WarriorKitSpotProbe = nil

print(("placing %d windows open where you left them, the chat window on its own"
	.. " setting and the question box on none"):format(kept))
