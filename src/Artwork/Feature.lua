local ADDON, ns = ...

-- Everything Core and the panel need to know about the bar art.
-- Artwork.lua holds the behaviour and never talks to either.

local function Describe()
	local count = ns.Artwork.Found()
	if count == 0 then
		return "found nothing to strip, this client names the art something else"
	end
	if ns.db.blizzArt then
		return ("Blizzard art shown, %d regions"):format(count)
	end
	if ns.Artwork.Deferred() then
		return ("stripped %d regions, the rest follows when combat drops"):format(count)
	end
	return ("stripped %d regions"):format(count)
end

local function Set(value)
	ns.db.blizzArt = value
	ns.Artwork.Apply()
end

ns.Register({
	name = "artwork",
	order = 5,

	defaults = {
		-- False means the gryphons and the metal strip are gone, which is the
		-- point of the part and so the state it starts in.
		blizzArt = false,
	},

	words = {
		art = function(arg)
			Set(ns.Command.Toggle(arg))
			ns.Print("Blizzard bar art " .. (ns.db.blizzArt and "shown" or "stripped")
				.. ", " .. Describe() .. ".")
		end,
	},

	help = {
		"art on|off",
	},

	status = Describe,

	reset = function()
		Set(ns.DefaultFor("blizzArt"))
	end,

	panel = function(ui)
		ui.Header("Bar art")
		ui.Check("show Blizzard bar art",
			function() return ns.db.blizzArt end,
			Set)
		ui.Note(function()
			if ns.db.blizzArt then
				return "The gryphons, the metal strip behind bar 1 and the page arrows are visible."
			end
			return "Gryphons, metal strip and page arrows stripped. The experience bar is left alone."
		end)
	end,
})
