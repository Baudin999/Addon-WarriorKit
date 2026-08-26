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

-- Anti-aliasing off, which is what actually made the frames sharp.
--
-- UI/Pixel.lua already lands every glyph on a whole number of physical pixels,
-- so the softness that was left was the rasteriser and not the geometry. A 14
-- pixel Arial Narrow stem is about a pixel and a half wide and anti-aliased to
-- grey at both edges. OUTLINE then wraps an anti-aliased black rim round that,
-- and what reaches the screen is grey, dark grey, grey, with no fully opaque
-- pixel anywhere along the stem. That is the blur, and no amount of pixel
-- alignment removes it.
--
-- MONOCHROME turns the rasteriser off. Every pixel of a glyph is on or off, a
-- stem is a hard column of solid colour, and a rim round a hard edge stays a
-- rim instead of bleeding into it.
--
-- The ceiling is there because the trade reverses as the glyph grows. At eleven
-- pixels a diagonal has three steps and reads as a letter; at twenty it has six
-- and reads as a staircase. Sixteen is where this addon stops drawing chrome
-- and starts drawing prose, and the only thing that goes above it is the chat
-- text size slider, which runs to 20.
local MONO = "MONOCHROME"
local MONO_CEILING = 16

-- A caller asking for a one pixel drop shadow. Not a client flag, and it never
-- reaches SetFont: it rides in the flags string so that it threads through
-- UI.Label and every other site that already passes flags along, instead of
-- adding a parameter to all of them.
--
-- What it replaces is the outline, over every surface the addon drew itself. An
-- outline and a shadow do the same job, which is to keep a pale glyph off the
-- surface behind it, and the outline does it by spending the glyph's own pixels
-- while the shadow does it by spending the pixel below and to the right. Over
-- opaque art that makes the shadow strictly better. Over the world it is not
-- available at all, because a shadow needs a known colour to be darker than and
-- the world is not one.
UI.SHADOW = "SHADOW"

-- One unit, which inside a frame ns.UI.Adopt has taken onto the grid is one
-- physical pixel. Off the grid it is near enough one, and that is the same
-- honest degradation the rest of the addon takes there.
local SHADOW_OFFSET = 1

local fonts = {}
local made = 0

-- What actually reaches SetFont, and whether the font wants a shadow. Both come
-- out of the same two inputs, so they are decided together and once.
local function Compose(size, flags)
	local shadow = flags:find(UI.SHADOW, 1, true) ~= nil
	local real = flags:gsub(UI.SHADOW, ""):gsub("^[%s,]+", ""):gsub("[%s,]+$", "")
	if size <= MONO_CEILING then
		real = (real == "") and MONO or (real .. ", " .. MONO)
	end
	return real, shadow
end

-- One object per size and flag pair, made on first ask and never freed. The key
-- is the caller's own string rather than the composed one, because two callers
-- that asked differently are allowed to land on one object and neither should
-- have to know that they did. The path is not in the key because the path is
-- not a setting: one font, chosen here.
function UI.Font(size, flags)
	flags = flags or DEFAULT_FLAGS
	local key = size .. flags
	local font = fonts[key]
	if font then
		return font
	end

	local real, shadow = Compose(size, flags)
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
-- Only text over the world reaches this now. Everything the addon draws over
-- its own art is flat and shadowed, which is the choice this number used to
-- make on that text's behalf. What is left has no fallback to switch to: a pale
-- number over pale ground with no rim is not softer, it is gone. So the floor
-- stopped being a switch and became a minimum size, and a string that must be
-- outlined must also be at least this tall.
--
-- Fourteen, and MONOCHROME is why it is still fourteen rather than sixteen. A
-- rim round an anti-aliased stem bleeds into it and the hole in a 6 fills well
-- above fourteen, which is what the enemy bars were showing. Round a hard edge
-- it does not bleed and fourteen holds.
local OUTLINE_FLOOR = 14

-- A number drawn over art rather than over the world: the timer and the stack
-- count on a debuff square, the spell name and the seconds in the cast chamber.
-- Flat and shadowed at every size.
--
-- This used to pick up an outline at OUTLINE_FLOOR and drop it below. The switch
-- existed because a rim was the only thing holding a pale digit off a bright
-- icon, and it cost the counters of every digit under fourteen: a 3 and an 8
-- stopped being different shapes. A shadow holds the digit off just as well and
-- spends no pixel of the glyph to do it, so there is nothing left for a switch
-- to choose between and the small sizes are the ones that gain most.
function UI.NumberFont(size)
	return UI.Font(size, UI.SHADOW)
end

function UI.OutlineFloor()
	return OUTLINE_FLOOR
end

function UI.MonoCeiling()
	return MONO_CEILING
end

-- Outlined by default, because the default caller is a string over the world
-- and a shadow disappears against a dark floor. Everything over the addon's own
-- art passes UI.SHADOW, and panel prose passes UI.FLAT.
function UI.Label(parent, size, color, justify, flags)
	local text = parent:CreateFontString(nil, "OVERLAY")
	text:SetFontObject(UI.Font(size, flags))
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

function UI.FontName()
	local path = UI.Font(10):GetFont()
	return (path == PATH) and "Arial Narrow" or "the client default"
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
