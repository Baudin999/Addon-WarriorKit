local ADDON, ns = ...

-- The clutter window. One card, one item, two buttons.
--
-- Clutter.lua works out what is finished with and why; this file shows them one
-- at a time and is the only thing in the addon that destroys anything. Every
-- line below that looks like caution is caution: an item that goes is not
-- coming back, and there is no vendor buyback tab behind a delete.
--
-- The queue is never advanced. It is rebuilt on every press, because the bags
-- move under an open window: something loots, the vendor sweep sells, a stack
-- splits and every slot after it shifts by one. A window holding index 4 of a
-- list it took thirty seconds ago is a window pointing at whatever is in that
-- slot now, and that is the failure this cannot have.

local Destroy = {}
ns.Destroy = Destroy

local UI = ns.UI
local C, M = UI.Color, UI.Metric

local WIDTH = 320
local ICON = 32
local REASON_LINES = 3

local window, card
local queue = {}

-- Skipped for as long as the window stays open, keyed by the item's link rather
-- than its slot, because the slot is the thing that moves. Two stacks of the
-- same item are the same item, and skipping one skips both, which is what you
-- meant.
local skipped = {}

-- How many cards you have already answered, so the counter can say "3 of 7"
-- without holding a total that goes stale the moment a bag changes. The total
-- is this plus whatever is still in the queue, which is always true.
local answered = 0

-- The last destroy, so a second click landing on the card that just replaced
-- the one you meant cannot destroy it. Cheaper than a ticker and it is the
-- whole of the double-click problem.
local DEBOUNCE = 0.4
local lastTake = 0

--------------------------------------------------------------------------
-- The queue
--------------------------------------------------------------------------

local function Rebuild()
	local found, problem = ns.Clutter.Scan()
	queue = {}
	for index = 1, #found do
		if not skipped[found[index].link] then
			queue[#queue + 1] = found[index]
		end
	end
	return problem
end

local function Current()
	return queue[1]
end

--------------------------------------------------------------------------
-- Destroying one
--
-- Four checks and then the deed, and the checks are the point.
--
-- The slot is re-read and compared against the link on the card, so a bag that
-- moved since the scan fails here rather than destroying a neighbour. The item
-- is then picked up and the cursor is asked what it is actually holding, which
-- is an independent second opinion from the client itself. Only then is
-- DeleteCursorItem reached, and it is probed and pcalled because nothing
-- installed here calls it: Questie hooks it, which proves the global exists,
-- and hooking is not calling.
--------------------------------------------------------------------------

local function Take(entry)
	if ns.ContainerItemLink(entry.bag, entry.slot) ~= entry.link then
		return false, "that item is not in that slot any more"
	end

	if type(_G.ClearCursor) == "function" then
		_G.ClearCursor()
	end

	if not ns.PickupContainerItem(entry.bag, entry.slot) then
		return false, "this client will not let an addon pick an item up"
	end

	local kind, cursorId = _G.GetCursorInfo()
	if kind ~= "item" or cursorId ~= entry.id then
		if type(_G.ClearCursor) == "function" then
			_G.ClearCursor()
		end
		return false, "the cursor came up holding something else"
	end

	local delete = _G.DeleteCursorItem
	if type(delete) ~= "function" then
		_G.ClearCursor()
		return false, "this client has no DeleteCursorItem"
	end

	if not pcall(delete) then
		_G.ClearCursor()
		return false, "the client refused the delete"
	end
	return true
end

--------------------------------------------------------------------------
-- Painting
--------------------------------------------------------------------------

local function Prose(problem)
	if problem == "questie" then
		return "Questie is not answering. It carries the only map from an item to the quest it belongs to, so without it nothing here can be traced and nothing is offered."
	end
	if problem == "questlog" then
		return "This client will not enumerate the quest log, so there is no way to tell a finished quest from one you are on."
	end
	if answered > 0 then
		return "Nothing else in your bags is finished with."
	end
	return "No quest item in your bags belongs to a quest you have finished."
end

local function Paint(problem)
	if not window then
		return
	end

	local entry = Current()
	card.destroy:SetShown(entry ~= nil)
	card.skip:SetShown(entry ~= nil)
	card.close:SetShown(entry == nil)

	if not entry then
		card.icon:Hide()
		card.name:SetText("nothing to destroy")
		card.name:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
		card.count:SetText(answered > 0 and ("%d answered"):format(answered) or "")
		card.reason:SetText(Prose(problem))
		return
	end

	card.icon:Show()
	card.icon:SetTexture(entry.icon or "Interface\\Icons\\INV_Misc_QuestionMark")

	-- The link carries its own quality colour and the client already worked it
	-- out, so it is read off the link rather than looked up again.
	card.name:SetText((entry.color and ("|c" .. entry.color) or "") .. entry.name .. "|r")
	card.name:SetTextColor(C.text[1], C.text[2], C.text[3])

	card.count:SetText(("%d of %d"):format(answered + 1, answered + #queue))
	card.reason:SetText(entry.reason or "")

	-- Certain and uncertain do not get the same button. An item whose quests are
	-- all behind you is a straightforward yes; one that belongs to a quest still
	-- out there is a decision, and the button says which it is.
	if ns.Clutter.Certain(entry) then
		card.destroy.text:SetText("destroy")
	else
		card.destroy.text:SetText("destroy anyway")
	end
end

local function Refresh()
	Paint(Rebuild())
end

--------------------------------------------------------------------------
-- The two answers
--------------------------------------------------------------------------

function Destroy.Skip()
	local entry = Current()
	if entry then
		skipped[entry.link] = true
		answered = answered + 1
	end
	Refresh()
end

function Destroy.Take()
	local entry = Current()
	if not entry then
		return
	end

	local now = GetTime()
	if now - lastTake < DEBOUNCE then
		return
	end
	lastTake = now

	local ok, why = Take(entry)
	if not ok then
		ns.Print(("kept %s, %s."):format(entry.name, why))
		-- Not counted as answered. Nothing happened to it, and the rescan below
		-- either brings it back where it belongs or drops it because the bag has
		-- genuinely changed.
		Refresh()
		return
	end

	answered = answered + 1
	ns.Print(("destroyed %s. %s"):format(entry.name, entry.reason or ""))
	Refresh()
end

--------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------

local function Build()
	window = UI.Window({
		name = "WarriorKitClutter",
		title = "Clutter",
		width = WIDTH,
		height = M.title + M.pad * 2 + ICON + M.gutter
			+ (M.font + 2) * REASON_LINES + M.footer,
	})

	card = {}
	local body = window.content

	card.icon = UI.Icon(body, "ARTWORK")
	card.icon:SetSize(ICON, ICON)
	card.icon:SetPoint("TOPLEFT", M.pad, -M.pad)

	card.name = UI.Label(body, M.heading, C.text, "LEFT", UI.FLAT)
	card.name:SetPoint("TOPLEFT", card.icon, "TOPRIGHT", M.gutter, 0)
	card.name:SetPoint("RIGHT", body, "RIGHT", -M.pad, 0)

	card.count = UI.Label(body, M.small, C.quiet, "LEFT", UI.FLAT)
	card.count:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -M.rowGap)

	card.reason = UI.Label(body, M.font, C.dim, "LEFT", UI.FLAT)
	UI.Wrap(card.reason, true)
	card.reason:SetSpacing(2)
	card.reason:SetPoint("TOPLEFT", M.pad, -(M.pad + ICON + M.gutter))
	card.reason:SetWidth(WIDTH - M.pad * 2)

	card.destroy = UI.Button(window.footer, { label = "destroy", width = 118, height = M.row,
		onClick = function() Destroy.Take() end })
	card.destroy:SetPoint("LEFT")
	UI.Tint(card.destroy.bg, C.danger)
	card.destroy:SetScript("OnEnter", function(self)
		UI.Tint(self.bg, C.dangerHover)
	end)
	card.destroy:SetScript("OnLeave", function(self)
		UI.Tint(self.bg, C.danger)
	end)

	card.skip = UI.Button(window.footer, { label = "skip", width = 118, height = M.row,
		onClick = function() Destroy.Skip() end })
	card.skip:SetPoint("RIGHT")

	card.close = UI.Button(window.footer, { label = "close", width = 118, height = M.row,
		onClick = function() Destroy.Hide() end })
	card.close:SetPoint("CENTER")
	card.close:Hide()

	-- What is in this window, recorded on the window the way the options panel
	-- records its rail. Nothing in the addon reads it; the harness drives the
	-- two buttons through it rather than through a hook cut in for its benefit.
	window.card = card

	UI.OnRescale(function()
		if window then
			UI.Rezoom(window.frame, UI.WindowZoom())
			window.zoom = UI.WindowZoom()
		end
	end)
end

function Destroy.Show()
	if not window then
		Build()
	end
	-- A fresh visit is a fresh set of skips. Holding them across an open would
	-- mean an item you passed over an hour ago never being offered again, and
	-- the reason you skipped it has usually changed by then.
	wipe(skipped)
	answered = 0
	window:Show()
	Refresh()
end

function Destroy.Hide()
	if window then
		window:Hide()
	end
end

function Destroy.Toggle()
	if window and window.frame:IsShown() then
		Destroy.Hide()
	else
		Destroy.Show()
	end
end

-- One line for /wk status. It walks the bags, which is why nothing on a refresh
-- path calls it.
function Destroy.Describe()
	local found, problem = ns.Clutter.Scan()
	if problem then
		return ns.Clutter.Describe()
	end
	if #found == 0 then
		return "nothing finished with in your bags"
	end

	local certain = 0
	for index = 1, #found do
		if ns.Clutter.Certain(found[index]) then
			certain = certain + 1
		end
	end
	return ("%d to review, %d of them finished with for certain"):format(#found, certain)
end
