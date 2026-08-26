local ADDON, ns = ...

-- Everything Core and the panel need to know about the buff nag. Upkeep.lua
-- says what should be up and is not, Racials.lua says which cooldown you own
-- and are not pressing, Nag.lua draws the row, and none of the three names
-- anything outside this folder.
--
-- Not gated on warrior. A lapsed sharpening stone costs a hunter's melee weapon
-- exactly what it costs a warrior's, and a troll rogue forgets Berserking the
-- same way. The one warrior-only entry is Battle Shout and it is gated inside
-- Upkeep.Rebuild, which is the same seam Charge/Feature.lua draws: the part
-- runs for everybody and the class-specific piece asks ns.IsWarrior.

local LOW_ZOOM, HIGH_ZOOM = 1, 3

local function SetBuffs(value)
	ns.db.buffs = value
	ns.BuffNag.Apply()
end

local function BuffWord(arg)
	local option, value = arg:match("^(%S*)%s*(.-)$")

	if option == "" or option == "show" then
		ns.Print("buff nag " .. ns.BuffNag.Describe() .. ".")
		return
	end

	if option == "racial" then
		ns.db.buffRacial = ns.Command.Toggle(value)
		ns.BuffNag.Apply()
		ns.Print("racial nag " .. (ns.db.buffRacial and "on" or "off")
			.. ", " .. ns.Racials.Describe() .. ".")
		return
	end

	if option == "pulse" then
		ns.db.buffPulse = ns.Command.Toggle(value)
		ns.Print("the racial square " .. (ns.db.buffPulse and "pulses" or "sits still") .. ".")
		return
	end

	if option == "resting" then
		ns.db.buffResting = ns.Command.Toggle(value)
		ns.BuffNag.Apply()
		ns.Print(ns.db.buffResting and "the row nags in inns and cities too."
			or "the row is quiet while you are resting.")
		return
	end

	if option == "zoom" then
		local zoom = ns.Command.Number(value, LOW_ZOOM, HIGH_ZOOM, "buff zoom")
		if zoom then
			ns.db.buffZoom = zoom
			ns.BuffNag.Apply()
			ns.Print(("the buff row draws at %dx."):format(zoom))
		end
		return
	end

	if option == "list" then
		local extra = ns.Upkeep.Extra()
		if #extra == 0 then
			ns.Print("nothing of your own on the row. buffs add <spell id>, or use the panel.")
			return
		end
		for index = 1, #extra do
			local id = extra[index]
			ns.Print(("  %d  %s"):format(id, ns.SpellName(id) or "this client cannot name it"))
		end
		return
	end

	if option == "add" then
		local ok, message = ns.Upkeep.Add(value)
		ns.Print(ok and (message .. " is on the row.") or message)
		ns.BuffNag.Apply()
		return
	end

	if option == "remove" then
		if ns.Upkeep.Remove(value) then
			ns.Print("off the row.")
			ns.BuffNag.Apply()
		else
			ns.Print("nothing on the row has that id. buffs list shows them.")
		end
		return
	end

	SetBuffs(ns.Command.Toggle(option))
	ns.Print("buff nag " .. (ns.db.buffs and "on" or "off") .. ".")
end

-- One row of the list you keep: the spell's own icon, its name, and the button
-- that takes it off. Built once at login at the cap and shown only while the
-- list is that long, because the panel is built once and the list is not.
--
-- The same shape UnitFrames/Feature.lua's debuff row has, and deliberately a
-- second copy rather than a shared widget. UI/Widgets.lua has no list widget,
-- two callers is not enough to grow one, and the two lists differ in what a row
-- does when the client cannot name the id.
local function ExtraRow(ui, slot)
	local M, C = ns.UI.Metric, ns.UI.Color
	local removeWidth = 62
	local row, art, name

	local function Spell()
		return ns.Upkeep.Extra()[slot]
	end

	ui.Custom(function(frame)
		row = frame

		art = ns.UI.Icon(frame, "ARTWORK")
		art:SetSize(M.control, M.control)
		art:SetPoint("TOPLEFT")

		local remove = ns.UI.Button(frame, { label = "remove", width = removeWidth,
			onClick = function()
				local id = Spell()
				if id then
					ns.Upkeep.Remove(id)
					ns.BuffNag.Apply()
					ns.Options.Refresh()
				end
			end })
		remove:SetPoint("TOPRIGHT")

		name = ns.UI.Label(frame, M.font, C.text, "LEFT", ns.UI.FLAT)
		name:SetPoint("LEFT", art, "RIGHT", M.gutter, 0)
		name:SetPoint("RIGHT", remove, "LEFT", -M.gutter, 0)

		-- An unused slot is not a short row, it is no row. Six of them left at
		-- a control's height would put a hand's width of air under the list.
		return function(cell)
			local used = Spell() ~= nil
			cell.gap = used and M.rowGap or 0
			return used and M.control or 0
		end
	end, { height = M.control, refresh = function()
		local id = Spell()
		row:SetShown(id ~= nil)
		if id then
			art:SetTexture(ns.SpellTexture(id))
			name:SetText(ns.SpellName(id) or ("spell " .. id .. ", unknown to this client"))
		end
	end })
end

ns.Register({
	name = "buffs",

	-- Beside the swing timer, which is the other thing on screen that says what
	-- to press next. Not a whole number for the reason Swing/Feature.lua's is
	-- not: renumbering five parts to make room for one row is a bigger change
	-- than a fraction is a wart.
	order = 7.6,

	defaults = {
		buffs = true,

		-- On, because the racial half is the reason the feature was asked for.
		-- Off leaves the missing-buff half running, which is the split anybody
		-- turning this off actually wants.
		buffRacial = true,

		-- On. A still square in the middle of the screen is a thing you learn
		-- to look past in a week, and the request was for something you cannot
		-- ignore. Off is a real preference and this is where it lives.
		buffPulse = true,

		-- Off, meaning quiet while you are resting. An inn or a capital is
		-- where you have not put a stone on yet on purpose, and a row that
		-- stayed up through an hour at the auction house would be furniture by
		-- the time it mattered. On for anyone who buffs in the bank.
		buffResting = false,

		-- 2, and this is the one readout in the addon that ships at twice the
		-- size of the others. Its whole job is to be impossible to miss, and 27
		-- design pixels at 2x is 54 physical ones, which is also the other size
		-- a 64 texel icon resamples onto exactly. Bigger is not sharper: 3x
		-- draws 81 from a 54 texel source and blends.
		buffZoom = 2,

		-- Above the middle of the screen, over your character's head and clear
		-- of the charge icon at -160 and the swing bars at -220. Both numbers
		-- whole, because half of an odd number is half a pixel and this frame
		-- is on the grid.
		buffPoint = { "CENTER", "UIParent", "CENTER", 0, 140 },

		-- Empty. Which flask and which elixirs you keep up is a fact about your
		-- spec and your gold, and these clients will not say an aura came from
		-- an elixir, so there is nothing to ship a default for. Spell ids, in
		-- the order you added them.
		buffExtra = {},
	},

	words = {
		buffs = BuffWord,
	},

	help = {
		"buffs on|off, the row of what is missing",
		"buffs racial on|off, the racial you have not pressed",
		"buffs pulse on|off, resting on|off, zoom 1 to 3",
		"buffs list, buffs add|remove <spell id>, your own flask and elixirs",
	},

	status = function()
		return ns.BuffNag.Describe()
	end,

	lock = function()
		ns.BuffNag.Lock()
	end,

	reset = function()
		ns.BuffNag.Reset()
	end,

	panel = function(ui)
		ui.Header("Missing buffs")

		ui.Check("show the row", function() return ns.db.buffs end, SetBuffs)

		ui.Note(function()
			return "A row of squares over your character, and only when something is"
				.. " wrong. Nothing missing means nothing drawn, so the row carries its"
				.. " whole message in being there at all. Unlock the frames and it shows"
				.. " everything it watches, which is how you find it to drag it."
		end)

		ui.Note(function()
			return "Checked out of combat, because out of combat is when you can fix it."
				.. " A stone that runs out mid pull is not something to tell you about"
				.. " while you are swinging."
		end)

		ui.Note(function()
			if not ns.Upkeep.EnchantShape() then
				return "|cffd08040This client has no GetWeaponEnchantInfo|r, so nothing is"
					.. " said about either hand. Every other entry still works."
			end
			if not GetInventoryItemLink("player", ns.Gear.MAINHAND) then
				return "Nothing in your main hand, so there is nothing to put a stone on."
			end
			local hand = ns.Upkeep.Left(ns.Gear.MAINHAND)
			if hand == nil then
				return "|cffd08040Nothing on your main hand weapon.|r A stone or an oil is"
					.. " the cheapest damage increase in the game and the easiest to"
					.. " forget after a weapon swap."
			end
			return ("Main hand enchanted, %d minutes left."):format(math.floor(hand / 60))
		end)

		ui.Note(function()
			return "The off hand is only ever nagged about when there is a weapon in it."
				.. " A shield takes no stone, a held-in-off-hand item takes no stone, and"
				.. " an empty hand is most warriors most of the time. All three are the"
				.. " client's own answer to whether that hand holds a weapon, not a guess"
				.. " off what is in the slot."
		end)

		ui.Note(function()
			if not ns.IsWarrior() then
				return "Battle Shout is on the list for a warrior and nowhere else. The"
					.. " weapon enchants and the food buff are worth the same to anybody"
					.. " standing in melee and are watched here."
			end
			return "Battle Shout is matched by name, so rank 1 covers all eight and"
				.. " somebody else's shout counts as yours, which is the truth: the"
				.. " attack power is on you either way."
		end)

		ui.Header("Racials")

		ui.Check("nag me about my racial",
			function() return ns.db.buffRacial end,
			function(value)
				ns.db.buffRacial = value
				ns.BuffNag.Apply()
			end)

		ui.Note(function()
			return "Yours: " .. ns.Racials.Describe() .. "."
		end)

		ui.Note(function()
			if not ns.Racials.Worth() then
				return "Only the racials that are damage are nagged about, which is Blood"
					.. " Fury and Berserking. Stoneform and War Stomp and the rest are"
					.. " cooldowns you spend when something happens, not on a timer, and a"
					.. " row that shouted about them every fight would teach you to ignore"
					.. " the row."
			end
			return "This one fires in combat, which is the opposite of the half above and"
				.. " on purpose. A missing buff is something to fix between pulls. A"
				.. " racial off cooldown while you are swinging is damage you are not"
				.. " doing this second."
		end)

		ui.Check("make it pulse",
			function() return ns.db.buffPulse end,
			function(value) ns.db.buffPulse = value end)

		ui.Note(function()
			if not ns.db.buffPulse then
				return "A still square. Quieter, and easier to look past, which is the"
					.. " trade you are making."
			end
			return "The square breathes over about a second and a half. There is no sound"
				.. " and there will not be: a chime in a raid competes with the sounds you"
				.. " are already listening for, and a racial coming off cooldown is worth"
				.. " noticing within a few seconds rather than immediately."
		end)

		ui.Header("Placing")

		ui.Check("nag in inns and cities too",
			function() return ns.db.buffResting end,
			function(value)
				ns.db.buffResting = value
				ns.BuffNag.Apply()
			end)

		ui.Stepper("zoom", LOW_ZOOM, HIGH_ZOOM, 1,
			function() return ns.db.buffZoom end,
			function(value)
				ns.db.buffZoom = value
				ns.BuffNag.Apply()
			end)

		ui.Note(function()
			if ns.db.buffZoom == 2 then
				return "Each square is 54 screen pixels, which is one stored texel per"
					.. " pixel and the sharpest a spell icon gets."
			end
			if ns.db.buffZoom == 1 then
				return "Each square is 27 screen pixels, which is also exact. Smaller and"
					.. " quieter than the row ships at."
			end
			return "Each square is 81 screen pixels, drawn from a 54 texel source, so the"
				.. " art is blended rather than exact. Big, and slightly soft."
		end)

		ui.Action(function() return "put the row back" end, function()
			ns.BuffNag.Reset()
		end)

		ui.Header("Your own")

		ui.Note(function()
			return "These clients will not tell you an aura came from an elixir. There is"
				.. " no category on an aura and no call that maps one back to the item, so"
				.. " a built-in flask check would be forty hand written spell ids that go"
				.. " stale on the next patch and are wrong in a way nothing reports. This"
				.. " list is the honest version of that."
		end)

		for slot = 1, ns.Upkeep.MaxExtra() do
			ExtraRow(ui, slot)
		end

		ui.TextField("add a buff by id",
			function() return "" end,
			function(text)
				if text:match("^%s*$") then
					return
				end
				local ok, message = ns.Upkeep.Add(text)
				ns.Print(ok and (message .. " is on the row.") or message)
				ns.BuffNag.Apply()
			end)

		ui.Note(function()
			local extra = ns.Upkeep.Extra()
			return ("%d of %d slots used. The id is the last part of the spell's address"
				.. " on Wowhead, and it has to be the id of the aura that lands on you"
				.. " rather than of the item that applies it. Flask of Relentless Assault"
				.. " is an item; the buff it puts on you is a spell with its own number.")
				:format(#extra, ns.Upkeep.MaxExtra())
		end)
	end,
})

-- What the timing figure on the performance tab is a timing of. A row with
-- nothing on it costs one comparison; the number only means something beside a
-- count of squares.
ns.Perf.Gauge("buff squares on screen", function()
	return ns.BuffNag.Shown()
end)
