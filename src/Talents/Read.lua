local ADDON, ns = ...

local Read = {}
ns.TalentRead = Read

--------------------------------------------------------------------------
-- The client's talent calls, behind one door
--
-- Every question the talent window asks the client is asked here, and nothing
-- else in the folder names a client function. That is the shape Quests/Client.lua
-- has and it is here for the same reason: the talent API is the one that moved
-- most between the two clients this addon runs on, and a window that asked
-- twelve globals in six places would break in six places on the next build.
--
-- **Three shapes of the same answer.** The anniversary client carries
-- C_SpecializationInfo, whose GetTalentInfo takes a query table and hands back a
-- record. Under it, and on the older client alone, GetTalentInfo takes a tab and
-- an index and answers a run of values, and that run itself comes in two
-- orders: the deprecated wrapper on the newer builds puts the prerequisite
-- flag seventh, the older client puts it eighth. The tab call is worse: the
-- points spent in a tree are the seventh value from C_SpecializationInfo, the
-- fifth from a GetTalentTabInfo that leads with a number, and the third from
-- one that leads with the name. Every one of those is probed at call time and
-- read by position, and the one thing no shape is trusted for is the
-- prerequisite flag, which the board works out for itself off the ranks.
--
-- **Read at call time, not at load.** Unit/Spec.lua takes GetTalentTabInfo
-- into a local when the file loads, which is the right economy for a call on
-- a ticker. Nothing here is on a ticker: a window paints when a point is spent
-- and when it opens. Reaching through _G each time costs a lookup and buys the
-- harness a way to stand the addon on the other client for one section
-- without reloading it.
--
-- **Groups are an argument everywhere, whether or not this client has them.**
-- Dual specialisation is two talent groups, one active. A client with one
-- group answers one to the count and ignores the argument on every other call,
-- so the window passes the group it is looking at down every read and the
-- client that cannot use it does not mind.
--------------------------------------------------------------------------

-- How many points a tier costs to reach. Five points in the tree opens the
-- second row, ten the third, and the client's own frame reads the same number
-- off PLAYER_TALENTS_PER_TIER.
Read.PER_TIER = 5

-- Three trees on every class this client has. Asked of the client where the
-- client answers, and this where it does not.
local TABS = 3

-- The query table C_SpecializationInfo.GetTalentInfo takes, reused. One table
-- rather than one per call, because a repaint asks forty times.
local query = {}

local function Spec()
	local spec = _G.C_SpecializationInfo
	return type(spec) == "table" and spec or nil
end

--------------------------------------------------------------------------
-- The trees
--------------------------------------------------------------------------

-- Whether this client answers about talents at all. A client that carries
-- neither door draws an empty window that says so, rather than raising.
function Read.Ready()
	local spec = Spec()
	if spec and type(spec.GetTalentInfo) == "function" then
		return true
	end
	return type(_G.GetTalentInfo) == "function"
end

function Read.Tabs()
	if type(_G.GetNumTalentTabs) == "function" then
		local count = tonumber(_G.GetNumTalentTabs(false, false))
		if count and count > 0 then
			return count
		end
	end
	return TABS
end

-- One tree: its name, its icon and the points in it, for the group asked.
--
-- The three shapes are told apart in the order they were added to the client,
-- newest first, and the legacy pair by the type of the first value, which is
-- the discriminator Unit/Spec.lua already uses.
function Read.Tree(tab, group)
	local spec = Spec()
	if spec and type(spec.GetSpecializationInfo) == "function" then
		local ok, _, name, _, icon, _, _, points = pcall(spec.GetSpecializationInfo,
			tab, false, false, nil, nil, group)
		if ok and type(name) == "string" then
			return name, icon, tonumber(points) or 0
		end
	end
	local fn = _G.GetTalentTabInfo
	if type(fn) ~= "function" then
		return nil
	end
	local first, second, third, fourth, fifth = fn(tab, false, false, group)
	if type(first) == "number" then
		return second, fourth, tonumber(fifth) or 0
	end
	if type(first) ~= "string" then
		return nil
	end
	return first, second, tonumber(third) or 0
end

-- Every point in every tree, which is what the ledger watches for a wipe.
function Read.Spent(group)
	local total = 0
	for tab = 1, Read.Tabs() do
		local _, _, points = Read.Tree(tab, group)
		total = total + (points or 0)
	end
	return total
end

--------------------------------------------------------------------------
-- The talents
--------------------------------------------------------------------------

function Read.Count(tab)
	if type(_G.GetNumTalents) == "function" then
		return tonumber(_G.GetNumTalents(tab, false, false)) or 0
	end
	return 0
end

-- One talent: name, icon, tier, column, rank, max rank, and the id the newer
-- client keys its tooltip by. Nil for an index this tab does not have.
--
-- No prerequisite flag, on purpose. The two legacy orders disagree about where
-- it sits and the board can answer the question itself off the ranks of the
-- talents Prereqs names, which is an answer that cannot be in the wrong slot.
function Read.Talent(tab, index, group)
	local spec = Spec()
	if spec and type(spec.GetTalentInfo) == "function" then
		query.specializationIndex, query.talentIndex = tab, index
		query.isInspect, query.isPet, query.groupIndex = false, false, group
		local ok, info = pcall(spec.GetTalentInfo, query)
		if ok then
			if type(info) ~= "table" or type(info.name) ~= "string" then
				return nil
			end
			return info.name, info.icon, tonumber(info.tier) or 1, tonumber(info.column) or 1,
				tonumber(info.rank) or 0, tonumber(info.maxRank) or 0, tonumber(info.talentID)
		end
	end
	local fn = _G.GetTalentInfo
	if type(fn) ~= "function" then
		return nil
	end
	local name, icon, tier, column, rank, maxRank = fn(tab, index, false, false, group)
	if type(name) ~= "string" then
		return nil
	end
	local id = select(12, fn(tab, index, false, false, group))
	return name, icon, tonumber(tier) or 1, tonumber(column) or 1,
		tonumber(rank) or 0, tonumber(maxRank) or 0, tonumber(id)
end

-- The talents this one needs first, as a flat run of tier, column pairs.
--
-- The client answers a record per prerequisite and the record is three values
-- on the older client and four on the newer, which is why the stride is read
-- off the answer rather than assumed: a run that divides by four whose fourth
-- value is not a tier is the newer shape. Nearly every talent has one
-- prerequisite or none, so the run is three or four values and the question
-- settles itself.
--
-- Only the tier and the column are handed on. Whether the prerequisite is met
-- is a fact the board already holds, and the flag in the record is the value
-- the two shapes disagree about.
function Read.Prereqs(tab, index, group)
	local fn = _G.GetTalentPrereqs
	if type(fn) ~= "function" then
		return {}
	end
	local run = { fn(tab, index, false, false, group) }
	local total = #run
	if total < 2 then
		return {}
	end
	local stride = 3
	if total % 4 == 0 and type(run[4]) ~= "number" then
		stride = 4
	end
	local pairs = {}
	for at = 1, total, stride do
		local tier, column = tonumber(run[at]), tonumber(run[at + 1])
		if tier and column then
			pairs[#pairs + 1] = tier
			pairs[#pairs + 1] = column
		end
	end
	return pairs
end

--------------------------------------------------------------------------
-- Points and groups
--------------------------------------------------------------------------

-- Points waiting to be spent in the group asked. The newer call is group
-- aware; the older one only ever knows the group you are standing in, and on
-- a client with one group that is the same answer.
function Read.Unspent(group)
	if type(_G.GetUnspentTalentPoints) == "function" then
		local ok, points = pcall(_G.GetUnspentTalentPoints, false, false, group)
		if ok and tonumber(points) then
			return tonumber(points)
		end
	end
	if type(_G.UnitCharacterPoints) == "function" then
		local ok, points = pcall(_G.UnitCharacterPoints, "player")
		if ok and tonumber(points) then
			return tonumber(points)
		end
	end
	return 0
end

-- How many talent groups this character has, and which one is live. One and
-- one on a client with no dual specialisation, which is what the window reads
-- as "no strip".
function Read.Groups()
	local count = 1
	if type(_G.GetNumTalentGroups) == "function" then
		local ok, answer = pcall(_G.GetNumTalentGroups, false, false)
		if ok and tonumber(answer) and tonumber(answer) > 1 then
			count = tonumber(answer)
		end
	end
	if count < 2 then
		return 1, 1
	end
	local active = 1
	local spec = Spec()
	if spec and type(spec.GetActiveSpecGroup) == "function" then
		local ok, answer = pcall(spec.GetActiveSpecGroup, false, false)
		if ok and tonumber(answer) then
			active = tonumber(answer)
		end
	elseif type(_G.GetActiveTalentGroup) == "function" then
		local ok, answer = pcall(_G.GetActiveTalentGroup, false, false)
		if ok and tonumber(answer) then
			active = tonumber(answer)
		end
	end
	return count, active
end

--------------------------------------------------------------------------
-- The two calls that change something
--------------------------------------------------------------------------

-- Spends a point. True when the client was asked, which is not the same as
-- the point landing: the client refuses in its own way and says so with
-- PLAYER_LEARN_TALENT_FAILED, and the repaint reads whatever it decided.
function Read.Learn(tab, index, group)
	if type(_G.LearnTalent) ~= "function" then
		return false
	end
	local ok = pcall(_G.LearnTalent, tab, index, false, group)
	return ok
end

-- Makes the other group the live one. The client casts a spell to do it, which
-- takes a few seconds and is refused in a fight, and the window hears the
-- change through ACTIVE_TALENT_GROUP_CHANGED rather than assuming it.
function Read.Activate(group)
	local spec = Spec()
	if spec and type(spec.SetActiveSpecGroup) == "function" then
		return pcall(spec.SetActiveSpecGroup, group)
	end
	if type(_G.SetActiveTalentGroup) == "function" then
		return pcall(_G.SetActiveTalentGroup, group)
	end
	return false
end

--------------------------------------------------------------------------
-- The tooltip
--------------------------------------------------------------------------

-- What the client's tooltip setter wants to be handed, decided once.
--
-- SetTalent took a tab and an index on every client until the anniversary
-- build, which keys it by the talent's id instead. Neither is documented for
-- 2.5.6 and a wrong guess is a box describing the wrong talent, so the first
-- hover asks both ways and keeps whichever one wrote this talent's own name on
-- its first line. False once both have been tried and neither did, which is a
-- box that carries the addon's lines and no description under them.
local shape

function Read.TipArgs(tab, index, id, name)
	if shape == nil then
		local Scan = ns.UI.Scan
		local lines = Scan.Read("talent", tab, index)
		if lines and lines[1] and lines[1][1] == name then
			shape = "index"
		elseif id and id > 0 then
			lines = Scan.Read("talent", id, false)
			shape = (lines and lines[1] and lines[1][1] == name) and "id" or false
		else
			shape = false
		end
	end
	if shape == "index" then
		return tab, index
	end
	if shape == "id" and id then
		return id, false
	end
	return nil
end

-- Forgotten, for the harness, which stands the addon on the other client
-- without reloading it.
function Read.ForgetTipShape()
	shape = nil
end

function Read.Describe()
	local spec = Spec()
	if spec and type(spec.GetTalentInfo) == "function" then
		return "read through C_SpecializationInfo"
	end
	if type(_G.GetTalentInfo) == "function" then
		return "read through GetTalentInfo"
	end
	return "this client answers no talent call"
end
