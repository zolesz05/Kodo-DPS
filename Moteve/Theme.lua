-- Moteve Damage Meter - shared "arcane glass" theme helpers (same look as Moteve Quest / Moteve Chat)
local ADDON_NAME, ns = ...
local format = string.format

---------------------------------------------------------------------------
-- Theme: "Arcane glass" - translucent navy panels, cold cyan / violet light, gold turn-ins.
-- Shapes (hexagons, rounded panels, glows) are small TGA textures in Textures\.
---------------------------------------------------------------------------
local WHITE = "Interface\\Buttons\\WHITE8X8"
local CIRCLE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local MEDIA = "Interface\\AddOns\\" .. ADDON_NAME .. "\\"

ns.WHITE = WHITE
function ns.TEX(name) return MEDIA .. "Textures\\" .. name end

-- Marcellus (titles, map glyphs) and Barlow (text). Both OFL, both cover Hungarian ő/ű.
ns.FONT_TITLE = MEDIA .. "Fonts\\Marcellus-Regular.ttf"
ns.FONT_BODY = MEDIA .. "Fonts\\Barlow-Regular.ttf"
ns.FONT_BODY_BOLD = MEDIA .. "Fonts\\Barlow-SemiBold.ttf"
ns.FONT_LABEL = ns.FONT_BODY_BOLD

local function hex(s)
    return { tonumber(s:sub(1, 2), 16) / 255, tonumber(s:sub(3, 4), 16) / 255, tonumber(s:sub(5, 6), 16) / 255 }
end
ns.C = {
    cyan       = hex("7FD8FF"),   -- available quests, areas
    cyanPale   = hex("DFF4FF"),
    violet     = hex("A88BFF"),   -- focus, route, chain
    violetPale = hex("CDBBFF"),
    gold       = hex("FFCF5A"),   -- ready to turn in
    goldPale   = hex("FFF1C2"),
    goldSoft   = hex("FFE8A6"),
    text       = hex("EEF2FF"),
    sub        = hex("B9C2E6"),
    muted      = hex("9AA4C7"),
    low        = hex("7D86A8"),
    glass      = { 16 / 255, 20 / 255, 44 / 255 },
    navy       = { 18 / 255, 24 / 255, 52 / 255 },
    edge       = { 150 / 255, 180 / 255, 1 },
    ink        = hex("2A2140"),
    green      = hex("7FE3B0"),
    dungeon    = hex("A88BFF"),
    kill       = hex("FF6B81"),   -- objective: kill
    loot       = hex("FFB45A"),   -- objective: loot from mobs
    pickup     = hex("7CE38B"),   -- objective: pick up from the ground
    mint       = hex("6FE3D6"),   -- objective: use an object
}
local C = ns.C
-- older names still used in a few places
C.goldBright, C.goldDim, C.cream, C.xp, C.grey = C.gold, C.gold, C.text, C.violetPale, C.low

function ns.Hex(c) return format("|cff%02x%02x%02x", c[1] * 255, c[2] * 255, c[3] * 255) end

---------------------------------------------------------------------------
-- Widget helpers
---------------------------------------------------------------------------
function ns.Tex(parent, layer, c, a, sub)
    local t = parent:CreateTexture(nil, layer or "ARTWORK", nil, sub)
    t:SetTexture(WHITE)
    if c then t:SetVertexColor(c[1], c[2], c[3], a or 1) end
    return t
end

function ns.Img(parent, name, layer, sub, c, a)
    local t = parent:CreateTexture(nil, layer or "ARTWORK", nil, sub)
    t:SetTexture(ns.TEX(name))
    if c then t:SetVertexColor(c[1], c[2], c[3], a or 1) end
    return t
end

function ns.Grad(t, orient, c1, a1, c2, a2)
    t:SetTexture(WHITE)
    t:SetVertexColor(1, 1, 1, 1)
    t:SetGradient(orient, CreateColor(c1[1], c1[2], c1[3], a1 or 1), CreateColor(c2[1], c2[2], c2[3], a2 or 1))
end

-- SetFont's return value differs between client builds, so success is checked with GetFont
local function SetFontSafe(fs, path, size)
    local ok = pcall(fs.SetFont, fs, path, size, "")
    if not ok or not fs:GetFont() then fs:SetFont(STANDARD_TEXT_FONT, size, "") end
end
ns.SetFontSafe = SetFontSafe

function ns.Font(parent, kind, size, c, justify, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    local path = (kind == "label" and ns.FONT_LABEL) or (kind == "title" and ns.FONT_TITLE)
        or (kind == "bold" and ns.FONT_BODY_BOLD) or ns.FONT_BODY
    SetFontSafe(fs, path, size)
    fs:SetShadowColor(0, 0, 0, 0.6)
    fs:SetShadowOffset(0, -1)
    if c then fs:SetTextColor(c[1], c[2], c[3]) end
    fs:SetJustifyH(justify or "LEFT")
    fs:SetWordWrap(false)
    return fs
end

function ns.SetFontKind(fs, kind, size)
    local path = (kind == "title" and ns.FONT_TITLE) or (kind == "bold" and ns.FONT_BODY_BOLD)
        or (kind == "label" and ns.FONT_LABEL) or ns.FONT_BODY
    SetFontSafe(fs, path, size)
end

-- a filled circle (or ellipse, if width ~= height)
function ns.Circle(parent, layer, sub)
    return ns.Img(parent, "circle", layer, sub)
end

-- Nine-slice made of 9 textures, so rounded shapes stay crisp at any size.
-- file: texture name; frac: corner size inside the texture (0..0.5)
local SLICE = {
    { "TOPLEFT", 0, 1, 0, 1 }, { "TOP", 1, 2, 0, 1 }, { "TOPRIGHT", 2, 3, 0, 1 },
    { "LEFT", 0, 1, 1, 2 }, { "CENTER", 1, 2, 1, 2 }, { "RIGHT", 2, 3, 1, 2 },
    { "BOTTOMLEFT", 0, 1, 2, 3 }, { "BOTTOM", 1, 2, 2, 3 }, { "BOTTOMRIGHT", 2, 3, 2, 3 },
}
local SliceMixin = {}
function SliceMixin:SetColor(c, a)
    for i = 1, 9 do self[i]:SetVertexColor(c[1], c[2], c[3], a or 1) end
end
function SliceMixin:SetShown(v) for i = 1, 9 do self[i]:SetShown(v) end end
function SliceMixin:Show() self:SetShown(true) end
function SliceMixin:Hide() self:SetShown(false) end
function SliceMixin:SetBlendMode(m) for i = 1, 9 do self[i]:SetBlendMode(m) end end
-- region: what to wrap; r: corner size in pixels; out: grow outwards (glows/shadows)
function SliceMixin:Fit(region, r, out)
    out = out or 0
    local t = self
    -- corners
    t[1]:ClearAllPoints(); t[1]:SetPoint("TOPLEFT", region, "TOPLEFT", -out, out); t[1]:SetSize(r, r)
    t[3]:ClearAllPoints(); t[3]:SetPoint("TOPRIGHT", region, "TOPRIGHT", out, out); t[3]:SetSize(r, r)
    t[7]:ClearAllPoints(); t[7]:SetPoint("BOTTOMLEFT", region, "BOTTOMLEFT", -out, -out); t[7]:SetSize(r, r)
    t[9]:ClearAllPoints(); t[9]:SetPoint("BOTTOMRIGHT", region, "BOTTOMRIGHT", out, -out); t[9]:SetSize(r, r)
    -- edges
    t[2]:ClearAllPoints(); t[2]:SetPoint("TOPLEFT", t[1], "TOPRIGHT"); t[2]:SetPoint("BOTTOMRIGHT", t[3], "BOTTOMLEFT")
    t[8]:ClearAllPoints(); t[8]:SetPoint("TOPLEFT", t[7], "TOPRIGHT"); t[8]:SetPoint("BOTTOMRIGHT", t[9], "BOTTOMLEFT")
    t[4]:ClearAllPoints(); t[4]:SetPoint("TOPLEFT", t[1], "BOTTOMLEFT"); t[4]:SetPoint("BOTTOMRIGHT", t[7], "TOPRIGHT")
    t[6]:ClearAllPoints(); t[6]:SetPoint("TOPLEFT", t[3], "BOTTOMLEFT"); t[6]:SetPoint("BOTTOMRIGHT", t[9], "TOPRIGHT")
    t[5]:ClearAllPoints(); t[5]:SetPoint("TOPLEFT", t[1], "BOTTOMRIGHT"); t[5]:SetPoint("BOTTOMRIGHT", t[9], "TOPLEFT")
    return self
end

function ns.Slice(parent, file, frac, layer, sub)
    local s = {}
    local cuts = { 0, frac, 1 - frac, 1 }
    for i, d in ipairs(SLICE) do
        local t = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sub)
        t:SetTexture(ns.TEX(file))
        t:SetTexCoord(cuts[d[2] + 1], cuts[d[3] + 1], cuts[d[4] + 1], cuts[d[5] + 1])
        s[i] = t
    end
    for k, v in pairs(SliceMixin) do s[k] = v end
    return s
end

-- Glass panel: translucent navy fill, thin light edge, soft shadow, faint top sheen.
-- opts: radius, alpha, edge (edge alpha), shadow (bool), tint (colour of the fill)
function ns.Glass(f, opts)
    opts = opts or {}
    local r = opts.radius or 14
    local g = {}
    if opts.shadow ~= false then
        g.shadow = ns.Slice(f, "shadow", 0.5, "BACKGROUND", -8):Fit(f, r + 18, 18)
        g.shadow:SetColor({ 0, 0, 0 }, 0.45)
    end
    g.fill = ns.Slice(f, "round", 0.25, "BACKGROUND", -7):Fit(f, r)
    g.fill:SetColor(opts.tint or C.glass, opts.alpha or 0.72)
    g.line = ns.Slice(f, "roundline", 0.25, "BORDER", -7):Fit(f, r)
    g.line:SetColor(opts.edgeColor or C.edge, opts.edge or 0.28)
    -- top sheen (inset highlight)
    g.sheen = f:CreateTexture(nil, "BORDER", nil, -6)
    g.sheen:SetPoint("TOPLEFT", r * 0.6, -1); g.sheen:SetPoint("TOPRIGHT", -r * 0.6, -1); g.sheen:SetHeight(1)
    ns.Grad(g.sheen, "HORIZONTAL", { 1, 1, 1 }, 0.02, { 1, 1, 1 }, 0.1)
    function g:SetShown(v)
        if self.shadow then self.shadow:SetShown(v) end
        self.fill:SetShown(v); self.line:SetShown(v); self.sheen:SetShown(v)
    end
    return g
end

-- Pill / chip: rounded label. pill:Set(text, textColor, fill, fillAlpha, edge, edgeAlpha)
function ns.Pill(parent, size, kind)
    local p = CreateFrame("Frame", nil, parent)
    p.padX = 8
    p.text = ns.Font(p, kind or "bold", size or 11, C.text, "CENTER")
    p.text:SetPoint("CENTER", 0, 0)
    local h = (size or 11) + 8
    p:SetHeight(h)
    p.fill = ns.Slice(p, "circle", 0.5, "BACKGROUND", 1):Fit(p, h / 2)
    p.line = ns.Slice(p, "circlering", 0.5, "BORDER", 1):Fit(p, h / 2)
    function p:Set(text, tc, fc, fa, ec, ea)
        self.text:SetText(text or "")
        self.text:SetTextColor(tc[1], tc[2], tc[3])
        self.fill:SetColor(fc or { 1, 1, 1 }, fa or 0.08)
        if ec then self.line:SetColor(ec, ea or 0.4); self.line:Show() else self.line:Hide() end
        self:SetWidth(math.floor(self.text:GetStringWidth() + 0.5) + self.padX * 2)
        return self
    end
    return p
end

-- fading horizontal rule
function ns.Rule(parent, c, a)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetHeight(1)
    ns.Grad(t, "HORIZONTAL", c or C.edge, a or 0.4, c or C.edge, 0)
    return t
end

