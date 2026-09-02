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

--------------------------------------------------------------------------
-- Contrast
--
-- Which colours may carry text, and which colour that text is.
--
-- This arrived from a screenshot: the player frame drew a white name on the
-- warrior tan, and the two did not hold apart. They were never going to. Tan is
-- #C79C6E, white on it is 2.4:1, and the whole palette was the same shape.
-- White on the threat amber is 1.6:1, on the threat green 2.4:1, on the orange
-- 2.3:1. Only the red and the slate were over four. Every bar this addon draws
-- was carrying a name it was fighting.
--
-- Blizzard's numbers are not wrong, they are for the other problem. A class
-- colour exists to put a player's name IN that colour against a black chat
-- window, where bright is exactly right. A bar fill is the inverse: the colour
-- is the background and the text is on top of it. Six of the nine classes are
-- too light to be a background for anything, and one of them is literally
-- white.
--
-- So the palette carries a rule rather than a pile of hand-picked pairs. Every
-- colour this addon fills a bar with is taken under a luminance ceiling, and
-- the ceiling is the value at which Color.paper clears TEXT_RATIO on it. One
-- text colour, guaranteed on every fill, at every state of the bar: the spent
-- end is the fill through Color.Dim, which is darker still, so a fill that
-- clears also clears there.
--
-- The shaping runs once at load and writes into the tables in place, so a
-- colour keeps the identity Unit/Unit.lua's tickers guard on. Scaling in linear
-- space leaves hue and saturation exactly where they were and only takes
-- brightness off, which is why the warrior still reads as tan and the threat
-- green still reads as green.
--
-- The tokens run the other way. A level tag, a stack count and the name of
-- whoever else has this mob are short coloured strings ON a fill, so they need
-- a floor rather than a ceiling, and a hue that cannot reach it is blended
-- toward white until it does. TOKEN_RATIO is three rather than four and a half
-- and that is a judgement, not a rounding: these are two digits and a percent
-- sign in a HUD, not a paragraph, and holding a five colour scale apart is half
-- of what they are for.
--------------------------------------------------------------------------

-- The sRGB transfer function, inverted. WCAG's definition, and the reason the
-- shaping below is done on these numbers rather than on the stored ones: a
-- colour halved in sRGB is not half as bright, and a scale that pretends it is
-- turns a hue as it dims it.
local function Linear(c)
	if c <= 0.04045 then
		return c / 12.92
	end
	return ((c + 0.055) / 1.055) ^ 2.4
end

local function Gamma(c)
	if c <= 0.0031308 then
		return c * 12.92
	end
	return 1.055 * c ^ (1 / 2.4) - 0.055
end

-- Relative luminance, 0 for black and 1 for white.
function Color.Luma(color)
	return 0.2126 * Linear(color[1])
		+ 0.7152 * Linear(color[2])
		+ 0.0722 * Linear(color[3])
end

-- How far apart two colours are, as WCAG counts it. 1 is the same colour and
-- 21 is black against white.
function Color.Contrast(a, b)
	local first, second = Color.Luma(a), Color.Luma(b)
	if first < second then
		first, second = second, first
	end
	return (first + 0.05) / (second + 0.05)
end

-- The one colour text is drawn in over a fill. Not pure white: a bar is a lit
-- surface and paper at 0.97 sits on it rather than glaring off it.
Color.paper = { 0.97, 0.97, 1.00 }

Color.TEXT_RATIO = 4.5  -- a name and a number, which are read
Color.TOKEN_RATIO = 3.0 -- a level tag and a stack count, which are recognised

-- Solved rather than typed. Both are one rearrangement of the contrast formula,
-- and typing the answer is how a threshold and its consequence drift apart.
local FILL_CEILING = (Color.Luma(Color.paper) + 0.05) / Color.TEXT_RATIO - 0.05
local TOKEN_FLOOR = Color.TOKEN_RATIO * (FILL_CEILING + 0.05) - 0.05

Color.fillCeiling = FILL_CEILING
Color.tokenFloor = TOKEN_FLOOR

-- Brightness off, hue untouched. Scaling the linear components by one factor is
-- the only operation that does both, and the factor is exact because luminance
-- is linear in them: to land on a target luma, scale by the ratio.
local function Darken(color)
	local luma = Color.Luma(color)
	if luma <= FILL_CEILING then
		return false
	end
	local factor = FILL_CEILING / luma
	for index = 1, 3 do
		color[index] = Gamma(Linear(color[index]) * factor)
	end
	return true
end

-- Brightness on, and hue given up only as far as it has to be. A colour whose
-- strongest channel is already 1 cannot be scaled any brighter, so this walks
-- toward white instead, which is the one direction that always arrives. The
-- coral at the deadly end of the XP scale is the case that needs it: it is
-- 1.00 0.35 0.32 and reaches the floor as a salmon, because a red that dark
-- cannot be read off a dark fill and staying red would be choosing the hue over
-- the number.
--
-- Bisection rather than a formula, because blending toward white is not linear
-- in luma and twenty steps lands inside a thousandth.
local function Brighten(color)
	if Color.Luma(color) >= TOKEN_FLOOR then
		return false
	end
	local low, high = 0, 1
	local red, green, blue = color[1], color[2], color[3]
	local probe = { red, green, blue }
	for _ = 1, 20 do
		local mid = (low + high) / 2
		probe[1] = red + (1 - red) * mid
		probe[2] = green + (1 - green) * mid
		probe[3] = blue + (1 - blue) * mid
		if Color.Luma(probe) < TOKEN_FLOOR then
			low = mid
		else
			high = mid
		end
	end
	color[1] = red + (1 - red) * high
	color[2] = green + (1 - green) * high
	color[3] = blue + (1 - blue) * high
	return true
end

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

	-- Reaction, and the pair is deliberately lopsided. Hostile is chrome: it is
	-- what nearly everything on screen is, so the frame round it has to read as
	-- structure and disappear. Neutral is the exception worth seeing across a
	-- room, so it is the only one that carries a hue at all.
	--
	-- This used to be a deep blood red against the same amber, on a five pixel
	-- stripe outside the bar. Every bar the addon draws is on something you can
	-- attack, so the red was on almost every bar, permanently, at the outermost
	-- edge of the widget. That is the loudest position on the bar paying for the
	-- one bit that is nearly always the same. A channel that is loud in the
	-- common case is noise.
	iron    = { 0.24, 0.25, 0.29 },
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
Color.iconEdge = { 0, 0, 0, 0.90 }

-- The hairline between the two chambers of an enemy bar, health above and cast
-- below. Darker than the backdrop and fully opaque, because its whole job is to
-- be the one line that says these are two readings and not one fill. Against
-- the backdrop's own 0.85 it would show the world through the seam.
Color.seam = { 0.02, 0.02, 0.03, 1 }

-- What the spent part of a bar keeps of its own colour. A mob at ten percent
-- still reads as yours rather than as an empty box.
--
-- Raised from a fifth when the enemy bars' edge stopped carrying threat. A one
-- pixel ring at full saturation was never what made aggro legible on a nearly
-- empty bar; the track was, and at a fifth it was too dim to do it alone. Three
-- tenths puts the answer across the bar's whole width instead of round its rim.
Color.track = 0.30

-- What an edge keeps of the fill's colour. At full strength a hostile target
-- ringed the whole block in saturated red and the border shouted louder than
-- anything inside it. The fill carries the colour, the edge only has to agree.
Color.edgeDim = 0.60

Color.text = {
	name   = Color.paper,
	value  = { 0.74, 0.76, 0.82 },
	target = { 1.00, 0.90, 0.55 }, -- the one that is yours

	-- An aura's time left while it is still measured in minutes, and it is the
	-- client's NORMAL_FONT_COLOR written down rather than read, for the reason
	-- the class colours below are written down: a global this addon does not
	-- own can be absent on one client or moved by another addon. Under a minute
	-- the same number is Color.paper, which is the client's rule too.
	--
	-- Not a token, and deliberately. A token is short coloured text over a fill
	-- the palette owns, held to a contrast floor against it. This one stands
	-- over the world above an icon, where there is no fill to be held to and a
	-- shadow is what makes it readable.
	duration = { 1.00, 0.82, 0.00 },

	count  = { 1.00, 0.86, 0.45 }, -- a debuff's stack number

	-- The quest badge beside an enemy bar: how many of this one you still need.
	--
	-- Gold because gold has meant "quest" in this game since 2004, and a colour
	-- the player was taught by the game beats a prettier one that has to be
	-- learned. It is the same three numbers as UI.Color.heading and it is not
	-- that entry borrowed: heading is the title of a panel section this addon
	-- painted the background of, this is a string over the world beside a mob,
	-- and the day either one moves it should move on its own.
	--
	-- Deliberately not `duration`, which is two hundredths away from it. That
	-- one is the client's NORMAL_FONT_COLOR written down for an aura's minutes,
	-- and a palette that spends one entry on two facts drifts on the first edit
	-- that meant one of them.
	quest  = { 1.00, 0.82, 0.20 },
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

-- How far along you are: the experience rail and the rested pool drawn beyond
-- its fill. The one pair of colours in this palette that is about you rather
-- than about something you are fighting.
--
-- Purple and blue because that is what this game has drawn those two bars in
-- since it shipped, which is the same argument Color.heal makes for green: a
-- colour the player has already been taught beats a prettier one. The
-- reputation rail is not here, because a standing is what a faction thinks of
-- you and Color.reaction above is already that scale.
--
-- Its own entry rather than HUE.violet, which is close enough to reuse and is
-- spoken for. That one is documented as the colour of a cast you are timing a
-- press against, and a fill that is on the screen every minute of every session
-- would spend a hue the addon keeps for the moment it matters.
Color.progress = {
	experience = { 0.55, 0.32, 0.86 },
	rested     = { 0.30, 0.52, 0.92 },
}

-- The frame round a bar, which is where reaction lives now. A departure
-- channel: hostile and friendly both draw chrome and only neutral departs from
-- it, because neutral is the one you need told before you cleave.
--
-- Friendly answers iron rather than a colour of its own, and that is not a
-- placeholder. Both halves of the enemy bars require UnitCanAttack, so no bar
-- is ever drawn on something friendly and a third colour here would be one no
-- caller can reach. Something that stopped being attackable would get the
-- quiet frame, which is the right answer for a bar that is about to go away.
Color.frame = {
	hostile = HUE.iron,
	neutral = HUE.warning,
	idle    = HUE.iron,
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
-- The classes
--
-- Ours rather than RAID_CLASS_COLORS, and the reason is not taste. A fill has
-- to be shaped before it can carry text, shaping reads the number, and a global
-- this addon does not own is one that can be absent on one of the two clients
-- or moved by another addon that got there first. The nine below are the
-- client's own values written down, so both clients draw the same bar and the
-- shaping has something to work from.
--
-- Two colours per class, answering two different questions.
--
--   tint  the identity. A name in a line of chat, which is text IN the colour
--         against a dark window, and the job Blizzard chose these numbers for.
--   fill  the bar. The same colour under the luminance ceiling, so the name on
--         top of it can be read. A copy, and shaped by the pass below rather
--         than typed, because arithmetic done once by hand rots the first time
--         the ceiling moves.
--
-- Death knight is not here because neither of these clients has one. A class
-- this table does not know falls back to RAID_CLASS_COLORS and is shaped the
-- same way on the way through.
--------------------------------------------------------------------------

local CLASS_TINT = {
	WARRIOR = { 0.78, 0.61, 0.43 },
	PALADIN = { 0.96, 0.55, 0.73 },
	HUNTER  = { 0.67, 0.83, 0.45 },
	ROGUE   = { 1.00, 0.96, 0.41 },
	PRIEST  = { 1.00, 1.00, 1.00 },
	SHAMAN  = { 0.00, 0.44, 0.87 },
	MAGE    = { 0.41, 0.80, 0.94 },
	WARLOCK = { 0.58, 0.51, 0.79 },
	DRUID   = { 1.00, 0.49, 0.04 },
}

local CLASS = {}
for name, tint in pairs(CLASS_TINT) do
	CLASS[name] = { tint = tint, fill = { tint[1], tint[2], tint[3] } }
end

Color.class = CLASS

--------------------------------------------------------------------------
-- The shaping pass
--
-- Runs once at load over every table above that is one of the two roles, and
-- writes in place, so every reference to a colour moves together and the
-- identity Unit/Unit.lua's tickers guard on survives.
--
-- Deduped, because the roles share tables on purpose. HUE.slate is the idle
-- threat state, the idle reaction and a locked cast at once, and darkening it
-- three times would land it at a fraction of what the ceiling asked for. That
-- is the one bug this pass can have and the set is the whole of the fix.
--
-- Not shaped: Color.frame and the two hues under it. An edge is a pixel of
-- chrome round a box with nothing ever drawn on top of it, so a ceiling meant
-- for backgrounds would do nothing but stop the one state that departs from
-- departing.
--------------------------------------------------------------------------

local shaped = {}

local function Shape(list, apply)
	for _, color in ipairs(list) do
		if not shaped[color] then
			shaped[color] = true
			apply(color)
		end
	end
end

local fills, tokens = { Color.heal }, {}
for _, group in ipairs({ Color.threat, Color.reaction, Color.cast, Color.power,
	Color.progress }) do
	for _, color in pairs(group) do
		fills[#fills + 1] = color
	end
end
for _, pair in pairs(CLASS) do
	fills[#fills + 1] = pair.fill
end
for _, color in pairs(Color.xp) do
	tokens[#tokens + 1] = color
end
for _, color in ipairs({ Color.text.value, Color.text.target, Color.text.count }) do
	tokens[#tokens + 1] = color
end

Shape(fills, Darken)
Shape(tokens, Brighten)

-- Every fill the palette owns, so the harness can hold all of them to the
-- ceiling rather than to the five it happens to know the names of, and so
-- `/wk colors` can print the lot.
Color.fills = fills
Color.tokens = tokens


-- The whole palette as the player can check it: what each class fills a bar
-- with and how far the name on top of it is from the fill under it. Printed by
-- `/wk colors`, and it exists because a rule with no readout is a rule nobody
-- can argue with. The worst line is the one to read.
function Color.Describe()
	local rows, names = {}, {}
	for name in pairs(CLASS) do
		names[#names + 1] = name
	end
	table.sort(names)
	for _, name in ipairs(names) do
		local fill = CLASS[name].fill
		rows[#rows + 1] = ("%s %.2f %.2f %.2f, name at %.1f:1")
			:format(name:lower(), fill[1], fill[2], fill[3], Color.Contrast(Color.paper, fill))
	end
	local worst = 99
	for _, fill in ipairs(fills) do
		local ratio = Color.Contrast(Color.paper, fill)
		worst = ratio < worst and ratio or worst
	end
	local token = 99
	for _, color in ipairs(tokens) do
		for _, fill in ipairs(fills) do
			local ratio = Color.Contrast(color, fill)
			token = ratio < token and ratio or token
		end
	end
	return ("%d fills, worst name at %.1f:1 against a floor of %.1f; %d tokens, worst"
		.. " at %.1f:1 against a floor of %.1f")
		:format(#fills, worst, Color.TEXT_RATIO, #tokens, token, Color.TOKEN_RATIO), rows
end

--------------------------------------------------------------------------

local UnitClass = UnitClass
local UnitReaction = UnitReaction
local UnitIsPlayer = UnitIsPlayer

-- One cache, for the classes this table does not carry. Filled the first time
-- such a class is seen and kept for the session: the lookup is the guard the
-- allocation scan cannot see, and on these two clients it never fills at all.
local hexByClass = {}

-- What a class fills a bar with, or nil for anything with no class. Nil rather
-- than white, because the caller has a reaction colour to fall back to and
-- white is a claim that this thing is a player of no class.
--
-- The fill and not the tint. A bar is a background and the tint is a foreground
-- colour; handing the tint back here is the bug the whole contrast section
-- above exists to make impossible to write.
function Color.Class(class)
	if not class then
		return nil
	end
	local known = CLASS[class]
	if known then
		return known.fill
	end
	local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	if not color then
		return nil
	end
	-- A class off the end of the table, shaped on the way in so it obeys the
	-- same ceiling as the nine that are in it. Three tables for a class this
	-- addon has never heard of, on the one call that ever sees it: the CLASS
	-- lookup above is the guard from the second call onward, and on both of
	-- these clients this line never runs at all.
	local fill = { color.r, color.g, color.b } -- allocates: once per unknown class, and the CLASS lookup above is the guard the scan cannot see
	Darken(fill)
	CLASS[class] = { tint = { color.r, color.g, color.b }, fill = fill } -- allocates: once per unknown class, same guard
	return fill
end

-- The same colour as the eight hex digits a chat escape wants. Separate from
-- the table above rather than formatted from it on demand, because the one
-- caller asks per group member per tick and ("ff%02x%02x%02x"):format builds a
-- string every time it is called.
--
-- The tint and not the fill, which is the one place in the file that difference
-- is visible from outside. This goes into a chat line, where the colour is the
-- text and the dark window behind it is the background, so the bright identity
-- colour is right and the darkened bar colour would be unreadable.
--
-- White for a class neither this table nor the client will colour, because a
-- name with no colour still has to be legible.
function Color.ClassHex(class)
	if not class then
		return "ffffffff"
	end
	local cached = hexByClass[class]
	if cached then
		return cached
	end
	local known = CLASS[class] or (Color.Class(class) and CLASS[class])
	if not known then
		return "ffffffff"
	end
	local tint = known.tint
	cached = ("ff%02x%02x%02x"):format(tint[1] * 255, tint[2] * 255, tint[3] * 255) -- allocates: once per class, and the lookup above is the guard the scan cannot see
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

-- The frame colour for a unit, which is the reaction question asked in the one
-- channel that costs no pixels: 4 is neutral and departs, everything else is
-- chrome. What it cannot tell you is aggro radius, which shrinks as the mob
-- falls behind your level and which no API on these clients answers.
function Color.Frame(unit)
	local reaction = UnitReaction(unit, "player")
	if not reaction or reaction >= 5 then
		return Color.frame.idle
	end
	return reaction == 4 and Color.frame.neutral or Color.frame.hostile
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

-- And a colour a fraction of the way to white, which is the other end of the
-- same instrument. Dim is what a bar keeps behind its fill on a dark surface;
-- this is what the party and raid tiles draw the health somebody has lost in,
-- and the two have to be different directions or a tile's spent end reads as a
-- second, duller fill rather than as an absence.
--
-- Its own scratch, not Dim's. UnitFrames/Member.lua asks for both in one pass
-- and one table between them would hand the second call's answer back for the
-- first.
local WASHED = { 0, 0, 0 }

function Color.Wash(color, amount)
	for index = 1, 3 do
		WASHED[index] = color[index] + (1 - color[index]) * amount
	end
	return WASHED
end
