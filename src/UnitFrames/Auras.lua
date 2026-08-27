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
-- to it rather than assuming. ns.Strip refuses on a protected region in combat
-- and says so by returning false, so a button the client builds mid fight is
-- retried on the next tick and lands the moment combat drops. Whether these
-- buttons are protected at all on this hybrid client is in the untested list in
-- docs/README.md, because the honest answer is that nobody has watched a target
-- gain its ninth debuff in a raid yet.
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
-- the same way on demand. Two things this addon does not take off the screen.
-- Right click to cancel a buff goes with the client's row, because cancelling
-- one is a protected call and a square drawn here cannot make it. And the
-- temporary weapon enchant stays where the client draws it: it appears at no
-- aura index at all, so nothing below can find it, and Buffs/Nag.lua only says
-- when the sharpening stone is missing rather than how long the one on your
-- weapon has left.
--------------------------------------------------------------------------

local Aura = ns.UI.Aura
local Flow = ns.UI.Flow

-- Between two squares, and between the block and the first row. In pixels,
-- like every other number the skin draws with.
local GAP = 3

-- What the square's edge may be set to. The floor is where the stack count
-- stops being readable and the ceiling is the block's own default height, above
-- which the row is taller than the frame it hangs under.
local SIZE_MIN, SIZE_MAX = 12, 32

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
--   setting   how many of ours to draw
--   global    what this row is called, for the reason UnitFrames/Skin.lua
--             names the block: a row that lands in the wrong place can then be
--             measured from a macro or from the harness without this file
--             handing out a reference to its own tables
local ROWS = {
	player = {
		{ key = "debuffs", filter = "HARMFUL", head = "DebuffButton", below = true,
			max = "DEBUFF_MAX_DISPLAY", ceiling = 16,
			setting = "skinAuraDebuffs", global = "WarriorKitPlayerDebuffs" },
		{ key = "buffs", filter = "HELPFUL", head = "BuffButton", below = false,
			max = "BUFF_MAX_DISPLAY", ceiling = 32,
			setting = "skinAuraBuffs", global = "WarriorKitPlayerBuffs" },
	},
	target = {
		{ key = "debuffs", filter = "HARMFUL", head = "TargetFrameDebuff", below = true,
			max = "MAX_TARGET_DEBUFFS", ceiling = 16,
			setting = "skinAuraDebuffs", global = "WarriorKitTargetDebuffs" },
		{ key = "buffs", filter = "HELPFUL", head = "TargetFrameBuff", below = false,
			max = "MAX_TARGET_BUFFS", ceiling = 32,
			setting = "skinAuraBuffs", global = "WarriorKitTargetBuffs" },
	},
}

--------------------------------------------------------------------------
-- Reading the client
--------------------------------------------------------------------------

-- One aura slot, whichever API this client has. The shape is EnemyBars.lua's,
-- because it is the same question asked of a mob rather than of your target,
-- and the positional read of UnitAura is the only way that call can be read on
-- 2.5.6: name is first, the icon second, the stack count third, the expiry
-- sixth and the caster seventh.
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
		return aura.name, aura.icon, aura.expirationTime, aura.applications,
			aura.sourceUnit
	end
	if type(UnitAura) ~= "function" then
		return nil
	end
	local name, icon, count, _, _, expires, source = UnitAura(unit, index, filter)
	return name, icon, expires, count, source
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
local function Scan(row, unit)
	local wanted = row.wanted
	if wanted < 1 or not UnitExists(unit) then
		return 0
	end

	local found, filter, taken = row.found, row.filter, 0
	for pass = 1, 2 do
		local index = 1
		while taken < wanted do
			local name, icon, expires, count, source = AuraAt(unit, index, filter)
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
				slot.count, slot.mine, slot.index = count or 0, mine, index
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
-- single global lookup per row per tick once the row has settled, and a run of
-- them the first time a unit turns up with a full list.
--
-- A name this client does not use costs nothing and hides nothing, which is
-- the honest failure: the sweep stops at the first name that is not a frame
-- and /wk skin probe then says none of the client's are hidden. Whether these
-- four names are what this backport calls its own buttons is in the untested
-- list in docs/README.md.
--------------------------------------------------------------------------

-- False when combat refused, which is the caller's signal to try again at
-- PLAYER_REGEN_ENABLED rather than to eat a lockdown error.
local function Sweep(row)
	while row.swept < row.ceiling do
		local button = _G[row.names[row.swept + 1]]
		if not button then
			return true -- the client has not built this one yet
		end
		if not ns.Strip(button) then
			return false
		end
		row.stripped[button] = true
		row.swept = row.swept + 1
	end
	return true
end

local function Unsweep(row)
	local complete = true
	for button in pairs(row.stripped) do
		if ns.Unstrip(button) then
			row.stripped[button] = nil
		else
			complete = false
		end
	end
	-- Reset whether or not every one came back. ns.Strip is a no-op on a region
	-- it already holds, so a sweep that starts again from one costs a table
	-- lookup per button that never came back and cannot double-strip anything.
	row.swept = 0
	return complete
end

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
	local count = Scan(row, unit)

	for slot = 1, count do
		local found = row.found[slot]
		local square = squares[slot]
		square.auraIndex = found.index
		Aura.Draw(square, found.icon, found.mine and "mine" or "theirs",
			found.expires, found.count, now)
		if not square:IsShown() then
			square:Show()
		end
	end
	for slot = count + 1, #squares do
		local square = squares[slot]
		if square:IsShown() then
			square.auraIndex = nil
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
	square:SetScript("OnEnter", function(self)
		if not self.auraIndex or type(GameTooltip) ~= "table" then
			return
		end
		local setter = filter == "HARMFUL" and GameTooltip.SetUnitDebuff
			or GameTooltip.SetUnitBuff
		if type(setter) ~= "function" then
			return
		end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		setter(GameTooltip, unit, self.auraIndex)
		GameTooltip:Show()
	end)
	square:SetScript("OnLeave", function()
		if type(GameTooltip) == "table" and type(GameTooltip.Hide) == "function" then
			GameTooltip:Hide()
		end
	end)
end

-- One frame per row, parented to the unit frame so it hides with it. Nothing
-- is anchored or sized here: where a row goes is Auras.Place's, and how many
-- squares it holds is a setting that moves while the addon is up.
--
-- On the grid, like the three frames UnitFrames/Skin.lua builds beside it, so
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
		local names = {}
		local ceiling = _G[spec.max] or spec.ceiling
		for slot = 1, ceiling do
			names[slot] = spec.head .. slot
		end

		list[index] = {
			key = spec.key, filter = spec.filter, setting = spec.setting,
			below = spec.below, frame = frame, squares = {}, found = {},
			names = names, ceiling = ceiling, stripped = {}, swept = 0,
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
	local asked = ns.db.skinAuraSize or SIZE_MIN
	local side = math.floor(math.max(math.min(asked, SIZE_MAX), SIZE_MIN) + 0.5)
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
			Aura.Size(held, square, px,
				math.floor(TIMER_CEILING * unit + 0.5),
				math.floor(COUNT_CEILING * unit + 0.5))
			node[slot] = { frame = held, width = square, height = square }
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
-- What UnitFrames/Skin.lua calls
--------------------------------------------------------------------------

-- Hide the client's row and show ours. False where combat refused a strip, so
-- the caller can finish at PLAYER_REGEN_ENABLED like every other half of the
-- skin that a lockdown can turn down.
function Auras.Style(entry)
	local list = entry.auras
	if not list then
		return true
	end
	local complete = true
	for index = 1, #list do
		if not Sweep(list[index]) then
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
		Sweep(row)
		if row.wanted > 0 then
			Fill(row, unit, now)
		end
	end
end

-- What sits between the block and the first row, or nothing. Called by
-- UnitFrames/Skin.lua's Perch, which is the only thing that knows whether
-- target of target is currently parked on the corner these rows hang from.
function Auras.Under(entry, frame)
	local list = entry and entry.auras
	if not list or list.perch == frame then
		return
	end
	list.perch = frame
	list.head = nil
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
		parts[index] = ("%s %d of %d wide, %d of the client's hidden")
			:format(row.key, row.wanted, row.perLine, row.swept)
	end
	return table.concat(parts, ", ")
end

function Auras.Describe()
	if not ns.db.skinAuras then
		return "no aura rows on the player or the target: each frame is its"
			.. " block, so the client's own rows would land inside the gauges"
	end
	return ("aura rows under both blocks at %dpx, %d debuffs and %d buffs")
		:format(ns.db.skinAuraSize, ns.db.skinAuraDebuffs, ns.db.skinAuraBuffs)
end

-- What the two settings may be set to, so the slash word and the panel offer
-- the same range and neither has to repeat the numbers.
function Auras.SizeRange()
	return SIZE_MIN, SIZE_MAX
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
