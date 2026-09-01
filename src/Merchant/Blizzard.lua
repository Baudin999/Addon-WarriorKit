local ADDON, ns = ...

local Blizz = {}
ns.MerchantBlizzard = Blizz

--------------------------------------------------------------------------
-- Blizzard's merchant window, out of the way
--
-- The same shape as Mail/Blizzard.lua, and for the same reason, so this header
-- only writes down where the two differ and why the reason matters more here.
--
-- **It is parked, not hidden, and not caged.** MerchantFrame is not an ordinary
-- window. Standing at a vendor is a live interaction with the server, and the
-- client ends it when that frame stops being drawn: FrameXML's own handler on
-- the frame calls CloseMerchant, which is why walking out of range and pressing
-- escape both do the same thing. So the two mechanisms the rest of the addon
-- uses are both wrong here, and each is wrong in a way that looks like it works.
--
-- ns.Strip puts a region's own Hide where its Show was, and its first act is to
-- call Hide. That is the session going down.
--
-- Core/Attic.lua re-parents a frame into a room that is hidden, which is the
-- stronger guarantee everywhere else precisely because nothing the client does
-- can put the frame back on the screen. Here it is the wrong one for the same
-- reason it is wrong for the mailbox: visibility in this client is a property
-- of the parent chain, a frame whose parent is hidden stops being visible, and
-- stopping being visible is exactly what the frame's own handler reacts to. The
-- attic would close the merchant a frame after opening it, and the symptom
-- would be a window of ours with an empty rack in it.
--
-- What is left is to move it. The frame stays shown and stays parented to
-- UIParent, so the session stays up and every merchant call goes on working; it
-- is put off the side of the screen at no opacity, so it draws nothing and its
-- buttons are nowhere a cursor can reach them.
--
-- That last clause is what makes MerchantWindow.Leave load bearing. The client's
-- cross is the thing that would normally end a session and it is now off the
-- screen, so this addon's window has to end it instead, and it does, on the
-- frame's own OnHide.
--
-- **Why it has to be re-parked.** MerchantFrame is a UIPanel and the client
-- lays the panels out again whenever one opens or closes, which puts it back in
-- the middle of the screen. Opening your own bags at a vendor is enough to do
-- it. So the park is re-applied on the frame's own OnShow, through HookScript
-- rather than SetScript, because the handler already there is the client's.
--
-- **Comfort/Vendor.lua goes on working untouched, and that is not luck.** It
-- asks MerchantFrame:IsShown() before every sweep, because the call that sells
-- a bag slot *uses* it when no merchant is up. A parked frame is still shown:
-- what changed is where it is and what alpha it is drawn at, neither of which
-- that guard reads. Caging it would have kept IsShown true as well and closed
-- the session underneath, which is the failure that would have passed review.
--
-- **The switch is `hide Blizzard's merchant window`.** Off, both windows are up
-- and ours is the one in front, which is worth having while anything here is
-- unconfirmed in game: everything this addon's window cannot do, the client's
-- can, and it is one tick box away.
--------------------------------------------------------------------------

-- Far enough right that nothing of the client's window shows, and anchored to
-- the screen's own edge rather than to a number, so it is off the side of a 4K
-- panel as well as a laptop.
local PARK = 400

local parked, hooked = false, false
local anchors = nil

local function Frame()
	local frame = _G.MerchantFrame
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

-- Whether the client has put it back on the screen since the last pass.
--
-- Read rather than written, which is what lets the re-park sit on a once-a-
-- second walk without being a write per second forever. The frame is parked off
-- the right hand edge, so anything whose left edge is inside the screen has
-- been moved back by somebody, and a client that will not answer either
-- question is one this cannot make a claim about and leaves alone.
local function Drifted(frame)
	local left, edge = frame:GetLeft(), UIParent:GetRight()
	if not left or not edge then
		return false
	end
	return left < edge or (frame:GetAlpha() or 0) > 0
end

local function Repark()
	local frame = Frame()
	if not frame or not Drifted(frame) then
		return false
	end
	Move(frame)
	return true
end

--------------------------------------------------------------------------

-- Whether the client's window should be out of the way right now. Three things
-- have to hold, and the third is what keeps this safe: ours has to be open, or
-- there would be no merchant window on the screen at all.
function Blizz.Wanted()
	return (ns.db.merchant and ns.db.merchantHideBlizz
		and ns.MerchantWindow.Shown()) and true or false
end

-- Walked on every pass rather than only when the switch moves, and always true.
--
-- Both halves are Bags/Blizzard.lua's argument. The pass reads false as work a
-- combat lockdown refused and puts the whole thing on the PLAYER_REGEN_ENABLED
-- retry, and nothing here can be refused that way: moving an unprotected frame
-- and setting its alpha are allowed in a fight. So the guard is inside rather
-- than in the return, and what it guards on is whether the frame has actually
-- moved, which is two reads.
function Blizz.Apply()
	local wanted = Blizz.Wanted()
	if wanted ~= parked then
		parked = wanted
		if wanted then
			Park()
		else
			Unpark()
		end
		return true
	end
	if wanted then
		Repark()
	end
	return true
end

function Blizz.Parked()
	return parked
end

function Blizz.Describe()
	if not ns.db.merchantHideBlizz then
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

-- On the once-a-second pass, beside Mail/Blizzard.lua, which is on it for the
-- same reason: the client relays its panels out whenever one opens, and a park
-- applied only when the switch moves is a park that lasts until the next time
-- you open your bags.
ns.BlizzHide.Also(Blizz.Apply)
