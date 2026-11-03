-- Moteve tests outside the game, against tests/wow_mock.lua.
-- Run from the repository root with a Lua 5.1 interpreter (WoW's Lua version):
--   lua5.1 tests/moteve_test.lua
local print = print -- the mock replaces the global print to capture the addon's messages
package.path = "tests/?.lua;" .. package.path
local W = require("wow_mock")

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
        print("ok   " .. name)
    else
        failed = failed + 1
        print("FAIL " .. name .. "\n     " .. tostring(err))
    end
end

local function eq(a, b, msg)
    if a ~= b then error((msg or "values differ") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end
local function truthy(v, msg) if not v then error(msg or "expected a true value", 2) end end

local function contains(list, value)
    for _, v in ipairs(list) do if v == value then return true end end
    return false
end

local function countWindows() return #MoteveDB.windows end

local function shownRows(win)
    local t = {}
    for _, r in ipairs(win.rows) do if r:IsShown() then t[#t + 1] = r end end
    return t
end

local THREAT = 7

local FLAT_DB = {
    point = "TOPLEFT", relPoint = "BOTTOMLEFT", x = 42, y = -17, w = 333, h = 250, scale = 1.2,
    mode = 2, segment = 0, locked = true, shown = false,
}

---------------------------------------------------------------------------
-- Saved variables
---------------------------------------------------------------------------
test("flat 0.3.x MoteveDB moves into windows[1] and the old keys are removed", function()
    local db = {}
    for k, v in pairs(FLAT_DB) do db[k] = v end
    W.Boot({ db = db })
    eq(countWindows(), 1)
    local w1 = MoteveDB.windows[1]
    for k, v in pairs(FLAT_DB) do
        eq(w1[k], v, "windows[1]." .. k)
        eq(MoteveDB[k], nil, "top-level " .. k)
    end
    eq(w1.compact, false)
    local f = MoteveFrame
    eq(f.db, w1)
    local p, rel, rp, x, y = f:GetPoint()
    eq(p, "TOPLEFT"); eq(rel, UIParent); eq(rp, "BOTTOMLEFT"); eq(x, 42); eq(y, -17)
    eq(f:GetWidth(), 333); eq(f:GetHeight(), 250); eq(f:GetScale(), 1.2)
    eq(f:IsShown(), false)
    eq(f.grip:IsShown(), false)
end)

test("an existing windows table is left alone", function()
    local windows = {
        { point = "CENTER", relPoint = "CENTER", x = 1, y = 2, w = 300, h = 214, scale = 1, mode = 3, segment = 1,
          locked = false, shown = true, compact = false },
    }
    W.Boot({ db = { windows = windows, mode = 5, x = 999, minimap = { angle = 10, hide = false } } })
    eq(MoteveDB.windows, windows)
    eq(MoteveDB.windows[1].mode, 3)
    eq(MoteveDB.windows[1].x, 1)
    eq(MoteveDB.mode, 5, "stray flat key untouched")
    eq(MoteveDB.x, 999, "stray flat key untouched")
end)

test("fresh install gets one default window and minimap settings", function()
    W.Boot({ db = nil })
    eq(countWindows(), 1)
    eq(MoteveDB.windows[1].mode, 1)
    eq(MoteveDB.windows[1].w, 300)
    eq(MoteveDB.minimap.hide, false)
    eq(type(MoteveDB.minimap.angle), "number")
    eq(MoteveFrame:IsShown(), true)
    eq(MoteveMinimapButton:IsShown(), true)
end)

test("every saved window is created on load, with its own name", function()
    W.Boot({ db = { windows = { { mode = 1 }, { mode = 2, w = 250 }, { mode = THREAT, compact = true } } } })
    eq(MoteveFrame.db, MoteveDB.windows[1])
    eq(MoteveFrame2.db, MoteveDB.windows[2])
    eq(MoteveFrame3.db, MoteveDB.windows[3])
    eq(MoteveFrame2:GetWidth(), 250)
    eq(MoteveFrame3.compact, true)
    eq(MoteveFrame4, nil)
end)

---------------------------------------------------------------------------
-- Adding and removing windows
---------------------------------------------------------------------------
test("at most four windows; a fifth is refused", function()
    W.Boot({})
    W.Slash("new"); W.Slash("new"); W.Slash("new")
    eq(countWindows(), 4)
    truthy(MoteveFrame4 and MoteveFrame4:IsShown(), "MoteveFrame4 shown")
    W.Slash("new")
    eq(countWindows(), 4)
    W.Slash("threat")
    eq(countWindows(), 4)
    eq(_G.MoteveFrame5, nil)
    truthy(W.printed[#W.printed]:find("legfeljebb 4"), "refusal message")
end)

test("the last window cannot be removed", function()
    W.Boot({})
    W.Fire(MoteveFrame.modeBtn, "OnClick")
    truthy(W.ClickMenu("Ablak eltávolítása"))
    eq(countWindows(), 1)
    eq(MoteveFrame.db, MoteveDB.windows[1])
    truthy(W.printed[#W.printed]:find("utolsó ablak"), "refusal message")
end)

test("removing a middle window shifts the later ones down a slot", function()
    W.Boot({ db = { windows = { { mode = 1 }, { mode = 2 }, { mode = 3 } } } })
    local third = MoteveDB.windows[3]
    W.Fire(MoteveFrame2.modeBtn, "OnClick")
    truthy(W.ClickMenu("Ablak eltávolítása"))
    eq(countWindows(), 2)
    eq(MoteveDB.windows[2], third)
    eq(MoteveFrame2.db, third)
    eq(MoteveFrame3:IsShown(), false)
    -- the freed slot is reused
    W.Slash("new")
    eq(countWindows(), 3)
    eq(MoteveFrame3.db, MoteveDB.windows[3])
    eq(MoteveFrame3:IsShown(), true)
end)

---------------------------------------------------------------------------
-- Per-window dropdown
---------------------------------------------------------------------------
test("the dropdown changes only the window it was opened from", function()
    W.Boot({ db = { windows = { { mode = 1, segment = 1 }, { mode = 1, segment = 1 } } } })
    W.Fire(MoteveFrame2.modeBtn, "OnClick")
    eq(MoteveDropdown.owner, MoteveFrame2)
    truthy(W.ClickMenu("Gyógyítás"))
    W.Fire(MoteveFrame2.modeBtn, "OnClick")
    truthy(W.ClickMenu("Összesített"))
    eq(MoteveDB.windows[2].mode, 2); eq(MoteveDB.windows[2].segment, 0)
    eq(MoteveDB.windows[1].mode, 1); eq(MoteveDB.windows[1].segment, 1)
    W.Fire(MoteveFrame2.modeBtn, "OnClick")
    truthy(W.ClickMenu("Ablak zárolása"))
    eq(MoteveDB.windows[2].locked, true); eq(MoteveDB.windows[1].locked, false)
end)

---------------------------------------------------------------------------
-- Threat mode
---------------------------------------------------------------------------
local function threatBoot(opts)
    opts.db = { windows = { { mode = THREAT, w = 300, h = 214 } } }
    W.Boot(opts)
    W.dmCalls = {}
    MoteveFrame:Refresh()
    return MoteveFrame
end

local GROUP = {
    player = { name = "Me", class = "MAGE" },
    party1 = { name = "Tank", class = "WARRIOR" },
    party2 = { name = "Heal", class = "PRIEST" },
    target = { name = "Boar" },
}

test("MODES has a Threat entry in the dropdown", function()
    W.Boot({})
    W.Fire(MoteveFrame.modeBtn, "OnClick")
    truthy(contains(W.MenuTexts(), "Threat"))
    truthy(W.ClickMenu("Threat"))
    eq(MoteveDB.windows[1].mode, THREAT)
end)

test("threat mode uses an attackable target, sorts plain values and marks the tank", function()
    local win = threatBoot({
        units = GROUP, party = true, attackable = { target = true },
        threat = {
            player = { isTanking = false, status = 1, scaled = 60, raw = 66, value = 6000 },
            party1 = { isTanking = true, status = 3, scaled = 100, raw = 100, value = 10000 },
            party2 = { isTanking = false, status = 0, scaled = 20, raw = 22, value = 2000 },
        },
    })
    eq(#W.dmCalls, 0, "no C_DamageMeter call")
    for _, c in ipairs(W.threatCalls) do eq(c[2], "target") end
    eq(win.segText:GetText(), "Célpont")
    local rows = shownRows(win)
    eq(#rows, 3)
    eq(rows[1].name:GetText(), "Tank"); eq(rows[1].bar:GetValue(), 100); eq(rows[1].bar._max, 100)
    eq(rows[1].total:GetText(), "100%")
    eq(rows[1].tankMark:IsShown(), true)
    eq(rows[2].name:GetText(), "Me"); eq(rows[2].selfMark:IsShown(), true); eq(rows[2].tankMark:IsShown(), false)
    eq(rows[3].name:GetText(), "Heal")
    eq(win.emptyText:IsShown(), false)
    -- the tooltip makes no C_DamageMeter call either
    W.Fire(rows[1], "OnEnter")
    eq(#W.dmCalls, 0, "no C_DamageMeter call from the tooltip")
    truthy(contains(GameTooltip.lines, "Threat|100%"), "tooltip shows threat")
end)

test("threat mode falls back to the focus when the target cannot be attacked", function()
    local units = { player = GROUP.player, target = { name = "Friend" }, focus = { name = "Boss" } }
    local win = threatBoot({
        units = units, attackable = { focus = true },
        threat = { player = { isTanking = true, status = 3, scaled = 100, raw = 100, value = 5 } },
    })
    truthy(#W.threatCalls > 0)
    for _, c in ipairs(W.threatCalls) do eq(c[2], "focus") end
    eq(win.segText:GetText(), "Fókusz")
    eq(#shownRows(win), 1)
end)

test("threat mode shows Nincs célpont without target and focus", function()
    local win = threatBoot({ units = { player = GROUP.player } })
    eq(win.emptyText:GetText(), "Nincs célpont")
    eq(win.emptyText:IsShown(), true)
    eq(#shownRows(win), 0)
    eq(#W.threatCalls, 0)
    eq(#W.dmCalls, 0)
end)

test("threat mode shows Nincs threat when the target is not in combat with the group", function()
    local win = threatBoot({ units = GROUP, party = true, attackable = { target = true } })
    truthy(#W.threatCalls > 0)
    eq(win.emptyText:GetText(), "Nincs threat")
    eq(win.emptyText:IsShown(), true)
    eq(win.emptySub:GetText(), "A célpont még nem harcol a csoporttal.")
    eq(#shownRows(win), 0)
end)

test("secret threat values keep roster order and only reach SetValue/SetText", function()
    local S = W.Secret
    local win = threatBoot({
        units = GROUP, party = true, attackable = { target = true },
        threat = {
            player = { isTanking = S(false), status = S(1), scaled = S(10), raw = S(11), value = S(100) },
            party1 = { isTanking = S(true), status = S(3), scaled = S(100), raw = S(100), value = S(900) },
            party2 = { isTanking = S(false), status = S(0), scaled = S(50), raw = S(55), value = S(500) },
        },
    })
    local rows = shownRows(win)
    eq(#rows, 3, "every row filled without an error")
    eq(rows[1].name:GetText(), "Me"); eq(rows[2].name:GetText(), "Tank"); eq(rows[3].name:GetText(), "Heal")
    truthy(W.Secret ~= nil and rows[2].bar:GetValue().v == 100, "secret handed to SetValue")
    truthy(type(rows[2].total:GetText()) == "table", "secret handed to SetText")
    eq(rows[2].tankMark:IsShown(), false, "secret isTanking shows no marker")
    W.Fire(rows[2], "OnEnter")
    eq(#W.dmCalls, 0)
end)

test("the driver registers the threat events and they wake threat windows", function()
    W.Boot({ db = { windows = { { mode = 1 }, { mode = THREAT } } } })
    local d = W.Driver()
    for _, ev in ipairs({ "UNIT_THREAT_LIST_UPDATE", "UNIT_THREAT_SITUATION_UPDATE",
        "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED" }) do
        truthy(d._events[ev], ev .. " registered")
    end
    MoteveFrame.dirty, MoteveFrame2.dirty = false, false
    W.FireEvent("UNIT_THREAT_LIST_UPDATE", "target")
    eq(MoteveFrame.dirty, false); eq(MoteveFrame2.dirty, true)
    W.FireEvent("DAMAGE_METER_COMBAT_SESSION_UPDATED")
    eq(MoteveFrame.dirty, true)
end)

test("damage windows still read C_DamageMeter and throttle refreshes", function()
    W.Boot({})
    W.session = {
        totalAmount = 300, durationSeconds = 10, maxAmount = 200,
        combatSources = {
            { name = "A", totalAmount = 100, amountPerSecond = 10, classFilename = "MAGE" },
            { name = "B", totalAmount = 200, amountPerSecond = 20, classFilename = "ROGUE", isLocalPlayer = true },
        },
    }
    W.dmCalls = {}
    W.Update(0.05)
    eq(#W.dmCalls, 0, "not yet")
    W.Update(0.06)
    truthy(contains(W.dmCalls, "GetCombatSessionFromType"))
    local rows = shownRows(MoteveFrame)
    eq(rows[1].name:GetText(), "B"); eq(rows[1].total:GetText(), "200"); eq(rows[1].rate:GetText(), "20")
    eq(rows[1].pct:GetText(), "67%")
    eq(MoteveFrame.foot.total:GetText(), "300")
end)

---------------------------------------------------------------------------
-- Compact threat window
---------------------------------------------------------------------------
test("the Threat ablak preset is a compact 200x140 threat window", function()
    W.Boot({ units = GROUP, party = true, attackable = { target = true },
        threat = {}, })
    W.Slash("threat")
    local cfg = MoteveDB.windows[2]
    eq(cfg.mode, THREAT); eq(cfg.compact, true); eq(cfg.w, 200); eq(cfg.h, 140)
    local win = MoteveFrame2
    eq(win.footer:IsShown(), false)
    eq(win.L.barH, 16); eq(win.L.footerH, 0)
    win:Refresh()
    eq(#win.rows, 5, "five rows fit")
    eq(win.rows[1]:GetHeight(), 16)
    eq(MoteveFrame.footer:IsShown(), true)
    eq(MoteveFrame.L.barH, 22)
end)

---------------------------------------------------------------------------
-- Earlier fights (top-right picker, C_DamageMeter session IDs)
---------------------------------------------------------------------------
-- sessions 1..n named "Fight <id>", <id>*10 seconds long, handed out in a shuffled order
local function pastFights(n)
    local list = {}
    for id = 1, n, 2 do list[#list + 1] = { sessionID = id, name = "Fight " .. id, durationSeconds = id * 10 } end
    for id = 2, n, 2 do list[#list + 1] = { sessionID = id, name = "Fight " .. id, durationSeconds = id * 10 } end
    return list
end

local CURRENT_SESSION = {
    totalAmount = 30, durationSeconds = 5,
    combatSources = { { name = "Now", totalAmount = 30, amountPerSecond = 6, classFilename = "MAGE", sourceGUID = "g-now" } },
}

local OLD_SESSION = {
    totalAmount = 500, durationSeconds = 70, maxAmount = 300,
    combatSources = {
        { name = "Old1", totalAmount = 200, amountPerSecond = 3, classFilename = "MAGE", sourceGUID = "g-1", sourceCreatureID = 0 },
        { name = "Old2", totalAmount = 300, amountPerSecond = 4, classFilename = "ROGUE", sourceGUID = "g-2", sourceCreatureID = 0 },
    },
}

local function pickerBoot(db)
    W.Boot({ db = db, sessions = pastFights(13), sessionsByID = { [5] = OLD_SESSION, [7] = OLD_SESSION } })
    W.session = CURRENT_SESSION
    for _, w in ipairs({ MoteveFrame, MoteveFrame2 }) do w:Refresh() end
end

local function pickFight(win, label)
    MoteveDropdown:Hide()
    W.ClickSegment(win)
    truthy(MoteveDropdown:IsShown(), "picker opened")
    truthy(W.ClickMenu(label), "menu item " .. label)
end

test("the SZAKASZ part of the mode menu still holds exactly Aktuális harc and Összesített", function()
    pickerBoot()
    W.Fire(MoteveFrame.modeBtn, "OnClick")
    local spec, at = MoteveDropdown.spec, nil
    for i, s in ipairs(spec) do if s.kind == "header" and s.text == "SZAKASZ" then at = i end end
    truthy(at, "SZAKASZ header")
    eq(spec[at + 1].kind, "option"); eq(spec[at + 1].text, "Aktuális harc")
    eq(spec[at + 2].kind, "option"); eq(spec[at + 2].text, "Összesített")
    eq(spec[at + 3].kind, "sep")
    for _, t in ipairs(W.MenuTexts()) do truthy(not t:find("Fight", 1, true), "no fight in the mode menu: " .. t) end
end)

test("the picker lists Aktuális, then at most 10 fights by descending ID without the highest", function()
    pickerBoot()
    eq(MoteveFrame.segText:GetText(), "Aktuális")
    eq(MoteveFrame.segBtn.chev:IsShown(), true)
    W.ClickSegment(MoteveFrame)
    eq(MoteveDropdown:IsShown(), true)
    eq(MoteveDropdown.owner, MoteveFrame)
    local spec = MoteveDropdown.spec
    eq(spec[1].kind, "header"); eq(spec[1].text, "HARC")
    eq(spec[2].text, "Aktuális"); eq(spec[2].checked(), true)
    eq(spec[3].kind, "sep")
    local texts = W.MenuTexts()
    eq(#texts, 11, "Aktuális + 10 fights")
    eq(texts[1], "Aktuális")
    for i = 2, 11 do
        local id = 14 - i -- 12, 11, ..., 3
        eq(texts[i], string.format("Fight %d  ·  %d:%02d", id, math.floor(id * 10 / 60), id * 10 % 60))
    end
    truthy(contains(W.dmCalls, "GetAvailableCombatSessions"))
end)

test("a secret or missing fight name falls back to N. harc next to the duration", function()
    W.Boot({ sessions = {
        { sessionID = 9, name = "Top", durationSeconds = 1 },
        { sessionID = 8, name = W.Secret("Boss"), durationSeconds = 95 },
        { sessionID = 7, durationSeconds = 61 },
        { sessionID = 6, name = "", durationSeconds = 5 },
        { sessionID = 5, name = "No clock" },
        { sessionID = W.Secret(4), name = "Secret ID" },
    }, sessionsByID = { [8] = OLD_SESSION } })
    MoteveFrame:Refresh()
    W.ClickSegment(MoteveFrame)
    local texts = W.MenuTexts()
    eq(#texts, 5)
    eq(texts[2], "8. harc  ·  1:35")
    eq(texts[3], "7. harc  ·  1:01")
    eq(texts[4], "6. harc  ·  0:05")
    eq(texts[5], "No clock")
    truthy(W.ClickMenu("8. harc  ·  1:35"))
    eq(MoteveFrame.segText:GetText(), "8. harc")
end)

test("a picked fight is read by ID: rows, header and footer show that fight", function()
    pickerBoot()
    W.dmCalls, W.dmArgs = {}, {}
    pickFight(MoteveFrame, "Fight 7  ·  1:10")
    eq(MoteveFrame.sessionID, 7)
    local id, typeId = W.LastDMArgs("GetCombatSessionFromID")
    eq(id, 7); eq(typeId, 0)
    eq(contains(W.dmCalls, "GetCombatSessionFromType"), false, "no FromType call")
    local rows = shownRows(MoteveFrame)
    eq(#rows, 2)
    eq(rows[1].name:GetText(), "Old2"); eq(rows[1].total:GetText(), "300")
    eq(rows[2].name:GetText(), "Old1")
    eq(MoteveFrame.foot.total:GetText(), "500")
    eq(MoteveFrame.foot.left:GetText(), "1:10")
    eq(MoteveFrame.segText:GetText(), "Fight 7")
    -- the other window still shows the current fight
    W.ClickSegment(MoteveFrame)
    eq(MoteveDropdown.spec[2].checked(), false)
    MoteveDropdown:Hide()
end)

test("the row tooltip of a picked fight reads its spells by the same ID", function()
    pickerBoot()
    pickFight(MoteveFrame, "Fight 7  ·  1:10")
    W.dmCalls, W.dmArgs = {}, {}
    W.Fire(shownRows(MoteveFrame)[1], "OnEnter")
    local id, typeId, guid = W.LastDMArgs("GetCombatSessionSourceFromID")
    eq(id, 7); eq(typeId, 0); eq(guid, "g-2")
    eq(contains(W.dmCalls, "GetCombatSessionSourceFromType"), false)
end)

test("a fight picked mid-combat shows its duration in the footer, not the live marker", function()
    pickerBoot()
    W.inCombat = true
    MoteveFrame:Refresh()
    eq(MoteveFrame.foot.left:GetText(), "Harcban", "current fight is live")
    eq(MoteveFrame.foot.liveDot:IsShown(), true)
    pickFight(MoteveFrame, "Fight 7  ·  1:10")
    MoteveFrame:Refresh()
    eq(MoteveFrame.sessionID, 7)
    eq(MoteveFrame.foot.left:GetText(), "1:10")
    eq(MoteveFrame.foot.liveDot:IsShown(), false, "no live dot")
    eq(MoteveFrame.foot.pulse:IsPlaying(), false, "no pulse")
    W.inCombat = false
end)

test("a fight that is gone falls back to the current one in the same refresh", function()
    for _, broken in ipairs({ "nil", "error" }) do
        pickerBoot()
        pickFight(MoteveFrame, "Fight 7  ·  1:10")
        eq(MoteveFrame.sessionID, 7)
        if broken == "nil" then
            W.sessionsByID[7] = nil
        else
            C_DamageMeter.GetCombatSessionFromID = function() error("session expired") end
        end
        W.dmCalls = {}
        MoteveFrame:Refresh()
        eq(MoteveFrame.sessionID, nil, broken .. ": sessionID cleared")
        truthy(contains(W.dmCalls, "GetCombatSessionFromType"), broken .. ": FromType called")
        eq(shownRows(MoteveFrame)[1].name:GetText(), "Now", broken .. ": current rows")
        eq(MoteveFrame.segText:GetText(), "Aktuális", broken .. ": header")
    end
end)

test("PLAYER_REGEN_DISABLED brings every window back to the current fight", function()
    pickerBoot({ windows = { { mode = 1 }, { mode = 2 } } })
    pickFight(MoteveFrame, "Fight 7  ·  1:10")
    pickFight(MoteveFrame2, "Fight 5  ·  0:50")
    eq(MoteveFrame.sessionID, 7); eq(MoteveFrame2.sessionID, 5)
    W.FireEvent("PLAYER_REGEN_DISABLED")
    eq(MoteveFrame.sessionID, nil); eq(MoteveFrame2.sessionID, nil)
    W.Update(0.2)
    eq(MoteveFrame.segText:GetText(), "Aktuális"); eq(MoteveFrame2.segText:GetText(), "Aktuális")
end)

test("DAMAGE_METER_RESET, Adatok törlése and /moteve reset bring back the current fight", function()
    local resets = {
        function() W.FireEvent("DAMAGE_METER_RESET") end,
        function() W.Fire(MoteveFrame.modeBtn, "OnClick"); truthy(W.ClickMenu("Adatok törlése")) end,
        function() W.Slash("reset") end,
    }
    for i, reset in ipairs(resets) do
        pickerBoot({ windows = { { mode = 1 }, { mode = 1 } } })
        pickFight(MoteveFrame, "Fight 7  ·  1:10")
        pickFight(MoteveFrame2, "Fight 7  ·  1:10")
        reset()
        eq(MoteveFrame.sessionID, nil, "reset " .. i .. " window 1")
        eq(MoteveFrame2.sessionID, nil, "reset " .. i .. " window 2")
    end
end)

test("switching the segment drops the picked fight, switching the mode keeps it", function()
    pickerBoot()
    pickFight(MoteveFrame, "Fight 7  ·  1:10")
    W.Fire(MoteveFrame.modeBtn, "OnClick"); truthy(W.ClickMenu("Gyógyítás"))
    eq(MoteveFrame.sessionID, 7)
    local _, typeId = W.LastDMArgs("GetCombatSessionFromID")
    eq(typeId, 2, "healing read from the picked fight")
    W.Fire(MoteveFrame.modeBtn, "OnClick"); truthy(W.ClickMenu("Aktuális harc"))
    eq(MoteveFrame.sessionID, nil)
    pickFight(MoteveFrame, "Fight 7  ·  1:10")
    W.Fire(MoteveFrame.modeBtn, "OnClick"); truthy(W.ClickMenu("Összesített"))
    eq(MoteveFrame.sessionID, nil)
end)

test("no picker on the overall segment or in threat mode", function()
    W.Boot({ db = { windows = { { mode = 1, segment = 0 }, { mode = THREAT } } },
        sessions = pastFights(5), units = GROUP, attackable = { target = true } })
    MoteveFrame:Refresh(); MoteveFrame2:Refresh()
    eq(MoteveFrame.segText:GetText(), "Összesített")
    eq(MoteveFrame.segBtn.chev:IsShown(), false)
    W.ClickSegment(MoteveFrame)
    eq(MoteveDropdown:IsShown(), false, "no menu on Összesített")
    eq(MoteveFrame2.segText:GetText(), "Célpont")
    eq(MoteveFrame2.segBtn.chev:IsShown(), false)
    W.ClickSegment(MoteveFrame2)
    eq(MoteveDropdown:IsShown(), false, "no menu in threat mode")
    W.units.target = nil; W.units.focus = { name = "Boss" }
    MoteveFrame2:Refresh()
    eq(MoteveFrame2.segText:GetText(), "Fókusz")
    W.ClickSegment(MoteveFrame2)
    eq(MoteveDropdown:IsShown(), false)
end)

test("without GetAvailableCombatSessions the picker stays shut and the type API is used", function()
    pickerBoot()
    C_DamageMeter.GetAvailableCombatSessions = nil
    W.dmCalls = {}
    MoteveFrame:Refresh()
    eq(MoteveFrame.segText:GetText(), "Aktuális")
    eq(MoteveFrame.segBtn.chev:IsShown(), false)
    W.ClickSegment(MoteveFrame)
    eq(MoteveDropdown:IsShown(), false)
    eq(MoteveFrame.sessionID, nil)
    truthy(contains(W.dmCalls, "GetCombatSessionFromType"))
    eq(contains(W.dmCalls, "GetCombatSessionFromID"), false)
end)

test("the picked fight is not saved and a reload starts on Aktuális", function()
    pickerBoot()
    pickFight(MoteveFrame, "Fight 7  ·  1:10")
    eq(MoteveFrame.sessionID, 7)
    for k in pairs(MoteveDB.windows[1]) do
        truthy(k ~= "sessionID" and k ~= "sessionLabel", "saved key " .. tostring(k))
    end
    W.Boot({ db = MoteveDB, sessions = pastFights(13), sessionsByID = { [7] = OLD_SESSION } })
    eq(MoteveFrame.sessionID, nil)
end)

test("the picker opens right-aligned, the other menus stay left-aligned", function()
    pickerBoot()
    W.ClickSegment(MoteveFrame)
    local p, rel, rp = MoteveDropdown:GetPoint()
    eq(p, "TOPRIGHT"); eq(rel, MoteveFrame.segBtn); eq(rp, "BOTTOMRIGHT")
    eq(#MoteveDropdown._points, 1)
    MoteveDropdown:Hide()
    W.Fire(MoteveFrame.modeBtn, "OnClick")
    p, rel, rp = MoteveDropdown:GetPoint()
    eq(p, "TOPLEFT"); eq(rel, MoteveFrame.modeBtn); eq(rp, "BOTTOMLEFT")
    MoteveDropdown:Hide()
    W.Fire(MoteveMinimapButton, "OnClick", "LeftButton")
    p, rel, rp = MoteveDropdown:GetPoint()
    eq(p, "TOPLEFT"); eq(rel, MoteveMinimapButton); eq(rp, "BOTTOMLEFT")
end)

test("a long fight name is cut so it does not reach the mode button", function()
    local long = string.rep("Very long boss name ", 4)
    W.Boot({ db = { windows = { { mode = 1, compact = true, w = 200, h = 140 } } },
        sessions = { { sessionID = 2, name = "Top" }, { sessionID = 1, name = long, durationSeconds = 30 } },
        sessionsByID = { [1] = OLD_SESSION } })
    MoteveFrame:Refresh()
    pickFight(MoteveFrame, long .. "  ·  0:30")
    eq(MoteveFrame.segText:GetText(), long)
    local L = MoteveFrame.L
    local modeRight = L.pad + MoteveFrame.title:GetStringWidth() + 6 + MoteveFrame.modeBtn:GetWidth()
    local btnLeft = MoteveFrame:GetWidth() - (L.pad - 5) - MoteveFrame.segBtn:GetWidth()
    truthy(btnLeft >= modeRight, string.format("button starts at %d, mode button ends at %d", btnLeft, modeRight))
    truthy(MoteveFrame.segText:GetWidth() < MoteveFrame.segText:GetStringWidth(), "text width capped")
end)

---------------------------------------------------------------------------
-- Minimap button
---------------------------------------------------------------------------
test("minimap angle and hide flag are read on load", function()
    W.Boot({ db = { windows = { {} }, minimap = { angle = 90, hide = true } } })
    local b = MoteveMinimapButton
    eq(b:IsShown(), false)
    local _, rel, _, x, y = b:GetPoint()
    eq(rel, Minimap)
    truthy(math.abs(x) < 0.001 and y > 70, "placed at the top of the minimap")
    W.Slash("minimap")
    eq(MoteveDB.minimap.hide, false); eq(b:IsShown(), true)
end)

test("minimap left click opens the window menu, right click toggles all windows", function()
    W.Boot({ db = { windows = { { mode = 1 }, { mode = THREAT } } } })
    local b = MoteveMinimapButton
    W.Fire(b, "OnClick", "LeftButton")
    local texts = W.MenuTexts()
    truthy(contains(texts, "+ Új ablak")); truthy(contains(texts, "+ Threat ablak"))
    truthy(contains(texts, "Eltávolítás: 1. ablak (Sebzés)"))
    truthy(contains(texts, "Eltávolítás: 2. ablak (Threat)"))
    truthy(W.ClickMenu("+ Threat ablak"))
    eq(countWindows(), 3); eq(MoteveDB.windows[3].compact, true)
    W.Fire(b, "OnClick", "LeftButton")
    truthy(W.ClickMenu("Eltávolítás: 1. ablak (Sebzés)"))
    eq(countWindows(), 2); eq(MoteveDB.windows[1].mode, THREAT)

    W.Fire(b, "OnClick", "RightButton")
    eq(MoteveFrame:IsShown(), false); eq(MoteveFrame2:IsShown(), false)
    eq(MoteveDB.windows[1].shown, false)
    W.Fire(b, "OnClick", "RightButton")
    eq(MoteveFrame:IsShown(), true); eq(MoteveFrame2:IsShown(), true)
end)

test("dragging the minimap button saves its angle", function()
    W.Boot({})
    local b = MoteveMinimapButton
    W.Fire(b, "OnDragStart")
    W.cursorX, W.cursorY = 100, 200 -- straight above the minimap centre (100, 100)
    W.Update(0.01)
    W.Fire(b, "OnDragStop")
    truthy(math.abs(MoteveDB.minimap.angle - 90) < 0.001, "angle 90, got " .. MoteveDB.minimap.angle)
    eq(b:GetScript("OnUpdate"), nil)
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
test("slash commands apply to every window and the usage lists the new ones", function()
    W.Boot({ db = { windows = { {}, {}, {} } } })
    W.Slash("lock")
    for i = 1, 3 do eq(MoteveDB.windows[i].locked, true) end
    W.Slash("unlock")
    for i = 1, 3 do eq(MoteveDB.windows[i].locked, false) end
    W.Slash("scale 1.5")
    for i = 1, 3 do eq(MoteveDB.windows[i].scale, 1.5) end
    W.Slash("hide")
    for i = 1, 3 do eq(MoteveDB.windows[i].shown, false) end
    W.Slash("show")
    for i = 1, 3 do eq(MoteveDB.windows[i].shown, true) end
    W.Slash("center")
    eq(MoteveDB.windows[1].point, "CENTER"); eq(MoteveDB.windows[3].point, "CENTER")
    W.Slash("help")
    local usage = W.printed[#W.printed]
    for _, word in ipairs({ "new", "threat", "minimap", "show", "hide", "lock", "unlock", "scale", "center" }) do
        truthy(usage:find(word, 1, true), "usage lists " .. word)
    end
end)

---------------------------------------------------------------------------
-- Addon folder, .toc and media paths
---------------------------------------------------------------------------
local function exists(path)
    local fh = io.open(path, "rb")
    if fh then fh:close() return true end
    return false
end

test("the addon folder and its .toc are both named Moteve Damage Meter", function()
    eq(W.ADDON, "Moteve Damage Meter")
    truthy(exists("Moteve Damage Meter/Moteve Damage Meter.toc"), "Moteve Damage Meter/Moteve Damage Meter.toc exists")
    eq(exists("Moteve/Moteve.toc"), false, "old Moteve/Moteve.toc is gone")
    eq(exists("Moteve Damage Meter/Moteve.toc"), false, "no .toc with the old name in the folder")
    local fields, files = W.ReadToc()
    local title = fields.Title:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    eq(title, "Moteve Damage Meter", "## Title matches the folder name")
    eq(fields.SavedVariables, "MoteveDB")
    eq(#files, 2)
    for _, file in ipairs(files) do
        truthy(exists("Moteve Damage Meter/" .. file), "listed file exists: " .. file)
    end
end)

test("fonts and textures resolve under Interface\\AddOns\\Moteve Damage Meter", function()
    local ns = W.Boot()
    local MEDIA = "Interface\\AddOns\\Moteve Damage Meter\\"
    eq(ns.FONT_TITLE, MEDIA .. "Fonts\\Marcellus-Regular.ttf")
    eq(ns.FONT_BODY, MEDIA .. "Fonts\\Barlow-Regular.ttf")
    eq(ns.FONT_BODY_BOLD, MEDIA .. "Fonts\\Barlow-SemiBold.ttf")
    eq(ns.TEX("glow"), MEDIA .. "Textures\\glow")
    local fonts, textures = 0, 0
    for _, path in ipairs(W.media) do
        if path:sub(1, #MEDIA) == MEDIA then
            -- the client path with the AddOns prefix removed is the file's path in the repository;
            -- textures may be given without their extension
            local file = W.ADDON .. "/" .. path:sub(#MEDIA + 1):gsub("\\", "/")
            truthy(exists(file) or exists(file .. ".tga") or exists(file .. ".blp"), "media file exists: " .. path)
            if file:find("/Fonts/", 1, true) then fonts = fonts + 1 else textures = textures + 1 end
        end
    end
    truthy(fonts > 0, "the addon set at least one of its own fonts")
    truthy(textures > 0, "the addon set at least one of its own textures")
end)

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
