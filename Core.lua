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
    db.included = type(db.included) == "table" and db.included or {}
    db.classTemplates = type(db.classTemplates) == "table" and db.classTemplates or {}
    db.classMaster = type(db.classMaster) == "table" and db.classMaster or {}
    if db.autoApply == nil then db.autoApply = false end
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

function CS.SetMaster(scope, on)
    local me = on and CS.CharKey() or nil
    if scope == "class" then CS.db.classMaster[(CS.PlayerClass())] = me else CS.db.master = me end
end

function CS.SaveTemplate(scope, silent)
    local data = {}
    for _, m in ipairs(CS.MODULE_ORDER) do
        local def = CS.MODULES[m]
        if def.scope == scope then
            local ok, res = pcall(def.capture)
            if ok then data[m] = res
            elseif not silent then CS.Print(L["Fehler beim Speichern von „%s“: %s"]:format(L[def.title], tostring(res))) end
        end
    end
    local class, classLocal = CS.PlayerClass()
    local tpl = { source = CS.CharKey(), sourceName = UnitName("player"), class = class, classLocal = classLocal, time = time(), data = data }
    if scope == "class" then CS.db.classTemplates[class] = tpl else CS.db.template = tpl end
    CS.cdb.applied[scope] = tpl.time
    if not silent then
        if scope == "class" then
            CS.Print(L["Makros und Aktionsleisten von %s als Vorlage für %s gespeichert."]:format(tpl.sourceName, classLocal))
        else
            CS.Print(L["Vorlage von %s gespeichert. Andere Chars übernehmen sie beim nächsten Login."]:format(tpl.sourceName))
        end
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
                    cur = "", new = "", desc = tostring(res), blocked = tostring(res), apply = function() end }
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

function CS.IsSelected(item)
    return CS.db.modules[item.module] and CS.IsChecked(item)
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
    for _, it in ipairs(CS.SelectedDiff()) do
        local ok, err = pcall(it.apply)
        if ClearCursor then ClearCursor() end
        if ok then
            n = n + 1
            if it.reload then reload = true end
            CS.Print(("  %s: |cffff9090%s|r → |cff90ff90%s|r"):format(it.label, tostring(it.cur or ""), tostring(it.new or "")))
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
events:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        InitDB()
        if CS.UI then CS.UI.RegisterSettings() end
    elseif event == "PLAYER_ENTERING_WORLD" then
        if arg1 then C_Timer.After(6, CS.LoginCheck) end -- nur beim echten Login, nicht bei /reload
    elseif event == "PLAYER_LOGOUT" then
        if not CS.db then return end
        for _, scope in ipairs(CS.SCOPES) do
            if CS.IsMaster(scope) then CS.SaveTemplate(scope, true) end
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
    else CS.UI.Toggle() end
end
