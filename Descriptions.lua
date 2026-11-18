-- CharSync: Klartext zu den Einstellungen – Name, was die Änderung bewirkt und wie der Wert lesbar angezeigt wird.
local _, CS = ...
local L = CS.L

local function OnOff(v)
    if v == nil then return L["Standard"] end
    v = tostring(v)
    if v == "1" or v == "true" then return L["An"] end
    if v == "0" or v == "false" then return L["Aus"] end
    return v
end
CS.OnOff = OnOff

local function Number(fmt)
    return function(v)
        local n = tonumber(v)
        if not n then return tostring(v) end
        return fmt:format(n)
    end
end

-- Zusätzliche Aktionsleisten: Bitmaske
local BAR_BITS = {
    { 1, "Leiste 2 (unten links)" }, { 2, "Leiste 3 (unten rechts)" }, { 4, "Leiste 4 (rechts)" },
    { 8, "Leiste 5 (rechts 2)" }, { 16, "Leiste 6" }, { 32, "Leiste 7" }, { 64, "Leiste 8" },
}
local function Bars(v)
    local n = tonumber(v) or 0
    local out = {}
    for _, b in ipairs(BAR_BITS) do
        if math.floor(n / b[1]) % 2 == 1 then out[#out + 1] = L[b[2]] end
    end
    if #out == 0 then return L["keine"] end
    return table.concat(out, ", ")
end

-- Interface-Optionen, die WoW pro Charakter speichert
CS.CVAR_INFO = {
    enableMultiActionBars = { name = "Zusätzliche Aktionsleisten", fmt = Bars,
        desc = "Blendet die zusätzlichen Aktionsleisten ein oder aus (Optionen > Aktionsleisten). Die Belegung der Leisten bleibt, wie sie ist – sie liegt auf dem Server." },
    nameplateShowSelf = { name = "Persönliche Ressourcenanzeige", fmt = OnOff,
        desc = "Zeigt unter deinem Charakter eine eigene Leiste mit Gesundheit und Mana/Energie (eigene Namensplakette)." },
    showQuestLevel = { name = "Questlevel anzeigen", fmt = OnOff,
        desc = "Zeigt im Questlog und im Questtracker das Level jeder Quest vor dem Namen an." },
    raidFramesDisplayClassColor = { name = "Raidframes: Klassenfarben", fmt = OnOff,
        desc = "Färbt die Gesundheitsleisten in Gruppen- und Schlachtzugsfenstern in der Klassenfarbe statt grün." },
    raidFramesDisplayPowerBars = { name = "Raidframes: Kraftleisten", fmt = OnOff,
        desc = "Zeigt in Gruppen- und Schlachtzugsfenstern unter der Gesundheit eine Leiste für Mana, Wut oder Energie." },
    raidFramesDisplayOnlyDispellableDebuffs = { name = "Raidframes: nur entfernbare Schwächungen", fmt = OnOff,
        desc = "Zeigt in den Raidframes nur Schwächungen, die du selbst entfernen kannst." },
    raidFramesHealthText = { name = "Raidframes: Gesundheitstext",
        desc = "Welcher Text in den Raidframes auf der Gesundheitsleiste steht (keiner, Gesundheit, verlorene Gesundheit, Prozent)." },
    raidOptionDisplayPets = { name = "Raidframes: Begleiter anzeigen", fmt = OnOff,
        desc = "Zeigt die Begleiter der Gruppenmitglieder als eigene Raidframes." },
    raidOptionDisplayMainTankAndAssist = { name = "Raidframes: Haupttank und -assistent", fmt = OnOff,
        desc = "Zeigt Haupttank und Hauptassistent als eigene Raidframes." },
    useCompactPartyFrames = { name = "Gruppenfenster im Raid-Stil", fmt = OnOff,
        desc = "Nutzt für die Gruppe dieselben kompakten Fenster wie im Schlachtzug." },
    mapFade = { name = "Karte beim Laufen ausblenden", fmt = OnOff,
        desc = "Macht die geöffnete Weltkarte durchsichtig, während du dich bewegst." },
    miniWorldMap = { name = "Kleine Weltkarte", fmt = OnOff,
        desc = "Öffnet die Weltkarte als kleines Fenster statt als großes Vollbild." },
    minimapTrackedInfov4 = { name = "Minimap-Verfolgung",
        fmt = function(v) return L["Auswahl %s"]:format(tostring(v)) end,
        desc = "Was die Minimap anzeigt, z. B. Briefkasten, Lehrer, Händler, Gasthäuser (Lupe an der Minimap). Kräuter- und Erzsuche hängen vom Beruf ab und bleiben dabei unverändert." },
    minimapZoom = { name = "Minimap-Zoom (draußen)", fmt = Number("%d"),
        desc = "Zoomstufe der Minimap im Freien (0 = ganz herausgezoomt, 5 = ganz hineingezoomt)." },
    minimapInsideZoom = { name = "Minimap-Zoom (drinnen)", fmt = Number("%d"),
        desc = "Zoomstufe der Minimap in Gebäuden und Höhlen." },
    cooldownViewerEnabled = { name = "Abklingzeiten-Manager", fmt = OnOff,
        desc = "Blendet die Blizzard-Leiste ein, die die Abklingzeiten deiner wichtigsten Fähigkeiten anzeigt." },
    closedInfoFrames = { name = "Geschlossene Tipps",
        fmt = function() return L["Liste"] end,
        desc = "Merkt sich, welche Hilfe-Tipps und Tutorial-Fenster du schon weggeklickt hast. Übernehmen heißt: diese Tipps tauchen auch bei diesem Char nicht mehr auf." },
}

-- Name einer CVar: eigene Beschreibung, sonst der Name aus den Blizzard-Optionen, sonst die CVar selbst
function CS.CVarLabel(name)
    local info = CS.CVAR_INFO[name]
    if info then return L[info.name] end
    if Settings and Settings.GetSetting then
        local ok, setting = pcall(Settings.GetSetting, name)
        if ok and type(setting) == "table" and setting.GetName then
            local ok2, label = pcall(setting.GetName, setting)
            if ok2 and type(label) == "string" and label ~= "" then return label end
        end
    end
    return name
end

function CS.CVarDesc(name)
    local info = CS.CVAR_INFO[name]
    if info then return L[info.desc] end
    return L["WoW-Einstellung, die pro Charakter gespeichert wird (CVar „%s“). Zu ihr ist keine Beschreibung hinterlegt."]:format(name)
end

-- Nur die Teile, die sich unterscheiden (bei Listen wie den Aktionsleisten interessiert nur, was anders ist)
function CS.CVarDiffValues(name, cur, want)
    if name == "enableMultiActionBars" then
        local a, b = tonumber(cur) or 0, tonumber(want) or 0
        local here, there = {}, {}
        for _, bit in ipairs(BAR_BITS) do
            local had, will = math.floor(a / bit[1]) % 2 == 1, math.floor(b / bit[1]) % 2 == 1
            if had ~= will then
                here[#here + 1] = ("%s: %s"):format(L[bit[2]], had and L["An"] or L["Aus"])
                there[#there + 1] = ("%s: %s"):format(L[bit[2]], will and L["An"] or L["Aus"])
            end
        end
        if #here > 0 then return table.concat(here, ", "), table.concat(there, ", ") end
    end
    return CS.CVarValue(name, cur), CS.CVarValue(name, want)
end

-- Was „Übernehmen“ bei dieser Option konkret tut
function CS.CVarEffect(name, cur, want)
    if name == "enableMultiActionBars" then
        local a, b = tonumber(cur) or 0, tonumber(want) or 0
        local on, off = {}, {}
        for _, bit in ipairs(BAR_BITS) do
            local had, will = math.floor(a / bit[1]) % 2 == 1, math.floor(b / bit[1]) % 2 == 1
            if will and not had then on[#on + 1] = L[bit[2]] end
            if had and not will then off[#off + 1] = L[bit[2]] end
        end
        local parts = {}
        if #on > 0 then parts[#parts + 1] = L["blendet ein: %s"]:format(table.concat(on, ", ")) end
        if #off > 0 then parts[#parts + 1] = L["blendet aus: %s"]:format(table.concat(off, ", ")) end
        return table.concat(parts, "; ")
    end
    local info = CS.CVAR_INFO[name]
    if info and info.fmt == OnOff and (tostring(want) == "1" or tostring(want) == "0") then
        return tostring(want) == "1" and L["schaltet ein"] or L["schaltet aus"]
    end
    return L["stellt „%s“ auf „%s“ um"]:format(CS.CVarValue(name, cur), CS.CVarValue(name, want))
end

function CS.CVarValue(name, v)
    local info = CS.CVAR_INFO[name]
    if info and info.fmt then return info.fmt(v) end
    return tostring(v)
end

