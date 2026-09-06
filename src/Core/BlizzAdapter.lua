local ADDON, ns = ...

local Adapter = {}
ns.BlizzAdapter = Adapter

--------------------------------------------------------------------------
-- The two ways this addon takes one of the client's windows off the screen
--
-- Eight parts drew the same file. Merchant and Sockets were a hundred and eight
-- identical lines out of a hundred and thirteen; Character and Spellbook were a
-- hundred and sixteen out of a hundred and fifty-six; Mail and Sockets were
-- eighty-four out of ninety-one. Nobody chose that. Each one was written by
-- copying the last one that worked, and what the copies drifted on was never the
-- mechanism, only the wording of a sentence and whether one branch was there.
-- Eight copies of a mechanism are eight places a fix has to land, and this addon
-- has already paid that twice: the SetShown hole Core/Attic.lua's header
-- describes had to be closed in every file that had a Show in it.
--
-- So the mechanism is here once and each part says what it is doing to which
-- frame. There are two shapes, they are not interchangeable, and picking the
-- wrong one is the failure mode this file exists to make hard.
--
-- **The park shape, for a frame that is a live session with the server.**
-- Mail, Merchant, Sockets. The client ends the session when the frame stops
-- being drawn: MailFrame_Hide, CloseMerchant and CloseSocketInfo all hang off
-- that, so both of the mechanisms the rest of the addon uses would close the
-- conversation a frame after opening it. ns.Strip begins by calling Hide, and
-- Core/Attic.lua re-parents into a hidden room, which takes visibility away by
-- the parent chain and fires the same handler. What is left is to move the
-- frame: off the right hand edge at no opacity, still shown and still parented
-- to UIParent, so every API on it goes on working and nothing of it is anywhere
-- a cursor can reach. The cost is honest and is why this is not the default: a
-- client that relays its panels puts the frame back, which is what the re-park
-- on the frame's own OnShow and the drift check on the pass are for.
--
-- **The cage shape, for a frame that is only a picture.** Character,
-- Spellbook, Talents, Quests, Map. Nothing about your gear, your spells, your
-- talents, your log or the map is a session: every call works with the frame
-- nowhere near the screen. So these take the stronger mechanism and go into
-- Core/Attic.lua, where a hidden parent beats every route the client has to put
-- a frame back, and the key that used to open the client's window is taken with
-- them, because a hidden window whose key still opens nothing is worse than
-- either window on its own.
--
-- **One field decides three things, and that is not a shortcut.** `pass` says
-- the part is registered on Core/BlizzHide.lua's once-a-second walk. A part on
-- the walk has to re-apply on every call, because a pass that remembers what it
-- did cannot see a frame the client built since; it has nothing a combat
-- lockdown can refuse, so it always answers true and there is nothing for the
-- PLAYER_REGEN_ENABLED retry to pick up; and it is the only place a drift
-- correction could run. A part off the walk is called when the switch moves and
-- answers whether it moved anything. Those are one decision written three ways,
-- and they were three fields in the copies.
--
-- **What the descriptor does not carry is a frame or a window.** It carries the
-- global's name and the ns key of the part that owns the replacement, both as
-- strings, resolved when something calls rather than when this file loads. That
-- is what keeps Core out of the features: scripts/trees.lua refuses a base tree
-- naming a feature back, and it is the right refusal, because a Core file that
-- named ns.CharWindow would put every part in the addon behind the character
-- sheet.
--
-- **Four parts stayed on their own, and the reason is that neither shape fits.**
--
--   Bags/Blizzard.lua replaces nine globals and cages nothing. The client's bags
--   are not a frame you take down, they are thirteen containers it only ever
--   builds through named calls, so taking the calls is cheaper than caging the
--   result and cannot leave one half-placed.
--
--   Buttons/Blizzard.lua hides secure action buttons one at a time with
--   statehidden and Hide, and its header says why nothing here may touch them:
--   the client's bar controller calls methods on those buttons from a stack that
--   goes on to perform protected actions, and this addon's function in that
--   stack is a taint.
--
--   Chat/Blizzard.lua cages a list it computes rather than one it declares, and
--   the cage is only a third of what it does. The other two thirds are the
--   AddMessage forward and the claim that stops the forward doubling every line.
--
--   CombatText/Blizzard.lua writes four CVars and touches no frame at all.
--
-- A forced fit is worse than the duplication, and those four are the boundary.
--------------------------------------------------------------------------

-- Far enough right that nothing of a four hundred pixel window shows, and
-- anchored to the screen's own edge rather than to a number, so it is off the
-- side of a 4K panel as well as a laptop. One number for all three parked
-- frames, because it is the same question about three frames of about the same
-- width.
local PARK = 400

--------------------------------------------------------------------------
-- The park shape
--------------------------------------------------------------------------

-- The descriptor:
--
--   frame    the global the client's window is named by
--   feature  the db key for this addon's own part being on
--   switch   the db key for the switch that hides the client's
--   window    the ns key of the part that draws the replacement, asked
--            whether it is open, because a parked frame with no window over
--            it is a session with nothing on the screen at all
--   pass     registered on the once-a-second walk, and re-parked on it
--   late     what Describe says before the client has ever built the frame,
--            for a window that arrives with a load-on-demand addon
--   loads    that addon's name, watched so the park lands the moment it does
function Adapter.Park(d)
	local Blizz = {}
	local parked, hooked = false, false
	local anchors = nil

	local function Frame()
		local frame = _G[d.frame]
		if type(frame) ~= "table" or type(frame.SetPoint) ~= "function" then
			return nil
		end
		return frame
	end

	-- Where the client had it, recorded once before it is ever moved. Restoring
	-- the points it actually had beats putting it back at a number this file
	-- guessed, and the client relays it on the next show anyway.
	local function Remember(frame)
		if anchors or type(frame.GetNumPoints) ~= "function" then
			return
		end
		anchors = {}
		for index = 1, frame:GetNumPoints() do
			local point, relative, relativePoint, x, y = frame:GetPoint(index)
			anchors[index] = { point, relative, relativePoint, x, y }
		end
	end

	local function Move(frame)
		frame:ClearAllPoints()
		frame:SetPoint("TOPLEFT", UIParent, "TOPRIGHT", PARK, 0)
		frame:SetAlpha(0)
	end

	local function Park()
		local frame = Frame()
		if not frame then
			return false
		end
		Remember(frame)
		-- A clamped frame snaps back onto the screen, which would undo the move
		-- and leave a window at no opacity swallowing clicks in the middle of
		-- the game.
		if type(frame.SetClampedToScreen) == "function" then
			frame:SetClampedToScreen(false)
		end
		Move(frame)

		-- The frame is a UIPanel and the client lays the panels out again
		-- whenever one opens or closes, which puts it back in the middle of the
		-- screen. HookScript rather than SetScript, because the handler already
		-- there is the client's and taking it off would be taking the session
		-- with it.
		if not hooked and type(frame.HookScript) == "function" then
			hooked = pcall(frame.HookScript, frame, "OnShow", function(this)
				if parked then
					Move(this)
				end
			end)
		end
		return true
	end

	local function Unpark()
		local frame = Frame()
		if not frame then
			return false
		end
		frame:SetAlpha(1)
		if anchors then
			frame:ClearAllPoints()
			for index = 1, #anchors do
				local held = anchors[index]
				frame:SetPoint(held[1], held[2], held[3], held[4], held[5])
			end
		end
		return true
	end

	-- Whether the client has put it back on the screen since the last pass.
	--
	-- Read rather than written, which is what lets the re-park sit on a once-a-
	-- second walk without being a write per second forever. The frame is parked
	-- off the right hand edge, so anything whose left edge is inside the screen
	-- has been moved back by somebody, and a client that will not answer either
	-- question is one this cannot make a claim about and leaves alone.
	local function Drifted(frame)
		local left, edge = frame:GetLeft(), UIParent:GetRight()
		if not left or not edge then
			return false
		end
		return left < edge or (frame:GetAlpha() or 0) > 0
	end

	local function Repark()
		local frame = Frame()
		if not frame or not Drifted(frame) then
			return false
		end
		Move(frame)
		return true
	end

	-- Three things have to hold, and the third is what keeps this safe: this
	-- addon's own window has to be open, or there would be no window of either
	-- kind on the screen.
	function Blizz.Wanted()
		return (ns.db[d.feature] and ns.db[d.switch]
			and ns[d.window].Shown()) and true or false
	end

	-- On the walk this is every call and the answer is always true, because
	-- moving an unprotected frame and setting its alpha are both allowed in a
	-- fight and there is nothing here a combat retry could put right. Off the
	-- walk it is the switch moving, and the answer is whether it moved.
	function Blizz.Apply()
		local wanted = Blizz.Wanted()
		if wanted ~= parked then
			parked = wanted
			local moved
			if wanted then
				moved = Park()
			else
				moved = Unpark()
			end
			if d.pass then
				return true
			end
			return moved
		end
		if not d.pass then
			return false
		end
		if wanted then
			Repark()
		end
		return true
	end

	function Blizz.Parked()
		return parked
	end

	function Blizz.Describe()
		if not ns.db[d.switch] then
			return "on screen"
		end
		if d.late and not Frame() then
			return d.late
		end
		if not parked then
			return "on screen while this window is closed"
		end
		if not hooked then
			return "moved aside, and this client would not let the addon keep it there"
		end
		return "moved aside"
	end

	-- The frame arriving after login, parked the moment it does. The client
	-- loads these inside its own handler for the event that opens a session, so
	-- this runs before the window this addon draws has been asked for anything.
	if d.loads then
		local watcher = CreateFrame("Frame")
		watcher:RegisterEvent("ADDON_LOADED")
		watcher:SetScript("OnEvent", function(_, _, name)
			if name == d.loads and ns.db then
				Blizz.Apply()
			end
		end)
	end

	if d.pass then
		ns.BlizzHide.Also(Blizz.Apply)
	end

	return Blizz
end

--------------------------------------------------------------------------
-- The cage shape
--------------------------------------------------------------------------

-- The descriptor:
--
--   frames    every global the client's window is made of, probed one at a
--             time, because these differ between the two clients this addon
--             ships for and a name that is missing has to cost that frame
--             rather than the feature
--   feature   the db key for this addon's own part being on
--   switch    the db key for the switch that hides the client's
--   global    the client's own toggle, taken so the key opens ours
--   Toggle    what to put on it, a named function at file scope in the part's
--             own file rather than a closure made here, because the swap runs
--             on a pass that goes once a second forever and a fresh closure a
--             second is garbage the collector walks. It is also what makes
--             "are we already holding it" a comparison
--   bindings  the names the client files that key under, where the part wants
--             to say which key in a sentence. Two names is the usual case:
--             the numbered one is what a modern Bindings.xml carries and the
--             bare one is the fallback
--   fallback  the letter the client ships with, for a client that answers none
--   bind      also take an override binding onto the part's own key button,
--             for a window with a secure button on it
--   window    the ns key of the part that draws the replacement, asked for
--             that button. Only the two that bind need it
--   pass      registered on the once-a-second walk, and re-applied on it
--   held      Caged answers off the attic and the global rather than off a
--             flag, for a part whose frame may not have been built yet
--   place     what Describe calls where the frame went
--   off       what Describe says when this addon's own part is switched off.
--             Absent means the part says "on screen" instead, which is the
--             honest answer where the cage follows nothing but the switch
--   offKey    the key named while the switch is off, where the part spells it
--             out rather than asking the client
--   onKey     the same with the switch on
--   loads     a load-on-demand addon of Blizzard's own, watched so a frame
--             that arrives after login is caged the moment it does
function Adapter.Cage(d)
	local Blizz = {}
	local BINDINGS = d.bindings or {}
	local original, bound = nil, nil
	local caged = false

	-- True at login and whenever the client says the bindings moved, false once
	-- they have been taken. A flag rather than a comparison, and that is not
	-- tidiness: the pass that calls this runs once a second forever, and asking
	-- the client for its keys and joining them into a string on every one of
	-- those passes is a string a second for the collector to walk. The harness's
	-- allocation gate caught exactly that.
	local dirty = true

	local function Frame(name)
		local frame = _G[name]
		if type(frame) ~= "table" or type(frame.GetParent) ~= "function" then
			return nil
		end
		return frame
	end

	-- Whoever is holding the global now, remembered once. Called before the swap
	-- and never after, so a second addon that wrapped the same global after us
	-- is not swallowed by a later re-apply.
	local function Remember()
		if original == nil and type(_G[d.global]) == "function" then
			original = _G[d.global]
		end
		return original ~= nil
	end

	-- Every key the client has on its own page, in the order it answers them.
	-- Called when the bindings have moved and never on the idle pass.
	local function Keys()
		local keys = {}
		if type(_G.GetBindingKey) ~= "function" then
			return keys
		end
		for index = 1, #BINDINGS do
			local first, second = GetBindingKey(BINDINGS[index])
			if first then
				keys[#keys + 1] = first
			end
			if second then
				keys[#keys + 1] = second
			end
		end
		return keys
	end

	-- The key on the secure button as well as on the global.
	--
	-- The global is what every other caller reaches and it is ordinary Lua, so
	-- it cannot show a window with a secure button on it in a fight. The press
	-- itself has to arrive somewhere else, and an override binding onto a secure
	-- button is that somewhere: the client sends the press to the button, the
	-- button's snippet shows the window, and a snippet is allowed to in combat
	-- because a snippet is secure code.
	--
	-- An override binding rather than SetBinding, because this is a key the
	-- addon is borrowing rather than a key the player set: it is not written to
	-- their bindings, and clearing it hands the key straight back to whatever
	-- they had. Refused in lockdown, like every binding call, and the pass that
	-- runs once a second and again when combat drops puts it right.
	local function Bind()
		if not d.bind or not dirty then
			return true
		end
		if type(_G.SetOverrideBindingClick) ~= "function" then
			return false
		end
		local button = ns[d.window].Key()
		if not button or InCombatLockdown() then
			return false
		end
		ClearOverrideBindings(button)
		local keys = Keys()
		for index = 1, #keys do
			SetOverrideBindingClick(button, true, keys[index],
				ns[d.window].KeyName(), "LeftButton")
		end
		dirty, bound = false, keys[1]
		return bound ~= nil
	end

	local function Unbind()
		if not bound then
			return false
		end
		local button = ns[d.window].Key()
		if not button or InCombatLockdown() then
			return false
		end
		ClearOverrideBindings(button)
		dirty, bound = true, nil
		return true
	end

	local function TakeKey()
		if _G[d.global] == d.Toggle then
			return Bind()
		end
		if not Remember() then
			return false
		end
		_G[d.global] = d.Toggle
		return Bind()
	end

	-- Only ever hands back what this part took. A client where somebody else is
	-- holding the global is a client this leaves alone, which is the same rule
	-- Remember keeps at the other end.
	local function GiveKey()
		Unbind()
		if type(original) ~= "function" or _G[d.global] ~= d.Toggle then
			return false
		end
		_G[d.global] = original
		return true
	end

	-- What to call the key in a sentence. The one this part is holding, then the
	-- first the client answers, then the letter it ships with, because a line
	-- telling somebody to press nothing is worse than a line naming the wrong
	-- key. Only offered where the part asked for bindings; the rest spell their
	-- letter out in the descriptor.
	if d.bindings then
		function Blizz.KeyText()
			if bound then
				return bound
			end
			local keys = Keys()
			return keys[1] or d.fallback
		end
	end

	-- Two things, and usually no third. The park shape adds "and ours is open"
	-- because a parked session needs a window over it; this one does not, because
	-- the key opens ours, so there is never a moment where the window is
	-- unreachable, and a frame caged only while ours happened to be up would
	-- flicker the client's onto the screen every time ours closed.
	function Blizz.Wanted()
		return (ns.db[d.feature] and ns.db[d.switch]) and true or false
	end

	-- On the walk this runs on every call rather than only where the answer
	-- changed, which is the rule Core/BlizzHide.lua's header argues for at
	-- length: a pass that remembers what it did cannot see a frame the client
	-- built since, and cannot see one the client put back by a route the hide
	-- did not cover. Off the walk it is the switch moving and nothing else.
	function Blizz.Apply()
		local wanted = Blizz.Wanted()
		if not d.pass and wanted == caged then
			return false
		end
		caged = wanted
		if wanted then
			TakeKey()
		else
			GiveKey()
		end

		local complete = true
		local act = wanted and ns.Attic.Vanish or ns.Attic.Return
		for index = 1, #d.frames do
			local frame = Frame(d.frames[index])
			if frame and not act(frame) then
				complete = false
			end
		end
		return complete
	end

	-- Whether the client's frame is in the attic right now, or would be the
	-- moment it existed. The second half is what `held` is for: a window behind
	-- a load-on-demand addon has no frame to ask, and the global standing in for
	-- it is the next best fact there is.
	function Blizz.Caged()
		if not d.held then
			return caged
		end
		for index = 1, #d.frames do
			local frame = Frame(d.frames[index])
			if frame then
				return ns.Attic.Held(frame)
			end
		end
		return Blizz.Wanted() and _G[d.global] == d.Toggle
	end

	function Blizz.Describe()
		if not ns.db[d.switch] then
			return ("on screen, and %s opens it")
				:format(d.offKey or Blizz.KeyText())
		end
		if d.off then
			if not ns.db[d.feature] then
				return d.off
			end
		elseif not caged then
			return "on screen"
		end
		if type(original) ~= "function" then
			return ("%s, and this client has no %s to redirect")
				:format(d.place, d.global)
		end
		return ("%s, and %s opens this one")
			:format(d.place, d.onKey or Blizz.KeyText())
	end

	-- The client's own binding set moved, so whatever this took has to be taken
	-- again off the new one. The pass does the work; this only says that there
	-- is work.
	if d.bind then
		local keys = CreateFrame("Frame")
		keys:RegisterEvent("UPDATE_BINDINGS")
		keys:SetScript("OnEvent", function()
			dirty = true
		end)
	end

	-- The frame arriving after login, caged the moment it does.
	if d.loads then
		local watcher = CreateFrame("Frame")
		watcher:RegisterEvent("ADDON_LOADED")
		watcher:SetScript("OnEvent", function(_, _, name)
			if name == d.loads and ns.db then
				Blizz.Apply()
			end
		end)
	end

	-- Registered with the switch it belongs to, so `/wk hide <part>`, the
	-- panel's own line and `/wk reset` all reach the part without any of them
	-- naming it.
	if d.pass then
		ns.BlizzHide.Also(Blizz.Apply)
	end

	return Blizz
end
