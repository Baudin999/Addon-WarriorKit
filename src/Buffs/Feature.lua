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
		local zoom = ns.Command.Number(value, ns.UI.ZOOM_LOW, ns.UI.ZOOM_HIGH, "buff zoom")
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

	-- One switch per watched entry, driven off the list itself so the four words
	-- and the four tick boxes on the panel cannot drift apart. Last of the named
	-- words and ahead of the bare on|off, because an unknown word has to reach
	-- the toggle the way it always did.
	local entry = ns.Upkeep.ByWord(option)
	if entry then
		if entry.warrior and not ns.IsWarrior() then
			ns.Print(entry.fixed .. " is on the row for a warrior and nowhere else,"
				.. " so there is nothing here to switch off.")
			return
		end
		ns.Upkeep.SetWatched(entry.key, ns.Command.Toggle(value))
		ns.BuffNag.Apply()
		ns.Print(entry.fixed .. (ns.Upkeep.Watched(entry.key)
			and " is watched again on this character."
			or " is switched off on this character."))
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

	switch = {
		key = "buffs",
		label = "the missing-buff row",
		apply = function(value) SetBuffs(value) end,
	},

	-- Beside the swing timer, which is the other thing on screen that says what
	-- to press next. Not a whole number for the reason Swing/Feature.lua's is
	-- not: renumbering five parts to make room for one row is a bigger change
	-- than a fraction is a wart.
	order = 9,

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

	-- Which entries this character still watches, keyed by the entry's own key
	-- and holding false for each one you switched off. Absent means watched, so
	-- a fresh character carries an empty table.
	--
	-- Per character, and it is the only buff setting that is. Everything in
	-- `defaults` above is a preference about the row itself: how big it is,
	-- whether it breathes, whether it draws in an inn. Those are the same answer
	-- on every character you own and they belong to the account.
	--
	-- Whether a missing sharpening stone is worth telling you about is not a
	-- preference. It is a fact about the character, and it differs between two
	-- characters on the same account more sharply than almost anything else this
	-- addon stores. A raiding main carries a stack of stones and wants the
	-- square. A bank alt has never bought one, is never going to, and is shown a
	-- red square over its head every time it leaves combat for a thing it cannot
	-- fix. That is the exact failure this setting exists to end, so putting the
	-- answer in ns.db would end it for one of those two characters and repeat it
	-- for the other.
	--
	-- The migration is free. Core moves a key that changes scope out of the
	-- account table once at ADDON_LOADED, and this key has never been in it.
	charDefaults = {
		buffWatch = {},
	},

	words = {
		buffs = BuffWord,
	},

	help = {
		"buffs on|off, the row of what is missing",
		"buffs weapon|offhand|shout|food on|off, one entry at a time",
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
		ui.Section("Missing buffs", "You")
		ui.Lede("A row of squares over your character, and only while something you keep up is missing.")

		ui.Reading("your main hand", function()
			if not ns.Upkeep.EnchantShape() then
				return "this client has no GetWeaponEnchantInfo"
			end
			if not GetInventoryItemLink("player", ns.Gear.MAINHAND) then
				return "empty, so there is nothing to put a stone on"
			end
			local hand = ns.Upkeep.Left(ns.Gear.MAINHAND)
			if hand == nil then
				return "bare"
			end
			return ("enchanted, %d minutes left"):format(math.floor(hand / 60))
		end)
		ui.Reading("the row", ns.BuffNag.Describe)

		ui.Section("What it watches", "You")
		ui.Lede("One switch per thing the row watches. Switched off is not watched, not drawn, not counted.")

		-- Built from Upkeep's own list rather than from four literals here, so a
		-- fifth entry would arrive with its switch already on the page. Battle
		-- Shout is skipped on anyone who cannot cast it, which is the same call
		-- the Charge page makes: a tick box that writes a setting nothing reads
		-- is worse than leaving it out.
		for index = 1, #ns.Upkeep.Fixed() do
			local entry = ns.Upkeep.Fixed()[index]
			if not entry.warrior or ns.IsWarrior() then
				ui.Check(entry.switch,
					function() return ns.Upkeep.Watched(entry.key) end,
					function(value)
						ns.Upkeep.SetWatched(entry.key, value)
						ns.BuffNag.Apply()
					end)
			end
		end
		ui.Hint("These four are per character, because whether a bare weapon is worth a square is a raiding main's answer and not a bank alt's. Everything else here is the account's.")

		ui.Reading("switched off", function()
			local silent, names = ns.Upkeep.Silent()
			return silent == 0 and "nothing, the row is watching all of it" or names
		end)

		ui.Section("Racials", "You")
		ui.Lede("A square while your racial is off cooldown, in combat, because that is damage you are not doing.")

		ui.Check("nag me about my racial",
			function() return ns.db.buffRacial end,
			function(value)
				ns.db.buffRacial = value
				ns.BuffNag.Apply()
			end)
		ui.Hint("Only the racials that are damage are nagged about, which is Blood Fury and Berserking. The rest are cooldowns you spend when something happens.")

		ui.Check("make it pulse",
			function() return ns.db.buffPulse end,
			function(value) ns.db.buffPulse = value end)
		ui.Hint("The square breathes over about a second and a half. There is no sound and there will not be: a chime competes with the sounds you are already listening for.")

		ui.Reading("yours", ns.Racials.Describe)

		ui.Section("Your own buffs", "You")
		ui.Lede("Up to six more auras of your own on the row, added by spell id.")

		-- No switch on these, and that is a decision rather than an omission.
		-- The four above cannot be taken off the row, so the only way to stop
		-- one is a switch. A spell you added is one you can remove in a press,
		-- and remove is a better answer than off: it hands the slot back, and a
		-- flask you have stopped keeping up is not a thing you want listed in a
		-- quiet state, it is a thing you want gone. A switch here would turn six
		-- slots into twelve states with nothing on screen to tell them apart.
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
		ui.Hint("The id is the last part of the spell's address on Wowhead, and it is the aura that lands on you rather than the item that applies it. A flask is an item; its buff is a spell.")

		ui.Reading("slots used", function()
			return ("%d of %d"):format(#ns.Upkeep.Extra(), ns.Upkeep.MaxExtra())
		end)

		ui.Section("Placing", "You")
		ui.Lede("Where the row sits and how big it is drawn. Unlock the frames to drag it.")

		ui.Check("nag in inns and cities too",
			function() return ns.db.buffResting end,
			function(value)
				ns.db.buffResting = value
				ns.BuffNag.Apply()
			end)

		ui.Action(function() return "put the row back" end, function()
			ns.BuffNag.Reset()
		end)
	end,
})

-- What the timing figure on the performance tab is a timing of. A row with
-- nothing on it costs one comparison; the number only means something beside a
-- count of squares.
ns.Perf.Gauge("buff squares on screen", function()
	return ns.BuffNag.Shown()
end)
