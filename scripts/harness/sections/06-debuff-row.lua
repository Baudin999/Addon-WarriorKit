-- The debuff row
--
-- Which debuffs it shows and how big they are are both settings, so what is
-- asserted here is the shape the settings have to keep producing: the row is
-- as long as the list, it ends flush with the right end of the gauge however
-- long that is, and when it no longer fits it wraps upwards rather than hanging
-- icons off the left edge of the bar.
--
-- Offsets rather than resolved rectangles. This stub records what a frame was
-- anchored to and does no layout, which is the honest thing to assert against:
-- the offset is the addon's half of the contract and the arithmetic on it is
-- the client's.
--
-- Measured against the gauge rather than read off one anchor pair. Every square
-- used to hang off the gauge's own top right corner and this asserted that pair
-- by name; ns.UI.Flow pins everything in a widget to the widget's top left
-- instead, so which pair it used is the layout engine's business and the only
-- thing worth asserting is where the square lands. That is what this measures,
-- and it covers the gauge's own placement too, which naming the anchor did not.

local H = ...
local ns, order, check = H.ns, H.order, H.check
local wanted, widget = H.carry.wanted, H.carry.widget

-- The scene is stated here rather than inherited. This section is about the
-- shape the row keeps and not about the numbers it ships at, and every figure
-- worked out in the comments below is worked out against a 180 pixel bar with
-- 20 pixel squares on it. Reading the shipped sizes instead would mean every
-- one of those arithmetic notes going stale the next time a default moves.
-- The shipped sizes go back at the foot of the file.
ns.db.barsWidth, ns.db.barsIconSize = 180, 20
ns.EnemyBars.ApplyLayout()
ns.EnemyBars.Rebuild()
widget = ns.EnemyBars.WidgetFor("nameplate1")

-- The offset a frame was pinned at, checked to be pinned the way Flow pins
-- everything inside a widget.
local function Corner(frame, bar, what)
	local point, relative, relativePoint, x, y = frame:GetPoint()
	check(point == "TOPLEFT" and relative == bar and relativePoint == "TOPLEFT",
		("%s is anchored %s to %s, not TOPLEFT to the widget's TOPLEFT")
			:format(what, tostring(point), tostring(relativePoint)))
	return x or 0, y or 0
end

-- Where every square sits relative to the right end of the gauge, grouped by
-- the line it is on. Returns the lines, the one nearest the gauge first, each
-- one a list of the offsets of the squares' left edges.
local function IconRows(bar)
	local rows, order = {}, {}
	local boxX = Corner(bar.box, bar, "the gauge")
	local edge = boxX + bar.box:GetWidth()
	for index = 1, #ns.EnemyBars.Spells() do
		local holder = bar.icons[index]
		local x, y = Corner(holder, bar, ("debuff %d"):format(index))
		check(holder:IsShown(), ("debuff %d is on the list and hidden"):format(index))
		if not rows[y] then
			rows[y] = {}
			order[#order + 1] = y
		end
		local row = rows[y]
		row[#row + 1] = x - edge
	end
	for index = #ns.EnemyBars.Spells() + 1, #bar.icons do
		check(not bar.icons[index]:IsShown(),
			("debuff slot %d is off the list and still shown"):format(index))
	end
	table.sort(order)
	local out = {}
	for _, y in ipairs(order) do
		out[#out + 1] = rows[y]
	end
	return out
end

-- What the cast chamber takes out of the widget's own height, which is nothing.
--
-- It used to be eleven pixels of bar, a hairline each side and a four pixel gap,
-- reserved whether or not anything was casting, and that reserve was part of
-- every height below. The chamber is inside the health box now and grows it
-- downward from the box's own bottom edge, so the widget Flow measured does not
-- change when a mob casts and neither does anything above the gauge.
--
-- Kept as a function rather than deleted, because the contract it states is the
-- one worth keeping true: the cast setting must not move the bar's height.
local function CastRoom(_)
	return 0
end

-- The whole of the alignment contract: the last square in every row ends on the
-- gauge's right edge, and the squares in a row are one gap apart.
local function CheckPacked(what)
	local bar = ns.EnemyBars.WidgetFor("nameplate1")
	local px = ns.UI.Pixel(bar)
	local size, gap = ns.db.barsIconSize * px, 4 * px
	local rows = IconRows(bar)
	for index, row in ipairs(rows) do
		table.sort(row)
		local right = row[#row] + size
		check(math.abs(right) < 1e-9,
			("%s: row %d ends %.0f px from the gauge's right edge, not on it"):format(what, index, right))
		for column = 2, #row do
			check(math.abs(row[column] - row[column - 1] - (size + gap)) < 1e-9,
				("%s: row %d has a %.0f px step between squares, expected %.0f")
					:format(what, index, row[column] - row[column - 1], size + gap))
		end
	end
	-- A list with nothing on it has no square to measure, which is what a class
	-- nobody has written a file for ships with now that the list is the spec's.
	-- The bare bar's own height is asserted further down, on a scene this one
	-- builds on purpose rather than on whichever class is running.
	if #ns.EnemyBars.Spells() == 0 then
		check(not bar.icons[1] or not bar.icons[1]:IsShown(),
			("%s: nothing is tracked and a square is still drawn"):format(what))
		return rows
	end

	-- A square is the setting wide and taller than that, because the time left
	-- stands over the art rather than on it. The setting is the art: what the
	-- panel says is what the icon draws, and the strip is what the widget adds
	-- on top of it.
	local square = bar.icons[1]
	check(math.abs(square.box:GetHeight() - size) < 1e-9,
		("%s: icon %d is set and the art is %.0f px"):format(what,
			ns.db.barsIconSize, square.box:GetHeight()))
	check(square:GetHeight() > square.box:GetHeight(),
		("%s: the square is %.0f px tall and the art in it is %.0f, so the"
			.. " timer has nowhere to stand"):format(what, square:GetHeight(),
			square.box:GetHeight()))
	local tall = square:GetHeight()

	-- The gauge and its hairlines, the strip the icon rows take, and the line
	-- above the lot. Nothing under the gauge: the cast chamber is inside the box.
	local wanted = (22 + 2) + #rows * (tall + gap) + 16 * px + CastRoom(bar)
	check(math.abs(bar:GetHeight() - wanted) < 1e-9,
		("%s: the bar is %.0f px tall over %d icon row(s), expected %.0f")
			:format(what, bar:GetHeight(), #rows, wanted))
	return rows
end

--------------------------------------------------------------------------
-- What this character was handed
--
-- The list a bar ships with is a fact about the spec you are playing and lives
-- in Class/<yours>.lua, so what is asserted here is that the character got that
-- list and not a number written out below. A warrior gets his own five, an
-- enhancement shaman gets four that are nothing like them, and a hunter gets
-- none at all because nobody has written the file.
--
-- Every count after this one is built out of SPARE instead, which is a block of
-- ids this stub will name and no class file uses. That is deliberate: the
-- arithmetic below is about how long a list may be and how it wraps, and
-- borrowing the ids from whichever class is running would make it about which
-- class is running.
--------------------------------------------------------------------------

do
	local shipped, spec = ns.EnemyBars.Spells(), ns.EnemyBars.DefaultSpells()
	check(#shipped == #spec,
		("the bar ships tracking %d debuffs and the spec lists %d")
			:format(#shipped, #spec))
	for index = 1, #spec do
		check(shipped[index] == spec[index],
			("debuff %d on the shipped list is %s and the spec says %s")
				:format(index, tostring(shipped[index]), tostring(spec[index])))
	end
end
CheckPacked("as it ships")

local SPARE = { 800001, 800002, 800003, 800004, 800005, 800006,
	800007, 800008, 800009, 800010, 800011 }

-- Down to nothing and back up to five, so the whole of the rest of this section
-- counts against a list it wrote itself.
local function Only(count)
	local list = ns.EnemyBars.Spells()
	for index = #list, 1, -1 do
		ns.EnemyBars.RemoveSpell(list[index])
	end
	for index = 1, count do
		check((ns.EnemyBars.AddSpell(SPARE[index])),
			("%d would not go on an empty list"):format(SPARE[index]))
	end
	check(#ns.EnemyBars.Spells() == count,
		("the list was built to %d and reads %d"):format(count, #ns.EnemyBars.Spells()))
end

Only(5)
CheckPacked("five spares")

-- One more, and the row is one longer and still ends where it did.
check((ns.EnemyBars.AddSpell(SPARE[6])), "a sixth debuff would not go on the list")
check(#ns.EnemyBars.Spells() == 6, "adding a debuff did not lengthen the list")
local packed = CheckPacked("with a sixth")
check(#packed == 1 and #packed[1] == 6,
	("six 20 px squares on a 180 px bar should be one row of six, got %d row(s)"):format(#packed))

-- The same id twice would be two squares lighting up together, and an id this
-- client cannot name would be a blank square.
check(not (ns.EnemyBars.AddSpell(SPARE[6])), "the same debuff went on the list twice")
check(not (ns.EnemyBars.AddSpell(900001)), "an id this client cannot name went on the list")
check(not (ns.EnemyBars.AddSpell("rend")), "a word went on the list as a spell id")
check(#ns.EnemyBars.Spells() == 6, "a refused add changed the list anyway")

-- Off again, and the row is back where it started.
check((ns.EnemyBars.RemoveSpell(SPARE[6])), "the sixth would not come off the list")
check(#ns.EnemyBars.Spells() == 5, "removing a debuff did not shorten the list")
CheckPacked("after a remove")

-- The size reaches the squares, and a longer list on a wider square wraps
-- upwards rather than running off the left end of the bar.
ns.db.barsIconSize = 32
ns.EnemyBars.ApplyLayout()
ns.EnemyBars.Rebuild()
check(ns.EnemyBars.WidgetFor("nameplate1").icons[1]:GetWidth()
		== 32 * ns.UI.Pixel(ns.EnemyBars.WidgetFor("nameplate1")),
	"bars icon 32 did not reach the squares")
CheckPacked("at 32 px")

for index = 6, 10 do
	check((ns.EnemyBars.AddSpell(SPARE[index])),
		("%d would not go on the list"):format(SPARE[index]))
end
check(#ns.EnemyBars.Spells() == 10, "the list did not reach ten")
check(not (ns.EnemyBars.AddSpell(SPARE[11])), "an eleventh debuff went on a list capped at ten")
local wrapped = CheckPacked("ten at 32 px on a 180 px bar")
-- 180 holds five 32 px squares with 4 px between them, so ten is two rows.
check(#wrapped == 2 and #wrapped[1] == 5 and #wrapped[2] == 5,
	("ten squares should wrap to two rows of five, got %d row(s)"):format(#wrapped))

-- Emptying the list leaves the threat line its own height and nothing else.
for index = #ns.EnemyBars.Spells(), 1, -1 do
	ns.EnemyBars.RemoveSpell(ns.EnemyBars.Spells()[index])
end
check(#ns.EnemyBars.Spells() == 0, "the list would not empty")
do
	local bare = ns.EnemyBars.WidgetFor("nameplate1")
	local px, unit = ns.UI.Pixel(bare), ns.UI.Unit(bare)
	-- Built from the design rather than from one number, so the zoom and the
	-- outline floor both reach it. The gauge is 22 with a hairline each side,
	-- the strip above it is the threat line's own height, and 16 is the room the
	-- name over the plate takes. The strip is the floor rather than the bar's
	-- text size because that line sits over the world and cannot go flat; the
	-- two are the same number now that the bar's own text is at the floor too.
	local strip = math.max(14, ns.UI.OutlineFloor())
	local wanted = 22 * unit + 2 * px + (4 + strip + 16) * unit + CastRoom(bare)
	check(math.abs(bare:GetHeight() - wanted) < 1e-9,
		("with nothing tracked the bar is %.0f px tall, expected %.0f"):format(bare:GetHeight(), wanted))
	check(not bare.icons[1]:IsShown(), "an empty list still shows a square")
end

-- Back to the shipped scene, because the churn figure below is quoted against
-- the list and the sizes the addon actually ships, and a ratchet measured on
-- another scene is a ratchet measuring something else.
ns.db.barsWidth = ns.DefaultFor("barsWidth")
ns.db.barsIconSize = ns.DefaultFor("barsIconSize")
ns.EnemyBars.ApplyLayout()
ns.EnemyBars.ResetSpells()
do
	local back, spec = ns.EnemyBars.Spells(), ns.EnemyBars.DefaultSpells()
	check(#back == #spec,
		("the reset left %d debuffs and the spec lists %d"):format(#back, #spec))
end
CheckPacked("after a reset")
widget = ns.EnemyBars.WidgetFor("nameplate1")

-- Left for the sections below.
H.carry.CheckPacked, H.carry.widget, H.carry.wrapped = CheckPacked, widget, wrapped
