-- Moteve Damage Meter 0.3 ("arcane glass" style, like Moteve Quest / Moteve Chat)
-- Built on Blizzard's C_DamageMeter API (the combat log is not available to addons on WoW Forever).
-- In combat most values are "secret": they can be handed to widgets (StatusBar/FontString)
-- but not compared, summed or formatted. Percentages and spell breakdowns appear after combat.

local ADDON_NAME, ns = ...

local DM = C_DamageMeter
local format, floor, max, min = string.format, math.floor, math.max, math.min

---------------------------------------------------------------------------
-- Theme: light "arcane glass" like Moteve Quest / Moteve Chat - no frame, a faint backdrop that
-- gets stronger on hover, thin glowing class-coloured lines instead of heavy bars.
---------------------------------------------------------------------------
local WHITE = ns.WHITE
local P = ns.C
local C = {
    text   = P.text,
    sub    = P.sub,
    muted  = P.muted,
    low    = P.low,
    accent1 = P.cyan,
    accent2 = P.violet,
    hover  = { 1, 1, 1, 0.05 },
    track  = { 1, 1, 1, 0.08 },
    hairline = { P.edge[1], P.edge[2], P.edge[3], 0.18 },
}

local HEADER_H, FOOTER_H = 24, 18
local BAR_H, GAP, PAD = 22, 3, 12

---------------------------------------------------------------------------
-- Modes / sessions
---------------------------------------------------------------------------
local T  = (Enum and Enum.DamageMeterType) or {}
local ST = (Enum and Enum.DamageMeterSessionType) or {}
local SESSION_OVERALL = ST.Overall or 0
local SESSION_CURRENT = ST.Current or 1

local MODES = {
    { id = T.DamageDone  or 0, label = "Sebzés",          rate = "DPS" },
    { id = T.HealingDone or 2, label = "Gyógyítás",       rate = "HPS" },
    { id = T.Absorbs     or 4, label = "Elnyelés",        rate = "APS" },
    { id = T.DamageTaken or 7, label = "Kapott sebzés",   rate = "DTPS" },
    { id = T.Interrupts  or 5, label = "Megszakítások" },
    { id = T.Dispels     or 6, label = "Dispelek" },
}

local DEFAULTS = {
    point = "CENTER", relPoint = "CENTER", x = 300, y = -100,
    w = 300, h = 214, scale = 1,
    mode = 1, segment = SESSION_CURRENT,
    locked = false, shown = true,
}

local db
local Moteve = CreateFrame("Frame", "MoteveFrame", UIParent)
Moteve:Hide()

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function IsSecret(v)
    if issecretvalue then return issecretvalue(v) end
    return false
end

local function Short(n)
    if n >= 1e9 then return format("%.2fB", n / 1e9)
    elseif n >= 1e6 then return format("%.2fM", n / 1e6)
    elseif n >= 1e4 then return format("%.1fK", n / 1e3)
    end
    return format("%d", floor(n + 0.5))
end

-- Writes a number that may be secret. Secret numbers are passed to the client untouched.
local function SetNum(fs, v)
    if IsSecret(v) then
        local ok, s = pcall(AbbreviateNumbers, v)
        if ok then fs:SetText(s) return end
        ok, s = pcall(format, "%.0f", v)
        if ok then fs:SetText(s) return end
        fs:SetText(v)
        return
    end
    fs:SetText(Short(v or 0))
end

-- per-second values: whole numbers, never abbreviated (2769, not 2.8K)
local function Int(n) return format("%d", floor((n or 0) + 0.5)) end
local function SetRate(fs, v)
    if IsSecret(v) then
        local ok, s = pcall(format, "%.0f", v)
        if ok then fs:SetText(s) return end
        fs:SetText(v)
        return
    end
    fs:SetText(Int(v))
end

local function Clock(sec)
    sec = floor(sec + 0.5)
    return format("%d:%02d", floor(sec / 60), sec % 60)
end

local function ClassColor(classFile)
    if type(classFile) ~= "string" or classFile == "" then return 0.42, 0.45, 0.52 end
    if C_ClassColor and C_ClassColor.GetClassColor then
        local col = C_ClassColor.GetClassColor(classFile)
        if col then return col.r, col.g, col.b end
    end
    local col = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if col then return col.r, col.g, col.b end
    return 0.42, 0.45, 0.52
end

local function Tex(parent, layer, c, sub)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sub)
    t:SetTexture(WHITE)
    if c then t:SetVertexColor(c[1], c[2], c[3], c[4] or 1) end
    return t
end

local function Font(parent, size, c, justify, kind)
    local fs = ns.Font(parent, kind or "body", size or 12, c, justify)
    fs:SetShadowColor(0, 0, 0, 0.9)
    fs:SetShadowOffset(1, -1)
    return fs
end

local function SetFontSize(fs, kind, size) ns.SetFontKind(fs, kind, size) end

local function Chevron(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(8, 5)
    local l = Tex(f, "OVERLAY", C.sub)
    l:SetSize(5, 1.5); l:SetPoint("CENTER", -1.6, 0); l:SetRotation(-math.pi / 4)
    local r = Tex(f, "OVERLAY", C.sub)
    r:SetSize(5, 1.5); r:SetPoint("CENTER", 1.6, 0); r:SetRotation(math.pi / 4)
    f.parts = { l, r }
    return f
end

---------------------------------------------------------------------------
-- Main panel + header
---------------------------------------------------------------------------
Moteve:SetFrameStrata("MEDIUM")
Moteve:SetMovable(true)
Moteve:SetResizable(true)
Moteve:SetClampedToScreen(true)
if Moteve.SetResizeBounds then Moteve:SetResizeBounds(200, 110, 640, 800) end

-- faint rounded backdrop; stronger while the mouse is over the meter
local glass = ns.Glass(Moteve, { radius = 12, alpha = 0.32, edge = 0.0, shadow = false })
glass.line:Hide(); glass.sheen:Hide()
local function Backdrop(strong)
    glass.fill:SetColor(P.glass, strong and 0.62 or 0.32)
end

local header = CreateFrame("Frame", nil, Moteve)
header:SetPoint("TOPLEFT", 0, 0); header:SetPoint("TOPRIGHT", 0, 0)
header:SetHeight(HEADER_H)
header:EnableMouse(true)
header:RegisterForDrag("LeftButton")

local title = Font(header, 10, C.sub, "LEFT", "bold")
title:SetPoint("LEFT", PAD, -1)
title:SetText("MOTEVE")
title:SetAlpha(0.8)

-- mode dropdown button
local modeBtn = CreateFrame("Button", nil, header)
modeBtn:SetPoint("LEFT", title, "RIGHT", 6, 0)
modeBtn:SetHeight(HEADER_H - 6)
local modeHl = ns.Slice(modeBtn, "round", 0.25, "BACKGROUND", 1):Fit(modeBtn, 6)
modeHl:SetColor({ 1, 1, 1 }, 0.07); modeHl:Hide()
modeBtn.text = Font(modeBtn, 12, C.text, "LEFT", "bold")
modeBtn.text:SetPoint("LEFT", 5, 0)
modeBtn.chev = Chevron(modeBtn)
modeBtn.chev:SetPoint("LEFT", modeBtn.text, "RIGHT", 5, -1)

local segText = Font(header, 11, C.muted, "RIGHT")
segText:SetPoint("RIGHT", -PAD, -1)

---------------------------------------------------------------------------
-- Footer
---------------------------------------------------------------------------
local footer = CreateFrame("Frame", nil, Moteve)
footer:SetPoint("BOTTOMLEFT", 0, 2); footer:SetPoint("BOTTOMRIGHT", 0, 2)
footer:SetHeight(FOOTER_H)

local liveDot = ns.Img(footer, "circle", "OVERLAY", 1, C.accent2, 1)
liveDot:SetSize(6, 6)
liveDot:SetPoint("LEFT", PAD, 0)
local liveGlow = ns.Img(footer, "glow", "OVERLAY", 0, C.accent2, 0.8)
liveGlow:SetBlendMode("ADD"); liveGlow:SetSize(18, 18); liveGlow:SetPoint("CENTER", liveDot)
local pulse = liveDot:CreateAnimationGroup()
pulse:SetLooping("BOUNCE")
local pa = pulse:CreateAnimation("Alpha")
pa:SetFromAlpha(1); pa:SetToAlpha(0.25); pa:SetDuration(0.7)

local footLeft = Font(footer, 11, C.muted)
footLeft:SetPoint("LEFT", PAD, 0)
local footRight = Font(footer, 11, C.muted, "RIGHT")
footRight:SetPoint("RIGHT", -20, 0)
local footTotal = Font(footer, 11, C.sub, "RIGHT", "bold")
footTotal:SetPoint("RIGHT", footRight, "LEFT", -4, 0)

---------------------------------------------------------------------------
-- Dropdown
---------------------------------------------------------------------------
local menu = CreateFrame("Frame", "MoteveDropdown", UIParent)
menu:SetFrameStrata("FULLSCREEN_DIALOG")
menu:SetClampedToScreen(true)
menu:EnableMouse(true)
menu:SetWidth(180)
menu:Hide()
ns.Glass(menu, { radius = 10, alpha = 0.94, edge = 0.28 })
tinsert(UISpecialFrames, "MoteveDropdown") -- closes on Escape

-- invisible click-catcher closes the menu when clicking elsewhere
local catcher = CreateFrame("Button", nil, UIParent)
catcher:SetAllPoints(UIParent)
catcher:SetFrameStrata("FULLSCREEN")
catcher:RegisterForClicks("AnyDown")
catcher:SetScript("OnClick", function() menu:Hide() end)
catcher:Hide()
menu:SetScript("OnShow", function() catcher:Show() end)
menu:SetScript("OnHide", function() catcher:Hide() end)

local menuItems = {}
local ITEM_H = 22

local function MenuItem(i)
    local it = menuItems[i]
    if it then return it end
    it = CreateFrame("Button", nil, menu)
    it:SetHeight(ITEM_H)
    it.hl = ns.Slice(it, "round", 0.25, "BACKGROUND", 1):Fit(it, 6); it.hl:SetColor({ 1, 1, 1 }, 0.07); it.hl:Hide()
    it.check = ns.Img(it, "circle", "ARTWORK", 1, C.accent2, 1); it.check:SetSize(6, 6); it.check:SetPoint("LEFT", 10, 0)
    it.text = Font(it, 12, C.sub); it.text:SetPoint("LEFT", 22, 0); it.text:SetPoint("RIGHT", -8, 0)
    it.line = Tex(it, "ARTWORK", C.hairline); it.line:SetPoint("LEFT", 8, 0); it.line:SetPoint("RIGHT", -8, 0); it.line:SetHeight(1)
    it:SetScript("OnEnter", function(self) if self.kind == "option" then self.hl:Show() end end)
    it:SetScript("OnLeave", function(self) self.hl:Hide() end)
    it:SetScript("OnClick", function(self)
        if self.kind == "option" and self.onClick then
            self.onClick()
            menu:Hide()
        end
    end)
    menuItems[i] = it
    return it
end

local function BuildMenu(spec)
    local y = -5
    for i, s in ipairs(spec) do
        local it = MenuItem(i)
        it.kind, it.onClick = s.kind, s.onClick
        it:ClearAllPoints()
        it:SetPoint("TOPLEFT", 5, y); it:SetPoint("RIGHT", -5, 0)
        it.check:Hide(); it.line:Hide(); it.hl:Hide()
        it.text:SetText("")
        if s.kind == "header" then
            it:SetHeight(16)
            SetFontSize(it.text, "bold", 10)
            it.text:SetTextColor(C.muted[1], C.muted[2], C.muted[3])
            it.text:SetPoint("LEFT", 12, 0)
            it.text:SetText(s.text)
            it:EnableMouse(false)
        elseif s.kind == "sep" then
            it:SetHeight(7)
            it.line:Show()
            it:EnableMouse(false)
        else
            it:SetHeight(ITEM_H)
            SetFontSize(it.text, "body", 12)
            it.text:SetPoint("LEFT", 22, 0)
            it.text:SetText(s.text)
            local on = s.checked and s.checked()
            it.check:SetShown(on)
            local c = on and C.text or (s.danger and { 1, 0.45, 0.45 } or C.sub)
            it.text:SetTextColor(c[1], c[2], c[3])
            it:EnableMouse(true)
        end
        it:Show()
        y = y - it:GetHeight()
    end
    for i = #spec + 1, #menuItems do menuItems[i]:Hide() end
    menu:SetHeight(-y + 5)
end

local ResetData -- forward

local function OpenMenu(anchor)
    if menu:IsShown() then menu:Hide() return end
    local spec = { { kind = "header", text = "MUTASD" } }
    for i, m in ipairs(MODES) do
        spec[#spec + 1] = {
            kind = "option", text = m.label,
            checked = function() return db.mode == i end,
            onClick = function() db.mode = i; Moteve:ResetScroll(); Moteve:Refresh() end,
        }
    end
    spec[#spec + 1] = { kind = "sep" }
    spec[#spec + 1] = { kind = "header", text = "SZAKASZ" }
    spec[#spec + 1] = { kind = "option", text = "Aktuális harc",
        checked = function() return db.segment == SESSION_CURRENT end,
        onClick = function() db.segment = SESSION_CURRENT; Moteve:ResetScroll(); Moteve:Refresh() end }
    spec[#spec + 1] = { kind = "option", text = "Összesített",
        checked = function() return db.segment == SESSION_OVERALL end,
        onClick = function() db.segment = SESSION_OVERALL; Moteve:ResetScroll(); Moteve:Refresh() end }
    spec[#spec + 1] = { kind = "sep" }
    spec[#spec + 1] = { kind = "option", text = "Adatok törlése", danger = true, onClick = function() ResetData() end }
    spec[#spec + 1] = { kind = "option", text = db.locked and "Ablak feloldása" or "Ablak zárolása",
        onClick = function() Moteve:SetLocked(not db.locked) end }

    BuildMenu(spec)
    menu:SetScale(Moteve:GetEffectiveScale() / UIParent:GetEffectiveScale())
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
    menu:Show()
end

modeBtn:SetScript("OnClick", function(self) OpenMenu(self) end)
modeBtn:SetScript("OnEnter", function() modeHl:Show() end)
modeBtn:SetScript("OnLeave", function() modeHl:Hide() end)

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------
local content = CreateFrame("Frame", nil, Moteve)
content:SetPoint("TOPLEFT", 0, -HEADER_H - PAD)
content:SetPoint("BOTTOMRIGHT", 0, FOOTER_H + PAD)
content:EnableMouseWheel(true)

local emptyText = Font(content, 11, C.sub, "CENTER")
emptyText:SetPoint("CENTER", 0, 6)
local emptySub = Font(content, 10, C.muted, "CENTER")
emptySub:SetPoint("TOP", emptyText, "BOTTOM", 0, -4)

local rows = {}
local scrollOffset = 0

function Moteve:ResetScroll() scrollOffset = 0 end

local function RowTooltip(row)
    local src = row.source
    if not src then return end
    GameTooltip:SetOwner(row, "ANCHOR_LEFT")

    local name = src.name
    if IsSecret(name) then
        GameTooltip:SetText(name)
    else
        GameTooltip:SetText(name and Ambiguate(name, "short") or "?", ClassColor(src.classFilename))
    end

    local guid = src.sourceGUID
    if IsSecret(guid) or IsSecret(src.totalAmount) then
        GameTooltip:AddLine("A spellenkénti bontás harc után látszik.", C.muted[1], C.muted[2], C.muted[3])
        GameTooltip:Show()
        return
    end

    local mode = MODES[db.mode]
    local ok, detail = pcall(DM.GetCombatSessionSourceFromType, db.segment, mode.id, guid, src.sourceCreatureID)
    local spells = ok and detail and detail.combatSpells
    if not spells or #spells == 0 then
        GameTooltip:AddLine("Nincs spell-adat.", C.muted[1], C.muted[2], C.muted[3])
        GameTooltip:Show()
        return
    end

    local list, total = {}, 0
    for i = 1, #spells do
        list[i] = spells[i]
        total = total + (spells[i].totalAmount or 0)
    end
    table.sort(list, function(a, b) return (a.totalAmount or 0) > (b.totalAmount or 0) end)

    GameTooltip:AddLine(" ")
    for i = 1, min(8, #list) do
        local s = list[i]
        local sName = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(s.spellID)) or ("Spell " .. tostring(s.spellID))
        local icon = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(s.spellID)
        local left = icon and format("|T%s:14:14:0:0:64:64:5:59:5:59|t  %s", icon, sName) or sName
        local right = Short(s.totalAmount or 0)
        if mode.rate and s.amountPerSecond then right = right .. "  |cff8c93a6" .. Int(s.amountPerSecond) .. "|r" end
        if total > 0 then right = right .. format("  |cff6f7585%.0f%%|r", (s.totalAmount or 0) / total * 100) end
        GameTooltip:AddDoubleLine(left, right, 1, 1, 1, C.text[1], C.text[2], C.text[3])
    end
    GameTooltip:Show()
end

local function CreateRow(i)
    local row = CreateFrame("Button", nil, content)
    row:SetHeight(BAR_H)

    row.hl = row:CreateTexture(nil, "BACKGROUND")
    row.hl:SetPoint("TOPLEFT", PAD - 6, 1); row.hl:SetPoint("BOTTOMRIGHT", -PAD + 6, -1)
    ns.Grad(row.hl, "HORIZONTAL", P.edge, 0.10, P.edge, 0.02)
    row.hl:Hide()

    -- thin glowing line under the name: the "bar"
    local bar = CreateFrame("StatusBar", nil, row)
    bar:SetPoint("BOTTOMLEFT", PAD, 1)
    bar:SetPoint("BOTTOMRIGHT", -PAD, 1)
    bar:SetHeight(2)
    bar:SetStatusBarTexture(WHITE)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    row.bar = bar
    row.fill = bar:GetStatusBarTexture()
    local track = Tex(bar, "BACKGROUND", C.track)
    track:SetAllPoints()
    row.glow = ns.Img(bar, "glow", "ARTWORK", -1)
    row.glow:SetBlendMode("ADD")
    row.glow:SetPoint("TOPLEFT", row.fill, "TOPLEFT", -3, 4)
    row.glow:SetPoint("BOTTOMRIGHT", row.fill, "BOTTOMRIGHT", 3, -4)

    -- marker for your own line: small violet dot
    row.selfMark = ns.Img(row, "circle", "OVERLAY", 1, C.accent2, 1)
    row.selfMark:SetSize(5, 5)
    row.selfMark:SetPoint("LEFT", PAD - 9, 2)
    row.selfMark:Hide()

    local tl = CreateFrame("Frame", nil, row)
    tl:SetPoint("TOPLEFT", PAD, 0)
    tl:SetPoint("BOTTOMRIGHT", -PAD, 4)

    row.rank = Font(tl, 11, C.low)
    row.rank:SetPoint("LEFT", 0, 0)
    row.rank:SetWidth(16)

    row.pct = Font(tl, 11, C.muted, "RIGHT")
    row.pct:SetWidth(32)
    row.rate = Font(tl, 11, C.sub, "RIGHT")
    row.rate:SetWidth(52)
    row.total = Font(tl, 12, C.text, "RIGHT", "bold")
    row.tl = tl

    row.name = Font(tl, 12.5, C.text)
    row.name:SetPoint("LEFT", row.rank, "RIGHT", 2, 0)
    row.name:SetPoint("RIGHT", row.total, "LEFT", -6, 0)

    row:SetScript("OnEnter", function(self) self.hl:Show(); RowTooltip(self) end)
    row:SetScript("OnLeave", function(self) self.hl:Hide(); GameTooltip:Hide() end)

    rows[i] = row
    return row
end

-- right-side columns: [total] [rate] [pct]; rate/pct collapse when not used
local function LayoutColumns(row, showRate, showPct)
    row.pct:ClearAllPoints(); row.rate:ClearAllPoints(); row.total:ClearAllPoints()
    local anchor, point, x = row.tl, "RIGHT", 0
    if showPct then
        row.pct:SetPoint("RIGHT", anchor, point, x, 0); row.pct:Show()
        anchor, point, x = row.pct, "LEFT", -4
    else
        row.pct:Hide()
    end
    if showRate then
        row.rate:SetPoint("RIGHT", anchor, point, x, 0); row.rate:Show()
        anchor, point, x = row.rate, "LEFT", -4
    else
        row.rate:Hide()
    end
    row.total:SetPoint("RIGHT", anchor, point, x, 0)
end

local function VisibleRowCount()
    local h = content:GetHeight() or 0
    return max(1, floor((h + GAP) / (BAR_H + GAP)))
end

local function LayoutRows()
    local n = VisibleRowCount()
    for i = 1, n do
        local row = rows[i] or CreateRow(i)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -(i - 1) * (BAR_H + GAP))
        row:SetPoint("RIGHT")
    end
    for i = n + 1, #rows do rows[i]:Hide() end
    return n
end

---------------------------------------------------------------------------
-- Data -> rows
---------------------------------------------------------------------------
local function FillRow(row, rank, src, mode, maxAmount, sessionTotal, wide)
    row.source = src
    row.rank:SetText(rank)

    local name = src.name
    if IsSecret(name) then
        row.name:SetText(name)
    else
        row.name:SetText(name and Ambiguate(name, "short") or "?")
    end

    -- class colour: name and the thin line
    local r, g, b = ClassColor(src.classFilename)
    row.name:SetTextColor(r, g, b)
    row.fill:SetVertexColor(1, 1, 1, 1)
    row.fill:SetGradient("HORIZONTAL", CreateColor(r * 0.7, g * 0.7, b * 0.7, 0.9), CreateColor(r, g, b, 1))
    row.glow:SetVertexColor(r, g, b, 0.45)
    row.bar:SetMinMaxValues(0, maxAmount)
    local v = src.totalAmount
    if IsSecret(v) then row.bar:SetValue(v) else row.bar:SetValue(v or 0) end

    row.selfMark:SetShown(src.isLocalPlayer == true)

    -- columns
    local showRate = mode.rate ~= nil
    local showPct = wide and not IsSecret(v) and not IsSecret(sessionTotal)
        and sessionTotal ~= nil and sessionTotal > 0
    LayoutColumns(row, showRate, showPct)

    SetNum(row.total, v)
    if showRate then SetRate(row.rate, src.amountPerSecond) end
    if showPct then row.pct:SetText(format("%.0f%%", (v or 0) / sessionTotal * 100)) end
    row:Show()
end

local function UpdateHeader()
    local mode = MODES[db.mode]
    modeBtn.text:SetText(mode.label)
    modeBtn:SetWidth(modeBtn.text:GetStringWidth() + 22)
    segText:SetText(db.segment == SESSION_OVERALL and "Összesített" or "Aktuális")
end

local function UpdateFooter(session, mode)
    local inCombat = InCombatLockdown() or UnitAffectingCombat("player")
    if inCombat then
        liveDot:Show(); if not pulse:IsPlaying() then pulse:Play() end
        liveGlow:Show()
        footLeft:ClearAllPoints(); footLeft:SetPoint("LEFT", liveDot, "RIGHT", 7, 0)
        footLeft:SetText("Harcban")
    else
        pulse:Stop(); liveDot:Hide(); liveGlow:Hide()
        footLeft:ClearAllPoints(); footLeft:SetPoint("LEFT", PAD, 0)
        local d = session and session.durationSeconds
        if not IsSecret(d) and d ~= nil and d > 0 then footLeft:SetText(Clock(d)) else footLeft:SetText("") end
    end

    footTotal:SetText(""); footRight:SetText("")
    if not session then return end
    local total = session.totalAmount
    if IsSecret(total) then
        SetNum(footTotal, total)
        footRight:SetText("össz.")
        return
    end
    if total == nil then return end
    footTotal:SetText(Short(total))
    local d = session.durationSeconds
    if mode.rate and not IsSecret(d) and d ~= nil and d > 0 then
        footRight:SetText(format("össz.  ·  %s %s", Int(total / d), mode.rate))
    else
        footRight:SetText("össz.")
    end
end

local function ShowEmpty(n, msg, sub)
    for i = 1, n do rows[i]:Hide() end
    emptyText:SetText(msg); emptyText:Show()
    emptySub:SetText(sub or ""); emptySub:Show()
end

function Moteve:Refresh()
    if not db or not self:IsShown() then return end
    UpdateHeader()
    local n = LayoutRows()
    local mode = MODES[db.mode]

    if not DM then
        UpdateFooter(nil, mode)
        return ShowEmpty(n, "Nincs damage meter API", "Ebben a kliensben nincs C_DamageMeter.")
    end
    local available, reason = DM.IsDamageMeterAvailable()
    if not available then
        UpdateFooter(nil, mode)
        return ShowEmpty(n, "A damage meter most nem elérhető", reason)
    end

    local ok, session = pcall(DM.GetCombatSessionFromType, db.segment, mode.id)
    if not ok then session = nil end
    UpdateFooter(session, mode)

    local sources = session and session.combatSources
    if not sources or #sources == 0 then
        return ShowEmpty(n, "Még nincs adat", "Kezdj egy harcot.")
    end
    emptyText:Hide(); emptySub:Hide()

    -- Out of combat values are plain numbers: sort to be safe. In combat, keep the client's order.
    local list = sources
    if not IsSecret(sources[1].totalAmount) then
        list = {}
        for i = 1, #sources do list[i] = sources[i] end
        pcall(table.sort, list, function(a, b) return (a.totalAmount or 0) > (b.totalAmount or 0) end)
    end

    local maxAmount = session.maxAmount
    if not IsSecret(maxAmount) and (not maxAmount or maxAmount <= 0) then
        local top = list[1].totalAmount
        if IsSecret(top) then
            maxAmount = top
        else
            maxAmount = (top and top > 0) and top or 1
        end
    end

    local sessionTotal = session.totalAmount
    if not IsSecret(sessionTotal) and sessionTotal == nil and not IsSecret(list[1].totalAmount) then
        sessionTotal = 0
        for i = 1, #list do sessionTotal = sessionTotal + (list[i].totalAmount or 0) end
    end

    local wide = (self:GetWidth() or 0) >= 270
    scrollOffset = max(0, min(scrollOffset, #list - n))
    for i = 1, n do
        local src = list[i + scrollOffset]
        if src then
            local okRow, rowErr = pcall(FillRow, rows[i], i + scrollOffset, src, mode, maxAmount, sessionTotal, wide)
            if not okRow then rows[i]:Hide(); if DMDEBUG then print("rowerr", rowErr) end end
        else
            rows[i]:Hide()
        end
    end
end

---------------------------------------------------------------------------
-- Interaction
---------------------------------------------------------------------------
local function SavePosition()
    local p, _, rp, x, y = Moteve:GetPoint()
    db.point, db.relPoint, db.x, db.y = p, rp, x, y
    db.w, db.h = Moteve:GetSize()
end

header:SetScript("OnDragStart", function() if not db.locked then menu:Hide(); Moteve:StartMoving() end end)
header:SetScript("OnDragStop", function() Moteve:StopMovingOrSizing(); SavePosition() end)

local function Print(msg) print("|cffa88bffMoteve|r: " .. msg) end

ResetData = function()
    local ok = DM and pcall(DM.ResetAllCombatSessions)
    if not ok then Print("a törlés most nem engedélyezett.") end
    scrollOffset = 0
    Moteve:Refresh()
end

content:SetScript("OnMouseWheel", function(_, delta)
    scrollOffset = max(0, scrollOffset - delta)
    Moteve:Refresh()
end)

-- resize grip: two short diagonal lines
local grip = CreateFrame("Button", nil, Moteve)
grip:SetSize(12, 12)
grip:SetPoint("BOTTOMRIGHT", -2, 2)
grip:SetFrameLevel(footer:GetFrameLevel() + 10)
local g1 = Tex(grip, "OVERLAY", C.low); g1:SetSize(9, 1); g1:SetPoint("CENTER", 1, -1); g1:SetRotation(math.pi / 4)
local g2 = Tex(grip, "OVERLAY", C.low); g2:SetSize(4, 1); g2:SetPoint("CENTER", 3, -3); g2:SetRotation(math.pi / 4)
local function GripAlpha(a) g1:SetAlpha(a); g2:SetAlpha(a) end
GripAlpha(0)
grip:SetScript("OnEnter", function() GripAlpha(1) end)
grip:SetScript("OnLeave", function() GripAlpha(0.4) end)
grip:SetScript("OnMouseDown", function() if not db.locked then menu:Hide(); Moteve:StartSizing("BOTTOMRIGHT") end end)
grip:SetScript("OnMouseUp", function() Moteve:StopMovingOrSizing(); SavePosition(); Moteve:Refresh() end)

Moteve:SetScript("OnSizeChanged", function(self) if db then self:Refresh() end end)

function Moteve:SetLocked(locked)
    db.locked = locked
    grip:SetShown(not locked)
    Print(locked and "ablak zárolva." or "ablak feloldva.")
end

---------------------------------------------------------------------------
-- Updates
---------------------------------------------------------------------------
local dirty, elapsedSince = true, 0
local UPDATE_INTERVAL_COMBAT, UPDATE_INTERVAL_IDLE = 0.3, 1.0

local hovered
Moteve:SetScript("OnUpdate", function(self, elapsed)
    local over = self:IsMouseOver()
    if over ~= hovered then
        hovered = over
        Backdrop(over)
        GripAlpha(over and not db.locked and 0.4 or 0)
    end
    elapsedSince = elapsedSince + elapsed
    local interval = InCombatLockdown() and UPDATE_INTERVAL_COMBAT or UPDATE_INTERVAL_IDLE
    if (dirty and elapsedSince >= 0.1) or elapsedSince >= interval then
        dirty, elapsedSince = false, 0
        self:Refresh()
    end
end)

Moteve:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end
        MoteveDB = MoteveDB or {}
        for k, v in pairs(DEFAULTS) do
            if MoteveDB[k] == nil then MoteveDB[k] = v end
        end
        db = MoteveDB
        if not MODES[db.mode] then db.mode = 1 end

        self:SetScale(db.scale)
        self:SetSize(db.w, db.h)
        self:ClearAllPoints()
        self:SetPoint(db.point, UIParent, db.relPoint, db.x, db.y)
        grip:SetShown(not db.locked)
        self:SetShown(db.shown)
        self:UnregisterEvent("ADDON_LOADED")
        return
    end
    dirty = true
end)

Moteve:RegisterEvent("ADDON_LOADED")
for _, ev in ipairs({
    "DAMAGE_METER_COMBAT_SESSION_UPDATED",
    "DAMAGE_METER_CURRENT_SESSION_UPDATED",
    "DAMAGE_METER_RESET",
    "PLAYER_REGEN_ENABLED",
    "PLAYER_REGEN_DISABLED",
    "GROUP_ROSTER_UPDATE",
    "PLAYER_ENTERING_WORLD",
}) do
    pcall(Moteve.RegisterEvent, Moteve, ev)
end

Moteve:HookScript("OnShow", function() dirty = true end)
Moteve:HookScript("OnHide", function() menu:Hide() end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
SLASH_MOTEVE1, SLASH_MOTEVE2 = "/moteve", "/mtv"
SlashCmdList.MOTEVE = function(input)
    local cmd, arg = (input or ""):lower():match("^(%S*)%s*(.-)$")
    if cmd == "" or cmd == "toggle" then
        db.shown = not Moteve:IsShown()
        Moteve:SetShown(db.shown)
    elseif cmd == "show" then
        db.shown = true; Moteve:Show()
    elseif cmd == "hide" then
        db.shown = false; Moteve:Hide()
    elseif cmd == "lock" then
        Moteve:SetLocked(true)
    elseif cmd == "unlock" then
        Moteve:SetLocked(false)
    elseif cmd == "reset" then
        ResetData()
    elseif cmd == "scale" then
        local s = tonumber(arg)
        if s and s >= 0.5 and s <= 2 then
            db.scale = s; Moteve:SetScale(s); Print("scale " .. s)
        else
            Print("usage: /moteve scale 0.5-2")
        end
    elseif cmd == "center" then
        Moteve:ClearAllPoints(); Moteve:SetPoint("CENTER"); SavePosition()
    else
        Print("/moteve [toggle | show | hide | lock | unlock | reset | scale <0.5-2> | center]")
    end
end
