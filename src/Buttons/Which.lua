local ADDON, ns = ...

local Which = {}
ns.WhichBars = Which

--------------------------------------------------------------------------
-- Which bars there are, and which of them you want
--
-- The plan and the question. Buttons/Bars.lua is what a bar is made of and
-- Buttons/Placing.lua is where it goes; this is which bars exist at all.
--
-- Split out because the answer stopped being a reading of the client. It used
-- to be one line inside Discover: clone a bar if Blizzard's frame for it is up.
-- That is the right default and the wrong rule, because it left the player no
-- way to say "clone the bottom left bar and leave the right one to Blizzard",
-- and no way at all to clone a bar whose Blizzard frame is switched off even
-- though its twelve slots are still there and your keys still point at them.
--
-- So there are two answers per bar and the saved one wins:
--
--   nothing saved, which is the shipping state, means follow the client. A bar
--   you have on is a bar we clone. That is "clone from your current bars" with
--   no setting to find and nothing to press, and it is why turning the feature
--   on gives you back what you already had.
--
--   a saved true or false is a decision, and from then on the client's own
--   switch is not consulted for that bar. Unticking every box puts the whole
--   thing back to following the client.
--
-- Nothing here draws, hides or binds anything. It answers a question about a
-- bar and hands the answer to Bars.lua, which owns every frame.
--------------------------------------------------------------------------

-- Every bar this client can have, in draw order.
--
--   buttons   the Blizzard button name the slot is read off and which then gets
--             hidden. Hiding the twelve buttons rather than the frame holding
--             them is deliberate: bar 1's buttons live on MainMenuBarArtFrame
--             along with the micro menu and the bag bar, and Artwork.lua
--             already carries the note about what hiding that frame costs.
--   command   the binding command its keys are saved under
--   frame     the Blizzard frame whose IsShown is the default answer to whether
--             you want this bar. nil for bar 1, which is always wanted
--   pages     bar 1 alone, which the client re-points at a different twelve
--             slots in each stance
--
-- The rest is geometry: how many columns the twelve break into, and where the
-- bar's corner lands on UIParent. Those offsets are in the bar's own units, and
-- every bar goes on the pixel grid, so they are whole screen pixels and mean
-- the same thing on a 1080p panel as on a 4K one.
Which.PLAN = {
	{ key = "bar1", label = "bar 1", pages = true,
		buttons = "ActionButton%d", command = "ACTIONBUTTON%d",
		columns = 12, point = "BOTTOM", to = "BOTTOM", x = 0, y = 8 },

	{ key = "bottomleft", label = "bottom left bar",
		buttons = "MultiBarBottomLeftButton%d", command = "MULTIACTIONBAR1BUTTON%d",
		frame = "MultiBarBottomLeft",
		columns = 12, point = "BOTTOM", to = "BOTTOM", x = 0, y = 44 },

	{ key = "bottomright", label = "bottom right bar",
		buttons = "MultiBarBottomRightButton%d", command = "MULTIACTIONBAR2BUTTON%d",
		frame = "MultiBarBottomRight",
		columns = 12, point = "BOTTOM", to = "BOTTOM", x = 0, y = 80 },

	-- MultiBarRight is the client's "right bar" and MultiBarLeft is "right bar
	-- 2", which sits to its left. The names are the wrong way round and have
	-- been since 2005; the command numbers are what the binding set actually
	-- carries and those are right.
	{ key = "right", label = "right bar",
		buttons = "MultiBarRightButton%d", command = "MULTIACTIONBAR3BUTTON%d",
		frame = "MultiBarRight",
		columns = 2, point = "RIGHT", to = "RIGHT", x = -8, y = 0 },

	{ key = "right2", label = "right bar 2",
		buttons = "MultiBarLeftButton%d", command = "MULTIACTIONBAR4BUTTON%d",
		frame = "MultiBarLeft",
		columns = 2, point = "RIGHT", to = "RIGHT", x = -73, y = 0 },
}

--------------------------------------------------------------------------
-- The question
--------------------------------------------------------------------------

-- What the client says about a bar right now.
--
-- Read off the bar frame rather than off its buttons. Once the clone is up this
-- addon has hidden every one of those buttons, so their own IsShown is our own
-- answer coming back; the frame holding them is what MultiActionBar_Update
-- actually toggles and is the only honest source left.
function Which.Theirs(def)
	if def.frame == nil then
		return true
	end
	local holder = _G[def.frame]
	return (holder and holder:IsShown()) or false
end

-- Whether this bar is one we clone. The saved answer if there is one, and what
-- the client says if there is not.
function Which.Wanted(def)
	local saved = ns.db and ns.db.barsShown and ns.db.barsShown[def.key]
	if saved ~= nil then
		return saved and true or false
	end
	return Which.Theirs(def)
end

-- Say so, or stop saying so. `nil` drops the decision and goes back to
-- following the client, which is what the panel's reset row does.
function Which.Want(key, value)
	if not (ns.db and ns.db.barsShown) then
		return
	end
	ns.db.barsShown[key] = value == nil and nil or (value and true or false)
end

-- Drop every decision, so all five bars follow the client again. This is the
-- "clone what I have right now" button, and it is a deletion rather than a
-- write for the reason the whole file is arranged this way: the shipping state
-- has no entries in it, so matching your current bars is going back to it.
function Which.Follow()
	if not (ns.db and ns.db.barsShown) then
		return 0
	end
	local dropped = 0
	for key in pairs(ns.db.barsShown) do
		ns.db.barsShown[key] = nil
		dropped = dropped + 1
	end
	return dropped
end

-- How many bars carry a decision rather than following the client.
function Which.Decided()
	local count = 0
	if ns.db and ns.db.barsShown then
		for _ in pairs(ns.db.barsShown) do
			count = count + 1
		end
	end
	return count
end

--------------------------------------------------------------------------
-- What is out there
--------------------------------------------------------------------------

-- One entry per bar this client can answer for, wanted or not. Bars.lua builds
-- the wanted ones and needs the rest to know what to hand back.
--
-- Asked again on every apply, so a bar that was not up yet when this file first
-- looked is still cloned. Build in Bars.lua leaves a bar already built exactly
-- as it is, which is what makes asking twice safe.
function Which.Discover()
	local found = {}
	for index = 1, #Which.PLAN do
		local def = Which.PLAN[index]
		local base = ns.Layout.SlotOf(def.buttons:format(1))
		if base then
			local entry = { def = def, base = base, wanted = Which.Wanted(def) }
			if def.pages then
				-- nil where this client does not page bar 1 by stance, which is
				-- every non-warrior and is a state Layout already reports.
				entry.pages = ns.Layout.Bar1Bases()
			end
			found[#found + 1] = entry
		end
	end
	return found
end
