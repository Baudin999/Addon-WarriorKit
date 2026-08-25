local ADDON, ns = ...

local EditMode = {}
ns.EditMode = EditMode

-- Edit Mode is the retail frame manager, backported into 2.5.6. Titan calls
-- EditModeManagerFrame:GetActiveLayoutInfo() unguarded, which is what proves
-- the frame is on this client. Nothing past that one method is confirmed by
-- any installed addon, so each is probed by name before it is called and every
-- call goes through pcall.
--
-- Why a file and not saved variables: the point of this part is to carry a
-- layout to another computer. Saved variables live in WTF, which is per
-- install and does not travel. The addon folder does, so the baked layout is a
-- generated Lua file, EditMode/Saved.lua, written by ./bake-ui.sh.
--------------------------------------------------------------------------

local NEEDED = {
	"GetActiveLayoutInfo",
	"GetLayouts",
	"SelectLayout",
	"SaveLayouts",
	"ImportLayout",
}

local function Manager()
	local manager = _G.EditModeManagerFrame
	return type(manager) == "table" and manager or nil
end

-- Deliberately not cached, unlike the Buttons probe. Blizzard_EditMode can be
-- load on demand, so an answer taken at login is not still true a moment later,
-- and the whole check is six table lookups.
function EditMode.CanApply()
	local manager = Manager()
	if not manager then
		return false, "this client has no Edit Mode"
	end
	for _, name in ipairs(NEEDED) do
		if type(manager[name]) ~= "function" then
			return false, "EditModeManagerFrame:" .. name .. " is missing on this client"
		end
	end
	if InCombatLockdown() then
		return false, "not in combat"
	end
	return true
end

local function Call(method, ...)
	local manager = Manager()
	if not manager or type(manager[method]) ~= "function" then
		return false, method .. " is missing on this client"
	end
	local ok, result = pcall(manager[method], manager, ...)
	if not ok then
		return false, tostring(result)
	end
	return true, result
end

-- The manager hands back its own table and goes on editing it, so a reference
-- would drift with whatever is done in Edit Mode next. Take a copy or take
-- nothing.
local function Copy(value)
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for key, inner in pairs(value) do
		out[Copy(key)] = Copy(inner)
	end
	return out
end

function EditMode.Capture()
	local can, why = EditMode.CanApply()
	if not can then
		return nil, why
	end
	local ok, layout = Call("GetActiveLayoutInfo")
	if not ok then
		return nil, layout
	end
	if type(layout) ~= "table" then
		return nil, "the client handed back no active layout"
	end
	return Copy(layout)
end

-- The index SelectLayout wants, which is the position in the manager's own
-- list. Presets sit in that list too, so this is a name lookup and never a
-- guess at an offset.
function EditMode.IndexOf(name)
	if not name or name == "" then
		return nil
	end
	local ok, layouts = Call("GetLayouts")
	if not ok or type(layouts) ~= "table" then
		return nil
	end
	for index, layout in ipairs(layouts) do
		if type(layout) == "table" and layout.layoutName == name then
			return index
		end
	end
	return nil
end

-- The baked layout, or nil when bake-ui.sh has not been run yet.
function EditMode.Saved()
	local saved = EditMode.SAVED
	if type(saved) ~= "table" or type(saved.layout) ~= "table" then
		return nil
	end
	return saved.layout, saved.name or saved.layout.layoutName, saved.stamp
end

-- Imports the baked layout if this client has no layout by that name, then
-- makes it active. Never overwrites a layout that is already here: a name
-- collision means the user has one of their own and it is theirs to keep.
function EditMode.Apply()
	local can, why = EditMode.CanApply()
	if not can then
		return false, why
	end
	local layout, name = EditMode.Saved()
	if not layout then
		return false, "no layout is baked in, capture one with /wk ui save and run ./bake-ui.sh"
	end

	local index, imported = EditMode.IndexOf(name), false
	if not index then
		local layoutType = layout.layoutType
			or (Enum and Enum.EditModeLayoutType and Enum.EditModeLayoutType.Account)
		local ok, err = Call("ImportLayout", Copy(layout), layoutType, name)
		if not ok then
			return false, "the client refused the import: " .. err
		end
		index = EditMode.IndexOf(name)
		if not index then
			return false, "the import ran and no layout called " .. name .. " came back"
		end
		imported = true
	end

	local ok, err = Call("SelectLayout", index)
	if not ok then
		return false, "the client refused to select it: " .. err
	end
	Call("SaveLayouts")
	return true, imported
end

--------------------------------------------------------------------------
-- Automatic import
--
-- The whole point of the part: a fresh install has the addon folder and none
-- of the user's WTF, so the layout has to arrive from the addon. It arrives
-- once. A layout already on the client is the user's, and swapping the UI out
-- from under them at every login is not automatic, it is a fight.
--------------------------------------------------------------------------

local done = false

local function AutoApply()
	if done or not ns.db or not ns.db.uiAuto then
		return
	end
	local layout, name = EditMode.Saved()
	if not layout then
		done = true
		return
	end
	if not EditMode.CanApply() then
		return -- not loaded yet, or in combat. Another event comes back here.
	end
	if EditMode.IndexOf(name) then
		done = true
		return
	end
	done = true
	local ok, result = EditMode.Apply()
	if ok then
		ns.Print(("no %s layout on this client, so it came from the addon and is now active."):format(name))
	else
		ns.Print(("could not import the %s layout: %s."):format(name, tostring(result)))
	end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" and arg1 ~= "Blizzard_EditMode" then
		return
	end
	AutoApply()
end)
