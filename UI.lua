-- CharSync: Fenster (/charsync) mit Vorher-Nachher-Vergleich je Einstellung und Eintrag unter Optionen > AddOns.
local ADDON, CS = ...
local L = CS.L
local UI = {}
CS.UI = UI
-- Standard: zugeklappt (nur Überschriften); aufgeklappt bleibt, was der Spieler aufgeklappt hat
local function Collapsed(key) return CS.db.collapsed[key] ~= false end
local function Mark(key) return Collapsed(key) and "|cffffd100[+]|r " or "|cffffd100[–]|r " end
local function Resettable(it) return not it.excl and (it.acct or it.undo or CS.IsOwn(it)) end
local function ItemOn(it)
    if it.excl then return not CS.db.excluded[it.key] end
    if Resettable(it) then return UI.resetSel[it.key] == true end
    return CS.IsChecked(it)
end
local function SetItemOn(it, v)
    if it.excl then CS.db.excluded[it.key] = (not v) and true or nil
    elseif Resettable(it) then UI.resetSel[it.key] = v or nil
    elseif not it.blocked then CS.SetChecked(it, v) end
end
-- Haken in der Überschrift eines Abschnitts: hakt alles darin an bzw. ab
local function HeaderCheck(r, list, indent)
    indent = indent or 0
    local sel = {}
    for _, it in ipairs(list) do if not it.isError and not it.blocked then sel[#sel + 1] = it end end
    r.groupItems = sel
    r.header:ClearAllPoints()
    r.header:SetPoint("RIGHT", r, "RIGHT", -4, 0)
    if #sel == 0 then
        r.check:Hide()
        r.header:SetPoint("BOTTOMLEFT", 4 + indent, 4)
        return
    end
    local all = true
    for _, it in ipairs(sel) do if not ItemOn(it) then all = false break end end
    r.check:ClearAllPoints()
    r.check:SetPoint("BOTTOMLEFT", 2 + indent, 0)
    r.check:SetEnabled(true)
    r.check:SetChecked(all)
    r.check:Show()
    r.header:SetPoint("BOTTOMLEFT", 28 + indent, 4)
end
UI.resetSel = {} -- angehakte zurücksetzbare Einträge (Änderungen seit der Vorlage, letzte Übernahme, accountweit; nur für die Sitzung)

local WIDTH, HEIGHT, LEFT_W = 900, 664, 270
local MIN_W, MIN_H = 760, 644 -- rechts passen so auch im Prüfmodus alle drei Knöpfe nebeneinander
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

-- Makro mit Symbol und vollständigem Text für den Tooltip
local function MacroBlock(lines, title, m, color)
    lines[#lines + 1] = " "
    if not m then
        lines[#lines + 1] = ("|cffffd100%s|r %s"):format(title, L["(kein Makro)"])
        return
    end
    local icon = m.icon and ("|T" .. tostring(m.icon) .. ":16:16|t ") or ""
    lines[#lines + 1] = ("|cffffd100%s|r %s%s"):format(title, icon, CS.MacroLabel(m.name))
    local body = tostring(m.body or "")
    if body == "" then lines[#lines + 1] = "   |cff999999" .. L["(leer)"] .. "|r" end
    for line in body:gmatch("[^\n]+") do lines[#lines + 1] = "   " .. color .. (line:gsub("|", "||")) .. "|r" end
end

local function MacroLines(lines, it, own)
    local cur, tpl = it.curMacro, it.tplMacro
    if not cur and not tpl then return end
    local same = cur and tpl and cur.body == tpl.body and tostring(cur.icon) == tostring(tpl.icon)
    if same or not (cur and tpl) then
        -- gleich oder nur auf einer Seite: Inhalt einmal zeigen (welche Seite, steht schon in „Vorlage/Jetzt“ darüber)
        MacroBlock(lines, L["Makro-Text:"], cur or tpl, "|cffffffff")
    elseif own then
        MacroBlock(lines, L["In der Vorlage:"], tpl, "|cffffffff")
        MacroBlock(lines, L["Jetzt:"], cur, "|cffffffff")
    else
        MacroBlock(lines, L["Vorlage:"], tpl, "|cff90ff90")
        MacroBlock(lines, L["Dieser Char:"], cur, "|cffff9090")
    end
end

-- Tooltip einer Abweichung: was sie bewirkt, vorher/nachher, Einzelheiten
local function ItemTooltip(it)
    local lines = {}
    if it.excl then
        lines[#lines + 1] = L["Abgewählt: wird nie synchronisiert bzw. nicht verfolgt."]
        lines[#lines + 1] = "|cff999999" .. L["Haken setzen: wieder einbeziehen."] .. "|r"
        return lines
    end
    if it.acct then
        lines[#lines + 1] = "|cff88bbff" .. tostring(it.group) .. "|r"
        lines[#lines + 1] = " "
        lines[#lines + 1] = L["|cffffd100Vorher:|r %s"]:format(it.old)
        lines[#lines + 1] = L["|cffffd100Jetzt:|r %s"]:format(it.cur)
        lines[#lines + 1] = " "
        lines[#lines + 1] = "|cff999999" .. L["Zurücksetzen = alten Wert wiederherstellen. Übernehmen = neuen Wert als Stand merken."] .. "|r"
        lines[#lines + 1] = "|cff999999" .. L["Rechtsklick: diese Einstellung nie verfolgen."] .. "|r"
        lines[#lines + 1] = "|cff777777" .. L["Intern: %s"]:format(tostring(it.tech)) .. "|r"
        return lines
    end
    if it.isError then
        lines[#lines + 1] = "|cffff6060" .. tostring(it.blocked) .. "|r"
        return lines
    end
    if it.undo then
        lines[#lines + 1] = L["Macht nur diese Änderung der letzten Übernahme rückgängig."]
        lines[#lines + 1] = " "
        lines[#lines + 1] = L["|cffffd100Vor der Übernahme:|r %s"]:format(tostring(it.new or ""))
        lines[#lines + 1] = L["|cffffd100Jetzt:|r %s"]:format(tostring(it.cur or ""))
        local cur, old = it.curMacro, it.tplMacro
        if cur or old then
            MacroBlock(lines, L["Vor der Übernahme:"], old, "|cff90ff90")
            MacroBlock(lines, L["Jetzt:"], cur, "|cffff9090")
        end
        return lines
    end
    if CS.IsOwn(it) then
        -- Vorlage-Char: Änderung seit dem Speichern der Vorlage
        lines[#lines + 1] = L["Seit dem Speichern der Vorlage geändert. Mit „Vorlage aktualisieren“ geht diese Änderung an die anderen Chars."]
        lines[#lines + 1] = " "
        lines[#lines + 1] = L["|cffffd100In der Vorlage:|r %s"]:format(tostring(it.tplText or it.new or ""))
        lines[#lines + 1] = L["|cffffd100Jetzt:|r %s"]:format(tostring(it.curText or it.cur or ""))
        MacroLines(lines, it, true)
        return lines
    end
    if it.desc then lines[#lines + 1] = it.desc end
    lines[#lines + 1] = " "
    local def = CS.MODULES[it.module]
    local tpl = def and CS.Template(def.scope)
    lines[#lines + 1] = L["|cffffd100Vorlage (%s):|r %s"]:format(tpl and CS.ClassText(tpl.class, tpl.sourceName, "|cffffd100") or "?", tostring(it.new or ""))
    lines[#lines + 1] = L["|cffffd100Dieser Char:|r %s"]:format(tostring(it.cur or ""))
    if it.effect and it.effect ~= "" then
        lines[#lines + 1] = " "
        lines[#lines + 1] = "|cff33ccff" .. L["Beim Übernehmen: %s"]:format(it.effect) .. "|r"
    end
    if it.details and #it.details > 0 then
        lines[#lines + 1] = " "
        for _, d in ipairs(it.details) do lines[#lines + 1] = d end
    end
    MacroLines(lines, it, false)
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
    -- Knöpfe je Zeile (Vorlage-Char: „In Vorlage“/„Zurücksetzen“, Rückgängig-Liste: „Rückgängig“)
    r.btn2 = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
    r.btn2:SetSize(100, 20)
    r.btn2:SetPoint("RIGHT", r, "RIGHT", -24, 0)
    r.btn1 = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
    r.btn1:SetSize(100, 20)
    r.btn1:SetPoint("RIGHT", r.btn2, "LEFT", -4, 0)
    r.btn1:Hide(); r.btn2:Hide()
    -- Einrückung (Einträge unter einer Addon-Gruppe): Haken, Text und Hintergrund nach rechts
    r.indent = 0
    function r.SetIndent(n)
        r.indent = n or 0
        r.check:ClearAllPoints(); r.check:SetPoint("TOPLEFT", 2 + r.indent, -4)
        r.bg:ClearAllPoints(); r.bg:SetPoint("TOPLEFT", r.indent, 0); r.bg:SetPoint("BOTTOMRIGHT")
    end
    -- Platz rechts für Knöpfe frei halten
    function r.SetRightInset(off)
        for _, fs in ipairs({ r.label, r.value, r.desc }) do
            fs:ClearAllPoints()
        end
        r.label:SetPoint("TOPLEFT", (r.check:IsShown() and 28 or 6) + (r.indent or 0), -5)
        r.label:SetPoint("RIGHT", r, "RIGHT", -off, 0)
        r.value:SetPoint("TOPLEFT", r.label, "BOTTOMLEFT", 0, -3)
        r.value:SetPoint("RIGHT", r, "RIGHT", -off, 0)
        r.desc:SetPoint("TOPLEFT", r.value, "BOTTOMLEFT", 0, -3)
        r.desc:SetPoint("RIGHT", r, "RIGHT", -off, 0)
    end
    r.header = r:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    r.header:SetPoint("BOTTOMLEFT", 4, 4)
    r.header:SetWordWrap(false)
    -- Auswahl-Knöpfe der Zurücksetzen-Leiste (links)
    r.sel1 = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
    r.sel1:SetSize(110, 20)
    r.sel1:SetPoint("BOTTOMLEFT", 2, 2)
    r.sel1:Hide()
    r.sel2 = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
    r.sel2:SetSize(70, 20)
    r.sel2:SetPoint("LEFT", r.sel1, "RIGHT", 4, 0)
    r.sel2:Hide()
    r.hbtn = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
    r.hbtn:SetSize(130, 20)
    r.hbtn:SetPoint("BOTTOMRIGHT", -24, 2)
    r.hbtn:Hide()
    r.hbtn2 = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
    r.hbtn2:SetSize(120, 20)
    r.hbtn2:SetPoint("RIGHT", r.hbtn, "LEFT", -4, 0)
    r.hbtn2:Hide()
    r.hbtn3 = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
    r.hbtn3:SetSize(160, 20)
    r.hbtn3:SetPoint("RIGHT", r.hbtn2, "LEFT", -4, 0)
    r.hbtn3:Hide()
    r.header:SetPoint("RIGHT", r, "RIGHT", -4, 0)
    r.header:SetJustifyH("LEFT")
    r.check:SetScript("OnClick", function(self)
        if r.groupItems then
            local v = self:GetChecked() and true or false
            for _, it in ipairs(r.groupItems) do SetItemOn(it, v) end
            UI.Refresh()
        elseif r.item and r.item.excl then
            SetItemOn(r.item, self:GetChecked())
            UI.Refresh()
        elseif r.item and (r.item.acct or r.item.undo or CS.IsOwn(r.item)) then
            UI.resetSel[r.item.key] = self:GetChecked() and true or nil
            UI.Refresh()
        elseif r.item then
            CS.SetChecked(r.item, self:GetChecked())
            UI.Refresh()
        end
    end)
    local function enter(self)
        if r.groupItems and self == r.check then
            GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
            GameTooltip:SetText(L["Alles in diesem Abschnitt anhaken oder abwählen."], 1, 1, 1, 1, true)
            GameTooltip:Show()
            return
        end
        if not r.item then return end
        GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
        GameTooltip:SetText(r.item.label, 1, 1, 1, 1, true)
        for _, l in ipairs(ItemTooltip(r.item)) do GameTooltip:AddLine(l, nil, nil, nil, true) end
        GameTooltip:Show()
    end
    r:SetScript("OnEnter", enter)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r.check:SetScript("OnEnter", enter)
    r:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" and self.collapseKey then
            CS.db.collapsed[self.collapseKey] = not Collapsed(self.collapseKey)
            UI.Refresh()
            return
        end
        if button == "RightButton" and self.item and self.item.acct then
            CS.db.excluded["acct:" .. self.item.id] = true
            UI.Refresh()
        end
    end)
    r.check:SetScript("OnLeave", function() GameTooltip:Hide() end)
    rows[i] = r
    return r
end

local function TemplateLine(scope)
    local tpl = CS.Template(scope)
    local class, classLocal = CS.PlayerClass()
    local title = scope == "class" and L["Vorlage für %s"]:format(CS.ClassText(class, classLocal, "|cffffd100")) or L["Allgemeine Vorlage"]
    if not tpl then return ("|cffffd100%s:|r |cff999999%s|r"):format(title, L["noch keine"]) end
    local me = (tpl.source == CS.CharKey()) and (" |cff00ff00" .. L["(dieser Char)"] .. "|r") or ""
    return ("|cffffd100%s:|r %s%s – %s"):format(title, CS.ClassText(tpl.class, tpl.source or "?"), me, date(L["%d.%m.%Y um %H:%M"], tpl.time or 0))
end

function UI.Build()
    if window then return end
    window = CreateFrame("Frame", "CharSyncFrame", UIParent, "BasicFrameTemplateWithInset")
    -- Größe: nie größer als der Bildschirm (eine zu große gespeicherte Größe wird gekürzt)
    local function MaxW() return math.max(MIN_W, math.floor((UIParent:GetWidth() or 1600) - 40)) end
    local function MaxH() return math.max(MIN_H, math.floor((UIParent:GetHeight() or 900) - 40)) end
    local size = type(CS.db.window) == "table" and CS.db.window or {}
    window:SetSize(math.min(MaxW(), math.max(MIN_W, size.w or WIDTH)), math.min(MaxH(), math.max(MIN_H, size.h or HEIGHT)))
    window:SetResizable(true)
    local function SetBounds()
        if window.SetResizeBounds then window:SetResizeBounds(MIN_W, MIN_H, MaxW(), MaxH())
        elseif window.SetMinResize then window:SetMinResize(MIN_W, MIN_H); if window.SetMaxResize then window:SetMaxResize(MaxW(), MaxH()) end end
    end
    SetBounds()
    local grip = CreateFrame("Button", nil, window)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -3, 3)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    local function StopSizing()
        if not window.sizing then return end
        window.sizing = false
        window:StopMovingOrSizing()
        window:SetClampedToScreen(true)
        SetBounds()
        CS.db.window = { w = window:GetWidth(), h = window:GetHeight() }
        UI.Refresh()
    end
    grip:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then return end
        -- vorher oben links festmachen: von der Mitte aus verankert wächst das Fenster in beide Richtungen,
        -- stößt oben an den Bildschirmrand und springt dann auf volle Höhe
        local left, top = window:GetLeft(), window:GetTop()
        if left and top then
            window:ClearAllPoints()
            window:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        end
        -- höchstens bis zum Bildschirmrand unten/rechts: größer würde das Am-Rand-Festhalten (ClampedToScreen) das
        -- Fenster nach oben schieben, während es weiter wächst – es spränge auf volle Höhe
        local maxW = math.max(MIN_W, math.floor((UIParent:GetWidth() or 1600) - (left or 0) - 8))
        local maxH = math.max(MIN_H, math.floor((top or 900) - 8))
        if window.SetResizeBounds then window:SetResizeBounds(MIN_W, MIN_H, math.min(MaxW(), maxW), math.min(MaxH(), maxH))
        else SetBounds() end
        window:SetClampedToScreen(false)
        window.sizing = true
        window:StartSizing("BOTTOMRIGHT")
    end)
    grip:SetScript("OnMouseUp", StopSizing)
    window:HookScript("OnHide", StopSizing)
    window.grip = grip
    window:SetScript("OnSizeChanged", function() UI.Relayout() end)
    window:SetPoint("CENTER")
    window:SetFrameStrata("HIGH")
    -- eigenes Fenster: kommt beim Öffnen und Anklicken nach vorn (sonst zeichnet WoW gleich hohe Fenster anderer Addons,
    -- durcheinander) und hat einen deckenden Hintergrund
    window:SetToplevel(true)
    window:SetFrameLevel(20)
    local solid = window:CreateTexture(nil, "BACKGROUND", nil, -8)
    solid:SetPoint("TOPLEFT", 4, -4)
    solid:SetPoint("BOTTOMRIGHT", -4, 4)
    solid:SetColorTexture(0.04, 0.04, 0.05, 0.96)
    window:SetClampedToScreen(true)
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    window:Hide()
    tinsert(UISpecialFrames, "CharSyncFrame")
    -- X-Knopf: direkt schließen statt über HideUIPanel (das kann im Kampf blockiert werden)
    local close = window.CloseButton or _G["CharSyncFrameCloseButton"]
    if type(close) == "table" and close.SetScript then close:SetScript("OnClick", function() window:Hide() end) end

    local title = window.TitleText
    if not title then
        title = window:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        title:SetPoint("TOP", 0, -5)
    end
    title:SetText(L["CharSync – Einstellungen auf alle Chars übertragen"])

    -- Hinweis bei neuer Vorlage
    window.banner = window:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    window.banner:SetPoint("TOPLEFT", 16, -32)
    window.banner:SetPoint("RIGHT", window, "RIGHT", -210, 0)
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
        CS.SaveAll()
        UI.Refresh()
    end)
    window.save:SetPoint("TOPLEFT", 14, y)
    Tip(window.save, L["Allgemeine Vorlage"], L["Speichert alle Einstellungen dieses Chars, wie sie gerade sind: die allgemeine Vorlage und die Vorlage seiner Klasse (wenn dieser Char sie stellt). Accountweite Einstellungen bleiben unberührt – die übernimmst du über die Knöpfe unten rechts."])
    y = y - 28
    window.saveClass = MakeButton(window, L["Als Klassen-Vorlage speichern"], LEFT_W - 20, function()
        CS.SaveTemplate("class")
        UI.Refresh()
    end)
    window.saveClass:SetPoint("TOPLEFT", 14, y)
    Tip(window.saveClass, L["Klassen-Vorlage"], function()
        local _, classLocal = CS.PlayerClass()
        return L["Speichert Makros und Aktionsleisten dieses Chars als Vorlage für alle Chars der Klasse %s."]:format(CS.ClassText((CS.PlayerClass()), classLocal))
    end)
    y = y - 32

    window.master = MakeCheck(window, L["Allgemeiner Vorlage-Char"],
        L["Dieser Char stellt die allgemeine Vorlage. Mit „Vorlage automatisch aktualisieren“ wird sie automatisch gespeichert, sonst per Knopf oder einzeln mit „In Vorlage“."])
    window.master:SetPoint("TOPLEFT", 12, y)
    window.master:SetScript("OnClick", function(self) CS.SetMaster("general", self:GetChecked()); UI.Refresh() end)
    y = y - 24
    window.classMaster = MakeCheck(window, L["Vorlage-Char seiner Klasse"],
        L["Dieser Char stellt Makros und Aktionsleisten für seine Klasse. Mit „Vorlage automatisch aktualisieren“ wird diese Vorlage automatisch gespeichert."])
    window.classMaster:SetPoint("TOPLEFT", 12, y)
    window.classMaster:SetScript("OnClick", function(self) CS.SetMaster("class", self:GetChecked()); UI.Refresh() end)
    y = y - 24
    window.auto = MakeCheck(window, L["Ohne Nachfrage übernehmen"],
        L["Neue Vorlagen werden beim Einloggen sofort übernommen, ohne dass sich dieses Fenster zum Prüfen öffnet."])
    window.auto:SetPoint("TOPLEFT", 12, y)
    window.auto:SetScript("OnClick", function(self) CS.db.autoApply = self:GetChecked() and true or false end)
    y = y - 24
    window.autoUpdate = MakeCheck(window, L["Vorlage automatisch aktualisieren"],
        L["Vorlage-Chars speichern ihre Vorlage einmal pro Minute und beim Ausloggen, wenn sich etwas geändert hat. Standard: aus."])
    window.autoUpdate:SetPoint("TOPLEFT", 12, y)
    window.autoUpdate:SetScript("OnClick", function(self) CS.db.autoUpdate = self:GetChecked() and true or false; UI.Refresh() end)
    y = y - 34

    -- oben rechts in der Ecke: Minimap-Icon (Beschriftung links vom Häkchen)
    window.minimap = MakeCheck(window, L["Minimap-Icon anzeigen"], L["Zeigt das CharSync-Icon an der Minimap. Ein Klick darauf öffnet dieses Fenster."])
    window.minimap:SetPoint("TOPRIGHT", -12, -28)
    window.minimap.label:ClearAllPoints()
    window.minimap.label:SetPoint("RIGHT", window.minimap, "LEFT", -2, 0)
    window.minimap:SetScript("OnClick", function(self)
        CS.db.minimap.hide = not self:GetChecked()
        if UI.UpdateMinimapButton then UI.UpdateMinimapButton() end
    end)

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
    window.acctCheck = MakeCheck(window, L["Accountweite Einstellungen"],
        L["Verfolgt Einstellungen, die für alle Chars gelten (accountweite Addon-Einstellungen, accountweite WoW-Optionen): Bei jedem Einloggen merkt sich CharSync den Stand, danach erscheint hier jede Änderung mit vorherigem Wert – einzeln übernehmen oder zurücksetzen, ausgewählte oder alle. Standard: aus."])
    window.acctCheck:SetPoint("TOPLEFT", 12, y)
    window.acctCheck:SetScript("OnClick", function(self)
        CS.db.trackAccount = self:GetChecked() and true or false
        if CS.db.trackAccount then CS.Account.EnsureBase() end
        UI.Refresh()
    end)
    y = y - 24
    window.exclCheck = MakeCheck(window, L["Abgewählte Einstellungen"],
        L["Zeigt am Ende der Liste die Einstellungen, die du abgewählt hast (nie synchronisieren, nie verfolgen). Ein Haken dort holt sie zurück."])
    window.exclCheck:SetPoint("TOPLEFT", 12, y)
    window.exclCheck:SetScript("OnClick", function(self)
        CS.db.showExcluded = self:GetChecked() and true or false
        UI.Refresh()
    end)
    y = y - 24

    -- rechte Spalte: Vergleich
    local x = LEFT_W + 6
    local h2 = window:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    h2:SetPoint("TOPLEFT", x, -96)
    h2:SetText(L["Vergleich: dieser Char » Vorlage"])
    window.count = window:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    window.count:SetPoint("TOPRIGHT", -36, -100)
    window.count:SetJustifyH("RIGHT")
    window.count:SetWordWrap(false)
    -- Überschrift endet vor dem Zähler (wird bei wenig Platz abgeschnitten statt überlagert)
    h2:SetPoint("RIGHT", window.count, "LEFT", -10, 0)
    h2:SetJustifyH("LEFT")
    h2:SetWordWrap(false)

    local scroll = CreateFrame("ScrollFrame", "CharSyncScroll", window, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", x, -118)
    scroll:SetPoint("BOTTOMRIGHT", -32, 72)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(WIDTH - x - 40, 1)
    scroll:SetScrollChild(content)
    window.scroll = scroll

    window.empty = window:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    window.empty:SetPoint("TOPLEFT", scroll, "TOPLEFT", 6, -10)
    window.empty:SetPoint("RIGHT", scroll, "RIGHT", -6, 0)
    window.empty:SetJustifyH("LEFT")

    -- „Alle anhaken“ wirkt accountweit: alle Bereiche an, alle Abwahlen zurück – auch die von anderen Chars
    window.all = MakeButton(window, L["Alle anhaken"], 110, function()
        for _, it in ipairs(UI.resettable or {}) do UI.resetSel[it.key] = true end
        UI.Refresh()
    end)
    window.all:SetPoint("BOTTOMLEFT", 14, 12) -- links unter den Bereichen: kann nie mit den Knöpfen rechts überlappen
    Tip(window.all, L["Alle anhaken"], L["Hakt alles in der Liste an. Abgewählte Einstellungen bleiben abgewählt."])
    window.none = MakeButton(window, L["Keine"], 80, function()
        for _, it in ipairs(CS.ComputeDiff()) do if not CS.IsOwn(it) and CS.db.modules[it.module] then CS.SetChecked(it, false) end end
        wipe(UI.resetSel)
        UI.Refresh()
    end)
    window.none:SetPoint("LEFT", window.all, "RIGHT", 6, 0)
    Tip(window.none, L["Keine"], L["Entfernt alle Haken in der Liste."])
    window.excludedCount = window:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    window.excludedCount:SetPoint("BOTTOMLEFT", 16, 42)

    window.apply = MakeButton(window, L["Angehakte übernehmen"], 190, function()
        reviewMode = false
        -- angehakte Änderungen behalten (accountweit -> neuer Stand, Vorlage-Char -> in die Vorlage) …
        local keep = {}
        for _, it in ipairs(UI.resettable or {}) do if UI.resetSel[it.key] then keep[#keep + 1] = it end end
        if #keep > 0 then UI.AcceptBatch(keep) end
        -- … und angehakte Abweichungen anderer Chars aus der Vorlage übernehmen
        if #CS.SelectedDiff() > 0 then CS.ApplyNow() end
    end)
    Tip(window.apply, L["Angehakte übernehmen"], L["Übernimmt alles Angehakte: Abweichungen zur Vorlage werden übernommen, accountweite Einstellungen werden der neue Stand, Änderungen seit der Vorlage gehen in die Vorlage."])
    -- Position folgt unten (rechte Spalte „Alle …“, links daneben „Angehakte / Ausgewählte …“)
    window.applyAll = MakeButton(window, L["Alle übernehmen"], 150, function()
        reviewMode = false
        UI.AcceptBatch(UI.resettable or {}, true)
        if #CS.SelectedDiff() > 0 then CS.ApplyNow() end
    end)
    window.applyAll:SetPoint("BOTTOMRIGHT", -28, 12)
    window.apply:SetPoint("RIGHT", window.applyAll, "LEFT", -6, 0)
    Tip(window.applyAll, L["Alle übernehmen"], L["Übernimmt alles in der Liste: Abweichungen zur Vorlage (außer nie zu synchronisierenden), accountweite Einstellungen als neuen Stand, Änderungen seit der Vorlage in die Vorlage."])
    window.resetAll = MakeButton(window, L["Alle zurücksetzen"], 150, function() UI.ResetBatch(UI.resettable or {}) end)
    -- Spalten: „Alle …“ über „Alle …“, „Ausgewählte …“ über „Angehakte …“ (gleich breit)
    Tip(window.resetAll, L["Alle zurücksetzen"], L["Setzt alle zurücksetzbaren Änderungen in der Liste zurück: Änderungen seit der Vorlage, die letzte Übernahme und accountweite Einstellungen."])
    window.resetSel = MakeButton(window, L["Ausgewählte zurücksetzen"], 190, function()
        local list = {}
        for _, it in ipairs(UI.resettable or {}) do if UI.resetSel[it.key] then list[#list + 1] = it end end
        UI.ResetBatch(list)
    end)
    window.resetSel:SetPoint("BOTTOMRIGHT", window.apply, "TOPRIGHT", 0, 4)
    window.resetAll:SetPoint("BOTTOMRIGHT", window.applyAll, "TOPRIGHT", 0, 4)
    Tip(window.resetSel, L["Ausgewählte zurücksetzen"], L["Setzt nur die angehakten Änderungen zurück."])
    window.later = MakeButton(window, L["Später"], 90, function()
        reviewMode = false
        window:Hide()
    end)
    window.later:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", LEFT_W + 6, 40)
    Tip(window.later, L["Später"], L["Schließt das Fenster. Beim nächsten Login wirst du wieder gefragt."])
    window.skip = MakeButton(window, L["Diesmal nichts"], 120, function()
        reviewMode = false
        CS.MarkApplied()
        window:Hide()
    end)
    window.skip:SetPoint("LEFT", window.later, "RIGHT", 6, 0)
    Tip(window.skip, L["Diesmal nichts"], L["Übernimmt nichts und fragt erst wieder, wenn eine neuere Vorlage gespeichert wird."])

    window:SetScript("OnShow", function() window:Raise(); UI.Refresh() end)
    window:SetScript("OnHide", function() reviewMode = false end)
end

function UI.Refresh()
    if not window or not window:IsShown() then return end
    local db = CS.db
    local class, classLocal = CS.PlayerClass()
    local classText = CS.ClassText(class, classLocal)

    local pending = CS.PendingScopes()
    if reviewMode and #pending > 0 then
        local names = {}
        for _, scope in ipairs(pending) do
            local tpl = CS.Template(scope)
            names[#names + 1] = CS.ClassText(tpl.class, tpl.sourceName or "?", "|cff33ccff")
        end
        window.banner:SetText("|cff33ccff" .. L["Neue Vorlage von %s – prüfe, was übernommen werden soll."]:format(table.concat(names, ", ")) .. "|r")
    else
        window.banner:SetText(L["Einstellungen dieses Chars (%s, %s)"]:format(CS.ClassText(class, UnitName("player") or "?", "|cffffd100"), CS.ClassText(class, classLocal, "|cffffd100")))
    end
    window.info1:SetText(TemplateLine("general"))
    window.info2:SetText(TemplateLine("class"))
    window.saveClass:SetText(L["Als Vorlage für %s speichern"]:format(classText))
    window.master:SetChecked(CS.IsMaster("general"))
    window.classMaster:SetChecked(CS.IsMaster("class"))
    window.classMaster.label:SetText(L["Vorlage-Char für %s"]:format(classText))
    window.autoUpdate:SetChecked(db.autoUpdate)
    window.auto:SetChecked(db.autoApply)
    window.minimap:SetChecked(not (db.minimap and db.minimap.hide))
    for m, cb in pairs(window.modChecks) do cb:SetChecked(db.modules[m]) end
    window.later:SetShown(reviewMode)
    window.skip:SetShown(reviewMode)

    -- links ausgeschaltete Bereiche: rechts versteckt und von allen Sammel-Knöpfen ausgenommen
    local items = {}
    for _, it in ipairs(CS.ComputeDiff()) do if db.modules[it.module] then items[#items + 1] = it end end
    local byModule = {}
    for _, it in ipairs(items) do
        byModule[it.module] = byModule[it.module] or {}
        table.insert(byModule[it.module], it)
    end

    local acctItems, acctLoading = {}, false
    window.acctCheck:SetChecked(db.trackAccount)
    window.exclCheck:SetChecked(db.showExcluded ~= false)
    if db.trackAccount then
        CS.Account.EnsureBase()
        local d = CS.Account.Diff()
        if not d or not CS.Account.Base() then acctLoading = true end
        acctItems = d or {}
        -- Fenster, die oben im Bereich „Fensterpositionen“ schon stehen, accountweit nicht noch einmal zeigen
        local inFrames = {}
        for _, it in ipairs(items) do
            local n = it.module == "frames" and it.key:match("^frames:(.*)$")
            if n then inFrames[n] = true end
        end
        if next(inFrames) then
            local keep = {}
            for _, it in ipairs(acctItems) do
                local n = it.id and it.id:match("^frame\001(.*)$")
                if not (n and inFrames[n]) then keep[#keep + 1] = it end
            end
            acctItems = keep
        end
    end
    local undoItems = {}
    for _, it in ipairs(CS.UndoDiff()) do if not it.module or db.modules[it.module] then undoItems[#undoItems + 1] = it end end
    -- alles, was sich zurücksetzen lässt, in Anzeige-Reihenfolge
    local resettable = {}
    for _, it in ipairs(undoItems) do resettable[#resettable + 1] = it end
    for _, m in ipairs(CS.MODULE_ORDER) do
        for _, it in ipairs(byModule[m] or {}) do
            if not it.isError and CS.IsOwn(it) and not it.blocked then resettable[#resettable + 1] = it end
        end
    end
    for _, it in ipairs(acctItems) do resettable[#resettable + 1] = it end
    UI.resettable = resettable
    local valid, nsel = {}, 0
    for _, it in ipairs(resettable) do valid[it.key] = true end
    for k in pairs(UI.resetSel) do if not valid[k] then UI.resetSel[k] = nil else nsel = nsel + 1 end end

    for _, r in ipairs(rows) do
        r.groupItems = nil
        r.SetIndent(0)
        r.header:ClearAllPoints(); r.header:SetPoint("BOTTOMLEFT", 4, 4); r.header:SetPoint("RIGHT", r, "RIGHT", -4, 0)
    end
    for _, r in ipairs(rows) do r:Hide(); r.item = nil; r.collapseKey = nil; r.hbtn2:Hide(); r.hbtn3:Hide(); r.sel1:Hide(); r.sel2:Hide() end
    local width = math.max(200, (window.scroll:GetWidth() or 400) - 4)
    content:SetWidth(width)
    local y, idx, selected, own = 0, 0, 0, 0

    -- Letzte Übernahme: jede Änderung einzeln oder alle rückgängig machen
    if #undoItems > 0 then
        idx = idx + 1
        local h = GetRow(idx)
        h:SetSize(width, HEAD_H)
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", 0, -y)
        h.check:Hide(); h.label:Hide(); h.value:Hide(); h.desc:Hide(); h.info:Hide(); h.bg:Hide(); h.btn1:Hide(); h.btn2:Hide()
        h.header:Show()
        HeaderCheck(h, undoItems)
        h.collapseKey = "undo"
        h.header:SetText(Mark("undo") .. "|cff33ccff" .. L["Letzte Übernahme vom %s"]:format(date(L["%d.%m.%Y um %H:%M"], CS.cdb.undo.time or 0)) .. "|r")
        h.hbtn:SetText(L["Alles rückgängig"])
        h.hbtn:SetScript("OnClick", function() CS.UndoAll() end)
        Tip(h.hbtn, L["Alles rückgängig"], L["Macht alle Änderungen der letzten Übernahme rückgängig, die noch bestehen."])
        h.hbtn:Show()
        h:Show()
        y = y + HEAD_H
        for _, it in ipairs(Collapsed("undo") and {} or undoItems) do
            idx = idx + 1
            local row = GetRow(idx)
            row:SetSize(width, ROW_H - 2)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -y)
            row.item = it
            row.SetIndent(16)
            row.header:Hide(); row.hbtn:Hide()
            row.check:Show(); row.check:SetEnabled(true); row.check:SetChecked(UI.resetSel[it.key] == true)
            row.label:Show(); row.value:Show(); row.desc:Show(); row.info:Show(); row.bg:Show()
            row.label:SetText(it.label)
            row.label:SetTextColor(1, 1, 1)
            row.value:SetText(L["|cffffd100Vor der Übernahme:|r |cff90ff90%s|r   »   |cffffd100Jetzt:|r |cffff9090%s|r"]:format(tostring(it.new or ""), tostring(it.cur or "")))
            row.desc:SetText(L["Macht nur diese Änderung der letzten Übernahme rückgängig."])
            row.btn1:Hide()
            row.btn2:SetText(L["Rückgängig"])
            row.btn2:SetScript("OnClick", function() CS.UndoItem(it) end)
            row.btn2:Show()
            row.SetRightInset(130)
            row:Show()
            y = y + ROW_H
        end
    end

    for _, m in ipairs(CS.MODULE_ORDER) do
        local list = byModule[m]
        if list then
            local on = db.modules[m]
            idx = idx + 1
            local r = GetRow(idx)
            r:SetSize(width, HEAD_H)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 0, -y)
            r.check:Hide(); r.label:Hide(); r.value:Hide(); r.desc:Hide(); r.info:Hide(); r.bg:Hide(); r.btn1:Hide(); r.btn2:Hide(); r.hbtn:Hide()
            r.header:Show()
            HeaderCheck(r, list)
            local tag = CS.MODULES[m].scope == "class" and ("  |cff999999" .. L["(Klassen-Vorlage)"] .. "|r") or ""
            if CS.IsOwn(list[1]) then tag = tag .. "  |cff33ccff" .. L["(seit der Vorlage geändert)"] .. "|r" end
            r.collapseKey = "mod:" .. m
            r.header:SetText(Mark("mod:" .. m) .. L[CS.MODULES[m].title] .. tag)
            r:Show()
            y = y + HEAD_H
            for _, it in ipairs(Collapsed("mod:" .. m) and {} or list) do
                idx = idx + 1
                local row = GetRow(idx)
                row:SetSize(width, ROW_H - 2)
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 0, -y)
                row.item = it
                row.SetIndent(16)
                row.header:Hide(); row.hbtn:Hide()
                row.check:Show(); row.label:Show(); row.value:Show(); row.desc:Show(); row.info:Show(); row.bg:Show()
                row.btn1:Hide(); row.btn2:Hide()
                if it.isError then
                    -- Fehler des Bereichs: Meldung zeigen, keine Knöpfe
                    row.check:Hide()
                    row.label:SetText(it.label)
                    row.label:SetTextColor(1, 0.4, 0.4)
                    row.value:SetText("")
                    row.desc:SetText("|cffff6060" .. tostring(it.blocked) .. "|r")
                    row.SetRightInset(24)
                elseif CS.IsOwn(it) then
                    -- Vorlage-Char: Änderung seit dem Speichern, kein Haken, dafür je Änderung „In Vorlage“ / „Zurücksetzen“
                    own = own + 1
                    row.check:Show(); row.check:SetEnabled(not it.blocked); row.check:SetChecked(UI.resetSel[it.key] == true)
                    row.btn1:SetText(L["In Vorlage"])
                    row.btn1:SetScript("OnClick", function() CS.PushItem(it) end)
                    Tip(row.btn1, L["In Vorlage"], L["Übernimmt nur diese Änderung in die Vorlage. Die anderen Chars bekommen sie beim nächsten Login angezeigt."])
                    row.btn1:SetEnabled(it.toTemplate ~= nil)
                    row.btn1:Show()
                    row.btn2:SetText(L["Zurücksetzen"])
                    row.btn2:SetScript("OnClick", function() CS.ResetItem(it) end)
                    Tip(row.btn2, L["Zurücksetzen"], L["Setzt nur diese Einstellung bei diesem Char auf den Stand der Vorlage zurück."])
                    row.btn2:SetEnabled(not it.blocked and not it.noReset)
                    row.btn2:Show()
                    row.label:SetText(it.label)
                    row.label:SetTextColor(1, 1, 1)
                    row.value:SetText(L["|cffffd100In der Vorlage:|r %s   »   |cffffd100Jetzt:|r %s"]:format(tostring(it.tplText or it.new or ""), tostring(it.curText or it.cur or "")))
                    row.desc:SetText(it.noResetText or L["Seit dem Speichern der Vorlage geändert. Mit „Vorlage aktualisieren“ geht diese Änderung an die anderen Chars."])
                    row.SetRightInset(234)
                else
                    row.SetRightInset(24)
                    local checked = CS.IsChecked(it)
                    local sel = on and checked
                    row.check:SetChecked(checked)
                    row.check:SetEnabled(on and not it.blocked)
                    row.label:SetText(it.label)
                    local c = sel and 1 or 0.55
                    row.label:SetTextColor(c, c, c)
                    row.value:SetText(L["|cffffd100Vorlage:|r |cff90ff90%s|r   »   |cffffd100Dieser Char:|r |cffff9090%s|r"]:format(tostring(it.new or ""), tostring(it.cur or "")))
                    if it.blocked then
                        row.desc:SetText("|cffff6060" .. L["Nicht möglich: %s"]:format(it.blocked) .. "|r")
                    elseif it.effect and it.effect ~= "" then
                        row.desc:SetText("|cff33ccff" .. L["Beim Übernehmen: %s"]:format(it.effect) .. "|r")
                    else
                        row.desc:SetText((tostring(it.desc or ""):gsub("\n.*", "")))
                    end
                    if sel then selected = selected + 1 end
                end
                row:Show()
                y = y + ROW_H
            end
        end
    end
    -- Accountweite Einstellungen (nur wenn angehakt): Änderungen seit dem Einloggen
    if db.trackAccount then
        local loading = acctLoading
        local base = CS.Account.Base()
        idx = idx + 1
        local h = GetRow(idx)
        h:SetSize(width, HEAD_H + 4)
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", 0, -y)
        h.check:Hide(); h.label:Hide(); h.value:Hide(); h.desc:Hide(); h.info:Hide(); h.bg:Hide(); h.btn1:Hide(); h.btn2:Hide(); h.hbtn:Hide()
        h.header:Show()
        HeaderCheck(h, acctItems)
        h.collapseKey = "acct"
        h.header:SetText(Mark("acct") .. L["Accountweite Einstellungen"] .. "  |cff999999" .. L["(seit dem Einloggen um %s)"]:format(date(L["%d.%m.%Y um %H:%M"], base and base.time or 0)) .. "|r")
        h:Show()
        y = y + HEAD_H + 4
        if #acctItems == 0 and not Collapsed("acct") then
            idx = idx + 1
            local r = GetRow(idx)

            r:SetSize(width, HEAD_H)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 0, -y)
            r.check:Hide(); r.label:Hide(); r.value:Hide(); r.desc:Hide(); r.info:Hide(); r.bg:Hide(); r.btn1:Hide(); r.btn2:Hide(); r.hbtn:Hide()
            r.header:Show()
            r.header:SetText("|cff999999" .. (loading and L["Wird gelesen …"] or L["Keine Änderungen seit dem Einloggen."]) .. "|r")
            r:Show()
            y = y + HEAD_H
        end
        local group
        for _, it in ipairs(Collapsed("acct") and {} or acctItems) do
          if it.group ~= group or not Collapsed("grp:" .. tostring(it.group)) then
            if it.group ~= group then
                group = it.group
                idx = idx + 1
                local g = GetRow(idx)
                g:SetSize(width, HEAD_H)
                g:ClearAllPoints()
                g:SetPoint("TOPLEFT", 0, -y)
                g.check:Hide(); g.label:Hide(); g.value:Hide(); g.desc:Hide(); g.info:Hide(); g.bg:Hide(); g.btn1:Hide(); g.btn2:Hide(); g.hbtn:Hide()
                g.header:Show()
                local inGroup = {}
                for _, x in ipairs(acctItems) do if x.group == group then inGroup[#inGroup + 1] = x end end
                HeaderCheck(g, inGroup, 16)
                g.collapseKey = "grp:" .. tostring(group)
                g.header:SetText(Mark(g.collapseKey) .. "|cff88bbff" .. group .. "|r")
                g:Show()
                y = y + HEAD_H
            end
          if not Collapsed("grp:" .. tostring(it.group)) then
            idx = idx + 1
            local row = GetRow(idx)
            row:SetSize(width, ROW_H - 2)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -y)
            row.item = it
            row.SetIndent(32) -- unter der Addon-Gruppe eingerückt (eine Stufe tiefer als deren Haken)
            row.header:Hide(); row.hbtn:Hide()
            row.check:Show()
            row.check:SetEnabled(true)
            row.check:SetChecked(UI.resetSel[it.key] == true)
            row.label:Show(); row.value:Show(); row.desc:Show(); row.info:Show(); row.bg:Show()
            row.label:SetText(it.label)
            row.label:SetTextColor(1, 1, 1)
            row.value:SetText(L["|cffffd100Vorher:|r |cff90ff90%s|r   »   |cffffd100Jetzt:|r |cffff9090%s|r"]:format(it.old, it.cur))
            row.desc:SetText(L["Gilt für alle Chars. Rechtsklick: nie verfolgen."])
            row.btn1:SetText(L["Übernehmen"])
            row.btn1:SetScript("OnClick", function() CS.Account.Accept(it); UI.Refresh() end)
            Tip(row.btn1, L["Übernehmen"], L["Merkt sich den neuen Wert als Stand; die Zeile verschwindet."])
            row.btn1:SetEnabled(true)
            row.btn1:Show()
            row.btn2:SetText(L["Zurücksetzen"])
            row.btn2:SetScript("OnClick", function() CS.Account.Reset(it); UI.Refresh() end)
            Tip(row.btn2, L["Zurücksetzen"], L["Stellt den vorherigen Wert wieder her."])
            row.btn2:SetEnabled(true)
            row.btn2:Show()
            row.SetRightInset(234)
            row:Show()
            y = y + ROW_H
          end
          end
        end
    end
    -- Abgewählt: alles, was nie synchronisiert/verfolgt wird und gerade nicht oben in der Liste steht – Haken holt es zurück
    local shown = {}
    for _, it in ipairs(items) do shown[it.key] = true end
    local exclItems = {}
    for key in pairs(db.excluded) do
        if not shown[key] then
            local label
            local acctId = key:match("^acct:(.*)$")
            if acctId then
                label = CS.Account.Label(acctId)
            else
                local m, rest = key:match("^([^:]+):(.*)$")
                local def = m and CS.MODULES[m]
                label = def and (L[def.title] .. " › " .. rest) or key
            end
            exclItems[#exclItems + 1] = { key = key, excl = true, label = label }
        end
    end
    table.sort(exclItems, function(a, b) return a.label < b.label end)
    if #exclItems > 0 and db.showExcluded ~= false then
        idx = idx + 1
        local h = GetRow(idx)
        h:SetSize(width, HEAD_H + 4)
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", 0, -y)
        h.check:Hide(); h.label:Hide(); h.value:Hide(); h.desc:Hide(); h.info:Hide(); h.bg:Hide(); h.btn1:Hide(); h.btn2:Hide(); h.hbtn:Hide()
        h.header:Show()
        HeaderCheck(h, exclItems)
        h.collapseKey = "excl"
        h.header:SetText(Mark("excl") .. "|cff999999" .. L["Abgewählt (%d)"]:format(#exclItems) .. "|r")
        h:Show()
        y = y + HEAD_H + 4
        for _, it in ipairs(Collapsed("excl") and {} or exclItems) do
            idx = idx + 1
            local row = GetRow(idx)
            row:SetSize(width, HEAD_H)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -y)
            row.item = it
            row.SetIndent(16)
            row.header:Hide(); row.hbtn:Hide(); row.btn1:Hide(); row.btn2:Hide(); row.value:Hide(); row.desc:Hide(); row.info:Hide()
            row.check:Show(); row.check:SetEnabled(true); row.check:SetChecked(false)
            row.label:Show(); row.bg:Show()
            row.label:SetText(it.label)
            row.label:SetTextColor(0.6, 0.6, 0.6)
            row.SetRightInset(24)
            row:Show()
            y = y + HEAD_H
        end
    end
    content:SetHeight(math.max(1, y))

    -- Zähler unabhängig vom Auf-/Zuklappen
    own, selected = 0, 0
    for _, it in ipairs(items) do
        if not it.isError then
            if CS.IsOwn(it) then own = own + 1
            elseif db.modules[it.module] and CS.IsChecked(it) then selected = selected + 1 end
        end
    end

    if not CS.Template("general") and not CS.Template("class") then
        window.empty:SetText(L["Noch keine Vorlage gespeichert. Log dich mit dem Char ein, dessen Einstellungen für alle gelten sollen, und klick links auf „Als allgemeine Vorlage speichern“. Für Makros und Aktionsleisten speicherst du je Klasse eine Klassen-Vorlage."])
    elseif #items == 0 and not db.trackAccount then
        window.empty:SetText(L["Keine Abweichungen – dieser Char entspricht den Vorlagen."])
    else
        window.empty:SetText("")
    end
    local others = #items - own
    local parts = {}
    if others > 0 then parts[#parts + 1] = L["%d Abweichungen, %d angehakt"]:format(others, selected) end
    if own > 0 then parts[#parts + 1] = L["%d Änderungen seit der Vorlage"]:format(own) end
    if #acctItems > 0 then parts[#parts + 1] = L["%d accountweit"]:format(#acctItems) end
    window.count:SetText(table.concat(parts, " · "))
    window.resetAll:SetEnabled(#resettable > 0)
    window.resetAll:SetShown(not reviewMode)
    window.resetSel:SetShown(not reviewMode)
    window.resetSel:SetText(L["Ausgewählte zurücksetzen"] .. (nsel > 0 and (" (" .. nsel .. ")") or ""))
    window.resetSel:SetEnabled(nsel > 0)
    window.applyAll:SetEnabled(#resettable > 0 or #CS.SelectedDiff() > 0)
    window.apply:SetEnabled(selected > 0 or nsel > 0)

    local excluded = 0
    for _ in pairs(db.excluded) do excluded = excluded + 1 end
    window.all:SetEnabled(nsel < #resettable)
    window.none:SetEnabled(others > 0 or nsel > 0)
    window.excludedCount:SetText(excluded > 0 and L["%d Einstellung(en) abgewählt"]:format(excluded) or "")
end


-- mehrere Änderungen auf einmal behalten: accountweit -> neuer Stand, Vorlage-Char -> in die Vorlage
function UI.AcceptBatch(list, all)
    local n = 0
    if all and CS.cdb.undo then CS.cdb.undo = nil end
    for _, it in ipairs(list or {}) do
        if it.acct then CS.Account.Accept(it); n = n + 1
        elseif CS.IsOwn(it) and it.toTemplate then
            local def = CS.MODULES[it.module]
            local tpl = def and CS.Template(def.scope)
            if tpl and pcall(it.toTemplate) then
                tpl.time = time()
                CS.cdb.applied[def.scope] = tpl.time
                n = n + 1
            end
        end
    end
    CS.Print(L["%d Änderung(en) übernommen."]:format(n))
    wipe(UI.resetSel)
    UI.Refresh()
end

-- mehrere Änderungen auf einmal zurücksetzen (gemischt: Vorlage-Char, letzte Übernahme, accountweit)
function UI.ResetBatch(list)
    if InCombatLockdown() then CS.Print(L["Im Kampf nicht möglich."]) return end
    local acct, other = {}, {}
    for _, it in ipairs(list or {}) do
        if it.acct then acct[#acct + 1] = it else other[#other + 1] = it end
    end
    if #other > 0 then CS.ResetMany(other) end
    if #acct > 0 then CS.Account.ResetItems(acct) end
    wipe(UI.resetSel)
    UI.Refresh()
end

function UI.Relayout()
    if not window or not content or not window.scroll then return end
    local width = math.max(200, (window.scroll:GetWidth() or 400) - 4)
    content:SetWidth(width)
    for _, r in ipairs(rows) do if r:IsShown() then r:SetWidth(width) end end
end

function UI.Show()
    UI.Build()
    if CS.InvalidateFrames then CS.InvalidateFrames() end
    if CS.Account and CS.db.trackAccount then CS.Account.Invalidate() end -- frisch lesen; bis dahin der letzte Stand
    window:Show()
    UI.Refresh()
end
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
UI.TooltipLines = ItemTooltip -- für die Tests

---------------------------------------------------------------------------------------------------
-- Minimap-Icon: über LibDBIcon, wenn ein anderes Addon es mitbringt (dann sammeln Button-Taschen wie die von
-- Addons für Minimap-Knöpfe es mit ein), sonst ein eigener Knopf.
---------------------------------------------------------------------------------------------------
local ICON = "Interface\\Icons\\INV_Misc_Note_05"

local function MinimapTooltip(tt)
    tt:AddLine("CharSync")
    local pending = CS.PendingScopes and CS.PendingScopes() or {}
    if #pending > 0 then tt:AddLine(L["Neue Vorlage zum Prüfen"], 0.2, 0.8, 1) end
    tt:AddLine(L["Klicken: Fenster öffnen"], 1, 1, 1)
    tt:AddLine(L["Ziehen: Icon verschieben"], 0.7, 0.7, 0.7)
end

local function OwnMinimapButton()
    local db = CS.db.minimap
    local button = CreateFrame("Button", "CharSyncMinimapButton", Minimap)
    button.db = db -- wie bei LibDBIcon: gespeicherter Winkel (minimapPos), den CharSync beim Zurücksetzen mitschreibt
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local icon = button:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", 0, 1)
    icon:SetTexture(ICON)
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    local function Place()
        local angle = math.rad(db.minimapPos or 220)
        local radius = Minimap:GetWidth() / 2 + 5
        button:ClearAllPoints()
        button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
    end
    button:SetScript("OnClick", function() UI.Toggle() end)
    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            db.minimapPos = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
            Place()
        end)
    end)
    button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        MinimapTooltip(GameTooltip)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    Place()
    C_Timer.After(1, Place) -- die Minimap-Größe steht beim Login evtl. noch nicht fest
    Minimap:HookScript("OnSizeChanged", Place)
    function UI.UpdateMinimapButton() button:SetShown(not db.hide) end
    function UI.ResetMinimapButton()
        db.hide = false; db.minimapPos = 220
        Place(); button:SetAlpha(1); button:Show()
        if window then window.minimap:SetChecked(true) end
        CS.Print(L["Minimap-Icon zurückgesetzt."])
    end
    UI.UpdateMinimapButton()
end

function UI.CreateMinimapButton()
    if UI.minimapCreated then return end
    UI.minimapCreated = true
    CS.db.minimap = type(CS.db.minimap) == "table" and CS.db.minimap or { hide = false }
    local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
    local DBIcon = LibStub and LibStub("LibDBIcon-1.0", true)
    if LDB and LDB.NewDataObject and DBIcon and DBIcon.Register then
        local obj = LDB:NewDataObject("CharSync", {
            type = "launcher", icon = ICON, label = "CharSync",
            OnClick = function() UI.Toggle() end,
            OnTooltipShow = MinimapTooltip,
        })
        DBIcon:Register("CharSync", obj, CS.db.minimap)
        local function Button() return DBIcon.GetMinimapButton and DBIcon:GetMinimapButton("CharSync") end
        -- nie als „vom Spieler platziert“ merken (sonst stellt WoW eine alte Position wieder her)
        local b = Button()
        if b and b.SetUserPlaced then pcall(b.SetUserPlaced, b, false) end
        function UI.UpdateMinimapButton()
            if CS.db.minimap.hide then DBIcon:Hide("CharSync") else DBIcon:Show("CharSync") end
        end
        function UI.ResetMinimapButton()
            CS.db.minimap.hide = false
            CS.db.minimap.minimapPos = 220
            DBIcon:Show("CharSync")
            if DBIcon.Refresh then pcall(DBIcon.Refresh, DBIcon, "CharSync", CS.db.minimap) end
            local bb = Button()
            if bb then
                if bb.SetUserPlaced then pcall(bb.SetUserPlaced, bb, false) end
                bb:SetAlpha(1); bb:Show()
            end
            if window then window.minimap:SetChecked(true) end
            CS.Print(L["Minimap-Icon zurückgesetzt."])
        end
    else
        OwnMinimapButton()
    end
end
