local H = ...

local Region = H.Region

--------------------------------------------------------------------------
-- A press on a button
--
-- The half of a click that the addon writes is its handlers. The other half
-- belongs to the client, and this file is here because that half decides
-- whether a button does anything at all.
--
-- **The edge is the point.** A button registered for AnyDown does nothing on an
-- up press, so the caller says which edge: a key binding press and a mouse
-- release are not the same event and the client does not guess either.
--
-- **And a secure button does not act on the edge it registered for.** It reads
-- its own `useOnKeyDown` attribute, falls back to the player's
-- ActionButtonUseKeyDown setting where it does not answer, and on the other
-- edge does nothing whatever its attributes say. That is how a gear square
-- registered for the release, holding a correct macro, drew and hovered and
-- applied no sharpening stone, and it is the second time this addon has shipped
-- that bug. A stub that ran the handlers and called that a click cannot tell
-- the two apart, so this one runs the client's half in the middle.
--------------------------------------------------------------------------

-- Which attribute a mouse button reads, at the client's own numbers.
local SUFFIX = { LeftButton = "1", RightButton = "2", MiddleButton = "3" }

-- What the client does between PreClick and OnClick on a secure button.
--
-- The macro first, then the slot a spell that is waiting for an item lands on,
-- in the client's own order, because the first can be what makes something wait.
-- An attribute is looked up per button and then plain, which is the tail of the
-- client's own lookup and the only part of it this addon writes.
local function secure(self, button, down)
	local keyDown = self:GetAttribute("useOnKeyDown")
	if keyDown == nil then
		keyDown = _G.GetCVarBool("ActionButtonUseKeyDown")
	end
	if (down and true or false) ~= (keyDown and true or false) then
		return
	end

	local suffix = SUFFIX[button] or ""
	local function attribute(name)
		local value = self:GetAttribute(name .. suffix)
		if value == nil then
			value = self:GetAttribute(name)
		end
		return value
	end

	if attribute("type") == "macro" and _G.RunMacroText then
		local text = attribute("macrotext")
		if text then
			_G.RunMacroText(text)
		end
	end

	if _G.SpellCanTargetItem and _G.SpellCanTargetItem() then
		local slot = attribute("target-slot")
		if slot and _G.UseInventoryItem then
			_G.UseInventoryItem(slot)
		end
	end
end

-- PreClick, the client's own half, OnClick, PostClick, in the client's order.
-- That order is why anything reading the world before the click changes it is
-- written into PreClick and anything tidying up after one into PostClick.
function Region:Click(button, down)
	button = button or "LeftButton"
	local edge = down and "Down" or "Up"
	-- A button the frame hands through to whatever is behind it never reaches
	-- the frame's own scripts, however it registered. The chat rail shipped
	-- with the right button registered and passed through at once, and the
	-- harness pressed the script directly, so it certified a close the live
	-- client could not perform.
	if self.passed and self.passed[button] then
		return false
	end
	local scripts = self.scripts
	-- OnMouseDown and OnMouseUp fire for every button on a frame that takes
	-- the mouse, registered or not; RegisterForClicks decides OnClick alone.
	-- The mail window's take on a bag square rests on exactly that: the right
	-- button taken off the registration, so the secure OnClick never runs, and
	-- an OnMouseUp of the addon's answering in its place.
	local mouse = scripts and scripts["OnMouse" .. edge]
	if mouse then
		mouse(self, button)
	end
	local clicks = self.clicks
	if clicks and not (clicks["Any" .. edge] or clicks[button .. edge]) then
		return mouse ~= nil
	end
	if scripts and scripts.PreClick then
		scripts.PreClick(self, button, down and true or false)
	end
	if self.secure then
		secure(self, button, down)
	end
	if scripts and scripts.OnClick then
		scripts.OnClick(self, button, down and true or false)
	end
	if scripts and scripts.PostClick then
		scripts.PostClick(self, button, down and true or false)
	end
	return true
end
