local ADDON, ns = ...

local Class = {}
ns.Class = Class

--------------------------------------------------------------------------
-- What the addon knows about a class
--
-- Six things in this addon are facts about a warrior rather than facts about
-- Warcraft: the three stance spells, the three abilities the charge button
-- casts, the two abilities a fight hands you, Slam, Battle Shout on the upkeep
-- row, and the bar plan. Until now each lived in the file that used it and each
-- asked ns.IsWarrior for itself, so the addon knew it was a warrior addon in
-- six places and there was nowhere to write down a seventh class.
--
-- So a class is one table, registered from one file, and the parts read fields
-- off it. Class\Warrior.lua is the whole of what this addon knows about a
-- warrior and nothing outside it names a warrior spell.
--
-- The split is between facts and mechanism, and it is the only rule here worth
-- stating. A class file holds ids, names and plans. It holds no frames, no
-- events and no drawing. The charge button's camera aiming, the reaction
-- windows' combat log parse and the loadout's cursor handling are mechanism and
-- stay where they are, because they are the same code whoever is standing in
-- them.
--
-- A class that registers nothing is a supported class. It gets the ten parts of
-- the addon that never ask, and the parts that do ask find no field and do not
-- build. That is what makes adding a class additive: one file, no edits
-- anywhere else.
--------------------------------------------------------------------------

-- Every class that has signed in, by token. Written at load and never after.
local defs = {}

--------------------------------------------------------------------------
-- The two constructors a loadout is built out of
--
-- Here rather than in Buttons\Layout.lua because every class file writes a plan
-- and none of them may name a file outside Class\. Each cell of a plan is
-- { kind, name }, where kind is "spell" or "macro" and nil is a slot the plan
-- leaves alone.
--
-- Names are English because this install is enUS. A localised client needs the
-- names swapping, which is the one thing about a plan that is not locale-proof.
--------------------------------------------------------------------------

function Class.Spell(name)
	return { kind = "spell", name = name }
end

function Class.Macro(name)
	return { kind = "macro", name = name }
end

--------------------------------------------------------------------------
-- Signing in
--------------------------------------------------------------------------

-- One call per class file, at load. Two files claiming the same token is a bug
-- in the addon rather than a state to recover from, so it is an error at load
-- and not a silent overwrite: the second table would win, the first would go
-- quiet, and nothing on screen would say which.
--
-- label is the addon's own word for the class, lower case, and it is what the
-- refusals read out. The client's own localised name is Class.Name and is what
-- the rail is titled with, because a rail entry is a proper noun and a sentence
-- in the middle of a refusal is not.
function Class.Register(token, def)
	assert(type(token) == "string" and token ~= "",
		"a class registered without a token")
	assert(not defs[token],
		("two class files registered %s"):format(token))
	assert(type(def) == "table" and type(def.label) == "string",
		("%s registered no label"):format(token))
	def.token = token
	defs[token] = def
end

--------------------------------------------------------------------------
-- Which class this is
--
-- Held once the client has answered, and asked again every time until it has.
--
-- Both halves matter. Class data is not reliable while the files load, so an
-- answer taken then would be nil, and a nil written down once would lock a
-- warrior out of the charge button for the rest of the session. That is the bug
-- this used to guard against by never holding anything at all.
--
-- Never holding anything is the wrong price now. The swing timer asks what you
-- are on the way to deciding where a band goes, which is ten times a second, and
-- a character does not change class between two of those. So the first answer
-- that is not nil is the answer, and every call after it is a local read.
--
-- The guard on the rest of the addon is when it asks, not what this returns.
-- Ask at PLAYER_LOGIN or later, never at file scope, and never cache the answer
-- of your own. A nil here does not mean no, it means the client has not said
-- yet, so anything that would turn a nil into a decision it then writes down
-- has to ask for the token first: Loadouts\Loadouts.lua is the one place in the
-- addon that keeps such an answer, and it is the one place that checks.
--
-- There was a Class.Is(want) here that answered true on a nil for that reason,
-- and nothing called it. Every part that decides at login goes through Class.Of,
-- which answers nil, so the guard sat in a function outside the path while the
-- path itself had none. Timing and that one explicit check are the guard.
--------------------------------------------------------------------------

local token

function Class.Token()
	if token then
		return token
	end
	token = (select(2, UnitClass("player")))
	return token
end

-- The client's own name for the class, in the language it is running in. Nil
-- while the client will not say, which is the same moment Token is nil.
function Class.Name()
	return (UnitClass("player"))
end

--------------------------------------------------------------------------
-- What this character's class brought
--
-- Mine is nil for a class no file has been written for, and Of is nil for a
-- field that class did not fill in. Both are asked on demand rather than held
-- at login, because both are a table lookup on top of Token and Token is the
-- one thing here worth holding.
--
-- Nil is the whole gate. A part that wants a fact asks for it, gets nil, and
-- does not build: no frame, no ticker, no page, and no setting that writes a
-- value nothing on this character reads.
--------------------------------------------------------------------------

function Class.Mine()
	local mine = Class.Token()
	return mine and defs[mine] or nil
end

function Class.Of(field)
	local mine = Class.Mine()
	return mine and mine[field] or nil
end

-- The addon's own word for what you are, for a refusal to read out. Falls back
-- to the client's name for a class no file has been written for, and to a
-- phrase for the moment before the client will say, because a refusal that
-- names nothing reads as a bug in the addon rather than an answer about you.
--
-- Whatever comes back has to be a noun phrase that follows an indefinite
-- article, because five of the sentences that read it put one in front: "a
-- warrior", "a mage", and before the client answers, "a character of unknown
-- class". The last fallback used to be "this character", so all five read "a
-- this character" for as long as the client stayed quiet. Section 21 gates the
-- shape rather than the words.
function Class.Label()
	local mine = Class.Mine()
	if mine then
		return mine.label
	end
	return Class.Name() or "character of unknown class"
end

-- Every class that has signed in, for the one caller that has to look past your
-- own: a slash word that belongs to another class is worth naming as such, and
-- falling through to the bare on|off toggle instead would switch a whole
-- feature off and report that it had done something else. Read only.
function Class.All()
	return defs
end
