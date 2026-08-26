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
	-- The gauge and its hairlines, the strip the icon rows take, and the line
	-- above the lot. Nothing under the gauge: the cast chamber is inside the box.
	local wanted = (22 + 2) + #rows * (size + gap) + 16 * px + CastRoom(bar)
	check(math.abs(bar:GetHeight() - wanted) < 1e-9,
		("%s: the bar is %.0f px tall over %d icon row(s), expected %.0f")
			:format(what, bar:GetHeight(), #rows, wanted))
	return rows
end

check(#ns.EnemyBars.Spells() == 4, "the bar does not ship tracking four debuffs")
CheckPacked("as it ships")

-- One more, and the row is one longer and still ends where it did.
check((ns.EnemyBars.AddSpell(12721)), "Deep Wound would not go on the list")
check(#ns.EnemyBars.Spells() == 5, "adding a debuff did not lengthen the list")
local packed = CheckPacked("with a fifth")
check(#packed == 1 and #packed[1] == 5,
	("five 20 px squares on a 180 px bar should be one row of five, got %d row(s)"):format(#packed))

-- The same id twice would be two squares lighting up together, and an id this
-- client cannot name would be a blank square.
check(not (ns.EnemyBars.AddSpell(12721)), "the same debuff went on the list twice")
check(not (ns.EnemyBars.AddSpell(900001)), "an id this client cannot name went on the list")
check(not (ns.EnemyBars.AddSpell("rend")), "a word went on the list as a spell id")
check(#ns.EnemyBars.Spells() == 5, "a refused add changed the list anyway")

-- Off again, and the row is back where it started.
check((ns.EnemyBars.RemoveSpell(12721)), "Deep Wound would not come off the list")
check(#ns.EnemyBars.Spells() == 4, "removing a debuff did not shorten the list")
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

for _, spellID in ipairs({ 1715, 12323, 355, 694, 1161, 676 }) do
	check((ns.EnemyBars.AddSpell(spellID)), ("%d would not go on the list"):format(spellID))
end
check(#ns.EnemyBars.Spells() == 10, "the list did not reach ten")
check(not (ns.EnemyBars.AddSpell(5246)), "an eleventh debuff went on a list capped at ten")
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
-- four debuffs at twenty pixels and a ratchet measured on another list is a
-- ratchet measuring something else.
ns.db.barsIconSize = 20
ns.EnemyBars.ResetSpells()
check(#ns.EnemyBars.Spells() == 4, "the reset did not put the four back")
CheckPacked("after a reset")
widget = ns.EnemyBars.WidgetFor("nameplate1")

-- Left for the sections below.
H.carry.CheckPacked, H.carry.widget, H.carry.wrapped = CheckPacked, widget, wrapped
