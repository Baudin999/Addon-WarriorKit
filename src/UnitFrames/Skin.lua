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
-- Four rules shape it, and the first two are the artwork part's.
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
--   Fit the frame to the block, not the block to the frame. The block used
--   to hang off the portrait's own anchor inside a frame five times its size,
--   and everything that reads a unit frame's rectangle read that one: Edit
--   Mode selected it, snapped it against other frames and saved it, while
--   what you could see sat somewhere inside it, and the empty three quarters
--   went on eating clicks. So the block is anchored to the frame's own corner
--   now and the frame is sized to the block. What Edit Mode drags is what is
--   drawn, the hit region is the block, and Blizzard's auras and target of
--   target follow the frame in rather than hanging where a 232 by 100 frame
--   left them. The frame's size is put back by `/wk skin off`, like every
--   other change here.
--
--   Draw on the grid, measure off it. Everything this file creates goes on
--   the pixel grid in UI/Pixel.lua, so a size written here as 34 means 34
--   physical pixels and a hairline is one. Nothing the client owns can go
--   with it: the portrait and the two bars are regions of a secure unit
--   button and the addon must not scale, reparent or hide one of them. So
--   the boundary runs between what we made and what we borrowed, and every
--   number that crosses it is converted and snapped. What cannot cross is
--   position. The block sits on a corner of a frame that is not on the grid
--   and that Edit Mode positions in its own units, so where the whole block
--   lands is a fraction of a pixel no addon can read, exactly as a bar on a
--   nameplate is. The geometry is exact; the origin is Blizzard's.

local REFRESH = 0.2

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

-- How much of the gauge the health bar takes. The rest is power, less the
-- three hairlines: one along the top, one along the bottom, one between.
local HEALTH_SHARE = 0.70

-- Target of target against the other two. It is a glance, not a frame you
-- read, and Blizzard parks it across the target's aura row, so it is the one
-- that has to stay out of the way.
local TOT_SCALE = 0.62

-- The gap between the target block and target of target under it, in pixels.
-- Blizzard's own anchor for that frame was written against a 232 by 100
-- target frame and means nothing once the frame is the size of the block, so
-- this file places it and this is the whole of the placement.
local TOT_GAP = 3

-- Below this many pixels tall a power bar cannot hold a readable number, so it
-- carries none. Target of target is the frame that hits it.
local VALUE_FLOOR = 9

-- The block's own geometry, in pixels, because everything this file draws is
-- on the grid. Three hairlines cross the square: one along the top of the
-- gauge, one along the bottom and one between the two bars.
local HAIRLINES = 3
local TEXT_PAD = 4

-- Font sizes are taken off the bar heights, because the same code draws a 34
-- pixel player frame and a 21 pixel target of target and one size cannot serve
-- both. These are the fraction of the bar a glyph gets and the range it is
-- allowed to land in.
local BIG_SHARE, BIG_MIN, BIG_MAX = 0.72, 8, 14
local SMALL_SHARE, SMALL_MIN, SMALL_MAX = 0.80, 7, 11

-- The look, and deliberately the enemy bars' look: the same flat fills, the
-- same hairline, no gloss, no gradient and no file path, so there is no art
-- asset that has to still exist on this client.
--
-- "Deliberately the enemy bars' look" used to be a comment and two copies of
-- the same nine literals. It is one table now. ns.Unit.Color is where every
-- colour the addon puts on a unit lives, and both files read it, so the two
-- cannot drift the way they were free to before.
local Unit = ns.Unit
local Color = Unit.Color
local Level = Unit.Level
local Gauge = ns.UI.Gauge

-- The stack panel the enemy bars are laid out with, which lays the block out.
local Flow = ns.UI.Flow

local BACKDROP = Color.backdrop
local NAME_TEXT = Color.text.name
local VALUE_TEXT = Color.text.value
local HEAL = Color.heal
local IDLE = Color.reaction.idle

-- What a spent track is until the first tick paints it its unit's colour.
-- ns.Fill defaulted to opaque black and ns.UI.Gauge.Underlay leaves a
-- texture uncoloured, so this is passed rather than dropped: the two paths
-- only differ on a styled frame whose unit does not exist, and a refactor
-- is the wrong place to decide that black was the wrong answer.
local BUILD_BLACK = { 0, 0, 0, 1 }

-- Only reached when a bar's original texture answers no file path, which is
-- what a bar wearing an atlas rather than a file would do. Restoring the wrong
-- 2007 texture is a worse look than the skin; restoring none at all is an
-- invisible bar, and that is the one that reads as broken.
local FALLBACK_BAR = "Interface\\TargetingFrame\\UI-StatusBar"

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

--------------------------------------------------------------------------
-- The three frames
--
-- frames  candidate globals, first one that exists wins
-- art     extra frames to walk that are not children, if a client has any
-- names   globals to fall back to when a parent key is missing
-- level   the level text, which has no parent key on any of them
-- scale   this frame's share of the height and width settings
-- mirror  the gauge sits left of the portrait rather than right of it
-- under   the key of the frame this one is parked beneath once both are
--         fitted, because its own anchor was written against the size the
--         frame no longer is
-- global  what the block this file draws over that frame is called. Named
--         rather than anonymous for one reason: the box is the frame every
--         measurement in this file is taken in, so a block that lands wrong
--         can be measured from a macro or a harness without this file
--         handing out a reference to its own internals.
--------------------------------------------------------------------------

local SPECS = {
	{
		key = "player", unit = "player", mirror = false,
		scale = 1, global = "WarriorKitSkinPlayer",
		frames = { "PlayerFrame" },
		art = { "PlayerFrameTextureFrame" },
		names = {
			portrait = { "PlayerPortrait" },
			name = { "PlayerName" },
			healthbar = { "PlayerFrameHealthBar" },
			manabar = { "PlayerFrameManaBar" },
		},
		level = { "PlayerLevelText" },
		-- Blizzard's combat feedback text: the damage number it flashes over
		-- the portrait. See the note in StripArt.
		feedback = { "PlayerHitIndicator" },
	},
	{
		-- Mirrored, because the target frame sits on the right of the screen
		-- and its portrait has always been on the outside edge. Moving it to
		-- the left would be a second change nobody asked for.
		key = "target", unit = "target", mirror = true,
		scale = 1, global = "WarriorKitSkinTarget",
		frames = { "TargetFrame" },
		art = { "TargetFrameTextureFrame" },
		-- The first icon of each aura row, which is the only one the client
		-- anchors to the frame itself. Everything after it hangs off one of
		-- these two, so these two are where the row's position is measured.
		auras = { "TargetFrameBuff1", "TargetFrameDebuff1" },
		names = {
			portrait = { "TargetFramePortrait" },
			name = { "TargetName", "TargetFrameTextureFrameName" },
			healthbar = { "TargetFrameHealthBar" },
			manabar = { "TargetFrameManaBar" },
		},
		level = { "TargetLevelText", "TargetFrameTextureFrameLevelText" },
		feedback = { "TargetFrameHitIndicator", "TargetHitIndicator" },
	},
	{
		key = "tot", unit = "targettarget", mirror = false, under = "target",
		scale = TOT_SCALE, global = "WarriorKitSkinToT",
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
		-- The client offers no getter for either half of the sampling fix, so
		-- what goes back is the client's own default rather than what was read.
		-- Snapping on and no bias is what every texture ships with, so the only
		-- way this is wrong is if something else had already turned it off, in
		-- which case that addon's next draw sets it again.
		if shot.crisp and object.SetSnapToPixelGrid then
			object:SetSnapToPixelGrid(true)
		end
		if shot.barColor then
			object:SetStatusBarTexture(shot.barPath or FALLBACK_BAR)
			object:SetStatusBarColor(shot.barColor[1], shot.barColor[2],
				shot.barColor[3], shot.barColor[4] or 1)
		end
	end)
end

-- The one piece of Blizzard art this file keeps rather than hides is sampled
-- art: a portrait render and four state icons, each a texture being resampled
-- to whatever square the layout asked for. Flat colour has nothing to get
-- wrong and needs none of this. Recorded in the snapshot so Revert knows it
-- has something to hand back.
local function Crisp(object)
	if not object then
		return
	end
	ns.UI.Crisp(object)
	if memory[object] then
		memory[object].crisp = true
	end
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
		-- Resolved by global name only, the way the level text is and for the
		-- same reason: it hangs off no parent key on either client, and asking
		-- a frame for a key it does not carry is a question whose answer
		-- depends on what that frame's metatable does with a miss.
		feedback = Piece(frame, nil, spec.feedback),
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
		-- Ours, on a bar of theirs. The walk that strips a bar's decoration
		-- reaches every texture on it, and three of them are the gauge this
		-- file drew. Kept across every entry rather than this one, for the
		-- reason the skip set is: these frames nest.
		mark(keep, other.healthTrack)
		mark(keep, other.powerTrack)
		mark(keep, other.healSlice)
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
	--
	-- The combat feedback number goes with them, and it is the one on the list
	-- that is not replaced by anything. It is drawn at Blizzard's font size,
	-- centred on a portrait that used to be twice this size, so on the block it
	-- lands across the level and the power gauge and neither number can be
	-- read. Blizzard's own art no longer exists to hold it, so there is nowhere
	-- correct to put it and hiding is the honest answer.
	local texts = { BarText(entry.healthbar), BarText(entry.manabar),
		entry.name, entry.level, entry.feedback }
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
-- The boundary
--
-- On one side of it are the three frames this file creates per unit frame,
-- which are on the pixel grid and are counted in pixels. On the other are the
-- portrait, the two bars and the state icons, which are Blizzard's, are on
-- whatever scale the unit frame carries, and are counted in that frame's own
-- units. Two numbers cross the line, both of them outbound, because nothing
-- this file reads off the client decides a size any more.
--
-- ns.Pixel(frame) takes a length out: it is one physical pixel expressed in
-- that frame's units, so a size we want to be N pixels is written on one of
-- Blizzard's regions as N times that.
--
-- Fit() takes the whole block out. The block is the size the settings ask
-- for, in pixels, and the unit frame under it is given that same rectangle in
-- its own units, which is the one number in this file whose exactness is the
-- client's business rather than ours.
--------------------------------------------------------------------------

-- The frame's own geometry, taken before the first fit and put back by
-- Unstyle. Deliberately not the Snapshot table every region goes through:
-- that records anchors too, and the anchors on the player and target frames
-- belong to Edit Mode. Handing one of those back would drag a frame the user
-- moved while the skin was on to wherever it stood at login. The anchors are
-- kept all the same, because target of target is the one frame this file
-- re-anchors, and it is the only one ever given them back.
local function RememberFrame(entry)
	if entry.frameShot then
		return
	end
	local frame, shot = entry.frame, {}
	pcall(function()
		shot.width, shot.height = frame:GetWidth(), frame:GetHeight()
		shot.points = {}
		for index = 1, frame:GetNumPoints() do
			shot.points[index] = { frame:GetPoint(index) }
		end
		-- The mouse region, which the fit pulls back off the strip the aura
		-- row hangs in. Recorded rather than assumed to be four zeroes: the
		-- client insets its own unit frames, and handing back zeroes would
		-- widen the target's hit region past anything it ever had.
		if frame.GetHitRectInsets then
			shot.insets = { frame:GetHitRectInsets() }
		end
	end)
	entry.frameShot = shot
end

local function RestoreFrame(entry)
	local shot = entry.frameShot
	if not shot then
		return
	end
	local frame = entry.frame
	entry.frameShot = nil
	pcall(function()
		if shot.width and shot.width > 0 and shot.height and shot.height > 0 then
			frame:SetSize(shot.width, shot.height)
		end
		if entry.perched and shot.points and #shot.points > 0 then
			frame:ClearAllPoints()
			for _, point in ipairs(shot.points) do
				frame:SetPoint(point[1], point[2] or frame:GetParent(),
					point[3], point[4], point[5])
			end
		end
		if shot.insets and #shot.insets == 4 and frame.SetHitRectInsets then
			frame:SetHitRectInsets(shot.insets[1], shot.insets[2],
				shot.insets[3], shot.insets[4])
		end
	end)
	entry.perched = false
	entry.auraLift = nil
end

-- Whether the unit frame refuses to be touched right now, which is what a
-- secure unit button does in combat. Everything below the boundary asks this
-- before it writes, and the caller carries the refusal to the next
-- PLAYER_REGEN_ENABLED rather than eating a lockdown error.
local function Blocked(entry)
	return ns.Blocked(entry.frame)
end

--------------------------------------------------------------------------
-- The aura row
--
-- The client hangs the target's buffs and debuffs off the target frame's
-- bottom left corner and lifts the first icon of each row by the height of
-- the art that used to hang under the bars: a target frame is 100 units tall
-- and the portrait and the two gauges stop about a third of the way up it.
-- Fitting the frame to the block took that third away, so the same lift now
-- puts the row inside the gauge, which is where a screenshot found it.
--
-- The row is not moved, and that is deliberate. Every icon in it is a child
-- of a secure unit button and is protected with it, so an addon may only
-- anchor one out of combat, and the client re-anchors the head of each row on
-- every aura the target gains or loses. A row placed by this file would be
-- back inside the gauge on the first refresh of the first fight and stay
-- there until it ended, which is the half of the day the row matters.
--
-- What moves is the edge they hang from. The frame is fitted to the block
-- plus the lift, so its bottom edge sits exactly one lift below the block and
-- the client's own arithmetic lands the row against the block's bottom. It
-- holds in combat because nothing has to be written in combat: the client
-- does the anchoring it always did, against an edge this file put in the
-- right place while it was allowed to.
--
-- The lift is measured, not assumed. Both clients write it into
-- TargetFrame.lua as a local, so it cannot be read, but where the client put
-- the icon can be: an anchor whose relative frame is the unit frame and whose
-- relative point is a bottom one carries the lift as its Y offset. Until an
-- aura has been seen there is no tail and the frame is the block exactly, and
-- a client that anchors its row below the frame rather than above it measures
-- as no lift and gets no tail either.
--
-- A tail is a strip of frame under the block, and a strip of frame takes
-- clicks and draws an Edit Mode selection. Both are pulled back off it: the
-- hit rect is inset by the tail and the selection is pinned to the block, so
-- what you can click and what you can drag are still the thing you can see.
--------------------------------------------------------------------------

-- Past this, in the frame's own units, the number did not come from the layout
-- this file is reading and is not going to be believed.
local AURA_CEILING = 96

-- The first of a region's anchors, or nothing where it has none. Written out
-- rather than called inline so the pcall below takes a function that is
-- already there: a closure per aura per relayout is garbage for nothing, and
-- an icon that has never been anchored answers zero points rather than nil.
local function AnchorOf(region)
	if region:GetNumPoints() < 1 then
		return nil
	end
	return region:GetPoint(1)
end

local function AuraLift(entry)
	local lift = 0
	-- Two of the three frames have no aura row of their own, and an empty list
	-- built to walk zero times is still a table the collector has to see.
	if not entry.spec.auras then
		return lift
	end
	for _, name in ipairs(entry.spec.auras) do
		local button = _G[name]
		if button and button.GetNumPoints and button.GetPoint then
			local ok, point, relative, relativePoint, _, y = pcall(AnchorOf, button)
			if ok and relative == entry.frame and y and y > lift
				and y <= AURA_CEILING and point and relativePoint
				and point:find("TOP") and relativePoint:find("BOTTOM") then
				lift = y
			end
		end
	end
	return lift
end

-- The unit frame, given the block's rectangle in the unit frame's own units
-- and whatever the client hangs under it.
--
-- Read back before it is written for the reason the tick reads a bar back:
-- this runs on every relayout and a SetSize is a resize of every anchor
-- underneath it, which on a unit frame is the aura row and the cast bar.
local function Fit(entry, width, height, tail)
	local frame, box = entry.frame, entry.box
	local wide = ns.UI.Convert(width, box, frame)
	local tall = ns.UI.Convert(height, box, frame)
	if not wide or not tall or wide <= 0 or tall <= 0 then
		return
	end
	-- The tail is already in the frame's units, because it was read off one of
	-- the frame's own anchors. It is the one number here that does not cross
	-- the boundary, so it is added after the conversion and not before it.
	tall = tall + (tail or 0)
	if frame:GetWidth() ~= wide or frame:GetHeight() ~= tall then
		frame:SetSize(wide, tall)
	end
	-- The mouse stops at the block. Nothing else this file does needs the
	-- insets, so they go back to zero on a frame with no tail rather than
	-- being left wherever the last layout put them.
	if frame.SetHitRectInsets then
		frame:SetHitRectInsets(0, 0, 0, tail or 0)
	end
end

-- Edit Mode draws its selection over the system it is dragging, and on this
-- client the box it drew was not the one on the screen. Pinned to the block
-- rather than to the frame, because those two are the same rectangle on every
-- frame but the target, where the frame is the block plus the strip of empty
-- the client's aura row hangs in. A selection drawn around that strip is
-- drawn around nothing you can see.
--
-- Every step is probed and nothing here exists on a client without Edit Mode,
-- where all three functions answer false and the skin is unchanged.
local function PinSelection(entry)
	local selection = entry.frame.Selection
	if type(selection) ~= "table" or type(selection.SetAllPoints) ~= "function" then
		return false
	end
	local ok = pcall(function()
		selection:ClearAllPoints()
		selection:SetAllPoints(entry.box or entry.frame)
	end)
	return ok
end

-- Edit Mode re-anchors its own selection whenever it puts one up, so pinning
-- it once at style time lasts until the next time the user opens Edit Mode.
-- The hook is the only piece of this file that cannot be taken off again,
-- which is why it does nothing at all while the skin is off.
local function HookSelection(entry)
	local frame = entry.frame
	if entry.hooked or type(frame.AnchorSelectionFrame) ~= "function"
		or type(hooksecurefunc) ~= "function" then
		return false
	end
	entry.hooked = pcall(hooksecurefunc, frame, "AnchorSelectionFrame", function()
		if entry.styled then
			PinSelection(entry)
		end
	end)
	return entry.hooked
end

--------------------------------------------------------------------------
-- The block we draw
--------------------------------------------------------------------------

-- The two textures this file draws inside Blizzard's own bars: the spent track
-- and the incoming heal slice. Both are regions of the client's bar rather than
-- of our rail beside it, and ns.UI.Gauge.Underlay carries the reason, which is
-- a bug this file shipped. The sublevels are ours to choose and are the two
-- lowest the client allows, which leaves the track under the slice and both
-- under the fill.
local TRACK_LAYER, SLICE_LAYER = -8, -7

-- One box, one divider, one text frame. It used to be two outlined boxes
-- pushed together, and two edges meeting down the middle is what made the
-- border read as furniture rather than as a frame. The portrait and the gauge
-- share one outline now with a single hairline between them, which is what the
-- enemy bars do with the mob tag for the same reason.
--
-- Three frame levels, and they are the whole z-order:
--
--   box  the unit frame's own level. Backdrop, edge and divider. It has to
--        stay at the parent's level because the portrait is a region of the
--        parent, and a box one level up would cover it.
--   bar  two levels up. Blizzard's health and power bars, carrying the two
--        spent tracks and the heal slice as regions of their own.
--   top  three levels up. Every piece of text, because font strings under a
--        status bar is exactly what the first version shipped.
local function Build(entry)
	local frame = entry.frame

	-- Ours, so all three go on the grid. SetIgnoreParentScale takes them off
	-- whatever scale the unit frame carries and a scale of 768 over the
	-- monitor's height makes one unit inside them one physical pixel, which is
	-- what lets every number in Place be a whole one. Blizzard's own regions
	-- cannot come with them: they are children of a secure unit button and
	-- rescaling one is both a protected action and a change to a frame the
	-- addon promised to hand back.
	--
	-- What the grid cannot fix here is where the block starts. It hangs off
	-- the portrait's anchor on a frame that is not on the grid, so the origin
	-- is a fraction of a pixel, the same way a bar on a nameplate takes its
	-- origin from wherever the mob is standing.
	--
	-- Adopt answers false on a client with no SetIgnoreParentScale, and
	-- nothing below cares: Place multiplies every constant by ns.Pixel, which
	-- is exactly 1 on the grid and the honest fraction off it.

	-- No textures of its own. It exists to hold the portrait's square, which
	-- is the one point on the block whose position the client decides.
	entry.slot = CreateFrame("Frame", nil, frame)
	entry.slot:EnableMouse(false)
	ns.UI.Adopt(entry.slot)

	entry.box = CreateFrame("Frame", entry.spec.global, frame)
	entry.box:EnableMouse(false)
	ns.UI.Adopt(entry.box)
	local backdrop = ns.Fill(entry.box, "BACKGROUND",
		BACKDROP[1], BACKDROP[2], BACKDROP[3], BACKDROP[4])
	backdrop:SetAllPoints()
	entry.box.edges = ns.Outline(entry.box, IDLE[1], IDLE[2], IDLE[3], 1)
	entry.divider = ns.Fill(entry.box, "BORDER", IDLE[1], IDLE[2], IDLE[3], 1)

	-- Two rails, one per bar, holding nothing but a rectangle of the right
	-- size. They are ours and they are on the grid, so their four corners are
	-- whole pixels; Blizzard's bars are then pinned to them corner to corner
	-- rather than given a size, and an anchor is resolved on the screen rather
	-- than in either frame's units. That is the whole trick: a bar whose
	-- geometry is exact without the bar ever leaving Blizzard's scale, and
	-- without a height that has to be converted and rounded to get there.
	entry.healthRail = CreateFrame("Frame", nil, entry.box)
	entry.healthRail:EnableMouse(false)
	entry.powerRail = CreateFrame("Frame", nil, entry.box)
	entry.powerRail:EnableMouse(false)

	-- The spent part of each bar, in the bar's own hue at a fifth of the
	-- brightness, so a unit at ten percent still reads as itself rather than
	-- as an empty box. Filling the bar, so it is placed once here rather than
	-- re-anchored on every relayout.
	entry.healthTrack = Gauge.Underlay(entry.healthbar, TRACK_LAYER, BUILD_BLACK)
	entry.powerTrack = Gauge.Underlay(entry.manabar, TRACK_LAYER, BUILD_BLACK)

	-- The incoming heal, between the track and the fill, on the sublevel
	-- between them. That ordering is the clamp doing itself a favour: a heal
	-- that overruns what is missing is covered by the fill rather than drawn
	-- past it, and the arithmetic below only has to be right, not defensive.
	--
	-- Anchored nowhere yet. Where it starts is where the fill stops, and that
	-- is a region the client owns and may hand back a different object for, so
	-- HealSlice pins it on the first tick and re-pins it if the object moves.
	entry.healSlice = Gauge.Underlay(entry.healthbar, SLICE_LAYER, HEAL)
	entry.healSlice:ClearAllPoints()
	entry.healSlice:Hide()

	entry.top = CreateFrame("Frame", nil, frame)
	entry.top:EnableMouse(false)
	ns.UI.Adopt(entry.top)

	-- One shared font object per size rather than a font on each string. Place
	-- picks the real size off the bar heights a moment later; these are only
	-- what the strings carry until it does.
	entry.nameText = ns.UI.Label(entry.top, BIG_MAX, NAME_TEXT, "LEFT", ns.UI.FLAT)
	entry.healthText = ns.UI.Label(entry.top, BIG_MAX, VALUE_TEXT, "RIGHT", ns.UI.FLAT)
	entry.levelText = ns.UI.Label(entry.top, SMALL_MAX, VALUE_TEXT, "LEFT", ns.UI.FLAT)
	entry.powerText = ns.UI.Label(entry.top, SMALL_MAX, VALUE_TEXT, "RIGHT", ns.UI.FLAT)
end

-- Sized off the two settings, placed on the frame's own corner, and the frame
-- resized to what came out.
--
-- The corner is the one the portrait is on, which is the left of the player
-- frame and the right of the target frame, so the block grows away from it in
-- opposite directions on the two. Nothing is measured off Blizzard's layout any
-- more. The block used to hang on the portrait's own anchor and be clamped to
-- the room the frame had left, which put the drawn rectangle somewhere inside a
-- much bigger invisible one; the frame is the drawn rectangle now, so there is
-- no room to be left and nothing to clamp against. What is inside the block
-- used to be SetPoint arithmetic with the mirror's sign threaded through every
-- offset in it, and is a tree handed to ns.UI.Flow now.
local function Place(entry)
	local spec, frame = entry.spec, entry.frame

	-- Every number below this line is a whole count of physical pixels, and px is
	-- what turns one into the units the block is drawn in. On the grid px is
	-- exactly 1 and every multiply is free. Off it, on a client with no
	-- SetIgnoreParentScale, it is the fraction that keeps the block the same
	-- physical size and its hairlines one pixel wide.
	local px = ns.Pixel(entry.box)
	-- And this is one pixel in Blizzard's units, for the handful of sizes and
	-- offsets that get written onto a region of theirs rather than one of ours.
	local theirs = ns.Pixel(frame)

	local side = math.max(math.floor(ns.db.skinHeight * spec.scale + 0.5), 16)
	local width = math.max(math.floor(ns.db.skinWidth * spec.scale + 0.5), 60)

	-- LEFT is the side the portrait is on, RIGHT the side the gauge runs to, and
	-- pull is the sign that turns an inset into an offset on whichever edge that
	-- leaves. What is left for them is what Flow cannot place: the block's corner
	-- on Blizzard's frame, four badges of theirs on the square, and four strings
	-- of ours as wide as whatever the unit happens to be called.
	local portraitEdge = spec.mirror and "RIGHT" or "LEFT"
	local gaugeEdge = spec.mirror and "LEFT" or "RIGHT"
	local pull = spec.mirror and 1 or -1

	-- The block first, on the frame's corner, then the frame given the block's
	-- rectangle. In that order: the fit converts the block's size out of the grid
	-- into the frame's units, and a block not yet sized hands it last tick's.
	entry.box:ClearAllPoints()
	entry.box:SetPoint("TOP" .. portraitEdge, frame, "TOP" .. portraitEdge, 0, 0)
	entry.box:SetSize((side + width) * px, side * px)
	entry.box:SetFrameLevel(frame:GetFrameLevel())
	ns.EdgeSize(entry.box.edges, px)

	-- Measured every time rather than once, because the first target this addon
	-- sees may carry no aura at all and the number is only readable off an icon
	-- the client has already placed. It settles on the first target that has one.
	entry.auraLift = AuraLift(entry)
	Fit(entry, (side + width) * px, side * px, entry.auraLift)
	PinSelection(entry)

	-- The z-order Build's note sets out, rewritten on every relayout.
	entry.top:ClearAllPoints()
	entry.top:SetAllPoints(entry.box)
	entry.top:SetFrameLevel(frame:GetFrameLevel() + 3)
	entry.slot:SetFrameLevel(frame:GetFrameLevel())
	entry.healthRail:SetFrameLevel(entry.box:GetFrameLevel() + 1)
	entry.powerRail:SetFrameLevel(entry.box:GetFrameLevel() + 1)

	-- Whole pixels, because the two bars have to add up to the square exactly:
	-- health plus power plus the three hairlines is the side, and a fractional
	-- share leaves a seam along one of them that reads as a rendering fault.
	local inner = side - HAIRLINES
	local health = math.floor(inner * HEALTH_SHARE)
	local power = inner - health

	-- The whole inside of the block, in one row of three: the portrait's square,
	-- the gauge, and one pixel of nothing on the far edge for the box's own
	-- outline to draw into. The divider is the square's inner column rather than
	-- a cell of its own, so the square and the gauge read as one strip with a
	-- hairline down it rather than as two boxes that happen to touch.
	--
	-- `reverse` is the whole of the mirroring: it runs the row backwards, so the
	-- target's three cells land the other way round with no sign anywhere here.
	--
	-- Every node holding a frame stretches across the axis it is not sized on. A
	-- node with neither a size nor a stretch measures zero and is handed one
	-- pixel, which is what shipped on the enemy bars' gauge and stood until
	-- somebody measured it. Both rails are measured in the harness now.
	--
	-- A rail carries no texture, only the rectangle its bar is pinned to. It used
	-- to hold the spent track, which made the gauge depend on an order between
	-- two frames the client did not keep: see the note on Underlay.
	Flow.Arrange(entry.box, {
		direction = "row", reverse = spec.mirror, align = "stretch",
		width = (side + width) * px, height = side * px,
		{ frame = entry.slot, width = side * px, align = "stretch",
			direction = "row", reverse = spec.mirror, pad = { 0, px, 0, px },
			{ grow = 1 }, { frame = entry.divider, width = px } },
		{ direction = "column", grow = 1, gap = px, align = "stretch",
			pad = { 0, px, 0, px },
			{ frame = entry.healthRail, height = health * px },
			{ frame = entry.powerRail, height = power * px } },
		{ width = px },
	})

	if entry.portrait then
		-- Inset by one pixel written in Blizzard's units, because a SetPoint
		-- offset is measured in the units of the region being placed and the
		-- portrait is theirs. The corner it is inset from is ours and is on a
		-- pixel boundary, so the square the render lands in is exact.
		entry.portrait:ClearAllPoints()
		entry.portrait:SetPoint("TOPLEFT", entry.slot, "TOPLEFT", theirs, -theirs)
		entry.portrait:SetPoint("BOTTOMRIGHT", entry.slot, "BOTTOMRIGHT", -theirs, theirs)
		-- Above everything the box draws, because the box sits at the same
		-- frame level as the frame this portrait is a region of.
		entry.portrait:SetDrawLayer("OVERLAY")
	end

	-- What the tick needs to draw an incoming heal, worked out here because all
	-- three answers change with the layout and none of them changes between two
	-- ticks. The width a heal is a fraction of is read back off the rail Flow
	-- just sized rather than derived from the settings again, so one thing
	-- decides how wide the gauge is and not two.
	entry.railPixels = math.max(math.floor(entry.healthRail:GetWidth() / px + 0.5), 1)
	-- One pixel in the units the slice is drawn in, which are the bar's and no
	-- longer the block's: the slice is a region of Blizzard's health bar now,
	-- so a width written on it crosses the boundary like every other number
	-- that lands on something of theirs.
	entry.pixel = theirs
	-- Which end of the bar the fill stops at. This file mirrors the target
	-- frame and Blizzard does not mirror the bar inside it, so the two disagree
	-- on which side is which and the bar is the one that is right. Asked rather
	-- than assumed, because a slice drawn off the wrong end of the fill is not
	-- a pixel out, it is on the wrong side of the number it is describing.
	local healthbar = entry.healthbar
	entry.healReverse = (healthbar and healthbar.GetReverseFill
		and healthbar:GetReverseFill()) or false
	-- The tick guards every write on the width it last drew, and that width is
	-- now a different number of pixels. Forgetting it here is what makes a
	-- resolution change leave a slice at the old scale until the heal changes.
	entry.healSpan = nil
	entry.healAnchor = nil

	-- Blizzard's bars take the rails corner to corner. No size is written on
	-- either one, so nothing about them has to be converted or rounded: the
	-- client resolves an anchor on the screen, and the corners it is resolving
	-- to are ours and are whole pixels.
	for index, key in ipairs(BARS) do
		entry[key]:SetFrameLevel(entry.box:GetFrameLevel() + 2)
		entry[key]:ClearAllPoints()
		entry[key]:SetAllPoints(index == 1 and entry.healthRail or entry.powerRail)
	end

	-- Sized off the block, because the same code draws a 34 pixel player frame
	-- and a 21 pixel target of target. One shared object per size; UI/Text.lua
	-- says why. Not rounded: `big` is a whole count of pixels and `px` is what
	-- one costs in units, so `big * px` is already exact and the round that sat
	-- here undid it. Shadowed, not outlined: all four sit on an opaque bar.
	local big = math.min(math.max(math.floor(health * BIG_SHARE), BIG_MIN), BIG_MAX)
	local small = math.min(math.max(math.floor(power * SMALL_SHARE), SMALL_MIN), SMALL_MAX)
	local bigFont = ns.UI.Font(big * px, ns.UI.FLAT)
	local smallFont = ns.UI.Font(small * px, ns.UI.FLAT)

	entry.nameText:SetFontObject(bigFont)
	entry.healthText:SetFontObject(bigFont)
	entry.levelText:SetFontObject(smallFont)
	entry.powerText:SetFontObject(smallFont)

	-- Floored to a whole pixel rather than left on the bar's exact centre.
	-- Half of an odd bar is half a pixel, and a glyph asked for at half a pixel
	-- is rasterised across two, which is what makes small outlined text look
	-- like it has been breathed on.
	local pad = TEXT_PAD * px
	local healthMid = -(1 + math.floor(health / 2)) * px
	local powerMid = -(2 + health + math.floor(power / 2)) * px

	-- Anchored to the square's inner corner rather than to its side, because a
	-- side point sits at half height and the vertical offsets here are all
	-- measured down from the top of the block.
	entry.healthText:ClearAllPoints()
	entry.healthText:SetPoint(gaugeEdge, entry.box, "TOP" .. gaugeEdge, pull * pad, healthMid)

	entry.nameText:ClearAllPoints()
	entry.nameText:SetPoint(portraitEdge, entry.slot, "TOP" .. gaugeEdge, -pull * pad, healthMid)
	entry.nameText:SetPoint(gaugeEdge, entry.healthText, portraitEdge, pull * pad, 0)

	-- The level goes on the power bar's inner end, which is empty on every
	-- unit in the game, and the power number on its outer end.
	entry.levelText:ClearAllPoints()
	entry.levelText:SetPoint(portraitEdge, entry.slot, "TOP" .. gaugeEdge, -pull * pad, powerMid)

	entry.powerText:ClearAllPoints()
	entry.powerText:SetPoint(gaugeEdge, entry.box, "TOP" .. gaugeEdge, pull * pad, powerMid)
	entry.powerText:SetShown(power >= VALUE_FLOOR)

	-- On the outer corners of the square, the two the gauge is not against,
	-- each centred on its corner so it half overhangs the block. Lifted to
	-- OVERLAY for the portrait's reason: the box sits at the same frame level
	-- as the frame these are regions of.
	--
	-- An even number of pixels, because the badge is centred on a corner and
	-- half of an odd one puts all four of its edges on a half pixel. The size
	-- is written in Blizzard's units, since the region is theirs.
	for _, badge in ipairs(BADGES) do
		local region = entry.badges[badge.slot]
		if region then
			local size = math.floor(side * badge.scale / 2 + 0.5) * 2 * theirs
			region:ClearAllPoints()
			region:SetSize(size, size)
			region:SetPoint("CENTER", entry.slot, badge.corner .. portraitEdge, 0, 0)
			region:SetDrawLayer("OVERLAY")
		end
	end
end

local function EntryFor(key)
	for _, entry in ipairs(entries) do
		if entry.spec.key == key then
			return entry
		end
	end
	return nil
end

-- Target of target, parked under the target block.
--
-- It has to be placed by this file once the target frame is fitted, and only
-- then. Blizzard anchored that frame against a target frame 100 units tall,
-- so the moment the target frame is the height of the block instead, its own
-- anchor points at a corner that has moved and it lands across whatever is
-- there. Anchored by the edge the two blocks share rather than by the
-- portrait's: the target is mirrored and target of target is not, so aligning
-- their outer edges is what puts one portrait under the other.
--
-- Both halves are conditional on the target being fitted, because a target
-- frame that is back at Blizzard's size wants Blizzard's anchor back with it.
local function Perch(entry)
	local host = entry.spec.under and EntryFor(entry.spec.under)
	if not host then
		return true
	end
	local want = entry.styled and host.styled and true or false
	if want == (entry.perched or false) then
		return true
	end
	if Blocked(entry) then
		return false
	end
	local frame = entry.frame
	if want then
		RememberFrame(entry)
		local edge = "TOP" .. (host.spec.mirror and "RIGHT" or "LEFT")
		local corner = "BOTTOM" .. (host.spec.mirror and "RIGHT" or "LEFT")
		frame:ClearAllPoints()
		-- Under the target's block, not under the target's frame. On the target
		-- those two have different bottom edges: the frame carries the strip
		-- the client's aura row hangs in, and hanging target of target off
		-- that would leave a gap the size of a row of icons.
		frame:SetPoint(edge, host.box or host.frame, corner, 0, -TOT_GAP * ns.Pixel(frame))
		entry.perched = true
	else
		local shot = entry.frameShot
		if shot and shot.points and #shot.points > 0 then
			frame:ClearAllPoints()
			for _, point in ipairs(shot.points) do
				frame:SetPoint(point[1], point[2] or frame:GetParent(),
					point[3], point[4], point[5])
			end
		end
		entry.perched = false
	end
	return true
end

--------------------------------------------------------------------------
-- Colour
--
-- All of it is ns.Unit.Color's now. What used to be here was a class colour
-- cache, a reaction ladder and a level tag cache, and every one of the three
-- had a twin in UnitFrames/EnemyBars.lua. The two class caches even disagreed
-- about the shape of an answer, one returning a table and one a hex string,
-- which is what happens when the same thing is written twice by the same
-- person a month apart.
--------------------------------------------------------------------------

--------------------------------------------------------------------------
-- Styling and unstyling
--------------------------------------------------------------------------

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
	-- Before Place, which is the first thing here that resizes it.
	RememberFrame(entry)
	HookSelection(entry)

	if not entry.box then
		Build(entry)
	end

	local complete = StripArt(entry)

	-- After the strip, not before it: the badges are discovered by that walk,
	-- and Place is about to move them.
	for _, region in pairs(entry.badges) do
		Snapshot(region)
		Crisp(region)
	end
	Crisp(entry.portrait)

	for _, key in ipairs(BARS) do
		Gauge.Flatten(entry[key])
		Freeze(entry[key], "SetStatusBarColor")
	end

	Place(entry)
	entry.box:Show()
	entry.top:Show()
	-- The two tracks are regions of Blizzard's bars rather than of the box, so
	-- hiding the box no longer takes them with it and showing it does not
	-- bring them back. The slice stays hidden until the tick has a heal to
	-- draw, which Place has just told it to work out again.
	entry.healthTrack:Show()
	entry.powerTrack:Show()
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
		entry.healthTrack:Hide()
		entry.powerTrack:Hide()
		entry.healSlice:Hide()
	end

	for _, key in ipairs(BARS) do
		Thaw(entry[key], "SetStatusBarColor")
		-- Revert is about to put the file path back on this bar's fill, so the
		-- flatten guard has to forget that it ever saw it flat.
		entry[key].wkFlat = nil
	end

	local complete = RestoreArt(entry)
	EachTouched(entry, Revert)
	RestoreFrame(entry)
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

local function Refresh(entry)
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

	-- Guarded on the string, which ns.Unit.Level hands over already built rather
	-- than building one per tick to compare.
	local tag = Level.Tag(unit)
	if entry.levelTag ~= tag then
		entry.levelTag = tag
		entry.levelText:SetText(tag)
	end

	-- Both re-applied rather than set once, because the bars and the portrait
	-- are Blizzard's and their own code puts a texture and a crop back on them
	-- whenever it swaps the art underneath. Both now read back first: being the
	-- last word costs one comparison in the common case, where nothing has
	-- touched either since the last tick, rather than nine writes across three
	-- frames five times a second.
	--
	-- The comparison is exact because the crop is a power of two fraction. A
	-- crop written as 0.15 would come back as whatever the client rounded it
	-- to and this guard would never hold.
	Gauge.Flatten(entry.healthbar)
	Gauge.Flatten(entry.manabar)
	local portrait = entry.portrait
	if portrait then
		local left = portrait.GetTexCoord and portrait:GetTexCoord()
		if left ~= PORTRAIT_TRIM then
			portrait:SetTexCoord(PORTRAIT_TRIM, 1 - PORTRAIT_TRIM,
				PORTRAIT_TRIM, 1 - PORTRAIT_TRIM)
		end
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
	-- After every frame has settled, not inside the loop above: where target
	-- of target goes depends on whether the target frame came out fitted, and
	-- the target is styled after it on a client that names them in that order.
	for _, entry in ipairs(entries) do
		if not Perch(entry) then
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
--
-- Anchoring a region of a secure unit button is what combat forbids, so a
-- relayout that arrives in lockdown is remembered rather than dropped. That
-- matters more now than it did: a resolution change comes through here too,
-- and a block left on the old grid is the wrong size until something else
-- happens to move it.
function Skin.Relayout()
	if not ns.db or not ns.db.skin then
		return
	end
	for _, entry in ipairs(entries) do
		if entry.styled then
			if Blocked(entry) then
				pending = true
			else
				Place(entry)
				if not Perch(entry) then
					pending = true
				end
			end
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
-- The fit, which is the line to read when Edit Mode's box is not the block.
-- What the frame was before the skin touched it, and whether this client put
-- an Edit Mode selection on it for the skin to pin: a client with none is one
-- where the fit is the whole of the answer.
local function FitText(entry)
	local shot = entry.frameShot
	local was = shot and shot.width and shot.width > 0
		and ("was %dx%d, "):format(shot.width, shot.height) or ""
	-- The aura row, which is the one piece of the layout this file places by
	-- resizing the frame rather than by anchoring anything. A row in the wrong
	-- place is either a lift that was never measured, which this says, or a
	-- lift that measured wrong, which this prints the number of.
	local row = ""
	if entry.spec.auras then
		row = entry.auraLift and entry.auraLift > 0
			and (", aura row lifted %.1f, frame tailed by the same"):format(entry.auraLift)
			or ", aura row not measured yet, no tail on the frame"
	end
	return ("%sedit mode selection %s%s%s"):format(was,
		type(entry.frame.Selection) == "table" and "pinned to the block"
			or "not on this client",
		entry.perched and (", parked under the " .. entry.spec.under) or "", row)
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
		ns.Print("  " .. FitText(entry))
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
	if ns.db.skinHeals then
		line = line .. (ns.HasHealPrediction() and ", incoming heals on the gauge"
			or ", incoming heals asked for and this client has no prediction api")
	end
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
-- Blizzard_EditMode is load on demand, so the selection this file pins may not
-- exist until the first time the user opens Edit Mode.
events:RegisterEvent("ADDON_LOADED")
-- How far above the frame's bottom edge the client starts the target's aura
-- row is a number that can only be read off an icon it has already placed, so
-- the first target carrying an aura is what settles it. Filtered to the target
-- where the client can filter: unfiltered, this is every aura on every unit in
-- range and in a raid that is thousands of calls a fight to answer a question
-- whose answer changes once.
if type(events.RegisterUnitEvent) == "function" then
	events:RegisterUnitEvent("UNIT_AURA", "target")
else
	events:RegisterEvent("UNIT_AURA")
end

events:SetScript("OnEvent", function(_, event, arg1)
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
				ns.Perf.Start("skin")
				for _, entry in ipairs(entries) do
					Refresh(entry)
				end
				ns.Perf.Stop("skin")
			end
		end)
		return
	end

	if event == "ADDON_LOADED" then
		if arg1 == "Blizzard_EditMode" then
			Skin.Relayout()
		end
		return
	end

	if event == "UNIT_AURA" then
		-- Guarded on the number and not on the event. This fires on every aura
		-- the target gains and loses, a relayout is a full pass over three
		-- frames, and the lift it is watching for changes once and then never
		-- again. The read is two anchors and no allocation.
		local target = EntryFor("target")
		if target and target.styled and target.auraLift ~= AuraLift(target) then
			Skin.Relayout()
		end
		return
	end

	if event == "PLAYER_REGEN_ENABLED" then
		if pending then
			-- Apply finishes a strip or a style combat refused. Relayout
			-- finishes a re-anchor it refused, which Apply cannot: Style
			-- returns early on a frame that is already styled, so a block on
			-- the wrong grid would stay there.
			Skin.Apply()
			Skin.Relayout()
		end
		return
	end

	Skin.Relayout()
end)

-- A resolution change moves the grid under the whole block at once, and a UI
-- scale change moves the three Blizzard frames it is anchored to without
-- moving the block, because the block is off their scale by construction. Both
-- want the same answer: measure the frames again and lay the block out on what
-- they say now. Relayout refuses in lockdown and PLAYER_REGEN_ENABLED picks it
-- up, so a monitor swapped mid pull is a block one fight out of date rather
-- than an error.
ns.UI.OnRescale(function()
	Skin.Relayout()
end)
