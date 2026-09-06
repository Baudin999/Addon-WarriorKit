local ADDON, ns = ...

-- Everything Core needs to know about the three halves of this part: the enemy
-- bars on the mobs, the skin on the player, target and target of target
-- frames, and the target's own aura rows. EnemyBars.lua, Auras.lua and the
-- skin's own four files hold the behaviour, and none of them talks to Core or
-- to the panel.
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
		ns.Print("debuff list back to the five it ships with: " .. ns.EnemyBars.DescribeSpells() .. ".")
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

-- What the whole word redraws, which is not one call: a setting that changes
-- what a bar says needs the widget laid out again as well as rebuilt, and two
-- of them need neither.
local function BarsRebuild()
	ns.EnemyBars.Rebuild()
end

local function BarsRelayout()
	ns.EnemyBars.ApplyLayout()
	ns.EnemyBars.Rebuild()
end

-- The words the enemy bars answer to.
--
-- The first four are about the plate under the bar rather than about the bar:
-- which buttons it hands back, whether it takes the mouse at all, how the
-- driver spaces two of them and how far out it puts one up. They are first and
-- they are together because they are one subject: every one of them ends in a
-- Plates call or a sentence about the client's own nameplate driver, and none
-- of them touches the widget.
local BarsWord = ns.Command.Word({
	name = "bars",
	finally = function() ns.EnemyBars.Update() end,

	{ "camera", choice = { "right", "left", "both", "off" }, key = "barsCamera",
	  apply = BarsRebuild,
	  say = function(value)
		return value == "off"
			and "plates keep every button. The camera will not turn over a bar."
			or ("plates hand the %s button back to the world, so the camera turns over a bar. %s")
				:format(value == "both" and "left and right" or value,
					value == "right"
						and "Click targeting and ctrl-click marking still work."
						or "Click targeting on a plate is gone with it."),
			"camera pass-through: " .. ns.EnemyBars.CameraState() .. "."
	  end },

	{ "clickthrough", toggle = true, key = "barsClickThrough", apply = BarsRebuild,
	  say = function(on)
		return on
			and "plates pass the mouse through. The camera turns over a bar again, and clicking a plate no longer targets or marks."
			or "plates take the mouse. Click targeting and ctrl-click marking work, and the camera will not turn over a bar."
	  end },

	{ "stack", toggle = true, key = "barsStack",
	  apply = function() ns.Plates.Apply() end,
	  say = function(on)
		return on
			and "asking the client to stack nameplates, so two mobs standing together get two bars that do not cover each other."
			or "nameplate motion handed back to the client. A plate is still sized to the bar on it, because that is what a click on the bar lands on.",
			"plates: " .. ns.Plates.Describe() .. "."
	  end },

	-- Not a plain number, because `off` is a fifth answer that means no limit
	-- rather than a distance of nothing.
	{ "distance", run = function(value)
		local low, high = ns.Plates.DistanceRange()
		local yards = value == "off" and 0
			or ns.Command.Number(value, low, high, "bars distance")
		if yards then
			ns.db.barsDistance = yards
			ns.Plates.Apply()
			ns.Print(ns.Plates.DescribeDistance() .. ".")
		end
	  end },

	{ "mode", choice = { "auto", "plates", "list" }, key = "barsMode",
	  apply = BarsRebuild,
	  say = function(value)
		return "bars mode " .. value .. ", running as " .. ns.EnemyBars.Mode() .. "."
	  end },

	{ "style", choice = { "replace", "attach" }, key = "barsStyle",
	  apply = BarsRebuild,
	  say = function(value)
		return value == "replace" and "our bars replace the Blizzard nameplate."
			or "our bars ride above the Blizzard nameplate."
	  end },

	{ "offset", number = { -60, 60 }, key = "barsOffset", apply = BarsRebuild,
	  say = function(offset)
		return "plate offset " .. offset .. "."
	  end },

	{ "level", toggle = true, key = "barsLevel", apply = BarsRelayout,
	  say = function(on)
		return "mob level " .. (on and "on" or "off")
			.. ": drawn inside the bar, left of the name, coloured by what the kill is worth."
			.. " Grey pays no XP and red is five levels up. Whether a mob is neutral is the"
			.. " bar's own frame, and that stays either way."
	  end },

	{ "cast", toggle = true, key = "barsCast", apply = BarsRelayout,
	  say = function(on)
		return "enemy cast bar " .. (on and "on" or "off")
				.. ": " .. ns.Cast.Describe() .. ".",
			not on and "Blizzard's own plate cast bar is back, so a cast still shows." or nil
	  end },

	{ "marker", toggle = true, key = "barsMarker", apply = BarsRebuild,
	  say = function(on)
		return "raid marker on the bars " .. (on and "on" or "off")
			.. ", Blizzard's marker takes over when ours is off."
	  end },

	{ "quest", toggle = true, key = "barsQuest", apply = BarsRebuild,
	  say = function(on)
		return "quest badge on the bars " .. (on and "on" or "off")
				.. ": how many of this one a quest in your log still wants, in gold off the"
				.. " bar's right edge. The mob's own hover says which quest and what it"
				.. " drops at. Both are Questie's to answer.",
			"a creature's hover says " .. ns.QuestDrops.Describe() .. "."
	  end },

	{ "max", number = { 1, 15 }, key = "barsMax",
	  say = function(count)
		return "showing up to " .. count .. " bars in list mode."
	  end },

	{ "width", number = { 120, 400 }, key = "barsWidth",
	  apply = function() ns.EnemyBars.ApplyLayout() end,
	  say = function(width)
		return "bar width " .. width .. " pixels, on a plate and in the list."
	  end },

	{ "zoom", number = { 1, 3 }, key = "barsZoom", apply = BarsRelayout,
	  say = function(zoom)
		return "bars zoom " .. zoom .. ", so one pixel of the design is "
			.. zoom .. " on screen. " .. ns.UI.Describe() .. "."
	  end },

	{ "debuff", run = function(value)
		DebuffWord(value:match("^(%S*)%s*(.-)$"))
	  end },

	{ "icon", key = "barsIconSize", apply = BarsRelayout,
	  number = function() return ns.EnemyBars.IconRange() end,
	  say = function(size)
		return ("debuff icons %d pixels square, %s.")
			:format(size, ns.EnemyBars.DescribeIcon(size))
	  end },

	{ "fade", toggle = true, key = "barsFade",
	  say = function(on)
		return on
			and "bars ramp in as a mob comes into range and out again behind it."
			or "bars appear and disappear with the plate under them."
	  end },

	otherwise = { toggle = true, key = "bars", apply = BarsRebuild,
	  say = function(on)
		return "enemy bars " .. (on and "on" or "off") .. "."
	  end },
})

-- One entry per frame the skin can be told about on its own. The word and the
-- label it is said by come in together, so a fourth frame is one line here and
-- nothing else anywhere.
local function FrameEntry(word, label)
	return { word, toggle = true,
		apply = function() ns.FrameSkin.Apply() end,
		set = function(on) ns.db.skinFrames[word] = on end,
		say = function(on)
			return label .. " skin " .. (on and "on" or "off") .. "."
		end }
end

-- The words `/wk hide` answers to, off the same list the panel draws from so
-- the two cannot drift.
local function Words()
	local words = {}
	for index, switch in ipairs(ns.BlizzHide.Switches()) do
		words[index] = switch.word
	end
	return table.concat(words, ", ")
end

local function SkinRelayout()
	ns.FrameSkin.Relayout()
end

local function SkinApply()
	ns.FrameSkin.Apply()
end

local SkinWord = ns.Command.Word({
	name = "skin",

	{ "probe", run = function()
		ns.FrameSkin.Probe()
	  end },

	-- Pixels, not units, since the block went on the grid. The old ceiling was
	-- written when the numbers were UI units, which on a screen taller than 768
	-- buy more than one pixel each, so the same setting draws a smaller square
	-- now and the range has to reach further to put it back.
	{ "width", number = { 90, 360 }, key = "skinWidth", apply = SkinRelayout,
	  say = function(size)
		return "skin width " .. size .. "."
	  end },

	{ "height", number = { 18, 72 }, key = "skinHeight", apply = SkinRelayout,
	  say = function(size)
		return "skin height " .. size .. "."
	  end },

	{ "link", toggle = true, key = "skinLink", apply = SkinApply,
	  say = function(on)
		return "frame link " .. (on and "on" or "off")
				.. ": " .. ns.FrameSkin.DescribeLink() .. ".",
			on and "The target is the player mirrored in the middle of the"
				.. " screen. Unlock the frames and drag the player to set the"
				.. " corridor; dragging the target sets the level."
			or "Unlock the frames and drag the target wherever you like."
	  end },

	{ "level", key = "skinLevel", apply = SkinRelayout,
	  number = function() return ns.FrameSkin.LinkRange() end,
	  say = function(size)
		return "skin level " .. size .. ": " .. ns.FrameSkin.DescribeLink() .. "."
	  end },

	{ "heals", toggle = true, key = "skinHeals", apply = SkinApply,
	  say = function(on)
		return "incoming heals " .. (on and "on" or "off")
				.. ": the green slice on the gauge is what is already in the air"
				.. " for that unit, clamped to what it is actually missing.",
			(on and not ns.HasHealPrediction())
				and "this client answers no UnitGetIncomingHeals, so nothing will draw."
				or nil
	  end },

	{ "auras", toggle = true, key = "skinAuras", apply = SkinRelayout,
	  say = function(on)
		return "aura rows " .. (on and "on" or "off")
				.. " under the player and target blocks.",
			on and "what is on you and on the target, drawn here rather than by"
				.. " the client: yours in colour, everyone else's drained, and"
				.. " yours first so a raid cannot push your Rend off the end."
			or "neither frame now carries an aura row at all. Each is the size"
				.. " of its block, so the client's own rows would hang inside the"
				.. " gauges; /wk skin off gives both frames back their size and"
				.. " their rows with it."
	  end },

	{ "aura", key = "skinAuraSize", apply = SkinRelayout,
	  number = function() return ns.FrameAuras.SizeRange() end,
	  say = function(size)
		return "aura square " .. size .. " pixels on both blocks."
	  end },

	FrameEntry("player", "player frame"),
	FrameEntry("target", "target frame"),
	FrameEntry("tot", "target of target"),

	otherwise = { toggle = true, key = "skin", apply = SkinApply,
	  say = function(on)
		return "unit frame skin " .. (on and "on" or "off")
			.. ", " .. ns.FrameSkin.Describe() .. "."
	  end },
})

-- Your own cast bar, which is its own word rather than a corner of `skin` or of
-- `bars`. It is neither: it draws nothing on a Blizzard frame and nothing on a
-- nameplate, and it is a bar of its own that you drag where you want it.
local CastWord = ns.Command.Word({
	name = "cast",
	apply = function() ns.PlayerCast.Apply() end,

	{ "width", key = "playerCastWidth",
	  number = function()
		local low, high = ns.PlayerCast.SizeRange()
		return low, high
	  end,
	  say = function(size)
		return "cast width " .. size .. " pixels."
	  end },

	{ "height", key = "playerCastHeight",
	  number = function()
		local _, _, low, high = ns.PlayerCast.SizeRange()
		return low, high
	  end,
	  say = function(size)
		return "cast height " .. size .. " pixels."
	  end },

	{ "zoom", key = "playerCastZoom",
	  number = function() return ns.UI.ZOOM_LOW, ns.UI.ZOOM_HIGH end,
	  say = function(zoom)
		return "cast zoom " .. zoom .. ", so one pixel of the design is "
			.. zoom .. " on screen."
	  end },

	{ "reset", run = function()
		ns.PlayerCast.Reset()
		ns.Print("cast bar back under the swing timer.")
	  end },

	otherwise = { toggle = true, key = "playerCast",
	  say = function(on)
		return "your cast bar " .. (on and "on" or "off")
				.. ": " .. ns.PlayerCast.Describe() .. ".",
			(not on and ns.db.hideBlizzPlayerCast)
				and "Blizzard's own is hidden by `/wk hide playercast`, so nothing"
					.. " is drawing your casts at all."
				or nil
	  end },
})

local ROLE_WORDS = { tank = true, healer = true, dps = true, none = true }

-- One name given a role by hand, which beats every source Unit/Role.lua reads.
-- It exists because inspection fails in the exact case where you already know
-- the answer: the friend standing next to you who has just respecced.
local function PartyRole(arg)
	local name, role = arg:match("^(%S*)%s*(%S*)$")
	if name == "" then
		ns.Print("party role <name> tank|healer|dps|none, kept for this character.")
		ns.Print(ns.Unit.Role.Describe() .. ".")
		return
	end
	if not ROLE_WORDS[role] then
		ns.Print("party role takes tank, healer, dps or none after the name.")
		return
	end
	ns.Unit.Role.Set(name, role ~= "none" and role or nil)
	ns.Group.Rebuild()
	ns.Print(role == "none"
		and (name .. " goes back to whatever the client and their talents say.")
		or ("%s sits in the %s band until you say otherwise."):format(name, role))
end

-- One of the numbers a `party` or `raid` word is setting. The key comes off
-- UnitFrames/Group.lua rather than being spelled here a second time, and so
-- does every range, off the file that owns it.
local function ListNumber(which, word, name, range)
	return { word, key = ns.Group.Key(which, name), number = range,
		say = function(size)
			return ("%s %s %d."):format(which, word, size)
		end }
end

-- One of the switches, said with its own sentence about what the switch does.
local function ListSwitch(which, word, name, said)
	return { word, toggle = true, key = ns.Group.Key(which, name), say = said }
end

-- Which way one group's members run. Four answers for both lists now: a party
-- is a line and reads either way round, and a raid is a grid that can be five
-- to a row with a row per group or five down a column with a column per group.
local function GrowWord(which, value)
	local across = value == "right" or value == "left"
	if not across and value ~= "up" then
		value = "down"
	end
	ns.db[ns.Group.Key(which, "grow")] = value
	ns.Group.Apply()
	ns.Print(("the %s grows %s: it is centred on where you dragged it and fills"
		.. " outward from there, so this picks which end the first slot is at.")
		:format(which, value))
end

-- The words one list answers to, built for that list. Everything in here reads
-- its own list's setting through ns.Group.Key, so the party cannot be given the
-- raid's numbers by a word that forgot which one it was called for, and the two
-- grid words are in the table only where the list has a grid: the party has no
-- columns and no key to write one to.
local function ListWords(which)
	local spec = {
		name = which,
		apply = function() ns.Group.Apply() end,

		ListNumber(which, "width", "width", function()
			local low, high = ns.Group.SizeRange()
			return low, high
		end),

		ListNumber(which, "height", "height", function()
			local _, _, low, high = ns.Group.SizeRange()
			return low, high
		end),

		ListNumber(which, "gap", "gap", function() return ns.Group.GapRange() end),

		ListNumber(which, "zoom", "zoom",
			function() return ns.UI.ZOOM_LOW, ns.UI.ZOOM_HIGH end),

		ListSwitch(which, "self", "mine", function(on)
			return ("your own block in the %s %s."):format(which, on and "on" or "off")
		end),

		ListSwitch(which, "icons", "icons", function(on)
			return "role icons " .. (on and "on" or "off")
				.. ", drawn in Blizzard's own art on the portrait side of each block."
		end),

		ListSwitch(which, "range", "range", function(on)
			return "out of range " .. (on and "on" or "off")
				.. ": a member you cannot reach drains to the track colour and says so."
		end),

		{ "grow", run = function(value) GrowWord(which, value) end },

		{ "reset", run = function()
			ns.Group.Reset(which)
			ns.Print(("the %s is back where the addon ships it."):format(which))
		  end },

		otherwise = { toggle = true, key = ns.Group.Key(which, "on"),
		  say = function(on)
			return ("%s frames %s, %s."):format(which, on and "on" or "off",
				ns.Group.Describe(which))
		  end },
	}

	if ns.Group.Key(which, "columns") then
		spec[#spec + 1] = ListNumber(which, "columns", "columns", function()
			local low, high = ns.Group.ColumnRange()
			return low, high
		end)
		spec[#spec + 1] = ListNumber(which, "percolumn", "per", function()
			local _, _, low, high = ns.Group.ColumnRange()
			return low, high
		end)
		spec[#spec + 1] = { "order", run = function(value)
			local key = ns.Group.Key(which, "order")
			ns.db[key] = value == "role" and "role" or "group"
			ns.Group.Apply()
			ns.Print("raid order " .. ns.db[key] .. ": "
				.. ns.Group.Describe(which) .. ".")
		  end }
		spec[#spec + 1] = ListSwitch(which, "headings", "headings", function(on)
			return "group headings " .. (on and "on" or "off")
				.. ", on each run of five in a raid ordered by group."
		end)
	else
		spec[#spec + 1] = { "role", run = function(value) PartyRole(value) end }
	end

	return ns.Command.Word(spec)
end

local PartyWord = ListWords("party")
local RaidWord = ListWords("raid")

-- What the bars cost is one number and what they cost per mob is another, and
-- the performance tab cannot tell them apart without being told how many are
-- up. Registered from here rather than from EnemyBars, because a behaviour file
-- names nothing outside its own folder.
if ns.Perf then
	ns.Perf.Gauge("enemy bars on screen", function()
		return ns.EnemyBars.Count()
	end)
	ns.Perf.Gauge("party blocks on screen", function()
		return ns.Group.Count("party") + ns.Group.Count("raid")
	end)
end

-- Ctrl-click marking on a party member, which goes off the screen with
-- Blizzard's party frames unless something puts it back.
--
-- Registered from here rather than from UnitFrames/Group.lua, because a
-- behaviour file may not name a file outside its own folder and this is the one
-- file in this part that is allowed to name Marking.
ns.Group.OnMember(function(button)
	if ns.Marking then
		ns.Marking.Watch(button)
	end
end)

-- And on the player, target and target of target buttons, which Marking used
-- to reach by hooking Blizzard's three by name. Those three are in the attic
-- now and ours take the click.
ns.FrameSkin.OnFrame(function(button)
	if ns.Marking then
		ns.Marking.Watch(button)
	end
end)

ns.Register({
	name = "unit frames",
	order = 7,

	switch = {
		key = "bars",
		label = "enemy bars",
		page = "Enemy bars",
		apply = function() ns.EnemyBars.Rebuild() end,
	},

	zooms = {
		{ key = "barsZoom", label = "Enemy bars", fight = true, apply = function() ns.EnemyBars.ApplyLayout() end },
		{ key = "playerCastZoom", label = "Your cast bar", fight = true, apply = function() ns.PlayerCast.Apply() end },
		{ key = "partyZoom", label = "Party list", apply = function() ns.Group.Apply() end },
		{ key = "raidZoom", label = "Raid list", apply = function() ns.Group.Apply() end },
	},

	defaults = {
		bars = true,
		barsMode = "auto",     -- "auto" follows the nameplate cvar, or force "plates" / "list"
		barsStyle = "replace", -- "replace" takes over the nameplate look, "attach" rides above Blizzard's
		barsOffset = 2,
		barsMarker = true,
		barsLevel = true, -- the level, inside the bar, coloured by XP value

		-- The quest badge off the bar's right edge: how many of this one you
		-- still owe a quest in your log. On, because it costs a table index per
		-- plate per tick and it answers at pull range the question the hover
		-- answers at cursor range. It draws nothing at all without Questie,
		-- which is the same thing the hover does.
		barsQuest = true,

		-- The cast row under the gauge. On by default, because it is the one
		-- thing Blizzard's nameplate said that the bar replacing it did not,
		-- and because on a mob that never casts it is a strip of empty screen
		-- and nothing else. Off hands the job back to Blizzard's own plate cast
		-- bar, which `replace` style stops hiding at the same moment.
		barsCast = true,
		barsClickThrough = true, -- the camera, at the price of click targeting and marking on a plate
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
		-- was told how much room a bar wants. 220 is wide enough to hold a five
		-- debuff row under a full mob name.
		barsWidth = 220,

		-- One debuff square's edge, in pixels like every other size in the bars.
		-- 29 is the one size in the range that draws a stored texel on a pixel,
		-- because the square's border takes two pixels off and the crop leaves
		-- 54 texels. See the header of EnemyBars.lua. 27 is two under that and
		-- is what five squares fit into over a 220 pixel bar, which is the
		-- trade this default makes: the row stays one row.
		barsIconSize = 27,

		-- A whole number, because the bars are drawn on a pixel grid and a
		-- fractional zoom would put every edge back on a half pixel. 1 is the
		-- design size, which is the same physical size on every monitor and is
		-- small on a 4K one.
		barsZoom = 1,

		-- Whether the addon owns nameplateMotion and nameplateOverlapV, which
		-- between them are what stops two bars landing on top of each other.
		-- Off means the client's own, untouched. The plate's size is not on
		-- this switch and has not been since it became the click target too:
		-- see the head of UnitFrames/Plates.lua.
		barsStack = true,

		-- How many yards out the client puts an enemy nameplate up, which is
		-- how far out a bar can be seen: a bar is drawn on a plate, so nothing
		-- here can appear before one does. 41 is as far as either of these two
		-- clients goes; ask for more and it clamps, which is why the panel and
		-- `/wk status` report the CVar and never this number. Not a yard over
		-- it either: Plates.ApplyDistance saves the clamped figure back into
		-- this setting so the panel shows what the client is holding rather
		-- than what somebody typed at a wall, so a default of 60 would be a
		-- default that rewrites itself to 41 on the first login and a
		-- shipped answer no account file ever holds. 0 hands the setting back
		-- and leaves the client's own alone.
		barsDistance = 41,

		-- Whether a bar ramps in and out or is simply there and then not.
		-- On, because a plate is put up and taken down in one frame and
		-- fifteen bars blinking on at a pull reads as a fault.
		barsFade = true,

		-- What those three CVars were before the addon first wrote to them, so
		-- turning a setting off puts back what was actually there. Empty is
		-- the sentinel for "not remembered yet". Account scoped, because the
		-- CVars are.
		platesMotionPrior = "",
		platesOverlapPrior = "",
		platesDistancePrior = "",
		barsPoint = { "CENTER", "UIParent", "CENTER", 378, 184 },

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
		skinHeight = 68,
		skinWidth = 198,

		-- Where the player block sits, and where the target block sits while
		-- the link below is off. Two of the twelve HUD frames you drag, and
		-- the corners are roughly where the client keeps its own two: yours
		-- top left, the target's top right, both in pixels because both
		-- frames are on the grid.
		skinPlayerPoint = { "TOPLEFT", "UIParent", "TOPLEFT", 40, -40 },
		skinTargetPoint = { "TOPRIGHT", "UIParent", "TOPRIGHT", -40, -40 },

		-- The target block hung off the player block: you place the player
		-- and this addon positions everything against it. On by default for
		-- the reason the frames themselves are, and it is the point of the
		-- part rather than an extra. `/wk skin link off` puts the target on
		-- the corner above, without a reload.
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
		-- draws. 28 against a 198 pixel block is eight squares to a row, which
		-- is the number below, and it is a square you can read a stack count
		-- off from where you sit.
		skinAuraSize = 28,

		-- How many of each the row draws. Eight and eight, which is what a 198
		-- pixel block holds in one row at 28 pixels a square, so neither row
		-- ever wraps under the frame. Either at 0 turns that row off on its
		-- own; both at 0 is `skin auras off` said the long way.

		-- Your own cast bar, drawn by this addon rather than by the client.
		-- On by default for the reason the skin is: it is a thing the addon
		-- draws and the client's copy is hidden below, so shipping it off
		-- would ship a screen with no cast bar on it.
		playerCast = true,

		-- 180, which is a spell name and the seconds beside it and nothing
		-- wider. It used to be tied to the swing bars, on the argument that two
		-- bars of different lengths stacked on each other read as two features;
		-- the swing bars ship off now and sit above the character rather than
		-- under it, so there is nothing for this one to match and the number is
		-- its own. 16 is tall enough to hold that text at a size worth reading.
		playerCastWidth = 180,
		playerCastHeight = 16,

		-- A whole number, like every other zoom in the addon, because a
		-- fractional one puts every edge back on a half pixel. 2, because this
		-- bar is under your character and read while you are looking at the
		-- fight rather than at it.
		playerCastZoom = 2,

		-- Under the swing bars, which sit at -220 and are ten pixels tall on
		-- one hand and twenty two on two. Both numbers are whole, because half
		-- of an odd one is half a pixel and this frame is on the grid.
		playerCastPoint = { "CENTER", "UIParent", "CENTER", 0, -250 },

		-- The client's own copies of what this addon draws. One switch per
		-- thing you can see twice, and every one of them means exactly what
		-- its label says.
		--
		-- All of them ship on, because an addon that draws your buffs under
		-- your portrait and leaves the client's in the corner has not replaced
		-- anything, it has added to it. The frames each one takes down are in
		-- Core/BlizzHide.lua.
		hideBlizzUnitFrames = true,
		hideBlizzBuffs = true,
		hideBlizzDebuffs = true,
		hideBlizzTargetAuras = true,
		hideBlizzTargetCast = true,
		hideBlizzPlayerCast = true,
		hideBlizzParty = true,
		hideBlizzRaid = true,

		-- The party blocks, drawn by this addon out of a secure group header.
		-- On for the reason the skin is: it is the point of the item, and the
		-- two switches above take Blizzard's copies down, so shipping it off
		-- would ship a screen with no group frames on it at all.
		party = true,

		-- Your own block in the list, at your own role's slot rather than at the
		-- top. On, because a party list you are not in reads as somebody else's
		-- group: the four tiles are the other four and the fifth is somewhere
		-- off to the side. Off leaves you to the block UnitFrames/Skin.lua
		-- draws, which is the older answer and still a defensible one.
		partySelf = true,

		partyRoleIcon = true,

		-- A tile about twice as wide as it is tall, which is the shape a name
		-- fits across and a health fill is still read as an area rather than as
		-- a length. Five of them across is 620 pixels, which is a strip under
		-- the player block and not a second screen.
		--
		-- These deliberately no longer match the skin's block. That match was
		-- the old party row's whole argument and it was the wrong one: the
		-- player frame is a gauge you take a reading off, and a group frame is
		-- five or forty shapes you scan. Two jobs, two instruments.
		partyWidth = 120,
		partyHeight = 56,
		partyGap = 4,

		-- Which way the four of them run, and which end the first slot is at.
		-- Across, because that is the shape that fits under a player block in
		-- the middle of the screen: five of these down the middle would cover
		-- the swing bar, the charge icon and your own cast bar.
		partyGrow = "right",

		-- A whole number, like every other zoom in the addon, because a
		-- fractional one puts every edge back on a half pixel.
		partyZoom = 1,

		-- Whether a member you cannot reach drains to the track colour. On,
		-- because the whole reason the list exists is the Charge button casting
		-- Intervene at whoever you are looking at, and a block that says
		-- nothing about range is a block you aim at and miss.
		partyRange = true,

		-- Two hundred and twenty pixels under the middle of the screen, which is
		-- under the player block and over the action bars.
		--
		-- The point is the middle of the list and not a corner of it, because
		-- the list fills outward from here in both directions: two people and
		-- five people are centred on the same pixel, and nobody joining moves
		-- anybody who was already on the screen.
		--
		-- This shipped on the left edge of the screen until now, which is where
		-- a party list has always gone and is the wrong side of the screen for
		-- what this one is for. The Charge button casts Intervene at whoever you
		-- are looking at, and what you are aiming with is in the middle.
		-- The middle of the line, and the name says so: it used to be whatever
		-- corner a drag left the frame on, and it is the middle now because that
		-- is the only anchor a list can grow both ways out of. partyPoint is
		-- retired in Core.lua rather than reused, because the numbers under the
		-- old name meant a corner and reading them as a middle would put the
		-- frames somewhere nobody asked for.
		partyMiddle = { "CENTER", "UIParent", "CENTER", 0, -220 },

		-- The raid, which is its own frame and not the party in a bigger room.
		-- Its own place on the screen, its own block size, its own order and
		-- its own switches, because a grid of twenty five over your character
		-- and a line of four under it are two things you put in two places.
		raid = true,

		-- You are in the raid grid. The opposite of the party's answer and for
		-- the opposite reason: a grid of twenty five with exactly one person
		-- missing out of it is a grid you have to count along to read.
		raidSelf = true,

		-- The same tile at two thirds the size, because forty of them is a
		-- monitor. Five to a row is 412 across and eight rows is 325 down, which
		-- is a forty man raid in a rectangle you can put over your character
		-- and still see past.
		raidWidth = 80,
		raidHeight = 38,
		raidGap = 3,

		-- Across, so a group is a row of five and the groups stack downward.
		-- This is the shape Classic's raid actually has: the roster is parties
		-- of five whatever the raid size is, and a grid whose rows are those
		-- parties is a grid you find somebody in by reading the row you were
		-- told to heal. It shipped as the transpose and the transpose is still
		-- one press away, for a grid that has to live against a screen edge.
		raidGrow = "right",

		-- Eight groups of five, which is a full forty man. A raid that runs
		-- smaller shows the groups it has and reserves nothing for the rest,
		-- because the rectangle is measured off who is in the list.
		raidColumns = 8,
		raidPerColumn = 5,

		-- "group" is the raid's own group numbers, one run each, which is what
		-- somebody with assignments per group wants and what makes the headings
		-- mean anything. "role" is the party's own bands instead.
		raidOrder = "group",

		-- The group number on each run: over a column, or beside a row. Only
		-- ever drawn in group order, because in role order a run is not a group.
		raidHeadings = true,

		-- The role square is off in a raid and on in a party. At raid size it is
		-- a third of the tile's height in the corner the name starts from, and
		-- what it costs is the room the name is read in, which is the one thing
		-- a raid frame is for.
		raidRoleIcon = false,
		raidRange = true,
		raidZoom = 1,

		-- Over the middle of the screen, clear of the party under it. A raid
		-- frame goes where you can watch it without looking away from what you
		-- are fighting, and the top of the screen is where the client's own
		-- one has always been.
		raidMiddle = { "CENTER", "UIParent", "CENTER", 0, 290 },
	},

	charDefaults = {
		-- Roles you typed, name to role, lower cased. Per character rather than
		-- per account, because the answer is about the people this character
		-- plays with, and by name rather than by GUID, because a GUID would be
		-- right and unreadable.
		partyRoles = {},

		-- Which debuffs the row above each bar shows, as spell IDs in the order
		-- they are drawn.
		--
		-- Per character, and it was per account until an alt made the case. An
		-- arms warrior watches Rend, Deep Wound and Mortal Strike; a shaman on
		-- the same account applies none of the three and got all five of the
		-- warrior's squares, every one of them dark for the life of the
		-- character. One account cannot hold one answer to a question that is
		-- about which spells you have.
		--
		-- Empty here and seeded on first read rather than written down as a
		-- default: what belongs in it is ns.Class.Of("debuffs"), the class is
		-- not reliably known while the files load, and a list written at load
		-- would be the wrong one for everybody. Core's migration carries an account-wide list over on the
		-- first login after this moved, and a list that arrives with something
		-- in it counts as seeded so nothing you edited is overwritten.
		barsSpells = {},
		barsSpellsSeeded = false,
	},

	words = {
		bars = BarsWord,

		skin = SkinWord,

		cast = CastWord,

		party = PartyWord,

		raid = RaidWord,

		-- The client's own copies, one word each. Its own word rather than a
		-- corner of `skin`, because none of these four is part of the skin:
		-- they answer on a client where every Blizzard frame is standing
		-- exactly where it always was.
		hide = function(arg)
			local word, value = arg:match("^(%S*)%s*(.-)$")
			-- What is actually on the screen, name by name. Every bug these
			-- switches have had looked the same from the outside, a switch that
			-- was on with the frame still drawn, and telling a name this client
			-- spells differently from a frame the client put back used to take a
			-- guess at FrameXML. It takes this instead.
			if word == "probe" then
				ns.Print("hide: " .. ns.BlizzHide.Describe() .. ".")
				for _, row in ipairs(ns.BlizzHide.Probe()) do
					ns.Print(row)
				end
				return
			end
			local switch = ns.BlizzHide.Find(word)
			if not switch then
				ns.Print("hide takes one of: " .. Words() .. ".")
				for _, each in ipairs(ns.BlizzHide.Switches()) do
					ns.Print(("  %s: %s, %s"):format(each.word, each.label,
						ns.db[each.key] and "hidden" or "on screen"))
				end
				return
			end
			ns.db[switch.key] = ns.Command.Toggle(value)
			ns.BlizzHide.Apply()
			ns.Print(switch.label .. " "
				.. (ns.db[switch.key] and "hidden." or "back on screen."))
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
		"bars offset <-60-60>, bars marker on|off, bars level on|off, bars quest on|off",
		"bars clickthrough on|off, bars camera right|left|both|off",
		"bars cast on|off, the cast row under each bar",
		"bars max <1-15>, bars width <120-400>, bars zoom <1-3>",
		"bars debuff list|reset, bars debuff add|remove <spell id>, what the icon row tracks",
		"bars icon <16-32>, the size of one debuff square",
		"bars stack on|off, whether the client spaces plates by the size of our bar",
		"bars distance <20-60>|off, how many yards out a plate goes up",
		"bars fade on|off, whether a bar ramps in and out or simply appears",
		"skin on|off, the square player, target and target of target frames",
		"skin player|target|tot on|off, one frame at a time",
		"skin height <18-72>, skin width <90-360>, both in screen pixels",
		"skin link on|off, mirror the target block off the player block",
		"skin level <-100-100>, the target's drop from the player; drag either with the frames unlocked",
		"skin heals on|off, the incoming heal on the health gauge",
		"skin auras on|off, our own aura rows under the player and target blocks",
		"skin aura <12 up to the block height>, one aura square, in screen pixels",
		"skin debuffs <0-16>, skin buffs <0-32>, how long each row runs",
		"skin probe, what this client answered for each frame",
		"cast on|off, your own cast bar, which sits under the swing timer",
		"cast width <90-400>, cast height <10-40>, cast zoom <1-3>",
		"cast reset, the bar back where it started",
		"party on|off, blocks for the people you are grouped with",
		"party self on|off, whether your own block is in the list",
		"party role <name> tank|healer|dps|none, an answer you type",
		"party icons on|off, party range on|off",
		"party width <60-360>, party height <26-72>, party gap <0-20>",
		"party grow right|left|down|up, party zoom <1-3>",
		"party reset, the line back under the middle of the screen",
		"raid on|off, the grid, which is its own frame in its own place",
		"raid order group|role, a run of five per group or role bands",
		"raid columns <1-8> groups, raid percolumn <1-40> in a group",
		"raid headings on|off, the group number on each run of five",
		"raid self on|off, raid icons on|off, raid range on|off",
		"raid width <60-360>, raid height <26-72>, raid gap <0-20>",
		"raid grow right|left|down|up, raid zoom <1-3>, raid reset",
		"hide <switch> on|off, one of the client's own frames this addon replaces",
		"hide probe, every frame those switches name and what is on screen now",
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
			.. ("; %s; bars %s in and out"):format(ns.Plates.DescribeDistance(),
				ns.db.barsFade and "ramp" or "do not ramp")
			.. ("; debuffs at %dpx: %s"):format(ns.db.barsIconSize, ns.EnemyBars.DescribeSpells())
			.. ("; cast bar %s"):format(ns.Cast.Describe())
			.. ("; %s"):format(ns.FrameAuras.Describe())
			.. ("; your cast bar %s"):format(ns.PlayerCast.Describe())
			.. ("; party %s; raid %s; %s"):format(ns.Group.Describe("party"),
				ns.Group.Describe("raid"), ns.Unit.Role.Describe())
	end,

	lock = function()
		ns.EnemyBars.ApplyLock()
		ns.PlayerCast.Lock()
		ns.Group.Lock()
		ns.FrameSkin.Lock()
	end,

	reset = function()
		ns.db.barsPoint = ns.DefaultCopy("barsPoint")
		ns.db.barsWidth = ns.DefaultCopy("barsWidth")
		ns.db.barsOffset = ns.DefaultCopy("barsOffset")
		ns.db.barsCamera = ns.DefaultCopy("barsCamera")
		ns.db.barsZoom = ns.DefaultCopy("barsZoom")
		ns.db.barsStack = ns.DefaultCopy("barsStack")
		ns.db.barsIconSize = ns.DefaultCopy("barsIconSize")
		ns.db.barsCast = ns.DefaultCopy("barsCast")
		-- A fresh table, not ns.DefaultFor: adding and removing a debuff mutates
		-- the list in place, so by now the registered default is whatever the
		-- last edit left it as. This relays out on its own and the two calls
		-- under it do it again, which is one wasted pass on a command nobody
		-- types twice a minute and is cheaper than a reset that depends on
		-- what follows it.
		ns.EnemyBars.ResetSpells()
		ns.EnemyBars.ApplyLayout()
		ns.EnemyBars.Rebuild()
		ns.db.skin = ns.DefaultCopy("skin")
		-- A fresh table, not ns.DefaultFor: the default is handed out by
		-- reference and every toggle since has been writing into it.
		ns.db.skinFrames = { player = true, target = true, tot = true }
		ns.db.skinHeight = ns.DefaultCopy("skinHeight")
		ns.db.skinWidth = ns.DefaultCopy("skinWidth")
		ns.db.skinHeals = ns.DefaultCopy("skinHeals")
		-- The two corners a drag writes and the number a linked drag writes,
		-- back where they started. Reset already means put the frames back,
		-- and a level that survived one would be the only thing on these
		-- three frames that did not.
		ns.db.skinPlayerPoint = ns.DefaultCopy("skinPlayerPoint")
		ns.db.skinTargetPoint = ns.DefaultCopy("skinTargetPoint")
		ns.db.skinLink = ns.DefaultCopy("skinLink")
		ns.db.skinLevel = ns.DefaultCopy("skinLevel")
		ns.db.skinAuras = ns.DefaultCopy("skinAuras")
		ns.db.skinAuraSize = ns.DefaultCopy("skinAuraSize")
		-- Reset means put the frames back, and the client's own copies are
		-- frames this part took down. Somebody who put one back deliberately
		-- loses that in a reset, which is the same trade every other setting
		-- here makes and the reason `/wk reset` prints what it did.
		for _, switch in ipairs(ns.BlizzHide.Switches()) do
			ns.db[switch.key] = ns.DefaultCopy(switch.key)
		end
		ns.db.playerCast = ns.DefaultCopy("playerCast")
		ns.db.playerCastWidth = ns.DefaultCopy("playerCastWidth")
		ns.db.playerCastHeight = ns.DefaultCopy("playerCastHeight")
		ns.db.playerCastZoom = ns.DefaultCopy("playerCastZoom")
		-- PlayerCast.Reset puts the point back and lays the bar out again, so
		-- the four above it land in the same pass.
		ns.PlayerCast.Reset()
		for _, key in ipairs({ "party", "partySelf", "partyRoleIcon", "partyWidth",
			"partyHeight", "partyGap", "partyGrow", "partyZoom", "partyRange",
			"raid", "raidSelf", "raidRoleIcon", "raidWidth", "raidHeight",
			"raidGap", "raidGrow", "raidZoom", "raidRange", "raidColumns",
			"raidPerColumn", "raidOrder", "raidHeadings" }) do
			ns.db[key] = ns.DefaultCopy(key)
		end
		-- The roles you typed are deliberately not in that list. A reset means
		-- put the frames back, and who your friend heals on is not a frame: it
		-- is a fact about them that would have to be typed again. `party role
		-- <name> none` is how one of them comes off.
		--
		-- Group.Reset puts a point back and lays both lists out again, so the
		-- numbers above land in the same pass as the second of them.
		ns.Group.Reset("party")
		ns.Group.Reset("raid")
		ns.BlizzHide.Apply()
		ns.FrameSkin.Apply()
	end,

	panel = function(ui)
		ns.UnitFramesPanel.Draw(ui)
	end,
})
