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
--   setting   how many of ours to draw
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
			setting = "skinAuraDebuffs", global = "WarriorKitPlayerDebuffs" },
		{ key = "buffs", filter = "HELPFUL", head = "BuffButton", below = false,
			max = "BUFF_MAX_DISPLAY", ceiling = 32, enchants = true,
			hides = "hideBlizzBuffs",
			setting = "skinAuraBuffs", global = "WarriorKitPlayerBuffs" },
	},
	target = {
		{ key = "debuffs", filter = "HARMFUL", head = "TargetFrameDebuff", below = true,
			max = "MAX_TARGET_DEBUFFS", ceiling = 16, hides = "hideBlizzTargetAuras",
			setting = "skinAuraDebuffs", global = "WarriorKitTargetDebuffs" },
		{ key = "buffs", filter = "HELPFUL", head = "TargetFrameBuff", below = false,
			max = "MAX_TARGET_BUFFS", ceiling = 32, hides = "hideBlizzTargetAuras",
			setting = "skinAuraBuffs", global = "WarriorKitTargetBuffs" },
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

-- One aura slot, whichever API this client has. The shape is EnemyBars.lua's,
-- because it is the same question asked of a mob rather than of your target,
-- and the positional read of UnitAura is the only way that call can be read on
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
	local api = C_UnitAuras
	local getter
	if api then
		if filter == "HARMFUL" then
			getter = api.GetDebuffDataByIndex
		else
			getter = api.GetBuffDataByIndex
		end
	end
	if getter then
		local aura = getter(unit, index)
		if not aura then
			return nil
		end
		return aura.name, Art(aura.icon, aura.spellId), aura.expirationTime,
			aura.duration, aura.applications, aura.sourceUnit
	end
	if type(UnitAura) ~= "function" then
		return nil
	end
	local name, icon, count, _, duration, expires, source, _, _, spell =
		UnitAura(unit, index, filter)
	return name, Art(icon, spell), expires, duration, count, source
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
-- tick is the kind of garbage that shows up as a stutter on a pull rather than
-- as a number on a frame counter.
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
-- single global lookup per run per tick once the run has settled, and a run of
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

local function Fill(row, unit, now)
	local squares = row.squares
	local count = Scan(row, unit, now)

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
	ns.Tip.Hang(square, function(self)
		-- A weapon enchant answers to the hand it is on rather than to an aura
		-- index, which is the same question Blizzard's own enchant button asks:
		-- the item's tooltip carries the enchant line.
		if self.auraGear then
			return { kind = "inventory", unit = unit, slot = self.auraGear }
		end
		if not self.auraIndex then
			return nil
		end
		return { kind = filter == "HARMFUL" and "debuff" or "buff",
			unit = unit, index = self.auraIndex }
	end)
end

-- One frame per row, parented to the unit frame so it hides with it. Nothing
-- is anchored or sized here: where a row goes is Auras.Place's, and how many
-- squares it holds is a setting that moves while the addon is up.
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
			key = spec.key, filter = spec.filter, setting = spec.setting,
			below = spec.below, enchants = spec.enchants, hides = spec.hides,
			frame = frame, squares = {}, found = {},
			runs = runs, ceiling = ceiling, stripped = {},
			wanted = 0, perLine = 1,
		}
	end
	entry.auras = list
end

-- Both rows, under the block, in the units the block is drawn in.
--
-- `width` is the block's, so the row wraps against the frame it hangs under and
-- a long list grows downwards rather than off the side of the screen. `mirror`
-- is the spec's, and it is the whole of the mirroring: the row starts on the
-- corner the portrait is on and runs away from it, so the target's row reads
-- outward from its own edge exactly as the block inside it does.
--
-- Every square is placed once, here, for the longest the row is allowed to be.
-- The tick shows a prefix of them and never moves one. That is what keeps
-- ns.UI.Flow off the ticker, which is the boundary the head of UI/Flow.lua
-- draws and check.sh enforces.
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
		local unit = ns.UI.Unit(row.frame)
		row.wanted = on and math.max(math.min(ns.db[row.setting] or 0, row.ceiling), 0) or 0
		row.edge = (row.below and "TOP" or "BOTTOM") .. hand
		row.corner = (row.below and "BOTTOM" or "TOP") .. hand

		-- Wrapped, packed to the gauge end, and growing away from the block.
		--
		-- `reverse` runs the row backwards and `justify` puts a part filled
		-- line against the same edge the full ones start from, which between
		-- them are the whole of the mirroring: with neither, a short line on
		-- the target would hug one side and the full lines would hug the other.
		-- `lineOrder` is what keeps line one against the block whichever side
		-- of it the row is on, so a row that grows grows outward and the line
		-- you read first never moves.
		local node = {
			direction = "row", wrap = true, width = width, gap = gap,
			reverse = not mirror, justify = mirror and "start" or "end",
			lineOrder = row.below and "down" or "up",
			pad = row.below and { 0, gap, 0, 0 } or { 0, 0, 0, gap },
		}
		for slot = 1, row.wanted do
			local held = row.squares[slot]
			if not held then
				held = Aura.New(row.frame)
				Hover(held, entry.spec.unit, row.filter)
				row.squares[slot] = held
			end
			-- The height is what comes back rather than the square, because the
			-- number stands over the art now and the widget is taller than it
			-- is wide. UI/Aura.lua is the only file that knows by how much.
			local wide, tall = Aura.Size(held, square, px,
				math.floor(TIMER_CEILING * unit + 0.5),
				math.floor(COUNT_CEILING * unit + 0.5))
			node[slot] = { frame = held, width = wide, height = tall }
		end
		for slot = row.wanted + 1, #row.squares do
			row.squares[slot]:Hide()
		end

		row.frame:ClearAllPoints()
		row.frame:SetPoint(row.edge, entry.box, row.corner, 0, 0)
		row.frame:SetWidth(width)
		-- Sized to the longest the row is allowed to be and left at it. The
		-- tick draws a prefix of the squares and moves none of them, and
		-- nothing hangs off a row any more, so a height that changed with the
		-- count would buy nothing and would cost the row above the block every
		-- square it had: those are placed against the frame's bottom edge, and
		-- that edge is the one an anchor on the block's top holds still.
		Flow.Arrange(row.frame, node)

		-- How many fit on a line, asked of Flow rather than worked out again
		-- here, so there is one rule for where a line breaks and not two that
		-- agree until somebody changes the gap. Only /wk skin probe reads it.
		local lines = Flow.Lines(node)
		row.perLine = math.max(lines[1] and #lines[1] or 0, 1)

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

-- The tick, off UnitFrames/Skin.lua's. Both halves are here rather than on an
-- event for the reason the head of that file gives for reading health on a
-- ticker: the event names that carry auras have been renamed between these two
-- clients and a missed one is a row that lies.
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
	return ("aura rows under both blocks at %dpx, %d debuffs and %d buffs")
		:format(ns.db.skinAuraSize, ns.db.skinAuraDebuffs, ns.db.skinAuraBuffs)
end

-- What the two settings may be set to, so the slash word and the panel offer
-- the same range and neither has to repeat the numbers.
function Auras.SizeRange()
	local block = ns.db.skinHeight or SIZE_CEILING
	return SIZE_MIN, math.max(math.min(block, SIZE_CEILING), SIZE_MIN)
end

-- The most of one kind of aura any frame will draw, which is what the slash
-- word and the panel stepper clamp to. Read across every frame rather than off
-- the target's, so a row given a longer ceiling than the others cannot end up
-- with a setting that refuses to reach it.
function Auras.CountCeiling(key)
	local most = 0
	for _, plan in pairs(ROWS) do
		for index = 1, #plan do
			local spec = plan[index]
			if spec.key == key and spec.ceiling > most then
				most = spec.ceiling
			end
		end
	end
	return most
end
