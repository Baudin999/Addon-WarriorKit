local ADDON, ns = ...

local Skills = {}
ns.CharSkills = Skills

--------------------------------------------------------------------------
-- Your skills, as bars rather than as a list of numbers
--
-- The client's own skill tab is right about what to show and wrong about how.
-- Every line is a name, a bar and two numbers, and the two numbers are the only
-- thing on the line that says anything, because the bar is the same length on
-- a weapon skill you have capped and a profession you started this morning.
-- What you actually want to know is which of them are behind, and that is one
-- comparison the client never makes.
--
-- So every row here carries how far along it is as a fraction, and a weapon
-- skill under the cap for your level carries a sentence saying what that is
-- costing you. It is the same number the hit and miss page is computed from,
-- said in the place you would go looking for it.
--
-- **A weapon skill is told from a profession by what it caps at, not by what
-- its header is called.** Every header on this page is a localised string and
-- matching on one is how an addon works in English and lists nothing at all in
-- German. A weapon skill caps at five times your level and cannot be
-- abandoned; a profession caps at a multiple of seventy-five and can. The two
-- tests together are wrong only for a character at exactly level fifteen with a
-- profession at its first cap, which draws one extra sentence and nothing else.
--
-- **Reading the list expands the client's headers.** There is no way to
-- enumerate the skills under a collapsed header, so they are expanded, once,
-- before the first read. That is a write to the client's own state and it is
-- worth saying out loud: the only thing that reads it back is the client's own
-- skill frame, which this part puts in the attic.
--------------------------------------------------------------------------

local expanded = false

local function Ask(name, ...)
	local call = _G[name]
	if type(call) ~= "function" then
		return nil
	end
	local ok, a, b, c, d, e, f, g, h = pcall(call, ...)
	if not ok then
		return nil
	end
	return a, b, c, d, e, f, g, h
end

-- Every header open, once per session. Zero is the client's own word for all of
-- them, and a client that will not take it is a client where whatever was
-- already open is what gets listed, which is a shorter page rather than a
-- broken one.
local function Expand()
	if expanded then
		return
	end
	expanded = true
	Ask("ExpandSkillHeader", 0)
end

-- What kind of line this is, from what it caps at.
local function Kind(maximum, abandonable, level)
	if maximum == nil or maximum == 0 then
		return "other"
	end
	if abandonable then
		return "profession"
	end
	if maximum == level * 5 then
		return "weapon"
	end
	return "other"
end

-- The sentence under a weapon skill, and nothing at all for one at the cap.
--
-- The number is the same one Stats.MeleeMiss is built on, asked the other way
-- round: what the shortfall adds rather than what the total comes to. Written
-- here rather than fetched from that file because what belongs to both is the
-- curve, and the curve is four constants in one place.
local function Costing(rank, maximum)
	local short = maximum - rank
	if short <= 0 then
		return nil
	end
	local base = ns.CharStats.MeleeMiss(3)
	local now = base + short * 0.6
	return ("%d points short. Against a boss that is %.2f%% to miss rather than %.2f%%.")
		:format(short, now, base)
end

--------------------------------------------------------------------------

-- Every skill line, grouped under the client's own headers, in the shape the
-- readout pane draws: a title and a list of rows, each row a label, a value, an
-- optional sentence and an optional fraction that becomes a bar.
function Skills.Groups()
	Expand()
	local level = Ask("UnitLevel", "player") or 1
	local count = Ask("GetNumSkillLines") or 0
	local groups, current = {}, nil

	for index = 1, count do
		local name, header, _, rank, temporary, modifier, maximum, abandonable =
			Ask("GetSkillLineInfo", index)
		if type(name) == "string" and name ~= "" then
			if header then
				current = { title = name, rows = {} }
				groups[#groups + 1] = current
			elseif current then
				local total = (rank or 0) + (temporary or 0) + (modifier or 0)
				local kind = Kind(maximum, abandonable, level)
				current.rows[#current.rows + 1] = {
					label = name,
					value = ("%d of %d"):format(total, maximum or total),
					fraction = (maximum and maximum > 0) and (total / maximum) or nil,
					note = kind == "weapon" and Costing(total, maximum) or nil,
				}
			end
		end
	end

	-- A header the client listed with nothing under it is a header the page
	-- would draw as a title over air.
	local kept = {}
	for index = 1, #groups do
		if #groups[index].rows > 0 then
			kept[#kept + 1] = groups[index]
		end
	end
	return kept
end

-- How many weapon skills are under the cap for your level, and by how much at
-- the worst. This is the one line the status word and the page footer both
-- want, and it is the only question about this page that is worth asking
-- without opening it.
function Skills.Behind()
	Expand()
	local level = Ask("UnitLevel", "player") or 1
	local count = Ask("GetNumSkillLines") or 0
	local behind, worst = 0, 0

	for index = 1, count do
		local _, header, _, rank, temporary, modifier, maximum, abandonable =
			Ask("GetSkillLineInfo", index)
		if not header and Kind(maximum, abandonable, level) == "weapon" then
			local short = maximum - ((rank or 0) + (temporary or 0) + (modifier or 0))
			if short > 0 then
				behind = behind + 1
				worst = math.max(worst, short)
			end
		end
	end
	return behind, worst
end

function Skills.Describe()
	local count = Ask("GetNumSkillLines")
	if not count then
		return "this client will not list them"
	end
	local behind, worst = Skills.Behind()
	if behind == 0 then
		return "every weapon skill at the cap for your level"
	end
	return ("%d weapon skill%s behind, the worst by %d points")
		:format(behind, behind == 1 and "" or "s", worst)
end
