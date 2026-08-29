local ADDON, ns = ...

local UI = ns.UI
local Ability = {}
UI.Ability = Ability

--------------------------------------------------------------------------
-- An ability, drawn
--
-- One square that says what an ability is, whether a press would land it, and
-- how long until it would. Every icon in this addon that stands for something
-- castable is one of these: the charge button on the HUD, the marker in the
-- world, and the buttons on the bars.
--
-- It was written twice before this file existed and the two copies had already
-- started to drift. Charge/Icon.lua and Charge/Marker.lua both build a black
-- backing texture, a cropped icon, a cooldown swipe with the client's numbers
-- turned off and a timer string of their own, then recolour a border and
-- desaturate the art from one shared status. The same square, the same six
-- writes, the same guard. What differed was an accident: the icon had a border
-- it recoloured through SetColorTexture on a single background texture, the
-- marker had one too, and neither could grow a range tint without the other
-- being edited to match.
--
-- Three calls, split by when they run rather than by what reads tidily, which
-- is the split UI/Gauge.lua already uses.
--
--   Ability.New       allocates. Once per button.
--   Ability.Size      lays the square out. On a settings change or a rescale.
--   Ability.Draw      runs on a ticker against every square on the screen, so
--                     it allocates nothing and writes nothing already there.
--                     check.sh's HOT list holds it to that.
--
-- What a square answers to the hand, as opposed to what it says about the
-- game, is here too and was the thing missing when the bars did not feel like
-- buttons. Three pieces, all of them free:
--
--   A highlight under the cursor, drawn on the HIGHLIGHT layer, which the
--   client shows and hides itself for any frame that takes the mouse. No
--   script, no per-tick work.
--
--   A pushed tint on the way down, which the Button widget draws itself for
--   whatever SetPushedTexture was handed. Buttons only; a plain frame has no
--   such state and the marker in the world is not something you press.
--
--   An active ring and tint, for the one square whose ability is already what
--   is running: the stance you are standing in, the auto attack already
--   swinging, the Heroic Strike queued onto the next swing. That one is not
--   free, because nothing in the client knows to draw it, so it is an argument
--   to Ability.Draw like every other fact about the square.
--
--   It started as the tint alone, at 22% additive gold over a 27 pixel icon,
--   and that is not visible on art that is already bright. Queueing Heroic
--   Strike is the case that proved it: the one press in a warrior's rotation
--   whose whole answer is "it is armed and it goes off on the next swing", and
--   the square said nothing you could see. Blizzard draws a checked border for
--   the same fact. So does this now, and the tint stays underneath it, because
--   the ring is the edge and the fill is what makes the square read as lit
--   rather than as outlined.
--
-- And a green ring for an item you are wearing, which is what Blizzard's own
-- buttons draw for the same fact. It is a second outline one pixel inside the
-- first rather than a recolour of it, because the outer edge already carries
-- the status and being equipped is not a status: a wielded weapon can be on
-- cooldown and out of range at once, and all three are worth saying.
--
-- What this file does not do, and will not: decide what an ability is doing.
-- It is handed a status and draws it. Charge/Charge.lua works out the status
-- for the three charge abilities against a picked unit; Buttons/Slot.lua works
-- it out for an action slot. Those two are different questions with the same
-- ten answers, and keeping the answers here is what stops a third display
-- inventing an eleventh.
--------------------------------------------------------------------------

--------------------------------------------------------------------------
-- The vocabulary
--
-- Ten statuses and six looks. The statuses are reasons and are the same
-- everywhere; the looks are what a reason is worth on screen and are not.
--
-- Splitting them is the whole design of this file. A status is a fact about
-- the game: you have no rage, the mob is too far, you are in the wrong stance.
-- A look is an editorial decision about how loudly to say it, and the right
-- volume depends on how many squares are on screen. One charge icon in the
-- middle of the view can afford to go green when it is ready, because green
-- means "now" and there is nothing to compare it against. Twenty-four bar
-- buttons cannot: a wall of green says nothing at all, and the state worth
-- shouting about there is the one that is wrong.
--
-- So the status to outcome map below is shared and the outcome to look map is
-- the caller's, chosen at Ability.New.
--------------------------------------------------------------------------

-- Every reason a press does or does not land, in the order a source should
-- test them: what cannot be fixed at all, then what a few seconds or a stance
-- swap fixes, then range. Named here rather than in each source so a display
-- cannot be handed a status no palette has a colour for.
Ability.STATUS = {
	empty     = true, -- the slot holds nothing
	unknown   = true, -- there is an ability, this character cannot cast it
	cooldown  = true, -- on cooldown, longer than the global
	reaction  = true, -- a reactive ability whose window is shut
	condition = true, -- the fight has not met what the ability waits on
	combat    = true, -- right ability, wrong side of the combat line
	notarget  = true, -- nothing to cast it on
	stance    = true, -- wrong stance, or unusable for a reason that is not cost
	cost      = true, -- not enough rage, mana, energy or focus
	range     = true, -- everything else is fine and the unit is too far
	ready     = true, -- press it
}

-- Which of the six looks a status is worth. Everything absent is "no", which
-- is where cooldown, wrong stance and an empty slot all land: the reasons
-- differ, and the answer to "would a press do the thing" does not.
--
-- Range and cost are pulled out of "no" on purpose, and they are the only two
-- that are. Both are states you can act on within a second or two, one by
-- walking and one by waiting, and both are what you are actually asking a bar
-- when you glance at it mid-fight. Cooldown is not in that group because the
-- swipe already says it, in more detail than a colour could.
--
-- Cost keeps the drain that "no" has, and that is the one look in the table
-- that says the same thing twice. It has to, because this addon draws no rage
-- bar and no mana bar on the bars themselves: what you can afford right now is
-- readable off the squares or it is not readable anywhere. A hairline of blue
-- on a 27 pixel square is a thing you find when you go looking for it, and the
-- question "what can I press" is asked with the eye moving, not stopping. The
-- drained art answers it at a glance and the blue edge says which of the two
-- kinds of no it is once the eye has landed.
--
-- Range does not get the drain, and the asymmetry is deliberate. Out of range
-- is a fact about one mob and it goes away when you take a step; out of rage
-- is a fact about you and it is the one that decides what to press.
--
-- Reaction is a new reason and takes no new look, which is the answer the two
-- paragraphs above ask for rather than a way of avoiding the question. A shut
-- Overpower window is not a state you can act on. You cannot walk out of it and
-- you cannot wait it out on purpose; it opens when the mob dodges you and never
-- otherwise, so there is nothing for a colour to tell you to do. That is the
-- definition of "no", and four of the ten statuses already sit there for the
-- same reason.
--
-- What says the window opened is the square leaving "no". On a bar that is a
-- jump from 55% drained grey to full colour, which is a bigger change than any
-- border in this table makes and is the one thing the eye catches in a row of
-- twenty-four. Giving the shut state its own colour would put a permanent
-- coloured edge on two squares for the length of every fight, which is the wall
-- of colour the paragraph at the top of this file argues against, and it would
-- spend that colour on the state you are meant to ignore.
--
-- Condition and notarget take no new look either, and for the reason reaction
-- does not. A target above a fifth of its health is not a state you can act on:
-- you cannot walk out of it, you cannot wait it out on purpose, and the fight
-- will hand it to you or it will not. That is the definition of "no". What says
-- Execute has come in is the square leaving "no", which on a bar is a jump from
-- 55% drained grey to full colour and is the biggest change any square makes.
--
-- Swap is drained, and it did not used to be. That was the defect this table
-- shipped with. Wrong stance is the one outcome here where the press will not
-- land and the art was drawn at ready brightness anyway, so the whole of what
-- the square said was an orange hairline, and a Whirlwind in Battle Stance read
-- as pressable across the room. The rule the rest of the table already follows
-- is the one it now follows: a fact about you drains the art, a fact about the
-- mob does not. Out of rage drains, out of range does not, and wrong stance is
-- a fact about you. The orange keeps saying there is something you can do about
-- it, which is what makes it worth a colour of its own rather than the grey.
--
-- Empty is pulled out for a different reason than range and cost are, and it is
-- the one that made a half filled bar look broken. An empty slot has no art, so
-- it fell to "no" and was drawn as the fallback question mark at 55% alpha:
-- twelve grey question marks where Blizzard's bar had twelve holes. `blank`
-- says draw no art at all, which is what a hole looks like.
--
-- Drawn at full alpha rather than faded, which looks backwards and is not. With
-- `blank` there is no art left to fade, so the alpha only reaches the black
-- backing and the hairline, and fading those leaves a drop target you cannot
-- see. Buttons/Bars.lua lets you drag a spell onto a square, so where the holes
-- are is a thing the bar has to answer. This is also why there is no grid: the
-- client shows one on ACTIONBAR_SHOWGRID because its bar has no background to
-- see a hole against, and this one is squares on a box.
local OUTCOME = {
	ready  = "go",
	stance = "swap",
	range  = "range",
	cost   = "cost",
	empty  = "empty",
}

-- What a look is: a border colour, whether to drain the art, and what alpha to
-- draw the whole square at. One table per outcome per palette, made once at
-- load and never rebuilt, because every ticker in this addon guards its writes
-- by comparing what it is about to draw against what it drew last and for a
-- look that comparison is table identity. A palette that built its answers
-- would make every square repaint five times a second forever.

-- One icon on the HUD or in the world, with nothing beside it to compare
-- against. Ready is worth a colour here.
Ability.SHOUT = {
	go    = { color = { 0.16, 0.80, 0.32 }, alpha = 1 },
	swap  = { color = { 0.96, 0.62, 0.16 }, alpha = 0.6, grey = true },
	range = { color = { 0.85, 0.25, 0.22 }, alpha = 0.6 },
	cost  = { color = { 0.29, 0.45, 0.85 }, alpha = 0.6, grey = true },
	empty = { color = { 0.20, 0.20, 0.24 }, alpha = 1, blank = true },
	no    = { color = { 0.38, 0.38, 0.43 }, alpha = 0.6, grey = true },
}

-- A square in a row of them. Ready is the common case and gets the quietest
-- edge in the palette, so what you see is the two or three buttons that are
-- not ready rather than the twenty that are.
Ability.QUIET = {
	go    = { color = { 0.16, 0.16, 0.19 }, alpha = 1 },
	swap  = { color = { 0.96, 0.62, 0.16 }, alpha = 1, grey = true },
	range = { color = { 0.85, 0.25, 0.22 }, alpha = 1 },
	cost  = { color = { 0.29, 0.45, 0.85 }, alpha = 1, grey = true },
	empty = { color = { 0.13, 0.13, 0.16 }, alpha = 1, blank = true },
	no    = { color = { 0.16, 0.16, 0.19 }, alpha = 0.55, grey = true },
}

-- The look one status is worth in one palette. Called from every ticker that
-- draws a square, so it does no work beyond two table lookups and never
-- allocates.
function Ability.Look(palette, status)
	return palette[OUTCOME[status] or "no"]
end

--------------------------------------------------------------------------
-- Building one
--------------------------------------------------------------------------

local FALLBACK_TEXTURE = "Interface\\Icons\\INV_Misc_QuestionMark"

-- How much of the square the timer and the count take, as a fraction of its
-- side. Both are read at Ability.Size, so a square that changes size changes
-- its type with it and the two never drift into a fixed point size that is
-- right at 54 and unreadable at 27.
local TIMER_SHARE = 0.42
local COUNT_SHARE = 0.30
local KEY_SHARE = 0.26

-- A square. The caller owns the frame's identity: `template` is what makes it
-- pressable, and passing nil makes a plain frame that only draws, which is
-- what the world marker is.
--
-- `palette` is one of the two above, or any table with the same five keys.
-- Held on the widget rather than passed to every Draw, because it never
-- changes for the life of a button and a per-tick argument that never changes
-- is an argument that gets passed wrongly once.
function Ability.New(parent, name, template, palette)
	local kind = template and "Button" or "Frame"
	local w = CreateFrame(kind, name, parent, template)

	w.palette = palette or Ability.SHOUT

	-- The backing, which is what shows through as the one pixel frame around
	-- the art. Solid black rather than the border's colour: a coloured edge on
	-- a coloured icon needs a dark gap between them or the two blend at every
	-- boundary and the edge stops reading as an edge.
	w.backing = ns.Fill(w, "BACKGROUND", 0, 0, 0, 1)
	w.backing:SetAllPoints()

	w.icon = UI.Icon(w, "ARTWORK")

	-- Already what is running: the stance you are standing in, the auto attack
	-- already swinging. Additive rather than a border colour, because it is not
	-- a rung on the status ladder and must be able to sit on top of any rung
	-- without arguing with it. A square can be the active stance and out of
	-- rage at the same time and both are worth saying.
	w.active = ns.Fill(w, "OVERLAY", 1, 0.84, 0.32, 0.22)
	w.active:SetBlendMode("ADD")
	w.active:Hide()

	-- The edge of the same fact. Four textures on the art's own bounds, laid
	-- out exactly where the equipped ring is laid out, and built after it so
	-- that on the one square that is both they draw over it.
	--
	-- That is a real decision and not an accident of order. Two rings one pixel
	-- apart on a 27 pixel square is mush, so there is only room for one and it
	-- has to be picked. Being armed is momentary and being worn is not: a
	-- weapon you are wielding is still wielded a second from now and the ring
	-- comes back the moment the swing lands, where an armed press missed is a
	-- press you make again.
	w.armed = {}
	for index = 1, 4 do
		w.armed[index] = ns.Fill(w, "OVERLAY", 1, 0.82, 0.28, 1)
		w.armed[index]:Hide()
	end

	-- Worn or wielded. Four edges anchored to the art rather than to the frame,
	-- which lands them exactly one pixel inside the status border, and on
	-- OVERLAY rather than BORDER because BORDER is under the art and a ring
	-- drawn on the art's own bounds would be covered by it.
	w.equipped = {}
	for index = 1, 4 do
		w.equipped[index] = ns.Fill(w, "OVERLAY", 0.24, 0.78, 0.35, 1)
		w.equipped[index]:Hide()
	end

	-- Four edge textures rather than one recoloured background, so the border
	-- can be a real hairline at any square size instead of a fixed inset. This
	-- is the piece both charge displays were missing.
	w.edges = ns.Outline(w, 0, 0, 0, 1)

	-- Under the cursor. The HIGHLIGHT draw layer is the one the client shows
	-- and hides by itself for any frame that takes the mouse, so this is a
	-- texture and no script at all. Drawn for the world marker too, which costs
	-- one texture nobody will ever hover.
	w.hover = ns.Fill(w, "HIGHLIGHT", 1, 1, 1, 0.16)

	-- On the way down. The Button widget draws this itself between mouse down
	-- and mouse up, whatever RegisterForClicks says the press is worth, so a
	-- click has an answer even on a spell whose whole cooldown is the global.
	-- A Frame has no pushed state and SetPushedTexture is not on it.
	if kind == "Button" then
		w:SetPushedTexture("Interface\\Buttons\\WHITE8X8")
		local pushed = w:GetPushedTexture()
		if pushed then
			pushed:SetColorTexture(0, 0, 0, 0.36)
			w.pushed = pushed
		end
	end

	w.cooldown = CreateFrame("Cooldown", name and (name .. "Cooldown") or nil, w,
		"CooldownFrameTemplate")
	if w.cooldown.SetHideCountdownNumbers then
		w.cooldown:SetHideCountdownNumbers(true) -- this file draws its own
	end
	-- The swipe covers the whole icon, so anything it took would be a click on
	-- the ability. Said rather than assumed: a Cooldown is a frame, what a
	-- frame does with the mouse is the template's business, and a square you
	-- cannot press is indistinguishable from a square that is drawn wrong.
	w.cooldown:EnableMouse(false)
	-- The swipe covers the whole icon, so anything it took would be a click on
	-- the ability. Said rather than assumed: a Cooldown is a frame, what a
	-- frame does with the mouse is the template's business, and a square you
	-- cannot press is indistinguishable from a square that is drawn wrong.

	w.timer = UI.Label(w, 12, nil, "CENTER", UI.SHADOW)
	w.timer:SetPoint("CENTER")

	-- The stack or charge count, bottom right, where every action bar in the
	-- game has put it for twenty years.
	w.count = UI.Label(w, 10, nil, "RIGHT", UI.SHADOW)

	-- The key that presses it. Set once by the caller and never touched by the
	-- tick, because a binding changes when you change it and not otherwise.
	w.key = UI.Label(w, 10, nil, "RIGHT", UI.SHADOW)

	-- How much of the look's own alpha to draw at, which is the caller's half
	-- of visibility. A look says how loud a status is; a fade says whether the
	-- square is wanted on screen at all, which is a question about settings and
	-- about whether you are placing the thing, not about the ability. The two
	-- are multiplied in Ability.Draw so that neither ever overwrites the other,
	-- which is what happened when the charge icon set its own alpha after the
	-- look had set one.
	w.fade = 1

	-- What was last drawn. Every one of these is compared before its write in
	-- Ability.Draw, and they start as values no first draw can equal so that
	-- the first draw writes everything.
	w.shownTexture = nil
	w.shownLook = nil
	w.shownAlpha = -1
	w.shownStart, w.shownDuration = -1, -1
	w.shownCount = -1
	w.shownTick = nil
	w.shownActive = nil
	w.shownEquipped = nil

	return w
end

-- Lay the square out. Everything inside is derived from the one number: the
-- icon is inset by a hairline for the backing to show through, and all three
-- strings are sized as a fraction of the side.
--
-- `side` is in the frame's own units, not in design pixels. The conversion
-- belongs at the call site and not here, which is the rule UnitFrames/Skin.lua
-- already follows when it writes `side * px`. A square on the grid passes the
-- design number straight through, because there one unit is one pixel. A
-- square that is not on the grid, which is both charge displays, passes
-- whatever its own setting says and keeps the size it has always had.
--
-- The hairline is the exception and is asked for in pixels, because it means
-- one screen pixel in both cases. That is the whole of the difference between
-- UI.Pixel and UI.Unit, stated in UI/Pixel.lua.
--
-- Called on a settings change and on a rescale, never on a tick.
function Ability.Size(w, side)
	local edge = UI.Pixel(w)

	w:SetSize(side, side)

	-- The art, inset by one real pixel on every edge. Written in pixels rather
	-- than in design units because it is a hairline: it stays one pixel when
	-- the design grows, which is the rule UI/Pixel.lua states for the
	-- difference between UI.Pixel and UI.Unit.
	w.icon:ClearAllPoints()
	w.icon:SetPoint("TOPLEFT", w, "TOPLEFT", edge, -edge)
	w.icon:SetPoint("BOTTOMRIGHT", w, "BOTTOMRIGHT", -edge, edge)

	ns.EdgeSize(w.edges, edge)
	w.cooldown:ClearAllPoints()
	w.cooldown:SetAllPoints(w.icon)

	-- Both cover the art and not the frame, so the hairline border stays a
	-- border under a hover and under a press rather than being tinted with
	-- everything else.
	w.hover:ClearAllPoints()
	w.hover:SetAllPoints(w.icon)
	w.active:ClearAllPoints()
	w.active:SetAllPoints(w.icon)

	-- Anchored to the art on both ends of each edge, so the ring is inside the
	-- status border at any square size rather than at a fixed inset.
	local ring = w.equipped
	for index = 1, 4 do
		ring[index]:ClearAllPoints()
	end
	ring[1]:SetPoint("TOPLEFT", w.icon, "TOPLEFT")
	ring[1]:SetPoint("TOPRIGHT", w.icon, "TOPRIGHT")
	ring[2]:SetPoint("BOTTOMLEFT", w.icon, "BOTTOMLEFT")
	ring[2]:SetPoint("BOTTOMRIGHT", w.icon, "BOTTOMRIGHT")
	ring[3]:SetPoint("TOPLEFT", w.icon, "TOPLEFT")
	ring[3]:SetPoint("BOTTOMLEFT", w.icon, "BOTTOMLEFT")
	ring[4]:SetPoint("TOPRIGHT", w.icon, "TOPRIGHT")
	ring[4]:SetPoint("BOTTOMRIGHT", w.icon, "BOTTOMRIGHT")
	ns.EdgeSize(ring, edge)

	-- The armed ring sits exactly where the equipped one does, for the reason
	-- Ability.New states. Anchored to the same four corners rather than to the
	-- ring's textures, so neither depends on the other having been laid out.
	local armed = w.armed
	for index = 1, 4 do
		armed[index]:ClearAllPoints()
	end
	armed[1]:SetPoint("TOPLEFT", w.icon, "TOPLEFT")
	armed[1]:SetPoint("TOPRIGHT", w.icon, "TOPRIGHT")
	armed[2]:SetPoint("BOTTOMLEFT", w.icon, "BOTTOMLEFT")
	armed[2]:SetPoint("BOTTOMRIGHT", w.icon, "BOTTOMRIGHT")
	armed[3]:SetPoint("TOPLEFT", w.icon, "TOPLEFT")
	armed[3]:SetPoint("BOTTOMLEFT", w.icon, "BOTTOMLEFT")
	armed[4]:SetPoint("TOPRIGHT", w.icon, "TOPRIGHT")
	armed[4]:SetPoint("BOTTOMRIGHT", w.icon, "BOTTOMRIGHT")
	ns.EdgeSize(armed, edge)

	if w.pushed then
		w.pushed:ClearAllPoints()
		w.pushed:SetAllPoints(w.icon)
	end

	-- Whole pixels, because a font size that lands on a fraction is a glyph
	-- rasterised across two rows and that is exactly what a timer must not be.
	-- UI.NumberFont is the shadowed role at every size, which is what all three
	-- of these want: they sit on a spell icon this addon did not paint.
	local timer = math.max(math.floor(side * TIMER_SHARE), 8)
	local count = math.max(math.floor(side * COUNT_SHARE), 7)
	local key = math.max(math.floor(side * KEY_SHARE), 7)

	w.timer:SetFontObject(UI.NumberFont(timer))
	w.count:SetFontObject(UI.NumberFont(count))
	w.key:SetFontObject(UI.NumberFont(key))

	w.count:ClearAllPoints()
	w.count:SetPoint("BOTTOMRIGHT", w, "BOTTOMRIGHT", -edge, edge)
	w.key:ClearAllPoints()
	w.key:SetPoint("TOPRIGHT", w, "TOPRIGHT", -edge, -edge)

	return side
end

-- The key that presses this square, or "" for none. Once per binding change.
function Ability.Bind(w, text)
	w.key:SetText(text or "")
end

--------------------------------------------------------------------------
-- Drawing one
--
-- On the ticker. Nothing below allocates and nothing writes a value already on
-- the widget, and check.sh enforces both.
--------------------------------------------------------------------------

-- Minutes above a minute, whole seconds above ten, tenths below it. Returned as
-- an integer so the caller can compare it against the last one without building
-- the string it would print: the string is the expensive half and it is only
-- worth making when the number behind it has actually moved.
--
-- Three scales and each one is offset out of the others' range, because a
-- countdown crossing from one to the next has to compare unequal or the tick
-- that crossed leaves the old scale's string on screen. The tenths come back
-- negative and the minutes come back past ten thousand; without either, 5.0
-- seconds and 50 both answer 50, and two minutes and the number 2 both answer 2.
--
-- The minute scale is what the cooldown row asked for and every action bar
-- square gets it too. A thirty minute Recklessness drew "1798" on a 27 pixel
-- square, which is four digits of false precision about a number nobody reads
-- to the second.
--
-- It rounds down, so 1m means a minute or more and the ladder has no gap in it:
-- 3m, 2m, 1m, then 59 and the seconds. Rounding up reads as the safer choice
-- and is not, because ceil(119/60) and ceil(61/60) are both 2 and the label
-- would go from 2m straight to 59 without ever saying 1m, which looks like a
-- square that skipped a number.
local function Quantum(remaining)
	if remaining >= 60 then
		return 10000 + math.floor(remaining / 60)
	end
	if remaining >= 10 then
		return math.floor(remaining)
	end
	return -math.floor(remaining * 10)
end

-- The three scales written out, on the ticks where Quantum says the number has
-- moved. Its own function rather than four more lines inside Ability.Draw,
-- which is at the shape gate's hundred line ceiling: what a countdown reads is
-- a different job from what a square draws, and this is the only part of the
-- tick that builds a string.
local function Countdown(text, remaining)
	if remaining >= 60 then
		text:SetText(("%dm"):format(math.floor(remaining / 60)))
	elseif remaining >= 10 then
		text:SetText(("%d"):format(remaining))
	else
		text:SetText(("%.1f"):format(remaining))
	end
end

-- One square, one tick. `texture` is the art, `status` one of Ability.STATUS,
-- `start` and `duration` the cooldown when there is one, `count` a stack or
-- charge number, `active` whether the ability is already what is running, and
-- `equipped` whether the item in the slot is worn.
--
-- Deliberately eight arguments rather than one table. A table would be an
-- allocation per square per tick, which at twenty-four buttons five times a
-- second is a hundred and twenty throwaway tables a second to say what eight
-- values already say.
--
-- Eight is the ceiling and the last two are both booleans, which is the shape
-- that gets passed in the wrong order eventually. A ninth fact about a square
-- is the point at which this takes a table built once per widget and mutated,
-- rather than one more positional flag.
--
-- `start` and `duration` are the swipe and are drawn whenever they are given.
-- `status` says whether the swipe also gets a number over it, and it is only
-- "cooldown" for a wait longer than the global. That split is the difference
-- between a bar that answers a press and one that does not: below the global
-- there is nothing to count down, and a bar that drew nothing at all there was
-- a bar where pressing a rage dump changed no pixel on the screen.
function Ability.Draw(w, texture, status, start, duration, count, active, equipped)
	-- Read before the art, because whether an empty square draws the fallback
	-- question mark or nothing at all is the look's decision and not the
	-- texture's.
	local look = Ability.Look(w.palette, status)

	local art = texture
	if not art and not look.blank then
		art = FALLBACK_TEXTURE
	end
	if art ~= w.shownTexture then
		w.shownTexture = art
		-- nil blanks the texture, which is what an empty slot looks like on
		-- every action bar the game has ever shipped.
		w.icon:SetTexture(art)
	end

	-- Guarded on the look's identity rather than on its two drawn fields,
	-- because a palette hands back the same table for the same outcome every
	-- time and one comparison replaces two.
	if look ~= w.shownLook then
		w.shownLook = look
		ns.Recolor(w.edges, look.color)
		w.icon:SetDesaturated(look.grey and true or false)
	end

	-- Alpha is guarded on the product rather than inside the look's guard,
	-- because the fade moves without the status moving: mode "ready" hides the
	-- charge icon while it is on cooldown, and unlocking the frames shows it
	-- again whatever it is doing. Folded in here so there is one write.
	local alpha = look.alpha * w.fade
	if alpha ~= w.shownAlpha then
		w.shownAlpha = alpha
		w:SetAlpha(alpha)
	end

	-- The swipe. Driven by the numbers alone, so a global cooldown sweeps the
	-- square without the status having moved and without the art going grey.
	if start and duration and duration > 0 then
		if start ~= w.shownStart or duration ~= w.shownDuration then
			w.shownStart, w.shownDuration = start, duration
			w.cooldown:SetCooldown(start, duration)
		end
	elseif w.shownDuration ~= 0 then
		w.shownStart, w.shownDuration = 0, 0
		w.cooldown:SetCooldown(0, 0)
	end

	-- The number over it, which only a real cooldown gets. A global is one and
	-- a half seconds and the swipe has already said so.
	if status == "cooldown" then
		-- The string is built only when the number it would show has moved,
		-- which at a tenth of a second between ticks is most ticks skipped
		-- once the countdown is above ten seconds.
		local remaining = start + duration - GetTime()
		local tick = Quantum(remaining)
		if tick ~= w.shownTick then
			w.shownTick = tick
			Countdown(w.timer, remaining)
		end
	elseif w.shownTick ~= nil then
		w.shownTick = nil
		w.timer:SetText("")
	end

	-- One comparison for the tint and the ring, because they are two halves of
	-- one fact and can never disagree.
	local on = active and true or false
	if on ~= w.shownActive then
		w.shownActive = on
		w.active:SetShown(on)
		local armed = w.armed
		for index = 1, 4 do
			armed[index]:SetShown(on)
		end
	end

	local worn = equipped and true or false
	if worn ~= w.shownEquipped then
		w.shownEquipped = worn
		local ring = w.equipped
		for index = 1, 4 do
			ring[index]:SetShown(worn)
		end
	end

	if count ~= w.shownCount then
		w.shownCount = count
		if count and count > 1 then
			w.count:SetText(("%d"):format(count))
		else
			w.count:SetText("")
		end
	end
end
