-- CharSync: Sprachen. Schlüssel ist der deutsche Text; fehlt eine Übersetzung, gilt Englisch, sonst der Schlüssel.
local _, CS = ...

local locale = GetLocale and GetLocale() or "enUS"
if locale == "enGB" then locale = "enUS" end
CS.LOCALE = locale

CS.TRANSLATIONS = CS.TRANSLATIONS or {}
local T = CS.TRANSLATIONS

CS.L = setmetatable({}, {
    __index = function(_, key)
        if locale == "deDE" then return key end
        local own = T[locale] or (locale == "esMX" and T.esES)
        return (own and own[key]) or (T.enUS and T.enUS[key]) or key
    end,
})
