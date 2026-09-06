-- The cloned action bars
--
-- The proof the whole part is for: can every bar the player already has, with
-- every key they already have on it, be replaced by squares this addon draws.
-- Four things below cannot be settled by reading Buttons/Bars.lua.
--
--   That discovery reads the client rather than a number somebody typed. The
--   stub has three multi-bars on and one off, so a clone that assumed two bars
--   and one that cloned every name it knows both fail here.
--
--   That the geometry lands on whole pixels. Every square is 27 across because
--   27 is one of the two sizes where a stored icon texel lands on one screen
--   pixel, and the bar around it is that arithmetic and nothing else.
--
--   That each square presses the slot it should in each stance. Bar 1 pages,
--   and the paging happens inside a secure snippet, so the snippet is run.
--
--   That the keys arrive and that the off switch gives everything back. An
--   override that was set and never read back is a key that silently does
--   nothing, and a hidden Blizzard button with no way back is worse than no
--   feature at all.

local H = ...
local state = H.state
local CHURN, chat, region = H.CHURN, H.chat, H.region
local child, plates, plateSize = H.child, H.plates, H.plateSize
local PLATE_W, PLATE_H, guids = H.PLATE_W, H.PLATE_H, H.guids
local slots, ns, fire = H.slots, H.ns, H.fire
local check = H.check

do
	local barsChurn = 0
	local Bars = ns.Bars
	local slots = _G.WarriorKitSlots
	local ART = "Interface\\Icons\\Ability_Warrior_Charge"

	-- 27 is not a taste decision and the plan is not allowed to drift off it.
	local sharp = false
	for _, size in ipairs(ns.UI.IconSizes()) do
		if size == 27 then
			sharp = true
		end
	end
	check(sharp, "the shipped square size is not one the client can draw sharp")

	-- Bar 1's twelve slots carry art so the tick has something real to draw;
	-- the rest stay empty, which is the mixed scene a fresh character has.
	for index = 0, 11 do
		slots[73 + index] = { texture = ART }
	end

	ns.db.actionBars = true
	check(Bars.Apply(), "the clone reported combat deferring it with no combat running")

	local bars = Bars.All()
	check(#bars == 4, ("the stub has four action bars on and %d were cloned"):format(#bars))

	local found = {}
	for index = 1, #bars do
		found[bars[index].def.key] = bars[index]
	end
	check(found.bar1 and found.bottomleft and found.bottomright and found.right,
		"a bar the client has switched on was not cloned")
	check(found.right2 == nil,
		"a bar the client has switched off was cloned, so the off switch would show it")

	--------------------------------------------------------------------------
	-- Geometry
	--------------------------------------------------------------------------

	local squares = 0
	for index = 1, #bars do
		local entry = bars[index]
		local px = ns.UI.Pixel(entry.frame)
		check(px == 1, ("%s is not on the pixel grid, one unit is %.3f pixels")
			:format(entry.def.key, px))

		local columns = entry.def.columns
		local rows = 12 / columns
		local width = 3 * 2 + columns * 27 + (columns - 1) * 2
		local height = 3 * 2 + rows * 27 + (rows - 1) * 2
		check(entry.frame:GetWidth() == width,
			("%s came out %s wide, the plan says %d"):format(entry.def.key,
				tostring(entry.frame:GetWidth()), width))
		check(entry.frame:GetHeight() == height,
			("%s came out %s tall, the plan says %d"):format(entry.def.key,
				tostring(entry.frame:GetHeight()), height))

		for slot = 1, 12 do
			local w = entry.buttons[slot]
			squares = squares + 1
			check(w:GetWidth() == 27 and w:GetHeight() == 27,
				("%s square %d is %s by %s, not 27 square"):format(entry.def.key, slot,
					tostring(w:GetWidth()), tostring(w:GetHeight())))
		end
	end
	check(squares == 48, ("four bars of twelve is 48 squares and %d were made"):format(squares))

	--------------------------------------------------------------------------
	-- Which slot each square presses
	--------------------------------------------------------------------------

	local function pressing(entry, index)
		return entry.buttons[index]:GetAttribute("action")
	end

	-- The bars that do not page each keep the twelve the button they replaced
	-- was reading, which is the whole of "do not invent a slot space".
	check(pressing(found.bottomleft, 1) == 61 and pressing(found.bottomleft, 12) == 72,
		"the bottom left clone is not on the slots its Blizzard bar was on")
	check(pressing(found.bottomright, 1) == 49 and pressing(found.right, 12) == 48,
		"a clone is not on the slots its Blizzard bar was on")

	-- Bar 1 pages. Battle is 73, and the other two stances are the twelve slot
	-- stride away, which is what the live client answered on Tusksfirst.
	check(Bars.CanPage(), "the state driver did not come up, so bar 1 cannot page in combat")
	check(pressing(found.bar1, 1) == 73 and pressing(found.bar1, 12) == 84,
		"bar 1 did not start on the stance it is standing in")

	local macro = _G.WarriorKitDriver(found.bar1.header, "page")
	check(type(macro) == "string" and macro:match("stance:1") and macro:match("stance:2")
		and macro:match("stance:3") and macro:match("nostance"),
		"the page driver does not cover all three stances and no stance")

	-- Driven the way the client drives it, through the snippet, because in
	-- combat the snippet is the only thing that can do this at all.
	local PAGES = { ["1"] = 73, ["2"] = 85, ["3"] = 97 }
	for state, base in pairs(PAGES) do
		check(_G.WarriorKitDriveState(found.bar1.header, "page", state),
			"the header carries no page handler for the state driver to run")
		local wrong = 0
		for index = 1, 12 do
			if pressing(found.bar1, index) ~= base + index - 1 then
				wrong = wrong + 1
			end
		end
		check(wrong == 0,
			("stance page %s left %d of 12 squares on the wrong slot"):format(state, wrong))
	end

	-- A stance the macro maps to nothing falls to page one rather than to a bar
	-- of twelve empty squares.
	_G.WarriorKitDriveState(found.bar1.header, "page", "9")
	check(pressing(found.bar1, 1) == 73, "an unknown page left bar 1 pointing at nothing")
	_G.WarriorKitDriveState(found.bar1.header, "page", "1")

	--------------------------------------------------------------------------
	-- The keys
	--------------------------------------------------------------------------

	local claimed, missed = 0, {}
	for index = 1, #bars do
		local entry = bars[index]
		for slot = 1, 12 do
			local name = entry.buttons[slot]:GetName()
			-- The stub's set: an overridden key stops answering to its command.
			for _, key in ipairs(_G.WarriorKitBindings[entry.def.command:format(slot)] or {}) do
				claimed = claimed + 1
				if _G.GetBindingAction(key, true) ~= ("CLICK %s:LeftButton"):format(name) then
					missed[#missed + 1] = key
				end
			end
		end
	end
	check(claimed == 37,
		("the stub binds 37 keys across the bars it has on and %d were read"):format(claimed))

	-- One key of the 37 does not reach a square on a warrior: the charge button
	-- ships holding it, and Buttons/Bars.lua reads the binding layer back before
	-- claiming a key, so the square gives it up. Nothing saw that until the
	-- binder's snippet ran, and no other class has a charge button.
	local lent = _G.WarriorKitChargeButton and ns.db.chargeKey or nil
	local away = lent and 1 or 0
	check(#missed == away and (not lent or (missed[1] == lent
			and _G.GetBindingAction(lent, true) == "CLICK WarriorKitChargeButton:LeftButton")),
		("%d of %d keys did not reach the square they were put on: %s")
			:format(#missed, claimed, table.concat(missed, ", ")))
	check(Bars.Keys() == claimed - away,
		("the clone holds %d keys of the %d the override layer carries")
			:format(Bars.Keys(), claimed - away))

	-- The secondary key is a key the player set on purpose and is the one a
	-- clone drops silently.
	check(_G.GetBindingAction("SHIFT-BUTTON3", true)
		== ("CLICK %s:LeftButton"):format(found.bar1.buttons[1]:GetName()),
		"the second key on a button was read and not bound")

	-- And what gets drawn in the corner, which is a different question from
	-- what gets bound. "SHIFT-BUTTON3" at seven pixels is a smear.
	check(Bars.Short("SHIFT-BUTTON3") == "sM3", "a modified mouse button does not shorten")
	check(Bars.Short("CTRL-SHIFT-NUMPAD7") == "csn7", "a stacked modifier does not shorten")
	check(Bars.Short("E") == "E", "a plain key was rewritten")
	check(found.bottomleft.buttons[1].key:GetText() == "sE",
		"the square is not showing the key that presses it")

	--------------------------------------------------------------------------
	-- Blizzard's own buttons
	--------------------------------------------------------------------------

	check(not _G.ActionButton1:IsShown(), "Blizzard's bar 1 button is still on screen")
	check(not _G.MultiBarRightButton12:IsShown(), "a cloned bar's Blizzard button is still up")
	check(_G.MultiBarLeftButton1:IsShown(),
		"a button on a bar nobody cloned was hidden, so the off switch would show it")
	check(Bars.Hidden() == 48, ("48 buttons were cloned over and %d were hidden")
		:format(Bars.Hidden()))

	-- A square you cannot click.
	--
	-- Every one of these registered AnyDown, copied off the charge button,
	-- which registers AnyDown and then calls EnableMouse(false) on itself
	-- because the only ways to press it are a key and /click. On 2.5.6 the
	-- client's own ActionButton_OnLoad registers AnyUp; casting on the down
	-- edge came with a later expansion and its CVar. So the bars drew
	-- correctly, lit correctly, counted down correctly, and did nothing at all
	-- when clicked, and nothing in this file could see it because
	-- RegisterForClicks was a no-op.
	local mute, blind, deaf, seen = 0, 0, 0, 0
	for index = 1, #bars do
		for slot = 1, 12 do
			local w = bars[index].buttons[slot]
			seen = seen + 1
			local clicks = w:GetRegisteredClicks()
			if not clicks or not (clicks.AnyUp or clicks.LeftButtonUp) then
				mute = mute + 1
			end
			-- And the key edge, which is a second switch and was the second
			-- half of the same bug. The registration above is what the mouse
			-- obeys; a key bound with SetOverrideBindingClick fires on
			-- whichever edge useOnKeyDown names, and with the attribute unset
			-- that is the down edge. A square registered AnyUp and left unset
			-- therefore answered the mouse, went dark under the key because
			-- the client pushes a button on the down edge either way, and cast
			-- nothing. Asserted as agreement rather than as a value, so it
			-- keeps holding if the registration above is ever changed.
			local keyDown = w:GetAttribute("useOnKeyDown")
			local answersDown = clicks and (clicks.AnyDown or clicks.LeftButtonDown)
			if keyDown == nil or (keyDown and true or false) ~= (answersDown and true or false) then
				deaf = deaf + 1
			end
			-- And nothing laid over the icon may answer the mouse, or the
			-- click lands on the swipe instead of on the ability.
			if w.cooldown:IsMouseEnabled() ~= false then
				blind = blind + 1
			end
		end
	end
	check(seen == 48, ("walked %d squares, expected 48"):format(seen))

	-- A square nothing can reach.
	--
	-- The one above is about what a square answers. This is about whether the
	-- mouse ever gets to ask, and it is a different bug with the same face: bar
	-- 1 drew, lit, counted down and cast off its keys, and every drop and every
	-- click on it went into Blizzard's MainActionBar, which sits mouse enabled
	-- and invisible across the bottom of the screen at level 50 while a frame
	-- built on UIParent starts at 1.
	--
	-- Asserted against the fixture's own level rather than a number written
	-- twice, and asserted on every bar rather than on bar 1, because the next
	-- bar somebody drags down there has to win the same argument.
	local sunk = 0
	for index = 1, #bars do
		local level = bars[index].frame:GetFrameLevel()
		if not level or level <= _G.MainActionBar:GetFrameLevel() then
			sunk = sunk + 1
		end
	end
	check(sunk == 0, ("%d cloned bars sit at or under Blizzard's own mouse enabled "
		.. "bar, so nothing can be dropped on them"):format(sunk))
	check(found.bar1.header:GetFrameLevel() > _G.MainActionBar:GetFrameLevel(),
		"the header the squares hang off is under Blizzard's bar frame")

	-- And the level is not the fix, which is what the trace finally said.
	--
	-- MainActionBar is mouse enabled in TOOLTIP, the top strata there is, so
	-- every drop aimed at bar 1 went into it whatever level the clone stood at.
	-- The frame is not ours to hide, because the micro menu and the bag bar hang
	-- off the same corner, so the mouse comes off it instead: it has no click
	-- handler and no drag handler, and the bar of ours standing over it is doing
	-- the only job it was doing.
	--
	-- Asserted on the frame walked up from the button rather than on a name, and
	-- asserted alongside a holder that never took the mouse, because a fix that
	-- silenced every frame it could reach would pass a check that only looked at
	-- this one.
	check(not _G.MainActionBar:IsMouseEnabled(),
		"Blizzard's bar frame still takes the mouse, so bar 1 still takes no drop")
	check(ns.TheirBars.Deafened() == 1,
		("%d of Blizzard's frames were silenced, expected the one that takes the mouse")
			:format(ns.TheirBars.Deafened()))
	check(not _G.MultiBarBottomLeft:IsMouseEnabled(),
		"a holder that never took the mouse was handed one")

	--------------------------------------------------------------------------
	-- Placing them
	--
	-- The bars shipped with no lock handling and no drag at all, which followed
	-- from the plan living in source and was never said out loud. /wk unlock
	-- reached the charge icon and the meters and silently did nothing here.
	--------------------------------------------------------------------------

	local shipped = ns.db.locked
	ns.db.locked = true
	ns.Each("lock")
	local showing = 0
	for index = 1, #bars do
		if bars[index].handle and bars[index].handle:IsShown() then
			showing = showing + 1
		end
	end
	check(showing == 0, ("%d drag handles are up with the frames locked"):format(showing))

	ns.db.locked = false
	ns.Each("lock")
	showing = 0
	for index = 1, #bars do
		if bars[index].handle and bars[index].handle:IsShown() then
			showing = showing + 1
		end
	end
	check(showing == #bars,
		("%d of %d bars grew a drag handle when the frames unlocked"):format(showing, #bars))

	-- The handle takes the mouse and the bar underneath it does not, which is
	-- the whole reason it is a separate frame: everything inside a bar is a
	-- secure button that has to keep answering clicks while you place it.
	check(bars[1].handle:IsMouseEnabled() == true, "the drag handle does not take the mouse")
	check(bars[1].frame:IsMouseEnabled() ~= true,
		"the bar itself takes the mouse, so it is competing with its own buttons")
	check(bars[1].frame.movable == true, "the bar was never made movable, so a drag does nothing")

	-- A drag writes an override, and the override is what draws.
	-- Delivered to a point rather than to the handle's script by name, which is
	-- the difference between "the handler is right" and "the player can reach
	-- it": the handle is a frame laid over the bar in HIGH and every square in
	-- the bar takes the mouse. Dropped on a fraction on purpose, because the bar
	-- is on the pixel grid and a fractional offset puts every icon and glyph
	-- across two rows of pixels, so this is where position is made whole.
	local one = found.bar1
	local took, dragging = H.mouse.DragTo(one.handle, one.frame, 40.4, 259.6)
	check(took == one.handle and dragging,
		("a drag on the middle of bar 1 landed on %s, dragging %s")
			:format(took and (took:GetName() or took:GetObjectType()) or "nothing",
				tostring(dragging)))
	local saved = ns.db.barPoints.bar1
	check(saved and saved[4] == 40 and saved[5] == 260,
		("a drag to 40.4, 259.6 recorded %s, %s"):format(
			tostring(saved and saved[4]), tostring(saved and saved[5])))

	-- And it comes back in the plan's own shape, so it can be pasted into
	-- Buttons/Bars.lua and stop depending on saved variables at all. That is
	-- the whole reconciliation between a plan in git and a bar you drag.
	local printed = ns.Bars.Where()
	check(#printed == #bars, ("where printed %d lines for %d bars"):format(#printed, #bars))
	check(printed[1]:find("x = 40") and printed[1]:find("y = 260") and printed[1]:find("dragged"),
		"the printed plan line does not carry what the drag recorded: " .. tostring(printed[1]))

	check(ns.Bars.ResetPlacing() == 1, "reset dropped no dragged position")
	check(next(ns.db.barPoints) == nil, "reset left a dragged position behind")
	local back, planned = ns.Bars.Where(), ns.WhichBars.PLAN[1].y
	check(back[1]:find("y = " .. planned) and not back[1]:find("dragged"),
		"reset did not put bar 1 back on the plan: " .. tostring(back[1]))

	ns.db.locked = shipped
	ns.Each("lock")
	check(mute == 0,
		("%d squares register no up edge, so a click on them does nothing"):format(mute))
	check(blind == 0,
		("%d cooldown swipes still answer the mouse and would eat the click"):format(blind))
	check(deaf == 0,
		("%d squares fire their key on an edge they do not answer, so the key does nothing")
			:format(deaf))

	-- Not by replacing a method on Blizzard's frame. ns.Strip swaps a region's
	-- Show for its Hide, which is right for a texture and wrong for a secure
	-- action button: the client's own bar controller calls Show on these from
	-- code that goes on to take protected actions, and an addon function
	-- running inside that stack taints it. The symptom is a press failing
	-- mid-fight with "Interface action failed because of an AddOn" and nothing
	-- on screen tying it to this addon, which is why it is asserted here rather
	-- than left to a comment.
	local swapped, flagged = 0, 0
	for index = 1, 12 do
		for _, pattern in ipairs({ "ActionButton%d", "MultiBarRightButton%d" }) do
			local frame = _G[pattern:format(index)]
			if frame then
				if rawget(frame, "Show") or rawget(frame, "wkStripped") then
					swapped = swapped + 1
				end
				if frame.attributes and frame.attributes.statehidden == true then
					flagged = flagged + 1
				end
			end
		end
	end
	check(swapped == 0,
		("%d of Blizzard's buttons had a method or a field written onto them"):format(swapped))
	check(flagged == 24,
		("%d of 24 hidden buttons carry statehidden, which is what stops the client showing them")
			:format(flagged))

	-- And when the client shows one anyway, the next repaint event puts it
	-- back. This is the half of the trade that statehidden buys: no taint, at
	-- the cost of having to answer the controller.
	_G.ActionButton1:Show()
	check(_G.ActionButton1:IsShown(), "the stub refused to show a hidden button, so the next check proves nothing")
	fire("ACTIONBAR_PAGE_CHANGED")
	check(not _G.ActionButton1:IsShown(),
		"the client put a button back and nothing hid it again")

	--------------------------------------------------------------------------
	-- A bar that was not there when we first looked
	--
	-- Discovery is a race, and the shipped version lost it. The client puts its
	-- own bars up on entering the world, which is after PLAYER_LOGIN, so the
	-- first look found bar 1 and four hidden holders; the build then refused to
	-- look again because something had been built, and one bar was the answer
	-- for the rest of the session.
	--
	-- MultiBarLeft is the fixture's off bar for exactly this. Turning it on and
	-- applying again has to clone it, and has to leave the four already
	-- standing alone rather than building them a second time.
	--------------------------------------------------------------------------

	do
	local was = #bars
	local names = {}
	for index = 1, #bars do
		names[bars[index].def.key] = (names[bars[index].def.key] or 0) + 1
	end

	_G.MultiBarLeft.shown = true
	check(Bars.Apply(), "a bar turning on reported combat deferring the clone")
	check(#bars == was + 1,
		("a bar turned on and the clone went from %d bars to %d"):format(was, #bars))

	local twice = 0
	for index = 1, #bars do
		local key = bars[index].def.key
		if names[key] then
			twice = twice + 1
			names[key] = nil
		end
	end
	check(twice == was, ("%d of %d bars survived the second look"):format(twice, was))
	check(Bars.Count() == (was + 1) * 12,
		("%d squares on %d bars, expected %d"):format(Bars.Count(), #bars, (was + 1) * 12))
	check(Bars.Hidden() == (was + 1) * 12,
		("%d of Blizzard's buttons are hidden behind %d cloned bars")
			:format(Bars.Hidden(), #bars))
	end

	--------------------------------------------------------------------------
	-- One bar at a time
	--
	-- The whole point of a switch per bar is that a bar which misbehaves can be
	-- handed back on its own. Handing one back is three things and any one of
	-- them left out leaves the player worse off than before they ticked it: the
	-- squares go, Blizzard's twelve come back, and the keys stop being taken.
	-- The last is the one that hides, because a key still pointing at a square
	-- nobody can see is a key that does nothing at all.
	--------------------------------------------------------------------------

	do
	local standing = #bars
	ns.WhichBars.Want("bottomleft", false)
	check(Bars.Apply(), "unticking a bar reported combat deferring it")

	check(#bars == standing - 1,
		("unticking one bar took the clone from %d bars to %d"):format(standing, #bars))
	check(not found.bottomleft.frame:IsShown(), "an unticked bar is still on screen")
	check(_G.MultiBarBottomLeftButton1:IsShown(),
		"an unticked bar did not give Blizzard's buttons back")
	check(_G.GetBindingAction("SHIFT-E", true) == "MULTIACTIONBAR1BUTTON1",
		"an unticked bar is still holding the key that presses it")
	check(Bars.Count() == (standing - 1) * 12,
		("%d squares are still on the tick with one bar unticked"):format(Bars.Count()))

	-- And a bar the client has switched off, ticked on. This is the half that
	-- reading IsShown alone could never do: the twelve slots are there and your
	-- keys point at them whether or not Blizzard is drawing a bar over them.
	ns.WhichBars.Want("bottomleft", true)
	check(Bars.Apply(), "ticking a bar back reported combat deferring it")
	check(#bars == standing, ("ticking the bar back left %d bars"):format(#bars))
	check(not _G.MultiBarBottomLeftButton1:IsShown(),
		"the bar came back and Blizzard's buttons stayed up behind it")
	check(_G.GetBindingAction("SHIFT-E", true)
		== ("CLICK %s:LeftButton"):format(found.bottomleft.buttons[1]:GetName()),
		"the key did not come back with the bar")

	-- Match drops every decision and follows the client again, which is the
	-- shipping state and the fast way in.
	check(ns.WhichBars.Decided() > 0, "ticking bars by hand recorded no decision to drop")
	check(ns.WhichBars.Follow() > 0, "match dropped nothing")
	check(ns.WhichBars.Decided() == 0, "match left a decision behind")
	check(Bars.Apply(), "following the client again reported combat deferring it")
	check(#bars == standing, ("following the client again left %d bars"):format(#bars))
	end

	--------------------------------------------------------------------------
	-- What a tick costs
	--------------------------------------------------------------------------

	local writes = 0
	local function countWrites(host, method)
		host[method] = function() writes = writes + 1 end
	end

	local watched = found.bar1.buttons[1]
	countWrites(watched.icon, "SetTexture")
	countWrites(watched.icon, "SetDesaturated")
	countWrites(watched, "SetAlpha")
	countWrites(watched.cooldown, "SetCooldown")
	countWrites(watched.timer, "SetText")
	countWrites(watched.count, "SetText")

	Bars.Update()
	writes = 0
	for _ = 1, 50 do
		Bars.Update()
	end
	check(writes == 0,
		("50 ticks with nothing moving wrote a square %d times"):format(writes))

	-- A slot that changed writes, so the guard above is a guard and not a
	-- ticker that has quietly stopped drawing.
	slots[73] = { texture = ART, usable = false, noPower = true }
	Bars.Update()
	check(writes > 0, "a square did not redraw when its slot changed")

	collectgarbage()
	collectgarbage("stop")
	local before = collectgarbage("count")
	for _ = 1, 50 do
		Bars.Update()
	end
	barsChurn = collectgarbage("count") - before
	collectgarbage("restart")

	--------------------------------------------------------------------------
	-- What a square answers to the hand
	--
	-- UI/Ability.lua's own section proves a square can draw a hover, a pushed
	-- tint, a swipe for the global and an active wash. None of that proves the
	-- squares this file builds are wired to any of it: the tooltip is hung on
	-- the button in Buttons/Bars.lua and the active flag is the seventh
	-- argument to a Draw call there, and either could be dropped by a refactor
	-- with every check in the ability section still green.
	--
	-- Driven on buttons[2] and not buttons[1]. Every drawing method on the
	-- first square is shadowed above by a counter that records the call and
	-- stores nothing, so a readback off it answers whatever was there before
	-- the shadow went on rather than what the tick just drew.
	--------------------------------------------------------------------------

	local square = found.bar1.buttons[2]
	local seat = square:GetAttribute("action")

	check(square.pushed ~= nil,
		"a bar square draws nothing on the way down, so a click has no answer")
	check(square.hover and square.hover.layer == "HIGHLIGHT",
		"a bar square has no highlight layer, so hovering it does nothing")

	-- The global sweeps, carries no number, and does not move the look. That
	-- last one is the whole point of keeping it out of the status: if it moved
	-- the look, the entire bar would grey for a second and a half on every
	-- press.
	slots[seat] = { texture = ART, start = _G.GetTime(), duration = 1.5, current = true }
	Bars.Update()
	check(square.cooldown.cdDuration == 1.5,
		"the global draws no swipe, so pressing a rage dump changes nothing on screen")
	check((square.timer:GetText() or "") == "",
		"the global is being counted down on the square like a real cooldown")
	check(square.shownLook == ns.UI.Ability.Look(ns.UI.Ability.QUIET, "ready"),
		"the global moved the square's look, so the whole bar greys on every press")
	check(square.active:IsShown(),
		"the tick does not hand the active flag through, so the stance you are in is invisible")

	slots[seat] = { texture = ART, start = _G.GetTime(), duration = 30 }
	Bars.Update()
	check((square.timer:GetText() or "") ~= "", "a real cooldown lost its countdown")
	check(not square.active:IsShown(), "the active tint outlived the ability running")

	slots[seat] = nil
	Bars.Update()
	check(square.icon:GetTexture() == nil,
		"an empty square draws the fallback question mark, so an unfilled bar reads as broken")
	check(square.cooldown.cdDuration == 0, "an emptied square kept its swipe")

	-- The tooltip. The box is the addon's own and the words in it are still the
	-- client's, read off a hidden one by UI/Scan.lua because the rank and the
	-- cost are computed inside the game. Both halves are asserted, because
	-- either alone is a passing test and a broken square.
	local Tip = ns.UI.Tooltip
	H.tooltips.action[seat] = { { "Heroic Strike" }, { "Rank 8", "12 rage" } }

	-- Both scripts are checked for before either is called. A square that was
	-- never given them answers nil here, and calling nil aborts the run with a
	-- stack trace instead of naming the thing that is missing, which is the
	-- opposite of what a gate is for.
	local enter, leave = square:GetScript("OnEnter"), square:GetScript("OnLeave")
	check(enter and leave,
		"a bar square has no hover scripts, so it can never show a tooltip")

	slots[seat] = { texture = ART }
	Bars.Update()
	if enter then
		enter(square)
	end
	check(Tip.IsShown(), "hovering a square opened nothing")
	check(Tip.Owner() == square, "the tooltip is not anchored to the square you hovered")
	check(Tip.Text(1) == "Heroic Strike",
		("the square says %s and the client says Heroic Strike")
			:format(tostring(Tip.Text(1))))
	local rank, cost = Tip.Text(2)
	check(rank == "Rank 8" and cost == "12 rage",
		("the client's paired line came through as %s / %s")
			:format(tostring(rank), tostring(cost)))
	if leave then
		leave(square)
	end
	check(Tip.Owner() == nil, "leaving the square left the box still anchored to it")
	check(not H.tipSettle(), "the tooltip stays up after the cursor has left the square")

	-- An empty slot fills nothing and would leave the last ability's tooltip on
	-- screen anchored to a square that has none, which is worse than silence.
	slots[seat] = nil
	Bars.Update()
	if enter then
		enter(square)
	end
	check(not Tip.IsShown(), "an empty square opened a tooltip it cannot fill")

	H.tooltips.action[seat] = nil
	slots[seat] = nil

	--------------------------------------------------------------------------
	-- Dragging a spell onto a square
	--
	-- The only way to fill one by hand, because the Blizzard button underneath
	-- is hidden and cannot be dropped on. Driven end to end across two squares:
	-- a pickup that never fills the cursor and a drop that never moves a slot
	-- look exactly like a bar you cannot drop on.
	--------------------------------------------------------------------------

	local other = found.bar1.buttons[3]
	local there = other:GetAttribute("action")
	check(square.dragButton ~= nil and other.dragButton ~= nil,
		"a bar square is not registered for a drag, so nothing can be moved onto it")

	-- Picked up and put down by the pointer, one square to another, rather than
	-- by two scripts called by name.
	slots[seat] = { texture = ART }
	slots[there] = nil
	local function carry(from) return H.mouse.Grab(H.mouse.Point(from)) end
	local function put(target) return H.mouse.Drop(H.mouse.Point(target)) end

	check(carry(square) == square,
		"the pointer over a square found something else on top of it")
	check(GetCursorInfo() ~= nil, "dragging a square picked nothing up")
	check(slots[seat] == nil, "the slot kept its ability while the cursor carried it")
	put(other)
	check(slots[there] ~= nil and slots[there].texture == ART,
		"dropping on an empty square did not fill it")
	check(GetCursorInfo() == nil, "the cursor is still full after a drop onto an empty slot")

	-- And a swap, which is the case that loses a bar if it is wrong: dropping
	-- onto a filled square has to hand the displaced ability back rather than
	-- destroy it.
	local OTHER_ART = "Interface\\Icons\\Ability_Warrior_Cleave"
	slots[seat] = { texture = OTHER_ART }
	H.mouse.Onto(square, other)
	check(slots[there] ~= nil and slots[there].texture == OTHER_ART,
		"a drop onto a filled square did not replace what was there")
	check(GetCursorInfo() ~= nil, "the displaced ability was destroyed instead of handed back")
	ClearCursor()

	-- Refused in combat, where PickupAction cannot be called at all. The clone
	-- shares Layout's probe, so it is the refusal that stops a loadout writing
	-- mid-fight.
	slots[seat] = { texture = ART }
	local realLockdown = _G.InCombatLockdown
	_G.InCombatLockdown = function() return true end
	H.mouse.Onto(square, square)
	_G.InCombatLockdown = realLockdown
	check(GetCursorInfo() == nil, "a square let go of its ability in combat")
	check(slots[seat] ~= nil, "a slot was emptied by a drag started in combat")

	slots[seat] = nil
	slots[there] = nil

	--------------------------------------------------------------------------
	-- A drop that goes nowhere, said out loud
	--
	-- What this pays for: bar 1 hovered, named what was on it and pushed under a
	-- click, and took no drop at all, through two fixes written by reading the
	-- code. Every one of those failures printed nothing, so the three ways a drop
	-- can die looked identical on screen. Driven rather than asserted, for the
	-- reason the drag above is: a message never reached is worth no message.
	--------------------------------------------------------------------------

	local chat = _G.DEFAULT_CHAT_FRAME.AddMessage
	local heard = {}
	_G.DEFAULT_CHAT_FRAME.AddMessage = function(_, text)
		heard[#heard + 1] = tostring(text)
	end
	local function Heard(what)
		for index = 1, #heard do
			if heard[index]:find(what, 1, true) then
				return true
			end
		end
		return false
	end

	-- The client taking the call and doing nothing with it, which is what a
	-- slot it will not write looks like from this side.
	local realPlace = _G.PlaceAction
	slots[seat] = { texture = ART }
	carry(square)
	_G.PlaceAction = function() end
	heard = {}
	put(other)
	_G.PlaceAction = realPlace
	check(Heard("changed nothing"),
		"a drop the client did nothing with said nothing either")
	ClearCursor()
	slots[seat], slots[there] = nil, nil

	-- A square pointing at no slot, which is the state a bar 1 whose stance
	-- pages never arrived would sit in. It draws, it hovers and it presses,
	-- because all three read the same missing attribute and find nothing to
	-- complain about.
	local held = other:GetAttribute("action")
	other:SetAttribute("action", nil)
	slots[seat] = { texture = ART }
	carry(square)
	heard = {}
	put(other)
	check(Heard("not pointing at an action slot"),
		"a square with no slot behind it swallowed a drop in silence")
	other:SetAttribute("action", held)
	ClearCursor()
	slots[seat], slots[there] = nil, nil

	-- And a drop that worked says nothing at all, because a bar that talks
	-- every time it works is a bar nobody reads when it stops working.
	slots[seat] = { texture = ART }
	carry(square)
	heard = {}
	put(other)
	check(#heard == 0,
		("a drop that worked printed %d lines"):format(#heard))
	ClearCursor()
	slots[seat], slots[there] = nil, nil

	--------------------------------------------------------------------------
	-- The trace
	--
	-- Off unless asked for, and when asked for it prints the two things no
	-- reading of the code produced: which gesture reached a square, and which
	-- frame the client says the cursor is over.
	--------------------------------------------------------------------------

	check(not ns.BarTrace.Running(), "the trace ships switched on")
	slots[seat] = { texture = ART }
	heard = {}
	H.mouse.Onto(square, square)
	check(#heard == 0, "the trace talks with its switch off")
	ClearCursor()
	slots[seat] = nil

	-- Which call this client answers "what is the cursor over" with, said on
	-- the way in. The first live run of this trace printed every gesture and
	-- never named a single frame, which from the chat frame looks exactly like
	-- a cursor touching nothing rather than a client with no such call.
	local realFocus, realFoci = _G.GetMouseFocus, _G.GetMouseFoci
	_G.GetMouseFocus, _G.GetMouseFoci = nil, nil
	heard = {}
	ns.BarTrace.Set(true)
	check(Heard("neither GetMouseFocus nor GetMouseFoci"),
		"a client with no way to name the frame under the cursor said nothing about it")
	ns.BarTrace.Set(false)

	_G.GetMouseFoci = function() return { _G.ActionButton1 } end
	heard = {}
	ns.BarTrace.Set(true)
	check(Heard("GetMouseFoci"), "the trace did not say which call it is reading the cursor with")

	slots[seat] = { texture = ART }
	heard = {}
	H.mouse.Onto(square, other)
	check(Heard("pick up from slot " .. seat) and Heard("drop on slot " .. there),
		"the trace missed the gesture it exists to print")

	-- A click, which is how a spell is dropped as often as a drag is, and which
	-- the first version of this file could not see at all.
	heard = {}
	check(other:GetScript("PostClick"),
		"a square has no PostClick, so a drop made by clicking is invisible")
	H.mouse.On(other, "LeftButton")
	check(Heard("click LeftButton on slot " .. there),
		"the trace missed a click on a square")

	ClearCursor()
	slots[seat], slots[there] = nil, nil

	-- The newer of the two calls answers a stack, topmost first, and only the
	-- top of it is under the cursor.
	heard = {}
	ns.BarTrace.Sample(nil, 1)
	check(Heard("ActionButton1"),
		"the sampler did not read the frame out of the stack GetMouseFoci answers")
	_G.GetMouseFoci = realFoci
	ns.BarTrace.Set(false)

	-- The sampler, which is the whole instrument. A drop that never reaches a
	-- square is a frame with a name, a strata and a level, and this is what
	-- prints them.
	_G.GetMouseFocus = function() return _G.ActionButton1 end
	ns.BarTrace.Set(true)
	heard = {}
	ns.BarTrace.Sample(nil, 1)
	-- TOOLTIP rather than MEDIUM, and the button never asked for it: it hangs off
	-- MainActionBar, which sits in the top strata, and a strata is inherited
	-- where nobody sets one.
	check(Heard("ActionButton1") and Heard("TOOLTIP"),
		"the sampler did not name the frame the client says is under the cursor")
	-- and it says it once rather than five times a second for as long as the
	-- cursor sits still, which is what makes it readable at all.
	heard = {}
	ns.BarTrace.Sample(nil, 1)
	check(#heard == 0, "the sampler repeats itself while the cursor sits still")
	_G.GetMouseFocus = realFocus
	ns.BarTrace.Set(false)
	_G.DEFAULT_CHAT_FRAME.AddMessage = chat

	-- The ring, on the square the tick actually drives.
	slots[seat] = { texture = ART, equipped = true }
	Bars.Update()
	check(square.equipped[1]:IsShown(),
		"the tick does not hand the equipped flag through, so a worn item has no ring")
	slots[seat] = { texture = ART }
	Bars.Update()
	check(not square.equipped[1]:IsShown(), "the equipped ring outlived the item on the bar")
	slots[seat] = nil

	--------------------------------------------------------------------------
	-- The off switch
	--------------------------------------------------------------------------

	ns.db.actionBars = false
	check(Bars.Apply(), "turning the clone off reported combat deferring it")

	check(_G.ActionButton1:IsShown() and _G.MultiBarRightButton12:IsShown(),
		"Blizzard's buttons did not come back")
	check(_G.MainActionBar:IsMouseEnabled(),
		"the off switch left Blizzard's own bar frame deaf to the mouse")
	check(ns.TheirBars.Deafened() == 0,
		"the off switch left frames silenced with no way to find them")
	check(Bars.Hidden() == 0, "the off switch left buttons hidden with no way to find them")
	check(not found.bar1.frame:IsShown(), "a cloned bar is still on screen with the clone off")
	check(_G.GetBindingAction("E", true) == "ACTIONBUTTON1",
		"an override binding outlived the feature that set it")
	check(Bars.Count() == 0, "the tick is still drawing squares nobody can see")

	-- And back, because the anchor sweep at the end of this file is the only
	-- thing that holds these bars to a whole pixel at 2x and 3x, and it can
	-- only see frames that are there.
	ns.db.actionBars = true
	Bars.Apply()
	check(_G.GetBindingAction("E", true) ~= "", "the keys did not come back with the bars")

	slots[73] = { texture = ART }

	print(("bars   %d bars, %d squares of 27 px, %d keys, pages %s, %.2f KB per 50 ticks, gate is %.2f")
		:format(#bars, Bars.Count(), claimed, Bars.CanPage() and "in combat" or "out of combat only",
			barsChurn, CHURN.bars))
	check(barsChurn <= CHURN.bars,
		("the bars tick allocated %.2f KB per 50 ticks, over the %.2f KB gate")
			:format(barsChurn, CHURN.bars))
end

-- A mob and the plate the client puts up for it, carrying a scale of its own
-- the way a real plate does, so a widget that inherited it would be measurably
-- wrong. The size is whatever the client has in force, which is this stub's own
-- figure until the addon has asked for another.
local function Pull(index)
	local unit = "nameplate" .. index
	local plate = region("frame", _G.UIParent)
	plate.namePlateUnitToken = unit
	plate.scale = 1.1
	plate:SetSize(plateSize[1] or PLATE_W, plateSize[2] or PLATE_H)
	plate.UnitFrame = region("frame", plate)
	plate.UnitFrame:SetSize(plate:GetWidth(), plate:GetHeight())
	-- The child regions a nameplate carries, read off the client's XML: they
	-- must exist rather than fall through to the metatable above, which hands
	-- the strip a method. The cast bar sits inside its container, nowhere else.
	for _, child in ipairs({ "healthBar", "name", "LevelFrame", "ClassificationFrame",
		"selectionHighlight", "aggroHighlight", "RaidTargetFrame", "CastBarsContainer" }) do
		plate.UnitFrame[child] = region("frame", plate.UnitFrame)
	end
	plate.UnitFrame.CastBarsContainer.castBar = region("frame", plate.UnitFrame.CastBarsContainer)
	plates[#plates + 1] = plate
	guids[unit] = ("Creature-0-0-0-0-1234-0000000%d"):format(index)
	fire("NAME_PLATE_UNIT_ADDED", unit)
	return ns.EnemyBars.WidgetFor(unit)
end

for i = 1, 2 do
	Pull(i)
end

local anchor = _G.WarriorKitEnemyBarsAnchor
local widget = ns.EnemyBars.WidgetFor("nameplate1")
check(anchor ~= nil, "no anchor came up")
check(widget ~= nil, "no widget attached to nameplate1")

-- The grid.
check(math.abs(ns.UI.Scale() - 768 / state.SCREEN_H) < 1e-9,
	("perfect scale is %.6f, expected %.6f"):format(ns.UI.Scale(), 768 / state.SCREEN_H))
for name, frame in pairs({ anchor = anchor, widget = widget }) do
	local px = ns.UI.Pixel(frame)
	check(math.abs(px - 1) < 1e-9, ("%s is not on the grid: one pixel is %.4f units"):format(name, px))
end

-- Whole pixels where the grid can reach. The health number is the one size
-- derived from a measurement the client made, so it is the one that can come
-- back fractional; the tag frame that used to hold that job is gone.
-- The debuff square is in the walk only where there is one. Which debuffs a bar
-- tracks is a fact about your spec now, and a class nobody has written a file
-- for tracks none until you pick some, so on that run there is no square to put
-- on the grid rather than a square that is off it.
for _, pair in ipairs({ { "widget", widget }, { "box", widget.box },
	{ "health number", widget.healthText },
	widget.icons[1] and { "icon", widget.icons[1] } or nil }) do
	for _, axis in ipairs({ "GetWidth", "GetHeight" }) do
		local size = pair[2][axis](pair[2])
		check(math.abs(size - math.floor(size + 0.5)) < 1e-9,
			("%s %s is %.4f, not a whole pixel"):format(pair[1], axis, size))
	end
end

-- A bar on a plate is `bars width` pixels, every bar, and it stays there.
--
-- It used to be as wide as the plate under it, and it then told the driver to
-- size plates by a footprint a tag wider than itself, so the next bar measured
-- off a plate came back changed: wider every round where a plate is scaled
-- above UIParent, which is this stub and was the harness case, narrower every
-- round on the client this was reported from. Either way no fixed point and no
-- setting that chose one. The five lines below are the whole of the contract:
-- the setting decides, six mobs do not move it, and a setting change does not
-- either.
local function BarWidth(unit)
	local bar = ns.EnemyBars.WidgetFor(unit)
	return bar and bar:GetWidth() or -1
end

local wanted = ns.db.barsWidth * ns.UI.Pixel(widget)
check(BarWidth("nameplate1") == wanted,
	("a bar on a plate is %.0f px, the setting says %.0f"):format(BarWidth("nameplate1"), wanted))
for i = 3, 6 do
	Pull(i)
	check(BarWidth("nameplate" .. i) == wanted,
		("mob %d got a bar %.0f px wide, the setting says %.0f"):format(
			i, BarWidth("nameplate" .. i), wanted))
end
ns.EnemyBars.Rebuild() -- what every setting in the panel does
check(BarWidth("nameplate1") == wanted,
	("a setting change took the bar to %.0f px, the setting says %.0f"):format(
		BarWidth("nameplate1"), wanted))

-- And the setting reaches a bar that is already on a plate, which is the half
-- of it that has no second chance: a widget on a plate is laid out when it
-- attaches, and these attached before the number changed.
ns.db.barsWidth = 240
ns.EnemyBars.ApplyLayout()
check(BarWidth("nameplate1") == 240 * ns.UI.Pixel(widget),
	("bars width 240 left the bar on a plate at %.0f px"):format(BarWidth("nameplate1")))
ns.db.barsWidth = ns.DefaultFor("barsWidth")
ns.EnemyBars.ApplyLayout()

-- Back down to the two the churn figure below is quoted at. The gate is a
-- number of KB per fifty ticks with two bars up, so the mobs pulled to prove
-- the width holds have to leave again or the ratchet is measuring a different
-- scene than the one it was set on.
for i = #plates, 3, -1 do
	fire("NAME_PLATE_UNIT_REMOVED", plates[i].namePlateUnitToken)
	guids[plates[i].namePlateUnitToken] = nil
	plates[i] = nil
end

-- The gauge fills the inside of the box, which is the box less one hairline on
-- each edge. Asserted because it was briefly one pixel tall: the gauge carries
-- no height of its own and takes whatever the box has left, and a layout node
-- that is not told to grow measures zero and gets zero.
do
	local px = ns.UI.Pixel(widget)
	-- Horizontally the gauge is still the box less a hairline each side, and
	-- that half has not moved.
	check(math.abs(widget.health:GetWidth() - (widget.box:GetWidth() - 2 * px)) < 1e-9,
		("the gauge is %.0f px wide inside a %.0f px box, expected %.0f")
			:format(widget.health:GetWidth(), widget.box:GetWidth(),
				widget.box:GetWidth() - 2 * px))

	-- Vertically it is the box less two hairlines only while nothing is casting.
	-- The box has two chambers now and the second one comes and goes, so what is
	-- asserted is the arithmetic both states have to satisfy:
	--
	--   idle = hairline + health + hairline
	--   open = idle + seam + cast
	--
	-- and, the part that is the whole reason the chamber is not a Flow node,
	-- that the health gauge is the same height and in the same place in both.
	check(math.abs(widget.health:GetHeight() - (widget.boxIdle - 2 * px)) < 1e-9,
		("the gauge is %.0f px tall inside a %.0f px idle box, expected %.0f")
			:format(widget.health:GetHeight(), widget.boxIdle, widget.boxIdle - 2 * px))
	check(math.abs(widget.box:GetHeight() - widget.boxIdle) < 1e-9,
		("nothing is casting and the box is %.0f px, idle is %.0f")
			:format(widget.box:GetHeight(), widget.boxIdle))

	local cast = widget.cast
	check(math.abs(widget.boxOpen - (widget.boxIdle + px + cast:GetHeight())) < 1e-9,
		("the open box is %.0f px, expected idle %.0f plus a seam plus a %.0f px chamber")
			:format(widget.boxOpen, widget.boxIdle, cast:GetHeight()))

	local beforeH = widget.health:GetHeight()
	local _, _, _, _, beforeY = widget.health:GetPoint()
	ns.db.locked = false -- unlocked, the chamber previews itself on every bar
	ns.Cast.Update(widget, "nameplate1")
	check(math.abs(widget.box:GetHeight() - widget.boxOpen) < 1e-9,
		("a cast left the box at %.0f px, open is %.0f")
			:format(widget.box:GetHeight(), widget.boxOpen))
	check(widget.cast.seam:IsShown(), "the box has two chambers and no seam between them")
	local _, _, _, _, afterY = widget.health:GetPoint()
	check(widget.health:GetHeight() == beforeH and afterY == beforeY,
		"the cast chamber moved the health gauge, which is the whole thing it must not do")

	ns.db.locked = true
	ns.Cast.Clear(widget)
	check(math.abs(widget.box:GetHeight() - widget.boxIdle) < 1e-9,
		("the cast ended and the box stayed at %.0f px, idle is %.0f")
			:format(widget.box:GetHeight(), widget.boxIdle))
	check(not widget.cast.seam:IsShown(), "nothing is casting and the seam is still drawn")
end

-- The edges are one pixel, which was the whole complaint.
check(widget.box.edges[1].height == ns.UI.Pixel(widget),
	("hairline is %.4f units, expected %.4f"):format(widget.box.edges[1].height, ns.UI.Pixel(widget)))

-- The icon crop lands on texel boundaries and the client's snapping is off.
-- Asked only where the bar is tracking something, for the reason the grid walk
-- above skips the same square, and every class run reaches it.
local art = widget.icons[1] and widget.icons[1].icon
check(not art or (art.texcoord and math.abs(art.texcoord[1] * 64 - 5) < 1e-9),
	"icon crop is not on a texel boundary")
check(not art or (art.snapped == false and art.bias == 0),
	"icon texture is still being snapped")

-- Left for the sections below.
H.carry.anchor, H.carry.wanted, H.carry.widget = anchor, wanted, widget
