local ADDON, ns = ...

local Auras = {}
ns.FrameAuras = Auras

--------------------------------------------------------------------------
-- The target's aura rows
--
-- Two rows of squares under the target block: what the target is bleeding
-- from, and what is helping it. Ours, out of C_UnitAuras with the UnitAura
-- fallback every other aura reader in this addon uses, drawn with UI/Aura.lua
-- and laid out by ns.UI.Flow.
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
-- The player is not here. Blizzard does not hang your own buffs off PlayerFrame
-- at all; they are BuffFrame, a top level Edit Mode system of its own carrying
-- thirty-two buffs, sixteen debuffs, three temporary weapon enchants and right
-- click to cancel, and none of the payoff above is on that side. What this
-- addon has to say about your own buffs is Buffs/Nag.lua's, which reads
-- GetWeaponEnchantInfo as well as your auras and so can see the sharpening
-- stone that no aura scan reports. Adding the player later is one entry in
-- ROWS below and an answer to the BuffFrame question, in that order.
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
-- Debuffs first, nearest the block. This is a warrior's addon and the target's
-- debuffs are the row it is for: your Rend, your Sunder stacks, Demoralizing
-- Shout still up. What is helping the target is worth knowing and is worth
-- knowing second.
--
--   filter    what the client calls this half of the aura list
--   head      the client's own button names, which are what gets hidden
--   ceiling   how many of those the client will ever build
--   setting   how many of ours to draw
--   global    what this row is called, for the reason UnitFrames/Skin.lua
--             names the block: a row that lands in the wrong place can then be
--             measured from a macro or from the harness without this file
--             handing out a reference to its own tables
local ROWS = {
	target = {
		{ key = "debuffs", filter = "HARMFUL", head = "TargetFrameDebuff",
			ceiling = 16, setting = "skinAuraDebuffs",
			global = "WarriorKitTargetDebuffs" },
		{ key = "buffs", filter = "HELPFUL", head = "TargetFrameBuff",
			ceiling = 32, setting = "skinAuraBuffs",
			global = "WarriorKitTargetBuffs" },
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
-- Hiding the client's row
--
-- The buttons are built on demand: the client makes TargetFrameDebuff5 the
-- first time a target carries five debuffs, and never before. So this cannot be
-- a walk done once at style time, and it must not be a walk of all forty-eight
-- names on every tick either.
--
-- It is neither. The buttons are built in order, so the only one that can have
-- appeared since the last look is the one after the last one hidden. That is a
-- single global lookup per row per tick once the row has settled, and a run of
-- them the first time a target turns up with a full list.
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

-- How tall a row of `lines` is, with the gap that separates it from whatever is
-- above it folded into its own height. That is what lets an empty row cost
-- nothing: with no debuffs on the target the buff row sits against the block
-- rather than one gap below where the debuffs would have been.
local function Height(row, lines)
	if lines < 1 then
		return row.px
	end
	return row.gap + lines * row.side + (lines - 1) * row.gap
end

-- What the first row hangs off, which is not always the block.
--
-- Target of target is parked on exactly the corner these rows hang from, three
-- pixels under the block, so while it is there the rows go under it and while
-- it is not they go against the block. Guarded on the frame itself, so this is
-- one comparison a tick until that frame is shown or hidden, which happens
-- when the target picks something up or drops it.
--
-- It has to be on the ticker rather than at layout because the client shows
-- and hides that frame with the unit, and a target with nothing targeted would
-- otherwise leave a hole the size of it above the debuffs. Writing it here is
-- allowed in combat where re-anchoring target of target itself is not: this
-- frame is ours.
local function Hang(list)
	local perch = list.perch
	local head = (perch and perch:IsShown()) and perch or list.box
	if list.head ~= head then
		list.head = head
		local first = list[1].frame
		first:ClearAllPoints()
		first:SetPoint(list.edge, head, list.corner, 0, 0)
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

	-- The row's own height, which is the whole of what the tick moves. Every
	-- square was placed once at layout and none of them moves again, so a row
	-- that grows from one line to two only has to tell whatever hangs under it.
	local lines = math.ceil(count / row.perLine)
	if row.lines ~= lines then
		row.lines = lines
		row.frame:SetHeight(Height(row, lines))
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
		local ceiling = spec.ceiling
		if spec.filter == "HARMFUL" then
			ceiling = _G.MAX_TARGET_DEBUFFS or ceiling
		else
			ceiling = _G.MAX_TARGET_BUFFS or ceiling
		end
		for slot = 1, ceiling do
			names[slot] = spec.head .. slot
		end

		list[index] = {
			key = spec.key, filter = spec.filter, setting = spec.setting,
			frame = frame, squares = {}, found = {},
			names = names, ceiling = ceiling, stripped = {}, swept = 0,
			wanted = 0, perLine = 1, lines = nil,
			side = 0, gap = 0, px = 1,
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

	local corner = "BOTTOM" .. (mirror and "RIGHT" or "LEFT")
	local edge = "TOP" .. (mirror and "RIGHT" or "LEFT")
	-- Where the chain starts, and the two points it is chained by. Kept on the
	-- list because Hang re-anchors the first row on the ticker and must not
	-- work either of them out again.
	list.box, list.edge, list.corner = entry.box, edge, corner
	list.head = nil

	local above = entry.box
	for index = 1, #list do
		local row = list[index]
		local unit = ns.UI.Unit(row.frame)
		row.side, row.gap, row.px = square, gap, px
		row.wanted = on and math.max(math.min(ns.db[row.setting] or 0, row.ceiling), 0) or 0

		-- Wrapped, and packed to the same corner the block's portrait is on.
		-- `reverse` runs the row backwards and `justify` puts a part filled line
		-- against that same edge, which between them are the whole of the
		-- mirroring: with neither, a short line on the target would hug the
		-- corridor side and the full lines above it would not.
		local node = {
			direction = "row", wrap = true, width = width, gap = gap,
			reverse = mirror, justify = mirror and "end" or "start",
			pad = { 0, gap, 0, 0 },
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
		row.frame:SetPoint(edge, above, corner, 0, 0)
		row.frame:SetWidth(width)
		Flow.Arrange(row.frame, node)

		-- How many fit on a line, asked of Flow rather than worked out again
		-- here, so there is one rule for where a line breaks and not two that
		-- agree until somebody changes the gap.
		local lines = Flow.Lines(node)
		row.perLine = math.max(lines[1] and #lines[1] or 0, 1)
		-- The tick guards the row's height against the height it last wrote,
		-- and that height is now a different number of pixels.
		row.lines = nil

		row.frame:SetShown(on and row.wanted > 0)
		above = row.frame
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
		row.lines = nil
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
		return "no aura row on the target: the frame is the block, so the"
			.. " client's own row would land inside the gauge"
	end
	return ("target auras at %dpx, %d debuffs and %d buffs")
		:format(ns.db.skinAuraSize, ns.db.skinAuraDebuffs, ns.db.skinAuraBuffs)
end

-- What the two settings may be set to, so the slash word and the panel offer
-- the same range and neither has to repeat the numbers.
function Auras.SizeRange()
	return SIZE_MIN, SIZE_MAX
end

function Auras.CountCeiling(key)
	local plan = ROWS.target
	for index = 1, #plan do
		if plan[index].key == key then
			return plan[index].ceiling
		end
	end
	return 0
end
