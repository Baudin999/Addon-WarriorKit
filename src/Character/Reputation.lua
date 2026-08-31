local ADDON, ns = ...

local Rep = {}
ns.CharRep = Rep

local C = ns.UI.Color

--------------------------------------------------------------------------
-- Who likes you
--
-- This tab exists because of what hiding the client's character window costs.
-- Reputation is a tab on that window, the addon is taking the window away, and
-- a replacement that quietly deletes a page the game has is not a replacement.
-- So it is here, drawn the same way the skills tab is drawn, out of the same
-- pane.
--
-- What it does not carry is the client's own at-war tick and the watched-bar
-- picker. Both are writes to a live server state off a frame this addon owns,
-- and neither is what anybody opens a reputation list to find out. Untick the
-- switch that hides the client's sheet and both are one click away, which is
-- the honest answer for two controls rather than the elaborate one.
--
-- **Reading the list expands the client's headers**, the same as the skills
-- tab and for the same reason: there is no way to enumerate what is under a
-- collapsed one. Expanding grows the list under the cursor, so the walk reads
-- the count again on every step rather than taking it once.
--------------------------------------------------------------------------

-- What the eight standings are drawn in. Three colours, not eight, and they are
-- the palette's own rather than the client's: red for somebody who would attack
-- you, grey for somebody who has no opinion, green for somebody who does. The
-- client paints eight shades between orange and blue, which is a gradient that
-- says something only if you have memorised the order.
local HOSTILE, NEUTRAL = 3, 4

local function Tone(standing)
	if standing <= HOSTILE then
		return C.stranger
	end
	if standing == NEUTRAL then
		return C.dim
	end
	return C.alt
end

local function Ask(name, ...)
	local call = _G[name]
	if type(call) ~= "function" then
		return nil
	end
	local ok, a, b, c, d, e, f, g, h, i, j, k = pcall(call, ...)
	if not ok then
		return nil
	end
	return a, b, c, d, e, f, g, h, i, j, k
end

-- The client's own word for a standing, which is a localised global and is why
-- nothing here spells out "Honored".
local function Standing(id)
	local label = _G["FACTION_STANDING_LABEL" .. tostring(id)]
	return type(label) == "string" and label or ("standing " .. tostring(id))
end

-- Every header open. The list grows underneath as they expand, so the count is
-- read again on every step and the loop is bounded by the count rather than by
-- a number taken before the first write.
local function Expand()
	local index = 1
	while index <= (Ask("GetNumFactions") or 0) do
		local _, _, _, _, _, _, _, _, header, collapsed = Ask("GetFactionInfo", index)
		if header and collapsed then
			Ask("ExpandFactionHeader", index)
		end
		index = index + 1
	end
end

local function Bar(value, low, high)
	if type(value) ~= "number" or type(low) ~= "number" or type(high) ~= "number"
		or high <= low then
		return nil
	end
	return math.max(0, math.min((value - low) / (high - low), 1))
end

--------------------------------------------------------------------------

function Rep.Groups()
	if type(_G.GetNumFactions) ~= "function" then
		return {}
	end
	Expand()

	local groups, current = {}, nil
	for index = 1, (Ask("GetNumFactions") or 0) do
		local name, _, standing, low, high, value, _, _, header, _, hasRep =
			Ask("GetFactionInfo", index)
		if type(name) == "string" and name ~= "" then
			if header and not hasRep then
				current = { title = name, rows = {} }
				groups[#groups + 1] = current
			else
				if not current then
					current = { title = "Reputation", rows = {} }
					groups[#groups + 1] = current
				end
				current.rows[#current.rows + 1] = {
					label = name,
					value = ("%s, %d of %d"):format(Standing(standing),
						(value or 0) - (low or 0), (high or 0) - (low or 0)),
					fraction = Bar(value, low, high),
					tone = Tone(standing or NEUTRAL),
				}
			end
		end
	end

	local kept = {}
	for index = 1, #groups do
		if #groups[index].rows > 0 then
			kept[#kept + 1] = groups[index]
		end
	end
	return kept
end

function Rep.Describe()
	if type(_G.GetNumFactions) ~= "function" then
		return "this client will not list them"
	end
	local exalted, known = 0, 0
	for index = 1, (Ask("GetNumFactions") or 0) do
		local _, _, standing, _, _, _, _, _, header, _, hasRep = Ask("GetFactionInfo", index)
		if not header or hasRep then
			known = known + 1
			if standing == 8 then
				exalted = exalted + 1
			end
		end
	end
	return ("%d factions, %d of them exalted"):format(known, exalted)
end
