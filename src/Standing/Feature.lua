local ADDON, ns = ...

-- Everything Core and the panel need to know about the row of what you have
-- out. Standing.lua says what the slots are and what is in them, Row.lua draws
-- them on your screen, and neither names anything outside this folder.
--
-- Gated on class, which is the difference between this part and the two rows
-- beside it. A missing sharpening stone and a trinket you have not pressed are
-- facts about anybody; a slot with nothing standing in it exists only for a
-- class whose file wrote the slots down. Nothing here names a totem, an element
-- or a stance: the plan is in Class\<yours>.lua and this file reads the class's
-- own word for it off Standing.Word.

local function SetRow(value)
	ns.db.standing = value
	ns.StandingRow.Apply()
end

-- The words the row answers to.
--
-- Two of them reach this handler, and which one you type is a fact about your
-- class rather than about the addon: a shaman thinks of this row as the totems
-- and a warrior will think of it as the stances. One part, one page, two names
-- for it, and the refusal on a class with neither says so.
local StandingWord = ns.Command.Word({
	name = "standing",
	apply = function() ns.StandingRow.Apply() end,
	show = function()
		return ns.Standing.Describe() .. "."
	end,

	{ "idle", toggle = true, key = "standingIdle",
	  say = function(on)
		return on and "the row stays up out of combat."
			or "out of combat the row is up only while something is still standing."
	  end },

	ns.Command.Zoom("standingZoom", "the row draws at %dx."),

	{ "list", run = function()
		local refusal = ns.Standing.Refusal()
		if refusal then
			ns.Print(refusal .. ".")
			return
		end
		for index = 1, ns.Standing.Count() do
			local slot = ns.Standing.Slot(index)
			local up, _, _, _, name = ns.Standing.State(index)
			ns.Print(("  %-8s %s"):format(slot.label,
				up and name or ("nothing in it")))
		end
	  end },

	otherwise = { toggle = true, key = "standing",
	  say = function(on)
		return "the row is " .. (on and "on" or "off") .. "."
	  end },
})

ns.Register({
	name = "standing",

	-- Straight after the cooldown row, which is the other row over your
	-- character that is up for the whole fight. The twenty three parts below it
	-- moved down one to make the room, because the registry takes whole numbers
	-- only.
	order = 12,

	switch = {
		key = "standing",
		label = "the row of what you have out",
		apply = function(value) SetRow(value) end,
		-- Nothing here is built on a class whose file wrote no slots down, so
		-- the row is left out of On and off rather than drawn there refusing.
		-- That is Charge/Feature.lua's argument and it applies word for word:
		-- there would be no page in the rail to be a shortcut to.
		available = function() return ns.Standing.Available() end,
	},

	zooms = {
		{ key = "standingZoom", label = "What you have out",
		  apply = function() ns.StandingRow.Apply() end },
	},

	defaults = {
		standing = true,

		-- 1, and for the cooldown row's reason rather than the buff nag's. This
		-- row is up for whole fights and carries a number per square, and a row
		-- of double sized squares over your character for three minutes at a
		-- time is in the way rather than in view.
		standingZoom = 1,

		-- Off, so the row goes away between fights once everything has run out.
		standingIdle = false,

		-- Above the buff nag rather than below it. The nag owns 157 and is only
		-- there when something is wrong, so a row that sat under it would jump
		-- up and down the screen as the nag came and went. This one is the
		-- steadier of the two and takes the higher line. Whole numbers, because
		-- half of an odd number is half a pixel and this frame is on the grid.
		standingPoint = { "CENTER", "UIParent", "CENTER", -1, 205 },
	},

	words = {
		totems = StandingWord,
		stances = StandingWord,
	},

	-- Both words, because the part answers to both and which one you would
	-- think to type is a fact about your class.
	help = {
		"totems|stances on|off, the row of what you have out, over your character",
		"totems list, one line per slot and what is in it",
		"totems idle on|off, zoom 1 to 3",
	},

	status = function()
		return ns.Standing.Describe()
	end,

	lock = function()
		ns.StandingRow.Lock()
	end,

	reset = function()
		ns.StandingRow.Reset()
	end,

	panel = function(ui)
		-- No page at all on a class that wrote no slots down, rather than a
		-- tick box that writes a setting nothing on this character reads.
		if not ns.Standing.Available() then
			return
		end

		ui.Section(ns.Standing.Page(), ns.Options.CLASS)
		ui.Lede("One square per slot, in the same order every time. An empty one"
			.. " stays as a hole, so what you have out is the shape of the row"
			.. " rather than four names.")

		ui.Reading("the row", ns.Standing.Describe)

		ui.Check("keep it up out of combat",
			function() return ns.db.standingIdle end,
			function(value)
				ns.db.standingIdle = value
				ns.StandingRow.Apply()
			end)
		ui.Hint("Off, the row is there in a fight and afterwards while something"
			.. " is still standing. On, it never leaves.")

		ui.Zoom(function() return ns.db.standingZoom end,
			function(value)
				ns.db.standingZoom = value
				ns.StandingRow.Apply()
			end)

		ui.Action(function() return "put the row back" end, function()
			ns.StandingRow.Reset()
		end)
		ui.Hint("Unlock the frames to drag the row somewhere else. This puts it"
			.. " back where the addon ships it.")
	end,
})

-- What the timing figure on the performance tab is a timing of. A row of four
-- squares costs four calls into the client a tick; the number only means
-- something beside a count of them.
ns.Perf.Gauge("slots watched", function()
	return ns.StandingRow.Shown()
end)
