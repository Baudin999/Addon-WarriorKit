local ADDON, ns = ...

local UI = ns.UI

--------------------------------------------------------------------------
-- Text
--
-- Three reasons this is not a SetFont call at each site.
--
-- One is sharpness. Friz Quadrata is the client's default and it is a serif cut
-- for a 2004 headline, not for a ten pixel number over a moving nameplate. The
-- addon drew every string in Arial Narrow for a year instead, because every
-- client ships it at Fonts\ARIALN.TTF and it costs no asset and no dependency
-- to reach. It is still the fallback and it is still a defensible face. It is
-- not this addon's face, and PATH below says why.
--
-- The second is that a glyph is drawn by three decisions and only one of them
-- is the typeface. The other two are whether the rasteriser anti-aliases it and
-- what holds it off the surface behind it, and both are settled below rather
-- than at the forty sites that ask for a font.
--
-- The third is cost. A font string given a font by SetFont carries its own
-- copy of that font. Given a font object it shares one. The enemy bars alone
-- put eight strings on every widget and lay out a widget per nameplate, so the
-- difference is a couple of hundred private font instances against six shared
-- ones, and a font size change is six writes instead of one per string.
--------------------------------------------------------------------------

-- The text face.
--
-- Noto Sans Regular, version 2.000, shipped whole in Media/Sans.ttf under the
-- SIL OFL with the licence beside it. Every string in the addon is drawn in
-- this and it is the one line that decides that.
--
-- Picked at eleven pixels, which is UI.Metric.small: the hint under a control,
-- the caption on a feed row, the count in a corner. At that height a face is
-- two measurements and neither of them is the em size the caller passed.
--
-- The first is the x-height, because that is what the eye reads and the em box
-- is not. Arial Narrow's is 0.519 em, so eleven pixels of it is 5.7 pixels of
-- letter. Noto Sans is 0.536 and gets 5.9. Source Sans Pro, which is the other
-- face Narcissus ships and the obvious answer, is 0.486 and gets 5.3, so every
-- string in the addon would have come out smaller on the screen at the size it
-- already asks for. That is the wrong direction for the one thing this change
-- is for.
--
-- The second is whether the face carries instructions. Noto Sans is
-- ttfautohinted and ships fpgm, prep, cvt and gasp, so the rasteriser is told
-- where to put a stem rather than rounding each one on its own. The Source Sans
-- Pro on this disk has none of those tables at all. The MONOCHROME gravestone
-- further down is what an unhinted face at these sizes looks like, and shipping
-- one deliberately after writing that note down would be a strange thing to do.
--
-- The cost is width. Over the addon's own strings Noto Sans averages 0.481 em
-- per glyph against Arial Narrow's 0.379, so every label is about 27 per cent
-- wider at the same pixel height. Two things were sized against the narrow face
-- and clipped on the wide one: seven of the options window's section titles ran
-- off the end of their line in the rail, and a five figure crit ran out of the
-- feed's number column. Both were widened rather than the font shrunk to fit
-- them, because a number that fits because the text got smaller is this change
-- undone.
local PATH = "Interface\\AddOns\\" .. ADDON .. "\\Media\\Sans.ttf"

-- What a client that will not take the file falls back to, for both faces.
--
-- Arial Narrow is in the client rather than in the addon folder, so it is the
-- one face here that cannot be missing. It is also what the addon drew until
-- this commit, which makes the failure state the last known good one rather
-- than Friz Quadrata.
local NARROW = "Fonts\\ARIALN.TTF"

-- The glyph face.
--
-- Marks of Font Awesome Free, subset into Media/Glyphs.ttf by
-- scripts/bake-glyphs.sh and cut onto the letters they replace: `v` and `>` are
-- the chevrons on a group that folds, `x` is the close cross, `+` and `-` are
-- the two ends of a stepper, `V` is the tick against something finished and `s`
-- is the share arrow. Nothing that draws one knows it is drawing a font
-- at all. UI.Glyph hands back a string in this face and every caller carries on
-- writing the same letter it wrote before.
--
-- Cutting the icons onto letters rather than onto their own codepoints is what
-- makes the fallback free. A client that will not take the file leaves the font
-- object empty, the readback below puts Arial Narrow in its place, and what
-- comes out is the `v` and the `>` this window drew until the font existed.
-- Nothing checks a flag and there is no second path through any caller.
--
-- A glyph is not an icon. An icon is the game's own art for a spell and
-- UI/Draw.lua crops it; a glyph is a mark this addon draws at the size of a
-- letter. Two words, kept apart.
local GLYPHS = "Interface\\AddOns\\" .. ADDON .. "\\Media\\Glyphs.ttf"

-- Every letter that face has a mark on, in one string.
--
-- The cmap of the subset is rewritten to exactly these letters, so a glyph
-- string given any other letter draws nothing at all: no error, no fallback, an
-- empty rectangle where a mark should be. That is the failure this exists to
-- gate. scripts/check.sh reads this string and the PICK table in
-- scripts/bake-glyphs.sh and fails if they disagree, so a letter added to the
-- addon without rebaking the font, or baked and never written down here, is
-- caught before it ships rather than seen in a screenshot.
--
-- Sorted, because the two lists are compared as text and an order nobody
-- maintains is a diff nobody can read.
UI.GLYPHS = "!$*+-=>Vefmoqstvx"

-- Three roles, and every string in the addon is exactly one of them. This is
-- the whole font policy and it is here rather than argued again at each site.
--
--   flat      over a surface this addon painted and knows the colour of. Panel
--             prose, and every string on a bar, because Unit/Color.lua caps
--             every fill it owns so that Color.paper clears 4.5:1 on it. The
--             contrast is guaranteed by the palette, so the glyph needs nothing
--             round it and gets nothing. UI.FLAT.
--   shadowed  over art the addon did not paint and cannot predict: a spell icon
--             on a debuff square, and the chat window, whose background alpha
--             is a setting that ships at zero. A one pixel drop shadow, which
--             holds the glyph off a bright icon without spending any of the
--             glyph's own pixels. UI.SHADOW.
--   outlined  over the world at a size that can carry a rim. No known colour
--             behind it at all, so a shadow has nothing to be darker than and
--             the rim is the only thing that works. UI.OUTLINE, and
--             UI.OutlineFloor is its minimum size. Under that floor the rim
--             closes the counters, so text over the world at eleven or twelve
--             pixels takes the shadow instead: that is the chat window, and it
--             is why the second role reaches further than one debuff square.
--
-- All three are named and every caller passes one. An outline used to be the
-- unnamed default, which is a policy nobody reads holding a value everybody
-- gets, and it went wrong exactly where you would expect: the purse along the
-- bottom of the loot feed and every row of the feed above it are painted on an
-- opaque surface this addon owns, they asked for no role, and they were drawn
-- with a rim meant for text over a mob. Twelve pixel Arial Narrow with an
-- outline round it is the "worse font" that got reported, and no site had to
-- be wrong for it to happen. scripts/check.sh now fails any call that names no
-- role. FALLBACK is what a call the grep did not see still draws, because a
-- readable string is a better failure than a raise in the middle of a layout.
--
-- What is deliberately not here is MONOCHROME. It was tried as the default for
-- everything at or under sixteen pixels and it was a mistake, so this note is
-- the gravestone rather than a switch. Turning the rasteriser off gives a
-- purpose built pixel font hard clean edges; it gives Arial Narrow broken ones,
-- because an unhinted humanist face at eleven to fourteen pixels has stems that
-- do not land on pixel boundaries and rounding each one independently makes
-- them different weights. The report was that all the text went fuzzy, and it
-- had. The grid already puts every glyph on a whole pixel and that is as far as
-- geometry can take this; the rest of what reads as sharpness is contrast, and
-- that is Unit/Color.lua's job.
--
-- UI.SHADOW is not a client flag and never reaches SetFont. It rides in the
-- flags string so that it threads through UI.Label and every other site that
-- already passes flags along, instead of adding a parameter to all of them.
-- UI.FLAT is the empty string for the same reason: a role is a value a caller
-- passes, and "no flags" has to be one of the values or it is a gap.
UI.FLAT = ""
UI.SHADOW = "SHADOW"
UI.OUTLINE = "OUTLINE"

local FALLBACK = UI.OUTLINE

-- One unit, which inside a frame ns.UI.Adopt has taken onto the grid is one
-- physical pixel. Off the grid it is near enough one, and that is the same
-- honest degradation the rest of the addon takes there.
local SHADOW_OFFSET = 1

-- One table of sizes per flag string for the text face, and one table of sizes
-- for the glyph face, which has no flags to key on. Two tables rather than one
-- keyed by a built string, so nothing here concatenates to find a font.
local fonts = {}
local glyphs = {}
local made = 0

-- What actually reaches SetFont, and whether the font wants a shadow.
local function Compose(flags)
	local shadow = flags:find(UI.SHADOW, 1, true) ~= nil
	if not shadow then
		return flags, false
	end
	return (flags:gsub(UI.SHADOW, ""):gsub("^[%s,]+", ""):gsub("[%s,]+$", "")), true
end

-- Left, and top to bottom the middle, on every object this file hands out.
--
-- A font object carries a justification as well as a face, the client's default
-- for a fresh one is centred, and a frame given the object takes both. Nothing
-- noticed for a year because UI.Label justifies each font string itself after
-- it sets the object, so the object's own answer never reached the screen.
--
-- Then the chat window put a ScrollingMessageFrame on one of these. That frame
-- has no font strings a caller can reach: it makes its own, and the only place
-- to say how they are justified is the frame, which SetFontObject then
-- overwrites with the object's centred default. Every line anybody spoke came
-- out centred, and the SetJustifyH("LEFT") in UI/Log.lua three lines above the
-- SetFontObject was doing nothing at all.
--
-- So it is set here, once, where a font is made. A caller that wants something
-- else still says so on its own string and still wins.
local function Justify(font)
	if type(font.SetJustifyH) == "function" then
		font:SetJustifyH("LEFT")
	end
	if type(font.SetJustifyV) == "function" then
		font:SetJustifyV("MIDDLE")
	end
	return font
end

-- One object per size and flag pair, made on first ask and never freed. The
-- flags are the caller's own string rather than the composed one, because two
-- callers that asked differently are allowed to land on one object and neither
-- should have to know that they did. The face is in the key and the path is not:
-- there are two faces and neither is a setting, so which one you get is a
-- function you called rather than a string you passed.
--
-- Two lookups rather than a string built out of the size and the flags. This is
-- asked for every line of every tooltip and again on the keystroke path, and a
-- concatenation there is a fresh string per ask for a table this file already
-- has: the flags name a table of sizes, and the size is a number key in it.
function UI.Font(size, flags)
	flags = flags or FALLBACK
	local sized = fonts[flags]
	if not sized then
		sized = {}
		fonts[flags] = sized
	end
	local font = sized[size]
	if font then
		return font
	end

	local real, shadow = Compose(flags)
	made = made + 1
	font = CreateFont(ADDON .. "Font" .. made)
	font:SetFont(PATH, size, real)
	-- SetFont answers differently across these two clients and a missing file
	-- is silent on both, so the readback is what proves it took. This used to be
	-- defensive and is now load bearing: PATH is in the addon folder rather than
	-- in the client, which is the one place a font path can be missing on an
	-- install that otherwise works.
	if not font:GetFont() then
		font:SetFont(NARROW, size, real)
	end
	if shadow then
		font:SetShadowColor(0, 0, 0, 1)
		font:SetShadowOffset(SHADOW_OFFSET, -SHADOW_OFFSET)
	end
	Justify(font)
	sized[size] = font
	return font
end

-- The smallest glyph an outline can go round without eating it.
--
-- Only text over the world reaches this. Everything else has a known colour
-- behind it and takes a shadow or nothing, which is the choice this number used
-- to make on that text's behalf. What is left has no fallback to switch to: a
-- pale number over pale ground with no rim is not softer, it is gone. So the
-- floor is not a switch, it is a minimum size, and a string that must be
-- outlined must also be at least this tall.
--
-- Fourteen is where a rim stops closing a counter. An outline costs a pixel on
-- every stroke whatever the glyph is, so below it the hole in a 6 and the waist
-- of an 8 fill in and a 3 and an 8 stop being different shapes.
--
-- The number was measured on Arial Narrow and it did not move when the face
-- did. A counter closes at the height of the letter rather than at the size the
-- caller asked for, and Noto Sans buys 0.017 em of x-height over Arial Narrow,
-- which at fourteen pixels is a quarter of a pixel. Not a floor's worth.
local OUTLINE_FLOOR = 14

-- A number drawn over art the addon did not paint: the timer and the stack
-- count on a debuff square, which sit on whatever the spell icon happens to be.
-- Shadowed at every size.
--
-- This used to pick up an outline at OUTLINE_FLOOR and drop it below. The switch
-- existed because a rim was the only thing holding a pale digit off a bright
-- icon, and it cost the counters of every digit under fourteen. A shadow holds
-- the digit off just as well and spends no pixel of the glyph to do it, so
-- there is nothing left for a switch to choose between.
function UI.NumberFont(size)
	return UI.Font(size, UI.SHADOW)
end

function UI.OutlineFloor()
	return OUTLINE_FLOOR
end

-- The glyph face at one size, or Arial Narrow at that size on a client that
-- would not take it. Flat and unshadowed, because every glyph in the addon sits
-- on a surface this addon painted, which is the same argument UI.FLAT is.
function UI.GlyphFont(size)
	local font = glyphs[size]
	if font then
		return font
	end

	made = made + 1
	font = CreateFont(ADDON .. "Font" .. made)
	Justify(font)
	font:SetFont(GLYPHS, size, "")
	-- The same readback UI.Font does, and to the same place. Both faces are in
	-- Media/ now, so a client that refused one is not a client to try the other
	-- on: the fallback is the client's own Arial Narrow, which is the letter the
	-- caller wrote before a mark was cut onto it.
	if not font:GetFont() then
		font:SetFont(NARROW, size, "")
	end
	glyphs[size] = font
	return font
end

-- What both of the calls below are: a font string on a shared font object, in a
-- colour, justified. The object is the only thing that differs between them.
local function String(parent, object, color, justify)
	local text = parent:CreateFontString(nil, "OVERLAY")
	text:SetFontObject(object)
	if color then
		text:SetTextColor(color[1], color[2], color[3])
	end
	text:SetJustifyH(justify or "LEFT")
	-- Nothing installed here proves SetWordWrap exists on 2.5.6, and this runs
	-- once per nameplate, so an absent method would raise per widget rather
	-- than once.
	if text.SetWordWrap then
		text:SetWordWrap(false)
	end
	return text
end

-- One of the three roles at the head of this file, named by every caller. Which
-- one is not a default worth having: it is a fact about what is behind the
-- string, the caller is the only thing that knows it, and the answer is
-- different for a mob's name over a floor and the same name in a panel row.
function UI.Label(parent, size, color, justify, flags)
	return String(parent, UI.Font(size, flags), color, justify)
end

-- One mark in the glyph face: a chevron, a cross, a plus. The caller sets the
-- letter it has always set.
function UI.Glyph(parent, size, color, justify)
	return String(parent, UI.GlyphFont(size), color, justify)
end

-- Whether the text face took, which is what tells a shipped install from one
-- that lost Media/Sans.ttf in a bad update. Both answers are readable, so
-- nothing else in the addon behaves differently on them and this string is the
-- only way to tell them apart.
function UI.FontName()
	local path = UI.Font(10):GetFont()
	return (path == PATH) and "Noto Sans" or "Arial Narrow"
end

-- Whether the glyph face took, which is what tells a chevron from the letter v
-- in a bug report.
function UI.GlyphName()
	local path = UI.GlyphFont(10):GetFont()
	return (path == GLYPHS) and "the glyph face" or "Arial Narrow, so the letters"
end

-- Word wrap is off in UI.Label because a mob's name over a nameplate wants
-- clipping rather than folding onto a second line. Panel prose wants the exact
-- opposite, and the method is probed here for the same reason it is probed
-- there: nothing installed on 2.5.6 proves SetWordWrap is on this client.
function UI.Wrap(text, on)
	if text.SetWordWrap then
		text:SetWordWrap(on and true or false)
	end
	return text
end

-- How tall a string is once it has wrapped to the width it was given. Set the
-- width and the text before asking, because a font string measured before
-- either is one line tall and a row sized off that answer clips its own prose.
--
-- A hidden font string is not obliged to answer at all on this client, and the
-- symptom would be every note in a tab you have not opened yet laying out one
-- line high. That is what the floor is for, and it is why the panel reflows the
-- section it has just shown rather than trusting the measurement it took while
-- the section was still hidden.
function UI.TextHeight(text, floor)
	floor = floor or 0
	local height = text.GetStringHeight and text:GetStringHeight() or 0
	if type(height) ~= "number" or height < floor then
		return floor
	end
	return height
end
