--[[
    server/stress.lua

    Stress is a number in the framework's player metadata, so the server owns it. The client
    asks for a change and never applies one: a client that could set its own stress could set
    it to zero, and the whole mechanic is then decorative.

    The qb-hud event names are kept alongside the new ones because a dozen stock qb resources
    fire `hud:server:GainStress` and none of them are going to be edited.
]]

local function clampStress(value)
    if value < 0 then return 0 end
    if value > 100 then return 100 end
    return value
end

--- Move a player's stress by `delta` and tell them. Returns the new value, or nil when
--- nothing happened - a missing player, an exempt job, or stress switched off entirely.
local function adjust(src, delta, notifyKey)
    if not Config.Stress.enabled then return nil end
    if Bridge.stressExempt(src) then return nil end

    local player = Bridge.player(src)
    if not player then return nil end

    local current = tonumber(Bridge.metadata(src, 'stress')) or 0
    local updated = clampStress(current + delta)
    if updated == current then return current end

    if not Bridge.setMetadata(src, 'stress', updated) then return nil end

    TriggerClientEvent('vhud:client:UpdateStress', src, updated)
    if notifyKey then
        Bridge.notify(src, L(notifyKey), delta > 0 and 'error' or 'primary')
    end

    return updated
end

local function sanitiseAmount(amount)
    local value = tonumber(amount)
    if not value or value ~= value then return nil end
    -- A client asking for a thousand points of stress is a client to ignore. The cap is the
    -- whole scale, so a legitimate caller is never clipped.
    if value < 0 then value = -value end
    return math.min(value, 100)
end

RegisterNetEvent('vhud:server:GainStress', function(amount)
    local value = sanitiseAmount(amount)
    if not value then return end
    adjust(source, value, 'notify.stress_gain')
end)

RegisterNetEvent('vhud:server:RelieveStress', function(amount)
    local value = sanitiseAmount(amount)
    if not value then return end
    adjust(source, -value, 'notify.stress_relieved')
end)

-- The qb-hud names. Same handlers, so a stock qb-storerobbery or qb-vehiclekeys keeps
-- working with qb-hud stopped.
if Config.Compat.qbHudEvents then
    RegisterNetEvent('hud:server:GainStress', function(amount)
        local value = sanitiseAmount(amount)
        if not value then return end
        adjust(source, value, 'notify.stress_gain')
    end)

    RegisterNetEvent('hud:server:RelieveStress', function(amount)
        local value = sanitiseAmount(amount)
        if not value then return end
        adjust(source, -value, 'notify.stress_relieved')
    end)
end

-- ---------------------------------------------------------------------------------------
-- Exports for other resources
-- ---------------------------------------------------------------------------------------

--- Add stress to a player. Returns the new level, or nil when nothing changed.
exports('AddStress', function(src, amount)
    local value = sanitiseAmount(amount)
    if not value then return nil end
    return adjust(src, value, 'notify.stress_gain')
end)

--- Remove stress from a player.
exports('RemoveStress', function(src, amount)
    local value = sanitiseAmount(amount)
    if not value then return nil end
    return adjust(src, -value, 'notify.stress_relieved')
end)

--- Set a player's stress outright. Used by a jail or a hospital that wants to zero it.
exports('SetStress', function(src, amount)
    local value = sanitiseAmount(amount)
    if not value then return nil end

    local current = tonumber(Bridge.metadata(src, 'stress')) or 0
    return adjust(src, value - current, nil)
end)

--- Read a player's stress without changing it.
exports('GetStress', function(src)
    return tonumber(Bridge.metadata(src, 'stress')) or 0
end)
