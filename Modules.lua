-- CharSync: Bereiche. Jeder Bereich liefert capture() (Momentaufnahme) und diff(vorlage) -> Abweichungen.
-- Reihenfolge = Reihenfolge beim Übernehmen (Makros vor Aktionsleisten, damit neue Makros schon da sind).
local ADDON, CS = ...
local L = CS.L
local Ser = CS.Ser
local NONE = "—"

local function short(v, n)
    v = tostring(v)
    n = n or 48
    if #v > n then return v:sub(1, n - 1) .. "…" end
    return v
end

local function SortedKeys(t)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    return keys
end

local function StripCodes(s)
    return (tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

---------------------------------------------------------------------------------------------------
-- 1) Interface-Optionen: CVars, die WoW pro Charakter speichert
---------------------------------------------------------------------------------------------------
-- Spielstand/Zustand statt Einstellung -> nie synchronisieren
local CVAR_BLACKLIST = {
    "^tracked", "^hardTracked", "^camera", "Collapsed", "^num", "^last", "Club", "^EJ", "^lfg", "Recipe",
    "Shapeshift", "^currency", "^reputation", "^transmog", "^petJournal", "^toy", "^heirloom", "^mountJournal",
    "^wardrobe", "Seen", "^flagged", "^talent", "^spec", "^professionsOrder", "^playerStat",
}
local CVAR_FALLBACK = {}
for name in pairs(CS.CVAR_INFO) do CVAR_FALLBACK[#CVAR_FALLBACK + 1] = name end

local function Blacklisted(name)
    for _, p in ipairs(CVAR_BLACKLIST) do
        if name:find(p) then return true end
    end
    return false
end
CS.CVarBlacklisted = Blacklisted

local function CharCVarNames()
    local names, seen = {}, {}
    local getAll = (C_Console and C_Console.GetAllCommands) or ConsoleGetAllCommands
    local cvarType = (Enum and Enum.ConsoleCommandType and Enum.ConsoleCommandType.Cvar) or 0
    if getAll and C_CVar and C_CVar.GetCVarInfo then
        local ok, list = pcall(getAll)
        if ok and type(list) == "table" then
            for _, info in ipairs(list) do
                local name = info.command
                if info.commandType == cvarType and name and not seen[name] and not Blacklisted(name) then
                    local ok2, value, _, _, isChar, locked, _, readonly = pcall(C_CVar.GetCVarInfo, name)
                    if ok2 and value ~= nil and isChar and not locked and not readonly then
                        seen[name] = true
                        names[#names + 1] = name
                    end
                end
            end
        end
    end
    for _, name in ipairs(CVAR_FALLBACK) do
        if not seen[name] and GetCVar(name) ~= nil then
            seen[name] = true
            names[#names + 1] = name
        end
    end
    return names
end

CS.RegisterModule("cvars", {
    title = "Interface-Optionen",
    desc = "Optionen, die WoW pro Charakter speichert: zusätzliche Aktionsleisten, persönliche Ressourcenanzeige, Questlevel, Raidframe-Optionen, Weltkarte, Minimap. Grafik, Sound und die meisten anderen Optionen gelten ohnehin für alle Chars.",
    capture = function()
        local t = {}
        for _, name in ipairs(CharCVarNames()) do t[name] = GetCVar(name) end
        return t
    end,
    diff = function(tpl)
        local items = {}
        for _, name in ipairs(SortedKeys(tpl)) do
            local want, cur = tpl[name], GetCVar(name)
            if cur ~= nil and tostring(cur) ~= tostring(want) and not Blacklisted(name) then
                items[#items + 1] = {
                    key = "cvars:" .. name, label = CS.CVarLabel(name),
                    cur = CS.CVarValue(name, cur), new = CS.CVarValue(name, want),
                    desc = CS.CVarDesc(name),
                    details = { L["Interner Name: %s"]:format(name) },
                    apply = function() SetCVar(name, want) end,
                }
            end
        end
        return items
    end,
})

---------------------------------------------------------------------------------------------------
-- 2) Chatfenster und Chatfarben
---------------------------------------------------------------------------------------------------
local function NumChatWindows() return NUM_CHAT_WINDOWS or 10 end

local function GroupName(group)
    local g = _G[group]
    if type(g) == "string" and g ~= "" then return g end
    return group
end

local function ReadWindow(i)
    local name, size, r, g, b, a, shown, locked, docked = GetChatWindowInfo(i)
    local inUse = (i <= 2) or (name and name ~= "" and (shown or docked)) and true or false
    if not inUse then return { inUse = false } end
    local w = { inUse = true, name = name, size = size, r = r, g = g, b = b, a = a, locked = locked and true or false }
    local msgs = { GetChatWindowMessages(i) }
    table.sort(msgs)
    w.messages = msgs
    local ch, chans = { GetChatWindowChannels(i) }, {}
    for k = 1, #ch, 2 do chans[#chans + 1] = ch[k] end
    table.sort(chans)
    w.channels = chans
    return w
end

local function ReadColors()
    local t = {}
    for typ, info in pairs(ChatTypeInfo or {}) do
        if type(info) == "table" and info.r then t[typ] = { info.r, info.g, info.b } end
    end
    return t
end

local function Hex(c) return string.format("%02x%02x%02x", (c[1] or 0) * 255, (c[2] or 0) * 255, (c[3] or 0) * 255) end
local function Swatch(c) return "|cff" .. Hex(c) .. "■■■|r" end

local function ApplyWindowSettings(f, w, i)
    if FCF_SetWindowName and w.name then FCF_SetWindowName(f, w.name) end
    if FCF_SetChatWindowFontSize and w.size then FCF_SetChatWindowFontSize(nil, f, w.size) end
    if FCF_SetWindowColor and w.r then FCF_SetWindowColor(f, w.r, w.g, w.b) end
    if FCF_SetWindowAlpha and w.a then FCF_SetWindowAlpha(f, w.a) end
    if FCF_SetLocked then FCF_SetLocked(f, w.locked) end
    if i == 2 then return end -- Kampflog: keine Nachrichtengruppen/Kanäle
    if ChatFrame_RemoveAllMessageGroups then ChatFrame_RemoveAllMessageGroups(f) end
    for _, grp in ipairs(w.messages or {}) do ChatFrame_AddMessageGroup(f, grp) end
    local cur = { GetChatWindowChannels(f:GetID()) }
    for k = 1, #cur, 2 do ChatFrame_RemoveChannel(f, cur[k]) end
    for _, c in ipairs(w.channels or {}) do
        if GetChannelName(c) == 0 and JoinPermanentChannel then JoinPermanentChannel(c, nil, f:GetID()) end
        ChatFrame_AddChannel(f, c)
    end
end

-- Liste „+ dazu / − weg“ zwischen zwei sortierten Listen
local function ListChanges(old, new, nameOf)
    local inOld, inNew, out = {}, {}, {}
    for _, v in ipairs(old or {}) do inOld[v] = true end
    for _, v in ipairs(new or {}) do inNew[v] = true end
    for _, v in ipairs(new or {}) do if not inOld[v] then out[#out + 1] = "|cff90ff90+ " .. nameOf(v) .. "|r" end end
    for _, v in ipairs(old or {}) do if not inNew[v] then out[#out + 1] = "|cffff9090− " .. nameOf(v) .. "|r" end end
    return out
end

local function WindowDetails(cur, want)
    local d = {}
    if not cur.inUse then
        d[#d + 1] = L["Das Fenster wird neu angelegt."]
        cur = { messages = {}, channels = {} }
    elseif not want.inUse then
        d[#d + 1] = L["Das Fenster wird geschlossen."]
        return d
    end
    local function line(label, a, b) if tostring(a) ~= tostring(b) then d[#d + 1] = ("%s: %s → %s"):format(label, tostring(a or NONE), tostring(b or NONE)) end end
    line(L["Name"], cur.name, want.name)
    line(L["Schriftgröße"], cur.size, want.size)
    if cur.a and want.a then line(L["Hintergrund-Deckkraft"], math.floor(cur.a * 100 + 0.5) .. "%", math.floor(want.a * 100 + 0.5) .. "%") end
    if cur.r and want.r and Hex({ cur.r, cur.g, cur.b }) ~= Hex({ want.r, want.g, want.b }) then
        d[#d + 1] = L["Hintergrundfarbe: %s → %s"]:format(Swatch({ cur.r, cur.g, cur.b }), Swatch({ want.r, want.g, want.b }))
    end
    if cur.locked ~= nil and cur.locked ~= want.locked then line(L["Gesperrt"], CS.OnOff(cur.locked), CS.OnOff(want.locked)) end
    local msgs = ListChanges(cur.messages, want.messages, GroupName)
    if #msgs > 0 then
        d[#d + 1] = L["Nachrichten:"]
        for _, l in ipairs(msgs) do d[#d + 1] = "   " .. l end
    end
    local chans = ListChanges(cur.channels, want.channels, function(c) return c end)
    if #chans > 0 then
        d[#d + 1] = L["Kanäle:"]
        for _, l in ipairs(chans) do d[#d + 1] = "   " .. l end
    end
    return d
end

local function WindowSummary(w)
    if not w.inUse then return L["nicht vorhanden"] end
    return L["%s, Schrift %s, %d Nachrichtenarten, %d Kanäle"]:format(tostring(w.name), tostring(w.size), #(w.messages or {}), #(w.channels or {}))
end

CS.RegisterModule("chat", {
    title = "Chatfenster & Farben",
    desc = "Chat-Tabs (Name, Schriftgröße, Hintergrund), welche Nachrichtenarten und Kanäle darin erscheinen und die Farben der Chat-Arten. Fehlende Kanäle werden betreten.",
    capture = function()
        local t = { windows = {}, colors = ReadColors() }
        for i = 1, NumChatWindows() do t.windows[i] = ReadWindow(i) end
        return t
    end,
    diff = function(tpl)
        local items = {}
        for i = 1, NumChatWindows() do
            local want = tpl.windows and tpl.windows[i]
            if want then
                local cur = ReadWindow(i)
                if Ser(cur) ~= Ser(want) then
                    local name = want.name or cur.name
                    items[#items + 1] = {
                        key = "chat:window" .. i,
                        label = L["Chatfenster %d"]:format(i) .. ((name and name ~= "") and (" (" .. name .. ")") or ""),
                        cur = WindowSummary(cur), new = WindowSummary(want),
                        desc = L["Stellt diesen Chat-Tab so ein wie beim Vorlage-Char: Name, Schrift, Hintergrund und welche Nachrichten und Kanäle darin erscheinen."],
                        details = WindowDetails(cur, want),
                        apply = function()
                            local f = _G["ChatFrame" .. i]
                            local now = ReadWindow(i)
                            if want.inUse and not now.inUse and FCF_OpenNewWindow then
                                f = FCF_OpenNewWindow(want.name) or f
                            elseif not want.inUse and now.inUse and i > 2 and FCF_Close then
                                FCF_Close(f)
                                return
                            end
                            if f and want.inUse then ApplyWindowSettings(f, want, i) end
                        end,
                    }
                end
            end
        end
        if tpl.colors then
            local cur, changed, details = ReadColors(), {}, {}
            for _, typ in ipairs(SortedKeys(tpl.colors)) do
                local c = tpl.colors[typ]
                if cur[typ] and Hex(cur[typ]) ~= Hex(c) then
                    changed[#changed + 1] = typ
                    details[#details + 1] = ("%s: %s → %s"):format(GroupName(typ), Swatch(cur[typ]), Swatch(c))
                end
            end
            if #changed > 0 then
                items[#items + 1] = {
                    key = "chat:colors", label = L["Chatfarben"],
                    cur = L["%d Farben anders"]:format(#changed), new = L["Farben der Vorlage"],
                    desc = L["Färbt die Chat-Arten (Gilde, Gruppe, Flüstern …) wie beim Vorlage-Char."],
                    details = details,
                    apply = function()
                        for _, typ in ipairs(changed) do
                            local c = tpl.colors[typ]
                            ChangeChatColor(typ, c[1], c[2], c[3])
                        end
                    end,
                }
            end
        end
        return items
    end,
})

---------------------------------------------------------------------------------------------------
-- 3) Aktives Edit-Mode-Layout
---------------------------------------------------------------------------------------------------
local function EditModeLayouts()
    local f = EditModeManagerFrame
    if not (f and f.GetLayouts and f.GetActiveLayoutInfo and f.layoutInfo and C_EditMode and C_EditMode.SetActiveLayout) then return nil end
    return f:GetLayouts(), f:GetActiveLayoutInfo()
end

CS.RegisterModule("editmode", {
    title = "Edit-Mode-Layout",
    desc = "Welches Edit-Mode-Layout aktiv ist. Die Layouts selbst sind accountweit, nur die Auswahl ist pro Char.",
    capture = function()
        local _, active = EditModeLayouts()
        if not active then return nil end
        return { name = active.layoutName, type = active.layoutType }
    end,
    diff = function(tpl)
        local layouts, active = EditModeLayouts()
        if not layouts or not tpl.name then return {} end
        if active and active.layoutName == tpl.name then return {} end
        local exists = false
        for _, layout in ipairs(layouts) do if layout.layoutName == tpl.name then exists = true end end
        return { {
            key = "editmode:layout", label = L["Aktives Edit-Mode-Layout"],
            cur = active and active.layoutName or "?", new = tpl.name, reload = true,
            desc = L["Wechselt das Edit-Mode-Layout. Damit sitzen Aktionsleisten, Minimap, Einheitenfenster, Chat und Taschen dort, wo sie im Layout des Vorlage-Chars sitzen."],
            blocked = (not exists) and L["Das Layout gibt es bei diesem Char nicht (Charakter-Layout des Vorlage-Chars)."] or nil,
            apply = function()
                for index, layout in ipairs(EditModeLayouts() or {}) do
                    if layout.layoutName == tpl.name then
                        C_EditMode.SetActiveLayout(index)
                        return
                    end
                end
                error(L["Layout nicht gefunden"])
            end,
        } }
    end,
})

---------------------------------------------------------------------------------------------------
-- 4) Tastenbelegung
---------------------------------------------------------------------------------------------------
local function ReadBindings()
    local map = {}
    for i = 1, GetNumBindings() do
        local cmd, _, k1, k2 = GetBinding(i)
        if cmd and not cmd:find("^HEADER_") then
            if k1 then map[k1] = cmd end
            if k2 then map[k2] = cmd end
        end
    end
    return map
end

local function CommandName(cmd)
    if not cmd then return NONE end
    local n = _G["BINDING_NAME_" .. cmd]
    if type(n) == "string" and n ~= "" then return n end
    return cmd
end

local function KeyName(key)
    if GetBindingText then
        local ok, t = pcall(GetBindingText, key)
        if ok and type(t) == "string" and t ~= "" then return t end
    end
    return key
end

CS.RegisterModule("bindings", {
    title = "Tastenbelegung",
    desc = "Alle Tastenbelegungen. Nutzen alle Chars die accountweite Belegung, gibt es hier keine Abweichungen – wichtig nur für Chars mit charakterspezifischer Belegung.",
    capture = ReadBindings,
    diff = function(tpl)
        local cur, items = ReadBindings(), {}
        local keys = {}
        for key, cmd in pairs(tpl) do if cur[key] ~= cmd then keys[#keys + 1] = key end end
        for key in pairs(cur) do if tpl[key] == nil then keys[#keys + 1] = key end end
        table.sort(keys)
        for _, key in ipairs(keys) do
            local want = tpl[key]
            items[#items + 1] = {
                key = "bindings:" .. key, label = L["Taste %s"]:format(KeyName(key)),
                cur = CommandName(cur[key]), new = CommandName(want),
                desc = want and L["Belegt die Taste so wie beim Vorlage-Char."] or L["Entfernt die Belegung dieser Taste, weil sie beim Vorlage-Char frei ist."],
                apply = function()
                    if want then SetBinding(key, want) else SetBinding(key) end
                end,
            }
        end
        return items
    end,
    afterApply = function()
        if SaveBindings and GetCurrentBindingSet then SaveBindings(GetCurrentBindingSet()) end
    end,
})

---------------------------------------------------------------------------------------------------
-- 5) Addon-Auswahl
---------------------------------------------------------------------------------------------------
local A = C_AddOns or {}
local GetNumAddOnsF = A.GetNumAddOns or GetNumAddOns
local GetAddOnInfoF = A.GetAddOnInfo or GetAddOnInfo
local GetMetaF = A.GetAddOnMetadata or GetAddOnMetadata
local EnableAddOnF = A.EnableAddOn or EnableAddOn
local DisableAddOnF = A.DisableAddOn or DisableAddOn

local function AddOnEnabled(name)
    local me = UnitName("player")
    local state
    if A.GetAddOnEnableState then state = A.GetAddOnEnableState(name, me)
    else state = GetAddOnEnableState(me, name) end
    return (state or 0) > 0
end

local function AddOnMeta(name, field)
    if not GetMetaF then return nil end
    local ok, v = pcall(GetMetaF, name, field .. "-" .. (CS.LOCALE or ""))
    if not (ok and v) then ok, v = pcall(GetMetaF, name, field) end
    if ok and type(v) == "string" and v ~= "" then return StripCodes(v) end
    return nil
end

local function ReadAddons()
    local t = {}
    for i = 1, GetNumAddOnsF() do
        local name = GetAddOnInfoF(i)
        if name and name ~= ADDON then t[name] = AddOnEnabled(name) end
    end
    return t
end

CS.RegisterModule("addons", {
    title = "Addon-Auswahl",
    desc = "Welche Addons bei diesem Char aktiviert sind (Addon-Menü am Charakterauswahl-Bildschirm). Wird nach einem Neuladen aktiv.",
    capture = ReadAddons,
    diff = function(tpl)
        local items, cur = {}, ReadAddons()
        for _, name in ipairs(SortedKeys(tpl)) do
            local want = tpl[name]
            if cur[name] ~= nil and cur[name] ~= want then
                local title = AddOnMeta(name, "Title") or name
                local notes = AddOnMeta(name, "Notes")
                local what = want and L["Aktiviert das Addon „%s“ für diesen Char."]:format(title)
                    or L["Deaktiviert das Addon „%s“ für diesen Char. Seine Einstellungen bleiben erhalten."]:format(title)
                items[#items + 1] = {
                    key = "addons:" .. name, label = title,
                    cur = cur[name] and L["aktiv"] or L["aus"], new = want and L["aktiv"] or L["aus"], reload = true,
                    desc = what .. (notes and ("\n\n" .. L["Über das Addon: %s"]:format(notes)) or ""),
                    apply = function()
                        if want then EnableAddOnF(name, UnitName("player")) else DisableAddOnF(name, UnitName("player")) end
                    end,
                }
            end
        end
        return items
    end,
})

---------------------------------------------------------------------------------------------------
-- 6) Addon-Profile (Ace3 / AceDB): AtlasLoot, Questie, SilverDragon ...
---------------------------------------------------------------------------------------------------
local svNameCache
local function AceDatabases()
    local AceDB = LibStub and LibStub("AceDB-3.0", true)
    if not AceDB or not AceDB.db_registry then return {} end
    local roots, count = {}, 0
    for db in pairs(AceDB.db_registry) do
        if type(db) == "table" and db.sv and not db.parent then roots[db.sv] = db; count = count + 1 end
    end
    if not svNameCache or svNameCache.count ~= count then
        svNameCache = { count = count, names = {} }
        for k, v in pairs(_G) do
            if type(k) == "string" and type(v) == "table" and roots[v] then svNameCache.names[v] = k end
        end
    end
    local res = {}
    for sv, db in pairs(roots) do
        local name = svNameCache.names[sv]
        if name and db.GetCurrentProfile then res[name] = db end
    end
    return res
end

CS.RegisterModule("profiles", {
    title = "Addon-Profile (Ace3)",
    desc = "Welches Profil Ace3-Addons (z. B. AtlasLoot, Questie, SilverDragon) nutzen. Mit dem Profil des Vorlage-Chars teilen sich beide alle Einstellungen dieses Addons, auch Fensterpositionen und das Minimap-Icon.",
    capture = function()
        local t = {}
        for name, db in pairs(AceDatabases()) do t[name] = db:GetCurrentProfile() end
        return t
    end,
    diff = function(tpl)
        local items, dbs = {}, AceDatabases()
        for _, name in ipairs(SortedKeys(tpl)) do
            local want, db = tpl[name], dbs[name]
            if db then
                local cur = db:GetCurrentProfile()
                local exists = db.sv and db.sv.profiles and db.sv.profiles[want] ~= nil
                if cur ~= want and exists then
                    local addon = (name:gsub("DB$", ""):gsub("Config$", ""))
                    items[#items + 1] = {
                        key = "profiles:" .. name, label = L["Profil von %s"]:format(addon),
                        cur = short(cur), new = short(want), reload = true,
                        desc = L["Wechselt %s bei diesem Char auf das Profil „%s“. Danach gelten hier dieselben Einstellungen wie beim Vorlage-Char – Änderungen wirken künftig bei beiden. Das bisherige Profil bleibt gespeichert."]:format(addon, want),
                        apply = function() db:SetProfile(want) end,
                    }
                end
            end
        end
        return items
    end,
})

---------------------------------------------------------------------------------------------------
-- 7) MyCharForever (speichert seine Einstellungen pro Char, inkl. Minimap-Icon-Position)
---------------------------------------------------------------------------------------------------
local MCF_SKIP = { equipmentSeeded = true, achievementPanelsVersion = true, chronicleBindingInitialized = true }

local function MCFSettings()
    if type(MyCharForeverDB) ~= "table" then return nil end
    if type(MyCharForeverDB.settings) ~= "table" then MyCharForeverDB.settings = {} end
    return MyCharForeverDB.settings
end

CS.RegisterModule("mcf", {
    title = "MyCharForever",
    desc = "Einstellungen, die MyCharForever pro Char speichert: Minimap-Icon-Position, Karten-Markierungen, Screenshot-Optionen. Charakterdaten (Erfolge, Verlauf …) werden nicht angefasst.",
    capture = function()
        local s = MCFSettings()
        if not s then return nil end
        local t = {}
        for k, v in pairs(s) do
            if type(v) ~= "table" and type(v) ~= "function" and not MCF_SKIP[k] then t[k] = v end
        end
        return t
    end,
    diff = function(tpl)
        local s = MCFSettings()
        if not s then return {} end
        local items = {}
        for _, k in ipairs(SortedKeys(tpl)) do
            local want = tpl[k]
            if Ser(s[k]) ~= Ser(want) then
                items[#items + 1] = {
                    key = "mcf:" .. k, label = CS.MCFLabel(k),
                    cur = CS.MCFValue(k, s[k]), new = CS.MCFValue(k, want), reload = true,
                    desc = CS.MCFDesc(k),
                    apply = function() MCFSettings()[k] = want end,
                }
            end
        end
        return items
    end,
})

---------------------------------------------------------------------------------------------------
-- 8) Makros (nur Chars derselben Klasse). Accountweite Makros gelten ohnehin für alle Chars.
---------------------------------------------------------------------------------------------------
local function MacroLimits()
    return MAX_ACCOUNT_MACROS or 120, MAX_CHARACTER_MACROS or 18
end

local function ReadCharMacros()
    local maxAcc = MacroLimits()
    local _, numChar = GetNumMacros()
    local list = {}
    for i = maxAcc + 1, maxAcc + (numChar or 0) do
        local name, icon, body = GetMacroInfo(i)
        if name then list[#list + 1] = { name = name, icon = icon, body = body or "" } end
    end
    return list
end

local function FindCharMacro(name)
    local maxAcc = MacroLimits()
    local _, numChar = GetNumMacros()
    for i = maxAcc + 1, maxAcc + (numChar or 0) do
        if GetMacroInfo(i) == name then return i end
    end
    return nil
end

local function BodyLines(prefix, body)
    local out = {}
    for line in tostring(body or ""):gmatch("[^\n]+") do out[#out + 1] = prefix .. line end
    if #out == 0 then out[1] = prefix .. L["(leer)"] end
    return out
end

local function Append(t, list) for _, v in ipairs(list) do t[#t + 1] = v end return t end

CS.RegisterModule("macros", {
    scope = "class",
    title = "Makros",
    desc = "Charakterspezifische Makros – nur zwischen Chars derselben Klasse. Fehlende Makros werden angelegt, abweichende angepasst. Makros, die es beim Vorlage-Char nicht gibt, werden nur gelöscht, wenn du sie ausdrücklich anhakst.",
    capture = ReadCharMacros,
    diff = function(tpl)
        local items, cur, byName = {}, ReadCharMacros(), {}
        for _, m in ipairs(cur) do byName[m.name] = m end
        local _, maxChar = MacroLimits()
        local free = maxChar - #cur
        local wanted = {}
        for _, want in ipairs(tpl) do
            wanted[want.name] = true
            local have = byName[want.name]
            if not have then
                local blocked
                if free <= 0 then blocked = L["Kein Platz mehr für charakterspezifische Makros (höchstens %d)."]:format(maxChar) end
                free = free - 1
                items[#items + 1] = {
                    key = "macros:" .. want.name, label = L["Makro „%s“"]:format(want.name),
                    cur = L["nicht vorhanden"], new = L["wird angelegt"], blocked = blocked,
                    desc = L["Legt das Makro mit Symbol und Text wie beim Vorlage-Char an. Auf die Aktionsleiste kommt es über den Bereich „Aktionsleisten“."],
                    details = Append({ L["Text:"] }, BodyLines("   ", want.body)),
                    apply = function() CreateMacro(want.name, want.icon, want.body, true) end,
                }
            elseif have.body ~= want.body or tostring(have.icon) ~= tostring(want.icon) then
                local details = {}
                if have.body ~= want.body then
                    Append(details, { L["Vorher:"] }); Append(details, BodyLines("   |cffff9090", have.body))
                    Append(details, { L["Nachher:"] }); Append(details, BodyLines("   |cff90ff90", want.body))
                end
                if tostring(have.icon) ~= tostring(want.icon) then details[#details + 1] = L["Das Symbol ändert sich."] end
                items[#items + 1] = {
                    key = "macros:" .. want.name, label = L["Makro „%s“"]:format(want.name),
                    cur = L["anderer Inhalt"], new = L["Inhalt der Vorlage"],
                    desc = L["Ersetzt Text und Symbol dieses Makros durch die Fassung des Vorlage-Chars."],
                    details = details,
                    apply = function()
                        local idx = FindCharMacro(want.name)
                        if not idx then error(L["Makro nicht gefunden"]) end
                        EditMacro(idx, want.name, want.icon, want.body)
                    end,
                }
            end
        end
        for _, have in ipairs(cur) do
            if not wanted[have.name] then
                items[#items + 1] = {
                    key = "macros:del:" .. have.name, label = L["Makro „%s“"]:format(have.name),
                    cur = L["vorhanden"], new = L["wird gelöscht"], defaultOff = true,
                    desc = L["Dieses Makro gibt es beim Vorlage-Char nicht. Es wird nur gelöscht, wenn du den Haken setzt."],
                    details = Append({ L["Text:"] }, BodyLines("   ", have.body)),
                    apply = function()
                        local idx = FindCharMacro(have.name)
                        if idx then DeleteMacro(idx) end
                    end,
                }
            end
        end
        return items
    end,
})

---------------------------------------------------------------------------------------------------
-- 9) Aktionsleisten (nur Chars derselben Klasse)
---------------------------------------------------------------------------------------------------
local NUM_SLOTS = 120
local BAR_NAMES = {
    "Hauptleiste", "Hauptleiste Seite 2", "Leiste rechts", "Leiste rechts 2", "Leiste unten rechts", "Leiste unten links",
    "Haltungs-/Gestaltleiste 1", "Haltungs-/Gestaltleiste 2", "Haltungs-/Gestaltleiste 3", "Haltungs-/Gestaltleiste 4",
}

local function SlotLabel(slot)
    local bar = math.floor((slot - 1) / 12) + 1
    local pos = (slot - 1) % 12 + 1
    return L["%s, Platz %d"]:format(L[BAR_NAMES[bar] or "Leiste"], pos)
end

local function SpellName(id)
    if C_Spell and C_Spell.GetSpellName then
        local ok, n = pcall(C_Spell.GetSpellName, id)
        if ok and n then return n end
    end
    if GetSpellInfo then return (GetSpellInfo(id)) end
    return nil
end

local function ItemName(id)
    local n = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)) or (GetItemInfo and GetItemInfo(id))
    return n or L["Gegenstand %d"]:format(id)
end

local function ReadSlot(slot)
    if not HasAction(slot) then return { t = "none" } end
    local kind, id, sub = GetActionInfo(slot)
    if kind == "spell" then return { t = "spell", id = id, name = SpellName(id) } end
    if kind == "macro" then
        local name = GetMacroInfo(id)
        local maxAcc = MacroLimits()
        return { t = "macro", name = name, global = (id or 0) <= maxAcc }
    end
    if kind == "item" then return { t = "item", id = id } end
    if kind == "equipmentset" then return { t = "equipmentset", name = id } end
    return { t = tostring(kind), id = id, sub = sub }
end

-- Vergleichsschlüssel: Fähigkeiten nach Name (ein anderer Rang zählt als gleich)
local function SlotKey(s)
    if s.t == "spell" then return "spell:" .. tostring(s.name or s.id) end
    if s.t == "macro" then return "macro:" .. tostring(s.name) end
    if s.t == "item" then return "item:" .. tostring(s.id) end
    if s.t == "equipmentset" then return "set:" .. tostring(s.name) end
    if s.t == "none" then return "none" end
    return s.t .. ":" .. tostring(s.id)
end

local function SlotText(s)
    if s.t == "none" then return L["leer"] end
    if s.t == "spell" then return s.name or ("#" .. tostring(s.id)) end
    if s.t == "macro" then return L["Makro: %s"]:format(tostring(s.name)) end
    if s.t == "item" then return ItemName(s.id) end
    if s.t == "equipmentset" then return L["Ausrüstungsset: %s"]:format(tostring(s.name)) end
    return s.t
end

local function KnowsSpell(s)
    if s.id and IsSpellKnown and IsSpellKnown(s.id) then return true end
    if s.id and IsPlayerSpell and IsPlayerSpell(s.id) then return true end
    if s.name and GetSpellInfo and GetSpellInfo(s.name) then return true end
    return false
end

local function MacroExists(s)
    if FindCharMacro(s.name) then return true end
    return (GetMacroIndexByName and GetMacroIndexByName(s.name) or 0) > 0
end

local function PickupSlotContent(s)
    if s.t == "spell" then
        if s.id and IsSpellKnown and IsSpellKnown(s.id) then PickupSpell(s.id) else PickupSpell(s.name or s.id) end
    elseif s.t == "macro" then
        local idx = (not s.global and FindCharMacro(s.name)) or GetMacroIndexByName(s.name)
        if idx and idx > 0 then PickupMacro(idx) end
    elseif s.t == "item" then
        PickupItem(s.id)
    elseif s.t == "equipmentset" and C_EquipmentSet then
        local id = C_EquipmentSet.GetEquipmentSetID(s.name)
        if id then C_EquipmentSet.PickupEquipmentSet(id) end
    end
end

CS.RegisterModule("actionbars", {
    scope = "class",
    title = "Aktionsleisten",
    desc = "Was auf den Aktionsleisten liegt – nur zwischen Chars derselben Klasse. Fähigkeiten, die dieser Char noch nicht kennt, und Makros, die es hier nicht gibt, werden übersprungen.",
    capture = function()
        local t = {}
        for slot = 1, NUM_SLOTS do t[slot] = ReadSlot(slot) end
        return t
    end,
    diff = function(tpl)
        local items = {}
        local macroTpl = CS.Template("class")
        local macrosComing = {}
        if macroTpl and macroTpl.data and type(macroTpl.data.macros) == "table" and CS.db.modules.macros then
            for _, m in ipairs(macroTpl.data.macros) do macrosComing[m.name] = true end
        end
        for slot = 1, NUM_SLOTS do
            local want = tpl[slot]
            if want then
                local cur = ReadSlot(slot)
                if SlotKey(cur) ~= SlotKey(want) then
                    local blocked
                    if want.t == "spell" and not KnowsSpell(want) then
                        blocked = L["Diese Fähigkeit kennt dieser Char (noch) nicht."]
                    elseif want.t == "macro" and not MacroExists(want) and not macrosComing[want.name] then
                        blocked = L["Das Makro gibt es bei diesem Char nicht."]
                    elseif want.t ~= "none" and want.t ~= "spell" and want.t ~= "macro" and want.t ~= "item" and want.t ~= "equipmentset" then
                        blocked = L["Diese Art von Aktion kann nicht übertragen werden."]
                    end
                    items[#items + 1] = {
                        key = "actionbars:" .. slot, label = SlotLabel(slot),
                        cur = SlotText(cur), new = SlotText(want), blocked = blocked,
                        desc = (want.t == "none") and L["Leert diesen Platz, weil er beim Vorlage-Char frei ist."]
                            or L["Legt „%s“ auf diesen Platz der Aktionsleiste, wie beim Vorlage-Char."]:format(SlotText(want)),
                        apply = function()
                            ClearCursor()
                            if want.t == "none" then
                                PickupAction(slot)
                                ClearCursor()
                                return
                            end
                            PickupSlotContent(want)
                            if not GetCursorInfo() then error(L["konnte „%s“ nicht aufnehmen"]:format(SlotText(want))) end
                            PlaceAction(slot)
                            ClearCursor()
                        end,
                    }
                end
            end
        end
        return items
    end,
})
