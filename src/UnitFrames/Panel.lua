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

function Panel.Draw(ui)
	ui.Header("Enemy bars")
	ui.Check("show enemy bars",
		function() return ns.db.bars end,
		function(value)
			ns.db.bars = value
			ns.EnemyBars.Rebuild()
		end)
	ui.Cycle("mode", { "auto", "plates", "list" },
		function() return ns.db.barsMode end,
		function(value)
			ns.db.barsMode = value
			ns.EnemyBars.Rebuild()
		end)
	ui.Cycle("style", { "replace", "attach" },
		function() return ns.db.barsStyle end,
		function(value)
			ns.db.barsStyle = value
			ns.EnemyBars.Rebuild()
		end)
	ui.Cycle("button a plate hands back to the camera", { "right", "left", "both", "off" },
		function() return ns.db.barsCamera end,
		function(value)
			ns.db.barsCamera = value
			ns.EnemyBars.Rebuild()
		end)
	ui.Note(function()
		local state = ns.EnemyBars.CameraState()
		if state == "moot" then
			return "clickthrough is on below, so the plate has no mouse and every button already reaches the camera."
		elseif state == "unavailable" then
			return "this client has no SetPassThroughButtons, so it is the whole plate or none of it. Use clickthrough below."
		elseif state == "off" then
			return "the plate keeps every button, so a drag that starts on a bar will not turn the camera."
		elseif state == "unproven" then
			return "nothing has come up yet. This answers once a nameplate appears."
		elseif state == "right" then
			return "right button turns the camera, left still targets and ctrl-left still marks. Ctrl-right-click cross marking on a plate is the cost."
		end
		return "click targeting on a plate is gone with the button you handed back."
	end)
	ui.Check("plates pass the mouse through (camera turns, no click targeting)",
		function() return ns.db.barsClickThrough end,
		function(value)
			ns.db.barsClickThrough = value
			ns.EnemyBars.Rebuild()
		end)
	ui.Note(function()
		if ns.db.locked then
			return "unlock the frames to outline what each plate actually takes the mouse over."
		end
		return "the red outline on each plate is the region that takes the mouse. Our bar is anchored to it, so the two should agree."
	end)
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
	ui.Note(function()
		if not ns.HasCastInfo() then
			return "This client answers no UnitCastingInfo for a unit that is not"
				.. " you, so the row never draws whatever this is set to. Blizzard's"
				.. " own plate cast bar is left alone in that case."
		end
		if not ns.db.barsCast then
			return "Off, so Blizzard's own cast bar on the plate is left where it is"
				.. " and that is what says when to Pummel."
		end
		return "The row is under the gauge and is kept clear whether or not the mob"
			.. " is casting, so a cast starting does not shove the health bar"
			.. " upwards. Empty it draws nothing at all. A cast fills left to"
			.. " right, a channel drains right to left, and the number is the"
			.. " seconds left to interrupt it. |cffd08040Now:|r "
			.. ns.Cast.Describe() .. "."
	end)
	ui.Note(function()
		if not ns.db.locked then
			return "Unlocked, so every bar on screen is drawing a preview rather than"
				.. " asking the client: a cast, then a channel, five seconds around."
				.. " Lock the frames and the row goes back to what the mob is really"
				.. " doing. You still need an enemy bar to look at, which means a"
				.. " hostile target, or a nameplate up with V."
		end
		return "A mob that casts is not something you can arrange, so unlock the"
			.. " frames to see the row: every bar previews a cast and then a"
			.. " channel until you lock them again. Any hostile target will do."
	end)
	ui.Check("draw our own raid marker",
		function() return ns.db.barsMarker end,
		function(value)
			ns.db.barsMarker = value
			ns.EnemyBars.Rebuild()
		end)
	ui.Stepper("bar height on the plate", -60, 60, 2,
		function() return ns.db.barsOffset end,
		function(value)
			ns.db.barsOffset = value
			ns.EnemyBars.Rebuild()
		end)
	ui.Stepper("list bars", 1, 15, 1,
		function() return ns.db.barsMax end,
		function(value) ns.db.barsMax = value end)
	ui.Stepper("bar width, in pixels", 120, 400, 10,
		function() return ns.db.barsWidth end,
		function(value)
			ns.db.barsWidth = value
			ns.EnemyBars.ApplyLayout()
		end)
	ui.Stepper("zoom, whole steps only", 1, 3, 1,
		function() return ns.db.barsZoom end,
		function(value)
			ns.db.barsZoom = value
			ns.EnemyBars.ApplyLayout()
			ns.EnemyBars.Rebuild()
		end)
	ui.Note(function()
		return "Every size in the bars is a count of screen pixels, so a bar is the"
			.. " same physical size on any monitor and its edges are exactly one pixel."
			.. " Zoom multiplies that by a whole number, which is the only way to make"
			.. " a pixel grid bigger without leaving it. " .. ns.UI.Describe() .. "."
	end)
	ui.Check("let the client space nameplates by the size of our bar",
		function() return ns.db.barsStack end,
		function(value)
			ns.db.barsStack = value
			ns.Plates.Apply()
		end)
	ui.Note(function()
		if not ns.db.barsStack then
			return "Off, so nameplate motion, nameplate overlap and plate size are the"
				.. " client's own. Two mobs standing together will put two bars on top"
				.. " of each other, because the client is spacing Blizzard's nameplate"
				.. " and ours is twice the height of it."
		end
		return "Blizzard's driver decides where a plate goes, and it spaces them by how"
			.. " big it thinks a plate is. This tells it the real figure and asks it to"
			.. " stack rather than overlap. The cost is that a plate takes the mouse over"
			.. " the whole bar, which is more to click and more of a camera drag swallowed."
			.. " Turning it off puts all three back. Now: " .. ns.Plates.Describe() .. "."
	end)

	ui.Header("Debuffs on the bar")
	ui.Note(function()
		return "The row above each bar, left to right. Bright is yours, grey is"
			.. " somebody else's and faint is nobody's, with the seconds left along"
			.. " the bottom edge and the stack count in the corner. Matching is on"
			.. " the spell's name rather than its id, so rank 1 covers every rank"
			.. " and another warrior's Sunder counts."
	end)
	for slot = 1, ns.EnemyBars.MaxSpells() do
		DebuffRow(ui, slot)
	end
	ui.Note(function()
		local spells = ns.EnemyBars.Spells()
		if #spells == 0 then
			return "Nothing tracked. The row is empty and each bar is a debuff row shorter."
		end
		local unknown = ns.EnemyBars.Unresolved()
		if #unknown > 0 then
			return ("%d of %d slots used. This client cannot name %s, so nothing draws"
				.. " for them. They keep their place in case you log in on the flavour that can.")
				:format(#spells, ns.EnemyBars.MaxSpells(), table.concat(unknown, ", "))
		end
		return ("%d of %d slots used."):format(#spells, ns.EnemyBars.MaxSpells())
	end)
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
	ui.TextField("or add any spell by id",
		function() return "" end,
		function(text)
			if text:match("^%s*$") then
				return
			end
			local ok, message = ns.EnemyBars.AddSpell(text)
			ns.Print(ok and (message .. " is on the bar.") or message)
		end)
	ui.Note(function()
		return "The picker is the warrior's own debuffs and the shortlist, not the"
			.. " limit. Anything a mob can carry goes on by id, which is the last"
			.. " part of the spell's address on Wowhead. Use the id of the aura"
			.. " that lands on the mob, not the id of the spell or talent that"
			.. " puts it there. For a ranked spell those are the same and rank 1"
			.. " covers every rank, because the match is by name. For a proc they"
			.. " are two spells: the Deep Wounds talent is 12162, the bleed it"
			.. " applies is 12721, and the client spells that one Deep Wound."
	end)
	-- One pixel a step. It used to be two, which stepped straight over the
	-- sizes that draw sharp, on a range that stopped short of the biggest of
	-- them.
	local iconLow, iconHigh = ns.EnemyBars.IconRange()
	ui.Slider("icon size, in pixels", iconLow, iconHigh, 1,
		function() return ns.db.barsIconSize end,
		function(value)
			ns.db.barsIconSize = value
			ns.EnemyBars.ApplyLayout()
			ns.EnemyBars.Rebuild()
		end,
		function(value) return value .. " px" end)
	ui.Note(function()
		return "|cffd08040Now:|r " .. ns.EnemyBars.DescribeIcon() .. "."
	end)
	ui.Note(function()
		local _, _, nearest = ns.EnemyBars.IconAdvice()
		return "The client keeps half sized copies of every texture and picks the"
			.. " pair nearest the size asked for. The square carries a one pixel"
			.. " border and the art sits inside it, and the art itself is cropped"
			.. " five texels a side to lose the border the client bakes in, so"
			.. " what actually gets sampled is 54 texels drawn two pixels smaller"
			.. " than the number above. " .. (nearest and (nearest .. " is the size")
				or "No size in this range is one") .. " where that lands one texel"
			.. " on one pixel. Everything else is a blend of two copies, which is"
			.. " what soft icons are."
	end)
	ui.Note(function()
		return "The row is packed against the right end of the gauge and wraps"
			.. " upwards when it no longer fits, so a long list on a narrow bar"
			.. " becomes two rows rather than icons hanging off the left edge."
	end)
	ui.Action(function() return "back to the four it ships with" end, function()
		ns.EnemyBars.ResetSpells()
		ns.Options.Refresh()
	end)

	ui.Header("Player, target and target of target")
	ui.Check("square frames in your class colour",
		function() return ns.db.skin end,
		function(value)
			ns.db.skin = value
			ns.FrameSkin.Apply()
		end)
	ui.Stepper("frame height, in pixels", 18, 72, 2,
		function() return ns.db.skinHeight end,
		function(value)
			ns.db.skinHeight = value
			ns.FrameSkin.Relayout()
		end)
	ui.Stepper("frame width, in pixels", 90, 360, 6,
		function() return ns.db.skinWidth end,
		function(value)
			ns.db.skinWidth = value
			ns.FrameSkin.Relayout()
		end)
	local gapLow, gapHigh, levelLow, levelHigh = ns.FrameSkin.LinkRange()
	ui.Check("hang the target block off the player block",
		function() return ns.db.skinLink end,
		function(value)
			ns.db.skinLink = value
			ns.FrameSkin.Apply()
		end)
	ui.Stepper("gap between the two facing edges, in pixels", gapLow, gapHigh, 10,
		function() return ns.db.skinGap end,
		function(value)
			ns.db.skinGap = value
			ns.FrameSkin.Relayout()
		end)
	ui.Stepper("the target's drop from the player, in pixels", levelLow, levelHigh, 5,
		function() return ns.db.skinLevel end,
		function(value)
			ns.db.skinLevel = value
			ns.FrameSkin.Relayout()
		end)
	ui.Note(function()
		if not ns.db.skinLink then
			return "Off, so Edit Mode positions both blocks and the two are free to"
				.. " sit at unmatched heights and unmatched distances apart. "
				.. ns.FrameSkin.DescribeLink() .. "."
		end
		return "Edit Mode positions the player block and this addon positions"
			.. " everything against it: the target hangs off the player and target"
			.. " of target hangs off the target. Dragging the target in Edit Mode"
			.. " still works, and where you drop it becomes these two numbers."
			.. " Both blocks are mirrored, so linking them faces the two gauges"
			.. " across the gap and turns the portraits outward. |cffd08040Now:|r "
			.. ns.FrameSkin.DescribeLink() .. "."
	end)
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
	ui.Check("show incoming heals on the health gauge",
		function() return ns.db.skinHeals end,
		function(value)
			ns.db.skinHeals = value
			ns.FrameSkin.Apply()
		end)
	ui.Note(function()
		if not ns.HasHealPrediction() then
			return "This client answers no UnitGetIncomingHeals, so the slice never"
				.. " draws. Nothing else about the frames changes."
		end
		if not ns.db.skinHeals then
			return "Off, so the gauge shows what the unit has and nothing about what"
				.. " is on the way to it."
		end
		return "A green slice from where the gauge stops to where the heals already"
			.. " in the air will take it, clamped to what the unit is actually"
			.. " missing, so an overheal reads as a full bar rather than as a bar"
			.. " and a half. It is drawn under Blizzard's fill: the moment a heal"
			.. " lands, the fill covers the slice that predicted it."
	end)
	ui.Check("draw the target's buffs and debuffs",
		function() return ns.db.skinAuras end,
		function(value)
			ns.db.skinAuras = value
			ns.FrameSkin.Relayout()
		end)
	do
		local low, high = ns.FrameAuras.SizeRange()
		ui.Stepper("aura square, in pixels", low, high, 2,
			function() return ns.db.skinAuraSize end,
			function(value)
				ns.db.skinAuraSize = value
				ns.FrameSkin.Relayout()
			end)
	end
	ui.Stepper("debuffs on the row", 0, ns.FrameAuras.CountCeiling("debuffs"), 1,
		function() return ns.db.skinAuraDebuffs end,
		function(value)
			ns.db.skinAuraDebuffs = value
			ns.FrameSkin.Relayout()
		end)
	ui.Stepper("buffs on the row", 0, ns.FrameAuras.CountCeiling("buffs"), 1,
		function() return ns.db.skinAuraBuffs end,
		function(value)
			ns.db.skinAuraBuffs = value
			ns.FrameSkin.Relayout()
		end)
	ui.Note(function()
		if not ns.db.skin then
			return "The rows hang off the target block, so they need the target"
				.. " frame skinned before they mean anything."
		end
		if not ns.db.skinAuras then
			return "Off, and the target frame then carries no aura row at all. The"
				.. " frame is the size of the block, so the client's own row hangs"
				.. " inside the gauge rather than under it, which is why it is"
				.. " hidden either way. Turn the skin off to get both back."
		end
		return "Debuffs against the block and buffs under them, wrapping downwards"
			.. " when a row runs past the block's width. What you cast is drawn in"
			.. " colour and everything else is drained, and yours are placed first,"
			.. " so a raid's worth of other people's bleeds cannot push your Rend"
			.. " off the end. Hovering a square gives you the client's own tooltip"
			.. " for that aura. "
			.. ns.FrameAuras.Describe() .. "."
	end)
	ui.Note(function()
		if not ns.db.skin then
			return "Blizzard's own frames, exactly as they shipped. "
				.. ns.FrameSkin.Describe() .. "."
		end
		return "The ring and the banner are hidden, the portrait is square, and the"
			.. " gauge and its edge take the class colour, or the reaction colour on"
			.. " anything without a class. The raid marker stays. Almost nothing is"
			.. " rebuilt: clicking, the dropdown and the cast bar are still"
			.. " Blizzard's, and turning this off puts every piece back without a"
			.. " reload. The target's aura row is the one exception and it has its"
			.. " own switch above."
			.. " Each Blizzard frame is resized to the block over it, so the"
			.. " rectangle Edit Mode selects and snaps is the one you can see and"
			.. " the empty space around it no longer takes clicks. The two sizes"
			.. " above move that rectangle, so a frame you have already placed"
			.. " needs placing again. "
			.. ns.FrameSkin.Describe() .. "."
	end)
end
