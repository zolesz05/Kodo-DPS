-- Minimal WoW client mock for running Moteve outside the game (Lua 5.1).
-- Widgets record what the addon does to them; unknown methods are no-ops.
local M = {}

local Widget = {}
local WidgetMeta = {
    __index = function(_, key)
        local m = Widget[key]
        if m then return m end
        -- any other widget API method (they are capitalised) does nothing; data fields stay nil
        if type(key) == "string" and key:match("^%u") then return function() end end
    end,
}

local function NewWidget(kind, name, parent)
    local w = setmetatable({
        _kind = kind, _name = name, _parent = parent, _shown = true, _scripts = {}, _hooks = {},
        _points = {}, _w = 0, _h = 0, _scale = 1, _events = {}, _text = nil, _level = 1,
    }, WidgetMeta)
    M.widgets[#M.widgets + 1] = w
    if name then _G[name] = w end
    return w
end
M.NewWidget = NewWidget

local function Fire(w, script, ...)
    local fn = w._scripts[script]
    if fn then fn(w, ...) end
    for _, h in ipairs(w._hooks[script] or {}) do h(w, ...) end
end
M.Fire = Fire

function Widget:Show()
    if self._shown then return end
    self._shown = true
    Fire(self, "OnShow")
end
function Widget:Hide()
    if not self._shown then return end
    self._shown = false
    Fire(self, "OnHide")
end
function Widget:SetShown(v) if v then self:Show() else self:Hide() end end
function Widget:IsShown() return self._shown end
function Widget:IsVisible()
    local w = self
    while w do
        if not w._shown then return false end
        w = w._parent
    end
    return true
end
function Widget:SetScript(s, fn) self._scripts[s] = fn end
function Widget:GetScript(s) return self._scripts[s] end
function Widget:HookScript(s, fn)
    self._hooks[s] = self._hooks[s] or {}
    table.insert(self._hooks[s], fn)
end
function Widget:RegisterEvent(ev) self._events[ev] = true end
function Widget:UnregisterEvent(ev) self._events[ev] = nil end
function Widget:SetSize(w, h)
    local changed = self._w ~= w or self._h ~= h
    self._w, self._h = w, h
    if changed then Fire(self, "OnSizeChanged", w, h) end
end
function Widget:SetWidth(w) self._w = w end
function Widget:SetHeight(h) self._h = h end
function Widget:GetWidth() return self._w end
function Widget:GetHeight() return self._h end
function Widget:GetSize() return self._w, self._h end
function Widget:SetScale(s) self._scale = s end
function Widget:GetScale() return self._scale end
function Widget:GetEffectiveScale() return self._scale end
function Widget:ClearAllPoints() self._points = {} end
function Widget:SetPoint(p, a, b, c, d)
    local rel, rp, x, y
    if type(a) == "table" then rel, rp, x, y = a, b, c, d
    elseif type(a) == "string" then rel, rp, x, y = self._parent, a, b, c
    else rel, rp, x, y = self._parent, p, a, b end
    self._points[#self._points + 1] = { p, rel, rp, x or 0, y or 0 }
end
function Widget:GetPoint(i)
    local pt = self._points[i or 1]
    if pt then return pt[1], pt[2], pt[3], pt[4], pt[5] end
end
function Widget:GetCenter() return 100, 100 end
function Widget:SetText(t) self._text = t end
function Widget:GetText() return self._text end
function Widget:GetStringWidth()
    local t = self._text
    return type(t) == "string" and #t * 6 or 0
end
function Widget:SetMinMaxValues(a, b) self._min, self._max = a, b end
function Widget:SetValue(v) self._value = v end
function Widget:GetValue() return self._value end
function Widget:SetTextColor(r, g, b) self._color = { r, g, b } end
function Widget:GetFont() return "font", 12 end
function Widget:GetFrameLevel() return self._level end
function Widget:SetFrameLevel(l) self._level = l end
function Widget:IsMouseOver() return false end
function Widget:IsPlaying() return false end
function Widget:CreateTexture() return NewWidget("Texture", nil, self) end
function Widget:CreateFontString() return NewWidget("FontString", nil, self) end
function Widget:CreateAnimationGroup() return NewWidget("AnimationGroup", nil, self) end
function Widget:CreateAnimation() return NewWidget("Animation", nil, self) end
function Widget:GetStatusBarTexture()
    self._sbt = self._sbt or NewWidget("Texture", nil, self)
    return self._sbt
end

-- secret values: errors on any comparison or arithmetic
local SecretMeta = {}
local function boom() error("attempt to use a secret value", 2) end
for _, mm in ipairs({ "__lt", "__le", "__add", "__sub", "__mul", "__div", "__mod", "__pow", "__unm", "__concat", "__len" }) do
    SecretMeta[mm] = boom
end
function M.Secret(v) return setmetatable({ __secret = true, v = v }, SecretMeta) end

-- Resets the client state and loads the addon with the given saved variables.
-- opts.db: MoteveDB before ADDON_LOADED. Returns the addon namespace.
function M.Boot(opts)
    opts = opts or {}
    M.widgets = {}
    M.printed = {}
    M.dmCalls = {}
    M.dmArgs = {}     -- { name, arg1, arg2, ... } for every C_DamageMeter call
    M.sessions = opts.sessions or {}         -- GetAvailableCombatSessions()
    M.sessionsByID = opts.sessionsByID or {} -- GetCombatSessionFromID(id)
    M.threatCalls = {}
    M.units = opts.units or { player = { name = "Me", class = "WARRIOR" } }
    M.raid, M.party = opts.raid or false, opts.party or false
    M.threat = opts.threat or {}
    M.attackable = opts.attackable or {}
    M.inCombat = false

    for _, k in ipairs({ "MoteveFrame", "MoteveFrame2", "MoteveFrame3", "MoteveFrame4",
        "MoteveDropdown", "MoteveMinimapButton", "SLASH_MOTEVE1", "SLASH_MOTEVE2" }) do
        _G[k] = nil
    end

    _G.issecretvalue = function(v) return type(v) == "table" and rawget(v, "__secret") == true end
    _G.UIParent = NewWidget("Frame", "UIParent")
    _G.UIParent._w, _G.UIParent._h = 1920, 1080
    _G.Minimap = NewWidget("Frame", "Minimap")
    _G.Minimap._w, _G.Minimap._h = 140, 140
    _G.GameTooltip = NewWidget("GameTooltip", "GameTooltip")
    _G.GameTooltip.lines = {}
    function _G.GameTooltip:SetOwner() self.lines = {} end
    function _G.GameTooltip:SetText(t) self.lines = { t } end
    function _G.GameTooltip:AddLine(t) self.lines[#self.lines + 1] = t end
    function _G.GameTooltip:AddDoubleLine(a, b) self.lines[#self.lines + 1] = tostring(a) .. "|" .. tostring(b) end
    _G.UISpecialFrames = {}
    _G.SlashCmdList = {}
    _G.tinsert = table.insert
    _G.print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
        M.printed[#M.printed + 1] = table.concat(parts, " ")
    end
    _G.CreateFrame = function(kind, name, parent) return NewWidget(kind, name, parent) end
    _G.CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
    _G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
    _G.Ambiguate = function(n) return n end
    _G.AbbreviateNumbers = function(n) return tostring(n) end
    _G.InCombatLockdown = function() return M.inCombat end
    _G.UnitAffectingCombat = function() return M.inCombat end
    _G.GetCursorPosition = function() return M.cursorX or 100, M.cursorY or 200 end
    _G.GetThreatStatusColor = function(s) return 1, 1 - s * 0.3, 0 end
    _G.IsInRaid = function() return M.raid end
    _G.IsInGroup = function() return M.raid or M.party end
    _G.UnitExists = function(u) return M.units[u] ~= nil end
    _G.UnitIsUnit = function(a, b)
        local ua, ub = M.units[a], M.units[b]
        return ua ~= nil and ua == ub
    end
    _G.UnitCanAttack = function(_, u) return M.attackable[u] == true end
    _G.UnitName = function(u) return M.units[u] and M.units[u].name end
    _G.UnitClass = function(u) local d = M.units[u]; if d then return d.class, d.class end end
    _G.UnitDetailedThreatSituation = function(unit, mob)
        M.threatCalls[#M.threatCalls + 1] = { unit, mob }
        local t = M.threat[unit]
        if not t then return end
        return t.isTanking, t.status, t.scaled, t.raw, t.value
    end

    local function dm(name, ret)
        return function(...)
            M.dmCalls[#M.dmCalls + 1] = name
            M.dmArgs[#M.dmArgs + 1] = { name, ... }
            if type(ret) == "function" then return ret(...) end
            return ret
        end
    end
    _G.C_DamageMeter = {
        IsDamageMeterAvailable = dm("IsDamageMeterAvailable", function() return true end),
        GetCombatSessionFromType = dm("GetCombatSessionFromType", function()
            return M.session or { combatSources = {}, totalAmount = 0, durationSeconds = 0 }
        end),
        GetCombatSessionSourceFromType = dm("GetCombatSessionSourceFromType", function() return { combatSpells = {} } end),
        ResetAllCombatSessions = dm("ResetAllCombatSessions"),
        GetAvailableCombatSessions = dm("GetAvailableCombatSessions", function() return M.sessions end),
        GetCombatSessionFromID = dm("GetCombatSessionFromID", function(id) return M.sessionsByID[id] end),
        GetCombatSessionSourceFromID = dm("GetCombatSessionSourceFromID", function() return { combatSpells = {} } end),
    }
    _G.Enum = { DamageMeterType = {}, DamageMeterSessionType = { Overall = 0, Current = 1 } }

    _G.MoteveDB = opts.db
    local ns = {}
    for _, file in ipairs({ "Moteve/Theme.lua", "Moteve/Moteve.lua" }) do
        local chunk = assert(loadfile(file))
        chunk("Moteve", ns)
    end
    M.FireEvent("ADDON_LOADED", "Moteve")
    return ns
end

function M.FireEvent(event, ...)
    for _, w in ipairs(M.widgets) do
        if w._events[event] then Fire(w, "OnEvent", event, ...) end
    end
end

-- the frame that has an OnUpdate script and listens to ADDON_LOADED-era events
function M.Driver()
    for _, w in ipairs(M.widgets) do
        if w._events.DAMAGE_METER_RESET then return w end
    end
end

function M.Update(elapsed)
    for _, w in ipairs(M.widgets) do
        local fn = w._scripts.OnUpdate
        if fn then fn(w, elapsed) end
    end
end

function M.Slash(input) _G.SlashCmdList.MOTEVE(input) end

-- clicks the dropdown item with the given text; returns false when it is not there
function M.ClickMenu(text)
    local menu = _G.MoteveDropdown
    for _, s in ipairs(menu.spec or {}) do
        if s.text == text and s.kind == "option" then
            s.onClick()
            menu:Hide()
            return true
        end
    end
    return false
end

-- clicks the top-right segment / fight picker button of a window
function M.ClickSegment(win) Fire(win.segBtn, "OnClick") end

-- the arguments of the last C_DamageMeter call with this name, or nil
function M.LastDMArgs(name)
    for i = #M.dmArgs, 1, -1 do
        local c = M.dmArgs[i]
        if c[1] == name then return select(2, unpack(c)) end
    end
end

function M.MenuTexts()
    local t = {}
    for _, s in ipairs(_G.MoteveDropdown.spec or {}) do
        if s.kind == "option" then t[#t + 1] = s.text end
    end
    return t
end

return M
