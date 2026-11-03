-- Moteve Damage Meter 0.4 ("arcane glass" style, like Moteve Quest / Moteve Chat)
-- Built on Blizzard's C_DamageMeter API (the combat log is not available to addons on WoW Forever).
-- In combat most values are "secret": they can be handed to widgets (StatusBar/FontString)
-- but not compared, summed or formatted. Percentages and spell breakdowns appear after combat.
-- Up to MAX_WINDOWS meter windows, each with its own mode, segment, size, position and lock.
-- The threat mode reads UnitDetailedThreatSituation instead of C_DamageMeter.

local ADDON_NAME, ns = ...

local DM = C_DamageMeter
local format, floor, max, min, ceil = string.format, math.floor, math.max, math.min, math.ceil

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

-- Layout values are per window: a compact window has no footer and shorter rows.
local function Layout(compact)
    return {
        headerH = 24,
        footerH = compact and 0 or 18,
        barH    = compact and 16 or 22,
        gap     = 3,
        pad     = 12,
    }
end

local MAX_WINDOWS = 4

---------------------------------------------------------------------------
-- Modes / sessions
---------------------------------------------------------------------------
local T  = (Enum and Enum.DamageMeterType) or {}
local ST = (Enum and Enum.DamageMeterSessionType) or {}
local SESSION_OVERALL = ST.Overall or 0
local SESSION_CURRENT = ST.Current or 1

-- Saved windows store the index into this list: only append new modes at the end.
local MODES = {
    { id = T.DamageDone  or 0, label = "Sebzés",          rate = "DPS" },
    { id = T.HealingDone or 2, label = "Gyógyítás",       rate = "HPS" },
    { id = T.Absorbs     or 4, label = "Elnyelés",        rate = "APS" },
    { id = T.DamageTaken or 7, label = "Kapott sebzés",   rate = "DTPS" },
    { id = T.Interrupts  or 5, label = "Megszakítások" },
    { id = T.Dispels     or 6, label = "Dispelek" },
    { id = "threat",           label = "Fenyegetés",      kind = "threat" },
}
local THREAT_MODE
for i, m in ipairs(MODES) do if m.kind == "threat" then THREAT_MODE = i end end

-- per-window settings (MoteveDB.windows[i])
local WINDOW_DEFAULTS = {
    point = "CENTER", relPoint = "CENTER", x = 300, y = -100,
    w = 300, h = 214, scale = 1,
    mode = 1, segment = SESSION_CURRENT,
    locked = false, shown = true, compact = false,
}
-- addon-wide settings (MoteveDB.minimap; MoteveDB.windows is built on load)
local MINIMAP_DEFAULTS = { angle = 225, hide = false }

-- keys of the flat 0.3.x MoteveDB that move into MoteveDB.windows[1]
local LEGACY_KEYS = { "point", "relPoint", "x", "y", "w", "h", "scale", "mode", "segment", "locked", "shown" }

local PRESET_THREAT = { mode = THREAT_MODE, compact = true, w = 200, h = 140 }

local windows = {}  -- live windows, windows[i].db == MoteveDB.windows[i]
local slots = {}    -- every window frame ever built, by slot (frames cannot be destroyed)

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

local function Print(msg) print("|cffa88bffMoteve|r: " .. msg) end

local function IndexOf(win)
    for i, w in ipairs(windows) do if w == win then return i end end
end

---------------------------------------------------------------------------
-- Dropdown (one shared frame: only one menu is open at a time)
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
menu:SetScript("OnHide", function() catcher:Hide(); menu.owner = nil end)

local menuItems = {}
local ITEM_H = 22
local MENU_MIN_W = 180

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
    local y, width = -5, MENU_MIN_W
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
            width = max(width, ceil((it.text:GetStringWidth() or 0) + 40))
        end
        it:Show()
        y = y - it:GetHeight()
    end
    for i = #spec + 1, #menuItems do menuItems[i]:Hide() end
    menu:SetWidth(width)
    menu:SetHeight(-y + 5)
    menu.spec = spec
end

local function ShowMenu(spec, owner, anchor)
    BuildMenu(spec)
    menu.owner = owner
    menu:SetScale(anchor:GetEffectiveScale() / UIParent:GetEffectiveScale())
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
    menu:Show()
end

local ResetData, AddWindow, RemoveWindow -- forward

-- the dropdown of one window: its mode, segment, lock and removal
local function OpenMenu(win, anchor)
    if menu:IsShown() then menu:Hide() return end
    local spec = { { kind = "header", text = "MUTASD" } }
    for i, m in ipairs(MODES) do
        spec[#spec + 1] = {
            kind = "option", text = m.label,
            checked = function() return win.db.mode == i end,
            onClick = function() win.db.mode = i; win:ResetScroll(); win:Refresh() end,
        }
    end
    if MODES[win.db.mode].kind ~= "threat" then
        spec[#spec + 1] = { kind = "sep" }
        spec[#spec + 1] = { kind = "header", text = "SZAKASZ" }
        spec[#spec + 1] = { kind = "option", text = "Aktuális harc",
            checked = function() return win.db.segment == SESSION_CURRENT end,
            onClick = function() win.db.segment = SESSION_CURRENT; win:ResetScroll(); win:Refresh() end }
        spec[#spec + 1] = { kind = "option", text = "Összesített",
            checked = function() return win.db.segment == SESSION_OVERALL end,
            onClick = function() win.db.segment = SESSION_OVERALL; win:ResetScroll(); win:Refresh() end }
    end
    spec[#spec + 1] = { kind = "sep" }
    spec[#spec + 1] = { kind = "option", text = "Adatok törlése", danger = true, onClick = function() ResetData() end }
    spec[#spec + 1] = { kind = "option", text = win.db.locked and "Ablak feloldása" or "Ablak zárolása",
        onClick = function() win:SetLocked(not win.db.locked) end }
    spec[#spec + 1] = { kind = "option", text = "Ablak eltávolítása", danger = true,
        onClick = function() RemoveWindow(win) end }

    ShowMenu(spec, win, anchor)
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------
local function ThreatTooltip(row)
    local e = row.threat
    GameTooltip:SetOwner(row, "ANCHOR_LEFT")
    if IsSecret(e.name) then
        GameTooltip:SetText(e.name)
    else
        GameTooltip:SetText(e.name or "?", ClassColor(e.class))
    end
    if IsSecret(e.scaled) or IsSecret(e.raw) or IsSecret(e.value) then
        GameTooltip:AddLine("Az értékek most titkosak, csak a sáv és a felirat látszik.", C.muted[1], C.muted[2], C.muted[3])
    else
        local r, g, b = C.text[1], C.text[2], C.text[3]
        if e.scaled ~= nil then GameTooltip:AddDoubleLine("Fenyegetés", format("%.0f%%", e.scaled), 1, 1, 1, r, g, b) end
        if e.raw ~= nil then GameTooltip:AddDoubleLine("Nyers", format("%.0f%%", e.raw), 1, 1, 1, r, g, b) end
        if e.value ~= nil then GameTooltip:AddDoubleLine("Érték", Short(e.value), 1, 1, 1, r, g, b) end
    end
    if not IsSecret(e.isTanking) and e.isTanking == true then
        GameTooltip:AddLine("Ő tankolja a célpontot.", C.accent1[1], C.accent1[2], C.accent1[3])
    end
    GameTooltip:Show()
end

local function RowTooltip(win, row)
    if row.threat then return ThreatTooltip(row) end
    local src = row.source
    if not src then return end
    local mode = MODES[win.db.mode]
    if mode.kind == "threat" then return end
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

    local ok, detail = pcall(DM.GetCombatSessionSourceFromType, win.db.segment, mode.id, guid, src.sourceCreatureID)
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

-- everything in a row that depends on the window's layout (compact or not)
local function StyleRow(row, L, compact)
    row.compact = compact
    row:SetHeight(L.barH)
    row.hl:ClearAllPoints()
    row.hl:SetPoint("TOPLEFT", L.pad - 6, 1); row.hl:SetPoint("BOTTOMRIGHT", -L.pad + 6, -1)
    row.bar:ClearAllPoints()
    row.bar:SetPoint("BOTTOMLEFT", L.pad, 1)
    row.bar:SetPoint("BOTTOMRIGHT", -L.pad, 1)
    row.selfMark:ClearAllPoints()
    row.selfMark:SetPoint("LEFT", L.pad - 9, 2)
    row.tl:ClearAllPoints()
    row.tl:SetPoint("TOPLEFT", L.pad, 0)
    row.tl:SetPoint("BOTTOMRIGHT", -L.pad, compact and 3 or 4)
    SetFontSize(row.rank, "body", compact and 10 or 11)
    SetFontSize(row.pct, "body", compact and 10 or 11)
    SetFontSize(row.rate, "body", compact and 10 or 11)
    SetFontSize(row.total, "bold", compact and 11 or 12)
    SetFontSize(row.name, "body", compact and 11.5 or 12.5)
end

local function CreateRow(win, i)
    local row = CreateFrame("Button", nil, win.content)
    row.win = win

    row.hl = row:CreateTexture(nil, "BACKGROUND")
    ns.Grad(row.hl, "HORIZONTAL", P.edge, 0.10, P.edge, 0.02)
    row.hl:Hide()

    -- thin glowing line under the name: the "bar"
    local bar = CreateFrame("StatusBar", nil, row)
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
    row.selfMark:Hide()

    local tl = CreateFrame("Frame", nil, row)
    row.tl = tl

    row.rank = Font(tl, 11, C.low)
    row.rank:SetPoint("LEFT", 0, 0)
    row.rank:SetWidth(16)

    -- threat mode: cyan ring in the rank column on the unit that is tanking
    row.tankMark = ns.Img(tl, "circlering", "OVERLAY", 1, C.accent1, 1)
    row.tankMark:SetSize(9, 9)
    row.tankMark:SetPoint("CENTER", row.rank, "CENTER", -3, 0)
    row.tankMark:Hide()

    row.pct = Font(tl, 11, C.muted, "RIGHT")
    row.pct:SetWidth(32)
    row.rate = Font(tl, 11, C.sub, "RIGHT")
    row.rate:SetWidth(52)
    row.total = Font(tl, 12, C.text, "RIGHT", "bold")

    row.name = Font(tl, 12.5, C.text)
    row.name:SetPoint("LEFT", row.rank, "RIGHT", 2, 0)
    row.name:SetPoint("RIGHT", row.total, "LEFT", -6, 0)

    row:SetScript("OnEnter", function(self) self.hl:Show(); RowTooltip(self.win, self) end)
    row:SetScript("OnLeave", function(self) self.hl:Hide(); GameTooltip:Hide() end)

    StyleRow(row, win.L, win.compact)
    win.rows[i] = row
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

-- the content area spans the window minus header, footer and padding
local function VisibleRowCount(win)
    local L = win.L
    local h = (win:GetHeight() or 0) - L.headerH - L.footerH - 2 * L.pad
    return max(1, floor((h + L.gap) / (L.barH + L.gap)))
end

local function LayoutRows(win)
    local L, rows = win.L, win.rows
    local n = VisibleRowCount(win)
    for i = 1, n do
        local row = rows[i] or CreateRow(win, i)
        if row.compact ~= win.compact then StyleRow(row, L, win.compact) end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -(i - 1) * (L.barH + L.gap))
        row:SetPoint("RIGHT")
    end
    for i = n + 1, #rows do rows[i]:Hide() end
    return n
end

---------------------------------------------------------------------------
-- Data -> rows
---------------------------------------------------------------------------
local function SetRowName(row, name, classFile, short)
    if IsSecret(name) then
        row.name:SetText(name)
    elseif short then
        row.name:SetText(name and Ambiguate(name, "short") or "?")
    else
        row.name:SetText(name or "?")
    end
    -- class colour: name and the thin line
    local r, g, b = ClassColor(classFile)
    row.name:SetTextColor(r, g, b)
    row.fill:SetVertexColor(1, 1, 1, 1)
    row.fill:SetGradient("HORIZONTAL", CreateColor(r * 0.7, g * 0.7, b * 0.7, 0.9), CreateColor(r, g, b, 1))
    row.glow:SetVertexColor(r, g, b, 0.45)
end

local function FillRow(win, row, rank, src, mode, maxAmount, sessionTotal, wide)
    row.source, row.threat = src, nil
    row.rank:SetText(rank)
    row.tankMark:Hide()
    row.total:SetTextColor(C.text[1], C.text[2], C.text[3])

    SetRowName(row, src.name, src.classFilename, true)
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

-- One threat row. Threat values may be secret: those only go to SetValue / SetText (via SetRate/SetNum).
local function FillThreatRow(win, row, rank, e)
    row.source, row.threat = nil, e
    SetRowName(row, e.name, e.class, false)

    row.bar:SetMinMaxValues(0, 100)
    if IsSecret(e.scaled) then row.bar:SetValue(e.scaled) else row.bar:SetValue(e.scaled or 0) end

    row.selfMark:SetShown(e.isSelf == true)

    local tanking = not IsSecret(e.isTanking) and e.isTanking == true
    row.tankMark:SetShown(tanking)
    row.rank:SetText(tanking and "" or rank)

    local r, g, b = C.text[1], C.text[2], C.text[3]
    if not IsSecret(e.status) and e.status ~= nil and GetThreatStatusColor then
        local ok, sr, sg, sb = pcall(GetThreatStatusColor, e.status)
        if ok and sr then r, g, b = sr, sg, sb end
    end
    row.total:SetTextColor(r, g, b)

    local showRate = not win.compact
    LayoutColumns(row, showRate, false)
    if IsSecret(e.scaled) then
        SetRate(row.total, e.scaled)
    elseif e.scaled ~= nil then
        row.total:SetText(format("%.0f%%", e.scaled))
    else
        row.total:SetText("–")
    end
    if showRate then
        if IsSecret(e.value) or e.value ~= nil then SetNum(row.rate, e.value) else row.rate:SetText("") end
    end
    row:Show()
end

local function UpdateHeader(win, mode)
    win.modeBtn.text:SetText(mode.label)
    win.modeBtn:SetWidth(win.modeBtn.text:GetStringWidth() + 22)
    if mode.kind ~= "threat" then
        win.segText:SetText(win.db.segment == SESSION_OVERALL and "Összesített" or "Aktuális")
    end
end

local function UpdateFooter(win, session, mode)
    if win.compact then return end -- no footer
    local f = win.foot
    local inCombat = InCombatLockdown() or UnitAffectingCombat("player")
    if inCombat then
        f.liveDot:Show(); if not f.pulse:IsPlaying() then f.pulse:Play() end
        f.liveGlow:Show()
        f.left:ClearAllPoints(); f.left:SetPoint("LEFT", f.liveDot, "RIGHT", 7, 0)
        f.left:SetText("Harcban")
    else
        f.pulse:Stop(); f.liveDot:Hide(); f.liveGlow:Hide()
        f.left:ClearAllPoints(); f.left:SetPoint("LEFT", win.L.pad, 0)
        local d = session and session.durationSeconds
        if not IsSecret(d) and d ~= nil and d > 0 then f.left:SetText(Clock(d)) else f.left:SetText("") end
    end

    f.total:SetText(""); f.right:SetText("")
    if not session then return end
    local total = session.totalAmount
    if IsSecret(total) then
        SetNum(f.total, total)
        f.right:SetText("össz.")
        return
    end
    if total == nil then return end
    f.total:SetText(Short(total))
    local d = session.durationSeconds
    if mode.rate and not IsSecret(d) and d ~= nil and d > 0 then
        f.right:SetText(format("össz.  ·  %s %s", Int(total / d), mode.rate))
    else
        f.right:SetText("össz.")
    end
end

local function ShowEmpty(win, n, msg, sub)
    for i = 1, n do win.rows[i]:Hide() end
    win.emptyText:SetText(msg); win.emptyText:Show()
    win.emptySub:SetText(sub or ""); win.emptySub:Show()
end

---------------------------------------------------------------------------
-- Threat (UnitDetailedThreatSituation; no C_DamageMeter involved)
---------------------------------------------------------------------------
-- you first, then the group in roster order; pets are not listed
local function ThreatUnits()
    local units = { "player" }
    if IsInRaid and IsInRaid() then
        for i = 1, 40 do
            local u = "raid" .. i
            if UnitExists(u) and not UnitIsUnit(u, "player") then units[#units + 1] = u end
        end
    elseif IsInGroup and IsInGroup() then
        for i = 1, 4 do
            local u = "party" .. i
            if UnitExists(u) then units[#units + 1] = u end
        end
    end
    return units
end

-- the mob whose threat list is shown: an attackable target, otherwise the focus
local function ThreatMob()
    if UnitExists("target") and UnitCanAttack("player", "target") then return "target" end
    if UnitExists("focus") then return "focus" end
end

local function ThreatEntry(unit, mob)
    local ok, isTanking, status, scaled, raw, value = pcall(UnitDetailedThreatSituation, unit, mob)
    if not ok then return end
    -- not on the threat table: every value is a plain nil
    if not IsSecret(status) and status == nil and not IsSecret(scaled) and scaled == nil then return end
    local name = UnitName(unit)
    local _, class = UnitClass(unit)
    if IsSecret(class) then class = nil end
    return {
        unit = unit, name = name, class = class, isSelf = UnitIsUnit(unit, "player") and true or false,
        isTanking = isTanking, status = status, scaled = scaled, raw = raw, value = value,
    }
end

local function RefreshThreat(win, n, mode)
    UpdateFooter(win, nil, mode)
    local mob = ThreatMob()
    win.segText:SetText(mob == "focus" and "Fókusz" or "Célpont")
    if not mob then
        return ShowEmpty(win, n, "Nincs célpont", "Jelölj ki egy ellenfelet vagy egy fókuszt.")
    end

    local list = {}
    for _, unit in ipairs(ThreatUnits()) do
        local e = ThreatEntry(unit, mob)
        if e then list[#list + 1] = e end
    end
    if #list == 0 then
        return ShowEmpty(win, n, "Nincs fenyegetés", "A célpont még nem harcol a csoporttal.")
    end
    win.emptyText:Hide(); win.emptySub:Hide()

    -- Plain numbers can be sorted; once any value is secret, keep roster order.
    local sortable = true
    for i = 1, #list do
        if IsSecret(list[i].scaled) then sortable = false break end
    end
    if sortable then
        pcall(table.sort, list, function(a, b) return (a.scaled or 0) > (b.scaled or 0) end)
    end

    win.scrollOffset = max(0, min(win.scrollOffset, #list - n))
    for i = 1, n do
        local e = list[i + win.scrollOffset]
        local row = win.rows[i]
        if e then
            local okRow, rowErr = pcall(FillThreatRow, win, row, i + win.scrollOffset, e)
            if not okRow then row:Hide(); if DMDEBUG then print("rowerr", rowErr) end end
        else
            row:Hide()
        end
    end
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local Window = {}

function Window:ResetScroll() self.scrollOffset = 0 end

function Window:Refresh()
    local db = self.db
    if not db or not self:IsShown() then return end
    local mode = MODES[db.mode]
    UpdateHeader(self, mode)
    local n = LayoutRows(self)
    local rows = self.rows

    -- threat data does not come from C_DamageMeter: branch off before touching it
    if mode.kind == "threat" then return RefreshThreat(self, n, mode) end

    if not DM then
        UpdateFooter(self, nil, mode)
        return ShowEmpty(self, n, "Nincs damage meter API", "Ebben a kliensben nincs C_DamageMeter.")
    end
    local available, reason = DM.IsDamageMeterAvailable()
    if not available then
        UpdateFooter(self, nil, mode)
        return ShowEmpty(self, n, "A damage meter most nem elérhető", reason)
    end

    local ok, session = pcall(DM.GetCombatSessionFromType, db.segment, mode.id)
    if not ok then session = nil end
    UpdateFooter(self, session, mode)

    local sources = session and session.combatSources
    if not sources or #sources == 0 then
        return ShowEmpty(self, n, "Még nincs adat", "Kezdj egy harcot.")
    end
    self.emptyText:Hide(); self.emptySub:Hide()

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
    self.scrollOffset = max(0, min(self.scrollOffset, #list - n))
    for i = 1, n do
        local src = list[i + self.scrollOffset]
        if src then
            local okRow, rowErr = pcall(FillRow, self, rows[i], i + self.scrollOffset, src, mode, maxAmount, sessionTotal, wide)
            if not okRow then rows[i]:Hide(); if DMDEBUG then print("rowerr", rowErr) end end
        else
            rows[i]:Hide()
        end
    end
end

function Window:SavePosition()
    local db = self.db
    local p, _, rp, x, y = self:GetPoint()
    db.point, db.relPoint, db.x, db.y = p, rp, x, y
    db.w, db.h = self:GetSize()
end

function Window:SetLocked(locked, quiet)
    self.db.locked = locked
    self.grip:SetShown(not locked)
    if not quiet then Print(locked and "ablak zárolva." or "ablak feloldva.") end
end

function Window:Backdrop(strong)
    self.glass.fill:SetColor(P.glass, strong and 0.62 or 0.32)
end

function Window:GripAlpha(a)
    self.grip.g1:SetAlpha(a); self.grip.g2:SetAlpha(a)
end

-- header, content and footer positions follow the compact flag
function Window:ApplyLayout()
    local L = self.L
    self.header:SetHeight(L.headerH)
    self.modeBtn:SetHeight(L.headerH - 6)
    self.title:SetPoint("LEFT", L.pad, -1)
    self.segText:SetPoint("RIGHT", -L.pad, -1)
    self.content:ClearAllPoints()
    self.content:SetPoint("TOPLEFT", 0, -L.headerH - L.pad)
    self.content:SetPoint("BOTTOMRIGHT", 0, L.footerH + L.pad)
    self.footer:SetHeight(max(L.footerH, 1))
    self.footer:SetShown(not self.compact)
end

-- attach a saved window table (MoteveDB.windows[i]) to this frame
function Window:Bind(cfg)
    self.db = nil -- no refreshes while the frame is being set up
    self.compact = cfg.compact == true
    self.L = Layout(self.compact)
    self.scrollOffset = 0
    self.hovered = nil
    self:ApplyLayout()
    self:SetScale(cfg.scale)
    self:SetSize(cfg.w, cfg.h)
    self:ClearAllPoints()
    self:SetPoint(cfg.point, UIParent, cfg.relPoint, cfg.x, cfg.y)
    self.grip:SetShown(not cfg.locked)
    self.db = cfg
    self.dirty, self.elapsedSince = true, 0
    self:SetShown(cfg.shown)
end

local UPDATE_INTERVAL_COMBAT, UPDATE_INTERVAL_IDLE = 0.3, 1.0

-- called by the driver every frame while the window is shown
function Window:Tick(elapsed)
    local over = self:IsMouseOver()
    if over ~= self.hovered then
        self.hovered = over
        self:Backdrop(over)
        self:GripAlpha(over and not self.db.locked and 0.4 or 0)
    end
    self.elapsedSince = self.elapsedSince + elapsed
    local interval = InCombatLockdown() and UPDATE_INTERVAL_COMBAT or UPDATE_INTERVAL_IDLE
    if (self.dirty and self.elapsedSince >= 0.1) or self.elapsedSince >= interval then
        self.dirty, self.elapsedSince = false, 0
        self:Refresh()
    end
end

-- builds the frame of one window slot; window 1 keeps the global name MoteveFrame
local function BuildFrame(slot)
    local win = CreateFrame("Frame", slot == 1 and "MoteveFrame" or ("MoteveFrame" .. slot), UIParent)
    win:Hide()
    for k, fn in pairs(Window) do win[k] = fn end
    win.slot = slot
    win.rows = {}
    win.scrollOffset = 0
    win.dirty, win.elapsedSince = true, 0
    win.compact = false
    win.L = Layout(false)
    local L = win.L

    win:SetFrameStrata("MEDIUM")
    win:SetMovable(true)
    win:SetResizable(true)
    win:SetClampedToScreen(true)
    if win.SetResizeBounds then win:SetResizeBounds(200, 110, 640, 800) end

    -- faint rounded backdrop; stronger while the mouse is over the meter
    win.glass = ns.Glass(win, { radius = 12, alpha = 0.32, edge = 0.0, shadow = false })
    win.glass.line:Hide(); win.glass.sheen:Hide()

    -- header
    local header = CreateFrame("Frame", nil, win)
    header:SetPoint("TOPLEFT", 0, 0); header:SetPoint("TOPRIGHT", 0, 0)
    header:SetHeight(L.headerH)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    win.header = header

    local title = Font(header, 10, C.sub, "LEFT", "bold")
    title:SetPoint("LEFT", L.pad, -1)
    title:SetText("MOTEVE")
    title:SetAlpha(0.8)
    win.title = title

    -- mode dropdown button
    local modeBtn = CreateFrame("Button", nil, header)
    modeBtn:SetPoint("LEFT", title, "RIGHT", 6, 0)
    modeBtn:SetHeight(L.headerH - 6)
    local modeHl = ns.Slice(modeBtn, "round", 0.25, "BACKGROUND", 1):Fit(modeBtn, 6)
    modeHl:SetColor({ 1, 1, 1 }, 0.07); modeHl:Hide()
    modeBtn.text = Font(modeBtn, 12, C.text, "LEFT", "bold")
    modeBtn.text:SetPoint("LEFT", 5, 0)
    modeBtn.chev = Chevron(modeBtn)
    modeBtn.chev:SetPoint("LEFT", modeBtn.text, "RIGHT", 5, -1)
    modeBtn:SetScript("OnClick", function(self) OpenMenu(win, self) end)
    modeBtn:SetScript("OnEnter", function() modeHl:Show() end)
    modeBtn:SetScript("OnLeave", function() modeHl:Hide() end)
    win.modeBtn = modeBtn

    win.segText = Font(header, 11, C.muted, "RIGHT")
    win.segText:SetPoint("RIGHT", -L.pad, -1)

    -- footer
    local footer = CreateFrame("Frame", nil, win)
    footer:SetPoint("BOTTOMLEFT", 0, 2); footer:SetPoint("BOTTOMRIGHT", 0, 2)
    footer:SetHeight(L.footerH)
    win.footer = footer

    local f = {}
    f.liveDot = ns.Img(footer, "circle", "OVERLAY", 1, C.accent2, 1)
    f.liveDot:SetSize(6, 6)
    f.liveDot:SetPoint("LEFT", L.pad, 0)
    f.liveGlow = ns.Img(footer, "glow", "OVERLAY", 0, C.accent2, 0.8)
    f.liveGlow:SetBlendMode("ADD"); f.liveGlow:SetSize(18, 18); f.liveGlow:SetPoint("CENTER", f.liveDot)
    f.pulse = f.liveDot:CreateAnimationGroup()
    f.pulse:SetLooping("BOUNCE")
    local pa = f.pulse:CreateAnimation("Alpha")
    pa:SetFromAlpha(1); pa:SetToAlpha(0.25); pa:SetDuration(0.7)

    f.left = Font(footer, 11, C.muted)
    f.left:SetPoint("LEFT", L.pad, 0)
    f.right = Font(footer, 11, C.muted, "RIGHT")
    f.right:SetPoint("RIGHT", -20, 0)
    f.total = Font(footer, 11, C.sub, "RIGHT", "bold")
    f.total:SetPoint("RIGHT", f.right, "LEFT", -4, 0)
    win.foot = f

    -- rows area
    local content = CreateFrame("Frame", nil, win)
    content:EnableMouseWheel(true)
    content:SetScript("OnMouseWheel", function(_, delta)
        win.scrollOffset = max(0, win.scrollOffset - delta)
        win:Refresh()
    end)
    win.content = content

    win.emptyText = Font(content, 11, C.sub, "CENTER")
    win.emptyText:SetPoint("CENTER", 0, 6)
    win.emptySub = Font(content, 10, C.muted, "CENTER")
    win.emptySub:SetPoint("TOP", win.emptyText, "BOTTOM", 0, -4)

    -- moving
    header:SetScript("OnDragStart", function() if not win.db.locked then menu:Hide(); win:StartMoving() end end)
    header:SetScript("OnDragStop", function() win:StopMovingOrSizing(); win:SavePosition() end)

    -- resize grip: two short diagonal lines
    local grip = CreateFrame("Button", nil, win)
    grip:SetSize(12, 12)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    grip:SetFrameLevel(footer:GetFrameLevel() + 10)
    grip.g1 = Tex(grip, "OVERLAY", C.low); grip.g1:SetSize(9, 1); grip.g1:SetPoint("CENTER", 1, -1); grip.g1:SetRotation(math.pi / 4)
    grip.g2 = Tex(grip, "OVERLAY", C.low); grip.g2:SetSize(4, 1); grip.g2:SetPoint("CENTER", 3, -3); grip.g2:SetRotation(math.pi / 4)
    grip:SetScript("OnEnter", function() win:GripAlpha(1) end)
    grip:SetScript("OnLeave", function() win:GripAlpha(0.4) end)
    grip:SetScript("OnMouseDown", function() if not win.db.locked then menu:Hide(); win:StartSizing("BOTTOMRIGHT") end end)
    grip:SetScript("OnMouseUp", function() win:StopMovingOrSizing(); win:SavePosition(); win:Refresh() end)
    win.grip = grip
    win:GripAlpha(0)

    win:SetScript("OnSizeChanged", function(self) if self.db then self:Refresh() end end)
    win:HookScript("OnShow", function(self) self.dirty = true end)
    win:HookScript("OnHide", function(self) if menu.owner == self then menu:Hide() end end)

    win:ApplyLayout()
    return win
end

-- creates (or reuses the hidden frame of) the next window slot for a saved window table
local function CreateWindow(cfg)
    local slot = #windows + 1
    local win = slots[slot] or BuildFrame(slot)
    slots[slot] = win
    windows[slot] = win
    win:Bind(cfg)
    return win
end

local function FillDefaults(t, defaults)
    for k, v in pairs(defaults) do
        if t[k] == nil then t[k] = v end
    end
end

-- a new saved window table: defaults, cascaded so it does not cover the others, then the preset
local function NewWindowConfig(preset)
    local cfg = {}
    FillDefaults(cfg, WINDOW_DEFAULTS)
    local n = #windows
    cfg.x, cfg.y = WINDOW_DEFAULTS.x - n * 30, WINDOW_DEFAULTS.y - n * 30
    if preset then
        for k, v in pairs(preset) do cfg[k] = v end
    end
    cfg.shown = true
    return cfg
end

AddWindow = function(preset)
    if #windows >= MAX_WINDOWS then
        Print(format("legfeljebb %d ablak lehet.", MAX_WINDOWS))
        return
    end
    local cfg = NewWindowConfig(preset)
    MoteveDB.windows[#windows + 1] = cfg
    return CreateWindow(cfg)
end

-- removes a window; the last remaining one stays. The frames of later windows
-- move down one slot, so window i is always MoteveFrame / MoteveFrame<i>.
RemoveWindow = function(win)
    if #windows <= 1 then
        Print("az utolsó ablak nem távolítható el.")
        return false
    end
    local idx = IndexOf(win)
    if not idx then return false end
    menu:Hide()
    table.remove(MoteveDB.windows, idx)
    local last = windows[#windows]
    windows[#windows] = nil
    last.db = nil
    last:Hide()
    for i = idx, #windows do windows[i]:Bind(MoteveDB.windows[i]) end
    return true
end

local function SetAllShown(shown)
    for _, w in ipairs(windows) do
        w.db.shown = shown
        w:SetShown(shown)
    end
end

local function ToggleAll()
    local any = false
    for _, w in ipairs(windows) do if w:IsShown() then any = true end end
    SetAllShown(not any)
end

ResetData = function()
    local ok = DM and pcall(DM.ResetAllCombatSessions)
    if not ok then Print("a törlés most nem engedélyezett.") end
    for _, w in ipairs(windows) do
        w.scrollOffset = 0
        w:Refresh()
    end
end

---------------------------------------------------------------------------
-- Minimap button (bundled textures only, round positioning around the minimap)
---------------------------------------------------------------------------
local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end

local mm = CreateFrame("Button", "MoteveMinimapButton", Minimap)
mm:SetSize(28, 28)
mm:SetFrameStrata("MEDIUM")
mm:SetFrameLevel(Minimap:GetFrameLevel() + 8)
mm:SetClampedToScreen(true)
mm:RegisterForClicks("LeftButtonUp", "RightButtonUp")
mm:RegisterForDrag("LeftButton")
mm:Hide()
do
    local bg = ns.Img(mm, "circle", "BACKGROUND", 0, P.glass, 0.92); bg:SetAllPoints()
    local ring = ns.Img(mm, "circlering", "BORDER", 0, P.edge, 0.55); ring:SetAllPoints()
    mm.glow = ns.Img(mm, "glow", "ARTWORK", 0, C.accent2, 0.6)
    mm.glow:SetBlendMode("ADD"); mm.glow:SetPoint("TOPLEFT", -6, 6); mm.glow:SetPoint("BOTTOMRIGHT", 6, -6); mm.glow:Hide()
    local label = ns.Font(mm, "title", 15, C.accent1, "CENTER")
    label:SetPoint("CENTER", 0, 0)
    label:SetText("M")
end

local function PlaceMinimapButton()
    local a = math.rad(MoteveDB.minimap.angle)
    local r = (Minimap:GetWidth() or 140) / 2 + 5
    mm:ClearAllPoints()
    mm:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

local function MinimapDragUpdate()
    local mx, my = Minimap:GetCenter()
    if not mx then return end
    local scale = Minimap:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    cx, cy = cx / scale, cy / scale
    MoteveDB.minimap.angle = math.deg(atan2(cy - my, cx - mx)) % 360
    PlaceMinimapButton()
end

local function OpenMinimapMenu(anchor)
    if menu:IsShown() then menu:Hide() return end
    local spec = {
        { kind = "header", text = "MOTEVE" },
        { kind = "option", text = "+ Új ablak", onClick = function() AddWindow() end },
        { kind = "option", text = "+ Fenyegetés ablak", onClick = function() AddWindow(PRESET_THREAT) end },
        { kind = "sep" },
        { kind = "header", text = "ABLAKOK" },
    }
    for i, w in ipairs(windows) do
        spec[#spec + 1] = {
            kind = "option", danger = true,
            text = format("Eltávolítás: %d. ablak (%s)", i, MODES[w.db.mode].label),
            onClick = function() RemoveWindow(w) end,
        }
    end
    ShowMenu(spec, anchor, anchor)
end

mm:SetScript("OnClick", function(self, button)
    if button == "RightButton" then
        menu:Hide()
        ToggleAll()
    else
        OpenMinimapMenu(self)
    end
end)
mm:SetScript("OnDragStart", function(self) menu:Hide(); self:SetScript("OnUpdate", MinimapDragUpdate) end)
mm:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
mm:SetScript("OnEnter", function(self)
    self.glow:Show()
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("Moteve Damage Meter")
    GameTooltip:AddLine("Bal klikk: ablakok hozzáadása / eltávolítása", C.sub[1], C.sub[2], C.sub[3])
    GameTooltip:AddLine("Jobb klikk: minden ablak megjelenítése / elrejtése", C.sub[1], C.sub[2], C.sub[3])
    GameTooltip:AddLine("Húzás: áthelyezés a minitérkép szélén", C.muted[1], C.muted[2], C.muted[3])
    GameTooltip:Show()
end)
mm:SetScript("OnLeave", function(self) self.glow:Hide(); GameTooltip:Hide() end)

---------------------------------------------------------------------------
-- Saved variables
---------------------------------------------------------------------------
-- 0.3.x kept one window's settings at the top level of MoteveDB: move them into windows[1].
-- An existing windows table is left alone.
local function MigrateDB(sv)
    if sv.windows ~= nil then return end
    local first = {}
    for _, k in ipairs(LEGACY_KEYS) do first[k] = sv[k] end
    sv.windows = { first }
    for _, k in ipairs(LEGACY_KEYS) do sv[k] = nil end
end

local function InitDB()
    MoteveDB = type(MoteveDB) == "table" and MoteveDB or {}
    local sv = MoteveDB
    MigrateDB(sv)
    if type(sv.windows) ~= "table" then sv.windows = {} end

    local list = {}
    for _, cfg in ipairs(sv.windows) do
        if type(cfg) == "table" and #list < MAX_WINDOWS then list[#list + 1] = cfg end
    end
    if #list < #sv.windows then sv.windows = list end
    if #sv.windows == 0 then sv.windows[1] = {} end
    for _, cfg in ipairs(sv.windows) do
        FillDefaults(cfg, WINDOW_DEFAULTS)
        if not MODES[cfg.mode] then cfg.mode = 1 end
    end

    if type(sv.minimap) ~= "table" then sv.minimap = {} end
    FillDefaults(sv.minimap, MINIMAP_DEFAULTS)
end

---------------------------------------------------------------------------
-- Driver: events and the update throttle for every window
---------------------------------------------------------------------------
local THREAT_EVENTS = {
    UNIT_THREAT_LIST_UPDATE = true,
    UNIT_THREAT_SITUATION_UPDATE = true,
    PLAYER_TARGET_CHANGED = true,
    PLAYER_FOCUS_CHANGED = true,
}

local driver = CreateFrame("Frame")

driver:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end
        InitDB()
        for _, cfg in ipairs(MoteveDB.windows) do CreateWindow(cfg) end
        PlaceMinimapButton()
        mm:SetShown(not MoteveDB.minimap.hide)
        self:UnregisterEvent("ADDON_LOADED")
        return
    end
    -- threat events fire often: they only wake windows that show threat
    local threatOnly = THREAT_EVENTS[event]
    for _, w in ipairs(windows) do
        if not threatOnly or MODES[w.db.mode].kind == "threat" then w.dirty = true end
    end
end)

driver:SetScript("OnUpdate", function(_, elapsed)
    for _, w in ipairs(windows) do
        if w:IsShown() then w:Tick(elapsed) end
    end
end)

driver:RegisterEvent("ADDON_LOADED")
for _, ev in ipairs({
    "DAMAGE_METER_COMBAT_SESSION_UPDATED",
    "DAMAGE_METER_CURRENT_SESSION_UPDATED",
    "DAMAGE_METER_RESET",
    "PLAYER_REGEN_ENABLED",
    "PLAYER_REGEN_DISABLED",
    "GROUP_ROSTER_UPDATE",
    "PLAYER_ENTERING_WORLD",
    "UNIT_THREAT_LIST_UPDATE",
    "UNIT_THREAT_SITUATION_UPDATE",
    "PLAYER_TARGET_CHANGED",
    "PLAYER_FOCUS_CHANGED",
}) do
    pcall(driver.RegisterEvent, driver, ev)
end

---------------------------------------------------------------------------
-- Slash commands (show/hide/lock/unlock/scale/center apply to every window)
---------------------------------------------------------------------------
SLASH_MOTEVE1, SLASH_MOTEVE2 = "/moteve", "/mtv"
SlashCmdList.MOTEVE = function(input)
    local cmd, arg = (input or ""):lower():match("^(%S*)%s*(.-)$")
    if cmd == "" or cmd == "toggle" then
        ToggleAll()
    elseif cmd == "show" then
        SetAllShown(true)
    elseif cmd == "hide" then
        SetAllShown(false)
    elseif cmd == "lock" or cmd == "unlock" then
        local locked = cmd == "lock"
        for _, w in ipairs(windows) do w:SetLocked(locked, true) end
        Print(locked and "ablakok zárolva." or "ablakok feloldva.")
    elseif cmd == "reset" then
        ResetData()
    elseif cmd == "scale" then
        local s = tonumber(arg)
        if s and s >= 0.5 and s <= 2 then
            for _, w in ipairs(windows) do w.db.scale = s; w:SetScale(s) end
            Print("scale " .. s)
        else
            Print("usage: /moteve scale 0.5-2")
        end
    elseif cmd == "center" then
        for i, w in ipairs(windows) do
            w:ClearAllPoints(); w:SetPoint("CENTER", (i - 1) * 24, -(i - 1) * 24); w:SavePosition()
        end
    elseif cmd == "new" then
        AddWindow()
    elseif cmd == "threat" then
        AddWindow(PRESET_THREAT)
    elseif cmd == "minimap" then
        MoteveDB.minimap.hide = not MoteveDB.minimap.hide
        mm:SetShown(not MoteveDB.minimap.hide)
        Print(MoteveDB.minimap.hide and "minimap gomb elrejtve." or "minimap gomb megjelenítve.")
    else
        Print("/moteve [toggle | show | hide | lock | unlock | reset | scale <0.5-2> | center | new | threat | minimap]")
    end
end
