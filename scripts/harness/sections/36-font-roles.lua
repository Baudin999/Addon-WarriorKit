-- What is behind every string in the addon
--
-- UI/Text.lua names three roles and argues for each. Flat over a surface this
-- addon painted and knows the colour of; shadowed over art it did not paint,
-- which is a spell icon; outlined over the world, where there is no known
-- colour at all and the rim is the only thing that works. scripts/check.sh
-- fails any call that names no role, and that gate is worth having, but it can
-- only see that a role was named. Whether it is the right one is a fact about
-- what is behind the string, and no amount of reading the call answers it.
--
-- This does. Every frame the addon builds is here, every font string hangs off
-- one of them, and every backing texture is a region with an alpha on it, so
-- the question "is there a surface under this glyph" is one the built addon can
-- be asked directly. It is asked twice: once as the addon comes up, and once
-- with every background opacity dragged to zero.
--
-- The second pass is the one that matters and it is the one that caught the
-- fix that went in before it. Three surfaces in this addon are not surfaces:
-- the two feeds and the chat window paint a background whose opacity is a
-- slider, the slider goes to zero, and Feeds/Feature.lua tells the player in
-- writing that the text reads all the way down to nothing. A string on one of
-- those is a string over the world that happens to look like it is not, and it
-- was flat for exactly as long as it took to run this.
--
-- Three rules, and each is a way this has already gone wrong.
--
-- An outlined string is at least UI.OutlineFloor() tall. A rim costs a pixel of
-- every stroke whatever the glyph is, so under the floor it closes the hole in
-- a 6 and the waist of an 8. This is what the report about the purse's font was
-- looking at, and the two drag captions on the swing bars and the buff row were
-- the same defect nobody had hovered.
--
-- A string with nothing behind it is outlined. Flat over the world is not
-- softer, it is gone, and a shadow has nothing to be darker than.
--
-- Nothing is MONOCHROME. It was tried and it broke Arial Narrow's stems.
-- UI/Text.lua keeps the gravestone; this keeps the gate.
--
-- What is deliberately not checked: that a string with a surface behind it is
-- flat. A shadow over an opaque bar is a defensible choice and UnitFrames makes
-- it on purpose, so the rule that would catch a stray outline there would also
-- fail every number on a debuff square. 12-debuff-square-size.lua checks that
-- per widget, where the surface is known by name.

local H = ...
local ns, check = H.ns, H.check
local frames = H.frames

local UI = ns.UI
local floor = UI.OutlineFloor()

-- Sites this rule does not hold for, and why. An entry with no reason is the
-- same invisible debt as a warning, so the reason is the value.
-- Keyed by file and then by the rule it is exempt from, so a file excused one
-- of the three is still held to the other two. Keyed by file rather than by
-- line because a line number moves and an allow-list that goes stale silently
-- is worse than no allow-list.
local ALLOWED = {
	["UI/Aura.lua"] = { bare =
		"the timer over an aura square, which sits above the art rather than on "
		.. "it and so has the world behind it. It keeps the shadow anyway, and "
		.. "UI/Aura.lua argues it where the trade is made: the string is 8 to 14 "
		.. "pixels tall and an outline at that size closes the hole in a 6, so "
		.. "there is no role here that is right, only a least wrong one. The "
		.. "stack count beside it is on the icon and is not exempt." },
	["UI/Log.lua"] = { bare =
		"the chat window's own text, and the one place the three roles do not "
		.. "settle it: the size is a slider from 9 to 20 and the background is "
		.. "a slider to 0, so at the bottom of both there is no role that works "
		.. "- an outline eats a 9 pixel glyph and flat has nothing behind it. "
		.. "Left flat, which is right for every stop but the last, until one of "
		.. "the two sliders gets a floor." },
	["Chat/Window.lua"] = { bare =
		"the chat window's entry line, on the same two sliders as the log above "
		.. "it and left flat for the same reason." },
}

------------------------------------------------------------
-- Is there a surface under this glyph
------------------------------------------------------------

-- Opaque enough that Unit/Color.lua's palette can be trusted on it. Below this
-- the world is showing through and the string is over the world whatever the
-- frame it is parented to looks like in a screenshot.
local SOLID = 0.6

-- Three things count as something to stand on, and the two that are not a
-- colour are the ones this got wrong first time.
--
-- A colour the addon painted over the whole frame, near enough opaque. That is
-- every panel and window surface in the addon and is what the rule is mostly
-- about.
--
-- Art, meaning a texture set from a file path. A spell icon is set that way and
-- carries no alpha at all, and it is cropped rather than pinned corner to
-- corner, so a coverage test throws it away. Every shadowed number in the addon
-- is standing on one: without this the aura square's timer and count read as a
-- hundred and sixty eight strings over the world.
--
-- A status bar's own fill, which the client keeps off the region list where
-- GetRegions cannot see it. The four strings on each skinned unit frame sit on
-- Blizzard's health and power bars, which is a surface, and it is the client's
-- rather than ours.
-- A colour that is not pinned corner to corner still counts if it runs the
-- width of the frame and is taller than the glyph standing on it. That is the
-- title bar: a window's chrome is a band across the top, it is opaque, and
-- Window:SetOpacity does not touch it, so a window dragged to nothing still has
-- a strip of chrome under its own title.
--
-- The two halves are what keep this from accepting a hairline. An edge from
-- ns.Outline spans the top the same way and is one pixel tall, and the two down
-- the sides are anchored to one edge rather than across.
local function Spans(r, size)
	local left, right = false, false
	for _, pt in ipairs(r.points or {}) do
		local name = pt[1] or ""
		left = left or name:find("LEFT") ~= nil
		right = right or name:find("RIGHT") ~= nil
	end
	return left and right and (r.height or 0) >= (size or 0)
end

-- A texture given an explicit size that is most of the frame it is in.
--
-- This is the aura square's icon: it is one anchor and a size rather than four
-- corners, because the square crops it, so neither test above sees it. Measured
-- against the frame rather than against the glyph on purpose. A loot row also
-- carries an icon and it is also bigger than the text beside it, but it is a
-- sixteen pixel square in a two hundred pixel row and it is not a surface for
-- anything except itself.
local function Covers(r, frame)
	local fw, fh = frame.width or 0, frame.height or 0
	if fw <= 0 or fh <= 0 then
		return false
	end
	return (r.width or 0) >= fw * 0.8 and (r.height or 0) >= fh * 0.8
end

local function Backing(frame, size)
	if frame.kind == "statusbar" and frame.fill then
		return true
	end
	for _, r in ipairs(frame.regions or {}) do
		-- Covering is required of art exactly as it is of a colour. Letting any
		-- texture with a file path count was the first version of this and it
		-- was too generous by a long way: a loot row carries the item's icon at
		-- its left edge, and that made the whole row look like a surface for
		-- the name sitting beside it. Twenty six rows passed a rule they should
		-- have been measured by.
		if r.kind == "texture"
			and (r.allPoints or Spans(r, size) or Covers(r, frame)) then
			if r.texture ~= nil then
				return true
			end
			if r.a and r.a >= SOLID then
				return true
			end
		end
	end
	return false
end

local function Surface(text, size)
	local node = text.parent
	while node and node ~= _G.UIParent and node ~= _G.WorldFrame do
		if Backing(node, size) then
			return true
		end
		node = node.parent
	end
	return false
end

------------------------------------------------------------
-- One pass over every string there is
------------------------------------------------------------

local function Sweep(why)
	local bad, total = {}, 0
	local seen = {}
	for _, frame in ipairs(frames) do
		for _, r in ipairs(frame.regions or {}) do
			if r.kind == "fontstring" and not seen[r] then
				seen[r] = true
				local path, size, flags = r:GetFont()
				-- A string nothing has drawn into yet has no font and no role
				-- to be wrong about. The addon makes a few and fills them on
				-- first use.
				local text = r:GetText()
				if path and text and text ~= "" then
					total = total + 1
					flags = flags or ""
					local at = r.madeAt or "?"
					local file = at:gsub(":%d+$", "")
					local outlined = flags:find("OUTLINE", 1, true) ~= nil
					local function fault(rule, what)
						local exempt = ALLOWED[file]
						if exempt and exempt[rule] then
							return
						end
						bad[#bad + 1] = ("%s  %s"):format(at, what)
					end

					if outlined and size and size < floor then
						fault("floor", ("outlined at %d, under the floor of %d")
							:format(size, floor))
					end
					if not outlined and not Surface(r, size) then
						fault("bare", "not outlined and nothing painted behind it")
					end
					if flags:find("MONOCHROME", 1, true) then
						fault("mono",
							"MONOCHROME, which breaks Arial Narrow's stems")
					end
				end
			end
		end
	end
	table.sort(bad)
	for _, line in ipairs(bad) do
		check(false, ("%s (%s)"):format(line, why))
	end
	return total, #bad
end

local drawn, faults = Sweep("as it comes up")

------------------------------------------------------------
-- And again with every surface taken away
------------------------------------------------------------
--
-- Four sliders, and each one turns a background into nothing. They are named
-- here rather than found, because a setting this rule depends on that nobody
-- listed is a setting that can be added without the rule noticing.

local SLIDERS = {
	{ "lootFeedAlpha", function() ns.LootFeed.Stream():Apply() end },
	{ "combatFeedAlpha", function() ns.CombatFeed.Stream():Apply() end },
	{ "chatAlpha", function() ns.ChatWindow.Apply() end },
	{ "meterBarAlpha", function() ns.MeterWindow.Apply() end },
}

local restore = {}
for _, entry in ipairs(SLIDERS) do
	restore[entry[1]] = ns.db[entry[1]]
	ns.db[entry[1]] = 0
end
for _, entry in ipairs(SLIDERS) do
	pcall(entry[2])
end

local _, bare = Sweep("with every background slider at zero")

for key, value in pairs(restore) do
	ns.db[key] = value
end
for _, entry in ipairs(SLIDERS) do
	pcall(entry[2])
end

print(("fonts  %d strings drawn, %d wrong as it stands, %d wrong with every"
	.. " background at zero, %d sites allow-listed")
	:format(drawn, faults, bare, (function()
		local n = 0
		for _ in pairs(ALLOWED) do n = n + 1 end
		return n
	end)()))
