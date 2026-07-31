--[[
    bridge/shared/hud.lua

    `HUD` is the one global this resource publishes to itself. It carries the small helpers
    every other file needs and nothing else: table utilities that both sides use to merge a
    settings payload, and a debug printer that is silent unless the operator asks for output.

    Nothing in here touches a framework, a native, or a config value. It loads before
    config.lua so that config.lua can already call HUD.deepCopy.
]]

HUD = HUD or {}

HUD.resource = GetCurrentResourceName()

--- Whether tracing is on. Read from a replicated convar so the client sees it too - a plain
--- `set` convar exists only on the server, and the client read comes back empty.
function HUD.debugEnabled()
    return GetConvar('hud_debug', 'false') == 'true'
end

--- Print only when tracing is on. Every diagnostic in this resource goes through here so that
--- a normal server console stays clean.
function HUD.debug(...)
    if not HUD.debugEnabled() then return end
    local parts = {}
    for i = 1, select('#', ...) do
        parts[#parts + 1] = tostring((select(i, ...)))
    end
    print(('[v-hud] %s'):format(table.concat(parts, ' ')))
end

--- Always printed. Reserved for a condition an operator has to act on.
function HUD.warn(message)
    print(('[v-hud] %s'):format(message))
end

--- A value copy of `source`, recursing into table values. Used everywhere a default must be
--- handed out without the caller being able to mutate the shared default.
function HUD.deepCopy(source)
    if type(source) ~= 'table' then return source end
    local copy = {}
    for key, value in pairs(source) do
        copy[key] = type(value) == 'table' and HUD.deepCopy(value) or value
    end
    return copy
end

--- Overlay `patch` onto a copy of `base`, recursing into tables that exist on both sides.
--- A key in `patch` that `base` does not know is dropped: that is what stops a client from
--- inventing settings keys, and it is why the server can call this on an untrusted payload.
function HUD.merge(base, patch)
    local result = HUD.deepCopy(base)
    if type(patch) ~= 'table' then return result end

    for key, value in pairs(patch) do
        local current = result[key]
        if current ~= nil then
            if type(current) == 'table' and type(value) == 'table' then
                result[key] = HUD.merge(current, value)
            elseif type(current) == type(value) then
                result[key] = value
            end
        end
    end

    return result
end

--- Like HUD.merge, but a key `patch` has and `base` does not is KEPT rather than dropped.
--- Used where the input is trusted and additive - an operator's extra theme in config.lua,
--- for instance, which is allowed to name a colour the shipped theme never mentioned.
--- Never call this on a client payload; that is what HUD.merge is for.
function HUD.overlay(base, patch)
    local result = HUD.deepCopy(base)
    if type(patch) ~= 'table' then return result end

    for key, value in pairs(patch) do
        if type(result[key]) == 'table' and type(value) == 'table' then
            result[key] = HUD.overlay(result[key], value)
        else
            result[key] = HUD.deepCopy(value)
        end
    end

    return result
end

--- True when `value` is one of the entries in the array `list`.
function HUD.oneOf(value, list)
    for i = 1, #list do
        if list[i] == value then return true end
    end
    return false
end

--- Clamp a number, tolerating a nil or a non-number by returning the fallback. Settings
--- arriving from the NUI are strings often enough that this has to be forgiving.
function HUD.clamp(value, min, max, fallback)
    local number = tonumber(value)
    if not number or number ~= number then return fallback end
    if number < min then return min end
    if number > max then return max end
    return number
end

--- Normalise a colour to `#rrggbb`. Anything that is not six hex digits with an optional
--- leading `#` comes back as the fallback, so a hand-edited config or a crafted NUI payload
--- can never inject a CSS expression into the stylesheet.
function HUD.colour(value, fallback)
    if type(value) ~= 'string' then return fallback end
    local hex = value:match('^#?(%x%x%x%x%x%x)$')
    if not hex then return fallback end
    return '#' .. hex:lower()
end

--- Keys of `map`, sorted, so a table that is written to KVP or compared between two runs has
--- a stable order.
function HUD.sortedKeys(map)
    local keys = {}
    for key in pairs(map) do keys[#keys + 1] = key end
    table.sort(keys)
    return keys
end
