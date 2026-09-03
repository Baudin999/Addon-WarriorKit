local ADDON, ns = ...

local Paint = {}
ns.FramePaint = Paint

--------------------------------------------------------------------------
-- The tick
--
-- One pass over one skinned block: the colours off the unit, the four numbers,
-- the incoming heal, and the two things Blizzard writes back over.
--
-- Run when UnitFrames/Skin.lua says the unit moved, and once a second behind
-- that whatever the client has said. It used to run five times a second on
-- every block whatever had happened, because the head of this file said the
-- event names that carry health and power have been renamed between these two
-- clients and a missed one is a bar that lies. The names are checked against
-- Blizzard's own frames now and the note over Skin.lua's WATCHED is what they
-- came back as.
--
-- Everything here takes a unit token and nil guards, because anything a ticker
-- does has to be incapable of raising. Every write is guarded on the value
-- already on the frame, because a SetText or a SetColorTexture costs a measure
-- and a relayout whether or not the value changed, and a player at full health
-- is the common case.
--
-- Nothing here decides a rectangle. UnitFrames/Block.lua worked all of those
-- out at layout time and left the answers on the entry, which is why this file
-- reads entry.railPixels and entry.pixel rather than measuring anything.
--
-- All of the colour is ns.Unit.Color's. What used to be in here was a class
-- colour cache, a reaction ladder and a level tag cache, and every one of the
-- three had a twin in UnitFrames/EnemyBars.lua. The two class caches even
-- disagreed about the shape of an answer, one returning a table and one a hex
-- string, which is what happens when the same thing is written twice by the
-- same person a month apart.
--------------------------------------------------------------------------

local Unit = ns.Unit
local Color = Unit.Color
local Level = Unit.Level
local Gauge = ns.UI.Gauge
local IDLE = Color.reaction.idle

-- What the level tag reads as on something that is not a kill. The XP scale is
-- an answer to "what is this worth", and your own frame and a friendly target
-- are not asking it: painting them even yellow would be a number claiming to
-- be a reward.
local PLAIN_LEVEL = Color.text.value

local UnitCanAttack = UnitCanAttack

-- The portrait render carries dead space around the head. Blizzard hides it
-- under the ring; with the ring gone it has to be cropped instead.
--
-- Written as a fraction of 64 rather than as a decimal, for the reason
-- UI/Draw.lua crops an icon at 5/64: a portrait is sampled art, and a crop
-- that lands between two texels makes the sampler interpolate across the whole
-- image to find the edge. 0.15 cut 9.6 texels. Ten is the nearest boundary,
-- and 10/64 is exact in binary as well, which is what lets the tick compare
-- what it reads back against what it wrote.
local PORTRAIT_TRIM = 10 / 64

-- The slice of the gauge an incoming heal is about to fill, drawn from where
-- the bar stops to where it is headed.
--
-- Pinned to the health bar's own fill texture rather than measured along the
-- rail. The fill's inner edge is exactly where the bar stops, whichever end the
-- client fills from and whatever the scale between us comes to, so the slice
-- starts on the fill rather than a pixel off it and stands as tall as the bar
-- without this file having to know how tall that is. The width is ours, in
-- whole pixels, the same way every other number here is.
--
-- Every write is guarded on the span last drawn. This runs five times a second
-- on three frames, and on all three the common case is that nobody is healing
-- anybody, which should cost a comparison and nothing else.
local function HealSlice(entry, span)
	local slice = entry.healSlice
	local bar = entry.healthbar
	local fill = bar and bar.GetStatusBarTexture and bar:GetStatusBarTexture()
	if not fill then
		span = 0
	end
	-- Re-pinned only when the client hands back a different texture object.
	-- That is the readback Flatten does, for the reason Flatten gives. A cached
	-- one would be pointing at nothing.
	if fill and entry.healAnchor ~= fill then
		entry.healAnchor = fill
		local mine = entry.healReverse and "RIGHT" or "LEFT"
		local theirs = entry.healReverse and "LEFT" or "RIGHT"
		slice:ClearAllPoints()
		slice:SetPoint("TOP" .. mine, fill, "TOP" .. theirs, 0, 0)
		slice:SetPoint("BOTTOM" .. mine, fill, "BOTTOM" .. theirs, 0, 0)
	end
	if entry.healSpan == span then
		return
	end
	entry.healSpan = span
	if span > 0 then
		slice:SetWidth(span * entry.pixel)
		slice:Show()
	else
		slice:Hide()
	end
end

-- The level tag, and what the kill is worth.
--
-- Guarded on the string, which ns.Unit.Level hands over already built rather
-- than building one per tick to compare, and on the colour table's identity the
-- way every other colour on this frame is.
--
-- The colour is the newer half. This frame drew the level in one flat shade for
-- its whole life while the nameplates beside it carried the XP scale on the
-- same two characters, so the one mob you had actually picked was the one the
-- addon would not price. Grey here is the plate's grey: the kill pays nothing,
-- because the mob is too far below you or because somebody else tagged it.
--
-- Only on something you can attack. Your own frame and a friendly target are
-- not asking what a kill is worth, and an even yellow on those two is a reward
-- being claimed where there is none.
local function PaintLevel(entry, unit)
	local tag, xp = Level.Of(unit)
	if not UnitCanAttack("player", unit) then
		xp = PLAIN_LEVEL
	end
	if entry.levelTag ~= tag then
		entry.levelTag = tag
		entry.levelText:SetText(tag)
	end
	if entry.levelColor ~= xp then
		entry.levelColor = xp
		entry.levelText:SetTextColor(xp[1], xp[2], xp[3])
	end
end

-- The two things Blizzard writes back over, put back.
--
-- Both are re-applied rather than set once, because the bars and the portrait
-- are Blizzard's and their own code puts a texture and a crop on them whenever
-- it swaps the art underneath.
--
-- The bars are asked only when something has asked for them. UnitFrames/Skin.lua
-- hooks SetStatusBarTexture on both, which is the only call that can swap a
-- status bar's fill, so the hook says exactly when the answer changed and the
-- four readbacks this used to make on every pass are gone. Where the hook could
-- not be installed `barsHooked` is false, the flag never comes down, and both
-- bars are read back on every pass the way they always were.
--
-- The portrait keeps its readback and has to. Blizzard swaps the render through
-- SetPortraitTexture, which is handed the texture and writes it from the C side
-- without going through any method an addon can hook, so there is nothing to be
-- told by and one comparison is the whole cost.
--
-- That comparison is exact because the crop is a power of two fraction. A crop
-- written as 0.15 would come back as whatever the client rounded it to and the
-- guard would never hold.
local function Writeback(entry)
	if entry.flatten then
		entry.flatten = not entry.barsHooked
		Gauge.Flatten(entry.healthbar)
		Gauge.Flatten(entry.manabar)
	end
	local portrait = entry.portrait
	if portrait then
		local left = portrait.GetTexCoord and portrait:GetTexCoord()
		if left ~= PORTRAIT_TRIM then
			portrait:SetTexCoord(PORTRAIT_TRIM, 1 - PORTRAIT_TRIM,
				PORTRAIT_TRIM, 1 - PORTRAIT_TRIM)
		end
	end
end

function Paint.Refresh(entry)
	local unit = entry.spec.unit
	if not entry.styled or not UnitExists(unit) then
		return
	end

	local tint = Color.OfUnit(unit)
	if entry.tint ~= tint then
		entry.tint = tint
		Gauge.Paint(entry.healthbar, entry.healthTrack, tint)
		local edge = Color.Dim(tint, Color.edgeDim)
		ns.Recolor(entry.box.edges, edge)
		entry.divider:SetColorTexture(edge[1], edge[2], edge[3], 1)
	end

	local shownPower, maxPower, powerType = Unit.Power(unit)
	local power = (maxPower > 0 and Color.power[powerType]) or IDLE
	if entry.power ~= power then
		entry.power = power
		Gauge.Paint(entry.manabar, entry.powerTrack, power)
	end

	-- Compared as the integers that get drawn, the same way the enemy bars do
	-- it. A SetText costs a string measure and a relayout whether or not the
	-- text changed, and a player at full health is the common case.
	local health, maxHealth, percent = Unit.Health(unit)
	if entry.shownPercent ~= percent then
		entry.shownPercent = percent
		entry.healthText:SetText(percent >= 0 and (percent .. "%") or "")
	end

	-- Incoming heals, in whole pixels of the rail, measured from where the
	-- fill stops. Clamped to what is missing: a 2,000 heal landing on a warrior
	-- who is down 300 would otherwise run off the end of the gauge, and a slice
	-- that overshoots the bar is saying something untrue about both numbers.
	-- Nil out of ns.IncomingHeals is a client with no prediction at all, and it
	-- takes the same road as a quiet moment, which is to draw nothing.
	local span = 0
	if ns.db.skinHeals and maxHealth > 0 and health > 0 then
		local incoming = ns.IncomingHeals(unit) or 0
		if incoming > 0 then
			local missing = maxHealth - health
			if incoming > missing then
				incoming = missing
			end
			span = math.floor(incoming / maxHealth * entry.railPixels + 0.5)
		end
	end
	HealSlice(entry, span)

	-- -1 rather than 0 for a unit with no power bar at all, so "empty" and
	-- "has none" guard apart. Most of what you fight has none.
	local drawnPower = maxPower > 0 and shownPower or -1
	if entry.shownPower ~= drawnPower then
		entry.shownPower = drawnPower
		entry.powerText:SetText(drawnPower >= 0 and tostring(drawnPower) or "")
	end

	local name = UnitName(unit) or ""
	if entry.shownName ~= name then
		entry.shownName = name
		entry.nameText:SetText(name)
	end

	PaintLevel(entry, unit)

	Writeback(entry)

	-- The aura rows, which come along on the same pass. UNIT_AURA is one of the
	-- four events that mark this block, so a target gaining a debuff is a row
	-- redrawn a fifth of a second later and a target standing still is a row
	-- nothing reads. Everything it does is guarded in there.
	ns.FrameAuras.Update(entry)
end
