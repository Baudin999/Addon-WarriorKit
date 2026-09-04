local ADDON, ns = ...

local Auras = {}
ns.FrameAuras = Auras

--------------------------------------------------------------------------
-- The aura rows on the skinned frames
--
-- Two rows of squares under each block: what the unit is bleeding from, and
-- what is helping it. The player has a pair and so does the target. Ours, out
-- of C_UnitAuras with the UnitAura fallback every other aura reader in this
-- addon uses, drawn with UI/Aura.lua and laid out by ns.UI.Flow.
--
-- The client's own row is hidden, and that is the point of the file rather
-- than a side effect. UnitFrames/Skin.lua used to leave Blizzard's row where
-- it was and make room for it by fitting the target frame to the block plus a
-- measured lift, so the client's own arithmetic dropped the icons under the
-- block. That worked and it cost a measured lift, a UNIT_AURA handler waiting
-- for the first target carrying an aura to settle the number, a frame that was
-- not the same rectangle as the block, and a mouse region inset to pull clicks
-- off the strip underneath. All four are gone. The target frame is the block
-- exactly, like the other two.
--
-- The row could not be moved and that is why it had to be replaced. Every icon
-- in it is a child of a secure unit button, so an addon may anchor one out of
-- combat only, and the client re-anchors the head of each row on every aura the
-- target gains or loses. A row placed here would be back inside the gauge one
-- refresh into the first pull and stay there until it ended.
--
-- Hiding is a different question from anchoring and this file gets one answer
-- to it rather than assuming. The buttons go into Core/Attic.lua, the same place
-- every Blizzard frame this addon replaces goes, so a client that re-shows one
-- through SetShown gets nothing: the button's parent is hidden and cannot be
-- shown. The attic refuses on a protected region in combat and says so by
-- returning false, so a button the client builds mid fight is retried on the
-- next tick and lands the moment combat drops. Whether these buttons are
-- protected at all on this hybrid client is in the untested list in
-- docs/README.md, because the honest answer is that nobody has watched a target
-- gain its ninth debuff in a raid yet.
--
-- A button the client re-parents back out of the attic is caught by
-- ns.Attic.Sweep, which UnitFrames/Blizzard.lua runs once a second over
-- everything the attic holds. Nothing here has to keep its own watch.
--
-- The player has the same two rows under its own block. That was left out of
-- the first build and it was the wrong call: the two blocks are one HUD now
-- that the target is the player mirrored, and what is on you belongs beside
-- what is on the target rather than in the top corner of the screen where the
-- client keeps it. The rows are the same rows, off the same settings, drawn by
-- the same code, which is the whole reason ROWS is a table keyed by frame.
--
-- The client's own buffs and debuffs are hidden the same way the target's are,
-- by name and one at a time, because BuffButton1 and DebuffButton1 are built
-- the same way on demand. One thing goes with them and does not come back:
-- right click to cancel a buff, because cancelling one is a protected call and
-- a square drawn here cannot make it.
--
-- The temporary weapon enchant does come back, and it has to. It sits at no
-- aura index at all, so the walk below cannot find it and GetWeaponEnchantInfo
-- is the only call in the client that knows about it. Hiding the client's row
-- without it would take the last reading of the stone on your weapon off the
-- screen, and Buffs/Nag.lua only says when one is missing. Both hands go at the
-- head of your buff row, out of Buffs/Upkeep.lua so the three shapes that call
-- has had are counted in one place.
--
-- So the client's own enchant buttons go too, and they were left up for one
-- release. TemporaryEnchantFrame was deliberately spared while the enchant was
-- the one thing on you nothing here drew; the moment the row started drawing
-- it, sparing the client's copy stopped being a reading of the stone and
-- became a second one, in the top corner, under a square saying the same
-- number. That is the rule the whole file is built on: an aura the addon draws
-- has exactly one place on the screen.
--
-- They are swept as a run of their own rather than appended to the buff row's
-- names, because the two runs do not fill together. The sweep stops at the
-- first name the client has not built, and the client builds BuffButton6 only
-- once you carry six buffs, so a single list of both would stop short of the
-- enchants on every character who has ever had fewer buffs than the ceiling.
--------------------------------------------------------------------------

local Aura = ns.UI.Aura
local Flow = ns.UI.Flow

-- Between two squares, and between the block and the first row. In pixels,
-- like every other number the skin draws with.
local GAP = 3

-- The client's temporary weapon enchant buttons: the name it counts them from
-- and how many of them it keeps. Three, because that is main hand, off hand and
-- ranged, and the third has never been drawn on a warrior. Swept by the row
-- that draws the enchants itself, which is the only row that has earned the
-- right to take the client's copy off the screen.
local ENCHANT_HEAD, ENCHANT_COUNT = "TempEnchant", 3

-- What the square's edge may be set to. The floor is where the stack count
-- stops being readable. The ceiling is the block's own height, above which a
-- square is taller than the frame it hangs off, and that is `/wk skin height`
-- rather than the constant it was written as: the block was 34 pixels tall
-- when this file was new and it is a setting that runs to 72.
local SIZE_MIN, SIZE_CEILING = 12, 72

-- The largest either number on a square may be drawn at. UI/Aura.lua takes the
-- rest off the square's own size; these stop a large square carrying type
-- larger than the block above it.
local TIMER_CEILING, COUNT_CEILING = 14, 11

-- Which rows a skinned frame gets, by the key UnitFrames/Skin.lua's SPECS uses.
--
-- Debuffs under the block and buffs over it, on both frames. The two rows do
-- not chain and neither can push the other about, which is the whole reason
-- they are on opposite sides: a target picking up a raid's worth of bleeds
-- moves nothing that was already on your screen.
--
-- Which way each one runs is not in this table, because it is not a property of
-- the row. It comes off the block's mirror in Auras.Place: both pairs start on
-- the gauge end, the edge that faces the other block, and run outward from
-- there. So your rows run right to left and the target's run left to right, and
-- the four of them read outward from the corridor in the middle of the screen
-- the way the two blocks already do.
--
-- How long a row runs is not in this table either, and it is not a setting any
-- more. A row draws every aura the client reports, up to the client's own
-- ceiling, and wraps away from the block when a line fills. It was a count,
-- shipped at eight, and eight is exactly one line of the block the addon
-- ships: a raid's worth of buffs stopped at the end of the line and the ninth
-- was simply not on the screen. A cap on a row that wraps buys nothing, and
-- the switch that takes the rows off is `/wk skin auras`.
--
--   filter    what the client calls this half of the aura list
--   head      the client's own button names, which are what gets hidden
--   max       what the client calls its own ceiling, asked of the client
--             first so a backport that raised it is followed rather than
--             argued with
--   ceiling   how many of those the client will ever build, for a client
--             that does not carry the global above
--   enchants  put the temporary weapon enchants at the head of this row,
--             which only your own buffs can be, because they are the one
--             thing on you that no aura index answers for. It is also what
--             hides the client's own enchant buttons, and that is one flag
--             rather than two on purpose: drawing them here is the whole of
--             the reason we are allowed to take the client's copy down
--   hides     the switch that takes the client's copy of this row off the
--             screen. Three of them across the four rows, because the target's
--             buffs and debuffs are one row of icons over one frame and nobody
--             wants half of it
--   global    what this row is called, for the reason UnitFrames/Skin.lua
--             names the block: a row that lands in the wrong place can then be
--             measured from a macro or from the harness without this file
--             handing out a reference to its own tables
local ROWS = {
	player = {
		{ key = "debuffs", filter = "HARMFUL", head = "DebuffButton", below = true,
			max = "DEBUFF_MAX_DISPLAY", ceiling = 16, hides = "hideBlizzDebuffs",
			global = "WarriorKitPlayerDebuffs" },
		{ key = "buffs", filter = "HELPFUL", head = "BuffButton", below = false,
			max = "BUFF_MAX_DISPLAY", ceiling = 32, enchants = true,
			hides = "hideBlizzBuffs", global = "WarriorKitPlayerBuffs" },
	},
	target = {
		{ key = "debuffs", filter = "HARMFUL", head = "TargetFrameDebuff", below = true,
			max = "MAX_TARGET_DEBUFFS", ceiling = 16, hides = "hideBlizzTargetAuras",
			global = "WarriorKitTargetDebuffs" },
		{ key = "buffs", filter = "HELPFUL", head = "TargetFrameBuff", below = false,
			max = "MAX_TARGET_BUFFS", ceiling = 32, hides = "hideBlizzTargetAuras",
			global = "WarriorKitTargetBuffs" },
	},
}

--------------------------------------------------------------------------
-- Reading the client
--------------------------------------------------------------------------

-- The art for one aura, and where to look when the aura carries none.
--
-- The comment below has always said a client may hand back an aura with no art,
-- and until now the only thing that followed from it was that the walk did not
-- stop. The square drew empty, which on a row that also draws a timer is a
-- number floating over the block with nothing behind it.
--
-- These rows are the only reader in the addon that takes an icon off the aura
-- rather than off a spell it already knows: the enemy bars draw the list you
-- asked them to watch and have ns.SpellTexture for every entry in it. So this
-- is the same picture asked for from the other end, and it costs one call on
-- the aura that has no art rather than one on every aura.
local function Art(icon, spell)
	if icon then
		return icon
	end
	if not spell then
		return nil
	end
	return ns.SpellTexture(spell)
end

-- One aura slot, whichever API this client has.
--
-- UnitAura is asked first and C_UnitAuras second, which is the rule
-- ns.BuffName states in Core/Core.lua and for the reason it gives there: the
-- old call hands back a row of values and the new one hands back a table it
-- built to put them in. Every caller here wants the values. This file had the
-- preference the other way round, and the note under Scan saying the per-slot
-- tables are built once and never again was true of this file's own tables and
-- false of the walk that fills them: a fresh table per aura per pass, which on
-- a target carrying a raid's worth of bleeds is the garbage that shows up as a
-- stutter rather than as a number. Where only the new call exists the table is
-- made and dropped, which is the cost of that client.
--
-- The positional read of UnitAura is the only way that call can be read on
-- 2.5.6: name is first, the icon second, the stack count third, the duration
-- fifth, the expiry sixth, the caster seventh and the spell tenth.
--
-- The duration comes back with the expiry and is the sweep's half of the
-- answer. The expiry alone says when the aura ends and nothing about how much
-- of it is left, and a wedge is a fraction.
--
-- The name is the existence flag rather than the icon, because a client is
-- allowed to hand back an aura with no art and the walk must not stop there.
local function AuraAt(unit, index, filter)
	if type(UnitAura) == "function" then
		local name, icon, count, _, duration, expires, source, _, _, spell =
			UnitAura(unit, index, filter)
		return name, Art(icon, spell), expires, duration, count, source
	end
	local api = C_UnitAuras
	local getter
	if api then
		if filter == "HARMFUL" then
			getter = api.GetDebuffDataByIndex
		else
			getter = api.GetBuffDataByIndex
		end
	end
	if not getter then
		return nil
	end
	local aura = getter(unit, index)
	if not aura then
		return nil
	end
	return aura.name, Art(aura.icon, aura.spellId), aura.expirationTime,
		aura.duration, aura.applications, aura.sourceUnit
end

-- Fill one row's slots from the unit, yours first, and answer how many came
-- out.
--
-- Yours first is the one opinion in this file and it is worth the second walk.
-- The client's order is the order the auras landed in, so on anything with a
-- raid on it your Rend is somewhere past a screen of other people's bleeds and
-- a row capped at twelve loses it. Sorting would be an allocation on a ticker;
-- two passes over the same list are not, and the answer is the same.
--
-- The per-slot tables are built once and reused for the life of the session,
-- which is EnemyBars.lua's rule for the same reason: a fresh table per aura per
-- pass is the kind of garbage that shows up as a stutter on a pull rather than
-- as a number on a frame counter. The walk that fills them allocates nothing
-- either now, which it did not before; see the head of AuraAt.
-- The sharpening stone on your weapon, at the head of the row it belongs to.
--
-- It is here rather than left to the client because it is the one thing on you
-- that no aura scan can find: a temporary weapon enchant sits at no aura index
-- at all, and GetWeaponEnchantInfo is the only call that knows about it. Hiding
-- the client's buff row without this would take the last reading of it off the
-- screen, which is what the first build of these rows did.
--
-- Read through Buffs/Upkeep.lua rather than out of the call, because that file
-- already counts the returns instead of picking one of the three shapes
-- GetWeaponEnchantInfo has had. A client with no such call answers nil there
-- and this adds nothing, which is the same trade every other shim here makes.
--
-- On the tick, and it allocates nothing: two numbers out of one call and a
-- texture the client already holds.
local function Enchants(row, found, wanted, taken, now)
	local Upkeep = ns.Upkeep
	if not row.enchants or type(Upkeep) ~= "table" then
		return taken
	end
	local mine, mineLeft, other, otherLeft = Upkeep.Enchants()
	if mine == nil then
		return taken
	end
	for hand = 1, 2 do
		local has = (hand == 1) and mine or other
		local left = (hand == 1) and mineLeft or otherLeft
		if has and taken < wanted then
			taken = taken + 1
			local slot = found[taken]
			if not slot then
				slot = {}
				found[taken] = slot
			end
			local gear = (hand == 1) and ns.Gear.MAINHAND or ns.Gear.OFFHAND
			slot.icon = GetInventoryItemTexture("player", gear)
			slot.expires = (left and left > 0) and (now + left) or 0
			-- No sweep on a stone or an oil, because the client says how long
			-- one has left and never says how long it was for. A wedge here
			-- would be drawn against a number this file made up.
			slot.duration = 0
			slot.count, slot.mine, slot.index, slot.gear = 0, true, nil, gear
		end
	end
	return taken
end

local function Scan(row, unit, now)
	local wanted = row.wanted
	if wanted < 1 or not UnitExists(unit) then
		return 0
	end

	local found, filter = row.found, row.filter
	local taken = Enchants(row, found, wanted, 0, now)
	for pass = 1, 2 do
		local index = 1
		while taken < wanted do
			local name, icon, expires, duration, count, source =
				AuraAt(unit, index, filter)
			if not name then
				break
			end
			local mine = source == "player"
			if mine == (pass == 1) then
				taken = taken + 1
				local slot = found[taken]
				if not slot then
					slot = {}
					found[taken] = slot
				end
				slot.icon, slot.expires = icon, expires or 0
				slot.duration = duration or 0
				slot.count, slot.mine, slot.index = count or 0, mine, index
				slot.gear = nil
			end
			index = index + 1
		end
	end
	return taken
end

--------------------------------------------------------------------------
-- Hiding the client's rows
--
-- The buttons are built on demand: the client makes TargetFrameDebuff5 the
-- first time a target carries five debuffs, and BuffButton9 the first time you
-- carry nine buffs, and never before. So this cannot be a walk done once at
-- style time, and it must not be a walk of all ninety-six names on every tick
-- either.
--
-- It is neither. The buttons are built in order, so the only one that can have
-- appeared since the last look is the one after the last one hidden. That is a
-- single global lookup per run per pass once the run has settled, and a run of
-- them the first time a unit turns up with a full list.
--
-- A run is one name the client counts from 1, and a row can replace more than
-- one of them: your buff row stands in for BuffButton and for TempEnchant
-- both. Each carries its own mark, because each fills on its own and a sweep
-- that walked them as one list would stop at the first BuffButton the client
-- has not built and never reach the enchants at all.
--
-- A name this client does not use costs nothing and hides nothing, which is
-- the honest failure: the sweep stops at the first name that is not a frame
-- and /wk skin probe then says none of the client's are hidden. Whether these
-- five names are what this backport calls its own buttons is in the untested
-- list in docs/README.md.
--------------------------------------------------------------------------

-- One run of the client's button names, counted from 1 and stopping where the
-- client stops. `swept` is how far down it the sweep has got, which is also
-- how many of the client's this run currently has off the screen.
local function Run(head, ceiling)
	local names = {}
	for slot = 1, ceiling do
		names[slot] = head .. slot
	end
	return { names = names, swept = 0 }
end

-- False when combat refused, which is the caller's signal to try again at
-- PLAYER_REGEN_ENABLED rather than to eat a lockdown error.
--
-- A refusal on one run gives up on that run and not on the next one. The two
-- are separate frames of the client's, so a lockdown refusing one says nothing
-- about the other, and the caller retries the row whole either way.
local function Sweep(row)
	local complete = true
	local runs = row.runs
	for index = 1, #runs do
		local run = runs[index]
		local names, last = run.names, #run.names
		while run.swept < last do
			local button = _G[names[run.swept + 1]]
			if not button then
				break -- the client has not built this one yet
			end
			if not ns.Attic.Vanish(button) then
				complete = false
				break
			end
			row.stripped[button] = true
			run.swept = run.swept + 1
		end
	end
	return complete
end

-- How many of the client's buttons this row currently has off the screen,
-- across every run. Only /wk skin probe asks.
local function Swept(row)
	local runs, total = row.runs, 0
	for index = 1, #runs do
		total = total + runs[index].swept
	end
	return total
end

local function Unsweep(row)
	local complete = true
	for button in pairs(row.stripped) do
		if ns.Attic.Return(button) then
			row.stripped[button] = nil
		else
			complete = false
		end
	end
	-- Reset whether or not every one came back. The attic is a no-op on a frame
	-- it already holds, so a sweep that starts again from one costs a table
	-- lookup per button that never came back and cannot double-take anything.
	local runs = row.runs
	for index = 1, #runs do
		runs[index].swept = 0
	end
	return complete
end

-- The sweep or the undo, whichever this row's switch is asking for. Called on
-- the tick as well as on a style, so a switch that moves shows up within one
-- pass and nothing has to work out which one moved.
local function Groom(row)
	if ns.db[row.hides] then
		return Sweep(row)
	end
	return Unsweep(row)
end

--------------------------------------------------------------------------
-- The client's own buttons
--
-- Everything above takes them off the screen one name at a time, because a row
-- of ours is standing in for exactly that row of theirs and a name is the only
-- handle a button built on demand has.
--
-- That handle is not good enough on its own. A name this backport spells
-- differently is a button the sweep never reaches, and the sweep stops at the
-- first name that is not a frame, so one renamed button leaves the whole run
-- above it up. The screenshot that started this was the client's debuff still
-- on screen over the row already drawing it.
--
-- So the frames those buttons hang off go down as well, and that half lives in
-- UnitFrames/Blizzard.lua with the switch it answers to. Your buffs and your
-- debuffs have a frame between them and the world; the target's do not, and
-- for those the sweep here is the only handle there is.
--
-- The two never argue over a region. The sweep holds buttons, the other file
-- holds frames, and the attic marks what it holds, so turning either off gives
-- back only what it took.
--------------------------------------------------------------------------

--------------------------------------------------------------------------
-- The rows we draw
--------------------------------------------------------------------------

-- What a row under the block hangs from, which is not always the block.
--
-- Target of target is parked three pixels under the target block on the corner
-- the portrait is on, and the debuff row runs from the other corner, so the two
-- cannot be chained by an anchor: the row would land inset by the difference
-- between the two widths. What is taken off that frame instead is its height,
-- which is the only thing about it this row cares about, and the row goes on
-- hanging from the block's own corner with that much more drop.
--
-- The height is read on a change of head rather than every pass. The client
-- shows and hides that frame with the unit, so this measures when the target
-- picks something up or drops it, and costs one comparison against nil the
-- rest of the time. Nothing is ever parked under the player block, so over
-- there it is that comparison for the life of the session.
--
-- Writing the anchor here is allowed in combat where re-anchoring target of
-- target itself is not: this frame is ours.
local function Hang(list)
	local perch = list.perch
	local shown = (perch and perch:IsShown()) and perch or nil
	if list.head == shown then
		return
	end
	list.head = shown

	local drop = 0
	if shown then
		-- In the block's units, because that is what an anchor offset counts
		-- in and target of target is drawn at a scale of its own.
		local mine = ns.Measure(list.box, "GetEffectiveScale") or 1
		local theirs = ns.Measure(shown, "GetEffectiveScale") or mine
		if mine > 0 then
			drop = (ns.Measure(shown, "GetHeight") or 0) * theirs / mine + list.gap
		end
	end
	for index = 1, #list do
		local row = list[index]
		if row.below then
			row.frame:ClearAllPoints()
			row.frame:SetPoint(row.edge, list.box, row.corner, 0, -drop)
		end
	end
end

-- Declared here and written under Hover, which it calls. The tick is what finds
-- out how long a row has to be, and this is the one thing on that path that
-- builds anything.
local Grow

local function Fill(row, unit, now)
	local count = Scan(row, unit, now)
	-- The squares this unit has turned out to need, built the first time it
	-- needs them. See Grow, which is where the placing happens and why it is not
	-- on this path more than once per row per session.
	if count > row.drawn then
		Grow(row, count)
	end

	local squares = row.squares
	for slot = 1, count do
		local found = row.found[slot]
		local square = squares[slot]
		square.auraIndex, square.auraGear = found.index, found.gear
		Aura.Draw(square, found.icon, found.mine and "mine" or "theirs",
			found.expires, found.duration, found.count, now)
		if not square:IsShown() then
			square:Show()
		end
	end
	for slot = count + 1, #squares do
		local square = squares[slot]
		if square:IsShown() then
			square.auraIndex, square.auraGear = nil, nil
			square:Hide()
		end
	end

end

--------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------

-- What one square answers to the mouse, which is the one thing Blizzard's row
-- did that ours would otherwise drop. The index is written by the tick, so a
-- hover reads whatever the last pass a fifth of a second ago put there.
--
-- Both setters are probed rather than assumed. A client without them draws the
-- row and answers nothing, which is the same trade every other shim in this
-- addon makes.
local function Hover(square, unit, filter)
	square:EnableMouse(true)
	-- Beside the square whatever the tooltip setting says, on both answers
	-- below. The box here is the aura's own label: you are pointing at a
	-- sixteen pixel icon to find out which of eight buffs it is, and an answer
	-- that opens in the far corner of the screen makes you look back at the row
	-- and count squares to be sure it was the one under the cursor. The corner
	-- is for the box about a creature out in the world, which is a thing you
	-- cannot point at.
	local BESIDE = ns.UI.Tooltip.BESIDE

	ns.Tip.Hang(square, function(self)
		-- A weapon enchant answers to the hand it is on rather than to an aura
		-- index, which is the same question Blizzard's own enchant button asks:
		-- the item's tooltip carries the enchant line.
		if self.auraGear then
			return { kind = "inventory", unit = unit, slot = self.auraGear,
				place = BESIDE }
		end
		if not self.auraIndex then
			return nil
		end
		return { kind = filter == "HARMFUL" and "debuff" or "buff",
			unit = unit, index = self.auraIndex, place = BESIDE }
	end)
end

-- The squares a row has turned out to need, built and placed.
--
-- This is the one thing on the tick path that builds a frame, and it is here
-- because the alternative was building all of them at login: ninety six
-- squares, sixteen debuffs and thirty two buffs on each of two blocks, before
-- the player had a target. Nobody carries thirty two buffs, and a session where
-- nothing is ever targeted carried the whole ninety six anyway.
--
-- So a row is as long as the longest list that unit has actually shown it, and
-- it grows on the pass that finds the list longer. That happens a handful of
-- times in the first minute of a session and never again, which is what the
-- cold marker says: the walk in scripts/hot.lua stops here, and Aura.New,
-- Aura.Size and Flow.Arrange are not on the tick path because of it.
--
-- Everything the placing needs was worked out in Auras.Place and left on the
-- row, so nothing here decides anything: the node is the one Place built, in
-- the direction and at the width it chose, and this appends to it.
--
-- cold: builds the squares a row has not needed yet, on the pass a unit first
-- carries that many auras
function Grow(row, count)
	local plan = row.plan
	if not plan then
		return 0
	end

	-- A node of its own each time rather than one kept and appended to. Flow
	-- caches a node's measurement on the node, so a tree handed back a second
	-- time is laid out at the size it came out at the first time, which is a row
	-- of squares all sitting on the same corner.
	local node = {
		direction = "row", wrap = true, width = plan.width, gap = plan.gap,
		flow = plan.flow, pad = plan.pad,
	}
	for slot = 1, count do
		local held = row.squares[slot]
		if not held then
			held = Aura.New(row.frame)
			Hover(held, plan.unit, row.filter)
			row.squares[slot] = held
		end
		-- The height is what comes back rather than the square, because the
		-- number stands over the art now and the widget is taller than it is
		-- wide. UI/Aura.lua is the only file that knows by how much.
		local wide, tall = Aura.Size(held, plan.square, plan.px, plan.timer, plan.count)
		node[slot] = { frame = held, width = wide, height = tall }
	end
	row.drawn = count

	Flow.Arrange(row.frame, node)
	-- How many fit on a line, asked of Flow rather than worked out again here,
	-- so there is one rule for where a line breaks and not two that agree until
	-- somebody changes the gap. Only /wk skin probe reads it.
	local lines = Flow.Lines(node)
	row.perLine = math.max(lines[1] and #lines[1] or 0, 1)
	return count
end

-- One frame per row, parented to the unit frame so it hides with it. Nothing
-- is anchored or sized here: where a row goes is Auras.Place's, and the
-- squares are built there too, because their size is a setting that moves
-- while the addon is up.
--
-- On the grid, like the three frames UnitFrames/Block.lua builds beside it, so
-- every number in Place is a whole count of physical pixels.
function Auras.Build(entry)
	local plan = ROWS[entry.spec.key]
	if not plan or entry.auras then
		return
	end
	local list = {}
	for index, spec in ipairs(plan) do
		local frame = CreateFrame("Frame", spec.global, entry.frame)
		frame:EnableMouse(false)
		ns.UI.Adopt(frame)
		frame:Hide()

		-- The client's own button names, built once. A tick that concatenated
		-- them would allocate a string per name per pass to answer a question
		-- whose answer never changes.
		--
		-- One run per name the client counts from 1. Your buff row replaces
		-- two of them, because the sharpening stone it leads with is drawn by
		-- the client under a name of its own.
		local ceiling = _G[spec.max] or spec.ceiling
		local runs = { Run(spec.head, ceiling) }
		if spec.enchants then
			runs[2] = Run(ENCHANT_HEAD, ENCHANT_COUNT)
		end

		list[index] = {
			key = spec.key, filter = spec.filter, below = spec.below, enchants = spec.enchants, hides = spec.hides,
			frame = frame, squares = {}, found = {},
			runs = runs, ceiling = ceiling, stripped = {},
			-- `wanted` is the longest this row may ever be and `drawn` is how
			-- much of it has been built and placed. The second starts at nothing
			-- and Grow is the only thing that moves it.
			wanted = 0, drawn = 0, perLine = 1,
		}
	end
	entry.auras = list
end

-- Whether anything this row is laid out from has moved since the last pass.
--
-- Block.Place runs on every target change, which is every few seconds in a
-- pull, and this is the half of it that used to walk ninety six squares. Five
-- numbers decide the whole of the layout below: whether the rows are on, how
-- large a square is, what a pixel costs in the block's units, how wide the
-- block is, and which way it is mirrored. Nothing else in Place can move one of
-- them, so a pass where all five hold is a pass with nothing to lay out.
-- Only the layout: whether the row is shown is written on every pass, below.
--
-- The five are written down here rather than compared and written by the
-- caller, so there is one place that knows what the layout depends on.
local function Settled(row, on, side, px, width, mirror)
	if row.laidOn == on and row.laidSide == side and row.laidPx == px
		and row.laidWidth == width and row.laidMirror == mirror then
		return true
	end
	row.laidOn, row.laidSide, row.laidPx = on, side, px
	row.laidWidth, row.laidMirror = width, mirror
	return false
end

-- Both rows, under the block, in the units the block is drawn in.
--
-- `width` is the block's, so the row wraps against the frame it hangs under and
-- a long list grows downwards rather than off the side of the screen. `mirror`
-- is the spec's, and it is the whole of the mirroring: the row starts on the
-- corner the portrait is on and runs away from it, so the target's row reads
-- outward from its own edge exactly as the block inside it does.
--
-- Every square this row has is placed here and the tick moves none of them. It
-- used to place the longest the row is ever allowed to be, which is sixteen
-- debuffs and thirty two buffs on each of two blocks before the player had a
-- target, and none of that is built until a unit turns up carrying it now. The
-- one thing that builds a square outside this is Grow, and it carries a cold
-- marker so ns.UI.Flow stays off the tick path, which is the boundary the head
-- of UI/Flow.lua draws and check.sh enforces.
function Auras.Place(entry, px, width, mirror)
	local list = entry.auras
	if not list then
		return
	end

	local on = ns.db.skinAuras and true or false
	local low, high = Auras.SizeRange()
	local asked = ns.db.skinAuraSize or low
	local side = math.floor(math.max(math.min(asked, high), low) + 0.5)
	local gap = GAP * px
	local square = side * px

	-- Which end of the block every row starts from. It is the gauge end, the
	-- edge facing the other block, which is the opposite corner to the one the
	-- portrait is on. So the four rows all run outward from the corridor in the
	-- middle of the screen, the same way the two blocks read outward from it.
	local hand = mirror and "LEFT" or "RIGHT"
	-- Kept on the list because Hang re-anchors the rows under the block on the
	-- ticker and must not work any of this out again.
	list.box, list.gap = entry.box, gap
	list.head = nil

	for index = 1, #list do
		local row = list[index]
		row.wanted = on and row.ceiling or 0
		row.edge = (row.below and "TOP" or "BOTTOM") .. hand
		row.corner = (row.below and "BOTTOM" or "TOP") .. hand

		if not Settled(row, on, side, px, width, mirror) then
			local unit = ns.UI.Unit(row.frame)

			-- Wrapped, packed to the gauge end, and growing away from the block.
			--
			-- The direction is one word each way. Across: away from the gauge
			-- end, which is leftward on your block and rightward on the mirrored
			-- target. Down the lines: away from the block, so a row under it
			-- stacks downward and a row over it stacks upward, and line one stays
			-- against the block whichever side it is on. Flow turns the pair into
			-- the reverse, justify and lineOrder it needs, and it owns them: the
			-- earlier version set two of the three by hand and a short line on
			-- the target hugged the wrong edge until somebody set the third.
			--
			-- Everything the layout is decided from, kept on the row, because Grow
			-- lays the row out again on the pass a unit first turns up carrying more
			-- auras than the row has squares and nothing about the shape may be
			-- worked out twice.
			local plan = row.plan
			if not plan then
				plan = {}
				row.plan = plan
			end
			plan.width, plan.gap = width, gap
			plan.flow = (mirror and "right" or "left") .. (row.below and " down" or " up")
			plan.pad = row.below and { 0, gap, 0, 0 } or { 0, 0, 0, gap }
			plan.square, plan.px, plan.unit = square, px, entry.spec.unit
			plan.timer = math.floor(TIMER_CEILING * unit + 0.5)
			plan.count = math.floor(COUNT_CEILING * unit + 0.5)

			row.frame:ClearAllPoints()
			row.frame:SetPoint(row.edge, entry.box, row.corner, 0, 0)
			row.frame:SetWidth(width)
			-- Every square the row already has, placed again at the size the
			-- settings now say, and none it has not needed yet. The tick draws a
			-- prefix of them and moves none, and nothing hangs off a row any
			-- more, so a height that changed with the count would buy nothing and
			-- would cost the row above the block every square it had: those are
			-- placed against the frame's bottom edge, and that edge is the one an
			-- anchor on the block's top holds still.
			row.drawn = 0
			Grow(row, math.min(#row.squares, row.wanted))
			for slot = row.wanted + 1, #row.squares do
				row.squares[slot]:Hide()
			end
		end

		-- Outside the guard above, because whether a row is on the screen is not
		-- part of its layout and something else can move it. Auras.Unstyle hides
		-- these frames, and the style that follows is five numbers that all held,
		-- so a settled pass showed nothing: a row taken off by `/wk skin` and put
		-- back came up empty and stayed empty for the rest of the session. Place is
		-- the only thing that shows a row, so it says so on every pass rather than
		-- on the pass that happens to lay one out.
		row.frame:SetShown(on and row.wanted > 0)
	end
end

--------------------------------------------------------------------------
-- What the skin calls
--------------------------------------------------------------------------

-- Put the client's copy of each row where its switch says, and show ours. False
-- where combat refused a strip, so the caller can finish at
-- PLAYER_REGEN_ENABLED like every other half of the skin that a lockdown can
-- turn down.
function Auras.Style(entry)
	local list = entry.auras
	if not list then
		return true
	end
	local complete = true
	for index = 1, #list do
		if not Groom(list[index]) then
			complete = false
		end
	end
	return complete
end

function Auras.Unstyle(entry)
	local list = entry.auras
	if not list then
		return true
	end
	local complete = true
	for index = 1, #list do
		local row = list[index]
		row.frame:Hide()
		if not Unsweep(row) then
			complete = false
		end
	end
	return complete
end

-- One pass, off UnitFrames/Paint.lua's, which runs when UNIT_AURA said this
-- unit's list moved and once a second behind that. Both halves are here: the
-- sweep of the client's own buttons and the fill of ours. The sweep belongs on
-- the same pass rather than on its own clock because the client builds
-- BuffButton9 the first time you carry nine buffs, which is an aura event. A
-- switch under `/wk hide` that moves is picked up by the reading behind the
-- events, so it takes up to a second rather than up to a fifth of one.
function Auras.Update(entry)
	local list = entry.auras
	if not list or not entry.styled then
		return
	end
	local unit, now = entry.spec.unit, GetTime()
	Hang(list)
	for index = 1, #list do
		local row = list[index]
		Groom(row)
		if row.wanted > 0 then
			Fill(row, unit, now)
		end
	end
end

-- What sits between the block and the first row, or nothing. Called by
-- UnitFrames/Block.lua's Perch, which is the only thing that knows whether
-- target of target is currently parked on the corner these rows hang from.
function Auras.Under(entry, frame)
	local list = entry and entry.auras
	if not list or list.perch == frame then
		return
	end
	list.perch = frame
	list.head = nil
end

-- What square one actually came out as, measured off the widget rather than
-- read back out of the numbers that went into it.
--
-- It is here because of the one failure the placement numbers cannot see. The
-- timer is a font string and draws off its own anchor whatever the square does,
-- while the art and the hairline are regions sized by the square's own edges.
-- So a square that is not the size it was asked for still shows its number in
-- roughly the right place and shows nothing else, and every number in the rest
-- of this line is the number that was asked for rather than the one the client
-- used. Three measurements settle it: how wide the square came out, how wide
-- the art inside it came out, and whether the art was ever handed a texture.
--
-- In pixels, like the rest of the line, so the answer can be read against
-- `/wk skin aura` without converting anything.
local function Drawn(row)
	local square = row.squares[1]
	if not square then
		return "no square built"
	end
	local unit = ns.UI.Unit(row.frame)
	if not unit or unit <= 0 then
		unit = 1
	end
	return ("square %.1fpx, art %.1fpx %s, hairline %.2fpx"):format(
		(ns.Measure(square, "GetWidth") or 0) / unit,
		(ns.Measure(square.icon, "GetWidth") or 0) / unit,
		square.shownIcon and "held" or "none",
		(ns.Measure(square.edges[1], "GetHeight") or 0) / unit)
end

-- One line for /wk skin probe, per frame that has rows.
function Auras.Probe(entry)
	local list = entry.auras
	if not list then
		return nil
	end
	local parts = {}
	for index = 1, #list do
		local row = list[index]
		parts[index] = ("%s %d of %d wide, %s, %d of the client's hidden")
			:format(row.key, row.wanted, row.perLine, Drawn(row), Swept(row))
	end
	return table.concat(parts, ", ")
end

function Auras.Describe()
	if not ns.db.skinAuras then
		return "no aura rows on the player or the target: each frame is its"
			.. " block, so a row would land inside the gauge"
	end
	return ("aura rows on both blocks at %dpx, every debuff and buff the client"
		.. " reports, wrapping away from the block"):format(ns.db.skinAuraSize)
end

-- What the size may be set to, so the slash word and the panel offer the same
-- range and neither has to repeat the numbers.
function Auras.SizeRange()
	local block = ns.db.skinHeight or SIZE_CEILING
	return SIZE_MIN, math.max(math.min(block, SIZE_CEILING), SIZE_MIN)
end
