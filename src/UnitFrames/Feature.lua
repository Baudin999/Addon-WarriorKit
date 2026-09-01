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

-- The words that are about the plate under the bar rather than about the bar:
-- which buttons it hands back, whether it takes the mouse at all, how the
-- driver spaces two of them and how far out it puts one up. Answers true when
-- it took the word, so BarsWord below stays a dispatcher for what we draw.
--
-- They are together because they are one subject and they read as one: every
-- line in here ends in a Plates call or a sentence about the client's own
-- nameplate driver, and none of them touches the widget.
local function PlateWord(option, value)
	if option == "camera" then
		if value ~= "right" and value ~= "left" and value ~= "both" and value ~= "off" then
			ns.Print("bars camera takes right, left, both or off.")
			return true
		end
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
	elseif option == "clickthrough" then
		ns.db.barsClickThrough = ns.Command.Toggle(value)
		ns.EnemyBars.Rebuild()
		ns.Print(ns.db.barsClickThrough
			and "plates pass the mouse through. The camera turns over a bar again, and clicking a plate no longer targets or marks."
			or "plates take the mouse. Click targeting and ctrl-click marking work, and the camera will not turn over a bar.")
	elseif option == "stack" then
		ns.db.barsStack = ns.Command.Toggle(value)
		ns.Plates.Apply()
		ns.Print(ns.db.barsStack
			and "asking the client to stack nameplates, so two mobs standing together get two bars that do not cover each other."
			or "nameplate motion handed back to the client. A plate is still sized to the bar on it, because that is what a click on the bar lands on.")
		ns.Print("plates: " .. ns.Plates.Describe() .. ".")
	elseif option == "distance" then
		local low, high = ns.Plates.DistanceRange()
		local yards = value == "off" and 0 or ns.Command.Number(value, low, high, "bars distance")
		if yards then
			ns.db.barsDistance = yards
			ns.Plates.Apply()
			ns.Print(ns.Plates.DescribeDistance() .. ".")
		end
	else
		return false
	end
	return true
end

-- What `bars quest` prints, out of line because BarsWord is a dispatcher at its
-- branch ceiling and a two-way message inside it costs two more.
local function QuestBadgeSaid()
	ns.Print("quest badge on the bars " .. (ns.db.barsQuest and "on" or "off")
		.. ": how many of this one a quest in your log still wants, in gold off the"
		.. " bar's right edge. The mob's own hover says which quest and what it"
		.. " drops at. Both are Questie's to answer.")
	ns.Print("a creature's hover says " .. ns.QuestDrops.Describe() .. ".")
end

local function BarsWord(option, value)
	if PlateWord(option, value) then
		ns.EnemyBars.Update()
		return
	end
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
	elseif option == "quest" then
		ns.db.barsQuest = ns.Command.Toggle(value)
		ns.EnemyBars.Rebuild()
		QuestBadgeSaid()
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
	elseif option == "fade" then
		ns.db.barsFade = ns.Command.Toggle(value)
		ns.Print(ns.db.barsFade
			and "bars ramp in as a mob comes into range and out again behind it."
			or "bars appear and disappear with the plate under them.")
	else
		ns.db.bars = ns.Command.Toggle(option)
		ns.EnemyBars.Rebuild()
		ns.Print("enemy bars " .. (ns.db.bars and "on" or "off") .. ".")
	end
	ns.EnemyBars.Update()
end

local FRAME_WORDS = { player = "player frame", target = "target frame",
	tot = "target of target" }

-- The words `/wk hide` answers to, off the same list the panel draws from so
-- the two cannot drift.
local function Words()
	local words = {}
	for index, switch in ipairs(ns.BlizzHide.Switches()) do
		words[index] = switch.word
	end
	return table.concat(words, ", ")
end

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

-- Your own cast bar, which is its own word rather than a corner of `skin` or of
-- `bars`. It is neither: it draws nothing on a Blizzard frame and nothing on a
-- nameplate, and it is a bar of its own that you drag where you want it.
local function CastWord(arg)
	local option, value = arg:match("^(%S*)%s*(.-)$")

	if option == "width" or option == "height" then
		local wideLow, wideHigh, tallLow, tallHigh = ns.PlayerCast.SizeRange()
		local low, high = wideLow, wideHigh
		if option == "height" then
			low, high = tallLow, tallHigh
		end
		local size = ns.Command.Number(value, low, high, "cast " .. option)
		if size then
			ns.db[option == "width" and "playerCastWidth" or "playerCastHeight"] = size
			ns.PlayerCast.Apply()
			ns.Print("cast " .. option .. " " .. size .. " pixels.")
		end
		return
	end

	if option == "zoom" then
		local zoom = ns.Command.Number(value, ns.UI.ZOOM_LOW, ns.UI.ZOOM_HIGH, "cast zoom")
		if zoom then
			ns.db.playerCastZoom = zoom
			ns.PlayerCast.Apply()
			ns.Print("cast zoom " .. zoom .. ", so one pixel of the design is "
				.. zoom .. " on screen.")
		end
		return
	end

	if option == "reset" then
		ns.PlayerCast.Reset()
		ns.Print("cast bar back under the swing timer.")
		return
	end

	ns.db.playerCast = ns.Command.Toggle(option)
	ns.PlayerCast.Apply()
	ns.Print("your cast bar " .. (ns.db.playerCast and "on" or "off")
		.. ": " .. ns.PlayerCast.Describe() .. ".")
	if not ns.db.playerCast and ns.db.hideBlizzPlayerCast then
		ns.Print("Blizzard's own is hidden by `/wk hide playercast`, so nothing"
			.. " is drawing your casts at all.")
	end
end

-- Which number a `party` or `raid` word is setting, and what it is allowed to
-- be. The key comes off UnitFrames/Group.lua rather than being spelled here a
-- second time, and so does every range, off the file that owns it.
local function ListRange(which, option)
	local wide, wideHigh, tall, tallHigh = ns.Group.SizeRange()
	local gapLow, gapHigh = ns.Group.GapRange()
	local columns, columnsHigh, per, perHigh = ns.Group.ColumnRange()
	if option == "width" then
		return ns.Group.Key(which, "width"), wide, wideHigh
	elseif option == "height" then
		return ns.Group.Key(which, "height"), tall, tallHigh
	elseif option == "gap" then
		return ns.Group.Key(which, "gap"), gapLow, gapHigh
	elseif option == "zoom" then
		return ns.Group.Key(which, "zoom"), ns.UI.ZOOM_LOW, ns.UI.ZOOM_HIGH
	elseif option == "columns" then
		return ns.Group.Key(which, "columns"), columns, columnsHigh
	elseif option == "percolumn" then
		return ns.Group.Key(which, "per"), per, perHigh
	end
	return nil
end

-- True where the word was one of the numbers, whether or not the number was any
-- good, so the dispatcher below knows it has been dealt with. The two column
-- words belong to the raid and answer nothing at all for the party, which has
-- no grid to describe.
local function ListNumber(which, option, value)
	local key, low, high = ListRange(which, option)
	if not key then
		return false
	end
	local size = ns.Command.Number(value, low, high, which .. " " .. option)
	if size then
		ns.db[key] = size
		ns.Group.Apply()
		ns.Print(("%s %s %d."):format(which, option, size))
	end
	return true
end

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

-- Which way a list runs. Four answers for the party, which is a line and can be
-- a line either way round, and two for the raid, which is a grid whose columns
-- already run across.
local function GrowWord(which, value)
	local across = value == "right" or value == "left"
	if across and which == "raid" then
		ns.Print("a raid is a grid, so it grows down or up and its columns run across.")
		return
	end
	if not across and value ~= "up" then
		value = "down"
	end
	ns.db[ns.Group.Key(which, "grow")] = value
	ns.Group.Apply()
	ns.Print(("the %s grows %s: it is centred on where you dragged it and fills"
		.. " outward from there, so this picks which end the first slot is at.")
		:format(which, value))
end

-- The words both lists answer to. Everything here reads its own list's setting
-- through ns.Group.Key, so the party cannot be given the raid's numbers by a
-- word that forgot which one it was called for.
local function ListWord(which, option, value)
	if ListNumber(which, option, value) then
		return
	end

	if option == "self" then
		local key = ns.Group.Key(which, "mine")
		ns.db[key] = ns.Command.Toggle(value)
		ns.Group.Apply()
		ns.Print(("your own block in the %s %s."):format(which,
			ns.db[key] and "on" or "off"))
	elseif option == "grow" then
		GrowWord(which, value)
	elseif option == "icons" then
		local key = ns.Group.Key(which, "icons")
		ns.db[key] = ns.Command.Toggle(value)
		ns.Group.Apply()
		ns.Print("role icons " .. (ns.db[key] and "on" or "off")
			.. ", drawn in Blizzard's own art on the portrait side of each block.")
	elseif option == "range" then
		local key = ns.Group.Key(which, "range")
		ns.db[key] = ns.Command.Toggle(value)
		ns.Group.Apply()
		ns.Print("out of range " .. (ns.db[key] and "on" or "off")
			.. ": a member you cannot reach drains to the track colour and says so.")
	elseif option == "order" and which == "raid" then
		ns.db.raidOrder = value == "role" and "role" or "group"
		ns.Group.Apply()
		ns.Print("raid order " .. ns.db.raidOrder .. ": " .. ns.Group.Describe("raid") .. ".")
	elseif option == "headings" and which == "raid" then
		ns.db.raidHeadings = ns.Command.Toggle(value)
		ns.Group.Apply()
		ns.Print("group headings " .. (ns.db.raidHeadings and "on" or "off")
			.. ", over each column of a raid ordered by group.")
	elseif option == "role" and which == "party" then
		PartyRole(value)
	elseif option == "reset" then
		ns.Group.Reset(which)
		ns.Print(("the %s is back where the addon ships it."):format(which))
	else
		local key = ns.Group.Key(which, "on")
		ns.db[key] = ns.Command.Toggle(option)
		ns.Group.Apply()
		ns.Print(("%s frames %s, %s."):format(which, ns.db[key] and "on" or "off",
			ns.Group.Describe(which)))
	end
end

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

ns.Register({
	name = "unit frames",
	order = 7,

	switch = {
		key = "bars",
		label = "enemy bars",
		apply = function() ns.EnemyBars.Rebuild() end,
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
		-- draws. 28 against a 198 pixel block is eight squares to a row, which
		-- is the number below, and it is a square you can read a stack count
		-- off from where you sit.
		skinAuraSize = 28,

		-- How many of each the row draws. Eight and eight, which is what a 198
		-- pixel block holds in one row at 28 pixels a square, so neither row
		-- ever wraps under the frame. Either at 0 turns that row off on its
		-- own; both at 0 is `skin auras off` said the long way.
		skinAuraDebuffs = 8,
		skinAuraBuffs = 8,

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

		-- The client's own copies of what this addon draws. Five switches, one
		-- per thing you can see twice, and every one of them means exactly what
		-- its label says.
		--
		-- All four ship on, because an addon that draws your buffs under your
		-- portrait and leaves the client's in the corner has not replaced
		-- anything, it has added to it. The frames each one takes down are in
		-- UnitFrames/Blizzard.lua.
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

		-- Your own block in the list. Off, because UnitFrames/Skin.lua already
		-- draws you as a block and two of your own frames on one screen is the
		-- exact complaint UnitFrames/Blizzard.lua exists to answer. On puts you
		-- in at your own role's slot rather than at the top.
		partySelf = false,

		partyRoleIcon = true,

		-- The same two numbers as the skin, because a party block and the
		-- player block are the same instrument and a party frame that does not
		-- match the player frame reads as a second addon. Width is the gauge;
		-- the block is that plus the height again for the role icon's square.
		partyWidth = 168,
		partyHeight = 34,
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

		-- Small, because forty of them is a monitor. A cell is the width here
		-- plus the height again for the role icon's square, so the shipped cell
		-- is 116 by 26 and a full five by five is 600 by 142.
		raidWidth = 90,
		raidHeight = 26,
		raidGap = 3,
		raidGrow = "down",

		-- Five groups of five, which is the raid everybody actually runs. Eight
		-- columns is what a forty man needs and it is one press away.
		raidColumns = 5,
		raidPerColumn = 5,

		-- "group" is the raid's own group numbers, a column each, which is what
		-- somebody with assignments per group wants and what makes the headings
		-- mean anything. "role" is the party's own bands instead.
		raidOrder = "group",

		-- The group number over each column. Only ever drawn in group order,
		-- because in role order a column is not a group.
		raidHeadings = true,

		-- The role icon is off in a raid and on in a party. At 26 pixels the
		-- square is a quarter of the cell and it costs the name the room to be
		-- read in, which is the one thing a raid frame is for.
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
		-- Empty here and seeded on first read, the way Loadouts/Feature.lua
		-- seeds its rows and for the same reason: what belongs in it is
		-- ns.Class.Of("debuffs"), the class is not reliably known while the
		-- files load, and a list written at load would be the wrong one for
		-- everybody. Core's migration carries an account-wide list over on the
		-- first login after this moved, and a list that arrives with something
		-- in it counts as seeded so nothing you edited is overwritten.
		barsSpells = {},
		barsSpellsSeeded = false,
	},

	words = {
		bars = function(arg)
			BarsWord(arg:match("^(%S*)%s*(.-)$"))
		end,

		skin = SkinWord,

		cast = CastWord,

		party = function(arg)
			ListWord("party", arg:match("^(%S*)%s*(.-)$"))
		end,

		raid = function(arg)
			ListWord("raid", arg:match("^(%S*)%s*(.-)$"))
		end,

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
		"skin level <-100-100>, the target's drop from the player",
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
		"party width <60-360>, party height <14-72>, party gap <0-20>",
		"party grow right|left|down|up, party zoom <1-3>",
		"party reset, the line back under the middle of the screen",
		"raid on|off, the grid, which is its own frame in its own place",
		"raid order group|role, group numbers a column each or role bands",
		"raid columns <1-8>, raid percolumn <1-40>, the shape of the grid",
		"raid headings on|off, the group number over each column",
		"raid self on|off, raid icons on|off, raid range on|off",
		"raid width <60-360>, raid height <14-72>, raid gap <0-20>",
		"raid grow down|up, raid zoom <1-3>, raid reset",
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
		-- The number a drag in Edit Mode writes, back where it started. Reset
		-- already means put the frames back, and a level that survived one
		-- would be the only thing on these three frames that did not.
		ns.db.skinLink = ns.DefaultCopy("skinLink")
		ns.db.skinLevel = ns.DefaultCopy("skinLevel")
		ns.db.skinAuras = ns.DefaultCopy("skinAuras")
		ns.db.skinAuraSize = ns.DefaultCopy("skinAuraSize")
		ns.db.skinAuraDebuffs = ns.DefaultCopy("skinAuraDebuffs")
		ns.db.skinAuraBuffs = ns.DefaultCopy("skinAuraBuffs")
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
