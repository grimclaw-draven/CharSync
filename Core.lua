-- CharSync: Vorlagen speichern, Abweichungen ermitteln, übernehmen.
-- Ein Addon kann keine Dateien anderer Chars schreiben. Deshalb speichert ein Vorlage-Char eine Momentaufnahme seiner
-- Einstellungen in der accountweiten SavedVariable CharSyncDB. Jeder andere Char vergleicht sich beim Login damit und
-- übernimmt nach Prüfung die ausgewählten Abweichungen.
--   allgemeine Vorlage  (CharSyncDB.template)               – gilt für alle Chars
--   Klassen-Vorlage     (CharSyncDB.classTemplates[Klasse]) – Makros und Aktionsleisten, nur für Chars derselben Klasse
local ADDON, CS = ...
local L = CS.L
_G.CharSync = CS

CS.MODULES = {}
CS.MODULE_ORDER = {}
CS.draggedFrames = {} -- Namen der Fenster, die in dieser Sitzung per Maus gezogen wurden
CS.dragBefore = {}    -- deren Position vor dem ersten Ziehen
CS.minimapFrames = {} -- Elemente an der Minimap (Icons), deren Position CharSync mitführt

-- Durchnummerierte Namen (…Frame10, …Pin12) stammen aus einem Vorrat von Markierungen (Karten-/Minimap-Pins),
-- die Addons laufend neu setzen – keine Fenster/Icons, die der Spieler verschiebt
-- Nur an der Minimap: Fenster mit Nummer am Ende (z. B. Taschen-Fenster „…Frame1“) sind normale Fenster.
function CS.IsPooledName(name)
    if type(name) ~= "string" or not name:find("%d+$") or name:find("^LibDBIcon") then return false end
    if CS.draggedFrames[name] then return false end -- vom Spieler gezogen: echtes Fenster
    local f = _G[name]
    if type(f) ~= "table" then return true end -- gibt es (noch) nicht: alte Markierung
    local ok, parent = pcall(function() return f:GetParent() end)
    if not ok or type(parent) ~= "table" then return true end
    return parent == _G.Minimap or parent == _G.MinimapBackdrop
end
CS.SCOPES = { "general", "class" }

function CS.RegisterModule(key, def)
    def.key = key
    def.scope = def.scope or "general"
    CS.MODULES[key] = def
    CS.MODULE_ORDER[#CS.MODULE_ORDER + 1] = key
end

function CS.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffCharSync:|r " .. tostring(msg))
end

function CS.CharKey()
    return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end

function CS.PlayerClass()
    local localized, file = UnitClass("player")
    return file or "?", localized or file or "?"
end

-- Text in der Klassenfarbe; resume = Farbcode, in dem der umgebende Text danach weiterläuft
-- (Farbcodes lassen sich nicht verschachteln: |r springt immer auf die Grundfarbe zurück)
function CS.ClassText(class, text, resume)
    local colors = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
    local c = class and colors and colors[class]
    if not c then return tostring(text) end
    local code = c.colorStr or ("ff%02x%02x%02x"):format((c.r or 1) * 255, (c.g or 1) * 255, (c.b or 1) * 255)
    return "|c" .. code .. tostring(text) .. "|r" .. (resume or "")
end

-- deterministische Serialisierung zum Vergleichen von Werten
function CS.Ser(v)
    local t = type(v)
    if t == "table" then
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        local parts = {}
        for _, k in ipairs(keys) do parts[#parts + 1] = tostring(k) .. "=" .. CS.Ser(v[k]) end
        return "{" .. table.concat(parts, ",") .. "}"
    elseif t == "number" then
        return string.format("%.3f", v)
    end
    return tostring(v)
end

local function InitDB()
    if type(CharSyncDB) ~= "table" then CharSyncDB = {} end
    local db = CharSyncDB
    db.modules = type(db.modules) == "table" and db.modules or {}
    for _, m in ipairs(CS.MODULE_ORDER) do
        if db.modules[m] == nil then db.modules[m] = true end
    end
    db.excluded = type(db.excluded) == "table" and db.excluded or {}
    db.collapsed = type(db.collapsed) == "table" and db.collapsed or {} -- zugeklappte Abschnitte der Liste
    db.minimap = type(db.minimap) == "table" and db.minimap or { hide = false }
    db.included = type(db.included) == "table" and db.included or {}
    db.classTemplates = type(db.classTemplates) == "table" and db.classTemplates or {}
    db.classMaster = type(db.classMaster) == "table" and db.classMaster or {}
    if db.autoApply == nil then db.autoApply = false end
    if db.autoUpdate == nil then db.autoUpdate = false end
    if type(CharSyncCharDB) ~= "table" then CharSyncCharDB = {} end
    CharSyncCharDB.applied = type(CharSyncCharDB.applied) == "table" and CharSyncCharDB.applied or {}
    CS.db, CS.cdb = db, CharSyncCharDB
end
CS.InitDB = InitDB

---------------------------------------------------------------------------------------------------
-- Vorlagen
---------------------------------------------------------------------------------------------------
function CS.Template(scope)
    if scope == "class" then return CS.db.classTemplates[(CS.PlayerClass())] end
    return CS.db.template
end

function CS.IsMaster(scope)
    if scope == "class" then return CS.db.classMaster[(CS.PlayerClass())] == CS.CharKey() end
    return CS.db.master == CS.CharKey()
end

-- Wird diese Vorlage von diesem Char automatisch aktualisiert? (eigene Option, Standard aus)
function CS.AutoUpdates(scope)
    return CS.db and CS.db.autoUpdate == true and CS.IsMaster(scope)
end

function CS.SetMaster(scope, on)
    local me = on and CS.CharKey() or nil
    if scope == "class" then CS.db.classMaster[(CS.PlayerClass())] = me else CS.db.master = me end
end

-- auto = automatisch (Vorlage-Char): leere Ergebnisse (z. B. Aktionsleisten während des Ausloggens) ersetzen nie
-- eine gefüllte Vorlage, und ohne Änderung bleibt der Zeitstempel, damit andere Chars nicht grundlos gefragt werden.
function CS.SaveTemplate(scope, silent, auto)
    local old = CS.Template(scope)
    local oldData = (old and old.source == CS.CharKey() and old.data) or {}
    local data = {}
    for _, m in ipairs(CS.MODULE_ORDER) do
        local def = CS.MODULES[m]
        if def.scope == scope then
            local ok, res = pcall(def.capture)
            if ok then
                if auto and def.isEmpty and def.isEmpty(res) then
                    -- leer (z. B. beim Ausloggen): letzter gültiger Stand aus dem Spiel, sonst die bisherige Vorlage
                    if CS.live[m] ~= nil then res = CS.live[m]
                    elseif oldData[m] ~= nil and not def.isEmpty(oldData[m]) then res = oldData[m] end
                end
                data[m] = res
            elseif auto then
                data[m] = oldData[m]
            elseif not silent then
                CS.Print(L["Fehler beim Speichern von „%s“: %s"]:format(L[def.title], tostring(res)))
            end
        end
    end
    if auto and old and old.source == CS.CharKey() and CS.Ser(old.data) == CS.Ser(data) then return end
    local class, classLocal = CS.PlayerClass()
    local tpl = { source = CS.CharKey(), sourceName = UnitName("player"), class = class, classLocal = classLocal, time = time(), data = data }
    if scope == "class" then CS.db.classTemplates[class] = tpl else CS.db.template = tpl end
    CS.cdb.applied[scope] = tpl.time
    if not silent then
        if scope == "class" then
            CS.Print(L["Makros und Aktionsleisten von %s als Vorlage für %s gespeichert."]:format(CS.ClassText(class, tpl.sourceName), CS.ClassText(class, classLocal)))
        else
            CS.Print(L["Vorlage von %s gespeichert. Andere Chars übernehmen sie beim nächsten Login."]:format(CS.ClassText(class, tpl.sourceName)))
        end
    end
    if CS.UI then CS.UI.Refresh() end
end

-- Automatisch speichern (Option je Vorlage, Standard aus): höchstens einmal pro Minute und beim Ausloggen, nur bei Änderungen.
-- Dazwischen bleiben Änderungen sichtbar und lassen sich einzeln übernehmen oder zurücksetzen. CharSync merkt sich kurz nach
-- jeder Änderung den letzten gültigen Stand (CS.live), denn beim Ausloggen liefert WoW keine Aktionsleisten/Makros/Tasten mehr.
CS.AUTOSAVE_INTERVAL = 60
CS.live = {}
local autoPending, inWorld, ticker = false, false, nil
function CS.RememberLive()
    for _, scope in ipairs(CS.SCOPES) do
        if CS.AutoUpdates(scope) then
            for _, m in ipairs(CS.MODULE_ORDER) do
                local def = CS.MODULES[m]
                if def.scope == scope then
                    local ok, res = pcall(def.capture)
                    if ok and res ~= nil and not (def.isEmpty and def.isEmpty(res)) then CS.live[m] = res end
                end
            end
        end
    end
end
function CS.ScheduleAutoSave()
    if autoPending or not CS.db then return end
    autoPending = true
    C_Timer.After(3, function()
        autoPending = false
        -- nur wenn automatisch gespeichert wird; das Fenster rechnet bei Ereignissen NICHT neu (Looten & Co. sollen nichts kosten)
        if inWorld and not InCombatLockdown() then
            for _, scope in ipairs(CS.SCOPES) do
                if CS.AutoUpdates(scope) then CS.RememberLive() break end
            end
        end
    end)
end
-- einmal pro Minute: Vorlagen mit eingeschaltetem automatischem Speichern schreiben, wenn sich etwas geändert hat
function CS.AutoSaveTick()
    if not inWorld or not CS.db or InCombatLockdown() then return end
    for _, scope in ipairs(CS.SCOPES) do
        if CS.AutoUpdates(scope) then
            local own = 0
            for _, it in ipairs(CS.ComputeDiff()) do
                if CS.IsOwn(it) and CS.MODULES[it.module].scope == scope then own = own + 1 end
            end
            if own > 0 then
                CS.SaveTemplate(scope, true, true)
                CS.Print(L["Vorlage automatisch gespeichert (%d Änderungen)."]:format(own))
            end
        end
    end
end
function CS.StartAutoSave()
    if ticker or not C_Timer.NewTicker then return end
    ticker = C_Timer.NewTicker(CS.AUTOSAVE_INTERVAL, CS.AutoSaveTick)
end
function CS.SetInWorld(v) inWorld = v end

-- „Als allgemeine Vorlage speichern“: alles, was zu diesem Char gehört, so wie es gerade ist
function CS.SaveAll()
    CS.SaveTemplate("general")
    local ct = CS.Template("class")
    if CS.IsMaster("class") or (ct and ct.source == CS.CharKey()) then CS.SaveTemplate("class") end
    -- accountweite Einstellungen bleiben unberührt: die übernimmt man nur über die Knöpfe unten rechts
    if CS.UI and CS.UI.resetSel then
        for k in pairs(CS.UI.resetSel) do if not k:find("^acct:") then CS.UI.resetSel[k] = nil end end
    end
end

-- Vorlagen, die neuer sind als das, was dieser Char zuletzt übernommen hat
function CS.PendingScopes()
    local out = {}
    for _, scope in ipairs(CS.SCOPES) do
        local tpl = CS.Template(scope)
        if tpl and tpl.source ~= CS.CharKey() and (CS.cdb.applied[scope] or 0) < (tpl.time or 0) then
            out[#out + 1] = scope
        end
    end
    return out
end

---------------------------------------------------------------------------------------------------
-- Abweichungen
---------------------------------------------------------------------------------------------------
-- Eine Abweichung: { key, module, label, cur, new, desc, details = {Zeilen}, apply, reload,
--                    defaultOff = nur übernehmen, wenn ausdrücklich angehakt, blocked = Grund, warum es nicht geht }
function CS.ComputeDiff()
    local items = {}
    for _, m in ipairs(CS.MODULE_ORDER) do
        local def = CS.MODULES[m]
        local tpl = CS.Template(def.scope)
        if tpl and tpl.data and tpl.data[m] ~= nil then
            local ok, res = pcall(def.diff, tpl.data[m])
            if ok and type(res) == "table" then
                for _, it in ipairs(res) do
                    it.module = m
                    items[#items + 1] = it
                end
            elseif not ok then
                items[#items + 1] = { module = m, key = m .. ":error", label = L["Fehler beim Vergleichen"],
                    cur = "", new = "", desc = tostring(res), blocked = tostring(res), isError = true, apply = function() end }
            end
        end
    end
    return items
end

function CS.IsChecked(item)
    if item.blocked then return false end
    if item.defaultOff then return CS.db.included[item.key] == true end
    return not CS.db.excluded[item.key]
end

function CS.SetChecked(item, on)
    if item.defaultOff then CS.db.included[item.key] = on and true or nil
    else CS.db.excluded[item.key] = (not on) and true or nil end
end

-- Stammt die Vorlage dieses Bereichs von diesem Char selbst? Dann ist eine Abweichung eine Änderung seit dem Speichern,
-- die in die Vorlage gehört – nie etwas, das hier übernommen (also rückgängig gemacht) wird.
function CS.IsOwn(item)
    local def = CS.MODULES[item.module]
    local tpl = def and CS.Template(def.scope)
    return tpl ~= nil and tpl.source == CS.CharKey()
end

function CS.IsSelected(item)
    return CS.db.modules[item.module] and not CS.IsOwn(item) and CS.IsChecked(item)
end

-- Vorlagen dieses Chars neu speichern, in denen sich etwas geändert hat
function CS.UpdateOwnTemplates()
    local scopes = {}
    for _, it in ipairs(CS.ComputeDiff()) do
        if CS.IsOwn(it) then scopes[CS.MODULES[it.module].scope] = true end
    end
    for _, scope in ipairs(CS.SCOPES) do
        if scopes[scope] then CS.SaveTemplate(scope) end
    end
end

function CS.SelectedDiff()
    local out = {}
    for _, it in ipairs(CS.ComputeDiff()) do
        if CS.IsSelected(it) then out[#out + 1] = it end
    end
    return out
end

---------------------------------------------------------------------------------------------------
-- Übernehmen
---------------------------------------------------------------------------------------------------
local events = CreateFrame("Frame")

local function MarkApplied()
    for _, scope in ipairs(CS.SCOPES) do
        local tpl = CS.Template(scope)
        if tpl then CS.cdb.applied[scope] = tpl.time end
    end
end
CS.MarkApplied = MarkApplied

function CS.ApplyNow()
    if not CS.Template("general") and not CS.Template("class") then
        CS.Print(L["Es ist noch keine Vorlage gespeichert."])
        return
    end
    if InCombatLockdown() then
        CS.pendingApply = true
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
        CS.Print(L["Im Kampf – die Einstellungen werden nach dem Kampf übernommen."])
        return
    end
    local n, failed, reload = 0, 0, false
    local selected = CS.SelectedDiff()
    CS.SnapshotForUndo(selected)
    for _, it in ipairs(selected) do
        local ok, err = pcall(it.apply)
        if ClearCursor then ClearCursor() end
        if ok then
            n = n + 1
            if it.reload then reload = true end
            CS.Print(("  %s: |cffff9090%s|r » |cff90ff90%s|r"):format(it.label, tostring(it.cur or ""), tostring(it.new or "")))
        else
            failed = failed + 1
            CS.Print(L["|cffff6060Nicht übernommen:|r %s (%s)"]:format(it.label, tostring(err)))
        end
    end
    for _, m in ipairs(CS.MODULE_ORDER) do
        local def = CS.MODULES[m]
        if def.afterApply then pcall(def.afterApply) end
    end
    MarkApplied()
    if failed > 0 then
        CS.Print(L["%d Einstellung(en) übernommen, %d nicht möglich."]:format(n, failed))
    else
        CS.Print(L["%d Einstellung(en) übernommen."]:format(n))
    end
    if CS.UI then CS.UI.Refresh() end
    if reload then StaticPopup_Show("CHARSYNC_RELOAD") end
end

---------------------------------------------------------------------------------------------------
-- Einzelne Änderungen: in die Vorlage, zurücksetzen, rückgängig machen
---------------------------------------------------------------------------------------------------
local function RunOne(item, message)
    if CS.InvalidateFrames then CS.InvalidateFrames() end
    if InCombatLockdown() then
        CS.Print(L["Im Kampf nicht möglich."])
        return false
    end
    local ok, err = pcall(item.apply)
    if ClearCursor then ClearCursor() end
    local def = CS.MODULES[item.module]
    if def and def.afterApply then pcall(def.afterApply) end
    if not ok then
        CS.Print(L["|cffff6060Nicht übernommen:|r %s (%s)"]:format(item.label, tostring(err)))
        return false
    end
    if message then CS.Print(message:format(item.label)) end
    if item.reload then StaticPopup_Show("CHARSYNC_RELOAD") end
    return true
end

-- Vorlage-Char: nur diese eine Änderung in die Vorlage schreiben
function CS.PushItem(item)
    local def = CS.MODULES[item.module]
    local tpl = def and CS.Template(def.scope)
    if not (tpl and item.toTemplate) then return end
    local ok, err = pcall(item.toTemplate)
    if not ok then CS.Print(tostring(err)) return end
    tpl.time = time()
    CS.cdb.applied[def.scope] = tpl.time
    CS.Print(L["„%s“ in die Vorlage übernommen."]:format(item.label))
    if CS.UI then CS.UI.Refresh() end
end

-- Vorlage-Char: nur diese Einstellung bei sich selbst auf den Stand der Vorlage zurücksetzen
function CS.ResetItem(item)
    if item.noReset then return end
    RunOne(item, L["„%s“ zurückgesetzt."])
    if CS.UI then CS.UI.Refresh() end
end

-- Vor dem Übernehmen den alten Stand der betroffenen Bereiche sichern (pro Char)
function CS.SnapshotForUndo(items)
    local data, any = {}, false
    for _, it in ipairs(items) do
        local def = CS.MODULES[it.module]
        if def and data[it.module] == nil then
            local ok, res = pcall(def.capture)
            if ok and res ~= nil then data[it.module] = res; any = true end
        end
    end
    if any then CS.cdb.undo = { time = time(), data = data } end
end

-- Was sich seit der letzten Übernahme vom gesicherten Stand unterscheidet (jeder Eintrag stellt den alten Stand her)
function CS.UndoDiff()
    local undo = CS.cdb and CS.cdb.undo
    local items = {}
    if not undo or not undo.data then return items end
    for _, m in ipairs(CS.MODULE_ORDER) do
        local def = CS.MODULES[m]
        if undo.data[m] ~= nil then
            local ok, res = pcall(def.diff, undo.data[m], { undo = true })
            if ok and type(res) == "table" then
                for _, it in ipairs(res) do
                    if not it.blocked then
                        it.module = m
                        it.key = "undo:" .. tostring(it.key)
                        it.undo = true
                        items[#items + 1] = it
                    end
                end
            end
        end
    end
    return items
end

function CS.UndoItem(item)
    RunOne(item, L["„%s“ rückgängig gemacht."])
    if CS.UI then CS.UI.Refresh() end
end

function CS.ResetMany(list)
    if InCombatLockdown() then CS.Print(L["Im Kampf nicht möglich."]) return end
    local n = 0
    for _, it in ipairs(list or {}) do
        if not it.noReset and RunOne(it) then n = n + 1 end
    end
    CS.Print(L["%d Einstellung(en) zurückgesetzt."]:format(n))
    if CS.UI then CS.UI.Refresh() end
end

function CS.UndoAll()
    if InCombatLockdown() then CS.Print(L["Im Kampf nicht möglich."]) return end
    local n = 0
    for _, it in ipairs(CS.UndoDiff()) do
        if RunOne(it) then n = n + 1 end
    end
    CS.cdb.undo = nil
    CS.Print(L["%d Änderung(en) rückgängig gemacht."]:format(n))
    if CS.UI then CS.UI.Refresh() end
end

function CS.LoginCheck()
    if #CS.PendingScopes() == 0 then return end
    local items = CS.SelectedDiff()
    if #items == 0 then MarkApplied() return end
    if CS.db.autoApply then CS.ApplyNow() else CS.UI.ShowReview() end
end

StaticPopupDialogs["CHARSYNC_RELOAD"] = {
    text = L["|cff33ccffCharSync|r\n\nEinige Änderungen (Addons, Profile, Edit-Mode) werden erst nach einem Neuladen der Oberfläche vollständig aktiv.\n\nJetzt neu laden?"],
    button1 = L["Neu laden"],
    button2 = L["Später"],
    OnAccept = function() ReloadUI() end,
    timeout = 0, whileDead = 1, hideOnEscape = 1, preferredIndex = 3,
}

events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_LOGOUT")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_LEAVING_WORLD")
-- Änderungen, nach denen ein Vorlage-Char seine Vorlage aktualisiert
local CHANGE_EVENTS = { "ACTIONBAR_SLOT_CHANGED", "UPDATE_MACROS", "UPDATE_BINDINGS", "CVAR_UPDATE", "EDIT_MODE_LAYOUTS_UPDATED", "UPDATE_CHAT_WINDOWS", "UPDATE_CHAT_COLOR" }
for _, e in ipairs(CHANGE_EVENTS) do pcall(events.RegisterEvent, events, e) end
local IS_CHANGE = {}
for _, e in ipairs(CHANGE_EVENTS) do IS_CHANGE[e] = true end
events:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 ~= ADDON then
        if CS.Account then CS.Account.MarkDirty() end
    elseif event == "ADDON_LOADED" and arg1 == ADDON then
        InitDB()
        if CS.UI then CS.UI.RegisterSettings() end
    elseif event == "PLAYER_LOGIN" then
        if CS.UI then CS.UI.CreateMinimapButton() end
    elseif event == "PLAYER_ENTERING_WORLD" then
        if arg1 then C_Timer.After(6, CS.LoginCheck) end -- nur beim echten Login, nicht bei /reload
        local isLogin = arg1
        C_Timer.After(8, function()
            CS.SetInWorld(true); CS.ScheduleAutoSave(); CS.StartAutoSave()
            -- accountweite Einstellungen: bei jedem Einloggen neuer Stand (nicht bei /reload – manche Addons schreiben
            -- ihre Änderungen erst dabei, sie sollen sichtbar bleiben)
            if CS.Account and CS.db.trackAccount then
                if isLogin then pcall(CS.Account.SaveBase) else pcall(CS.Account.EnsureBase) end
            end
        end)
    elseif event == "PLAYER_LEAVING_WORLD" then
        CS.SetInWorld(false)
    elseif IS_CHANGE[event] then
        CS.ScheduleAutoSave()
    elseif event == "PLAYER_LOGOUT" then
        -- letzte Sicherung; leere Aktionsleisten/Makros/Tasten beim Ausloggen überschreiben die Vorlage nicht
        if not CS.db then return end
        for _, scope in ipairs(CS.SCOPES) do
            if CS.AutoUpdates(scope) then CS.SaveTemplate(scope, true, true) end
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        if CS.pendingApply then CS.pendingApply = nil; CS.ApplyNow() end
    end
end)

SLASH_CHARSYNC1 = "/charsync"
SLASH_CHARSYNC2 = "/csync"
SlashCmdList.CHARSYNC = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "save" then CS.SaveTemplate("general"); CS.UI.Refresh()
    elseif msg == "saveclass" then CS.SaveTemplate("class"); CS.UI.Refresh()
    elseif msg == "apply" then CS.ApplyNow()
    elseif msg == "icon" or msg == "minimap" then CS.UI.ResetMinimapButton()
    else CS.UI.Toggle() end
end
