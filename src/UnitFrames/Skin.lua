local ADDON, ns = ...

local Skin = {}
ns.FrameSkin = Skin

-- The player frame, the target frame and target of target, wearing the enemy
-- bar's look: flat fills, one pixel edges, a square portrait, and the class
-- colour on the gauge and on the frame around it.
--
-- Almost nothing is rebuilt. Blizzard's frames stay where they are and keep
-- their clicks, their dropdown and their cast bar, because a frame drawn from
-- scratch here would have to earn all of that back and would fight the Edit
-- Mode layout this addon already carries. The target's aura row is the one
-- exception and UnitFrames/Auras.lua is where it went, along with the reason
-- it could not stay. Every region the skin moves, resizes, recolours or hides
-- is written down before it is touched and put back by `/wk skin off`, without
-- a reload.
--
-- Four rules shape the skin, and they are quoted where the code they govern
-- lives, because this file is no longer where any of it happens:
--
--   Textures go, frames stay, and walk the regions rather than naming them.
--   Both are UnitFrames/Art.lua's, which is the whole of what the skin does to
--   a region Blizzard owns: remember it, hide it, hand it back.
--
--   Fit the frame to the block, and draw on the grid while measuring off it.
--   Both are UnitFrames/Block.lua's, which is the whole of the geometry: the
--   square, the two rails, the four strings, and where the three blocks hang
--   off each other.
--
-- The fourth thing that was in here is the tick, and it is UnitFrames/Paint.lua
-- now: given a block that already exists, read the unit and write what changed.
--
-- What is left is this file, and it is the part rather than any of the three.
-- Which frames this client has, whether each one is wanted, styling and
-- unstyling them in the order that survives combat, and what the slash commands
-- and the panel are told. It owns the entry list, so it is the only file that
-- can answer which block a link or a perch hangs off, and it hands that answer
-- to Block rather than letting Block go looking.

local Art = ns.FrameArt
local Block = ns.FrameBlock
local Paint = ns.FramePaint

local REFRESH = 0.2

-- Target of target against the other two. It is a glance, not a frame you
-- read, so it is the one that has to stay out of the way. Blizzard parked it
-- across the target's aura row, which is where this addon's own rows go now,
-- so Perch tells them to hang under it rather than through it.
local TOT_SCALE = 0.62


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
--         frame no longer is. It is also what says this frame goes up and
--         down with its host's unit rather than with the player's own, which
--         is Block.Reveal's question
-- beside  the key of the frame this one hangs off sideways, gauge edge to
--         gauge edge, once both are fitted. Edit Mode positions the block
--         named here and this file positions everything against it
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
		key = "target", unit = "target", mirror = true, beside = "player",
		scale = 1, global = "WarriorKitSkinTarget",
		frames = { "TargetFrame" },
		art = { "TargetFrameTextureFrame" },
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

local entries = {}
local pending = false

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
-- The chain
--
-- Edit Mode positions the player block and nothing else. The target block
-- hangs off the player block and target of target hangs off the target block,
-- so the three are one HUD and Edit Mode keeps the one job it is good at.
-- UnitFrames/Block.lua writes the anchors; what this file adds is the only
-- part of it that needs the list, which is which entry a spec's `beside` or
-- `under` names.
--------------------------------------------------------------------------

local function EntryFor(key)
	for _, entry in ipairs(entries) do
		if entry.spec.key == key then
			return entry
		end
	end
	return nil
end

-- Edit Mode's drop, turned back into the level setting. Hooked onto the frame
-- at style time and called from Skin.Landed, and it lives here rather than in
-- Block for one reason: it is the host lookup, and the list is here.
local function Dropped(entry)
	return Block.Landed(entry, EntryFor(entry.spec.beside))
end

--------------------------------------------------------------------------
-- Styling and unstyling
--
-- The order in both directions is the whole content of these two, and it is
-- not arbitrary. Everything Blizzard owns is recorded before the first change
-- reaches it; the block is built before the walk, so the walk knows to spare
-- it; the block is placed after the walk, because the walk is what finds the
-- badges the layout moves. Coming off, the aura rows go down between the
-- artwork coming back and the regions being handed their old state, because a
-- row anchored to something already reverted is a row hanging off nothing.
--
-- Anchoring and resizing a protected region is what combat forbids, and these
-- are children of a secure unit button, so both halves ask ns.Blocked first
-- and the caller carries a refusal to the next PLAYER_REGEN_ENABLED.
--------------------------------------------------------------------------

local function Style(entry)
	if entry.styled then
		return true
	end
	-- Everything else here would go through in combat, but half a skin is
	-- worse than none, so the whole of it waits together.
	if ns.Blocked(entry.frame) then
		return false
	end
	if not entry.healthbar or not entry.manabar then
		return true -- nothing to skin on this client, and saying so is Describe's job
	end

	Art.Remember(entry)
	-- Before Place, which is the first thing here that resizes the frame.
	Block.Remember(entry)
	Block.Hook(entry, Dropped)

	if not entry.box then
		Block.Build(entry)
	end

	-- After Build, because the walk is told to spare our own three frames and
	-- the two tracks, and none of them exists until Build has run.
	local complete = Art.Strip(entry, entries)

	Block.Place(entry)
	Block.Show(entry)
	entry.tint, entry.power, entry.levelTag = nil, nil, nil
	entry.shownPercent, entry.shownPower, entry.shownName = nil, nil, nil
	entry.styled = true
	-- After entry.styled, because the rows only draw on a styled frame, and
	-- not folded into `complete` with an `and`, which would skip the call on a
	-- strip that combat had already refused.
	if not ns.FrameAuras.Style(entry) then
		complete = false
	end
	return complete
end

local function Unstyle(entry)
	if not entry.styled then
		return true
	end
	if ns.Blocked(entry.frame) then
		return false
	end

	entry.styled = false
	Block.Hide(entry)

	local complete = Art.Restore(entry)
	if not ns.FrameAuras.Unstyle(entry) then
		complete = false
	end
	Art.Forget(entry)
	Block.Restore(entry)
	return complete
end
--------------------------------------------------------------------------
-- Public
--------------------------------------------------------------------------

-- Puts every frame where the setting says it should be. Idempotent, and safe
-- to call before the saved variables exist, the same as every other part.
-- Both halves have to agree: the part is on, and this frame has not been
-- turned off on its own. Target of target is the one worth turning off by
-- itself, because Blizzard parks it where this addon's own aura rows go.
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
	-- After every frame has settled, not inside the loop above: where a frame
	-- hangs depends on whether the one it hangs off came out fitted, and the
	-- target is styled after target of target on a client that names them in
	-- that order.
	for _, entry in ipairs(entries) do
		if not Block.Link(entry, EntryFor(entry.spec.beside)) then
			pending = true
		end
		local host = EntryFor(entry.spec.under)
		if not Block.Perch(entry, host) then
			pending = true
		end
		if not Block.Reveal(entry, host) then
			pending = true
		end
	end
	-- Painted here rather than left to the next tick, because up to a fifth of
	-- a second of a white gauge is exactly long enough to read as a bug.
	for _, entry in ipairs(entries) do
		Paint.Refresh(entry)
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
			if ns.Blocked(entry.frame) then
				pending = true
			else
				Block.Place(entry)
				if not Block.Link(entry, EntryFor(entry.spec.beside)) then
					pending = true
				end
				local host = EntryFor(entry.spec.under)
				if not Block.Perch(entry, host) then
					pending = true
				end
				if not Block.Reveal(entry, host) then
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

-- The drop, from Edit Mode's own hook or from a harness standing one up.
-- Public because a drag is a scene rather than a state and there is no other
-- way to reach it: the hook needs a client with Edit Mode and a mouse on it.
function Skin.Landed()
	for _, entry in ipairs(entries) do
		if entry.spec.beside then
			Dropped(entry)
		end
	end
end

-- What a level is allowed to be. One source for the slash command, the panel's
-- stepper and the clamp a dropped drag goes through, because three copies of a
-- range is three chances for a drag to store a number the command would have
-- refused.
function Skin.LinkRange()
	return Block.Range()
end

-- What the link is doing, which is not always what the setting asks for. It
-- needs both frames skinned, so this says which half is missing rather than
-- leaving the setting on and nothing drawn.
function Skin.DescribeLink()
	if not ns.db.skinLink then
		return "the target block sits on its own Edit Mode point"
	end
	if not ns.db.skin then
		return "the link is on and waiting for the skin, which is off"
	end
	if not (Skin.Wanted("player") and Skin.Wanted("target")) then
		return "the link needs the player and target frames skinned, and one of them is off"
	end
	return ("the target block is the player block mirrored in the middle of the"
		.. " screen, %s"):format(ns.db.skinLevel == 0 and "both tops on one line"
			or ("%d pixels %s"):format(math.abs(ns.db.skinLevel),
				ns.db.skinLevel > 0 and "lower" or "higher"))
end

-- What the client actually answered, printed rather than guessed at. Every
-- number the layout is built from comes out here, so a block that lands in the
-- wrong place is one line of output rather than another round of inference.
function Skin.Probe()
	if #entries == 0 then
		ns.Print("skin: none of the three unit frames exist under any name this addon knows.")
		return
	end
	for _, entry in ipairs(entries) do
		-- Taken here as well, so the probe answers with real numbers while the
		-- skin is off.
		Art.Measure(entry)

		local spec = entry.spec
		ns.Print(("%s: %s %dx%d, portrait %s %d tall, bar %d wide, %s"):format(
			spec.key, spec.frames[1],
			math.floor(ns.Measure(entry.frame, "GetWidth") or 0),
			math.floor(ns.Measure(entry.frame, "GetHeight") or 0),
			entry.portrait and "found" or "MISSING",
			math.floor(Art.Was(entry.portrait, "height") or 0),
			math.floor(Art.Was(entry.healthbar, "width") or 0),
			entry.styled and ("skinned, " .. entry.hidden .. " hidden") or "not skinned"))
		ns.Print("  " .. Block.Probe(entry))
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
	local line = ("square frames, %d regions hidden, %s"):format(Skin.Hidden(),
		Skin.DescribeLink())
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
	-- Combat is the usual reason a pass did not finish, and it is not the only
	-- one any more: a link written before the client has resolved the player
	-- block's edge waits for a pass that can measure it. Saying "when combat
	-- drops" out of combat sends the reader to look at the wrong thing.
	if pending then
		line = line .. (InCombatLockdown() and ", the rest follows when combat drops"
			or ", the rest follows on the next pass")
	end
	return line
end

--------------------------------------------------------------------------

-- When a pass over the three blocks happens. What one pass does is
-- UnitFrames/Paint.lua's; this is the clock and nothing else.
local elapsed = 0
local function Tick(_, delta)
	elapsed = elapsed + delta
	if elapsed < REFRESH then
		return
	end
	elapsed = 0
	ns.Perf.Start("skin")
	for _, entry in ipairs(entries) do
		-- Before the paint, because a frame that has just been put up wants
		-- its numbers on this pass rather than a fifth of a second later, for
		-- the reason Apply paints in line rather than leaving it to the tick.
		--
		-- On the ticker rather than on UNIT_TARGET, which is the event that
		-- carries it: this file reads health, power and auras off a ticker
		-- already, and the head of it says why. A target that picks up a
		-- target is the same kind of change and gets the same treatment. A
		-- refusal is left to the next pass, which is a fifth of a second away,
		-- rather than setting the deferred flag: the answer changes with the
		-- units and the flag is for work that stays undone.
		Block.Reveal(entry, EntryFor(entry.spec.under))
		Paint.Refresh(entry)
	end
	ns.Perf.Stop("skin")
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
-- Blizzard_EditMode is load on demand, so the selection this file pins may not
-- exist until the first time the user opens Edit Mode.
events:RegisterEvent("ADDON_LOADED")
-- Edit Mode writes its own saved point back over the link's anchor whenever a
-- layout is applied, so the link is written again on the event that says it
-- did. The name is retail's and this client is a backport of it, so the
-- registration goes through pcall: a client that has never heard of the event
-- refuses it and loses nothing, because PLAYER_ENTERING_WORLD and the
-- Blizzard_EditMode load already reach Relayout. Which of the three this
-- client actually fires is in docs/README.md under what has never run.
pcall(events.RegisterEvent, events, "EDIT_MODE_LAYOUTS_UPDATED")
events:SetScript("OnEvent", function(_, event, arg1)
	if event == "PLAYER_LOGIN" then
		for _, spec in ipairs(SPECS) do
			local entry = Resolve(spec)
			if entry then
				entries[#entries + 1] = entry
			end
		end
		Skin.Apply()

		events:SetScript("OnUpdate", Tick)
		return
	end

	if event == "ADDON_LOADED" then
		if arg1 == "Blizzard_EditMode" then
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
