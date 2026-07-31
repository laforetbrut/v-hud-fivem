--[[
    bridge/shared/locale.lua

    `L(key, ...)` on either side. English is the base table and the fallback for a key another
    locale file has not translated, so a half-finished translation shows English rather than
    the raw key.

    The active language is the `hud_locale` convar, falling back to `qb_locale` so a server
    that already set one language does not have to set a second, then to Config.Locale.
]]

Locales = Locales or {}

local active

--- Resolve the language once, on first use. Config may not exist yet when this file loads.
local function resolveLanguage()
    if active then return active end

    local candidates = {
        GetConvar('hud_locale', ''),
        GetConvar('qb_locale', ''),
        (Config and Config.Locale) or '',
        'en',
    }

    for i = 1, #candidates do
        local name = candidates[i]
        if name ~= '' and Locales[name] then
            active = name
            return active
        end
    end

    active = 'en'
    return active
end

--- The active language code. Exposed so the NUI can be told which one it is running in.
function CurrentLocale()
    return resolveLanguage()
end

--- Translate `key`, formatting with `...` when placeholders are present. An unknown key comes
--- back as the key itself in brackets rather than nil, so a missing string is visible in game
--- instead of erroring three call frames later.
function L(key, ...)
    local language = resolveLanguage()
    local text = (Locales[language] and Locales[language][key])
        or (Locales.en and Locales.en[key])

    if not text then return ('[%s]'):format(key) end
    if select('#', ...) == 0 then return text end

    local ok, formatted = pcall(string.format, text, ...)
    return ok and formatted or text
end

--- The whole active table, English-filled, for handing to the NUI in one message. The menu
--- has around two hundred strings in it; sending them individually would be two hundred
--- round trips.
function LocaleTable()
    local language = resolveLanguage()
    local merged = {}

    for key, value in pairs(Locales.en or {}) do
        merged[key] = value
    end
    if language ~= 'en' then
        for key, value in pairs(Locales[language] or {}) do
            merged[key] = value
        end
    end

    return merged
end
