local ADDON, ns = ...

-- Everything Core and the panel need to know about the two halves of this
-- part: the enemy bars on the mobs, and the skin on the player, target and
-- target of target frames. EnemyBars.lua and Skin.lua hold the behaviour and
-- neither talks to Core or to the panel.

-- The two icon sizes the client keeps a copy of. Everything between them draws
-- a little soft, which is worth saying out loud rather than leaving the stepper
-- to imply that every step on it is equal.

local function DebuffWord(action, value)
	if action == "add" then
		local ok, message = ns.EnemyBars.AddSpell(value)
		ns.Print(ok and (message .. " is on the bar.") or message)
	elseif action == "remove" then
		if value == "" then
			ns.Print("bars debuff remove takes the spell id. bars debuff lists them.")
			return
		end
		local ok, name = ns.EnemyBars.RemoveSpell(value)
		ns.Print(ok and (name .. " is off the bar.")
			or ("nothing on the bar has the id " .. value .. "."))
	elseif action == "reset" then
		ns.EnemyBars.ResetSpells()
		ns.Print("debuff list back to the four it ships with: " .. ns.EnemyBars.DescribeSpells() .. ".")
	elseif action == "list" or action == "" then
		local spells = ns.EnemyBars.Spells()
		if #spells == 0 then
			ns.Print("nothing tracked. bars debuff add <spell id>, or use the panel.")
			return
		end
		ns.Print("on the bar, left to right:")
		for index, spellID in ipairs(spells) do
			ns.Print(("  %d. %s (%d)"):format(index, ns.SpellName(spellID) or "unknown to this client", spellID))
		end
		ns.Print(("%d of %d slots used."):format(#spells, ns.EnemyBars.MaxSpells()))
	else
		ns.Print("bars debuff takes list, add <spell id>, remove <spell id> or reset.")
	end
end

local function BarsWord(option, value)
	if option == "mode" then
		if value == "auto" or value == "plates" or value == "list" then
			ns.db.barsMode = value
			ns.EnemyBars.Rebuild()
			ns.Print("bars mode " .. value .. ", running as " .. ns.EnemyBars.Mode() .. ".")
		else
			ns.Print("bars mode takes auto, plates or list.")
		end
	elseif option == "style" then
		if value == "replace" or value == "attach" then
			ns.db.barsStyle = value
			ns.EnemyBars.Rebuild()
			ns.Print(value == "replace" and "our bars replace the Blizzard nameplate."
				or "our bars ride above the Blizzard nameplate.")
		else
			ns.Print("bars style takes replace or attach.")
		end
	elseif option == "offset" then
		local offset = ns.Command.Number(value, -60, 60, "bars offset")
		if offset then
			ns.db.barsOffset = offset
			ns.EnemyBars.Rebuild()
			ns.Print("plate offset " .. offset .. ".")
		end
	elseif option == "camera" then
		if value == "right" or value == "left" or value == "both" or value == "off" then
			ns.db.barsCamera = value
			ns.EnemyBars.Rebuild()
			if value == "off" then
				ns.Print("plates keep every button. The camera will not turn over a bar.")
			else
				ns.Print(("plates hand the %s button back to the world, so the camera turns over a bar. %s")
					:format(value == "both" and "left and right" or value,
						value == "right"
							and "Click targeting and ctrl-click marking still work."
							or "Click targeting on a plate is gone with it."))
			end
			ns.Print("camera pass-through: " .. ns.EnemyBars.CameraState() .. ".")
		else
			ns.Print("bars camera takes right, left, both or off.")
		end
	elseif option == "clickthrough" then
		ns.db.barsClickThrough = ns.Command.Toggle(value)
		ns.EnemyBars.Rebuild()
		ns.Print(ns.db.barsClickThrough
			and "plates pass the mouse through. The camera turns over a bar again, and clicking a plate no longer targets or marks."
			or "plates take the mouse. Click targeting and ctrl-click marking work, and the camera will not turn over a bar.")
	elseif option == "level" then
		ns.db.barsLevel = ns.Command.Toggle(value)
		ns.EnemyBars.ApplyLayout()
		ns.EnemyBars.Rebuild()
		ns.Print("mob tag " .. (ns.db.barsLevel and "on" or "off")
			.. ": the level coloured by what the kill is worth, grey pays no XP and red is five levels"
			.. " up, and a stripe beside it, bright amber when the mob is neutral and will not start it.")
	elseif option == "cast" then
		ns.db.barsCast = ns.Command.Toggle(value)
		ns.EnemyBars.ApplyLayout()
		ns.EnemyBars.Rebuild()
		ns.Print("enemy cast bar " .. (ns.db.barsCast and "on" or "off")
			.. ": " .. ns.Cast.Describe() .. ".")
		if not ns.db.barsCast then
			ns.Print("Blizzard's own plate cast bar is back, so a cast still shows.")
		end
	elseif option == "marker" then
		ns.db.barsMarker = ns.Command.Toggle(value)
		ns.EnemyBars.Rebuild()
		ns.Print("raid marker on the bars " .. (ns.db.barsMarker and "on" or "off")
			.. ", Blizzard's marker takes over when ours is off.")
	elseif option == "max" then
		local count = ns.Command.Number(value, 1, 15, "bars max")
		if count then
			ns.db.barsMax = count
			ns.Print("showing up to " .. count .. " bars in list mode.")
		end
	elseif option == "width" then
		local width = ns.Command.Number(value, 120, 400, "bars width")
		if width then
			ns.db.barsWidth = width
			ns.EnemyBars.ApplyLayout()
			ns.Print("bar width " .. width .. " pixels, on a plate and in the list.")
		end
	elseif option == "zoom" then
		local zoom = ns.Command.Number(value, 1, 3, "bars zoom")
		if zoom then
			ns.db.barsZoom = zoom
			ns.EnemyBars.ApplyLayout()
			ns.EnemyBars.Rebuild()
			ns.Print("bars zoom " .. zoom .. ", so one pixel of the design is "
				.. zoom .. " on screen. " .. ns.UI.Describe() .. ".")
		end
	elseif option == "debuff" then
		DebuffWord(value:match("^(%S*)%s*(.-)$"))
	elseif option == "icon" then
		local low, high = ns.EnemyBars.IconRange()
		local size = ns.Command.Number(value, low, high, "bars icon")
		if size then
			ns.db.barsIconSize = size
			ns.EnemyBars.ApplyLayout()
			ns.EnemyBars.Rebuild()
			ns.Print(("debuff icons %d pixels square, %s.")
				:format(size, ns.EnemyBars.DescribeIcon(size)))
		end
	elseif option == "stack" then
		ns.db.barsStack = ns.Command.Toggle(value)
		ns.Plates.Apply()
		ns.Print(ns.db.barsStack
			and "asking the client to stack nameplates and sizing a plate to the bar on it, so two mobs standing together get two bars that do not cover each other."
			or "nameplate motion and plate size handed back to the client.")
		ns.Print("plates: " .. ns.Plates.Describe() .. ".")
	else
		ns.db.bars = ns.Command.Toggle(option)
		ns.EnemyBars.Rebuild()
		ns.Print("enemy bars " .. (ns.db.bars and "on" or "off") .. ".")
	end
	ns.EnemyBars.Update()
end

local FRAME_WORDS = { player = "player frame", target = "target frame",
	tot = "target of target" }

local function SkinWord(arg)
	local option, value = arg:match("^(%S*)%s*(.-)$")

	if option == "probe" then
		ns.FrameSkin.Probe()
		return
	end

	if option == "height" or option == "width" then
		-- Pixels, not units, since the block went on the grid. The old ceiling
		-- was written when the numbers were UI units, which on a screen taller
		-- than 768 buy more than one pixel each, so the same setting draws a
		-- smaller square now and the range has to reach further to put it back.
		local low, high = 18, 72
		if option == "width" then
			low, high = 90, 360
		end
		local size = ns.Command.Number(value, low, high, "skin " .. option)
		if size then
			ns.db[option == "height" and "skinHeight" or "skinWidth"] = size
			ns.FrameSkin.Relayout()
			ns.Print("skin " .. option .. " " .. size .. ".")
		end
		return
	end

	if option == "heals" then
		ns.db.skinHeals = ns.Command.Toggle(value)
		ns.FrameSkin.Apply()
		ns.Print("incoming heals " .. (ns.db.skinHeals and "on" or "off")
			.. ": the green slice on the gauge is what is already in the air"
			.. " for that unit, clamped to what it is actually missing.")
		if ns.db.skinHeals and not ns.HasHealPrediction() then
			ns.Print("this client answers no UnitGetIncomingHeals, so nothing will draw.")
		end
		return
	end

	if FRAME_WORDS[option] then
		ns.db.skinFrames[option] = ns.Command.Toggle(value)
		ns.FrameSkin.Apply()
		ns.Print(FRAME_WORDS[option] .. " skin "
			.. (ns.db.skinFrames[option] and "on" or "off") .. ".")
		return
	end

	ns.db.skin = ns.Command.Toggle(option)
	ns.FrameSkin.Apply()
	ns.Print("unit frame skin " .. (ns.db.skin and "on" or "off")
		.. ", " .. ns.FrameSkin.Describe() .. ".")
end

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

-- What the bars cost is one number and what they cost per mob is another, and
-- the performance tab cannot tell them apart without being told how many are
-- up. Registered from here rather than from EnemyBars, because a behaviour file
-- names nothing outside its own folder.
if ns.Perf then
	ns.Perf.Gauge("enemy bars on screen", function()
		return ns.EnemyBars.Count()
	end)
end

ns.Register({
	name = "unit frames",
	order = 6,

	defaults = {
		bars = true,
		barsMode = "auto",     -- "auto" follows the nameplate cvar, or force "plates" / "list"
		barsStyle = "replace", -- "replace" takes over the nameplate look, "attach" rides above Blizzard's
		barsOffset = 0,
		barsMarker = true,
		barsLevel = true, -- the mob tag: level coloured by XP value, plus the reaction stripe

		-- The cast row under the gauge. On by default, because it is the one
		-- thing Blizzard's nameplate said that the bar replacing it did not,
		-- and because on a mob that never casts it is a strip of empty screen
		-- and nothing else. Off hands the job back to Blizzard's own plate cast
		-- bar, which `replace` style stops hiding at the same moment.
		barsCast = true,
		barsClickThrough = false, -- the camera, at the price of click targeting and marking on a plate
		-- Which buttons a plate hands back to the world while keeping the
		-- rest. "right" is the default because it buys the camera drag and
		-- costs only right-click-to-interact and ctrl-right-click cross
		-- marking on a plate, both of which have somewhere else to happen.
		-- "left" or "both" give up click targeting, which is what
		-- barsClickThrough already does more plainly. "off" is the old
		-- all-or-nothing behaviour.
		barsCamera = "right",
		barsMax = 8,
		-- Pixels, like every other size in the bars, and one figure for both
		-- modes. A bar on a plate used to take the plate's own width, which
		-- was a number nobody chose and one that moved every time the driver
		-- was told how much room a bar wants.
		barsWidth = 180,

		-- Which debuffs the row above each bar shows, as spell IDs in the order
		-- they are drawn. A setting rather than a constant, because which
		-- debuffs matter is a spec question: an arms warrior watches Deep
		-- Wounds and Mortal Strike, a protection one watches neither and wants
		-- the room back. EnemyBars owns the list and every write to it.
		barsSpells = ns.EnemyBars.DefaultSpells(),

		-- One debuff square's edge, in pixels like every other size in the bars.
		-- 29 is the one size in the range that draws a stored texel on a pixel,
		-- because the square's border takes two pixels off and the crop leaves
		-- 54 texels. See the header of EnemyBars.lua. 20 is where this shipped,
		-- and it is close to the worst place in the range to stand, but a
		-- default that moves rewrites a setting the player never touched.
		barsIconSize = 20,

		-- A whole number, because the bars are drawn on a pixel grid and a
		-- fractional zoom would put every edge back on a half pixel. 1 is the
		-- design size, which is the same physical size on every monitor and is
		-- small on a 4K one.
		barsZoom = 1,

		-- Whether the addon owns nameplateMotion, nameplateOverlapV and the
		-- enemy plate size, which between them are what stops two bars landing
		-- on top of each other. Off means the client's own, untouched.
		barsStack = true,

		-- What those two CVars were before the addon first wrote to them, so
		-- turning the setting off puts back what was actually there. Empty is
		-- the sentinel for "not remembered yet". Account scoped, because the
		-- CVars are.
		platesMotionPrior = "",
		platesOverlapPrior = "",
		barsPoint = { "CENTER", "UIParent", "CENTER", 280, 120 },

		-- The square skin on the player, target and target of target frames.
		-- On by default for the reason the bar art strip is: it is the point
		-- of the part, and one word turns it off without a reload.
		skin = true,

		-- One switch per frame under that one, because they do not fail
		-- together. Target of target is the one to reach for: Blizzard parks
		-- it across the target's aura row, so ours lands there too.
		skinFrames = { player = true, target = true, tot = true },

		-- The block's shape, as a setting rather than a constant, because the
		-- first shipped guess was a square as tall as Blizzard's portrait and
		-- that was far too tall in both directions that matter: it crowded the
		-- text and it dropped target of target onto the target's aura row.
		-- Target of target takes a fixed fraction of both.
		--
		-- Pixels, like every size in the enemy bars, because the block sits on
		-- the same grid. 34 is 34 pixels on a laptop and 34 on a 4K panel, which
		-- is the point of the grid and also the whole of what it costs.
		skinHeight = 34,
		skinWidth = 168,

		-- The incoming heal slice on the health gauge. On by default, and it
		-- costs nothing on a client that answers no prediction: the shim in
		-- Core hands back nil and the tick draws the same nothing it draws for
		-- a unit nobody is healing.
		skinHeals = true,
	},

	words = {
		bars = function(arg)
			BarsWord(arg:match("^(%S*)%s*(.-)$"))
		end,

		skin = SkinWord,
	},

	help = {
		"bars on|off, bars mode auto|plates|list, bars style replace|attach",
		"bars offset <-60-60>, bars marker on|off, bars level on|off",
		"bars clickthrough on|off, bars camera right|left|both|off",
		"bars cast on|off, the cast row under each bar",
		"bars max <1-15>, bars width <120-400>, bars zoom <1-3>",
		"bars debuff list|reset, bars debuff add|remove <spell id>, what the icon row tracks",
		"bars icon <16-32>, the size of one debuff square",
		"bars stack on|off, whether the client spaces plates by the size of our bar",
		"skin on|off, the square player, target and target of target frames",
		"skin player|target|tot on|off, one frame at a time",
		"skin height <18-72>, skin width <90-360>, both in screen pixels",
		"skin heals on|off, the incoming heal on the health gauge",
		"skin probe, what this client answered for each frame",
	},

	status = function()
		return ("bars %s, mode %s (%s), style %s, up to %d, plates %s, camera %s%s; screen %s; %s; font %s; skin %s")
			:format(ns.db.bars and "on" or "off", ns.db.barsMode,
				ns.EnemyBars.Mode(), ns.db.barsStyle, ns.db.barsMax,
				ns.db.barsClickThrough and "click through" or "clickable",
				ns.EnemyBars.CameraState(),
				ns.HasThreat() and "" or ", no threat api so colour is who each mob is hitting",
				ns.UI.Describe(), ns.Plates.Describe(), ns.UI.FontName(),
				ns.FrameSkin.Describe())
			.. ("; debuffs at %dpx: %s"):format(ns.db.barsIconSize, ns.EnemyBars.DescribeSpells())
			.. ("; cast bar %s"):format(ns.Cast.Describe())
	end,

	lock = function()
		ns.EnemyBars.ApplyLock()
	end,

	reset = function()
		-- A fresh table, not ns.DefaultFor: dragging mutates the anchor in place.
		ns.db.barsPoint = { "CENTER", "UIParent", "CENTER", 280, 120 }
		ns.db.barsWidth = ns.DefaultFor("barsWidth")
		ns.db.barsOffset = ns.DefaultFor("barsOffset")
		ns.db.barsCamera = ns.DefaultFor("barsCamera")
		ns.db.barsZoom = ns.DefaultFor("barsZoom")
		ns.db.barsStack = ns.DefaultFor("barsStack")
		ns.db.barsIconSize = ns.DefaultFor("barsIconSize")
		ns.db.barsCast = ns.DefaultFor("barsCast")
		-- A fresh table, not ns.DefaultFor: adding and removing a debuff mutates
		-- the list in place, so by now the registered default is whatever the
		-- last edit left it as. This relays out on its own and the two calls
		-- under it do it again, which is one wasted pass on a command nobody
		-- types twice a minute and is cheaper than a reset that depends on
		-- what follows it.
		ns.EnemyBars.ResetSpells()
		ns.EnemyBars.ApplyLayout()
		ns.EnemyBars.Rebuild()
		ns.db.skin = ns.DefaultFor("skin")
		-- A fresh table, not ns.DefaultFor: the default is handed out by
		-- reference and every toggle since has been writing into it.
		ns.db.skinFrames = { player = true, target = true, tot = true }
		ns.db.skinHeight = ns.DefaultFor("skinHeight")
		ns.db.skinWidth = ns.DefaultFor("skinWidth")
		ns.db.skinHeals = ns.DefaultFor("skinHeals")
		ns.FrameSkin.Apply()
	end,

	panel = function(ui)
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
		ui.Check("mob tag: level by XP value, stripe by hostile or neutral",
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
		ui.Note(function()
			if not ns.db.skin then
				return "Blizzard's own frames, exactly as they shipped. "
					.. ns.FrameSkin.Describe() .. "."
			end
			return "The ring and the banner are hidden, the portrait is square, and the"
				.. " gauge and its edge take the class colour, or the reaction colour on"
				.. " anything without a class. The raid marker stays. Nothing is rebuilt:"
				.. " clicking, the dropdown, auras and the cast bar are still Blizzard's,"
				.. " and turning this off puts every piece back without a reload."
				.. " Each Blizzard frame is resized to the block over it, so the"
				.. " rectangle Edit Mode selects and snaps is the one you can see and"
				.. " the empty space around it no longer takes clicks. The two sizes"
				.. " above move that rectangle, so a frame you have already placed"
				.. " needs placing again. "
				.. ns.FrameSkin.Describe() .. "."
		end)
	end,
})
