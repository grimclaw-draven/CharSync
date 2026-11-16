-- CharSync: Fenster (/charsync) mit Vorher-Nachher-Vergleich je Einstellung und Eintrag unter Optionen > AddOns.
local ADDON, CS = ...
local L = CS.L
local UI = {}
CS.UI = UI

local WIDTH, HEIGHT, LEFT_W = 900, 620, 270
local ROW_H, HEAD_H = 50, 24
local window, content
local rows = {}
local reviewMode = false

local function Tip(widget, title, lines)
    widget:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title, 1, 1, 1, 1, true)
        local list = type(lines) == "function" and lines() or lines
        if type(list) == "string" then list = { list } end
        for _, l in ipairs(list or {}) do GameTooltip:AddLine(l, nil, nil, nil, true) end
        GameTooltip:Show()
    end)
    widget:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function MakeCheck(parent, label, tip)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    local fs = cb.Text or cb.text
    if not fs then
        fs = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        fs:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    end
    fs:SetFontObject("GameFontHighlight")
    fs:SetText(label)
    cb.label = fs
    if tip then Tip(cb, label, tip) end
    return cb
end

local function MakeButton(parent, text, w, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 24)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

-- Tooltip einer Abweichung: was sie bewirkt, vorher/nachher, Einzelheiten
local function ItemTooltip(it)
    local lines = {}
    if it.desc then lines[#lines + 1] = it.desc end
    lines[#lines + 1] = " "
    lines[#lines + 1] = L["|cffffd100Vorher:|r %s"]:format(tostring(it.cur or ""))
    lines[#lines + 1] = L["|cffffd100Nachher:|r %s"]:format(tostring(it.new or ""))
    if it.details and #it.details > 0 then
        lines[#lines + 1] = " "
        for _, d in ipairs(it.details) do lines[#lines + 1] = d end
    end
    if it.blocked then
        lines[#lines + 1] = " "
        lines[#lines + 1] = "|cffff6060" .. L["Nicht möglich: %s"]:format(it.blocked) .. "|r"
    elseif it.defaultOff then
        lines[#lines + 1] = " "
        lines[#lines + 1] = "|cffffd100" .. L["Wird nur übernommen, wenn du den Haken ausdrücklich setzt."] .. "|r"
    end
    if it.reload then lines[#lines + 1] = "|cff999999" .. L["Wird nach einem Neuladen der Oberfläche vollständig aktiv."] .. "|r" end
    lines[#lines + 1] = " "
    lines[#lines + 1] = "|cff999999" .. L["Haken entfernen = diese Einstellung nie synchronisieren (gilt für alle Chars)."] .. "|r"
    return lines
end

local function GetRow(i)
    if rows[i] then return rows[i] end
    local r = CreateFrame("Frame", nil, content)
    r:EnableMouse(true)
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.bg:SetColorTexture(1, 1, 1, 0.04)
    r.check = CreateFrame("CheckButton", nil, r, "UICheckButtonTemplate")
    r.check:SetSize(22, 22)
    r.check:SetPoint("TOPLEFT", 2, -4)
    local t = r.check.Text or r.check.text
    if t then t:SetText("") end
    r.label = r:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    r.label:SetPoint("TOPLEFT", 28, -5)
    r.label:SetPoint("RIGHT", r, "RIGHT", -24, 0)
    r.label:SetJustifyH("LEFT")
    r.label:SetWordWrap(false)
    r.value = r:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    r.value:SetPoint("TOPLEFT", r.label, "BOTTOMLEFT", 0, -3)
    r.value:SetPoint("RIGHT", r, "RIGHT", -24, 0)
    r.value:SetJustifyH("LEFT")
    r.value:SetWordWrap(false)
    r.desc = r:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    r.desc:SetPoint("TOPLEFT", r.value, "BOTTOMLEFT", 0, -3)
    r.desc:SetPoint("RIGHT", r, "RIGHT", -24, 0)
    r.desc:SetJustifyH("LEFT")
    r.desc:SetWordWrap(false)
    r.info = r:CreateTexture(nil, "ARTWORK")
    r.info:SetSize(16, 16)
    r.info:SetPoint("TOPRIGHT", -4, -6)
    r.info:SetTexture("Interface\\FriendsFrame\\InformationIcon")
    r.header = r:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    r.header:SetPoint("BOTTOMLEFT", 4, 4)
    r.header:SetPoint("RIGHT", r, "RIGHT", -4, 0)
    r.header:SetJustifyH("LEFT")
    r.check:SetScript("OnClick", function(self)
        if r.item then
            CS.SetChecked(r.item, self:GetChecked())
            UI.Refresh()
        end
    end)
    local function enter(self)
        if not r.item then return end
        GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
        GameTooltip:SetText(r.item.label, 1, 1, 1, 1, true)
        for _, l in ipairs(ItemTooltip(r.item)) do GameTooltip:AddLine(l, nil, nil, nil, true) end
        GameTooltip:Show()
    end
    r:SetScript("OnEnter", enter)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r.check:SetScript("OnEnter", enter)
    r.check:SetScript("OnLeave", function() GameTooltip:Hide() end)
    rows[i] = r
    return r
end

local function TemplateLine(scope)
    local tpl = CS.Template(scope)
    local _, classLocal = CS.PlayerClass()
    local title = scope == "class" and L["Vorlage für %s"]:format(classLocal) or L["Allgemeine Vorlage"]
    if not tpl then return ("|cffffd100%s:|r |cff999999%s|r"):format(title, L["noch keine"]) end
    local me = (tpl.source == CS.CharKey()) and (" |cff00ff00" .. L["(dieser Char)"] .. "|r") or ""
    return ("|cffffd100%s:|r |cffffffff%s|r%s – %s"):format(title, tpl.source or "?", me, date(L["%d.%m.%Y um %H:%M"], tpl.time or 0))
end

function UI.Build()
    if window then return end
    window = CreateFrame("Frame", "CharSyncFrame", UIParent, "BasicFrameTemplateWithInset")
    window:SetSize(WIDTH, HEIGHT)
    window:SetPoint("CENTER")
    window:SetFrameStrata("HIGH")
    window:SetClampedToScreen(true)
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    window:Hide()
    tinsert(UISpecialFrames, "CharSyncFrame")

    local title = window.TitleText
    if not title then
        title = window:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        title:SetPoint("TOP", 0, -5)
    end
    title:SetText(L["CharSync – Einstellungen auf alle Chars übertragen"])

    -- Hinweis bei neuer Vorlage
    window.banner = window:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    window.banner:SetPoint("TOPLEFT", 16, -32)
    window.banner:SetPoint("RIGHT", window, "RIGHT", -16, 0)
    window.banner:SetJustifyH("LEFT")

    window.info1 = window:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    window.info1:SetPoint("TOPLEFT", 16, -56)
    window.info1:SetPoint("RIGHT", window, "RIGHT", -16, 0)
    window.info1:SetJustifyH("LEFT")
    window.info2 = window:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    window.info2:SetPoint("TOPLEFT", window.info1, "BOTTOMLEFT", 0, -4)
    window.info2:SetPoint("RIGHT", window, "RIGHT", -16, 0)
    window.info2:SetJustifyH("LEFT")

    -- linke Spalte: Vorlagen speichern, Optionen, Bereiche
    local y = -96
    window.save = MakeButton(window, L["Als allgemeine Vorlage speichern"], LEFT_W - 20, function()
        CS.SaveTemplate("general")
        UI.Refresh()
    end)
    window.save:SetPoint("TOPLEFT", 14, y)
    Tip(window.save, L["Allgemeine Vorlage"], L["Speichert Interface-Optionen, Chat, Edit-Mode, Tasten, Addon-Auswahl und Addon-Einstellungen dieses Chars als Vorlage für alle Chars."])
    y = y - 28
    window.saveClass = MakeButton(window, L["Als Klassen-Vorlage speichern"], LEFT_W - 20, function()
        CS.SaveTemplate("class")
        UI.Refresh()
    end)
    window.saveClass:SetPoint("TOPLEFT", 14, y)
    Tip(window.saveClass, L["Klassen-Vorlage"], function()
        local _, classLocal = CS.PlayerClass()
        return L["Speichert Makros und Aktionsleisten dieses Chars als Vorlage für alle Chars der Klasse %s."]:format(classLocal)
    end)
    y = y - 32

    window.master = MakeCheck(window, L["Allgemeiner Vorlage-Char"],
        L["Dieser Char aktualisiert die allgemeine Vorlage bei jedem Ausloggen automatisch."])
    window.master:SetPoint("TOPLEFT", 12, y)
    window.master:SetScript("OnClick", function(self) CS.SetMaster("general", self:GetChecked()); UI.Refresh() end)
    y = y - 24
    window.classMaster = MakeCheck(window, L["Vorlage-Char seiner Klasse"],
        L["Dieser Char aktualisiert Makros und Aktionsleisten seiner Klasse bei jedem Ausloggen automatisch."])
    window.classMaster:SetPoint("TOPLEFT", 12, y)
    window.classMaster:SetScript("OnClick", function(self) CS.SetMaster("class", self:GetChecked()); UI.Refresh() end)
    y = y - 24
    window.auto = MakeCheck(window, L["Ohne Nachfrage übernehmen"],
        L["Neue Vorlagen werden beim Einloggen sofort übernommen, ohne dass sich dieses Fenster zum Prüfen öffnet."])
    window.auto:SetPoint("TOPLEFT", 12, y)
    window.auto:SetScript("OnClick", function(self) CS.db.autoApply = self:GetChecked() and true or false end)
    y = y - 34

    local h1 = window:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    h1:SetPoint("TOPLEFT", 16, y)
    h1:SetText(L["Bereiche"])
    y = y - 22
    window.modChecks = {}
    for _, m in ipairs(CS.MODULE_ORDER) do
        local def = CS.MODULES[m]
        local label = L[def.title] .. (def.scope == "class" and (" |cff999999" .. L["(gleiche Klasse)"] .. "|r") or "")
        local cb = MakeCheck(window, label, L[def.desc])
        cb:SetPoint("TOPLEFT", 12, y)
        cb:SetScript("OnClick", function(self)
            CS.db.modules[m] = self:GetChecked() and true or false
            UI.Refresh()
        end)
        window.modChecks[m] = cb
        y = y - 24
    end
    local note = window:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", 16, y - 6)
    note:SetWidth(LEFT_W - 24)
    note:SetJustifyH("LEFT")
    note:SetText(L["Grafik, Sound, die meisten Interface-Optionen und fast alle Addon-Einstellungen gelten ohnehin für alle Chars."])

    -- rechte Spalte: Vergleich
    local x = LEFT_W + 6
    local h2 = window:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    h2:SetPoint("TOPLEFT", x, -96)
    h2:SetText(L["Vergleich: dieser Char → Vorlage"])
    window.count = window:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    window.count:SetPoint("TOPRIGHT", -36, -100)

    local scroll = CreateFrame("ScrollFrame", "CharSyncScroll", window, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", x, -118)
    scroll:SetPoint("BOTTOMRIGHT", -32, 44)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(WIDTH - x - 40, 1)
    scroll:SetScrollChild(content)
    window.scroll = scroll

    window.empty = window:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    window.empty:SetPoint("TOPLEFT", scroll, "TOPLEFT", 6, -10)
    window.empty:SetPoint("RIGHT", scroll, "RIGHT", -6, 0)
    window.empty:SetJustifyH("LEFT")

    window.all = MakeButton(window, L["Alle anhaken"], 110, function()
        for _, it in ipairs(CS.ComputeDiff()) do if not it.defaultOff then CS.SetChecked(it, true) end end
        UI.Refresh()
    end)
    window.all:SetPoint("BOTTOMLEFT", x, 12)
    window.none = MakeButton(window, L["Keine"], 80, function()
        for _, it in ipairs(CS.ComputeDiff()) do CS.SetChecked(it, false) end
        UI.Refresh()
    end)
    window.none:SetPoint("LEFT", window.all, "RIGHT", 6, 0)

    window.apply = MakeButton(window, L["Angehakte übernehmen"], 190, function()
        reviewMode = false
        CS.ApplyNow()
    end)
    window.apply:SetPoint("BOTTOMRIGHT", -28, 12)
    window.later = MakeButton(window, L["Später"], 90, function()
        reviewMode = false
        window:Hide()
    end)
    window.later:SetPoint("RIGHT", window.apply, "LEFT", -6, 0)
    Tip(window.later, L["Später"], L["Schließt das Fenster. Beim nächsten Login wirst du wieder gefragt."])
    window.skip = MakeButton(window, L["Diesmal nichts"], 120, function()
        reviewMode = false
        CS.MarkApplied()
        window:Hide()
    end)
    window.skip:SetPoint("RIGHT", window.later, "LEFT", -6, 0)
    Tip(window.skip, L["Diesmal nichts"], L["Übernimmt nichts und fragt erst wieder, wenn eine neuere Vorlage gespeichert wird."])

    window:SetScript("OnShow", UI.Refresh)
    window:SetScript("OnHide", function() reviewMode = false end)
end

function UI.Refresh()
    if not window or not window:IsShown() then return end
    local db = CS.db
    local _, classLocal = CS.PlayerClass()

    local pending = CS.PendingScopes()
    if reviewMode and #pending > 0 then
        local names = {}
        for _, scope in ipairs(pending) do
            local tpl = CS.Template(scope)
            names[#names + 1] = tpl.sourceName or "?"
        end
        window.banner:SetText("|cff33ccff" .. L["Neue Vorlage von %s – prüfe, was übernommen werden soll."]:format(table.concat(names, ", ")) .. "|r")
    else
        window.banner:SetText(L["Einstellungen dieses Chars (%s, %s)"]:format(UnitName("player") or "?", classLocal))
    end
    window.info1:SetText(TemplateLine("general"))
    window.info2:SetText(TemplateLine("class"))
    window.saveClass:SetText(L["Als Vorlage für %s speichern"]:format(classLocal))
    window.master:SetChecked(CS.IsMaster("general"))
    window.classMaster:SetChecked(CS.IsMaster("class"))
    window.classMaster.label:SetText(L["Vorlage-Char für %s"]:format(classLocal))
    window.auto:SetChecked(db.autoApply)
    for m, cb in pairs(window.modChecks) do cb:SetChecked(db.modules[m]) end
    window.later:SetShown(reviewMode)
    window.skip:SetShown(reviewMode)

    local items = CS.ComputeDiff()
    local byModule = {}
    for _, it in ipairs(items) do
        byModule[it.module] = byModule[it.module] or {}
        table.insert(byModule[it.module], it)
    end

    for _, r in ipairs(rows) do r:Hide(); r.item = nil end
    local width = math.max(200, (window.scroll:GetWidth() or 400) - 4)
    content:SetWidth(width)
    local y, idx, selected = 0, 0, 0
    for _, m in ipairs(CS.MODULE_ORDER) do
        local list = byModule[m]
        if list then
            local on = db.modules[m]
            idx = idx + 1
            local r = GetRow(idx)
            r:SetSize(width, HEAD_H)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 0, -y)
            r.check:Hide(); r.label:Hide(); r.value:Hide(); r.desc:Hide(); r.info:Hide(); r.bg:Hide()
            r.header:Show()
            local tag = CS.MODULES[m].scope == "class" and ("  |cff999999" .. L["(Klassen-Vorlage)"] .. "|r") or ""
            r.header:SetText(L[CS.MODULES[m].title] .. tag .. (on and "" or ("  |cff808080" .. L["(Bereich ausgeschaltet)"] .. "|r")))
            r:Show()
            y = y + HEAD_H
            for _, it in ipairs(list) do
                idx = idx + 1
                local row = GetRow(idx)
                row:SetSize(width, ROW_H - 2)
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 0, -y)
                row.item = it
                row.header:Hide()
                row.check:Show(); row.label:Show(); row.value:Show(); row.desc:Show(); row.info:Show(); row.bg:Show()
                local checked = CS.IsChecked(it)
                local sel = on and checked
                row.check:SetChecked(checked)
                row.check:SetEnabled(on and not it.blocked)
                row.label:SetText(it.label)
                local c = sel and 1 or 0.55
                row.label:SetTextColor(c, c, c)
                row.value:SetText(L["|cffffd100Vorher:|r |cffff9090%s|r   →   |cffffd100Nachher:|r |cff90ff90%s|r"]:format(tostring(it.cur or ""), tostring(it.new or "")))
                if it.blocked then
                    row.desc:SetText("|cffff6060" .. L["Nicht möglich: %s"]:format(it.blocked) .. "|r")
                else
                    row.desc:SetText((tostring(it.desc or ""):gsub("\n.*", "")))
                end
                row:Show()
                if sel then selected = selected + 1 end
                y = y + ROW_H
            end
        end
    end
    content:SetHeight(math.max(1, y))

    if not CS.Template("general") and not CS.Template("class") then
        window.empty:SetText(L["Noch keine Vorlage gespeichert. Log dich mit dem Char ein, dessen Einstellungen für alle gelten sollen, und klick links auf „Als allgemeine Vorlage speichern“. Für Makros und Aktionsleisten speicherst du je Klasse eine Klassen-Vorlage."])
    elseif #items == 0 then
        window.empty:SetText(L["Keine Abweichungen – dieser Char entspricht den Vorlagen."])
    else
        window.empty:SetText("")
    end
    window.count:SetText(#items > 0 and L["%d Abweichungen, %d angehakt"]:format(#items, selected) or "")
    window.apply:SetEnabled(selected > 0)
end

function UI.Show() UI.Build(); window:Show(); UI.Refresh() end
function UI.ShowReview()
    UI.Build()
    reviewMode = true
    window:Show()
    UI.Refresh()
end
function UI.Toggle()
    UI.Build()
    if window:IsShown() then window:Hide() else UI.Show() end
end

-- Eintrag unter Optionen > AddOns
function UI.RegisterSettings()
    local panel = CreateFrame("Frame")
    panel.name = "CharSync"
    local t = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    t:SetPoint("TOPLEFT", 16, -16)
    t:SetText("CharSync")
    local d = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    d:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -8)
    d:SetWidth(560)
    d:SetJustifyH("LEFT")
    d:SetText(L["Speichert die Einstellungen des aktuellen Chars als Vorlage und überträgt sie auf die anderen Chars, sobald diese sich einloggen. Makros und Aktionsleisten gehen nur an Chars derselben Klasse. Vor dem Übernehmen siehst du für jede Einstellung vorher und nachher und kannst sie einzeln abwählen.\n\nBefehle: /charsync (Fenster), /charsync save (allgemeine Vorlage), /charsync saveclass (Klassen-Vorlage), /charsync apply (übernehmen)"])
    local b = MakeButton(panel, L["CharSync-Fenster öffnen"], 220, function()
        if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
        if InterfaceOptionsFrame and InterfaceOptionsFrame:IsShown() then HideUIPanel(InterfaceOptionsFrame) end
        UI.Show()
    end)
    b:SetPoint("TOPLEFT", d, "BOTTOMLEFT", 0, -16)

    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, "CharSync")
        Settings.RegisterAddOnCategory(category)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end
