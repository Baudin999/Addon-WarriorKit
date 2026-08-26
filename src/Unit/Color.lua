local ADDON, ns = ...

local Unit = ns.Unit
local Color = {}
Unit.Color = Color

--------------------------------------------------------------------------
-- The unit palette
--
-- Every colour two or more parts of the addon put on a unit. Not the same
-- palette as ns.UI.Color, which dresses windows and controls: this one is the
-- look of the game world and it answers questions the interface never asks,
-- like what a mob thinks of you.
--
-- It exists because it was written twice. UnitFrames/EnemyBars.lua declared
-- five colours for threat and UnitFrames/Skin.lua declared four for reaction,
-- and four of the nine were the same three literals typed out again. That is
-- fine until somebody warms the green, at which point the mob's bar and your
-- target frame stop agreeing about what friendly looks like and nothing in the
-- build can tell.
--
-- Two layers, and the split is the point. HUE is the set of colours the addon
-- draws with, named for what they are. Everything under it maps a question the
-- game asks onto one of them, named for what it means. A green that appears in
-- two answers is the same table in both, because it is the same green, and one
-- edit moves both.
--
-- Handing back a shared table is not a leak, it is the contract. See the note
-- in Unit/Unit.lua: the tickers guard their widget writes on colour identity,
-- so the same state has to answer the same table every time. Nothing in this
-- file builds a colour at call time and nothing may start.
--------------------------------------------------------------------------

local HUE = {
	green  = { 0.20, 0.72, 0.38 },
	amber  = { 0.95, 0.77, 0.25 },
	orange = { 0.98, 0.55, 0.20 },
	red    = { 0.88, 0.25, 0.28 },
	slate  = { 0.42, 0.45, 0.52 },

	-- The XP scale, which is the client's own quest scale. Deliberately not the
	-- threat greens and ambers even where they are close: the two scales say
	-- different things and a bar carrying both in one colour says neither.
	grey   = { 0.55, 0.56, 0.60 },
	lime   = { 0.35, 0.85, 0.35 },
	yellow = { 1.00, 0.92, 0.25 },
	gold   = { 1.00, 0.62, 0.25 },
	coral  = { 1.00, 0.35, 0.32 },

	-- Hostile is the deep one because it is what nearly everything on screen
	-- is, and a third bright red beside threat red and five-levels-up red would
	-- be one red too many. Neutral is the exception worth seeing across a room.
	blood   = { 0.55, 0.12, 0.12 },
	warning = { 0.95, 0.75, 0.15 },

	-- The cast bar's own, and it is deliberately none of the above. The gauge
	-- over it carries threat, which is the green through red scale, and the tag
	-- beside it carries the XP scale, which is those same five again meaning
	-- something else. A cast bar in any of them would read as a third opinion
	-- about the mob's health.
	violet = { 0.62, 0.45, 0.95 },
}

Color.hue = HUE

-- The surfaces. Flat fills, one pixel edges, no gloss and no gradient, and no
-- file path anywhere, so there is no art asset that has to still exist on this
-- client.
Color.backdrop = { 0.04, 0.04, 0.05, 0.85 }
Color.plate    = { 0.03, 0.03, 0.04, 0.95 } -- the level tag's own chip
Color.iconEdge = { 0, 0, 0, 0.90 }

-- What the spent part of a bar keeps of its own colour. A mob at ten percent
-- still reads as yours rather than as an empty box.
Color.track = 0.20

-- What an edge keeps of the fill's colour. At full strength a hostile target
-- ringed the whole block in saturated red and the border shouted louder than
-- anything inside it. The fill carries the colour, the edge only has to agree.
Color.edgeDim = 0.60

Color.text = {
	name   = { 0.97, 0.97, 1.00 },
	value  = { 0.74, 0.76, 0.82 },
	target = { 1.00, 0.90, 0.55 }, -- the one that is yours
	count  = { 1.00, 0.86, 0.45 }, -- a debuff's stack number
}

-- Incoming heals, laid over the part of a gauge a heal is about to reach. Half
-- transparent, because the whole job of the slice is to read as not yours yet.
-- Green because that is what heal prediction has been in every unit frame that
-- draws it, and a colour the game has already taught beats a prettier one.
Color.heal = { 0.42, 0.86, 0.52, 0.55 }

-- Tanking colours key off how close the nearest challenger is. Not tanking is
-- always red, because the mob is on the wrong person.
Color.threat = {
	safe   = HUE.green,
	close  = HUE.amber,
	losing = HUE.orange,
	off    = HUE.red,
	idle   = HUE.slate,
}

-- What a unit thinks of you, which is the fallback for anything with no class.
Color.reaction = {
	friendly = HUE.green,
	neutral  = HUE.amber,
	hostile  = HUE.red,
	idle     = HUE.slate,
}

-- What killing it is worth, on the client's own XP scale.
Color.xp = {
	none   = HUE.grey,
	easy   = HUE.lime,
	even   = HUE.yellow,
	hard   = HUE.gold,
	deadly = HUE.coral,
}

-- Whether it comes for you on its own. Hostile mobs do inside their aggro
-- radius; neutral ones stand there until you hit them.
Color.aggro = {
	comes = HUE.blood,
	waits = HUE.warning,
	idle  = HUE.slate,
}

-- A cast running on something you can attack. Two states and not three: one you
-- can stop, and one the client says you cannot. A channel wears the same two
-- and drains from the other end, because which way the fill runs already says
-- which it is and a third colour would be a third thing to learn.
Color.cast = {
	open   = HUE.violet,
	locked = HUE.slate,
}

-- Keyed by the number UnitPowerType returns rather than by the token beside
-- it, because the number is the half that has never been renamed.
-- PowerBarColor would answer this too and is a global nothing installed here
-- calls unguarded, so the five colours live here instead.
Color.power = {
	[0] = { 0.25, 0.44, 0.90 }, -- mana
	[1] = { 0.78, 0.25, 0.22 }, -- rage
	[2] = { 1.00, 0.50, 0.25 }, -- focus
	[3] = { 0.95, 0.90, 0.35 }, -- energy
	[4] = { 0.40, 0.80, 0.90 }, -- happiness
}

--------------------------------------------------------------------------

local UnitClass = UnitClass
local UnitReaction = UnitReaction
local UnitIsPlayer = UnitIsPlayer

-- Two caches, because the two callers want two different shapes and neither
-- should pay to convert. Both are filled the first time a class is seen and
-- kept for the session: there are ten classes and the lookup below is the
-- guard the allocation scan cannot see.
local byClass = {}
local hexByClass = {}

-- The class colour as { r, g, b }, or nil for anything with no class. Nil
-- rather than white, because the caller has a reaction colour to fall back to
-- and white is a claim that this thing is a player of no class.
function Color.Class(class)
	if not class then
		return nil
	end
	local cached = byClass[class]
	if cached then
		return cached
	end
	local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	if not color then
		return nil
	end
	cached = { color.r, color.g, color.b } -- allocates: once per class, and the lookup above is the guard the scan cannot see
	byClass[class] = cached
	return cached
end

-- The same colour as the eight hex digits a chat escape wants. Separate from
-- the table above rather than formatted from it on demand, because the one
-- caller asks per group member per tick and ("ff%02x%02x%02x"):format builds a
-- string every time it is called.
--
-- White for a class this client will not colour, because a name with no colour
-- still has to be readable and this one is going into a line of text rather
-- than onto a bar.
function Color.ClassHex(class)
	if not class then
		return "ffffffff"
	end
	local cached = hexByClass[class]
	if cached then
		return cached
	end
	local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	if not color then
		return "ffffffff"
	end
	cached = ("ff%02x%02x%02x"):format(color.r * 255, color.g * 255, color.b * 255) -- allocates: once per class, and the lookup above is the guard the scan cannot see
	hexByClass[class] = cached
	return cached
end

-- What a unit thinks of you, as one of the four reaction colours. 4 is
-- neutral, under it is hostile, over it does not fight you at all.
function Color.Reaction(unit)
	local reaction = UnitReaction(unit, "player")
	if not reaction then
		return Color.reaction.idle
	end
	if reaction >= 5 then
		return Color.reaction.friendly
	end
	return reaction == 4 and Color.reaction.neutral or Color.reaction.hostile
end

-- Whether it comes for you unprompted. The reaction is the whole question and
-- the whole answer; what it cannot tell you is aggro radius, which shrinks as
-- the mob falls behind your level.
function Color.Aggro(unit)
	local reaction = UnitReaction(unit, "player")
	if not reaction or reaction >= 5 then
		return Color.aggro.idle
	end
	return reaction == 4 and Color.aggro.waits or Color.aggro.comes
end

-- The colour a unit's own gauge wears. A player wears their class; anything
-- else has no class and falls back to what it thinks of you.
function Color.OfUnit(unit)
	if UnitIsPlayer(unit) then
		local _, class = UnitClass(unit)
		local tint = Color.Class(class)
		if tint then
			return tint
		end
	end
	return Color.Reaction(unit)
end

-- A colour at a fraction of its brightness, written into one scratch table
-- rather than allocated, because every caller is on a ticker.
--
-- The scratch is shared and is overwritten by the next call. That is safe for
-- the one shape any caller uses, which is to hand the result straight to a
-- SetColorTexture or an ns.Recolor and never keep it. Keeping it is a bug this
-- file cannot catch, so do not.
local SCRATCH = { 0, 0, 0 }

function Color.Dim(color, factor)
	SCRATCH[1], SCRATCH[2], SCRATCH[3] = color[1] * factor, color[2] * factor, color[3] * factor
	return SCRATCH
end
