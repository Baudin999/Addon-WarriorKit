-- What login built
--
-- Every other section opens something, so this is the only place in the run
-- that can say what the addon costs before anybody has asked it for anything.
-- It runs first and it asserts one thing per part that used to build itself at
-- login and no longer does.
--
-- The readings are taken in the runner, straight after the two login events,
-- and handed over as H.login. Taking them here would be too late: loading this
-- file is already after the fact for anything a section above it did, and there
-- is nothing above it on purpose.
--
-- Nothing here opens a window or turns a switch on. The other half of each
-- claim, that the thing does exist once something has asked for it, belongs to
-- the section that asks: 52-character opens the sheet, 68-spellbook opens the
-- book.
--
-- What this cannot prove: that the client agrees any of it is cheap. What it
-- says is that the call was not made, which is the only half a stub can answer
-- for.

local H = ...
local check = H.check
local login = H.login

----------------------------------------------------------------------
-- The two windows the key has to be able to open in a fight
--
-- Both are built at login because a snippet may only touch a frame it has been
-- handed a reference to, and neither the frame nor the reference can be made
-- in combat. What waited is the work behind them: the sheet's two paints and
-- its figure, and the book's walk of every rank of every spell.
----------------------------------------------------------------------

check(login.durability == 0,
	("login read %d gear slots for a character sheet nobody had opened")
		:format(login.durability))

check(login.models == 0,
	("login loaded %d player models"):format(login.models))

check(login.book == 0,
	("login read %d spell book entries for a window nobody had opened")
		:format(login.book))
