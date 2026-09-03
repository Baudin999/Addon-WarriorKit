local ADDON, ns = ...

local Bound = {}
ns.Bound = Bound

local C = ns.UI.Color

--------------------------------------------------------------------------
-- Which key presses it
--
-- A hearthstone in a bag and a Heroic Strike on a square are both things you
-- press a key for, and neither tooltip said which key. The square draws its key
-- in the corner at seven pixels, which is a smear you learn rather than read,
-- and the item in the bag says nothing at all: the client's tooltip for it is
-- about the item, and the key is a fact about the slot it happens to be
-- standing on. This is the one place the two are joined.
--
-- So one tooltip source, in the extra band ahead of the vendor price, that
-- answers for two kinds of subject. An action subject is a slot already; an
-- item subject is walked through every slot until one holds the same id. The
-- line is the key in full rather than Bars.Short's corner form, because a
-- tooltip has the room and "Shift-Mouse 3" is what somebody reads, not "sM3".
--
-- The key comes from two places and the order matters. Buttons/Bars.lua's
-- clone holds an override on every key it took, and a key with an override on
-- it stops answering to its command in the binding set, so the clone is asked
-- first for the key it recorded. The binding set answers for a bar the clone
-- is not standing in for, and for the clone being off.
--
-- Which command a slot answers to is the one thing here that is not a lookup.
-- Bar 1 pages by stance on a warrior, so slot 85 is ACTIONBUTTON1 in defensive
-- stance and nothing at all in battle stance, and the tooltip on the
-- hearthstone should say the key either way: the key is the same, only the
-- stance you press it in changes. Buttons/Which.lua already knows every bar's
-- base slot and every page of bar 1, so the map is read off that rather than
-- kept here.
--------------------------------------------------------------------------

-- Twelve slots to a bar, and the last slot the client has.
local PER_BAR = 12
local SLOTS = 120

-- The client's names for the keys that are not letters, said the way the
-- keybinding panel says them. Anything not here is already readable.
local NAMED = {
	BUTTON1 = "Mouse 1", BUTTON2 = "Mouse 2", BUTTON3 = "Mouse 3",
	BUTTON4 = "Mouse 4", BUTTON5 = "Mouse 5",
	MOUSEWHEELUP = "Wheel up", MOUSEWHEELDOWN = "Wheel down",
	PAGEUP = "Page up", PAGEDOWN = "Page down",
	INSERT = "Insert", DELETE = "Delete", HOME = "Home", END = "End",
	SPACE = "Space", BACKSPACE = "Backspace", ESCAPE = "Escape",
	ENTER = "Enter", TAB = "Tab",
}

local MODIFIER = { ALT = "Alt", CTRL = "Ctrl", SHIFT = "Shift" }

-- A binding string the way a person reads it: SHIFT-BUTTON3 is Shift-Mouse 3
-- and NUMPAD7 is Num 7.
function Bound.Text(key)
	if type(key) ~= "string" or key == "" then
		return ""
	end
	local words, rest = {}, key
	while true do
		local head, tail = rest:match("^(%u+)%-(.+)$")
		if not head or not MODIFIER[head] then
			break
		end
		words[#words + 1] = MODIFIER[head]
		rest = tail
	end
	words[#words + 1] = NAMED[rest] or (rest:gsub("^NUMPAD", "Num "))
	return table.concat(words, "-")
end

-- Whether a slot lies on the twelve starting at this base.
local function On(slot, base)
	return type(base) == "number" and slot >= base and slot < base + PER_BAR
end

-- The binding command a slot answers to, or nil for a slot on no bar this
-- client has. Read off Which.Discover each time rather than held, because the
-- bases move when the client re-points a bar and a hover is not a tick.
function Bound.Command(slot)
	if type(slot) ~= "number" or not ns.WhichBars then
		return nil
	end
	for _, entry in ipairs(ns.WhichBars.Discover()) do
		local bases = entry.pages or { entry.base }
		for _, base in ipairs(bases) do
			if On(slot, base) then
				return entry.def.command:format(slot - base + 1)
			end
		end
	end
	return nil
end

-- The key that presses this slot, or nil for one nothing presses.
function Bound.Key(slot)
	local command = Bound.Command(slot)
	if not command then
		return nil
	end
	local key = ns.Bars and ns.Bars.Held(command)
	if key then
		return key
	end
	if type(GetBindingKey) ~= "function" then
		return nil
	end
	local ok, first = pcall(GetBindingKey, command)
	if ok and type(first) == "string" and first ~= "" then
		return first
	end
	return nil
end

-- The slot an item is standing on, or nil for one on no bar. A slot with a key
-- wins over one without, because the same potion on two bars is pressed by
-- whichever one has a key, and the first is the answer when neither does.
function Bound.Slot(itemId)
	if type(itemId) ~= "number" or not ns.Slot then
		return nil
	end
	local first
	for slot = 1, SLOTS do
		if ns.Slot.Item(slot) == itemId then
			if Bound.Key(slot) then
				return slot
			end
			first = first or slot
		end
	end
	return first
end

-- The line. "Key" and the key for a slot something presses; "Key" and "none"
-- for an item that is on a bar nothing presses, because that is the one case
-- where the bag is the honest answer to where the key went. Nothing at all for
-- an item on no bar, which is most of the bag.
local function Line(slot)
	if not slot then
		return nil
	end
	local key = Bound.Key(slot)
	if key then
		return { "Key", Bound.Text(key), tone = C.accent }
	end
	return { "Key", "none", tone = C.quiet }
end

ns.Tip.Source({
	name = "which key presses it",
	kind = "*",
	band = "extra",
	order = 5,
	fill = function(subject)
		if subject.kind == "action" then
			return Line(subject.slot)
		end
		if subject.kind == "item" then
			local itemId = ns.ItemKind(subject.link)
			return Line(Bound.Slot(itemId))
		end
		return nil
	end,
})
