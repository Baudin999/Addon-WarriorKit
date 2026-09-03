local ADDON, ns = ...

local UI = ns.UI
local Gauge = {}
UI.Gauge = Gauge

--------------------------------------------------------------------------
-- The gauge
--
-- A status bar with a flat fill and the spent part of it drawn behind, which
-- is what every health and power gauge in this addon is.
--
-- It was written twice and neither copy was wrong. UnitFrames/EnemyBars.lua
-- builds a bar of its own with a white texture the bar tints; Skin.lua takes
-- the bar Blizzard already made and turns its fill into the same white
-- texture. Those two really are different jobs. What made them one file is the
-- line underneath, which was the same in both: the fill set to the unit's
-- colour and the track set to a fifth of that colour at nine tenths alpha,
-- with the same constant and the same 0.9 typed out in each. A pair of writes
-- like that drifts the first time somebody decides the spent end is too dark,
-- and the two gauges stop agreeing about what a mob at ten percent looks like.
--
-- Four calls, split by when they run rather than by what reads tidily.
-- Gauge.New and Gauge.Underlay allocate and are called once per widget.
-- Gauge.Flatten and Gauge.Paint run on a ticker against every mob on the
-- screen and every unit frame on it, so neither allocates and neither writes
-- what is already there. check.sh's HOT list holds the second pair to that.
--
-- Not in here: the meter's rows. Meter/Window.lua draws each row's bar as one
-- texture whose width is that player's share of the top row's number, with
-- nothing behind it and no spent part to colour. Putting a status bar under
-- every row would add a frame per row, an ordering question between that frame
-- and the row's own icon and text, and float arithmetic where the meter rounds
-- a share to whole pixels on purpose. It looks like the same widget from a
-- distance and shares one line of code with it, which is the colour, and that
-- line is class colour at its own alpha rather than anything on this page.
--------------------------------------------------------------------------

-- What the spent part keeps of the fill's colour. Off the unit palette rather
-- than restated here: the enemy bars and the skinned frames already agreed on
-- one fifth, and a second copy of the number in the drawing layer is what the
-- extraction into ns.Unit.Color was for.
local TRACK = ns.Unit.Color.track

-- And what it keeps of the surface behind it. Not opaque, so the empty end of
-- a gauge reads as the frame's own dark showing through rather than as a
-- second fill in a duller colour. Nine tenths is the figure both callers
-- shipped and it is kept rather than rounded, because rounding it to one is a
-- look change wearing a tidy-up's clothes.
local TRACK_ALPHA = 0.9

-- A status bar's own fill texture, turned into a flat colour.
--
-- Swapping in a new texture instead left the original parented to the bar and
-- still drawing, which is what kept the soft rounded ends of UI-StatusBar
-- under a flat colour that was doing nothing.
--
-- Re-fetched rather than cached, because a client that swaps the texture
-- object out from under the bar would leave a cached one pointing at nothing,
-- and re-applied from the tick, because Blizzard's own code sets these back
-- and ours has to be the last word.
--
-- Being the last word is not the same as writing every tick, which is what
-- this did. A colour texture answers no file path, so a bar that is still flat
-- costs one comparison, and the moment Blizzard puts UI-StatusBar back the
-- path answers and this writes again. Six bars at five ticks a second is
-- thirty texture writes saved, all of them writing the colour already there.
-- Where the client has no GetTexture the write stands unguarded, which is what
-- this did before and is the safe half to be wrong on.
function Gauge.Flatten(bar)
	local fill = bar and bar.GetStatusBarTexture and bar:GetStatusBarTexture()
	if not fill or not fill.SetColorTexture then
		return nil
	end
	local flat = fill.GetTexture and bar.wkFlat == fill and not fill:GetTexture()
	if not flat then
		bar.wkFlat = fill
		fill:SetColorTexture(1, 1, 1, 1)
	end
	return fill
end

-- A texture of ours, drawn inside a status bar and under its fill.
--
-- Under it by draw layer, not by frame level, and that is the whole reason
-- these textures live on the bar rather than on a rail of ours behind it. Two
-- frames agree on an order only while their levels do, and the code that
-- writes both of those levels can still be wrong about them: on the live
-- client the target frame came out with its rail level with its bar, the tie
-- went to whichever was built later, which was ours, and the spent track drew
-- over the fill at nine tenths alpha. A target at full health read at 28
-- percent of its own colour, which is what a dead one looks like. The player
-- frame, one line of the same code away, was correct.
--
-- Inside one frame there is nothing to disagree about. Layer beats level and
-- BACKGROUND is the bottom one, so a sublevel there is below every layer a
-- status bar's fill can be built on, on any client, and no number a caller
-- writes can move it. A caller drawing two underlays in one bar orders them by
-- passing the two lowest sublevels the client allows; a caller drawing one
-- passes nothing and takes the default.
--
-- The colour is optional and a gauge that is painted on its first tick leaves
-- it out, because a colour set here is a colour drawn for the frame before
-- that tick lands.
function Gauge.Underlay(bar, sublevel, color)
	local texture
	if color then
		texture = ns.Fill(bar, "BACKGROUND", color[1], color[2], color[3], color[4])
	else
		texture = bar:CreateTexture(nil, "BACKGROUND")
	end
	texture:SetAllPoints()
	if sublevel and texture.SetDrawLayer then
		texture:SetDrawLayer("BACKGROUND", sublevel)
	end
	return texture
end

-- A gauge of our own: flat fill, spent track behind it, and a scale of zero to
-- one until the caller knows what the unit's maximum is.
--
-- The track hangs off the bar as `track` because this one owns both. A caller
-- painting a bar it did not build hands its own track to Gauge.Paint instead.
function Gauge.New(parent)
	local bar = CreateFrame("StatusBar", nil, parent)
	local fill = bar:CreateTexture(nil, "ARTWORK")
	bar:SetStatusBarTexture(fill)
	Gauge.Flatten(bar)
	bar:SetMinMaxValues(0, 1)
	bar.track = Gauge.Underlay(bar)
	return bar
end

-- The fill and the spent part behind it, in one colour. This is the pair of
-- writes the file exists for.
--
-- Through the setter the bar came with, or through the copy the skin put aside
-- when it froze the client's own: a frozen bar's SetStatusBarColor is a no-op
-- and the original lives under the same wk-prefixed key ns.Strip and
-- UnitFrames/Art.lua's Freeze use, so painting one has to go the long way
-- round.
--
-- No guard in here, and that is the one difference from ns.Recolor. Both
-- callers already compare the colour table's identity against the one they
-- drew last, and the same comparison decides three or four other writes beside
-- these two, so a cache here would be a second one to keep true across a
-- pooled widget. ns.Recolor guards internally because its callers cannot all
-- compare the same thing; these two can and do.
function Gauge.Paint(bar, track, color)
	local r, g, b = color[1], color[2], color[3]
	local set = bar and (bar.wkSetStatusBarColor or bar.SetStatusBarColor)
	if set then
		set(bar, r, g, b, 1)
	end
	if track then
		track:SetColorTexture(r * TRACK, g * TRACK, b * TRACK, TRACK_ALPHA)
	end
end

