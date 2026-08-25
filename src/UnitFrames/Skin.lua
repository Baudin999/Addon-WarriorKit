local ADDON, ns = ...

local Skin = {}
ns.FrameSkin = Skin

-- The player frame, the target frame and target of target, wearing the enemy
-- bar's look: flat fills, one pixel edges, a square portrait, and the class
-- colour on the gauge and on the frame around it.
--
-- Nothing is rebuilt. Blizzard's frames stay where they are and keep their
-- clicks, their dropdown, their auras and their cast bar, because a frame
-- drawn from scratch here would have to earn all of that back and would fight
-- the Edit Mode layout this addon already carries. Every region this file
-- moves, resizes, recolours or hides is written down before it is touched and
-- put back by `/wk skin off`, without a reload.
--
-- Three rules shape it, and the first two are the artwork part's.
--
--   Textures go, frames stay. The ring, the banner and the backdrop are
--   regions of the unit frame, so they are walked and hidden one at a time.
--   The frame itself is never hidden: it is a secure unit button, and hiding
--   it would take targeting and the dropdown with it.
--
--   Walk the regions, do not name them, and walk the children too. This
--   client is a hybrid, TBC art under a backported Edit Mode, so a texture
--   global the wiki names may not be the one 2.5.6 has and neither may the
--   frame holding it. Naming the holders was tried and got half the job: the
--   target's ring went and the player's stayed, because the player's lives
--   somewhere this file had not guessed. Children are discovered now. What is
--   still named is the short keep list and the level text, and an absent name
--   costs one hidden icon rather than an error.
--
--   Measure Blizzard's layout rather than guessing it. The block is placed on
--   the portrait's own anchor, sized off the portrait's own height and given
--   the health bar's own width, so it lands where the frame already sat on
--   whatever numbers this client uses. The constants in SPECS are the fallback
--   for a client that answers none of those, not the plan.

local REFRESH = 0.2

-- The portrait render carries dead space around the head. Blizzard hides it
-- under the ring; with the ring gone it has to be cropped instead.
local PORTRAIT_TRIM = 0.15

-- How much of the gauge the health bar takes. The rest is power, less the
-- three hairlines: one along the top, one along the bottom, one between.
local HEALTH_SHARE = 0.70

-- Target of target against the other two. It is a glance, not a frame you
-- read, and Blizzard parks it across the target's aura row, so it is the one
-- that has to stay out of the way.
local TOT_SCALE = 0.62

-- The edge takes the fill's colour at this much of its brightness. At full
-- strength a hostile target ringed the whole block in saturated red and the
-- border shouted louder than anything inside it. The fill carries the colour;
-- the edge only has to agree with it.
local EDGE_DIM = 0.60

-- Below this many units tall a power bar cannot hold a readable number, so it
-- carries none. Target of target is the frame that hits it.
local VALUE_FLOOR = 9

-- The look, and deliberately the enemy bars' look: the same flat fills, the
-- same hairline, no gloss, no gradient and no file path, so there is no art
-- asset that has to still exist on this client.
local BACKDROP = { 0.04, 0.04, 0.05, 0.85 }
local TRACK = 0.20 -- the spent part of a bar is its own colour, this dark
local NAME_TEXT = { 0.97, 0.97, 1.00 }
local VALUE_TEXT = { 0.74, 0.76, 0.82 }

-- What the gauge and the edge around it are coloured by. A player wears their
-- class colour, which is the whole point of the setting. Anything else has no
-- class, so it falls back to what it thinks of you, on the same three colours
-- the enemy bars use for the same question.
local IDLE = { 0.42, 0.45, 0.52 }
local DIM = { 0, 0, 0 } -- scratch, rewritten by Dim() on every recolour
local HOSTILE = { 0.88, 0.25, 0.28 }
local NEUTRAL = { 0.95, 0.77, 0.25 }
local FRIENDLY = { 0.20, 0.72, 0.38 }

-- Keyed by the number UnitPowerType returns rather than by the token it
-- returns beside it, because the number is the half that has never been
-- renamed. PowerBarColor would answer this too and is a global nothing
-- installed here calls unguarded, so the five colours live here instead.
local POWER = {
	[0] = { 0.25, 0.44, 0.90 }, -- mana
	[1] = { 0.78, 0.25, 0.22 }, -- rage
	[2] = { 1.00, 0.50, 0.25 }, -- focus
	[3] = { 0.95, 0.90, 0.35 }, -- energy
	[4] = { 0.40, 0.80, 0.90 }, -- happiness
}

-- Only reached when a bar's original texture answers no file path, which is
-- what a bar wearing an atlas rather than a file would do. Restoring the wrong
-- 2007 texture is a worse look than the skin; restoring none at all is an
-- invisible bar, and that is the one that reads as broken.
local FALLBACK_BAR = "Interface\\TargetingFrame\\UI-StatusBar"

-- The same suffix vocabulary the enemy bars use, so an elite reads the same
-- way on the target frame as it does on the mob's own bar.
--
--     42   normal        42+   elite        42r   rare        42r+  rare elite
--     ??   a boss, or a level this client will not name
-- The state icons the walk must not hide, matched on the end of a region's
-- name rather than on the whole of it. Naming them outright would mean three
-- names per icon across two clients and a hybrid between them; the suffix is
-- the half that has never moved. Everything matched here is kept, re-anchored
-- to a corner of the portrait's square and left to Blizzard to show and hide,
-- because whether you are resting, fighting or flagged is their question and
-- they already answer it.
--
-- Rest and combat share a corner on purpose: Blizzard shows one or the other,
-- never both. The leader and master looter icons are deliberately absent, and
-- a line here is all either would take.
local BADGES = {
	{ pattern = "RaidTargetIcon$", slot = "marker", corner = "TOP", scale = 0.55 },
	{ pattern = "AttackIcon$", slot = "combat", corner = "TOP", scale = 0.55 },
	{ pattern = "RestIcon$", slot = "rest", corner = "TOP", scale = 0.55 },
	-- Bigger, because the PvP texture carries a wide transparent margin and
	-- renders visibly smaller than the box it is given.
	{ pattern = "PVPIcon$", slot = "pvp", corner = "BOTTOM", scale = 0.72 },
}

local CLASSIFICATION = {
	elite = "+",
	worldboss = "+",
	rareelite = "r+",
	rare = "r",
}

--------------------------------------------------------------------------
-- The three frames
--
-- frames  candidate globals, first one that exists wins
-- art     extra frames to walk that are not children, if a client has any
-- names   globals to fall back to when a parent key is missing
-- level   the level text, which has no parent key on any of them
-- scale   this frame's share of the height and width settings
-- mirror  the gauge sits left of the portrait rather than right of it
--------------------------------------------------------------------------

local SPECS = {
	{
		key = "player", unit = "player", mirror = false,
		scale = 1,
		frames = { "PlayerFrame" },
		art = { "PlayerFrameTextureFrame" },
		names = {
			portrait = { "PlayerPortrait" },
			name = { "PlayerName" },
			healthbar = { "PlayerFrameHealthBar" },
			manabar = { "PlayerFrameManaBar" },
		},
		level = { "PlayerLevelText" },
	},
	{
		-- Mirrored, because the target frame sits on the right of the screen
		-- and its portrait has always been on the outside edge. Moving it to
		-- the left would be a second change nobody asked for.
		key = "target", unit = "target", mirror = true,
		scale = 1,
		frames = { "TargetFrame" },
		art = { "TargetFrameTextureFrame" },
		names = {
			portrait = { "TargetFramePortrait" },
			name = { "TargetName", "TargetFrameTextureFrameName" },
			healthbar = { "TargetFrameHealthBar" },
			manabar = { "TargetFrameManaBar" },
		},
		level = { "TargetLevelText", "TargetFrameTextureFrameLevelText" },
	},
	{
		key = "tot", unit = "targettarget", mirror = false,
		scale = TOT_SCALE,
		frames = { "TargetFrameToT", "TargetofTargetFrame" },
		art = { "TargetFrameToTTextureFrame" },
		names = {
			portrait = { "TargetFrameToTPortrait" },
			name = { "TargetFrameToTName", "TargetFrameToTTextureFrameName" },
			healthbar = { "TargetFrameToTHealthBar" },
			manabar = { "TargetFrameToTManaBar" },
		},
		level = {},
	},
}

-- Walked by key rather than collected into a list, because a list built as
-- { entry.portrait, entry.healthbar, ... } stops at the first nil and ipairs
-- would then silently snapshot nothing on a client missing one piece.
-- The name and the level are not in here. They used to be re-anchored into
-- the gauge and they are hidden outright now, with this file drawing its own
-- pair on a frame that sits above the bars. Two problems went with them: a
-- font string is Blizzard's and sits at Blizzard's frame level, which put it
-- under our own status bars, and restoring a font it never explicitly had is
-- guesswork. Hiding is reversible in one call and drawing is fully ours.
local TOUCHED = { "portrait", "healthbar", "manabar" }
local BARS = { "healthbar", "manabar" }

-- The pieces this file mutates, in one walk. The badges are discovered during
-- the strip rather than resolved by name up front, so they cannot live in
-- TOUCHED and are walked alongside it.
local function EachTouched(entry, fn)
	for _, key in ipairs(TOUCHED) do
		fn(entry[key])
	end
	for _, region in pairs(entry.badges) do
		fn(region)
	end
end

local entries = {}
local classTint = {}
local pending = false

--------------------------------------------------------------------------
-- Remembering what was there
--
-- The non-destructive half. Everything below reads a region's state once,
-- before the first change reaches it, and Revert puts that state back. Both
-- run inside pcall for the reason ns.Measure does: a frame the addon does not
-- own may refuse a call that looks harmless, and a screenful of errors is a
-- worse outcome than a frame that stays skinned until the next reload.
--------------------------------------------------------------------------

local memory = {}

local function Snapshot(object)
	if not object or memory[object] then
		return
	end
	local shot = {}
	pcall(function()
		if object.GetNumPoints and object.GetPoint then
			shot.points = {}
			for i = 1, object:GetNumPoints() do
				shot.points[i] = { object:GetPoint(i) }
			end
		end
		-- A font string answers the size of the text currently in it, which
		-- was never set and must never be set back: restoring it would clamp
		-- the name to whatever it happened to say when the skin went on.
		shot.text = object.GetObjectType and object:GetObjectType() == "FontString"
		if object.GetSize and not shot.text then
			shot.width, shot.height = object:GetSize()
		end
		if object.GetJustifyH then
			shot.justify = object:GetJustifyH()
		end
		if object.GetFrameLevel then
			shot.level = object:GetFrameLevel()
		end
		if object.GetDrawLayer then
			shot.layer, shot.sublayer = object:GetDrawLayer()
		end
		if object.GetFont then
			shot.font = { object:GetFont() }
		end
		if object.GetTexCoord then
			shot.coords = { object:GetTexCoord() }
		end
		if object.GetStatusBarTexture then
			local texture = object:GetStatusBarTexture()
			shot.barPath = texture and texture.GetTexture and texture:GetTexture() or nil
			shot.barColor = { object:GetStatusBarColor() }
		end
	end)
	memory[object] = shot
end

local function Revert(object)
	local shot = object and memory[object]
	if not shot then
		return
	end
	memory[object] = nil
	pcall(function()
		if shot.points and #shot.points > 0 then
			object:ClearAllPoints()
			for _, point in ipairs(shot.points) do
				-- A nil relativeTo means the parent, and SetPoint reads a nil
				-- there as UIParent instead, which would fling the region off
				-- into the middle of the screen.
				object:SetPoint(point[1], point[2] or object:GetParent(),
					point[3], point[4], point[5])
			end
		end
		-- Zero is what a region anchored on all four sides answers, and
		-- SetSize(0, 0) on one of those collapses it rather than freeing it.
		if shot.width and shot.width > 0 and shot.height and shot.height > 0 then
			object:SetSize(shot.width, shot.height)
		end
		if shot.level then
			object:SetFrameLevel(shot.level)
		end
		if shot.layer then
			object:SetDrawLayer(shot.layer, shot.sublayer)
		end
		if shot.font and shot.font[1] then
			object:SetFont(shot.font[1], shot.font[2], shot.font[3])
		end
		if shot.justify then
			object:SetJustifyH(shot.justify)
		end
		if shot.coords and #shot.coords >= 8 then
			object:SetTexCoord(shot.coords[1], shot.coords[2], shot.coords[3], shot.coords[4],
				shot.coords[5], shot.coords[6], shot.coords[7], shot.coords[8])
		end
		if shot.barColor then
			object:SetStatusBarTexture(shot.barPath or FALLBACK_BAR)
			object:SetStatusBarColor(shot.barColor[1], shot.barColor[2],
				shot.barColor[3], shot.barColor[4] or 1)
		end
	end)
end

--------------------------------------------------------------------------
-- Holding a method shut
--
-- Blizzard recolours a health bar on every unit change, and a skin that only
-- painted over it afterwards would flicker green on every target. So the
-- method is swapped for a no-op and the original is kept beside it, which is
-- exactly what ns.Strip does to Show, and Thaw hands it back. Nothing here is
-- a protected action: replacing a field on a table is not one, and neither is
-- colouring a status bar.
--------------------------------------------------------------------------

local function Freeze(object, method)
	if not object or type(object[method]) ~= "function" or object["wk" .. method] then
		return
	end
	object["wk" .. method] = object[method]
	object[method] = function() end
end

local function Thaw(object, method)
	local original = object and object["wk" .. method]
	if not original then
		return
	end
	object[method] = original
	object["wk" .. method] = nil
end

-- Blizzard's own fill texture, turned into a flat colour. Swapping in a new
-- texture instead left the original parented to the bar and still drawing,
-- which is what kept the soft rounded ends of UI-StatusBar under a flat colour
-- that was doing nothing.
--
-- Re-fetched rather than cached, because a client that swaps the texture
-- object out from under the bar would leave a cached one pointing at nothing,
-- and re-applied from the tick, because the portrait's crop had to be for the
-- same reason: their code sets these back and ours has to be the last word.
local function Flatten(bar)
	local fill = bar and bar.GetStatusBarTexture and bar:GetStatusBarTexture()
	if fill and fill.SetColorTexture then
		fill:SetColorTexture(1, 1, 1, 1)
	end
	return fill
end

local function Paint(bar, color)
	if not bar then
		return
	end
	local set = bar.wkSetStatusBarColor or bar.SetStatusBarColor
	if set then
		set(bar, color[1], color[2], color[3], 1)
	end
end

--------------------------------------------------------------------------
-- Finding the pieces
--------------------------------------------------------------------------

-- The parent key first, because UnitFrame_Initialize hangs portrait, name,
-- healthbar and manabar off every one of these frames and has since vanilla,
-- and a key cannot be renamed by a client that renamed the global. The names
-- are the fallback for the pieces that never had a key.
local function Piece(frame, key, names)
	if key and frame[key] then
		return frame[key]
	end
	for _, name in ipairs(names or {}) do
		if _G[name] then
			return _G[name]
		end
	end
	return nil
end

local function Resolve(spec)
	local frame = Piece(_G, nil, spec.frames)
	if not frame or type(frame.GetRegions) ~= "function" then
		return nil
	end

	local entry = {
		spec = spec,
		frame = frame,
		level = Piece(frame, nil, spec.level),
		badges = {},
		stripped = {},
		names = {},
		hidden = 0,
		styled = false,
	}
	for key, names in pairs(spec.names) do
		entry[key] = Piece(frame, key, names)
	end
	return entry
end

--------------------------------------------------------------------------
-- Hiding the furniture
--------------------------------------------------------------------------

local function EachTexture(frame, keep, apply)
	if not frame or type(frame.GetRegions) ~= "function" then
		return true
	end
	local ok, regions = pcall(function(target)
		return { target:GetRegions() }
	end, frame)
	if not ok or not regions then
		return true
	end

	local complete = true
	for _, region in ipairs(regions) do
		if type(region) == "table" and not keep[region] and region.GetObjectType
			and region:GetObjectType() == "Texture" then
			if not apply(region) then
				complete = false
			end
		end
	end
	return complete
end

-- The status bar text is Blizzard's own numbers, on a CVar, centred on the
-- bar. The skin draws its own on the right instead, so this hides theirs
-- rather than leaving two answers stacked on one gauge.
local function BarText(bar)
	if not bar then
		return
	end
	return bar.TextString or bar.LeftText or bar.RightText
end

-- Down two levels, into child frames only. An aura icon is a Button and the
-- cast bar is a StatusBar, so testing for exactly "Frame" leaves both alone
-- while still reaching a texture frame whatever it is called. The skip set is
-- what stops the target frame's walk from stripping target of target, which is
-- one of its children and has its own portrait to keep.
local function WalkFrames(frame, depth, skip, keep, apply, seen)
	if not frame or seen[frame] then
		return true
	end
	seen[frame] = true

	local complete = EachTexture(frame, keep, apply)
	if depth <= 0 then
		return complete
	end

	local ok, children = pcall(function(target)
		return { target:GetChildren() }
	end, frame)
	if not ok or not children then
		return complete
	end

	for _, child in ipairs(children) do
		if type(child) == "table" and not skip[child] and child.GetObjectType
			and child:GetObjectType() == "Frame" then
			if not WalkFrames(child, depth - 1, skip, keep, apply, seen) then
				complete = false
			end
		end
	end
	return complete
end

local function StripArt(entry)
	-- Built across every entry, not just this one, because the frames are
	-- nested: target of target is a child of the target frame, and a walk that
	-- did not know that would hide the portrait the other entry is keeping.
	local keep, skip = {}, {}
	local function mark(into, object)
		-- A nil key is not a miss in Lua, it is an error, and box and top are
		-- both nil until the first Build has run.
		if object then
			into[object] = true
		end
	end
	for _, other in ipairs(entries) do
		mark(skip, other.frame)
		mark(skip, other.box)
		mark(skip, other.top)
		mark(skip, other.slot)
		mark(keep, other.portrait)
	end
	wipe(entry.badges)

	-- Counted into the entry and assigned rather than accumulated, because a
	-- strip that combat refused runs again at PLAYER_REGEN_ENABLED and an
	-- accumulating count would report every region twice.
	local count = 0
	local complete = true
	wipe(entry.names)
	local function apply(region)
		local ok, found = pcall(function(target)
			return target:GetName()
		end, region)
		local name = ok and found or nil

		-- Kept rather than hidden, and not counted: the count is what the
		-- probe reports as regions removed, and a badge was never removed.
		if name then
			for _, badge in ipairs(BADGES) do
				if name:find(badge.pattern) then
					entry.badges[badge.slot] = region
					return true
				end
			end
		end

		entry.stripped[region] = true
		count = count + 1
		if #entry.names < 24 then
			entry.names[#entry.names + 1] = name or "unnamed"
		end
		return ns.Strip(region)
	end

	-- The two bars are walked by name rather than reached by the recursion,
	-- because a status bar is not a Frame and the type test that keeps aura
	-- buttons and the cast bar out of the walk keeps these out too. Anything
	-- decorative parented to a bar survived that gap, which is why the rage
	-- bar kept a rounded end after its fill had already been flattened. Each
	-- bar's own fill is kept, or the walk would hide the gauge itself.
	for _, key in ipairs(BARS) do
		local fill = entry[key].GetStatusBarTexture and entry[key]:GetStatusBarTexture()
		mark(keep, fill)
	end

	local seen = {}
	if not WalkFrames(entry.frame, 2, skip, keep, apply, seen) then
		complete = false
	end
	for _, key in ipairs(BARS) do
		if not EachTexture(entry[key], keep, apply) then
			complete = false
		end
	end
	for _, name in ipairs(entry.spec.art) do
		if not WalkFrames(_G[name], 1, skip, keep, apply, seen) then
			complete = false
		end
	end

	-- Font strings are not textures, so the walk never reaches them. Blizzard's
	-- name, its level and the two status bar numbers all go, because this file
	-- draws its own pair and two answers stacked on one gauge is worse than
	-- either.
	local texts = { BarText(entry.healthbar), BarText(entry.manabar),
		entry.name, entry.level }
	for _, text in pairs(texts) do
		entry.stripped[text] = true
		count = count + 1
		if not ns.Strip(text) then
			complete = false
		end
	end

	entry.hidden = count
	return complete
end

local function RestoreArt(entry)
	local complete = true
	for region in pairs(entry.stripped) do
		if ns.Unstrip(region) then
			entry.stripped[region] = nil
		else
			complete = false
		end
	end
	if complete then
		entry.hidden = 0
	end
	return complete
end

--------------------------------------------------------------------------
-- The block we draw
--------------------------------------------------------------------------

local function Text(parent, size, color, justify)
	local text = parent:CreateFontString(nil, "OVERLAY")
	text:SetFont((GameFontNormal:GetFont()), size, "OUTLINE")
	text:SetTextColor(color[1], color[2], color[3])
	text:SetJustifyH(justify or "LEFT")
	if text.SetWordWrap then
		text:SetWordWrap(false)
	end
	return text
end

-- One box, one divider, one text frame. It used to be two outlined boxes
-- pushed together, and two edges meeting down the middle is what made the
-- border read as furniture rather than as a frame. The portrait and the gauge
-- share one outline now with a single hairline between them, which is what the
-- enemy bars do with the mob tag for the same reason.
--
-- Three frame levels, and they are the whole z-order:
--
--   box  the unit frame's own level. Backdrop, edge, divider and the two
--        tracks. It has to stay at the parent's level because the portrait is
--        a region of the parent, and a box one level up would cover it.
--   bar  two levels up. Blizzard's health and power bars.
--   top  three levels up. Every piece of text, because font strings under a
--        status bar is exactly what the first version shipped.
local function Build(entry)
	local frame = entry.frame

	-- No textures of its own. It exists to hold the portrait's square, which
	-- is the one point on the block whose position the client decides.
	entry.slot = CreateFrame("Frame", nil, frame)
	entry.slot:EnableMouse(false)

	entry.box = CreateFrame("Frame", nil, frame)
	entry.box:EnableMouse(false)
	local backdrop = ns.Fill(entry.box, "BACKGROUND",
		BACKDROP[1], BACKDROP[2], BACKDROP[3], BACKDROP[4])
	backdrop:SetAllPoints()
	entry.box.edges = ns.Outline(entry.box, IDLE[1], IDLE[2], IDLE[3], 1)
	entry.divider = ns.Fill(entry.box, "BORDER", IDLE[1], IDLE[2], IDLE[3], 1)

	-- The spent part of each bar, in the bar's own hue at a fifth of the
	-- brightness, so a unit at ten percent still reads as itself rather than
	-- as an empty box.
	entry.healthTrack = ns.Fill(entry.box, "ARTWORK", 0, 0, 0, 1)
	entry.powerTrack = ns.Fill(entry.box, "ARTWORK", 0, 0, 0, 1)

	entry.top = CreateFrame("Frame", nil, frame)
	entry.top:EnableMouse(false)

	entry.nameText = Text(entry.top, 11, NAME_TEXT, "LEFT")
	entry.healthText = Text(entry.top, 11, VALUE_TEXT, "RIGHT")
	entry.levelText = Text(entry.top, 9, VALUE_TEXT, "LEFT")
	entry.powerText = Text(entry.top, 9, VALUE_TEXT, "RIGHT")
end

-- Placed on the portrait's own anchor, sized off the two settings. The anchor
-- is measured because only the client knows where the frame sits; the size is
-- a setting because only you know how tall you want it, and the first shipped
-- guess was a square as tall as Blizzard's portrait, which crowded the text
-- and dropped target of target straight onto the target's auras.
--
-- Everything is anchored off `slot`, the portrait's square. The block cannot
-- be anchored by a corner of its own, because the anchor read off the client
-- names the portrait's corner and the portrait is on the left of the player
-- frame and the right of the target frame: the same anchor has to grow the
-- block in opposite directions. The square is the fixed point in both.
local function Place(entry)
	local spec, frame = entry.spec, entry.frame
	local px = ns.Pixel(frame)

	local side = math.max(math.floor(ns.db.skinHeight * spec.scale), 16)
	local width = math.max(math.floor(ns.db.skinWidth * spec.scale), 60)

	-- Never draw wider or taller than the frame being skinned. The space
	-- around these rectangles is not empty: the target's auras run along the
	-- bottom of the target frame and target of target sits in the same strip.
	local room = ns.Measure(frame, "GetWidth")
	if room and room > 60 then
		width = math.max(math.min(width, room - side - 2), 50)
	end
	local tall = ns.Measure(frame, "GetHeight")
	if tall and tall > 20 and side > tall then
		side = tall
	end

	-- LEFT is the side the portrait is on, RIGHT the side the gauge runs to,
	-- and pull is the sign that turns an inset into an offset on whichever
	-- edge that leaves. Mirroring the frame swaps all three and nothing else.
	local portraitEdge = spec.mirror and "RIGHT" or "LEFT"
	local gaugeEdge = spec.mirror and "LEFT" or "RIGHT"
	local pull = spec.mirror and 1 or -1

	local shot = entry.portrait and memory[entry.portrait]
	local anchor = shot and shot.points and shot.points[1]

	entry.slot:ClearAllPoints()
	if anchor then
		entry.slot:SetPoint(anchor[1], anchor[2] or frame, anchor[3], anchor[4], anchor[5])
	else
		entry.slot:SetPoint("TOP" .. portraitEdge, frame, "TOP" .. portraitEdge,
			-pull * side / 2, -side / 2)
	end
	entry.slot:SetSize(side, side)
	entry.slot:SetFrameLevel(frame:GetFrameLevel())

	entry.box:ClearAllPoints()
	entry.box:SetPoint("TOP" .. portraitEdge, entry.slot, "TOP" .. portraitEdge, 0, 0)
	entry.box:SetSize(side + width, side)
	entry.box:SetFrameLevel(frame:GetFrameLevel())
	ns.EdgeSize(entry.box.edges, px)

	entry.top:ClearAllPoints()
	entry.top:SetAllPoints(entry.box)
	entry.top:SetFrameLevel(frame:GetFrameLevel() + 3)

	local inner = side - px * 3
	local health = math.floor(inner * HEALTH_SHARE)
	local power = inner - health

	if entry.portrait then
		entry.portrait:ClearAllPoints()
		entry.portrait:SetPoint("TOPLEFT", entry.slot, "TOPLEFT", px, -px)
		entry.portrait:SetPoint("BOTTOMRIGHT", entry.slot, "BOTTOMRIGHT", -px, px)
		-- Above everything the box draws, because the box sits at the same
		-- frame level as the frame this portrait is a region of.
		entry.portrait:SetDrawLayer("OVERLAY")
	end

	-- One hairline where the square meets the gauge, drawn on the square's
	-- inner edge, so the two read as one strip rather than as two boxes that
	-- happen to touch.
	entry.divider:ClearAllPoints()
	entry.divider:SetPoint("TOP" .. gaugeEdge, entry.slot, "TOP" .. gaugeEdge, 0, -px)
	entry.divider:SetPoint("BOTTOM" .. gaugeEdge, entry.slot, "BOTTOM" .. gaugeEdge, 0, px)
	entry.divider:SetWidth(px)

	-- The gauge is everything past the divider. Both bars are pinned on both
	-- sides rather than given a width, so they fill it exactly however the
	-- numbers round.
	local function Span(region, top, height)
		local y = top and -px or -(px * 2 + health)
		region:ClearAllPoints()
		region:SetPoint("TOP" .. gaugeEdge, entry.box, "TOP" .. gaugeEdge, pull * px, y)
		region:SetPoint("TOP" .. portraitEdge, entry.slot, "TOP" .. gaugeEdge, 0, y)
		region:SetHeight(height)
	end

	for index, key in ipairs(BARS) do
		entry[key]:SetFrameLevel(entry.box:GetFrameLevel() + 2)
		Span(entry[key], index == 1, index == 1 and health or power)
	end
	Span(entry.healthTrack, true, health)
	Span(entry.powerTrack, false, power)

	-- Sized off the block rather than off a constant, because the same code
	-- draws a 34 unit player frame and a 21 unit target of target and one font
	-- size cannot serve both.
	local font = (GameFontNormal:GetFont())
	local big = math.min(math.max(math.floor(health * 0.72), 8), 14)
	local small = math.min(math.max(math.floor(power * 0.80), 7), 11)

	entry.nameText:SetFont(font, big, "OUTLINE")
	entry.healthText:SetFont(font, big, "OUTLINE")
	entry.levelText:SetFont(font, small, "OUTLINE")
	entry.powerText:SetFont(font, small, "OUTLINE")

	local healthMid = -(px + health / 2)
	local powerMid = -(px * 2 + health + power / 2)

	-- Anchored to the square's inner corner rather than to its side, because a
	-- side point sits at half height and the vertical offsets here are all
	-- measured down from the top of the block.
	entry.healthText:ClearAllPoints()
	entry.healthText:SetPoint(gaugeEdge, entry.box, "TOP" .. gaugeEdge, pull * 4, healthMid)

	entry.nameText:ClearAllPoints()
	entry.nameText:SetPoint(portraitEdge, entry.slot, "TOP" .. gaugeEdge, -pull * 4, healthMid)
	entry.nameText:SetPoint(gaugeEdge, entry.healthText, portraitEdge, pull * 4, 0)

	-- The level goes on the power bar's inner end, which is empty on every
	-- unit in the game, and the power number on its outer end.
	entry.levelText:ClearAllPoints()
	entry.levelText:SetPoint(portraitEdge, entry.slot, "TOP" .. gaugeEdge, -pull * 4, powerMid)

	entry.powerText:ClearAllPoints()
	entry.powerText:SetPoint(gaugeEdge, entry.box, "TOP" .. gaugeEdge, pull * 4, powerMid)
	entry.powerText:SetShown(power >= VALUE_FLOOR)

	-- On the outer corners of the square, the two the gauge is not against,
	-- each centred on its corner so it half overhangs the block. Lifted to
	-- OVERLAY for the portrait's reason: the box sits at the same frame level
	-- as the frame these are regions of.
	for _, badge in ipairs(BADGES) do
		local region = entry.badges[badge.slot]
		if region then
			region:ClearAllPoints()
			region:SetSize(side * badge.scale, side * badge.scale)
			region:SetPoint("CENTER", entry.slot, badge.corner .. portraitEdge, 0, 0)
			region:SetDrawLayer("OVERLAY")
		end
	end
end

--------------------------------------------------------------------------
-- Colour
--------------------------------------------------------------------------

-- Cached per class rather than built per tick, so the identity guards below
-- work and nothing allocates five times a second.
local function ClassTint(unit)
	local _, class = UnitClass(unit)
	if not class then
		return nil
	end
	if classTint[class] then
		return classTint[class]
	end
	local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	if not color then
		return nil
	end
	classTint[class] = { color.r, color.g, color.b }
	return classTint[class]
end

-- The edge's colour, written into one scratch table rather than allocated,
-- because this is reached from the tick.
local function Dim(color)
	DIM[1], DIM[2], DIM[3] = color[1] * EDGE_DIM, color[2] * EDGE_DIM, color[3] * EDGE_DIM
	return DIM
end

local function Tint(unit)
	if UnitIsPlayer(unit) then
		local tint = ClassTint(unit)
		if tint then
			return tint
		end
	end
	local reaction = UnitReaction(unit, "player")
	if not reaction then
		return IDLE
	end
	if reaction >= 5 then
		return FRIENDLY
	end
	return reaction == 4 and NEUTRAL or HOSTILE
end

--------------------------------------------------------------------------
-- Styling and unstyling
--------------------------------------------------------------------------

local function Blocked(entry)
	return ns.Blocked(entry.frame)
end

local function Style(entry)
	if entry.styled then
		return true
	end
	-- Anchoring and resizing a protected region is what combat forbids, and
	-- these are children of a secure unit button. Everything else here would
	-- go through in combat, but half a skin is worse than none, so the whole
	-- of it waits for PLAYER_REGEN_ENABLED together.
	if Blocked(entry) then
		return false
	end
	if not entry.healthbar or not entry.manabar then
		return true -- nothing to skin on this client, and saying so is Describe's job
	end

	for _, key in ipairs(TOUCHED) do
		Snapshot(entry[key])
	end

	if not entry.box then
		Build(entry)
	end

	local complete = StripArt(entry)

	-- After the strip, not before it: the badges are discovered by that walk,
	-- and Place is about to move them.
	for _, region in pairs(entry.badges) do
		Snapshot(region)
	end

	for _, key in ipairs(BARS) do
		Flatten(entry[key])
		Freeze(entry[key], "SetStatusBarColor")
	end

	Place(entry)
	entry.box:Show()
	entry.top:Show()
	entry.tint, entry.power, entry.levelTag = nil, nil, nil
	entry.shownPercent, entry.shownPower, entry.shownName = nil, nil, nil
	entry.styled = true
	return complete
end

local function Unstyle(entry)
	if not entry.styled then
		return true
	end
	if Blocked(entry) then
		return false
	end

	entry.styled = false
	if entry.box then
		entry.box:Hide()
		entry.top:Hide()
	end

	for _, key in ipairs(BARS) do
		Thaw(entry[key], "SetStatusBarColor")
	end

	local complete = RestoreArt(entry)
	EachTouched(entry, Revert)
	return complete
end

--------------------------------------------------------------------------
-- The tick
--
-- Five times a second, the same rate the enemy bars run at, and for the same
-- reason the artwork part does not use events: the event names that carry
-- health and power have been renamed twice between these two clients and a
-- missed one is a bar that lies. Everything here takes a unit token and nil
-- guards, because anything a ticker does has to be incapable of raising.
--------------------------------------------------------------------------

local function Refresh(entry)
	local unit = entry.spec.unit
	if not entry.styled or not UnitExists(unit) then
		return
	end

	local tint = Tint(unit)
	if entry.tint ~= tint then
		entry.tint = tint
		Paint(entry.healthbar, tint)
		entry.healthTrack:SetColorTexture(tint[1] * TRACK, tint[2] * TRACK, tint[3] * TRACK, 0.9)
		local edge = Dim(tint)
		ns.Recolor(entry.box.edges, edge)
		entry.divider:SetColorTexture(edge[1], edge[2], edge[3], 1)
	end

	local powerType = UnitPowerType(unit)
	local maxPower = UnitPowerMax(unit) or 0
	local power = (maxPower > 0 and POWER[powerType]) or IDLE
	if entry.power ~= power then
		entry.power = power
		Paint(entry.manabar, power)
		entry.powerTrack:SetColorTexture(power[1] * TRACK, power[2] * TRACK, power[3] * TRACK, 0.9)
	end

	-- Compared as the integers that get drawn, the same way the enemy bars do
	-- it. A SetText costs a string measure and a relayout whether or not the
	-- text changed, and a player at full health is the common case.
	local health, maxHealth = UnitHealth(unit) or 0, UnitHealthMax(unit) or 0
	local percent = maxHealth > 0 and math.floor(health / maxHealth * 100) or -1
	if entry.shownPercent ~= percent then
		entry.shownPercent = percent
		entry.healthText:SetText(percent >= 0 and (percent .. "%") or "")
	end

	local shownPower = maxPower > 0 and (UnitPower(unit) or 0) or -1
	if entry.shownPower ~= shownPower then
		entry.shownPower = shownPower
		entry.powerText:SetText(shownPower >= 0 and tostring(shownPower) or "")
	end

	local name = UnitName(unit) or ""
	if entry.shownName ~= name then
		entry.shownName = name
		entry.nameText:SetText(name)
	end

	-- Guarded on the string, because the level of a unit changes when the unit
	-- does and this runs five times a second for each of three frames.
	local level = UnitLevel(unit) or 0
	local tag = level > 0 and tostring(level) or "??"
	local suffix = CLASSIFICATION[ns.Classification(unit) or "normal"]
	if suffix then
		tag = tag .. suffix
	end
	if entry.levelTag ~= tag then
		entry.levelTag = tag
		entry.levelText:SetText(tag)
	end

	-- Both re-applied rather than set once, because the bars and the portrait
	-- are Blizzard's and their own code puts a texture and a crop back on them
	-- whenever it swaps the art underneath.
	Flatten(entry.healthbar)
	Flatten(entry.manabar)
	if entry.portrait then
		entry.portrait:SetTexCoord(PORTRAIT_TRIM, 1 - PORTRAIT_TRIM,
			PORTRAIT_TRIM, 1 - PORTRAIT_TRIM)
	end
end

--------------------------------------------------------------------------
-- Public
--------------------------------------------------------------------------

-- Puts every frame where the setting says it should be. Idempotent, and safe
-- to call before the saved variables exist, the same as every other part.
-- Both halves have to agree: the part is on, and this frame has not been
-- turned off on its own. Target of target is the one worth turning off by
-- itself, because Blizzard parks it across the target's aura row.
function Skin.Wanted(key)
	return ns.db.skin and ns.db.skinFrames[key] ~= false
end

function Skin.Apply()
	if not ns.db or #entries == 0 then
		return
	end
	pending = false
	for _, entry in ipairs(entries) do
		local complete
		if Skin.Wanted(entry.spec.key) then
			complete = Style(entry)
		else
			complete = Unstyle(entry)
		end
		if not complete then
			pending = true
		end
	end
	-- Painted here rather than left to the next tick, because up to a fifth of
	-- a second of a white gauge is exactly long enough to read as a bug.
	for _, entry in ipairs(entries) do
		Refresh(entry)
	end
end

-- Blizzard re-lays a unit frame out when the unit under it changes, so the
-- block is put back on its anchors then rather than trusted to stay.
function Skin.Relayout()
	if not ns.db or not ns.db.skin then
		return
	end
	for _, entry in ipairs(entries) do
		if entry.styled and not Blocked(entry) then
			Place(entry)
		end
	end
end

-- How many regions the last apply hid. Zero with the skin on is the answer
-- worth seeing: it means the walk found no textures on these frames, which
-- says this client builds them out of something else rather than that they
-- were already bare.
function Skin.Hidden()
	local count = 0
	for _, entry in ipairs(entries) do
		count = count + entry.hidden
	end
	return count
end

function Skin.Deferred()
	return pending
end

-- What the client actually answered, printed rather than guessed at. Every
-- number the layout is built from comes out here, so a block that lands in the
-- wrong place is one line of output rather than another round of inference.
local function AnchorText(entry)
	local shot = entry.portrait and memory[entry.portrait]
	local point = shot and shot.points and shot.points[1]
	if not point then
		return "no anchor recorded"
	end
	local relative = point[2]
	local name = relative and relative.GetName and relative:GetName() or "parent"
	return ("%s to %s %s %d,%d"):format(point[1], name, point[3] or "?",
		math.floor(point[4] or 0), math.floor(point[5] or 0))
end

function Skin.Probe()
	if #entries == 0 then
		ns.Print("skin: none of the three unit frames exist under any name this addon knows.")
		return
	end
	for _, entry in ipairs(entries) do
		-- Taken here as well, so the probe answers with real numbers while the
		-- skin is off. Snapshot is a no-op on anything already recorded, so it
		-- cannot overwrite what a live skin is holding.
		EachTouched(entry, Snapshot)

		local spec = entry.spec
		ns.Print(("%s: %s %dx%d, portrait %s %d tall, bar %d wide, %s"):format(
			spec.key, spec.frames[1],
			math.floor(ns.Measure(entry.frame, "GetWidth") or 0),
			math.floor(ns.Measure(entry.frame, "GetHeight") or 0),
			entry.portrait and "found" or "MISSING",
			math.floor((entry.portrait and memory[entry.portrait]
				and memory[entry.portrait].height) or 0),
			math.floor((entry.healthbar and memory[entry.healthbar]
				and memory[entry.healthbar].width) or 0),
			entry.styled and ("skinned, " .. entry.hidden .. " hidden") or "not skinned"))
		ns.Print("  portrait anchor " .. AnchorText(entry))
		local kept = {}
		for slot in pairs(entry.badges) do
			kept[#kept + 1] = slot
		end
		if #kept > 0 then
			ns.Print("  kept " .. table.concat(kept, " "))
		end
		if #entry.names > 0 then
			ns.Print("  hid " .. table.concat(entry.names, " "))
		end
	end
end

function Skin.Describe()
	if #entries == 0 then
		return "no unit frames found, this client names them something else"
	end
	local missing = 0
	for _, entry in ipairs(entries) do
		if not entry.healthbar or not entry.manabar then
			missing = missing + 1
		end
	end
	if not ns.db.skin then
		return "Blizzard frames, untouched"
	end
	local off = {}
	for _, entry in ipairs(entries) do
		if not Skin.Wanted(entry.spec.key) then
			off[#off + 1] = entry.spec.key
		end
	end
	local line = ("square frames, %d regions hidden"):format(Skin.Hidden())
	if missing > 0 then
		line = line .. (", %d of 3 frames had no bars to skin"):format(missing)
	end
	if #off > 0 then
		line = line .. ", " .. table.concat(off, " and ") .. " left alone"
	end
	if pending then
		line = line .. ", the rest follows when combat drops"
	end
	return line
end

--------------------------------------------------------------------------

local elapsed = 0
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")

events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		for _, spec in ipairs(SPECS) do
			local entry = Resolve(spec)
			if entry then
				entries[#entries + 1] = entry
			end
		end
		Skin.Apply()

		events:SetScript("OnUpdate", function(_, delta)
			elapsed = elapsed + delta
			if elapsed >= REFRESH then
				elapsed = 0
				for _, entry in ipairs(entries) do
					Refresh(entry)
				end
			end
		end)
		return
	end

	if event == "PLAYER_REGEN_ENABLED" then
		if pending then
			Skin.Apply()
		end
		return
	end

	Skin.Relayout()
end)
