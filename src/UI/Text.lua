local ADDON, ns = ...

local UI = ns.UI

--------------------------------------------------------------------------
-- Text
--
-- Three reasons this is not a SetFont call at each site.
--
-- One is sharpness. Friz Quadrata is the client's default and it is a serif cut
-- for a 2004 headline, not for a ten pixel number over a moving nameplate. Every
-- client since the first ships Arial Narrow at Fonts\ARIALN.TTF, which is what
-- nearly every legible Classic UI runs on, and it costs no asset in the addon
-- folder and no dependency to reach it.
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

local PATH = "Fonts\\ARIALN.TTF"
local DEFAULT_FLAGS = "OUTLINE"

-- The glyph face.
--
-- Five marks of Font Awesome Free, subset into Media/Glyphs.ttf by
-- scripts/bake-glyphs.sh and cut onto the letters they replace: `v` and `>` are
-- the chevrons on a group that folds, `x` is the close cross, `+` and `-` are
-- the two ends of a stepper. Nothing that draws one knows it is drawing a font
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

-- Three roles, and every string in the addon is exactly one of them. This is
-- the whole font policy and it is here rather than argued again at each site.
--
--   flat      over a surface this addon painted and knows the colour of. Panel
--             prose, and every string on a bar, because Unit/Color.lua caps
--             every fill it owns so that Color.paper clears 4.5:1 on it. The
--             contrast is guaranteed by the palette, so the glyph needs nothing
--             round it and gets nothing. UI.FLAT.
--   shadowed  over art the addon did not paint and cannot predict: a spell icon
--             on a debuff square. A one pixel drop shadow, which holds the
--             glyph off a bright icon without spending any of the glyph's own
--             pixels. UI.SHADOW.
--   outlined  over the world. No known colour behind it at all, so a shadow has
--             nothing to be darker than and the rim is the only thing that
--             works. The default, and UI.OutlineFloor is its minimum size.
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
UI.SHADOW = "SHADOW"

-- One unit, which inside a frame ns.UI.Adopt has taken onto the grid is one
-- physical pixel. Off the grid it is near enough one, and that is the same
-- honest degradation the rest of the addon takes there.
local SHADOW_OFFSET = 1

local fonts = {}
local made = 0

-- What actually reaches SetFont, and whether the font wants a shadow.
local function Compose(flags)
	local shadow = flags:find(UI.SHADOW, 1, true) ~= nil
	if not shadow then
		return flags, false
	end
	return (flags:gsub(UI.SHADOW, ""):gsub("^[%s,]+", ""):gsub("[%s,]+$", "")), true
end

-- One object per size and flag pair, made on first ask and never freed. The key
-- is the caller's own string rather than the composed one, because two callers
-- that asked differently are allowed to land on one object and neither should
-- have to know that they did. The face is in the key and the path is not: there
-- are two faces and neither is a setting, so which one you get is a function
-- you called rather than a string you passed.
function UI.Font(size, flags)
	flags = flags or DEFAULT_FLAGS
	local key = "text" .. size .. flags
	local font = fonts[key]
	if font then
		return font
	end

	local real, shadow = Compose(flags)
	made = made + 1
	font = CreateFont(ADDON .. "Font" .. made)
	font:SetFont(PATH, size, real)
	-- SetFont answers differently across these two clients and a missing file
	-- is silent on both, so the readback is what proves it took.
	if not font:GetFont() then
		font:SetFont((GameFontNormal:GetFont()), size, real)
	end
	if shadow then
		font:SetShadowColor(0, 0, 0, 1)
		font:SetShadowOffset(SHADOW_OFFSET, -SHADOW_OFFSET)
	end
	fonts[key] = font
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
-- Fourteen is where a rim stops closing an Arial Narrow counter. An outline
-- costs a pixel on every stroke whatever the glyph is, so below it the hole in
-- a 6 and the waist of an 8 fill in and a 3 and an 8 stop being different
-- shapes.
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
	local key = "glyph" .. size
	local font = fonts[key]
	if font then
		return font
	end

	made = made + 1
	font = CreateFont(ADDON .. "Font" .. made)
	font:SetFont(GLYPHS, size, "")
	-- The same readback UI.Font does, and here it is load bearing rather than
	-- defensive: this file is in the addon folder rather than in the client, so
	-- it is the one font path that can be missing on a working install.
	if not font:GetFont() then
		font:SetFont(PATH, size, "")
	end
	fonts[key] = font
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

-- Outlined by default, because the default caller is a string over the world
-- and a shadow disappears against a dark floor. Everything else passes one of
-- the other two roles at the head of this file.
function UI.Label(parent, size, color, justify, flags)
	return String(parent, UI.Font(size, flags), color, justify)
end

-- One mark in the glyph face: a chevron, a cross, a plus. The caller sets the
-- letter it has always set.
function UI.Glyph(parent, size, color, justify)
	return String(parent, UI.GlyphFont(size), color, justify)
end

function UI.FontName()
	local path = UI.Font(10):GetFont()
	return (path == PATH) and "Arial Narrow" or "the client default"
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
