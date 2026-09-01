local ADDON, ns = ...

local Class = ns.Class
local Spec = {}
Class.Spec = Spec

--------------------------------------------------------------------------
-- Which of your class's specs you are playing
--
-- Class.lua answers what you are. This answers what you are doing with it, and
-- it is the difference between an addon that works on one character and an
-- addon that works on the account.
--
-- The registry was one table per class, so a shaman got the enhancement bar
-- plan whatever they had spent their points on and an alt inherited the
-- warrior's debuff row because that list was saved per account. Both are the
-- same defect: the addon knew which class it was standing in and had nowhere
-- to write down which half of it.
--
-- So a class file may carry `specs`, an array of tables, and every field a
-- class registers may be written again inside one of them. Class.Of asks the
-- spec first and the class second, per field, which means a spec says only what
-- it disagrees with. A class with no specs behaves exactly as it did.
--
-- Nothing here draws, nothing here is a spell, and no part of the addon outside
-- Class/ has to know a spec exists: the eight fields are read through Class.Of
-- the way they always were and come back already swapped.
--------------------------------------------------------------------------

--------------------------------------------------------------------------
-- How the answer is arrived at
--
-- Neither of these clients has a spec. There is no GetSpecialization and
-- nothing on a unit that says "Enhancement", so the question has to be answered
-- from what the character has, and there are two readings of that.
--
--   a signature spell   an ability only one tree grants, asked with
--                       IsSpellKnown. Exact when it answers: a shaman with
--                       Shamanistic Rage spent forty one points to get it and
--                       is not elemental.
--
--   the talent trees    whichever tree has the most points in it, which
--                       Unit/Spec.lua already reads for the meter's row icons.
--                       Always answers for anyone who has committed to
--                       anything, and is what grants the signature spell in
--                       the first place.
--
-- Signature first, because it is a fact rather than a majority, and the tree
-- second because it answers for the levelling character who has fifteen points
-- in and no capstone yet. Neither answers at level nine, and that is correct:
-- nil means the class file's own fields stand, which is what shipped before
-- specs existed.
--
-- Every id in a `signature` list is a talent with one rank, which is the whole
-- reason those and not the obvious ones are the signatures. Mortal Strike says
-- arms louder than anything else a warrior owns and has six ranks, so asking
-- IsSpellKnown about it means carrying a rank table that goes stale at the next
-- trainer visit. Death Wish has one rank for the life of the character. Arms
-- has no such talent and is answered by its tree, which costs nothing.
--------------------------------------------------------------------------

local NONE = {}

local function List()
	local mine = Class.Mine()
	return mine and mine.specs or nil
end

-- Every spec your class has, in tree order, for the panel and the slash words.
-- Empty for a class that registered none, which is not an error and is the
-- shape three of the four class files were in before this was written.
function Spec.All()
	return List() or NONE
end

-- Does this character own something only this spec grants.
local function Signed(spec)
	local ranks = spec.signature or NONE
	for index = 1, #ranks do
		if IsSpellKnown(ranks[index]) then
			return true
		end
	end
	return false
end

-- Which tree has the most points, through the reader that already exists.
--
-- Unit/Spec.Own rather than Unit/Spec.Tree, and the difference is the GUID. The
-- meter keeps one answer per person and asks for yours by GUID; this asks the
-- client the same three questions with nothing keyed on anything, because at
-- login the client will happily read your own talent trees and will not always
-- name your own GUID yet. A spec that depended on the second would be a spec
-- that resolved or did not depending on whether you were in a party.
local function Tree()
	return (ns.Unit.Spec.Own())
end

local function Resolve()
	local list = List()
	if not list then
		return nil
	end

	for index = 1, #list do
		if Signed(list[index]) then
			return list[index]
		end
	end

	local tree = Tree()
	if not tree then
		return nil
	end
	for index = 1, #list do
		if list[index].tree == tree then
			return list[index]
		end
	end
	return nil
end

--------------------------------------------------------------------------
-- Holding it
--
-- Held once, including a nil, and taken again only on the event that can move
-- it. That is stricter than the rule Class.Token keeps, and it has to be.
--
-- Class.Token latches the first answer that is not nil, because a class is
-- settled for the life of the character and a nil there only ever means the
-- client has not spoken yet. A spec has a second reason to be nil: a character
-- at level nine has spent no points and owns no signature, and that is a real
-- answer rather than a client that is still waking up. Re-resolving it on every
-- ask would be three talent calls and a walk of every signature list, on the
-- swing timer's ten asks a second, for the whole of a character's first nine
-- levels.
--
-- So `asked` latches the question rather than the answer. What moves it
-- afterwards is a talent point, which is the same event that grants every
-- signature spell in every class file, and CHARACTER_POINTS_CHANGED is exactly
-- that.
--
-- Nothing is latched before PLAYER_LOGIN, and that is the guard the stricter
-- rule needs. Both readings are unreliable while the files load: the spellbook
-- is not filled in yet, so IsSpellKnown answers false about a talent you have
-- had for forty levels, and the talent trees read zero. A nil taken then and
-- kept would leave a character on their class's own fields for the session,
-- which is the same class of bug Class.Token's own rule exists to avoid, one
-- level down. Asked that early this resolves and answers without writing
-- anything down, which costs a handful of client calls on a path almost nobody
-- is on: every part of the addon reads the registry at login or later.
--------------------------------------------------------------------------

local mine, asked, live

function Spec.Mine()
	if asked then
		return mine
	end
	if not Class.Token() then
		return nil
	end
	local answer = Resolve()
	if live then
		mine, asked = answer, true
	end
	return answer
end

function Spec.Token()
	local spec = Spec.Mine()
	return spec and spec.key or nil
end

-- The addon's own word for the spec, or nil where nothing has been decided.
-- Nil rather than a phrase, because every caller puts it in a different
-- sentence and two of them drop the word entirely when there is none.
function Spec.Label()
	local spec = Spec.Mine()
	return spec and spec.label or nil
end

-- What you are, in one noun phrase, for a refusal to read out: "an enhancement
-- shaman", or "a warrior" where no spec resolved. It keeps the rule Class.Label
-- keeps, because the same five sentences put an indefinite article in front of
-- whichever of the two they get.
function Spec.Says()
	local label = Spec.Label()
	if label then
		return label .. " " .. Class.Label()
	end
	return Class.Label()
end

function Spec.Forget()
	mine, asked = nil, nil
end

--------------------------------------------------------------------------
-- A respec
--
-- The answer is taken again and the parts that hold a list are not rebuilt,
-- because they cannot be. The cooldown row is built once at login at its
-- ceiling, the options page keeps the spell names it labelled its switches
-- with, and the upkeep row hands out one table it built the first time it was
-- asked. Every one of those is a decision the addon takes at PLAYER_LOGIN on
-- purpose, and unpicking it to save a reload after a trainer visit would be
-- rebuilding the whole interface on an event that fires a handful of times in
-- a character's life.
--
-- So it says so instead, once, and only when the answer actually moved. A
-- respec that keeps you in the same tree is silent.
--------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("CHARACTER_POINTS_CHANGED")
events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		live = true
		Spec.Mine()
		return
	end

	local before = Spec.Token()
	Spec.Forget()
	local after = Spec.Token()
	if before ~= after and after then
		ns.Print(("your talents now read as %s. Type /reload to move the bars,"
			.. " the debuff row and the cooldowns over with them."):format(Spec.Says()))
	end
end)
