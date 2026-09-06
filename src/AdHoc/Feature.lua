local ADDON, ns = ...

-- Everything Core needs to know about the bars you made yourself. AdHoc.lua is
-- the list, Bars.lua is the frames, the keys and the tick, Panel.lua is the
-- page, and this file is the registration and the slash word. It draws
-- nothing.

-- What `/wk adhoc <bar> <key>` says back. Three sentences rather than one,
-- because a key this addon takes is a key something else was using, and saying
-- which is what stops somebody wondering all evening why their jump is gone.
local function BindWord(index, key)
	local bar = ns.AdHoc.Get(index)
	local displaced, why = ns.AdHocBars.Bind(index, key)
	if not displaced then
		ns.Print(why)
	elseif key == "" then
		ns.Print(bar.name .. " is unbound.")
	elseif displaced ~= "" then
		ns.Print(("%s opens %s. It shadows %s, and your saved bindings are untouched.")
			:format(key, bar.name, displaced))
	else
		ns.Print(("%s opens %s. Nothing else wanted it."):format(key, bar.name))
	end
end

local function List()
	local list = ns.AdHoc.All()
	if #list == 0 then
		return "no bars yet. /wk adhoc add <name> makes one."
	end
	for index, bar in ipairs(list) do
		ns.Print(("%d %s: %s, %d square%s"):format(index, bar.name,
			ns.AdHocBars.Describe(index), #bar.buttons, #bar.buttons == 1 and "" or "s"))
	end
	return nil
end

local Word = ns.Command.Word({
	name = "adhoc",
	apply = function() ns.AdHocBars.Apply() end,
	show = List,

	ns.Command.Zoom("adhocZoom", "ad hoc bars at %.1fx."),

	{ "add", run = function(_, rawValue)
		local index, why = ns.AdHoc.Add(rawValue:match("^%s*(.-)%s*$"))
		ns.Print(index and ("added " .. ns.AdHoc.Get(index).name .. ".") or why)
	end },

	{ "reset", run = function()
		ns.AdHocBars.Reset()
		ns.Print("every ad hoc bar is back where it started.")
	end },

	{ "on", toggle = true, key = "adhoc", what = "adhoc",
		say = function(on) return "ad hoc bars " .. (on and "on." or "off.") end },

	-- A word that is not one of the above is a bar, by number or by name, and
	-- what follows it is the key.
	otherwise = function(option, value)
		if option == "off" then
			ns.db.adhoc = false
			ns.AdHocBars.Apply()
			ns.Print("ad hoc bars off.")
			return
		end
		local index = ns.AdHoc.Find(option)
		if not index then
			ns.Print(("no bar called %s. /wk adhoc lists them."):format(option))
			return
		end
		local key = value:upper()
		if key == "NONE" then
			key = ""
		end
		BindWord(index, key)
	end,
})

ns.Register({
	name = "adhoc",
	order = 35,

	switch = {
		key = "adhoc",
		label = "bars of your own, each on a key",
		apply = function() ns.AdHocBars.Apply() end,
		page = "Ad hoc bars",
	},

	zooms = {
		{ key = "adhocZoom", label = "Ad hoc bars", apply = function() ns.AdHocBars.Apply() end },
	},

	defaults = {
		adhoc = true,
		-- 1.4, not 1. Every other zoom in the addon starts at 1 because every
		-- other part is on the screen all the time and a part you read all
		-- night wants to be small. A bar is on the screen for the second your
		-- thumb is on its key, and a square you have that long has to be read
		-- in one look. 1.4 puts the 27-unit square at 38, which is the size the
		-- client's own action bar draws at.
		adhocZoom = 1.4,
	},

	-- A bar is the character's: a trade skill belongs to one character and a
	-- totem to one class, and a bar of either written into the account would be
	-- a bar of spells another character does not know.
	--
	-- The list starts empty rather than carrying a bar here, because
	-- ApplyDefaults copies a default one level deep and a list of tables would
	-- hand every character the same rows.
	charDefaults = {
		adhocBars = {},   -- { name, key, displaced, point, columns, close, buttons = { { kind, name, id, icon } } }
		adhocShown = 1,   -- which one the page is showing
	},

	words = { adhoc = Word },

	help = {
		"adhoc, every bar, its key and how many squares it holds",
		"adhoc add <name>, a new bar",
		"adhoc <bar> <key|none>, the key that shows and hides that bar",
		"adhoc zoom 1.5, the bars' zoom, 0.5 to 3",
		"adhoc reset, every bar back where it started",
		"adhoc on|off",
	},

	status = function()
		if not ns.db.adhoc then
			return "off"
		end
		local parts = {}
		for index, bar in ipairs(ns.AdHoc.All()) do
			parts[#parts + 1] = bar.name .. " " .. ns.AdHocBars.Describe(index)
		end
		if #parts == 0 then
			return "none yet"
		end
		return table.concat(parts, ", ")
	end,

	-- The lock does not reach a bar: it is dragged from a snippet, which no Lua
	-- flag can hold, and it is only on the screen while you are using it.
	reset = function() ns.AdHocBars.Reset() end,

	panel = function(ui) ns.AdHocPanel.Build(ui) end,
})
