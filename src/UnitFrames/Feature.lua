local ADDON, ns = ...

-- Everything Core needs to know about the three halves of this part: the enemy
-- bars on the mobs, the skin on the player, target and target of target
-- frames, and the target's own aura rows. EnemyBars.lua, Skin.lua and
-- Auras.lua hold the behaviour and none of them talks to Core or to the panel.
--
-- The page itself is UnitFrames/Panel.lua. It was here until the aura settings
-- took this file past the 800 line gate, and the seam it left along is a real
-- one: nothing in the page decides anything, and nothing left here draws.

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
		ns.Print("mob level " .. (ns.db.barsLevel and "on" or "off")
			.. ": drawn inside the bar, left of the name, coloured by what the kill is worth."
			.. " Grey pays no XP and red is five levels up. Whether a mob is neutral is the"
			.. " bar's own frame, and that stays either way.")
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

	if option == "link" then
		ns.db.skinLink = ns.Command.Toggle(value)
		ns.FrameSkin.Apply()
		ns.Print("frame link " .. (ns.db.skinLink and "on" or "off")
			.. ": " .. ns.FrameSkin.DescribeLink() .. ".")
		if ns.db.skinLink then
			ns.Print("Edit Mode positions the player block and this addon positions"
				.. " everything against it. The target is the player mirrored in the"
				.. " middle of the screen, so drag the player to set the corridor;"
				.. " dragging the target sets the level.")
		end
		return
	end

	if option == "level" then
		local low, high = ns.FrameSkin.LinkRange()
		local size = ns.Command.Number(value, low, high, "skin level")
		if size then
			ns.db.skinLevel = size
			ns.FrameSkin.Relayout()
			ns.Print("skin level " .. size .. ": "
				.. ns.FrameSkin.DescribeLink() .. ".")
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

	if option == "auras" then
		ns.db.skinAuras = ns.Command.Toggle(value)
		ns.FrameSkin.Relayout()
		ns.Print("aura rows " .. (ns.db.skinAuras and "on" or "off")
			.. " under the player and target blocks.")
		if ns.db.skinAuras then
			ns.Print("what is on you and on the target, drawn here rather than by"
				.. " the client: yours in colour, everyone else's drained, and"
				.. " yours first so a raid cannot push your Rend off the end.")
		else
			ns.Print("neither frame now carries an aura row at all. Each is the size"
				.. " of its block, so the client's own rows would hang inside the"
				.. " gauges; /wk skin off gives both frames back their size and"
				.. " their rows with it.")
		end
		return
	end

	if option == "aura" then
		local low, high = ns.FrameAuras.SizeRange()
		local size = ns.Command.Number(value, low, high, "skin aura")
		if size then
			ns.db.skinAuraSize = size
			ns.FrameSkin.Relayout()
			ns.Print("aura square " .. size .. " pixels on both blocks.")
		end
		return
	end

	if option == "debuffs" or option == "buffs" then
		local key = option == "debuffs" and "skinAuraDebuffs" or "skinAuraBuffs"
		local high = ns.FrameAuras.CountCeiling(option)
		local many = ns.Command.Number(value, 0, high, "skin " .. option)
		if many then
			ns.db[key] = many
			ns.FrameSkin.Relayout()
			ns.Print(("up to %d %s under each block%s.")
				:format(many, option, many == 0 and ", so that row is off" or ""))
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

	switch = {
		key = "bars",
		label = "enemy bars",
		apply = function() ns.EnemyBars.Rebuild() end,
	},

	defaults = {
		bars = true,
		barsMode = "auto",     -- "auto" follows the nameplate cvar, or force "plates" / "list"
		barsStyle = "replace", -- "replace" takes over the nameplate look, "attach" rides above Blizzard's
		barsOffset = 0,
		barsMarker = true,
		barsLevel = true, -- the level, inside the bar, coloured by XP value

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

		-- The target block hung off the player block, which is the whole
		-- shape of the change: Edit Mode is left positioning the player
		-- block and this addon positions everything against it. On by
		-- default for the reason the skin itself is, and it is the point of
		-- the part rather than an extra. `/wk skin link off` puts the
		-- target frame back on the point Edit Mode gave it, without a
		-- reload, and every drag in Edit Mode goes on working either way.
		skinLink = true,

		-- How far the target's top edge drops below the player's, in screen
		-- pixels like the two sizes above. Zero puts both block tops on one
		-- line, which is what the pair looked wrong without.
		--
		-- There is no distance setting beside it. The corridor across is the
		-- player's distance from the middle of the screen doubled, so it is
		-- set by dragging the player rather than by typing a number.
		skinLevel = 0,

		-- The incoming heal slice on the health gauge. On by default, and it
		-- costs nothing on a client that answers no prediction: the shim in
		-- Core hands back nil and the tick draws the same nothing it draws for
		-- a unit nobody is healing.
		skinHeals = true,

		-- The target's own buff and debuff rows, under the target block. On by
		-- default because the alternative is a target frame with no aura row at
		-- all: the frame is the block now, so the client's own row would land
		-- inside the gauge, and hiding it is what this draws in place of.
		skinAuras = true,

		-- The square, in pixels, on the same grid as everything else the skin
		-- draws. 20 is what the enemy bars ship their debuff square at, and the
		-- two rows wearing one size is the point of them being one file.
		skinAuraSize = 20,

		-- How many of each the row draws. Debuffs get the longer row because
		-- this is a warrior's addon and the target's debuffs are what it is
		-- for. Either at 0 turns that row off on its own; both at 0 is
		-- `skin auras off` said the long way.
		skinAuraDebuffs = 12,
		skinAuraBuffs = 8,

		-- The client's own aura row, in the top corner of the screen. On, and
		-- on a default install that changes nothing you can see: the player
		-- block is skinned, so it is drawing your buffs and the client's frames
		-- are down whatever this says.
		--
		-- It ships on because the switch is only about the install where that
		-- is not true. With `skin off`, or the player frame turned off on its
		-- own, your buffs are the client's row and nothing else, and taking that
		-- away without being asked would leave nothing on the screen saying what
		-- is on you. Off is a real preference and this is where it lives.
		blizzAuras = true,
	},

	words = {
		bars = function(arg)
			BarsWord(arg:match("^(%S*)%s*(.-)$"))
		end,

		skin = SkinWord,

		-- The client's own aura row, which is not part of the skin and is a
		-- word of its own for that reason: it answers on a client where every
		-- Blizzard unit frame is standing where it always was.
		auras = function(arg)
			ns.db.blizzAuras = ns.Command.Toggle(arg)
			ns.FrameAuras.Client()
			if ns.db.blizzAuras then
				ns.Print("the client's own aura row is back in the corner of the"
					.. " screen wherever nothing here is standing in for it."
					.. " What the skin draws under the blocks is `skin auras`,"
					.. " and this is the client's.")
				if ns.FrameSkin.Wanted("player") then
					ns.Print("the player block is skinned, so your buffs are"
						.. " under it and the client's row stays down: two copies"
						.. " of one aura is not something this switch will do."
						.. " `/wk skin player off` is what puts it back.")
				end
			else
				ns.Print("the client's own aura row is hidden: your buffs, your"
					.. " debuffs and the weapon enchant beside them. Right click"
					.. " to cancel a buff goes with it, because cancelling one is"
					.. " a call an addon is not allowed to make.")
			end
		end,

		-- The palette, as numbers you can check against what is on screen.
		--
		-- It is here rather than under `skin` because it answers for the enemy
		-- bars too, and it exists because the rule it prints is invisible: every
		-- fill is capped so the name on it clears Color.TEXT_RATIO, and the only
		-- way to see that from in the game is to be told the ratio.
		colors = function()
			local summary, rows = ns.Unit.Color.Describe()
			ns.Print("colours: " .. summary .. ".")
			for _, row in ipairs(rows) do
				ns.Print("  " .. row)
			end
		end,
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
		"skin link on|off, mirror the target block off the player block",
		"skin level <-100-100>, the target's drop from the player",
		"skin heals on|off, the incoming heal on the health gauge",
		"skin auras on|off, our own aura rows under the player and target blocks",
		"skin aura <12 up to the block height>, one aura square, in screen pixels",
		"skin debuffs <0-16>, skin buffs <0-32>, how long each row runs",
		"skin probe, what this client answered for each frame",
		"auras on|off, the client's own buff row in the corner of the screen",
		"colors, every class fill and how far the name on it is from it",
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
			.. ("; %s"):format(ns.FrameAuras.Describe())
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
		-- The number a drag in Edit Mode writes, back where it started. Reset
		-- already means put the frames back, and a level that survived one
		-- would be the only thing on these three frames that did not.
		ns.db.skinLink = ns.DefaultFor("skinLink")
		ns.db.skinLevel = ns.DefaultFor("skinLevel")
		ns.db.skinAuras = ns.DefaultFor("skinAuras")
		ns.db.skinAuraSize = ns.DefaultFor("skinAuraSize")
		ns.db.skinAuraDebuffs = ns.DefaultFor("skinAuraDebuffs")
		ns.db.skinAuraBuffs = ns.DefaultFor("skinAuraBuffs")
		-- Reset means put the frames back, and the client's own row is a frame
		-- this part took down. Somebody who hid it deliberately loses that in a
		-- reset, which is the same trade every other setting here makes and the
		-- reason `/wk reset` prints what it did.
		ns.db.blizzAuras = ns.DefaultFor("blizzAuras")
		ns.FrameAuras.Client()
		ns.FrameSkin.Apply()
	end,

	panel = function(ui)
		ns.UnitFramesPanel.Draw(ui)
	end,
})
