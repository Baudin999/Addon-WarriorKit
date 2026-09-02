local ADDON, ns = ...

local Blizz = {}
ns.BookBlizzard = Blizz

--------------------------------------------------------------------------
-- Blizzard's spell book, out of the way
--
-- One frame and one key, and the argument for both is the character sheet's.
-- SpellBookFrame is not a live server session the way the mail window is:
-- every call this addon makes about your spells, reading the book and
-- picking a rank up included, works with that frame nowhere near the screen.
-- So it goes in the attic, where a hidden parent beats every route the client
-- has to put a frame back, rather than being parked off the side where a
-- relayout could return it.
--
-- Your pet's book goes with it, because it is a page of the same frame. This
-- addon does not draw one, and that is said in the switch's own hint rather
-- than worked around: the honest answer to a page a warrior never opens is a
-- sentence and a tick box.
--
-- **The key has to come with it.** Hiding the window and leaving P bound to
-- the client's own toggle is a spell book you cannot open, which is worse
-- than either window on its own. ToggleSpellBook is a plain global on both of
-- these clients and it carries which book it meant, so it is replaced with
-- one that opens this addon's window for the spell book and says so for the
-- pet's, and the original is kept so the switch can hand it back exactly.
--
-- The key goes onto a secure button as well as onto the global, for the
-- reason the character sheet's does: every square on the window is a secure
-- button, showing a window with one inside it is protected, and only a
-- snippet may do that in a fight. An override binding onto the window's key
-- button is that snippet's doorbell.
--
-- **The switch is the one on the Blizzard page.** There is one place in this
-- addon where a frame of the client's is switched on or off, it is the list
-- in UnitFrames/Blizzard.lua, and this file registers into it the way the
-- character sheet's and the talent window's do.
--------------------------------------------------------------------------

local FRAMES = {
	"SpellBookFrame",
}

-- The book the client's toggle is asked for when it means your pet's.
local PET = "pet"

-- What the client's P key called before this addon took it.
local original = nil

-- Whether the secure button's binding needs looking at. True at login and
-- whenever the client says the bindings moved, false once they have been
-- taken. A flag rather than a comparison, because the pass that calls this
-- runs once a second forever and the harness's allocation gate measures it.
local dirty = true

-- The first key this file is currently holding, or nil where it holds none.
local bound = nil

-- The client's own binding for its spell book, one name on both clients.
local BINDINGS = { "TOGGLESPELLBOOK" }

local function Frame(name)
	local frame = _G[name]
	if type(frame) ~= "table" or type(frame.GetParent) ~= "function" then
		return nil
	end
	return frame
end

--------------------------------------------------------------------------
-- The key
--------------------------------------------------------------------------

-- Whoever is holding ToggleSpellBook now, remembered once. Called before the
-- swap and never after, so a second addon that wrapped the same global after
-- us is not swallowed by a later re-apply.
local function Remember()
	if original == nil and type(_G.ToggleSpellBook) == "function" then
		original = _G.ToggleSpellBook
	end
	return original ~= nil
end

-- What P does while the switch is on. Declared once at load rather than
-- built inside TakeKey, because the pass below runs once a second forever.
local function Toggle(bookType)
	if bookType == PET then
		ns.Print("this window does not draw your pet's book. Untick hiding Blizzard's spell book to get it back.")
		return
	end
	ns.SpellWindow.Toggle()
end

-- Every key the client has on its own spell book, in the order it answers
-- them. Called when the bindings have moved and never on the idle pass.
local function Keys()
	local keys = {}
	if type(_G.GetBindingKey) ~= "function" then
		return keys
	end
	for index = 1, #BINDINGS do
		local first, second = GetBindingKey(BINDINGS[index])
		if first then
			keys[#keys + 1] = first
		end
		if second then
			keys[#keys + 1] = second
		end
	end
	return keys
end

-- An override binding rather than SetBinding, because this is a key this
-- addon is borrowing rather than a key the player set: it is not written to
-- their bindings, and clearing it hands the key straight back to whatever
-- they had. Refused in lockdown, like every binding call, and the pass that
-- runs once a second and again when combat drops puts it right.
local function Bind()
	if not dirty then
		return true
	end
	if type(_G.SetOverrideBindingClick) ~= "function" then
		return false
	end
	local button = ns.SpellWindow.Key()
	if not button or InCombatLockdown() then
		return false
	end
	ClearOverrideBindings(button)
	local keys = Keys()
	for index = 1, #keys do
		SetOverrideBindingClick(button, true, keys[index], ns.SpellWindow.KeyName(), "LeftButton")
	end
	dirty, bound = false, keys[1]
	return bound ~= nil
end

local function Unbind()
	if not bound then
		return false
	end
	local button = ns.SpellWindow.Key()
	if not button or InCombatLockdown() then
		return false
	end
	ClearOverrideBindings(button)
	dirty, bound = true, nil
	return true
end

-- The client's own binding set moved, so whatever this file took has to be
-- taken again off the new one. The pass does the work; this only says that
-- there is work.
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("UPDATE_BINDINGS")
watcher:SetScript("OnEvent", function()
	dirty = true
end)

local function TakeKey()
	if not Remember() then
		return false
	end
	if _G.ToggleSpellBook ~= Toggle then
		_G.ToggleSpellBook = Toggle
	end
	return Bind()
end

-- Only ever hands back what this file took. A client where somebody else is
-- holding the global is a client this file leaves alone.
local function GiveKey()
	Unbind()
	if type(original) ~= "function" or _G.ToggleSpellBook ~= Toggle then
		return false
	end
	_G.ToggleSpellBook = original
	return true
end

-- What to call the key in a sentence: the one this file is holding, the
-- first the client answers, or the letter it ships with where it answers
-- none.
function Blizz.KeyText()
	if bound then
		return bound
	end
	local keys = Keys()
	return keys[1] or "P"
end

--------------------------------------------------------------------------
-- The frames
--------------------------------------------------------------------------

-- Whether the client's window should be out of the way right now. Two things
-- and no third: our window has to be built at all, and the switch has to be
-- on.
function Blizz.Wanted()
	return (ns.db.spellbook and ns.db.hideBlizzSpellbook) and true or false
end

-- Run on every pass rather than only where the answer changed, which is the
-- rule UnitFrames/Blizzard.lua's header argues for at length: a pass that
-- remembers what it did cannot see a frame the client put back.
function Blizz.Apply()
	local wanted = Blizz.Wanted()
	if wanted then
		TakeKey()
	else
		GiveKey()
	end

	local complete = true
	local act = wanted and ns.Attic.Vanish or ns.Attic.Return
	for index = 1, #FRAMES do
		local frame = Frame(FRAMES[index])
		if frame and not act(frame) then
			complete = false
		end
	end
	return complete
end

-- Whether the client's frame is in the attic right now.
function Blizz.Caged()
	for index = 1, #FRAMES do
		local frame = Frame(FRAMES[index])
		if frame then
			return ns.Attic.Held(frame)
		end
	end
	return Blizz.Wanted() and _G.ToggleSpellBook == Toggle
end

function Blizz.Describe()
	if not ns.db.hideBlizzSpellbook then
		return "on screen, and " .. Blizz.KeyText() .. " opens it"
	end
	if not ns.db.spellbook then
		return "on screen, because this addon's own book is off"
	end
	if type(original) ~= "function" then
		return "in the attic, and this client has no ToggleSpellBook to redirect"
	end
	return ("in the attic, and %s opens this one"):format(Blizz.KeyText())
end

--------------------------------------------------------------------------

-- Registered with the switch it belongs to, so `/wk hide spellbook`, the
-- panel's own line and `/wk reset` all reach this file without any of them
-- naming it.
ns.BlizzHide.Also(Blizz.Apply)
