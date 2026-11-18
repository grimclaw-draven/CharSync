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

local cvarNamesCache
local function CharCVarNames()
    if cvarNamesCache then return cvarNamesCache end
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
    cvarNamesCache = names
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
                local curText, newText = CS.CVarDiffValues(name, cur, want)
                items[#items + 1] = {
                    key = "cvars:" .. name, label = CS.CVarLabel(name),
                    toTemplate = function() tpl[name] = cur end,
                    cur = curText, new = newText,
                    desc = CS.CVarDesc(name), effect = CS.CVarEffect(name, cur, want),
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
-- Farbfläche als Textur (das Zeichen ■ fehlt in den WoW-Schriften)
local function Swatch(c)
    return ("|TInterface\\Buttons\\WHITE8X8:12:24:0:0:8:8:0:8:0:8:%d:%d:%d|t"):format((c[1] or 0) * 255, (c[2] or 0) * 255, (c[3] or 0) * 255)
end

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
    local function line(label, a, b) if tostring(a) ~= tostring(b) then d[#d + 1] = ("%s: %s » %s"):format(label, tostring(a or NONE), tostring(b or NONE)) end end
    line(L["Name"], cur.name, want.name)
    line(L["Schriftgröße"], cur.size, want.size)
    if cur.a and want.a then line(L["Hintergrund-Deckkraft"], math.floor(cur.a * 100 + 0.5) .. "%", math.floor(want.a * 100 + 0.5) .. "%") end
    if cur.r and want.r and Hex({ cur.r, cur.g, cur.b }) ~= Hex({ want.r, want.g, want.b }) then
        d[#d + 1] = L["Hintergrundfarbe: %s » %s"]:format(Swatch({ cur.r, cur.g, cur.b }), Swatch({ want.r, want.g, want.b }))
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

-- Nur die Eigenschaften, in denen sich zwei Chatfenster unterscheiden – je Seite ein kurzer Text
local function WindowDiffTexts(a, b)
    if not a.inUse or not b.inUse then
        local function state(w) return w.inUse and (w.name or L["vorhanden"]) or L["nicht vorhanden"] end
        return state(a), state(b)
    end
    local pa, pb = {}, {}
    local function add(x, y) pa[#pa + 1] = x; pb[#pb + 1] = y end
    if tostring(a.name) ~= tostring(b.name) then add(tostring(a.name), tostring(b.name)) end
    if tostring(a.size) ~= tostring(b.size) then add(L["Schrift %s"]:format(tostring(a.size)), L["Schrift %s"]:format(tostring(b.size))) end
    if a.a and b.a and math.floor(a.a * 100 + 0.5) ~= math.floor(b.a * 100 + 0.5) then
        add(L["Deckkraft %s"]:format(math.floor(a.a * 100 + 0.5) .. "%"), L["Deckkraft %s"]:format(math.floor(b.a * 100 + 0.5) .. "%"))
    end
    if a.r and b.r and Hex({ a.r, a.g, a.b }) ~= Hex({ b.r, b.g, b.b }) then
        add(L["Farbe %s"]:format(Swatch({ a.r, a.g, a.b })), L["Farbe %s"]:format(Swatch({ b.r, b.g, b.b })))
    end
    if a.locked ~= b.locked then add(a.locked and L["gesperrt"] or L["nicht gesperrt"], b.locked and L["gesperrt"] or L["nicht gesperrt"]) end
    -- Listen: je Seite nur, was die andere nicht hat
    local function only(x, y, nameOf)
        local inY, out = {}, {}
        for _, v in ipairs(y or {}) do inY[v] = true end
        for _, v in ipairs(x or {}) do if not inY[v] then out[#out + 1] = nameOf(v) end end
        return #out > 0 and table.concat(out, ", ") or NONE
    end
    local ma, mb = only(a.messages, b.messages, GroupName), only(b.messages, a.messages, GroupName)
    if ma ~= NONE or mb ~= NONE then add(L["Nachrichten:"] .. " " .. ma, L["Nachrichten:"] .. " " .. mb) end
    local ca, cb = only(a.channels, b.channels, tostring), only(b.channels, a.channels, tostring)
    if ca ~= NONE or cb ~= NONE then add(L["Kanäle:"] .. " " .. ca, L["Kanäle:"] .. " " .. cb) end
    return table.concat(pa, ", "), table.concat(pb, ", ")
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
                        toTemplate = function() tpl.windows[i] = ReadWindow(i) end,
                        label = L["Chatfenster %d"]:format(i) .. ((name and name ~= "") and (" (" .. name .. ")") or ""),
                        cur = select(1, WindowDiffTexts(cur, want)), new = select(2, WindowDiffTexts(cur, want)),
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
                    details[#details + 1] = ("%s: %s » %s"):format(GroupName(typ), Swatch(cur[typ]), Swatch(c))
                end
            end
            if #changed > 0 then
                items[#items + 1] = {
                    key = "chat:colors", label = L["Chatfarben"],
                    toTemplate = function() tpl.colors = ReadColors() end,
                    cur = (function() local t = {} for _, typ in ipairs(changed) do t[#t + 1] = GroupName(typ) .. " " .. Swatch(cur[typ]) end return table.concat(t, ", ") end)(),
                    new = (function() local t = {} for _, typ in ipairs(changed) do t[#t + 1] = GroupName(typ) .. " " .. Swatch(tpl.colors[typ]) end return table.concat(t, ", ") end)(),
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
            toTemplate = function() local _, a = EditModeLayouts(); if a then tpl.name, tpl.type = a.layoutName, a.layoutType end end,
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
    isEmpty = function(t) return next(t) == nil end,
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
                toTemplate = function() tpl[key] = cur[key] end,
                cur = CommandName(cur[key]), new = CommandName(want),
                desc = want and L["Belegt die Taste so wie beim Vorlage-Char."] or L["Entfernt die Belegung dieser Taste, weil sie beim Vorlage-Char frei ist."],
                effect = (not want) and L["entfernt „%s“"]:format(CommandName(cur[key]))
                    or (cur[key] and L["ersetzt „%s“ durch „%s“"]:format(CommandName(cur[key]), CommandName(want)))
                    or L["belegt die Taste mit „%s“"]:format(CommandName(want)),
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
                    toTemplate = function() tpl[name] = cur[name] end,
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
-- 6) Addon-Profile (alle Addons, die die Bibliothek Ace3/AceDB nutzen)
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
    desc = "Welches Profil Addons nutzen, die ihre Einstellungen über die Bibliothek Ace3 speichern. Mit dem Profil des Vorlage-Chars teilen sich beide alle Einstellungen dieses Addons, auch Fensterpositionen und das Minimap-Icon.",
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
                        toTemplate = function() tpl[name] = cur end,
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
-- 7b) Fensterpositionen: verschobene Fenster, deren Position WoW pro Char merkt (IsUserPlaced, layout-local.txt).
-- Positionen, die ein Addon selbst accountweit speichert (z. B. Minimap-Knöpfe), gelten ohnehin für alle Chars.
---------------------------------------------------------------------------------------------------
local FRAME_SKIP = { UIParent = true, WorldFrame = true, Minimap = true }
local frameScan, frameScanAt = nil, -1
local hookedIcons = setmetatable({}, { __mode = "k" })

local function Round(v) return v and math.floor(v * 10 + 0.5) / 10 end

-- eigene Fenster/Icons nie mitführen (die Position des CharSync-Icons speichert CharSync selbst accountweit)
local function SkipName(name)
    if name == "CharSyncMinimapButton" then return false end -- eigenes Minimap-Icon: wie jedes andere Icon
    return FRAME_SKIP[name] or name:find("^CharSync") ~= nil
end

CS.SkipFrameName = SkipName

-- Fenster an eine Position setzen. Minimap-Icons nie als „vom Spieler platziert“ merken (das stellt WoW nach dem
-- Laden an einer alten Stelle wieder her); bei Icons mit gespeichertem Winkel (LibDBIcon und das eigene Icon:
-- button.db.minimapPos) den Winkel mitschreiben, damit die Position auch nach dem Neuladen gilt.
function CS.PlaceFrame(f, name, point, rel, relPoint, x, y)
    f:ClearAllPoints()
    f:SetPoint(point, _G[rel] or UIParent, relPoint, x or 0, y or 0)
    local icon = CS.minimapFrames[name] or (type(name) == "string" and name:find("^LibDBIcon") ~= nil)
    if icon then
        if (rel == "Minimap" or rel == nil) and point == "CENTER" and (x ~= 0 or y ~= 0) then
            local deg = math.deg(math.atan2(y or 0, x or 0))
            local db = rawget(f, "db")
            if type(db) == "table" then
                db.minimapPos = deg % 360                     -- LibDBIcon und das eigene Icon
            elseif CS.Account and CS.Account.WriteIconAngle then
                CS.Account.WriteIconAngle(name, deg)          -- eigener Winkel in den Addon-Einstellungen
            end
        end
        if f.SetUserPlaced then pcall(f.SetUserPlaced, f, false) end
    elseif f.SetUserPlaced and f.IsMovable and f:IsMovable() then
        pcall(f.SetUserPlaced, f, true)
    end
end

-- lesbarer Name: Minimap-Icons über LibDBIcon heißen intern „LibDBIcon10_<Addon>“
function CS.FrameLabel(name)
    local addon = type(name) == "string" and name:match("^LibDBIcon%d*_(.+)$")
    if addon then return L["Icon „%s“"]:format(addon) end
    if CS.minimapFrames[name] then return L["Icon „%s“"]:format(name) end
    return L["Fenster „%s“"]:format(name)
end

-- gesperrte Werte (moderne Clients wie Forever) lassen sich nicht vergleichen oder verrechnen
local function Secret(v) return issecretvalue and issecretvalue(v) or false end

local function ReadFrameRaw(f)
    local point, rel, relPoint, x, y = f:GetPoint(1)
    if not point or Secret(point) or Secret(x) or Secret(y) or Secret(rel) then return nil end
    local relName = (rel and rel.GetName and rel:GetName()) or "UIParent"
    if Secret(relName) then return nil end
    local t = { point = point, rel = relName, relPoint = relPoint or point, x = Round(x or 0), y = Round(y or 0) }
    local resizable = f.IsResizable and f:IsResizable()
    if not Secret(resizable) and resizable then
        local w, h = f:GetWidth(), f:GetHeight()
        if not Secret(w) and not Secret(h) then t.w, t.h = Round(w), Round(h) end
    end
    return t
end

-- jedes Fenster abgesichert lesen: ein geschütztes oder fremdes Fenster darf den Bereich nie abbrechen
local function ReadFrame(f)
    local ok, t = pcall(ReadFrameRaw, f)
    if ok then return t end
    return nil
end

local function Movable(f)
    -- gesperrte Werte (secret) nie auf wahr/falsch prüfen – erst Secret(), dann der Test
    local ok, forbidden = pcall(function() return f.IsForbidden and f:IsForbidden() end)
    if not ok or Secret(forbidden) or forbidden then return nil end
    local ok2, name, placed, protected = pcall(function()
        return f:GetName(), f:IsUserPlaced(), f.IsProtected and f:IsProtected()
    end)
    if not ok2 or Secret(name) or Secret(placed) or Secret(protected) then return nil end
    if not placed or protected or type(name) ~= "string" then return nil end
    return name
end

-- alle verschobenen, benannten Fenster (kurz zwischengespeichert, das Durchsuchen aller Frames kostet etwas)
local function ScanPlacedFrames()
    local now = GetTime and GetTime() or 0
    if frameScan and now - frameScanAt < 30 then return frameScan end
    local t = {}
    if EnumerateFrames then
        local f = EnumerateFrames()
        while f do
            -- billige Vorprüfung: nur verschobene Fenster genauer ansehen
            local ok, placed = pcall(f.IsUserPlaced, f)
            local name = ok and not Secret(placed) and placed and Movable(f) or nil
            if name and not SkipName(name) then
                local pos = ReadFrame(f)
                if pos then t[name] = pos end
            end
            f = EnumerateFrames(f)
        end
    end
    -- Minimap-Icons: alle benannten Elemente an der Minimap (Icons werden nicht über StartMoving gezogen, sondern
    -- hängen als Unterelemente an der Minimap) – für alle Addons gleich
    for _, parentName in ipairs({ "Minimap", "MinimapBackdrop" }) do
        local parent = _G[parentName]
        if type(parent) == "table" and parent.GetChildren then
            local ok, kids = pcall(function() return { parent:GetChildren() } end)
            if ok then
                for _, child in ipairs(kids) do
                    local okn, name = pcall(function()
                        if child.IsForbidden and child:IsForbidden() then return nil end
                        return child:GetName()
                    end)
                    -- nur ziehbare Icons (mit Zieh-Handler), keine durchnummerierten Markierungen
                    local okd, drag = pcall(function() return child.GetScript and child:GetScript("OnDragStart") end)
                    if okn and type(name) == "string" and not Secret(name) and t[name] == nil and not SkipName(name)
                        and not CS.IsPooledName(name) and okd and drag then
                        local pos = ReadFrame(child)
                        if pos then t[name] = pos; CS.minimapFrames[name] = true end
                        -- Icons ziehen sich selbst (OnDragStart + OnUpdate) statt über StartMoving: dort mithören
                        if not hookedIcons[child] and child.HookScript then
                            hookedIcons[child] = true
                            pcall(child.HookScript, child, "OnDragStart", function(self) CS.OnDragStart(self) end)
                        end
                    end
                end
            end
        end
    end
    -- dazu alle Fenster, die in dieser Sitzung per Maus gezogen wurden (auch solche, die WoW sich nicht merkt)
    for name in pairs(CS.draggedFrames) do
        local fr = _G[name]
        if t[name] == nil and type(fr) == "table" and not SkipName(name) then
            local pos = ReadFrame(fr)
            if pos then t[name] = pos end
        end
    end
    frameScan, frameScanAt = t, now
    return t
end

CS.ScanPlacedFrames = function() return ScanPlacedFrames() end

-- Jedes Fenster, das per Maus gezogen wird, läuft über StartMoving. CharSync hängt sich (ohne einzugreifen) an diese
-- WoW-Funktion und merkt sich beim ersten Anfassen die Position VOR dem Verschieben – für alle Addons gleich.
function CS.OnDragStart(f)
    local ok, name = pcall(function()
        if f.IsForbidden and f:IsForbidden() then return nil end
        return f:GetName()
    end)
    if not ok or type(name) ~= "string" or Secret(name) or SkipName(name) then return end
    if CS.draggedFrames[name] then return end
    CS.draggedFrames[name] = true
    local before = ReadFrame(f)
    CS.dragBefore[name] = before
    frameScan = nil
    if before and CS.Account and CS.Account.NoteFrameBefore then CS.Account.NoteFrameBefore(name, before) end
end

do
    if hooksecurefunc and CreateFrame then
        for _, kind in ipairs({ "Frame", "Button" }) do
            local ok, obj = pcall(CreateFrame, kind)
            local mt = ok and type(obj) == "table" and getmetatable(obj)
            local methods = type(mt) == "table" and mt.__index
            if type(methods) == "table" and type(methods.StartMoving) == "function" then
                pcall(hooksecurefunc, methods, "StartMoving", CS.OnDragStart)
            end
        end
    end
end
function CS.InvalidateFrames() frameScan = nil end

local function PosText(p)
    if not p then return L["Standardposition"] end
    local txt = ("%d, %d"):format(p.x or 0, p.y or 0)
    if p.w then txt = txt .. (" (%d × %d)"):format(p.w, p.h or 0) end
    return txt
end

local function SamePos(a, b)
    if not a or not b then return a == b end
    if a.point ~= b.point or a.rel ~= b.rel or a.relPoint ~= b.relPoint then return false end
    if math.abs((a.x or 0) - (b.x or 0)) > 1 or math.abs((a.y or 0) - (b.y or 0)) > 1 then return false end
    if (a.w or b.w) and (math.abs((a.w or 0) - (b.w or 0)) > 1 or math.abs((a.h or 0) - (b.h or 0)) > 1) then return false end
    return true
end

CS.RegisterModule("frames", {
    title = "Fensterpositionen",
    desc = "Wo verschiebbare Fenster stehen, deren Position WoW pro Char merkt (Fenster von WoW und von Addons). Positionen, die ein Addon selbst accountweit speichert, gelten ohnehin für alle Chars.",
    capture = function()
        local t = {}
        for name, pos in pairs(ScanPlacedFrames()) do t[name] = pos end
        return t
    end,
    diff = function(tpl)
        local items = {}
        local placed = ScanPlacedFrames()
        local names = {}
        for name in pairs(tpl) do names[#names + 1] = name end
        -- Vorlage-Char: auch Fenster, die er verschoben hat, die Vorlage aber noch nicht kennt
        local own = CS.Template("general")
        if own and own.source == CS.CharKey() then
            for name in pairs(placed) do if tpl[name] == nil then names[#names + 1] = name end end
        end
        table.sort(names)
        for _, name in ipairs(names) do
          if not CS.IsPooledName(name) and not SkipName(name) then -- alte Einträge von Markierungen (vor dem Filter gespeichert) ignorieren
            local want = tpl[name]
            local f = _G[name]
            -- Fenster abgesichert ansehen: gesperrte/geschützte Fenster nie direkt anfassen
            local exists = type(f) == "table" and pcall(function() return f.SetPoint end)
            local usable = exists and Movable(f) ~= nil or false
            local cur = placed[name] or (usable and ReadFrame(f)) or nil
            -- Fenster, das WoW/Addon selbst platziert (nicht vom Spieler verschoben), die Vorlage aber kennt:
            -- mit der tatsächlichen Position vergleichen – sonst bliebe es nach dem Zurücksetzen ewig „Standard“
            if not cur and want and exists then
                local okf, bad = pcall(function() return f:IsForbidden() or f:IsProtected() end)
                if okf and not Secret(bad) and not bad then cur = ReadFrame(f) end
            end
            -- in der Vorlage nicht verschoben und wieder an der Stelle vor dem ersten Ziehen: keine Abweichung
            -- (das Fenster bleibt in dieser Sitzung erfasst, weil es gezogen wurde)
            if not want and cur and CS.dragBefore[name] and SamePos(cur, CS.dragBefore[name]) then cur = nil end
            if not SamePos(cur, want) then
                local blocked
                if not exists then
                    blocked = L["Das Fenster wurde bei diesem Char noch nicht geöffnet. Öffne es einmal, dann lässt sich die Position übernehmen."]
                elseif not usable then
                    local ok, prot = pcall(function() return f:IsForbidden() or f:IsProtected() end)
                    if not ok or Secret(prot) or prot then blocked = L["Dieses Fenster kann ein Addon nicht verschieben (geschützt)."] end
                end
                local isIcon = CS.minimapFrames[name] or name:find("^LibDBIcon") ~= nil
                local noReset = (not want and isIcon and not CS.dragBefore[name]) or nil
                items[#items + 1] = {
                    noReset = noReset,
                    noResetText = noReset and L["Die Vorlage kennt dieses Icon noch nicht. Mit „In Vorlage“ übernimmst du seine Position."] or nil,
                    key = "frames:" .. name, label = CS.FrameLabel(name),
                    toTemplate = function() tpl[name] = cur end,
                    cur = PosText(cur), new = PosText(want), blocked = blocked,
                    desc = L["Setzt das Fenster an dieselbe Stelle wie beim Vorlage-Char."],
                    effect = L["verschiebt das Fenster an die Position des Vorlage-Chars"],
                    reload = (want == nil and not CS.dragBefore[name] and not noReset) or nil,
                    apply = function()
                        if not want then
                            -- in der Vorlage nicht verschoben: Standardposition. Kennt CharSync die Position vor dem
                            -- ersten Ziehen, sofort dorthin; sonst wirkt es nach dem Neuladen.
                            local b = CS.dragBefore[name]
                            if b then CS.PlaceFrame(f, name, b.point, b.rel, b.relPoint, b.x, b.y) end
                            if f.SetUserPlaced then pcall(f.SetUserPlaced, f, false) end
                            frameScan = nil
                            if CS.Account and CS.Account.Invalidate then CS.Account.Invalidate() end
                            return
                        end
                        CS.PlaceFrame(f, name, want.point, want.rel, want.relPoint, want.x, want.y)
                        if want.w and f.SetSize then f:SetSize(want.w, want.h) end
                        frameScan = nil
                        if CS.Account and CS.Account.Invalidate then CS.Account.Invalidate() end
                    end,
                }
            end
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

-- Index eines Charakter-Makros; bei gleichen Namen entscheidet zusätzlich der Text
local function FindCharMacro(name, body)
    local maxAcc = MacroLimits()
    local _, numChar = GetNumMacros()
    local first
    for i = maxAcc + 1, maxAcc + (numChar or 0) do
        local n, _, b = GetMacroInfo(i)
        if n == name then
            if body == nil or b == body then return i end
            first = first or i
        end
    end
    return first
end

-- Nur das Abweichende zweier Makros: die erste abweichende Zeile (und wie viele es sonst noch sind) oder die Symbole
local function SplitLines(body)
    local out = {}
    for line in tostring(body or ""):gmatch("[^\n]+") do out[#out + 1] = line end
    return out
end
local function MacroDiffTexts(a, b)
    local la, lb = SplitLines(a.body), SplitLines(b.body)
    local first, count = nil, 0
    for i = 1, math.max(#la, #lb) do
        if la[i] ~= lb[i] then
            count = count + 1
            first = first or i
        end
    end
    local ta, tb = {}, {}
    if first then
        local more = count > 1 and (" " .. L["(+%d)"]:format(count - 1)) or ""
        ta[#ta + 1] = L["Zeile %d: %s"]:format(first, la[first] or NONE) .. more
        tb[#tb + 1] = L["Zeile %d: %s"]:format(first, lb[first] or NONE) .. more
    end
    if tostring(a.icon) ~= tostring(b.icon) then
        ta[#ta + 1] = "|T" .. tostring(a.icon) .. ":14:14|t"
        tb[#tb + 1] = "|T" .. tostring(b.icon) .. ":14:14|t"
    end
    return table.concat(ta, ", "), table.concat(tb, ", ")
end

-- Makros ohne Namen (nur Leerzeichen) lesbar anzeigen
local function MacroLabel(name)
    if not name or tostring(name):match("^%s*$") then return L["(ohne Namen)"] end
    return name
end
CS.MacroLabel = MacroLabel

-- Zuordnung Vorlage <-> dieser Char in Stufen, damit Umbenennen, gleiche Namen und die alphabetische
-- Umsortierung von WoW nichts durcheinanderbringen:
--   1) Name, Text und Symbol gleich (unverändert)   2) Text gleich (nur umbenannt)
--   3) Name gleich (nur Inhalt geändert)             4) Symbol gleich (umbenannt und geändert)
-- Liefert die Paare {want, have}, die offenen Vorlagen-Makros (Index -> Makro) und die vergebenen eigenen (Index -> true).
local function MatchMacros(tpl, cur)
    local used, pairs_, open = {}, {}, {}
    for i, want in ipairs(tpl) do open[i] = want end
    local function stage(pred)
        for i = 1, #tpl do
            local want = open[i]
            if want then
                for j, m in ipairs(cur) do
                    if not used[j] and pred(m, want) then
                        used[j] = true
                        pairs_[#pairs_ + 1] = { want = want, have = m }
                        open[i] = nil
                        break
                    end
                end
            end
        end
    end
    stage(function(m, w) return m.name == w.name and m.body == w.body and tostring(m.icon) == tostring(w.icon) end)
    stage(function(m, w) return m.body == w.body end)
    stage(function(m, w) return m.name == w.name end)
    stage(function(m, w) return tostring(m.icon) == tostring(w.icon) end)
    return pairs_, open, used
end
CS.MatchMacros = MatchMacros

-- Makro (Name, Text, Symbol) in einer Liste von Paaren finden: erst genau, dann Name + Symbol, dann Name
local function FindPair(list, side, s)
    for _, pr in ipairs(list) do local m = pr[side]; if m.name == s.name and m.body == s.body then return pr end end
    for _, pr in ipairs(list) do local m = pr[side]; if m.name == s.name and tostring(m.icon) == tostring(s.icon) then return pr end end
    for _, pr in ipairs(list) do if pr[side].name == s.name then return pr end end
    return nil
end

CS.RegisterModule("macros", {
    scope = "class",
    title = "Makros",
    desc = "Charakterspezifische Makros – nur zwischen Chars derselben Klasse. Fehlende Makros werden angelegt, abweichende angepasst. Makros, die es beim Vorlage-Char nicht gibt, werden nur gelöscht, wenn du sie ausdrücklich anhakst.",
    capture = ReadCharMacros,
    isEmpty = function(t) return #t == 0 end,
    diff = function(tpl)
        local items, cur = {}, ReadCharMacros()
        local occurrence = {}
        local _, maxChar = MacroLimits()
        local free = maxChar - #cur
        -- eindeutiger Schlüssel auch bei gleichen Namen
        local function KeyOf(prefix, name)
            occurrence[prefix .. name] = (occurrence[prefix .. name] or 0) + 1
            local n = occurrence[prefix .. name]
            return prefix .. name .. (n > 1 and ("#" .. n) or "")
        end
        local pairs_, open, used = MatchMacros(tpl, cur)

        -- Reihenfolge wie in der Vorlage
        local order = {}
        for i, want in ipairs(tpl) do order[want] = i end
        table.sort(pairs_, function(x, y) return order[x.want] < order[y.want] end)

        for _, pr in ipairs(pairs_) do
            local want, have = pr.want, pr.have
            local renamed = have.name ~= want.name
            local changed = have.body ~= want.body or tostring(have.icon) ~= tostring(want.icon)
            if renamed or changed then
                local ca, cb = "", ""
                if changed then ca, cb = MacroDiffTexts(have, want) end
                local cur, new = ca, cb
                if renamed then
                    cur = L["heißt „%s“"]:format(MacroLabel(have.name)) .. (ca ~= "" and (", " .. ca) or "")
                    new = L["heißt „%s“"]:format(MacroLabel(want.name)) .. (cb ~= "" and (", " .. cb) or "")
                end
                items[#items + 1] = {
                    key = KeyOf("macros:", want.name), label = L["Makro „%s“"]:format(MacroLabel(want.name)),
                    toTemplate = function()
                        local neu = { name = have.name, icon = have.icon, body = have.body }
                        for i, m in ipairs(tpl) do if m == want then tpl[i] = neu end end
                        -- Aktionsleisten der Vorlage zeigen über Name/Symbol auf das Makro: mit umbenennen
                        local ct = CS.Template("class")
                        local bars = ct and ct.data and ct.data.actionbars
                        if type(bars) == "table" then
                            for slot, sl in pairs(bars) do
                                if type(sl) == "table" and sl.t == "macro" and not sl.global and sl.name == want.name
                                    and (sl.body == nil or sl.body == want.body or tostring(sl.icon) == tostring(want.icon)) then
                                    bars[slot] = { t = "macro", name = neu.name, icon = neu.icon, body = neu.body }
                                end
                            end
                        end
                    end,
                    cur = cur, new = new,
                    desc = changed and L["Ersetzt Text und Symbol dieses Makros durch die Fassung des Vorlage-Chars."]
                        or L["Benennt das Makro um. Text und Symbol bleiben wie beim Vorlage-Char."],
                    curMacro = have, tplMacro = want,
                    apply = function()
                        local idx = FindCharMacro(have.name, have.body)
                        if not idx then error(L["Makro nicht gefunden"]) end
                        EditMacro(idx, want.name, want.icon, want.body)
                    end,
                }
            end
        end
        -- fehlt bei diesem Char: anlegen
        for i, want in ipairs(tpl) do
            if open[i] then
                local blocked
                if free <= 0 then blocked = L["Kein Platz mehr für charakterspezifische Makros (höchstens %d)."]:format(maxChar) end
                free = free - 1
                items[#items + 1] = {
                    key = KeyOf("macros:", want.name), label = L["Makro „%s“"]:format(MacroLabel(want.name)),
                    toTemplate = function() for j, m in ipairs(tpl) do if m == want then table.remove(tpl, j) break end end end,
                    cur = L["nicht vorhanden"], new = L["wird angelegt"], blocked = blocked, tplText = L["vorhanden"],
                    desc = L["Legt das Makro mit Symbol und Text wie beim Vorlage-Char an. Auf die Aktionsleiste kommt es über den Bereich „Aktionsleisten“."],
                    tplMacro = want,
                    apply = function() CreateMacro(want.name, want.icon, want.body, true) end,
                }
            end
        end
        -- 3) gibt es nur bei diesem Char: löschen nur auf ausdrücklichen Haken
        for i, have in ipairs(cur) do
            if not used[i] then
                items[#items + 1] = {
                    key = KeyOf("macros:del:", have.name), label = L["Makro „%s“"]:format(MacroLabel(have.name)),
                    toTemplate = function() tpl[#tpl + 1] = { name = have.name, icon = have.icon, body = have.body } end,
                    cur = L["vorhanden"], new = L["wird gelöscht"], defaultOff = true, tplText = L["nicht vorhanden"],
                    desc = L["Dieses Makro gibt es beim Vorlage-Char nicht. Es wird nur gelöscht, wenn du den Haken setzt."],
                    curMacro = have,
                    apply = function()
                        local idx = FindCharMacro(have.name, have.body)
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

-- Welches Charakter-Makro liegt auf dem Platz? WoW nennt nur den Namen (GetActionText); bei mehreren gleichnamigen
-- Makros (z. B. alle ohne Namen) entscheidet der Zauber, den GetActionInfo auf diesem Client statt der Makronummer
-- liefert (GetMacroSpell), sonst das Symbol des Platzes.
local function MacroForSlot(slot, name, id)
    if not name then return nil end
    local maxAcc = MacroLimits()
    local _, numChar = GetNumMacros()
    local cands = {}
    for i = maxAcc + 1, maxAcc + (numChar or 0) do
        if GetMacroInfo(i) == name then cands[#cands + 1] = i end
    end
    if #cands <= 1 then return cands[1] end
    if type(id) == "number" and GetMacroSpell then
        for _, i in ipairs(cands) do
            local ok, spell = pcall(GetMacroSpell, i)
            if ok and spell == id then return i end
        end
    end
    local tex = GetActionTexture and GetActionTexture(slot)
    if tex then
        for _, i in ipairs(cands) do
            local _, icon = GetMacroInfo(i)
            if tostring(icon) == tostring(tex) then return i end
        end
    end
    return cands[1]
end

local function ReadSlot(slot)
    if not HasAction(slot) then return { t = "none" } end
    local kind, id, sub = GetActionInfo(slot)
    if kind == "spell" then return { t = "spell", id = id, name = SpellName(id) } end
    if kind == "macro" then
        -- Name über GetActionText: GetActionInfo liefert je nach Client statt der Makro-Nummer z. B. die Zauber-ID
        local name = GetActionText and GetActionText(slot)
        local maxAcc = MacroLimits()
        local byIndex = type(id) == "number" and id > 0 and id <= maxAcc + 18 and GetMacroInfo(id) or nil
        name = name or byIndex
        local global = (GetMacroIndexByName and GetMacroIndexByName(name or "") or 0)
        local idx = (byIndex and byIndex == name) and id or MacroForSlot(slot, name, id) or (global > 0 and global) or nil
        local _, icon, body
        if idx then _, icon, body = GetMacroInfo(idx) end
        return { t = "macro", name = name, global = global > 0 and global <= maxAcc, icon = icon, body = body }
    end
    if kind == "item" then return { t = "item", id = id } end
    if kind == "equipmentset" then return { t = "equipmentset", name = id } end
    if kind == "flyout" then
        local name = GetFlyoutInfo and GetFlyoutInfo(id)
        return { t = "flyout", id = id, name = name }
    end
    return { t = tostring(kind), id = id, sub = sub }
end

-- Vergleichsschlüssel: Fähigkeiten nach Name (ein anderer Rang zählt als gleich)
local function SlotKey(s)
    if s.t == "spell" then return "spell:" .. tostring(s.name or s.id) end
    -- Name + Symbol: hält gleichnamige Makros (z. B. alle ohne Namen) auseinander, ohne dass eine reine Textänderung
    -- am Makro hier ein zweites Mal auftaucht (die steht schon im Bereich „Makros“)
    if s.t == "macro" then return "macro:" .. tostring(s.name) .. ":" .. tostring(s.icon or "") end
    if s.t == "item" then return "item:" .. tostring(s.id) end
    if s.t == "equipmentset" then return "set:" .. tostring(s.name) end
    if s.t == "none" then return "none" end
    return s.t .. ":" .. tostring(s.id)
end

local function SlotText(s)
    if s.t == "none" then return L["leer"] end
    if s.t == "spell" then return s.name or ("#" .. tostring(s.id)) end
    if s.t == "macro" then return L["Makro: %s"]:format(MacroLabel(s.name)) end
    if s.t == "item" then return ItemName(s.id) end
    if s.t == "equipmentset" then return L["Ausrüstungsset: %s"]:format(tostring(s.name)) end
    if s.t == "flyout" then return L["Ausklappleiste: %s"]:format(tostring(s.name or s.id)) end
    return s.t
end

-- Zauber-/Gegenstand-Funktionen: je nach Client global (alt) oder in C_Spell/C_SpellBook/C_Item (neu, z. B. Forever)
local function SpellKnownByID(id)
    if not id then return false end
    if IsSpellKnown and IsSpellKnown(id) then return true end
    if C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(id) then return true end
    if IsPlayerSpell and IsPlayerSpell(id) then return true end
    return false
end

-- per Name: liefert der Client Infos nur für bekannte Zauber, ist das zugleich die Prüfung
local function SpellInfoByName(name)
    if not name then return nil end
    if GetSpellInfo then return (GetSpellInfo(name)) end
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, name)
        if ok and type(info) == "table" then return info.name, info.spellID end
    end
    return nil
end

local function PickupSpellAny(x)
    if PickupSpell then return PickupSpell(x) end
    if C_Spell and C_Spell.PickupSpell then return C_Spell.PickupSpell(x) end
    error("PickupSpell")
end

local function PickupItemAny(id)
    if PickupItem then return PickupItem(id) end
    if C_Item and C_Item.PickupItem then return C_Item.PickupItem(id) end
    error("PickupItem")
end

local function KnowsSpell(s)
    if SpellKnownByID(s.id) then return true end
    if s.name and SpellInfoByName(s.name) then return true end
    return false
end

local function MacroExists(s)
    if s.body and FindCharMacro(s.name, s.body) then return true end
    if FindCharMacro(s.name) then return true end
    return (GetMacroIndexByName and GetMacroIndexByName(s.name) or 0) > 0
end

local function PickupSlotContent(s)
    if s.t == "spell" then
        if SpellKnownByID(s.id) then PickupSpellAny(s.id) else
            -- anderer Rang: über den Namen den bekannten Zauber nehmen
            local _, known = SpellInfoByName(s.name)
            PickupSpellAny(known or s.name or s.id)
        end
    elseif s.t == "macro" then
        local idx = (not s.global and FindCharMacro(s.name, s.body)) or GetMacroIndexByName(s.name)
        if idx and idx > 0 then PickupMacro(idx) end
    elseif s.t == "item" then
        PickupItemAny(s.id)
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
    -- leer = WoW hat (z. B. beim Ausloggen) keine Aktionen geliefert
    isEmpty = function(t)
        for _, s in pairs(t) do if type(s) == "table" and s.t ~= "none" then return false end end
        return true
    end,
    diff = function(tpl, opts)
        local items = {}
        local filled = opts and opts.undo
        for _, s in pairs(tpl) do if type(s) == "table" and s.t ~= "none" then filled = true break end end
        if not filled then
            return { {
                key = "actionbars:empty", label = L["Vorlage ohne Aktionen"], cur = "", new = "",
                desc = L["Die Vorlage enthält keine Aktionen. Speichere sie beim Vorlage-Char neu."],
                blocked = L["Die Vorlage enthält keine Aktionen. Speichere sie beim Vorlage-Char neu."],
                apply = function() end,
            } }
        end
        local macroTpl = CS.Template("class")
        local macrosComing = {}
        if macroTpl and macroTpl.data and type(macroTpl.data.macros) == "table" and CS.db.modules.macros then
            for _, m in ipairs(macroTpl.data.macros) do macrosComing[m.name] = true end
        end
        -- Umbenannte Makros: die Leiste vergleicht mit dem Makro dieses Chars, das zum Vorlagen-Makro gehört
        -- (gleiche Zuordnung wie im Bereich „Makros“). So erscheint Umbenennen + Verschieben als Verschieben
        -- desselben Makros, und Übernehmen findet es unter altem wie neuem Namen.
        local mpairs = {}
        if not (opts and opts.undo) and macroTpl and macroTpl.data and type(macroTpl.data.macros) == "table" then
            mpairs = MatchMacros(macroTpl.data.macros, ReadCharMacros())
        end
        local function Mapped(s)
            if type(s) ~= "table" or s.t ~= "macro" or s.global then return s end
            local pr = FindPair(mpairs, "want", s)
            if not pr then return s end
            return { t = "macro", name = pr.have.name, icon = pr.have.icon, body = pr.have.body }
        end
        local function Unmapped(s)
            if type(s) ~= "table" or s.t ~= "macro" or s.global then return s end
            local pr = FindPair(mpairs, "have", s)
            if not pr then return s end
            return { t = "macro", name = pr.want.name, icon = pr.want.icon, body = pr.want.body }
        end
        for slot = 1, NUM_SLOTS do
            local orig = tpl[slot]
            if orig then
                local cur = ReadSlot(slot)
                local want = Mapped(orig)
                if SlotKey(cur) ~= SlotKey(want) then
                    local blocked
                    if want.t == "spell" and not KnowsSpell(want) then
                        blocked = L["Diese Fähigkeit kennt dieser Char (noch) nicht."]
                    elseif want.t == "macro" and not MacroExists(want) and not MacroExists(orig) and not macrosComing[orig.name] then
                        blocked = L["Das Makro gibt es bei diesem Char nicht."]
                    elseif want.t ~= "none" and want.t ~= "spell" and want.t ~= "macro" and want.t ~= "item" and want.t ~= "equipmentset" then
                        blocked = L["Diese Art von Aktion kann nicht übertragen werden."]
                    end
                    items[#items + 1] = {
                        curMacro = cur.t == "macro" and cur or nil, tplMacro = want.t == "macro" and want or nil,
                        key = "actionbars:" .. slot, label = SlotLabel(slot),
                        toTemplate = function() tpl[slot] = Unmapped(cur) end,
                        cur = SlotText(cur), new = SlotText(want), blocked = blocked,
                        defaultOff = want.t == "none" or nil,
                        effect = (want.t == "none") and L["leert diesen Platz („%s“ fällt weg)"]:format(SlotText(cur))
                            or (cur.t == "none" and L["legt „%s“ auf diesen Platz"]:format(SlotText(want)))
                            or L["ersetzt „%s“ durch „%s“"]:format(SlotText(cur), SlotText(want)),
                        desc = (want.t == "none") and L["Leert diesen Platz, weil er beim Vorlage-Char frei ist."]
                            or L["Legt „%s“ auf diesen Platz der Aktionsleiste, wie beim Vorlage-Char."]:format(SlotText(want)),
                        apply = function()
                            ClearCursor()
                            if want.t == "none" then
                                PickupAction(slot)
                                ClearCursor()
                                return
                            end
                            -- erst wie in der Vorlage (Makro evtl. gerade umbenannt), sonst das zugeordnete Makro
                            PickupSlotContent(orig)
                            if not GetCursorInfo() and want ~= orig then ClearCursor(); PickupSlotContent(want) end
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
