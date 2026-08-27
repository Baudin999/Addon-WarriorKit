local ADDON, ns = ...

local Panel = {}
ns.UnitFramesPanel = Panel

-- The part's page in the options window, and nothing else.
--
-- It was the second half of Feature.lua and it took that file past the 800 line
-- gate. The seam is a real one rather than a place the knife happened to land:
-- everything here reads a setting, draws a control and writes it back, and
-- nothing here decides anything. What is left in Feature.lua is the part's
-- contract with Core, which is the defaults, the slash words, the status line
-- and the reset, and none of it draws.
--
-- One page and not two, even though the part has two halves that share nothing.
-- The enemy bars and the frame skin are one rail entry because they are one
-- answer to one question, which is what the units around you look like.

-- One row of the debuff list: the spell's own icon, its name, and the button
-- that takes it off. There is one per slot, built once at login and shown only
-- while the list is that long, because the panel is built once and the list is
-- not: a row that appears when you add a spell has to already exist.
--
-- ui.Custom is the seam for this. UI/Widgets.lua has no list widget and should
-- not grow one for a single caller; what it has is a bare row of the right
-- width that measures itself, and an unused slot measures to nothing.
local function DebuffRow(ui, slot)
	local M, C = ns.UI.Metric, ns.UI.Color
	local removeWidth = 62
	local row, art, name

	local function Spell()
		return ns.EnemyBars.Spells()[slot]
	end

	ui.Custom(function(frame)
		row = frame

		art = ns.UI.Icon(frame, "ARTWORK")
		art:SetSize(M.control, M.control)
		art:SetPoint("TOPLEFT")

		local remove = ns.UI.Button(frame, { label = "remove", width = removeWidth,
			onClick = function()
				local spellID = Spell()
				if spellID then
					ns.EnemyBars.RemoveSpell(spellID)
					ns.Options.Refresh()
				end
			end })
		remove:SetPoint("TOPRIGHT")

		name = ns.UI.Label(frame, M.font, C.text, "LEFT", ns.UI.FLAT)
		name:SetPoint("LEFT", art, "RIGHT", M.gutter, 0)
		name:SetPoint("RIGHT", remove, "LEFT", -M.gutter, 0)

		-- An empty slot is not a short row, it is no row: zero height and no
		-- gap under it, or ten unused slots would leave a hand's width of air
		-- between the list and the controls below it.
		return function(cell)
			local used = Spell() ~= nil
			cell.gap = used and M.rowGap or 0
			return used and M.control or 0
		end
	end, { height = M.control, refresh = function()
		local spellID = Spell()
		row:SetShown(spellID ~= nil)
		if spellID then
			art:SetTexture(ns.SpellTexture(spellID))
			name:SetText(ns.SpellName(spellID) or ("spell " .. spellID .. ", unknown to this client"))
		end
	end })
end

-- Three sections in two groups, one function each. They were one function
-- while they were one rail entry called after this folder; now that a section
-- names its own group, the enemy bars and your own frames are not the same
-- subject and there is no reason for them to share a body.
local function EnemyBars(ui)
	ui.Section("Enemy bars", "Them")
	ui.Lede("Our own health bar on every hostile nameplate, or a list of them beside the screen.")

	ui.Cycle("mode", { "auto", "plates", "list" },
		function() return ns.db.barsMode end,
		function(value)
			ns.db.barsMode = value
			ns.EnemyBars.Rebuild()
		end)
	ui.Hint("Auto follows the client's own nameplate setting. Plates and list force one or the other, whatever the CVar says.")

	ui.Cycle("style", { "replace", "attach" },
		function() return ns.db.barsStyle end,
		function(value)
			ns.db.barsStyle = value
			ns.EnemyBars.Rebuild()
		end)
	ui.Hint("Replace takes over the nameplate's look. Attach rides above Blizzard's and leaves it where it is.")

	ui.Cycle("button a plate hands back to the camera", { "right", "left", "both", "off" },
		function() return ns.db.barsCamera end,
		function(value)
			ns.db.barsCamera = value
			ns.EnemyBars.Rebuild()
		end)
	ui.Hint("A plate swallows every button that lands on it, and the right button drag that turns the camera is one of them. Handing one back costs whatever that button did.")

	ui.Check("plates pass the mouse through (camera turns, no click targeting)",
		function() return ns.db.barsClickThrough end,
		function(value)
			ns.db.barsClickThrough = value
			ns.EnemyBars.Rebuild()
		end)
	ui.Hint("Unlock the frames and each plate outlines the region that takes the mouse in red. Our bar is anchored to it, so the two should agree.")

	ui.Check("mob level inside the bar, coloured by XP value",
		function() return ns.db.barsLevel end,
		function(value)
			ns.db.barsLevel = value
			ns.EnemyBars.ApplyLayout()
			ns.EnemyBars.Rebuild()
		end)

	ui.Check("cast bar under each enemy bar",
		function() return ns.db.barsCast end,
		function(value)
			ns.db.barsCast = value
			ns.EnemyBars.ApplyLayout()
			ns.EnemyBars.Rebuild()
		end)
	ui.Hint("The row is kept clear whether or not the mob is casting, so a cast starting does not shove the health bar upwards. Unlock the frames to preview one.")

	ui.Check("draw our own raid marker",
		function() return ns.db.barsMarker end,
		function(value)
			ns.db.barsMarker = value
			ns.EnemyBars.Rebuild()
		end)

	ui.Check("let the client space nameplates by the size of our bar",
		function() return ns.db.barsStack end,
		function(value)
			ns.db.barsStack = value
			ns.Plates.Apply()
		end)
	ui.Hint("Off, two mobs standing together put two bars on top of each other, because the client is spacing Blizzard's plate and ours is twice its height.")

	ui.Size("bar height on the plate", -60, 60, 2,
		function() return ns.db.barsOffset end,
		function(value)
			ns.db.barsOffset = value
			ns.EnemyBars.Rebuild()
		end)
	ui.Count("rows", 1, 15,
		function() return ns.db.barsMax end,
		function(value) ns.db.barsMax = value end)
	ui.Hint("How many bars the list shows at once. It does nothing in plates mode, where the client decides how many nameplates there are.")

	ui.Size("width", 120, 400, 10,
		function() return ns.db.barsWidth end,
		function(value)
			ns.db.barsWidth = value
			ns.EnemyBars.ApplyLayout()
		end)
	ui.Zoom(
		function() return ns.db.barsZoom end,
		function(value)
			ns.db.barsZoom = value
			ns.EnemyBars.ApplyLayout()
			ns.EnemyBars.Rebuild()
		end)
	ui.Hint("Every size here is a count of screen pixels, so a bar is the same physical size on any monitor. Zoom multiplies that by a whole number, which keeps the grid.")

	ui.Reading("the camera", ns.EnemyBars.CameraState)
	ui.Reading("nameplate spacing", ns.Plates.Describe)
	ui.Reading("cast bars", function()
		if not ns.HasCastInfo() then
			return "this client answers no UnitCastingInfo for anyone but you"
		end
		return ns.Cast.Describe()
	end)
	ui.Reading("the grid", ns.UI.Describe)

end

local function Debuffs(ui)
	ui.Section("Debuffs on the bar", "Them")
	ui.Lede("A row of icons over each bar: bright is yours, grey is somebody else's, faint is nobody's.")

	for slot = 1, ns.EnemyBars.MaxSpells() do
		DebuffRow(ui, slot)
	end

	ui.Picker("add a warrior debuff",
		function() return "pick one" end,
		function(spellID)
			if type(spellID) ~= "number" then
				return
			end
			local ok, message = ns.EnemyBars.AddSpell(spellID)
			if not ok then
				ns.Print(message)
			end
		end,
		function()
			local options = {}
			for _, spellID in ipairs(ns.EnemyBars.Suggestions()) do
				local name = ns.SpellName(spellID)
				if name and not ns.EnemyBars.Slot(spellID) then
					options[#options + 1] = { value = spellID, text = name,
						icon = ns.SpellTexture(spellID) }
				end
			end
			if #options == 0 then
				options[1] = { text = "every one of them is already on the bar" }
			end
			return options
		end)
	ui.Hint("The picker is the warrior's own debuffs and a shortlist, not the limit. Matching is by name, so rank 1 covers every rank and another warrior's Sunder counts.")

	ui.TextField("or add any spell by id",
		function() return "" end,
		function(text)
			if text:match("^%s*$") then
				return
			end
			local ok, message = ns.EnemyBars.AddSpell(text)
			ns.Print(ok and (message .. " is on the bar.") or message)
		end)
	ui.Hint("Use the id of the aura that lands on the mob, not of the spell that puts it there. The Deep Wounds talent is 12162; the bleed it applies is 12721.")

	-- One pixel a step. It used to be two, which stepped straight over the
	-- sizes that draw sharp, on a range that stopped short of the biggest of
	-- them.
	local iconLow, iconHigh = ns.EnemyBars.IconRange()
	ui.Slider("icon size", iconLow, iconHigh, 1,
		function() return ns.db.barsIconSize end,
		function(value)
			ns.db.barsIconSize = value
			ns.EnemyBars.ApplyLayout()
			ns.EnemyBars.Rebuild()
		end,
		function(value) return value .. "px" end)
	ui.Hint("The row packs against the right end of the gauge and wraps upwards, so a long list on a narrow bar becomes two rows rather than icons hanging off the left edge.")

	ui.Action(function() return "back to the four it ships with" end, function()
		ns.EnemyBars.ResetSpells()
		ns.Options.Refresh()
	end)

	ui.Reading("slots used", function()
		local spells = ns.EnemyBars.Spells()
		local unknown = ns.EnemyBars.Unresolved()
		if #unknown > 0 then
			return ("%d of %d, and this client cannot name %s")
				:format(#spells, ns.EnemyBars.MaxSpells(), table.concat(unknown, ", "))
		end
		return ("%d of %d"):format(#spells, ns.EnemyBars.MaxSpells())
	end)
	ui.Reading("icons", ns.EnemyBars.DescribeIcon)

end

local function Frames(ui)
	ui.Section("Player and target frames", "You")
	ui.Lede("Squares Blizzard's own player, target and target of target frames in your class colour.")

	ui.Check("square frames in your class colour",
		function() return ns.db.skin end,
		function(value)
			ns.db.skin = value
			ns.FrameSkin.Apply()
		end)
	ui.Hint("The ring and banner are hidden, the portrait is square and the gauge takes the class colour. Clicking, the dropdown and the cast bar are still Blizzard's.")

	for _, frame in ipairs({ { "player", "the player frame" },
		{ "target", "the target frame" },
		{ "tot", "target of target, which sits on the target's auras" } }) do
		ui.Check("skin " .. frame[2],
			function() return ns.db.skinFrames[frame[1]] end,
			function(value)
				ns.db.skinFrames[frame[1]] = value
				ns.FrameSkin.Apply()
			end)
	end

	ui.Size("frame height", 18, 72, 2,
		function() return ns.db.skinHeight end,
		function(value)
			ns.db.skinHeight = value
			ns.FrameSkin.Relayout()
		end)
	ui.Size("frame width", 90, 360, 6,
		function() return ns.db.skinWidth end,
		function(value)
			ns.db.skinWidth = value
			ns.FrameSkin.Relayout()
		end)
	ui.Hint("Each Blizzard frame is resized to the block over it, so a frame you have already placed in Edit Mode needs placing again after these move.")

	local levelLow, levelHigh = ns.FrameSkin.LinkRange()
	ui.Check("mirror the target block off the player block",
		function() return ns.db.skinLink end,
		function(value)
			ns.db.skinLink = value
			ns.FrameSkin.Apply()
		end)
	ui.Hint("The target becomes the player reflected in the middle of the screen. Drag the player to widen or close the corridor, or past the centre to make the pair cross.")

	ui.Size("the target's drop from the player", levelLow, levelHigh, 5,
		function() return ns.db.skinLevel end,
		function(value)
			ns.db.skinLevel = value
			ns.FrameSkin.Relayout()
		end)

	ui.Check("show incoming heals on the health gauge",
		function() return ns.db.skinHeals end,
		function(value)
			ns.db.skinHeals = value
			ns.FrameSkin.Apply()
		end)
	ui.Hint("A green slice from where the gauge stops to where the heals in the air will take it, clamped to what the unit is missing, so an overheal reads as a full bar.")

	ui.Check("draw your own and the target's buffs and debuffs",
		function() return ns.db.skinAuras end,
		function(value)
			ns.db.skinAuras = value
			ns.FrameSkin.Relayout()
		end)
	ui.Hint("Debuffs under each block and buffs over it. Yours are placed first, so a raid's worth of other people's bleeds cannot push your Rend off the end.")

	do
		local low, high = ns.FrameAuras.SizeRange()
		ui.Size("aura square", low, high, 2,
			function() return ns.db.skinAuraSize end,
			function(value)
				ns.db.skinAuraSize = value
				ns.FrameSkin.Relayout()
			end)
	end
	ui.Count("debuffs on each row", 0, ns.FrameAuras.CountCeiling("debuffs"),
		function() return ns.db.skinAuraDebuffs end,
		function(value)
			ns.db.skinAuraDebuffs = value
			ns.FrameSkin.Relayout()
		end)
	ui.Count("buffs on each row", 0, ns.FrameAuras.CountCeiling("buffs"),
		function() return ns.db.skinAuraBuffs end,
		function(value)
			ns.db.skinAuraBuffs = value
			ns.FrameSkin.Relayout()
		end)

	ui.Check("show the client's own aura row where nothing here replaces it",
		function() return ns.db.blizzAuras end,
		function(value)
			ns.db.blizzAuras = value
			ns.FrameAuras.Client()
		end)
	ui.Hint("A skinned player block draws your buffs and keeps the client's row down whatever this says; turn the player frame off and this decides. Right click to cancel a buff goes with that row.")

	ui.Reading("the frames", ns.FrameSkin.Describe)
	ui.Reading("the corridor", ns.FrameSkin.DescribeLink)
	ui.Reading("the aura rows", ns.FrameAuras.Describe)
	ui.Reading("incoming heals", function()
		return ns.HasHealPrediction() and "this client answers UnitGetIncomingHeals"
			or "this client answers no UnitGetIncomingHeals, so the slice never draws"
	end)
end

function Panel.Draw(ui)
	EnemyBars(ui)
	Debuffs(ui)
	Frames(ui)
end
