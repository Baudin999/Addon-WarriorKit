-- Which other addons are running
--
-- One call, and the whole of it: IsAddOnLoaded answers out of a set of folder
-- names. Two things in the addon ask it. Chat/Voice.lua asks whether the
-- client's own Channels module is in memory, and ns.AddOnRunning asks whether
-- somebody else's addon is, which is what Core/Replaced.lua's notice is built
-- on. Both read one list here rather than one stub each, because "is this
-- loaded" is one question however different the two callers are.
--
-- Blizzard_Channels is in the set from the start. That module is load on demand
-- in the game, so the probe answers true and the load call is never reached; a
-- run that reached it would be testing this file's idea of LoadAddOn rather than
-- the addon. It was two lines in 07-chat.lua until this file existed, which is
-- where it was written because the voice window asked first.
--
-- Everything else in the set is a section's to write. Nothing is loaded by
-- default, because that is the install nearly every player has and the one the
-- notice has to stay quiet on.
--
-- Last, and it needs nothing at all: no frame, no geometry, and no name any
-- file above it left. It takes IsAddOnLoaded over from 07-chat.lua, which is
-- the only reason it is not first.

local H = ...

local loaded = { Blizzard_Channels = true }

-- Written by a section, read by the call below. A section that turns one on
-- calls ns.Replaced.Forget() after it, because the addon holds the answer for
-- the session on the grounds that a real client cannot change it.
H.addons = loaded

function _G.IsAddOnLoaded(name)
	return loaded[name] == true
end
