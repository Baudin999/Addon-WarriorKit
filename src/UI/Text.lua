local ADDON, ns = ...

local UI = ns.UI

--------------------------------------------------------------------------
-- Text
--
-- Two reasons this is not a SetFont call at each site.
--
-- One is sharpness. Friz Quadrata is the client's default and it is a serif cut
-- for a 2004 headline, not for a ten pixel number over a moving nameplate. Every
-- client since the first ships Arial Narrow at Fonts\ARIALN.TTF, which is what
-- nearly every legible Classic UI runs on, and it costs no asset in the addon
-- folder and no dependency to reach it.
--
-- The other is cost. A font string given a font by SetFont carries its own
-- copy of that font. Given a font object it shares one. The enemy bars alone
-- put eight strings on every widget and lay out a widget per nameplate, so the
-- difference is a couple of hundred private font instances against six shared
-- ones, and a font size change is six writes instead of one per string.
--------------------------------------------------------------------------

local PATH = "Fonts\\ARIALN.TTF"
local DEFAULT_FLAGS = "OUTLINE"

local fonts = {}
local made = 0

-- One object per size and flag pair, made on first ask and never freed. The key
-- is not the path, because the path is not a setting: one font, chosen here.
function UI.Font(size, flags)
	flags = flags or DEFAULT_FLAGS
	local key = size .. flags
	local font = fonts[key]
	if font then
		return font
	end

	made = made + 1
	font = CreateFont(ADDON .. "Font" .. made)
	font:SetFont(PATH, size, flags)
	-- SetFont answers differently across these two clients and a missing file
	-- is silent on both, so the readback is what proves it took.
	if not font:GetFont() then
		font:SetFont((GameFontNormal:GetFont()), size, flags)
	end
	fonts[key] = font
	return font
end

-- The smallest glyph an outline can go round without eating it.
--
-- UI/Theme.lua already states this rule for panel text: over an opaque surface
-- an outline "only thickens a twelve pixel glyph until it closes up its own
-- counters". A cooldown number on a debuff square is over an opaque surface too,
-- and the enemy bars were drawing those at seven to twelve pixels with an
-- outline on them. At that size a 3 and an 8 stop being different shapes, which
-- is a timer you cannot read rather than a timer that looks soft.
local OUTLINE_FLOOR = 14

-- A number drawn over art rather than over the world: the timer and the stack
-- count on a debuff square. Outlined where the glyph is big enough to carry one,
-- flat where it is not, because a closed up glyph is worse than one with no rim.
--
-- The floor is a property of the typeface and the outline, not of any part, so
-- it lives here with the font cache rather than in whichever file happens to
-- draw a small number first.
function UI.NumberFont(size)
	return UI.Font(size, size >= OUTLINE_FLOOR and DEFAULT_FLAGS or "")
end

function UI.OutlineFloor()
	return OUTLINE_FLOOR
end

-- Outlined rather than shadowed, because these sit over the world and a drop
-- shadow disappears against a dark floor.
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
