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

function CS.CVarValue(name, v)
    local info = CS.CVAR_INFO[name]
    if info and info.fmt then return info.fmt(v) end
    return tostring(v)
end

-- MyCharForever-Einstellungen
local MAP_LAYERS = {
    Journey = "Reiseweg", Deaths = "Tode", LevelUps = "Level-Aufstiege", Journal = "Journal-Einträge",
    Screenshots = "Screenshot-Orte", Hearthstone = "Ruhestein-Ort", CurrentSession = "aktuelle Sitzung",
    Drops = "Beute", Iconic = "besondere Momente", Achievements = "Erfolge", Pvp = "PvP",
}
CS.MCF_INFO = {
    minimapAngle = { name = "Position des Minimap-Icons", fmt = Number("%d°"),
        desc = "Wo das MyCharForever-Icon am Rand der Minimap sitzt (Winkel im Uhrzeigersinn ab rechts)." },
    showMinimapButton = { name = "Minimap-Icon anzeigen", fmt = OnOff,
        desc = "Ob MyCharForever ein Icon an der Minimap zeigt." },
    screenshotEnabled = { name = "Automatische Screenshots", fmt = OnOff,
        desc = "MyCharForever macht bei besonderen Ereignissen automatisch Screenshots." },
    screenshotLevelUp = { name = "Screenshot bei Level-Aufstieg", fmt = OnOff, desc = "Screenshot, wenn der Char ein Level aufsteigt." },
    levelScreenshots = { name = "Level-Screenshots", fmt = OnOff, desc = "Screenshots zu Level-Aufstiegen im Verlauf speichern." },
    screenshotDeath = { name = "Screenshot beim Tod", fmt = OnOff, desc = "Screenshot, wenn der Char stirbt." },
    screenshotDeathV106 = { name = "Screenshot beim Tod (neu)", fmt = OnOff, desc = "Neuere Fassung der Option „Screenshot beim Tod“." },
    screenshotDungeon = { name = "Screenshot in Dungeons", fmt = OnOff, desc = "Screenshots bei Bosskills in Dungeons." },
    screenshotDungeonV102 = { name = "Screenshot in Dungeons (neu)", fmt = OnOff, desc = "Neuere Fassung der Option „Screenshot in Dungeons“." },
    screenshotDungeonMode = { name = "Dungeon-Screenshots: wann", desc = "Bei welchen Dungeon-Ereignissen ein Screenshot entsteht (z. B. „every“ = bei jedem Boss)." },
    screenshotEquip = { name = "Screenshot bei neuer Ausrüstung", fmt = OnOff, desc = "Screenshot, wenn der Char ein besseres Ausrüstungsteil anlegt." },
    screenshotMinQuality = { name = "Ausrüstungs-Screenshots ab Qualität", desc = "Ab welcher Qualität neue Ausrüstung einen Screenshot auslöst (2 = selten/grün, 3 = rar/blau)." },
    screenshotMinQualityV30 = { name = "Mindestqualität (neu)", fmt = OnOff, desc = "Interne Umstellung der Mindestqualität." },
    screenshotLogin = { name = "Screenshot beim Einloggen", fmt = OnOff, desc = "Screenshot direkt nach dem Login." },
    screenshotPeriodic = { name = "Regelmäßige Screenshots", fmt = OnOff, desc = "Macht in festen Abständen Screenshots." },
    screenshotInterval = { name = "Abstand regelmäßiger Screenshots", fmt = Number(L["%d Min."]), desc = "Wie oft regelmäßige Screenshots entstehen." },
    screenshotCooldown = { name = "Mindestabstand zwischen Screenshots", fmt = Number(L["%d s"]), desc = "So viele Sekunden muss mindestens zwischen zwei automatischen Screenshots liegen." },
    screenshotNoUiInInstance = { name = "Screenshots in Instanzen ohne Oberfläche", fmt = OnOff, desc = "Blendet in Instanzen für den Screenshot die Oberfläche aus." },
    screenshotLogAll = { name = "Alle Screenshots protokollieren", fmt = OnOff, desc = "Trägt jeden Screenshot in den Verlauf ein." },
    trackJourney = { name = "Reiseweg aufzeichnen", fmt = OnOff, desc = "Zeichnet auf, wo der Char unterwegs war." },
    mapJourneyMinLevel = { name = "Reiseweg auf der Karte ab Level", fmt = Number("%d"), desc = "Ab welchem Level der Reiseweg auf der Karte gezeigt wird." },
    mapJourneyMaxLevel = { name = "Reiseweg auf der Karte bis Level", fmt = Number("%d"), desc = "Bis zu welchem Level der Reiseweg auf der Karte gezeigt wird." },
    mapMenuCollapsed = { name = "Kartenmenü eingeklappt", fmt = OnOff, desc = "Ob das MyCharForever-Menü auf der Weltkarte eingeklappt ist." },
}
for key, label in pairs(MAP_LAYERS) do
    CS.MCF_INFO["showMap" .. key] = { name = "Karte: " .. label, fmt = OnOff, mapLayer = label }
end

function CS.MCFLabel(key)
    local info = CS.MCF_INFO[key]
    if info then return info.mapLayer and L["Karte: %s"]:format(L[info.mapLayer]) or L[info.name] end
    return key
end

function CS.MCFDesc(key)
    local info = CS.MCF_INFO[key]
    if info and info.mapLayer then
        return L["Ob MyCharForever „%s“ als Markierungen auf der Weltkarte einzeichnet."]:format(L[info.mapLayer])
    end
    if info then return L[info.desc] end
    return L["Einstellung „%s“ von MyCharForever."]:format(key)
end

function CS.MCFValue(key, v)
    if v == nil then return L["Standard"] end
    local info = CS.MCF_INFO[key]
    if info and info.fmt then return info.fmt(v) end
    if type(v) == "boolean" then return OnOff(v) end
    return tostring(v)
end
