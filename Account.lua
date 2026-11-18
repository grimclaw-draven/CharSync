-- CharSync: accountweite Einstellungen verfolgen (Reiter „Accountweit“).
-- Accountweite Einstellungen (SavedVariables der Addons, accountweite WoW-Optionen) gelten sofort für alle Chars – es gibt
-- nichts zu übertragen, aber man will Änderungen zurücknehmen können. Dafür merkt sich CharSync einen Stand
-- (CharSyncDB.acctBase) und zeigt jede Abweichung davon: zurücksetzen (alter Wert) oder übernehmen (neuer Stand).
-- Verfolgt werden nur einfache Werte (Schalter, Zahlen, kurze Texte); große Listen und Datenfelder (Zeit, Zähler,
-- Verlauf, Cache …) werden übersprungen, damit nur echte Einstellungen erscheinen.
local ADDON, CS = ...
local L = CS.L
local ACC = {}
CS.Account = ACC

local SEP = "\001"
local MAX_CHILDREN = 150      -- Tabellen mit mehr Einträgen sind Daten (Listen, Preise, Bestände), keine Einstellungen
local MAX_ARRAY = 30
local MAX_DEPTH = 8
local MAX_PER_SV = 4000
local MAX_STRING = 120
-- Schlüssel, die nach Spieldaten statt nach Einstellungen aussehen (Kleinbuchstaben, Teil des Namens)
local NOISE = {
    "time", "date", "last", "seen", "stamp", "count", "cache", "log", "history", "version", "session", "played",
    "money", "gold", "stat", "guid", "seed", "dump", "debug", "scan", "price", "record", "archive", "queue", "recent",
    "backup", "progress", "achievement", "unlocked", "death", "revision", "latest",
    "displaytext", "total",
}

-- Arbeit in Häppchen: läuft die Aufnahme im Hintergrund (Coroutine), gibt sie nach STEP Schritten den Frame frei,
-- damit das Spiel nicht einfriert. Außerhalb einer Coroutine (Tests, ACC.sync) läuft alles am Stück.
local STEP = 300
local steps = 0
local function Tick()
    steps = steps + 1
    if steps >= STEP then
        steps = 0
        if coroutine.running() then coroutine.yield() end
    end
end

-- Schlüssel, die bei fast allen Addons Daten pro Char/Realm enthalten (AceDB-Namensräume, Char-Listen)
local PER_CHAR_KEYS = { char = true, chars = true, characters = true, realm = true, realms = true, faction = true,
    factionrealm = true, profilekeys = true, class = true, race = true, toons = true, alts = true }

local function Noise(key)
    if type(key) ~= "string" then return false end
    local k = key:lower()
    if PER_CHAR_KEYS[k] then return true end
    for _, n in ipairs(NOISE) do
        if k:find(n, 1, true) then return true end
    end
    return false
end

local function Secret(v) return issecretvalue and issecretvalue(v) or false end

-- Pfad-Teil kodieren: Zahlen und Texte unterscheidbar halten, damit sich der Wert wiederherstellen lässt
local function Enc(k) return (type(k) == "number" and "#" or "$") .. tostring(k) end
local function Dec(seg)
    local p, rest = seg:sub(1, 1), seg:sub(2)
    if p == "#" then return tonumber(rest) end
    return rest
end

local function Simple(v)
    local t = type(v)
    if t == "boolean" or t == "number" then return not Secret(v) end
    if t == "string" then return #v <= MAX_STRING and not Secret(v) end
    return false
end

-- Einstellung oder Daten? Einstellungen haben Namen als Schlüssel (showMinimapButton, fontSize). Daten sind nach IDs
-- geordnet: Zahlen, Item-/Quest-IDs, Char- und Realm-Namen, Links – oder es sind lange Listen von Einträgen.
local function IdLike(k)
    if type(k) == "number" then return true end
    if type(k) ~= "string" then return true end
    if k:find("^%-?%d") then return true end                  -- 12345, "12345", "1:2"
    if k:find("^%u%a+%-%d+%-%x+") then return true end        -- GUIDs: "Player-6949-01188C11", "Creature-…"
    if k:find(" %- ") or k:find("[|%[%]]") or k:find(":%d") or k:find("::", 1, true) then return true end -- "Name - Realm", "item:123", "Name::Realm", Links (ATT-Optionen wie "Auto:List" bleiben)
    if #k > 40 then return true end
    -- Daten eines Chars: Schlüssel mit dem eigenen Namen samt Realm („Name-Realm“) oder dem Realm-Namen
    local me = UnitName and UnitName("player")
    if type(me) == "string" and me ~= "" and k:find(me .. "-", 1, true) then return true end
    local realm = GetRealmName and GetRealmName()
    if type(realm) == "string" and #realm > 3 and k:find((realm:gsub("%s", "")), 1, true) then return true end
    return false
end

-- Tabelle sieht nach Daten aus: viele Einträge mit ID-Schlüsseln oder viele gleichartige Unter-Einträge
local function LooksLikeData(t)
    if #t > MAX_ARRAY then return true end
    local n, ids, sub = 0, 0, 0
    for k, v in pairs(t) do
        n = n + 1
        if IdLike(k) then ids = ids + 1 end
        if type(v) == "table" then sub = sub + 1 end
        if n > 400 then return true end                        -- so viele Einträge hat keine Einstellungs-Tabelle
        if n >= 60 and ids / n > 0.5 then return true end      -- früh erkannt: nach IDs geordnet
        Tick()
    end
    if n >= 12 and ids / n > 0.5 then return true end         -- nach IDs geordnet
    if sub > MAX_CHILDREN then return true end                -- sehr viele Unter-Einträge (Datensätze)
    return false
end

local MAX_TABLES_PER_SV = 1500
local function Flatten(out, prefix, tbl, depth, budget)
    if depth > MAX_DEPTH or budget.n >= MAX_PER_SV then return end
    budget.t = (budget.t or 0) + 1
    if budget.t > MAX_TABLES_PER_SV then budget.n = MAX_PER_SV return end -- riesige Tabelle: hier aufhören
    if LooksLikeData(tbl) then return end
    for k, v in pairs(tbl) do
        if budget.n >= MAX_PER_SV then return end
        Tick()
        -- Zahlen-Schlüssel nur in kurzen Listen (z. B. Farben {r, g, b} als Liste), sonst sind es IDs (Berufe, Erfolge …)
        local numData = type(k) == "number" and (#tbl == 0 or k > #tbl)
        if (type(k) == "string" or type(k) == "number") and not Noise(k) and not numData and not (type(v) == "table" and IdLike(k)) then
            local id = prefix .. SEP .. Enc(k)
            if Simple(v) then
                out[id] = v
                budget.n = budget.n + 1
            elseif type(v) == "table" then
                Flatten(out, id, v, depth + 1, budget)
            end
        end
    end
end

---------------------------------------------------------------------------------------------------
-- Welche accountweiten SavedVariables gibt es? (aus den .toc-Angaben aller geladenen Addons)
---------------------------------------------------------------------------------------------------
local A = C_AddOns or {}
local svInfo -- sv -> { addon = Name, title = Titel }

local function StripCodes(s)
    return (tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

local function Meta(name, field)
    local f = A.GetAddOnMetadata or GetAddOnMetadata
    if not f then return nil end
    local ok, v = pcall(f, name, field)
    if ok and type(v) == "string" and v ~= "" then return v end
    return nil
end

-- Typische Namen gespeicherter Addon-Einstellungen (Ende des Namens, klein geschrieben)
local SV_SUFFIX = { "db", "settings", "config", "options", "vars", "variables", "sets", "profiles", "prefs", "saved", "conf" }
local svScanAt = -1000

local function LooksLikeSVName(name)
    local n = name:lower()
    if n:find("^c_") or n:find("^enum") or n:find("char", 1, true) then return false end -- Blizzard-APIs, Daten pro Char
    for _, suf in ipairs(SV_SUFFIX) do
        if #n > #suf and n:sub(-#suf) == suf then return true end
    end
    return false
end

local function IsFrameTable(t)
    if type(rawget(t, 0)) == "userdata" then return true end
    local ok, f = pcall(function() return t.GetObjectType end)
    return ok and type(f) == "function"
end

-- Gespeicherte Einstellungen enthalten nie Funktionen – Addon-Module und -Datenbanken schon.
-- Nur die ersten Einträge ansehen, das reicht und bleibt schnell.
local function HasFunctions(t)
    local n = 0
    for _, v in pairs(t) do
        if type(v) == "function" then return true end
        n = n + 1
        if n > 60 then return false end
    end
    return false
end

-- Addon-Titel zu einem Einstellungsnamen: das Addon, dessen Ordnername am Anfang steht (längster Treffer)
local function TitleFor(sv, addons)
    local low, best, bestLen = sv:lower(), nil, 0
    for _, a in ipairs(addons) do
        local an = a.name:lower():gsub("[^%w]", "")
        local sn = low:gsub("[^%w]", "")
        if #an >= 3 and sn:sub(1, #an) == an and #an > bestLen then best, bestLen = a, #an end
    end
    return best and best.title or sv, best and best.name or nil
end

-- Welche accountweiten SavedVariables gibt es?
-- 1) Angabe „SavedVariables“ aus der .toc (manche Clients geben sie über GetAddOnMetadata nicht heraus)
-- 2) zusätzlich alle globalen Tabellen mit typischem Namen (…DB, …Config, …Settings, …_Sets, …SavedVariables)
local svDirty = true
function ACC.MarkDirty() svDirty = true end

function ACC.SavedVariables(fresh)
    if svInfo and not svDirty and not fresh then return svInfo end
    svDirty = false
    svInfo = {}
    local num = (A.GetNumAddOns or GetNumAddOns)()
    local info = A.GetAddOnInfo or GetAddOnInfo
    local loaded = A.IsAddOnLoaded or IsAddOnLoaded
    local addons = {}
    for i = 1, num do
        local name = info(i)
        if name and name ~= ADDON and (not loaded or loaded(name)) then
            local title = StripCodes(Meta(name, "Title") or name)
            addons[#addons + 1] = { name = name, title = title }
            local list = Meta(name, "SavedVariables")
            if list then
                for sv in list:gmatch("[^,%s]+") do svInfo[sv] = { addon = name, title = title } end
            end
        end
    end
    for k, v in pairs(_G) do
        Tick()
        if type(k) == "string" and type(v) == "table" and not svInfo[k] and not k:find("^CharSync")
            and LooksLikeSVName(k) and not IsFrameTable(v) and not HasFunctions(v) then
            local title, addon = TitleFor(k, addons)
            svInfo[k] = { addon = addon, title = title } -- ohne passenden Addon-Namen steht der Tabellenname
        end
    end
    return svInfo
end

---------------------------------------------------------------------------------------------------
-- Aufnahme: Addon-Werte + accountweite WoW-Optionen
---------------------------------------------------------------------------------------------------
local acctCVarNames
local function AccountCVars(out)
    if not acctCVarNames then
        acctCVarNames = {}
        local getAll = (C_Console and C_Console.GetAllCommands) or ConsoleGetAllCommands
        local cvarType = (Enum and Enum.ConsoleCommandType and Enum.ConsoleCommandType.Cvar) or 0
        if not (getAll and C_CVar and C_CVar.GetCVarInfo) then return end
        local ok, list = pcall(getAll)
        if not ok or type(list) ~= "table" then return end
        for _, info in ipairs(list) do
            Tick()
            local name = info.command
            if info.commandType == cvarType and name and not (CS.CVarBlacklisted and CS.CVarBlacklisted(name)) and not Noise(name) then
                local ok2, value, _, _, isChar, locked, _, readonly = pcall(C_CVar.GetCVarInfo, name)
                if ok2 and value ~= nil and not isChar and not locked and not readonly and Simple(value) then
                    acctCVarNames[#acctCVarNames + 1] = name
                end
            end
        end
    end
    for _, name in ipairs(acctCVarNames) do
        local v = GetCVar(name)
        if v ~= nil and Simple(v) then out["cvar" .. SEP .. name] = v end
    end
end

local function DoCapture()
    local out = {}
    for sv in pairs(ACC.SavedVariables()) do
        local t = _G[sv]
        if type(t) == "table" then
            Flatten(out, "sv" .. SEP .. sv, t, 1, { n = 0 })
        elseif Simple(t) then
            out["sv" .. SEP .. sv] = t
        end
    end
    AccountCVars(out)
    -- Positionen aller verschobenen Fenster (WoW merkt sie pro Char): so lässt sich jedes Verschieben zurücknehmen
    if CS.ScanPlacedFrames then
        local ok, frames = pcall(CS.ScanPlacedFrames)
        if ok and type(frames) == "table" then
            for name, p in pairs(frames) do
                out["frame" .. SEP .. name] = ("%s|%s|%s|%.1f|%.1f"):format(p.point, p.rel, p.relPoint, p.x or 0, p.y or 0)
            end
        end
    end
    return out
end

local function Copy(t) local c = {} for k, v in pairs(t) do c[k] = v end return c end

ACC.sync = false            -- Tests: alles sofort statt im Hintergrund
ACC.MAX_AGE = 20            -- Sekunden, bis eine Aufnahme als veraltet gilt
local cache, cacheAt = nil, -1000
local job, waiters = nil, {}

local function Now() return GetTime and GetTime() or 0 end

-- sofort aufnehmen (Tests, ausdrücklich frisch)
function ACC.Capture(fresh)
    if not fresh and cache and Now() - cacheAt < ACC.MAX_AGE then return cache end
    if fresh then ACC.SavedVariables(true) end
    cache, cacheAt = DoCapture(), Now()
    return cache
end

-- im Hintergrund aufnehmen; cb(out) wird gerufen, wenn fertig
function ACC.Request(cb)
    if cb then waiters[#waiters + 1] = cb end
    if ACC.sync or not (coroutine and C_Timer and C_Timer.After) then
        ACC.Capture(true)
        local list = waiters; waiters = {}
        for _, f in ipairs(list) do f(cache) end
        return
    end
    if job then return end
    job = coroutine.create(function() return DoCapture() end)
    local function Step()
        local ok, res = coroutine.resume(job)
        if not ok then
            job = nil; waiters = {}
            CS.Print(L["|cffff6060Nicht übernommen:|r %s (%s)"]:format(L["Accountweite Einstellungen"], tostring(res)))
            return
        end
        if coroutine.status(job) == "dead" then
            job = nil
            cache, cacheAt = res, Now()
            local list = waiters; waiters = {}
            for _, f in ipairs(list) do f(cache) end
        else
            C_Timer.After(0, Step)
        end
    end
    Step()
end

function ACC.Busy() return job ~= nil end

-- Fenster wird zum ersten Mal gezogen und war beim Einloggen nicht erfasst: Position davor als Stand nachtragen
function ACC.NoteFrameBefore(name, p)
    local base = CS.db and CS.db.trackAccount and CS.db.acctBase
    if not (base and base.data and p) then return end
    local id = "frame" .. SEP .. name
    if base.data[id] == nil then
        base.data[id] = ("%s|%s|%s|%.1f|%.1f"):format(p.point, p.rel, p.relPoint, p.x or 0, p.y or 0)
    end
    ACC.Invalidate()
end
function ACC.Invalidate() cacheAt = -1000 end

---------------------------------------------------------------------------------------------------
-- Stand merken, Abweichungen, zurücksetzen, übernehmen
---------------------------------------------------------------------------------------------------
function ACC.Base() return CS.db and CS.db.acctBase end

local baseRequested = false
function ACC.SaveBase(cb)
    if baseRequested then return end
    baseRequested = true
    ACC.Invalidate()
    ACC.Request(function(out)
        baseRequested = false
        CS.db.acctBase = { time = time(), data = Copy(out) }
        if cb then cb() end
        if CS.UI then CS.UI.Refresh() end
    end)
end

-- erster Stand: beim Anhaken bzw. kurz nach dem Login
function ACC.EnsureBase()
    if CS.db and not CS.db.acctBase then ACC.SaveBase() end
end

local function Split(id)
    local parts = {}
    for seg in (id .. SEP):gmatch("(.-)" .. SEP) do parts[#parts + 1] = seg end
    return parts
end

-- Wert in die Addon-Tabelle zurückschreiben (fehlende Zwischentabellen anlegen; nil löscht den Schlüssel)
local function WriteValue(id, value)
    local parts = Split(id)
    if parts[1] == "cvar" then
        SetCVar(parts[2], value == nil and GetCVarDefault and GetCVarDefault(parts[2]) or value)
        return
    end
    if parts[1] == "frame" then
        local f = _G[parts[2]]
        if type(f) ~= "table" or not f.SetPoint then error(L["Fenster nicht gefunden"]) end
        if value == nil then
            if f.SetUserPlaced then f:SetUserPlaced(false) end -- vorher nie verschoben: Standardposition nach Neuladen
            return
        end
        local point, rel, relPoint, x, y = tostring(value):match("^(.-)|(.-)|(.-)|(.-)|(.-)$")
        CS.PlaceFrame(f, parts[2], point, rel, relPoint, tonumber(x) or 0, tonumber(y) or 0)
        return
    end
    local sv = parts[2]
    if #parts == 2 then _G[sv] = value return end
    if type(_G[sv]) ~= "table" then _G[sv] = {} end
    local t = _G[sv]
    local chain = {}
    for i = 3, #parts - 1 do
        local k = Dec(parts[i])
        if type(t[k]) ~= "table" then t[k] = {} end
        chain[#chain + 1] = { t, k }
        t = t[k]
    end
    t[Dec(parts[#parts])] = value
    if value == nil then
        for i = #chain, 1, -1 do
            local parent, k = chain[i][1], chain[i][2]
            if next(parent[k]) == nil then parent[k] = nil else break end
        end
    end
end

-- Sofort anwenden: Addons lesen ihre Einstellungen oft nur beim Laden. Für bekannte Fälle stößt CharSync das Addon
-- direkt an; sonst bleibt der Hinweis auf ein Neuladen. Jeder Eintrag gibt true zurück, wenn er den Wert angewendet hat.
local LIVE = {
    -- Minimap-Icons aller Addons, die die Bibliothek LibDBIcon nutzen: Position/Sichtbarkeit neu setzen
    function(parts)
        local key = Dec(parts[#parts])
        if key ~= "minimapPos" and key ~= "hide" then return false end
        local DBIcon = LibStub and LibStub("LibDBIcon-1.0", true)
        if not (DBIcon and DBIcon.GetButtonList and DBIcon.Refresh) then return false end
        for _, name in ipairs(DBIcon:GetButtonList() or {}) do pcall(DBIcon.Refresh, DBIcon, name) end
        return true
    end,
    -- WoW-Optionen wirken sofort
    function(parts) return parts[1] == "cvar" end,
    -- Fensterpositionen werden direkt gesetzt
    function(parts) return parts[1] == "frame" end,
}

local function ApplyLive(id)
    local parts = Split(id)
    for _, f in ipairs(LIVE) do
        local ok, done = pcall(f, parts)
        if ok and done then return true end
    end
    return false
end

local function Show(v, id)
    if id and id:find("^frame" .. SEP) then
        if v == nil then return L["Standardposition"] end
        local x, y = tostring(v):match("|([^|]*)|([^|]*)$")
        return ("%d, %d"):format(tonumber(x) or 0, tonumber(y) or 0)
    end
    if v == nil then return L["(nicht gesetzt)"] end
    if type(v) == "boolean" then return v and L["An"] or L["Aus"] end
    if type(v) == "number" then
        if v == math.floor(v) then return tostring(v) end
        return ("%.2f"):format(v)
    end
    return tostring(v)
end

-- Anzeige: Addon-Titel und lesbarer Pfad (Profilebenen von AceDB weglassen)
local function Describe(id)
    local parts = Split(id)
    if parts[1] == "cvar" then
        local name = parts[2]
        return L["WoW-Optionen (accountweit)"], CS.CVarLabel and CS.CVarLabel(name) or name, name
    end
    if parts[1] == "frame" then
        local label = CS.FrameLabel(parts[2])
        if CS.minimapFrames[parts[2]] or parts[2]:find("^LibDBIcon%d*_") then return L["Minimap-Icons"], label, parts[2] end
        return L["Fensterpositionen"], label, parts[2]
    end
    local sv = parts[2]
    local info = ACC.SavedVariables()[sv]
    local group = info and info.title or sv
    local segs = {}
    local i = 3
    if Dec(parts[3] or "") == "profiles" and parts[4] then i = 5 end -- AceDB: profiles › <Profil> › …
    for j = i, #parts do
        local k = Dec(parts[j])
        segs[#segs + 1] = type(k) == "number" and ("[" .. k .. "]") or tostring(k)
    end
    if #segs == 0 then segs[1] = sv end
    return group, table.concat(segs, " › "), sv
end

function ACC.Label(id)
    local ok, group, label = pcall(Describe, id)
    if not ok then return tostring(id) end
    return tostring(group) .. " › " .. tostring(label)
end

function ACC.Diff()
    local base = ACC.Base()
    local items = {}
    if not base or not base.data then return items end
    local now = cache
    if not now or Now() - cacheAt >= ACC.MAX_AGE then
        if ACC.sync then now = ACC.Capture(true)
        else
            ACC.Request(function() if CS.UI then CS.UI.Refresh() end end)
            if not now then return nil end
        end
    end
    local ids, seen = {}, {}
    for id in pairs(base.data) do ids[#ids + 1] = id; seen[id] = true end
    -- Tabellen, die es beim Einloggen schon gab (alle Vorfahren der gemerkten Einträge)
    local existed = {}
    for id in pairs(base.data) do
        local p = id
        while true do
            local cut = p:match("^(.*)" .. SEP .. "[^" .. SEP .. "]*$")
            if not cut or existed[cut] then break end
            existed[cut] = true
            p = cut
        end
    end
    for id in pairs(now) do if not seen[id] then ids[#ids + 1] = id end end
    -- neu angelegte Untertabellen: oberste neue Tabelle je Eintrag und wie viele Werte darin stecken
    local function Parent(x) return x:match("^(.*)" .. SEP .. "[^" .. SEP .. "]*$") end
    local function FreshTop(id)
        local top, p = nil, Parent(id)
        while p and not existed[p] do top = p; p = Parent(p) end
        return top
    end
    local freshCount = {}
    for id in pairs(now) do
        if base.data[id] == nil and not id:find("^frame" .. SEP) then
            local top = FreshTop(id)
            if top then freshCount[top] = (freshCount[top] or 0) + 1 end
        end
    end
    for _, id in ipairs(ids) do
        local old, cur = base.data[id], now[id]
        if id:find("^frame" .. SEP) and (CS.IsPooledName(Split(id)[2]) or CS.SkipFrameName(Split(id)[2] or "")) then old, cur = nil, nil end -- Markierungen: nie zeigen
        -- ganzer neuer Datensatz (z. B. ATT legt beim Verschieben ein Fenster mit Hintergrund, Farben … an): kein Rauschen.
        -- Kleine neue Tabellen (z. B. eine Position {x, y}) bleiben sichtbar und zurücksetzbar.
        local top = old == nil and not id:find("^frame" .. SEP) and FreshTop(id) or nil
        local freshTable = top ~= nil and (freshCount[top] or 0) > 6
        if not freshTable and CS.Ser(old) ~= CS.Ser(cur) and not (CS.db.excluded and CS.db.excluded["acct:" .. id]) then
            local group, label, tech = Describe(id)
            items[#items + 1] = {
                id = id, key = "acct:" .. id, group = group, label = label, tech = tech, acct = true,
                old = Show(old, id), cur = Show(cur, id), oldValue = old, curValue = cur,
            }
        end
    end
    table.sort(items, function(a, b)
        if a.group ~= b.group then return a.group < b.group end
        return a.label < b.label
    end)
    return items
end

local function ReloadHint()
    StaticPopup_Show("CHARSYNC_RELOAD")
end

-- Zugehörige Fenster/Icons eines Addon-Werts: alle Fenster-Einträge, deren Name mit demselben Wort beginnt wie die
-- Einstellungs-Tabelle des Addons (z. B. Tabelle „XyzDB“ -> Fenster „XyzMinimapButton“, „XyzMainFrame“).
-- Viele Addons lesen ihre gespeicherte Position nur beim Laden; das Fenster selbst mitzusetzen macht es sofort sichtbar.
local SV_STRIP = { "savedvariables", "settings", "config", "options", "profiles", "variables", "_sets", "sets", "vars", "prefs", "saved", "conf", "db" }
local function SVStem(sv)
    local s = sv:lower()
    for _, suf in ipairs(SV_STRIP) do
        if #s > #suf + 3 and s:sub(-#suf) == suf then s = s:sub(1, -#suf - 1) break end
    end
    s = s:gsub("[%d_]+$", "")
    return s
end

-- Gespeicherter Winkel eines Minimap-Icons in den Addon-Einstellungen: Einstellungs-Tabelle, deren Stamm wie der
-- Icon-Name beginnt (XyzDB -> XyzMinimapButton), darin Zahlen namens angle/minimapPos unter einem „minimap“-Pfad.
-- Viele Addons lesen diesen Winkel nur beim Laden – ohne ihn mitzuschreiben, gälte ein Zurücksetzen nur bis zum Neuladen.
local ANGLE_KEYS = { angle = true, minimappos = true, minimapangle = true, pos = true, position = true, degree = true, degrees = true }
function ACC.WriteIconAngle(frameName, deg)
    if type(frameName) ~= "string" then return 0 end
    local lname, n = frameName:lower(), 0
    for sv in pairs(ACC.SavedVariables() or {}) do
        local stem = SVStem(sv)
        local t = _G[sv]
        if #stem >= 5 and lname:sub(1, #stem) == stem and type(t) == "table" then
            local visited = 0
            local function walk(tbl, depth, minimapPath)
                if depth > 4 or visited > 300 then return end
                visited = visited + 1
                for k, v in pairs(tbl) do
                    if type(k) == "string" then
                        local lk = k:lower()
                        local mm = minimapPath or lk:find("minimap", 1, true) ~= nil
                        if type(v) == "number" and ANGLE_KEYS[lk] and (mm or lk:find("minimap", 1, true)) then
                            tbl[k] = deg
                            n = n + 1
                        elseif type(v) == "table" then
                            walk(v, depth + 1, mm)
                        end
                    end
                end
            end
            walk(t, 1, false)
        end
    end
    if n > 0 then ACC.Invalidate() end
    return n
end

-- nur Werte, die nach Position aussehen (sonst würde z. B. ein Sound-Schalter das verschobene Icon mit zurücksetzen)
local POS_WORDS = { "pos", "angle", "point", "anchor", "minimap", "offset" }
local function LooksLikePosition(parts)
    for i = 3, #parts do
        local k = tostring(Dec(parts[i])):lower()
        if k == "x" or k == "y" then return true end
        for _, w in ipairs(POS_WORDS) do if k:find(w, 1, true) then return true end end
    end
    return false
end

function ACC.LinkedFrames(item)
    local parts = Split(item.id)
    if parts[1] ~= "sv" or not LooksLikePosition(parts) then return {} end
    local stem = SVStem(parts[2])
    if #stem < 5 then return {} end
    local out = {}
    for _, it in ipairs(ACC.Diff() or {}) do
        if it.id:find("^frame" .. SEP) then
            local fname = Split(it.id)[2] or ""
            if fname:lower():sub(1, #stem) == stem then out[#out + 1] = it end
        end
    end
    return out
end

function ACC.Reset(item, quiet, noLinked)
    if InCombatLockdown() then CS.Print(L["Im Kampf nicht möglich."]) return false end
    local linked = (not noLinked) and ACC.LinkedFrames(item) or {}
    local ok, err = pcall(WriteValue, item.id, item.oldValue)
    if cache then cache[item.id] = item.oldValue end
    if not ok then
        CS.Print(L["|cffff6060Nicht übernommen:|r %s (%s)"]:format(item.label, tostring(err)))
        return false
    end
    local live = ApplyLive(item.id)
    -- zugehörige Fenster/Icons gleich mit zurücksetzen: dann ist die Änderung sofort zu sehen
    for _, fr in ipairs(linked) do
        if pcall(WriteValue, fr.id, fr.oldValue) then
            if cache then cache[fr.id] = fr.oldValue end
            live = true
        end
    end
    if not quiet then
        CS.Print(L["„%s“ zurückgesetzt."]:format(item.label))
        if not live then ReloadHint() end
    end
    return true, live
end

function ACC.Accept(item)
    local base = ACC.Base()
    if not base then return end
    base.data[item.id] = item.curValue
end

-- mehrere Einstellungen zurücksetzen (alle oder nur ausgewählte)
function ACC.ResetItems(list)
    local n, needReload = 0, false
    for _, it in ipairs(list or {}) do
        local ok, live = ACC.Reset(it, true)
        if ok then
            n = n + 1
            if not live then needReload = true end
        end
    end
    CS.Print(L["%d Einstellung(en) zurückgesetzt."]:format(n))
    if needReload then ReloadHint() end
end

function ACC.ResetAll()
    ACC.ResetItems(ACC.Diff())
end
