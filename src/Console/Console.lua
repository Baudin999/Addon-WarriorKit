local ADDON, ns = ...

-- A few lines of Lua, run inside the game, and what they printed.
--
-- The one thing this exists for is reading a client answer back without
-- typing it into chat. A macro is the usual way, and on a machine where the
-- clipboard does not reach the game window a macro is typed by hand, which is
-- fine for one call and not for six with their names beside them. So the
-- calls are written here once, under a name, and the page in Console/Feature.lua
-- draws a button for each. A line typed into the box on that page goes through
-- the same runner.
--
-- Nothing here touches the addon. The chunk runs as the client's own globals,
-- the same as a macro would, and the only thing borrowed is `print`, for as long
-- as the chunk runs and not a call longer.

local Console = {}
ns.Console = Console

-- The questions with a button each. `name` is the word after `/wk console`,
-- `label` is what the button says, and `code` is what runs. A probe prints
-- what it found rather than returning it, so that a probe of four calls reads
-- as four lines with the call named on each.
--
-- xp: every reading Progress/Progress.lua takes before it decides whether there
-- is an experience bar to draw, plus the two the client's own bar asks instead
-- on the builds that have them. Which of the two cap questions this client
-- answers is the reason the probe was written.
Console.PROBES = {
	{ name = "xp", label = "the experience readings", code = [[
print("level", UnitLevel("player"))
print("xp", UnitXP("player"), "of", UnitXPMax("player"))
print("rested", GetXPExhaustion and GetXPExhaustion())
print("GetMaxPlayerLevel", GetMaxPlayerLevel and GetMaxPlayerLevel())
print("MAX_PLAYER_LEVEL", MAX_PLAYER_LEVEL)
print("IsXPUserDisabled", IsXPUserDisabled and IsXPUserDisabled())
print("IsPlayerAtEffectiveMaxLevel", IsPlayerAtEffectiveMaxLevel and IsPlayerAtEffectiveMaxLevel())
print("GetMaxLevelForPlayerExpansion", GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion())]] },

	-- rail: the experience rail's own frame, WarriorKitProgress, as the client
	-- holds it. Whether it and each bar inside it are shown and visible, where
	-- they are on the screen, the fill's colour and value, and then every
	-- visible frame that sits over the rail's centre at its level or above,
	-- which is the list that says what is drawn on top of it.
	{ name = "rail", label = "the experience rail's frame", code = [[
local pw, ph = GetPhysicalScreenSize and GetPhysicalScreenSize()
print("screen", ("%.0f x %.0f"):format(GetScreenWidth(), GetScreenHeight()), "physical", pw, ph,
	"UIParent scale", ("%.4f"):format(UIParent:GetEffectiveScale()), "bottom", UIParent:GetBottom(), "top", UIParent:GetTop())
local f = WarriorKitProgress
if not f then print("no frame called WarriorKitProgress") return end
local function rect(r)
	local l, b, w, h = r:GetRect()
	if not l then return "no rect" end
	return ("%.0f,%.0f %.0fx%.0f"):format(l, b, w, h)
end
print("frame shown", f:IsShown(), "visible", f:IsVisible(), "alpha", f:GetAlpha(),
	"scale", ("%.3f"):format(f:GetEffectiveScale() or 0))
print("frame", rect(f), f:GetFrameStrata(), "level", f:GetFrameLevel(),
	"parent", f:GetParent() and f:GetParent():GetName())
for i, child in ipairs({ f:GetChildren() }) do
	local kind = child:GetObjectType()
	local line = ("child %d %s shown %s visible %s %s level %s"):format(i, tostring(kind),
		tostring(child:IsShown()), tostring(child:IsVisible()), rect(child), tostring(child:GetFrameLevel()))
	if kind == "StatusBar" then
		local lo, hi = child:GetMinMaxValues()
		local r, g, b, a = child:GetStatusBarColor()
		line = line .. (" value %s of %s..%s colour %s %s %s %s"):format(tostring(child:GetValue()),
			tostring(lo), tostring(hi), tostring(r), tostring(g), tostring(b), tostring(a))
		local tex = child:GetStatusBarTexture()
		if tex then
			line = line .. " fill " .. rect(tex) .. " alpha " .. tostring(tex:GetAlpha())
		end
	end
	print(line)
end
if not EnumerateFrames then return end
local l, b, w, h = f:GetRect()
if not l then return end
local scale = f:GetEffectiveScale()
local cx, cy = (l + w / 2) * scale, (b + h / 2) * scale
local mine = f:GetFrameLevel()
local over, frame = 0, EnumerateFrames()
while frame and over < 12 do
	if frame ~= f and not frame:IsForbidden() and frame:IsVisible() then
		local fl, fb, fw, fh = frame:GetRect()
		local s = frame:GetEffectiveScale()
		if fl and fw > 0 and fh > 0 and fl * s <= cx and (fl + fw) * s >= cx
				and fb * s <= cy and (fb + fh) * s >= cy and frame:GetFrameLevel() >= mine then
			over = over + 1
			local parent = frame:GetParent()
			print("over", frame:GetName() or "(unnamed)", frame:GetFrameStrata(), "level", frame:GetFrameLevel(),
				"under", parent and (parent:GetName() or "(unnamed)") or "nothing")
		end
	end
	frame = EnumerateFrames(frame)
end
print("frames over the rail's centre", over)]] },
}

function Console.Probe(name)
	for index = 1, #Console.PROBES do
		if Console.PROBES[index].name == name then
			return Console.PROBES[index]
		end
	end
	return nil
end

-- The probe names, as the sentence that lists them.
function Console.Names()
	local names = {}
	for index = 1, #Console.PROBES do
		names[index] = Console.PROBES[index].name
	end
	return table.concat(names, ", ")
end

local function Words(...)
	local parts = {}
	for index = 1, select("#", ...) do
		parts[index] = tostring((select(index, ...)))
	end
	return table.concat(parts, "  ")
end

-- Run one chunk. Every line it printed comes back in order, then whatever it
-- returned as one more line, and a chunk that did neither says so, because a
-- page that shows nothing after a click is a page that looks broken.
--
-- The second answer is whether it ran. A chunk that does not parse and a chunk
-- that raised both come back false with the message as the last line, rather
-- than raising out of the button: a typo in the box is the ordinary case here,
-- not the exceptional one.
function Console.Run(code)
	local lines = {}
	local chunk, problem = loadstring(code, "=console")
	if not chunk then
		lines[1] = "error: " .. tostring(problem)
		return lines, false
	end

	local held = _G.print
	_G.print = function(...)
		lines[#lines + 1] = Words(...)
	end
	local answers = { pcall(chunk) }
	_G.print = held

	if not answers[1] then
		lines[#lines + 1] = "error: " .. tostring(answers[2])
		return lines, false
	end
	if #answers > 1 then
		lines[#lines + 1] = "returned  " .. Words(unpack(answers, 2))
	end
	if #lines == 0 then
		lines[1] = "ran, and printed nothing"
	end
	return lines, true
end
