local ADDON, ns = ...

-- Everything Core and the panel need to know about the world hover. World.lua
-- owns the event, the box and the ticker, and knows the name of no part.

local World = ns.World

ns.Register({
	name = "world",
	order = 25,

	switch = {
		key = "worldTips",
		label = "creatures in the addon's own box",
		apply = function() World.Apply() end,
	},

	defaults = {
		-- On. A mob was the last thing in the game still raising a parchment
		-- scroll beside an interface that has one nowhere else, and a setting
		-- defaulted off would leave it there for everybody who never opens this
		-- window.
		worldTips = true,
	},

	words = {
		world = function(arg)
			World.Set(ns.Command.Toggle(arg))
			ns.Print("hovering a creature: " .. World.Describe() .. ".")
		end,
	},

	help = {
		"world on|off, the addon's own tooltip on a creature in the world",
	},

	status = function()
		return World.Describe()
	end,

	reset = function()
		World.Set(ns.DefaultFor("worldTips"))
	end,

	panel = function(ui)
		ui.Section("The world hover", "The screen")
		ui.Lede("A creature under the cursor is described in the addon's own box, out in the world and on a nameplate both. Off puts Blizzard's parchment back.")

		ui.Reading("now", World.Describe)
	end,
})
