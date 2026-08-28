local ADDON, ns = ...

local Art = {}
ns.FrameArt = Art

--------------------------------------------------------------------------
-- Blizzard's own regions on the three unit frames
--
-- The half of the skin that touches nothing this addon made. It reads a
-- region's state before the first change reaches it, hides the artwork, keeps
-- the handful of pieces worth keeping, and hands every one of them back on
-- `/wk skin off` without a reload.
--
-- Two of the four rules in UnitFrames/Skin.lua's header are this file's, and
-- they are the two that decide what the walk does.
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
-- Nothing in here knows where the block goes or what a gauge reads. It is
-- handed an entry, it works on the regions hanging off it, and it says whether
-- combat let it finish. UnitFrames/Block.lua is the other side of that
-- boundary and UnitFrames/Skin.lua is what calls both.
--------------------------------------------------------------------------

local Gauge = ns.UI.Gauge




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

local function StripArt(entry, list)
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
	for _, other in ipairs(list) do
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
-- Public
--------------------------------------------------------------------------

-- The three regions the skin moves, recorded before the first change reaches
-- one of them. The badges are not in here: they are discovered by the walk
-- below and recorded the moment it finds them.
function Art.Remember(entry)
	for _, key in ipairs(TOUCHED) do
		Snapshot(entry[key])
	end
end

-- Everything the walk touches, recorded whether or not the skin is on. The
-- probe calls this so it prints what the client actually answered rather than
-- zeroes, and Snapshot is a no-op on anything already recorded, so it cannot
-- overwrite what a live skin is holding.
function Art.Measure(entry)
	EachTouched(entry, Snapshot)
end

-- One recorded field off one region, for the probe. Nil where nothing was ever
-- recorded, which the caller draws as zero rather than deriving a number from.
function Art.Was(object, field)
	local shot = object and memory[object]
	return shot and shot[field]
end

-- Everything the skin does to Blizzard's regions, in one call and in the order
-- it has to happen in: hide the furniture, then keep sharp the sampled art the
-- walk spared, then flatten the two bars and hold their colour shut.
--
-- `list` is every entry, not just this one, because the frames nest and the
-- walk has to know which portraits belong to a neighbour. Answers false where
-- combat refused any part of it, and the caller retries at the next
-- PLAYER_REGEN_ENABLED.
function Art.Strip(entry, list)
	local complete = StripArt(entry, list)

	-- After the strip, not before it: the badges are discovered by that walk,
	-- and the layout is about to move them.
	for _, region in pairs(entry.badges) do
		Snapshot(region)
		Crisp(region)
	end
	Crisp(entry.portrait)

	for _, key in ipairs(BARS) do
		Gauge.Flatten(entry[key])
		Freeze(entry[key], "SetStatusBarColor")
	end
	return complete
end

-- The artwork back up and the two bars back under Blizzard's own colouring.
-- Separate from Forget below because the aura rows come off between the two,
-- and a region reverted before its row is taken down is a row anchored to
-- something that has already moved.
function Art.Restore(entry)
	for _, key in ipairs(BARS) do
		Thaw(entry[key], "SetStatusBarColor")
		-- Revert is about to put the file path back on this bar's fill, so the
		-- flatten guard has to forget that it ever saw it flat.
		entry[key].wkFlat = nil
	end
	return RestoreArt(entry)
end

-- Every region handed back the state it arrived with, and the memory of it
-- dropped. Last, because everything above still reads what this throws away.
function Art.Forget(entry)
	EachTouched(entry, Revert)
end

-- The state icons the walk kept, for the file that has to place them. One
-- table rather than two, because which of Blizzard's regions are spared is
-- this file's question and which corner each one lands on is the block's, and
-- a table split down that seam is two lists free to disagree about how many
-- badges there are.
function Art.Badges()
	return BADGES
end

-- The two status bars, by the key each hangs off the entry on. Taken from here
-- rather than written out again, for the reason the badges are: the block pins
-- both of them to a rail and the walk keeps both of their fills, and two lists
-- of the same two names are two chances to add a third to one of them.
function Art.Bars()
	return BARS
end
