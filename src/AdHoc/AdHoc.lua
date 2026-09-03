local ADDON, ns = ...

local AdHoc = {}
ns.AdHoc = AdHoc

--------------------------------------------------------------------------
-- Bars you made yourself
--
-- A bar is a name, a key, a place on the screen and a list of what you dragged
-- onto it. It is hidden until the key is pressed and hidden again after a press
-- on one of its squares, so a bar of your trade skills lives under T and a bar
-- of totems under Shift-T, and neither is on the screen while you fight.
--
-- This file is the list and nothing else. It knows what a bar holds and what
-- the cursor is carrying; it does not know what a frame is. Bars.lua builds the
-- frames, the squares and the keys off this list, and Panel.lua draws the page
-- you design a bar on. That is the split Loadouts/Loadouts.lua and
-- Loadouts/Page.lua already have, and for the same reason: a list you can read
-- in a harness without a screen is a list whose rules can be asserted.
--
-- Everything is per character. A trade skill is the character's, a totem is the
-- class's, and a bar of either written into the account would be a bar of
-- spells another character does not know. Loadouts made the same call.
--
-- A square holds a spell by name and never by id. `/cast Frost Shock` with no
-- rank named casts the best rank you know, so a bar never goes stale after a
-- trainer visit; Buttons/Ranks.lua exists to give the action bars that same
-- property and a bar built here gets it for free. Hover/Hover.lua makes the
-- argument at length. An item is held by name for the same reason, with its id
-- beside it because the cooldown call wants a number. A macro is held by name
-- because a macro index moves every time you make or delete one.
--------------------------------------------------------------------------

-- Six bars is the cap and sixteen squares is the width of one. Both are caps
-- rather than sizes: a bar carries only what you put on it, and a cap that is
-- reached says so rather than dropping the seventh bar or the seventeenth
-- square on the floor. Six because the keys a bar wants are the letters left
-- over after the client's own, and sixteen because a shaman owns more totems
-- than a bar of twelve would hold.
AdHoc.MAX = 6
AdHoc.PER_BAR = 16

-- How many squares sit on one row before the next starts. Eight is half of
-- the width, so a full bar is two even rows, and a bar of six is one.
AdHoc.COLUMNS = 8

-- The two the binding system must never lose, refused here for the reason
-- Marking/Keys.lua and Loadouts/Loadouts.lua refuse them: a bare mouse button
-- binding eats plain targeting and the camera drag.
local BARE = { BUTTON1 = true, BUTTON2 = true }
AdHoc.BARE = BARE

--------------------------------------------------------------------------
-- The list
--------------------------------------------------------------------------

function AdHoc.All()
	return ns.dbc.adhocBars
end

function AdHoc.Get(index)
	return ns.dbc.adhocBars[index]
end

function AdHoc.Count()
	return #ns.dbc.adhocBars
end

-- Which one the panel is showing. Clamped on read rather than on delete, the
-- way Loadouts.Shown is, so a saved index from a longer list lands somewhere
-- real and nothing has to remember to fix it.
function AdHoc.Shown()
	local count = AdHoc.Count()
	if count == 0 then
		return 0
	end
	local index = ns.dbc.adhocShown or 1
	if index < 1 or index > count then
		index = 1
	end
	return index
end

function AdHoc.Show(index)
	ns.dbc.adhocShown = index
end

local function Apply()
	if ns.AdHocBars then
		ns.AdHocBars.Apply()
	end
end

function AdHoc.Add(name)
	local list = AdHoc.All()
	if #list >= AdHoc.MAX then
		return nil, ("%d bars is the cap."):format(AdHoc.MAX)
	end
	list[#list + 1] = {
		name = name and name ~= "" and name or ("Bar %d"):format(#list + 1),
		key = "", displaced = "",
		buttons = {},
	}
	AdHoc.Show(#list)
	Apply()
	return #list
end

-- The key goes with the row. Bars.Apply rebuilds every binding from the list
-- afterwards, so the bars under the one removed move up onto different frames
-- and their keys move with them; nothing else needs saying here.
function AdHoc.Remove(index)
	local list = AdHoc.All()
	if not list[index] then
		return false
	end
	table.remove(list, index)
	Apply()
	return true
end

function AdHoc.Rename(index, name)
	local bar = AdHoc.Get(index)
	if not bar then
		return false
	end
	bar.name = (name and name ~= "") and name or bar.name
	return true
end

-- The shape and the closing rule, each with a default that is not a setting.
-- A bar nobody has reshaped carries no columns field and a bar nobody has told
-- to stay up carries no close field, so a record restates nothing the code
-- already says. Buttons/Look.lua argues this at length.
function AdHoc.Columns(index)
	local bar = AdHoc.Get(index)
	return bar and bar.columns or AdHoc.COLUMNS
end

function AdHoc.SetColumns(index, columns)
	local bar = AdHoc.Get(index)
	if not bar then
		return false
	end
	columns = math.floor(tonumber(columns) or AdHoc.COLUMNS)
	if columns < 1 then
		columns = 1
	elseif columns > AdHoc.PER_BAR then
		columns = AdHoc.PER_BAR
	end
	bar.columns = columns ~= AdHoc.COLUMNS and columns or nil
	Apply()
	return true
end

function AdHoc.Closes(index)
	local bar = AdHoc.Get(index)
	return bar ~= nil and bar.close ~= false
end

function AdHoc.SetCloses(index, closes)
	local bar = AdHoc.Get(index)
	if not bar then
		return false
	end
	if closes then
		bar.close = nil
	else
		bar.close = false
	end
	Apply()
	return true
end

--------------------------------------------------------------------------
-- What the cursor is carrying
--
-- A record is what a square holds and what Bars.lua arms a button with: the
-- kind, the name a press goes by, and the picture. A spell and an item go
-- through Hover/Hover.lua's reading, which is the one in the addon proven
-- against this client's three-value GetCursorInfo. A macro is this file's
-- own, because a macro cannot be cast on whatever the mouse is over and
-- Hover refuses one for that reason; here it is simply a button.
--------------------------------------------------------------------------

function AdHoc.Carry(kind, a, b, c)
	if kind == "macro" then
		if type(GetMacroInfo) ~= "function" then
			return nil, "this client would not say which macro that was."
		end
		local name, icon = GetMacroInfo(a)
		if type(name) ~= "string" or name == "" then
			return nil, "this client would not say which macro that was."
		end
		return { kind = "macro", name = name, icon = icon }
	end

	local pick, why = ns.Hover.Carry(kind, a, b, c)
	if not pick then
		if kind then
			return nil, ("a %s is not something a bar holds. Drop a spell, an item or a macro."):format(kind)
		end
		return nil, why
	end
	local record = { kind = pick.kind, name = pick.name, icon = pick.icon }
	if pick.kind == "item" and type(a) == "number" then
		record.id = a
	end
	return record
end

--------------------------------------------------------------------------
-- The squares
--------------------------------------------------------------------------

-- Put a record at a place on the bar. At a place past the end it is added;
-- at a place that is taken it replaces what was there, which is what a drop
-- on a full square means on every bar the client has ever drawn.
function AdHoc.Put(index, at, record)
	local bar = AdHoc.Get(index)
	if not bar then
		return false, "no such bar."
	end
	if type(record) ~= "table" or type(record.name) ~= "string" then
		return false, "nothing to put there."
	end
	local buttons = bar.buttons
	at = math.floor(tonumber(at) or (#buttons + 1))
	if at < 1 then
		at = 1
	end
	if at > #buttons then
		if #buttons >= AdHoc.PER_BAR then
			return false, ("%d squares is the width of a bar."):format(AdHoc.PER_BAR)
		end
		at = #buttons + 1
	end
	buttons[at] = record
	Apply()
	return true
end

-- Take a record off the bar. The squares after it close the gap, because a
-- bar with a hole in it is a bar and a stump.
function AdHoc.Take(index, at)
	local bar = AdHoc.Get(index)
	if not bar or not bar.buttons[at] then
		return nil
	end
	local record = table.remove(bar.buttons, at)
	Apply()
	return record
end

-- Move a record from one square to another on the same bar, which is what a
-- drag between two squares on the page means.
function AdHoc.Move(index, from, to)
	local bar = AdHoc.Get(index)
	if not bar or not bar.buttons[from] or from == to then
		return false
	end
	local record = table.remove(bar.buttons, from)
	if to > #bar.buttons + 1 then
		to = #bar.buttons + 1
	end
	table.insert(bar.buttons, to, record)
	Apply()
	return true
end

function AdHoc.Squares(index)
	local bar = AdHoc.Get(index)
	return bar and bar.buttons or nil
end

--------------------------------------------------------------------------
-- Words
--------------------------------------------------------------------------

-- Which bar a typed word means: a number, or a name matched whole and without
-- regard to case.
function AdHoc.Find(word)
	local index = tonumber(word)
	if index and AdHoc.Get(index) then
		return index
	end
	local wanted = tostring(word or ""):lower()
	for at, bar in ipairs(AdHoc.All()) do
		if bar.name:lower() == wanted then
			return at
		end
	end
	return nil
end
