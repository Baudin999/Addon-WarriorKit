local ADDON, ns = ...

local Blizz = {}
ns.MailBlizzard = Blizz

--------------------------------------------------------------------------
-- Blizzard's mail window, out of the way
--
-- **It is parked, not hidden, and that distinction is the whole file.**
--
-- MailFrame is not an ordinary window. The mailbox is a live interaction with
-- the server, and the client ends it when that frame stops being drawn:
-- TitanPost secure-hooks MailFrame_Hide for exactly that signal, which is how
-- you know hiding is the thing that closes the mailbox rather than a
-- consequence of it. The client's own MAIL_SHOW handler makes the same point
-- from the other side, calling CloseMail when ShowUIPanel could not find room
-- for the frame.
--
-- So this part uses neither of the two mechanisms the rest of the addon uses,
-- and the next person to read this file will want to change that. Both would
-- close the mailbox.
--
-- ns.Strip puts a region's own Hide where its Show was, and its first act is to
-- call Hide. That is the frame going down.
--
-- Core/Attic.lua re-parents a frame into a room that is hidden, which is the
-- better mechanism everywhere else precisely because nothing the client does
-- can put the frame back on the screen. Here it is the wrong one for the same
-- reason: visibility in this client is a property of the parent chain, a frame
-- whose parent is hidden stops being visible, and stopping being visible is
-- what MailFrame's own handler reacts to. The attic is a stronger guarantee
-- than parking and this is the one frame that must not have it.
--
-- What is left is to move it. The frame stays shown and stays parented to
-- UIParent, so the interaction stays up and every mail API goes on working; it
-- is put off the side of the screen at no opacity, so it draws nothing and its
-- buttons are nowhere a cursor can reach them. Every one of those is reversible
-- in one call and none of them touches the frame's shown state or its parent.
--
-- The cost against the attic is honest and is why this is not the default
-- anywhere else: a client that repositions the frame between our re-parks puts
-- it back on the screen, where the attic could not. That failure is visible
-- rather than silent, and `/wk mail hide off` is the way out of it.
--
-- **Why it has to be re-parked.** MailFrame is a UIPanel and the client lays
-- the panels out again whenever one opens or closes, which puts it back in the
-- middle of the screen. So the park is re-applied on the frame's own OnShow,
-- through HookScript rather than SetScript, because the handler already there
-- is the client's and taking it off would be taking the mailbox with it.
--
-- **The switch is `hide Blizzard's mail window`.** Off, both windows are up and
-- ours is the one in front, which is worth having while anything here is still
-- unconfirmed in game: everything this addon's window cannot do, the client's
-- can, and it is one tick box away.
--------------------------------------------------------------------------

-- Far enough right that nothing of a four hundred pixel window shows, and
-- anchored to the screen's own edge rather than to a number, so it is off the
-- side of a 4K panel as well as a laptop.
local PARK = 400

local parked, hooked = false, false
local anchors = nil

local function Frame()
	local frame = _G.MailFrame
	if type(frame) ~= "table" or type(frame.SetPoint) ~= "function" then
		return nil
	end
	return frame
end

-- Where the client had it, recorded once before it is ever moved. Restoring the
-- points it actually had beats putting it back at a number this file guessed,
-- and the client relays it on the next show anyway.
local function Remember(frame)
	if anchors or type(frame.GetNumPoints) ~= "function" then
		return
	end
	anchors = {}
	for index = 1, frame:GetNumPoints() do
		local point, relative, relativePoint, x, y = frame:GetPoint(index)
		anchors[index] = { point, relative, relativePoint, x, y }
	end
end

local function Move(frame)
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", UIParent, "TOPRIGHT", PARK, 0)
	frame:SetAlpha(0)
end

local function Park()
	local frame = Frame()
	if not frame then
		return false
	end
	Remember(frame)
	-- A clamped frame snaps back onto the screen, which would undo the move and
	-- leave a window at no opacity swallowing clicks in the middle of the game.
	if type(frame.SetClampedToScreen) == "function" then
		frame:SetClampedToScreen(false)
	end
	Move(frame)

	if not hooked and type(frame.HookScript) == "function" then
		hooked = pcall(frame.HookScript, frame, "OnShow", function(this)
			if parked then
				Move(this)
			end
		end)
	end
	return true
end

local function Unpark()
	local frame = Frame()
	if not frame then
		return false
	end
	frame:SetAlpha(1)
	if anchors then
		frame:ClearAllPoints()
		for index = 1, #anchors do
			local held = anchors[index]
			frame:SetPoint(held[1], held[2], held[3], held[4], held[5])
		end
	end
	return true
end

--------------------------------------------------------------------------

-- Whether the client's window should be out of the way right now. Three things
-- have to hold, and the third is what keeps this safe: ours has to be open, or
-- there would be no mail window on the screen at all.
function Blizz.Wanted()
	return (ns.db.mail and ns.db.mailHideBlizz and ns.MailWindow.Shown()) and true or false
end

function Blizz.Apply()
	local wanted = Blizz.Wanted()
	if wanted == parked then
		return false
	end
	parked = wanted
	if wanted then
		return Park()
	end
	return Unpark()
end

function Blizz.Parked()
	return parked
end

function Blizz.Describe()
	if not ns.db.mailHideBlizz then
		return "on screen"
	end
	if not parked then
		return "on screen while this window is closed"
	end
	if not hooked then
		return "moved aside, and this client would not let the addon keep it there"
	end
	return "moved aside"
end
