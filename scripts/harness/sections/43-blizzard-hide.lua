-- Blizzard's own frames, held down
--
-- Every switch under `/wk hide` used to be a frame hidden once at login by
-- putting its own Hide where its Show was, and a record that said it had been.
-- That shipped and failed twice in game, so this section is written against the
-- two failures rather than against the switches: the switches were on both
-- times, and reading a setting back proves nothing at all about what is on the
-- screen.
--
-- The failures were the same failure. `SetShown` is resolved in C and never
-- reads the Lua `Show` a strip replaced, so every FrameXML path written that way
-- walked past the hide. `FCF_` uses it on the chat window, which is why
-- `/logout` put the client's chat back; the cast bar mixin uses it on the
-- target's bar, which is why there were two cast bars for one cast. And because
-- the file remembered what it had done, the first frame that got past it stayed
-- past it for the rest of the session.
--
-- So every assertion below is on IsVisible rather than on IsShown, and most of
-- them fire SetShown first. A frame in the attic is allowed to have its own flag
-- turned back on: its parent is hidden and cannot be shown, so the flag is the
-- only thing that moved. That is the whole claim, and IsShown cannot see it.
--
-- What is not measured here: the frames each switch names on the live client.
-- The fixture carries the names this addon was written against, so this section
-- answers for the mechanism and `/wk hide probe` answers for the names.

local H = ...
local ns, check, frames, advance = H.ns, H.check, H.frames, H.advance
local CHURN = H.CHURN

local Attic, Blizz = ns.Attic, ns.BlizzHide

-- The seconds Core/BlizzHide.lua puts between passes. Written here rather
-- than read off the ticker, because the ticker is the thing being driven and a
-- number taken from it would agree with itself whatever it was.
local HIDE_INTERVAL = 5

----------------------------------------------------------------------
-- The room itself
----------------------------------------------------------------------

local attic = Attic.Frame()
check(attic ~= nil, "no attic was built, so nothing is caged and every hide is a strip")
check(attic:IsShown() == false, "the attic is on the screen")

-- The two calls that reach a frame from outside. Neither may work on this one,
-- because a room somebody shows is a room with nothing in it, and the second is
-- the same call every bug in this file has been about.
attic:Show()
check(attic:IsShown() == false, "Show put the attic on the screen")
attic:SetShown(true)
check(attic:IsShown() == false, "SetShown put the attic on the screen")

----------------------------------------------------------------------
-- The target's cast bar, which was drawn twice
----------------------------------------------------------------------

do
	-- With Blizzard's target frame on the screen, because the cast bar is a
	-- child of it and every question below about whether the bar can be seen
	-- is a question about the bar's own switch and not about its parent's.
	ns.db.hideBlizzUnitFrames = false
	ns.db.hideBlizzTargetCast = true
	Blizz.Apply()

	local bar = _G.TargetFrameSpellBar
	check(bar:IsVisible() == false, "the client's target cast bar is still on the screen")
	check(Attic.Held(bar), "the target cast bar is hidden but not caged")

	-- The cast bar mixin starting a cast. This is the call the old hide lost to,
	-- and the flag really does come back on: nothing an addon installs can stop
	-- SetShown. What stops the picture is the parent.
	_G.Target_Spellbar_OnEvent()
	check(bar:IsShown(), "the fixture cannot put the cast bar back, so this proves nothing")
	check(bar:IsVisible() == false,
		"a cast put the client's cast bar back on the screen with the switch on")

	-- The fourth call site, and the one the key cannot guard. TargetFrame's
	-- three go through the key; the bar's own handler calls AdjustPosition on
	-- itself and never asks TargetFrame for anything. The call above would have
	-- raised on every cast, one error per cast rather than one per OnUpdate,
	-- which is why this one outlived the key by a fortnight. So the method is
	-- taken off the bar for as long as the bar is in the attic.
	check(bar.wkMuted ~= nil,
		"the caged cast bar is still holding the layout call that reads its parent")

	-- Reached under FrameXML's parent key as well, so a client that renamed the
	-- global still loses its bar. Same frame both ways, which the pass has to
	-- take in its stride.
	--
	-- And the key is gone while the bar is caged, which is the third failure this
	-- section is written against. TargetFrame calls spellbar:AdjustPosition()
	-- from three places, that function reads auraRows off the bar's parent, and
	-- the attic has no such field: an evening with the switch on and a target
	-- selected was sixteen hundred Lua errors, one per pass of the target
	-- frame's OnUpdate. All three call sites are guarded by the key, so the key
	-- coming out is what takes the bar out of the client's hands. The cage is
	-- still what keeps it off the screen; this is what stops the client driving
	-- a frame it can no longer see.
	check(Blizz.Stashed("TargetFrame", "spellbar"),
		"the target's cast bar is caged and the client is still holding the key to it")
	check(_G.TargetFrame.spellbar == nil,
		"TargetFrame still names a cast bar that is in the attic")
	check(Blizz.Apply() ~= false, "a second pass over the same frame refused")

	-- And off again, all the way back to where it was found.
	ns.db.hideBlizzTargetCast = false
	Blizz.Apply()
	check(bar:IsVisible(), "turning the switch off left the client's cast bar hidden")
	check(bar:GetParent() == _G.TargetFrame,
		"the cast bar came back parented somewhere other than the target frame")
	check(Attic.Held(bar) == false, "the attic is still holding a frame it handed back")
	check(_G.TargetFrame.spellbar == bar,
		"the switch went off and TargetFrame never got its cast bar key back")
	check(Blizz.Stashed("TargetFrame", "spellbar") == false,
		"the key was handed back and this file still thinks it is holding it")
	check(bar.wkMuted == nil, "the cast bar came back with its own layout call still off")
	check(pcall(_G.Target_Spellbar_OnEvent),
		"a cast on the cast bar raised after the switch went off")
	check(bar.offset == 0,
		"the cast bar is back on the screen and something else is laying it out")

	ns.db.hideBlizzTargetCast = true
	Blizz.Apply()
end

----------------------------------------------------------------------
-- Blizzard's chat window, which came back on /logout
----------------------------------------------------------------------

do
	-- The sections above leave the client's window back on the screen, so the
	-- scene is set here rather than inherited. Hiding follows our window as well
	-- as the switch: a game with neither has no chat in it at all.
	ns.db.chat, ns.db.hideBlizzChat = true, true
	ns.ChatWindow.Show()
	check(ns.ChatWindow.Shown(), "our chat window would not open, so nothing may hide the client's")
	check(ns.ChatBlizzard.Hiding(), "the client's chat window is not hidden to begin with")
	local chat = _G.ChatFrame1
	check(chat:IsVisible() == false, "the client's first chat frame is on the screen")

	-- What `FCF_` does when anything docks, selects or flashes a frame, which is
	-- what running a slash command through the client's own edit box ends in.
	chat:SetShown(true)
	check(chat:IsVisible() == false,
		"the client's chat window came back on a SetShown, which is the /logout bug")

	-- A window the client opens after login, which is every temporary window a
	-- whisper makes. The old pass returned early when the answer had not changed
	-- and never saw one of these.
	_G.NUM_CHAT_WINDOWS = 3
	local late = _G.CreateFrame("Frame", "ChatFrame3", _G.UIParent)
	check(late:IsVisible(), "the fixture's late chat window was never on the screen")
	Blizz.Apply()
	check(late:IsVisible() == false,
		"a chat window the client opened after login was left on the screen")

	_G.NUM_CHAT_WINDOWS = 2

	-- And back where the sections above this one left it, because the client's
	-- window on the screen is the state they set up and this one borrowed.
	ns.db.hideBlizzChat = false
	ns.ChatWindow.Apply()
	check(chat:IsVisible(), "the client's chat window was left hidden for whatever runs next")

	-- And Blizzard's target frame back in the attic, which is where every
	-- section after this one expects it.
	ns.db.hideBlizzUnitFrames = true
	Blizz.Apply()
end

----------------------------------------------------------------------
-- Somebody else's SetParent, which is the one call a cage loses to
----------------------------------------------------------------------

do
	local bar = _G.TargetFrameSpellBar
	check(Attic.Held(bar), "the cast bar is not caged, so this measures nothing")

	bar:SetParent(_G.TargetFrame)
	check(bar:IsVisible() == false,
		"the fixture's re-parent did not put the bar back where it can be seen")

	-- The sweep is the backstop, and it is what a client with no hooks has. It
	-- runs inside every pass.
	check(Attic.Sweep(), "the sweep refused to put a re-parented frame back")
	check(bar:GetParent() == attic, "a frame re-parented out of the attic stayed out")
end

----------------------------------------------------------------------
-- The same call answered on the frame it happens
--
-- The sweep above used to be the whole answer and ran once a second for it.
-- Core/Attic.lua now hooks SetParent on every frame it takes, so the frame is
-- back in the room before the caller's next line and the walk is a backstop
-- rather than the mechanism. That is what lets the clock drop to five seconds.
--
-- hooksecurefunc is installed for this block alone and taken away after, the
-- same as in 29-social.lua and 39-party-raid.lua and for the same reason:
-- leaving it in the fixture switches on hooks in UnitFrames/Skin.lua and
-- Chat/Blizzard.lua that have never been able to install here, which changes
-- what every section above is measuring. The attic asks for it at Take time, so
-- the bar is handed back and taken again for the hook to land on it.
----------------------------------------------------------------------

do
	_G.hooksecurefunc = function(target, name, post)
		local original = target[name]
		target[name] = function(...)
			original(...)
			post(...)
		end
	end

	ns.db.hideBlizzTargetCast = false
	Blizz.Apply()
	ns.db.hideBlizzTargetCast = true
	Blizz.Apply()
	_G.hooksecurefunc = nil

	local bar = _G.TargetFrameSpellBar
	check(Attic.Held(bar), "the cast bar went back in the room and the attic did not record it")

	-- No sweep, no tick, no pass. The call itself and then the question.
	bar:SetParent(_G.TargetFrame)
	check(bar:GetParent() == attic,
		"a frame re-parented out of the attic is still out of it on the very next line")
	check(bar:IsVisible() == false, "the re-parented bar was on the screen")

	-- The second hook rides on a field ns.Strip already owns, so what is
	-- measured here is the pair of them: the strip put Hide where Show was, the
	-- hook sits over that, and a Show still leaves nothing on the screen.
	bar:Show()
	check(bar:IsVisible() == false, "a Show put the caged cast bar back on the screen")
	check(bar:GetParent() == attic, "a Show took the cast bar out of the attic")
end

----------------------------------------------------------------------
-- The probe, which is how the next report costs one command
----------------------------------------------------------------------

do
	local rows = Blizz.Probe()
	check(#rows > 0, "the probe reported nothing at all")

	local found, escaped = false, false
	for _, row in ipairs(rows) do
		if row:find("TargetFrameSpellBar", 1, true) then
			found = true
		end
		if row:find("ON SCREEN", 1, true) then
			escaped = true
		end
	end
	check(found, "the probe does not name the target's cast bar")
	check(not escaped, "the probe says a frame is on screen that a switch asked to hide")
end

----------------------------------------------------------------------
-- The clock
--
-- Every five seconds forever, behind the hook and ADDON_LOADED rather than in
-- front of them, so a client where neither works still has nothing of Blizzard's
-- left on the screen. What it must not do is allocate: a pass that produces
-- garbage on a timer is a pass the collector walks in the middle of a frame,
-- which is the rule every ticker in this addon is held to.
--
-- Driven at the interval rather than at one second, so the number below is a
-- hundred passes of the work and stays comparable with what it measured while
-- the clock ran at one hertz.
----------------------------------------------------------------------

do
	check(ns.UI.Ticking("hide") ~= nil, "the hide pass registered no ticker")
	local ticker = H.tick("hide")

	local function churn(ticks)
		collectgarbage("collect")
		collectgarbage("stop")
		local before = collectgarbage("count")
		for _ = 1, ticks do
			advance(HIDE_INTERVAL)
			ticker:Beat(HIDE_INTERVAL)
		end
		local after = collectgarbage("count")
		collectgarbage("restart")
		return (after - before) / (ticks / 50)
	end

	-- Cold first, for the reason every other churn measurement here takes a cold
	-- pass: the first run interns every string the walk will ever build.
	churn(100)
	local burn = churn(100)
	check(burn <= CHURN.hide,
		("the hide tick allocates %.2f KB per 50 ticks, the gate is %.2f")
			:format(burn, CHURN.hide))

	print(("hide   %s; %.2f KB per 50 ticks, gate is %.2f")
		:format(Blizz.Describe(), burn, CHURN.hide))
end
