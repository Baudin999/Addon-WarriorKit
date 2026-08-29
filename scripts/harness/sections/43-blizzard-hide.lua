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

	-- Reached under FrameXML's parent key as well, so a client that renamed the
	-- global still loses its bar. Same frame both ways, which the pass has to
	-- take in its stride.
	check(_G.TargetFrame.spellbar == bar, "the fixture lost the parent key")
	check(Blizz.Apply() ~= false, "a second pass over the same frame refused")

	-- And off again, all the way back to where it was found.
	ns.db.hideBlizzTargetCast = false
	Blizz.Apply()
	check(bar:IsVisible(), "turning the switch off left the client's cast bar hidden")
	check(bar:GetParent() == _G.TargetFrame,
		"the cast bar came back parented somewhere other than the target frame")
	check(Attic.Held(bar) == false, "the attic is still holding a frame it handed back")

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

	-- The sweep is what turns "no call we thought of can undo this" into "nothing
	-- stays up for longer than a second". It runs inside every pass.
	check(Attic.Sweep(), "the sweep refused to put a re-parented frame back")
	check(bar:GetParent() == attic, "a frame re-parented out of the attic stayed out")
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
-- One hertz forever, so a frame the client builds later is down within a second
-- without anybody having guessed which event says so. What it must not do is
-- allocate: a pass that produces garbage once a second is a pass the collector
-- walks in the middle of a frame, which is the rule every ticker in this addon
-- is held to.
----------------------------------------------------------------------

do
	local ticker
	for _, f in ipairs(frames) do
		if f.scripts.OnUpdate and f.origin:match("UnitFrames/Blizzard") then
			ticker = f
		end
	end
	check(ticker ~= nil, "the hide pass registered no ticker")

	local function churn(ticks)
		collectgarbage("collect")
		collectgarbage("stop")
		local before = collectgarbage("count")
		for _ = 1, ticks do
			advance(1)
			ticker.scripts.OnUpdate(ticker, 1)
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
