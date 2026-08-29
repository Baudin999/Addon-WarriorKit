-- The experience and reputation rails
--
-- Two bars along the bottom of the screen, and almost everything worth checking
-- about them is a state the client puts them in rather than a pixel. So this
-- section drives the fixture through the five: partway through a level with a
-- rested pool, the same level with the pool spent, a level landing between two
-- readings, the level cap, and a character watching no faction.
--
-- What is asserted, in the order it is written:
--
--   The shape. Two rails stacked with the gap between them, the frame exactly
--   as tall as what is in it, and both of them on the pixel grid.
--
--   That a rail with nothing to say is not there. The frame is the height of
--   one rail at the level cap and the height of one rail with no faction
--   watched, and there is no frame at all when both are true. A bar drawn empty
--   would be a claim about a character who has run out of things to earn.
--
--   The rested pool, which is the one region here that is placed by hand. It
--   starts where the fill ends and it is clamped at the end of the level,
--   because a week away is a pool bigger than the level and drawn unclamped it
--   would hang off the end of the rail.
--
--   The session clock, which is this addon's arithmetic and not the client's.
--   The level up is the case worth writing a test for: experience goes down
--   rather than up, and read as a plain difference it is a large negative that
--   would say you are earning backwards.
--
--   Both shapes of the watched faction. The older clients answer five values
--   and the newer ones a table with different field names, and this addon ships
--   for a client where it is genuinely either. The fixture starts with the
--   first and this section installs the second.
--
--   That nothing here runs on a ticker. Every other readout in the addon draws
--   on one; this one is asserted not to have one, because that is the claim the
--   file's head makes and the reason none of its functions is in check.sh's HOT
--   list.

local H = ...
local ns, check, fire, frames = H.ns, H.check, H.fire, H.frames
local progress = H.progress

do
	local Progress, Rails = ns.Progress, ns.ProgressRails
	local Box = ns.UI.Tooltip

	local frame = _G.WarriorKitProgress
	check(frame ~= nil, "no experience frame came up")

	local xp, faction = Rails.Bar("xp"), Rails.Bar("faction")
	check(xp ~= nil and faction ~= nil, "the part built fewer than two rails")

	-- The fixture, put back at the end of every scene that moves it, so the
	-- assertions read in the order they are written rather than against
	-- whatever the last one left behind.
	local function scene()
		progress.xp, progress.max, progress.rested = 12000, 40000, 8000
		progress.disabled, progress.ceiling = false, 70
		progress.faction = { name = "Thrallmar", standing = 6,
			low = 6000, high = 12000, value = 8400 }
		fire("UPDATE_FACTION")
		Rails.Apply()
	end
	scene()

	------------------------------------------------------------------
	-- The shape
	------------------------------------------------------------------

	check(math.abs(ns.UI.Pixel(frame) - 1) < 1e-9,
		("the rails are not on the grid: one pixel is %.4f units")
			:format(ns.UI.Pixel(frame)))
	check(frame:GetWidth() == ns.db.progressWidth,
		("the frame is %.1f px wide, the setting says %d")
			:format(frame:GetWidth(), ns.db.progressWidth))

	local height = ns.db.progressHeight
	check(xp:GetHeight() == height and faction:GetHeight() == height,
		"a rail is not the height the setting says")
	check(frame:GetHeight() == height * 2 + 2,
		("two rails and the gap should be %d px and the frame is %.1f")
			:format(height * 2 + 2, frame:GetHeight()))

	-- The experience rail on top and the reputation rail under it, which is the
	-- order this game has always drawn them in.
	local _, _, _, _, top = xp:GetPoint()
	local _, _, _, _, under = faction:GetPoint()
	check(top == 0 and under == -(height + 2),
		("the two rails are at %s and %s, and the second should hang under the first")
			:format(tostring(top), tostring(under)))

	------------------------------------------------------------------
	-- What each rail says
	------------------------------------------------------------------

	check(xp:GetValue() == 12000, ("the experience rail reads %s of the level")
		:format(tostring(xp:GetValue())))
	local _, ceiling = xp:GetMinMaxValues()
	check(ceiling == 40000, ("the rail counts to %s and the level costs 40000")
		:format(tostring(ceiling)))

	-- Band relative, not scale relative. The client answers 8400 out of a band
	-- that runs from 6000 to 12000, and 8400 out of 12000 would draw a rail
	-- most of the way along a standing you have barely started.
	local name, standing, into, span = Progress.Faction()
	check(name == "Thrallmar" and standing == 6,
		"the watched faction did not come back off the five value shape")
	check(into == 2400 and span == 6000,
		("the standing reads %s of %s and the band is 2400 of 6000")
			:format(tostring(into), tostring(span)))
	check(faction:GetValue() == 2400, "the reputation rail is not drawing the band")

	-- The client's own word where it has one, and this addon's where it has not.
	check(Progress.Standing(6) == "Honored",
		"the client's own standing label was not preferred: " .. Progress.Standing(6))
	check(Progress.Standing(8) == "exalted",
		"a standing the client names nothing for did not fall back: " .. Progress.Standing(8))
	check(Progress.Band(2) == "hostile" and Progress.Band(4) == "neutral"
		and Progress.Band(6) == "friendly",
		"the eight standings do not fold onto the three reaction colours")

	------------------------------------------------------------------
	-- The rested pool, which is the one region placed by hand
	------------------------------------------------------------------

	do
		local width = ns.db.progressWidth
		local pool = xp.rested
		check(pool ~= nil, "the experience rail draws no rested pool at all")

		-- 12000 of 40000 is three tenths along the rail, and 8000 rested is a
		-- fifth of it. The pool starts where the fill ends, which is the whole
		-- of what it is saying.
		check(pool:IsShown(), "a character with 8000 rested is drawing no pool")
		check(pool:GetWidth() == 96,
			("the pool is %.1f px of a %d px rail and a fifth of it is 96")
				:format(pool:GetWidth(), width))
		local _, _, _, offset = pool:GetPoint()
		check(offset == 144,
			("the pool starts at %s and the fill ends at 144"):format(tostring(offset)))

		-- Bigger than the rest of the level, which is what a week away looks
		-- like. Clamped at the end of the rail, or it hangs off it.
		progress.rested = 999999
		fire("UPDATE_EXHAUSTION")
		check(pool:GetWidth() == width - 144,
			("a pool bigger than the level drew %.1f px on a %d px rail")
				:format(pool:GetWidth(), width))

		-- And spent, it is not drawn at all rather than drawn one pixel wide.
		progress.rested = nil
		fire("UPDATE_EXHAUSTION")
		check(not pool:IsShown(), "a spent rested pool is still drawing")
		scene()

		-- The two strings, which are the reading a player actually takes off
		-- the rail without hovering anything.
		check(xp.left:GetText() == "level 62",
			"the experience rail does not say what level you are: " .. tostring(xp.left:GetText()))
		check(xp.right:GetText() == "12,000 / 40,000  30%",
			"the count on the experience rail reads " .. tostring(xp.right:GetText()))
		check(faction.left:GetText() == "Thrallmar",
			"the reputation rail does not name the faction: " .. tostring(faction.left:GetText()))
		check(faction.right:GetText() == "Honored  2,400 / 6,000",
			"the count on the reputation rail reads " .. tostring(faction.right:GetText()))
	end

	------------------------------------------------------------------
	-- The session clock
	------------------------------------------------------------------

	do
		local started = Progress.Gained()

		progress.xp = 14000
		fire("PLAYER_XP_UPDATE")
		check(Progress.Gained() == started + 2000,
			("2000 experience read as %s"):format(tostring(Progress.Gained() - started)))

		-- The level lands. The client now answers a smaller number against a
		-- bigger level, and what was earned is the rest of the old level plus
		-- what carried into the new one: 26000 to finish the level and 500 into
		-- the next.
		progress.xp, progress.max = 500, 45000
		fire("PLAYER_LEVEL_UP")
		check(Progress.Gained() == started + 2000 + 26500,
			("a level landing between two readings counted %s rather than 26500")
				:format(tostring(Progress.Gained() - started - 2000)))
		scene()
		-- And the reading after the reset does not count the drop back down as
		-- earnings of its own.
		local settled = Progress.Gained()
		fire("PLAYER_XP_UPDATE")
		check(Progress.Gained() == settled,
			"putting the fixture back counted as experience earned")
	end

	------------------------------------------------------------------
	-- A rail with nothing to say is not drawn
	------------------------------------------------------------------

	do
		-- The level cap, which is the state the experience rail exists to not
		-- be in. The frame is the reputation rail alone and it is at the top of
		-- the frame rather than hanging under a gap where the other one was.
		progress.ceiling = 62
		fire("PLAYER_XP_UPDATE")
		check(Progress.Experience() == nil, "the level cap still answers an experience reading")
		check(frame:GetHeight() == height,
			("at the cap the frame is %.1f px and one rail is %d")
				:format(frame:GetHeight(), height))
		check(not xp:IsShown(), "the experience rail is drawn at the level cap")
		local _, _, _, _, y = faction:GetPoint()
		check(y == 0, "the reputation rail is still hanging under a rail that is not there")

		-- And with nothing watched either, there is no frame on the screen.
		progress.faction = nil
		fire("UPDATE_FACTION")
		check(not frame:IsShown(),
			"nothing to count and no faction watched still draws a frame")

		-- Unlocked, both rails come back whatever the client says, because
		-- "unlock the frames and drag it" has to mean dragging a rectangle you
		-- can see. This is the one state where the picture is not the reading.
		local shipped = ns.db.locked
		ns.db.locked = false
		Rails.Lock()
		check(frame:IsShown() and xp:IsShown() and faction:IsShown(),
			"unlocking the frames left nothing on the screen to drag")
		ns.db.locked = shipped
		Rails.Lock()
		check(not frame:IsShown(), "locking again left the empty rails on the screen")

		-- A character with experience switched off is the same answer by
		-- another route, which is worth its own line because it is the one of
		-- the three that is a setting rather than a level.
		progress.ceiling, progress.disabled = 70, true
		fire("PLAYER_XP_UPDATE")
		check(Progress.Experience() == nil,
			"experience switched off still answers a reading")
		progress.disabled = false
		scene()
		check(frame:IsShown() and xp:IsShown() and faction:IsShown(),
			"both rails did not come back when the fixture did")
	end

	------------------------------------------------------------------
	-- The newer clients' shape
	--
	-- Same reading, different call and different field names. Installed here
	-- rather than in the fixture so that both halves of the fold are reached
	-- from a run that started without it, which is the way a client that has
	-- both would be met.
	------------------------------------------------------------------

	do
		_G.C_Reputation = {
			GetWatchedFactionData = function()
				return { name = "Cenarion Expedition", reaction = 7,
					currentStanding = 15000, currentReactionThreshold = 12000,
					nextReactionThreshold = 21000 }
			end,
		}
		fire("UPDATE_FACTION")
		local name, standing, into, span = Progress.Faction()
		check(name == "Cenarion Expedition" and standing == 7,
			"the table shape was not preferred over the five value one")
		check(into == 3000 and span == 9000,
			("the table shape folded to %s of %s rather than 3000 of 9000")
				:format(tostring(into), tostring(span)))
		_G.C_Reputation = nil
		fire("UPDATE_FACTION")
		check(select(1, Progress.Faction()) == "Thrallmar",
			"taking the newer call away did not fall back to the older one")
	end

	------------------------------------------------------------------
	-- The twenty segments
	------------------------------------------------------------------

	do
		local function drawn()
			local count = 0
			for _, mark in ipairs(xp.marks) do
				if mark:IsShown() then
					count = count + 1
				end
			end
			return count
		end

		ns.db.progressBubbles = true
		ns.db.progressWidth = 480
		Rails.Apply()
		check(drawn() == 19,
			("%d of the nineteen segment marks are drawn on a 480 pixel rail"):format(drawn()))

		-- Under the floor they come off on their own, whatever the setting says,
		-- because twenty marks on a narrow rail is hatching rather than
		-- division.
		ns.db.progressWidth = 140
		Rails.Apply()
		check(drawn() == 0, ("%d marks are still drawn on a 140 pixel rail"):format(drawn()))

		ns.db.progressWidth = ns.DefaultFor("progressWidth")
		ns.db.progressBubbles = false
		Rails.Apply()
		check(drawn() == 0, "the marks are drawn with the setting off")

		ns.db.progressBubbles = ns.DefaultFor("progressBubbles")
		Rails.Apply()
	end

	------------------------------------------------------------------
	-- What a hover says
	------------------------------------------------------------------

	do
		scene()
		xp.scripts.OnEnter(xp)
		check(Box.IsShown(), "hovering the experience rail opened nothing")
		local said = {}
		for index = 1, Box.Lines() do
			said[index] = Box.Text(index) or ""
		end
		check(said[1] == "Experience", "the box is not titled: " .. tostring(said[1]))
		-- Every line is a pair, which is what UI/Tip.lua draws when a spec has
		-- two entries in it, so the label is what comes back off the box and
		-- the number sits opposite it.
		local rested, level, session = false, false, false
		for _, line in ipairs(said) do
			rested = rested or line == "Rested"
			level = level or line == "Level 62"
			session = session or line == "This session"
		end
		check(level, "the hover does not say what level you are")
		check(rested, "the hover does not mention the rested pool it is drawing")
		check(session, "the hover says nothing about what the session is earning")
		xp.scripts.OnLeave(xp)
	end

	------------------------------------------------------------------
	-- Blizzard's own, and no ticker of ours
	------------------------------------------------------------------

	do
		local bar = _G.MainMenuExpBar
		check(bar ~= nil, "the fixture stands up no experience bar of the client's")
		check(ns.db.hideBlizzXP, "the switch that takes the client's bars down ships off")
		ns.BlizzHide.Apply()
		check(bar:IsVisible() == false,
			"the client's own experience bar is on the screen under ours")
		check(ns.Attic.Held(bar), "the client's experience bar is hidden but not caged")

		for _, f in ipairs(frames) do
			if f.scripts.OnUpdate and f.origin:match("Progress/") then
				check(false, "the rails registered a ticker, and they draw on events")
			end
		end
	end

	print(("xp     %s"):format(Rails.Describe()))
	print(("xp     %s"):format(Progress.Describe()))
end
